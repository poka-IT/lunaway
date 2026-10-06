//! Fuel near a point and along a route, through the router: the 80
//! stations of the recorded fuel export near the A20 between Limoges and
//! Brive (2026-10-06 13:24 UTC, its dates moved to now), the route's real
//! line (Valhalla 3.9.0 on the France graph, 93.7 km), and a fake routing
//! engine that measures the legs it is asked for from the points it is
//! given: 1.3 times the straight line, at 60 km/h.

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
    routing::post,
};
use chrono::{DateTime, Utc};
use http_body_util::BodyExt;
use lunaway_api::{
    ApiConfig, ApiState,
    config::{Quota, RoutingConfig},
};
use lunaway_db::{PgPool, fuel::PriceSeen, pois::NewJoin};
use lunaway_domain::{Position, SourceId, poi::FuelKind, routing::polyline};
use lunaway_ingest::{fuel, store::store_joins};
use serde_json::{Value, json};
use tower::ServiceExt;

const FEED: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/fuel_export_a20_sample.json");
const ROUTE: &str =
    include_str!("../../lunaway-domain/tests/fixtures/route_limoges_brive.polyline6");
const RECORDED_AT: &str = "2026-10-06T13:24:14Z";
/// The fake engine's road distance per straight-line kilometre.
const ROAD: f64 = 1.3;
/// The fake engine's speed, km/h.
const SPEED: f64 = 60.0;
/// Masseret, the Porte de Corrèze service area of the A20.
const MASSERET: &str = "19510002";

fn rows_of_now() -> Vec<Value> {
    let mut rows: Vec<Value> = serde_json::from_slice(FEED).unwrap();
    let shift = Utc::now()
        - DateTime::parse_from_rfc3339(RECORDED_AT)
            .unwrap()
            .with_timezone(&Utc);
    for row in &mut rows {
        for (key, value) in row.as_object_mut().unwrap().iter_mut() {
            if (key.ends_with("_maj") || key.ends_with("_rupture_debut"))
                && let Some(text) = value.as_str()
            {
                *value = (DateTime::parse_from_rfc3339(text).unwrap() + shift)
                    .to_rfc3339()
                    .into();
            }
        }
    }
    rows
}

async fn seed(pool: &PgPool) -> Vec<Value> {
    let rows = rows_of_now();
    let parsed = fuel::parse(&serde_json::to_vec(&rows).unwrap()).unwrap();
    let data: Vec<Value> = parsed
        .stations
        .iter()
        .map(|s| serde_json::to_value(&s.station).unwrap())
        .collect();
    let joins: Vec<NewJoin<'_>> = parsed
        .stations
        .iter()
        .zip(&data)
        .map(|(s, d)| NewJoin {
            key: &s.key,
            data: d,
            raw: &s.raw,
            fetched_at: Utc::now(),
        })
        .collect();
    store_joins(pool, &SourceId::FUEL_PRICES, &joins)
        .await
        .unwrap();
    rows
}

/// What the fake engine was asked.
type Asked = Arc<Mutex<Vec<Value>>>;

#[derive(Clone)]
struct Fake {
    asked: Asked,
    /// A station position the engine finds no road to.
    unreachable: Option<(f64, f64)>,
}

fn point(v: &Value) -> Position {
    Position::new(v["lat"].as_f64().unwrap(), v["lon"].as_f64().unwrap()).unwrap()
}

async fn matrix(State(f): State<Fake>, Json(body): Json<Value>) -> (StatusCode, Json<Value>) {
    f.asked.lock().unwrap().push(body.clone());
    let sources: Vec<Position> = body["sources"]
        .as_array()
        .unwrap()
        .iter()
        .map(point)
        .collect();
    let targets: Vec<Position> = body["targets"]
        .as_array()
        .unwrap()
        .iter()
        .map(point)
        .collect();
    let blocked = |p: Position| {
        f.unreachable
            .is_some_and(|(lat, lon)| (p.lat() - lat).abs() < 1e-6 && (p.lon() - lon).abs() < 1e-6)
    };
    let rows: Vec<Value> = sources
        .iter()
        .enumerate()
        .map(|(i, s)| {
            targets
                .iter()
                .enumerate()
                .map(|(j, t)| {
                    if blocked(*s) || blocked(*t) {
                        return json!({"distance": null, "time": null, "from_index": i, "to_index": j});
                    }
                    let km = s.distance_m(*t) / 1_000.0 * ROAD;
                    json!({"distance": km, "time": km / SPEED * 3_600.0, "from_index": i, "to_index": j})
                })
                .collect::<Vec<_>>()
                .into()
        })
        .collect();
    (
        StatusCode::OK,
        Json(json!({"sources_to_targets": rows, "units": "kilometers"})),
    )
}

