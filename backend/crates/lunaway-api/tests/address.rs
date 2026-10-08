//! `searchAll`: the places, then the addresses of the geocoders, through the
//! router, with fake geocoders on the loopback.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Router,
    body::Body,
    extract::{Query, State},
    http::{Request, StatusCode},
    response::IntoResponse,
    routing::get,
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState, config::GeocodeConfig};
use lunaway_db::PgPool;
use lunaway_domain::SourceId;
use lunaway_ingest::{atout_france, geocode, osm, store::store_complete};
use serde_json::{Value, json};
use tower::ServiceExt;

const OVERPASS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/ban_answer_sample.csv");
const BAN_HOUSE: &[u8] = include_bytes!("fixtures/geocode/ban_housenumber.json");
const PHOTON_MIXED: &[u8] = include_bytes!("fixtures/geocode/photon_mixed.json");

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
    lunaway_conflate::run(
        pool,
        Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap(),
        None,
    )
    .await
    .unwrap();
    // As the worker does with the places' tiles: the towns of the search.
    lunaway_conflate::publish_place_layer(pool, Duration::ZERO)
        .await
        .unwrap();
}

/// What a fake geocoder answers, and what it was asked.
#[derive(Clone)]
struct Fake {
    status: u16,
    body: Arc<Vec<u8>>,
    delay: Duration,
    asked: Arc<Mutex<Vec<HashMap<String, String>>>>,
}

async fn answer(
    State(f): State<Fake>,
    Query(q): Query<Vec<(String, String)>>,
) -> impl IntoResponse {
    f.asked.lock().unwrap().push(q.into_iter().collect());
    tokio::time::sleep(f.delay).await;
    (
        StatusCode::from_u16(f.status).unwrap(),
        [("content-type", "application/json"), ("retry-after", "5")],
        f.body.as_ref().clone(),
    )
}

/// A geocoder on the loopback answering `body` on `path`: its URL and
/// the queries it receives.
async fn fake(
    path: &str,
    status: u16,
    body: &[u8],
    delay: Duration,
) -> (String, Arc<Mutex<Vec<HashMap<String, String>>>>) {
    let f = Fake {
        status,
        body: Arc::new(body.to_vec()),
        delay,
        asked: Arc::default(),
    };
    let asked = Arc::clone(&f.asked);
    let app = Router::new().route(path, get(answer)).with_state(f);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

fn config(ban: Option<&str>, photon: Option<&str>) -> ApiConfig {
    ApiConfig {
        geocode: GeocodeConfig {
            ban_url: ban.map(str::to_owned),
            photon_urls: photon.map(str::to_owned).into_iter().collect(),
            timeout: Duration::from_millis(400),
            ..GeocodeConfig::default()
        },
        ..ApiConfig::default()
    }
}

async fn gql(app: &Router, query: &str, variables: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

const SEARCH: &str = "query($t: String!, $near: LatLonInput) {
  searchAll(text: $t, near: $near) {
    places { name address { city postcode } }
    addresses { kind name postcode city countryCode lat lon source { id attribution licence } }
    addressesComplete
  }
}";

fn names(list: &Value) -> Vec<&str> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|a| a["name"].as_str().unwrap())
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_house_number_comes_after_the_places_with_its_source(pool: PgPool) {
    seeded(&pool).await;
    let (ban, asked) = fake("/search", 200, BAN_HOUSE, Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(Some(&ban), None)));
    let body = gql(
        &app,
        SEARCH,
        json!({"t": "20 avenue de segur 75007 paris", "near": {"lat": 48.8513, "lon": 2.3089}}),
    )
    .await;
    let answer = &body["data"]["searchAll"];
    assert_eq!(answer["addressesComplete"], true, "{body}");
    let first = &answer["addresses"][0];
    assert_eq!(first["kind"], "HOUSE_NUMBER");
    assert_eq!(first["name"], "20 Avenue de Ségur");
    assert_eq!(first["city"], "Paris");
    assert_eq!(first["postcode"], "75007");
    assert_eq!(first["source"]["id"], "ban");
    assert_eq!(first["source"]["licence"], "Licence Ouverte 2.0");
    let sent = asked.lock().unwrap()[0].clone();
    assert_eq!(sent["q"], "20 avenue de segur 75007 paris");
    assert_eq!(sent["autocomplete"], "1");
    assert_eq!(
        sent["limit"], "10",
        "twice the five shown: a commune's homonyms come after the streets of its name"
    );
    assert_eq!(
        (sent["lat"].as_str(), sent["lon"].as_str()),
        ("48.85", "2.3"),
        "the geocoder gets the grid's node, never the point the app sent"
    );
}

