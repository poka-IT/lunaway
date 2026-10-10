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

/// Shut until the test opens it (`add_permits(1)`): the fake holds every
/// text into Portuguese until then, and lets them all through after.
type Gate = Arc<tokio::sync::Semaphore>;

async fn answer(
    State((asked, gate)): State<(Asked, Gate)>,
    Json(body): Json<Value>,
) -> impl IntoResponse {
    let source = body["source"].as_str().unwrap().to_owned();
    let target = body["target"].as_str().unwrap().to_owned();
    let text = body["text"].as_str().unwrap().to_owned();
    asked
        .lock()
        .unwrap()
        .push((source.clone(), target.clone(), text.clone()));
    // The target language picks how the fake behaves: no model for
    // Italian, busy for Spanish, an answer past every bound for Dutch, an
    // answer once the test opens the gate for Portuguese, the gateway's
    // error of a stopped server for Swedish, the text given back as it
    // came for Danish (a model fed a language it does not know).
    if target == "pt" {
        drop(gate.acquire().await.unwrap());
    }
    match target.as_str() {
        // What Caddy answers for a translation server that is stopped.
        "sv" => {
            return (StatusCode::BAD_GATEWAY, Json(json!({})));
        }
        "it" => {
            return (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"error": "no model for this pair"})),
            );
        }
        "es" => {
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "busy"})),
            );
        }
        "nl" => {
            return (
                StatusCode::OK,
                Json(json!({"text": "x".repeat(200_000), "engine": "opus-mt", "model": "m"})),
            );
        }
        "da" => {
            return (
                StatusCode::OK,
                Json(json!({"text": text, "engine": "opus-mt", "model": "m"})),
            );
        }
        _ => {}
    }
    (
        StatusCode::OK,
        Json(json!({
            "text": made(&source, &target, &text),
            "engine": "opus-mt",
            "model": format!("{source}-{target} test"),
        })),
    )
}

/// What the fake makes of `text`: a text no word of which is the
/// original's, as a translation.
fn made(source: &str, target: &str, text: &str) -> String {
    format!(
        "[{source}>{target}] {}",
        text.chars().rev().collect::<String>()
    )
}

/// A translation server on the loopback: its base URL, as Caddy's path to
/// it, and what it is asked. It never answers a text into Portuguese.
async fn fake_server() -> (String, Asked) {
    let (url, asked, _) = gated_server().await;
    (url, asked)
}

