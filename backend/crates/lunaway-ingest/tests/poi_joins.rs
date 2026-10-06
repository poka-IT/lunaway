//! The sources joined to the points of interest: the fuel price feed, La
//! Poste's opening calendar and FINESS, each read from a recorded answer
//! (`tests/fixtures/`), and fetched through a local server that plays the
//! source.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    collections::HashSet,
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Router,
    extract::State,
    http::{HeaderMap, StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::any,
};
use chrono::{NaiveDate, NaiveTime};
use lunaway_domain::{
    SourceId,
    poi::{FinessEstablishment, FuelKind, FuelStation, PostOfficeDays, ShortageKind},
};
use lunaway_ingest::{
    IngestError,
    cache::Cache,
    finess, fuel,
    http::{self, RetryPolicy},
    laposte,
};
use sqlx::PgPool;

const FUEL: &[u8] = include_bytes!("fixtures/fuel_export_sample.json");
const LAPOSTE: &[u8] = include_bytes!("fixtures/laposte_ouvertur_sample.json");
const FINESS: &[u8] = include_bytes!("fixtures/finess_structures_sample.json");

const FAST: RetryPolicy = RetryPolicy {
    min_delay: Duration::from_millis(5),
    max_delay: Duration::from_millis(20),
    max_retries: 2,
};

/// A server answering each request with the next scripted body (the last
/// one repeats), recording the path, query and User-Agent it received.
#[derive(Clone)]
struct Fake {
    bodies: Arc<Mutex<Vec<Vec<u8>>>>,
    seen: Arc<Mutex<Vec<(String, String)>>>,
}

async fn handle(State(f): State<Fake>, uri: Uri, headers: HeaderMap) -> Response {
    let ua = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_owned();
    f.seen.lock().unwrap().push((uri.to_string(), ua));
    let mut bodies = f.bodies.lock().unwrap();
    let body = if bodies.len() > 1 {
        bodies.remove(0)
    } else {
        bodies[0].clone()
    };
    (StatusCode::OK, body).into_response()
}

async fn serve(bodies: Vec<Vec<u8>>) -> (Fake, SocketAddr) {
    let fake = Fake {
        bodies: Arc::new(Mutex::new(bodies)),
        seen: Arc::new(Mutex::new(Vec::new())),
    };
    let app = Router::new().fallback(any(handle)).with_state(fake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (fake, addr)
}

fn station<'a>(parsed: &'a fuel::ParsedFuel, key: &str) -> &'a FuelStation {
    &parsed
        .stations
        .iter()
        .find(|s| s.key == key)
        .unwrap_or_else(|| panic!("station {key}"))
        .station
}

#[test]
fn the_fuel_export_reads_into_stations() {
    let parsed = fuel::parse(FUEL).unwrap();
    assert_eq!(
        (parsed.rows, parsed.stations.len(), parsed.skipped),
        (5, 5, 0)
    );
    assert!(
        parsed.stations.iter().any(|s| s.key == "5100009"),
        "the feed's ids are numbers, without the leading zero of department 05"
    );

    let motorway = station(&parsed, "18200011");
    assert!(motorway.highway, "pop A is a motorway station");
    assert!(!motorway.automate_24_24);
    let lpg = motorway
        .prices
        .iter()
        .find(|p| p.fuel == FuelKind::Lpg)
        .unwrap();
    assert!((lpg.price_eur - 1.114).abs() < 1e-9);
    assert_eq!(motorway.prices.len(), 4, "diesel, E10, SP98 and LPG");
    assert!(
        motorway
            .shortages
            .iter()
            .any(|s| s.fuel == FuelKind::E85 && s.kind == ShortageKind::Temporary)
    );
    assert!(motorway.tile.lpg);
    assert_eq!(motorway.services.len(), 11);
    assert!(motorway.position.is_some());

    let out_for_now = station(&parsed, "95650002");
    let gplc = out_for_now
        .shortages
        .iter()
        .find(|s| s.fuel == FuelKind::Lpg)
        .unwrap();
    assert_eq!(gplc.kind, ShortageKind::Temporary);
    assert!(gplc.since.is_some(), "the feed dates the shortage");
    assert!(
        out_for_now.tile.lpg,
        "a temporary shortage is a station that sells LPG"
    );

    let stopped = station(&parsed, "34150003");
    assert!(!stopped.tile.lpg, "a definitive shortage is no LPG");
    assert!(stopped.automate_24_24);
    assert_eq!(
        parsed
            .stations
            .iter()
            .filter(|s| s.station.tile.lpg)
            .count(),
        3
    );
}

