//! Places the lines of road events on the routing graph, through the
//! routing engine on the backend's loopback.
//!
//! A DIR section is two points up to 62 km apart (median 2 km,
//! `plan/research/20-travaux-temps-reel.md`, part 6), farther than the
//! `breakage_distance` of the engine's map matching (2 000 m in
//! `infra/routing/valhalla.json`, `meili.default`), so the engine is asked
//! for a route instead: from the section's start to its
//! end, leaving in the direction of the section so that a dual carriageway
//! is matched on the carriageway the section describes, and once the other
//! way for a section that concerns both directions. The route is kept when
//! it holds together: both ends on the road, a length close to the
//! section's, and most of it on the section's road number. A street drawn
//! as a line (DiaLog, the cities) is followed through points every 150 m
//! and kept when the route stays on it.
//!
//! The kept lines are in driving order: the route check counts them only
//! for a route driving the same way (`match_route_directed`).

use std::time::{Duration, Instant};

use chrono::Utc;
use lunaway_db::{PgPool, road_events as db, routing::active_graph};
use lunaway_domain::{
    Position,
    road_events::{EventDirection, road},
    routing::{RouteLine, heading, polyline},
};
use serde_json::{Value, json};

use crate::IngestError;

/// Largest answer read from the engine: a route of a few kilometres.
const MAX_ANSWER_BYTES: usize = 4 * 1024 * 1024;
/// How far a section's end may be from the road it is snapped to, metres:
/// 99 of 100 DIR points lie within 5 m of a road (research, part 6).
const MAX_SNAP_M: f64 = 60.0;
/// Heading tolerance at a section's start, degrees: wide enough for a bend
/// at the start, narrow enough to refuse the opposite carriageway.
const HEADING_TOLERANCE_DEG: u32 = 75;
/// Spacing of the through points along a drawn street, metres.
const THROUGH_EVERY_M: f64 = 150.0;
/// Most locations of one request: the `auto` limit the engine is served
/// with (`service_limits.auto.max_locations` in
/// `infra/routing/valhalla.json`), which also bounds the API's stops.
const MAX_LOCATIONS: usize = 7;
/// Share of a two-point section's route on its road number.
const ROAD_SHARE: f64 = 0.6;
/// How far a drawn street's route may stray from the street, metres.
const STRAY_M: f64 = 20.0;
/// Share of a drawn street's route that must lie within [`STRAY_M`].
const STAY_SHARE: f64 = 0.9;
/// Refusals in a row after which the pass stops: one refused line is that
/// line's matter, a run of them more likely the engine's.
const REFUSALS_IN_A_ROW: u32 = 5;

