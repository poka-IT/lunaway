//! Overture Maps Places (`lunaway_ingest::overture`) on a fixture written in
//! the exact schema of the release 2026-09-23.1 with invented places
//! (`fixtures/overture_places_sample.parquet`, three row groups: thirteen
//! places around Saumur, one in Marrakech, one in New York): the reading of
//! the file and its row groups, the rules, the deduplication against
//! OpenStreetMap, the incremental writes and the retirement, and a whole
//! run through a local server that plays the STAC catalogue and the bucket.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    collections::{BTreeSet, HashMap},
    net::SocketAddr,
    path::{Path, PathBuf},
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
use chrono::Utc;
use lunaway_domain::{
    Position, SourceId,
    poi::{PoiKind, PoiRecord},
};
use lunaway_ingest::{
    cache::Cache,
    http::{self, RetryPolicy},
    overture::{self, LocalFile, OvertureConfig, Skip, parquet::Place},
};
use sqlx::PgPool;

const FIXTURE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/tests/fixtures/overture_places_sample.parquet"
);

const FAST: RetryPolicy = RetryPolicy {
    min_delay: Duration::from_millis(5),
    max_delay: Duration::from_millis(20),
    max_retries: 2,
};

fn areas(codes: &[&str]) -> BTreeSet<String> {
    codes.iter().map(|c| (*c).to_owned()).collect()
}

fn read(codes: &[&str]) -> (Vec<Place>, overture::parquet::GroupCounts) {
    let mut out = Vec::new();
    let counts = overture::parquet::read_places(Path::new(FIXTURE), &areas(codes), |places| {
        out.extend(places);
        Ok(())
    })
    .unwrap();
    (out, counts)
}

#[test]
fn only_the_row_groups_of_the_run_are_read() {
    let (places, counts) = read(&["FR", "MC"]);
    assert_eq!(counts.groups, 3);
    assert_eq!(
        (counts.read, counts.rows, places.len()),
        (1, 13, 13),
        "the groups of Marrakech and New York are skipped by their statistics"
    );
    let (_, counts) = read(&["FR", "MC", "MA"]);
    assert_eq!(
        (counts.read, counts.rows),
        (2, 14),
        "Morocco is read when asked"
    );
}

#[test]
fn a_place_reads_with_its_columns() {
    let (places, _) = read(&["FR"]);
    let salon = places.iter().find(|p| p.id == "ov-salon").unwrap();
    assert_eq!(salon.name.as_deref(), Some("Studio Tif'Hair"));
    assert_eq!(
        (salon.lat, salon.lon),
        (Some(47.2598), Some(-0.0765)),
        "the point of the WKB geometry"
    );
    assert_eq!(salon.confidence, Some(0.98));
    assert_eq!(salon.phones, ["+33241000000"]);
    assert_eq!(salon.websites, ["https://studio-tifhair.example"]);
    let address = salon.address.as_ref().unwrap();
    assert_eq!(address.freeform.as_deref(), Some("12 Rue d'Orléans"));
    assert_eq!(address.locality.as_deref(), Some("Saumur"));
    assert_eq!(address.postcode.as_deref(), Some("49400"));
    assert_eq!(
        salon.hierarchy,
        [
            "lifestyle_services",
            "personal_or_beauty_service",
            "hair_salon"
        ]
    );
    let datasets: Vec<&str> = salon
        .sources
        .iter()
        .filter_map(|s| s.dataset.as_deref())
        .collect();
    assert_eq!(datasets, ["meta", "Overture"]);
    let dealer = places.iter().find(|p| p.id == "ov-rv-dealer").unwrap();
    assert_eq!(dealer.brand.as_deref(), Some("Rapido"));
    assert_eq!(dealer.sources[0].license.as_deref(), Some("CC0-1.0"));
}

#[test]
fn every_place_of_the_fixture_is_kept_or_left_out_for_its_reason() {
    let (places, _) = read(&["FR"]);
    let france = areas(&["FR", "MC"]);
    let outcome: HashMap<&str, Result<PoiKind, Skip>> = places
        .iter()
        .map(|p| {
            (
                p.id.as_str(),
                overture::select(p, &france, overture::MIN_CONFIDENCE).map(|(r, _)| r.kind),
            )
        })
        .collect();
    let expected: HashMap<&str, Result<PoiKind, Skip>> = [
        ("ov-salon", Ok(PoiKind::Hairdresser)),
        ("ov-twin-name", Ok(PoiKind::Hairdresser)),
        ("ov-twin-family", Ok(PoiKind::Restaurant)),
        ("ov-florist", Ok(PoiKind::Florist)),
        ("ov-rv-dealer", Ok(PoiKind::MotorhomeShop)),
        ("ov-stylist", Err(Skip::Category)),
        ("ov-accountant", Err(Skip::Category)),
        ("ov-low", Err(Skip::Confidence)),
        ("ov-closed", Err(Skip::Closed)),
        ("ov-foursquare", Err(Skip::Licence)),
        ("ov-brightquery", Err(Skip::Dataset)),
        ("ov-no-street", Err(Skip::Street)),
        ("ov-at-home", Err(Skip::ComesToYou)),
    ]
    .into();
    assert_eq!(outcome, expected);
}

