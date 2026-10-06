//! Sync regions, their packs and the persisted queries, as a client sees
//! them: a device downloads its region's pack, checks it, copies it, then
//! follows the feed from the pack's cursor without missing a change.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::io::Read;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{
    ApiConfig, ApiState,
    packs::{BuildReport, Dropped, PackError, PackOptions, build},
};
use lunaway_db::PgPool;
use lunaway_domain::SourceId;
use lunaway_ingest::{atout_france, geocode, osm, store::store_complete};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tower::ServiceExt;

const OVERPASS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/ban_answer_sample.csv");

fn app(pool: PgPool) -> axum::Router {
    lunaway_api::router(ApiState::new(pool, ApiConfig::default()))
}

/// A pool that never connects, for the fields that need no database.
fn no_db() -> PgPool {
    sqlx::postgres::PgPoolOptions::new()
        .connect_lazy("postgres://nobody@127.0.0.1:1/none")
        .unwrap()
}

async fn post(app: &axum::Router, body: Value) -> (StatusCode, Value) {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

async fn gql(app: &axum::Router, query: &str, variables: Value) -> Value {
    let (status, body) = post(app, json!({"query": query, "variables": variables})).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

fn code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or_else(|| panic!("no error code in {body}"))
}

/// The fixture pipeline (OSM and Atout France records, conflated), then a
/// commune of Maine-et-Loire covering the Pays de la Loire places: the
/// places of the Landes keep no commune.
async fn seeded(pool: &PgPool) {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let o = osm::parse(OVERPASS, at).unwrap();
    store_complete(pool, &SourceId::OSM, Some("FR-PDL"), &o.records)
        .await
        .unwrap();
    let parsed = atout_france::parse_csv(ATOUT_CSV).unwrap();
    let answer = geocode::parse_answer(BAN_ANSWER).unwrap();
    let (af, _) = atout_france::to_records(&parsed.campsites, &answer, at);
    store_complete(pool, &SourceId::ATOUT_FRANCE, None, &af)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO municipalities (code, name, geom, fetched_at) VALUES \
         ('49007', 'Angers', ST_Multi(ST_MakeEnvelope(-2.7, 46.8, 0.0, 48.0, 4326)), now())",
    )
    .execute(pool)
    .await
    .unwrap();
    lunaway_conflate::run(
        pool,
        Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap(),
        None,
    )
    .await
    .unwrap();
}

const PLACE: &str = "id name kind lat lon services region updatedAt \
                     openingIntervals { start end } \
                     sources { source { id name licence attribution url } externalId \
                               externalUrl fetchedAt matchScore }";

fn changes_query() -> String {
    format!(
        "query($region: String, $since: String) {{ changes(region: $region, since: $since) {{ \
         places {{ {PLACE} }} deleted left cursor hasMore }} }}"
    )
}

