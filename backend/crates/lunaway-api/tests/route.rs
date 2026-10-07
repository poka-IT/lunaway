//! `Query.route` through the router, against a fake routing engine on
//! loopback that answers with real shapes (the Rue Maurice Utrillo case,
//! Limoges: Valhalla 3.9.0 on the France graph of 2026-10-06) and records
//! what the API asks: the check after each route, the recalculation around
//! a blocker, and every limit and failure of the engine.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{Request, StatusCode},
    routing::{get, post},
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{
    ApiConfig, ApiState,
    config::{Quota, RoutingConfig},
};
use lunaway_db::{
    PgPool,
    routing::{self, NewGraph},
};
use lunaway_domain::{
    Position,
    routing::{
        Certainty, RestrictionFeature, RestrictionKind, RestrictionRecord, RestrictionSource,
        polyline,
    },
};
use serde_json::{Value, json};
use tower::ServiceExt;

/// A 2.5 m van's route under the 2.7 m railway bridge of Rue Maurice
/// Utrillo (way 52984577), 269 m.
const ROUTE_UNDER: &str = "yhhmvAshlmAD_@^wBlAcCnAiAvAy@jB_@tC]hDm@jj@q`@hd@c]~G_EjPyIlAu@";
/// A 3.3 m motorhome's route between the same points, around the bridge,
/// 2 020 m.
const ROUTE_AROUND: &str = "yhhmvAshlmAObBFtCZvCjAzFxFbPnKp_@l@hCx@bGD~Ds@~EaAvEwXttAwOb{@eAdGdLfQxBtD`BjCnAxBjA`CjAxCrEzLtBhF|AjDnAzBlA~AtA`BbB~AvHpHhD~ExF~LhF|NtGzQ~EzLn@zAlBbEpFuAn@S~b@iNxa@sOpNyDfSoCxCc@`Cs@fMoDjCoA|ByAzM{J`BmBfBiAde@uT~FeE|EaG|JqLnHkJdr@o{@}@_Aq|@}_AmAmArCy@vFiNpBeFGoCeBgJ_XuaA_YufAoAoFaBgDdEiDbRiWo@iA]s@}Pw[yF}GgKoF}g@cXq@OmCi@mGIeHvBaHvEak@p]";
const GRAPH: &str = "20261006T0300Z-fr";

fn osrm(geometries: &[&str]) -> Value {
    let routes: Vec<Value> = geometries
        .iter()
        .map(|g| {
            json!({
                "geometry": g,
                "distance": if *g == ROUTE_UNDER { 268.7 } else { 2020.3 },
                "duration": if *g == ROUTE_UNDER { 40.0 } else { 177.1 },
                "weight_name": "auto",
                "legs": [{"steps": [{
                    "mode": "driving",
                    "intersections": [{"classes": ["toll"]}],
                    "maneuver": {"instruction": "Ensuite, dans 60 mètres, Tournez à gauche."},
                    "voiceInstructions": [{"announcement": "Continuez sur Boulevard Voltaire.."}]
                }]}]
            })
        })
        .collect();
    json!({"code": "Ok", "routes": routes, "waypoints": []})
}

/// What the fake engine answers, in turn; the last answer repeats.
#[derive(Clone)]
struct Fake {
    answers: Arc<Vec<(u16, Value)>>,
    asked: Arc<Mutex<Vec<Value>>>,
    delay: Duration,
}

async fn fake_route(State(f): State<Fake>, Json(body): Json<Value>) -> (StatusCode, Json<Value>) {
    tokio::time::sleep(f.delay).await;
    let n = {
        let mut asked = f.asked.lock().unwrap();
        asked.push(body);
        asked.len()
    };
    let (status, answer) = f.answers[(n - 1).min(f.answers.len() - 1)].clone();
    (StatusCode::from_u16(status).unwrap(), Json(answer))
}

/// Starts a fake engine; its URL and the requests it receives.
async fn engine(answers: Vec<(u16, Value)>, delay: Duration) -> (String, Arc<Mutex<Vec<Value>>>) {
    let fake = Fake {
        answers: Arc::new(answers),
        asked: Arc::new(Mutex::new(Vec::new())),
        delay,
    };
    let asked = Arc::clone(&fake.asked);
    let app = Router::new()
        .route("/route", post(fake_route))
        .route(
            "/status",
            get(|| async { Json(json!({"version": "3.9.0"})) }),
        )
        .with_state(fake);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

fn config(url: &str) -> ApiConfig {
    ApiConfig {
        routing: RoutingConfig {
            valhalla_url: Some(url.to_owned()),
            timeout: Duration::from_millis(500),
            concurrency: 4,
            queue_wait: Duration::from_millis(200),
        },
        ..ApiConfig::default()
    }
}

fn tunnel_record() -> (RestrictionRecord, Vec<Position>) {
    let points = vec![
        Position::new(45.846_841, 1.285_024).unwrap(),
        Position::new(45.846_147, 1.285_561).unwrap(),
    ];
    let r = RestrictionRecord {
        source: RestrictionSource::Osm,
        external_id: "way/52984577".to_owned(),
        kind: RestrictionKind::MaxHeight,
        limit: Some(2.7),
        certainty: Certainty::Known,
        feature: RestrictionFeature::Underpass,
        name: Some("Rue Maurice Utrillo".to_owned()),
        other_value: None,
        other_source: None,
        shape: polyline::encode(&points),
        observed_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 20, 43).unwrap(),
    };
    (r, points)
}

