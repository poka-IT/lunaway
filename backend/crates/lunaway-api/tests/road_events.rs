//! Road events in the API: a route goes around a closure active when the
//! vehicle gets there (and only then), never around a closure of the other
//! carriageway, around a closed exit by its slip road only; a stale feed
//! warns instead of blocking; the users' reports warn, then block once a
//! second account confirms them; the change feed a phone polls.
//! The engine is a fake on loopback answering with real shapes (the Rue
//! Maurice Utrillo case, Limoges: `tests/route.rs`).

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
use base64::Engine as _;
use chrono::{DateTime, TimeZone, Timelike as _, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState, config::RoutingConfig};
use lunaway_db::{
    PgPool,
    road_events::{self as events, NewEvent},
    routing::{self, NewGraph},
};
use lunaway_domain::{
    Position,
    road_events::{
        Carriageway, Confidence, EventClass, EventDirection, MatchQuality, Schedule,
        SourceGeometry, VehicleLimits,
    },
    routing::{RouteLine, polyline},
};
use p256::ecdsa::{SigningKey, signature::Signer};
use serde_json::{Value, json};
use tower::ServiceExt;

/// A 2.5 m van's route under the bridge of Rue Maurice Utrillo, 269 m.
const ROUTE_UNDER: &str = "yhhmvAshlmAD_@^wBlAcCnAiAvAy@jB_@tC]hDm@jj@q`@hd@c]~G_EjPyIlAu@";
/// The route around it, 2 020 m.
const ROUTE_AROUND: &str = "yhhmvAshlmAObBFtCZvCjAzFxFbPnKp_@l@hCx@bGD~Ds@~EaAvEwXttAwOb{@eAdGdLfQxBtD`BjCnAxBjA`CjAxCrEzLtBhF|AjDnAzBlA~AtA`BbB~AvHpHhD~ExF~LhF|NtGzQ~EzLn@zAlBbEpFuAn@S~b@iNxa@sOpNyDfSoCxCc@`Cs@fMoDjCoA|ByAzM{J`BmBfBiAde@uT~FeE|EaG|JqLnHkJdr@o{@}@_Aq|@}_AmAmArCy@vFiNpBeFGoCeBgJ_XuaA_YufAoAoFaBgDdEiDbRiWo@iA]s@}Pw[yF}GgKoF}g@cXq@OmCi@mGIeHvBaHvEak@p]";
const GRAPH: &str = "20261006T0300Z-fr";

fn route_json(geometry: &str, steps: &Value) -> Value {
    let points = polyline::decode(geometry).unwrap();
    let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    json!({"code": "Ok", "waypoints": [], "routes": [{
        "geometry": geometry,
        "distance": distance,
        "duration": distance / 10.0,
        "weight_name": "auto",
        "legs": [{"distance": distance, "steps": steps}]
    }]})
}

fn osrm(geometry: &str) -> Value {
    let points = polyline::decode(geometry).unwrap();
    let distance: f64 = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    route_json(
        geometry,
        &json!([{"distance": distance, "mode": "driving", "maneuver": {"type": "depart"}}]),
    )
}

#[derive(Clone)]
struct Fake {
    answers: Arc<Vec<Value>>,
    asked: Arc<Mutex<Vec<Value>>>,
}

async fn fake_route(State(f): State<Fake>, Json(body): Json<Value>) -> (StatusCode, Json<Value>) {
    let n = {
        let mut asked = f.asked.lock().unwrap();
        asked.push(body);
        asked.len()
    };
    (
        StatusCode::OK,
        Json(f.answers[(n - 1).min(f.answers.len() - 1)].clone()),
    )
}

async fn engine(answers: Vec<Value>) -> (String, Arc<Mutex<Vec<Value>>>) {
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
    let defaults = ApiConfig::default();
    let mut quotas = defaults.quotas;
    quotas.account_creation.count = 1_000;
    quotas.sign_in.count = 1_000;
    quotas.challenge.count = 1_000;
    ApiConfig {
        routing: RoutingConfig {
            valhalla_url: Some(url.to_owned()),
            timeout: Duration::from_millis(500),
            concurrency: 4,
            queue_wait: Duration::from_millis(200),
        },
        quotas,
        ..defaults
    }
}