/// Why the engine could not be asked.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum MatchError {
    /// The engine's URL is not a loopback HTTP URL.
    #[error("the routing engine must be on loopback, got {0}")]
    NotLoopback(String),
    /// The client could not be built.
    #[error("cannot build the routing engine client")]
    Client(#[source] reqwest::Error),
    /// No answer, or a broken one.
    #[error("the routing engine did not answer")]
    Unreachable(#[source] reqwest::Error),
    /// The answer is larger than any short route.
    #[error("the routing engine's answer is too large")]
    TooLarge,
    /// The answer is not JSON.
    #[error("the routing engine's answer is not JSON")]
    NotJson(#[source] serde_json::Error),
    /// The engine answered with an error it should not give.
    #[error("the routing engine refused: {0}")]
    Refused(String),
}

impl MatchError {
    /// Whether the engine answered and refused this request (a bad
    /// request, an error of its own on these points), rather than not
    /// answering at all: a refusal concerns one event, the others are
    /// asked; a silent engine stops the pass.
    #[must_use]
    pub const fn is_refusal(&self) -> bool {
        matches!(self, Self::Refused(_) | Self::TooLarge)
    }
}

/// The reason in an engine's error answer (`{"error_code": 154, "error":
/// "Insufficient number of locations provided", "status_code": 400}`),
/// short enough to store.
fn refusal(status: reqwest::StatusCode, value: &Value) -> String {
    let code = value
        .get("error_code")
        .and_then(Value::as_i64)
        .map(|c| format!(" error {c}"))
        .unwrap_or_default();
    let text = value
        .get("error")
        .and_then(Value::as_str)
        .or_else(|| value.get("code").and_then(Value::as_str))
        .unwrap_or("no reason given");
    format!("HTTP {}{code}: {text}", status.as_u16())
        .chars()
        .take(300)
        .collect()
}

/// The routing engine as the matcher uses it; a fake in tests.
pub trait Engine {
    /// `POST /route` with `body`: the OSRM answer, or `None` when the
    /// engine finds no route or no road near a point.
    fn route(
        &self,
        body: &Value,
    ) -> impl std::future::Future<Output = Result<Option<Value>, MatchError>> + Send;
}

/// Whether `url` is plain HTTP on loopback: the engine receives positions
/// and must not be reached across a network.
#[must_use]
pub fn is_loopback(url: &str) -> bool {
    let Ok(u) = reqwest::Url::parse(url) else {
        return false;
    };
    u.scheme() == "http"
        && u.username().is_empty()
        && u.password().is_none()
        && u.host_str().is_some_and(|h| {
            h == "localhost"
                || h.trim_start_matches('[')
                    .trim_end_matches(']')
                    .parse::<std::net::IpAddr>()
                    .is_ok_and(|ip| ip.is_loopback())
        })
}

/// The engine at a loopback URL.
#[derive(Debug, Clone)]
pub struct Valhalla {
    http: reqwest::Client,
    base: String,
}

impl Valhalla {
    /// A client of `base` (`http://127.0.0.1:8002`): no proxy, no
    /// redirect, `timeout` per call.
    ///
    /// # Errors
    ///
    /// [`MatchError`] when `base` is not on loopback or the client cannot
    /// be built.
    pub fn new(base: &str, timeout: Duration) -> Result<Self, MatchError> {
        if !is_loopback(base) {
            return Err(MatchError::NotLoopback(base.to_owned()));
        }
        crate::http::install_crypto_provider();
        let http = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(2))
            .timeout(timeout)
            .build()
            .map_err(MatchError::Client)?;
        Ok(Self {
            http,
            base: base.trim_end_matches('/').to_owned(),
        })
    }
}

impl Engine for Valhalla {
    async fn route(&self, body: &Value) -> Result<Option<Value>, MatchError> {
        let mut response = self
            .http
            .post(format!("{}/route", self.base))
            .json(body)
            .send()
            .await
            .map_err(MatchError::Unreachable)?;
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(MatchError::Unreachable)? {
            bytes.extend_from_slice(&chunk);
            if bytes.len() > MAX_ANSWER_BYTES {
                return Err(MatchError::TooLarge);
            }
        }
        let status = response.status();
        let value: Value = serde_json::from_slice(&bytes).map_err(MatchError::NotJson)?;
        match value.get("code").and_then(Value::as_str) {
            Some("Ok") => Ok(Some(value)),
            Some("NoRoute" | "NoSegment") => Ok(None),
            _ => Err(MatchError::Refused(refusal(status, &value))),
        }
    }
}

/// Length of a line, metres.
fn length_m(line: &[Position]) -> f64 {
    line.windows(2).map(|w| w[0].distance_m(w[1])).sum()
}

/// The points of `line` every `every_m` metres, its ends included, at most
/// `max` of them.
fn sample(line: &[Position], every_m: f64, max: usize) -> Vec<Position> {
    let total = length_m(line);
    let step = every_m.max(total / (max.saturating_sub(1).max(1)) as f64);
    let mut out = vec![line[0]];
    let mut next = step;
    let mut along = 0.0;
    for w in line.windows(2) {
        let d = w[0].distance_m(w[1]);
        while next < along + d && out.len() + 1 < max {
            let t = (next - along) / d;
            if let Ok(p) = Position::new(
                w[0].lat() + (w[1].lat() - w[0].lat()) * t,
                w[0].lon() + (w[1].lon() - w[0].lon()) * t,
            ) {
                out.push(p);
            }
            next += step;
        }
        along += d;
    }
    if let Some(last) = line.last()
        && out.last() != Some(last)
    {
        out.push(*last);
    }
    out
}

/// The points a request goes through for `line`: its ends, and points
/// every [`THROUGH_EVERY_M`] along a drawn street, two in a row never
/// closer than a metre (the engine refuses a request with fewer than two
/// locations, and a through point on top of another). `None` for a line
/// that comes back on itself within a metre: there is nothing to follow.
fn locations(line: &[Position]) -> Option<Vec<Position>> {
    let sampled = if line.len() == 2 {
        line.to_vec()
    } else {
        sample(line, THROUGH_EVERY_M, MAX_LOCATIONS)
    };
    let mut points: Vec<Position> = Vec::with_capacity(sampled.len());
    for p in sampled {
        if points.last().is_none_or(|q| q.distance_m(p) >= 1.0) {
            points.push(p);
        }
    }
    (points.len() >= 2).then_some(points)
}

/// The request that follows `line` in its order, through [`locations`];
/// `None` when there is nothing to follow.
fn request(line: &[Position]) -> Option<Value> {
    let points = locations(line)?;
    let start_heading = heading(line[0], line[1]).rem_euclid(360.0);
    let last = points.len() - 1;
    let stops: Vec<Value> = points
        .iter()
        .enumerate()
        .map(|(i, p)| {
            let mut l = json!({
                "lat": p.lat(),
                "lon": p.lon(),
                "type": if i == 0 || i == last { "break" } else { "through" },
                "search_cutoff": 200,
            });
            if i == 0 {
                #[allow(
                    clippy::cast_possible_truncation,
                    clippy::cast_sign_loss,
                    reason = "a heading between 0 and 360 degrees"
                )]
                let h = start_heading.round() as u32 % 360;
                l["heading"] = h.into();
                l["heading_tolerance"] = HEADING_TOLERANCE_DEG.into();
            }
            l
        })
        .collect();
    Some(json!({
        "locations": stops,
        "costing": "auto",
        "format": "osrm",
        "shape_format": "polyline6",
        "language": "en-US",
    }))
}