async fn seed(pool: &PgPool) {
    routing::load_graph(
        pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 20, 43).unwrap(),
            ign_fetched_at: None,
            ign_edition: chrono::NaiveDate::from_ymd_opt(2026, 6, 15),
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 7, 0, 0).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[tunnel_record()],
    )
    .await
    .unwrap();
    routing::activate(pool, GRAPH).await.unwrap();
}

const ROUTE_QUERY: &str = r"
query Route($input: RouteInput!) {
  route(input: $input) {
    status osrmJson recalculations disclaimerKey
    routes { index distanceM durationS hasToll hasFerry hasMotorway
      warnings { kind severity limit vehicleValue distanceFromStartM geometryIndex lat lon source certainty place name externalId } }
    blockers { kind severity limit externalId distanceFromStartM }
    reroute { vehicle { kind heightM } options { avoidTolls } language costingOptionsJson }
    graph { id osmDataAt }
  }
}";

fn input(height_m: f64) -> Value {
    json!({"input": {
        "origin": {"lat": 45.84719, "lon": 1.28476},
        "destination": {"lat": 45.84510, "lon": 1.28637},
        "vehicle": {"kind": "OVERCAB", "heightM": height_m, "widthM": 2.3, "lengthM": 7.4, "weightT": 3.5},
        "options": {"avoidTolls": true},
        "language": "FR"
    }})
}

