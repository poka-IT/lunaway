//! What `Query.route` says when no route comes back, and what it says of
//! the ferries a route takes, against the routing engine's real answers:
//! each trip's calls were recorded on the Europe graph
//! (`fixtures/no_route/*.json`, `plan/research/40-backend-routage-europe.md`)
//! and the fake engine answers them again in the same order.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::sync::{Arc, Mutex};

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

const GRAPH: &str = "20261006T2326Z-eu";

/// The recorded answers of a trip, in the order the API asked.
fn recorded(name: &str) -> Vec<(u16, Value)> {
    let text = match name {
        "toulouse" => include_str!("fixtures/no_route/toulouse.json"),
        "warsaw" => include_str!("fixtures/no_route/warsaw.json"),
        "venice_lido" => include_str!("fixtures/no_route/venice_lido.json"),
        "venice_filter" => include_str!("fixtures/no_route/venice_filter.json"),
        "sea" => include_str!("fixtures/no_route/sea.json"),
        "porquerolles" => include_str!("fixtures/no_route/porquerolles.json"),
        "elba" => include_str!("fixtures/no_route/elba.json"),
        _ => unreachable!("no recording named {name}"),
    };
    let doc: Value = serde_json::from_str(text).unwrap();
    doc["calls"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            (
                u16::try_from(c["status"].as_u64().unwrap()).unwrap(),
                c["answer"].clone(),
            )
        })
        .collect()
}

#[derive(Clone)]
struct Fake {
    answers: Arc<Vec<(u16, Value)>>,
    asked: Arc<Mutex<Vec<Value>>>,
}

async fn fake_route(State(f): State<Fake>, Json(body): Json<Value>) -> (StatusCode, Json<Value>) {
    let n = {
        let mut asked = f.asked.lock().unwrap();
        asked.push(body);
        asked.len()
    };
    // Past the recording, the engine has nothing more to say: a call the
    // recording did not make fails the test through its answer.
    let (status, answer) = f.answers.get(n - 1).cloned().unwrap_or((
        500,
        json!({"code": "InternalError", "message": "not recorded"}),
    ));
    (StatusCode::from_u16(status).unwrap(), Json(answer))
}

/// A fake engine answering `answers` in turn; its URL and what it was asked.
async fn engine(answers: Vec<(u16, Value)>) -> (String, Arc<Mutex<Vec<Value>>>) {
    let fake = Fake {
        answers: Arc::new(answers),
        asked: Arc::new(Mutex::new(Vec::new())),
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
            timeout: std::time::Duration::from_secs(5),
            concurrency: 4,
            queue_wait: std::time::Duration::from_millis(500),
        },
        ..ApiConfig::default()
    }
}

/// A restriction as the Europe graph's bundle gives it.
fn restriction(
    source: RestrictionSource,
    external_id: &str,
    kind: RestrictionKind,
    limit: f64,
    feature: RestrictionFeature,
    name: &str,
    lon_lat: &[(f64, f64)],
) -> (RestrictionRecord, Vec<Position>) {
    let points: Vec<Position> = lon_lat
        .iter()
        .map(|(lon, lat)| Position::new(*lat, *lon).unwrap())
        .collect();
    let record = RestrictionRecord {
        source,
        external_id: external_id.to_owned(),
        kind,
        limit: Some(limit),
        certainty: Certainty::Known,
        feature,
        name: Some(name.to_owned()),
        other_value: None,
        other_source: None,
        shape: polyline::encode(&points),
        observed_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 21, 35).unwrap(),
        except_destination: false,
        enclosed: false,
    };
    (record, points)
}

/// The restrictions behind the recorded trips, read from the graph's
/// bundle (`restrictions.ndjson.gz` of `20261006T2326Z-eu`).
fn restrictions() -> Vec<(RestrictionRecord, Vec<Position>)> {
    vec![
        restriction(
            RestrictionSource::Ign,
            "ign/TRONROUT0000000073480284",
            RestrictionKind::MaxHeight,
            3.2,
            RestrictionFeature::Road,
            "Chemin de Gabardie",
            &[
                (1.482_297, 43.636_938),
                (1.482_296, 43.636_884),
                (1.482_292, 43.636_824),
                (1.482_274, 43.636_685),
            ],
        ),
        restriction(
            RestrictionSource::Osm,
            "way/23554963",
            RestrictionKind::MaxWeight,
            1.5,
            RestrictionFeature::Road,
            "Wrzesińska",
            &[
                (21.034_222, 52.250_439),
                (21.034_258, 52.250_412),
                (21.034_294, 52.250_384),
                (21.034_341, 52.250_345),
                (21.034_613, 52.250_117),
                (21.034_832, 52.249_936),
                (21.034_883, 52.249_894),
                (21.035_272, 52.249_578),
                (21.035_445, 52.249_44),
            ],
        ),
        restriction(
            RestrictionSource::Osm,
            "way/103289002",
            RestrictionKind::MaxHeight,
            2.1,
            RestrictionFeature::BuildingPassage,
            "Isola Nova del Tronchetto",
            &[
                (12.307_504, 45.443_126),
                (12.307_146, 45.443_27),
                (12.307_061, 45.443_295),
                (12.306_987, 45.443_305),
                (12.306_934, 45.443_308),
            ],
        ),
    ]
}