/// The route of an answer, if it holds together as the place of `line`
/// (on road `road`, canonical, when known).
fn accept(answer: &Value, line: &[Position], road: Option<&str>) -> Option<Vec<Position>> {
    let snapped_far = answer
        .get("waypoints")
        .and_then(Value::as_array)
        .is_some_and(|w| {
            w.iter()
                .any(|p| p.get("distance").and_then(Value::as_f64).unwrap_or(0.0) > MAX_SNAP_M)
        });
    if snapped_far {
        return None;
    }
    let route = answer.get("routes")?.get(0)?;
    let points = polyline::decode(route.get("geometry")?.as_str()?).ok()?;
    if points.len() < 2 {
        return None;
    }
    let expected = length_m(line);
    let got = route
        .get("distance")
        .and_then(Value::as_f64)
        .unwrap_or_else(|| length_m(&points));
    if line.len() == 2 {
        // Two points: the road may bend, but not double back.
        if got > 2.0 * expected + 300.0 {
            return None;
        }
        if let Some(road) = road {
            let mut on = 0.0;
            let mut all = 0.0;
            for step in route
                .get("legs")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(|l| l.get("steps").and_then(Value::as_array))
                .flatten()
            {
                let d = step.get("distance").and_then(Value::as_f64).unwrap_or(0.0);
                all += d;
                let refs = step
                    .get("ref")
                    .and_then(Value::as_str)
                    .map(road::numbers)
                    .unwrap_or_default();
                if refs.iter().any(|r| r == road) {
                    on += d;
                }
            }
            if all <= 0.0 || on / all < ROAD_SHARE {
                return None;
            }
        }
    } else {
        // A drawn street: the route keeps to it.
        if got > 1.3 * expected + 100.0 {
            return None;
        }
        let street = RouteLine::new(line.to_vec())?;
        let near = points
            .iter()
            .filter(|p| street.project(**p, STRAY_M).is_some())
            .count();
        #[allow(
            clippy::cast_precision_loss,
            reason = "counts of a few thousand points"
        )]
        let share = near as f64 / points.len() as f64;
        if share < STAY_SHARE {
            return None;
        }
    }
    Some(points)
}

