//! The open content of a place as the card reads it: photos with their
//! author and licence served from Lunaway's media host, descriptions with
//! their source and language, reviews with their author's pseudonym.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use axum::{body::Body, http::Request};
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::{
    PgPool,
    content::{self, NewDescription, NewPhoto, NewReview, PhotoFiles},
};
use lunaway_domain::SourceId;
use lunaway_ingest::{osm, store::store_complete};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const OVERPASS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/overpass_sample.json");

fn app(pool: &PgPool) -> axum::Router {
    let defaults = ApiConfig::default();
    let config = ApiConfig {
        media: lunaway_api::config::MediaConfig {
            base_url: "https://media.test/".into(),
            ..defaults.media.clone()
        },
        ..defaults
    };
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

async fn gql(app: &axum::Router, query: &str, variables: Value) -> Value {
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

async fn a_place(pool: &PgPool) -> Uuid {
    let at = Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap();
    let o = osm::parse(OVERPASS, at).unwrap();
    store_complete(pool, &SourceId::OSM, Some("FR-PDL"), &o.records)
        .await
        .unwrap();
    lunaway_conflate::run(pool, at, None).await.unwrap();
    sqlx::query_scalar!("SELECT id FROM places WHERE deleted_at IS NULL ORDER BY id LIMIT 1")
        .fetch_one(pool)
        .await
        .unwrap()
}

const CARD: &str = r#"
query($id: UUID!) {
  place(id: $id) {
    externalPhotos {
      sourceId relation distanceM thumbUrl largeUrl width height thumbhash
      title author publisher sourceUpdatedOn licence licenceUrl pageUrl
    }
    externalDescriptions {
      sourceId lang text title publisher licence licenceUrl pageUrl
    }
    externalReviews(first: 5) {
      sourceId rating text authorName writtenAt licence licenceUrl pageUrl
    }
  }
}"#;

#[sqlx::test(migrations = "../../migrations")]
async fn the_card_reads_open_content_with_its_attribution(pool: PgPool) {
    let place = a_place(&pool).await;
    let now = Utc::now();
    let h = "ab".repeat(32);
    content::replace_photos(
        &pool,
        place,
        "panoramax",
        &[NewPhoto {
            external_id: "d8dc9efb-d1b4-4a64-b948-f28bde76b202".into(),
            version: "d8dc9efb-d1b4-4a64-b948-f28bde76b202".into(),
            relation: "facing".into(),
            distance_m: Some(14.5),
            page_url: "https://panoramax.openstreetmap.fr/?focus=pic&pic=d8dc9efb".into(),
            title: None,
            author: Some("PanierAvide".into()),
            publisher: Some("Panoramax OpenStreetMap France".into()),
            source_updated_on: None,
            licence: "CC BY-SA 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
            taken_at: None,
            rights_end_on: None,
            files: PhotoFiles {
                path: format!("external/ab/ab/{h}.webp"),
                thumb_path: format!("external/ab/ab/{h}.webp"),
                width: 1280,
                height: 853,
                thumbhash: vec![1, 2, 3],
            },
        }],
        now,
        1,
    )
    .await
    .unwrap();
    content::replace_descriptions(
        &pool,
        place,
        "datatourisme",
        &[NewDescription {
            lang: "fr".into(),
            text: "Aire de services au bord du lac.".into(),
            title: None,
            page_url: "https://data.datatourisme.fr/23/f771da87".into(),
            author: None,
            publisher: Some("Corrèze Tourisme".into()),
            source_updated_on: chrono::NaiveDate::from_ymd_opt(2026, 8, 4),
            licence: "Licence Ouverte 2.0".into(),
            licence_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence/".into(),
        }],
        now,
        1,
    )
    .await
    .unwrap();
    content::replace_reviews(
        &pool,
        "mangrove",
        &[NewReview {
            place_id: place,
            external_id: "sig".into(),
            rating: Some(4),
            text: Some("Calme.".into()),
            lang: None,
            author: Some("Surreality".into()),
            author_key: None,
            written_at: now,
            page_url: "https://mangrove.reviews/list?signature=sig".into(),
            licence: "CC BY 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
            distance_m: Some(3.0),
        }],
        now,
    )
    .await
    .unwrap();
    let app = app(&pool);
    let body = gql(&app, CARD, json!({"id": place})).await;
    assert!(body.get("errors").is_none(), "{body}");
    let p = &body["data"]["place"];
    let photo = &p["externalPhotos"][0];
    assert_eq!(photo["relation"], "FACING");
    assert_eq!(
        photo["largeUrl"],
        format!("https://media.test/external/ab/ab/{h}.webp"),
        "served from Lunaway's media host, never the source's"
    );
    assert_eq!(photo["author"], "PanierAvide");
    assert_eq!(photo["licence"], "CC BY-SA 4.0");
    assert_eq!(photo["publisher"], "Panoramax OpenStreetMap France");
    let d = &p["externalDescriptions"][0];
    assert_eq!(d["sourceId"], "datatourisme");
    assert_eq!(d["lang"], "fr");
    assert_eq!(d["publisher"], "Corrèze Tourisme");
    let r = &p["externalReviews"][0];
    assert_eq!(r["rating"], 4);
    assert_eq!(r["authorName"], "Surreality");
    assert_eq!(r["licence"], "CC BY 4.0");
    let sources = gql(&app, "{ sources { id licence } }", json!({})).await;
    let ids: Vec<&str> = sources["data"]["sources"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|s| s["id"].as_str())
        .collect();
    for id in [
        "wikimedia-commons",
        "wikipedia",
        "panoramax",
        "mangrove",
        "datatourisme",
    ] {
        assert!(
            ids.contains(&id),
            "every content source is listed with its licence: {id}"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn open_content_is_too_dear_to_read_for_a_whole_viewport(pool: PgPool) {
    let place = a_place(&pool).await;
    let app = app(&pool);
    let body = gql(
        &app,
        "{ places(bbox: {south: 46, west: -2, north: 48.5, east: 1}, first: 200) { nodes { id externalPhotos { id } } } }",
        json!({}),
    )
    .await;
    assert!(
        body.get("errors").is_some(),
        "a database query per place is for the card, not for a list: {body}"
    );
    let bad = gql(
        &app,
        "query($id: UUID!) { place(id: $id) { externalReviews(first: 500) { text } } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(
        bad["errors"][0]["extensions"]["code"], "INVALID_INPUT",
        "a page of reviews is bounded: {bad}"
    );
}