async fn seed(pool: &PgPool) {
    routing::load_graph(
        pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 21, 35).unwrap(),
            ign_fetched_at: None,
            ign_edition: chrono::NaiveDate::from_ymd_opt(2026, 6, 15),
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 23, 35, 20).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &restrictions(),
    )
    .await
    .unwrap();
    routing::activate(pool, GRAPH).await.unwrap();
}

const QUERY: &str = r"
query Route($input: RouteInput!) {
  route(input: $input) {
    status osrmJson
    noRouteReasons { kind stopIndex
      limits { kind limit vehicleValue restriction { kind severity limit source externalId name lat lon place } } }
    routes { hasFerry notices { kind ferry { name ports fromLat fromLon toLat toLon fromCountry toCountry
      distanceFromStartM distanceM durationS geometryIndex } } }
  }
}";

/// The API's request for a 3.3 m, 3.5 t motorhome, as the recordings
/// were made.
fn trip(from: (f64, f64), to: (f64, f64), options: &Value) -> Value {
    json!({"input": {
        "origin": {"lat": from.0, "lon": from.1},
        "destination": {"lat": to.0, "lon": to.1},
        "vehicle": {"kind": "OVERCAB", "heightM": 3.3, "widthM": 2.3, "lengthM": 7.4, "weightT": 3.5},
        "options": options,
        "alternatives": 2,
        "language": "FR"
    }})
}

