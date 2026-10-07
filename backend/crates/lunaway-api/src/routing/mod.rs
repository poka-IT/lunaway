//! Routes for a motorhome: the engine's routes, each checked against every
//! physical limit we know of before the app sees it.
//!
//! The engine refuses most restricted roads by itself, with the vehicle's
//! dimensions, but not a limit mapped on a node (a car park's height bar),
//! not one on the edge a route starts or ends on, and not a limit it does
//! not read (`plan/research/07-navigation.md`, A.4). So each route is
//! matched against the restrictions near it (`lunaway_db::routing`,
//! `lunaway_domain::routing::corridor`): a limit the vehicle exceeds is a
//! blocker, and the engine is asked again with a small ring excluded around
//! each blocker, a bounded number of times. A route with a blocker never
//! reaches the app: either a route without one comes back, or no route
//! with the blockers that stopped every attempt.
//!
//! Road events (closures, works, temporary limits) are checked the same
//! way ([`events`]), at the time the vehicle gets to each: a closure active
//! then, or a limit the vehicle exceeds, is a blocker too.
//!
//! When the engine finds no route at all, [`diagnose`] asks it why; each
//! route says which ferries it takes ([`ferries`]).

pub(crate) mod diagnose;
pub(crate) mod events;
pub(crate) mod ferries;
pub(crate) mod limits;
pub(crate) mod valhalla;

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};

use chrono::{DateTime, Utc};
use lunaway_db::{PgPool, road_events::EventRow, routing as db};
use lunaway_domain::{
    Position,
    routing::{
        Finding, Hit, Restriction, RestrictionSource, RouteLine, RoutingDimensions, Severity,
        VehicleProfile, assess, exclusion_ring, match_route, polyline,
    },
};
use serde_json::Value;
use tokio::sync::Semaphore;

use self::{
    diagnose::Unreachable,
    events::{EventHit, Freshness, Timing},
    ferries::Ferry,
    valhalla::{Answer, Avoid, Engine, EngineError, Stop},
};
use crate::config::RoutingConfig;

/// Engine calls for one route at most: the first, and three more with the
/// blockers excluded (twice that, and one, when the blockers remembered
/// from earlier trips closed the way and the trip is asked again without
/// them). Road events add blockers the physical limits did not
/// have (a closure met only once the route avoids a bridge), hence one
/// more than the three of the restrictions alone.
pub(crate) const MAX_ATTEMPTS: usize = 4;
/// Longest a route may take, everything together (waits for an engine slot,
/// engine calls, corridor queries, matching): under the API's request
/// timeout (20 s by default), so a slow engine ends in `UNAVAILABLE` and a
/// refunded quota rather than a cut connection.
const ROUTE_DEADLINE: Duration = Duration::from_secs(15);
/// Most exclusion rings sent at once: 200 octagons of 9 points are 1 800
/// vertices, within the 2 000 of `max_exclude_polygons_vertices` in
/// `infra/routing/valhalla.json` (a test reads it), and 6.2 km of
/// perimeter within its 50 km.
pub(crate) const MAX_EXCLUSIONS: usize = 200;
/// Longest the speed limits of a route's answer may take, all its routes
/// together, after the route itself: the route's deadline and this one stay
/// under the API's request timeout (20 s by default).
const LIMITS_DEADLINE: Duration = Duration::from_secs(3);
/// Radius of the ring around a blocker, metres: enough to catch the road
/// the route used, small enough to spare a road crossing a few metres away.
const RING_M: f64 = 5.0;
/// How far from a route the database looks for restrictions, metres: the
/// widest tolerance of a source (`RestrictionSource::tolerance_m`).
pub(crate) const CORRIDOR_M: f64 = 15.0;
/// How close to a stretch already queried a sample of a later route must
/// lie for that stretch's corridor queries to cover it, metres.
const COVERED_M: f64 = 1.0;
/// Spacing of the samples of a later route compared with the stretches
/// already queried, metres: every point of the route lies within half of
/// it of a sample.
const SAMPLE_M: f64 = 20.0;
/// How much farther than the check needs the corridor queries reach,
/// metres: a point of a later route within [`SAMPLE_M`] / 2 of a sample
/// within [`COVERED_M`] of a queried stretch lies within this of it, so
/// what the queries of that stretch found holds everything near the point.
const QUERY_MARGIN_M: f64 = SAMPLE_M / 2.0 + COVERED_M;
/// Most shape points of one corridor query of the restrictions: a longer
/// stretch is split in two halves asked at once. One query over a route of
/// 5 400 km took 2.3 s on the backend (2026-10-07).
const QUERY_POINTS: usize = 35_000;
/// Margin kept on the route's deadline when its diagnosis takes the rest:
/// the answer, unexplained if need be, still leaves before the deadline.
const DIAGNOSIS_MARGIN: Duration = Duration::from_secs(1);
/// Largest OSRM answer passed to the app: alternatives are dropped, last
/// first, until the routes fit, so the GraphQL answer stays under the API's
/// response limit (16 MB by default). The longest trip accepted gives one
/// route of up to 10.4 MB (2.3 kB per kilometre of straight line, measured
/// on the Europe graph on 2026-10-07; Seville to the North Cape, 4 166 km,
/// 7.1 MB).
pub(crate) const MAX_OSRM_BYTES: usize = 11 * 1024 * 1024;

/// What the app asked for.
#[derive(Debug, Clone)]
pub(crate) struct RouteRequest {
    /// Start, waypoints, destination.
    pub(crate) stops: Vec<Stop>,
    /// The vehicle.
    pub(crate) vehicle: VehicleProfile,
    /// What to avoid.
    pub(crate) avoid: Avoid,
    /// Alternatives wanted, 0 to 2.
    pub(crate) alternatives: u8,
    /// The engine's language tag (`fr-FR`, `en-US`).
    pub(crate) language: &'static str,
    /// When the trip starts: road events count at the time the vehicle
    /// reaches them.
    pub(crate) depart_at: DateTime<Utc>,
}

impl RouteRequest {
    /// The trip's length in a straight line from stop to stop, metres.
    pub(crate) fn straight_m(&self) -> f64 {
        self.stops
            .windows(2)
            .map(|w| w[0].at.distance_m(w[1].at))
            .sum()
    }
}

/// A restriction met along a route, and what it means for the vehicle.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Met {
    /// What it means.
    pub(crate) finding: Finding,
    /// The restriction.
    pub(crate) restriction: db::NearRestriction,
    /// Where along the route.
    pub(crate) hit: Hit,
}

/// One route the app receives.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct CheckedRoute {
    /// Its index in the OSRM answer passed on.
    pub(crate) index: usize,
    /// Metres.
    pub(crate) distance_m: f64,
    /// Seconds.
    pub(crate) duration_s: f64,
    /// Whether it uses a toll road.
    pub(crate) has_toll: bool,
    /// Whether it uses a ferry.
    pub(crate) has_ferry: bool,
    /// Whether it uses a motorway.
    pub(crate) has_motorway: bool,
    /// Its ferry crossings, in driving order.
    pub(crate) ferries: Vec<Ferry>,
    /// The restrictions the vehicle passes with little margin, or whose
    /// figure is unknown, in driving order.
    pub(crate) warnings: Vec<Met>,
    /// The road events met that warn or inform, in driving order.
    pub(crate) events: Vec<EventHit>,
}

/// Why no route came back.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum NoRoute {
    /// The engine found no road between the points, for the reasons its
    /// diagnosis gave (none when it could not tell in time).
    Unreachable(Vec<Unreachable>),
    /// A point is too far from any road: the stops that do not snap (none
    /// when the engine could not tell).
    OffNetwork(Vec<usize>),
    /// These stops lie outside the area the graph covers; the engine was
    /// not asked.
    OutsideCoverage(Vec<usize>),
}