fn days(sites: &laposte::ParsedSites, key: &str) -> PostOfficeDays {
    sites
        .sites
        .iter()
        .find(|s| s.key == key)
        .unwrap_or_else(|| panic!("site {key}"))
        .days
        .clone()
}

fn t(h: u32, m: u32) -> NaiveTime {
    NaiveTime::from_hms_opt(h, m, 0).unwrap()
}

fn date(d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(2026, 10, d).unwrap()
}

#[test]
fn la_poste_lines_group_into_sites_with_their_closed_days() {
    let page = laposte::parse_page(LAPOSTE).unwrap();
    assert_eq!((page.total, page.next.as_deref()), (Some(45), None));
    let sites = laposte::build(page.lines);
    assert_eq!(sites.sites.len(), 3);
    assert_eq!(sites.skipped_lines, 0);

    let office = days(&sites, "00001A");
    assert_eq!(office.kind.as_deref(), Some("Bureau de Poste"));
    assert_eq!(office.days.len(), 15, "today and the 14 days after");
    let day = |d: u32| office.days.iter().find(|x| x.date == date(d)).unwrap();
    assert_eq!(
        day(6).open,
        vec![[t(9, 0), t(12, 0)], [t(14, 0), t(18, 0)]],
        "a weekday, morning and afternoon"
    );
    assert_eq!(day(10).open, vec![[t(9, 0), t(12, 0)]], "Saturday morning");
    assert!(day(11).open.is_empty(), "FERME on Sunday is a closed day");

    let agency = days(&sites, "00013A");
    assert_eq!(agency.kind.as_deref(), Some("Agence postale communale"));
    assert!(
        agency.days[0].open.is_empty(),
        "closed on Tuesday 6 October"
    );
    assert!(
        agency.days.windows(2).all(|w| w[0].date < w[1].date),
        "days in order"
    );
}

#[test]
fn finess_keeps_the_wanted_establishments_open_or_closed() {
    let wanted: HashSet<String> = ["010002285", "010003887", "010002699"]
        .into_iter()
        .map(str::to_owned)
        .collect();
    let parsed = finess::parse(FINESS, &wanted).unwrap();
    assert_eq!(
        parsed.structures, 4,
        "every establishment of the file is read"
    );
    let keys: Vec<&str> = parsed
        .establishments
        .iter()
        .map(|e| e.key.as_str())
        .collect();
    assert_eq!(
        keys,
        ["010002699", "010002285", "010003887"],
        "only the numbers a point carries are kept"
    );
    let of = |key: &str| -> &FinessEstablishment {
        &parsed
            .establishments
            .iter()
            .find(|e| e.key == key)
            .unwrap()
            .establishment
    };
    let open = of("010002285");
    assert!(open.open && !open.tile.closed);
    assert_eq!(open.category.as_deref(), Some("620"));
    assert_eq!(
        open.name.as_deref(),
        Some("NOUVELLE PHARMACIE DU CHAMP DE MARS")
    );
    assert_eq!(open.closed_on, None);
    let closed = of("010003887");
    assert!(
        !closed.open && closed.tile.closed,
        "etatObjet I is inactive"
    );
    assert_eq!(closed.closed_on, NaiveDate::from_ymd_opt(2026, 9, 28));
    let raw = &parsed
        .establishments
        .iter()
        .find(|e| e.key == "010003887")
        .unwrap()
        .raw;
    assert_eq!(
        raw["etatObjet"], "I",
        "the raw payload keeps the fields read"
    );
    assert!(raw.get("adresse").is_none(), "and only those");
}

/// The fixture's lines split into two pages, the first pointing to the
/// second through `next` at `next_base`.
fn two_pages(next_base: &str) -> (Vec<u8>, Vec<u8>) {
    let page: serde_json::Value = serde_json::from_slice(LAPOSTE).unwrap();
    let lines = page["results"].as_array().unwrap();
    let first = serde_json::json!({
        "total": lines.len(),
        "next": format!("{next_base}/lines?size=20&after=20"),
        "results": lines[..20],
    });
    let second = serde_json::json!({"total": lines.len(), "results": lines[20..]});
    (
        serde_json::to_vec(&first).unwrap(),
        serde_json::to_vec(&second).unwrap(),
    )
}

