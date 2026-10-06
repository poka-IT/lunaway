//! Guidance over routes recorded from the Lunaway API (Valhalla 3.9.0 in the
//! OSRM format, French instructions), driven by fixes along their line.
#![allow(
    clippy::expect_used,
    reason = "the helpers state the preconditions of the recorded fixtures"
)]

use lunaway_domain::Position;
use lunaway_domain::routing::polyline;
use lunaway_nav::api::engine::{
    EventShape, Fix, Guidance, GuidanceErrorKind, GuidanceSettings, GuidanceStatus, LatLon,
};

/// A 3.4 km drive across Limoges for a 3.3 m motorhome, ten steps, with
/// speed limits and lanes.
const LIMOGES: &str = include_str!("fixtures/limoges_drive.osrm.json");
/// Rue Maurice Utrillo for a 3.3 m motorhome: the main route round the
/// 2.7 m railway bridge and one alternative.
const UTRILLO: &str = include_str!("fixtures/utrillo_motorhome.osrm.json");

fn line(osrm: &str, route: usize) -> Vec<Position> {
    let value: serde_json::Value = serde_json::from_str(osrm).expect("a recorded answer");
    let shape = value["routes"][route]["geometry"]
        .as_str()
        .expect("a polyline6 geometry");
    polyline::decode(shape).expect("a valid polyline")
}

/// Points every `step_m` metres along `points`, with the heading of their
/// segment.
fn drive(points: &[Position], step_m: f64) -> Vec<(Position, f64)> {
    let mut out = Vec::new();
    let mut carry = 0.0;
    for pair in points.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        let d = a.distance_m(b);
        if d == 0.0 {
            continue;
        }
        let heading = heading(a, b);
        let mut s = carry;
        while s < d {
            let t = s / d;
            let p = Position::new(
                a.lat() + (b.lat() - a.lat()) * t,
                a.lon() + (b.lon() - a.lon()) * t,
            )
            .expect("between two valid points");
            out.push((p, heading));
            s += step_m;
        }
        carry = s - d;
    }
    let last = points[points.len() - 1];
    out.push((last, out.last().map_or(0.0, |(_, h)| *h)));
    out
}

fn heading(a: Position, b: Position) -> f64 {
    let (la, lb) = (a.lat().to_radians(), b.lat().to_radians());
    let dl = (b.lon() - a.lon()).to_radians();
    let y = dl.sin() * lb.cos();
    let x = la.cos() * lb.sin() - la.sin() * lb.cos() * dl.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}

fn fix(p: Position, heading: f64, second: i64) -> Fix {
    Fix {
        lat: p.lat(),
        lon: p.lon(),
        accuracy_m: 5.0,
        course_deg: Some(heading),
        speed_mps: Some(8.0),
        timestamp_ms: 1_791_000_000_000 + second * 1_000,
    }
}

#[test]
fn a_drive_along_the_route_walks_every_step_and_arrives() {
    let mut guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let steps = guidance.step_count();
    assert_eq!(steps, 10, "the recorded route has ten steps");

    let mut last_step = 0;
    let mut last_remaining = f64::MAX;
    let mut spoken = Vec::new();
    let mut limits = Vec::new();
    let mut arrived_at = None;
    for (i, (p, h)) in drive(&line(LIMOGES, 0), 8.0).into_iter().enumerate() {
        let state = guidance.update(fix(p, h, i64::try_from(i).expect("a few hundred")));
        if state.status == GuidanceStatus::Arrived {
            arrived_at = Some(i);
            break;
        }
        assert!(
            state.step_index >= last_step,
            "steps only move forward: {} after {last_step}",
            state.step_index
        );
        last_step = state.step_index;
        assert!(
            state.distance_remaining_m <= last_remaining + 1.0,
            "the distance left never grows on the route: {} after {last_remaining}",
            state.distance_remaining_m
        );
        last_remaining = state.distance_remaining_m;
        assert_eq!(
            state.off_route_m, None,
            "a drive on the line is on the route"
        );
        assert!(
            state.banner.is_some() || state.step_index + 1 >= steps,
            "a banner at every point before the arrival step: point {i}, step {}",
            state.step_index
        );
        if let Some(u) = state.utterance
            && spoken.last() != Some(&u.id)
        {
            spoken.push(u.id);
        }
        if let Some(limit) = state.speed_limit_kmh {
            limits.push(limit);
        }
    }
    assert!(arrived_at.is_some(), "the drive ends at the destination");
    assert!(
        last_step + 2 >= steps,
        "the last steps were reached before the arrival: {last_step} of {steps}"
    );
    assert!(
        spoken.len() >= 8,
        "an instruction is spoken for each maneuver, once: {}",
        spoken.len()
    );
    assert!(
        limits.contains(&50.0),
        "the town's 50 km/h limits are read from the annotations"
    );
}