async fn seed_graph(pool: &PgPool) {
    routing::load_graph(
        pool,
        &NewGraph {
            id: GRAPH.to_owned(),
            osm_data_at: Utc.with_ymd_and_hms(2026, 10, 5, 20, 20, 43).unwrap(),
            ign_fetched_at: None,
            ign_edition: None,
            built_at: Utc.with_ymd_and_hms(2026, 10, 6, 7, 0, 0).unwrap(),
            engine: "valhalla 3.9.0".to_owned(),
            stats: json!({}),
        },
        &[],
    )
    .await
    .unwrap();
    routing::activate(pool, GRAPH).await.unwrap();
}

/// The feed `source` read `ago` before now.
async fn read(pool: &PgPool, source: &str, ago: chrono::Duration) {
    let at = Utc::now() - ago;
    let read = events::Read {
        state: &json!({}),
        full: true,
        data_at: Some(at),
    };
    events::record_read(pool, source, at, Ok(read))
        .await
        .unwrap();
}

fn closure(id: &str, geometry: SourceGeometry, quality: MatchQuality) -> NewEvent {
    NewEvent {
        external_id: id.to_owned(),
        external_version: "0000000001".to_owned(),
        situation_id: None,
        class: EventClass::Closure,
        detail: "roadClosed".to_owned(),
        carriageway: Carriageway::Main,
        direction: EventDirection::Both,
        road_number: None,
        road_name: Some("Rue Maurice Utrillo".to_owned()),
        limits: VehicleLimits::default(),
        valid_from: Utc::now() - chrono::Duration::hours(1),
        valid_to: Some(Utc::now() + chrono::Duration::hours(3)),
        schedule: Schedule::default(),
        geometry,
        match_quality: quality,
        confidence: Confidence::Official,
        description: Some("Route barrée".to_owned()),
        detour: None,
        url: None,
        source_updated_at: Some(Utc::now()),
        raw: "<situationRecord/>".to_owned(),
        ended: None,
    }
}

/// Stores `e` for `source`, matched on `lines` when given.
async fn store(
    pool: &PgPool,
    source: &str,
    e: NewEvent,
    lines: Option<Vec<Vec<Position>>>,
) -> uuid::Uuid {
    let id = e.external_id.clone();
    let mut w = events::begin_writer(pool).await.unwrap();
    events::upsert(&mut w, source, &[e], Utc::now(), Utc::now(), true)
        .await
        .unwrap();
    w.commit().await.unwrap();
    let row = sqlx::query_scalar!("SELECT id FROM road_events WHERE external_id = $1", id)
        .fetch_one(pool)
        .await
        .unwrap();
    if let Some(lines) = lines {
        let task = events::match_tasks(pool, GRAPH, 1_000)
            .await
            .unwrap()
            .into_iter()
            .find(|t| t.id == row)
            .unwrap();
        let mut w = events::begin_writer(pool).await.unwrap();
        assert!(
            events::set_match(&mut w, &task, Some(&lines), GRAPH)
                .await
                .unwrap()
        );
        w.commit().await.unwrap();
    }
    row
}

/// The stretch of the route under the bridge, in its driving order.
fn under_stretch() -> Vec<Position> {
    polyline::decode(ROUTE_UNDER).unwrap()[3..9].to_vec()
}

const ROUTE_QUERY: &str = r"
query Route($input: RouteInput!) {
  route(input: $input) {
    status recalculations
    routes { roadEvents { severity reason distanceFromStartM arrivalAt dataAgeSeconds
      event { externalId class source match mayBlock } } }
    roadEventBlockers { reason event { externalId } }
    avoidedRoadEvents { externalId class source }
    roadEventSources { id fresh ageSeconds }
  }
}";

fn input(depart: Option<DateTime<Utc>>) -> Value {
    json!({"input": {
        "origin": {"lat": 45.84719, "lon": 1.28476},
        "destination": {"lat": 45.84510, "lon": 1.28637},
        "vehicle": {"kind": "VAN", "heightM": 2.5, "widthM": 2.0, "lengthM": 5.4, "weightT": 3.0},
        "departAt": depart.map(|d| d.to_rfc3339()),
        "language": "FR"
    }})
}

