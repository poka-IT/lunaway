//! A route's alternatives after its best route: `RouteResult.alternativesToken`
//! and `Query.routeAlternatives`, against the fake engine of `route.rs`.

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
use http_body_util::BodyExt;
use lunaway_api::{ApiState, config::Quota};
use lunaway_db::PgPool;
use lunaway_domain::{Position, routing::polyline};
use serde_json::{Value, json};
use tokio::sync::Notify;
use tower::ServiceExt;

use super::route::{ROUTE_AROUND, ROUTE_UNDER, code, config, engine, gql, input, osrm, seed};

/// The route as the app reads it from 0.4 on: the token selected.
const LATER_QUERY: &str = r"
query Route($input: RouteInput!) {
  route(input: $input) {
    status osrmJson alternativesToken recalculations
    routes { index distanceM }
  }
}";

/// The route as the app 0.1.0 reads it: no token.
const ONCE_QUERY: &str = r"
query Route($input: RouteInput!) {
  route(input: $input) {
    status osrmJson
    routes { index distanceM }
  }
}";

const ALTERNATIVES_QUERY: &str = r"
query Alternatives($token: String!) {
  routeAlternatives(token: $token) {
    status osrmJson
    routes { index distanceM warnings { externalId } }
  }
}";

/// A third way between the stops of `route.rs`, east of the bridge: a
/// route no limit blocks.
fn detour() -> String {
    polyline::encode(&[
        Position::new(45.847_19, 1.284_76).unwrap(),
        Position::new(45.846_8, 1.288_5).unwrap(),
        Position::new(45.845_1, 1.286_37).unwrap(),
    ])
}

/// `height_m`'s trip with two alternatives.
fn wanting_two(height_m: f64) -> Value {
    let mut v = input(height_m);
    v["input"]["alternatives"] = 2.into();
    v
}