/// The lines of the graph an event's `lines` cover, in driving order: each
/// line in its own order when the event concerns that direction only
/// (`Forward`), in both orders otherwise, a direction the engine cannot
/// drive (a one-way street backwards) left out. `None` when nothing
/// matches.
///
/// # Errors
///
/// [`MatchError`] when the engine fails.
pub async fn match_lines(
    engine: &impl Engine,
    lines: &[Vec<Position>],
    direction: EventDirection,
    road: Option<&str>,
) -> Result<Option<Vec<Vec<Position>>>, MatchError> {
    let road = road.and_then(road::normalize);
    let mut out = Vec::new();
    for line in lines.iter().filter(|l| l.len() >= 2 && length_m(l) >= 1.0) {
        let mut ways = vec![line.clone()];
        if direction != EventDirection::Forward {
            ways.push(line.iter().rev().copied().collect());
        }
        for way in ways {
            let Some(body) = request(&way) else {
                continue;
            };
            if let Some(answer) = engine.route(&body).await?
                && let Some(points) = accept(&answer, &way, road.as_deref())
            {
                out.push(points);
            }
        }
    }
    Ok((!out.is_empty()).then_some(out))
}

/// What a matching pass did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct MatchReport {
    /// Events placed on the graph.
    pub matched: u64,
    /// Events that could not be placed.
    pub unmatched: u64,
    /// Events whose lines the engine refused: left unplaced, asked again
    /// later ([`db::retry_after_refusal`]).
    pub refused: u64,
    /// Events that changed while the engine placed them: matched again at
    /// the next pass.
    pub stale: u64,
    /// Whether the pass stopped on its time budget or task count.
    pub more: bool,
}