/// What a route request gave.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Outcome {
    /// Routes the vehicle may drive.
    Found {
        /// The engine's OSRM answer, with only these routes.
        osrm: Value,
        /// The routes, in the answer's order.
        routes: Vec<CheckedRoute>,
        /// Engine calls after the first.
        recalculations: usize,
        /// The road events an earlier attempt met and the routes avoid.
        avoided: Vec<Arc<EventRow>>,
    },
    /// No route at all.
    NoRoute(NoRoute),
    /// Routes exist, but each one meets a limit the vehicle exceeds.
    NoSafeRoute {
        /// The limits that stopped the last attempt.
        blockers: Vec<Met>,
        /// The road events that stopped the last attempt.
        event_blockers: Vec<EventHit>,
        /// Engine calls after the first.
        recalculations: usize,
    },
}

/// Why a route could not be computed.
#[derive(Debug, thiserror::Error)]
pub(crate) enum RouteError {
    /// The engine is not configured, or no graph is active.
    #[error("routing is not set up")]
    NotSetUp,
    /// Every engine call is taken.
    #[error("the routing engine is busy")]
    Busy,
    /// The engine failed.
    #[error(transparent)]
    Engine(#[from] EngineError),
    /// The route's engine calls ran out of time together.
    #[error("the route took longer than {ROUTE_DEADLINE:?}")]
    Deadline,
    /// The database failed.
    #[error(transparent)]
    Db(#[from] lunaway_db::DbError),
    /// The engine's answer does not hold together.
    #[error("the routing engine's answer is malformed: {0}")]
    Malformed(&'static str),
    /// Even the first route alone exceeds the answer's limit, or its shape
    /// is longer than the check reads.
    #[error("the route is too large to send")]
    TooLarge,
    /// The engine's shape does not decode.
    #[error("the routing engine's route shape does not decode")]
    Shape(#[source] lunaway_domain::routing::polyline::InvalidPolyline),
    /// The check's blocking task stopped.
    #[error("the route check stopped")]
    Blocking(#[source] tokio::task::JoinError),
}

/// What a route request gave, and whether the engine answered for it.
pub(crate) struct Routed {
    /// The outcome, or why there is none.
    pub(crate) result: Result<Outcome, RouteError>,
    /// Whether the engine answered at least once: the work was done, and a
    /// failure after it is not given back to the client's quota.
    pub(crate) engine_answered: bool,
    /// Where the time went.
    pub(crate) spent: Spent,
}

/// Where a route's time went, logged once per route by the resolver: the
/// latency of a route is a sum of engine calls, corridor queries and
/// matching, and only this line tells them apart in production. Durations
/// and counts only, never a position.
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct Spent {
    /// Waiting for an engine slot.
    pub(crate) queue: Duration,
    /// Route calls of the engine, all attempts together.
    pub(crate) engine: Duration,
    /// Route calls made to the engine: the first, and one per
    /// recalculation around blockers.
    pub(crate) engine_calls: u32,
    /// Corridor queries of the database.
    pub(crate) corridor: Duration,
    /// Matching the routes against what the queries found, off the async
    /// threads.
    pub(crate) check: Duration,
}

/// The engine and its share of the server.
pub(crate) struct Routing {
    engine: Option<Engine>,
    /// Engine calls in flight, all clients together.
    slots: Semaphore,
    /// Diagnoses of a trip without a route running at once: one. Each holds
    /// its request's engine slot for several short calls; a second one
    /// meanwhile answers unexplained rather than take a second slot.
    diagnoses: Semaphore,
    queue_wait: Duration,
    /// The last answer of the engine's status, and when it was read.
    status: std::sync::Mutex<Option<(std::time::Instant, bool)>>,
    /// Blockers earlier checks found, excluded from the start of later
    /// routes.
    remembered: std::sync::Mutex<Remembered>,
}

/// Restrictions the engine does not apply by itself (a height barrier
/// mapped on a node, a ferry terminal's lane) that blocked earlier routes,
/// on the graph they were found on. A route meeting one costs a second
/// engine call and a second check: on 2026-10-07 every trip to Morocco met
/// the same barrier at Tarifa port, the trips from Edinburgh a 2 m lane at
/// Dover, at 1.2 to 2.6 s of engine time each
/// (`plan/research/48-latence-itineraires.md`). Excluded from the first
/// call of a later trip they may lie on, they cost nothing more.
///
/// Only the rows of OpenStreetMap and the IGN, which belong to a graph and
/// end with it: DiaLog's and the community's live outside the graphs, and
/// DiaLog's come back under new ids at every reading, so a remembered copy
/// would outlive the order it stood for. A blocker serves ahead once two
/// requests have met it: one trip alone leaves no trace another client
/// could read in its own answer. Public restrictions only, in memory,
/// never logged.
#[derive(Default)]
struct Remembered {
    graph_id: String,
    /// The least recently met first.
    blockers: std::collections::VecDeque<RememberedBlocker>,
}

struct RememberedBlocker {
    id: uuid::Uuid,
    /// The middle of the stretch the route met, where its ring went.
    at: Position,
    restriction: Restriction,
    /// Requests that met it.
    met: u32,
}

/// Blockers remembered at most: a few hundred places in Europe hold the
/// limits the engine misses on the main roads.
const REMEMBERED: usize = 512;
/// Requests that must have met a blocker before it is excluded ahead.
const MET_BEFORE_AHEAD: u32 = 2;
/// Remembered blockers excluded from a first call at most, under
/// [`MAX_EXCLUSIONS`].
const REMEMBERED_RINGS: usize = 50;
/// How far a remembered blocker must lie from every stop to be excluded
/// ahead, metres: a ring within reach of a stop's snapping (5 km) could
/// move the stop to another road unnoticed.
const CLEAR_OF_STOPS_M: f64 = 10_000.0;
/// How far beyond the box of its stops a trip may run, degrees: Lille to
/// Guelmim leaves it by 0.6 degree to take the ferry at Tarifa.
const TRIP_MARGIN_DEG: f64 = 1.0;

/// How long a status read stays good: `Query.routing` is public, and its
/// aliases must not turn into calls of the engine.
const STATUS_TTL: Duration = Duration::from_secs(10);

impl Routing {
    /// The engine of `config`; none when its URL is not usable.
    pub(crate) fn new(config: &RoutingConfig) -> Self {
        let engine = config.valhalla_url.as_deref().and_then(|url| {
            Engine::new(url, config.timeout)
                .inspect_err(|error| tracing::error!(%error, "cannot build the routing client"))
                .ok()
        });
        Self {
            engine,
            slots: Semaphore::new(config.concurrency.max(1)),
            diagnoses: Semaphore::new(1),
            queue_wait: config.queue_wait,
            status: std::sync::Mutex::new(None),
            remembered: std::sync::Mutex::new(Remembered::default()),
        }
    }

    /// Whether the engine answers, read at most every [`STATUS_TTL`].
    pub(crate) async fn alive_cached(&self) -> bool {
        let now = std::time::Instant::now();
        let cached = *self
            .status
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some((at, alive)) = cached
            && now.saturating_duration_since(at) < STATUS_TTL
        {
            return alive;
        }
        let alive = self.alive().await;
        *self
            .status
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some((now, alive));
        alive
    }

    /// Whether the engine answers.
    pub(crate) async fn alive(&self) -> bool {
        match &self.engine {
            Some(e) => e.alive().await,
            None => false,
        }
    }

    /// The engine's matrix from `sources` to `targets` with `costing`, one
    /// engine slot held for the call: a row per source, a cell per target,
    /// none where the engine found no way.
    pub(crate) async fn matrix(
        &self,
        sources: &[valhalla::MatrixPoint],
        targets: &[valhalla::MatrixPoint],
        costing: &Value,
    ) -> Result<Vec<Vec<Option<lunaway_domain::fuel::Leg>>>, RouteError> {
        let engine = self.engine.as_ref().ok_or(RouteError::NotSetUp)?;
        let _slot = tokio::time::timeout(self.queue_wait, self.slots.acquire())
            .await
            .map_err(|_| RouteError::Busy)?
            .map_err(|_| RouteError::Busy)?;
        let body = valhalla::matrix_body(sources, targets, costing);
        Ok(engine.matrix(&body, sources.len(), targets.len()).await?)
    }

    /// The speed limits along each route of `osrm` for `vehicle`, in the
    /// order of its routes: `None` for a route the engine could not trace
    /// within [`LIMITS_DEADLINE`] altogether (a route is never refused for
    /// its limits).
    pub(crate) async fn speed_limits(
        &self,
        osrm: &Value,
        vehicle: lunaway_domain::speed::Vehicle,
    ) -> Vec<Option<Vec<lunaway_domain::speed::Span>>> {
        let routes = osrm
            .get("routes")
            .and_then(Value::as_array)
            .map_or(&[][..], Vec::as_slice);
        let traced =
            tokio::time::timeout(LIMITS_DEADLINE, self.trace_routes(routes, vehicle)).await;
        match traced {
            Ok(limits) => limits,
            Err(_) => {
                tracing::warn!("the speed limits of a route ran out of time");
                vec![None; routes.len()]
            }
        }
    }

    async fn trace_routes(
        &self,
        routes: &[Value],
        vehicle: lunaway_domain::speed::Vehicle,
    ) -> Vec<Option<Vec<lunaway_domain::speed::Span>>> {
        use futures_util::StreamExt as _;
        let Some(engine) = self.engine.as_ref() else {
            return vec![None; routes.len()];
        };
        let mut prepared = Vec::with_capacity(routes.len());
        for route in routes {
            prepared.push(match prepare_trace(route).await {
                Ok(p) => p,
                Err(error) => {
                    tracing::warn!(%error, "no speed limits for a route");
                    None
                }
            });
        }
        // The pieces of every route, a few at a time under engine slots: a
        // piece takes 15 to 25 ms of the engine, and one after the other the
        // pieces of three 800 km routes took 0.24 s (2026-10-07). Two at a
        // time leaves the other slots to the route calls of other trips:
        // their waits stay short of the queue's limit, and best-effort speed
        // limits never make a route fail.
        let pieces: Vec<(usize, usize, &Value)> = prepared
            .iter()
            .enumerate()
            .filter_map(|(r, p)| p.as_ref().map(|p| (r, p)))
            .flat_map(|(r, p)| p.bodies.iter().map(move |(first, body)| (r, *first, body)))
            .collect();
        let calls: Vec<_> = pieces
            .iter()
            .map(|&(_, _, body)| self.trace_piece(engine, body))
            .collect();
        let answers: Vec<Result<Value, RouteError>> = futures_util::stream::iter(calls)
            .buffered(TRACES_AT_ONCE)
            .collect()
            .await;
        let mut edges: Vec<Option<Vec<lunaway_domain::speed::Edge>>> = prepared
            .iter()
            .map(|p| p.as_ref().map(|_| Vec::new()))
            .collect();
        for ((r, first, _), answer) in pieces.into_iter().zip(answers) {
            let found = match answer {
                Ok(a) => limits::edges_of(&a, first),
                Err(error) => {
                    tracing::warn!(%error, "no speed limits for a route");
                    None
                }
            };
            match (found, &mut edges[r]) {
                (Some(e), Some(all)) => all.extend(e),
                _ => edges[r] = None,
            }
        }
        let mut out = Vec::with_capacity(routes.len());
        for (p, e) in prepared.into_iter().zip(edges) {
            let (Some(p), Some(e)) = (p, e) else {
                out.push(None);
                continue;
            };
            let spans = tokio::task::spawn_blocking(move || {
                lunaway_domain::speed::spans(&p.points, &p.along, &e, vehicle)
            })
            .await;
            out.push(spans.ok());
        }
        out
    }

    /// One speed-limit trace, under an engine slot.
    async fn trace_piece(&self, engine: &Engine, body: &Value) -> Result<Value, RouteError> {
        let _slot = tokio::time::timeout(self.queue_wait, self.slots.acquire())
            .await
            .map_err(|_| RouteError::Busy)?
            .map_err(|_| RouteError::Busy)?;
        Ok(engine.trace(body).await?)
    }

    /// Computes and checks routes for `request` on graph `graph_id`.
    pub(crate) async fn route(
        &self,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
        fresh: &Freshness,
    ) -> Routed {
        // One deadline for everything a route does: waits for an engine
        // slot, engine calls, corridor queries, the matching.
        let deadline = tokio::time::Instant::now() + ROUTE_DEADLINE;
        let mut work = Work::default();
        let result = tokio::time::timeout_at(deadline, async {
            let first = self
                .route_within(pool, graph_id, request, fresh, deadline, &mut work)
                .await;
            match first {
                // The remembered blockers led the trip where no safe way
                // remained: asked again without them, it ends as it did
                // before they were remembered.
                Ok(Outcome::NoSafeRoute { .. }) if work.used_remembered => {
                    work.without_remembered = true;
                    self.route_within(pool, graph_id, request, fresh, deadline, &mut work)
                        .await
                }
                other => other,
            }
        })
        .await
        .map_err(|_| RouteError::Deadline)
        .and_then(|r| r);
        Routed {
            result,
            engine_answered: work.answered,
            spent: work.spent,
        }
    }

    /// Keeps the restriction blockers of a check of graph `graph_id`, those
    /// of OpenStreetMap and the IGN, each counted once per request.
    fn remember(&self, graph_id: &str, blockers: &[Met]) {
        let mut memory = self
            .remembered
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if memory.graph_id != graph_id {
            memory.blockers.clear();
            graph_id.clone_into(&mut memory.graph_id);
        }
        let mut counted: Vec<uuid::Uuid> = Vec::new();
        for b in blockers {
            let r = &b.restriction;
            if !matches!(
                r.restriction.source,
                RestrictionSource::Osm | RestrictionSource::Ign
            ) || counted.contains(&r.id)
            {
                continue;
            }
            counted.push(r.id);
            let known = memory.blockers.iter().position(|k| k.id == r.id);
            let entry = match known.and_then(|i| memory.blockers.remove(i)) {
                Some(mut k) => {
                    k.met = k.met.saturating_add(1);
                    k
                }
                None => RememberedBlocker {
                    id: r.id,
                    at: b.hit.middle,
                    restriction: r.restriction.clone(),
                    met: 1,
                },
            };
            memory.blockers.push_back(entry);
        }
        while memory.blockers.len() > REMEMBERED {
            memory.blockers.pop_front();
        }
    }

    /// The remembered blockers of graph `graph_id` that block `dims` and
    /// that a route of `stops` may meet, away from the stops: the latest
    /// first, [`REMEMBERED_RINGS`] at most.
    fn remembered_for(
        &self,
        graph_id: &str,
        stops: &[Stop],
        dims: &RoutingDimensions,
    ) -> Vec<Position> {
        let memory = self
            .remembered
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if memory.graph_id != graph_id || stops.is_empty() {
            return Vec::new();
        }
        let (mut south, mut west, mut north, mut east) =
            (90.0_f64, 180.0_f64, -90.0_f64, -180.0_f64);
        for s in stops {
            south = south.min(s.at.lat());
            north = north.max(s.at.lat());
            west = west.min(s.at.lon());
            east = east.max(s.at.lon());
        }
        memory
            .blockers
            .iter()
            .rev()
            .filter(|k| k.met >= MET_BEFORE_AHEAD)
            .filter(|RememberedBlocker { at, .. }| {
                (south - TRIP_MARGIN_DEG..=north + TRIP_MARGIN_DEG).contains(&at.lat())
                    && (west - TRIP_MARGIN_DEG..=east + TRIP_MARGIN_DEG).contains(&at.lon())
                    && stops
                        .iter()
                        .all(|s| s.at.distance_m(*at) > CLEAR_OF_STOPS_M)
            })
            .filter(|k| {
                assess(&k.restriction, dims).is_some_and(|f| f.severity != Severity::Warning)
            })
            .map(|k| k.at)
            .take(REMEMBERED_RINGS)
            .collect()
    }

    /// The reasons a trip has no route, within what is left of the route's
    /// `deadline` and [`diagnose::DIAGNOSIS_DEADLINE`]; none when another
    /// diagnosis runs, when time runs out or when the engine fails.
    async fn explain(
        &self,
        engine: &Engine,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
        deadline: tokio::time::Instant,
    ) -> Vec<Unreachable> {
        let Ok(_one) = self.diagnoses.try_acquire() else {
            tracing::info!("another trip is being explained: this one is answered unexplained");
            return Vec::new();
        };
        let budget = deadline
            .saturating_duration_since(tokio::time::Instant::now())
            .saturating_sub(DIAGNOSIS_MARGIN)
            .min(diagnose::DIAGNOSIS_DEADLINE);
        match tokio::time::timeout(budget, diagnose::diagnose(engine, pool, graph_id, request))
            .await
        {
            Ok(Ok(r)) => r,
            Ok(Err(error)) => {
                tracing::warn!(%error, "a trip without a route could not be explained");
                Vec::new()
            }
            Err(_) => {
                tracing::warn!("explaining a trip without a route ran out of time");
                Vec::new()
            }
        }
    }

    /// The stops that do not snap to a road, within what is left of the
    /// route's `deadline`; none when time runs out or the engine fails.
    async fn off_network(
        engine: &Engine,
        request: &RouteRequest,
        costing: &Value,
        deadline: tokio::time::Instant,
    ) -> Vec<usize> {
        let budget = deadline
            .saturating_duration_since(tokio::time::Instant::now())
            .saturating_sub(DIAGNOSIS_MARGIN)
            .min(diagnose::DIAGNOSIS_DEADLINE);
        match tokio::time::timeout(budget, diagnose::off_network(engine, request, costing)).await {
            Ok(Ok(stops)) => stops,
            Ok(Err(error)) => {
                tracing::warn!(%error, "the stops off the network could not be named");
                Vec::new()
            }
            Err(_) => {
                tracing::warn!("naming the stops off the network ran out of time");
                Vec::new()
            }
        }
    }

    #[allow(
        clippy::too_many_lines,
        reason = "one loop of attempts, each step of which reads the previous one"
    )]
    async fn route_within(
        &self,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
        fresh: &Freshness,
        deadline: tokio::time::Instant,
        work: &mut Work,
    ) -> Result<Outcome, RouteError> {
        let engine = self.engine.as_ref().ok_or(RouteError::NotSetUp)?;
        let dims = request.vehicle.routing();
        let costing = valhalla::costing_options(&dims, request.avoid);
        let mut exclusions: Vec<Vec<Position>> = Vec::new();
        let mut centres: Vec<Position> = Vec::new();
        let mut blockers: Vec<Met> = Vec::new();
        let mut event_blockers: Vec<EventHit> = Vec::new();
        let mut avoided: Vec<Arc<EventRow>> = Vec::new();
        let mut snapped: Option<Vec<f64>> = None;
        let mut calls = 0;
        let alternates = valhalla::alternates_for(request.alternatives, request.straight_m());
        if !work.without_remembered {
            for centre in self.remembered_for(graph_id, &request.stops, &dims) {
                if centres.iter().all(|c| c.distance_m(centre) >= RING_M / 2.0) {
                    centres.push(centre);
                    exclusions.push(exclusion_ring(centre, RING_M));
                }
            }
        }
        let mut ahead = !centres.is_empty();
        work.used_remembered = ahead;
        let mut attempt = 0;
        while attempt < MAX_ATTEMPTS {
            calls = attempt + 1;
            let body = valhalla::route_body(
                &request.stops,
                &costing,
                request.language,
                alternates,
                &exclusions,
            );
            // The slot is held until the answer is checked and trimmed: the
            // memory of the answers in hand stays bounded by the slots.
            let waited = std::time::Instant::now();
            let _slot = tokio::time::timeout(self.queue_wait, self.slots.acquire())
                .await
                .map_err(|_| RouteError::Busy)?
                .map_err(|_| RouteError::Busy)?;
            let called = std::time::Instant::now();
            work.spent.queue += called - waited;
            let answer = engine.route(&body).await;
            work.spent.engine += called.elapsed();
            work.spent.engine_calls += 1;
            let answer = answer?;
            // From here the engine has worked for this client: a later
            // failure of the server is not given back (a trip made slow on
            // purpose would otherwise cost nothing).
            work.answered = true;
            let osrm = match answer {
                Answer::Routes(v) => v,
                // The remembered blockers closed the last way, or the road
                // a stop lies on: the trip is asked again without them, so
                // that a trip without a route is told why by the engine and
                // the check, as before they were remembered.
                Answer::NoSegment | Answer::NoRoute if attempt == 0 && ahead => {
                    ahead = false;
                    work.used_remembered = false;
                    exclusions.clear();
                    centres.clear();
                    continue;
                }
                Answer::NoSegment if attempt == 0 => {
                    let stops = Self::off_network(engine, request, &costing, deadline).await;
                    return Ok(Outcome::NoRoute(NoRoute::OffNetwork(stops)));
                }
                Answer::NoRoute if attempt == 0 => {
                    let reasons = self
                        .explain(engine, pool, graph_id, request, deadline)
                        .await;
                    return Ok(Outcome::NoRoute(NoRoute::Unreachable(reasons)));
                }
                // The exclusions closed the last way through, or the road a
                // stop lies on: the blockers of the previous attempt are why.
                Answer::NoRoute | Answer::NoSegment => {
                    return Ok(Outcome::NoSafeRoute {
                        blockers: distinct(blockers),
                        event_blockers: distinct_events(event_blockers),
                        recalculations: attempt,
                    });
                }
            };
            // A ring on the road a stop lies on makes the engine snap the
            // stop to another road, maybe far away: that is not the trip
            // asked for.
            let distances = snap_distances(&osrm);
            match &snapped {
                None => snapped = Some(distances),
                Some(first) => {
                    let moved = first
                        .iter()
                        .zip(&distances)
                        .any(|(a, b)| b - a > STOP_MOVED_M);
                    if moved {
                        return Ok(Outcome::NoSafeRoute {
                            blockers: distinct(blockers),
                            event_blockers: distinct_events(event_blockers),
                            recalculations: attempt,
                        });
                    }
                }
            }
            // Shared with the checks off the async threads rather than copied
            // for each route: 1.3 ms for a 650 km route (measured, test
            // `copying_a_long_route_costs_little`).
            let osrm = Arc::new(osrm);
            let checked =
                check_routes(pool, graph_id, &osrm, &dims, request.depart_at, fresh, work).await?;
            // The checks are over and dropped their shares: no copy.
            let osrm = Arc::try_unwrap(osrm).unwrap_or_else(|shared| (*shared).clone());
            let (safe, blocked): (Vec<_>, Vec<_>) = checked
                .into_iter()
                .partition(|(_, blocking, events)| blocking.is_empty() && events.is_empty());
            if !safe.is_empty() {
                let routes = safe.into_iter().map(|(r, _, _)| r).collect();
                let (osrm, routes) = keep_routes(osrm, routes, request.language)?;
                return Ok(Outcome::Found {
                    osrm,
                    routes,
                    recalculations: attempt,
                    avoided,
                });
            }
            blockers = Vec::new();
            event_blockers = Vec::new();
            for (_, b, e) in blocked {
                blockers.extend(b);
                event_blockers.extend(e);
            }
            self.remember(graph_id, &blockers);
            for e in &event_blockers {
                if !avoided.iter().any(|a| a.id == e.event.id) {
                    avoided.push(Arc::clone(&e.event));
                }
            }
            let before = exclusions.len();
            let rings = blockers.iter().map(|b| (b.hit.middle, RING_M)).chain(
                event_blockers
                    .iter()
                    .flat_map(|e| e.rings.iter().map(|r| (*r, events::RING_M))),
            );
            // A blocker within half a radius of a ring already sent is
            // inside it (an OpenStreetMap way and the IGN section of the same
            // bridge): no second ring. One farther away gets its own, even on
            // the next road.
            for (centre, radius) in rings {
                if exclusions.len() >= MAX_EXCLUSIONS
                    || centres.iter().any(|c| c.distance_m(centre) < radius / 2.0)
                {
                    continue;
                }
                centres.push(centre);
                exclusions.push(exclusion_ring(centre, radius));
            }
            if exclusions.len() == before {
                // Nothing new to exclude: the engine keeps going through.
                break;
            }
            tracing::info!(
                attempt,
                blockers = blockers.len(),
                road_events = event_blockers.len(),
                exclusions = exclusions.len(),
                "route recalculated around limits the vehicle exceeds or closed roads"
            );
            attempt += 1;
        }
        Ok(Outcome::NoSafeRoute {
            blockers: distinct(blockers),
            event_blockers: distinct_events(event_blockers),
            recalculations: calls.saturating_sub(1),
        })
    }
}

/// Speed-limit pieces traced at once for one request.
const TRACES_AT_ONCE: usize = 2;

/// A route ready for its speed-limit traces.
struct Traced {
    points: Vec<Position>,
    along: Vec<f64>,
    /// Each piece's first shape index and its trace request.
    bodies: Vec<(usize, Value)>,
}

/// `route`'s shape, its distances and the trace requests of its pieces;
/// none when it needs more pieces than [`limits::MAX_CHUNKS`].
async fn prepare_trace(route: &Value) -> Result<Option<Traced>, RouteError> {
    let shape = route
        .get("geometry")
        .and_then(Value::as_str)
        .ok_or(RouteError::Malformed("no geometry"))?
        .to_owned();
    // Decoding a long shape and encoding its pieces is CPU work: off the
    // async threads.
    tokio::task::spawn_blocking(move || {
        let points = polyline::decode(&shape).map_err(RouteError::Shape)?;
        let mut along = Vec::with_capacity(points.len());
        let mut total = 0.0;
        for (i, p) in points.iter().enumerate() {
            if i > 0 {
                total += points[i - 1].distance_m(*p);
            }
            along.push(total);
        }
        let Some(pieces) = limits::chunks(&along) else {
            return Ok(None);
        };
        let bodies = pieces
            .into_iter()
            .map(|(first, last)| (first, limits::trace_body(&points[first..=last])))
            .collect();
        Ok(Some(Traced {
            points,
            along,
            bodies,
        }))
    })
    .await
    .map_err(RouteError::Blocking)?
}

/// Each road event once, at its first place, in driving order.
fn distinct_events(mut hits: Vec<EventHit>) -> Vec<EventHit> {
    let mut seen = std::collections::HashSet::new();
    hits.retain(|h| seen.insert(h.event.id));
    hits
}

/// How much farther a stop may be snapped after a recalculation than at
/// first, metres.
const STOP_MOVED_M: f64 = 30.0;

/// How far the engine snapped each stop from the point asked, metres, from
/// the OSRM answer's `waypoints`.
fn snap_distances(osrm: &Value) -> Vec<f64> {
    osrm.get("waypoints")
        .and_then(Value::as_array)
        .map(|w| {
            w.iter()
                .map(|p| p.get("distance").and_then(Value::as_f64).unwrap_or(0.0))
                .collect()
        })
        .unwrap_or_default()
}

/// Each restriction once, at its first place (the alternatives of one
/// answer meet the same bridge), in driving order.
fn distinct(mut blockers: Vec<Met>) -> Vec<Met> {
    let mut seen = std::collections::HashSet::new();
    blockers.retain(|m| seen.insert(m.restriction.id));
    blockers
}

/// What a route request has done so far. It lives outside the future the
/// route's deadline cuts, so a route out of time still tells whether the
/// engine worked for it and where the time went.
#[derive(Default)]
struct Work {
    /// Whether the engine answered at least once.
    answered: bool,
    /// Where the time went.
    spent: Spent,
    /// What the corridor queries found.
    known: Known,
    /// Whether the remembered blockers went into the first call.
    used_remembered: bool,
    /// Whether to leave them out.
    without_remembered: bool,
}

/// A route as checked: what the app receives, the restrictions that block
/// it, the road events that block it.
type Checked = (CheckedRoute, Vec<Met>, Vec<EventHit>);

/// What the corridor queries of one route request found so far: the
/// stretches they read, and the restrictions and road events near them. A
/// route computed again runs where the previous one ran but around a ring
/// of a few metres, and an alternative shares most of the best route: only
/// what no query covered is asked again. It holds a few lines and a few
/// thousand rows for the request's life, under its engine slot, and the
/// segments of the stretches: 40 bytes each, 4 to 6 MB for a trip of
/// 3 000 km and its alternatives.
#[derive(Default)]
struct Known {
    /// The stretches queried, each exactly as it was: a stretch only
    /// covered by an earlier one is not among them, so the margin is never
    /// spent twice.
    queried: Vec<Arc<RouteLine>>,
    /// The segments of those stretches, as their ends' exact coordinates:
    /// an alternative or a route computed again repeats most of the shape
    /// points of the routes before it, and a segment found here is covered
    /// without sampling it against every stretch.
    segments: Arc<HashSet<Segment>>,
    restrictions: HashMap<uuid::Uuid, db::NearRestriction>,
    events: HashMap<uuid::Uuid, Arc<EventRow>>,
}

/// A segment of a shape by its ends' coordinates, bit for bit: the engine
/// writes every route of an answer, and of a later answer, at the same
/// precision, so a road two routes share has the same points in both.
type Segment = [u64; 4];

fn segment(a: Position, b: Position) -> Segment {
    [
        a.lat().to_bits(),
        a.lon().to_bits(),
        b.lat().to_bits(),
        b.lon().to_bits(),
    ]
}

/// Whether the segment from `a` to `b` is covered: samples every
/// [`SAMPLE_M`] along it, its ends included, each within [`COVERED_M`] of
/// a queried stretch. A segment that cuts across between two covered ends
/// (a chord of a bend, a short link between two known roads) has a sample
/// off them.
fn covered(a: Position, b: Position, queried: &[Arc<RouteLine>]) -> bool {
    let near = |p: Position| queried.iter().any(|l| l.project(p, COVERED_M).is_some());
    let length = a.distance_m(b);
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        reason = "a count of samples along one segment of a route, positive and small"
    )]
    let steps = (length / SAMPLE_M).ceil().max(1.0) as u32;
    (0..=steps).all(|k| {
        let t = f64::from(k) / f64::from(steps);
        Position::new(
            a.lat() + (b.lat() - a.lat()) * t,
            a.lon() + (b.lon() - a.lon()) * t,
        )
        .is_ok_and(near)
    })
}

/// The stretches of `points` that the `queried` stretches do not cover,
/// as ranges of indices: the segments [`covered`] refuses, joined when
/// they touch. A segment of a queried stretch, either way round, is covered
/// as it is: every sample of it lies on that stretch.
fn uncovered(
    points: &[Position],
    queried: &[Arc<RouteLine>],
    segments: &HashSet<Segment>,
) -> Vec<std::ops::Range<usize>> {
    if queried.is_empty() {
        return std::iter::once(0..points.len()).collect();
    }
    let mut runs: Vec<std::ops::Range<usize>> = Vec::new();
    for (i, w) in points.windows(2).enumerate() {
        if segments.contains(&segment(w[0], w[1]))
            || segments.contains(&segment(w[1], w[0]))
            || covered(w[0], w[1], queried)
        {
            continue;
        }
        match runs.last_mut() {
            Some(last) if last.end > i => last.end = i + 2,
            _ => runs.push(i..i + 2),
        }
    }
    runs
}

/// Queries the corridor of each stretch of `points` that `known` does not
/// cover, and adds what it finds.
async fn query_corridors(
    pool: &PgPool,
    graph_id: &str,
    points: Arc<Vec<Position>>,
    known: &mut Known,
) -> Result<(), RouteError> {
    let queried = known.queried.clone();
    let segments = Arc::clone(&known.segments);
    let shared = Arc::clone(&points);
    // Sampling a long route every few metres: off the async threads.
    let runs = tokio::task::spawn_blocking(move || uncovered(&shared, &queried, &segments))
        .await
        .map_err(RouteError::Blocking)?;
    for run in runs {
        let stretch = &points[run];
        let Some(line) = RouteLine::new(stretch.to_vec()) else {
            continue;
        };
        let within = CORRIDOR_M + QUERY_MARGIN_M;
        let events = lunaway_db::road_events::events_near(
            pool,
            stretch,
            events::CORRIDOR_M + QUERY_MARGIN_M,
            events::WIDE_M + QUERY_MARGIN_M,
        );
        // Two pool connections at most for a route: the halves of a long
        // stretch together, then its events; a shorter one with its events.
        let (restrictions, events) = if stretch.len() > QUERY_POINTS {
            let mid = stretch.len() / 2;
            let (a, b) = tokio::try_join!(
                db::restrictions_near(pool, graph_id, &stretch[..=mid], within),
                db::restrictions_near(pool, graph_id, &stretch[mid..], within),
            )?;
            (a.into_iter().chain(b).collect::<Vec<_>>(), events.await?)
        } else {
            tokio::try_join!(
                db::restrictions_near(pool, graph_id, stretch, within),
                events
            )?
        };
        for r in restrictions {
            known.restrictions.entry(r.id).or_insert(r);
        }
        for e in events {
            known.events.entry(e.id).or_insert_with(|| Arc::new(e));
        }
        known.queried.push(Arc::new(line));
        // The task above has ended and dropped its share: no copy.
        Arc::make_mut(&mut known.segments).extend(stretch.windows(2).map(|w| segment(w[0], w[1])));
    }
    Ok(())
}

/// Each route of `osrm`, with its warnings and its blockers.
async fn check_routes(
    pool: &PgPool,
    graph_id: &str,
    osrm: &Arc<Value>,
    dims: &RoutingDimensions,
    depart_at: DateTime<Utc>,
    fresh: &Freshness,
    work: &mut Work,
) -> Result<Vec<Checked>, RouteError> {
    let routes = osrm
        .get("routes")
        .and_then(Value::as_array)
        .ok_or(RouteError::Malformed("no routes"))?;
    let mut out = Vec::with_capacity(routes.len());
    for (index, route) in routes.iter().enumerate() {
        let shape = route
            .get("geometry")
            .and_then(Value::as_str)
            .ok_or(RouteError::Malformed("no geometry"))?;
        let points = polyline::decode(shape).map_err(RouteError::Shape)?;
        // A shape longer than the corridor query reads is never checked in
        // part: an alternative that long is dropped, the best route refused.
        if points.len() > db::MAX_ROUTE_POINTS {
            if index == 0 {
                return Err(RouteError::TooLarge);
            }
            continue;
        }
        let points = Arc::new(points);
        let queried = std::time::Instant::now();
        query_corridors(pool, graph_id, Arc::clone(&points), &mut work.known).await?;
        work.spent.corridor += queried.elapsed();
        let matched = std::time::Instant::now();
        // Everything known near this request's routes: the check keeps what
        // this route meets.
        let near: Vec<db::NearRestriction> = work.known.restrictions.values().cloned().collect();
        let near_events: Vec<Arc<EventRow>> = work.known.events.values().cloned().collect();
        let legs: Vec<f64> = route
            .get("legs")
            .and_then(Value::as_array)
            .map(|legs| {
                legs.iter()
                    .map(|l| l.get("distance").and_then(Value::as_f64).unwrap_or(0.0))
                    .collect()
            })
            .unwrap_or_default();
        let dims = *dims;
        let shared = Arc::clone(osrm);
        let fresh = fresh.clone();
        // Indexing a long shape and matching hundreds of restrictions and
        // events takes milliseconds to tens of milliseconds of CPU: off the
        // async threads.
        let ((warnings, blocking), (events, event_blocking)) =
            tokio::task::spawn_blocking(move || {
                let route_value = &shared["routes"][index];
                let points = Arc::try_unwrap(points).unwrap_or_else(|p| (*p).clone());
                let line = RouteLine::new(points)
                    .ok_or(RouteError::Malformed("a route of one point"))?
                    .with_legs(&legs);
                let restrictions = match_restrictions(&line, near, &dims);
                let steps = events::steps_of(route_value, &line);
                let timing = Timing::of(route_value, &line, depart_at);
                let met = events::check(
                    &line,
                    &steps,
                    &timing,
                    &near_events,
                    &dims,
                    &fresh,
                    Utc::now(),
                );
                Ok::<_, RouteError>((restrictions, met))
            })
            .await
            .map_err(RouteError::Blocking)??;
        work.spent.check += matched.elapsed();
        let (has_toll, has_ferry, has_motorway) = classes(route);
        out.push((
            CheckedRoute {
                index,
                distance_m: route.get("distance").and_then(Value::as_f64).unwrap_or(0.0),
                duration_s: route.get("duration").and_then(Value::as_f64).unwrap_or(0.0),
                has_toll,
                has_ferry,
                has_motorway,
                ferries: ferries::crossings(route),
                warnings,
                events,
            },
            blocking,
            event_blocking,
        ));
    }
    Ok(out)
}

/// The restrictions `near` a route that it drives through, weighed against
/// the vehicle: (warnings, blockers), each in driving order. Fails closed: a
/// severity this code does not know blocks.
pub(crate) fn match_restrictions(
    line: &RouteLine,
    near: Vec<db::NearRestriction>,
    dims: &RoutingDimensions,
) -> (Vec<Met>, Vec<Met>) {
    let mut warnings = Vec::new();
    let mut blocking = Vec::new();
    for r in near {
        let hits = match_route(line, &r.geometry, r.restriction.source.tolerance_m());
        let Some(hit) = hits.first().copied() else {
            continue;
        };
        let Some(finding) = assess(&r.restriction, dims) else {
            continue;
        };
        let met = Met {
            finding,
            restriction: r,
            hit,
        };
        match finding.severity {
            Severity::Warning => warnings.push(met),
            _ => blocking.push(met),
        }
    }
    warnings.sort_by(|a, b| a.hit.start_m.total_cmp(&b.hit.start_m));
    blocking.sort_by(|a, b| a.hit.start_m.total_cmp(&b.hit.start_m));
    (warnings, blocking)
}

/// Whether a route of the OSRM answer uses a toll road, a ferry, a
/// motorway: the `classes` of its intersections, and the steps' mode.
fn classes(route: &Value) -> (bool, bool, bool) {
    let (mut toll, mut ferry, mut motorway) = (false, false, false);
    let steps = route
        .get("legs")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|leg| leg.get("steps").and_then(Value::as_array))
        .flatten();
    for step in steps {
        if step.get("mode").and_then(Value::as_str) == Some("ferry") {
            ferry = true;
        }
        let classes = step
            .get("intersections")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|i| i.get("classes").and_then(Value::as_array))
            .flatten()
            .filter_map(Value::as_str);
        for c in classes {
            match c {
                "toll" => toll = true,
                "ferry" => ferry = true,
                "motorway" => motorway = true,
                _ => {}
            }
        }
    }
    (toll, ferry, motorway)
}