#[test]
fn the_distance_along_the_route_follows_the_vehicle() {
    let mut guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = drive(&line(LIMOGES, 0), 8.0);
    // Ferrostar follows the vehicle step by step: a fix every second, as a
    // phone gives them, not a jump of a kilometre.
    let mut state = None;
    for (i, (p, h)) in points.iter().take(126).enumerate() {
        state = Some(guidance.update(fix(*p, *h, i64::try_from(i).expect("small"))));
    }
    let state = state.expect("126 fixes");
    // 125 gaps of 8 m: 1 000 m driven, give or take the bends the straight
    // sampling cuts.
    assert!(
        (state.distance_along_m - 1_000.0).abs() < 60.0,
        "about 1 km along: {}",
        state.distance_along_m
    );
    assert!(
        (state.distance_along_m + state.distance_remaining_m - guidance.route_length_m()).abs()
            < 1.0
    );
}

#[test]
fn a_vehicle_far_from_the_line_is_off_the_route() {
    let mut guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = drive(&line(LIMOGES, 0), 8.0);
    for (i, (p, h)) in points.iter().take(40).enumerate() {
        guidance.update(fix(*p, *h, i64::try_from(i).expect("small")));
    }
    let (p, h) = points[40];
    // 0.003 degrees east: about 230 m at this latitude, and more than 100 m
    // from any part of the route.
    let away = Position::new(p.lat(), p.lon() + 0.003).expect("valid");
    let first = guidance.update(fix(away, h, 40));
    // Ferrostar judges the deviation on the state before the fix: the
    // second fix away is the one that says it.
    let second = guidance.update(fix(away, h, 41));
    assert_eq!(first.off_route_m, None);
    assert!(
        second.off_route_m.is_some_and(|d| d > 100.0),
        "off the route by more than 100 m: {:?}",
        second.off_route_m
    );
}

#[test]
fn an_imprecise_fix_never_decides_the_vehicle_left() {
    let mut guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = drive(&line(LIMOGES, 0), 8.0);
    guidance.update(fix(points[0].0, points[0].1, 0));
    let (p, h) = points[10];
    let away = Position::new(p.lat(), p.lon() + 0.003).expect("valid");
    for second in 1..4 {
        let mut f = fix(away, h, second);
        f.accuracy_m = 120.0;
        assert_eq!(
            guidance.update(f).off_route_m,
            None,
            "a fix with 120 m of uncertainty is not evidence of a wrong turn"
        );
    }
}

#[test]
fn the_alternative_is_guided_on_its_own_line() {
    let main = Guidance::new(UTRILLO.to_owned(), 0, GuidanceSettings::default()).expect("main");
    let other = Guidance::new(UTRILLO.to_owned(), 1, GuidanceSettings::default()).expect("alt");
    assert!(
        (main.route_length_m() - 1_812.279).abs() < 0.01,
        "the main route's length as the router measured it"
    );
    assert!((other.route_length_m() - 4_887.279).abs() < 0.01);
}

#[test]
fn an_answer_without_the_route_asked_for_is_refused() {
    let Err(missing) = Guidance::new(UTRILLO.to_owned(), 2, GuidanceSettings::default()) else {
        panic!("the answer has two routes, not three");
    };
    assert_eq!(missing.kind, GuidanceErrorKind::NoSuchRoute);
    let Err(garbage) = Guidance::new("{\"code\":".to_owned(), 0, GuidanceSettings::default())
    else {
        panic!("a truncated answer cannot be guided");
    };
    assert_eq!(garbage.kind, GuidanceErrorKind::InvalidRoute);
}

fn points_between(points: &[Position], from_m: f64, to_m: f64) -> Vec<LatLon> {
    let mut along = 0.0;
    let mut out = Vec::new();
    for pair in points.windows(2) {
        let d = pair[0].distance_m(pair[1]);
        if along + d >= from_m && along <= to_m {
            out.push(LatLon {
                lat: pair[0].lat(),
                lon: pair[0].lon(),
            });
        }
        along += d;
    }
    out
}

/// The server's tolerances: 12 m along a matched line, 15 m from a point
/// (`plan/research/21-backend-travaux.md`, part 5).
const LINE_M: f64 = 12.0;
const POINT_M: f64 = 15.0;

fn shape(id: &str, points: Vec<LatLon>, directed: bool) -> EventShape {
    EventShape {
        id: id.into(),
        points,
        directed,
        heading_deg: None,
        heading_tolerance_deg: 0.0,
    }
}

