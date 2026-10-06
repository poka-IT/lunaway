//! `Query.enforcement`: each item in the only form its country allows,
//! checked again when served (a point in France or in Switzerland never
//! leaves the server, whatever a row says), the rules of every country, the
//! lists with their last read, and the changes since a cursor.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use axum::{
    Router,
    body::Body,
    http::{Request, StatusCode},
};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::{
    PgPool,
    enforcement::{self as db, Item, ItemKind},
};
use lunaway_domain::{Position, SourceId, routing::polyline};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const QUERY: &str = r"
query Enforcement($since: String, $countries: [String!]) {
  enforcement(since: $since, countries: $countries) {
    cursor full hasMore pollIntervalSeconds
    rules { version reviewedOn defaultMode
      countries { country mode zoneLengths { motorwayM ruralM urbanM } sources } }
    upserts { id kind category country line lat lon bearingDeg limitKmh sourceIds }
    removals
    sources { id licence attribution fetchedAt cameras }
  }
}";

async fn gql(app: &Router, variables: Value) -> (StatusCode, Value) {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": QUERY, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

fn p(lat: f64, lon: f64) -> Position {
    Position::new(lat, lon).unwrap()
}

fn item(key: &str, kind: ItemKind, category: &str, country: &str) -> Item {
    Item {
        id: Uuid::now_v7(),
        device_key: key.to_owned(),
        kind,
        category: category.to_owned(),
        country: country.to_owned(),
        line: None,
        point: None,
        bearing_deg: None,
        limit_kmh: None,
        source_ids: vec!["osm".to_owned()],
        content_hash: key.to_owned(),
    }
}

fn zone(key: &str, country: &str, line: Vec<Position>) -> Item {
    Item {
        line: Some(line),
        source_ids: vec!["securite-routiere".to_owned(), "osm".to_owned()],
        ..item(key, ItemKind::Zone, "fixed", country)
    }
}

fn camera(key: &str, country: &str, at: Position) -> Item {
    Item {
        point: Some(at),
        bearing_deg: Some(271.04),
        limit_kmh: Some(90),
        ..item(key, ItemKind::Camera, "section", country)
    }
}

fn ids(list: &Value) -> Vec<String> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|v| {
            v.as_str()
                .map_or_else(|| v["id"].as_str().unwrap().to_owned(), str::to_owned)
        })
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn each_item_is_served_in_the_form_its_country_allows(pool: PgPool) {
    let french_line = vec![p(45.83, 1.26), p(45.835, 1.27), p(45.84, 1.28)];
    let french = zone("securite-routiere/60004", "FR", french_line.clone());
    let madrid = camera("osm/node/1", "ES", p(40.4168, -3.7038));
    // Rows no build writes, as a bug or an older rule could leave them.
    let french_point = camera("osm/node/2", "FR", p(48.85, 2.35));
    let in_switzerland = camera("osm/node/3", "ES", p(46.948, 7.447));
    let moroccan = zone("osm/node/4", "MA", vec![p(34.0, -6.8), p(34.01, -6.81)]);
    db::write_items(
        &pool,
        &[
            french.clone(),
            madrid.clone(),
            french_point.clone(),
            in_switzerland,
            moroccan,
        ],
        &[],
    )
    .await
    .unwrap();
    let read_at = Utc.with_ymd_and_hms(2026, 10, 6, 16, 3, 47).unwrap();
    db::record_read(
        &pool,
        &SourceId::new("securite-routiere").unwrap(),
        read_at,
        3_664,
        None,
    )
    .await
    .unwrap();
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));

    let (status, body) = gql(&app, json!({})).await;
    assert_eq!(status, StatusCode::OK);
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], true, "{body}");
    assert_eq!(
        ids(&e["upserts"]),
        [french.id.to_string(), madrid.id.to_string()],
        "no point in France or in Switzerland, nothing in Morocco"
    );
    let z = &e["upserts"][0];
    assert_eq!(z["kind"], "ZONE");
    assert_eq!(z["category"], "FIXED");
    assert_eq!(z["lat"], Value::Null);
    assert_eq!(z["bearingDeg"], Value::Null);
    let line = polyline::decode(z["line"].as_str().unwrap()).unwrap();
    assert_eq!(line.len(), 3);
    assert!(line[1].distance_m(french_line[1]) < 0.5);
    let c = &e["upserts"][1];
    assert_eq!(c["kind"], "CAMERA");
    assert_eq!(c["category"], "SECTION_CONTROL");
    assert!((c["lat"].as_f64().unwrap() - 40.4168).abs() < 1e-9);
    assert_eq!(c["bearingDeg"], 271.0);
    assert_eq!(c["limitKmh"], 90);
    let rules = e["rules"]["countries"].as_array().unwrap();
    let rule = |c: &str| rules.iter().find(|r| r["country"] == c).unwrap();
    assert_eq!(rule("FR")["mode"], "ZONES");
    assert_eq!(rule("FR")["zoneLengths"]["motorwayM"], 4_000);
    assert_eq!(rule("CH")["mode"], "OFF");
    assert_eq!(rule("DE")["mode"], "OFF_WHILE_DRIVING");
    assert_eq!(e["rules"]["defaultMode"], "OFF");
    let source = &e["sources"][0];
    assert_eq!(source["id"], "securite-routiere");
    assert_eq!(
        source["attribution"],
        "Sécurité routière, radars.securite-routiere.gouv.fr"
    );
    let fetched =
        chrono::DateTime::parse_from_rfc3339(source["fetchedAt"].as_str().unwrap()).unwrap();
    assert_eq!(
        fetched, read_at,
        "the CRPA asks for the date of the list with its source"
    );
    assert_eq!(e["hasMore"], false);

    // Nothing changed: an empty answer.
    let cursor = e["cursor"].as_str().unwrap().to_owned();
    let (_, body) = gql(&app, json!({"since": cursor})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(
        (e["full"].clone(), e["upserts"].clone()),
        (json!(false), json!([]))
    );

    // Madrid's camera goes, the French point is written again: both come
    // back as removals.
    db::write_items(
        &pool,
        &[Item {
            content_hash: "moved".into(),
            ..french_point.clone()
        }],
        std::slice::from_ref(&madrid.device_key),
    )
    .await
    .unwrap();
    // The head is read at most every five seconds: a new state reads it.
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));
    let (_, body) = gql(&app, json!({"since": cursor})).await;
    let e = &body["data"]["enforcement"];
    assert_eq!(e["full"], false, "{body}");
    assert_eq!(e["upserts"], json!([]));
    let mut removed = ids(&e["removals"]);
    removed.sort();
    let mut expected = vec![madrid.id.to_string(), french_point.id.to_string()];
    expected.sort();
    assert_eq!(removed, expected);

    // One country only.
    let (_, body) = gql(&app, json!({"countries": ["fr"]})).await;
    assert_eq!(
        ids(&body["data"]["enforcement"]["upserts"]),
        [french.id.to_string()]
    );
    let (_, body) = gql(&app, json!({"countries": ["FRA"]})).await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
    let (_, body) = gql(
        &app,
        json!({"since": "e1.0123456789abcdef0123456789abcdef00004000.1"}),
    )
    .await;
    assert_eq!(body["errors"][0]["extensions"]["code"], "INVALID_INPUT");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_small_page_gives_every_item_once_and_says_when_more_wait(pool: PgPool) {
    let line = |lon: f64| vec![p(45.83, lon), p(45.835, lon + 0.01)];
    let written: Vec<Item> = (0..3)
        .map(|i| {
            zone(
                &format!("securite-routiere/{i}"),
                "FR",
                line(1.2 + f64::from(i) * 0.05),
            )
        })
        .collect();
    db::write_items(&pool, &written, &[]).await.unwrap();
    let app = lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()));
    let page = |since: Option<String>| {
        let app = app.clone();
        async move {
            let request = Request::post("/graphql")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "query": "query($since: String) { enforcement(since: $since, first: 2) \
                                  { cursor full hasMore upserts { id } removals } }",
                        "variables": {"since": since}
                    })
                    .to_string(),
                ))
                .unwrap();
            let response = app.oneshot(request).await.unwrap();
            let bytes = response.into_body().collect().await.unwrap().to_bytes();
            let body: Value = serde_json::from_slice(&bytes).unwrap();
            body["data"]["enforcement"].clone()
        }
    };
    let first = page(None).await;
    assert_eq!(
        (&first["full"], &first["hasMore"]),
        (&json!(true), &json!(true)),
        "{first}"
    );
    let second = page(first["cursor"].as_str().map(str::to_owned)).await;
    assert_eq!(
        (&second["full"], &second["hasMore"]),
        (&json!(false), &json!(false)),
        "{second}"
    );
    let mut seen = ids(&first["upserts"]);
    seen.extend(ids(&second["upserts"]));
    let mut expected: Vec<String> = written.iter().map(|i| i.id.to_string()).collect();
    seen.sort();
    expected.sort();
    assert_eq!(seen, expected, "every item once over the pages");
    assert_eq!(second["removals"], json!([]));
}