async fn gql(app: &Router, token: Option<&str>, query: &str, variables: Value) -> Value {
    let mut r = Request::post("/graphql").header("content-type", "application/json");
    if let Some(t) = token {
        r = r.header("authorization", format!("Bearer {t}"));
    }
    let request = r
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_goes_around_a_closure_active_when_the_vehicle_gets_there(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    store(
        &pool,
        "dir",
        closure(
            "closed",
            SourceGeometry::Lines(vec![under_stretch()]),
            MatchQuality::Pending,
        ),
        Some(vec![under_stretch()]),
    )
    .await;
    let (url, asked) = engine(vec![osrm(ROUTE_UNDER), osrm(ROUTE_AROUND)]).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(r["recalculations"], 1, "the closed road is avoided");
    assert_eq!(r["avoidedRoadEvents"][0]["externalId"], "closed");
    assert_eq!(r["avoidedRoadEvents"][0]["source"], "dir");
    let dir = r["roadEventSources"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["id"] == "dir")
        .unwrap();
    assert_eq!(dir["fresh"], true);
    let asked = asked.lock().unwrap();
    let ring = asked[1]["exclude_polygons"][0].as_array().unwrap();
    assert_eq!(ring.len(), 9);
    let centre = |ring: &[Value]| {
        let (sum_lat, sum_lon) = ring[..8].iter().fold((0.0, 0.0), |(a, b), p| {
            (a + p[1].as_f64().unwrap(), b + p[0].as_f64().unwrap())
        });
        Position::new(sum_lat / 8.0, sum_lon / 8.0).unwrap()
    };
    let c = centre(ring);
    let route = RouteLine::new(polyline::decode(ROUTE_UNDER).unwrap()).unwrap();
    let on = route
        .project(c, 1.0)
        .expect("the ring sits on the closed road the route used");
    assert!(on.distance_m < 0.5);
    let radius = c.distance_m(
        Position::new(ring[0][1].as_f64().unwrap(), ring[0][0].as_f64().unwrap()).unwrap(),
    );
    assert!(
        (radius - 3.0).abs() < 0.2,
        "a 3 m ring, small enough to spare a bridge above: {radius}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_closure_of_the_other_carriageway_or_another_time_is_not_avoided(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    let mut other_way = under_stretch();
    other_way.reverse();
    let mut one_way = closure(
        "other-way",
        SourceGeometry::Lines(vec![other_way.clone()]),
        MatchQuality::Pending,
    );
    one_way.direction = EventDirection::Forward;
    store(&pool, "dir", one_way, Some(vec![other_way])).await;
    let mut later = closure(
        "tonight",
        SourceGeometry::Lines(vec![under_stretch()]),
        MatchQuality::Pending,
    );
    later.valid_from = Utc::now() + chrono::Duration::hours(2);
    later.valid_to = Some(Utc::now() + chrono::Duration::hours(10));
    store(&pool, "dir", later, Some(vec![under_stretch()])).await;
    let (url, asked) = engine(vec![
        osrm(ROUTE_UNDER),
        osrm(ROUTE_UNDER),
        osrm(ROUTE_AROUND),
    ])
    .await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(
        r["recalculations"], 0,
        "a closure of the other direction, or one that starts after the vehicle has passed, \
         must not send it around: {body}"
    );
    assert_eq!(asked.lock().unwrap().len(), 1);

    // The same trip two hours later meets the evening closure.
    let body = gql(
        &app,
        None,
        ROUTE_QUERY,
        input(Some(
            Utc::now() + chrono::Duration::hours(2) + chrono::Duration::minutes(5),
        )),
    )
    .await;
    let r = &body["data"]["route"];
    assert_eq!(r["recalculations"], 1, "{body}");
    assert_eq!(r["avoidedRoadEvents"][0]["externalId"], "tonight");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_closure_whose_feed_is_stale_warns_instead_of_blocking(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::hours(3)).await;
    store(
        &pool,
        "dir",
        closure(
            "stale",
            SourceGeometry::Lines(vec![under_stretch()]),
            MatchQuality::Pending,
        ),
        Some(vec![under_stretch()]),
    )
    .await;
    let unmatched = closure(
        "unplaced",
        SourceGeometry::Point(polyline::decode(ROUTE_UNDER).unwrap()[5]),
        MatchQuality::Unmatched,
    );
    store(&pool, "dialog", unmatched, None).await;
    read(&pool, "dialog", chrono::Duration::minutes(1)).await;
    let (url, _) = engine(vec![osrm(ROUTE_UNDER)]).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(r["recalculations"], 0);
    let warnings = r["routes"][0]["roadEvents"].as_array().unwrap();
    let reason = |id: &str| {
        warnings
            .iter()
            .find(|w| w["event"]["externalId"] == id)
            .map(|w| (w["severity"].clone(), w["reason"].clone()))
    };
    assert_eq!(
        reason("stale"),
        Some((json!("WARNING"), json!("STALE"))),
        "a feed not read for three hours no longer closes roads: {body}"
    );
    assert_eq!(
        reason("unplaced"),
        Some((json!("WARNING"), json!("UNMATCHED"))),
        "an event that could not be placed is told with its position"
    );
    assert!(
        warnings
            .iter()
            .all(|w| w["dataAgeSeconds"].as_i64().is_some())
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_closed_exit_closes_its_slip_road_never_the_main_road(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    let around = polyline::decode(ROUTE_AROUND).unwrap();
    let line = RouteLine::new(around).unwrap();
    // The route follows the N20 for 1 000 m, then takes an exit.
    let steps = json!([
        {"distance": 1000.0, "ref": "N 20", "maneuver": {"type": "depart"}},
        {"distance": line.length_m() - 1000.0, "maneuver": {"type": "off ramp"}}
    ]);
    let with_exit = route_json(ROUTE_AROUND, &steps);
    let mut exit = closure(
        "exit",
        SourceGeometry::Point(line.point_at(900.0)),
        MatchQuality::Ramp,
    );
    exit.carriageway = Carriageway::Exit;
    exit.road_number = Some("N20".to_owned());
    exit.detail = "doNotUseExit".to_owned();
    store(&pool, "dir", exit, None).await;
    let (url, asked) = engine(vec![with_exit.clone(), osrm(ROUTE_UNDER)]).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(r["recalculations"], 1, "the closed exit is avoided: {body}");
    let ring = asked.lock().unwrap()[1]["exclude_polygons"][0][0].clone();
    let p = Position::new(ring[1].as_f64().unwrap(), ring[0].as_f64().unwrap()).unwrap();
    let at = line.project(p, 10.0).unwrap();
    assert!(
        at.along_m > 1_000.0,
        "the ring is on the slip road, past the exit, never on the N20: {}",
        at.along_m
    );

    // A route that stays on the N20 is untouched by the closed exit.
    let steps =
        json!([{"distance": line.length_m(), "ref": "N 20", "maneuver": {"type": "depart"}}]);
    let (url, asked) = engine(vec![route_json(ROUTE_AROUND, &steps)]).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    assert_eq!(body["data"]["route"]["recalculations"], 0, "{body}");
    assert_eq!(asked.lock().unwrap().len(), 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_exit_is_placed_where_the_engine_says_it_is_not_where_its_lengths_add_up(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    let around = polyline::decode(ROUTE_AROUND).unwrap();
    let line = RouteLine::new(around).unwrap();
    let mut exit = closure(
        "exit",
        SourceGeometry::Point(line.point_at(900.0)),
        MatchQuality::Ramp,
    );
    exit.carriageway = Carriageway::Exit;
    exit.road_number = Some("N20".to_owned());
    exit.detail = "doNotUseExit".to_owned();
    store(&pool, "dir", exit, None).await;
    let lon_lat = |s: f64| {
        let p = line.point_at(s);
        json!([p.lon(), p.lat()])
    };
    // The engine's lengths put the exit 100 m further than its maneuver
    // point, which lies on the route at 1 000 m.
    let steps = json!([
        {"distance": 1100.0, "ref": "N 20", "maneuver": {"type": "depart", "location": lon_lat(0.0)}},
        {"distance": line.length_m() - 1100.0, "maneuver": {"type": "off ramp", "location": lon_lat(1_000.0)}}
    ]);
    let (url, asked) = engine(vec![route_json(ROUTE_AROUND, &steps), osrm(ROUTE_UNDER)]).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    assert_eq!(body["data"]["route"]["recalculations"], 1, "{body}");
    let ring = asked.lock().unwrap()[1]["exclude_polygons"][0][0].clone();
    let p = Position::new(ring[1].as_f64().unwrap(), ring[0].as_f64().unwrap()).unwrap();
    let at = line.project(p, 10.0).unwrap();
    assert!(
        (at.along_m - 1_080.0).abs() < 15.0,
        "the ring is 80 m into the slip road from its maneuver point: {}",
        at.along_m
    );
}

struct Device(SigningKey);

impl Device {
    fn new(n: u8) -> Self {
        let mut d = [0u8; 32];
        d[31] = n;
        d[0] = 1;
        Self(SigningKey::from_slice(&d).unwrap())
    }

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
    }

    fn jwk(&self) -> String {
        let point = self.0.verifying_key().to_sec1_point(false);
        let bytes = point.as_bytes();
        json!({"kty": "EC", "crv": "P-256", "x": Self::b64(&bytes[1..33]), "y": Self::b64(&bytes[33..65])})
            .to_string()
    }

    fn sign(&self, message: &str) -> String {
        let signature: p256::ecdsa::Signature = self.0.sign(message.as_bytes());
        Self::b64(&signature.to_bytes())
    }
}

async fn sign_in(app: &Router, device: &Device) -> String {
    let body = gql(
        app,
        None,
        "mutation { authChallenge { nonce message } }",
        json!({}),
    )
    .await;
    let c = &body["data"]["authChallenge"];
    let body = gql(
        app,
        None,
        r#"mutation($jwk: String!, $nonce: String!, $sig: String!) {
          signIn(publicKeyJwk: $jwk, nonce: $nonce, signature: $sig, locale: "fr") { token } }"#,
        json!({"jwk": device.jwk(), "nonce": c["nonce"], "sig": device.sign(c["message"].as_str().unwrap())}),
    )
    .await;
    body["data"]["signIn"]["token"].as_str().unwrap().to_owned()
}

const REPORT: &str = r"mutation($input: RoadEventReportInput!) {
  reportRoadEvent(input: $input) { eventId confidence expiresAt } }";

#[sqlx::test(migrations = "../../migrations")]
async fn a_report_warns_and_a_second_account_s_report_blocks(pool: PgPool) {
    seed_graph(&pool).await;
    let route = RouteLine::new(polyline::decode(ROUTE_UNDER).unwrap()).unwrap();
    let spot = route.point_at(150.0);
    #[allow(
        clippy::cast_possible_truncation,
        reason = "a heading between 0 and 360"
    )]
    let heading = route.heading_at(150.0).round() as i64 % 360;
    let report = json!({"input": {"kind": "CLOSURE", "lat": spot.lat(), "lon": spot.lon(), "headingDeg": heading}});
    // The first route; the second, met by the confirmed closure, then
    // around it; the third, once the closure is over.
    let (url, asked) = engine(vec![
        osrm(ROUTE_UNDER),
        osrm(ROUTE_UNDER),
        osrm(ROUTE_AROUND),
        osrm(ROUTE_UNDER),
    ])
    .await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let anonymous = gql(&app, None, REPORT, report.clone()).await;
    assert_eq!(
        anonymous["errors"][0]["extensions"]["code"],
        "UNAUTHENTICATED"
    );
    let a = sign_in(&app, &Device::new(1)).await;
    let b = sign_in(&app, &Device::new(2)).await;
    // Both past level 0: two new accounts only warn (lunaway-db's tests).
    for id in sqlx::query_scalar::<_, uuid::Uuid>("SELECT id FROM accounts")
        .fetch_all(&pool)
        .await
        .unwrap()
    {
        lunaway_db::accounts::set_granted_level(&pool, id, 1)
            .await
            .unwrap();
    }
    let no_height = gql(
        &app,
        Some(&a),
        REPORT,
        json!({"input": {"kind": "LOW_CLEARANCE", "lat": spot.lat(), "lon": spot.lon()}}),
    )
    .await;
    assert_eq!(
        no_height["errors"][0]["extensions"]["code"],
        "INVALID_INPUT"
    );

    let first = gql(&app, Some(&a), REPORT, report.clone()).await;
    assert_eq!(
        first["data"]["reportRoadEvent"]["confidence"], "REPORTED",
        "{first}"
    );
    let body = gql(&app, Some(&b), ROUTE_QUERY, input(None)).await;
    let r = &body["data"]["route"];
    assert_eq!(
        r["recalculations"], 0,
        "one account alone does not close a road: {body}"
    );
    assert_eq!(r["routes"][0]["roadEvents"][0]["reason"], "UNCONFIRMED");
    assert_eq!(
        r["routes"][0]["roadEvents"][0]["event"]["source"],
        "community"
    );

    let second = gql(&app, Some(&b), REPORT, report).await;
    let event_id = second["data"]["reportRoadEvent"]["eventId"].clone();
    assert_eq!(
        second["data"]["reportRoadEvent"]["confidence"], "CONFIRMED",
        "{second}"
    );
    assert_eq!(event_id, first["data"]["reportRoadEvent"]["eventId"]);
    let feed = gql(
        &app,
        None,
        "{ roadEvents { upserts { source position { lat lon } validFrom firstSeenAt sourceUpdatedAt } } }",
        json!({}),
    )
    .await;
    let published = feed["data"]["roadEvents"]["upserts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["source"] == "community")
        .unwrap()
        .clone();
    for axis in ["lat", "lon"] {
        let v = published["position"][axis].as_f64().unwrap() * 10_000.0;
        assert!(
            (v - v.round()).abs() < 1e-6,
            "a user's position is published to about ten metres: {published}"
        );
    }
    for field in ["validFrom", "firstSeenAt"] {
        let t = chrono::DateTime::parse_from_rfc3339(published[field].as_str().unwrap()).unwrap();
        assert_eq!(
            (t.minute(), t.second(), t.nanosecond()),
            (0, 0, 0),
            "the reports' times are published to the hour: {published}"
        );
    }
    assert!(published["sourceUpdatedAt"].is_null(), "{published}");
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    assert_eq!(
        body["data"]["route"]["recalculations"], 1,
        "two accounts close it: {body}"
    );
    assert_eq!(asked.lock().unwrap().len(), 3);

    let clear = "mutation($id: UUID!) { clearRoadEvent(eventId: $id) }";
    let cleared = gql(&app, Some(&a), clear, json!({"id": event_id})).await;
    assert_eq!(
        cleared["data"]["clearRoadEvent"], "WARNING",
        "one account's \"plus de travaux\" makes it a warning: {cleared}"
    );
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    assert_eq!(
        body["data"]["route"]["recalculations"], 0,
        "a warning no longer closes the road: {body}"
    );
    let cleared = gql(&app, Some(&b), clear, json!({"id": event_id})).await;
    assert_eq!(
        cleared["data"]["clearRoadEvent"], "ENDED",
        "a second account's ends it for everyone: {cleared}"
    );
}

const DELTA: &str = r"query($since: String, $classes: [RoadEventClass!], $blocking: Boolean = true) {
  roadEvents(since: $since, classes: $classes, blockingOnly: $blocking) {
    cursor full hasMore pollIntervalSeconds removals
    upserts { id externalId class mayBlock match lines position { lat lon } schedule { timeZone marginMinutes } }
    sources { id fresh }
  } }";

#[sqlx::test(migrations = "../../migrations")]
async fn a_phone_polls_the_changes_without_sending_where_it_is(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    let closed = store(
        &pool,
        "dir",
        closure(
            "closed",
            SourceGeometry::Lines(vec![under_stretch()]),
            MatchQuality::Pending,
        ),
        Some(vec![under_stretch()]),
    )
    .await;
    let mut works = closure(
        "works",
        SourceGeometry::Point(under_stretch()[0]),
        MatchQuality::Point,
    );
    works.class = EventClass::Works;
    store(&pool, "dir", works, None).await;
    let (url, _) = engine(vec![osrm(ROUTE_UNDER)]).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));

    let body = gql(&app, None, DELTA, json!({})).await;
    let d = &body["data"]["roadEvents"];
    assert_eq!(d["full"], true, "{body}");
    assert_eq!(d["pollIntervalSeconds"], 180);
    let ids: Vec<&str> = d["upserts"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["externalId"].as_str().unwrap())
        .collect();
    assert_eq!(ids, ["closed"], "by default, what can block a route");
    assert_eq!(d["upserts"][0]["mayBlock"], true);
    assert_eq!(d["upserts"][0]["match"], "MATCHED");
    assert_eq!(d["upserts"][0]["lines"].as_array().unwrap().len(), 1);
    let cursor = d["cursor"].as_str().unwrap().to_owned();

    let body = gql(&app, None, DELTA, json!({"since": cursor})).await;
    let d = &body["data"]["roadEvents"];
    assert_eq!(d["full"], false);
    assert_eq!(d["upserts"], json!([]), "nothing changed");
    assert_eq!(d["removals"], json!([]));

    // The closure ends; a new one starts.
    let mut w = events::begin_writer(&pool).await.unwrap();
    events::end_records(&mut w, "dir", &["closed".to_owned()], Utc::now())
        .await
        .unwrap();
    w.commit().await.unwrap();
    store(
        &pool,
        "dir",
        closure(
            "new",
            SourceGeometry::Point(under_stretch()[1]),
            MatchQuality::Point,
        ),
        None,
    )
    .await;
    // The head is read again after its few seconds of trust.
    tokio::time::sleep(Duration::from_millis(5_100)).await;
    let body = gql(&app, None, DELTA, json!({"since": cursor})).await;
    let d = &body["data"]["roadEvents"];
    assert_eq!(d["full"], false, "{body}");
    assert_eq!(d["upserts"].as_array().unwrap().len(), 1);
    assert_eq!(d["upserts"][0]["externalId"], "new");
    assert_eq!(
        d["removals"],
        json!([closed.to_string()]),
        "the ended closure is dropped"
    );

    let other_copy = format!("e1.{}.0", "f".repeat(40));
    let body = gql(&app, None, DELTA, json!({"since": other_copy})).await;
    assert_eq!(
        body["data"]["roadEvents"]["full"], true,
        "a cursor of another copy of the database gets the whole set"
    );
    let body = gql(&app, None, DELTA, json!({"since": "e1.nope"})).await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
    let body = gql(&app, None, DELTA, json!({"classes": ["WORKS"]})).await;
    assert_eq!(
        body["data"]["roadEvents"]["upserts"],
        json!([]),
        "works cannot block a route: not in the blocking selection: {body}"
    );
    let body = gql(
        &app,
        None,
        DELTA,
        json!({"classes": ["WORKS"], "blocking": false}),
    )
    .await;
    assert_eq!(
        body["data"]["roadEvents"]["upserts"][0]["externalId"], "works",
        "{body}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_report_while_a_feed_is_written_answers_unavailable_within_seconds(pool: PgPool) {
    let (url, _) = engine(Vec::new()).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let token = sign_in(&app, &Device::new(1)).await;
    let feed = lunaway_db::road_events::begin_writer(&pool).await.unwrap();
    let started = std::time::Instant::now();
    let body = gql(
        &app,
        Some(&token),
        REPORT,
        json!({"input": {"kind": "CLOSURE", "lat": 45.8, "lon": 1.25}}),
    )
    .await;
    let waited = started.elapsed();
    assert_eq!(
        body["errors"][0]["extensions"]["code"], "UNAVAILABLE",
        "{body}"
    );
    assert!(
        waited < std::time::Duration::from_secs(10),
        "the API's connection is not held while a feed is written: {waited:?}"
    );
    feed.commit().await.unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_phone_receives_an_event_three_days_ahead_only_once_it_enters_the_window(pool: PgPool) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    let mut ahead = closure(
        "ahead",
        SourceGeometry::Lines(vec![under_stretch()]),
        MatchQuality::Pending,
    );
    ahead.valid_from = Utc::now() + chrono::Duration::days(3);
    ahead.valid_to = Some(Utc::now() + chrono::Duration::days(4));
    let ahead = store(&pool, "dir", ahead, Some(vec![under_stretch()])).await;
    let (url, _) = engine(vec![osrm(ROUTE_UNDER)]).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));

    let body = gql(&app, None, DELTA, json!({})).await;
    let d = &body["data"]["roadEvents"];
    assert_eq!(d["full"], true, "{body}");
    assert_eq!(
        d["upserts"],
        json!([]),
        "a closure three days ahead is not in a phone's whole set: {body}"
    );
    let cursor = d["cursor"].as_str().unwrap().to_owned();

    // Two days on, the poller's pass lets it into the window.
    let done = events::lifecycle(
        &pool,
        Utc::now() + chrono::Duration::hours(49),
        chrono::Duration::days(30),
        chrono::Duration::days(7),
        chrono::Duration::days(14),
    )
    .await
    .unwrap();
    assert_eq!(done.entered_window, 1);
    tokio::time::sleep(Duration::from_millis(5_100)).await;
    let body = gql(&app, None, DELTA, json!({"since": cursor})).await;
    let d = &body["data"]["roadEvents"];
    assert_eq!(d["full"], false, "{body}");
    assert_eq!(
        d["upserts"][0]["id"],
        ahead.to_string(),
        "the cursor the phone holds delivers it once it enters the window: {body}"
    );
    assert_eq!(d["upserts"].as_array().unwrap().len(), 1);
    assert_eq!(d["removals"], json!([]));
    let cursor = d["cursor"].as_str().unwrap().to_owned();

    // Postponed by its source past the window: the phone drops it.
    let mut postponed = closure(
        "ahead",
        SourceGeometry::Lines(vec![under_stretch()]),
        MatchQuality::Pending,
    );
    postponed.external_version = "0000000002".to_owned();
    postponed.valid_from = Utc::now() + chrono::Duration::days(5);
    postponed.valid_to = Some(Utc::now() + chrono::Duration::days(6));
    let mut w = events::begin_writer(&pool).await.unwrap();
    events::upsert(&mut w, "dir", &[postponed], Utc::now(), Utc::now(), true)
        .await
        .unwrap();
    w.commit().await.unwrap();
    tokio::time::sleep(Duration::from_millis(5_100)).await;
    let body = gql(&app, None, DELTA, json!({"since": cursor})).await;
    let d = &body["data"]["roadEvents"];
    assert_eq!(d["upserts"], json!([]), "{body}");
    assert_eq!(
        d["removals"],
        json!([ahead.to_string()]),
        "an event postponed past the window leaves the phones' sets"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_route_avoids_a_closure_in_force_when_it_arrives_whatever_the_phones_window(
    pool: PgPool,
) {
    seed_graph(&pool).await;
    read(&pool, "dir", chrono::Duration::minutes(5)).await;
    // One closure 30 hours ahead, inside the phones' window; one three
    // days ahead, outside it: the route reads both.
    for (id, from) in [
        ("tomorrow", chrono::Duration::hours(30)),
        ("in-three-days", chrono::Duration::days(3)),
    ] {
        let mut c = closure(
            id,
            SourceGeometry::Lines(vec![under_stretch()]),
            MatchQuality::Pending,
        );
        c.valid_from = Utc::now() + from;
        c.valid_to = Some(Utc::now() + from + chrono::Duration::hours(4));
        store(&pool, "dir", c, Some(vec![under_stretch()])).await;
    }
    let in_window: Vec<(String, bool)> =
        sqlx::query_as("SELECT external_id, in_window FROM road_events ORDER BY valid_from")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(
        in_window,
        [
            ("tomorrow".to_owned(), true),
            ("in-three-days".to_owned(), false)
        ]
    );
    let (url, _) = engine(vec![
        osrm(ROUTE_UNDER),
        osrm(ROUTE_UNDER),
        osrm(ROUTE_AROUND),
        osrm(ROUTE_UNDER),
        osrm(ROUTE_AROUND),
    ])
    .await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
    let body = gql(&app, None, ROUTE_QUERY, input(None)).await;
    assert_eq!(
        body["data"]["route"]["recalculations"], 0,
        "neither closure is in force now: {body}"
    );
    for (id, depart) in [
        ("tomorrow", chrono::Duration::hours(30)),
        ("in-three-days", chrono::Duration::days(3)),
    ] {
        let at = Utc::now() + depart + chrono::Duration::minutes(5);
        let body = gql(&app, None, ROUTE_QUERY, input(Some(at))).await;
        let r = &body["data"]["route"];
        assert_eq!(r["status"], "OK", "{body}");
        assert_eq!(r["recalculations"], 1, "{body}");
        assert_eq!(
            r["avoidedRoadEvents"][0]["externalId"], id,
            "the route checks every event at the vehicle's time of arrival, \
             not only those the phones receive: {body}"
        );
    }
}
