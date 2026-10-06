//! Where a route meets an event that is not a line of the graph: a slip
//! road closure, a point on a numbered road, a user's report. The route's
//! own steps say which road it is on and where it leaves or joins one, so
//! these rules need no map of their own.
//!
//! A slip road event is located on the main road (Cerema, "Publication
//! d'une situation de trafic Datex II", 2015, section 7.1): 45 of the 66
//! closures active in the DIR snapshot of 2026-10-06 were slip roads
//! (`plan/research/20-travaux-temps-reel.md`, part 6). Placing it on the
//! main road would close a motorway for a closed exit, so the rule here
//! only ever closes the slip roads the route itself takes near the event:
//! never the main carriageway.

use super::{Carriageway, EventDirection, road};
use crate::{
    Position,
    geo::EARTH_RADIUS_M,
    routing::{RouteLine, turn_between},
};

/// How far from the event a slip road may start or end and still be one of
/// its interchange, metres: an interchange's slip roads leave and join the
/// main road within a few hundred metres of its reference point.
pub const RAMP_SEARCH_M: f64 = 1_000.0;
/// How far into an exit slip road the exclusion goes, metres: past the
/// gore, where the slip road has left the main carriageway.
pub const RING_INTO_EXIT_M: f64 = 80.0;
/// How far into an entry slip road, metres: past the junction with the
/// local road it starts from.
pub const RING_INTO_ENTRY_M: f64 = 60.0;
/// Least distance between an exclusion on a slip road and the road the
/// route was on before it, metres: the exclusion ring's 3 m and a margin
/// for the drawing of both lines. Closer, at a gore where the slip road
/// runs beside the carriageway or on a short slip road, the exclusion
/// could close the carriageway the event never closes: the event then
/// warns instead.
pub const RING_CLEARANCE_M: f64 = 10.0;
/// How much of the route before a slip road is the road it left, metres.
const LEFT_STRETCH_M: f64 = 200.0;
/// How far past the gore the road left is carried on straight, beyond the
/// ring, metres: the route no longer follows it, but at a gore it runs on
/// beside the slip road, nearly straight on a main road.
const CARRIED_PAST_RING_M: f64 = 50.0;

/// The point `m` metres from `from` heading `heading_deg`, on a plane: a
/// few hundred metres at most.
fn ahead(from: Position, heading_deg: f64, m: f64) -> Option<Position> {
    let per_deg = EARTH_RADIUS_M.to_radians();
    let (sin, cos) = heading_deg.to_radians().sin_cos();
    Position::new(
        from.lat() + m * cos / per_deg,
        from.lon() + m * sin / (per_deg * from.lat().to_radians().cos()),
    )
    .ok()
}

/// Whether `ring`, on the slip road the route takes at `start_m`, lies
/// [`RING_CLEARANCE_M`] clear of the road the route leaves there: the
/// stretch it drove before, and that road carried on straight past the
/// gore.
fn clear_of_the_road_left(line: &RouteLine, start_m: f64, ring: Position, into_m: f64) -> bool {
    let behind = line
        .project_within(
            ring,
            RING_CLEARANCE_M,
            (start_m - LEFT_STRETCH_M).max(0.0),
            start_m,
        )
        .is_some();
    let gore = line.point_at(start_m);
    let heading = line.heading_at((start_m - 30.0).max(0.0));
    let beside = ahead(gore, heading, into_m + CARRIED_PAST_RING_M)
        .and_then(|end| RouteLine::new(vec![gore, end]))
        .is_some_and(|carried| carried.project(ring, RING_CLEARANCE_M).is_some());
    !behind && !beside
}
/// Largest angle between the route and a compass direction the source
/// gives ("northbound") that still counts as that direction: the label is
/// the road's general direction, and a road labelled northbound runs east
/// or west in places (18 of 120 northbound DIR sections ran mostly west on
/// 2026-10-06). A route heading the opposite way does not count.
pub const COMPASS_TOLERANCE_DEG: f64 = 100.0;
/// Largest angle between the route and the heading of a user's report.
pub const HEADING_TOLERANCE_DEG: f64 = 60.0;