async fn engine(unreachable: Option<(f64, f64)>) -> (String, Asked) {
    let fake = Fake {
        asked: Arc::new(Mutex::new(Vec::new())),
        unreachable,
    };
    let asked = Arc::clone(&fake.asked);
    let app = Router::new()
        .route("/sources_to_targets", post(matrix))
        .with_state(fake);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

fn app_with(pool: &PgPool, engine: Option<&str>, quota: Option<Quota>) -> Router {
    let mut config = ApiConfig {
        routing: RoutingConfig {
            valhalla_url: engine.map(str::to_owned),
            timeout: Duration::from_millis(800),
            concurrency: 4,
            queue_wait: Duration::from_millis(200),
        },
        ..ApiConfig::default()
    };
    if let Some(q) = quota {
        config.quotas.fuel_route = q;
    }
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

async fn gql(app: &Router, query: &str, variables: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

fn ok(body: &Value) -> &Value {
    assert!(body.get("errors").is_none(), "unexpected errors: {body}");
    &body["data"]
}

fn code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or_default()
}

const STOP: &str = "stationId poiId lat lon address { city postcode } fuel priceEur \
                    priceUpdatedAt shortage { kind } openNow { state } selfService24h highway \
                    distanceM alongKm detour { km minutes measured litres costEur } \
                    effectivePriceEur sourceId";

fn along_query() -> String {
    format!(
        "query($i: FuelAlongRouteInput!) {{ fuelAlongRoute(input: $i) {{ \
         routeKm candidates detoursMeasured stations {{ {STOP} }} }} }}"
    )
}

fn along_input(max_detour_km: f64, limit: i32) -> Value {
    json!({"i": {
        "polyline": ROUTE.trim(),
        "fuel": "DIESEL",
        "maxDetourKm": max_detour_km,
        "litresPer100Km": 12.0,
        "fillLitres": 60.0,
        "limit": limit,
    }})
}

/// The straight-line distance from `p` to the route, metres, by a scan of
/// every segment.
fn to_route(line: &[Position], p: Position) -> f64 {
    let k = 111_195.0;
    let cos = p.lat().to_radians().cos();
    line.windows(2)
        .map(|w| {
            let (ax, ay) = ((w[0].lon() - p.lon()) * k * cos, (w[0].lat() - p.lat()) * k);
            let (bx, by) = ((w[1].lon() - p.lon()) * k * cos, (w[1].lat() - p.lat()) * k);
            let (dx, dy) = (bx - ax, by - ay);
            let len2 = dx * dx + dy * dy;
            let t = if len2 > 0.0 {
                (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            (ax + t * dx).hypot(ay + t * dy)
        })
        .fold(f64::INFINITY, f64::min)
}

fn position(row: &Value) -> Position {
    let deg = |k: &str| row[k].as_str().unwrap().parse::<f64>().unwrap() / 100_000.0;
    Position::new(deg("latitude"), deg("longitude")).unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn stations_along_a_real_route_are_ranked_by_their_price_with_the_detour(pool: PgPool) {
    let rows = seed(&pool).await;
    let (url, asked) = engine(None).await;
    let api = app_with(&pool, Some(&url), None);
    let body = gql(&api, &along_query(), along_input(5.0, 5)).await;
    let r = &ok(&body)["fuelAlongRoute"];

    // The corridor: every station with a diesel price within 2.5 km of the
    // line, by a scan of the line.
    let line = polyline::decode(ROUTE.trim()).unwrap();
    let in_band = rows
        .iter()
        .filter(|row| row["gazole_prix"].is_number())
        .filter(|row| to_route(&line, position(row)) <= 2_500.0)
        .count();
    assert_eq!(r["candidates"], in_band);
    assert!((93.0..94.5).contains(&r["routeKm"].as_f64().unwrap()));
    assert_eq!(r["detoursMeasured"], true);

    let stations = r["stations"].as_array().unwrap();
    assert_eq!(stations.len(), 5);
    let mut last = 0.0;
    for s in stations {
        let price = s["priceEur"].as_f64().unwrap();
        let detour = &s["detour"];
        assert_eq!(detour["measured"], true);
        let km = detour["km"].as_f64().unwrap();
        assert!((0.0..=5.0).contains(&km), "{s}");
        // 12 l/100 km, 60 l bought.
        let litres = km * 12.0 / 100.0;
        assert!((detour["litres"].as_f64().unwrap() - litres).abs() < 1e-9);
        let effective = price + litres * price / 60.0;
        let e = s["effectivePriceEur"].as_f64().unwrap();
        assert!((e - effective).abs() < 1e-9, "{s}");
        assert!(e >= last, "ranked by effective price");
        last = e;
        assert!(s["distanceM"].as_f64().unwrap() <= 2_500.0);
        assert_eq!(s["fuel"], "DIESEL");
        assert_eq!(s["sourceId"], "prix-carburants");
        assert!(s["address"]["city"].is_string());
    }

    // Ten candidates measured (twice the five asked), in calls that stay
    // local: in each, the anchors of the route then the stations as
    // sources, the stations then the anchors as targets, every point less
    // than 60 km from every other.
    let asked = asked.lock().unwrap();
    let mut measured = 0;
    for m in asked.iter() {
        let sources = m["sources"].as_array().unwrap();
        let targets = m["targets"].as_array().unwrap();
        let k = sources.len() / 2;
        assert_eq!(sources.len(), targets.len());
        measured += k;
        assert!(
            sources[0]["heading"].is_number(),
            "an anchor keeps its carriageway"
        );
        assert!(sources[k].get("heading").is_none(), "a station has none");
        assert_eq!(sources[k], targets[0], "the stations are both");
        assert_eq!(m["verbose"], true);
        let all: Vec<Position> = sources.iter().chain(targets).map(point).collect();
        let widest = all
            .iter()
            .flat_map(|a| all.iter().map(move |b| a.distance_m(*b)))
            .fold(0.0, f64::max);
        assert!(widest < 60_000.0, "a call spans {widest:.0} m");
    }
    assert_eq!(measured, 10);
    assert!(
        asked.len() > 1,
        "stations along 93 km are measured run by run"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_engine_that_refuses_is_asked_once_and_the_detours_estimated(pool: PgPool) {
    seed(&pool).await;
    let refusals = Arc::new(Mutex::new(0));
    let counted = Arc::clone(&refusals);
    let app = Router::new().route(
        "/sources_to_targets",
        post(move || {
            let counted = Arc::clone(&counted);
            async move {
                *counted.lock().unwrap() += 1;
                // Valhalla 3.9.0 for an action its configuration leaves out.
                (
                    StatusCode::BAD_REQUEST,
                    Json(json!({"error_code": 106, "error": "Try any of: '/route'",
                                "status_code": 400, "status": "Bad Request"})),
                )
            }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    let api = app_with(&pool, Some(&url), None);
    let body = gql(&api, &along_query(), along_input(5.0, 5)).await;
    let r = &ok(&body)["fuelAlongRoute"];
    assert_eq!(r["detoursMeasured"], false);
    assert!(!r["stations"].as_array().unwrap().is_empty());
    assert_eq!(
        *refusals.lock().unwrap(),
        1,
        "a refusing engine is not asked again"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_station_the_engine_cannot_reach_or_too_far_off_is_left_out(pool: PgPool) {
    let rows = seed(&pool).await;
    let masseret = rows.iter().find(|r| r["id"] == 19_510_002).unwrap();
    let at = position(masseret);
    let (url, asked) = engine(Some((at.lat(), at.lon()))).await;
    let api = app_with(&pool, Some(&url), None);
    let body = gql(&api, &along_query(), along_input(5.0, 20)).await;
    let measured = asked
        .lock()
        .unwrap()
        .iter()
        .flat_map(|m| m["targets"].as_array().unwrap().clone())
        .any(|t| (point(&t).lat() - at.lat()).abs() < 1e-6);
    assert!(measured, "Masseret was a candidate");
    let r = &ok(&body)["fuelAlongRoute"];
    let ids: Vec<&str> = r["stations"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["stationId"].as_str().unwrap())
        .collect();
    assert!(!ids.is_empty());
    assert!(
        !ids.contains(&MASSERET),
        "no way from the route to it: not a station to send a driver to"
    );

    // A narrow detour keeps the stations beside the route only.
    let (url, _) = engine(None).await;
    let api = app_with(&pool, Some(&url), None);
    let body = gql(&api, &along_query(), along_input(0.5, 20)).await;
    for s in ok(&body)["fuelAlongRoute"]["stations"].as_array().unwrap() {
        assert!(s["detour"]["km"].as_f64().unwrap() <= 0.5, "{s}");
        assert!(s["distanceM"].as_f64().unwrap() <= 250.0, "{s}");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn without_the_engine_the_detours_are_estimated(pool: PgPool) {
    seed(&pool).await;
    let api = app_with(&pool, None, None);
    let body = gql(&api, &along_query(), along_input(5.0, 5)).await;
    let r = &ok(&body)["fuelAlongRoute"];
    assert_eq!(r["detoursMeasured"], false);
    for s in r["stations"].as_array().unwrap() {
        let d = &s["detour"];
        assert_eq!(d["measured"], false);
        // There and back in a straight line, times 1.3.
        let expected = 2.0 * s["distanceM"].as_f64().unwrap() * 1.3 / 1_000.0;
        assert!((d["km"].as_f64().unwrap() - expected).abs() < 1e-6, "{s}");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_search_along_a_route_is_bounded_and_counted(pool: PgPool) {
    seed(&pool).await;
    let (url, asked) = engine(None).await;
    let api = app_with(
        &pool,
        Some(&url),
        Some(Quota {
            count: 1,
            period: Duration::from_secs(600),
        }),
    );

    let mut wide = along_input(5.0, 5);
    wide["i"]["maxDetourKm"] = 31.0.into();
    let refused = gql(&api, &along_query(), wide).await;
    assert_eq!(code(&refused), "INVALID_INPUT");
    let mut both = along_input(5.0, 5);
    both["i"]["points"] = json!([{"lat": 45.8, "lon": 1.26}, {"lat": 45.1, "lon": 1.53}]);
    assert_eq!(
        code(&gql(&api, &along_query(), both).await),
        "INVALID_INPUT"
    );
    assert!(
        asked.lock().unwrap().is_empty(),
        "a bad request costs the engine nothing"
    );

    let twice = gql(
        &api,
        "query($i: FuelAlongRouteInput!) { a: fuelAlongRoute(input: $i) { candidates } \
         b: fuelAlongRoute(input: $i) { candidates } }",
        along_input(5.0, 5),
    )
    .await;
    assert_eq!(
        code(&twice),
        "INVALID_INPUT",
        "one engine search per request"
    );

    // The quota of one was spent by the first of the two above.
    let spent = gql(&api, &along_query(), along_input(5.0, 5)).await;
    assert_eq!(code(&spent), "RATE_LIMITED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn fuel_near_a_point_lists_the_cheapest_first_with_its_trend(pool: PgPool) {
    let rows = seed(&pool).await;
    // Brive-la-Gaillarde, place de la Guierle.
    let at = Position::new(45.1588, 1.5321).unwrap();
    let today = lunaway_domain::fuel::price_day(Utc::now());
    let seen = |price_eur| {
        vec![PriceSeen {
            station_ref: "19100016",
            fuel: FuelKind::Diesel,
            price_eur,
        }]
    };
    let yesterday = today.pred_opt().unwrap();
    lunaway_db::fuel::record_price_days(&pool, &seen(2.31), yesterday)
        .await
        .unwrap();
    for p in [2.27, 2.25] {
        lunaway_db::fuel::record_price_days(&pool, &seen(p), today)
            .await
            .unwrap();
    }
    let api = app_with(&pool, None, None);
    let body = gql(
        &api,
        "query($at: LatLonInput!) { fuelNearby(at: $at, fuel: DIESEL, radiusKm: 4, limit: 3) \
         { stationId priceEur distanceM effectivePriceEur detour { km } alongKm \
         priceTrend { fuel days { day lowEur highEur } \
         last7Days { lowEur highEur daysKnown changeEur } last30Days { daysKnown } } } }",
        json!({"at": {"lat": at.lat(), "lon": at.lon()}}),
    )
    .await;
    let found = ok(&body)["fuelNearby"].as_array().unwrap().clone();

    // What the recorded feed says: within 4 km, the cheapest diesel first,
    // equal prices by distance, a station out of diesel last.
    let mut expected: Vec<(bool, f64, f64, String)> = rows
        .iter()
        .filter(|r| r["gazole_prix"].is_number())
        .map(|r| {
            let out = r["gazole_rupture_type"].is_string();
            (
                out,
                r["gazole_prix"].as_f64().unwrap(),
                position(r).distance_m(at),
                r["id"].as_i64().unwrap().to_string(),
            )
        })
        .filter(|(_, _, d, _)| *d <= 4_000.0)
        .collect();
    expected.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let expected: Vec<&str> = expected.iter().take(3).map(|e| e.3.as_str()).collect();
    let got: Vec<&str> = found
        .iter()
        .map(|s| s["stationId"].as_str().unwrap())
        .collect();
    assert_eq!(got, expected);
    for s in &found {
        assert_eq!(
            s["effectivePriceEur"], s["priceEur"],
            "no detour near a point"
        );
        assert!(s["detour"].is_null() && s["alongKm"].is_null());
    }

    let with_trend = found
        .iter()
        .find(|s| s["stationId"] == "19100016")
        .expect("Brive's station at 2.25");
    let trend = &with_trend["priceTrend"];
    assert_eq!(trend["fuel"], "DIESEL");
    assert_eq!(
        trend["days"],
        json!([
            {"day": yesterday.to_string(), "lowEur": 2.31, "highEur": 2.31},
            {"day": today.to_string(), "lowEur": 2.25, "highEur": 2.27},
        ])
    );
    let week = &trend["last7Days"];
    assert_eq!(
        (week["lowEur"].as_f64(), week["highEur"].as_f64()),
        (Some(2.25), Some(2.31))
    );
    assert_eq!(week["daysKnown"], 2);
    assert!(
        (week["changeEur"].as_f64().unwrap() + 0.06).abs() < 1e-9,
        "2.31 to 2.25"
    );
    assert_eq!(trend["last30Days"]["daysKnown"], 2);
    let without = found.iter().find(|s| s["stationId"] != "19100016").unwrap();
    assert!(without["priceTrend"].is_null(), "no day seen, no trend");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_station_openstreetmap_names_shows_its_name_hours_and_trend(pool: PgPool) {
    seed(&pool).await;
    // An OpenStreetMap element for Brive's station 19100016, open day and
    // night, written as Overpass writes it.
    let osm = json!({"elements": [{
        "type": "node", "id": 1, "lat": 45.1645, "lon": 1.5244,
        "tags": {"amenity": "fuel", "name": "Station de la Gare", "brand": "TotalEnergies",
                 "opening_hours": "24/7", "fuel:diesel": "yes",
                 "ref:FR:prix-carburants": "19100016"}
    }]});
    let points = lunaway_ingest::poi_osm::parse(osm.to_string().as_bytes(), Utc::now()).unwrap();
    lunaway_ingest::store::store_pois(&pool, &SourceId::OSM, &points.points)
        .await
        .unwrap();
    let today = lunaway_domain::fuel::price_day(Utc::now());
    lunaway_db::fuel::record_price_days(
        &pool,
        &[PriceSeen {
            station_ref: "19100016",
            fuel: FuelKind::Diesel,
            price_eur: 2.25,
        }],
        today,
    )
    .await
    .unwrap();
    let api = app_with(&pool, None, None);
    let body = gql(
        &api,
        "{ fuelNearby(at: {lat: 45.1588, lon: 1.5321}, fuel: DIESEL, radiusKm: 4, limit: 1) \
         { stationId poiId name brand openNow { state } } }",
        json!({}),
    )
    .await;
    let s = &ok(&body)["fuelNearby"][0];
    assert_eq!(s["stationId"], "19100016");
    assert_eq!(s["name"], "Station de la Gare");
    assert_eq!(s["brand"], "TotalEnergies");
    assert_eq!(s["openNow"]["state"], "OPEN");
    let body = gql(
        &api,
        "query($id: UUID!) { poi(id: $id) { fuel { priceTrend(fuel: DIESEL) { days { lowEur } } \
         lpgTrend: priceTrend(fuel: LPG) { fuel } } } }",
        json!({"id": s["poiId"]}),
    )
    .await;
    let fuel = &ok(&body)["poi"]["fuel"];
    assert_eq!(fuel["priceTrend"]["days"], json!([{"lowEur": 2.25}]));
    assert!(fuel["lpgTrend"].is_null(), "no LPG day seen");
}
