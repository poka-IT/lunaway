//! The official camera lists as the importer reads them, on extracts of the
//! answers recorded on 2026-10-06, and what storing them keeps: never a
//! Swiss camera, and no retirement when a list comes back truncated.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::collections::BTreeMap;

use chrono::{Duration, Utc};
use lunaway_domain::{Position, enforcement::DeviceKind};
use lunaway_ingest::cameras::{CameraList, Listed, Parsed, store};
use sqlx::PgPool;

const FRANCE: &[u8] = include_bytes!("fixtures/securite_routiere_radars_sample.json");
const POLAND: &[u8] = include_bytes!("fixtures/pl_canard_sample.csv");
const LUXEMBOURG: &[u8] = include_bytes!("fixtures/lu_pch_radars_sample.geojson");
const NORWAY: &[u8] = include_bytes!("fixtures/no_nvdb_atk_sample.json");
/// The yearly file of data.gouv.fr of 2025-12-30, and of 2024-10-18: a few
/// rows of each type (research of 2026-10-09).
const FRANCE_DSR: &[u8] = include_bytes!("fixtures/fr_dsr_sample.csv");
const FRANCE_DSR_2024: &[u8] = include_bytes!("fixtures/fr_dsr_2024_sample.csv");
/// Brussels' regional and municipal layers of 2026-10-09, a camera of each
/// key and type.
const BRUSSELS: &[u8] = include_bytes!("fixtures/be_bru_sample.json");
/// The Garda's archives of 2026-01-12, a few zones each, a branched one
/// among them.
const GARDA_CURRENT: &[u8] = include_bytes!("fixtures/ie_garda_current_sample.kmz");
const GARDA_NEW: &[u8] = include_bytes!("fixtures/ie_garda_new_sample.kmz");

fn kinds(parsed: &Parsed) -> BTreeMap<&'static str, usize> {
    let mut out = BTreeMap::new();
    for l in &parsed.devices {
        *out.entry(l.device.kind.code()).or_insert(0) += 1;
    }
    out
}

fn find<'a>(parsed: &'a Parsed, id: &str) -> &'a Listed {
    parsed
        .devices
        .iter()
        .find(|l| l.device.external_id == id)
        .unwrap_or_else(|| panic!("{id} is read"))
}

fn near(p: Position, lat: f64, lon: f64) -> bool {
    p.distance_m(Position::new(lat, lon).unwrap()) < 2.0
}

#[test]
fn each_french_type_maps_to_its_kind_and_the_radar_cars_stay_out() {
    let parsed = CameraList::France.parse(FRANCE).unwrap();
    assert_eq!(parsed.rows, 92);
    assert_eq!(
        parsed.skipped, 2,
        "the routes of the radar cars are mobile, never a camera"
    );
    assert_eq!(
        kinds(&parsed),
        BTreeMap::from([
            ("fixed", 45),
            ("level_crossing", 15),
            ("red_light", 15),
            ("section", 15)
        ]),
        "fixes, discriminants and urbain are fixed cameras"
    );
    let red = find(&parsed, "FE110000");
    assert_eq!(red.device.kind, DeviceKind::RedLight);
    assert!(near(red.device.position, 48.267_35, 4.088_97));
    assert_eq!(
        red.raw["typeLabel"], "Radar feu rouge",
        "the row is kept as given"
    );
}

#[test]
fn the_polish_list_reads_from_windows_1250_with_its_sections_ends() {
    let parsed = CameraList::Poland.parse(POLAND).unwrap();
    assert_eq!(parsed.rows, 20);
    assert_eq!(parsed.skipped, 0);
    assert_eq!(
        kinds(&parsed),
        BTreeMap::from([
            ("fixed", 8),
            ("level_crossing", 3),
            ("red_light", 4),
            ("section", 5)
        ]),
        "a red light at a railway is a level crossing"
    );
    assert_eq!(
        find(&parsed, "CEN.1.109").raw[1],
        "Aleksandrów Łódzki",
        "the row is kept in its own letters"
    );
    let section = find(&parsed, "CAN.O.1.012");
    assert_eq!(section.device.kind, DeviceKind::Section);
    assert_eq!(section.device.section_length_m, Some(2_520.0));
    let end = section.device.section_end.unwrap();
    assert!(near(end, 52.150_588_9, 21.063_252_777_777_777));
}