/// What a step of the route does at its start.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Maneuver {
    /// Takes an entry slip road from a local road.
    OnRamp,
    /// Takes an exit slip road, or a connector to another motorway.
    OffRamp,
    /// Takes one branch where the road splits (a motorway junction).
    Fork,
    /// Anything else.
    Other,
}

/// A step of the route, as the engine describes it.
#[derive(Debug, Clone, PartialEq)]
pub struct RouteStep {
    /// Distance from the start of the route where the step begins, metres.
    pub start_m: f64,
    /// Its length, metres.
    pub length_m: f64,
    /// What it does at its start.
    pub maneuver: Maneuver,
    /// The road numbers of the road it follows, canonical
    /// ([`road::numbers`]).
    pub refs: Vec<String>,
}

/// Where the route takes a slip road of an event's interchange.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RampHit {
    /// Distance from the start where the route enters the slip road.
    pub start_m: f64,
    /// Where on the slip road an exclusion goes; `None` when no point of
    /// it lies [`RING_CLEARANCE_M`] clear of the road the route left: the
    /// event warns, it cannot be avoided without closing that road.
    pub ring_at: Option<Position>,
}

/// Whether a step follows road `road` (canonical), or no road is stated.
fn on_road(step: Option<&RouteStep>, road: Option<&str>) -> bool {
    match road {
        None => true,
        Some(r) => step.is_some_and(|s| s.refs.iter().any(|x| x == r)),
    }
}

/// Whether a heading agrees with the direction an event concerns.
fn heading_agrees(heading_deg: f64, direction: EventDirection) -> bool {
    direction
        .compass_deg()
        .is_none_or(|c| turn_between(heading_deg, c) <= COMPASS_TOLERANCE_DEG)
}

/// The slip roads of the event's interchange the route takes: an exit
/// leaving road `road` (canonical), or an entry joining it, within
/// [`RAMP_SEARCH_M`] of the event at `at`, in the direction the event
/// concerns. `steps` are the route's steps in order; each starts where
/// `line` is at its `start_m`.
///
/// A fork counts only for an event that names its road, and as an exit
/// only when the branch taken has no road number: where a motorway splits
/// into two numbered roads, the branch is a main carriageway, not the slip
/// road the event closes.
#[must_use]
pub fn ramp_hits(
    line: &RouteLine,
    steps: &[RouteStep],
    at: Position,
    carriageway: Carriageway,
    road: Option<&str>,
    direction: EventDirection,
) -> Vec<RampHit> {
    let (exits, entries) = match carriageway {
        Carriageway::Exit => (true, false),
        Carriageway::Entry => (false, true),
        Carriageway::Ramps => (true, true),
        Carriageway::Main | Carriageway::Unknown => return Vec::new(),
    };
    let road = road.and_then(road::normalize);
    let road = road.as_deref();
    let mut out = Vec::new();
    for (i, step) in steps.iter().enumerate() {
        let start = line.point_at(step.start_m);
        if start.distance_m(at) > RAMP_SEARCH_M {
            continue;
        }
        let before = i.checked_sub(1).and_then(|j| steps.get(j));
        let after = steps.get(i + 1);
        let leaves = |r: Option<&str>| {
            // The route was on the road before the step, and the step takes
            // it elsewhere (a fork that stays on the road is no exit).
            r.is_none_or(|r| {
                before.is_some_and(|b| b.refs.iter().any(|x| x == r))
                    && !step.refs.iter().any(|x| x == r)
            })
        };
        let joins = |r: Option<&str>| {
            // The slip road leads onto the road: the step names it or the
            // next one follows it, and the route was not on it already.
            r.is_none_or(|r| {
                (step.refs.iter().any(|x| x == r)
                    || after.is_some_and(|a| a.refs.iter().any(|x| x == r)))
                    && !before.is_some_and(|b| b.refs.iter().any(|x| x == r))
            })
        };
        let fork_named = step.maneuver == Maneuver::Fork && road.is_some();
        let slip = matches!(step.maneuver, Maneuver::OnRamp | Maneuver::OffRamp) || fork_named;
        let exit_here = exits
            && (step.maneuver == Maneuver::OffRamp || (fork_named && step.refs.is_empty()))
            && leaves(road)
            && heading_agrees(line.heading_at((step.start_m - 30.0).max(0.0)), direction);
        // An entry slip road from a local road ("on ramp"), or a connector
        // from another motorway ("off ramp" or "fork" onto this road).
        let entry_here = entries
            && slip
            && joins(road)
            && heading_agrees(
                line.heading_at(step.start_m + step.length_m.min(400.0)),
                direction,
            );
        let hit = if exit_here {
            Some(RING_INTO_EXIT_M)
        } else if entry_here {
            Some(RING_INTO_ENTRY_M)
        } else {
            None
        };
        if let Some(into) = hit {
            let into = into.min(step.length_m / 2.0);
            let ring = line.point_at(step.start_m + into);
            out.push(RampHit {
                start_m: step.start_m,
                ring_at: clear_of_the_road_left(line, step.start_m, ring, into).then_some(ring),
            });
        }
    }
    out
}

