//! The road event feeds read from recorded excerpts: the DIR's aggregate
//! of 2026-10-06 10:57 UTC and one of its increments (DATEX II 2.x),
//! DiaLog's temporary and permanent orders (DATEX II 3), the city datasets.
//! Each excerpt keeps the real records whole; DiaLog's geometries are cut
//! to their first points.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{DateTime, TimeZone, Utc};
use lunaway_db::road_events::NewEvent;
use lunaway_domain::{
    road_events::{
        AppliesTo, Carriageway, EndReason, EventClass, EventDirection, MatchQuality,
        SourceGeometry,
        schedule::{DAY, NIGHT, Zone},
    },
    routing::RestrictionKind,
};
use lunaway_ingest::road_events::{dialog, dir, local};

const DIR_CONTENT: &[u8] = include_bytes!("fixtures/road_events/dir_content_excerpt.xml");
const DIR_INCREMENT: &[u8] = include_bytes!("fixtures/road_events/dir_increment_end.xml");
const DIALOG_TEMPORARY: &[u8] = include_bytes!("fixtures/road_events/dialog_temporary_excerpt.xml");
const DIALOG_PERMANENT: &[u8] = include_bytes!("fixtures/road_events/dialog_permanent_excerpt.xml");
const PARIS_CLOSURES: &[u8] =
    include_bytes!("fixtures/road_events/paris_fermetures_excerpt.geojson");
const LYON_WORKS: &[u8] = include_bytes!("fixtures/road_events/lyon_chantiers_excerpt.geojson");
const CIFS: &[u8] = include_bytes!("fixtures/road_events/cd17_cifs_excerpt.json");

fn now() -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 10, 6, 11, 0, 0).unwrap()
}

fn dir_events() -> (dir::Publication, Vec<NewEvent>) {
    let p = dir::parse(DIR_CONTENT, now()).unwrap();
    let events = p.situations.iter().flat_map(|s| s.events.clone()).collect();
    (p, events)
}

fn find<'a>(events: &'a [NewEvent], id: &str) -> &'a NewEvent {
    events
        .iter()
        .find(|e| e.external_id == id)
        .unwrap_or_else(|| panic!("{id} not read"))
}

#[test]
fn the_dir_aggregate_reads_with_its_place_in_the_feed() {
    let (p, events) = dir_events();
    assert!(p.snapshot, "content.xml is the whole aggregate");
    assert_eq!(
        p.published_at.unwrap().to_rfc3339(),
        "2026-10-06T10:57:45.691+00:00"
    );
    assert_eq!(
        p.feed_number,
        Some(3_572_540),
        "increments from this number on are newer than the aggregate"
    );
    assert_eq!(p.situations.len(), 11);
    assert_eq!(
        events.len(),
        14,
        "a speed limit and a suspended record are left out"
    );
    assert!(
        events
            .iter()
            .all(|e| e.raw.contains("situationRecord") && e.raw.len() > 500),
        "every event keeps its record as it came"
    );
}

#[test]
fn a_slip_road_closure_is_kept_on_its_slip_road() {
    let (_, events) = dir_events();
    let exit = find(&events, "260113-001342-1");
    assert_eq!(exit.class, EventClass::Closure);
    assert_eq!(exit.carriageway, Carriageway::Exit);
    assert_eq!(
        exit.match_quality,
        MatchQuality::Ramp,
        "placed by the slip road rule, never on the main carriageway"
    );
    assert_eq!(exit.direction, EventDirection::North);
    assert_eq!(exit.road_number.as_deref(), Some("N118"));
    assert!(matches!(exit.geometry, SourceGeometry::Point(_)));
    let entry = find(&events, "260722-001668-1");
    assert_eq!(entry.carriageway, Carriageway::Entry);
    assert_eq!(entry.direction, EventDirection::West);
    assert_eq!(entry.road_number.as_deref(), Some("A13"));
}

#[test]
fn a_night_closure_takes_the_assumed_night_window() {
    let (_, events) = dir_events();
    let closed = find(&events, "260122-001799-2");
    assert_eq!(closed.class, EventClass::Closure);
    assert_eq!(closed.detail, "roadClosed");
    assert_eq!(closed.direction, EventDirection::Both);
    assert_eq!(
        closed.match_quality,
        MatchQuality::Pending,
        "a section waits for the matcher"
    );
    let SourceGeometry::Lines(lines) = &closed.geometry else {
        panic!("a section is a line");
    };
    assert_eq!(lines[0].len(), 2, "the DIR gives a section's two ends");
    assert!(closed.schedule.assumed, "hours chosen here are flagged");
    assert_eq!(
        (
            closed.schedule.windows[0].start_min,
            closed.schedule.windows[0].end_min
        ),
        NIGHT
    );
    let day = find(&events, "260827-000863-102");
    assert_eq!(
        (
            day.schedule.windows[0].start_min,
            day.schedule.windows[0].end_min
        ),
        DAY
    );
    assert!(
        day.schedule.exceptions.is_empty()
            && day
                .schedule
                .label
                .as_deref()
                .unwrap()
                .contains("sauf week-end"),
        "a named weekend exception is told, never applied: a Saturday closure is not missed"
    );
    let works = find(&events, "260928-001439-1");
    assert_eq!(
        works.schedule.exceptions.len(),
        1,
        "a dated exception period is applied"
    );
}

