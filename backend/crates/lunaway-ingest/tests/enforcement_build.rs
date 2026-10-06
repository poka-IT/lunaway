//! What the build makes of the stored cameras, country by country, with a
//! routing engine that answers along a straight road: zones in France with
//! no camera's point in them, points in Poland, nothing in a country that is
//! off; an unchanged camera is not built again, and a build that would
//! retire most items retires none.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    collections::HashMap,
    sync::atomic::{AtomicUsize, Ordering},
};

use chrono::Utc;
use lunaway_db::enforcement::{self as db, NewDevice};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, DeviceKind, ZONE_CLEAR_M},
    routing::{RouteLine, polyline},
};
use lunaway_ingest::{
    IngestError,
    cameras::{CameraList, store},
    enforcement::{BuildReport, Merged, build},
    road_events::matching::{Engine, MatchError},
};
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

const FRANCE: &[u8] = include_bytes!("fixtures/securite_routiere_radars_sample.json");
const POLAND: &[u8] = include_bytes!("fixtures/pl_canard_sample.csv");
const SECRET: &[u8] = b"a test secret of the zone builder";

/// How the fake engine answers.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Answer {
    /// Along a straight road through the locations.
    Straight,
    /// No route anywhere.
    Nothing,
    /// Not reachable.
    Down,
}

struct Fake {
    answer: Answer,
    calls: AtomicUsize,
}

impl Fake {
    fn new(answer: Answer) -> Self {
        Self {
            answer,
            calls: AtomicUsize::new(0),
        }
    }
}

impl Engine for Fake {
    async fn route(&self, body: &Value) -> Result<Option<Value>, MatchError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        match self.answer {
            Answer::Nothing => return Ok(None),
            Answer::Down => return Err(MatchError::NotLoopback("down".into())),
            Answer::Straight => {}
        }
        let points: Vec<Position> = body["locations"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| Position::new(l["lat"].as_f64().unwrap(), l["lon"].as_f64().unwrap()).unwrap())
            .collect();
        let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        Ok(Some(json!({
            "code": "Ok",
            "routes": [{
                "geometry": polyline::encode(&points),
                "distance": distance,
                "legs": [{"steps": [{"distance": distance, "intersections": [{"classes": []}]}]}],
            }],
        })))
    }
}

fn device(id: &str, kind: DeviceKind, lat: f64, lon: f64) -> Device {
    Device {
        external_id: id.to_owned(),
        kind,
        position: Position::new(lat, lon).unwrap(),
        bearing_deg: None,
        limit_kmh: None,
        road: None,
        section_end: None,
        section_length_m: None,
    }
}

/// The French and Polish lists, and four OpenStreetMap nodes: one on a
/// French camera with its direction and limit, one in France away from
/// any, one in Germany, one in Morocco.
async fn seed(pool: &PgPool) -> Device {
    let now = Utc::now();
    let france = CameraList::France.parse(FRANCE).unwrap();
    store(pool, CameraList::France, &france, now).await.unwrap();
    let poland = CameraList::Poland.parse(POLAND).unwrap();
    store(pool, CameraList::Poland, &poland, now).await.unwrap();
    let official = &france
        .devices
        .iter()
        .find(|l| l.device.kind == DeviceKind::Fixed)
        .unwrap()
        .device;
    let mut on_it = device(
        "node/1",
        DeviceKind::Fixed,
        official.position.lat() + 0.000_2,
        official.position.lon(),
    );
    on_it.bearing_deg = Some(90.0);
    on_it.limit_kmh = Some(130);
    let stray = device("node/2", DeviceKind::Fixed, 47.0, 2.0);
    let german = device("node/3", DeviceKind::Fixed, 52.52, 13.405);
    let moroccan = device("node/4", DeviceKind::Fixed, 34.02, -6.84);
    let raw = json!({});
    let rows = [
        (&on_it, "FR"),
        (&stray, "FR"),
        (&german, "DE"),
        (&moroccan, "MA"),
    ];
    let rows: Vec<NewDevice<'_>> = rows
        .iter()
        .map(|(d, c)| NewDevice {
            device: d,
            country: c,
            raw: &raw,
        })
        .collect();
    db::upsert_devices(pool, &SourceId::OSM, &rows, now)
        .await
        .unwrap();
    official.clone()
}

/// Every live item: its device key, kind, category, line and point.
async fn items(pool: &PgPool) -> HashMap<String, db::FeedItem> {
    let keys: Vec<(Uuid, String)> = sqlx::query_as("SELECT id, device_key FROM enforcement_items")
        .fetch_all(pool)
        .await
        .unwrap();
    let feed = db::changed_since(pool, 0, i64::MAX, 100_000, false, None)
        .await
        .unwrap();
    keys.into_iter()
        .filter_map(|(id, key)| feed.iter().find(|f| f.id == id).map(|f| (key, f.clone())))
        .collect()
}