/// Places at most `max_tasks` waiting events on the active graph, within
/// `budget`. Nothing without an active graph.
///
/// # Errors
///
/// [`IngestError::Db`] when the database fails. An event whose lines the
/// engine refuses is left unplaced with the engine's reason and the pass
/// goes on (`db::set_refused`); an engine that does not answer, or refuses
/// [`REFUSALS_IN_A_ROW`] events in a row, ends the pass with what was done
/// (the events wait for the next one).
pub async fn match_pending(
    pool: &PgPool,
    engine: &impl Engine,
    max_tasks: i64,
    budget: Duration,
) -> Result<MatchReport, IngestError> {
    let mut report = MatchReport::default();
    let Some(graph) = active_graph(pool).await? else {
        tracing::info!("no active routing graph: road events wait to be matched");
        return Ok(report);
    };
    let started = Instant::now();
    let tasks = db::match_tasks(pool, &graph.id, max_tasks).await?;
    report.more = i64::try_from(tasks.len()).unwrap_or(i64::MAX) >= max_tasks;
    let mut in_a_row = 0;
    for task in tasks {
        if started.elapsed() > budget {
            report.more = true;
            break;
        }
        let lines = match match_lines(
            engine,
            &task.lines,
            task.direction,
            task.road_number.as_deref(),
        )
        .await
        {
            Ok(l) => l,
            Err(error) if error.is_refusal() => {
                tracing::warn!(
                    source = %task.source,
                    %error,
                    "the routing engine refused a road event's lines; left unplaced"
                );
                let mut w = db::begin_writer(pool).await?;
                let stored =
                    db::set_refused(&mut w, &task, &error.to_string(), &graph.id, Utc::now())
                        .await?;
                w.commit().await?;
                if stored {
                    report.refused += 1;
                } else {
                    report.stale += 1;
                }
                in_a_row += 1;
                if in_a_row >= REFUSALS_IN_A_ROW {
                    tracing::warn!(
                        in_a_row,
                        "the routing engine refused every event in a row; matching stops for this pass"
                    );
                    report.more = true;
                    break;
                }
                continue;
            }
            Err(error) => {
                tracing::warn!(%error, "the routing engine failed; matching stops for this pass");
                report.more = true;
                break;
            }
        };
        in_a_row = 0;
        let mut w = db::begin_writer(pool).await?;
        let stored = db::set_match(&mut w, &task, lines.as_deref(), &graph.id).await?;
        w.commit().await?;
        if !stored {
            report.stale += 1;
        } else if lines.is_some() {
            report.matched += 1;
        } else {
            report.unmatched += 1;
            tracing::debug!(source = %task.source, "a road event could not be placed on the graph");
        }
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    #[test]
    fn a_line_that_comes_back_on_itself_asks_nothing() {
        let a = p(45.0, 1.0);
        assert_eq!(locations(&[a, a]), None, "two points on top of each other");
        let tiny_loop = [a, p(45.000_1, 1.0), a];
        assert_eq!(
            locations(&tiny_loop),
            None,
            "a loop shorter than the spacing samples its start twice"
        );
        let street = [a, p(45.001, 1.0), p(45.002, 1.0), p(45.003, 1.0)];
        let stops = locations(&street).unwrap();
        assert!(stops.len() >= 2);
        assert!(stops.windows(2).all(|w| w[0].distance_m(w[1]) >= 1.0));
    }

    #[test]
    fn an_engine_refusal_keeps_its_reason() {
        let body = serde_json::json!({
            "error_code": 154,
            "error": "Insufficient number of locations provided",
            "status_code": 400,
        });
        assert_eq!(
            refusal(reqwest::StatusCode::BAD_REQUEST, &body),
            "HTTP 400 error 154: Insufficient number of locations provided"
        );
        assert!(MatchError::Refused(String::new()).is_refusal());
    }

    #[test]
    fn only_a_loopback_engine_is_accepted() {
        assert!(is_loopback("http://127.0.0.1:8002"));
        assert!(is_loopback("http://[::1]:8002"));
        assert!(is_loopback("http://localhost:8002"));
        assert!(!is_loopback("https://127.0.0.1:8002"));
        assert!(!is_loopback("http://10.0.0.2:8002"));
        assert!(!is_loopback("http://user:pw@127.0.0.1:8002"));
    }

    #[test]
    fn a_request_stays_within_the_engine_s_limit_of_locations() {
        let config: Value =
            serde_json::from_str(include_str!("../../../../../infra/routing/valhalla.json"))
                .unwrap();
        let limit = config["service_limits"]["auto"]["max_locations"]
            .as_u64()
            .unwrap();
        assert!(
            MAX_LOCATIONS as u64 <= limit,
            "the engine refuses a request with more locations than its limit"
        );
        let long: Vec<Position> = (0..=400)
            .map(|i| p(45.80, 1.25 + f64::from(i) * 0.0005))
            .collect();
        assert!(
            request(&long).unwrap()["locations"]
                .as_array()
                .unwrap()
                .len()
                <= MAX_LOCATIONS
        );
    }

    #[test]
    fn a_drawn_street_is_followed_through_points() {
        let line: Vec<Position> = (0..=40)
            .map(|i| p(45.80, 1.25 + f64::from(i) * 0.0005))
            .collect();
        let body = request(&line).unwrap();
        let locations = body["locations"].as_array().unwrap();
        assert!(locations.len() <= MAX_LOCATIONS);
        assert!(
            locations.len() > 5,
            "a 1.5 km street is followed every 150 m"
        );
        assert_eq!(locations[0]["type"], "break");
        assert_eq!(locations[1]["type"], "through");
        assert_eq!(
            locations[0]["heading"], 90,
            "it leaves east, along the street"
        );
        let section = request(&[p(45.80, 1.25), p(45.82, 1.25)]).unwrap();
        assert_eq!(section["locations"].as_array().unwrap().len(), 2);
        assert_eq!(section["locations"][0]["heading"], 0);
    }
}