#[test]
fn records_the_route_must_know_and_their_end() {
    let (p, events) = dir_events();
    let lanes = find(&events, "251022-000640-1");
    assert_eq!(lanes.class, EventClass::LaneRestriction);
    assert_eq!(lanes.direction, EventDirection::Forward);
    assert_eq!(
        lanes.ended,
        Some(EndReason::PastEnd),
        "an aggregate still carries records ended long ago"
    );
    let weight = find(&events, "230814-001797-1");
    assert_eq!(weight.class, EventClass::VehicleLimit);
    assert_eq!(weight.limits.max_weight_t, Some(48.0));
    assert_eq!(
        weight.limits.applies_to,
        AppliesTo::GoodsVehicles,
        "a lorry limit concerns goods vehicles"
    );
    assert_eq!(weight.match_quality, MatchQuality::Point);
    let ended = find(&events, "260927-005546-103");
    assert_eq!(ended.ended, Some(EndReason::SourceEnd));
    assert!(
        p.situations
            .iter()
            .any(|s| s.ended == ["260927-005546-103"])
    );
    assert_eq!(p.skipped.get("suspended"), Some(&1));
    assert!(
        !events.iter().any(|e| e.external_id == "261002-001576-1"),
        "a speed limit on every lane is not a closure"
    );
    assert!(
        p.situations
            .iter()
            .any(|s| s.id == "261005-002919" && s.events.is_empty() && s.record_ids.is_empty()),
        "a suspended record is not present: a stored version of it ends"
    );
}

#[test]
fn a_dir_increment_ends_its_record() {
    let p = dir::parse(DIR_INCREMENT, now()).unwrap();
    assert!(!p.snapshot, "an increment updates a situation");
    assert_eq!(
        p.published_at.unwrap().to_rfc3339(),
        "2026-10-06T11:13:04.904+00:00"
    );
    assert_eq!(p.situations.len(), 1);
    assert_eq!(p.situations[0].id, "261006-000777");
    assert_eq!(
        p.situations[0].ended,
        ["261006-000777-102"],
        "the end marker is read even for a record that is not kept"
    );
}

#[test]
fn dialog_temporary_orders_become_closures_limits_and_lane_restrictions() {
    let p = dialog::parse_temporary(DIALOG_TEMPORARY, now()).unwrap();
    assert_eq!(p.orders, 7);
    assert_eq!(p.events.len(), 6);
    assert_eq!(p.skipped.get("speed, parking or overtaking rule"), Some(&1));
    let lorries = p
        .events
        .iter()
        .find(|e| e.road_name.as_deref() == Some("Rue de Jarménil"))
        .unwrap();
    assert_eq!(lorries.class, EventClass::VehicleLimit);
    assert_eq!(lorries.limits.max_weight_t, Some(3.5));
    assert_eq!(
        lorries.limits.applies_to,
        AppliesTo::GoodsVehicles,
        "DiaLog's weights name heavy goods vehicles: a motorhome is told, not stopped"
    );
    let height = p
        .events
        .iter()
        .find(|e| e.limits.max_height_m.is_some())
        .unwrap();
    assert_eq!(
        height.limits.max_height_m,
        Some(3.2),
        "the figure is the maximum allowed (see dialog.rs)"
    );
    assert_eq!(height.limits.applies_to, AppliesTo::All);
    assert_eq!(
        height.match_quality,
        MatchQuality::Unmatched,
        "a point standing for a section warns"
    );
    let night = p
        .events
        .iter()
        .find(|e| !e.schedule.windows.is_empty())
        .unwrap();
    assert_eq!(night.class, EventClass::Closure);
    assert_eq!(night.schedule.zone, Zone::Utc);
    assert_eq!(
        night.schedule.widen_min, 60,
        "an hour of doubt on DiaLog's UTC hours"
    );
    assert_eq!(
        (
            night.schedule.windows[0].start_min,
            night.schedule.windows[0].end_min
        ),
        (19 * 60, 4 * 60)
    );
    assert_eq!(
        p.events
            .iter()
            .filter(|e| e.class == EventClass::LaneRestriction)
            .count(),
        2
    );
    assert!(p.events.iter().all(|e| {
        e.url
            .as_deref()
            .is_some_and(|u| u.starts_with("https://dialog.beta.gouv.fr/"))
    }));
}

