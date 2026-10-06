//! Road events along a route: which ones the route meets, when the vehicle
//! gets there, and what they mean for it then
//! (`lunaway_domain::road_events`). A closure or a limit the vehicle
//! exceeds, active at its arrival, is a blocker: the route is computed
//! again with small rings excluded on the road the route used. The rest
//! warns or informs, with the age of its data.

use std::{collections::HashMap, sync::Arc};

use chrono::{DateTime, Duration, Utc};
use lunaway_db::road_events::{EventRow, SourceStatus};
use lunaway_domain::{
    Position,
    road_events::{
        Carriageway, EventContext, EventDirection, EventFinding, EventReason, EventSeverity,
        MatchQuality, SourceGeometry,
        along::{Maneuver, RouteStep, point_hit, ramp_hits},
        assess,
        assess::EventFacts,
        road,
    },
    routing::{RouteLine, RoutingDimensions, match_route, match_route_directed},
};
use serde_json::Value;

/// How far from a route the database looks for matched lines, metres.
pub(crate) const CORRIDOR_M: f64 = 20.0;
/// How far it looks for an event's own geometry: a slip road event lies on
/// the main road up to a kilometre from the slip roads it closes.
pub(crate) const WIDE_M: f64 = 1_000.0;
/// How far a matched line may lie from the route that follows it: both
/// come from the same graph.
const MATCHED_TOLERANCE_M: f64 = 12.0;
/// How far a point event may lie from the route.
const POINT_TOLERANCE_M: f64 = 15.0;
/// How far an event that could not be placed may lie from the route and
/// still be told.
const LOOSE_TOLERANCE_M: f64 = 50.0;
/// Radius of the ring excluded on a blocked road, metres: small, so that a
/// bridge over the closed road or the other carriageway is spared.
pub(crate) const RING_M: f64 = 3.0;
/// Spacing of the rings along a long closure: the engine could otherwise
/// leave and join the closed road between two rings.
const RING_EVERY_M: f64 = 2_000.0;
/// Most rings for one event.
const MAX_RINGS_PER_EVENT: usize = 8;

/// The time the vehicle reaches each point of the route.
#[derive(Debug, Clone)]
pub(crate) struct Timing {
    depart: DateTime<Utc>,
    /// Seconds from the start at each shape point.
    at_point: Vec<f64>,
}

impl Timing {
    /// The timing of an OSRM route: its legs' `annotation.duration`, one
    /// figure per segment of the shape, or the route's mean speed when
    /// they do not add up to the shape.
    pub(crate) fn of(route: &Value, line: &RouteLine, depart: DateTime<Utc>) -> Self {
        let mut durations: Vec<f64> = Vec::new();
        for leg in route
            .get("legs")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if let Some(d) = leg
                .get("annotation")
                .and_then(|a| a.get("duration"))
                .and_then(Value::as_array)
            {
                durations.extend(d.iter().map(|x| x.as_f64().unwrap_or(0.0)));
            }
        }
        let n = line.points().len();
        let mut at_point = Vec::with_capacity(n);
        if durations.len() + 1 == n {
            let mut t = 0.0;
            at_point.push(0.0);
            for d in durations {
                t += d.max(0.0);
                at_point.push(t);
            }
        } else {
            let total = route
                .get("duration")
                .and_then(Value::as_f64)
                .unwrap_or(0.0)
                .max(0.0);
            let length = line.length_m().max(1.0);
            let mut along = 0.0;
            at_point.push(0.0);
            for w in line.points().windows(2) {
                along += w[0].distance_m(w[1]);
                at_point.push(total * along / length);
            }
        }
        Self { depart, at_point }
    }

    /// When the vehicle is `s` metres from the start.
    pub(crate) fn at(&self, line: &RouteLine, s: f64) -> DateTime<Utc> {
        let i = line.index_at(s);
        let t = self.at_point.get(i).copied().unwrap_or(0.0);
        let next = self.at_point.get(i + 1).copied().unwrap_or(t);
        let along = line.along();
        let along_i = along.get(i).copied().unwrap_or(0.0);
        let along_next = along.get(i + 1).copied().unwrap_or(along_i);
        let share = if along_next > along_i {
            ((s - along_i) / (along_next - along_i)).clamp(0.0, 1.0)
        } else {
            0.0
        };
        #[allow(
            clippy::cast_possible_truncation,
            reason = "seconds of a trip, far inside i64"
        )]
        let ms = ((t + (next - t) * share) * 1_000.0) as i64;
        self.depart + Duration::milliseconds(ms)
    }
}

