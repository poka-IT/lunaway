//! `Query.route` end to end: the API, a real Valhalla 3.9.0 serving a graph
//! built by `infra/routing/build-graph.sh`, and the restrictions of the same
//! build in a real database. The places are the measured cases of
//! `plan/research/07-navigation.md` (A.4), in Limousin.
//!
//! Heavy, so ignored by default: `infra/routing/e2e.sh` builds the Limousin
//! graph on a machine with Docker, serves it, and runs this file's ignored
//! tests with `LUNAWAY_E2E_VALHALLA_URL` (the engine, on loopback) and
//! `LUNAWAY_E2E_RESTRICTIONS` (the build's `restrictions.ndjson.gz`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::Duration;

use axum::{
    Router,
    body::Body,
    http::{Request, StatusCode},
};
use chrono::Utc;
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState, config::RoutingConfig};
use lunaway_db::{
    PgPool,
    routing::{self, NewGraph},
};
use serde_json::{Value, json};
use tower::ServiceExt;

const GRAPH: &str = "20261006T0000Z-e2e";

/// The engine and the restrictions file of the end-to-end run.
fn setup() -> (String, String) {
    let var = |k: &str| {
        std::env::var(k).unwrap_or_else(|_| panic!("{k} is not set: run infra/routing/e2e.sh"))
    };
    (
        var("LUNAWAY_E2E_VALHALLA_URL"),
        var("LUNAWAY_E2E_RESTRICTIONS"),
    )
}

async fn app(pool: PgPool, url: &str, file: &str) -> Router {
    let records = lunaway_ingest::routing::read_records(std::path::Path::new(file)).unwrap();
    routing::load_graph(
        &pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc::now(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc::now(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &records,
    )
    .await
    .unwrap();
    routing::activate(&pool, GRAPH).await.unwrap();
    let config = ApiConfig {
        routing: RoutingConfig {
            valhalla_url: Some(url.to_owned()),
            timeout: Duration::from_secs(10),
            ..RoutingConfig::default()
        },
        ..ApiConfig::default()
    };
    lunaway_api::router(ApiState::new(pool, config))
}

async fn route(app: &Router, from: [f64; 2], to: [f64; 2], height_m: f64, weight_t: f64) -> Value {
    let query = "query R($input: RouteInput!) { route(input: $input) {
        status osrmJson recalculations
        routes { distanceM warnings { kind severity limit externalId distanceFromStartM } }
        blockers { kind severity limit externalId distanceFromStartM } } }";
    let variables = json!({"input": {
        "origin": {"lat": from[0], "lon": from[1]},
        "destination": {"lat": to[0], "lon": to[1]},
        "vehicle": {"kind": "OVERCAB", "heightM": height_m, "widthM": 2.3, "lengthM": 7.4, "weightT": weight_t},
    }});
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    assert!(body["errors"].is_null(), "{body}");
    body["data"]["route"].clone()
}

const UTRILLO_FROM: [f64; 2] = [45.84719, 1.28476];
const UTRILLO_TO: [f64; 2] = [45.84510, 1.28637];

