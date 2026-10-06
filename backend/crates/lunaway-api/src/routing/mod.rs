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

pub(crate) mod valhalla;

use std::time::Duration;

use lunaway_db::{PgPool, routing as db};
use lunaway_domain::{
    Position,
    routing::{
        Finding, Hit, RouteLine, RoutingDimensions, Severity, VehicleProfile, assess,
        exclusion_ring, match_route, polyline,
    },
};
use serde_json::Value;
use tokio::sync::Semaphore;

use self::valhalla::{Answer, Avoid, Engine, EngineError, Stop};
use crate::config::RoutingConfig;

/// Engine calls for one route at most: the first, and two more with the
/// blockers excluded.
pub(crate) const MAX_ATTEMPTS: usize = 3;
/// Longest a route may take, everything together (waits for an engine slot,
/// engine calls, corridor queries, matching): under the API's request
/// timeout (20 s by default), so a slow engine ends in `UNAVAILABLE` and a
/// refunded quota rather than a cut connection.
const ROUTE_DEADLINE: Duration = Duration::from_secs(15);
/// Most exclusion rings sent at once.
const MAX_EXCLUSIONS: usize = 100;
/// Radius of the ring around a blocker, metres: enough to catch the road
/// the route used, small enough to spare a road crossing a few metres away.
const RING_M: f64 = 5.0;
/// A blocker this close to the centre of a ring already sent is inside it
/// (an OpenStreetMap way and the IGN section of the same bridge): no second
/// ring. A blocker farther away gets its own, even on the next road.
const SAME_PLACE_M: f64 = RING_M / 2.0;
/// How far from a route the database looks for restrictions, metres: the
/// widest tolerance of a source (`RestrictionSource::tolerance_m`).
const CORRIDOR_M: f64 = 15.0;
/// Largest OSRM answer passed to the app: alternatives are dropped, last
/// first, until the routes fit, so the GraphQL answer stays under the API's
/// response limit (8 MB by default).
pub(crate) const MAX_OSRM_BYTES: usize = 6 * 1024 * 1024;

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
    /// The restrictions the vehicle passes with little margin, or whose
    /// figure is unknown, in driving order.
    pub(crate) warnings: Vec<Met>,
}