/// The places of a pack, read the way a device does: the file checked
/// against the manifest's hash, inflated, opened as SQLite.
fn read_pack(bytes: &[u8], sha256: &str) -> Vec<Value> {
    let digest: String = Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert_eq!(digest, sha256, "the manifest names the file's hash");
    let mut raw = Vec::new();
    flate2::read::GzDecoder::new(bytes)
        .read_to_end(&mut raw)
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("pack.sqlite");
    std::fs::write(&path, raw).unwrap();
    let db = rusqlite::Connection::open(&path).unwrap();
    let mut rows = db
        .prepare(
            "SELECT id, name, kind, lat, lon, services, region, updated_at, opening_intervals, \
             sources FROM places ORDER BY id",
        )
        .unwrap();
    let json_text =
        |t: Option<String>| t.map_or(Value::Null, |t| serde_json::from_str(&t).unwrap());
    rows.query_map([], |r| {
        Ok(json!({
            "id": r.get::<_, String>(0)?,
            "name": r.get::<_, Option<String>>(1)?,
            "kind": r.get::<_, String>(2)?,
            "lat": r.get::<_, f64>(3)?,
            "lon": r.get::<_, f64>(4)?,
            "services": json_text(r.get(5)?),
            "region": r.get::<_, Option<String>>(6)?,
            "updatedAt": r.get::<_, String>(7)?,
            "openingIntervals": json_text(r.get(8)?),
            "sources": json_text(r.get(9)?),
        }))
    })
    .unwrap()
    .collect::<Result<Vec<_>, _>>()
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_region_syncs_from_its_pack_then_from_the_feed(pool: PgPool) {
    seeded(&pool).await;
    let app = app(pool.clone());
    let regions_query = "{ regions { code country name nameFr pack { url format bytes rawBytes \
                         sha256 version cursor places bounds { south west north east } } } }";

    let before = gql(&app, regions_query, json!({})).await;
    let pdl = |body: &Value| {
        body["data"]["regions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["code"] == "FR-PDL")
            .cloned()
            .unwrap()
    };
    assert_eq!(pdl(&before)["nameFr"], "Pays de la Loire");
    assert_eq!(pdl(&before)["pack"], Value::Null, "no pack before a build");

    let dir = tempfile::tempdir().unwrap();
    let built = build(
        &pool,
        ApiConfig::default(),
        &PackOptions {
            dir: dir.path().to_owned(),
            only: Vec::new(),
            takedown: false,
        },
    )
    .await
    .unwrap()
    .built;
    let mut codes: Vec<&str> = built.iter().map(|b| b.pack.region.as_str()).collect();
    codes.sort_unstable();
    assert_eq!(
        codes,
        ["FR", "FR-PDL"],
        "the places of Maine-et-Loire, and those outside every commune"
    );

    let manifest = pdl(&gql(&app, regions_query, json!({})).await)["pack"].clone();
    assert_eq!(manifest["format"], "sqlite-gzip-1");
    let url = manifest["url"].as_str().unwrap();
    let file = url
        .strip_prefix("https://api.lunaway.net/packs/")
        .expect("served under the API's /packs/");
    let bytes = std::fs::read(dir.path().join(file)).unwrap();
    assert_eq!(manifest["bytes"].as_f64(), Some(bytes.len() as f64));
    let packed = read_pack(&bytes, manifest["sha256"].as_str().unwrap());
    assert_eq!(manifest["places"].as_u64(), Some(packed.len() as u64));

    // The same places as a full sync of the region, value for value.
    let full = gql(
        &app,
        &changes_query(),
        json!({"region": "FR-PDL", "since": null}),
    )
    .await;
    let mut synced: Vec<Value> = full["data"]["changes"]["places"]
        .as_array()
        .unwrap()
        .clone();
    synced.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    assert!(!synced.is_empty());
    assert_eq!(
        packed, synced,
        "a pack holds what the feed serves, field for field"
    );

    // A change after the build comes with the first page after the pack's
    // cursor, and nothing else does.
    let cursor = manifest["cursor"].as_str().unwrap();
    let quiet = gql(
        &app,
        &changes_query(),
        json!({"region": "FR-PDL", "since": cursor}),
    )
    .await;
    assert_eq!(quiet["data"]["changes"]["places"], json!([]));
    let moved = packed[0]["id"]
        .as_str()
        .unwrap()
        .parse::<uuid::Uuid>()
        .unwrap();
    sqlx::query(
        "UPDATE source_records SET needs_conflation = true, \
         data = jsonb_set(data, '{name}', '\"Renamed after the pack\"') \
         WHERE id IN (SELECT record_id FROM place_sources WHERE place_id = $1)",
    )
    .bind(moved)
    .execute(&pool)
    .await
    .unwrap();
    lunaway_conflate::run(
        &pool,
        Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap(),
        None,
    )
    .await
    .unwrap();
    let next = gql(
        &app,
        &changes_query(),
        json!({"region": "FR-PDL", "since": cursor}),
    )
    .await;
    let names: Vec<&str> = next["data"]["changes"]["places"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|p| p["name"].as_str())
        .collect();
    assert!(
        names.contains(&"Renamed after the pack"),
        "the change after the pack reaches the device: {next}"
    );

    // The next build makes a new pack of the region that changed only.
    let options = PackOptions {
        dir: dir.path().to_owned(),
        only: Vec::new(),
        takedown: false,
    };
    let rebuilt = build(&pool, ApiConfig::default(), &options)
        .await
        .unwrap()
        .built;
    let codes: Vec<&str> = rebuilt.iter().map(|b| b.pack.region.as_str()).collect();
    assert_eq!(
        codes,
        ["FR-PDL"],
        "a region nothing changed in keeps its pack and its version"
    );
    assert_eq!(
        rebuilt[0].removed,
        Vec::<String>::new(),
        "the previous pack stays for the devices that read the manifest before"
    );
    let again = build(&pool, ApiConfig::default(), &options).await.unwrap();
    assert_eq!(
        again,
        BuildReport::default(),
        "nothing changed since the last build"
    );

    // A takedown rebuilds the region and leaves no older file behind.
    let takedown = build(
        &pool,
        ApiConfig::default(),
        &PackOptions {
            dir: dir.path().to_owned(),
            only: vec!["FR-PDL".into()],
            takedown: true,
        },
    )
    .await
    .unwrap()
    .built;
    assert_eq!(takedown.len(), 1);
    let left: Vec<String> = std::fs::read_dir(dir.path().join("places"))
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|n| n.starts_with("FR-PDL-"))
        .collect();
    assert_eq!(
        left,
        [takedown[0]
            .pack
            .file
            .trim_start_matches("places/")
            .to_owned()],
        "no earlier pack of the region still serves what was taken down"
    );
    let pdl_after_takedown = left[0].clone();

    // A commune of Brittany now covers one place: it leaves the Pays de la
    // Loire. Its old region's feed says so, its new one has it, and the old
    // region's pack is built again.
    let before_move = gql(
        &app,
        &changes_query(),
        json!({"region": "FR-PDL", "since": null}),
    )
    .await["data"]["changes"]["cursor"]
        .as_str()
        .unwrap()
        .to_owned();
    let mover: (uuid::Uuid, f64, f64) = sqlx::query_as(
        "SELECT id, ST_Y(geom::geometry), ST_X(geom::geometry) FROM places \
         WHERE region = 'FR-PDL' AND deleted_at IS NULL ORDER BY id LIMIT 1",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO municipalities (code, name, geom, fetched_at) VALUES \
         ('35238', 'Rennes', ST_Multi(ST_Expand(ST_SetSRID(ST_MakePoint($1, $2), 4326), 0.001)), now())",
    )
    .bind(mover.2)
    .bind(mover.1)
    .execute(&pool)
    .await
    .unwrap();
    let mut tx = lunaway_db::conflation::begin_writer(&pool).await.unwrap();
    lunaway_db::municipalities::refresh_places(&mut tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let after_move = gql(
        &app,
        &changes_query(),
        json!({"region": "FR-PDL", "since": before_move}),
    )
    .await;
    assert_eq!(
        after_move["data"]["changes"]["left"],
        json!([mover.0.to_string()]),
        "the devices that keep the Pays de la Loire drop it: {after_move}"
    );
    assert_eq!(after_move["data"]["changes"]["deleted"], json!([]));
    let brittany = gql(
        &app,
        &changes_query(),
        json!({"region": "FR-BRE", "since": null}),
    )
    .await;
    assert_eq!(
        brittany["data"]["changes"]["places"][0]["id"],
        mover.0.to_string()
    );
    let moved = build(&pool, ApiConfig::default(), &options)
        .await
        .unwrap()
        .built;
    let mut codes: Vec<&str> = moved.iter().map(|b| b.pack.region.as_str()).collect();
    codes.sort_unstable();
    assert_eq!(
        codes,
        ["FR-BRE", "FR-PDL"],
        "the region a place left gets a new pack, not only the one it joined"
    );

    // Brittany's only place is taken down: a takedown leaves the region
    // without a pack and without a file, rather than its last pack, and
    // the Pays de la Loire, which the place left, without the previous
    // file that still holds it.
    let brittany_file = moved
        .iter()
        .find(|b| b.pack.region == "FR-BRE")
        .map(|b| b.pack.file.trim_start_matches("places/").to_owned())
        .unwrap();
    sqlx::query(
        "UPDATE places SET deleted_at = now(), updated_seq = nextval('place_change_seq') \
         WHERE id = $1",
    )
    .bind(mover.0)
    .execute(&pool)
    .await
    .unwrap();
    let takedown = PackOptions {
        dir: dir.path().to_owned(),
        only: vec!["FR-BRE".into()],
        takedown: true,
    };
    let withdrawn = build(&pool, ApiConfig::default(), &takedown).await.unwrap();
    assert_eq!(
        withdrawn,
        BuildReport {
            built: Vec::new(),
            dropped: vec![Dropped {
                region: "FR-BRE".into(),
                removed: vec![brittany_file],
            }],
            pruned: vec![pdl_after_takedown],
        }
    );
    let mut files: Vec<String> = std::fs::read_dir(dir.path().join("places"))
        .unwrap()
        .map(|e| format!("places/{}", e.unwrap().file_name().to_string_lossy()))
        .collect();
    files.sort_unstable();
    let mut recorded: Vec<String> = lunaway_db::packs::all(&pool)
        .await
        .unwrap()
        .into_iter()
        .map(|p| p.file)
        .collect();
    recorded.sort_unstable();
    assert_eq!(
        files, recorded,
        "after a takedown, the files left are the packs the manifest names"
    );
    let regions = gql(&app, "{ regions { code pack { url } } }", json!({})).await;
    let brittany = regions["data"]["regions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["code"] == "FR-BRE")
        .unwrap();
    assert_eq!(brittany["pack"], Value::Null, "the manifest names no file");
    let mistyped = PackOptions {
        only: vec!["FR-BRT".into()],
        ..takedown
    };
    assert!(matches!(
        build(&pool, ApiConfig::default(), &mistyped).await,
        Err(PackError::UnknownRegion(code)) if code == "FR-BRT"
    ));

    // Another place moves from the Pays de la Loire to Brittany and is taken
    // down before any build. The takedown names Brittany, where the place
    // is now; the Pays de la Loire, whose pack still holds it, is built
    // again too.
    let second: uuid::Uuid = sqlx::query_scalar(
        "SELECT id FROM places WHERE region = 'FR-PDL' AND deleted_at IS NULL ORDER BY id LIMIT 1",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    for change in [
        "UPDATE places SET municipality_code = '35238', \
         updated_seq = nextval('place_change_seq') WHERE id = $1",
        "UPDATE places SET deleted_at = now(), \
         updated_seq = nextval('place_change_seq') WHERE id = $1",
    ] {
        sqlx::query(change)
            .bind(second)
            .execute(&pool)
            .await
            .unwrap();
    }
    // What a build that stopped left: a pack it wrote and never recorded,
    // for a region with no place and no row, and its work files. An
    // operator's note stays.
    let places_dir = dir.path().join("places");
    let work_dir = dir.path().join(".work");
    let stray = "DE-1-0123456789ab.sqlite.gz";
    for path in [
        places_dir.join(stray),
        places_dir.join("notes.txt"),
        work_dir.join("raw-x.sqlite"),
        work_dir.join("FR-PDL-1-0123456789ab.sqlite.gz.partial"),
    ] {
        std::fs::write(path, b"x").unwrap();
    }
    let report = build(
        &pool,
        ApiConfig::default(),
        &PackOptions {
            dir: dir.path().to_owned(),
            only: vec!["fr-bre".into()],
            takedown: true,
        },
    )
    .await
    .unwrap();
    assert!(
        report.pruned.contains(&stray.to_owned()) && !places_dir.join(stray).exists(),
        "a pack no manifest names is not served after a takedown: {:?}",
        report.pruned
    );
    assert!(places_dir.join("notes.txt").exists());
    assert_eq!(
        std::fs::read_dir(&work_dir).unwrap().count(),
        0,
        "what a stopped build left in its work directory goes"
    );
    std::fs::remove_file(places_dir.join("notes.txt")).unwrap();
    let codes: Vec<&str> = report
        .built
        .iter()
        .map(|b| b.pack.region.as_str())
        .collect();
    assert_eq!(
        codes,
        ["FR-PDL"],
        "the region the place left is built again, without it"
    );
    let rebuilt = std::fs::read(dir.path().join(&report.built[0].pack.file)).unwrap();
    let ids: Vec<Value> = read_pack(&rebuilt, &report.built[0].pack.sha256)
        .into_iter()
        .map(|p| p["id"].clone())
        .collect();
    assert!(!ids.contains(&json!(second.to_string())));
    let mut files: Vec<String> = std::fs::read_dir(dir.path().join("places"))
        .unwrap()
        .map(|e| format!("places/{}", e.unwrap().file_name().to_string_lossy()))
        .collect();
    files.sort_unstable();
    let mut recorded: Vec<String> = lunaway_db::packs::all(&pool)
        .await
        .unwrap()
        .into_iter()
        .map(|p| p.file)
        .collect();
    recorded.sort_unstable();
    assert_eq!(files, recorded, "no older file of any region remains");

    let both = gql(
        &app,
        &changes_query().replace(
            "changes(region: $region",
            "changes(bbox: {south: 46, west: -2, north: 47, east: -1}, region: $region",
        ),
        json!({"region": "FR-PDL"}),
    )
    .await;
    assert_eq!(code(&both), "INVALID_INPUT", "a box or a region, not both");
    let unknown = gql(&app, &changes_query(), json!({"region": "XX-ZZZ"})).await;
    assert_eq!(code(&unknown), "INVALID_INPUT");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_build_waits_for_the_running_one_past_its_role_s_statement_timeout(pool: PgPool) {
    // As the import role in production: every statement bounded on the
    // server (10 minutes there, 300 ms here).
    let bounded = sqlx::postgres::PgPoolOptions::new()
        .max_connections(4)
        .connect_with(
            (*pool.connect_options())
                .clone()
                .options([("statement_timeout", "300ms")]),
        )
        .await
        .unwrap();
    let running = lunaway_db::packs::BuildLock::acquire(&pool).await.unwrap();
    let dir = tempfile::tempdir().unwrap();
    let options = PackOptions {
        dir: dir.path().to_owned(),
        only: Vec::new(),
        takedown: false,
    };
    let second = tokio::spawn(async move { build(&bounded, ApiConfig::default(), &options).await });
    tokio::time::sleep(std::time::Duration::from_millis(900)).await;
    assert!(
        !second.is_finished(),
        "a build started during another waits for it"
    );
    running.release().await.unwrap();
    let done = second.await.unwrap();
    assert!(
        done.is_ok(),
        "then runs, after three times its statement limit: {done:?}"
    );
}

#[tokio::test]
async fn a_persisted_query_runs_by_its_hash_once_the_server_knows_it() {
    let app = app(no_db());
    let document = "query Version { apiVersion }";
    let hash = lunaway_api::persisted::hash(document);
    let by_hash = json!({
        "operationName": "Version",
        "extensions": {"persistedQuery": {"version": 1, "sha256Hash": hash}},
    });

    let (status, unknown) = post(&app, by_hash.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        code(&unknown),
        "PERSISTED_QUERY_NOT_FOUND",
        "an Apollo client then sends the document with the hash"
    );
    assert_eq!(unknown["errors"][0]["message"], "PersistedQueryNotFound");

    let (status, wrong) = post(
        &app,
        json!({
            "query": "{ apiVersion }",
            "extensions": {"persistedQuery": {"version": 1, "sha256Hash": hash}},
        }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(
        code(&wrong),
        "INVALID_INPUT",
        "a hash that is not the document's"
    );

    let (_, broken) = post(
        &app,
        json!({
            "query": "{ noSuchField }",
            "extensions": {"persistedQuery": {"version": 1,
                "sha256Hash": lunaway_api::persisted::hash("{ noSuchField }")}},
        }),
    )
    .await;
    assert_eq!(code(&broken), "INVALID_INPUT");
    let (_, still_unknown) = post(
        &app,
        json!({"extensions": {"persistedQuery": {"version": 1,
            "sha256Hash": lunaway_api::persisted::hash("{ noSuchField }")}}}),
    )
    .await;
    assert_eq!(
        code(&still_unknown),
        "PERSISTED_QUERY_NOT_FOUND",
        "a document that failed is not kept"
    );

    let mut with_document = by_hash.clone();
    with_document["query"] = document.into();
    let (status, first) = post(&app, with_document).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(first["data"]["apiVersion"], env!("CARGO_PKG_VERSION"));
    let (status, again) = post(&app, by_hash).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        again["data"], first["data"],
        "the hash alone runs the document kept"
    );

    let (status, plain) = post(&app, json!({"query": document})).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "a document without a hash still runs"
    );
    assert_eq!(plain["data"], first["data"]);
    let (status, empty) = post(&app, json!({"variables": {}})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(code(&empty), "INVALID_INPUT");
}