const SEARCH_TOWNS: &str = "query($t: String!, $near: LatLonInput) {
  searchAll(text: $t, near: $near) {
    places { name address { city postcode } }
    towns { name postcode department countryCode placeCount lat lon }
    addresses { kind name postcode city countryCode lat lon source { id attribution licence } }
    addressesComplete
  }
}";

#[sqlx::test(migrations = "../../migrations")]
async fn the_towns_count_every_place_wherever_the_map_looks(pool: PgPool) {
    seeded(&pool).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));
    let in_town: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM places WHERE deleted_at IS NULL AND city = 'Mimizan'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(in_town > 0, "the fixtures hold places in Mimizan");
    let mut counts = Vec::new();
    for near in [
        json!({"lat": 44.2, "lon": -1.2}),
        json!({"lat": 48.85, "lon": 2.35}),
        Value::Null,
    ] {
        let body = gql(&app, SEARCH_TOWNS, json!({"t": "Mimizan", "near": near})).await;
        let towns = &body["data"]["searchAll"]["towns"];
        let mimizan = towns
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["name"] == "Mimizan")
            .unwrap_or_else(|| panic!("Mimizan among the towns: {body}"));
        assert_eq!(mimizan["countryCode"], "FR");
        counts.push(mimizan["placeCount"].as_i64().unwrap());
    }
    assert_eq!(
        counts, [in_town; 3],
        "every live place of the town, from Mimizan, from Paris or from nowhere"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_town_the_search_lists_is_not_an_address_again(pool: PgPool) {
    seeded(&pool).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));
    // The places and the towns of "mimizan", without addresses.
    let plain = gql(&app, SEARCH_TOWNS, json!({"t": "mimizan"})).await;
    let places = &plain["data"]["searchAll"]["places"];
    let town = plain["data"]["searchAll"]["towns"]
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["name"] == "Mimizan")
        .expect("Mimizan is a town of the search")
        .clone();
    let postcode = town["postcode"].as_str().unwrap_or("40200");
    let ban_body = json!({"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": {"type": "Point", "coordinates": [-1.2290, 44.2003]},
         "properties": {"type": "municipality", "name": "Mimizan", "postcode": postcode,
                        "city": "Mimizan", "score": 0.95}},
        {"type": "Feature", "geometry": {"type": "Point", "coordinates": [-0.5, 44.8]},
         "properties": {"type": "street", "name": "Avenue de Mimizan", "postcode": "33000",
                        "city": "Bordeaux", "score": 0.80}}
    ]})
    .to_string();
    let (ban, _) = fake("/search", 200, ban_body.as_bytes(), Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(Some(&ban), None)));
    let body = gql(&app, SEARCH_TOWNS, json!({"t": "mimizan"})).await;
    let answer = &body["data"]["searchAll"];
    assert_eq!(
        answer["places"], *places,
        "the places are those of the search without addresses"
    );
    assert_eq!(
        names(&answer["addresses"]),
        ["Avenue de Mimizan"],
        "Mimizan is among the towns listed already"
    );
    let alone = gql(
        &app,
        "{ searchAll(text: \"mimizan\") { addresses { name } addressesComplete } }",
        json!({}),
    )
    .await;
    assert_eq!(
        names(&alone["data"]["searchAll"]["addresses"]),
        ["Mimizan", "Avenue de Mimizan"],
        "without towns asked, no town is listed nor left out: the device \
         leaves out its own"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn photon_answers_outside_france_and_the_nearest_answer_leads(pool: PgPool) {
    let (ban, _) = fake("/search", 200, BAN_HOUSE, Duration::ZERO).await;
    let (photon, asked) = fake("/api", 200, PHOTON_MIXED, Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(Some(&ban), Some(&photon))));
    let body = gql(
        &app,
        SEARCH,
        json!({"t": "rue", "near": {"lat": 40.4, "lon": -3.7}}),
    )
    .await;
    let addresses = &body["data"]["searchAll"]["addresses"];
    assert_eq!(names(addresses).len(), 5, "five by default");
    assert_eq!(
        names(addresses),
        [
            "Calle Mayor 5",
            "20 Avenue de Ségur",
            "12 Rue Neuve",
            "Hauptstraße",
            "Chefchaouen",
        ],
        "the text names no town: Photon's match in Madrid first, then the \
         BAN's in Paris, nearer than Brussels, then Photon's in its own order; \
         France from the BAN only, the French match of Photon left out"
    );
    let madrid = &addresses[0];
    assert_eq!(madrid["source"]["id"], "osm");
    assert_eq!(
        madrid["source"]["attribution"],
        "© OpenStreetMap contributors"
    );
    assert_eq!(madrid["countryCode"], "ES");
    let sent = asked.lock().unwrap()[0].clone();
    assert_eq!(sent["limit"], "15", "room for the French matches dropped");
    assert!(!sent.contains_key("lang"), "no language asked, local names");
    let named = "{ searchAll(text: \"calle mayor\", language: \"FR\") { addressesComplete } }";
    gql(&app, named, json!({})).await;
    let other = "{ searchAll(text: \"calle mayor\", language: \"es\") { addressesComplete } }";
    gql(&app, other, json!({})).await;
    let asked = asked.lock().unwrap();
    assert_eq!(asked[1].get("lang").map(String::as_str), Some("fr"));
    assert_eq!(
        asked[2].get("lang"),
        None,
        "a language the database has no names in gets the local names"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_late_geocoder_leaves_the_places_on_time(pool: PgPool) {
    seeded(&pool).await;
    let (ban, _) = fake("/search", 200, BAN_HOUSE, Duration::from_secs(5)).await;
    let app = lunaway_api::router(ApiState::new(pool, config(Some(&ban), None)));
    let started = std::time::Instant::now();
    let body = gql(&app, SEARCH, json!({"t": "camping du lac"})).await;
    assert!(
        started.elapsed() < Duration::from_secs(2),
        "the geocoder's 400 ms bound holds, not its 5 s"
    );
    let answer = &body["data"]["searchAll"];
    assert!(!answer["places"].as_array().unwrap().is_empty());
    assert_eq!(answer["addresses"], json!([]));
    assert_eq!(answer["addressesComplete"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_request_asks_the_geocoders_once_and_a_429_pauses_them(pool: PgPool) {
    let (ban, asked) = fake("/search", 429, b"{}", Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool, config(Some(&ban), None)));
    let two = "{ a: searchAll(text: \"vaux\") { addressesComplete } \
                 b: searchAll(text: \"melun\") { addressesComplete } }";
    let body = gql(&app, two, json!({})).await;
    assert_eq!(body["data"]["a"]["addressesComplete"], false);
    assert_eq!(body["data"]["b"]["addressesComplete"], false);
    assert_eq!(
        asked.lock().unwrap().len(),
        1,
        "one geocoder call per request"
    );
    let again = gql(&app, SEARCH, json!({"t": "vaux"})).await;
    assert_eq!(again["data"]["searchAll"]["addressesComplete"], false);
    assert_eq!(
        asked.lock().unwrap().len(),
        1,
        "the 429's Retry-After holds every search off the Géoplateforme"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_short_text_or_no_geocoder_asks_nothing_and_is_complete(pool: PgPool) {
    let (ban, asked) = fake("/search", 200, BAN_HOUSE, Duration::ZERO).await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(&ban), None)));
    let short = gql(&app, SEARCH, json!({"t": "va"})).await;
    assert_eq!(short["data"]["searchAll"]["addressesComplete"], true);
    assert!(
        asked.lock().unwrap().is_empty(),
        "the BAN refuses fewer than 3 characters"
    );
    let off = lunaway_api::router(ApiState::new(pool, ApiConfig::default()));
    let body = gql(&off, SEARCH, json!({"t": "avenue de segur"})).await;
    assert_eq!(body["data"]["searchAll"]["addresses"], json!([]));
    assert_eq!(body["data"]["searchAll"]["addressesComplete"], true);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_client_past_its_quota_gets_its_places_without_asking_the_geocoders(pool: PgPool) {
    seeded(&pool).await;
    let (ban, asked) = fake("/search", 200, BAN_HOUSE, Duration::ZERO).await;
    let mut config = config(Some(&ban), None);
    config.quotas.geocode = lunaway_api::config::Quota {
        count: 1,
        period: Duration::from_secs(3_600),
    };
    let app = lunaway_api::router(ApiState::new(pool, config));
    let short = gql(&app, SEARCH, json!({"t": "ca"})).await;
    assert_eq!(short["data"]["searchAll"]["addressesComplete"], true);
    let first = gql(&app, SEARCH, json!({"t": "camping du lac"})).await;
    assert_eq!(
        first["data"]["searchAll"]["addressesComplete"], true,
        "two letters asked no geocoder and cost nothing"
    );
    let second = gql(&app, SEARCH, json!({"t": "camping du lac"})).await;
    let answer = &second["data"]["searchAll"];
    assert!(
        !answer["places"].as_array().unwrap().is_empty(),
        "the places come whatever the quota"
    );
    assert_eq!(answer["addresses"], json!([]));
    assert_eq!(answer["addressesComplete"], false, "{second}");
    assert_eq!(
        asked.lock().unwrap().len(),
        1,
        "the spent quota spares the BAN"
    );
}