#[test]
fn luxembourg_s_lines_are_sections_and_its_points_fixed_cameras() {
    let parsed = CameraList::Luxembourg.parse(LUXEMBOURG).unwrap();
    assert_eq!(parsed.rows, 39);
    assert_eq!(
        kinds(&parsed),
        BTreeMap::from([("fixed", 33), ("section", 6)])
    );
    let section = find(&parsed, "22");
    assert_eq!(
        section.device.road.as_deref(),
        Some("N11 Gonderange / Waldhof")
    );
    assert!(near(
        section.device.position,
        49.662_477_731_304_42,
        6.198_024_964_829_332
    ));
    assert!(near(
        section.device.section_end.unwrap(),
        49.688_420_221_087_26,
        6.233_778_534_333_346
    ));
}

#[test]
fn norway_s_points_read_with_their_name() {
    let parsed = CameraList::Norway.parse(NORWAY).unwrap();
    assert_eq!(parsed.rows, 8);
    assert_eq!(parsed.devices.len(), 8);
    let first = find(&parsed, "78774532");
    assert!(near(first.device.position, 61.550_591_35, 5.687_337_6));
    assert_eq!(
        first.device.road.as_deref(),
        Some("Naustdalstunnelen 1 mot Førde (P2)")
    );
}

#[test]
fn france_s_yearly_file_reads_each_type_and_never_a_discriminating_camera_s_limit() {
    let parsed = CameraList::FranceDsr.parse(FRANCE_DSR).unwrap();
    assert_eq!((parsed.rows, parsed.devices.len()), (20, 20));
    assert_eq!(
        kinds(&parsed),
        BTreeMap::from([
            ("fixed", 14),
            ("level_crossing", 2),
            ("red_light", 2),
            ("section", 2)
        ]),
        "ETF, ETT, ETD and ETU are fixed cameras, ETVM a section, ETFR a red light, ETPN a \
         level crossing"
    );
    let classic = find(&parsed, "103");
    assert!(near(classic.device.position, 48.670_29, 2.279_76));
    assert_eq!(classic.device.limit_kmh, Some(70));
    assert_eq!(classic.raw["Type de radar"], "ETF", "the row kept as read");
    assert_eq!(
        find(&parsed, "12001").device.limit_kmh,
        None,
        "a discriminating camera's VMA is the heavy vehicles' limit"
    );
    assert_eq!(find(&parsed, "FE110000").device.limit_kmh, None, "NA");
    assert_eq!(find(&parsed, "20006").device.kind, DeviceKind::Section);
    // The file of 2024: other column names, the VMA last.
    let older = CameraList::FranceDsr.parse(FRANCE_DSR_2024).unwrap();
    assert_eq!(older.devices.len(), 3);
    assert_eq!(find(&older, "00101").device.limit_kmh, Some(130));
    assert!(near(
        find(&older, "00101").device.position,
        49.958_42,
        2.854_79
    ));
    assert!(
        CameraList::FranceDsr
            .parse(b"Num;Kind\r\n1;ETF\r\n")
            .is_err(),
        "a file without coordinates is not this list"
    );
}

#[test]
fn brussels_reads_red_lights_by_their_key_and_municipal_cameras_as_fixed() {
    let parsed = CameraList::Brussels.parse(BRUSSELS).unwrap();
    assert_eq!((parsed.rows, parsed.devices.len()), (14, 14));
    // The kind read from the first letter of the key: an assumption, the
    // codes of `radar_type` being published nowhere.
    assert_eq!(find(&parsed, "RSG113").device.kind, DeviceKind::RedLight);
    assert_eq!(
        find(&parsed, "5340/9007").device.kind,
        DeviceKind::RedLight,
        "fr_key RJE401"
    );
    assert_eq!(find(&parsed, "SPW04_1").device.kind, DeviceKind::Fixed);
    assert_eq!(
        find(&parsed, "5342/9007").device.kind,
        DeviceKind::Fixed,
        "no key: a speed camera"
    );
    assert_eq!(
        find(&parsed, "SPW04_1").device.road.as_deref(),
        Some("Avenue de Tervueren")
    );
    assert!(near(
        find(&parsed, "SPW04_1").device.position,
        50.8348,
        4.427
    ));
    assert_eq!(find(&parsed, "municipal/1").device.kind, DeviceKind::Fixed);
}