fn laposte_config(addr: SocketAddr) -> laposte::LaPosteConfig {
    laposte::LaPosteConfig {
        url: format!("http://{addr}/lines"),
        hosts: vec!["127.0.0.1".into()],
        page_size: 20,
        pace: Duration::ZERO,
        retry: FAST,
    }
}

#[tokio::test]
async fn la_poste_pages_follow_next_on_their_host_and_are_cached_for_the_day() {
    let client = http::client_allowing_plain_http().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let (fake, addr) = serve(Vec::new()).await;
    let (first, second) = two_pages(&format!("http://{addr}"));
    *fake.bodies.lock().unwrap() = vec![first, second];
    let config = laposte_config(addr);

    let lines = laposte::fetch(&client, &cache, &config, date(6), false)
        .await
        .unwrap();
    assert_eq!(
        (lines.lines.len(), lines.pages, lines.cached),
        (45, 2, false)
    );
    let seen = fake.seen.lock().unwrap().clone();
    assert_eq!(seen.len(), 2);
    assert!(
        seen[0].0.contains("date_calendrier_gte=2026-10-06"),
        "{}",
        seen[0].0
    );
    assert!(
        seen[0].0.contains("date_calendrier_lte=2026-10-20"),
        "{}",
        seen[0].0
    );
    assert!(seen[1].0.contains("after=20"), "the next link is followed");
    assert!(
        seen[0].1.ends_with("(+https://lunaway.net)"),
        "{}",
        seen[0].1
    );

    let again = laposte::fetch(&client, &cache, &config, date(6), false)
        .await
        .unwrap();
    assert_eq!((again.lines.len(), again.cached), (45, true));
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        2,
        "the same day's pages come from the cache"
    );
    // Another day asks again: the cached pages are of the 6th.
    let _ = laposte::fetch(&client, &cache, &config, date(7), false).await;
    assert_eq!(
        fake.seen.lock().unwrap().len(),
        3,
        "a new day's window is read from La Poste"
    );
}