/// How far a step's maneuver point may lie from the route line, metres:
/// both come from the same engine.
const MANEUVER_TOLERANCE_M: f64 = 25.0;

/// The steps of an OSRM route, placed along `line`. Each step starts where
/// its maneuver point projects onto the line, searched near where the
/// previous step's length leads: the engine measures on another sphere and
/// rounds, and summing its lengths drifts with the number of steps. A step
/// whose point does not project starts where the previous one's length
/// leads.
pub(crate) fn steps_of(route: &Value, line: &RouteLine) -> Vec<RouteStep> {
    let raw: Vec<(f64, Option<Position>, Maneuver, Vec<String>)> = route
        .get("legs")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|l| l.get("steps").and_then(Value::as_array))
        .flatten()
        .map(|s| {
            let m = s.get("maneuver");
            let maneuver = match m.and_then(|m| m.get("type")).and_then(Value::as_str) {
                Some("off ramp") => Maneuver::OffRamp,
                Some("fork") => Maneuver::Fork,
                Some("on ramp") => Maneuver::OnRamp,
                _ => Maneuver::Other,
            };
            let location = m
                .and_then(|m| m.get("location"))
                .and_then(Value::as_array)
                .and_then(|l| Position::new(l.get(1)?.as_f64()?, l.first()?.as_f64()?).ok());
            let refs = s
                .get("ref")
                .and_then(Value::as_str)
                .map(road::numbers)
                .unwrap_or_default();
            (
                s.get("distance")
                    .and_then(Value::as_f64)
                    .unwrap_or(0.0)
                    .max(0.0),
                location,
                maneuver,
                refs,
            )
        })
        .collect();
    let total: f64 = raw.iter().map(|(d, ..)| d).sum();
    let scale = if total > 0.0 {
        line.length_m() / total
    } else {
        0.0
    };
    let mut starts: Vec<f64> = Vec::with_capacity(raw.len());
    let mut expected = 0.0;
    for (i, (d, location, ..)) in raw.iter().enumerate() {
        let floor = starts.last().copied().unwrap_or(0.0);
        let slack = 200.0 + 0.02 * expected;
        let anchored = if i == 0 {
            Some(0.0)
        } else {
            location.and_then(|p| {
                line.project_within(
                    p,
                    MANEUVER_TOLERANCE_M,
                    floor.max(expected - slack),
                    expected + slack,
                )
                .map(|q| q.along_m)
            })
        };
        let start = anchored.unwrap_or(expected).max(floor);
        starts.push(start);
        expected = start + d * scale;
    }
    let length = line.length_m();
    raw.into_iter()
        .enumerate()
        .map(|(i, (_, _, maneuver, refs))| {
            let start_m = starts[i];
            let end = starts.get(i + 1).copied().unwrap_or(length);
            RouteStep {
                start_m,
                length_m: (end - start_m).max(0.0),
                maneuver,
                refs,
            }
        })
        .collect()
}

/// Whether each source's events may block now.
#[derive(Debug, Clone, Default)]
pub(crate) struct Freshness {
    by_source: HashMap<String, (bool, Option<DateTime<Utc>>)>,
}

impl Freshness {
    /// The freshness of `sources`, `now`.
    pub(crate) fn of(sources: &[SourceStatus], now: DateTime<Utc>) -> Self {
        let by_source = sources
            .iter()
            .map(|s| {
                let fresh = s.id == lunaway_db::road_events::COMMUNITY
                    || s.data_at
                        .is_some_and(|t| (now - t).num_seconds() <= i64::from(s.stale_after_s));
                (s.id.clone(), (fresh, s.data_at))
            })
            .collect();
        Self { by_source }
    }

    fn fresh(&self, source: &str) -> bool {
        self.by_source.get(source).is_some_and(|(f, _)| *f)
    }

    /// When `source`'s data was last known current.
    pub(crate) fn read_at(&self, source: &str) -> Option<DateTime<Utc>> {
        self.by_source.get(source).and_then(|(_, t)| *t)
    }
}