async fn devices(pool: &PgPool) -> HashMap<String, Device> {
    db::live_devices(pool)
        .await
        .unwrap()
        .into_iter()
        .map(|d| (d.key(), d.device))
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn france_gets_zones_without_a_point_poland_points_and_morocco_nothing(pool: PgPool) {
    let enriched = seed(&pool).await;
    let engine = Fake::new(Answer::Straight);
    let report = build(&pool, &engine, SECRET, false).await.unwrap();
    assert_eq!(
        report.merged,
        Merged {
            matched: 1,
            left_out: 1,
            alone: 2
        },
        "a French node without an official camera stays out"
    );
    assert_eq!(report.off, 1, "Morocco is off");
    assert_eq!(report.points, 21, "Poland's 20 and Germany's node");
    assert_eq!(report.zones + report.unplaced, 90);
    assert!(report.unplaced <= 2, "{report:?}");
    let built = items(&pool).await;
    let cameras = devices(&pool).await;
    let mut zones = 0;
    for (key, item) in &built {
        assert_ne!(item.country, "CH");
        let camera = &cameras[key];
        if item.country == "FR" {
            zones += 1;
            assert_eq!(item.kind, "zone", "{key}");
            assert!(item.point.is_none() && item.bearing_deg.is_none() && item.limit_kmh.is_none());
            let line = item.line.clone().unwrap();
            assert!(
                line.iter()
                    .all(|v| v.distance_m(camera.position) > ZONE_CLEAR_M),
                "{key}: no vertex of the zone gives the camera's place"
            );
            let road = RouteLine::new(line).unwrap();
            let at = road
                .project(camera.position, 1.0)
                .unwrap_or_else(|| panic!("{key}: the zone runs past its camera"));
            let expected = if camera.position == enriched.position {
                4_000.0
            } else {
                2_000.0
            };
            assert!(
                (road.length_m() - expected).abs() < 5.0,
                "{key}: {} m",
                road.length_m()
            );
            let share = at.along_m / road.length_m();
            assert!(
                (0.149..=0.851).contains(&share),
                "{key}: the camera never sits near an end ({share})"
            );
            let category = match camera.kind {
                DeviceKind::Fixed => "fixed",
                DeviceKind::RedLight | DeviceKind::LevelCrossing => "red_light",
                DeviceKind::Section => "section_control",
            };
            assert_eq!(item.category, category, "{key}");
        } else {
            assert_eq!(item.kind, "camera", "{key}");
            assert_eq!(item.point, Some(camera.position), "{key}");
            assert_eq!(item.category, camera.kind.code());
        }
    }
    assert_eq!(zones, report.zones);
    let osm_on_french = built
        .values()
        .find(|i| i.source_ids == ["securite-routiere", "osm"])
        .expect("the node completed its official camera");
    assert_eq!(osm_on_french.kind, "zone");
    assert!(
        built.contains_key("osm/node/3"),
        "Germany: points, off while driving"
    );
    assert!(!built.contains_key("osm/node/4"), "Morocco: nothing");
    let section = &built["pl-canard/CAN.O.1.012"];
    assert_eq!(
        section.line.as_ref().map(Vec::len),
        Some(2),
        "a section's road from its start to its end"
    );

    // Nothing changed: nothing built, no engine call.
    let calls = engine.calls.load(Ordering::SeqCst);
    let again = build(&pool, &engine, SECRET, false).await.unwrap();
    assert_eq!(again.written, 0);
    assert_eq!(again.unchanged, report.zones + report.points);
    assert_eq!(engine.calls.load(Ordering::SeqCst), calls);
    let head = db::feed_head(&pool).await.unwrap();

    // A camera gone from the Polish list: its item goes, as a tombstone.
    let mut poland = CameraList::Poland.parse(POLAND).unwrap();
    poland
        .devices
        .retain(|l| l.device.external_id != "CAN.O.1.012");
    store(&pool, CameraList::Poland, &poland, Utc::now())
        .await
        .unwrap();
    let after = build(&pool, &engine, SECRET, false).await.unwrap();
    assert_eq!((after.written, after.retired), (0, 1));
    let changes = db::changed_since(&pool, head.revision, i64::MAX, 100, true, None)
        .await
        .unwrap();
    assert_eq!(changes.len(), 1);
    assert!(changes[0].deleted);
    assert_eq!(changes[0].id, section.id);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_build_that_would_drop_most_zones_retires_none(pool: PgPool) {
    seed(&pool).await;
    let first = build(&pool, &Fake::new(Answer::Straight), SECRET, false)
        .await
        .unwrap();
    let live = items(&pool).await.len();
    // A graph on which no zone is found: every zone would go.
    let report: BuildReport = build(&pool, &Fake::new(Answer::Nothing), SECRET, true)
        .await
        .unwrap();
    assert_eq!(report.zones, 0);
    assert_eq!(report.unplaced, first.zones + first.unplaced);
    assert!(report.retire_refused);
    assert_eq!(report.retired, 0);
    assert_eq!(items(&pool).await.len(), live, "every zone stays served");

    // An engine that does not answer: the build stops and writes nothing.
    let head = db::feed_head(&pool).await.unwrap();
    let down = build(&pool, &Fake::new(Answer::Down), SECRET, true).await;
    assert!(matches!(down, Err(IngestError::Engine(_))), "{down:?}");
    assert_eq!(db::feed_head(&pool).await.unwrap(), head);
}