/// `osrm` with only `routes` (in their order), their indices renumbered,
/// French instructions corrected, and alternatives dropped from the end
/// while the answer exceeds [`MAX_OSRM_BYTES`].
fn keep_routes(
    mut osrm: Value,
    mut routes: Vec<CheckedRoute>,
    language: &str,
) -> Result<(Value, Vec<CheckedRoute>), RouteError> {
    let mut all = osrm
        .get_mut("routes")
        .and_then(Value::as_array_mut)
        .map(std::mem::take)
        .unwrap_or_default();
    // Taken, not copied: the routes not kept are dropped with `all`.
    let mut kept: Vec<Value> = routes
        .iter()
        .filter_map(|r| all.get_mut(r.index).map(Value::take))
        .collect();
    for (i, r) in routes.iter_mut().enumerate() {
        r.index = i;
    }
    if language.starts_with("fr") {
        for route in &mut kept {
            fix_instructions(route);
        }
    }
    // Each route's size once; the envelope (code, waypoints) is small.
    let sizes: Vec<usize> = kept
        .iter()
        .map(|r| serde_json::to_vec(r).map_or(usize::MAX, |v| v.len()))
        .collect();
    let mut n = kept.len();
    while n > 0 && sizes[..n].iter().fold(0_usize, |a, b| a.saturating_add(*b)) > MAX_OSRM_BYTES {
        n -= 1;
    }
    if n == 0 {
        return Err(RouteError::TooLarge);
    }
    kept.truncate(n);
    routes.truncate(n);
    osrm["routes"] = Value::Array(kept);
    Ok((osrm, routes))
}