/// An event met along a route.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct EventHit {
    /// The event.
    pub(crate) event: Arc<EventRow>,
    /// What it means for the vehicle.
    pub(crate) finding: EventFinding,
    /// Where the route enters it, metres from the start.
    pub(crate) start_m: f64,
    /// Where it leaves it.
    pub(crate) end_m: f64,
    /// The shape point at or before the entry.
    pub(crate) geometry_index: usize,
    /// The route's point at the entry.
    pub(crate) at: Position,
    /// When the vehicle gets there.
    pub(crate) arrival: DateTime<Utc>,
    /// Where exclusion rings go, on the road the route used.
    pub(crate) rings: Vec<Position>,
}

/// Where a route meets an event: (start, end, rings).
type Meeting = (f64, f64, Vec<Position>);

/// The rings along a stretch of the route from `start` to `end`: its
/// middle, then every [`RING_EVERY_M`].
fn rings_along(line: &RouteLine, start: f64, end: f64) -> Vec<Position> {
    let mut out = vec![line.point_at((start + end) / 2.0)];
    let mut s = start + RING_EVERY_M / 2.0;
    while s < end && out.len() < MAX_RINGS_PER_EVENT {
        if (s - (start + end) / 2.0).abs() > RING_EVERY_M / 4.0 {
            out.push(line.point_at(s));
        }
        s += RING_EVERY_M;
    }
    out
}

/// Whether `p` lies inside `ring` (ray casting on the plane of degrees: the
/// areas are a few hundred metres wide).
fn inside(ring: &[Position], p: Position) -> bool {
    let mut inside = false;
    let n = ring.len();
    let mut j = n.saturating_sub(1);
    for i in 0..n {
        let (a, b) = (ring[i], ring[j]);
        if (a.lat() > p.lat()) != (b.lat() > p.lat())
            && p.lon() < (b.lon() - a.lon()) * (p.lat() - a.lat()) / (b.lat() - a.lat()) + a.lon()
        {
            inside = !inside;
        }
        j = i;
    }
    inside
}

/// Where `line` meets an event not placed on the graph, by its own
/// geometry: loosely, for a warning only.
fn loose(line: &RouteLine, e: &EventRow) -> Vec<Meeting> {
    match &e.geometry {
        SourceGeometry::Point(p) => line
            .project(*p, LOOSE_TOLERANCE_M)
            .map(|q| vec![(q.along_m, q.along_m, Vec::new())])
            .unwrap_or_default(),
        SourceGeometry::Lines(lines) => {
            let mut out = Vec::new();
            for l in lines {
                let hits = match_route(line, l, LOOSE_TOLERANCE_M);
                if let Some(h) = hits.first() {
                    out.push((h.start_m, h.end_m, Vec::new()));
                    continue;
                }
                // A DIR section is its two ends: the route passes both, in
                // order when it concerns one direction.
                if let (Some(a), Some(b)) = (l.first(), l.last())
                    && let (Some(pa), Some(pb)) = (
                        line.project(*a, LOOSE_TOLERANCE_M),
                        line.project(*b, LOOSE_TOLERANCE_M),
                    )
                    && (e.direction != EventDirection::Forward || pa.along_m <= pb.along_m)
                {
                    let (s, t) = (pa.along_m.min(pb.along_m), pa.along_m.max(pb.along_m));
                    out.push((s, t, Vec::new()));
                }
            }
            out
        }
        SourceGeometry::Polygons(rings) => {
            let points = line.points();
            for ring in rings {
                if let Some(i) = points.iter().position(|p| inside(ring, *p)) {
                    let s = line.along()[i];
                    return vec![(s, s, Vec::new())];
                }
            }
            Vec::new()
        }
    }
}

/// Where `line` meets `e`, by the rule of its placement.
fn meetings(line: &RouteLine, steps: &[RouteStep], e: &EventRow) -> Vec<Meeting> {
    match e.match_quality {
        MatchQuality::Matched => e
            .matched
            .iter()
            .flat_map(|l| match_route_directed(line, l, MATCHED_TOLERANCE_M))
            .map(|h| (h.start_m, h.end_m, rings_along(line, h.start_m, h.end_m)))
            .collect(),
        MatchQuality::Ramp => {
            let Some(at) = e.geometry.representative() else {
                return Vec::new();
            };
            let carriageway = if e.carriageway == Carriageway::Main {
                Carriageway::Ramps
            } else {
                e.carriageway
            };
            ramp_hits(
                line,
                steps,
                at,
                carriageway,
                e.road_number.as_deref(),
                e.direction,
            )
            .into_iter()
            .map(|h| (h.start_m, h.start_m, h.ring_at.into_iter().collect()))
            .collect()
        }
        MatchQuality::Point => {
            let Some(at) = e.geometry.representative() else {
                return Vec::new();
            };
            point_hit(
                line,
                steps,
                at,
                e.road_number.as_deref(),
                e.direction,
                e.heading_deg.map(f64::from),
                POINT_TOLERANCE_M,
            )
            .map(|s| vec![(s, s, vec![line.point_at(s)])])
            .unwrap_or_default()
        }
        _ => loose(line, e),
    }
}