/// Why no route came back.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum NoRoute {
    /// The engine found no road between the points.
    Unreachable,
    /// A point is too far from any road.
    OffNetwork,
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
    },
    /// No route at all.
    NoRoute(NoRoute),
    /// Routes exist, but each one meets a limit the vehicle exceeds.
    NoSafeRoute {
        /// The limits that stopped the last attempt.
        blockers: Vec<Met>,
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

/// The engine and its share of the server.
pub(crate) struct Routing {
    engine: Option<Engine>,
    /// Engine calls in flight, all clients together.
    slots: Semaphore,
    queue_wait: Duration,
    /// The last answer of the engine's status, and when it was read.
    status: std::sync::Mutex<Option<(std::time::Instant, bool)>>,
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
            queue_wait: config.queue_wait,
            status: std::sync::Mutex::new(None),
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

    /// Computes and checks routes for `request` on graph `graph_id`.
    pub(crate) async fn route(
        &self,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
    ) -> Result<Outcome, RouteError> {
        // One deadline for everything a route does: waits for an engine
        // slot, engine calls, corridor queries, the matching.
        tokio::time::timeout(ROUTE_DEADLINE, self.route_within(pool, graph_id, request))
            .await
            .map_err(|_| RouteError::Deadline)?
    }

    async fn route_within(
        &self,
        pool: &PgPool,
        graph_id: &str,
        request: &RouteRequest,
    ) -> Result<Outcome, RouteError> {
        let engine = self.engine.as_ref().ok_or(RouteError::NotSetUp)?;
        let dims = request.vehicle.routing();
        let costing = valhalla::costing_options(&dims, request.avoid);
        let mut exclusions: Vec<Vec<Position>> = Vec::new();
        let mut centres: Vec<Position> = Vec::new();
        let mut blockers: Vec<Met> = Vec::new();
        let mut snapped: Option<Vec<f64>> = None;
        let mut calls = 0;
        for attempt in 0..MAX_ATTEMPTS {
            calls = attempt + 1;
            let body = valhalla::route_body(
                &request.stops,
                &costing,
                request.language,
                request.alternatives,
                &exclusions,
            );
            // The slot is held until the answer is checked and trimmed: the
            // memory of the answers in hand stays bounded by the slots.
            let _slot = tokio::time::timeout(self.queue_wait, self.slots.acquire())
                .await
                .map_err(|_| RouteError::Busy)?
                .map_err(|_| RouteError::Busy)?;
            let osrm = match engine.route(&body).await? {
                Answer::Routes(v) => v,
                Answer::NoSegment if attempt == 0 => {
                    return Ok(Outcome::NoRoute(NoRoute::OffNetwork));
                }
                Answer::NoRoute if attempt == 0 => {
                    return Ok(Outcome::NoRoute(NoRoute::Unreachable));
                }
                // The exclusions closed the last way through, or the road a
                // stop lies on: the blockers of the previous attempt are why.
                Answer::NoRoute | Answer::NoSegment => {
                    return Ok(Outcome::NoSafeRoute {
                        blockers: distinct(blockers),
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
                            recalculations: attempt,
                        });
                    }
                }
            }
            let checked = check_routes(pool, graph_id, &osrm, &dims).await?;
            let (safe, blocked): (Vec<_>, Vec<_>) = checked
                .into_iter()
                .partition(|(_, blocking)| blocking.is_empty());
            if !safe.is_empty() {
                let routes = safe.into_iter().map(|(r, _)| r).collect();
                let (osrm, routes) = keep_routes(osrm, routes, request.language)?;
                return Ok(Outcome::Found {
                    osrm,
                    routes,
                    recalculations: attempt,
                });
            }
            blockers = blocked.into_iter().flat_map(|(_, b)| b).collect();
            let before = exclusions.len();
            for b in &blockers {
                let centre = b.hit.middle;
                if exclusions.len() >= MAX_EXCLUSIONS
                    || centres.iter().any(|c| c.distance_m(centre) < SAME_PLACE_M)
                {
                    continue;
                }
                centres.push(centre);
                exclusions.push(exclusion_ring(centre, RING_M));
            }
            if exclusions.len() == before {
                // Nothing new to exclude: the engine keeps going through.
                break;
            }
            tracing::info!(
                attempt,
                blockers = blockers.len(),
                exclusions = exclusions.len(),
                "route recalculated around limits the vehicle exceeds"
            );
        }
        Ok(Outcome::NoSafeRoute {
            blockers: distinct(blockers),
            recalculations: calls.saturating_sub(1),
        })
    }
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

/// Each route of `osrm`, with its warnings and its blockers.
async fn check_routes(
    pool: &PgPool,
    graph_id: &str,
    osrm: &Value,
    dims: &RoutingDimensions,
) -> Result<Vec<(CheckedRoute, Vec<Met>)>, RouteError> {
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
        let near = db::restrictions_near(pool, graph_id, &points, CORRIDOR_M).await?;
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
        // Indexing a long shape and matching hundreds of restrictions takes
        // milliseconds to tens of milliseconds of CPU: off the async threads.
        let (warnings, blocking) =
            tokio::task::spawn_blocking(move || match_restrictions(points, &legs, near, &dims))
                .await
                .map_err(RouteError::Blocking)??;
        let (has_toll, has_ferry, has_motorway) = classes(route);
        out.push((
            CheckedRoute {
                index,
                distance_m: route.get("distance").and_then(Value::as_f64).unwrap_or(0.0),
                duration_s: route.get("duration").and_then(Value::as_f64).unwrap_or(0.0),
                has_toll,
                has_ferry,
                has_motorway,
                warnings,
            },
            blocking,
        ));
    }
    Ok(out)
}

/// The restrictions `near` a route that it drives through, weighed against
/// the vehicle: (warnings, blockers), each in driving order. Fails closed: a
/// severity this code does not know blocks.
fn match_restrictions(
    points: Vec<Position>,
    legs: &[f64],
    near: Vec<db::NearRestriction>,
    dims: &RoutingDimensions,
) -> Result<(Vec<Met>, Vec<Met>), RouteError> {
    let line = RouteLine::new(points)
        .ok_or(RouteError::Malformed("a route of one point"))?
        .with_legs(legs);
    let mut warnings = Vec::new();
    let mut blocking = Vec::new();
    for r in near {
        let hits = match_route(&line, &r.geometry, r.restriction.source.tolerance_m());
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
    Ok((warnings, blocking))
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
    let all = osrm
        .get_mut("routes")
        .and_then(Value::as_array_mut)
        .map(std::mem::take)
        .unwrap_or_default();
    let mut kept: Vec<Value> = routes
        .iter()
        .filter_map(|r| all.get(r.index).cloned())
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