/// Verbs Valhalla's French instructions start with: after a comma they take
/// a lower case.
const FRENCH_VERBS: [&str; 16] = [
    "Tournez",
    "Prenez",
    "Continuez",
    "Restez",
    "Serrez",
    "Gardez",
    "Faites",
    "Entrez",
    "Sortez",
    "Quittez",
    "Rejoignez",
    "Empruntez",
    "Conduisez",
    "Roulez",
    "Dirigez",
    "Suivez",
];

/// Two defects of Valhalla 3.9.0's French text, measured in the research
/// (`plan/research/07-navigation.md`, C.2): a capital after a comma
/// ("Ensuite, dans 60 mètres, Tournez à gauche") and a doubled full stop
/// ("Boulevard Voltaire..").
pub(crate) fn fix_french(text: &str) -> String {
    let mut out = text.replace("..", ".");
    for verb in FRENCH_VERBS {
        let after = format!(", {verb}");
        if out.contains(&after) {
            let lower: String = verb
                .chars()
                .enumerate()
                .map(|(i, c)| if i == 0 { c.to_ascii_lowercase() } else { c })
                .collect();
            out = out.replace(&after, &format!(", {lower}"));
        }
    }
    out
}

/// Applies [`fix_french`] to every instruction text of a route.
fn fix_instructions(route: &mut Value) {
    fn walk(v: &mut Value) {
        match v {
            Value::Object(map) => {
                for (k, child) in map.iter_mut() {
                    match (k.as_str(), child) {
                        (
                            "instruction" | "announcement" | "ssmlAnnouncement" | "text",
                            Value::String(s),
                        ) => {
                            *s = fix_french(s);
                        }
                        (_, other) => walk(other),
                    }
                }
            }
            Value::Array(list) => list.iter_mut().for_each(walk),
            _ => {}
        }
    }
    if let Some(legs) = route.get_mut("legs") {
        walk(legs);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A height limit of 2.7 m from `source`, met by a route at `at`.
    fn met(source: RestrictionSource, id: u128, at: Position) -> Met {
        let restriction = Restriction {
            kind: lunaway_domain::routing::RestrictionKind::MaxHeight,
            limit: Some(2.7),
            source,
            certainty: lunaway_domain::routing::Certainty::Known,
            feature: lunaway_domain::routing::RestrictionFeature::Underpass,
        };
        Met {
            finding: assess(&restriction, &dims(3.3)).unwrap(),
            restriction: db::NearRestriction {
                id: uuid::Uuid::from_u128(id),
                restriction,
                external_id: format!("way/{id}"),
                name: None,
                geometry: vec![at],
            },
            hit: Hit {
                start_m: 0.0,
                end_m: 0.0,
                geometry_index: 0,
                at,
                middle: at,
            },
        }
    }

    fn dims(height_m: f64) -> RoutingDimensions {
        RoutingDimensions {
            height_m,
            width_m: 2.3,
            length_m: 7.4,
            weight_t: 3.5,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: None,
        }
    }

    fn stops(points: &[(f64, f64)]) -> Vec<Stop> {
        points
            .iter()
            .map(|&(lat, lon)| Stop {
                at: Position::new(lat, lon).unwrap(),
                heading: None,
            })
            .collect()
    }

    #[test]
    fn only_graph_blockers_two_requests_met_are_excluded_ahead() {
        let routing = Routing::new(&RoutingConfig::default());
        let g = "20261006T2326Z-eu";
        let bridge = Position::new(45.8465, 1.2853).unwrap();
        let order = Position::new(45.85, 1.29).unwrap();
        let trip = stops(&[(45.70, 1.10), (46.00, 1.45)]);
        let blockers = [
            met(RestrictionSource::Osm, 1, bridge),
            met(RestrictionSource::Dialog, 2, order),
        ];
        // The same bridge twice in one answer, from two of its routes.
        routing.remember(g, &[blockers[0].clone(), blockers[0].clone()]);
        assert!(
            routing.remembered_for(g, &trip, &dims(3.3)).is_empty(),
            "one request leaves nothing another client could notice"
        );
        routing.remember(g, &blockers);
        assert_eq!(
            routing.remembered_for(g, &trip, &dims(3.3)),
            [bridge],
            "the bridge of the graph, met by two requests; never DiaLog's \
             order, which a later reading may end"
        );
        routing.remember(g, &blockers);
        assert_eq!(routing.remembered_for(g, &trip, &dims(3.3)), [bridge]);
        assert!(
            routing.remembered_for(g, &trip, &dims(2.5)).is_empty(),
            "a van under the limit is not kept from it"
        );
        assert!(
            routing
                .remembered_for(g, &stops(&[(48.0, -4.0), (48.5, -3.0)]), &dims(3.3))
                .is_empty(),
            "a trip in Brittany cannot meet a bridge in Limoges"
        );
        assert!(
            routing
                .remembered_for(g, &stops(&[(45.80, 1.25), (46.00, 1.45)]), &dims(3.3))
                .is_empty(),
            "a trip starting near it: a ring there could move the stop"
        );
        routing.remember("20261013T0300Z-eu", &[]);
        assert!(
            routing.remembered_for(g, &trip, &dims(3.3)).is_empty(),
            "a new graph forgets the old one's blockers"
        );
    }

    /// Measures what copying a long route's answer costs before its check
    /// leaves the async threads (`check_routes`), against the steps and
    /// timing read from it: run with `--run-ignored only --no-capture`.
    #[test]
    #[ignore = "a measurement, printed"]
    fn copying_a_long_route_costs_little() {
        // A 650 km route as the engine answers it: one point every 40 m,
        // a duration and a distance per segment, 400 steps.
        let points: Vec<Position> = (0..16_000)
            .map(|i| Position::new(43.0 + f64::from(i) * 0.000_36, 1.0).unwrap())
            .collect();
        let segments = points.len() - 1;
        let steps: Vec<Value> = (0..400)
            .map(|i| {
                serde_json::json!({
                    "distance": 1_600.0, "duration": 60.0, "ref": "A 20; E 09",
                    "name": format!("Route {i}"),
                    "maneuver": {"type": "turn", "modifier": "right", "location": [1.0, 43.0],
                                 "bearing_before": 0, "bearing_after": 90,
                                 "instruction": "Tournez à droite sur la route"},
                    "intersections": [{"location": [1.0, 43.0], "bearings": [0, 90, 180],
                                       "entry": [true, true, false]}],
                })
            })
            .collect();
        let route = serde_json::json!({
            "distance": 650_000.0, "duration": 25_000.0,
            "geometry": polyline::encode(&points),
            "legs": [{"steps": steps, "annotation": {
                "duration": vec![1.5; segments], "distance": vec![40.0; segments]}}],
        });
        let line = RouteLine::new(points).unwrap();
        let rounds: u32 = 50;
        let t = std::time::Instant::now();
        for _ in 0..rounds {
            std::hint::black_box(route.clone());
        }
        let clone = t.elapsed() / rounds;
        let t = std::time::Instant::now();
        for _ in 0..rounds {
            std::hint::black_box(events::steps_of(&route, &line));
            std::hint::black_box(Timing::of(&route, &line, Utc::now()));
        }
        let read = t.elapsed() / rounds;
        println!("route of {segments} segments: clone {clone:?}, steps and timing {read:?}");
    }

    #[test]
    fn french_instructions_lose_their_two_defects() {
        assert_eq!(
            fix_french("Ensuite, dans 60 mètres, Tournez à gauche."),
            "Ensuite, dans 60 mètres, tournez à gauche."
        );
        assert_eq!(
            fix_french("Continuez sur Boulevard Voltaire.."),
            "Continuez sur Boulevard Voltaire."
        );
        assert_eq!(
            fix_french("Prenez la sortie, Rue Victor Hugo."),
            "Prenez la sortie, Rue Victor Hugo.",
            "a street name keeps its capital"
        );
    }

    #[test]
    fn the_rings_sent_stay_within_the_engine_s_limits() {
        // The configuration the backend serves the engine with.
        let config: Value =
            serde_json::from_str(include_str!("../../../../../infra/routing/valhalla.json"))
                .unwrap();
        let limits = &config["service_limits"];
        let vertices = limits["max_exclude_polygons_vertices"].as_u64().unwrap();
        let perimeter = limits["max_exclude_polygons_length"].as_f64().unwrap();
        let ring = exclusion_ring(Position::new(45.8, 1.25).unwrap(), RING_M);
        let ring_perimeter: f64 = ring.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        #[allow(
            clippy::cast_precision_loss,
            reason = "a count of rings of a few hundred"
        )]
        let all = MAX_EXCLUSIONS as f64;
        assert!(
            (MAX_EXCLUSIONS * ring.len()) as u64 <= vertices,
            "the engine refuses more vertices than its limit: the whole route request fails"
        );
        assert!(
            all * ring_perimeter <= perimeter,
            "nor more perimeter than its limit"
        );
    }

    #[test]
    fn the_matrix_is_bounded_whenever_the_engine_serves_it() {
        // Only the fuel search asks for matrices, its points less than 60 km
        // apart: an engine that serves them takes no farther pairs.
        let config: Value =
            serde_json::from_str(include_str!("../../../../../infra/routing/valhalla.json"))
                .unwrap();
        let served = config["loki"]["actions"]
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a == "sources_to_targets");
        let distance = config["service_limits"]["auto"]["max_matrix_distance"]
            .as_f64()
            .unwrap();
        assert!(
            !served || distance <= 60_000.0,
            "sources_to_targets is served with max_matrix_distance {distance}"
        );
    }

    /// The segments of the stretches queried, as `query_corridors` keeps
    /// them.
    fn segments_of(points: &[&[Position]]) -> HashSet<Segment> {
        points
            .iter()
            .flat_map(|p| p.windows(2).map(|w| segment(w[0], w[1])))
            .collect()
    }

    #[test]
    fn a_route_computed_again_is_queried_only_where_it_is_new() {
        let p = |lon: f64| Position::new(45.0, lon).unwrap();
        let first: Vec<Position> = (0..100).map(|i| p(1.0 + f64::from(i) * 0.001)).collect();
        let lines = vec![Arc::new(RouteLine::new(first.clone()).unwrap())];
        let known = segments_of(&[&first]);
        // The same answers with the segments known as without: they only
        // spare the sampling.
        for segments in [HashSet::new(), known] {
            let all = uncovered(&first, &[], &segments);
            assert!(all.len() == 1 && all[0] == (0..100), "nothing known yet");
            assert!(
                uncovered(&first, &lines, &segments).is_empty(),
                "the same route"
            );
            let back: Vec<Position> = first.iter().rev().copied().collect();
            assert!(
                uncovered(&back, &lines, &segments).is_empty(),
                "the same road the other way"
            );
            // The same route around a ring between its 40th and 45th points.
            let mut again = first.clone();
            for q in &mut again[40..45] {
                *q = Position::new(45.0005, q.lon()).unwrap();
            }
            let detour = uncovered(&again, &lines, &segments);
            assert!(
                detour.len() == 1 && detour[0] == (39..46),
                "the detour, with the points that join it to the known line: {detour:?}"
            );
        }
    }

    #[test]
    fn a_chord_between_two_known_points_is_queried() {
        // The first route turns a corner, X to Z to Y; the second goes
        // straight from X to Y, both ends on the first one, no point
        // between: a bridge on that street must not be missed.
        let x = Position::new(45.0, 1.0).unwrap();
        let z = Position::new(45.0, 1.01).unwrap();
        let y = Position::new(45.01, 1.01).unwrap();
        let first = vec![Arc::new(RouteLine::new(vec![x, z, y]).unwrap())];
        let segments = segments_of(&[&[x, z, y]]);
        let chord = uncovered(&[x, y], &first, &segments);
        assert!(chord.len() == 1 && chord[0] == (0..2), "{chord:?}");
        // Along the first route, however far apart its points.
        assert!(uncovered(&[x, z, y], &first, &segments).is_empty());
    }

    #[test]
    fn the_longest_route_fits_the_api_s_answer() {
        // The OSRM answer travels as a JSON string, its quotes escaped, with
        // the summaries beside it: Seville to the North Cape, an engine
        // answer of 6.4 MB, gave a response of 7.05 MB (2026-10-07), a tenth
        // more; the speed limits of a long route add a few hundred kB.
        #[allow(clippy::cast_precision_loss, reason = "sizes of a few megabytes")]
        let escaped = MAX_OSRM_BYTES as f64 * 1.1 + 1_000_000.0;
        #[allow(clippy::cast_precision_loss, reason = "sizes of a few megabytes")]
        let limit = crate::config::Limits::default().max_response_bytes as f64;
        assert!(
            escaped < limit,
            "a route the API keeps must fit the response it is sent in"
        );
        // The routes kept come out of the engine's answer.
        const { assert!(MAX_OSRM_BYTES < valhalla::MAX_ANSWER_BYTES) };
    }

    #[test]
    fn tolls_ferries_and_motorways_are_read_from_the_steps() {
        let route = serde_json::json!({"legs": [{"steps": [
            {"mode": "driving", "intersections": [{"classes": ["toll", "motorway"]}]},
            {"mode": "ferry", "intersections": [{}]}
        ]}]});
        assert_eq!(classes(&route), (true, true, true));
        assert_eq!(
            classes(&serde_json::json!({"legs": []})),
            (false, false, false)
        );
    }
}