#[test]
fn dialog_permanent_limits_join_the_static_restrictions() {
    let p = dialog::parse_permanent(DIALOG_PERMANENT, now()).unwrap();
    let kinds: Vec<(RestrictionKind, Option<f64>)> =
        p.records.iter().map(|(r, _)| (r.kind, r.limit)).collect();
    assert_eq!(
        kinds,
        [
            (RestrictionKind::MaxHeight, Some(1.9)),
            (RestrictionKind::MaxWidth, Some(4.45)),
            (RestrictionKind::MaxLength, Some(5.0)),
            (RestrictionKind::MaxWeightGoods, Some(3.5)),
            (RestrictionKind::MaxWeightGoods, Some(3.5)),
        ]
    );
    assert!(
        p.records
            .iter()
            .all(|(r, points)| r.external_id.starts_with("dialog/") && !points.is_empty())
    );
}

#[test]
fn paris_closures_take_the_widest_of_their_two_times() {
    let p = local::parse_geojson(
        "paris-fermetures",
        local::Format::ParisClosures,
        PARIS_CLOSURES,
        now(),
    )
    .unwrap();
    assert_eq!(
        p.skipped.get("finished"),
        Some(&1),
        "a finished closure is left out"
    );
    let ramp = p
        .events
        .iter()
        .find(|e| e.carriageway == Carriageway::Ramps)
        .unwrap();
    assert_eq!(ramp.class, EventClass::Closure);
    assert_eq!(
        ramp.match_quality,
        MatchQuality::Pending,
        "a drawn ramp is matched as a line"
    );
    for e in &p.events {
        assert!(e.valid_to.unwrap() > e.valid_from);
    }
}

#[test]
fn lyon_works_are_areas_that_warn() {
    let p = local::parse_geojson("lyon", local::Format::LyonWorks, LYON_WORKS, now()).unwrap();
    assert!(!p.events.is_empty());
    assert!(
        p.events
            .iter()
            .all(|e| e.match_quality == MatchQuality::Unmatched
                && matches!(e.geometry, SourceGeometry::Polygons(_)))
    );
    assert!(p.events.iter().any(|e| e.class == EventClass::Closure));
}

#[test]
fn a_cifs_feed_gives_its_closed_roads() {
    let p = local::parse_cifs("charente-maritime", CIFS, now()).unwrap();
    assert_eq!(
        p.skipped.get("not a closure"),
        Some(&1),
        "a hazard is not a closure"
    );
    let e = &p.events[0];
    assert_eq!(e.class, EventClass::Closure);
    let SourceGeometry::Lines(lines) = &e.geometry else {
        panic!("a CIFS polyline is a line");
    };
    assert!(
        (lines[0][0].lat() - 46.175_762).abs() < 1e-6,
        "CIFS pairs are latitude then longitude"
    );
}

/// Times the readers on whole feeds cached by a poll, when asked
/// (`ROAD_EVENTS_CACHE=<data/raw> cargo nextest run ... --run-ignored only`).
#[test]
#[ignore = "reads the whole feeds of a local cache"]
fn whole_feeds_read_in_time() {
    let Ok(root) = std::env::var("ROAD_EVENTS_CACHE") else {
        return;
    };
    let read = |p: &str| std::fs::read(format!("{root}/road-events/{p}")).unwrap();
    let dir_body = read("dir/content.xml");
    let t = std::time::Instant::now();
    let p = dir::parse(&dir_body, now()).unwrap();
    println!(
        "DIR aggregate: {} bytes, {} situations, {} events, {:?}",
        dir_body.len(),
        p.situations.len(),
        p.situations.iter().map(|s| s.events.len()).sum::<usize>(),
        t.elapsed()
    );
    let dialog_body = read("dialog/temporary.xml");
    let t = std::time::Instant::now();
    let d = dialog::parse_temporary(&dialog_body, now()).unwrap();
    println!(
        "DiaLog temporary: {} bytes, {} orders, {} events, {:?}",
        dialog_body.len(),
        d.orders,
        d.events.len(),
        t.elapsed()
    );
    let gz = read("dialog/permanent.xml.gz");
    let mut body = Vec::new();
    std::io::Read::read_to_end(&mut flate2::read::GzDecoder::new(&gz[..]), &mut body).unwrap();
    let t = std::time::Instant::now();
    let pm = dialog::parse_permanent(&body, now()).unwrap();
    println!(
        "DiaLog permanent: {} bytes, {} orders, {} restrictions, {:?}",
        body.len(),
        pm.orders,
        pm.records.len(),
        t.elapsed()
    );
}