/// [`fake_server`], with the gate that lets the texts into Portuguese
/// through.
async fn gated_server() -> (String, Asked, Gate) {
    let asked = Asked::default();
    let gate = Gate::new(tokio::sync::Semaphore::new(0));
    let app = Router::new()
        .route("/translator/translate", post(answer))
        .with_state((Arc::clone(&asked), Arc::clone(&gate)));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/translator", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await });
    (url, asked, gate)
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
            "text": made("de", "fr", "Ruhig und sauber."),
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
        body["data"]["translate"]["text"],
        made("en", "fr", "Quiet at night."),
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

/// A review in Finnish, taken for German and given back as it went
/// before (2026-10-10).
const FINNISH: &str = "Hyvä hiljainen paikka yöpymiseen. Alueella ajosuunta on niin hölmö että \
                       vesihuoltopisteelle vaikea kääntä yli 6m autolla.";

#[sqlx::test(migrations = "../../migrations")]
async fn a_text_the_model_gives_back_is_no_translation(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    // Labelled German by its source, as a guess would have said before.
    sqlx::query("UPDATE external_reviews SET lang = 'de', body = $1 WHERE external_id = 'r-2'")
        .bind(FINNISH)
        .execute(&pool)
        .await
        .unwrap();
    let (url, asked) = fake_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = one_use();
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    let id = review_id(&pool, "r-2").await;
    let echoed = gql(&app, TRANSLATE, review(id, "da")).await;
    assert_eq!(
        code(&echoed),
        ("INVALID_INPUT", Some("UNSUPPORTED_LANGUAGE")),
        "never shown as translated: {echoed}"
    );
    let again = gql(&app, TRANSLATE, review(id, "da")).await;
    assert_eq!(
        code(&again),
        ("INVALID_INPUT", Some("UNSUPPORTED_LANGUAGE")),
        "{again}"
    );
    assert_eq!(
        asked.lock().unwrap().len(),
        1,
        "the copy is kept as the verdict: the model is not asked again"
    );
    let spent = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(
        code(&spent).0,
        "RATE_LIMITED",
        "the model worked: the copy counts, so asking it again and again is no free load: {spent}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_finnish_review_is_said_finnish_and_its_old_copy_is_not_served(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    sqlx::query("UPDATE external_reviews SET lang = NULL, body = $1 WHERE external_id = 'r-2'")
        .bind(FINNISH)
        .execute(&pool)
        .await
        .unwrap();
    let id = review_id(&pool, "r-2").await;
    // What a release before kept: the German model's copy of the text.
    sqlx::query(
        "INSERT INTO translations (item_kind, item_id, item_source, item_lang, target_lang, \
                                   source_lang, source_sha256, text, engine, model, \
                                   translated_at) \
         VALUES ('external_review', $1, '', '', 'fr', 'de', $2, $3, 'opus-mt', 'de-fr', now())",
    )
    .bind(id)
    .bind(lunaway_domain::translation::text_fingerprint(FINNISH).to_vec())
    .bind(FINNISH)
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
    let node = card["data"]["place"]["externalReviews"]["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|n| n["id"] == json!(id))
        .unwrap()
        .clone();
    assert_eq!(node["lang"], "fi", "taken for German before: {card}");
    let body = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(
        body["data"]["translate"]["sourceLang"], "fi",
        "the copy kept under German is not served: {body}"
    );
    assert_eq!(asked.lock().unwrap()[0].0, "fi");
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

fn one_use() -> Quota {
    Quota {
        count: 1,
        period: Duration::from_secs(3_600),
    }
}

/// The description of `place` into French: a translation the fake makes.
fn description_to_french(place: Uuid) -> Value {
    json!({"kind": "DESCRIPTION", "id": place, "source": "extcom", "lang": "en", "to": "fr"})
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failed_translation_gives_the_use_back(pool: PgPool) {
    // Only a translation made counts (2026-10-09, plan/research/82-suites-4.md):
    // before, a stopped server (Caddy's 502), a bad answer or one too late
    // kept the client's use.
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, _) = fake_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = one_use();
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    let id = review_id(&pool, "r-2").await;
    let busy = gql(&app, TRANSLATE, review(id, "es")).await;
    assert_eq!(code(&busy).0, "RATE_LIMITED", "{busy}");
    let stopped = gql(&app, TRANSLATE, review(id, "sv")).await;
    assert_eq!(code(&stopped).0, "UNAVAILABLE", "{stopped}");
    let oversized = gql(&app, TRANSLATE, review(id, "nl")).await;
    assert_eq!(code(&oversized).0, "UNAVAILABLE", "{oversized}");
    let done = gql(&app, TRANSLATE, description_to_french(place)).await;
    assert!(
        done.get("errors").is_none(),
        "a stopped server and a bad answer gave the use back: {done}"
    );
    let spent = gql(&app, TRANSLATE, review(id, "fr")).await;
    assert_eq!(
        code(&spent).0,
        "RATE_LIMITED",
        "the translation made took the one use: {spent}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_server_out_of_time_gives_the_use_back(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, _) = fake_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = one_use();
    c.translate.timeout = Duration::from_millis(300);
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    let id = review_id(&pool, "r-2").await;
    let late = gql(&app, TRANSLATE, review(id, "pt")).await;
    assert_eq!(code(&late).0, "UNAVAILABLE", "{late}");
    let done = gql(&app, TRANSLATE, description_to_french(place)).await;
    assert!(
        done.get("errors").is_none(),
        "a text the server did not translate in time costs nothing: {done}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_translation_the_client_left_is_made_kept_and_counted(pool: PgPool) {
    // The API's limit cuts the request while the server works on the
    // text: the server's slot stays taken until it answers, as it does
    // not see the client leave, and the translation it makes is kept for
    // the next request, which costs nothing. Leaving and asking again
    // never gets a client free work from the server.
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, asked, gate) = gated_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = one_use();
    c.limits.request_timeout = Duration::from_millis(300);
    let app = lunaway_api::router(ApiState::new(pool.clone(), c));
    let id = review_id(&pool, "r-2").await;
    let cut = gql(&app, TRANSLATE, review(id, "pt")).await;
    assert!(cut.get("errors").is_some(), "{cut}");
    // The server answers once the client has left.
    gate.add_permits(1);
    let mut kept = 0;
    for _ in 0..50 {
        kept = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM translations"#)
            .fetch_one(&pool)
            .await
            .unwrap();
        if kept > 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!(
        kept, 1,
        "the translation made after the client left is kept"
    );
    let again = gql(&app, TRANSLATE, review(id, "pt")).await;
    assert!(again.get("errors").is_none(), "{again}");
    assert_eq!(asked.lock().unwrap().len(), 1, "read from what was kept");
    let spent = gql(&app, TRANSLATE, description_to_french(place)).await;
    assert_eq!(
        code(&spent).0,
        "RATE_LIMITED",
        "the translation made took the one use: {spent}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_request_translates_one_text(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, asked) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let id = review_id(&pool, "r-2").await;
    let body = gql(
        &app,
        "query($id: UUID!, $place: UUID!) {
           a: translate(kind: EXTERNAL_REVIEW, id: $id, targetLang: \"fr\") { text }
           b: translate(kind: DESCRIPTION, id: $place, sourceId: \"extcom\", lang: \"en\",
                        targetLang: \"fr\") { text }
         }",
        json!({"id": id, "place": place}),
    )
    .await;
    let errors = body["errors"].as_array().unwrap();
    assert_eq!(errors.len(), 1, "{body}");
    assert_eq!(errors[0]["extensions"]["code"], "INVALID_INPUT");
    assert_eq!(
        asked.lock().unwrap().len(),
        1,
        "aliases cannot hold the server's slots for one client"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_open_source_s_description_is_translated(pool: PgPool) {
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    lunaway_db::content::replace_descriptions(
        &pool,
        place,
        "wikipedia",
        &[lunaway_db::content::NewDescription {
            lang: "de".into(),
            text: "Ein ruhiger See am Rand der Stadt.".into(),
            title: Some("See".into()),
            page_url: "https://de.wikipedia.org/wiki/See".into(),
            author: None,
            publisher: Some("Wikipedia".into()),
            source_updated_on: None,
            licence: "CC BY-SA 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
        }],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    let (url, _) = fake_server().await;
    let app = lunaway_api::router(ApiState::new(pool.clone(), config(Some(url))));
    let body = gql(
        &app,
        TRANSLATE,
        json!({"kind": "EXTERNAL_DESCRIPTION", "id": place, "source": "wikipedia", "lang": "de", "to": "fr"}),
    )
    .await;
    assert_eq!(
        body["data"]["translate"]["text"],
        made("de", "fr", "Ein ruhiger See am Rand der Stadt."),
        "{body}"
    );
    let other = gql(
        &app,
        TRANSLATE,
        json!({"kind": "DESCRIPTION", "id": place, "source": "wikipedia", "lang": "de", "to": "fr"}),
    )
    .await;
    assert_eq!(
        code(&other).0,
        "NOT_FOUND",
        "an open source's text is named as such, not as the place's own"
    );
}

/// A router whose requests come through the local proxy, as in
/// production: each request names its client in `X-Forwarded-For`.
fn behind_proxy(state: ApiState) -> Router {
    lunaway_api::router(state).layer(axum::extract::connect_info::MockConnectInfo(
        "127.0.0.1:40000".parse::<std::net::SocketAddr>().unwrap(),
    ))
}

/// [`gql`] for the client at `ip`.
async fn gql_from(app: &Router, ip: &str, query: &str, variables: Value) -> Value {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .header("x-forwarded-for", ip)
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

/// Whether `body` refuses a text because the server, or the client's own
/// slots, stayed busy: worth asking again in a moment, unlike a spent
/// quota.
fn busy(body: &Value) -> bool {
    code(body).0 == "RATE_LIMITED"
        && body["errors"][0]["message"]
            .as_str()
            .is_some_and(|m| m.contains("busy"))
}

/// Waits until the fake server has been asked `n` texts.
async fn asked_at_least(asked: &Asked, n: usize) {
    for _ in 0..100 {
        if asked.lock().unwrap().len() >= n {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("the server was never asked {n} texts");
}

/// The place's French description, into `to`.
fn description_into(place: Uuid, to: &str) -> Value {
    json!({"kind": "DESCRIPTION", "id": place, "source": "extcom", "lang": "fr", "to": to})
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_client_translates_two_texts_at_once_and_the_others_still_get_theirs(pool: PgPool) {
    // A text the server always fails at costs its client no use of the
    // quota: two texts at once at most for one client, so the rest of the
    // API's four slots stay for everyone else
    // (plan/research/82-suites-4.md, open points).
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, asked, gate) = gated_server().await;
    let mut c = config(Some(url));
    c.quotas.translate = Quota {
        count: 3,
        period: Duration::from_secs(3_600),
    };
    c.translate.queue_wait = Duration::from_millis(300);
    let app = behind_proxy(ApiState::new(pool.clone(), c));
    let r1 = review_id(&pool, "r-1").await;
    let r2 = review_id(&pool, "r-2").await;
    // Two texts the server holds until the gate opens (into Portuguese).
    let mut holders = Vec::new();
    for ask in [review(r2, "pt"), description_into(place, "pt")] {
        let app = app.clone();
        holders.push(tokio::spawn(async move {
            gql_from(&app, "203.0.113.9", TRANSLATE, ask).await
        }));
    }
    asked_at_least(&asked, 2).await;
    let third = gql_from(&app, "203.0.113.9", TRANSLATE, review(r1, "en")).await;
    assert!(
        busy(&third),
        "a third text at once waits, then is refused as busy: {third}"
    );
    let other = gql_from(&app, "198.51.100.7", TRANSLATE, review(r2, "en")).await;
    assert!(
        other.get("errors").is_none(),
        "another client still gets a slot: {other}"
    );
    gate.add_permits(1);
    for h in holders {
        let done = h.await.unwrap();
        assert!(done.get("errors").is_none(), "{done}");
    }
    let after = gql_from(&app, "203.0.113.9", TRANSLATE, review(r1, "en")).await;
    assert!(
        after.get("errors").is_none(),
        "the refusal took none of the three uses: {after}"
    );
    let spent = gql_from(
        &app,
        "203.0.113.9",
        TRANSLATE,
        description_into(place, "de"),
    )
    .await;
    assert_eq!(code(&spent).0, "RATE_LIMITED", "{spent}");
    assert!(
        !busy(&spent),
        "the three translations made took the three uses: {spent}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_client_s_slots_stay_taken_until_its_translations_end_though_it_left(pool: PgPool) {
    // The requests are cut while the server works: the tasks that keep
    // the translations hold the client's slots until the server answers,
    // so leaving and asking again gives no third text at once.
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, asked, gate) = gated_server().await;
    let mut c = config(Some(url));
    c.limits.request_timeout = Duration::from_millis(300);
    c.translate.queue_wait = Duration::from_millis(100);
    let app = behind_proxy(ApiState::new(pool.clone(), c));
    let r1 = review_id(&pool, "r-1").await;
    let r2 = review_id(&pool, "r-2").await;
    for ask in [review(r2, "pt"), description_into(place, "pt")] {
        let cut = gql_from(&app, "203.0.113.9", TRANSLATE, ask).await;
        assert!(cut.get("errors").is_some(), "{cut}");
    }
    assert_eq!(asked.lock().unwrap().len(), 2);
    let held = gql_from(&app, "203.0.113.9", TRANSLATE, review(r1, "en")).await;
    assert!(
        busy(&held),
        "the translations of the client who left still hold its slots: {held}"
    );
    gate.add_permits(1);
    let mut kept = 0;
    for _ in 0..50 {
        kept = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM translations"#)
            .fetch_one(&pool)
            .await
            .unwrap();
        if kept == 2 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!(kept, 2, "both translations were made and kept");
    let freed = gql_from(&app, "203.0.113.9", TRANSLATE, review(r1, "en")).await;
    assert!(
        freed.get("errors").is_none(),
        "the slots came back when the translations ended: {freed}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_ipv6_site_rotating_its_64s_leaves_a_slot_to_the_others(pool: PgPool) {
    // A /48 holds 65 536 /64s, each a client of its own: together they
    // hold every slot of the API but one.
    let dir = tempfile::tempdir().unwrap();
    let place = seeded(&pool, dir.path()).await;
    let (url, asked, gate) = gated_server().await;
    let mut c = config(Some(url));
    c.translate.queue_wait = Duration::from_millis(300);
    let app = behind_proxy(ApiState::new(pool.clone(), c));
    let r1 = review_id(&pool, "r-1").await;
    let r2 = review_id(&pool, "r-2").await;
    let mut holders = Vec::new();
    for (ip, ask) in [
        ("2001:db8:1:1::1", review(r2, "pt")),
        ("2001:db8:1:1::2", description_into(place, "pt")),
        ("2001:db8:1:2::1", review(r1, "pt")),
    ] {
        let app = app.clone();
        holders.push(tokio::spawn(async move {
            gql_from(&app, ip, TRANSLATE, ask).await
        }));
        asked_at_least(&asked, holders.len()).await;
    }
    let fourth = gql_from(&app, "2001:db8:1:3::1", TRANSLATE, review(r2, "en")).await;
    assert!(
        busy(&fourth),
        "a third /64 of the same /48 finds its site's slots taken: {fourth}"
    );
    let elsewhere = gql_from(&app, "203.0.113.9", TRANSLATE, review(r1, "en")).await;
    assert!(
        elsewhere.get("errors").is_none(),
        "the last slot stays for another network: {elsewhere}"
    );
    gate.add_permits(1);
    for h in holders {
        let done = h.await.unwrap();
        assert!(done.get("errors").is_none(), "{done}");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn with_two_slots_for_the_api_a_client_holds_one(pool: PgPool) {
    // The slots of a client follow the API's (`LUNAWAY_TRANSLATE_AT_ONCE`,
    // 1 to 64): half of them, at least one, so with two or more a client
    // never holds them all.
    let dir = tempfile::tempdir().unwrap();
    seeded(&pool, dir.path()).await;
    let (url, asked, gate) = gated_server().await;
    let mut c = config(Some(url));
    c.translate.at_once = 2;
    c.translate.queue_wait = Duration::from_millis(300);
    let app = behind_proxy(ApiState::new(pool.clone(), c));
    let r1 = review_id(&pool, "r-1").await;
    let r2 = review_id(&pool, "r-2").await;
    let holder = tokio::spawn({
        let app = app.clone();
        async move { gql_from(&app, "203.0.113.9", TRANSLATE, review(r2, "pt")).await }
    });
    asked_at_least(&asked, 1).await;
    let second = gql_from(&app, "203.0.113.9", TRANSLATE, review(r1, "en")).await;
    assert!(busy(&second), "one slot of the two for a client: {second}");
    let other = gql_from(&app, "198.51.100.7", TRANSLATE, review(r1, "en")).await;
    assert!(
        other.get("errors").is_none(),
        "the other slot stays for another client: {other}"
    );
    gate.add_permits(1);
    let done = holder.await.unwrap();
    assert!(done.get("errors").is_none(), "{done}");
}
