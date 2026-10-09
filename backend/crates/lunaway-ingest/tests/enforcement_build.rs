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
use lunaway_db::enforcement::{self as db, ItemKind, NewDevice, Variant};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, DeviceKind, OptIns, ZONE_STEP_M},
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
    /// Along a straight road, its first 900 m on the A 20, the rest on an
    /// off ramp: every route leaves the camera's road.
    Ramp,
    /// Along a straight road one may drive eastward only: no route toward
    /// the west.
    EastOnly,
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
            Answer::Straight | Answer::Ramp | Answer::EastOnly => {}
        }
        let points: Vec<Position> = body["locations"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| Position::new(l["lat"].as_f64().unwrap(), l["lon"].as_f64().unwrap()).unwrap())
            .collect();
        if self.answer == Answer::EastOnly
            && let (Some(a), Some(b)) = (points.first(), points.last())
            && b.lon() < a.lon() - 1e-6
        {
            return Ok(None);
        }
        let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        let steps = if self.answer == Answer::Ramp {
            let named = distance.min(900.0);
            json!([
                {"distance": named, "name": "Autoroute", "ref": "A 20",
                 "maneuver": {"type": "depart"}, "intersections": [{"classes": []}]},
                {"distance": distance - named, "name": "", "maneuver": {"type": "off ramp"}},
                {"distance": 0.0, "name": "", "maneuver": {"type": "arrive"}}
            ])
        } else {
            json!([{"distance": distance, "intersections": [{"classes": []}]}])
        };
        Ok(Some(json!({
            "code": "Ok",
            "routes": [{
                "geometry": polyline::encode(&points),
                "distance": distance,
                "legs": [{"steps": steps}],
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
        zone_line: None,
    }
}

/// The French and Polish lists, and four OpenStreetMap nodes: one on a
/// French camera with its direction and limit, one in France away from
/// any, one in Germany, one in Morocco.
async fn seed(pool: &PgPool) -> Device {
    let now = Utc::now();
    let france = CameraList::France.parse(FRANCE).unwrap();
    store(pool, CameraList::France, &france, now, None)
        .await
        .unwrap();
    let poland = CameraList::Poland.parse(POLAND).unwrap();
    store(pool, CameraList::Poland, &poland, now, None)
        .await
        .unwrap();
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
            scope: c,
            raw: &raw,
        })
        .collect();
    db::upsert_devices(pool, &SourceId::OSM, &rows, now)
        .await
        .unwrap();
    official.clone()
}

/// Every live item a client without any choice gets, by device key.
async fn items(pool: &PgPool) -> HashMap<String, db::FeedItem> {
    items_for(pool, &[]).await
}

/// Every live item a client that made the choices `chosen` gets, by device
/// key.
async fn items_for(pool: &PgPool, chosen: &[&str]) -> HashMap<String, db::FeedItem> {
    let keys: Vec<(Uuid, String)> = sqlx::query_as("SELECT id, device_key FROM enforcement_items")
        .fetch_all(pool)
        .await
        .unwrap();
    let chosen = OptIns::new(chosen.iter().copied());
    let feed = db::changed_since(pool, 0, i64::MAX, 100_000, false, None, &chosen)
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
    let report = build(&pool, &engine, SECRET, false, false).await.unwrap();
    assert_eq!(
        report.merged,
        Merged {
            matched: 1,
            left_out: 1,
            alone: 2,
            ..Merged::default()
        },
        "a French node without an official camera stays out"
    );
    assert_eq!(
        report.points - report.opt_in,
        21,
        "Poland's 20 and Germany's node, for every client"
    );
    // Morocco is off, and so is a French camera within a kilometre of a
    // country the table does not name (Monaco, Andorra); one within a
    // kilometre of Switzerland was not even stored.
    let french = db::live_count(&pool, &SourceId::SECURITE_ROUTIERE)
        .await
        .unwrap();
    assert_eq!(
        i64::try_from(report.zones + report.unplaced + report.off - 1).unwrap(),
        french,
        "{report:?}"
    );
    assert!(report.unplaced <= 2, "{report:?}");
    let built = items(&pool).await;
    let cameras = devices(&pool).await;
    let mut zones = 0;
    for (key, item) in &built {
        assert_ne!(item.country, "CH");
        let camera = &cameras[key];
        if item.country == "FR" {
            zones += 1;
            assert_eq!(item.kind, ItemKind::Zone, "{key}");
            assert!(item.point.is_none() && item.bearing_deg.is_none() && item.limit_kmh.is_none());
            let line = item.line.clone().unwrap();
            let steps: Vec<f64> = line.windows(2).map(|w| w[0].distance_m(w[1])).collect();
            assert!(
                steps[..steps.len() - 1]
                    .iter()
                    .all(|d| (d - ZONE_STEP_M).abs() < 0.5),
                "{key}: drawn at even steps, no vertex of the road kept"
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
            assert_eq!(
                item.category, "danger_zone",
                "{key}: a zone never carries the kind of its camera"
            );
        } else {
            assert_eq!(item.kind, ItemKind::Camera, "{key}");
            assert_eq!(item.point, Some(camera.position), "{key}");
            assert_eq!(item.category, camera.kind.code());
        }
    }
    assert_eq!(zones, report.zones);
    let osm_on_french = built
        .values()
        .find(|i| i.source_ids == ["securite-routiere", "osm"])
        .expect("the node completed its official camera");
    assert_eq!(osm_on_french.kind, ItemKind::Zone);
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

    assert!(
        built.values().all(|i| i.variant != Variant::OptIn),
        "the feed leaves the points of a choice out for a client that did not make it"
    );
    // The same cameras for a client that chose France's positions: a point
    // for each French camera, placed as a zone or not, and no French zone;
    // the other countries' items are the same for every client.
    let chosen = items_for(&pool, &["FR"]).await;
    let mut french_points = 0;
    for (key, item) in &chosen {
        let camera = &cameras[key];
        if item.country == "FR" {
            french_points += 1;
            assert_eq!(item.kind, ItemKind::Camera, "{key}: a point once asked");
            assert_eq!(item.variant, Variant::OptIn, "{key}");
            assert_eq!(item.point, Some(camera.position), "{key}");
            assert_eq!(item.category, camera.kind.code(), "{key}");
            assert_ne!(
                Some(item.id),
                built.get(key).map(|z| z.id),
                "{key}: nothing ties the point's id to the zone's"
            );
        } else {
            assert_eq!(
                Some(item),
                built.get(key),
                "{key}: one item for every client"
            );
        }
    }
    assert_eq!(french_points, report.opt_in);
    assert_eq!(
        report.opt_in,
        report.zones + report.unplaced,
        "a point for every French camera that is not off, its zone placed or not"
    );
    let enriched_point = chosen
        .values()
        .find(|i| i.source_ids == ["securite-routiere", "osm"])
        .expect("the point of the camera OpenStreetMap completed");
    assert_eq!(
        (enriched_point.bearing_deg, enriched_point.limit_kmh),
        (Some(90.0), Some(130)),
        "the point carries the direction and the limit OpenStreetMap gave it"
    );

    // Nothing changed: nothing built, no engine call.
    let calls = engine.calls.load(Ordering::SeqCst);
    let again = build(&pool, &engine, SECRET, false, false).await.unwrap();
    assert_eq!(again.written, 0);
    assert_eq!(again.unchanged, report.zones + report.points);
    assert_eq!(engine.calls.load(Ordering::SeqCst), calls);
    let head = db::feed_head(&pool).await.unwrap();

    // A camera gone from the Polish list: its item goes, as a tombstone.
    let mut poland = CameraList::Poland.parse(POLAND).unwrap();
    poland
        .devices
        .retain(|l| l.device.external_id != "CAN.O.1.012");
    store(&pool, CameraList::Poland, &poland, Utc::now(), None)
        .await
        .unwrap();
    let after = build(&pool, &engine, SECRET, false, false).await.unwrap();
    assert_eq!((after.written, after.retired), (0, 1));
    let changes = db::changed_since(
        &pool,
        head.revision,
        i64::MAX,
        100,
        true,
        None,
        &OptIns::default(),
    )
    .await
    .unwrap();
    assert_eq!(changes.len(), 1);
    assert!(changes[0].deleted);
    assert_eq!(changes[0].id, section.id);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_build_that_would_drop_most_zones_retires_none(pool: PgPool) {
    seed(&pool).await;
    let first = build(&pool, &Fake::new(Answer::Straight), SECRET, false, false)
        .await
        .unwrap();
    let live = items(&pool).await.len();
    // A graph on which no zone is found: every zone would go.
    let report: BuildReport = build(&pool, &Fake::new(Answer::Nothing), SECRET, true, false)
        .await
        .unwrap();
    assert_eq!(report.zones, 0);
    assert_eq!(report.unplaced, first.zones + first.unplaced);
    assert!(report.retire_refused);
    assert_eq!(report.retired, 0);
    assert_eq!(items(&pool).await.len(), live, "every zone stays served");

    // An engine that does not answer: the build stops and writes nothing.
    let head = db::feed_head(&pool).await.unwrap();
    let down = build(&pool, &Fake::new(Answer::Down), SECRET, true, false).await;
    assert!(matches!(down, Err(IngestError::Engine(_))), "{down:?}");
    assert_eq!(db::feed_head(&pool).await.unwrap(), head);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_zone_keeps_to_its_road_where_a_route_leaves_it(pool: PgPool) {
    // Five French cameras, and an engine whose every route leaves the A 20
    // by an off ramp after 900 m: each zone is drawn from several routes,
    // each kept on the A 20 only.
    let mut france = CameraList::France.parse(FRANCE).unwrap();
    france.devices.truncate(5);
    store(&pool, CameraList::France, &france, Utc::now(), None)
        .await
        .unwrap();
    let engine = Fake::new(Answer::Ramp);
    let report = build(&pool, &engine, SECRET, false, false).await.unwrap();
    assert_eq!(report.zones, 5, "{report:?}");
    assert!(
        engine.calls.load(Ordering::SeqCst) >= 3 * report.zones,
        "more than one route a side: {} calls",
        engine.calls.load(Ordering::SeqCst)
    );
    for item in items(&pool).await.values() {
        let road = RouteLine::new(item.line.clone().unwrap()).unwrap();
        assert!(
            (road.length_m() - 2_000.0).abs() < 5.0,
            "the whole length, from several routes: {} m",
            road.length_m()
        );
    }
}

/// An official camera without a direction, completed by an OpenStreetMap
/// node that gives it the wrong one (the way the camera faces, toward the
/// west, on a road driven eastward only): the zone is asked again without
/// the direction, which a zone does not carry. The first full build with
/// OpenStreetMap's cameras retired 217 French zones this way (2026-10-06).
#[sqlx::test(migrations = "../../migrations")]
async fn a_direction_that_leads_nowhere_does_not_cost_a_camera_its_zone(pool: PgPool) {
    let now = Utc::now();
    let france = CameraList::France.parse(FRANCE).unwrap();
    store(&pool, CameraList::France, &france, now, None)
        .await
        .unwrap();
    let official = &france
        .devices
        .iter()
        .find(|l| l.device.kind == DeviceKind::Fixed)
        .unwrap()
        .device;
    let mut facing = device(
        "node/9",
        DeviceKind::Fixed,
        official.position.lat() + 0.000_2,
        official.position.lon(),
    );
    facing.bearing_deg = Some(270.0);
    let raw = json!({});
    db::upsert_devices(
        &pool,
        &SourceId::OSM,
        &[NewDevice {
            device: &facing,
            country: "FR",
            scope: "FR",
            raw: &raw,
        }],
        now,
    )
    .await
    .unwrap();
    let key = format!("securite-routiere/{}", official.external_id);
    assert_eq!(
        devices(&pool).await[&key].bearing_deg,
        None,
        "the official list gives no direction"
    );
    build(&pool, &Fake::new(Answer::EastOnly), SECRET, true, true)
        .await
        .unwrap();
    let built = items(&pool).await;
    assert_eq!(
        built.get(&key).map(|i| i.kind),
        Some(ItemKind::Zone),
        "the camera keeps its zone though the direction OpenStreetMap gave it leads nowhere"
    );
}

async fn as_role(pool: &PgPool, set_role: &'static str) -> PgPool {
    sqlx::postgres::PgPoolOptions::new()
        .max_connections(2)
        .after_connect(move |conn, _| {
            Box::pin(async move {
                sqlx::query(set_role).execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap()
}

/// Every item row: its device key, variant, choices and kind, in order.
async fn rows(pool: &PgPool) -> Vec<(String, String, Option<Vec<String>>, String)> {
    sqlx::query_as(
        "SELECT device_key, variant, opt_in_countries, kind FROM enforcement_items
         WHERE deleted_at IS NULL ORDER BY device_key, variant",
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

/// Cameras by the borders, written and built with the import role: a
/// camera whose form depends on France's choice gets a zone for the
/// clients without it and a point for those with it; one by a country that
/// is off gets nothing for anyone; any other, one item for everyone.
#[sqlx::test(migrations = "../../migrations")]
async fn a_camera_whose_form_depends_on_france_s_choice_gets_both_forms(pool: PgPool) {
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let now = Utc::now();
    let raw = json!({});
    let official = [
        device("1001", DeviceKind::Fixed, 45.8336, 1.2611),
        device("1002", DeviceKind::Section, 45.70, 1.50),
        // Within a kilometre of Switzerland (the importer stores none such,
        // a row may still say it) and of Monaco: off. By Andorra, which
        // allows points: France's form.
        device("1003", DeviceKind::Fixed, 46.1453, 6.0808),
        device("1004", DeviceKind::Fixed, 43.7430, 7.4210),
        device("1005", DeviceKind::Fixed, 42.5440, 1.7440),
    ];
    db::upsert_devices(
        &ingest,
        &SourceId::SECURITE_ROUTIERE,
        &official
            .iter()
            .map(|d| NewDevice {
                device: d,
                country: "FR",
                scope: "FR",
                raw: &raw,
            })
            .collect::<Vec<_>>(),
        now,
    )
    .await
    .unwrap();
    let mut on_limousin = device("node/10", DeviceKind::Fixed, 45.833_8, 1.2611);
    on_limousin.bearing_deg = Some(90.0);
    on_limousin.limit_kmh = Some(80);
    let mut section_end = device("node/11", DeviceKind::Section, 45.700_2, 1.50);
    section_end.section_end = Some(Position::new(45.70, 1.53).unwrap());
    section_end.limit_kmh = Some(110);
    let osm = [
        (on_limousin, "FR"),
        (section_end, "FR"),
        // Spain at Irun, and in Llívia, its enclave in France: within a
        // kilometre of France.
        (device("node/12", DeviceKind::Fixed, 43.3399, -1.7808), "ES"),
        (device("node/13", DeviceKind::Fixed, 42.4637, 1.9814), "ES"),
        // Italy and Austria allow points; Portugal, zones without a choice.
        (device("node/14", DeviceKind::Fixed, 43.79, 7.608), "IT"),
        (device("node/15", DeviceKind::Fixed, 48.2082, 16.3738), "AT"),
        (device("node/16", DeviceKind::Fixed, 38.7223, -9.1393), "PT"),
    ];
    db::upsert_devices(
        &ingest,
        &SourceId::OSM,
        &osm.iter()
            .map(|(d, c)| NewDevice {
                device: d,
                country: c,
                scope: c,
                raw: &raw,
            })
            .collect::<Vec<_>>(),
        now,
    )
    .await
    .unwrap();

    let engine = Fake::new(Answer::Straight);
    let report = build(&ingest, &engine, SECRET, false, false).await.unwrap();
    assert_eq!(
        report.off, 2,
        "nothing by Switzerland or Monaco: {report:?}"
    );
    assert_eq!(report.unplaced, 0, "{report:?}");
    assert_eq!((report.zones, report.points, report.opt_in), (6, 7, 5));
    let fr = Some(vec!["FR".to_owned()]);
    let row = |key: &str, variant: &str, choices: &Option<Vec<String>>, kind: &str| {
        (
            key.to_owned(),
            variant.to_owned(),
            choices.clone(),
            kind.to_owned(),
        )
    };
    assert_eq!(
        rows(&pool).await,
        [
            row("osm/node/12", "default", &fr, "zone"),
            row("osm/node/12", "opt_in", &fr, "camera"),
            row("osm/node/13", "default", &fr, "zone"),
            row("osm/node/13", "opt_in", &fr, "camera"),
            row("osm/node/14", "all", &None, "camera"),
            row("osm/node/15", "all", &None, "camera"),
            row("osm/node/16", "all", &None, "zone"),
            row("securite-routiere/1001", "default", &fr, "zone"),
            row("securite-routiere/1001", "opt_in", &fr, "camera"),
            row("securite-routiere/1002", "default", &fr, "zone"),
            row("securite-routiere/1002", "opt_in", &fr, "camera"),
            row("securite-routiere/1005", "default", &fr, "zone"),
            row("securite-routiere/1005", "opt_in", &fr, "camera"),
        ]
    );

    let without = items(&pool).await;
    let with = items_for(&pool, &["FR"]).await;
    for key in [
        "securite-routiere/1001",
        "securite-routiere/1002",
        "securite-routiere/1005",
        "osm/node/12",
        "osm/node/13",
    ] {
        assert_eq!(
            without[key].kind,
            ItemKind::Zone,
            "{key} without the choice"
        );
        assert!(without[key].point.is_none(), "{key}");
        assert_eq!(
            with[key].kind,
            ItemKind::Camera,
            "{key} with France's choice"
        );
        assert_ne!(
            without[key].id, with[key].id,
            "{key}: two ids, nothing ties them"
        );
    }
    let limousin = &with["securite-routiere/1001"];
    assert_eq!(
        (
            limousin.category.as_str(),
            limousin.bearing_deg,
            limousin.limit_kmh
        ),
        ("fixed", Some(90.0), Some(80)),
        "the point with its kind, direction and limit"
    );
    let section = &with["securite-routiere/1002"];
    assert_eq!(section.category, "section");
    assert_eq!(section.limit_kmh, Some(110));
    let road = RouteLine::new(section.line.clone().expect("the section's road")).unwrap();
    assert!(
        (road.length_m()
            - Position::new(45.70, 1.50)
                .unwrap()
                .distance_m(Position::new(45.70, 1.53).unwrap()))
        .abs()
            < 5.0,
        "from its start to its end: {} m",
        road.length_m()
    );
    for key in ["osm/node/14", "osm/node/15", "osm/node/16"] {
        assert_eq!(without[key], with[key], "{key}: one item for every client");
    }
    assert_eq!(
        items_for(&pool, &["ES", "CH", "IT"]).await,
        without,
        "choices France does not take change nothing"
    );

    // Nothing changed: nothing built again, no engine call.
    let calls = engine.calls.load(Ordering::SeqCst);
    let again = build(&ingest, &engine, SECRET, false, false).await.unwrap();
    assert_eq!((again.written, again.unchanged), (0, 13), "{again:?}");
    assert_eq!(engine.calls.load(Ordering::SeqCst), calls);

    // The camera at Irun gone: both its items go.
    let head = db::feed_head(&pool).await.unwrap();
    db::retire_missing_in(
        &ingest,
        &SourceId::OSM,
        &["ES".to_owned()],
        &["node/13".to_owned()],
        Utc::now(),
    )
    .await
    .unwrap();
    let after = build(&ingest, &engine, SECRET, false, false).await.unwrap();
    assert_eq!((after.written, after.retired), (0, 2), "{after:?}");
    let gone = db::changed_since(
        &pool,
        head.revision,
        i64::MAX,
        100,
        true,
        None,
        &OptIns::default(),
    )
    .await
    .unwrap();
    let mut gone_ids: Vec<Uuid> = gone.iter().filter(|g| g.deleted).map(|g| g.id).collect();
    gone_ids.sort();
    let mut irun = vec![without["osm/node/12"].id, with["osm/node/12"].id];
    irun.sort();
    assert_eq!(gone_ids, irun);
}

/// The points of France's choice are a small share of the items: a build
/// that would retire many of them retires none, though they stay under a
/// tenth of all the items.
#[sqlx::test(migrations = "../../migrations")]
async fn the_guard_on_retirements_holds_for_each_side_of_the_choice(pool: PgPool) {
    seed(&pool).await;
    let spain: Vec<Device> = (0..200)
        .map(|i| {
            device(
                &format!("node/es{i}"),
                DeviceKind::Fixed,
                40.0 + f64::from(i) * 0.001,
                -3.7,
            )
        })
        .collect();
    let raw = json!({});
    db::upsert_devices(
        &pool,
        &SourceId::OSM,
        &spain
            .iter()
            .map(|d| NewDevice {
                device: d,
                country: "ES",
                scope: "ES",
                raw: &raw,
            })
            .collect::<Vec<_>>(),
        Utc::now(),
    )
    .await
    .unwrap();
    let engine = Fake::new(Answer::Straight);
    build(&pool, &engine, SECRET, false, false).await.unwrap();
    // Points of the choice no camera gives any more, as a rule changed or
    // a bug would leave them to retire.
    let stale: Vec<db::Item> = (0..25)
        .map(|i| db::Item {
            id: Uuid::now_v7(),
            device_key: format!("securite-routiere/gone-{i}"),
            variant: Variant::OptIn,
            opt_in_countries: OptIns::new(["FR"]),
            kind: ItemKind::Camera,
            category: "fixed".to_owned(),
            country: "FR".to_owned(),
            line: None,
            point: Some(Position::new(46.0, 2.0 + f64::from(i) * 0.01).unwrap()),
            bearing_deg: None,
            limit_kmh: None,
            source_ids: vec!["securite-routiere".to_owned()],
            content_hash: format!("stale {i}"),
        })
        .collect();
    db::write_items(&pool, &stale, &[]).await.unwrap();
    let live: i64 =
        sqlx::query_scalar("SELECT count(*) FROM enforcement_items WHERE deleted_at IS NULL")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(
        25 <= live / 10,
        "a guard on the whole would let these go ({live} items): the test needs it"
    );

    let refused = build(&pool, &engine, SECRET, false, false).await.unwrap();
    assert!(refused.retire_refused, "{refused:?}");
    assert_eq!(refused.retired, 0);
    let allowed = build(&pool, &engine, SECRET, false, true).await.unwrap();
    assert_eq!(allowed.retired, 25, "{allowed:?}");
}

/// The review of 2026-10-09 turns Italy's zones into points and Greece's
/// points into zones. Over items an earlier table built, on a graph that
/// places no zone: an Italian zone becomes its point in its own row, under
/// the same id, and is no retirement; the Greek points whose zones are not
/// placed would all go, which the guard refuses without `allow_retire`.
#[sqlx::test(migrations = "../../migrations")]
async fn the_review_of_the_rules_retires_only_what_it_cannot_build(pool: PgPool) {
    let now = Utc::now();
    let raw = json!({});
    let italian = device("node/it1", DeviceKind::Fixed, 43.79, 7.608);
    let greek: Vec<Device> = (0..30)
        .map(|i| {
            device(
                &format!("node/gr{i}"),
                DeviceKind::Fixed,
                37.98 + f64::from(i) * 0.001,
                23.72,
            )
        })
        .collect();
    let mut rows = vec![NewDevice {
        device: &italian,
        country: "IT",
        scope: "IT",
        raw: &raw,
    }];
    rows.extend(greek.iter().map(|d| NewDevice {
        device: d,
        country: "GR",
        scope: "GR",
        raw: &raw,
    }));
    db::upsert_devices(&pool, &SourceId::OSM, &rows, now)
        .await
        .unwrap();
    // As the table of 2026-10-06 built them: a zone in Italy, points in
    // Greece.
    let old_item = |key: &str, kind: ItemKind, country: &str, at: Position| db::Item {
        id: Uuid::now_v7(),
        device_key: key.to_owned(),
        variant: Variant::All,
        opt_in_countries: OptIns::default(),
        kind,
        category: if kind == ItemKind::Zone {
            "danger_zone"
        } else {
            "fixed"
        }
        .to_owned(),
        country: country.to_owned(),
        line: (kind == ItemKind::Zone).then(|| {
            vec![
                Position::new(at.lat() - 0.005, at.lon()).unwrap(),
                Position::new(at.lat() + 0.005, at.lon()).unwrap(),
            ]
        }),
        point: (kind == ItemKind::Camera).then_some(at),
        bearing_deg: None,
        limit_kmh: None,
        source_ids: vec!["osm".to_owned()],
        content_hash: "built under the table of 2026-10-06".to_owned(),
    };
    let italian_zone = old_item("osm/node/it1", ItemKind::Zone, "IT", italian.position);
    let mut old = vec![italian_zone.clone()];
    old.extend(greek.iter().map(|d| {
        old_item(
            &format!("osm/{}", d.external_id),
            ItemKind::Camera,
            "GR",
            d.position,
        )
    }));
    db::write_items(&pool, &old, &[]).await.unwrap();

    let nowhere = Fake::new(Answer::Nothing);
    let refused = build(&pool, &nowhere, SECRET, false, false).await.unwrap();
    assert!(refused.retire_refused, "{refused:?}");
    assert_eq!((refused.retired, refused.unplaced), (0, 30), "{refused:?}");
    let served = items(&pool).await;
    let point = &served["osm/node/it1"];
    assert_eq!(
        (point.id, point.kind, point.point),
        (italian_zone.id, ItemKind::Camera, Some(italian.position)),
        "the Italian zone is now its point, in the same row"
    );
    assert_eq!(
        served.len(),
        31,
        "the Greek points stay until the guard is lifted"
    );

    let allowed = build(&pool, &nowhere, SECRET, false, true).await.unwrap();
    assert_eq!(allowed.retired, 30, "{allowed:?}");
    assert_eq!(items(&pool).await.len(), 1);
}

/// The lists of 2026-10-09 through the build, written and built with the
/// import role: France's yearly file gives the map's cameras their limit,
/// a camera the map no longer lists goes whatever the file says, Brussels'
/// cameras are points, and the Garda's zones are served as published, with
/// no kind.
#[sqlx::test(migrations = "../../migrations")]
async fn the_yearly_file_brussels_and_the_garda_join_the_build(pool: PgPool) {
    let ingest = as_role(&pool, "SET ROLE lunaway_ingest").await;
    let now = Utc::now();
    let map = CameraList::France.parse(FRANCE).unwrap();
    store(&ingest, CameraList::France, &map, now, None)
        .await
        .unwrap();
    let dsr = CameraList::FranceDsr
        .parse(include_bytes!("fixtures/fr_dsr_sample.csv"))
        .unwrap();
    store(&ingest, CameraList::FranceDsr, &dsr, now, None)
        .await
        .unwrap();
    let brussels = CameraList::Brussels
        .parse(include_bytes!("fixtures/be_bru_sample.json"))
        .unwrap();
    store(&ingest, CameraList::Brussels, &brussels, now, None)
        .await
        .unwrap();
    let garda_body = json!({
        "current_zones": lunaway_ingest::kmz::kml_of(include_bytes!(
            "fixtures/ie_garda_current_sample.kmz"
        ))
        .unwrap(),
        "new_zones": lunaway_ingest::kmz::kml_of(include_bytes!("fixtures/ie_garda_new_sample.kmz"))
            .unwrap(),
    });
    let garda = CameraList::IrelandGarda
        .parse(&serde_json::to_vec(&garda_body).unwrap())
        .unwrap();
    store(&ingest, CameraList::IrelandGarda, &garda, now, None)
        .await
        .unwrap();

    let engine = Fake::new(Answer::Straight);
    let report = build(&ingest, &engine, SECRET, false, false).await.unwrap();
    assert_eq!(
        (report.merged.dsr_matched, report.merged.dsr_alone),
        (16, 4),
        "the file's 16 metropolitan rows are the map's cameras; its 4 rows of Guadeloupe stand \
         alone: {report:?}"
    );
    assert_eq!(report.off, 4, "Guadeloupe is off: {report:?}");
    let with = items_for(&pool, &["FR"]).await;
    let classic = &with["securite-routiere/103"];
    assert_eq!(classic.limit_kmh, Some(70), "the file's VMA");
    assert_eq!(classic.source_ids, ["securite-routiere", "fr-dsr"]);
    assert_eq!(
        with["securite-routiere/12001"].limit_kmh, None,
        "never a discriminating camera's VMA"
    );
    assert!(
        !with.keys().any(|k| k.starts_with("fr-dsr/5000")),
        "Guadeloupe is off"
    );

    let without = items(&pool).await;
    let red = &without["be-bru-radars/RSG113"];
    assert_eq!(
        (red.kind, red.category.as_str()),
        (ItemKind::Camera, "red_light")
    );
    assert_eq!(without["be-bru-radars/municipal/1"].category, "fixed");
    let stored = devices(&pool).await;
    let zone = &without["ie-garda/current/2347"];
    assert_eq!(
        (zone.kind, zone.category.as_str(), zone.variant),
        (ItemKind::Zone, "danger_zone", Variant::All)
    );
    let published = stored["ie-garda/current/2347"].zone_line.clone().unwrap();
    let served = zone.line.clone().unwrap();
    assert_eq!(served.len(), published.len(), "the zone as published");
    assert!(served[0].distance_m(published[0]) < 0.5);
    assert!(
        without
            .keys()
            .any(|k| k.starts_with("ie-garda/current/2346")),
        "a branched zone served by its roads"
    );

    // The map no longer lists camera 103: it goes, though the yearly file
    // still names it.
    let mut fewer = map.clone();
    fewer.devices.retain(|l| l.device.external_id != "103");
    store(&ingest, CameraList::France, &fewer, now, None)
        .await
        .unwrap();
    let after = build(&ingest, &engine, SECRET, false, false).await.unwrap();
    assert_eq!(after.merged.dsr_left_out, 1, "{after:?}");
    assert!(
        !items_for(&pool, &["FR"])
            .await
            .keys()
            .any(|k| k.ends_with("/103")),
        "the map says which cameras are in service"
    );
}
