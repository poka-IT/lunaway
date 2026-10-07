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
pub(crate) mod public;
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
        Finding, Hit, RouteLine, RoutingDimensions, Severity, VehicleProfile, assess, distance_to,
        exclusion_ring, local_access_runs, match_restriction, polyline,
    },
};
use serde_json::Value;
use tokio::sync::Semaphore;

use self::{
    diagnose::{Place, Unreachable},
    events::{EventHit, Freshness, Timing},
    ferries::Ferry,
    valhalla::{Answer, Avoid, Engine, EngineError, Stop},
};
use crate::config::RoutingConfig;

/// Engine calls for one route at most: the first, and three more with the
/// blockers excluded (twice that, and one, when the restrictions excluded
/// ahead ([`public`]) closed the way and the trip is asked again without
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
/// Longest the speed limits of an engine answer may take, all its routes
/// together, from the answer: they are traced during its check, and their
/// wait after it stays within the route's deadline.
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
/// How near the user's point the restriction that keeps the vehicle from a
/// stop must lie for the stop to be looked for farther away, metres: the
/// car park under a square, the aisle the point was snapped to, the narrow
/// street in front of it. The three city centres still refused after the
/// tunnel filter had theirs at 30, 48 and 172 m (Strasbourg, Marseille
/// Saint-Charles, Montpellier; 2026-10-07,
/// `plan/research/65-accroche-et-desserte.md`); a limit farther away keeps
/// a whole district from the vehicle, and moving the stop would not help.
const MOVE_WITHIN_M: f64 = 200.0;
/// The search radii a stop the vehicle cannot reach is asked again with,
/// metres, the next one only when the first gives no route: at 100 m,
/// Saint-Charles reaches the station's forecourt (66 m) and Montpellier
/// the rue Baudin (80 m); Strasbourg needs 150 m (place de l'Homme de Fer,
/// 141 m). Within the engine's `max_radius` (`infra/routing/valhalla.json`,
/// a test reads it).
pub(crate) const MOVE_RADII_M: [u32; 2] = [100, 150];

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