/// An OpenStreetMap point of `kind` named `name` at `lat`, `lon`.
async fn osm_point(pool: &PgPool, id: &str, kind: PoiKind, name: &str, lat: f64, lon: f64) {
    let mut record = PoiRecord::new(kind, Position::new(lat, lon).unwrap());
    record.name = Some(name.to_owned());
    record.address.country_code = Some("FR".into());
    let raw = serde_json::value::to_raw_value(&serde_json::json!({})).unwrap();
    lunaway_db::pois::upsert(
        pool,
        &SourceId::OSM,
        &[lunaway_db::pois::NewPoi {
            external_id: id,
            external_url: None,
            record: &record,
            raw: &raw,
            fetched_at: Utc::now(),
            scope: Some("FR"),
            in_tiles: kind.tiled(),
        }],
    )
    .await
    .unwrap();
}

/// Metres north of a point, in degrees of latitude.
fn north(m: f64) -> f64 {
    m / 111_195.0
}

fn france_config() -> OvertureConfig {
    OvertureConfig {
        coverage: areas(&["FR", "MC"]),
        retry: FAST,
        pace: Duration::ZERO,
        ..OvertureConfig::default()
    }
}

fn local(cache: &Cache) -> LocalFile {
    let path: PathBuf = cache.root().join("overture/2026-09-23.1/sample.parquet");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::copy(FIXTURE, &path).unwrap();
    LocalFile {
        name: "sample.parquet".into(),
        path,
        fetched_at: Utc::now(),
        cached: true,
    }
}