/// Where the route passes an event placed at a point `at`: within
/// `tolerance_m`, on road `road` (canonical) when the event names one, in
/// the direction it concerns (a compass label of the source, or the
/// heading of a user's report). The distance from the start, if it does.
#[must_use]
pub fn point_hit(
    line: &RouteLine,
    steps: &[RouteStep],
    at: Position,
    road: Option<&str>,
    direction: EventDirection,
    heading_deg: Option<f64>,
    tolerance_m: f64,
) -> Option<f64> {
    let p = line.project(at, tolerance_m)?;
    let road = road.and_then(road::normalize);
    if road.is_some() {
        let step = steps.iter().rev().find(|s| s.start_m <= p.along_m);
        if !on_road(step, road.as_deref()) {
            return None;
        }
    }
    if !heading_agrees(p.heading_deg, direction) {
        return None;
    }
    if heading_deg.is_some_and(|h| turn_between(p.heading_deg, h) > HEADING_TOLERANCE_DEG) {
        return None;
    }
    Some(p.along_m)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn origin() -> Position {
        Position::new(47.75, -3.30).unwrap()
    }

    /// A point `east` and `north` metres from the origin.
    fn at(east: f64, north: f64) -> Position {
        let k = EARTH_RADIUS_M * std::f64::consts::PI / 180.0;
        Position::new(
            origin().lat() + north / k,
            origin().lon() + east / (k * origin().lat().to_radians().cos()),
        )
        .unwrap()
    }

    /// A route east along the N165 for 2 km, then off at an exit slip road
    /// bending north-east for 300 m, then a local road north.
    fn exit_route() -> (RouteLine, Vec<RouteStep>) {
        let mut points: Vec<Position> = (0..=40).map(|i| at(f64::from(i) * 50.0, 0.0)).collect();
        points.extend((1..=6).map(|i| at(2_000.0 + f64::from(i) * 40.0, f64::from(i) * 30.0)));
        points.extend((1..=10).map(|i| at(2_240.0, 180.0 + f64::from(i) * 50.0)));
        let line = RouteLine::new(points).unwrap();
        let steps = vec![
            RouteStep {
                start_m: 0.0,
                length_m: 2_000.0,
                maneuver: Maneuver::Other,
                refs: vec!["N165".into(), "E60".into()],
            },
            RouteStep {
                start_m: 2_000.0,
                length_m: 300.0,
                maneuver: Maneuver::OffRamp,
                refs: Vec::new(),
            },
            RouteStep {
                start_m: 2_300.0,
                length_m: 500.0,
                maneuver: Maneuver::Other,
                refs: vec!["D768".into()],
            },
        ];
        (line, steps)
    }

    #[test]
    fn an_exit_closure_closes_the_exit_the_route_takes_and_never_the_main_road() {
        let (line, steps) = exit_route();
        // The DIR places the closed exit on the N165 itself.
        let event = at(1_800.0, 0.0);
        let hits = ramp_hits(
            &line,
            &steps,
            event,
            Carriageway::Exit,
            Some("N0165"),
            EventDirection::East,
        );
        assert_eq!(hits.len(), 1, "{hits:?}");
        let ring = hits[0].ring_at.unwrap();
        assert!(
            ring.distance_m(at(2_000.0, 0.0)) > 50.0,
            "the ring sits on the slip road, past the gore"
        );
        let main_road = RouteLine::new(vec![at(0.0, 0.0), at(4_000.0, 0.0)]).unwrap();
        assert!(
            main_road.project(ring, 30.0).is_none(),
            "nothing of the main carriageway lies within 30 m of the ring"
        );
    }

    #[test]
    fn a_slip_road_event_spares_a_route_that_stays_on_the_main_road() {
        let line =
            RouteLine::new((0..=80).map(|i| at(f64::from(i) * 50.0, 0.0)).collect()).unwrap();
        let steps = vec![RouteStep {
            start_m: 0.0,
            length_m: 4_000.0,
            maneuver: Maneuver::Other,
            refs: vec!["N165".into()],
        }];
        let event = at(1_800.0, 0.0);
        for c in [Carriageway::Exit, Carriageway::Entry, Carriageway::Ramps] {
            assert!(
                ramp_hits(&line, &steps, event, c, Some("N165"), EventDirection::Both).is_empty(),
                "a closed {c} slip road never closes the main carriageway"
            );
        }
    }

    #[test]
    fn an_exit_of_another_road_or_direction_or_interchange_is_spared() {
        let (line, steps) = exit_route();
        let event = at(1_800.0, 0.0);
        assert!(
            ramp_hits(
                &line,
                &steps,
                event,
                Carriageway::Exit,
                Some("N24"),
                EventDirection::Both
            )
            .is_empty(),
            "the route leaves the N165, not the N24"
        );
        assert!(
            ramp_hits(
                &line,
                &steps,
                event,
                Carriageway::Exit,
                Some("N165"),
                EventDirection::West
            )
            .is_empty(),
            "the westbound exit is on the other carriageway"
        );
        assert!(
            ramp_hits(
                &line,
                &steps,
                at(-2_000.0, 0.0),
                Carriageway::Exit,
                Some("N165"),
                EventDirection::Both
            )
            .is_empty(),
            "an exit 4 km away is another interchange"
        );
        assert!(
            ramp_hits(
                &line,
                &steps,
                event,
                Carriageway::Entry,
                Some("N165"),
                EventDirection::Both
            )
            .is_empty(),
            "a closed entry does not close an exit"
        );
    }

    #[test]
    fn an_entry_closure_closes_the_entry_the_route_takes() {
        // A local road south, then an entry slip road onto the N165 east.
        let mut points: Vec<Position> = (0..=10)
            .map(|i| at(0.0, -500.0 + f64::from(i) * 50.0))
            .collect();
        points.extend((1..=6).map(|i| at(f64::from(i) * 50.0, f64::from(i) * 5.0)));
        points.extend((1..=30).map(|i| at(300.0 + f64::from(i) * 50.0, 30.0)));
        let line = RouteLine::new(points).unwrap();
        let steps = vec![
            RouteStep {
                start_m: 0.0,
                length_m: 500.0,
                maneuver: Maneuver::Other,
                refs: vec!["D768".into()],
            },
            RouteStep {
                start_m: 500.0,
                length_m: 1_800.0,
                maneuver: Maneuver::OnRamp,
                refs: vec!["N165".into(), "E60".into()],
            },
        ];
        let hits = ramp_hits(
            &line,
            &steps,
            at(200.0, 30.0),
            Carriageway::Entry,
            Some("N 165"),
            EventDirection::East,
        );
        assert_eq!(hits.len(), 1);
        assert!((hits[0].start_m - 500.0).abs() < 1.0);
    }

    #[test]
    fn a_closed_connector_from_another_motorway_is_an_entry_closure() {
        // On the A89, then a connector onto the A20 northbound.
        let (line, mut steps) = exit_route();
        steps[0].refs = vec!["A89".into()];
        steps[1].refs = vec!["A20".into()];
        steps[2].refs = vec!["A20".into()];
        let event = at(1_900.0, 0.0);
        assert_eq!(
            ramp_hits(
                &line,
                &steps,
                event,
                Carriageway::Entry,
                Some("A20"),
                EventDirection::Both
            )
            .len(),
            1,
            "the connector onto the A20 is the closed entry"
        );
        assert!(
            ramp_hits(
                &line,
                &steps,
                event,
                Carriageway::Exit,
                Some("A20"),
                EventDirection::Both
            )
            .is_empty(),
            "the route does not leave the A20 there"
        );
        // A fork that keeps the route on its road is no exit.
        steps[0].refs = vec!["A20".into()];
        steps[1].maneuver = Maneuver::Fork;
        assert!(
            ramp_hits(
                &line,
                &steps,
                event,
                Carriageway::Exit,
                Some("A20"),
                EventDirection::Both
            )
            .is_empty()
        );
    }

    #[test]
    fn a_fork_into_another_numbered_road_is_no_exit() {
        let (line, mut steps) = exit_route();
        steps[1].maneuver = Maneuver::Fork;
        let event = at(1_800.0, 0.0);
        let exit = |steps: &[RouteStep], road| {
            ramp_hits(
                &line,
                steps,
                event,
                Carriageway::Exit,
                road,
                EventDirection::Both,
            )
            .len()
        };
        assert_eq!(
            exit(&steps, Some("N165")),
            1,
            "an unnumbered link off the N165"
        );
        assert_eq!(
            exit(&steps, None),
            0,
            "without the event's road, any fork near it would do"
        );
        steps[1].refs = vec!["N24".into()];
        assert_eq!(
            exit(&steps, Some("N165")),
            0,
            "a branch that is the N24 is a main carriageway"
        );
    }

    #[test]
    fn a_ring_beside_the_road_left_warns_instead() {
        // A slip road that runs 6 m beside the N165 for its first 150 m.
        let mut points: Vec<Position> = (0..=40).map(|i| at(f64::from(i) * 50.0, 0.0)).collect();
        points.extend((1..=3).map(|i| at(2_000.0 + f64::from(i) * 50.0, 6.0)));
        points
            .extend((1..=6).map(|i| at(2_150.0 + f64::from(i) * 40.0, 6.0 + f64::from(i) * 30.0)));
        let line = RouteLine::new(points).unwrap();
        let steps = vec![
            RouteStep {
                start_m: 0.0,
                length_m: 2_000.0,
                maneuver: Maneuver::Other,
                refs: vec!["N165".into()],
            },
            RouteStep {
                start_m: 2_000.0,
                length_m: 450.0,
                maneuver: Maneuver::OffRamp,
                refs: Vec::new(),
            },
        ];
        let hits = ramp_hits(
            &line,
            &steps,
            at(1_800.0, 0.0),
            Carriageway::Exit,
            Some("N165"),
            EventDirection::Both,
        );
        assert_eq!(hits.len(), 1, "the route takes the closed exit");
        assert_eq!(
            hits[0].ring_at, None,
            "a ring 6 m from the N165 would close the N165 too"
        );
    }

    #[test]
    fn a_point_event_counts_on_its_road_in_its_direction_only() {
        let (line, steps) = exit_route();
        let event = at(1_000.0, 3.0);
        assert!(
            point_hit(
                &line,
                &steps,
                event,
                Some("N0165"),
                EventDirection::East,
                None,
                15.0
            )
            .is_some()
        );
        assert!(
            point_hit(
                &line,
                &steps,
                event,
                Some("N0165"),
                EventDirection::West,
                None,
                15.0
            )
            .is_none(),
            "the other carriageway's event"
        );
        assert!(
            point_hit(
                &line,
                &steps,
                event,
                Some("N24"),
                EventDirection::Both,
                None,
                15.0
            )
            .is_none(),
            "another road passing under the route at that point"
        );
        assert!(
            point_hit(
                &line,
                &steps,
                event,
                None,
                EventDirection::Unknown,
                Some(80.0),
                15.0
            )
            .is_some()
        );
        assert!(
            point_hit(
                &line,
                &steps,
                event,
                None,
                EventDirection::Unknown,
                Some(180.0),
                15.0
            )
            .is_none(),
            "a report made heading south is about the crossing road"
        );
        assert!(
            point_hit(
                &line,
                &steps,
                at(1_000.0, 40.0),
                None,
                EventDirection::Both,
                None,
                15.0
            )
            .is_none()
        );
    }
}