#[sqlx::test(migrations = "../../migrations")]
#[ignore = "needs a Valhalla server and a graph build: infra/routing/e2e.sh"]
async fn a_motorhome_goes_round_the_low_bridge_and_a_van_is_warned_under_it(pool: PgPool) {
    let (url, file) = setup();
    let app = app(pool, &url, &file).await;
    let high = route(&app, UTRILLO_FROM, UTRILLO_TO, 3.3, 3.5).await;
    assert_eq!(high["status"], "OK", "{high}");
    let d = high["routes"][0]["distanceM"].as_f64().unwrap();
    assert!(d > 1_000.0, "3.3 m goes round the 2.7 m bridge: {d} m");
    let van = route(&app, UTRILLO_FROM, UTRILLO_TO, 2.5, 3.3).await;
    assert_eq!(van["status"], "OK", "{van}");
    assert!(van["routes"][0]["distanceM"].as_f64().unwrap() < 500.0);
    let warning = van["routes"][0]["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["externalId"] == "way/52984577")
        .unwrap_or_else(|| panic!("the 2.7 m bridge is announced: {van}"));
    assert_eq!(warning["kind"], "LOW_CLEARANCE");
    assert_eq!(warning["severity"], "WARNING");
}

#[sqlx::test(migrations = "../../migrations")]
#[ignore = "needs a Valhalla server and a graph build: infra/routing/e2e.sh"]
async fn a_height_bar_the_engine_ignores_stops_the_route(pool: PgPool) {
    let (url, file) = setup();
    let app = app(pool, &url, &file).await;
    // Rue de la Brégère, Limoges: a 1.9 m height bar (node 348192004)
    // on the only way to the destination; Valhalla 3.9.0 routes a 3.3 m
    // vehicle under it.
    let r = route(&app, [45.8500, 1.2670], [45.85137, 1.26507], 3.3, 3.5).await;
    assert_eq!(r["status"], "NO_SAFE_ROUTE", "{r}");
    assert_eq!(r["osrmJson"], Value::Null);
    let blockers = r["blockers"].as_array().unwrap();
    assert!(
        blockers
            .iter()
            .any(|b| b["externalId"] == "node/348192004" && b["limit"] == 1.9),
        "{r}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
#[ignore = "needs a Valhalla server and a graph build: infra/routing/e2e.sh"]
async fn a_route_starting_under_the_bridge_is_not_given(pool: PgPool) {
    let (url, file) = setup();
    let app = app(pool, &url, &file).await;
    // Valhalla applies no limit to the edge a route starts on; the check
    // does.
    let r = route(&app, [45.84660, 1.28520], UTRILLO_FROM, 3.3, 3.5).await;
    assert_eq!(r["status"], "NO_SAFE_ROUTE", "{r}");
    assert!(
        r["blockers"]
            .as_array()
            .unwrap()
            .iter()
            .any(|b| b["kind"] == "LOW_CLEARANCE"),
        "{r}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
#[ignore = "needs a Valhalla server and a graph build: infra/routing/e2e.sh"]
async fn weight_and_motorhome_limits_hold(pool: PgPool) {
    let (url, file) = setup();
    let app = app(pool, &url, &file).await;
    // Rue du Pas Redon, Ussel: maxweightrating=3.5 alone.
    let heavy = route(&app, [45.53672, 2.15140], [45.53730, 2.15260], 3.3, 4.5).await;
    assert_eq!(heavy["status"], "OK", "{heavy}");
    assert!(
        heavy["routes"][0]["distanceM"].as_f64().unwrap() > 500.0,
        "{heavy}"
    );
    let light = route(&app, [45.53672, 2.15140], [45.53730, 2.15260], 3.3, 3.5).await;
    assert!(
        light["routes"][0]["distanceM"].as_f64().unwrap() < 500.0,
        "{light}"
    );
    // Route de Grandchamp: motorhome=no.
    let r = route(&app, [45.1500, 1.8760], [45.1488, 1.8690], 3.0, 3.5).await;
    assert_eq!(r["status"], "OK", "{r}");
    assert!(
        r["routes"][0]["distanceM"].as_f64().unwrap() > 1_500.0,
        "{r}"
    );
}

/// The duration of the recommended route from Limoges to Brive (the A20,
/// posted 130 and 110) for a motorhome of `weight_t` keeping to `cruise`.
async fn limoges_brive_s(app: &Router, weight_t: f64, cruise: Option<i32>) -> f64 {
    let mut vehicle = json!({"kind": "OVERCAB", "heightM": 3.0, "widthM": 2.3, "lengthM": 7.4, "weightT": weight_t});
    if let Some(kmh) = cruise {
        vehicle["cruiseSpeedKph"] = kmh.into();
    }
    let variables = json!({"input": {
        "origin": {"lat": 45.8336, "lon": 1.2611},
        "destination": {"lat": 45.1589, "lon": 1.5331},
        "vehicle": vehicle,
    }});
    let query =
        "query R($input: RouteInput!) { route(input: $input) { status routes { durationS } } }";
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    body["data"]["route"]["routes"][0]["durationS"]
        .as_f64()
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
#[ignore = "needs a Valhalla server and a graph build: infra/routing/e2e.sh"]
async fn a_driver_keeping_to_90_gets_a_longer_trip(pool: PgPool) {
    let (url, file) = setup();
    let app = app(pool, &url, &file).await;
    let free = limoges_brive_s(&app, 3.5, None).await;
    let at_90 = limoges_brive_s(&app, 3.5, Some(90)).await;
    assert!(
        at_90 > free * 1.05,
        "90 km/h on a motorway open at 130 takes longer: {at_90} s against {free} s"
    );
    let heavy = limoges_brive_s(&app, 4.5, None).await;
    assert!(heavy > free, "the 110 cap of a heavy motorhome: {heavy} s");
    let heavy_at_130 = limoges_brive_s(&app, 4.5, Some(130)).await;
    assert!(
        (heavy_at_130 - heavy).abs() < 1.0,
        "130 never lifts the 110 cap: {heavy_at_130} s against {heavy} s"
    );
}