#[test]
fn a_closure_on_the_road_ahead_is_found_and_one_behind_is_not() {
    let guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = line(LIMOGES, 0);
    let ahead = shape(
        "dir/closure-ahead",
        points_between(&points, 1_500.0, 1_700.0),
        true,
    );
    let behind = shape(
        "dir/closure-behind",
        points_between(&points, 200.0, 400.0),
        true,
    );
    let hits = guidance.events_ahead(1_000.0, vec![ahead, behind], LINE_M, POINT_M);
    assert_eq!(hits.len(), 1, "only the closure ahead: {hits:?}");
    assert_eq!(hits[0].id, "dir/closure-ahead");
    assert!(
        hits[0].start_m > 1_400.0 && hits[0].start_m < 1_600.0,
        "{hits:?}"
    );
}

#[test]
fn a_closure_of_the_other_carriageway_is_not_on_the_route() {
    let guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = line(LIMOGES, 0);
    let mut reversed = points_between(&points, 1_500.0, 1_700.0);
    reversed.reverse();
    let other_way = shape("dir/other-way", reversed.clone(), true);
    let both_ways = shape("dir/both-ways", reversed, false);
    let hits = guidance.events_ahead(0.0, vec![other_way, both_ways], LINE_M, POINT_M);
    assert_eq!(
        hits.iter().map(|h| h.id.as_str()).collect::<Vec<_>>(),
        ["dir/both-ways"],
        "a directed line drawn the other way closes the opposite direction only"
    );
}

#[test]
fn a_closed_street_the_route_only_crosses_is_not_on_the_route() {
    let guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = line(LIMOGES, 0);
    // A street square to the route at its 2 km point, 120 m long.
    let middle = points_between(&points, 2_000.0, 2_030.0);
    let (a, b) = (middle[0], middle[middle.len() - 1]);
    let (dlat, dlon) = (b.lat - a.lat, b.lon - a.lon);
    let norm = (dlat * dlat + dlon * dlon).sqrt();
    let (plat, plon) = (-dlon / norm * 0.0006, dlat / norm * 0.0006);
    let crossing = shape(
        "city/crossing",
        vec![
            LatLon {
                lat: a.lat - plat,
                lon: a.lon - plon,
            },
            LatLon {
                lat: a.lat + plat,
                lon: a.lon + plon,
            },
        ],
        false,
    );
    let hits = guidance.events_ahead(0.0, vec![crossing], LINE_M, POINT_M);
    assert!(hits.is_empty(), "a crossing is not a following: {hits:?}");
}

#[test]
fn a_point_event_counts_within_fifteen_metres_of_the_route_ahead() {
    let guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = line(LIMOGES, 0);
    let at = points_between(&points, 2_500.0, 2_510.0)[0];
    // 0.0001 degrees of latitude: 11 m; 0.0003: 33 m.
    let near = shape(
        "dialog/near",
        vec![LatLon {
            lat: at.lat + 0.0001,
            lon: at.lon,
        }],
        false,
    );
    let far = shape(
        "dialog/far",
        vec![LatLon {
            lat: at.lat + 0.0003,
            lon: at.lon,
        }],
        false,
    );
    let hits = guidance.events_ahead(100.0, vec![near, far], LINE_M, POINT_M);
    assert_eq!(
        hits.iter().map(|h| h.id.as_str()).collect::<Vec<_>>(),
        ["dialog/near"]
    );
    assert!(
        (hits[0].start_m - 2_500.0).abs() < 80.0,
        "where the route passes it: {hits:?}"
    );
}

#[test]
fn a_point_event_of_the_other_direction_is_not_on_the_route() {
    let guidance =
        Guidance::new(LIMOGES.to_owned(), 0, GuidanceSettings::default()).expect("a route");
    let points = line(LIMOGES, 0);
    // Avenue des Benedictins, about 1 km in, runs east-north-east.
    let pair = points_between(&points, 1_000.0, 1_040.0);
    let (a, b) = (pair[0], pair[pair.len() - 1]);
    let course = (b.lon - a.lon)
        .mul_add(a.lat.to_radians().cos(), 0.0)
        .atan2(b.lat - a.lat)
        .to_degrees()
        .rem_euclid(360.0);
    let with = |id: &str, heading: f64, tolerance: f64| EventShape {
        heading_deg: Some(heading),
        heading_tolerance_deg: tolerance,
        ..shape(id, vec![a], false)
    };
    let hits = guidance.events_ahead(
        0.0,
        vec![
            with("report/same-way", course + 30.0, 60.0),
            with("report/other-way", course + 180.0, 60.0),
            with("dir/cardinal", course + 80.0, 100.0),
        ],
        LINE_M,
        POINT_M,
    );
    assert_eq!(
        hits.iter().map(|h| h.id.as_str()).collect::<Vec<_>>(),
        ["report/same-way", "dir/cardinal"],
        "{hits:?}"
    );
}
