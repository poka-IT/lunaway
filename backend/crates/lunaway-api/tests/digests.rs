//! `Query.placeDigests`, what the rows of a list show beyond a place's
//! summary: the ratings by source as the place's card shows them, an
//! excerpt of the description in the reader's language, the day the place
//! was added; for the places of a list, or for an area the server widens
//! to the coarse grid.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::path::Path;

use axum::{body::Body, http::Request};
use chrono::{NaiveDate, TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::{PgPool, extcom};
use lunaway_domain::{SourceId, extcom::Terms};
use lunaway_ingest::{
    cache::Cache,
    extcom::{Input, Limits, Options, import},
};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const FEED: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../lunaway-ingest/tests/fixtures/extcom_feed.jsonl"
);

const DIGESTS: &str = r"
query($ids: [UUID!], $bbox: BBoxInput, $language: String) {
  placeDigests(ids: $ids, bbox: $bbox, language: $language) {
    placeId
    ratings { sourceId average count }
    excerpt { lang text sourceId }
    addedAt
  }
}";

const CARD_RATINGS: &str = r"
query($id: UUID!) { place(id: $id) { externalRatings { sourceId average count } } }";

/// The fixture feed imported and conflated; the place of spot 1001
/// ("Parking du lac", rated 4.2 by 87 on the partner's site, described in
/// French and English).
async fn seeded(pool: &PgPool, cache_dir: &Path) -> Uuid {
    let options = Options {
        terms: Terms::new("EXTCOM-TEST-2026-01", &["img.partner.example".into()]).unwrap(),
        limits: Limits::default(),
        refresh: false,
        today: NaiveDate::from_ymd_opt(2026, 10, 7).unwrap(),
    };
    let http = lunaway_ingest::http::client_allowing_plain_http().unwrap();
    import(
        pool,
        &http,
        &Cache::new(cache_dir),
        &Input::File(FEED.into()),
        &options,
    )
    .await
    .unwrap();
    let now = Utc.with_ymd_and_hms(2026, 10, 7, 12, 0, 0).unwrap();
    lunaway_conflate::run(pool, now, None).await.unwrap();
    sqlx::query_scalar(
        "SELECT ps.place_id FROM place_sources ps JOIN source_records r ON r.id = ps.record_id \
         WHERE r.source_id = 'extcom' AND r.external_id = '1001'",
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

fn app(pool: &PgPool) -> axum::Router {
    lunaway_api::router(ApiState::new(pool.clone(), ApiConfig::default()))
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

fn digests(body: &Value) -> &Vec<Value> {
    assert!(body.get("errors").is_none(), "unexpected errors: {body}");
    body["data"]["placeDigests"].as_array().unwrap()
}

fn code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or_else(|| panic!("expected an error: {body}"))
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_row_reads_the_partner_s_rating_as_the_card_does_and_an_excerpt(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let app = app(&pool);

    let body = gql(&app, DIGESTS, json!({"ids": [place], "language": "fr"})).await;
    let rows = digests(&body);
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(row["placeId"], json!(place));
    let card = gql(&app, CARD_RATINGS, json!({"id": place})).await;
    assert_eq!(
        row["ratings"], card["data"]["place"]["externalRatings"],
        "a row rates a place as its card does, or the list and the card disagree"
    );
    assert_eq!(
        row["ratings"],
        json!([{"sourceId": "extcom", "average": 4.2, "count": 87}])
    );
    assert_eq!(row["excerpt"]["lang"], "fr");
    assert_eq!(row["excerpt"]["sourceId"], "extcom");
    let text = row["excerpt"]["text"].as_str().unwrap();
    assert!(
        text.starts_with("Calme la nuit.") && !text.contains('\n'),
        "the French text on one line: {text}"
    );
    let added: chrono::DateTime<Utc> = row["addedAt"].as_str().unwrap().parse().unwrap();
    let created: chrono::DateTime<Utc> =
        sqlx::query_scalar("SELECT created_at FROM places WHERE id = $1")
            .bind(place)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(added, created, "the day the place was added to Lunaway");

    let english = gql(&app, DIGESTS, json!({"ids": [place], "language": "en"})).await;
    assert_eq!(digests(&english)[0]["excerpt"]["text"], "Quiet at night.");
    let german = gql(&app, DIGESTS, json!({"ids": [place], "language": "de"})).await;
    assert_eq!(
        digests(&german)[0]["excerpt"]["lang"],
        "en",
        "a language no source wrote falls back to English"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn lunaway_s_rating_comes_first_and_a_hidden_source_gives_none(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    sqlx::query("UPDATE places SET rating_avg = 4.5, rating_count = 2 WHERE id = $1")
        .bind(place)
        .execute(&pool)
        .await
        .unwrap();
    let app = app(&pool);
    let body = gql(&app, DIGESTS, json!({"ids": [place]})).await;
    assert_eq!(
        digests(&body)[0]["ratings"],
        json!([
            {"sourceId": "community-cc-by", "average": 4.5, "count": 2},
            {"sourceId": "extcom", "average": 4.2, "count": 87}
        ]),
        "each source apart, never added together"
    );

    extcom::set_hidden(&pool, &SourceId::EXTCOM, true, None)
        .await
        .unwrap();
    let body = gql(&app, DIGESTS, json!({"ids": [place]})).await;
    assert_eq!(
        digests(&body)[0]["ratings"],
        json!([{"sourceId": "community-cc-by", "average": 4.5, "count": 2}]),
        "the switch hides the partner's ratings from the lists as from the card"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_area_is_read_once_widened_to_the_grid(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let app = app(&pool);
    // Spot 1001 lies at 45.8992, 6.1294: this box stops 100 m short of it,
    // inside the same cell of the 0.05 degree grid.
    let body = gql(
        &app,
        DIGESTS,
        json!({"bbox": {"south": 45.8960, "west": 6.1270, "north": 45.8983, "east": 6.1285}}),
    )
    .await;
    assert!(
        digests(&body).iter().any(|d| d["placeId"] == json!(place)),
        "the server reads no area finer than the grid, whatever the client sends"
    );

    let wide = gql(
        &app,
        DIGESTS,
        json!({"bbox": {"south": 45.0, "west": 5.0, "north": 46.2, "east": 6.2}}),
    )
    .await;
    assert_eq!(code(&wide), "INVALID_INPUT", "a list never covers a region");
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_arguments_are_bounded(pool: PgPool) {
    let app = app(&pool);
    let both = gql(
        &app,
        DIGESTS,
        json!({"ids": [], "bbox": {"south": 45.0, "west": 6.0, "north": 45.1, "east": 6.1}}),
    )
    .await;
    assert_eq!(code(&both), "INVALID_INPUT");
    let neither = gql(&app, DIGESTS, json!({})).await;
    assert_eq!(code(&neither), "INVALID_INPUT");
    let many: Vec<Uuid> = (0..201).map(|_| Uuid::now_v7()).collect();
    let too_many = gql(&app, DIGESTS, json!({"ids": many})).await;
    assert_eq!(code(&too_many), "INVALID_INPUT");
    let language = gql(
        &app,
        DIGESTS,
        json!({"ids": [Uuid::now_v7()], "language": "fra"}),
    )
    .await;
    assert_eq!(code(&language), "INVALID_INPUT");
    let unknown = gql(&app, DIGESTS, json!({"ids": [Uuid::now_v7()]})).await;
    assert!(
        digests(&unknown).is_empty(),
        "an unknown or deleted place is left out"
    );
}