async fn gql(app: &Router, query: &str, variables: Value) -> (StatusCode, Value) {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

fn code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or("")
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_under_a_bridge_too_low_is_computed_again_around_it(pool: PgPool) {
    seed(&pool).await;
    let (url, asked) = engine(
        vec![(200, osrm(&[ROUTE_UNDER])), (200, osrm(&[ROUTE_AROUND]))],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(r["recalculations"], 1);
    let osrm: Value = serde_json::from_str(r["osrmJson"].as_str().unwrap()).unwrap();
    assert_eq!(
        osrm["routes"][0]["geometry"], ROUTE_AROUND,
        "a 3.3 m motorhome must never be sent under a 2.7 m bridge"
    );
    assert_eq!(r["routes"][0]["warnings"], json!([]));
    assert_eq!(r["routes"][0]["hasToll"], true);
    assert_eq!(r["graph"]["id"], GRAPH);
    assert_eq!(r["disclaimerKey"], "routing.disclaimer.v1");

    let asked = asked.lock().unwrap();
    assert_eq!(asked.len(), 2);
    let first = &asked[0];
    assert_eq!(first["costing"], "auto");
    assert_eq!(first["costing_options"]["auto"]["height"], 3.3);
    assert_eq!(first["costing_options"]["auto"]["use_tolls"], 0.0);
    assert_eq!(first["format"], "osrm");
    assert!(first.get("exclude_polygons").is_none());
    let ring = asked[1]["exclude_polygons"][0].as_array().unwrap();
    assert_eq!(ring.len(), 9, "an octagon, closed");
    let (lon, lat) = (ring[0][0].as_f64().unwrap(), ring[0][1].as_f64().unwrap());
    let centre = Position::new(45.846_494, 1.285_292).unwrap();
    assert!(
        Position::new(lat, lon).unwrap().distance_m(centre) < 10.0,
        "the ring sits on the road under the bridge, halfway through it"
    );
    // The French instructions passed on are corrected.
    let step = &osrm["routes"][0]["legs"][0]["steps"][0];
    assert_eq!(
        step["maneuver"]["instruction"],
        "Ensuite, dans 60 mètres, tournez à gauche."
    );
    assert_eq!(
        step["voiceInstructions"][0]["announcement"],
        "Continuez sur Boulevard Voltaire."
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_van_that_fits_is_warned_of_a_close_clearance(pool: PgPool) {
    seed(&pool).await;
    let (url, asked) = engine(vec![(200, osrm(&[ROUTE_UNDER]))], Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(2.5)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(r["recalculations"], 0);
    let w = &r["routes"][0]["warnings"][0];
    assert_eq!(w["kind"], "LOW_CLEARANCE");
    assert_eq!(w["severity"], "WARNING");
    assert_eq!(w["limit"], 2.7);
    assert_eq!(w["vehicleValue"], 2.5);
    assert_eq!(w["place"], "UNDERPASS");
    assert_eq!(w["source"], "OSM");
    assert_eq!(w["externalId"], "way/52984577");
    assert_eq!(
        w["geometryIndex"], 8,
        "the shape point where the bridge starts"
    );
    let d = w["distanceFromStartM"].as_f64().unwrap();
    assert!((40.0..60.0).contains(&d), "{d}");
    assert_eq!(asked.lock().unwrap().len(), 1);
    assert_eq!(r["reroute"]["vehicle"]["heightM"], 2.5);
    assert!(
        r["reroute"]["costingOptionsJson"]
            .as_str()
            .unwrap()
            .contains("\"height\":2.5")
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn when_every_way_meets_the_bridge_no_route_is_given(pool: PgPool) {
    seed(&pool).await;
    // An engine that keeps going under, whatever is excluded.
    let (url, asked) = engine(vec![(200, osrm(&[ROUTE_UNDER]))], Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "NO_SAFE_ROUTE", "{body}");
    assert_eq!(
        r["osrmJson"],
        Value::Null,
        "a route with a blocker never reaches the app"
    );
    assert_eq!(r["routes"], json!([]));
    assert_eq!(r["blockers"][0]["kind"], "LOW_CLEARANCE");
    assert_eq!(r["blockers"][0]["severity"], "BLOCKING");
    assert_eq!(r["blockers"][0]["externalId"], "way/52984577");
    assert_eq!(
        asked.lock().unwrap().len(),
        2,
        "the same ring again changes nothing: the API stops asking"
    );

    // An engine that finds no way once the bridge is excluded.
    let (url, _) = engine(
        vec![
            (200, osrm(&[ROUTE_UNDER])),
            (
                400,
                json!({"code": "NoRoute", "message": "Impossible route between points"}),
            ),
        ],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(body["data"]["route"]["status"], "NO_SAFE_ROUTE", "{body}");
    assert_eq!(body["data"]["route"]["recalculations"], 1);
    assert_eq!(body["data"]["route"]["blockers"][0]["limit"], 2.7);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_engine_s_refusals_and_failures_reach_the_app_as_codes(pool: PgPool) {
    seed(&pool).await;
    for (answer, status) in [
        (
            json!({"code": "NoRoute", "message": "Impossible route between points"}),
            "NO_ROUTE",
        ),
        (
            json!({"code": "NoSegment", "message": "One of the supplied input coordinates could not snap"}),
            "OFF_NETWORK",
        ),
    ] {
        let (url, _) = engine(vec![(400, answer)], Duration::ZERO).await;
        let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
        let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
        assert_eq!(body["data"]["route"]["status"], status, "{body}");
    }
    let (url, _) = engine(
        vec![(
            400,
            json!({"code": "InvalidOptions", "message": "Options are invalid."}),
        )],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(
        code(&body),
        "INVALID_INPUT",
        "a request the engine refuses is the client's: {body}"
    );

    // Slower than the timeout.
    let (url, _) = engine(vec![(200, osrm(&[ROUTE_AROUND]))], Duration::from_secs(2)).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(code(&body), "UNAVAILABLE", "{body}");

    // Nothing listening.
    let closed = {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        format!("http://{}", l.local_addr().unwrap())
    };
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&closed)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(code(&body), "UNAVAILABLE", "{body}");

    // An engine on another host is never called.
    let mut remote = ApiConfig::from_lookup(|k| {
        (k == "LUNAWAY_VALHALLA_URL").then(|| "http://10.42.0.3:8002".to_owned())
    });
    remote.routing.timeout = Duration::from_millis(200);
    let app = lunaway_api::router(ApiState::new(pool, remote));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(code(&body), "UNAVAILABLE", "{body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failure_of_the_server_does_not_cost_the_client_a_route(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = engine(
        vec![
            (500, json!({"code": "InternalError", "message": "boom"})),
            (200, osrm(&[ROUTE_AROUND])),
        ],
        Duration::ZERO,
    )
    .await;
    let mut c = config(&url);
    c.quotas.route = Quota {
        count: 1,
        period: Duration::from_secs(600),
    };
    let app = lunaway_api::router(ApiState::new(pool, c));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(code(&body), "UNAVAILABLE", "{body}");
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(
        body["data"]["route"]["status"], "OK",
        "the failed attempt was given back: {body}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_recalculation_that_moves_a_stop_or_loses_its_road_gives_no_route(pool: PgPool) {
    seed(&pool).await;
    // The ring on the bridge took the road a stop lies on.
    let (url, _) = engine(
        vec![
            (200, osrm(&[ROUTE_UNDER])),
            (
                400,
                json!({"code": "NoSegment", "message": "could not snap"}),
            ),
        ],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(
        body["data"]["route"]["status"], "NO_SAFE_ROUTE",
        "not OFF_NETWORK: the point is on a road, behind the bridge: {body}"
    );
    // The engine snapped the destination to another road 400 m away.
    let mut first = osrm(&[ROUTE_UNDER]);
    first["waypoints"] = json!([{"distance": 2.0}, {"distance": 3.0}]);
    let mut moved = osrm(&[ROUTE_AROUND]);
    moved["waypoints"] = json!([{"distance": 2.0}, {"distance": 400.0}]);
    let (url, _) = engine(vec![(200, first), (200, moved)], Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(
        body["data"]["route"]["status"], "NO_SAFE_ROUTE",
        "a route to another place is not the trip asked for: {body}"
    );
    assert_eq!(
        body["data"]["route"]["blockers"][0]["externalId"],
        "way/52984577"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn no_active_graph_means_unavailable(pool: PgPool) {
    let (url, asked) = engine(vec![(200, osrm(&[ROUTE_AROUND]))], Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(code(&body), "UNAVAILABLE", "{body}");
    assert!(asked.lock().unwrap().is_empty());
    let (_, body) = gql(&app, "{ routing { available graph { id } } }", json!({})).await;
    assert_eq!(
        body["data"]["routing"],
        json!({"available": false, "graph": null})
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_bad_request_costs_the_engine_nothing(pool: PgPool) {
    seed(&pool).await;
    let (url, asked) = engine(vec![(200, osrm(&[ROUTE_AROUND]))], Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    // El Hierro to the North Cape, 5 300 km in a straight line.
    let mut far = input(3.3);
    far["input"]["origin"] = json!({"lat": 27.75, "lon": -18.0});
    far["input"]["destination"] = json!({"lat": 70.98, "lon": 25.97});
    let mut tall = input(3.3);
    tall["input"]["vehicle"]["heightM"] = json!(330.0);
    let mut waypoints = input(3.3);
    waypoints["input"]["waypoints"] = Value::Array(vec![json!({"lat": 45.85, "lon": 1.28}); 6]);
    let mut alternatives = input(3.3);
    alternatives["input"]["alternatives"] = json!(3);
    for (what, variables) in [
        ("a trip longer than 3 000 km", far),
        ("a height in centimetres", tall),
        ("six waypoints", waypoints),
        ("three alternatives", alternatives),
    ] {
        let (_, body) = gql(&app, ROUTE_QUERY, variables).await;
        assert_eq!(code(&body), "INVALID_INPUT", "{what}: {body}");
    }
    assert!(
        asked.lock().unwrap().is_empty(),
        "nothing reached the engine"
    );
    let (_, body) = gql(
        &app,
        "query { a: route(input: {origin: {lat: 45.8, lon: 1.2}, destination: {lat: 45.9, lon: 1.3},
           vehicle: {kind: VAN, heightM: 2, widthM: 2, lengthM: 5, weightT: 3}}) { status }
         b: route(input: {origin: {lat: 45.8, lon: 1.2}, destination: {lat: 45.9, lon: 1.3},
           vehicle: {kind: VAN, heightM: 2, widthM: 2, lengthM: 5, weightT: 3}}) { status } }",
        json!({}),
    )
    .await;
    assert_eq!(
        code(&body),
        "INVALID_INPUT",
        "two routes in one request: {body}"
    );
    assert!(
        asked.lock().unwrap().len() <= 1,
        "one request reaches the engine for one route at most"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_client_s_routes_are_counted_and_the_engine_s_calls_capped(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = engine(vec![(200, osrm(&[ROUTE_AROUND]))], Duration::ZERO).await;
    let mut c = config(&url);
    c.quotas.route = Quota {
        count: 2,
        period: Duration::from_secs(600),
    };
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    for _ in 0..2 {
        let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
        assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    }
    let (status, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(code(&body), "RATE_LIMITED", "{body}");
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
    assert!(
        body["errors"][0]["extensions"]["retryAfterSeconds"]
            .as_u64()
            .unwrap()
            > 0
    );

    // One engine call at a time, a slow engine, two clients at once.
    let (url, _) = engine(
        vec![(200, osrm(&[ROUTE_AROUND]))],
        Duration::from_millis(400),
    )
    .await;
    let mut c = config(&url);
    c.routing.concurrency = 1;
    c.routing.queue_wait = Duration::from_millis(50);
    c.routing.timeout = Duration::from_secs(2);
    let app = lunaway_api::router(ApiState::new(pool, c));
    let (a, b) = tokio::join!(
        gql(&app, ROUTE_QUERY, input(3.3)),
        gql(&app, ROUTE_QUERY, input(3.3))
    );
    let codes = [code(&a.1).to_owned(), code(&b.1).to_owned()];
    assert!(
        codes.contains(&"RATE_LIMITED".to_owned()) && codes.contains(&String::new()),
        "one is served, the other told to wait: {codes:?}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_app_learns_the_data_date_the_bounds_and_the_presets(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = engine(vec![(200, osrm(&[ROUTE_AROUND]))], Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(
        &app,
        "{ routing { available disclaimerKey maxWaypoints maxAlternatives
             graph { id osmDataAt builtAt ignEdition }
             coveredArea { south west north east }
             vehicleBounds { heightM { min max } }
             vehiclePresets { id kind heightM weightT source }
             trailerPresets { id lengthM } } }",
        json!({}),
    )
    .await;
    let r = &body["data"]["routing"];
    assert_eq!(r["available"], true, "{body}");
    assert_eq!(r["graph"]["id"], GRAPH);
    assert_eq!(r["graph"]["osmDataAt"], "2026-10-05T20:20:43+00:00");
    assert_eq!(
        r["graph"]["ignEdition"], "2026-06-15",
        "the IGN attribution names its edition"
    );
    assert_eq!(r["maxWaypoints"], 5);
    assert_eq!(
        r["vehicleBounds"]["heightM"],
        json!({"min": 1.5, "max": 4.5})
    );
    let presets = r["vehiclePresets"].as_array().unwrap();
    assert_eq!(presets.len(), lunaway_domain::routing::PRESETS.len());
    assert!(
        presets
            .iter()
            .all(|p| !p["source"].as_str().unwrap().is_empty()),
        "every preset names its source"
    );
    assert_eq!(r["trailerPresets"][0]["id"], "car-trailer");
}

/// The route from Limoges to Brive on the A20 (Valhalla 3.9.0, Limousin
/// extract of 2026-10-04), and the engine's description of its 273 edges
/// (`trace_attributes`, `edge_walk`), recorded on 2026-10-06.
const LIMOGES_BRIVE: &str =
    include_str!("../../lunaway-domain/tests/fixtures/route_limoges_brive.polyline6");
const TRACE_LIMOGES_BRIVE: &str = include_str!("fixtures/trace_limoges_brive.json");

/// An engine that answers every route with Limoges to Brive, and every
/// trace with `trace`; the traces it was asked.
async fn traced_engine(trace: (u16, Value)) -> (String, Arc<Mutex<Vec<Value>>>) {
    let geometry = LIMOGES_BRIVE.trim().to_owned();
    let points = polyline::decode(&geometry).unwrap();
    let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    let route = json!({"code": "Ok", "waypoints": [], "routes": [{
        "geometry": geometry, "distance": distance, "duration": distance / 25.0,
        "weight_name": "auto",
        "legs": [{"distance": distance, "steps": [{"mode": "driving", "distance": distance,
            "intersections": [{"classes": ["motorway"]}]}]}]
    }]});
    let asked = Arc::new(Mutex::new(Vec::new()));
    let traces = Arc::clone(&asked);
    let app = Router::new()
        .route(
            "/route",
            post(move || {
                let route = route.clone();
                async move { Json(route) }
            }),
        )
        .route(
            "/trace_attributes",
            post(move |Json(body): Json<Value>| {
                let trace = trace.clone();
                let traces = Arc::clone(&traces);
                async move {
                    traces.lock().unwrap().push(body);
                    (StatusCode::from_u16(trace.0).unwrap(), Json(trace.1))
                }
            }),
        );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

const LIMITS_QUERY: &str = r"
query Route($input: RouteInput!) {
  route(input: $input) {
    status
    routes { distanceM speedLimits { fromM toM fromIndex toIndex kmh source } }
  }
}";

fn weighing(weight_t: f64) -> Value {
    let mut v = input(3.0);
    v["input"]["vehicle"]["weightT"] = weight_t.into();
    v
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_carries_the_speed_limits_of_its_vehicle(pool: PgPool) {
    seed(&pool).await;
    let trace: Value = serde_json::from_str(TRACE_LIMOGES_BRIVE).unwrap();
    let (url, traces) = traced_engine((200, trace)).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let (_, body) = gql(&app, LIMITS_QUERY, weighing(4.5)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    let spans = r["routes"][0]["speedLimits"].as_array().unwrap();
    assert!(spans.len() > 10, "{spans:?}");
    let length = r["routes"][0]["distanceM"].as_f64().unwrap();
    let mut at = 0.0;
    for s in spans {
        let (from, to) = (s["fromM"].as_f64().unwrap(), s["toM"].as_f64().unwrap());
        assert!(from >= at - 0.1 && to > from && to <= length + 1.0, "{s}");
        at = to;
        assert!(
            s["kmh"].as_i64().unwrap() <= 110,
            "a motorhome over 3.5 t never above 110 in France: {s}"
        );
    }
    let has = |kmh: i64, source: &str| {
        spans
            .iter()
            .any(|s| s["kmh"] == kmh && s["source"] == source)
    };
    assert!(
        has(110, "VEHICLE"),
        "the A20's 130 is 110 for it (R413-8-1)"
    );
    assert!(
        has(100, "VEHICLE"),
        "a dual carriageway without a sign: 100"
    );
    assert!(has(50, "POSTED"), "the towns' signs stand");
    {
        let traces = traces.lock().unwrap();
        assert_eq!(traces.len(), 1, "95 km traced at once");
        assert_eq!(traces[0]["shape_match"], "edge_walk");
        let traced = polyline::decode(traces[0]["encoded_polyline"].as_str().unwrap()).unwrap();
        assert_eq!(traced.len(), 1_661, "the route's own shape");
    }

    // A car-sized motorhome keeps the signs, and the defaults where none.
    let (_, body) = gql(&app, LIMITS_QUERY, weighing(3.5)).await;
    let spans = body["data"]["route"]["routes"][0]["speedLimits"]
        .as_array()
        .unwrap()
        .clone();
    assert!(
        spans
            .iter()
            .any(|s| s["kmh"] == 130 && s["source"] == "POSTED")
    );
    assert!(
        spans
            .iter()
            .any(|s| s["kmh"] == 110 && s["source"] == "DEFAULT")
    );
    assert!(!spans.iter().any(|s| s["source"] == "VEHICLE"));

    // A route asked without its limits costs the engine no trace.
    let before = traces.lock().unwrap().len();
    let (_, body) = gql(
        &app,
        "query Route($input: RouteInput!) { route(input: $input) { status routes { distanceM } } }",
        weighing(4.5),
    )
    .await;
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    assert_eq!(traces.lock().unwrap().len(), before);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_stands_without_limits_when_the_engine_cannot_trace_it(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = traced_engine((
        400,
        json!({"error_code": 443, "error": "Exact route match algorithm failed to find path"}),
    ))
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, LIMITS_QUERY, weighing(4.5)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(r["routes"][0]["speedLimits"], Value::Null);
}

/// An engine that answers every route with Limoges to Brive, refuses to
/// trace any stretch that starts at the route's first point, as Valhalla
/// 3.9 refused the start of the routes from Brest to Krakow, and traces any
/// other stretch as one motorway edge signed 130; the number of points of
/// each trace it was asked, and whether it refused it.
async fn picky_tracer() -> (String, Arc<Mutex<Vec<(usize, bool)>>>) {
    let geometry = LIMOGES_BRIVE.trim().to_owned();
    let points = polyline::decode(&geometry).unwrap();
    let start = points[0];
    let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    let route = json!({"code": "Ok", "waypoints": [], "routes": [{
        "geometry": geometry, "distance": distance, "duration": distance / 25.0,
        "weight_name": "auto",
        "legs": [{"distance": distance, "steps": [{"mode": "driving", "distance": distance,
            "intersections": [{"classes": ["motorway"]}]}]}]
    }]});
    let asked = Arc::new(Mutex::new(Vec::new()));
    let traces = Arc::clone(&asked);
    let app = Router::new()
        .route(
            "/route",
            post(move || {
                let route = route.clone();
                async move { Json(route) }
            }),
        )
        .route(
            "/trace_attributes",
            post(move |Json(body): Json<Value>| {
                let traces = Arc::clone(&traces);
                async move {
                    let shape =
                        polyline::decode(body["encoded_polyline"].as_str().unwrap()).unwrap();
                    let refused = shape[0] == start;
                    traces.lock().unwrap().push((shape.len(), refused));
                    if refused {
                        return (
                            StatusCode::BAD_REQUEST,
                            Json(json!({"error_code": 443,
                                "error": "Exact route match algorithm failed to find path"})),
                        );
                    }
                    (
                        StatusCode::OK,
                        Json(
                            json!({"edges": [{"speed_limit": 130, "road_class": "motorway",
                            "use": "road", "density": 1, "traversability": "forward",
                            "begin_shape_index": 0, "end_shape_index": shape.len() - 1}]}),
                        ),
                    )
                }
            }),
        );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_stretch_the_engine_cannot_walk_is_left_without_limits_and_the_rest_keeps_them(
    pool: PgPool,
) {
    seed(&pool).await;
    let (url, traces) = picky_tracer().await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, LIMITS_QUERY, weighing(3.5)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    let spans = r["routes"][0]["speedLimits"].as_array().unwrap();
    let length = r["routes"][0]["distanceM"].as_f64().unwrap();
    assert_eq!(spans.len(), 1, "{spans:?}");
    let from = spans[0]["fromM"].as_f64().unwrap();
    assert!(
        from > 0.0 && from < 1_500.0,
        "only the first few points go without a limit: {from} m"
    );
    assert!((spans[0]["toM"].as_f64().unwrap() - length).abs() < 1.0);
    let traces = traces.lock().unwrap();
    assert!(
        traces.iter().filter(|(_, refused)| *refused).count() <= 12,
        "one bad place costs a refusal per level of halves: {traces:?}"
    );
    assert!(
        traces.iter().any(|(n, refused)| *n <= 17 && *refused),
        "halved down to a few points: {traces:?}"
    );
}

/// A trip whose stops lie about 20 km from the bridge of Rue Maurice
/// Utrillo: farther than a restriction excluded ahead may lie from a stop.
/// The fake engine answers the shapes it is given.
fn far_input(height_m: f64) -> Value {
    json!({"input": {
        "origin": {"lat": 45.70, "lon": 1.10},
        "destination": {"lat": 46.00, "lon": 1.45},
        "vehicle": {"kind": "OVERCAB", "heightM": height_m, "widthM": 2.3, "lengthM": 7.4, "weightT": 3.5},
        "language": "FR"
    }})
}

/// The stops of [`far_input`], as the seeds of the routes that look for
/// the restrictions to exclude ahead.
const FAR_SEEDS: [(f64, f64); 2] = [(45.70, 1.10), (46.00, 1.45)];

/// The bridge of Rue Maurice Utrillo marked as a height barrier: a ring
/// under a bridge would cut the road above it too, so among height limits
/// only barriers are excluded ahead.
async fn as_barrier(pool: &PgPool) {
    sqlx::query(
        "UPDATE route_restrictions SET feature = 'barrier' WHERE external_id = 'way/52984577'",
    )
    .execute(pool)
    .await
    .unwrap();
}

/// The centres of the rings a request sent.
fn rings(request: &Value) -> Vec<Position> {
    request["exclude_polygons"]
        .as_array()
        .map(|rings| {
            rings
                .iter()
                .map(|ring| {
                    let points: Vec<(f64, f64)> = ring
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|p| (p[1].as_f64().unwrap(), p[0].as_f64().unwrap()))
                        .collect();
                    #[allow(clippy::cast_precision_loss, reason = "nine points")]
                    let n = (points.len() - 1) as f64;
                    let lat = points[..points.len() - 1].iter().map(|p| p.0).sum::<f64>() / n;
                    let lon = points[..points.len() - 1].iter().map(|p| p.1).sum::<f64>() / n;
                    Position::new(lat, lon).unwrap()
                })
                .collect()
        })
        .unwrap_or_default()
}

/// The answers of the routes between the seeds for the classes the bridge
/// stops (up to 3.0 m and above): under it, then around it, for each. The
/// vans' class has nothing to look for and costs no call.
fn seed_answers() -> Vec<(u16, Value)> {
    vec![
        (200, osrm(&[ROUTE_UNDER])),
        (200, osrm(&[ROUTE_AROUND])),
        (200, osrm(&[ROUTE_UNDER])),
        (200, osrm(&[ROUTE_AROUND])),
    ]
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_restriction_met_between_public_points_is_excluded_from_the_first_call(pool: PgPool) {
    seed(&pool).await;
    as_barrier(&pool).await;
    let mut answers = vec![(200, osrm(&[ROUTE_UNDER])), (200, osrm(&[ROUTE_AROUND]))];
    answers.extend(seed_answers());
    answers.push((200, osrm(&[ROUTE_AROUND])));
    let (url, asked) = engine(answers, Duration::ZERO).await;
    let state = ApiState::new(pool.clone(), config(&url));
    let app = lunaway_api::router(state.clone());
    // Before any list is computed, a trip excludes nothing ahead, and what
    // it meets is kept nowhere.
    let (_, body) = gql(&app, ROUTE_QUERY, far_input(3.3)).await;
    assert_eq!(body["data"]["route"]["recalculations"], 1, "{body}");
    let done = state.refresh_route_blockers_from(&FAR_SEEDS).await.unwrap();
    assert_eq!(done.graph_id, GRAPH);
    assert_eq!(
        done.kept,
        [0, 1, 1],
        "the bridge stops the low and the high classes"
    );
    assert_eq!(done.calls, 4, "under then around, for each of the two");
    assert!(
        state
            .refresh_route_blockers_from(&FAR_SEEDS)
            .await
            .is_none(),
        "nothing changed: nothing computed again"
    );
    let (_, body) = gql(&app, ROUTE_QUERY, far_input(3.3)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(
        r["recalculations"], 0,
        "the bridge is excluded from the start of the trip"
    );
    // A van under the bridge's height is not kept from it.
    let (_, body) = gql(&app, ROUTE_QUERY, far_input(2.5)).await;
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    // Nor is a trip that starts at the bridge: a ring there could move its
    // stop to another road.
    let (_, body) = gql(&app, ROUTE_QUERY, input(3.3)).await;
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    {
        let asked = asked.lock().unwrap();
        assert_eq!(
            asked.len(),
            9,
            "two calls for the first trip, four between the seeds, then one per trip"
        );
        assert!(
            asked[2].get("voice_instructions").is_none() && rings(&asked[2]).is_empty(),
            "the seeds' routes ask the shapes only"
        );
        assert_eq!(rings(&asked[3]).len(), 1, "the seeds' route around it");
        let centre = Position::new(45.846_494, 1.285_292).unwrap();
        let ahead = rings(&asked[6]);
        assert!(
            ahead.len() == 1 && ahead[0].distance_m(centre) < 10.0,
            "the trip's first call excludes the bridge: {ahead:?}"
        );
        assert!(
            rings(&asked[7]).is_empty(),
            "the van's call excludes nothing"
        );
        assert!(
            rings(&asked[8]).is_empty(),
            "nor the call of a trip from the bridge"
        );
    }

    // A new graph: the old one's list is never used on it.
    routing::load_graph(
        &pool,
        &NewGraph {
            id: "20261013T0300Z-fr".to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 12, 20, 20, 43).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 13, 7, 0, 0).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[tunnel_record()],
    )
    .await
    .unwrap();
    routing::activate(&pool, "20261013T0300Z-fr").await.unwrap();
    gql(&app, ROUTE_QUERY, far_input(3.3)).await;
    let asked = asked.lock().unwrap();
    assert!(
        rings(&asked[9]).is_empty(),
        "the old graph's list is not used on the new one"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_trip_closed_by_a_restriction_excluded_ahead_is_asked_again_without_it(pool: PgPool) {
    seed(&pool).await;
    as_barrier(&pool).await;
    let no_route = (
        400,
        json!({"code": "NoRoute", "message": "Impossible route between points"}),
    );
    let mut answers = seed_answers();
    answers.extend([
        no_route,
        (200, osrm(&[ROUTE_UNDER])),
        (200, osrm(&[ROUTE_AROUND])),
    ]);
    let (url, asked) = engine(answers, Duration::ZERO).await;
    let state = ApiState::new(pool, config(&url));
    let app = lunaway_api::router(state.clone());
    state.refresh_route_blockers_from(&FAR_SEEDS).await.unwrap();
    let (_, body) = gql(&app, ROUTE_QUERY, far_input(3.3)).await;
    let r = &body["data"]["route"];
    assert_eq!(
        r["status"], "OK",
        "a way the ring closed is found as it would be without it: {body}"
    );
    assert_eq!(r["recalculations"], 1);
    let asked = asked.lock().unwrap();
    assert_eq!(asked.len(), 7);
    assert_eq!(rings(&asked[4]).len(), 1);
    assert!(
        rings(&asked[5]).is_empty(),
        "asked again without the restrictions excluded ahead"
    );
    assert_eq!(rings(&asked[6]).len(), 1, "then around the blocker it met");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_trip_left_without_a_safe_route_by_restrictions_excluded_ahead_is_asked_again(
    pool: PgPool,
) {
    seed(&pool).await;
    as_barrier(&pool).await;
    let mut answers = seed_answers();
    answers.extend([
        // The ring sent ahead and still the bridge: nothing new to
        // exclude, no safe route with the restrictions excluded ahead.
        (200, osrm(&[ROUTE_UNDER])),
        (200, osrm(&[ROUTE_UNDER])),
        (200, osrm(&[ROUTE_AROUND])),
    ]);
    let (url, asked) = engine(answers, Duration::ZERO).await;
    let state = ApiState::new(pool, config(&url));
    let app = lunaway_api::router(state.clone());
    state.refresh_route_blockers_from(&FAR_SEEDS).await.unwrap();
    let (_, body) = gql(&app, ROUTE_QUERY, far_input(3.3)).await;
    let r = &body["data"]["route"];
    assert_eq!(
        r["status"], "OK",
        "the trip ends as it would without them: {body}"
    );
    let asked = asked.lock().unwrap();
    assert_eq!(asked.len(), 7);
    assert_eq!(rings(&asked[4]).len(), 1, "the ring ahead");
    assert!(rings(&asked[5]).is_empty(), "then the trip from scratch");
    assert_eq!(rings(&asked[6]).len(), 1, "around the bridge it met");
}
