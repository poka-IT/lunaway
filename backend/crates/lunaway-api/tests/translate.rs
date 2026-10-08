//! `Query.translate`: a stored review or description translated by the
//! translation server (a fake on the loopback here), kept so the same text
//! is translated once, within the client's quota, and never a text the
//! reader may not see.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{Request, StatusCode},
    response::IntoResponse,
    routing::post,
};
use chrono::{NaiveDate, TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{
    ApiConfig, ApiState,
    config::{Quota, TranslateConfig},
};
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

/// The partner's place 1001, with its reviews: `r-1` in French, `r-2` in
/// German ("Ruhig und sauber.").
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

async fn review_id(pool: &PgPool, external_id: &str) -> Uuid {
    sqlx::query_scalar("SELECT id FROM external_reviews WHERE external_id = $1")
        .bind(external_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// What the fake translation server was asked: source, target, text.
type Asked = Arc<Mutex<Vec<(String, String, String)>>>;

async fn answer(State(asked): State<Asked>, Json(body): Json<Value>) -> impl IntoResponse {
    let source = body["source"].as_str().unwrap().to_owned();
    let target = body["target"].as_str().unwrap().to_owned();
    let text = body["text"].as_str().unwrap().to_owned();
    asked
        .lock()
        .unwrap()
        .push((source.clone(), target.clone(), text.clone()));
    if target == "it" {
        return (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({"error": "no model for this pair"})),
        );
    }
    (
        StatusCode::OK,
        Json(json!({
            "text": format!("[{source}>{target}] {text}"),
            "engine": "opus-mt",
            "model": format!("{source}-{target} test"),
        })),
    )
}

/// A translation server on the loopback: its base URL, as Caddy's path to
/// it, and what it is asked.
async fn fake_server() -> (String, Asked) {
    let asked = Asked::default();
    let app = Router::new()
        .route("/translator/translate", post(answer))
        .with_state(Arc::clone(&asked));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/translator", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked)
}

fn config(url: Option<String>) -> ApiConfig {
    ApiConfig {
        translate: TranslateConfig {
            url,
            timeout: Duration::from_secs(5),
            ..TranslateConfig::default()
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
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

const TRANSLATE: &str = r"
query($kind: TranslatableKind!, $id: UUID!, $source: String, $lang: String, $to: String!) {
  translate(kind: $kind, id: $id, sourceId: $source, lang: $lang, targetLang: $to) {
    text sourceLang targetLang engine model
  }
}";

fn review(id: Uuid, to: &str) -> Value {
    json!({"kind": "EXTERNAL_REVIEW", "id": id, "to": to})
}

fn code(body: &Value) -> (&str, Option<&str>) {
    let ext = &body["errors"][0]["extensions"];
    (ext["code"].as_str().unwrap_or(""), ext["reason"].as_str())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_is_translated_once_then_read_from_what_was_kept(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    let (url, asked) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let id = review_id(&pool, "r-2").await;

    let first = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(
        first["data"]["translate"],
        json!({
            "text": "[de>fr] Ruhig und sauber.",
            "sourceLang": "de",
            "targetLang": "fr",
            "engine": "opus-mt",
            "model": "de-fr test",
        }),
        "{first}"
    );
    let again = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(again["data"]["translate"], first["data"]["translate"]);
    assert_eq!(
        asked.lock().unwrap().as_slice(),
        [(
            "de".to_owned(),
            "fr".to_owned(),
            "Ruhig und sauber.".to_owned()
        )],
        "the stored text, its language and the one asked go to the server, once"
    );

    // The partner purges its source: the translations go with the reviews.
    extcom::purge(&pool, &SourceId::EXTCOM, None).await.unwrap();
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM translations")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        left, 0,
        "nothing of a purged review stays, translated or not"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_text_in_the_language_asked_comes_back_as_it_is(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    let (url, asked) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let id = review_id(&pool, "r-1").await;
    let body = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(
        body["data"]["translate"],
        json!({
            "text": "Très calme, vue sur le lac.",
            "sourceLang": "fr",
            "targetLang": "fr",
            "engine": null,
            "model": null,
        })
    );
    assert!(asked.lock().unwrap().is_empty(), "nothing to translate");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_s_description_is_named_by_its_source_and_language(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, _) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let body = gql(
        &app,
        TRANSLATE,
        json!({"kind": "DESCRIPTION", "id": place, "source": "extcom", "lang": "en", "to": "fr"}),
    )
    .await;
    assert_eq!(
        body["data"]["translate"]["text"], "[en>fr] Quiet at night.",
        "{body}"
    );
    let unnamed = gql(
        &app,
        TRANSLATE,
        json!({"kind": "DESCRIPTION", "id": place, "to": "fr"}),
    )
    .await;
    assert_eq!(code(&unnamed).0, "INVALID_INPUT");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_language_without_a_model_is_said_apart_and_costs_nothing(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    let (url, _) = fake_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = Quota {
        count: 1,
        period: Duration::from_secs(3_600),
    };
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    let id = review_id(&pool, "r-2").await;
    let refused = gql(&app, TRANSLATE, review(id, "it")).await;
    assert_eq!(
        code(&refused),
        ("INVALID_INPUT", Some("UNSUPPORTED_LANGUAGE")),
        "the app stops offering a translation it cannot get: {refused}"
    );
    let done = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert!(
        done.get("errors").is_none(),
        "a refused pair gave its use of the quota back: {done}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_quota_counts_only_what_the_server_translates(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, asked) = fake_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = Quota {
        count: 1,
        period: Duration::from_secs(3_600),
    };
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    let id = review_id(&pool, "r-2").await;
    assert!(
        gql(&app, TRANSLATE, review(id, "fr"))
            .await
            .get("errors")
            .is_none()
    );
    let kept = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert!(
        kept.get("errors").is_none(),
        "a kept translation costs nothing: {kept}"
    );
    let spent = gql(
        &app,
        TRANSLATE,
        json!({"kind": "DESCRIPTION", "id": place, "source": "extcom", "lang": "en", "to": "fr"}),
    )
    .await;
    assert_eq!(code(&spent).0, "RATE_LIMITED", "{spent}");
    assert!(
        spent["errors"][0]["extensions"]["retryAfterSeconds"]
            .as_u64()
            .unwrap()
            > 0
    );
    assert_eq!(
        asked.lock().unwrap().len(),
        1,
        "the spent quota spares the server"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn without_a_server_nothing_is_translated(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    let id = review_id(&pool, "r-2").await;
    let off = lunaway_api::router(ApiState::new(pool.clone(), config(None)));
    assert_eq!(
        code(&gql(&off, TRANSLATE, review(id, "fr")).await).0,
        "UNAVAILABLE"
    );
    // A port nothing listens on: the server is down.
    let closed = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/translator", closed.local_addr().unwrap());
    drop(closed);
    let down = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    assert_eq!(
        code(&gql(&down, TRANSLATE, review(id, "fr")).await).0,
        "UNAVAILABLE"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_a_stored_text_a_reader_sees_is_translated(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    let (url, asked) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let unknown = gql(&app, TRANSLATE, review(Uuid::now_v7(), "fr")).await;
    assert_eq!(code(&unknown).0, "NOT_FOUND");
    let id = review_id(&pool, "r-2").await;
    assert_eq!(
        code(&gql(&app, TRANSLATE, review(id, "FR")).await).0,
        "INVALID_INPUT"
    );
    extcom::set_hidden(&pool, &SourceId::EXTCOM, true, None)
        .await
        .unwrap();
    assert_eq!(
        code(&gql(&app, TRANSLATE, review(id, "fr")).await).0,
        "NOT_FOUND",
        "a hidden source's reviews are out of reach, translated or not"
    );
    assert!(asked.lock().unwrap().is_empty());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_without_a_language_gets_the_one_its_words_say(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    sqlx::query(
        "UPDATE external_reviews SET lang = NULL, \
         body = 'Ruhig und sauber, die Säule funktioniert gut.' WHERE external_id = 'r-2'",
    )
    .execute(&pool)
    .await
    .unwrap();
    let (url, asked) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let card = gql(
        &app,
        "query($id: UUID!) { place(id: $id) { externalReviews { nodes { id lang } } } }",
        json!({"id": place}),
    )
    .await;
    let id = review_id(&pool, "r-2").await;
    let node = card["data"]["place"]["externalReviews"]["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|n| n["id"] == json!(id))
        .unwrap()
        .clone();
    assert_eq!(
        node["lang"], "de",
        "the app knows to offer a translation: {card}"
    );
    let body = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(body["data"]["translate"]["sourceLang"], "de", "{body}");
    assert_eq!(asked.lock().unwrap()[0].0, "de");
}