/// A stop the vehicle could not reach where the user put it, which the
/// routes start or end at instead.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct MovedStop {
    /// Its index among the request's stops.
    pub(crate) index: usize,
    /// Where the routes start or end now: the point of the road the engine
    /// snapped it to.
    pub(crate) at: Position,
    /// How far from the point asked, metres.
    pub(crate) distance_m: f64,
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
        /// The speed limits along each route, when asked: none for a route
        /// the engine could not trace in time.
        limits: Vec<Option<Vec<lunaway_domain::speed::Span>>>,
        /// The stops moved to a road the vehicle can reach.
        moved: Vec<MovedStop>,
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
    /// Waiting for the speed limits once the routes were checked: they
    /// are traced during the check.
    pub(crate) limits: Duration,
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
    /// Engine calls in flight at most.
    concurrency: usize,
    /// The restrictions excluded from the first call of a trip, computed
    /// from public data ([`public`]).
    public: std::sync::RwLock<Option<Arc<public::Lists>>>,
    /// Held by the refresh of [`Self::public`] that runs.
    refreshing: tokio::sync::Mutex<()>,
}

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
            concurrency: config.concurrency.max(1),
            public: std::sync::RwLock::new(None),
            refreshing: tokio::sync::Mutex::new(()),
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
    ///
    /// The pieces of a route marked in `skip` are not traced from then on:
    /// the check found the route blocked, and it will not be sent.
    async fn speed_limits(
        &self,
        osrm: &Value,
        vehicle: lunaway_domain::speed::Vehicle,
        skip: &[std::sync::atomic::AtomicBool],
    ) -> Vec<Option<Vec<lunaway_domain::speed::Span>>> {
        let routes = osrm
            .get("routes")
            .and_then(Value::as_array)
            .map_or(&[][..], Vec::as_slice);
        let traced =
            tokio::time::timeout(LIMITS_DEADLINE, self.trace_routes(routes, vehicle, skip)).await;
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
        skip: &[std::sync::atomic::AtomicBool],
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
        // The pieces of every route, one at a time under the route call's
        // engine slot: a piece takes 15 to 25 ms of the engine, those of a
        // route of 3 000 km 0.3 to 0.5 s, about as long as its check,
        // during which they run (2026-10-07). The other slots stay with
        // the route calls of other trips, and best-effort speed limits
        // never make a route fail.
        let pieces: Vec<(usize, &Traced, usize, usize, &Value)> = prepared
            .iter()
            .enumerate()
            .filter_map(|(r, p)| p.as_ref().map(|p| (r, p)))
            .flat_map(|(r, p)| {
                p.bodies
                    .iter()
                    .map(move |(first, last, body)| (r, p, *first, *last, body))
            })
            .collect();
        let calls: Vec<_> = pieces
            .iter()
            .map(|&(r, p, first, last, body)| async move {
                if skip
                    .get(r)
                    .is_some_and(|s| s.load(std::sync::atomic::Ordering::Relaxed))
                {
                    return Err(RouteError::Malformed("a route found blocked"));
                }
                self.trace_stretch(engine, &p.points, first, last, Some(body), &p.refused)
                    .await
            })
            .collect();
        let answers: Vec<Result<Vec<lunaway_domain::speed::Edge>, RouteError>> =
            futures_util::stream::iter(calls)
                .buffered(TRACES_AT_ONCE)
                .collect()
                .await;
        let mut edges: Vec<Option<Vec<lunaway_domain::speed::Edge>>> = prepared
            .iter()
            .map(|p| p.as_ref().map(|_| Vec::new()))
            .collect();
        for ((r, ..), answer) in pieces.into_iter().zip(answers) {
            match (answer, &mut edges[r]) {
                (Ok(e), Some(all)) => all.extend(e),
                (Err(error), _) => {
                    let blocked = skip
                        .get(r)
                        .is_some_and(|s| s.load(std::sync::atomic::Ordering::Relaxed));
                    if !blocked {
                        tracing::warn!(%error, "no speed limits for a route");
                    }
                    edges[r] = None;
                }
                (Ok(_), None) => {}
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
            out.push(
                spans
                    .inspect_err(|error| tracing::warn!(%error, "no speed limits for a route"))
                    .ok(),
            );
        }
        out
    }

    /// The edges of the stretch `first..=last` of `points`, traced with
    /// `body`, or a body made for the stretch. A stretch the engine refuses
    /// to walk is traced again in two halves, down to [`SPLIT_DOWN_TO`]
    /// points, and a shorter one is left without limits: Valhalla 3.9 failed
    /// `edge_walk` on the first ten points of the routes from Brest to
    /// Krakow, where the start is snapped in the middle of an edge, and
    /// walked the rest of their first piece (2026-10-07,
    /// `plan/research/53-obstacles-publics.md`). One bad place costs a
    /// refusal per level of halves; past [`MAX_REFUSALS`] refusals for the
    /// route (`refused`), the engine is refusing more than one place and
    /// the route gets no limits.
    fn trace_stretch<'a>(
        &'a self,
        engine: &'a Engine,
        points: &'a [Position],
        first: usize,
        last: usize,
        body: Option<&'a Value>,
        refused: &'a std::sync::atomic::AtomicUsize,
    ) -> std::pin::Pin<
        Box<dyn Future<Output = Result<Vec<lunaway_domain::speed::Edge>, RouteError>> + Send + 'a>,
    > {
        Box::pin(async move {
            let made;
            let body = if let Some(b) = body {
                b
            } else {
                made = limits::trace_body(&points[first..=last]);
                &made
            };
            match self.trace_piece(engine, body).await {
                // An answer without edges says nothing of the stretch:
                // the route goes without limits rather than with a silent
                // gap.
                Ok(answer) => limits::edges_of(&answer, first)
                    .ok_or(RouteError::Malformed("a trace without edges")),
                Err(RouteError::Engine(EngineError::Refused { status, code }))
                    if (400..500).contains(&status)
                        && refused.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
                            < MAX_REFUSALS =>
                {
                    if last - first <= SPLIT_DOWN_TO {
                        tracing::info!(
                            status,
                            %code,
                            points = last - first + 1,
                            "a stretch of a route left without speed limits"
                        );
                        return Ok(Vec::new());
                    }
                    let mid = first + (last - first) / 2;
                    let mut edges = self
                        .trace_stretch(engine, points, first, mid, None, refused)
                        .await?;
                    edges.extend(
                        self.trace_stretch(engine, points, mid, last, None, refused)
                            .await?,
                    );
                    Ok(edges)
                }
                Err(error) => Err(error),
            }
        })
    }

    /// One speed-limit trace. It takes no engine slot of its own: the
    /// traces of an answer run one at a time under the slot its route call
    /// took, held until they end (`route_within`), while the engine would
    /// otherwise wait for the check. A request never holds more than one
    /// slot, and never waits for a second one while holding the first.
    async fn trace_piece(&self, engine: &Engine, body: &Value) -> Result<Value, RouteError> {
        Ok(engine.trace(body).await?)
    }

    /// Computes and checks routes for `request` on graph `graph_id`, and
    /// the speed limits of the routes found for `limits`, when given.
    pub(crate) async fn route(
        &self,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
        fresh: &Freshness,
        limits: Option<lunaway_domain::speed::Vehicle>,
    ) -> Routed {
        // One deadline for everything a route does: waits for an engine
        // slot, engine calls, corridor queries, the matching.
        let deadline = tokio::time::Instant::now() + ROUTE_DEADLINE;
        let mut work = Work {
            limits,
            ..Work::default()
        };
        let result = tokio::time::timeout_at(deadline, async {
            let first = self
                .route_within(pool, graph_id, request, fresh, deadline, &mut work)
                .await;
            let first = match first {
                // The restrictions excluded ahead led the trip where no safe
                // way remained: asked again without them, it ends as it
                // would without them.
                // When the second run cannot end before the route's deadline,
                // the first answer stands.
                Ok(first @ Outcome::NoSafeRoute { .. }) if work.used_ahead => {
                    work.without_ahead = true;
                    let again =
                        self.route_within(pool, graph_id, request, fresh, deadline, &mut work);
                    match tokio::time::timeout_at(deadline - DIAGNOSIS_MARGIN, again).await {
                        Ok(r) => r,
                        Err(_) => Ok(first),
                    }
                }
                other => other,
            }?;
            let moving = stops_to_move(&first, &request.stops);
            if moving.is_empty() {
                return Ok(first);
            }
            Ok(self
                .move_stops(pool, graph_id, request, fresh, deadline, &moving, &mut work)
                .await
                .unwrap_or(first))
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

    /// The trip asked again with the stops at `moving` looked for farther
    /// around, at each of [`MOVE_RADII_M`] until one gives routes, within
    /// what is left of the route's `deadline`; none when no radius does,
    /// when time runs out or when the engine fails: the first answer then
    /// stands. Only a failure costs this: a trip with a route never gets
    /// here.
    #[allow(
        clippy::too_many_arguments,
        reason = "the route's own inputs, passed on to each attempt"
    )]
    async fn move_stops(
        &self,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
        fresh: &Freshness,
        deadline: tokio::time::Instant,
        moving: &[usize],
        work: &mut Work,
    ) -> Option<Outcome> {
        work.retrying = true;
        for radius in MOVE_RADII_M {
            let mut wider = request.clone();
            for &i in moving {
                if let Some(s) = wider.stops.get_mut(i) {
                    s.radius_m = Some(radius);
                }
            }
            tracing::info!(
                stops = moving.len(),
                radius,
                "a stop the vehicle cannot reach is looked for farther around"
            );
            let again = self.route_within(pool, graph_id, &wider, fresh, deadline, work);
            match tokio::time::timeout_at(deadline - DIAGNOSIS_MARGIN, again).await {
                Ok(Ok(Outcome::Found {
                    osrm,
                    routes,
                    recalculations,
                    avoided,
                    limits,
                    ..
                })) if within_radius(&osrm, moving, radius) => {
                    let moved = moved_stops(&osrm, moving);
                    return Some(Outcome::Found {
                        osrm,
                        routes,
                        recalculations,
                        avoided,
                        limits,
                        moved,
                    });
                }
                Ok(Ok(_)) => {}
                Ok(Err(error)) => {
                    tracing::warn!(%error, "a stop looked for farther around could not be routed");
                    return None;
                }
                Err(_) => {
                    tracing::warn!("looking for a stop farther around ran out of time");
                    return None;
                }
            }
        }
        None
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
        if !work.without_ahead {
            for centre in self.ahead(graph_id, &request.stops, &dims) {
                if centres.iter().all(|c| c.distance_m(centre) >= RING_M / 2.0) {
                    centres.push(centre);
                    exclusions.push(exclusion_ring(centre, RING_M));
                }
            }
        }
        let mut ahead = !centres.is_empty();
        work.used_ahead = ahead;
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
            // The slot is held until the answer is checked and its speed
            // limits traced: the memory of the answers in hand stays bounded
            // by the slots.
            let waited = std::time::Instant::now();
            let slot = tokio::time::timeout(self.queue_wait, self.slots.acquire())
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
                // The restrictions excluded ahead closed the last way, or
                // the road a stop lies on: the trip is asked again without
                // them, so that a trip without a route is told why by the
                // engine and the check, as it would be without them.
                Answer::NoSegment | Answer::NoRoute if attempt == 0 && ahead => {
                    ahead = false;
                    work.used_ahead = false;
                    exclusions.clear();
                    centres.clear();
                    continue;
                }
                // A stop asked again farther around: the first answer, with
                // its reasons, stands.
                Answer::NoSegment | Answer::NoRoute if attempt == 0 && work.retrying => {
                    return Ok(Outcome::NoRoute(NoRoute::Unreachable(Vec::new())));
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
                    // A stop looked for farther around may land anywhere
                    // within its radius.
                    let moved = first.iter().zip(&distances).enumerate().any(|(i, (a, b))| {
                        b - a > STOP_MOVED_M
                            && request
                                .stops
                                .get(i)
                                .and_then(|s| s.radius_m)
                                .is_none_or(|r| *b > f64::from(r))
                    });
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
            // The speed limits are traced while the routes are checked: the
            // traces of a route of 3 000 km take 0.3 to 0.5 s of the engine,
            // its check about as long (2026-10-07,
            // `plan/research/53-obstacles-publics.md`). Those of an answer
            // whose every route is blocked are dropped unfinished.
            let routes_in_answer = osrm
                .get("routes")
                .and_then(Value::as_array)
                .map_or(0, Vec::len);
            let skip: Arc<Vec<std::sync::atomic::AtomicBool>> = Arc::new(
                (0..routes_in_answer)
                    .map(|_| std::sync::atomic::AtomicBool::new(false))
                    .collect(),
            );
            let traces = work.limits.map(|vehicle| {
                let shared = Arc::clone(&osrm);
                let skip = Arc::clone(&skip);
                Box::pin(async move { self.speed_limits(&shared, vehicle, &skip).await })
            });
            let check = Box::pin(check_routes(
                pool,
                graph_id,
                &osrm,
                &dims,
                request.depart_at,
                fresh,
                work,
            ));
            let (checked, traces) = match traces {
                None => (check.await?, Traces::None),
                Some(traces) => match futures_util::future::select(check, traces).await {
                    futures_util::future::Either::Left((checked, pending)) => {
                        (checked?, Traces::Pending(pending))
                    }
                    futures_util::future::Either::Right((done, check)) => {
                        (check.await?, Traces::Done(done))
                    }
                },
            };
            let (safe, blocked): (Vec<_>, Vec<_>) = checked
                .into_iter()
                .partition(|(_, blocking, events)| blocking.is_empty() && events.is_empty());
            // The routes that will not be sent are traced no further: on a
            // long trip with alternatives, their pieces would hold the slot
            // a second more.
            for (i, flag) in skip.iter().enumerate() {
                if !safe.iter().any(|(r, _, _)| r.index == i) {
                    flag.store(true, std::sync::atomic::Ordering::Relaxed);
                }
            }
            if !safe.is_empty() {
                let waited = std::time::Instant::now();
                let traced = match traces {
                    Traces::None => Vec::new(),
                    Traces::Done(t) => t,
                    // Never past the route's deadline: the route is sent
                    // without its limits rather than lost.
                    Traces::Pending(p) => tokio::time::timeout_at(deadline - DIAGNOSIS_MARGIN, p)
                        .await
                        .unwrap_or_else(|_| {
                            tracing::warn!("the speed limits of a route ran out of time");
                            Vec::new()
                        }),
                };
                work.spent.limits += waited.elapsed();
                // The traces ran under the route's slot: it goes back now.
                drop(slot);
                // The checks and the traces are over and dropped their
                // shares: no copy.
                let osrm = Arc::try_unwrap(osrm).unwrap_or_else(|shared| (*shared).clone());
                let routes: Vec<CheckedRoute> = safe.into_iter().map(|(r, _, _)| r).collect();
                let order: Vec<usize> = routes.iter().map(|r| r.index).collect();
                let (osrm, routes) = keep_routes(osrm, routes, request.language)?;
                let limits = if traced.is_empty() {
                    Vec::new()
                } else {
                    order
                        .iter()
                        .take(routes.len())
                        .map(|&i| traced.get(i).cloned().flatten())
                        .collect()
                };
                return Ok(Outcome::Found {
                    osrm,
                    routes,
                    recalculations: attempt,
                    avoided,
                    limits,
                    moved: Vec::new(),
                });
            }
            drop(traces);
            blockers = Vec::new();
            event_blockers = Vec::new();
            for (_, b, e) in blocked {
                blockers.extend(b);
                event_blockers.extend(e);
            }
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

/// Speed-limit pieces traced at once for one request: one, under the
/// engine slot of its route call (`Routing::trace_piece`).
const TRACES_AT_ONCE: usize = 1;
/// Shape points of the shortest stretch traced again in two halves when
/// the engine refuses it: a refused piece of 10 000 points takes at most
/// ten levels of halves, two calls of a few milliseconds each.
const SPLIT_DOWN_TO: usize = 16;
/// Refusals of the engine to trace stretches of one route, after which the
/// route gets no limits: one bad place in a piece of 10 000 points costs
/// ten, and a route may start and end on one each.
const MAX_REFUSALS: usize = 24;

/// The speed limits of an answer while its routes are checked.
enum Traces<F> {
    /// None asked.
    None,
    /// Traced before the check ended.
    Done(Vec<Option<Vec<lunaway_domain::speed::Span>>>),
    /// Still running.
    Pending(F),
}

/// A route ready for its speed-limit traces.
struct Traced {
    points: Vec<Position>,
    along: Vec<f64>,
    /// Pieces or halves of pieces the engine refused to trace so far.
    refused: std::sync::atomic::AtomicUsize,
    /// Each piece's first and last shape index, and its trace request.
    bodies: Vec<(usize, usize, Value)>,
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
            .map(|(first, last)| (first, last, limits::trace_body(&points[first..=last])))
            .collect();
        Ok(Some(Traced {
            points,
            along,
            refused: std::sync::atomic::AtomicUsize::new(0),
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

/// The stops of `stops` to look for farther around after `outcome`: those
/// the vehicle may not reach or leave because of a restriction within
/// [`MOVE_WITHIN_M`] of the point asked, named by the diagnosis of a trip
/// without a route, or among the blockers of a trip without a safe one
/// (the narrow street a centre's point was snapped to). Never the
/// vehicle's own position: a driver is where they are.
fn stops_to_move(outcome: &Outcome, stops: &[Stop]) -> Vec<usize> {
    let near = |i: usize, m: &Met| {
        stops.get(i).is_some_and(|s| {
            s.movable() && distance_to(s.at, &m.restriction.geometry) <= MOVE_WITHIN_M
        })
    };
    let mut out: Vec<usize> = match outcome {
        Outcome::NoRoute(NoRoute::Unreachable(reasons)) => reasons
            .iter()
            .filter_map(|r| match r.place {
                Place::Stop(i)
                    if r.limits
                        .iter()
                        .filter_map(|l| l.blocker.as_ref())
                        .any(|m| near(i, m)) =>
                {
                    Some(i)
                }
                _ => None,
            })
            .collect(),
        Outcome::NoSafeRoute { blockers, .. } => (0..stops.len())
            .filter(|&i| blockers.iter().any(|m| near(i, m)))
            .collect(),
        _ => Vec::new(),
    };
    out.sort_unstable();
    out.dedup();
    out
}

/// How far from the point asked a stop looked for farther around must have
/// landed to be told as moved, metres: snapping a point to the road beside
/// it moves it a few metres anyway.
const TOLD_MOVED_M: f64 = 25.0;

/// Where the engine started or ended the trip for each stop of `moving`
/// that moved more than [`TOLD_MOVED_M`], from the OSRM answer's
/// `waypoints`.
fn moved_stops(osrm: &Value, moving: &[usize]) -> Vec<MovedStop> {
    let waypoints = osrm
        .get("waypoints")
        .and_then(Value::as_array)
        .map_or(&[][..], Vec::as_slice);
    moving
        .iter()
        .filter_map(|&index| {
            let w = waypoints.get(index)?;
            let location = w.get("location")?.as_array()?;
            let lon = location.first()?.as_f64()?;
            let lat = location.get(1)?.as_f64()?;
            let distance_m = w.get("distance").and_then(Value::as_f64)?;
            (distance_m > TOLD_MOVED_M).then_some(MovedStop {
                index,
                at: Position::new(lat, lon).ok()?,
                distance_m,
            })
        })
        .collect()
}

/// Whether every stop of `moving` landed within its `radius_m` in the OSRM
/// answer: the engine takes the nearest road beyond the radius when none
/// lies within, and a route from there is not the trip asked for.
fn within_radius(osrm: &Value, moving: &[usize], radius_m: u32) -> bool {
    let waypoints = osrm
        .get("waypoints")
        .and_then(Value::as_array)
        .map_or(&[][..], Vec::as_slice);
    moving.iter().all(|&i| {
        waypoints
            .get(i)
            .and_then(|w| w.get("distance"))
            .and_then(Value::as_f64)
            .is_some_and(|d| d <= f64::from(radius_m))
    })
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
    /// The vehicle whose speed limits the routes found carry, when asked.
    limits: Option<lunaway_domain::speed::Vehicle>,
    /// Whether restrictions excluded ahead went into the first call.
    used_ahead: bool,
    /// Whether to leave them out.
    without_ahead: bool,
    /// Whether stops are being looked for farther around: a trip still
    /// without a route keeps the reasons of the first answer.
    retrying: bool,
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
///
/// A limit the vehicle exceeds that spares local access ("sauf desserte")
/// warns where the route uses it to reach or leave a stop, and blocks where
/// it crosses it: the route may drive the runs of such limits of one kind
/// that reach a stop ([`local_access_runs`], stricter than the engine,
/// which lets a trip ending in one zone cross another on the way). A limit
/// met twice blocks at the place it is through traffic.
pub(crate) fn match_restrictions(
    line: &RouteLine,
    near: Vec<db::NearRestriction>,
    dims: &RoutingDimensions,
) -> (Vec<Met>, Vec<Met>) {
    let mut warnings = Vec::new();
    let mut blocking = Vec::new();
    // Decided once every such limit of the route is known: a run of them
    // reaches a stop or not as a whole.
    let mut sparing: Vec<(Met, Vec<Hit>)> = Vec::new();
    for r in near {
        let hits = match_restriction(line, &r.geometry, r.restriction.source);
        let Some(hit) = hits.first().copied() else {
            continue;
        };
        let Some(finding) = assess(&r.restriction, dims) else {
            continue;
        };
        let spares = r.restriction.except_destination
            && r.restriction.kind.spares_local_access()
            && finding.severity == Severity::Blocking;
        let met = Met {
            finding,
            restriction: r,
            hit,
        };
        if spares {
            sparing.push((met, hits));
            continue;
        }
        match finding.severity {
            Severity::Warning => warnings.push(met),
            _ => blocking.push(met),
        }
    }
    // One kind at a time: the engine's right to local access is per kind of
    // limit.
    sparing.sort_by_key(|(m, _)| m.restriction.restriction.kind);
    let mut sparing = sparing.into_iter().peekable();
    while let Some(first) = sparing.next() {
        let kind = first.0.restriction.restriction.kind;
        let mut group = vec![first];
        while let Some(next) = sparing.next_if(|(m, _)| m.restriction.restriction.kind == kind) {
            group.push(next);
        }
        let spans: Vec<(f64, f64)> = group
            .iter()
            .flat_map(|(_, hits)| hits.iter().map(|h| (h.start_m, h.end_m)))
            .collect();
        let runs = local_access_runs(line.stops(), &spans);
        let inside = |h: &Hit| runs.iter().any(|(a, b)| h.start_m >= *a && h.end_m <= *b);
        for (mut met, hits) in group {
            match hits.iter().find(|h| !inside(h)) {
                Some(through) => {
                    met.hit = *through;
                    blocking.push(met);
                }
                None => {
                    met.finding.severity = Severity::Warning;
                    warnings.push(met);
                }
            }
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
    fn a_sauf_desserte_street_met_twice_blocks_where_it_is_crossed() {
        use lunaway_domain::routing::{
            Certainty, Restriction, RestrictionFeature, RestrictionKind, RestrictionSource,
        };
        // A point `north` and `east` metres from (45, 1).
        let at = |north: f64, east: f64| {
            Position::new(
                45.0 + north / 111_195.0,
                1.0 + east / (111_195.0 * 45.0_f64.to_radians().cos()),
            )
            .unwrap()
        };
        // A long "sauf desserte" street runs 1 km north. The trip starts
        // 50 m into it and leaves it at 150 m, comes back to it 2 km later
        // at 800 m, follows it to 900 m and ends far east of it: local
        // access at the start, through traffic later.
        let points = vec![
            at(50.0, 0.0),
            at(150.0, 0.0),
            at(150.0, 500.0),
            at(800.0, 500.0),
            at(800.0, 0.0),
            at(900.0, 0.0),
            at(900.0, 500.0),
            at(1_500.0, 500.0),
        ];
        let line = RouteLine::new(points).unwrap();
        let street = db::NearRestriction {
            id: uuid::Uuid::nil(),
            restriction: Restriction {
                kind: RestrictionKind::MaxWeight,
                limit: Some(3.5),
                source: RestrictionSource::Osm,
                certainty: Certainty::Known,
                feature: RestrictionFeature::Road,
                except_destination: true,
            },
            external_id: "way/1".to_owned(),
            name: None,
            geometry: vec![at(0.0, 0.0), at(1_000.0, 0.0)],
        };
        let dims = RoutingDimensions {
            height_m: 3.0,
            width_m: 2.3,
            length_m: 7.0,
            weight_t: 4.5,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: None,
        };
        let (warnings, blocking) = match_restrictions(&line, vec![street], &dims);
        assert!(warnings.is_empty(), "{warnings:?}");
        assert_eq!(blocking.len(), 1);
        // 100 m along it, 500 east, 650 north, 500 west: 1 750 m.
        let s = blocking[0].hit.start_m;
        assert!(
            (1_700.0..1_800.0).contains(&s),
            "the block sits where the street is driven through, not at the start: {s}"
        );
    }

    /// A height limit of 1.9 m drawn as `geometry`, blocking a 3.2 m
    /// motorhome.
    fn bar(geometry: Vec<Position>) -> Met {
        use lunaway_domain::routing::{
            Certainty, FindingKind, Restriction, RestrictionFeature, RestrictionKind,
            RestrictionSource,
        };
        let at = geometry[0];
        Met {
            finding: Finding {
                kind: FindingKind::LowClearance,
                severity: Severity::Blocking,
                limit: Some(1.9),
                vehicle_value: Some(3.2),
            },
            restriction: db::NearRestriction {
                id: uuid::Uuid::nil(),
                restriction: Restriction {
                    kind: RestrictionKind::MaxHeight,
                    limit: Some(1.9),
                    source: RestrictionSource::Osm,
                    certainty: Certainty::Known,
                    feature: RestrictionFeature::Underpass,
                    except_destination: false,
                },
                external_id: "way/130049566".to_owned(),
                name: None,
                geometry,
            },
            hit: Hit {
                start_m: 0.0,
                end_m: 10.0,
                geometry_index: 0,
                at,
                middle: at,
            },
        }
    }

    #[test]
    fn a_stop_kept_from_the_vehicle_by_a_limit_beside_it_is_looked_for_farther() {
        use diagnose::Limit;
        use valhalla::Constraint;
        let p = |lat: f64, lon: f64| Position::new(lat, lon).unwrap();
        // Lyon to Marseille Saint-Charles: the diagnosis names the
        // destination and the covered aisle 48 m from the point asked
        // (production, 2026-10-07).
        let lyon = Stop::at(p(45.7640, 4.8357));
        let st_charles = Stop::at(p(43.3027, 5.3806));
        // Way 130049566, its first and last points and the one nearest the
        // point asked.
        let aisle = vec![
            p(43.302157, 5.382261),
            p(43.302259, 5.380754),
            p(43.302062, 5.380738),
        ];
        let unreachable = |geometry: Vec<Position>| {
            Outcome::NoRoute(NoRoute::Unreachable(vec![Unreachable {
                place: Place::Stop(1),
                limits: vec![Limit {
                    constraint: Constraint::Height,
                    vehicle_value: Some(3.2),
                    blocker: Some(bar(geometry)),
                }],
            }]))
        };
        let near = distance_to(st_charles.at, &aisle);
        assert!(near < MOVE_WITHIN_M, "{near}");
        assert_eq!(
            stops_to_move(&unreachable(aisle.clone()), &[lyon, st_charles]),
            [1]
        );
        // A limit 500 m away closes a district: moving the stop would not
        // reach it.
        let far = vec![p(43.3072, 5.3806), p(43.3075, 5.3806)];
        assert!(stops_to_move(&unreachable(far), &[lyon, st_charles]).is_empty());
        // Montpellier: the route found is blocked by the 1.5 m bollards of
        // node 12292104452, 171 m from the start: the start alone is looked
        // for farther.
        let comedie = Stop::at(p(43.6086, 3.8797));
        let hub = Stop::at(p(43.63413, 3.97046));
        let node = p(43.610082, 3.879151);
        let bollards = Outcome::NoSafeRoute {
            blockers: vec![bar(vec![node])],
            event_blockers: Vec::new(),
            recalculations: 1,
        };
        let d = distance_to(comedie.at, &[node]);
        assert!((150.0..MOVE_WITHIN_M).contains(&d), "{d}");
        assert_eq!(stops_to_move(&bollards, &[comedie, hub]), [0]);
        // The vehicle's own position during guidance is never moved, with
        // or without a course.
        let driving = Stop {
            vehicle: true,
            ..comedie
        };
        let heading = Stop {
            heading: Some(90),
            ..comedie
        };
        assert!(stops_to_move(&bollards, &[driving, hub]).is_empty());
        assert!(stops_to_move(&bollards, &[heading, hub]).is_empty());
    }

    #[test]
    fn a_moved_stop_is_read_from_the_engine_s_waypoints() {
        let osrm = serde_json::json!({"waypoints": [
            {"location": [3.88067, 43.608_739], "distance": 80.4},
            {"location": [3.97046, 43.63413], "distance": 0.2},
        ]});
        let moved = moved_stops(&osrm, &[0, 1]);
        assert_eq!(
            moved.len(),
            1,
            "a stop snapped beside its point is not told: {moved:?}"
        );
        assert_eq!(moved[0].index, 0);
        assert!((moved[0].at.lat() - 43.608_739).abs() < 1e-9);
        assert!((moved[0].at.lon() - 3.88067).abs() < 1e-9);
        assert!((moved[0].distance_m - 80.4).abs() < 1e-9);
        assert!(within_radius(&osrm, &[0], 100));
        assert!(
            !within_radius(&osrm, &[0], 50),
            "the engine went beyond the radius: not the trip asked for"
        );
    }

    #[test]
    fn the_radii_tried_stay_within_the_engine_s_limit() {
        let config: Value =
            serde_json::from_str(include_str!("../../../../../infra/routing/valhalla.json"))
                .unwrap();
        let max = config["service_limits"]["max_radius"].as_u64().unwrap();
        assert!(
            MOVE_RADII_M.iter().all(|r| u64::from(*r) <= max),
            "the engine clamps a radius above {max} m"
        );
        assert!(
            MOVE_RADII_M.windows(2).all(|w| w[0] < w[1]),
            "the nearest first"
        );
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