/// The events `near` a route that it meets, weighed for a vehicle of
/// `dims` at its arrival: (warnings and information, blockers), each in
/// driving order, an event once in each (at its first meeting; a blocker
/// keeps the rings of every meeting).
pub(crate) fn check(
    line: &RouteLine,
    steps: &[RouteStep],
    timing: &Timing,
    near: &[Arc<EventRow>],
    dims: &RoutingDimensions,
    fresh: &Freshness,
    now: DateTime<Utc>,
) -> (Vec<EventHit>, Vec<EventHit>) {
    let mut told = Vec::new();
    let mut blocking: Vec<EventHit> = Vec::new();
    for e in near {
        let mut first_told: Option<EventHit> = None;
        for (start, end, rings) in meetings(line, steps, e) {
            let arrival = timing.at(line, start);
            let facts = EventFacts {
                class: e.class,
                limits: e.limits,
                valid_from: e.valid_from,
                valid_to: e.valid_to,
                schedule: &e.schedule,
                confidence: e.confidence,
                match_quality: e.match_quality,
                updated_at: e.source_updated_at.unwrap_or(e.first_seen_at),
            };
            let ctx = EventContext {
                now,
                arrival,
                source_fresh: fresh.fresh(&e.source),
                at_an_end: end > start && (start <= 1.0 || end >= line.length_m() - 1.0),
            };
            let Some(mut finding) = assess(&facts, dims, &ctx) else {
                continue;
            };
            // A blocker the route cannot be steered around without closing
            // another road (a slip road beside its carriageway) warns.
            if finding.severity == EventSeverity::Blocking && rings.is_empty() {
                finding.severity = EventSeverity::Warning;
                finding.reason = EventReason::Unmatched;
            }
            let hit = EventHit {
                event: Arc::clone(e),
                finding,
                start_m: start,
                end_m: end,
                geometry_index: line.index_at(start),
                at: line.point_at(start),
                arrival,
                rings,
            };
            if finding.severity == EventSeverity::Blocking {
                match blocking.iter_mut().find(|b| b.event.id == e.id) {
                    Some(b) => b.rings.extend(hit.rings),
                    None => blocking.push(hit),
                }
            } else if first_told.is_none() {
                first_told = Some(hit);
            }
        }
        if let Some(t) = first_told
            && !blocking.iter().any(|b| b.event.id == t.event.id)
        {
            told.push(t);
        }
    }
    told.sort_by(|a, b| a.start_m.total_cmp(&b.start_m));
    blocking.sort_by(|a, b| a.start_m.total_cmp(&b.start_m));
    (told, blocking)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_point_inside_an_area_is_found() {
        let p = |lat, lon| Position::new(lat, lon).unwrap();
        let square = [p(45.0, 1.0), p(45.0, 1.01), p(45.01, 1.01), p(45.01, 1.0)];
        assert!(inside(&square, p(45.005, 1.005)));
        assert!(!inside(&square, p(45.02, 1.005)));
    }

    #[test]
    fn the_time_along_the_route_follows_its_annotations() {
        let p = |lon| Position::new(45.0, lon).unwrap();
        let line = RouteLine::new(vec![p(1.0), p(1.01), p(1.02)]).unwrap();
        let depart = DateTime::parse_from_rfc3339("2026-10-06T10:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let route = serde_json::json!({"duration": 999.0, "legs": [{"annotation": {"duration": [60.0, 600.0]}}]});
        let t = Timing::of(&route, &line, depart);
        let half = line.length_m() * 0.75;
        assert_eq!(t.at(&line, 0.0), depart);
        let minutes = (t.at(&line, half) - depart).num_seconds();
        assert!(
            (350..=370).contains(&minutes),
            "half of the slow segment: {minutes}"
        );
        let fallback = Timing::of(&serde_json::json!({"duration": 1000.0}), &line, depart);
        let end = (fallback.at(&line, line.length_m()) - depart).num_seconds();
        assert!((995..=1000).contains(&end), "{end}");
    }
}
