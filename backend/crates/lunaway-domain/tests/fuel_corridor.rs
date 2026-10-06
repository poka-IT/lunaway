//! The corridor of a real route: Limoges to Brive by the A20, 93.7 km, as
//! Valhalla 3.9.0 drew it on the France graph of 2026-10-06 (asked of
//! Lunaway's API that day), against the 80 stations of the fuel feed within
//! 15 km of it (export of 2026-10-06 13:24 UTC). The grid of the corridor
//! must find exactly the stations a scan of every segment finds.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_domain::{
    Position,
    fuel::{ANCHOR_REACH_M, Corridor},
    routing::polyline,
};

const ROUTE: &str = include_str!("fixtures/route_limoges_brive.polyline6");
const FEED: &str = include_str!("../../lunaway-ingest/tests/fixtures/fuel_export_a20_sample.json");

fn stations() -> Vec<(i64, Position)> {
    let rows: Vec<serde_json::Value> = serde_json::from_str(FEED).unwrap();
    rows.iter()
        .map(|r| {
            let deg = |k: &str| r[k].as_str().unwrap().parse::<f64>().unwrap() / 100_000.0;
            (
                r["id"].as_i64().unwrap(),
                Position::new(deg("latitude"), deg("longitude")).unwrap(),
            )
        })
        .collect()
}

/// The distance from `p` to the nearest segment of `line`, and how far
/// along the line that point is, by a scan of every segment.
fn scan(line: &[Position], along: &[f64], p: Position) -> (f64, f64) {
    let k = 111_195.0;
    let cos = p.lat().to_radians().cos();
    let mut best = (f64::INFINITY, 0.0);
    for i in 0..line.len() - 1 {
        let (a, b) = (line[i], line[i + 1]);
        let (ax, ay) = ((a.lon() - p.lon()) * k * cos, (a.lat() - p.lat()) * k);
        let (bx, by) = ((b.lon() - p.lon()) * k * cos, (b.lat() - p.lat()) * k);
        let (dx, dy) = (bx - ax, by - ay);
        let len2 = dx * dx + dy * dy;
        let t = if len2 > 0.0 {
            (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let d = (ax + t * dx).hypot(ay + t * dy);
        if d < best.0 {
            best = (d, along[i] + t * (along[i + 1] - along[i]));
        }
    }
    best
}

#[test]
fn the_corridor_finds_the_stations_a_full_scan_finds() {
    let line = polyline::decode(ROUTE.trim()).unwrap();
    assert_eq!(line.len(), 1_661);
    let stations = stations();
    assert_eq!(stations.len(), 80);
    // Counted by the same scan in Python, the day the stations were chosen.
    for (half_width_m, expected) in [
        (250.0, 3),
        (1_000.0, 11),
        (2_500.0, 34),
        (6_000.0, 52),
        (15_000.0, 80),
    ] {
        let corridor = Corridor::new(line.clone(), half_width_m).unwrap();
        let along = corridor.line().along();
        let mut inside = 0;
        for (id, p) in &stations {
            let (d, s) = scan(&line, along, *p);
            match corridor.locate(*p) {
                Some(found) => {
                    inside += 1;
                    assert!(d <= half_width_m, "{id} is {d:.0} m away");
                    assert!((found.offset_m - d).abs() < 0.01, "{id}");
                    assert!((found.along_m - s).abs() < 0.01, "{id}");
                }
                None => assert!(d > half_width_m, "{id} at {d:.0} m was missed"),
            }
        }
        assert_eq!(inside, expected, "{half_width_m} m each side");
    }
}

#[test]
fn a_motorway_station_is_reached_from_the_route_on_either_side() {
    let line = polyline::decode(ROUTE.trim()).unwrap();
    let corridor = Corridor::new(line, 2_500.0).unwrap();
    // Masseret, the Porte de Corrèze service area of the A20.
    let masseret = stations()
        .into_iter()
        .find(|(id, _)| *id == 19_510_002)
        .unwrap()
        .1;
    let found = corridor.locate(masseret).unwrap();
    assert!(found.offset_m < 1_000.0, "{found:?}");
    let length = corridor.line().length_m();
    assert!((93_000.0..94_500.0).contains(&length), "{length}");
    let (before, after) = corridor.anchors(found.along_m);
    assert!((found.along_m - before.along_m - ANCHOR_REACH_M).abs() < 1.0);
    assert!((after.along_m - found.along_m - ANCHOR_REACH_M).abs() < 1.0);
    // The A20 runs south from Limoges to Brive.
    assert!(
        (90.0..270.0).contains(&before.heading_deg),
        "{}",
        before.heading_deg
    );
    assert!(before.at.lat() > after.at.lat());
}
