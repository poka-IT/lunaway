//! The router answers over HTTP the way a client sees it, on a database
//! filled by the real pipeline: the recorded OSM and Atout France payloads,
//! stored and conflated.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
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

/// Pays de la Loire, roughly: holds every fixture place but the two in the
/// Landes.
fn pdl() -> Value {
    json!({"south": 46.8, "west": -2.7, "north": 48.0, "east": 0.0})
}

fn app(pool: PgPool, config: ApiConfig) -> axum::Router {
    lunaway_api::router(ApiState::new(pool, config))
}

/// A pool that never connects, for the fields that need no database.
fn no_db() -> PgPool {
    sqlx::postgres::PgPoolOptions::new()
        .connect_lazy("postgres://nobody@127.0.0.1:1/none")
        .unwrap()
}

async fn gql(app: &axum::Router, query: &str, variables: Value) -> Value {
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

fn error_code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or_else(|| panic!("no error code in {body}"))
}

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
}

#[tokio::test]
async fn health_answers_ok() {
    let response = app(no_db(), ApiConfig::default())
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .as_ref(),
        b"ok"
    );
}

#[tokio::test]
async fn version_taxonomy_and_config_need_no_database() {
    let body = gql(
        &app(no_db(), ApiConfig::default()),
        "{ apiVersion placeKinds config { minAppVersion } }",
        json!({}),
    )
    .await;
    assert_eq!(body["data"]["apiVersion"], env!("CARGO_PKG_VERSION"));
    let kinds = body["data"]["placeKinds"].as_array().unwrap();
    assert_eq!(
        kinds.len(),
        lunaway_domain::PlaceKind::ALL.len(),
        "the API must expose every kind the domain knows"
    );
    assert_eq!(body["data"]["config"], json!({"minAppVersion": "0.1.0"}));

    let newer = ApiConfig {
        min_app_version: "1.0.0".into(),
        ..ApiConfig::default()
    };
    let body = gql(
        &app(no_db(), newer),
        "{ config { minAppVersion } }",
        json!({}),
    )
    .await;
    assert_eq!(body["data"]["config"], json!({"minAppVersion": "1.0.0"}));

    let gone = gql(
        &app(no_db(), ApiConfig::default()),
        "{ config { deviceOverlay } }",
        json!({}),
    )
    .await;
    assert_eq!(
        error_code(&gone),
        "INVALID_INPUT",
        "the overlay switch of a dropped feature is gone from the contract"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_sources_carry_their_terms(pool: PgPool) {
    let body = gql(
        &app(pool, ApiConfig::default()),
        "{ sources { id name licence attribution url } }",
        json!({}),
    )
    .await;
    let sources = body["data"]["sources"].as_array().unwrap();
    let ids: Vec<&str> = sources.iter().map(|s| s["id"].as_str().unwrap()).collect();
    assert_eq!(
        ids,
        [
            "atout-france",
            "cat-sct-radars",
            "community",
            "community-cc-by",
            "finess",
            "laposte",
            "lu-pch-radars",
            "no-nvdb-atk",
            "osm",
            "pl-canard",
            "prix-carburants",
            "securite-routiere"
        ]
    );
    let of = |id: &str| &sources[ids.iter().position(|i| *i == id).unwrap()];
    assert_eq!(of("osm")["attribution"], "© OpenStreetMap contributors");
    assert_eq!(
        of("community")["licence"],
        "ODbL 1.0",
        "places added by users join the ODbL database"
    );
    assert_eq!(
        (
            &of("community-cc-by")["licence"],
            &of("community-cc-by")["attribution"]
        ),
        (&json!("CC BY 4.0"), &json!("Lunaway contributors")),
        "reviews and photos are published under CC BY 4.0, outside the database"
    );
    assert_eq!(
        of("laposte")["licence"],
        "ODbL 1.0",
        "La Poste's calendar is under the same licence as the database"
    );
    assert_eq!(
        of("securite-routiere")["attribution"],
        "Sécurité routière, radars.securite-routiere.gouv.fr",
        "the CRPA asks for the source of the French list to be cited"
    );
}

const CHANGES: &str = r"
query($bbox: BBoxInput!, $since: String, $first: Int) {
  changes(bbox: $bbox, since: $since, first: $first) {
    places { id name kind }
    deleted
    cursor
    hasMore
  }
}";

#[sqlx::test(migrations = "../../migrations")]
async fn a_region_syncs_page_by_page_and_then_receives_deletions(pool: PgPool) {
    seeded(&pool).await;
    let app = app(pool.clone(), ApiConfig::default());

    let mut seen = Vec::new();
    let mut since = Value::Null;
    let mut pages = Vec::new();
    loop {
        let body = gql(
            &app,
            CHANGES,
            json!({"bbox": pdl(), "since": since, "first": 10}),
        )
        .await;
        let set = &body["data"]["changes"];
        assert_eq!(set["deleted"], json!([]), "a first sync deletes nothing");
        let places = set["places"].as_array().unwrap();
        pages.push(places.len());
        seen.extend(places.iter().map(|p| p["id"].as_str().unwrap().to_owned()));
        since = set["cursor"].clone();
        if !set["hasMore"].as_bool().unwrap() {
            break;
        }
    }
    assert_eq!(
        pages,
        [10, 10, 1],
        "21 places in the region, the two in the Landes are outside"
    );
    let mut unique = seen.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(unique.len(), seen.len(), "no place is sent twice");

    let idle = gql(
        &app,
        CHANGES,
        json!({"bbox": pdl(), "since": since, "first": 10}),
    )
    .await;
    assert_eq!(idle["data"]["changes"]["places"], json!([]));
    assert_eq!(
        idle["data"]["changes"]["cursor"], since,
        "nothing new, the cursor stays"
    );
    assert_eq!(idle["data"]["changes"]["hasMore"], false);

    // The source drops a motorhome area: the next sync reports its deletion.
    let at = Utc.with_ymd_and_hms(2026, 10, 7, 0, 0, 0).unwrap();
    let records: Vec<_> = osm::parse(OVERPASS, at)
        .unwrap()
        .records
        .into_iter()
        .filter(|r| r.external_id != "way/347935372")
        .collect();
    store_complete(&pool, &SourceId::OSM, Some("FR-PDL"), &records)
        .await
        .unwrap();
    lunaway_conflate::run(
        &pool,
        Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap(),
        None,
    )
    .await
    .unwrap();
    let after = gql(&app, CHANGES, json!({"bbox": pdl(), "since": since})).await;
    let deleted = after["data"]["changes"]["deleted"].as_array().unwrap();
    assert_eq!(deleted.len(), 1);
    assert!(seen.contains(&deleted[0].as_str().unwrap().to_owned()));
}

#[sqlx::test(migrations = "../../migrations")]
async fn oversized_or_malformed_requests_are_refused_with_a_code(pool: PgPool) {
    let app = app(pool, ApiConfig::default());
    let too_many = gql(&app, CHANGES, json!({"bbox": pdl(), "first": 1001})).await;
    assert_eq!(error_code(&too_many), "INVALID_INPUT");
    let world = json!({"south": -80.0, "west": -170.0, "north": 80.0, "east": 170.0});
    assert_eq!(
        error_code(&gql(&app, CHANGES, json!({"bbox": world})).await),
        "INVALID_INPUT"
    );
    let forged = gql(&app, CHANGES, json!({"bbox": pdl(), "since": "c1.-4"})).await;
    assert_eq!(error_code(&forged), "INVALID_INPUT");
    let forged = gql(&app, CHANGES, json!({"bbox": pdl(), "since": "c2.x.4"})).await;
    assert_eq!(error_code(&forged), "INVALID_INPUT");

    let places = "query($bbox: BBoxInput!, $first: Int, $after: String) { places(bbox: $bbox, first: $first, after: $after) { totalCount } }";
    let big_page = gql(&app, places, json!({"bbox": pdl(), "first": 501})).await;
    assert_eq!(error_code(&big_page), "INVALID_INPUT");
    let wide = json!({"south": 42.0, "west": -5.0, "north": 51.0, "east": 8.0});
    let wide_body = gql(&app, places, json!({"bbox": wide})).await;
    assert_eq!(
        error_code(&wide_body),
        "INVALID_INPUT",
        "a whole-country viewport goes through changes"
    );
    let inverted = json!({"south": 48.0, "west": -2.7, "north": 46.8, "east": 0.0});
    assert_eq!(
        error_code(&gql(&app, places, json!({"bbox": inverted})).await),
        "INVALID_INPUT"
    );
    assert_eq!(
        error_code(
            &gql(
                &app,
                places,
                json!({"bbox": pdl(), "after": "not-a-cursor"})
            )
            .await
        ),
        "INVALID_INPUT"
    );
    let search = "query($t: String!) { search(text: $t) { id } }";
    assert_eq!(
        error_code(&gql(&app, search, json!({"t": "a"})).await),
        "INVALID_INPUT"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_viewport_filters_and_pages(pool: PgPool) {
    seeded(&pool).await;
    let app = app(pool, ApiConfig::default());
    let q = r"
    query($bbox: BBoxInput!, $filter: PlaceFilter, $first: Int, $after: String) {
      places(bbox: $bbox, filter: $filter, first: $first, after: $after) {
        nodes { id kind overnight services maxHeightM }
        endCursor hasNextPage totalCount
      }
    }";
    let all = gql(&app, q, json!({"bbox": pdl(), "first": 15})).await;
    let conn = &all["data"]["places"];
    assert_eq!(conn["totalCount"], 21);
    assert_eq!(conn["nodes"].as_array().unwrap().len(), 15);
    assert_eq!(conn["hasNextPage"], true);
    let next = gql(
        &app,
        q,
        json!({"bbox": pdl(), "first": 15, "after": conn["endCursor"]}),
    )
    .await;
    assert_eq!(next["data"]["places"]["nodes"].as_array().unwrap().len(), 6);
    assert_eq!(next["data"]["places"]["hasNextPage"], false);

    let filtered = gql(
        &app,
        q,
        json!({"bbox": pdl(), "filter": {"kinds": ["MOTORHOME_AREA"], "services": ["ELECTRICITY"], "overnightOk": true}}),
    )
    .await;
    let nodes = filtered["data"]["places"]["nodes"].as_array().unwrap();
    assert!(!nodes.is_empty());
    for n in nodes {
        assert_eq!(n["kind"], "MOTORHOME_AREA");
        assert!(
            n["services"]
                .as_array()
                .unwrap()
                .contains(&json!("ELECTRICITY"))
        );
        assert!(n["overnight"] == "ALLOWED" || n["overnight"] == "TOLERATED");
    }
    assert_eq!(filtered["data"]["places"]["totalCount"], nodes.len());
}

const PLACE: &str = r"
query($id: UUID!) {
  place(id: $id) {
    id name kind lat lon overnight services
    address { street postcode city countryCode }
    capacity stars openingHours openingHoursParsed openingIntervals { start end } openingIntervalsUntil
    sources { source { id name licence attribution url } externalId externalUrl fetchedAt matchScore }
    provenance { field sourceId alternatives { sourceId value } }
  }
}";

#[sqlx::test(migrations = "../../migrations")]
async fn a_merged_place_shows_both_sources_and_where_each_field_comes_from(pool: PgPool) {
    seeded(&pool).await;
    let id: uuid::Uuid = sqlx::query_scalar!(
        r"SELECT ps.place_id FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
           WHERE r.source_id = 'osm' AND r.external_id = 'way/207901408'"
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let app = app(pool, ApiConfig::default());
    let body = gql(&app, PLACE, json!({"id": id})).await;
    let place = &body["data"]["place"];
    assert_eq!(place["name"], "Camping municipal du Port");
    assert_eq!(place["kind"], "CAMPSITE");
    assert_eq!(place["capacity"], 30);
    assert_eq!(place["stars"], 1, "Atout France's classification");
    assert_eq!(place["openingIntervalsUntil"], Value::Null);
    assert_eq!(place["address"]["city"], "La Possonnière");
    assert_eq!(place["openingHoursParsed"], false);
    assert_eq!(
        place["openingIntervals"],
        Value::Null,
        "no opening hours, no intervals"
    );

    let sources = place["sources"].as_array().unwrap();
    let ids: Vec<&str> = sources
        .iter()
        .map(|s| s["source"]["id"].as_str().unwrap())
        .collect();
    assert_eq!(ids, ["atout-france", "osm"]);
    let osm = &sources[1];
    assert_eq!(osm["externalId"], "way/207901408");
    assert_eq!(
        osm["externalUrl"],
        "https://www.openstreetmap.org/way/207901408"
    );
    assert_eq!(osm["source"]["licence"], "ODbL 1.0");
    assert!(
        osm["fetchedAt"]
            .as_str()
            .unwrap()
            .starts_with("2026-10-05T22:00:00")
    );
    assert!(osm["matchScore"].as_f64().unwrap() >= 0.85);

    let provenance = place["provenance"].as_array().unwrap();
    let field = |f: &str| provenance.iter().find(|p| p["field"] == f).unwrap();
    assert_eq!(field("capacity")["sourceId"], "atout-france");
    assert_eq!(field("position")["sourceId"], "osm");
    assert_eq!(
        field("name")["alternatives"][0]["value"],
        "Camping Municipal du Port"
    );

    let missing = gql(&app, PLACE, json!({"id": uuid::Uuid::now_v7()})).await;
    assert_eq!(missing["data"]["place"], Value::Null);
}

#[sqlx::test(migrations = "../../migrations")]
async fn search_folds_accents_and_forgives_a_typo(pool: PgPool) {
    seeded(&pool).await;
    let app = app(pool, ApiConfig::default());
    let q = "query($t: String!, $near: LatLonInput) { search(text: $t, near: $near) { name address { city } } }";
    let names = |body: &Value| -> Vec<String> {
        body["data"]["search"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["name"].as_str().unwrap_or_default().to_owned())
            .collect()
    };
    let etang = gql(&app, q, json!({"t": "ETANG"})).await;
    assert_eq!(
        names(&etang)[0],
        "Camping de l'Étang",
        "accents and case fold"
    );
    let typo = gql(&app, q, json!({"t": "possoniere"})).await;
    assert_eq!(
        names(&typo)[0],
        "Camping municipal du Port",
        "one letter missing from La Possonnière still finds its campsite"
    );
    let near = gql(
        &app,
        q,
        json!({"t": "camping du lac", "near": {"lat": 44.30, "lon": -1.18}}),
    )
    .await;
    let cities: Vec<&str> = near["data"]["search"]
        .as_array()
        .unwrap()
        .iter()
        .take(2)
        .map(|p| p["address"]["city"].as_str().unwrap())
        .collect();
    assert_eq!(
        cities,
        ["Sainte-Eulalie-en-Born", "Mimizan"],
        "the nearer one first"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_full_sync_page_fits_the_budget_and_two_do_not(pool: PgPool) {
    let full = r"
      changes(bbox: $bbox, first: 1000) {
        places {
          id name kind lat lon overnight services activities description
          address { street postcode city countryCode }
          priceParkingEur priceServicesEur maxHeightM capacity stars openingHours openingHoursParsed
          openingIntervals { start end } openingIntervalsUntil
          website phone lastConfirmedAt updatedAt
          sources { source { id name licence attribution url } externalId externalUrl fetchedAt matchScore }
          provenance { field sourceId alternatives { sourceId value } }
        }
        deleted cursor hasMore
      }";
    let app = app(pool, ApiConfig::default());
    let one = gql(
        &app,
        &format!("query($bbox: BBoxInput!) {{ {full} }}"),
        json!({"bbox": pdl()}),
    )
    .await;
    assert!(
        one.get("errors").is_none(),
        "the app's sync query must fit: {one}"
    );
    let two = gql(
        &app,
        &format!("query($bbox: BBoxInput!) {{ a: {full} b: {full} }}"),
        json!({"bbox": pdl()}),
    )
    .await;
    let message = two["errors"][0]["message"].as_str().unwrap_or_default();
    assert!(message.contains("too complex"), "unexpected answer: {two}");
    assert_eq!(error_code(&two), "INVALID_INPUT");
}

fn preflight(origin: &str) -> Request<Body> {
    Request::builder()
        .method("OPTIONS")
        .uri("/graphql")
        .header("origin", origin)
        .header("access-control-request-method", "POST")
        .header("access-control-request-headers", "content-type")
        .body(Body::empty())
        .unwrap()
}

#[tokio::test]
async fn browsers_may_call_from_the_site_and_from_local_pages_in_development() {
    let prod = app(no_db(), ApiConfig::default());
    let site = prod
        .clone()
        .oneshot(preflight("https://lunaway.net"))
        .await
        .unwrap();
    let h = site.headers();
    assert_eq!(h["access-control-allow-origin"], "https://lunaway.net");
    assert!(
        h["access-control-allow-methods"]
            .to_str()
            .unwrap()
            .contains("POST")
    );
    assert_eq!(h["access-control-max-age"], "86400");
    assert!(
        h.get("access-control-allow-credentials").is_none(),
        "no credentials"
    );

    for refused in [
        "https://evil.example",
        "https://lunaway.net.evil.example",
        "http://localhost:8080",
    ] {
        let r = prod.clone().oneshot(preflight(refused)).await.unwrap();
        assert!(
            r.headers().get("access-control-allow-origin").is_none(),
            "{refused} must not be allowed in production"
        );
    }

    let dev = app(
        no_db(),
        ApiConfig {
            dev_cors: true,
            ..ApiConfig::default()
        },
    );
    for allowed in [
        "http://localhost:8080",
        "http://127.0.0.1:5173",
        "http://localhost",
    ] {
        let r = dev.clone().oneshot(preflight(allowed)).await.unwrap();
        assert_eq!(r.headers()["access-control-allow-origin"], allowed);
    }
    let r = dev
        .clone()
        .oneshot(preflight("http://localhost.evil.example"))
        .await
        .unwrap();
    assert!(r.headers().get("access-control-allow-origin").is_none());
}

#[tokio::test]
async fn responses_are_compressed_for_clients_that_accept_it() {
    let app = app(no_db(), ApiConfig::default());
    let query = || {
        Request::post("/graphql")
            .header("content-type", "application/json")
            .body(Body::from(r#"{"query":"{ placeKinds }"}"#))
            .unwrap()
    };
    let mut gz = query();
    gz.headers_mut()
        .insert("accept-encoding", "gzip".parse().unwrap());
    let compressed = app.clone().oneshot(gz).await.unwrap();
    assert_eq!(compressed.headers()["content-encoding"], "gzip");
    let plain = app.oneshot(query()).await.unwrap();
    assert!(plain.headers().get("content-encoding").is_none());
}

#[tokio::test]
async fn introspection_is_served_and_bounded_like_any_query() {
    let app = app(no_db(), ApiConfig::default());
    let shallow = gql(&app, "{ __schema { queryType { name } } }", json!({})).await;
    assert_eq!(shallow["data"]["__schema"]["queryType"]["name"], "Query");
    // `ofType` nests without end; 14 levels exceed the depth limit of 12.
    let mut deep = String::from("name");
    for _ in 0..12 {
        deep = format!("ofType {{ {deep} }}");
    }
    let q = format!("{{ __schema {{ types {{ fields {{ type {{ {deep} }} }} }} }} }}");
    let body = gql(&app, &q, json!({})).await;
    let message = body["errors"][0]["message"].as_str().unwrap_or_default();
    assert!(
        message.contains("nested too deep"),
        "unexpected answer: {body}"
    );
}

/// What a client gets back from a raw request: status, headers, JSON body
/// (null when the body is not JSON).
async fn send(
    app: &axum::Router,
    request: Request<Body>,
) -> (StatusCode, axum::http::HeaderMap, Value) {
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let headers = response.headers().clone();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        headers,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

fn post(content_type: &str, body: impl Into<Body>) -> Request<Body> {
    Request::post("/graphql")
        .header("content-type", content_type)
        .body(body.into())
        .unwrap()
}

#[tokio::test]
async fn a_batch_is_refused_whole() {
    let app = app(no_db(), ApiConfig::default());
    let batch = json!([{"query": "{ apiVersion }"}, {"query": "{ apiVersion }"}]).to_string();
    let (status, _, body) = send(&app, post("application/json", batch)).await;
    assert_eq!(
        status,
        StatusCode::BAD_REQUEST,
        "every entry of a batch got its own budget and ran in parallel"
    );
    assert_eq!(error_code(&body), "INVALID_INPUT");
    assert_eq!(body["data"], Value::Null);
}

#[tokio::test]
async fn an_oversized_body_is_refused_before_it_is_read() {
    let app = app(no_db(), ApiConfig::default());
    let padding = " ".repeat(70 * 1024);
    let big = format!(r#"{{"query": "{{ apiVersion }}"{padding}}}"#);
    let (status, _, body) = send(&app, post("application/json", big.clone())).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        error_code(&body),
        "INVALID_INPUT",
        "a JSON error like any other"
    );
    // Announced: refused on the header alone, the body never read.
    let announced = Request::post("/graphql")
        .header("content-type", "application/json")
        .header("content-length", big.len())
        .body(Body::from(big))
        .unwrap();
    let (status, _, body) = send(&app, announced).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(error_code(&body), "INVALID_INPUT");
}

#[tokio::test]
async fn only_json_posts_are_served() {
    let app = app(no_db(), ApiConfig::default());
    let get = Request::get("/graphql?query=%7BapiVersion%7D")
        .body(Body::empty())
        .unwrap();
    assert_eq!(
        send(&app, get).await.0,
        StatusCode::METHOD_NOT_ALLOWED,
        "a GET puts the query, positions included, in URLs that end up in logs"
    );
    let multipart = post(
        "multipart/form-data; boundary=x",
        "--x\r\nContent-Disposition: form-data; name=\"operations\"\r\n\r\n{}\r\n--x--\r\n",
    );
    let (status, _, body) = send(&app, multipart).await;
    assert_eq!(
        status,
        StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "no upload is ever accepted"
    );
    assert_eq!(error_code(&body), "INVALID_INPUT");
    assert_eq!(
        send(&app, post("text/plain", r#"{"query":"{ apiVersion }"}"#))
            .await
            .0,
        StatusCode::UNSUPPORTED_MEDIA_TYPE
    );
    let (status, _, body) = send(
        &app,
        post(
            "application/json; charset=utf-8",
            r#"{"query":"{ apiVersion }"}"#,
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["data"]["apiVersion"], env!("CARGO_PKG_VERSION"));
}

#[tokio::test]
async fn a_malformed_body_is_refused_without_the_parser_s_words() {
    let app = app(no_db(), ApiConfig::default());
    for raw in [
        r#"{"query": 12"#,
        r#"{"query": 12}"#,
        "not json",
        r#"{"variables": {}}"#,
    ] {
        let (status, _, body) = send(&app, post("application/json", raw)).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{raw}");
        assert_eq!(error_code(&body), "INVALID_INPUT");
        let message = body["errors"][0]["message"].as_str().unwrap();
        for leak in ["line", "column", "EOF", "invalid type", "expected"] {
            assert!(
                !message.contains(leak),
                "{raw:?} answered with the parser's own message: {message}"
            );
        }
    }
}

fn fan_out(levels: usize) -> String {
    let mut q = String::from("query { ...F0 }\n");
    for i in 0..levels {
        q.push_str(&format!(
            "fragment F{i} on Query {{ ...F{} ...F{} }}\n",
            i + 1,
            i + 1
        ));
    }
    q.push_str(&format!("fragment F{levels} on Query {{ apiVersion }}"));
    q
}

#[tokio::test]
async fn fragments_spread_into_billions_of_fields_are_refused_at_once() {
    let app = app(no_db(), ApiConfig::default());
    // 30 levels: 2^30 fields from 1.2 KB. Refusing it took async-graphql
    // about ten minutes of one core.
    let started = std::time::Instant::now();
    let body = gql(&app, &fan_out(30), json!({})).await;
    assert!(
        started.elapsed() < std::time::Duration::from_secs(1),
        "{:?}",
        started.elapsed()
    );
    assert_eq!(error_code(&body), "INVALID_INPUT");
    let message = body["errors"][0]["message"].as_str().unwrap();
    assert!(message.contains("fields"), "{message}");
}

#[tokio::test]
async fn a_deeply_nested_document_is_refused_without_parsing_it() {
    let app = app(no_db(), ApiConfig::default());
    // 5 000 levels in 15 KB overflowed the parser's stack and aborted the
    // whole process.
    let n = 5_000;
    let q = format!("{{{}b{}}}", "a{".repeat(n), "}".repeat(n));
    assert!(q.len() < 16 * 1024);
    let body = gql(&app, &q, json!({})).await;
    assert_eq!(error_code(&body), "INVALID_INPUT");
    assert!(
        gql(&app, "{ apiVersion }", json!({})).await["data"]["apiVersion"].is_string(),
        "the server is still up"
    );
}

#[tokio::test]
async fn aliases_of_database_fields_cost_a_share_of_the_budget_each() {
    let app = app(no_db(), ApiConfig::default());
    // Each database field costs 2000 whatever it returns: 30 searches of one
    // result no longer fit in a request.
    let aliases = (0..30)
        .map(|i| format!(r#"s{i}: search(text: "la", first: 1) {{ id }}"#))
        .collect::<Vec<_>>()
        .join(" ");
    let body = gql(&app, &format!("{{ {aliases} }}"), json!({})).await;
    let message = body["errors"][0]["message"].as_str().unwrap_or_default();
    assert!(message.contains("too complex"), "{body}");
    // The review's 3 000 aliases held the pool for 10 s; their 135 KB no
    // longer reach the GraphQL layer.
    let many = (0..3_000)
        .map(|i| format!(r#"s{i}: search(text: "la", first: 1) {{ id }}"#))
        .collect::<Vec<_>>()
        .join(" ");
    let body = json!({ "query": format!("{{ {many} }}") }).to_string();
    assert_eq!(
        send(&app, post("application/json", body)).await.0,
        StatusCode::PAYLOAD_TOO_LARGE
    );
    // Within the size limits, a document of 1 100 cheap fields is refused
    // by its count of selections.
    let cheap = (0..1_100)
        .map(|i| format!("a{i}: apiVersion"))
        .collect::<Vec<_>>()
        .join(" ");
    let body = gql(&app, &format!("{{ {cheap} }}"), json!({})).await;
    assert_eq!(error_code(&body), "INVALID_INPUT");
}

/// A router whose requests come from `peer`, as through the listener.
fn app_from(pool: PgPool, config: ApiConfig, peer: &str) -> axum::Router {
    app(pool, config).layer(axum::extract::connect_info::MockConnectInfo(
        peer.parse::<std::net::SocketAddr>().unwrap(),
    ))
}

fn as_client(query: &str, forwarded_for: Option<&str>) -> Request<Body> {
    let mut r = post("application/json", json!({ "query": query }).to_string());
    if let Some(ip) = forwarded_for {
        r.headers_mut()
            .insert("x-forwarded-for", ip.parse().unwrap());
    }
    r
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_client_over_its_budget_waits_and_the_others_do_not(pool: PgPool) {
    let config = ApiConfig {
        limits: lunaway_api::Limits {
            rate_burst: 30_000,
            rate_per_second: 1,
            ..lunaway_api::Limits::default()
        },
        ..ApiConfig::default()
    };
    // Behind Caddy: the peer is loopback and the header names the client.
    let app = app_from(pool, config, "127.0.0.1:40000");
    // 1 000 to start, 5 000 for the database, 1 for the field: four fit in
    // 30 000, a fifth does not.
    let q = "{ sources { id } }";
    let mut statuses = Vec::new();
    for _ in 0..5 {
        statuses.push(send(&app, as_client(q, Some("203.0.113.9"))).await.0);
    }
    assert_eq!(statuses[..4], [StatusCode::OK; 4]);
    let (status, headers, body) = send(&app, as_client(q, Some("203.0.113.9"))).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "{body}");
    assert_eq!(error_code(&body), "RATE_LIMITED");
    let wait: u64 = headers["retry-after"].to_str().unwrap().parse().unwrap();
    assert!(wait >= 1);
    assert_eq!(body["errors"][0]["extensions"]["retryAfterSeconds"], wait);
    assert_eq!(
        send(&app, as_client(q, Some("198.51.100.4"))).await.0,
        StatusCode::OK,
        "another client keeps its own budget"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_client_reaching_the_api_directly_cannot_choose_its_budget(pool: PgPool) {
    let config = ApiConfig {
        limits: lunaway_api::Limits {
            rate_burst: 15_000,
            rate_per_second: 1,
            ..lunaway_api::Limits::default()
        },
        ..ApiConfig::default()
    };
    let app = app_from(pool, config, "192.0.2.50:40000");
    let q = "{ sources { id } }";
    let mut last = StatusCode::OK;
    for i in 0..4 {
        // A new forged address each time: without the loopback check each
        // would get a fresh budget.
        last = send(&app, as_client(q, Some(&format!("10.0.0.{i}"))))
            .await
            .0;
    }
    assert_eq!(last, StatusCode::TOO_MANY_REQUESTS);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_saturated_server_answers_busy_and_a_stuck_request_times_out(pool: PgPool) {
    // A transaction holding `sources` makes every read of it wait.
    let mut blocker = pool.begin().await.unwrap();
    sqlx::query!("LOCK TABLE sources IN ACCESS EXCLUSIVE MODE")
        .execute(&mut *blocker)
        .await
        .unwrap();
    let config = ApiConfig {
        limits: lunaway_api::Limits {
            max_concurrent_requests: 1,
            queue_wait: std::time::Duration::from_millis(100),
            request_timeout: std::time::Duration::from_millis(800),
            ..lunaway_api::Limits::default()
        },
        ..ApiConfig::default()
    };
    let app = app(pool.clone(), config);
    let stuck = {
        let app = app.clone();
        tokio::spawn(async move { send(&app, as_client("{ sources { id } }", None)).await })
    };
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    let (status, headers, body) = send(&app, as_client("{ apiVersion }", None)).await;
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE, "{body}");
    assert_eq!(error_code(&body), "RATE_LIMITED");
    assert_eq!(headers["retry-after"], "1");
    let (status, _, body) = stuck.await.unwrap();
    assert_eq!(status, StatusCode::GATEWAY_TIMEOUT, "{body}");
    assert_eq!(error_code(&body), "INTERNAL");
    blocker.rollback().await.unwrap();
    assert_eq!(
        send(&app, as_client("{ apiVersion }", None)).await.0,
        StatusCode::OK,
        "the slot is free again"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_answer_over_its_size_limit_is_refused(pool: PgPool) {
    seeded(&pool).await;
    let config = ApiConfig {
        limits: lunaway_api::Limits {
            max_response_bytes: 2_000,
            ..lunaway_api::Limits::default()
        },
        ..ApiConfig::default()
    };
    let body = gql(&app(pool, config), CHANGES, json!({"bbox": pdl()})).await;
    assert_eq!(error_code(&body), "INVALID_INPUT");
    assert!(
        body["errors"][0]["message"]
            .as_str()
            .unwrap()
            .contains("smaller page")
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_cursor_from_before_a_restore_asks_for_a_full_sync(pool: PgPool) {
    seeded(&pool).await;
    let app = app(pool.clone(), ApiConfig::default());
    let first = gql(&app, CHANGES, json!({"bbox": pdl()})).await;
    let cursor = first["data"]["changes"]["cursor"].clone();
    let same = gql(&app, CHANGES, json!({"bbox": pdl(), "since": cursor})).await;
    assert!(same.get("errors").is_none(), "{same}");
    // The restore step of docs/deploy.md.
    sqlx::query!("UPDATE sync_epoch SET epoch = gen_random_uuid(), created_at = now()")
        .execute(&pool)
        .await
        .unwrap();
    let after = gql(&app, CHANGES, json!({"bbox": pdl(), "since": cursor})).await;
    assert_eq!(
        error_code(&after),
        "RESYNC",
        "a device ahead of the restored feed would otherwise miss changes"
    );
    let again = gql(&app, CHANGES, json!({"bbox": pdl()})).await;
    assert_eq!(
        again["data"]["changes"]["places"].as_array().unwrap().len(),
        21,
        "a full sync works at once"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_api_runs_with_the_read_only_role(pool: PgPool) {
    seeded(&pool).await;
    let app_role = sqlx::postgres::PgPoolOptions::new()
        .max_connections(4)
        .after_connect(|conn, _| {
            Box::pin(async move {
                sqlx::query("SET ROLE lunaway_app").execute(conn).await?;
                Ok(())
            })
        })
        .connect_with((*pool.connect_options()).clone())
        .await
        .unwrap();
    let app = app(app_role, ApiConfig::default());
    let body = gql(
        &app,
        r#"query($bbox: BBoxInput!) {
          sources { id }
          changes(bbox: $bbox, first: 5) { places { id sources { externalId } } cursor }
          places(bbox: $bbox, first: 5) { totalCount }
          search(text: "etang") { id }
        }"#,
        json!({"bbox": pdl()}),
    )
    .await;
    assert!(
        body.get("errors").is_none(),
        "every read of the API works with lunaway_app's grants: {body}"
    );
}

/// A writer the test reads back, for the log assertions.
#[derive(Clone, Default)]
struct Captured(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);

impl std::io::Write for Captured {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[tokio::test]
async fn request_logs_carry_the_path_never_the_query_string() {
    let captured = Captured::default();
    let writer = captured.clone();
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::TRACE)
        .with_writer(move || writer.clone())
        .with_ansi(false)
        .finish();
    let _guard = tracing::subscriber::set_default(subscriber);
    let app = app(no_db(), ApiConfig::default());
    let leaky = Request::get("/graphql?query=%7Bplaces(lat%3A47.4123)%7D&lat=47.4123")
        .body(Body::empty())
        .unwrap();
    let _ = send(&app, leaky).await;
    let logs = String::from_utf8(captured.0.lock().unwrap().clone()).unwrap();
    assert!(logs.contains("/graphql"), "the request is logged: {logs}");
    assert!(
        !logs.contains("47.4123") && !logs.contains("query="),
        "a position in a URL is personal data: {logs}"
    );
}

/// How many backends of this test's database wait on a lock.
async fn waiting_on_locks(pool: &PgPool) -> i64 {
    sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM pg_stat_activity
           WHERE datname = current_database() AND wait_event_type = 'Lock'"#
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_request_runs_its_database_fields_a_few_at_a_time(pool: PgPool) {
    let mut blocker = pool.begin().await.unwrap();
    sqlx::query!("LOCK TABLE sources IN ACCESS EXCLUSIVE MODE")
        .execute(&mut *blocker)
        .await
        .unwrap();
    let config = ApiConfig {
        limits: lunaway_api::Limits {
            db_queries_per_request: 1,
            ..lunaway_api::Limits::default()
        },
        ..ApiConfig::default()
    };
    let app = app(pool.clone(), config);
    let aliases = "{ a: sources { id } b: sources { id } c: sources { id } }";
    let request = {
        let app = app.clone();
        tokio::spawn(async move { send(&app, as_client(aliases, None)).await })
    };
    // The first alias reaches the lock whenever the machine gets to it;
    // from then on, a request that ran its fields at once would show the
    // other two waiting beside it within a few milliseconds.
    let reached = std::time::Instant::now();
    while waiting_on_locks(&pool).await == 0 {
        assert!(
            reached.elapsed() < std::time::Duration::from_secs(30),
            "the request reaches the database"
        );
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    assert_eq!(
        waiting_on_locks(&pool).await,
        1,
        "three aliases of a database field wait for each other, not for three connections"
    );
    blocker.rollback().await.unwrap();
    let (status, _, body) = request.await.unwrap();
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body["data"]["c"].as_array().unwrap().len(),
        12,
        "OpenStreetMap, Atout France, the community under its two licences, the three joined \
         to the points and the five camera lists"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_cost_running_at_once_is_bounded_across_clients(pool: PgPool) {
    let mut blocker = pool.begin().await.unwrap();
    sqlx::query!("LOCK TABLE sources IN ACCESS EXCLUSIVE MODE")
        .execute(&mut *blocker)
        .await
        .unwrap();
    let config = ApiConfig {
        limits: lunaway_api::Limits {
            // Room for one `sources` query (5 001) at a time.
            max_cost_in_flight: 8_000,
            queue_wait: std::time::Duration::from_millis(200),
            ..lunaway_api::Limits::default()
        },
        ..ApiConfig::default()
    };
    let app = app_from(pool.clone(), config, "127.0.0.1:40000");
    let q = "{ sources { id } }";
    let first = {
        let app = app.clone();
        tokio::spawn(async move { send(&app, as_client(q, Some("203.0.113.1"))).await })
    };
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    // Another client, with a full budget of its own.
    let (status, headers, body) = send(&app, as_client(q, Some("198.51.100.2"))).await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "{body}");
    assert_eq!(error_code(&body), "RATE_LIMITED");
    assert!(headers.contains_key("retry-after"));
    blocker.rollback().await.unwrap();
    assert_eq!(first.await.unwrap().0, StatusCode::OK);
    assert_eq!(
        send(&app, as_client(q, Some("198.51.100.2"))).await.0,
        StatusCode::OK,
        "the share is released when the request ends"
    );
}