async fn live(pool: &PgPool) -> Vec<(String, String, bool)> {
    sqlx::query!(
        r#"SELECT external_id, kind, in_tiles FROM pois
           WHERE source_id = 'overture' AND deleted_at IS NULL ORDER BY external_id"#
    )
    .fetch_all(pool)
    .await
    .unwrap()
    .into_iter()
    .map(|r| (r.external_id, r.kind, r.in_tiles))
    .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_openstreetmap_has_is_not_written_and_one_it_gains_is_retired(pool: PgPool) {
    // A shop of a close name 120 m away, of another family: the same
    // business by its name.
    osm_point(
        &pool,
        "node/1",
        PoiKind::Shop,
        "Coiff Annie",
        47.2650 + north(120.0),
        -0.0700,
    )
    .await;
    // A café 30 m from the restaurant: the same family, whatever the name.
    osm_point(
        &pool,
        "node/2",
        PoiKind::Cafe,
        "Café de la Paix",
        47.2550 + north(30.0),
        -0.0800,
    )
    .await;
    // A restaurant 40 m from the florist: another family, another name.
    osm_point(
        &pool,
        "node/3",
        PoiKind::Restaurant,
        "La Table",
        47.2500 + north(40.0),
        -0.0850,
    )
    .await;
    // The salon's name 200 m away: past the radius of a name.
    osm_point(
        &pool,
        "node/4",
        PoiKind::Shop,
        "Studio Tif Hair",
        47.2598 + north(200.0),
        -0.0765,
    )
    .await;
    // A beauty salon 60 m from the salon: the same family, past 50 m.
    osm_point(
        &pool,
        "node/6",
        PoiKind::Beauty,
        "Onglerie Belle",
        47.2598 - north(60.0),
        -0.0765,
    )
    .await;
    // The salon's own name next to it, on a point hidden by a moderator and
    // on a point OpenStreetMap deleted: neither is there any more.
    osm_point(
        &pool,
        "node/7",
        PoiKind::Hairdresser,
        "Studio Tif'Hair",
        47.2598,
        -0.0766,
    )
    .await;
    osm_point(
        &pool,
        "node/8",
        PoiKind::Hairdresser,
        "Studio Tif'Hair",
        47.2599,
        -0.0765,
    )
    .await;
    sqlx::query!("UPDATE pois SET hidden = true WHERE external_id = 'node/7'")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query!("UPDATE pois SET deleted_at = now() WHERE external_id = 'node/8'")
        .execute(&pool)
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let file = local(&cache);
    let config = france_config();

    let first = overture::import_files(
        &pool,
        &cache,
        "2026-09-23.1",
        std::slice::from_ref(&file),
        &config,
    )
    .await
    .unwrap();
    let f = &first.files[0];
    assert_eq!((f.candidates, f.twins), (5, 2), "{f:?}");
    assert_eq!(f.upsert.inserted, 3);
    assert_eq!(
        live(&pool).await,
        [
            ("ov-florist".to_owned(), "florist".to_owned(), false),
            (
                "ov-rv-dealer".to_owned(),
                "motorhome_shop".to_owned(),
                false
            ),
            ("ov-salon".to_owned(), "hairdresser".to_owned(), false),
        ],
        "outside the tiles, the twins of OpenStreetMap left out"
    );
    let row = sqlx::query!(
        r#"SELECT name, brand, scope, raw, data FROM pois
           WHERE source_id = 'overture' AND external_id = 'ov-rv-dealer'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(row.name.as_deref(), Some("Saumur Camping-Cars"));
    assert_eq!(row.brand.as_deref(), Some("Rapido"));
    assert_eq!(row.scope.as_deref(), Some("FR"));
    assert_eq!(
        row.raw["sources"][0]["dataset"], "AllThePlaces",
        "the payload keeps who said it, under which licence"
    );
    assert_eq!(row.raw["sources"][0]["license"], "CC0-1.0");
    assert_eq!(row.data["address"]["street"], "Route de Rouen");
    assert_eq!(row.data["phone"], "+33241999999");

    // OpenStreetMap gains the florist: the next run retires it, and writes
    // nothing else.
    osm_point(
        &pool,
        "node/5",
        PoiKind::Florist,
        "Fleurs du Château",
        47.2500,
        -0.0851,
    )
    .await;
    let second = overture::import_files(&pool, &cache, "2026-09-23.1", &[file], &config)
        .await
        .unwrap();
    let f = &second.files[0];
    assert_eq!(f.twins, 3);
    assert_eq!(
        (f.upsert.inserted, f.upsert.changed, f.upsert.unchanged),
        (0, 0, 2),
        "a place that did not change is not written again"
    );
    assert_eq!(second.retirement.retired, 1);
    assert_eq!(
        live(&pool)
            .await
            .into_iter()
            .map(|(id, ..)| id)
            .collect::<Vec<_>>(),
        ["ov-rv-dealer", "ov-salon"]
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_run_retires_only_in_its_own_countries(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let file = local(&cache);
    let mut config = france_config();
    config.coverage = areas(&["FR", "MC", "MA"]);
    overture::import_files(
        &pool,
        &cache,
        "2026-09-23.1",
        std::slice::from_ref(&file),
        &config,
    )
    .await
    .unwrap();
    assert!(
        live(&pool)
            .await
            .iter()
            .any(|(id, ..)| id == "ov-marrakech-cafe")
    );
    // A run of France alone leaves Morocco's places as they are.
    let report = overture::import_files(&pool, &cache, "2026-09-23.1", &[file], &france_config())
        .await
        .unwrap();
    assert_eq!(report.retirement.retired, 0);
    assert!(
        live(&pool)
            .await
            .iter()
            .any(|(id, ..)| id == "ov-marrakech-cafe"),
        "a country the run did not read keeps its places"
    );
}

/// What the fake catalogue and bucket saw: the path and the User-Agent.
type Seen = Arc<Mutex<Vec<(String, String)>>>;

#[derive(Clone)]
struct Fake {
    files: Arc<HashMap<String, Vec<u8>>>,
    seen: Seen,
}

async fn handle(State(f): State<Fake>, uri: Uri, headers: HeaderMap) -> Response {
    let ua = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_owned();
    f.seen.lock().unwrap().push((uri.path().to_owned(), ua));
    match f.files.get(uri.path()) {
        Some(body) => (StatusCode::OK, body.clone()).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

/// Serves the files `build` makes from the server's own base URL.
async fn serve(build: impl FnOnce(&str) -> HashMap<String, Vec<u8>>) -> (Seen, SocketAddr) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let seen: Seen = Arc::default();
    let fake = Fake {
        files: Arc::new(build(&format!("http://{addr}"))),
        seen: seen.clone(),
    };
    let app = Router::new().fallback(any(handle)).with_state(fake);
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (seen, addr)
}

/// The catalogue of one release with two items: the fixture, boxed over
/// western Europe, and a file of the Pacific the run must not download.
fn catalogue(base: &str) -> HashMap<String, Vec<u8>> {
    let fixture = std::fs::read(FIXTURE).unwrap();
    let release = "2026-09-23.1";
    let item = |n: &str, bbox: [f64; 4], file: &str, size: usize| {
        serde_json::json!({
            "type": "Feature",
            "id": n,
            "bbox": bbox,
            "properties": {"num_rows": 15},
            "assets": {
                "aws": {"href": format!("{base}/release/{release}/{file}"), "file:size": size},
                "azure": {"href": format!("https://overturemapswestus2.blob.core.windows.net/release/{release}/{file}"), "file:size": size},
            },
        })
        .to_string()
        .into_bytes()
    };
    let size = fixture.len();
    HashMap::from([
        (
            "/catalog.json".to_owned(),
            serde_json::json!({"type": "Catalog", "latest": release, "links": []})
                .to_string()
                .into_bytes(),
        ),
        (
            format!("/{release}/places/place/collection.json"),
            serde_json::json!({"type": "Collection", "links": [
                {"rel": "root", "href": format!("{base}/catalog.json")},
                {"rel": "item", "href": format!("{base}/{release}/places/place/00007/00007.json")},
                {"rel": "item", "href": format!("{base}/{release}/places/place/00000/00000.json")},
            ]})
            .to_string()
            .into_bytes(),
        ),
        (
            format!("/{release}/places/place/00007/00007.json"),
            item(
                "00007",
                [-1.6, 40.4, 6.3, 62.7],
                "part-00007.zstd.parquet",
                size,
            ),
        ),
        (
            format!("/{release}/places/place/00000/00000.json"),
            item(
                "00000",
                [-180.0, -85.0, -76.5, 28.6],
                "part-00000.zstd.parquet",
                size,
            ),
        ),
        (
            format!("/release/{release}/part-00007.zstd.parquet"),
            fixture.clone(),
        ),
        (
            format!("/release/{release}/part-00000.zstd.parquet"),
            fixture,
        ),
    ])
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_run_reads_the_latest_release_and_downloads_its_files_once(pool: PgPool) {
    let (seen, addr) = serve(catalogue).await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    // A file of an older release, which a complete run removes.
    let old = dir
        .path()
        .join("overture/2026-08-19.0/part-00007.zstd.parquet");
    std::fs::create_dir_all(old.parent().unwrap()).unwrap();
    std::fs::write(&old, b"old").unwrap();
    let old_state = dir
        .path()
        .join("overture/runs/2026-08-19.0-part-00007.zstd.parquet.seen");
    std::fs::create_dir_all(old_state.parent().unwrap()).unwrap();
    std::fs::write(&old_state, b"FR\tov-x\n").unwrap();
    let client = http::client_allowing_plain_http().unwrap();
    let config = OvertureConfig {
        stac: format!("http://{addr}"),
        asset_hosts: vec!["127.0.0.1".into()],
        ..france_config()
    };
    let report = overture::import(&pool, &client, &cache, &config)
        .await
        .unwrap();
    assert_eq!(report.release, "2026-09-23.1");
    assert_eq!(
        report.files.len(),
        1,
        "the Pacific's file is not downloaded"
    );
    assert_eq!(report.files[0].upsert.inserted, 5);
    assert!(!old.exists(), "the files of an older release are removed");
    assert!(!old_state.exists(), "and what a stopped run of it left");
    let paths: Vec<String> = seen
        .lock()
        .unwrap()
        .iter()
        .map(|(p, _)| p.clone())
        .collect();
    assert_eq!(
        paths,
        [
            "/catalog.json",
            "/2026-09-23.1/places/place/collection.json",
            "/2026-09-23.1/places/place/00007/00007.json",
            "/2026-09-23.1/places/place/00000/00000.json",
            "/release/2026-09-23.1/part-00007.zstd.parquet",
        ]
    );
    assert!(
        seen.lock()
            .unwrap()
            .iter()
            .all(|(_, ua)| ua.ends_with("(+https://lunaway.net)")),
        "every request names Lunaway"
    );
    seen.lock().unwrap().clear();
    overture::import(&pool, &client, &cache, &config)
        .await
        .unwrap();
    assert!(
        !seen
            .lock()
            .unwrap()
            .iter()
            .any(|(p, _)| p.ends_with(".parquet")),
        "a release never changes: its files are downloaded once"
    );
}

#[tokio::test]
async fn a_file_on_another_host_is_refused() {
    let (_, addr) = serve(|base| {
        let mut files = catalogue(base);
        let item = files
            .get_mut("/2026-09-23.1/places/place/00007/00007.json")
            .unwrap();
        *item = String::from_utf8(item.clone())
            .unwrap()
            .replace(
                &format!("{base}/release"),
                "http://files.evil.example/release",
            )
            .into_bytes();
        files
    })
    .await;
    let client = http::client_allowing_plain_http().unwrap();
    let config = OvertureConfig {
        stac: format!("http://{addr}"),
        asset_hosts: vec!["127.0.0.1".into()],
        ..france_config()
    };
    let err = overture::release_files(&client, &config).await.unwrap_err();
    assert!(
        matches!(err, lunaway_ingest::IngestError::UntrustedUrl { .. }),
        "{err:?}"
    );
}

/// A copy of the fixture under `name` in the cache, or `bytes` instead.
fn local_named(cache: &Cache, name: &str, bytes: Option<&[u8]>) -> LocalFile {
    let path: PathBuf = cache.root().join(format!("overture/2026-09-23.1/{name}"));
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    match bytes {
        Some(b) => std::fs::write(&path, b).unwrap(),
        None => {
            std::fs::copy(FIXTURE, &path).unwrap();
        }
    }
    LocalFile {
        name: name.to_owned(),
        path,
        fetched_at: Utc::now(),
        cached: true,
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_stopped_run_resumes_after_the_last_file_it_stored(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let first = local_named(&cache, "part-1.parquet", None);
    let broken = local_named(&cache, "part-2.parquet", Some(b"not a parquet file"));
    let files = [first.clone(), broken];
    let err = overture::import_files(&pool, &cache, "2026-09-23.1", &files, &france_config())
        .await
        .unwrap_err();
    assert!(
        matches!(err, lunaway_ingest::IngestError::Parquet { .. }),
        "{err:?}"
    );
    assert_eq!(live(&pool).await.len(), 5, "the first file is stored");
    // The second file arrives whole; the run starts again.
    let fixed = local_named(&cache, "part-2.parquet", None);
    let report = overture::import_files(
        &pool,
        &cache,
        "2026-09-23.1",
        &[first, fixed],
        &france_config(),
    )
    .await
    .unwrap();
    assert!(
        report.files[0].resumed && report.files[0].rows == 0,
        "the file stored before is not read again: {:?}",
        report.files[0]
    );
    assert!(!report.files[1].resumed);
    assert_eq!(
        report.retirement.retired, 0,
        "the places of the resumed file count as seen"
    );
    assert_eq!(live(&pool).await.len(), 5);
    assert!(
        !dir.path().join("overture/runs/2026-09-23.1.json").exists(),
        "a complete run leaves no state behind"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_run_without_a_file_retires_nothing(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let file = local(&cache);
    overture::import_files(&pool, &cache, "2026-09-23.1", &[file], &france_config())
        .await
        .unwrap();
    let err = overture::import_files(&pool, &cache, "2026-09-23.1", &[], &france_config())
        .await
        .unwrap_err();
    assert!(
        matches!(err, lunaway_ingest::IngestError::Implausible { .. }),
        "{err:?}"
    );
    assert_eq!(
        live(&pool).await.len(),
        5,
        "a catalogue that lists no file of the countries says nothing of their places"
    );
}

#[test]
fn a_broken_file_is_an_error_of_its_own() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("broken.parquet");
    std::fs::write(&path, b"PAR1 and nothing else").unwrap();
    let err = overture::parquet::read_places(&path, &areas(&["FR"]), |_| Ok(())).unwrap_err();
    assert!(
        matches!(err, lunaway_ingest::IngestError::Parquet { .. }),
        "{err:?}"
    );
}

#[tokio::test]
async fn a_download_of_the_wrong_size_is_removed() {
    let (_, addr) = serve(catalogue).await;
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let file = overture::ReleaseFile {
        name: "part-00007.zstd.parquet".into(),
        url: format!("http://{addr}/release/2026-09-23.1/part-00007.zstd.parquet"),
        size: Some(12),
        bbox: [40.0, -2.0, 50.0, 6.0],
    };
    let err = overture::fetch_file(&client, &cache, "2026-09-23.1", &file, FAST)
        .await
        .unwrap_err();
    assert!(
        matches!(err, lunaway_ingest::IngestError::Incomplete { .. }),
        "{err:?}"
    );
    assert!(
        !dir.path()
            .join("overture/2026-09-23.1/part-00007.zstd.parquet")
            .exists(),
        "a file the catalogue does not describe is not kept to be read next time"
    );
}