async fn gql(app: &Router, variables: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": QUERY, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

/// Runs a recorded trip: the answer, and the calls the engine received.
async fn replay(pool: PgPool, name: &str, variables: Value) -> (Value, Vec<Value>) {
    replay_then(pool, name, variables, Vec::new()).await
}

/// Runs a recorded trip whose calls are followed by `then`: the calls a
/// later version of the API makes after those recorded.
async fn replay_then(
    pool: PgPool,
    name: &str,
    variables: Value,
    then: Vec<(u16, Value)>,
) -> (Value, Vec<Value>) {
    seed(&pool).await;
    let mut answers = recorded(name);
    answers.extend(then);
    let (url, asked) = engine(answers.clone()).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let body = gql(&app, variables).await;
    let asked = asked.lock().unwrap().clone();
    assert_eq!(
        asked.len(),
        answers.len(),
        "the API asks what it asked when the trip was recorded: {body}"
    );
    (body, asked)
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_destination_behind_a_low_section_names_it(pool: PgPool) {
    // Toulouse to a gravel yard whose every access is an IGN section of
    // 3.2 m (plan/research/35, 4.1). The section lies 125 m from the
    // destination: after the recorded diagnosis, the destination alone is
    // looked for within 100, then 150 m, and the engine finds no road
    // there either.
    let (body, asked) = replay_then(
        pool,
        "toulouse",
        trip((43.6047, 1.4442), (43.63648, 1.48074), &json!({})),
        vec![no_route(), no_route()],
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "NO_ROUTE", "{body}");
    assert_eq!(r["osrmJson"], Value::Null);
    let reasons = r["noRouteReasons"].as_array().unwrap();
    assert_eq!(reasons.len(), 1, "the origin is reachable: {body}");
    let reason = &reasons[0];
    assert_eq!(reason["kind"], "DESTINATION_UNREACHABLE");
    assert_eq!(reason["stopIndex"], 1);
    let limit = &reason["limits"][0];
    assert_eq!(
        reason["limits"].as_array().unwrap().len(),
        1,
        "the height alone"
    );
    assert_eq!(limit["kind"], "HEIGHT");
    assert_eq!(limit["limit"], 3.2);
    assert_eq!(limit["vehicleValue"], 3.3);
    assert_eq!(
        limit["restriction"]["externalId"],
        "ign/TRONROUT0000000073480284"
    );
    assert_eq!(limit["restriction"]["source"], "IGN");
    assert_eq!(limit["restriction"]["severity"], "BLOCKING");

    // The trip as the app asked, then short questions without
    // instructions: never an alternative, never a voice. The two last
    // calls ask the trip again, below.
    let n = asked.len();
    assert_eq!(asked[0]["alternates"], 2);
    assert!(
        asked[1..n - 2]
            .iter()
            .all(|b| b["directions_type"] == "none"
                && b.get("alternates").is_none()
                && b.get("voice_instructions").is_none())
    );
    // Each stop was set against a reference at least 30 km away.
    let at = |b: &Value, i: usize| {
        Position::new(
            b["locations"][i]["lat"].as_f64().unwrap(),
            b["locations"][i]["lon"].as_f64().unwrap(),
        )
        .unwrap()
    };
    let destination = Position::new(43.63648, 1.48074).unwrap();
    assert!(at(&asked[2], 0).distance_m(destination) >= 30_000.0);
    // The limits were lifted one by one on the destination's trip.
    let lifted: Vec<&Value> = asked
        .iter()
        .map(|b| &b["costing_options"]["auto"])
        .filter(|a| a["height"] == 1.5 && a["weight"] == 3.5)
        .collect();
    assert_eq!(lifted.len(), 1, "the height lifted alone, once");
    // The two last calls: the trip again, the destination looked for
    // farther, the origin (the vehicle's own position for an app that does
    // not tell) never; then the first answer and its reasons stand, without
    // a second diagnosis.
    for (b, radius) in [(&asked[n - 2], 100), (&asked[n - 1], 150)] {
        assert_eq!(b["locations"][1]["radius"], radius, "{b}");
        assert!(b["locations"][0].get("radius").is_none());
        assert_eq!(b["alternates"], 2, "the trip as the app asked");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_destination_behind_a_weight_limit_names_it(pool: PgPool) {
    // The only way out of a street of Warsaw is limited to 1.5 t, 31 m
    // from the destination: looked for farther, it is still behind it.
    let (body, _) = replay_then(
        pool,
        "warsaw",
        trip((52.2297, 21.0122), (52.24994, 21.0354), &json!({})),
        vec![no_route(), no_route()],
    )
    .await;
    let reason = &body["data"]["route"]["noRouteReasons"][0];
    assert_eq!(reason["kind"], "DESTINATION_UNREACHABLE", "{body}");
    assert_eq!(reason["limits"][0]["kind"], "WEIGHT");
    assert_eq!(reason["limits"][0]["limit"], 1.5);
    assert_eq!(reason["limits"][0]["vehicleValue"], 3.5);
    assert_eq!(
        reason["limits"][0]["restriction"]["externalId"],
        "way/23554963"
    );
    assert_eq!(reason["limits"][0]["restriction"]["name"], "Wrzesińska");
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_open_end_of_a_short_trip_is_not_blamed(pool: PgPool) {
    // Mestre to the Lido: the car ferry's lanes lie behind a 2.1 m
    // passage, halfway along the trip. The middle of the trip is inside the
    // closed area; Mestre, the origin, is not.
    let (body, _) = replay(
        pool,
        "venice_lido",
        trip((45.4903, 12.2422), (45.43038, 12.34757), &json!({})),
    )
    .await;
    let reasons = body["data"]["route"]["noRouteReasons"].as_array().unwrap();
    assert_eq!(reasons.len(), 1, "{body}");
    assert_eq!(reasons[0]["kind"], "DESTINATION_UNREACHABLE");
    assert_eq!(reasons[0]["limits"][0]["kind"], "HEIGHT");
    assert_eq!(reasons[0]["limits"][0]["limit"], 2.1);
    assert_eq!(
        reasons[0]["limits"][0]["restriction"]["place"],
        "BUILDING_PASSAGE"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_stop_far_from_any_road_is_named(pool: PgPool) {
    // Limoges to the open sea, 40 km off the coast of the Landes.
    let (body, asked) = replay(
        pool,
        "sea",
        trip((45.8472, 1.2848), (45.5, -3.0), &json!({})),
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OFF_NETWORK", "{body}");
    assert_eq!(
        r["noRouteReasons"],
        json!([{"kind": "NO_ROAD_NEARBY", "stopIndex": 1, "limits": []}])
    );
    assert_eq!(
        asked[2]["locations"][0], asked[2]["locations"][1],
        "each stop asked alone, from itself to itself"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_island_without_a_car_ferry_is_not_connected(pool: PgPool) {
    // Toulon to Porquerolles, served by passenger boats only.
    let (body, _) = replay(
        pool,
        "porquerolles",
        trip((43.1242, 5.9280), (43.0003, 6.2025), &json!({})),
    )
    .await;
    assert_eq!(
        body["data"]["route"]["noRouteReasons"],
        json!([{"kind": "NOT_CONNECTED", "stopIndex": 1, "limits": []}]),
        "{body}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_stop_outside_the_graph_costs_nothing(pool: PgPool) {
    seed(&pool).await;
    let (url, asked) = engine(Vec::new()).await;
    let mut c = config(&url);
    c.quotas.route = Quota {
        count: 1,
        period: std::time::Duration::from_secs(600),
    };
    let app = lunaway_api::router(ApiState::new(pool, c));
    // Limoges to Sarajevo: Bosnia is not in the graph.
    for _ in 0..2 {
        let body = gql(&app, trip((45.8472, 1.2848), (43.86, 18.41), &json!({}))).await;
        let r = &body["data"]["route"];
        assert_eq!(r["status"], "NO_ROUTE", "{body}");
        assert_eq!(
            r["noRouteReasons"],
            json!([{"kind": "OUTSIDE_COVERAGE", "stopIndex": 1, "limits": []}])
        );
    }
    assert!(
        asked.lock().unwrap().is_empty(),
        "the engine is not asked, and a quota of one route served both"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn stops_are_snapped_off_ferry_lines(pool: PgPool) {
    // Mestre to a point of the lagoon by Tronchetto, which the engine
    // snapped onto the car ferry's line before (plan/research/35, 4.2).
    let (body, asked) = replay(
        pool,
        "venice_filter",
        trip((45.4903, 12.2422), (45.40972, 12.30661), &json!({})),
    )
    .await;
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    for b in &asked {
        for l in b["locations"].as_array().unwrap() {
            assert_eq!(
                l["search_filter"],
                json!({"exclude_ferry": true, "exclude_tunnel": true}),
                "every stop is snapped to a road in the open"
            );
        }
    }
    let osrm: Value =
        serde_json::from_str(body["data"]["route"]["osrmJson"].as_str().unwrap()).unwrap();
    assert!(
        osrm["waypoints"][1]["distance"].as_f64().unwrap() < 5_000.0,
        "the destination lies on a road within reach"
    );
    assert_eq!(body["data"]["route"]["routes"][0]["hasFerry"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_that_takes_a_ferry_says_so_even_when_ferries_are_avoided(pool: PgPool) {
    // Piombino to Portoferraio, on Elba: no road leads there.
    let (body, asked) = replay(
        pool,
        "elba",
        trip(
            (42.9256, 10.5267),
            (42.8137, 10.3149),
            &json!({"avoidFerries": true}),
        ),
    )
    .await;
    assert_eq!(asked[0]["costing_options"]["auto"]["use_ferry"], 0.0);
    let route = &body["data"]["route"]["routes"][0];
    assert_eq!(route["hasFerry"], true, "{body}");
    let notices = route["notices"].as_array().unwrap();
    assert_eq!(notices.len(), 1, "one crossing");
    assert_eq!(notices[0]["kind"], "ROUTE_USES_FERRY");
    let ferry = &notices[0]["ferry"];
    assert_eq!(ferry["name"], "Piombino - Portoferraio");
    assert_eq!(ferry["ports"], json!(["Piombino", "Portoferraio"]));
    assert_eq!(ferry["fromCountry"], "IT");
    assert_eq!(ferry["toCountry"], "IT");
    let km = ferry["distanceM"].as_f64().unwrap() / 1_000.0;
    assert!((20.0..35.0).contains(&km), "{km} km at sea");
    let from = Position::new(
        ferry["fromLat"].as_f64().unwrap(),
        ferry["fromLon"].as_f64().unwrap(),
    )
    .unwrap();
    assert!(
        from.distance_m(Position::new(42.9256, 10.5267).unwrap()) < 5_000.0,
        "boarded at Piombino"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_long_trip_asks_fewer_alternatives(pool: PgPool) {
    seed(&pool).await;
    let off = (
        400,
        json!({"code": "NoSegment", "message": "could not snap"}),
    );
    let (url, asked) = engine(vec![off.clone(), off.clone(), off]).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    // Lille to Guelmim, 2 645 km in a straight line.
    let body = gql(
        &app,
        trip((50.6292, 3.0573), (28.987, -10.0574), &json!({})),
    )
    .await;
    assert_eq!(body["data"]["route"]["status"], "OFF_NETWORK", "{body}");
    let first = asked.lock().unwrap()[0].clone();
    assert_eq!(
        first.get("alternates"),
        Some(&json!(1)),
        "three routes of 3 500 km by road would exceed what the API reads of the engine"
    );
    // El Hierro to the North Cape, 5 300 km: refused before the engine.
    let body = gql(&app, trip((27.75, -18.0), (70.98, 25.97), &json!({}))).await;
    assert_eq!(
        body["errors"][0]["extensions"]["code"], "INVALID_INPUT",
        "{body}"
    );
}

/// A 2.5 m van's route under the 2.7 m railway bridge of Rue Maurice
/// Utrillo, Limoges (way 52984577), as `tests/route.rs` has it.
const ROUTE_UNDER: &str = "yhhmvAshlmAD_@^wBlAcCnAiAvAy@jB_@tC]hDm@jj@q`@hd@c]~G_EjPyIlAu@";

/// A recording made with each request: the engine answers a call by what
/// it asks, whatever the order.
fn recorded_with_requests(name: &str) -> Vec<(Value, u16, Value)> {
    let text = match name {
        "st_charles" => include_str!("fixtures/no_route/st_charles.json"),
        "lyon_centre" => include_str!("fixtures/no_route/lyon_centre.json"),
        _ => unreachable!("no recording named {name}"),
    };
    let doc: Value = serde_json::from_str(text).unwrap();
    doc["calls"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            (
                request_key(&c["request"]),
                u16::try_from(c["status"].as_u64().unwrap()).unwrap(),
                c["answer"].clone(),
            )
        })
        .collect()
}

/// A request as the recording matches it: the rings excluded counted, not
/// compared to the last digit (they are drawn around where the route meets
/// a restriction, from the seeded geometry).
fn request_key(request: &Value) -> Value {
    let mut key = request.clone();
    if let Some(rings) = key.get_mut("exclude_polygons") {
        *rings = json!(rings.as_array().map_or(0, Vec::len));
    }
    key
}

#[derive(Clone)]
struct ByRequest {
    calls: Arc<Vec<(Value, u16, Value)>>,
    asked: Arc<Mutex<Vec<Value>>>,
}

async fn answer_by_request(
    State(f): State<ByRequest>,
    Json(body): Json<Value>,
) -> (StatusCode, Json<Value>) {
    let key = request_key(&body);
    f.asked.lock().unwrap().push(body);
    // A call the recording never made fails the test through its answer.
    let (status, answer) = f.calls.iter().find(|(k, _, _)| *k == key).map_or_else(
        || {
            (
                500,
                json!({"code": "InternalError", "message": "not recorded"}),
            )
        },
        |(_, s, a)| (*s, a.clone()),
    );
    (StatusCode::from_u16(status).unwrap(), Json(answer))
}

/// A restriction of the Saint-Charles recording: no name, as in the bundle.
fn unnamed(
    source: RestrictionSource,
    external_id: &str,
    kind: RestrictionKind,
    limit: f64,
    lon_lat: &[(f64, f64)],
) -> (RestrictionRecord, Vec<Position>) {
    let (mut record, points) = restriction(
        source,
        external_id,
        kind,
        limit,
        RestrictionFeature::Road,
        "",
        lon_lat,
    );
    record.name = None;
    (record, points)
}

/// Lyon to Marseille Saint-Charles from `origin`, on an engine that answers
/// the calls of the `st_charles` recording: the route's answer, and what the
/// engine was asked, every call of it recorded.
async fn st_charles(pool: &PgPool, origin: Value) -> (Value, Vec<Value>) {
    by_request(
        pool,
        "st_charles",
        json!({
            "origin": origin,
            "destination": {"lat": 43.3027, "lon": 5.3806},
            "vehicle": {"kind": "LOW_PROFILE", "heightM": 3.2, "widthM": 2.3,
                "lengthM": 7.0, "weightT": 3.5}
        }),
    )
    .await
}

/// The trip `input` on an engine that answers the calls of the recording
/// `name` by what they ask: the route's answer, and what the engine was
/// asked, every call of it recorded.
async fn by_request(pool: &PgPool, name: &str, input: Value) -> (Value, Vec<Value>) {
    let calls = Arc::new(recorded_with_requests(name));
    let fake = ByRequest {
        calls: Arc::clone(&calls),
        asked: Arc::new(Mutex::new(Vec::new())),
    };
    let asked = Arc::clone(&fake.asked);
    let engine = Router::new()
        .route("/route", post(answer_by_request))
        .route(
            "/status",
            get(|| async { Json(json!({"version": "3.9.0"})) }),
        )
        .with_state(fake);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, engine).await });
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "query": "query Route($input: RouteInput!) { route(input: $input) {
                    status routes { distanceM } movedStops { stopIndex lat lon distanceM }
                    blockers { kind limit externalId distanceFromStartM } } }",
                "variables": {"input": input}
            })
            .to_string(),
        ))
        .unwrap();
    let response = app.oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body: Value = serde_json::from_slice(&bytes).unwrap();
    let asked = asked.lock().unwrap().clone();
    let unrecorded: Vec<&Value> = asked
        .iter()
        .filter(|b| !calls.iter().any(|(k, _, _)| *k == request_key(b)))
        .collect();
    assert!(
        unrecorded.is_empty(),
        "the API asks what the recording never answered (record it again if the requests \
         changed on purpose): {unrecorded:?}"
    );
    (body, asked)
}

/// The search radius of each stop in each call of the trip asked again
/// (the destination's set), in order.
fn radii(asked: &[Value]) -> Vec<(Value, Value)> {
    asked
        .iter()
        .filter(|b| b["locations"][1]["radius"].is_number())
        .map(|b| {
            (
                b["locations"][0]["radius"].clone(),
                b["locations"][1]["radius"].clone(),
            )
        })
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_limit_met_beside_another_stop_once_one_moved_moves_that_stop_too(pool: PgPool) {
    // Lyon to Marseille Saint-Charles, recorded on the production engine
    // (plan/research/76-suites-3.md): no route, the diagnosis names the
    // station's underground aisle 221 m from the destination. Looked for
    // within 100 m, the destination lands on the car park's entrance, 66 m
    // away, and the route found starts on a street DiaLog closes to
    // vehicles over 5.5 m long, 18 m from the origin: the ring around it
    // closes the origin's road. Before, the origin stayed where it was, at
    // 100 m as at 150 m, and the trip had no route for any weight.
    let aisle = [
        (5.383_516, 43.302_249),
        (5.383_446, 43.302_312),
        (5.383_392, 43.302_335),
        (5.383_287, 43.302_35),
    ];
    routing::load_graph(
        &pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 7, 20, 21, 35).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 8, 1, 29, 0).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[
            unnamed(
                RestrictionSource::Osm,
                "way/417106729",
                RestrictionKind::MaxHeight,
                1.9,
                &aisle,
            ),
            unnamed(
                RestrictionSource::Osm,
                "way/417106729",
                RestrictionKind::MaxWidth,
                2.05,
                &aisle,
            ),
        ],
    )
    .await
    .unwrap();
    routing::activate(&pool, GRAPH).await.unwrap();
    // DiaLog's permanent orders hold for every graph.
    lunaway_db::road_events::replace_dialog_restrictions(
        &pool,
        &[unnamed(
            RestrictionSource::Dialog,
            "dialog/019f1d8c-357f-7ac1-b242-8d0156cd3ca8#0",
            RestrictionKind::MaxLength,
            5.5,
            &[(4.834_269, 45.763_817), (4.835_667, 45.763_84)],
        )],
    )
    .await
    .unwrap();
    let (body, asked) = st_charles(
        &pool,
        json!({"lat": 45.7640, "lon": 4.8357, "vehiclePosition": false}),
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    let km = r["routes"][0]["distanceM"].as_f64().unwrap() / 1000.0;
    assert!(
        (km - 316.2).abs() < 0.1,
        "the route the engine gave once both stops moved, 316.2 km: {km} km"
    );
    assert_eq!(
        r["movedStops"],
        json!([{"stopIndex": 1, "lat": 43.302_349, "lon": 5.379_943, "distanceM": 66.0}]),
        "the destination moved to the car park's entrance is told; the origin, 22 m from its \
         point, is not"
    );
    assert_eq!(
        radii(&asked),
        [
            (Value::Null, json!(100)),
            (Value::Null, json!(100)),
            (json!(100), json!(100)),
            (json!(100), json!(100)),
        ],
        "the destination at 100 m, then the origin met beside its limit too, at the same radius"
    );

    // The vehicle's own position (an origin that does not say counts as
    // one) is looked for within a phone's accuracy only, 25 m: the street
    // of the vehicle met beside its limit, 22 m away, is within it, and the
    // trip has its route (2026-10-09, plan/research/82-suites-4.md); before,
    // it ended at 100 m then 150 m for the destination alone, NO_ROUTE.
    let (body, asked) = st_charles(&pool, json!({"lat": 45.7640, "lon": 4.8357})).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(
        r["movedStops"],
        json!([{"stopIndex": 1, "lat": 43.302_349, "lon": 5.379_943, "distanceM": 66.0}]),
        "the vehicle's own position is never told as moved"
    );
    assert_eq!(
        radii(&asked),
        [
            (Value::Null, json!(100)),
            (Value::Null, json!(100)),
            (json!(25), json!(100)),
            (json!(25), json!(100)),
        ],
        "never more than 25 m around the vehicle"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_vehicle_beside_a_street_it_may_not_take_starts_on_the_next_one(pool: PgPool) {
    // Lyon's pedestrian centre to the Guillotiere, recorded on the
    // production engine (plan/research/82-suites-4.md). The vehicle's
    // position, in the rue de la Republique, is snapped to the rue Henri
    // Germain 18 m away, which DiaLog closes to vehicles over 5.5 m long;
    // the destination, 6 m from an underground car park's 1.8 m entrance,
    // to the service road that ends at it. The rings around both close the
    // only roads the engine took. The destination moves within 100 m; the
    // vehicle, once looked for within 25 m, starts on the rue de la
    // Poulaillerie, 22 m away. Before, the vehicle was never looked for
    // farther and the trip had no safe route at any weight.
    routing::load_graph(
        &pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 6, 20, 21, 6).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 8, 1, 29, 0).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[unnamed(
            RestrictionSource::Osm,
            "node/2987663855",
            RestrictionKind::MaxHeight,
            1.8,
            &[(4.846_64, 45.748_468)],
        )],
    )
    .await
    .unwrap();
    routing::activate(&pool, GRAPH).await.unwrap();
    lunaway_db::road_events::replace_dialog_restrictions(
        &pool,
        &[unnamed(
            RestrictionSource::Dialog,
            "dialog/019f1d8c-357f-7ac1-b242-8d0156cd3ca8#0",
            RestrictionKind::MaxLength,
            5.5,
            &[(4.834_269, 45.763_817), (4.835_667, 45.763_84)],
        )],
    )
    .await
    .unwrap();
    let trip = |origin: Value| {
        json!({
            "origin": origin,
            "destination": {"lat": 45.7485, "lon": 4.8467},
            "vehicle": {"kind": "LOW_PROFILE", "heightM": 2.9, "widthM": 2.3,
                "lengthM": 7.0, "weightT": 3.5}
        })
    };
    // An origin that does not say counts as the vehicle's position, as for
    // an app before `vehiclePosition`.
    let (body, asked) = by_request(
        &pool,
        "lyon_centre",
        trip(json!({"lat": 45.7640, "lon": 4.8357})),
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    let km = r["routes"][0]["distanceM"].as_f64().unwrap() / 1000.0;
    assert!(
        (km - 3.2).abs() < 0.1,
        "the route of the recording: {km} km"
    );
    assert_eq!(
        r["movedStops"],
        json!([]),
        "the destination landed 22 m away and the vehicle is never told as moved"
    );
    assert_eq!(
        radii(&asked),
        [(json!(25), json!(100)), (json!(25), json!(100))],
        "the vehicle within 25 m, the destination within 100 m, in one round"
    );

    // With a course, the vehicle is on the road it follows: never looked
    // for elsewhere, and the answer names the limit it stands beside.
    let (body, asked) = by_request(
        &pool,
        "lyon_centre",
        trip(json!({"lat": 45.7640, "lon": 4.8357, "headingDeg": 90, "vehiclePosition": true})),
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "NO_SAFE_ROUTE", "{body}");
    assert_eq!(
        r["blockers"][0],
        json!({"kind": "TOO_LONG", "limit": 5.5,
            "externalId": "dialog/019f1d8c-357f-7ac1-b242-8d0156cd3ca8#0", "distanceFromStartM": 0.0}),
        "the street the vehicle was snapped to, at the start"
    );
    assert!(
        asked
            .iter()
            .all(|b| b["locations"][0].get("radius").is_none()),
        "never a radius on a vehicle with a course"
    );
}

fn bridge() -> (RestrictionRecord, Vec<Position>) {
    restriction(
        RestrictionSource::Osm,
        "way/52984577",
        RestrictionKind::MaxHeight,
        2.7,
        RestrictionFeature::Underpass,
        "Rue Maurice Utrillo",
        &[(1.285_024, 45.846_841), (1.285_561, 45.846_147)],
    )
}

fn found(geometry: &str) -> (u16, Value) {
    (
        200,
        json!({"code": "Ok", "waypoints": [], "routes": [{
            "geometry": geometry, "distance": 268.7, "duration": 40.0,
            "legs": [{"distance": 268.7, "steps": []}]
        }]}),
    )
}

fn no_route() -> (u16, Value) {
    (
        400,
        json!({"code": "NoRoute", "message": "Impossible route between points"}),
    )
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_way_closed_between_reachable_stops_names_its_limit(pool: PgPool) {
    routing::load_graph(
        &pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 21, 35).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 23, 35, 20).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[bridge()],
    )
    .await
    .unwrap();
    routing::activate(&pool, GRAPH).await.unwrap();
    // No route for the vehicle; each stop reaches its reference; the small
    // vehicle's trip passes under the bridge.
    let (url, asked) = engine(vec![
        no_route(),
        found(ROUTE_UNDER),
        found(ROUTE_UNDER),
        found(ROUTE_UNDER),
    ])
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let body = gql(
        &app,
        trip((45.84719, 1.28476), (45.8451, 1.28637), &json!({})),
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "NO_ROUTE", "{body}");
    let reason = &r["noRouteReasons"][0];
    assert_eq!(reason["kind"], "BLOCKED_ON_THE_WAY", "{body}");
    assert_eq!(reason["stopIndex"], Value::Null);
    assert_eq!(reason["limits"][0]["kind"], "HEIGHT");
    assert_eq!(reason["limits"][0]["limit"], 2.7);
    assert_eq!(
        reason["limits"][0]["restriction"]["externalId"],
        "way/52984577"
    );
    let asked = asked.lock().unwrap();
    assert_eq!(asked.len(), 4);
    assert_eq!(
        asked[3]["costing_options"]["auto"]["height"], 1.5,
        "the whole trip asked for the smallest vehicle"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_diagnosis_that_fails_leaves_the_trip_unexplained(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = engine(vec![
        no_route(),
        (500, json!({"code": "InternalError", "message": "boom"})),
    ])
    .await;
    let mut c = config(&url);
    c.quotas.route = Quota {
        count: 1,
        period: std::time::Duration::from_secs(600),
    };
    let app = lunaway_api::router(ApiState::new(pool, c));
    let body = gql(
        &app,
        trip((45.84719, 1.28476), (45.8451, 1.28637), &json!({})),
    )
    .await;
    assert_eq!(body["data"]["route"]["status"], "NO_ROUTE", "{body}");
    assert_eq!(body["data"]["route"]["noRouteReasons"], json!([]));
    // The engine answered: the route is charged.
    let body = gql(
        &app,
        trip((45.84719, 1.28476), (45.8451, 1.28637), &json!({})),
    )
    .await;
    assert_eq!(
        body["errors"][0]["extensions"]["code"], "RATE_LIMITED",
        "{body}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failure_after_the_engine_answered_is_not_given_back(pool: PgPool) {
    routing::load_graph(
        &pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 21, 35).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 23, 35, 20).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[bridge()],
    )
    .await
    .unwrap();
    routing::activate(&pool, GRAPH).await.unwrap();
    // A route under the bridge, then a failure of the recalculation: a
    // client could make the second attempt slow on purpose, so the work
    // done counts.
    let (url, _) = engine(vec![
        found(ROUTE_UNDER),
        (500, json!({"code": "InternalError", "message": "boom"})),
    ])
    .await;
    let mut c = config(&url);
    c.quotas.route = Quota {
        count: 1,
        period: std::time::Duration::from_secs(600),
    };
    let app = lunaway_api::router(ApiState::new(pool, c));
    let body = gql(
        &app,
        trip((45.84719, 1.28476), (45.8451, 1.28637), &json!({})),
    )
    .await;
    assert_eq!(
        body["errors"][0]["extensions"]["code"], "UNAVAILABLE",
        "{body}"
    );
    let body = gql(
        &app,
        trip((45.84719, 1.28476), (45.8451, 1.28637), &json!({})),
    )
    .await;
    assert_eq!(
        body["errors"][0]["extensions"]["code"], "RATE_LIMITED",
        "{body}"
    );
}