#[tokio::test]
async fn a_next_link_to_another_host_is_refused() {
    let client = http::client_allowing_plain_http().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let (first, _) = two_pages("https://elsewhere.example");
    let (fake, addr) = serve(vec![first]).await;
    let err = laposte::fetch(&client, &cache, &laposte_config(addr), date(6), true)
        .await
        .unwrap_err();
    assert!(
        matches!(err, IngestError::UntrustedUrl { .. }),
        "a link out of the dataset's host is not followed: {err}"
    );
    assert_eq!(fake.seen.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn fewer_lines_than_announced_store_nothing() {
    let client = http::client_allowing_plain_http().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let mut page: serde_json::Value = serde_json::from_slice(LAPOSTE).unwrap();
    page["total"] = 60.into();
    let (_fake, addr) = serve(vec![serde_json::to_vec(&page).unwrap()]).await;
    let err = laposte::fetch(&client, &cache, &laposte_config(addr), date(6), true)
        .await
        .unwrap_err();
    assert!(
        matches!(
            err,
            IngestError::Incomplete {
                expected: 60,
                got: 45,
                ..
            }
        ),
        "a truncated calendar would retire sites: {err}"
    );
}

/// The fuel fixture with `edit` applied to the station `id`.
fn fuel_body(edit: impl Fn(&mut serde_json::Value), id: i64) -> Vec<u8> {
    let mut rows: Vec<serde_json::Value> = serde_json::from_slice(FUEL).unwrap();
    for row in &mut rows {
        if row["id"] == id {
            edit(row);
        }
    }
    serde_json::to_vec(&rows).unwrap()
}

/// The tiles' version once what waits is published: the worker publishes
/// at most every few hours, the tests at once.
async fn layer_version(pool: &PgPool) -> i64 {
    lunaway_db::pois::publish_layer(pool, std::time::Duration::ZERO)
        .await
        .unwrap();
    lunaway_db::pois::layer_version(pool).await.unwrap().version
}

/// An import of `points` as the whole of France: stored, then the French
/// points it did not see retired.
async fn store_pois(
    pool: &PgPool,
    points: &[lunaway_ingest::poi_osm::FetchedPoi],
) -> lunaway_ingest::store::Retirement {
    use lunaway_ingest::{osm_extract::Coverage, store};
    store::upsert_pois_by_country(pool, &SourceId::OSM, points)
        .await
        .unwrap();
    let seen: Vec<String> = points.iter().map(|p| p.external_id.clone()).collect();
    let france = Coverage::Countries(["FR".to_owned()].into_iter().collect());
    let by_scope = store::count_scopes(points.iter().map(store::poi_scope));
    let now = chrono::Utc::now();
    store::retire_pois_in_coverage(
        pool,
        &SourceId::OSM,
        &france,
        &seen,
        &by_scope,
        &[("FR".to_owned(), now)].into(),
        now,
    )
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_fuel_poll_moves_the_tiles_only_when_lpg_changes(pool: PgPool) {
    let unchanged = FUEL.to_vec();
    let new_price = fuel_body(
        |row| {
            row["gazole_prix"] = 2.199.into();
            row["gazole_maj"] = "2026-10-06T12:00:00+00:00".into();
        },
        40_500_002,
    );
    let lpg_stopped = fuel_body(
        |row| {
            row["gplc_prix"] = serde_json::Value::Null;
            row["gplc_maj"] = serde_json::Value::Null;
            row["gplc_rupture_type"] = "definitive".into();
            row["gplc_rupture_debut"] = "2026-10-06T12:00:00+00:00".into();
        },
        40_500_002,
    );
    let (fake, addr) = serve(vec![unchanged, new_price, lpg_stopped]).await;
    let client = http::client_allowing_plain_http().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let config = fuel::FuelConfig {
        url: format!("http://{addr}/exports/json"),
        retry: FAST,
    };
    let start = layer_version(&pool).await;

    let first = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!((first.stations, first.lpg), (5, 3));
    assert_eq!(first.store.upsert.upsert.inserted, 5);
    assert!(
        fake.seen.lock().unwrap()[0]
            .0
            .contains("select=id%2Clatitude"),
        "only the fields read are asked for"
    );
    let stored: Vec<(String, serde_json::Value)> =
        sqlx::query_as("SELECT ref, data FROM poi_join_records WHERE source_id = $1 ORDER BY ref")
            .bind(SourceId::FUEL_PRICES.as_str())
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(stored.len(), 5);
    let s: FuelStation = serde_json::from_value(
        stored
            .iter()
            .find(|(k, _)| k == "40500002")
            .unwrap()
            .1
            .clone(),
    )
    .unwrap();
    assert!(
        s.tile.lpg,
        "the stored data reads back as the domain's type"
    );
    let after_first = layer_version(&pool).await;
    assert!(after_first > start, "new stations on the map");

    let second = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(second.store.upsert.upsert.changed, 1);
    assert_eq!(
        layer_version(&pool).await,
        after_first,
        "a new price shows on no tile: the tiles keep their version"
    );

    let third = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(third.lpg, 2);
    assert_eq!(third.store.upsert.tile_changes, 1);
    assert!(
        layer_version(&pool).await > after_first,
        "a station that stopped selling LPG changes what its tile shows"
    );

    let cached = fuel::import(&pool, &client, &cache, &config, false)
        .await
        .unwrap();
    assert!(
        cached.cached,
        "without refresh the latest answer is read back"
    );
    assert_eq!(fake.seen.lock().unwrap().len(), 3);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_truncated_fetch_retires_no_point_and_no_joined_row(pool: PgPool) {
    use lunaway_db::pois::NewJoin;
    use lunaway_domain::{
        Position, SourceId,
        poi::{PoiKind, PoiRecord},
    };
    use lunaway_ingest::{poi_osm::FetchedPoi, store};
    let at = chrono::Utc::now();
    let points: Vec<FetchedPoi> = (0..10)
        .map(|i| FetchedPoi {
            external_id: format!("node/{i}"),
            external_url: None,
            record: PoiRecord::new(
                PoiKind::Toilets,
                Position::new(45.0 + f64::from(i) * 0.01, 5.0).unwrap(),
            ),
            raw: serde_json::json!({}),
            fetched_at: at,
        })
        .collect();
    store_pois(&pool, &points).await;
    let r = store_pois(&pool, &points[..3]).await;
    assert_eq!(r.refused, ["FR"], "3 of 10 looks truncated");
    assert_eq!(r.retired, 0);
    assert_eq!(
        lunaway_db::pois::live_count(&pool, &SourceId::OSM, None)
            .await
            .unwrap(),
        10
    );
    let r = store_pois(&pool, &points[..8]).await;
    assert_eq!((r.refused.len(), r.retired), (0, 2));

    let data = serde_json::json!({"days": []});
    let keys: Vec<String> = (0..10).map(|i| format!("{i:06}")).collect();
    let rows: Vec<NewJoin<'_>> = keys
        .iter()
        .map(|k| NewJoin {
            key: k,
            data: &data,
            raw: &data,
            fetched_at: at,
        })
        .collect();
    store::store_joins(&pool, &SourceId::LAPOSTE, &rows)
        .await
        .unwrap();
    let r = store::store_joins(&pool, &SourceId::LAPOSTE, &rows[..2])
        .await
        .unwrap();
    assert!(r.retire_refused);
    assert_eq!(
        lunaway_db::pois::live_join_count(&pool, &SourceId::LAPOSTE)
            .await
            .unwrap(),
        10
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_import_moves_the_tiles_once_and_only_when_a_tile_changes(pool: PgPool) {
    use lunaway_domain::{
        Position,
        poi::{PoiKind, PoiRecord},
    };
    use lunaway_ingest::poi_osm::FetchedPoi;
    let at = chrono::Utc::now();
    let make = |n: usize, name: &str| -> Vec<FetchedPoi> {
        (0..n)
            .map(|i| {
                let mut r = PoiRecord::new(
                    PoiKind::Bakery,
                    Position::new(45.0 + i as f64 * 1e-4, 5.0).unwrap(),
                );
                r.name = Some(format!("{name} {i}"));
                FetchedPoi {
                    external_id: format!("node/{i}"),
                    external_url: None,
                    record: r,
                    raw: serde_json::json!({}),
                    fetched_at: at,
                }
            })
            .collect()
    };
    let v0 = layer_version(&pool).await;
    // 2 500 points: three batches of the upsert, one move of the version.
    store_pois(&pool, &make(2_500, "Boulangerie")).await;
    assert_eq!(
        layer_version(&pool).await,
        v0 + 1,
        "once for the whole import"
    );
    store_pois(&pool, &make(2_500, "Boulangerie")).await;
    assert_eq!(
        layer_version(&pool).await,
        v0 + 1,
        "the same import changes no tile"
    );
    store_pois(&pool, &make(2_400, "Boulangerie")).await;
    assert_eq!(layer_version(&pool).await, v0 + 2, "a hundred points gone");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unchanged_import_writes_no_point_and_still_dates_its_read(pool: PgPool) {
    use chrono::TimeZone;
    use lunaway_ingest::{osm_extract::Coverage, poi_osm, store};
    let sample = include_bytes!("fixtures/osm_poi_sample.json");
    let day = |d| chrono::Utc.with_ymd_and_hms(2026, 10, d, 22, 0, 0).unwrap();
    let import = |d: u32| {
        let pool = pool.clone();
        async move {
            let points = poi_osm::parse(sample, day(d)).unwrap().points;
            let upsert = store::upsert_pois_by_country(&pool, &SourceId::OSM, &points)
                .await
                .unwrap();
            let seen: Vec<String> = points.iter().map(|p| p.external_id.clone()).collect();
            let by_scope = store::count_scopes(points.iter().map(store::poi_scope));
            let france = Coverage::Countries(["FR".to_owned()].into_iter().collect());
            store::retire_pois_in_coverage(
                &pool,
                &SourceId::OSM,
                &france,
                &seen,
                &by_scope,
                &[("FR".to_owned(), day(d))].into(),
                day(d),
            )
            .await
            .unwrap();
            upsert
        }
    };
    let versions = || async {
        sqlx::query_scalar!(r#"SELECT xmin::text AS "v!" FROM pois ORDER BY id"#)
            .fetch_all(&pool)
            .await
            .unwrap()
    };
    let first = import(1).await;
    assert_eq!(first.inserted, 28);
    let written = versions().await;
    let second = import(2).await;
    assert_eq!(
        (second.inserted, second.changed, second.unchanged),
        (0, 0, 28)
    );
    assert_eq!(
        versions().await,
        written,
        "the same points read again write no row: every point rewritten at each import \
         doubled the table until the next vacuum"
    );
    let id: uuid::Uuid = sqlx::query_scalar!("SELECT id FROM pois LIMIT 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    let shown = lunaway_db::pois::by_id(&pool, id).await.unwrap().unwrap();
    assert_eq!(
        shown.fetched_at,
        day(2),
        "the point was in the second read, and a client sees that date"
    );
}

/// The fuel feed polled again unchanged writes no row, yet every station
/// shows the date of that poll, which users read as the freshness of the
/// prices; a changed price rewrites its station only; a poll that looks
/// truncated dates the stations it saw, and only those.
#[sqlx::test(migrations = "../../migrations")]
async fn an_unchanged_fuel_poll_writes_no_row_and_dates_every_station(pool: PgPool) {
    let new_price = fuel_body(
        |row| {
            row["gazole_prix"] = 2.199.into();
            row["gazole_maj"] = "2026-10-06T12:00:00+00:00".into();
        },
        40_500_002,
    );
    let rows: Vec<serde_json::Value> = serde_json::from_slice(FUEL).unwrap();
    let truncated = serde_json::to_vec(&rows[..2]).unwrap();
    let seen_when_truncated: Vec<String> = rows[..2]
        .iter()
        .map(|r| r["id"].as_i64().unwrap().to_string())
        .collect();
    let (_, addr) = serve(vec![FUEL.to_vec(), FUEL.to_vec(), new_price, truncated]).await;
    let client = http::client_allowing_plain_http().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let config = fuel::FuelConfig {
        url: format!("http://{addr}/exports/json"),
        retry: FAST,
    };
    let versions = || async {
        sqlx::query_scalar!(r#"SELECT xmin::text AS "v!" FROM poi_join_records ORDER BY ref"#)
            .fetch_all(&pool)
            .await
            .unwrap()
    };
    let shown = || async {
        let refs: Vec<String> =
            sqlx::query_scalar!("SELECT ref FROM poi_join_records ORDER BY ref")
                .fetch_all(&pool)
                .await
                .unwrap();
        let mut stations = lunaway_db::fuel::by_refs(&pool, &refs).await.unwrap();
        stations.sort_by(|a, b| a.station_ref.cmp(&b.station_ref));
        stations
            .into_iter()
            .map(|s| (s.station_ref, s.fetched_at.timestamp_micros()))
            .collect::<Vec<_>>()
    };
    let first = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    let written = versions().await;
    assert_eq!(written.len(), 5);

    let second = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert!(second.fetched_at > first.fetched_at);
    let u = second.store.upsert.upsert;
    assert_eq!((u.inserted, u.changed, u.unchanged), (0, 0, 5));
    assert_eq!(
        versions().await,
        written,
        "the same feed read again writes no row: 96 polls a day rewrote the table each time"
    );
    assert!(
        shown()
            .await
            .iter()
            .all(|(_, at)| *at == second.fetched_at.timestamp_micros()),
        "every station shows the poll that read it, not the one that last changed it"
    );

    let third = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(third.store.upsert.upsert.changed, 1);
    let rewritten = versions()
        .await
        .iter()
        .zip(&written)
        .filter(|(a, b)| a != b)
        .count();
    assert_eq!(
        rewritten, 1,
        "only the station whose price moved is written"
    );
    assert!(
        shown()
            .await
            .iter()
            .all(|(_, at)| *at == third.fetched_at.timestamp_micros())
    );

    let fourth = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert!(
        fourth.store.retire_refused,
        "2 stations of 5 look truncated"
    );
    for (station, at) in shown().await {
        let expected = if seen_when_truncated.contains(&station) {
            fourth.fetched_at
        } else {
            third.fetched_at
        };
        assert_eq!(
            at,
            expected.timestamp_micros(),
            "station {station}: a truncated read dates what it saw, nothing more"
        );
    }
}