fn shapes(osrm_json: &Value) -> Vec<String> {
    let osrm: Value = serde_json::from_str(osrm_json.as_str().unwrap()).unwrap();
    osrm["routes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["geometry"].as_str().unwrap().to_owned())
        .collect()
}

async fn alternatives(app: &Router, token: &str) -> Value {
    gql(app, ALTERNATIVES_QUERY, json!({"token": token}))
        .await
        .1
}

#[sqlx::test(migrations = "../../migrations")]
async fn alternatives_too_large_are_asked_again_one_less(pool: PgPool) {
    seed(&pool).await;
    // Long trips off motorways: three routes weighed more than the API reads
    // of an answer, two did not (2026-10-11).
    let heavy = json!({"code": "Ok", "routes": [], "padding": "x".repeat(17 * 1024 * 1024)});
    let (url, asked) = engine(
        vec![
            (200, osrm(&[ROUTE_UNDER])),
            (200, heavy),
            (200, osrm(&[ROUTE_UNDER, ROUTE_AROUND])),
        ],
        Duration::ZERO,
    )
    .await;
    let mut c = config(&url);
    c.routing.timeout = Duration::from_secs(5);
    let app = lunaway_api::router(ApiState::new(pool, c));
    let (_, body) = gql(&app, LATER_QUERY, wanting_two(2.5)).await;
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let a = alternatives(&app, &token).await;
    let a = &a["data"]["routeAlternatives"];
    assert_eq!(a["status"], "OK", "{a}");
    assert_eq!(
        shapes(&a["osrmJson"]),
        [ROUTE_AROUND],
        "the alternative that fits comes back"
    );
    let asked = asked.lock().unwrap();
    let alternates: Vec<Option<u64>> = asked
        .iter()
        .map(|b| b.get("alternates").and_then(Value::as_u64))
        .collect();
    assert_eq!(alternates, [None, Some(2), Some(1)]);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_best_route_comes_alone_and_its_alternatives_follow_once(pool: PgPool) {
    seed(&pool).await;
    let detour = detour();
    let (url, asked) = engine(
        vec![
            (200, osrm(&[ROUTE_UNDER])),
            (200, osrm(&[ROUTE_UNDER, ROUTE_AROUND, &detour])),
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

    let (_, body) = gql(&app, LATER_QUERY, wanting_two(2.5)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(
        shapes(&r["osrmJson"]),
        [ROUTE_UNDER],
        "the best route alone, without waiting for the others"
    );
    let token = r["alternativesToken"].as_str().unwrap().to_owned();

    let a = alternatives(&app, &token).await;
    let a = &a["data"]["routeAlternatives"];
    assert_eq!(a["status"], "OK", "{a}");
    assert_eq!(
        shapes(&a["osrmJson"]),
        [ROUTE_AROUND, detour.as_str()],
        "the alternatives alone: the best route is not sent twice"
    );
    assert_eq!(a["routes"][0]["index"], 0);
    assert_eq!(a["routes"][1]["index"], 1);

    let asked = asked.lock().unwrap().clone();
    assert_eq!(
        asked.len(),
        2,
        "one call for the best route, one for the rest"
    );
    assert!(
        asked[0].get("alternates").is_none(),
        "the best route's call asks for no alternative: {}",
        asked[0]
    );
    assert_eq!(asked[1]["alternates"], 2);
    assert_eq!(
        asked[1]["locations"], asked[0]["locations"],
        "the same trip, the same stops"
    );
    assert_eq!(asked[1]["costing_options"], asked[0]["costing_options"]);

    let again = alternatives(&app, &token).await;
    assert_eq!(code(&again), "NOT_FOUND", "once per token: {again}");
    let (_, spent) = gql(&app, LATER_QUERY, wanting_two(2.5)).await;
    assert_eq!(
        code(&spent),
        "RATE_LIMITED",
        "the quota of one route was the route's: the alternatives took none"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_request_without_the_token_gets_its_alternatives_in_one_answer(pool: PgPool) {
    seed(&pool).await;
    let detour = detour();
    let (url, asked) = engine(
        vec![(200, osrm(&[ROUTE_UNDER, ROUTE_AROUND, &detour]))],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, ONCE_QUERY, wanting_two(2.5)).await;
    let r = &body["data"]["route"];
    assert_eq!(r["status"], "OK", "{body}");
    assert_eq!(
        shapes(&r["osrmJson"]),
        [ROUTE_UNDER, ROUTE_AROUND, detour.as_str()],
        "the app 0.1.0 gets every route in one answer, as before"
    );
    let asked = asked.lock().unwrap().clone();
    assert_eq!(asked.len(), 1);
    assert_eq!(asked[0]["alternates"], 2);

    // Selected without alternatives wanted: nothing follows.
    let (_, body) = gql(&app, LATER_QUERY, input(2.5)).await;
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    assert!(body["data"]["route"]["alternativesToken"].is_null());
}

#[sqlx::test(migrations = "../../migrations")]
async fn alternatives_the_vehicle_may_not_drive_or_none_at_all_are_told_none(pool: PgPool) {
    seed(&pool).await;
    // A 3.3 m motorhome: the way under the 2.7 m bridge is no alternative.
    let (url, asked) = engine(
        vec![
            (200, osrm(&[ROUTE_AROUND])),
            (200, osrm(&[ROUTE_AROUND, ROUTE_UNDER])),
            (200, osrm(&[ROUTE_AROUND])),
            (200, osrm(&[ROUTE_AROUND])),
        ],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, LATER_QUERY, wanting_two(3.3)).await;
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let a = alternatives(&app, &token).await;
    let a = &a["data"]["routeAlternatives"];
    assert_eq!(
        a["status"], "NONE",
        "a route under a bridge too low never reaches the app: {a}"
    );
    assert!(a["osrmJson"].is_null());
    assert_eq!(a["routes"], json!([]));

    // The engine finds the best route alone.
    let (_, body) = gql(&app, LATER_QUERY, wanting_two(3.3)).await;
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let a = alternatives(&app, &token).await;
    assert_eq!(a["data"]["routeAlternatives"]["status"], "NONE", "{a}");
    assert_eq!(asked.lock().unwrap().len(), 4);
}

/// A router whose requests come through the local proxy, as in
/// production: each request names its client in `X-Forwarded-For`.
fn behind_proxy(state: ApiState) -> Router {
    lunaway_api::router(state).layer(axum::extract::connect_info::MockConnectInfo(
        "127.0.0.1:40000".parse::<std::net::SocketAddr>().unwrap(),
    ))
}

async fn gql_from(app: &Router, ip: &str, query: &str, variables: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .header("x-forwarded-for", ip)
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_token_gives_nothing_to_another_client(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = engine(
        vec![
            (200, osrm(&[ROUTE_UNDER])),
            (200, osrm(&[ROUTE_UNDER, ROUTE_AROUND])),
        ],
        Duration::ZERO,
    )
    .await;
    let app = behind_proxy(ApiState::new(pool, config(&url)));
    let body = gql_from(&app, "198.51.100.7", LATER_QUERY, wanting_two(2.5)).await;
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let other = gql_from(
        &app,
        "203.0.113.9",
        ALTERNATIVES_QUERY,
        json!({"token": token}),
    )
    .await;
    assert_eq!(code(&other), "NOT_FOUND", "{other}");
    assert!(other["data"].is_null() || other["data"]["routeAlternatives"].is_null());
    let mine = gql_from(
        &app,
        "198.51.100.7",
        ALTERNATIVES_QUERY,
        json!({"token": token}),
    )
    .await;
    assert_eq!(
        mine["data"]["routeAlternatives"]["status"], "OK",
        "another client's attempt does not spend the token: {mine}"
    );
    let forged = gql_from(
        &app,
        "198.51.100.7",
        ALTERNATIVES_QUERY,
        json!({"token": "not-a-token"}),
    )
    .await;
    assert_eq!(code(&forged), "NOT_FOUND");
}

/// What a fake engine that holds one trip records, and what lets it go.
#[derive(Clone)]
struct Held {
    asked: Arc<Mutex<Vec<Value>>>,
    held_lat: f64,
    release: Arc<Notify>,
}

async fn held_route(State(s): State<Held>, Json(body): Json<Value>) -> Json<Value> {
    let held = body["locations"][1]["lat"].as_f64() == Some(s.held_lat);
    s.asked.lock().unwrap().push(body);
    if held {
        s.release.notified().await;
    }
    Json(osrm(&[ROUTE_AROUND]))
}

/// A fake engine that answers the trips to `held_lat` once its `Notify` is
/// told, and the others at once.
async fn holding_engine(held_lat: f64) -> (String, Arc<Mutex<Vec<Value>>>, Arc<Notify>) {
    let s = Held {
        asked: Arc::new(Mutex::new(Vec::new())),
        held_lat,
        release: Arc::new(Notify::new()),
    };
    let asked = Arc::clone(&s.asked);
    let release = Arc::clone(&s.release);
    let app = Router::new()
        .route("/route", post(held_route))
        .route(
            "/status",
            get(|| async { Json(json!({"version": "3.9.1"})) }),
        )
        .with_state(s);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked, release)
}

#[sqlx::test(migrations = "../../migrations")]
async fn alternatives_take_an_engine_call_only_while_another_stays_free(pool: PgPool) {
    seed(&pool).await;
    let slow_lat = 45.845_2;
    let (url, asked, release) = holding_engine(slow_lat).await;
    let mut c = config(&url);
    c.routing.concurrency = 2;
    c.routing.timeout = Duration::from_secs(3);
    let app = behind_proxy(ApiState::new(pool, c));
    // Another client's trip holds one of the two calls.
    let mut slow = input(3.3);
    slow["input"]["destination"]["lat"] = slow_lat.into();
    let other = {
        let app = app.clone();
        tokio::spawn(async move { gql_from(&app, "203.0.113.20", ONCE_QUERY, slow).await })
    };
    while asked.lock().unwrap().is_empty() {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    let body = gql_from(&app, "198.51.100.7", LATER_QUERY, wanting_two(3.3)).await;
    assert_eq!(
        body["data"]["route"]["status"], "OK",
        "the best route takes the call left: {body}"
    );
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let a = gql_from(
        &app,
        "198.51.100.7",
        ALTERNATIVES_QUERY,
        json!({"token": token}),
    )
    .await;
    assert_eq!(
        a["data"]["routeAlternatives"]["status"], "BUSY",
        "the last free call stays for the clients' routes: {a}"
    );
    release.notify_one();
    let other = other.await.unwrap();
    assert_eq!(other["data"]["route"]["status"], "OK", "{other}");
    let asked = asked.lock().unwrap();
    assert_eq!(asked.len(), 2, "no call for the alternatives");
    assert!(asked.iter().all(|b| b.get("alternates").is_none()));
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failure_of_the_engine_for_the_alternatives_leaves_the_best_route_alone(pool: PgPool) {
    seed(&pool).await;
    let (url, _) = engine(
        vec![(200, osrm(&[ROUTE_UNDER])), (500, json!({"error": "boom"}))],
        Duration::ZERO,
    )
    .await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    let (_, body) = gql(&app, LATER_QUERY, wanting_two(2.5)).await;
    assert_eq!(body["data"]["route"]["status"], "OK", "{body}");
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let a = alternatives(&app, &token).await;
    assert_eq!(
        a["data"]["routeAlternatives"]["status"], "FAILED",
        "the engine failed for them, and the best route went before: {a}"
    );
    assert!(a["errors"].is_null(), "no error to show: {a}");
}

/// What a fake engine that answers by the kind of call records, and its
/// answers by kind: the best route alone, then around rings, today's request
/// with its alternatives, and the alternatives asked after the best route
/// (with rings). The calls around rings without alternatives, the
/// recalculation of a best route blocked alone, wait `around_delay`.
#[derive(Clone)]
struct ByKind {
    asked: Arc<Mutex<Vec<Value>>>,
    answers: Arc<[Value; 4]>,
    around_delay: Duration,
}

async fn by_kind(State(k): State<ByKind>, Json(body): Json<Value>) -> Json<Value> {
    let n = match (
        body.get("alternates").is_some(),
        body.get("exclude_polygons").is_some(),
    ) {
        (false, false) => 0,
        (false, true) => 1,
        (true, false) => 2,
        (true, true) => 3,
    };
    k.asked.lock().unwrap().push(body);
    if n == 1 {
        tokio::time::sleep(k.around_delay).await;
    }
    Json(k.answers[n].clone())
}

/// A fake engine that answers by the kind of call ([`ByKind`]): its URL and
/// the requests it receives.
pub(super) async fn kind_engine(
    answers: [Value; 4],
    around_delay: Duration,
) -> (String, Arc<Mutex<Vec<Value>>>) {
    let k = ByKind {
        asked: Arc::new(Mutex::new(Vec::new())),
        answers: Arc::new(answers),
        around_delay,
    };
    let asked = Arc::clone(&k.asked);
    let app = Router::new()
        .route("/route", post(by_kind))
        .route(
            "/status",
            get(|| async { Json(json!({"version": "3.9.1"})) }),
        )
        .with_state(k);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

/// `osrm` with each route timed and measured as given: seconds, metres.
fn timed(routes: &[(&str, f64, f64)]) -> Value {
    let geometries: Vec<&str> = routes.iter().map(|(g, ..)| *g).collect();
    let mut answer = osrm(&geometries);
    for (r, (_, s, m)) in answer["routes"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .zip(routes)
    {
        r["duration"] = (*s).into();
        r["distance"] = (*m).into();
    }
    answer
}

/// The four answers of a trip whose best route alone runs under the 2.7 m
/// bridge: around it ROUTE_AROUND, and today the detour beside it, each
/// timed and measured as given.
fn race(around: (f64, f64), today: (f64, f64)) -> [Value; 4] {
    let detour = detour();
    [
        timed(&[(ROUTE_UNDER, 40.0, 268.7)]),
        timed(&[(ROUTE_AROUND, around.0, around.1)]),
        timed(&[(ROUTE_UNDER, 40.0, 268.7), (&detour, today.0, today.1)]),
        timed(&[
            (ROUTE_AROUND, around.0, around.1),
            (&detour, today.0, today.1),
        ]),
    ]
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_best_route_blocked_alone_races_the_trip_asked_with_its_alternatives(pool: PgPool) {
    seed(&pool).await;
    // A 3.3 m motorhome: alone, the engine's best route runs under the
    // 2.7 m bridge. Computed again around it, it takes ROUTE_AROUND; asked
    // with its alternatives as today, the detour of that answer is safe.
    // Each way wins by its time, then at the same time by its length.
    for (around, today, kept, follows) in [
        (
            (150.0, 2_020.3),
            (200.0, 1_500.0),
            ROUTE_AROUND.to_owned(),
            true,
        ),
        ((250.0, 2_020.3), (200.0, 1_500.0), detour(), false),
        ((200.0, 2_020.3), (200.0, 1_500.0), detour(), false),
        (
            (200.0, 1_000.0),
            (200.0, 1_500.0),
            ROUTE_AROUND.to_owned(),
            true,
        ),
    ] {
        let (url, asked) = kind_engine(race(around, today), Duration::ZERO).await;
        let app = lunaway_api::router(ApiState::new(pool.clone(), config(&url)));
        let (_, body) = gql(&app, LATER_QUERY, wanting_two(3.3)).await;
        let r = &body["data"]["route"];
        assert_eq!(r["status"], "OK", "{body}");
        assert_eq!(
            shapes(&r["osrmJson"]),
            [kept.as_str()],
            "the faster safe best route of the two ways, then the shorter: \
             {around:?} around, {today:?} today"
        );
        assert_eq!(
            r["alternativesToken"].is_string(),
            follows,
            "today's answer brings its alternatives with it; the recalculation's follow"
        );
        let asked = asked.lock().unwrap().clone();
        assert!(
            asked
                .iter()
                .any(|b| b.get("alternates").is_none() && b.get("exclude_polygons").is_some()),
            "the recalculation ran"
        );
        assert!(
            asked
                .iter()
                .any(|b| b.get("alternates").is_some() && b.get("exclude_polygons").is_none()),
            "today's request ran beside it"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_best_route_safe_alone_makes_one_call(pool: PgPool) {
    seed(&pool).await;
    let (url, asked) = kind_engine(race((150.0, 2_020.3), (200.0, 1_500.0)), Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(&url)));
    // A 2.5 m van passes under the bridge: the first call stands.
    let (_, body) = gql(&app, LATER_QUERY, wanting_two(2.5)).await;
    assert_eq!(shapes(&body["data"]["route"]["osrmJson"]), [ROUTE_UNDER]);
    let token = body["data"]["route"]["alternativesToken"]
        .as_str()
        .unwrap()
        .to_owned();
    let _ = alternatives(&app, &token).await;
    let asked = asked.lock().unwrap();
    assert_eq!(
        asked.len(),
        2,
        "the best route, then its alternatives: no race"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_best_route_left_without_a_safe_way_gets_the_trip_asked_with_its_alternatives(
    pool: PgPool,
) {
    seed(&pool).await;
    // The best route alone runs under the 2.7 m bridge, and again once a
    // ring is put on it; asked with its alternatives, one goes round.
    let [alone, _, today, later] = race((150.0, 2_020.3), (200.0, 2_020.3));
    let answers = [alone.clone(), alone, today, later];
    for (concurrency, around_delay) in [
        // Beside the recalculation.
        (4, Duration::ZERO),
        // One engine call held by the recalculation past today's wait:
        // asked afterwards instead.
        (1, Duration::from_millis(400)),
    ] {
        let (url, asked) = kind_engine(answers.clone(), around_delay).await;
        let mut c = config(&url);
        c.routing.concurrency = concurrency;
        c.routing.timeout = Duration::from_secs(2);
        c.routing.queue_wait = Duration::from_secs(1);
        let app = lunaway_api::router(ApiState::new(pool.clone(), c));
        let (_, body) = gql(&app, LATER_QUERY, wanting_two(3.3)).await;
        let r = &body["data"]["route"];
        assert_eq!(
            r["status"], "OK",
            "the trip a request without the token would get, {concurrency} engine calls: {body}"
        );
        assert_eq!(shapes(&r["osrmJson"]), [detour()]);
        assert!(
            r["alternativesToken"].is_null(),
            "the alternatives came in this answer: {body}"
        );
        let asked = asked.lock().unwrap();
        assert!(
            asked
                .iter()
                .any(|b| b["alternates"] == 2 && b.get("exclude_polygons").is_none()),
            "{concurrency} engine calls: the trip asked with its alternatives"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn without_an_engine_a_best_route_asked_alone_is_unavailable_at_once(pool: PgPool) {
    seed(&pool).await;
    let mut c = config("http://127.0.0.1:9");
    c.routing.valhalla_url = None;
    let app = lunaway_api::router(ApiState::new(pool, c));
    let started = std::time::Instant::now();
    let (_, body) = gql(&app, LATER_QUERY, wanting_two(3.3)).await;
    assert_eq!(code(&body), "UNAVAILABLE", "{body}");
    assert!(
        started.elapsed() < Duration::from_secs(3),
        "nothing waits for a race that never starts: {:?}",
        started.elapsed()
    );
}
