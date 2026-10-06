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
    packs::{PackOptions, build},
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
    lunaway_conflate::run(pool, Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap())
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
         places {{ {PLACE} }} deleted cursor hasMore }} }}"
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
        },
    )
    .await
    .unwrap();
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
    lunaway_conflate::run(&pool, Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap())
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