#[test]
fn the_garda_s_zones_read_as_lines_one_per_road_of_a_zone() {
    let body = serde_json::json!({
        "current_zones": lunaway_ingest::kmz::kml_of(GARDA_CURRENT).unwrap(),
        "new_zones": lunaway_ingest::kmz::kml_of(GARDA_NEW).unwrap(),
    });
    let parsed = CameraList::IrelandGarda
        .parse(&serde_json::to_vec(&body).unwrap())
        .unwrap();
    assert_eq!(parsed.rows, 6);
    assert!(
        parsed
            .devices
            .iter()
            .all(|l| l.device.kind == DeviceKind::MobileZone),
        "a zone, never a camera"
    );
    let zone = find(&parsed, "current/2346");
    let line = zone.device.zone_line.clone().unwrap();
    assert!(
        near(line[0], 53.318_930_2, -6.421_260_2)
            || near(line[line.len() - 1], 53.318_930_2, -6.421_260_2)
    );
    let length: f64 = line.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    assert!(
        (length - 1_500.0).abs() < 400.0,
        "about the 1.5 km the zone's table gives: {length}"
    );
    assert_eq!(zone.raw["fields"]["Length (KM)"], "1.5");
    assert!(
        parsed
            .devices
            .iter()
            .any(|l| l.device.external_id.starts_with("new/")),
        "both files read"
    );
    for l in &parsed.devices {
        let line = l.device.zone_line.as_ref().unwrap();
        let length: f64 = line.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        assert!(length >= 100.0, "{}: {length} m", l.device.external_id);
        assert_eq!(
            lunaway_domain::region::country_at(l.device.position),
            Some("IE"),
            "{}: its middle lies in Ireland",
            l.device.external_id
        );
    }
}

async fn live(pool: &PgPool, source: &str) -> i64 {
    sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM enforcement_devices WHERE source_id = $1 AND deleted_at IS NULL",
    )
    .bind(source)
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_swiss_camera_is_never_stored_and_a_truncated_list_retires_nothing(pool: PgPool) {
    let mut parsed = CameraList::Poland.parse(POLAND).unwrap();
    let mut geneva = parsed.devices[0].clone();
    geneva.device.external_id = "geneva".into();
    geneva.device.position = Position::new(46.204, 6.143).unwrap();
    let mut at_sea = parsed.devices[0].clone();
    at_sea.device.external_id = "at-sea".into();
    at_sea.device.position = Position::new(45.0, -20.0).unwrap();
    let twice = parsed.devices[1].clone();
    parsed.devices.push(geneva);
    parsed.devices.push(at_sea);
    parsed.devices.push(twice);
    let first = Utc::now() - Duration::days(2);
    let updated = Utc::now() - Duration::days(30);
    let s = store(&pool, CameraList::Poland, &parsed, first, Some(updated))
        .await
        .unwrap();
    assert_eq!(
        (
            s.devices,
            s.not_stored,
            s.written,
            s.retired,
            s.retire_refused
        ),
        (20, 3, 20, 0, false),
        "a camera listed twice is stored once"
    );
    let swiss: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM enforcement_devices WHERE external_id IN ('geneva', 'at-sea')",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(swiss, 0, "no data is kept for a Swiss position");
    let read: (i32,) =
        sqlx::query_as("SELECT devices FROM enforcement_sources WHERE source_id = 'pl-canard'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(read.0, 20, "the list's read is recorded with what it held");
    let list_date = || async {
        sqlx::query_scalar::<_, Option<chrono::DateTime<Utc>>>(
            "SELECT list_updated_at FROM enforcement_sources WHERE source_id = 'pl-canard'",
        )
        .fetch_one(&pool)
        .await
        .unwrap()
    };
    let kept = list_date().await;
    assert!(kept.is_some(), "the list's own date is recorded");

    // Five cameras gone from the list: retired.
    let mut shorter = CameraList::Poland.parse(POLAND).unwrap();
    shorter.devices.truncate(15);
    let second = first + Duration::days(1);
    let s = store(&pool, CameraList::Poland, &shorter, second, None)
        .await
        .unwrap();
    assert_eq!((s.retired, s.retire_refused), (5, false));
    assert_eq!(
        list_date().await,
        kept,
        "a read that gives no date keeps the list's last known one"
    );
    assert_eq!(live(&pool, "pl-canard").await, 15);

    // A list down to a third of what is stored: a truncated answer.
    shorter.devices.truncate(5);
    let s = store(&pool, CameraList::Poland, &shorter, Utc::now(), None)
        .await
        .unwrap();
    assert_eq!((s.retired, s.retire_refused), (0, true));
    assert_eq!(
        live(&pool, "pl-canard").await,
        15,
        "a truncated list must not retire the cameras it lost"
    );
}
