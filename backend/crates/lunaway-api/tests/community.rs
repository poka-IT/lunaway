//! Accounts and contributions over HTTP, as the app sees them: signing in
//! with a device key, trust levels, reviews and their moderation, mutes,
//! reports, favourites, recovery, deletion, new places and edits through the
//! conflation worker, and photo uploads.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::Engine;
use chrono::{TimeZone, Utc};
use http_body_util::BodyExt;
use lunaway_api::{ApiConfig, ApiState};
use lunaway_db::PgPool;
use lunaway_domain::{SourceId, community::trust::Thresholds};
use lunaway_ingest::{atout_france, geocode, osm, store::store_complete};
use p256::ecdsa::{SigningKey, signature::Signer};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

const OVERPASS: &[u8] = include_bytes!("../../lunaway-ingest/tests/fixtures/overpass_sample.json");
const ATOUT_CSV: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/atout_france_sample.csv");
const BAN_ANSWER: &[u8] =
    include_bytes!("../../lunaway-ingest/tests/fixtures/ban_answer_sample.csv");
const GPS_JPEG: &[u8] = include_bytes!("../../lunaway-media/tests/fixtures/gps_orientation6.jpg");
const BOMB_PNG: &[u8] = include_bytes!("../../lunaway-media/tests/fixtures/bomb_100000.png");
const WEBP: &[u8] = include_bytes!("../../lunaway-media/tests/fixtures/photo.webp");

fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// A device: a P-256 key the test derives from a small number.
struct Device(SigningKey);

impl Device {
    fn new(n: u8) -> Self {
        let mut d = [0u8; 32];
        d[31] = n;
        d[0] = 1;
        Self(SigningKey::from_slice(&d).unwrap())
    }

    fn jwk(&self) -> String {
        let point = self.0.verifying_key().to_sec1_point(false);
        let bytes = point.as_bytes();
        json!({"kty": "EC", "crv": "P-256", "x": b64(&bytes[1..33]), "y": b64(&bytes[33..65])})
            .to_string()
    }

    fn sign(&self, message: &str) -> String {
        let signature: p256::ecdsa::Signature = self.0.sign(message.as_bytes());
        b64(&signature.to_bytes())
    }
}

/// Every new account starts at level 1 (no age, no confirmation needed),
/// quotas wide enough for a test that creates many accounts.
fn config(media: &std::path::Path) -> ApiConfig {
    let defaults = ApiConfig::default();
    let mut quotas = defaults.quotas;
    quotas.account_creation.count = 1_000;
    quotas.sign_in.count = 1_000;
    quotas.challenge.count = 1_000;
    ApiConfig {
        trust: Thresholds {
            tl1_min_age_days: 0,
            tl1_min_confirmations: 0,
            ..Thresholds::default()
        },
        quotas,
        media: lunaway_api::config::MediaConfig {
            dir: media.to_path_buf(),
            base_url: "https://media.test/".into(),
            ..defaults.media.clone()
        },
        ..defaults
    }
}

fn app(pool: &PgPool, config: ApiConfig) -> axum::Router {
    lunaway_api::router(ApiState::new(pool.clone(), config))
}

async fn send(app: &axum::Router, request: Request<Body>) -> (StatusCode, Value) {
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

/// A GraphQL request, with the session `token` when given.
async fn gql(app: &axum::Router, token: Option<&str>, query: &str, variables: Value) -> Value {
    let mut r = Request::post("/graphql").header("content-type", "application/json");
    if let Some(t) = token {
        r = r.header("authorization", format!("Bearer {t}"));
    }
    let request = r
        .body(Body::from(
            json!({"query": query, "variables": variables}).to_string(),
        ))
        .unwrap();
    send(app, request).await.1
}

fn code(body: &Value) -> &str {
    body["errors"][0]["extensions"]["code"]
        .as_str()
        .unwrap_or_else(|| panic!("no error code in {body}"))
}

fn ok(body: &Value) -> &Value {
    assert!(body.get("errors").is_none(), "unexpected errors: {body}");
    &body["data"]
}

const SIGN_IN: &str = r#"
mutation($jwk: String!, $nonce: String!, $sig: String!) {
  signIn(publicKeyJwk: $jwk, nonce: $nonce, signature: $sig, locale: "en") {
    token expiresAt created account { id pseudonym trustLevel }
  }
}"#;

async fn challenge(app: &axum::Router) -> (String, String) {
    let body = gql(
        app,
        None,
        "mutation { authChallenge { nonce message expiresAt } }",
        json!({}),
    )
    .await;
    let c = &ok(&body)["authChallenge"];
    (
        c["nonce"].as_str().unwrap().to_owned(),
        c["message"].as_str().unwrap().to_owned(),
    )
}

/// Signs in with `device`; returns the session token and the account id.
async fn sign_in(app: &axum::Router, device: &Device) -> (String, Uuid) {
    let (nonce, message) = challenge(app).await;
    let body = gql(
        app,
        None,
        SIGN_IN,
        json!({"jwk": device.jwk(), "nonce": nonce, "sig": device.sign(&message)}),
    )
    .await;
    let s = &ok(&body)["signIn"];
    (
        s["token"].as_str().unwrap().to_owned(),
        s["account"]["id"].as_str().unwrap().parse().unwrap(),
    )
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
    work(pool).await;
}

/// One run of the conflation worker.
/// A run of the worker, then the points layer's publication, which the
/// worker makes at most every few hours and the tests at once.
async fn work(pool: &PgPool) -> lunaway_conflate::RunStats {
    let stats = lunaway_conflate::run(
        pool,
        Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap(),
        None,
    )
    .await
    .unwrap();
    lunaway_conflate::pois::publish_layer(pool, std::time::Duration::ZERO)
        .await
        .unwrap();
    stats
}

/// Two live places of the fixture, by name.
async fn place_named(pool: &PgPool, name: &str) -> Uuid {
    sqlx::query_scalar!(
        "SELECT id FROM places WHERE deleted_at IS NULL AND name = $1",
        name
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_key_signs_in_and_finds_its_account_again(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let phone = Device::new(1);
    let (nonce, message) = challenge(&app).await;
    assert_eq!(message, format!("lunaway-auth:v1:{nonce}"));
    let first = gql(
        &app,
        None,
        SIGN_IN,
        json!({"jwk": phone.jwk(), "nonce": nonce, "sig": phone.sign(&message)}),
    )
    .await;
    let s = &ok(&first)["signIn"];
    assert_eq!(s["created"], true, "an unknown key creates an account");
    let token = s["token"].as_str().unwrap();
    let id = s["account"]["id"].as_str().unwrap();
    assert!(s["account"]["pseudonym"].as_str().unwrap().len() >= 3);

    let reused = gql(
        &app,
        None,
        SIGN_IN,
        json!({"jwk": phone.jwk(), "nonce": nonce, "sig": phone.sign(&message)}),
    )
    .await;
    assert_eq!(code(&reused), "INVALID_INPUT", "a challenge answers once");

    let me = gql(
        &app,
        Some(token),
        "{ myAccount { id trustLevel } }",
        json!({}),
    )
    .await;
    assert_eq!(ok(&me)["myAccount"]["id"], id);

    let (again, again_id) = sign_in(&app, &phone).await;
    assert_ne!(again, token, "each sign-in opens its own session");
    assert_eq!(
        again_id.to_string(),
        id,
        "the same key finds the same account"
    );
    let stored: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM sessions"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 2);
    let hashes: Vec<Vec<u8>> = sqlx::query_scalar!("SELECT token_hash FROM sessions")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert!(
        hashes.iter().all(|h| h != token.as_bytes()),
        "the server keeps the hash of a session, never the token"
    );

    // Someone else's key cannot answer for this one.
    let thief = Device::new(2);
    let (nonce, message) = challenge(&app).await;
    let forged = gql(
        &app,
        None,
        SIGN_IN,
        json!({"jwk": phone.jwk(), "nonce": nonce, "sig": thief.sign(&message)}),
    )
    .await;
    assert_eq!(code(&forged), "UNAUTHENTICATED");
    let (nonce, message) = challenge(&app).await;
    let private = json!({"kty": "EC", "crv": "P-256", "x": "AA", "y": "AA", "d": "AA"});
    let leaked = gql(
        &app,
        None,
        SIGN_IN,
        json!({"jwk": private.to_string(), "nonce": nonce, "sig": phone.sign(&message)}),
    )
    .await;
    assert_eq!(code(&leaked), "INVALID_INPUT");

    let out = gql(&app, Some(token), "mutation { signOut }", json!({})).await;
    assert_eq!(ok(&out)["signOut"], true);
    let after = gql(&app, Some(token), "{ myAccount { id } }", json!({})).await;
    assert_eq!(
        code(&after),
        "UNAUTHENTICATED",
        "a signed-out session is gone"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_bad_token_is_ignored_on_reads_and_refused_on_writes(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let read = gql(
        &app,
        Some("not-a-token"),
        "query($id: UUID!) { place(id: $id) { id reviews { totalCount } photos { id } } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&read)["place"]["reviews"]["totalCount"], 0);
    let forged = lunaway_auth::new_session_token().unwrap().token;
    let unknown = gql(
        &app,
        Some(&forged),
        "query($id: UUID!) { place(id: $id) { id myReview { id } } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(
        ok(&unknown)["place"]["myReview"],
        Value::Null,
        "an unknown session reads as anonymous"
    );
    let rate = "mutation($id: UUID!) { rate(placeId: $id, stars: 4) { id } }";
    for token in [None, Some("not-a-token"), Some(forged.as_str())] {
        let body = gql(&app, token, rate, json!({"id": place})).await;
        assert_eq!(code(&body), "UNAUTHENTICATED", "{token:?}");
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn sign_ins_and_new_accounts_are_limited_per_client(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.quotas = lunaway_api::config::Quotas::default();
    let app = app(&pool, c);
    // Five new accounts an hour from one client.
    for n in 1..=5 {
        sign_in(&app, &Device::new(n)).await;
    }
    let (nonce, message) = challenge(&app).await;
    let sixth = Device::new(6);
    let refused = gql(
        &app,
        None,
        SIGN_IN,
        json!({"jwk": sixth.jwk(), "nonce": nonce, "sig": sixth.sign(&message)}),
    )
    .await;
    assert_eq!(code(&refused), "RATE_LIMITED");
    assert!(
        refused["errors"][0]["extensions"]["retryAfterSeconds"]
            .as_u64()
            .unwrap()
            > 0
    );
    // Known keys still sign in, up to ten sign-ins a minute in all.
    let mut outcomes = Vec::new();
    for n in 1..=5 {
        let (nonce, message) = challenge(&app).await;
        let d = Device::new(n);
        let body = gql(
            &app,
            None,
            SIGN_IN,
            json!({"jwk": d.jwk(), "nonce": nonce, "sig": d.sign(&message)}),
        )
        .await;
        outcomes.push(body.get("errors").is_none());
    }
    assert_eq!(
        outcomes,
        [true, true, true, true, false],
        "the eleventh sign-in of the minute waits"
    );
}

const REVIEWS: &str = r"
query($id: UUID!) {
  place(id: $id) {
    reviews(first: 10) {
      nodes { id sourceId rating text lang authorName authorId authorVehicle visitedAt createdAt }
      endCursor hasNextPage totalCount
    }
  }
}";

const REVIEW: &str = r#"
mutation($id: UUID!, $text: String!) {
  review(placeId: $id, stars: 4, text: $text, visitedOn: "2026-09-20", vehicle: CAMPERVAN, lang: "fr") {
    id status rating
  }
}"#;

#[sqlx::test(migrations = "../../migrations")]
async fn trust_levels_gate_what_an_account_may_write(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.trust = Thresholds::default();
    let app = app(&pool, c);
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, me_id) = sign_in(&app, &Device::new(1)).await;
    let me = gql(
        &app,
        Some(&token),
        "{ myAccount { trustLevel nextLevel { level missing { kind current needed } instead { kind } } } }",
        json!({}),
    )
    .await;
    let me = &ok(&me)["myAccount"];
    assert_eq!(me["trustLevel"], 0);
    assert_eq!(me["nextLevel"]["level"], 1);
    assert_eq!(
        me["nextLevel"]["missing"],
        json!([
            {"kind": "ACCOUNT_AGE_DAYS", "current": 0, "needed": 3},
            {"kind": "CONFIRMATIONS", "current": 0, "needed": 3}
        ])
    );
    assert_eq!(me["nextLevel"]["instead"]["kind"], "SPONSOR");

    let refused = gql(
        &app,
        Some(&token),
        REVIEW,
        json!({"id": place, "text": "Calme, propre, bien placé."}),
    )
    .await;
    assert_eq!(code(&refused), "FORBIDDEN");
    assert_eq!(refused["errors"][0]["extensions"]["requiredLevel"], 1);
    assert_eq!(refused["errors"][0]["extensions"]["level"], 0);
    let rated = gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { rate(placeId: $id, stars: 5) { rating status } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(
        ok(&rated)["rate"],
        json!({"rating": 5, "status": "PUBLISHED"})
    );

    // Three confirmations of one place count as one: a script confirming
    // the same place does not reach level 1.
    for _ in 0..3 {
        let c = gql(
            &app,
            Some(&token),
            "mutation($id: UUID!) { confirm(placeId: $id, status: STILL_OK) { status } }",
            json!({"id": place}),
        )
        .await;
        assert_eq!(ok(&c)["confirm"]["status"], "STILL_OK");
    }
    let me = gql(
        &app,
        Some(&token),
        "{ myAccount { nextLevel { missing { kind current needed } } } }",
        json!({}),
    )
    .await;
    assert_eq!(
        ok(&me)["myAccount"]["nextLevel"]["missing"][1],
        json!({"kind": "CONFIRMATIONS", "current": 1, "needed": 3})
    );

    // A level-2 account sponsors it: level 1 at once.
    let (sponsor, sponsor_id) = sign_in(&app, &Device::new(2)).await;
    let low = gql(
        &app,
        Some(&sponsor),
        "mutation($id: UUID!) { sponsorAccount(accountId: $id) }",
        json!({"id": me_id}),
    )
    .await;
    assert_eq!(code(&low), "FORBIDDEN", "sponsoring needs level 2");
    lunaway_db::accounts::set_granted_level(&pool, sponsor_id, 2)
        .await
        .unwrap();
    let sponsored = gql(
        &app,
        Some(&sponsor),
        "mutation($id: UUID!) { sponsorAccount(accountId: $id) }",
        json!({"id": me_id}),
    )
    .await;
    assert_eq!(ok(&sponsored)["sponsorAccount"], true);
    let review = gql(
        &app,
        Some(&token),
        REVIEW,
        json!({"id": place, "text": "Calme, propre, bien placé."}),
    )
    .await;
    assert_eq!(ok(&review)["review"]["status"], "PUBLISHED");
    let add = gql(
        &app,
        Some(&token),
        r#"mutation { addPlace(input: {kind: PARKING, lat: 47.3, lon: -0.6, details: {name: "Parking du bourg"}}) { status } }"#,
        json!({}),
    )
    .await;
    assert_eq!(code(&add), "FORBIDDEN", "new places need level 2");
    assert_eq!(add["errors"][0]["extensions"]["requiredLevel"], 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn reviews_are_listed_held_muted_reported_and_deleted(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let other = place_named(&pool, "Aire Val-du-Layon").await;
    let (alice, alice_id) = sign_in(&app, &Device::new(1)).await;
    let (bob, _) = sign_in(&app, &Device::new(2)).await;

    let text = "Calme la nuit, eau potable au bout du quai.";
    let written = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": place, "text": text}),
    )
    .await;
    assert_eq!(ok(&written)["review"]["status"], "PUBLISHED");
    let list = gql(&app, None, REVIEWS, json!({"id": place})).await;
    let page = &ok(&list)["place"]["reviews"];
    assert_eq!(page["totalCount"], 1);
    let node = &page["nodes"][0];
    assert_eq!(
        node["sourceId"], "community-cc-by",
        "a review is credited to the source whose licence it is published under"
    );
    assert_eq!(node["text"], text);
    assert_eq!(node["rating"], 4);
    assert_eq!(node["lang"], "fr");
    assert_eq!(node["authorVehicle"], "CAMPERVAN");
    assert_eq!(node["visitedAt"], "2026-09-20");
    assert_eq!(node["authorId"], alice_id.to_string());
    assert!(node["authorName"].as_str().is_some());

    // The same text on another place, and a link, wait for a moderator.
    let pasted = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": other, "text": text}),
    )
    .await;
    assert_eq!(ok(&pasted)["review"]["status"], "PENDING");
    let link = gql(
        &app,
        Some(&bob),
        REVIEW,
        json!({"id": place, "text": "Super endroit, voir www.example.com pour les tarifs"}),
    )
    .await;
    assert_eq!(ok(&link)["review"]["status"], "PENDING");
    let queued: Vec<String> = sqlx::query_scalar!(
        "SELECT reason FROM moderation_queue WHERE kind = 'held_review' ORDER BY created_at"
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(queued, ["repetition", "link"]);
    let list = gql(&app, None, REVIEWS, json!({"id": place})).await;
    assert_eq!(
        ok(&list)["place"]["reviews"]["totalCount"],
        1,
        "a held review is not public"
    );

    // Bob mutes Alice: her review leaves his list, not the others'.
    let mute = gql(
        &app,
        Some(&bob),
        "mutation($id: UUID!) { muteAuthor(accountId: $id) }",
        json!({"id": alice_id}),
    )
    .await;
    assert_eq!(ok(&mute)["muteAuthor"], true);
    let bob_sees = gql(&app, Some(&bob), REVIEWS, json!({"id": place})).await;
    assert_eq!(ok(&bob_sees)["place"]["reviews"]["totalCount"], 0);
    let others_see = gql(&app, None, REVIEWS, json!({"id": place})).await;
    assert_eq!(ok(&others_see)["place"]["reviews"]["totalCount"], 1);
    let muted = gql(
        &app,
        Some(&bob),
        "{ myAccount { mutedAuthors { id } } }",
        json!({}),
    )
    .await;
    assert_eq!(
        ok(&muted)["myAccount"]["mutedAuthors"][0]["id"],
        alice_id.to_string()
    );

    // Three accounts of level 1 report it, one of level 2: hidden.
    let review_id = node["id"].as_str().unwrap().to_owned();
    let report =
        r"mutation($id: UUID!) { reportContent(target: REVIEW, id: $id, reason: OFFENSIVE) }";
    let own = gql(&app, Some(&alice), report, json!({"id": review_id})).await;
    assert_eq!(
        code(&own),
        "NOT_FOUND",
        "an author cannot report their own review"
    );
    for n in 3..=5 {
        let (reporter, reporter_id) = sign_in(&app, &Device::new(n)).await;
        if n == 5 {
            lunaway_db::accounts::set_granted_level(&pool, reporter_id, 2)
                .await
                .unwrap();
        }
        let body = gql(&app, Some(&reporter), report, json!({"id": review_id})).await;
        assert_eq!(ok(&body)["reportContent"], true);
        let again = gql(&app, Some(&reporter), report, json!({"id": review_id})).await;
        assert_eq!(
            ok(&again)["reportContent"],
            true,
            "a second report counts once"
        );
        let visible = gql(&app, None, REVIEWS, json!({"id": place})).await;
        let expected = if n < 5 { 1 } else { 0 };
        assert_eq!(
            ok(&visible)["place"]["reviews"]["totalCount"],
            expected,
            "hidden at the third distinct reporter"
        );
    }

    // Writing it again with clean text does not bring it back: it stays
    // hidden and the new text goes to a moderator.
    let rewritten = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": place, "text": "Texte réécrit, toujours aussi calme la nuit."}),
    )
    .await;
    assert_eq!(ok(&rewritten)["review"]["status"], "HIDDEN");
    let visible = gql(&app, None, REVIEWS, json!({"id": place})).await;
    assert_eq!(ok(&visible)["place"]["reviews"]["totalCount"], 0);
    let reasons: Vec<String> = sqlx::query_scalar!(
        "SELECT reason FROM moderation_queue WHERE target_id = $1 AND status = 'open' ORDER BY kind",
        review_id.parse::<Uuid>().unwrap()
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(reasons, ["rewritten after moderation", "offensive"]);

    // A moderator removes Bob's held review; deleting it afterwards does
    // not erase the removal the trust rules count.
    let bob_entry: Uuid = sqlx::query_scalar!(
        "SELECT q.id FROM moderation_queue q JOIN reviews r ON r.id = q.target_id
         WHERE q.kind = 'held_review' AND r.body LIKE '%example.com%'"
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    lunaway_db::moderation::decide(
        &pool,
        bob_entry,
        lunaway_db::moderation::Decision::Reject,
        None,
    )
    .await
    .unwrap();
    let bob_review = gql(
        &app,
        Some(&bob),
        "query($id: UUID!) { place(id: $id) { myReview { id status } } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&bob_review)["place"]["myReview"]["status"], "REMOVED");
    let bob_review_id = ok(&bob_review)["place"]["myReview"]["id"].clone();
    gql(
        &app,
        Some(&bob),
        "mutation($id: UUID!) { deleteReview(id: $id) }",
        json!({"id": bob_review_id}),
    )
    .await;
    let removals: i32 = sqlx::query_scalar!(
        "SELECT moderation_removals FROM accounts a JOIN sessions s ON s.account_id = a.id
         WHERE s.token_hash = $1",
        &lunaway_auth::token_hash(&bob).unwrap()[..]
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        removals, 1,
        "a removal stays on the account after the author deletes the review"
    );

    // Alice deletes it: its text goes, the hidden state stays with its
    // reports, and writing at the place again does not publish anything.
    let deleted = gql(
        &app,
        Some(&alice),
        "mutation($id: UUID!) { deleteReview(id: $id) }",
        json!({"id": review_id}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteReview"], true);
    let again = gql(
        &app,
        Some(&bob),
        "mutation($id: UUID!) { deleteReview(id: $id) }",
        json!({"id": review_id}),
    )
    .await;
    assert_eq!(code(&again), "NOT_FOUND");
    let stub = sqlx::query!(
        "SELECT body, status FROM reviews WHERE id = $1",
        review_id.parse::<Uuid>().unwrap()
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!((stub.body, stub.status.as_str()), (None, "hidden"));
    let reports: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM content_reports"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(reports, 3, "the reports stay for the moderator");
    let reposted = gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": place, "text": "Calme la nuit, eau potable au bout du quai."}),
    )
    .await;
    assert_eq!(
        ok(&reposted)["review"]["status"],
        "HIDDEN",
        "deleting then posting again does not undo moderation"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn lockout_capable_actions_need_a_recent_signed_sign_in(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let phone = Device::new(1);
    let (old, _) = sign_in(&app, &phone).await;
    // A token stolen an hour ago.
    sqlx::query!("UPDATE sessions SET created_at = now() - interval '1 hour'")
        .execute(&pool)
        .await
        .unwrap();
    for action in [
        "mutation { createRecoveryCode { code } }",
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        "mutation { signOutElsewhere }",
    ] {
        let body = gql(&app, Some(&old), action, json!({})).await;
        assert_eq!(code(&body), "UNAUTHENTICATED", "{action}");
        assert_eq!(body["errors"][0]["extensions"]["reason"], "FRESH_SIGN_IN");
    }
    let still = gql(&app, Some(&old), "{ myAccount { id } }", json!({})).await;
    assert!(
        still.get("errors").is_none(),
        "the old session still reads and contributes"
    );
    // The device signs in again: the new session may end the old one.
    let (fresh, _) = sign_in(&app, &phone).await;
    let ended = gql(
        &app,
        Some(&fresh),
        "mutation { signOutElsewhere }",
        json!({}),
    )
    .await;
    assert_eq!(ok(&ended)["signOutElsewhere"], 1);
    let gone = gql(&app, Some(&old), "{ myAccount { id } }", json!({})).await;
    assert_eq!(code(&gone), "UNAUTHENTICATED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_change_feed_carries_the_community_summary_once_the_worker_ran(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let bbox = json!({"south": 46.8, "west": -2.7, "north": 48.0, "east": 0.0});
    let feed = r"
    query($bbox: BBoxInput!, $since: String) {
      changes(bbox: $bbox, since: $since) {
        places {
          id ratings { sourceId average count } reviewCount lastConfirmedAt
          reportedIssues { kind count } verification municipality
          descriptions { lang text sourceId } externalLinks { sourceId url label }
        }
        cursor
      }
    }";
    let first = gql(&app, None, feed, json!({"bbox": bbox, "since": null})).await;
    let cursor = ok(&first)["changes"]["cursor"].clone();
    let possonniere = ok(&first)["changes"]["places"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == place.to_string())
        .unwrap()
        .clone();
    assert_eq!(possonniere["ratings"], json!([]));
    assert_eq!(possonniere["verification"], "VERIFIED");
    assert!(
        possonniere["externalLinks"]
            .as_array()
            .unwrap()
            .iter()
            .any(|l| l["label"] == "OpenStreetMap"
                && l["url"]
                    .as_str()
                    .unwrap()
                    .starts_with("https://www.openstreetmap.org/")),
        "{possonniere}"
    );

    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let (bob, _) = sign_in(&app, &Device::new(2)).await;
    gql(
        &app,
        Some(&alice),
        REVIEW,
        json!({"id": place, "text": "Calme la nuit, quai propre."}),
    )
    .await;
    gql(
        &app,
        Some(&bob),
        "mutation($id: UUID!) { rate(placeId: $id, stars: 2) { id } }",
        json!({"id": place}),
    )
    .await;
    let confirmed = gql(
        &app,
        Some(&bob),
        r"mutation($id: UUID!) { confirm(placeId: $id, status: STILL_OK) { status createdAt } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&confirmed)["confirm"]["status"], "STILL_OK");
    let with_position = gql(
        &app,
        Some(&alice),
        r"mutation($id: UUID!) {
            confirm(placeId: $id, status: STILL_OK, presence: {lat: 48.85, lon: 2.35}) { status }
          }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(
        code(&with_position),
        "INVALID_INPUT",
        "a confirmation takes no position any more: the argument is gone from the contract"
    );
    let asked = gql(
        &app,
        Some(&alice),
        r"mutation($id: UUID!) { confirm(placeId: $id, status: STILL_OK) { presence } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(
        code(&asked),
        "INVALID_INPUT",
        "nor does it answer a verdict"
    );
    let alice_confirms = gql(
        &app,
        Some(&alice),
        r"mutation($id: UUID!) { confirm(placeId: $id, status: STILL_OK) { status } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&alice_confirms)["confirm"]["status"], "STILL_OK");
    let position = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM information_schema.columns
           WHERE table_name = 'confirmations'
             AND column_name IN ('lat', 'lon', 'geom', 'position', 'presence')"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        position, 0,
        "a confirmation keeps neither a position nor anything derived from one"
    );
    let issue = gql(
        &app,
        Some(&alice),
        r#"mutation($id: UUID!) { reportIssue(placeId: $id, kind: NIGHT_BAN, note: "Arrêté municipal") { kind } }"#,
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&issue)["reportIssue"]["kind"], "NIGHT_BAN");
    let again = gql(
        &app,
        Some(&alice),
        r#"mutation($id: UUID!) { reportIssue(placeId: $id, kind: NIGHT_BAN) { kind } }"#,
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&again)["reportIssue"]["kind"], "NIGHT_BAN");

    let unchanged = gql(&app, None, feed, json!({"bbox": bbox, "since": cursor})).await;
    assert_eq!(
        ok(&unchanged)["changes"]["places"],
        json!([]),
        "the feed moves when the worker has run, not before"
    );
    let stats = work(&pool).await;
    assert_eq!(stats.community_refreshed, 1);
    let after = gql(&app, None, feed, json!({"bbox": bbox, "since": cursor})).await;
    let p = &ok(&after)["changes"]["places"][0];
    assert_eq!(p["id"], place.to_string());
    assert_eq!(
        p["ratings"],
        json!([{"sourceId": "community-cc-by", "average": 3.0, "count": 2}])
    );
    assert_eq!(p["reviewCount"], 1);
    assert_eq!(
        p["reportedIssues"],
        json!([{"kind": "NIGHT_BAN", "count": 1}])
    );
    assert!(p["lastConfirmedAt"].as_str().is_some());
}

#[sqlx::test(migrations = "../../migrations")]
async fn favourites_sync_and_a_device_s_lists_merge_by_name(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let a = place_named(&pool, "Camping municipal du Port").await;
    let b = place_named(&pool, "Aire Val-du-Layon").await;
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let created = gql(
        &app,
        Some(&token),
        r#"mutation { createList(name: "Été 2027") { id name places { placeId } } }"#,
        json!({}),
    )
    .await;
    let list = ok(&created)["createList"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let dup = gql(
        &app,
        Some(&token),
        r#"mutation { createList(name: "Été  2027 ") { id } }"#,
        json!({}),
    )
    .await;
    assert_eq!(code(&dup), "INVALID_INPUT", "names are unique per account");
    let saved = gql(
        &app,
        Some(&token),
        "mutation($l: UUID!, $p: UUID!) { saveToList(listId: $l, placeId: $p) { places { placeId } } }",
        json!({"l": list, "p": a}),
    )
    .await;
    assert_eq!(
        ok(&saved)["saveToList"]["places"][0]["placeId"],
        a.to_string()
    );
    let imported = gql(
        &app,
        Some(&token),
        "mutation($lists: [FavoriteListInput!]!) { importFavorites(lists: $lists) { name places { placeId } } }",
        json!({"lists": [
            {"name": "Été 2027", "placeIds": [a, b, Uuid::now_v7()]},
            {"name": "Hiver", "placeIds": [b]}
        ]}),
    )
    .await;
    let lists = ok(&imported)["importFavorites"].as_array().unwrap();
    let summer = lists.iter().find(|l| l["name"] == "Été 2027").unwrap();
    assert_eq!(
        summer["places"].as_array().unwrap().len(),
        2,
        "merged into the list of the same name, an unknown place skipped"
    );
    assert!(lists.iter().any(|l| l["name"] == "Hiver"));
    let (other, _) = sign_in(&app, &Device::new(2)).await;
    let foreign = gql(
        &app,
        Some(&other),
        "mutation($l: UUID!) { deleteList(id: $l) }",
        json!({"l": list}),
    )
    .await;
    assert_eq!(
        code(&foreign),
        "NOT_FOUND",
        "another account's list does not exist for it"
    );
    let removed = gql(
        &app,
        Some(&token),
        "mutation($l: UUID!, $p: UUID!) { removeFromList(listId: $l, placeId: $p) { places { placeId } } }",
        json!({"l": list, "p": a}),
    )
    .await;
    assert_eq!(
        ok(&removed)["removeFromList"]["places"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let mine = gql(
        &app,
        Some(&token),
        "{ myFavoriteLists { name } }",
        json!({}),
    )
    .await;
    assert_eq!(ok(&mine)["myFavoriteLists"].as_array().unwrap().len(), 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_recovery_code_brings_the_account_to_a_new_device_and_can_delete_it(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, id) = sign_in(&app, &Device::new(1)).await;
    let created = gql(
        &app,
        Some(&token),
        "mutation { createRecoveryCode { code } }",
        json!({}),
    )
    .await;
    let code_text = ok(&created)["createRecoveryCode"]["code"]
        .as_str()
        .unwrap()
        .to_owned();
    let stored: Vec<u8> = sqlx::query_scalar!("SELECT code_hash FROM recovery_codes")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_ne!(
        stored,
        code_text.as_bytes(),
        "the server keeps the hash only"
    );

    let recover = r"
    mutation($code: String!, $jwk: String!, $nonce: String!, $sig: String!) {
      recoverAccount(code: $code, publicKeyJwk: $jwk, nonce: $nonce, signature: $sig) {
        token account { id }
      }
    }";
    let new_phone = Device::new(9);
    let (nonce, message) = challenge(&app).await;
    let typed = code_text.to_lowercase().replace('-', " ");
    let recovered = gql(
        &app,
        None,
        recover,
        json!({"code": typed, "jwk": new_phone.jwk(), "nonce": nonce, "sig": new_phone.sign(&message)}),
    )
    .await;
    let r = &ok(&recovered)["recoverAccount"];
    assert_eq!(
        r["account"]["id"],
        id.to_string(),
        "the code finds its account"
    );
    let (again, again_id) = sign_in(&app, &new_phone).await;
    assert_eq!(again_id, id, "the new key is attached for good");
    let _ = again;

    let wrong = lunaway_auth::RecoveryCode::generate().unwrap().display();
    let (nonce, message) = challenge(&app).await;
    let missed = gql(
        &app,
        None,
        recover,
        json!({"code": wrong, "jwk": Device::new(10).jwk(), "nonce": nonce,
               "sig": Device::new(10).sign(&message)}),
    )
    .await;
    assert_eq!(code(&missed), "NOT_FOUND");

    let deleted = gql(
        &app,
        None,
        "mutation($code: String!) { deleteAccountWithRecoveryCode(code: $code) }",
        json!({"code": code_text}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteAccountWithRecoveryCode"], true);
    let gone = gql(&app, Some(&token), "{ myAccount { id } }", json!({})).await;
    assert_eq!(code(&gone), "UNAUTHENTICATED");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_account_reads_the_date_of_its_recovery_code_on_every_device(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let date = "{ myAccount { recoveryCodeCreatedAt } }";
    let (token, id) = sign_in(&app, &Device::new(1)).await;
    let none = gql(&app, Some(&token), date, json!({})).await;
    assert!(
        ok(&none)["myAccount"]["recoveryCodeCreatedAt"].is_null(),
        "an account that never made a card has no date"
    );

    let made = gql(
        &app,
        Some(&token),
        "mutation { createRecoveryCode { code } }",
        json!({}),
    )
    .await;
    let code_text = ok(&made)["createRecoveryCode"]["code"]
        .as_str()
        .unwrap()
        .to_owned();
    // Back a year, so the replacement below shows as a move of the date.
    sqlx::query!(
        "UPDATE recovery_codes SET created_at = '2025-10-07T08:00:00Z' WHERE account_id = $1",
        id
    )
    .execute(&pool)
    .await
    .unwrap();
    let first = gql(&app, Some(&token), date, json!({})).await;
    assert_eq!(
        ok(&first)["myAccount"]["recoveryCodeCreatedAt"],
        "2025-10-07T08:00:00+00:00"
    );

    // Another account sees only its own: none.
    let (stranger, _) = sign_in(&app, &Device::new(2)).await;
    let theirs = gql(&app, Some(&stranger), date, json!({})).await;
    assert!(ok(&theirs)["myAccount"]["recoveryCodeCreatedAt"].is_null());
    let anonymous = gql(&app, None, date, json!({})).await;
    assert_eq!(code(&anonymous), "UNAUTHENTICATED");

    // The card brings the account to a new phone, which reads the same date.
    let phone = Device::new(9);
    let (nonce, message) = challenge(&app).await;
    let recovered = gql(
        &app,
        None,
        r"mutation($code: String!, $jwk: String!, $nonce: String!, $sig: String!) {
            recoverAccount(code: $code, publicKeyJwk: $jwk, nonce: $nonce, signature: $sig) {
              token account { recoveryCodeCreatedAt }
            }
          }",
        json!({"code": code_text, "jwk": phone.jwk(), "nonce": nonce, "sig": phone.sign(&message)}),
    )
    .await;
    let r = &ok(&recovered)["recoverAccount"];
    assert_eq!(
        r["account"]["recoveryCodeCreatedAt"], "2025-10-07T08:00:00+00:00",
        "every device of the account reads the date of the same card"
    );

    // A new card moves the date.
    let again = gql(
        &app,
        Some(&token),
        "mutation { createRecoveryCode { code } }",
        json!({}),
    )
    .await;
    ok(&again);
    let moved = gql(&app, Some(&token), date, json!({})).await;
    let at: chrono::DateTime<chrono::Utc> = ok(&moved)["myAccount"]["recoveryCodeCreatedAt"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    assert!(
        at > "2026-01-01T00:00:00Z"
            .parse::<chrono::DateTime<chrono::Utc>>()
            .unwrap(),
        "the date is the new card's: {at}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_an_account_keeps_its_published_reviews_without_author(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let other = place_named(&pool, "Aire Val-du-Layon").await;
    let (token, id) = sign_in(&app, &Device::new(1)).await;
    gql(
        &app,
        Some(&token),
        REVIEW,
        json!({"id": place, "text": "Calme la nuit, quai propre."}),
    )
    .await;
    gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { rate(placeId: $id, stars: 3) { id } }",
        json!({"id": other}),
    )
    .await;
    gql(
        &app,
        Some(&token),
        r#"mutation { createList(name: "Favoris") { id } }"#,
        json!({}),
    )
    .await;
    let wrong = gql(
        &app,
        Some(&token),
        r#"mutation { deleteAccount(confirm: "yes") }"#,
        json!({}),
    )
    .await;
    assert_eq!(code(&wrong), "INVALID_INPUT");
    let deleted = gql(
        &app,
        Some(&token),
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        json!({}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteAccount"], true);

    let list = gql(&app, None, REVIEWS, json!({"id": place})).await;
    let node = &ok(&list)["place"]["reviews"]["nodes"][0];
    assert_eq!(node["text"], "Calme la nuit, quai propre.");
    assert_eq!(
        node["authorName"],
        Value::Null,
        "the app shows Deleted account"
    );
    assert_eq!(node["authorId"], Value::Null);
    let left = sqlx::query!(
        r#"SELECT (SELECT count(*) FROM accounts) AS "accounts!",
                  (SELECT count(*) FROM sessions) AS "sessions!",
                  (SELECT count(*) FROM device_keys) AS "keys!",
                  (SELECT count(*) FROM favorite_lists) AS "lists!",
                  (SELECT count(*) FROM reviews WHERE account_id = $1) AS "own!",
                  (SELECT count(*) FROM reviews WHERE body IS NULL) AS "ratings!""#,
        id
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        (
            left.accounts,
            left.sessions,
            left.keys,
            left.lists,
            left.own,
            left.ratings
        ),
        (0, 0, 0, 0, 0, 0),
        "the account, its keys, sessions and lists go; a rating alone goes too"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_new_place_is_conflated_and_verified_by_two_other_accounts(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (author, author_id) = sign_in(&app, &Device::new(1)).await;
    lunaway_db::accounts::set_granted_level(&pool, author_id, 2)
        .await
        .unwrap();
    let add = r#"
    mutation {
      addPlace(input: {kind: NATURE, lat: 47.1, lon: -1.0, details: {
        name: "Clairière des Mauges", overnight: TOLERATED,
        description: {lang: "fr", text: "Au bout du chemin, calme."}
      }}) { id status placeId kind }
    }"#;
    let sent = gql(&app, Some(&author), add, json!({})).await;
    let s = &ok(&sent)["addPlace"];
    assert_eq!(s["status"], "ACCEPTED");
    assert_eq!(s["placeId"], Value::Null, "placed by the worker");
    let stats = work(&pool).await;
    assert_eq!(stats.submissions_applied, 1);
    let mine = gql(
        &app,
        Some(&author),
        "{ myAccount { placeSubmissions { nodes { status placeId } totalCount } } }",
        json!({}),
    )
    .await;
    let applied = &ok(&mine)["myAccount"]["placeSubmissions"]["nodes"][0];
    assert_eq!(applied["status"], "APPLIED");
    let place: Uuid = applied["placeId"].as_str().unwrap().parse().unwrap();
    let read = r"query($id: UUID!) { place(id: $id) { name overnight verification
                  sources { source { id } } descriptions { lang text sourceId } } }";
    let shown = gql(&app, None, read, json!({"id": place})).await;
    let p = &ok(&shown)["place"];
    assert_eq!(p["name"], "Clairière des Mauges");
    assert_eq!(p["overnight"], "TOLERATED");
    assert_eq!(p["sources"][0]["source"]["id"], "community");
    assert_eq!(p["verification"], "TO_VERIFY");
    assert_eq!(
        p["descriptions"],
        json!([{"lang": "fr", "text": "Au bout du chemin, calme.", "sourceId": "community"}])
    );

    let confirm = "mutation($id: UUID!) { confirm(placeId: $id, status: STILL_OK) { status } }";
    gql(&app, Some(&author), confirm, json!({"id": place})).await;
    let (bob, _) = sign_in(&app, &Device::new(2)).await;
    gql(&app, Some(&bob), confirm, json!({"id": place})).await;
    work(&pool).await;
    let shown = gql(&app, None, read, json!({"id": place})).await;
    assert_eq!(
        ok(&shown)["place"]["verification"],
        "TO_VERIFY",
        "the author's own confirmation does not count"
    );
    let (carol, _) = sign_in(&app, &Device::new(3)).await;
    gql(&app, Some(&carol), confirm, json!({"id": place})).await;
    work(&pool).await;
    let shown = gql(&app, None, read, json!({"id": place})).await;
    assert_eq!(ok(&shown)["place"]["verification"], "VERIFIED");
}

const EDIT: &str = r"
mutation($id: UUID!, $name: String!) {
  editPlace(placeId: $id, patch: {name: $name, maxHeightM: 3.2}) { id status placeId }
}";

#[sqlx::test(migrations = "../../migrations")]
async fn an_edit_waits_for_a_moderator_below_level_three_and_lands_on_its_place(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, account) = sign_in(&app, &Device::new(1)).await;
    let proposed = gql(
        &app,
        Some(&token),
        EDIT,
        json!({"id": place, "name": "Port de la Possonnière, quai nord"}),
    )
    .await;
    let s = &ok(&proposed)["editPlace"];
    assert_eq!(s["status"], "PROPOSED");
    assert_eq!(work(&pool).await.submissions_applied, 0, "a proposal waits");
    let entry = lunaway_db::moderation::open(&pool, 10).await.unwrap();
    assert_eq!(entry.len(), 1);
    assert_eq!(entry[0].kind, "place_proposal");
    lunaway_db::moderation::decide(
        &pool,
        entry[0].id,
        lunaway_db::moderation::Decision::Approve,
        Some("checked on the map"),
    )
    .await
    .unwrap();
    let stats = work(&pool).await;
    assert_eq!(stats.submissions_applied, 1);
    let shown = gql(
        &app,
        None,
        "query($id: UUID!) { place(id: $id) { id name sources { source { id } } provenance { field sourceId } } }",
        json!({"id": place}),
    )
    .await;
    let p = &ok(&shown)["place"];
    assert_eq!(
        p["id"],
        place.to_string(),
        "the edit lands on the place it targets"
    );
    assert_eq!(
        p["name"], "Port de la Possonnière, quai nord",
        "the community leads on names"
    );
    let sources: Vec<&str> = p["sources"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["source"]["id"].as_str().unwrap())
        .collect();
    assert!(sources.contains(&"community") && sources.contains(&"osm"));
    let must_link: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM conflation_constraints WHERE kind = 'must_link'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        must_link, 1,
        "the community record is tied to the place it edits"
    );

    // At level 3 the next edit applies without a moderator, into the same
    // community record.
    lunaway_db::accounts::set_granted_level(&pool, account, 3)
        .await
        .unwrap();
    let direct = gql(
        &app,
        Some(&token),
        EDIT,
        json!({"id": place, "name": "Camping municipal du Port"}),
    )
    .await;
    assert_eq!(ok(&direct)["editPlace"]["status"], "ACCEPTED");
    work(&pool).await;
    let community_records: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM source_records WHERE source_id = 'community'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(community_records, 1);
    let revisions: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM place_submissions WHERE place_id = $1 AND status = 'applied'"#,
        place
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(revisions, 2, "every revision is kept");
}

fn upload_request(
    token: Option<&str>,
    place: Uuid,
    file: &[u8],
    content_type: &str,
) -> Request<Body> {
    let boundary = "lunaway-test-boundary";
    let mut body = Vec::new();
    body.extend_from_slice(
        format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"placeId\"\r\n\r\n{place}\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(
        format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"p.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(file);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    let mut r = Request::post("/upload").header(
        "content-type",
        if content_type.is_empty() {
            format!("multipart/form-data; boundary={boundary}")
        } else {
            content_type.to_owned()
        },
    );
    if let Some(t) = token {
        r = r.header("authorization", format!("Bearer {t}"));
    }
    r.body(Body::from(body)).unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_photo_is_stripped_stored_published_and_deleted_with_its_files(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.trust = Thresholds::default();
    let app = app(&pool, c);
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, account) = sign_in(&app, &Device::new(1)).await;

    let (status, body) = send(&app, upload_request(None, place, GPS_JPEG, "")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(code(&body), "UNAUTHENTICATED");
    let (status, body) = send(&app, upload_request(Some(&token), place, GPS_JPEG, "")).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["errors"][0]["extensions"]["requiredLevel"], 1);
    lunaway_db::accounts::set_granted_level(&pool, account, 1)
        .await
        .unwrap();
    let (status, _) = send(
        &app,
        upload_request(Some(&token), place, GPS_JPEG, "application/json"),
    )
    .await;
    assert_eq!(status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    let (status, body) = send(&app, upload_request(Some(&token), place, BOMB_PNG, "")).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(code(&body), "INVALID_INPUT");
    let (status, body) = send(
        &app,
        upload_request(Some(&token), Uuid::now_v7(), GPS_JPEG, ""),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");

    let (status, body) = send(&app, upload_request(Some(&token), place, GPS_JPEG, "")).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let photo = &body["photo"];
    let large = photo["largeUrl"].as_str().unwrap();
    let thumb = photo["thumbUrl"].as_str().unwrap();
    assert!(large.starts_with("https://media.test/photos/") && large.ends_with(".webp"));
    let large_path = media
        .path()
        .join(large.trim_start_matches("https://media.test/"));
    let thumb_path = media
        .path()
        .join(thumb.trim_start_matches("https://media.test/"));
    let stored = std::fs::read(&large_path).unwrap();
    assert!(stored.starts_with(b"RIFF") && &stored[8..12] == b"WEBP");
    for marker in [&b"Exif"[..], b"GPS", b"XMP", b"http://ns.adobe.com"] {
        assert!(
            !stored.windows(marker.len()).any(|w| w == marker),
            "the stored photo carries no metadata ({})",
            String::from_utf8_lossy(marker)
        );
    }
    assert!(thumb_path.exists());

    let (status, body) = send(
        &app,
        upload_request(
            Some(&token),
            place_named(&pool, "Aire Val-du-Layon").await,
            GPS_JPEG,
            "",
        ),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");

    let listed = gql(
        &app,
        None,
        "query($id: UUID!) { place(id: $id) { photos { id sourceId thumbUrl largeUrl thumbhash } coverPhotos { id authorId } photoCount } }",
        json!({"id": place}),
    )
    .await;
    let p = &ok(&listed)["place"];
    assert_eq!(p["photos"][0]["largeUrl"], large);
    assert_eq!(
        p["photos"][0]["sourceId"], "community-cc-by",
        "a photo is published under CC BY 4.0, not the places' ODbL"
    );
    assert_eq!(
        p["coverPhotos"],
        json!([]),
        "the feed's summary waits for the worker"
    );
    work(&pool).await;
    let listed = gql(
        &app,
        None,
        "query($id: UUID!) { place(id: $id) { coverPhotos { id authorId thumbUrl } photoCount } }",
        json!({"id": place}),
    )
    .await;
    let p = &ok(&listed)["place"];
    assert_eq!(p["photoCount"], 1);
    assert_eq!(p["coverPhotos"][0]["authorId"], account.to_string());
    assert_eq!(p["coverPhotos"][0]["thumbUrl"], thumb);

    let deleted = gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { deletePhoto(id: $id) }",
        json!({"id": photo["id"]}),
    )
    .await;
    assert_eq!(ok(&deleted)["deletePhoto"], true);
    assert!(
        !large_path.exists() && !thumb_path.exists(),
        "deleting a photo removes its files"
    );
    let (status, body) = send(&app, upload_request(Some(&token), place, GPS_JPEG, "")).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "a photo its author deleted may be sent again: {body}"
    );

    // A photo a moderator removes is no longer served: its files go.
    let photo_id: Uuid = body["photo"]["id"].as_str().unwrap().parse().unwrap();
    let (reporter, _) = sign_in(&app, &Device::new(2)).await;
    let reported = gql(
        &app,
        Some(&reporter),
        "mutation($id: UUID!) { reportContent(target: PHOTO, id: $id, reason: PRIVACY) }",
        json!({"id": photo_id}),
    )
    .await;
    assert_eq!(ok(&reported)["reportContent"], true);
    let entry = lunaway_db::moderation::open(&pool, 10).await.unwrap();
    let decided = lunaway_db::moderation::decide(
        &pool,
        entry[0].id,
        lunaway_db::moderation::Decision::Reject,
        Some("a licence plate"),
    )
    .await
    .unwrap();
    let lunaway_db::moderation::Decided::Done { files, .. } = decided else {
        panic!("the entry was open");
    };
    assert_eq!(
        files.len(),
        2,
        "the image and its thumbnail are no longer served"
    );
    let (status, body) = send(&app, upload_request(Some(&token), place, GPS_JPEG, "")).await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "a removed photo cannot come back: {body}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_upload_over_the_size_limit_is_refused_before_it_is_read(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.media.max_upload_bytes = 1_000;
    let app = app(&pool, c);
    let (token, _) = sign_in(&app, &Device::new(1)).await;
    let mut r = upload_request(Some(&token), Uuid::now_v7(), &[0u8; 200_000], "");
    r.headers_mut()
        .insert("content-length", "200300".parse().unwrap());
    let (status, body) = send(&app, r).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE, "{body}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn three_new_accounts_cannot_hide_a_review(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.trust = Thresholds::default();
    let app = app(&pool, c);
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (author, author_id) = sign_in(&app, &Device::new(1)).await;
    lunaway_db::accounts::set_granted_level(&pool, author_id, 1)
        .await
        .unwrap();
    let written = gql(
        &app,
        Some(&author),
        REVIEW,
        json!({"id": place, "text": "Calme la nuit, quai propre."}),
    )
    .await;
    let review = ok(&written)["review"]["id"].as_str().unwrap().to_owned();
    let report = r"mutation($id: UUID!) { reportContent(target: REVIEW, id: $id, reason: SPAM) }";
    for n in 2..=4 {
        let (fresh, _) = sign_in(&app, &Device::new(n)).await;
        let body = gql(&app, Some(&fresh), report, json!({"id": review})).await;
        assert_eq!(ok(&body)["reportContent"], true);
    }
    let visible = gql(&app, None, REVIEWS, json!({"id": place})).await;
    assert_eq!(
        ok(&visible)["place"]["reviews"]["totalCount"],
        1,
        "reports of level-0 accounts reach the queue without hiding anything"
    );
    let queued: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM moderation_queue WHERE kind = 'reported_content'"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(queued, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_withdrawn_grant_takes_effect_at_once(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.trust = Thresholds::default();
    let app = app(&pool, c);
    let (moderator, moderator_id) = sign_in(&app, &Device::new(1)).await;
    let (_, other) = sign_in(&app, &Device::new(2)).await;
    let nominate = "mutation($id: UUID!) { nominateAccount(accountId: $id) }";
    lunaway_db::accounts::set_granted_level(&pool, moderator_id, 4)
        .await
        .unwrap();
    let granted = gql(&app, Some(&moderator), nominate, json!({"id": other})).await;
    assert_eq!(ok(&granted)["nominateAccount"], true);
    lunaway_db::accounts::set_granted_level(&pool, moderator_id, 0)
        .await
        .unwrap();
    let withdrawn = gql(&app, Some(&moderator), nominate, json!({"id": other})).await;
    assert_eq!(
        code(&withdrawn),
        "FORBIDDEN",
        "the session does not keep a withdrawn level"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_spent_quota_answers_429_with_retry_after(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.quotas.challenge.count = 1;
    let app = app(&pool, c);
    challenge(&app).await;
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({"query": "mutation { authChallenge { nonce } }"}).to_string(),
        ))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    let retry: u64 = response.headers()["retry-after"]
        .to_str()
        .unwrap()
        .parse()
        .unwrap();
    assert!(retry >= 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_lost_phone_is_detached_at_recovery_or_from_another_device(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let lost = Device::new(1);
    let (lost_token, id) = sign_in(&app, &lost).await;
    let created = gql(
        &app,
        Some(&lost_token),
        "mutation { createRecoveryCode { code } }",
        json!({}),
    )
    .await;
    let code_text = ok(&created)["createRecoveryCode"]["code"]
        .as_str()
        .unwrap()
        .to_owned();
    let second = Device::new(2);
    let (nonce, message) = challenge(&app).await;
    let recovered = gql(
        &app,
        None,
        r"mutation($code: String!, $jwk: String!, $nonce: String!, $sig: String!) {
            recoverAccount(code: $code, publicKeyJwk: $jwk, nonce: $nonce, signature: $sig,
                           revokeOtherDevices: true) { token account { id devices { id current } } }
          }",
        json!({"code": code_text, "jwk": second.jwk(), "nonce": nonce, "sig": second.sign(&message)}),
    )
    .await;
    let r = &ok(&recovered)["recoverAccount"];
    assert_eq!(r["account"]["id"], id.to_string());
    assert_eq!(r["account"]["devices"].as_array().unwrap().len(), 1);
    let gone = gql(&app, Some(&lost_token), "{ myAccount { id } }", json!({})).await;
    assert_eq!(
        code(&gone),
        "UNAUTHENTICATED",
        "the lost phone's sessions end with its key"
    );

    let token = r["token"].as_str().unwrap().to_owned();
    let third = Device::new(3);
    let (nonce, message) = challenge(&app).await;
    let recovered = gql(
        &app,
        None,
        r"mutation($code: String!, $jwk: String!, $nonce: String!, $sig: String!) {
            recoverAccount(code: $code, publicKeyJwk: $jwk, nonce: $nonce, signature: $sig) { token }
          }",
        json!({"code": code_text, "jwk": third.jwk(), "nonce": nonce, "sig": third.sign(&message)}),
    )
    .await;
    let third_token = ok(&recovered)["recoverAccount"]["token"]
        .as_str()
        .unwrap()
        .to_owned();
    let devices = gql(
        &app,
        Some(&token),
        "{ myAccount { devices { id current } } }",
        json!({}),
    )
    .await;
    let list = ok(&devices)["myAccount"]["devices"]
        .as_array()
        .unwrap()
        .clone();
    assert_eq!(list.len(), 2);
    let other = list.iter().find(|d| d["current"] == false).unwrap()["id"].clone();
    let current = list.iter().find(|d| d["current"] == true).unwrap()["id"].clone();
    let refused = gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { revokeDevice(id: $id) }",
        json!({"id": current}),
    )
    .await;
    assert_eq!(code(&refused), "INVALID_INPUT");
    let revoked = gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { revokeDevice(id: $id) }",
        json!({"id": other}),
    )
    .await;
    assert_eq!(ok(&revoked)["revokeDevice"], true);
    let after = gql(&app, Some(&third_token), "{ myAccount { id } }", json!({})).await;
    assert_eq!(code(&after), "UNAUTHENTICATED");
}

/// Reports `target` from three new accounts of level 1, the last one of
/// level 2: enough to hide it.
async fn hide_by_reports(app: &axum::Router, pool: &PgPool, target: &str, id: &Value, first: u8) {
    let report = format!(
        "mutation($id: UUID!) {{ reportContent(target: {target}, id: $id, reason: OFFENSIVE) }}"
    );
    for n in first..first + 3 {
        let (reporter, reporter_id) = sign_in(app, &Device::new(n)).await;
        if n == first + 2 {
            lunaway_db::accounts::set_granted_level(pool, reporter_id, 2)
                .await
                .unwrap();
        }
        let body = gql(app, Some(&reporter), &report, json!({"id": id})).await;
        assert_eq!(ok(&body)["reportContent"], true);
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_author_cannot_shake_off_reports_or_moderation(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (author, author_id) = sign_in(&app, &Device::new(1)).await;
    let written = gql(
        &app,
        Some(&author),
        REVIEW,
        json!({"id": place, "text": "Calme la nuit, quai propre."}),
    )
    .await;
    let review = ok(&written)["review"]["id"].clone();

    // One report, not enough to hide; the author deletes and posts again:
    // the same row, its report and its queue entry are still there.
    let (reporter, _) = sign_in(&app, &Device::new(2)).await;
    gql(
        &app,
        Some(&reporter),
        "mutation($id: UUID!) { reportContent(target: REVIEW, id: $id, reason: SPAM) }",
        json!({"id": review}),
    )
    .await;
    gql(
        &app,
        Some(&author),
        "mutation($id: UUID!) { deleteReview(id: $id) }",
        json!({"id": review}),
    )
    .await;
    let mine = gql(
        &app,
        Some(&author),
        "{ myAccount { reviews { totalCount } } }",
        json!({}),
    )
    .await;
    assert_eq!(
        ok(&mine)["myAccount"]["reviews"]["totalCount"],
        0,
        "gone from the author's list"
    );
    let reposted = gql(
        &app,
        Some(&author),
        REVIEW,
        json!({"id": place, "text": "Toujours calme la nuit."}),
    )
    .await;
    assert_eq!(
        ok(&reposted)["review"]["id"],
        review,
        "the same row comes back"
    );
    let pending = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM content_reports WHERE target_id = $1"#,
        review.as_str().unwrap().parse::<Uuid>().unwrap()
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(pending, 1, "the report still waits for a moderator");

    // Hidden, then approved: the reports are dismissed and the same
    // reporters cannot hide it again.
    hide_by_reports(&app, &pool, "REVIEW", &review, 3).await;
    let visible = gql(&app, None, REVIEWS, json!({"id": place})).await;
    assert_eq!(ok(&visible)["place"]["reviews"]["totalCount"], 0);
    let entry: Uuid = sqlx::query_scalar!(
        "SELECT id FROM moderation_queue WHERE kind = 'reported_content' AND status = 'open'"
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    lunaway_db::moderation::decide(
        &pool,
        entry,
        lunaway_db::moderation::Decision::Approve,
        None,
    )
    .await
    .unwrap();
    for n in 3..6 {
        let again = gql(
            &app,
            Some(&lunaway_test_token(&app, n).await),
            "mutation($id: UUID!) { reportContent(target: REVIEW, id: $id, reason: OFFENSIVE) }",
            json!({"id": review}),
        )
        .await;
        assert_eq!(ok(&again)["reportContent"], true);
    }
    let visible = gql(&app, None, REVIEWS, json!({"id": place})).await;
    assert_eq!(
        ok(&visible)["place"]["reviews"]["totalCount"],
        1,
        "an approved review is not hidden again by the reporters already heard"
    );
    let _ = author_id;
}

/// A session for the test device `n` (signs in again).
async fn lunaway_test_token(app: &axum::Router, n: u8) -> String {
    sign_in(app, &Device::new(n)).await.0
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_hidden_photo_withdrawn_by_its_author_still_counts_when_rejected(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, account) = sign_in(&app, &Device::new(1)).await;
    let (status, body) = send(&app, upload_request(Some(&token), place, GPS_JPEG, "")).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let photo = body["photo"]["id"].clone();
    let large = media.path().join(
        body["photo"]["largeUrl"]
            .as_str()
            .unwrap()
            .trim_start_matches("https://media.test/"),
    );
    hide_by_reports(&app, &pool, "PHOTO", &photo, 2).await;
    let deleted = gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { deletePhoto(id: $id) }",
        json!({"id": photo}),
    )
    .await;
    assert_eq!(ok(&deleted)["deletePhoto"], true);
    assert!(!large.exists(), "the files go as the author asked");
    let entry = lunaway_db::moderation::open(&pool, 10).await.unwrap();
    let approved = lunaway_db::moderation::decide(
        &pool,
        entry[0].id,
        lunaway_db::moderation::Decision::Approve,
        None,
    )
    .await
    .unwrap();
    let lunaway_db::moderation::Decided::Done { place: changed, .. } = approved else {
        panic!("the entry was open");
    };
    assert_eq!(
        changed, None,
        "an approval does not publish a withdrawn photo"
    );
    let status: String = sqlx::query_scalar!(
        "SELECT status FROM photos WHERE id = $1",
        photo.as_str().unwrap().parse::<Uuid>().unwrap()
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(status, "hidden");

    let report = "mutation($id: UUID!) { reportContent(target: PHOTO, id: $id, reason: SPAM) }";
    let (late, _) = sign_in(&app, &Device::new(9)).await;
    let refused = gql(&app, Some(&late), report, json!({"id": photo})).await;
    assert_eq!(
        code(&refused),
        "NOT_FOUND",
        "a withdrawn photo takes no new report"
    );

    // Another photo, hidden then withdrawn, then rejected: the removal
    // counts against its author all the same.
    let (status, body) = send(&app, upload_request(Some(&token), place, WEBP, "")).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let second = body["photo"]["id"].clone();
    hide_by_reports(&app, &pool, "PHOTO", &second, 10).await;
    gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { deletePhoto(id: $id) }",
        json!({"id": second}),
    )
    .await;
    let entry: Uuid = sqlx::query_scalar!(
        "SELECT id FROM moderation_queue WHERE target_id = $1 AND status = 'open'",
        second.as_str().unwrap().parse::<Uuid>().unwrap()
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    lunaway_db::moderation::decide(&pool, entry, lunaway_db::moderation::Decision::Reject, None)
        .await
        .unwrap();
    let removals: i32 = sqlx::query_scalar!(
        "SELECT moderation_removals FROM accounts WHERE id = $1",
        account
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        removals, 1,
        "withdrawing a hidden photo does not escape the removal count"
    );
}

const ADD_VENDING: &str = r#"
mutation($lat: Float!, $lon: Float!, $name: String) {
  addVendingMachine(input: {lat: $lat, lon: $lon, kind: VENDING_PIZZA, name: $name,
                            payment: ["cards"], alwaysOpen: true}) {
    id kind status poiId
  }
}"#;

const CONFIRM_POI: &str = r"
mutation($id: UUID!, $there: Boolean!) {
  confirmPoi(poiId: $id, stillThere: $there) { id poiId stillThere }
}";

#[sqlx::test(migrations = "../../migrations")]
async fn an_account_lists_its_answers_about_points(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let at = json!({"lat": 47.2678, "lon": -0.0696, "name": "Pizza Suzon"});
    ok(&gql(&app, Some(&alice), ADD_VENDING, at).await);
    work(&pool).await;
    let poi: Uuid = sqlx::query_scalar!("SELECT poi_id AS \"id!\" FROM place_submissions")
        .fetch_one(&pool)
        .await
        .unwrap();
    let (bob, _) = sign_in(&app, &Device::new(2)).await;
    let mut answers = Vec::new();
    for there in [true, false] {
        let answer = gql(
            &app,
            Some(&bob),
            CONFIRM_POI,
            json!({"id": poi, "there": there}),
        )
        .await;
        answers.push(ok(&answer)["confirmPoi"]["id"].clone());
    }
    ok(&gql(
        &app,
        Some(&alice),
        CONFIRM_POI,
        json!({"id": poi, "there": true}),
    )
    .await);

    let mine = r"{ myAccount { poiConfirmations(first: 10) {
        nodes { id poiId stillThere createdAt poi { id name kind } } totalCount hasNextPage } } }";
    let listed = gql(&app, Some(&bob), mine, json!({})).await;
    let list = &ok(&listed)["myAccount"]["poiConfirmations"];
    assert_eq!(
        list["totalCount"], 2,
        "the account's own answers, not another's"
    );
    assert_eq!(list["hasNextPage"], false);
    let nodes = list["nodes"].as_array().unwrap();
    assert_eq!(
        nodes.iter().map(|n| n["id"].clone()).collect::<Vec<_>>(),
        [answers[1].clone(), answers[0].clone()],
        "newest first"
    );
    assert_eq!(nodes[0]["stillThere"], false);
    assert_eq!(
        nodes[0]["poi"],
        json!({"id": poi.to_string(), "name": "Pizza Suzon", "kind": "VENDING_PIZZA"}),
        "the answer names its point, so the app lists it as it is"
    );

    let first_page = gql(
        &app,
        Some(&bob),
        "{ myAccount { poiConfirmations(first: 1) { nodes { id } endCursor hasNextPage } } }",
        json!({}),
    )
    .await;
    let page = &ok(&first_page)["myAccount"]["poiConfirmations"];
    assert_eq!(page["hasNextPage"], true);
    let next = gql(
        &app,
        Some(&bob),
        "query($after: String) { myAccount { poiConfirmations(first: 1, after: $after) { nodes { id } } } }",
        json!({"after": page["endCursor"]}),
    )
    .await;
    assert_eq!(
        ok(&next)["myAccount"]["poiConfirmations"]["nodes"][0]["id"],
        answers[0],
        "the cursor continues after the first page"
    );

    ok(&gql(
        &app,
        Some(&bob),
        "mutation($id: UUID!) { deletePoiConfirmation(id: $id) }",
        json!({"id": answers[1]}),
    )
    .await);
    let after = gql(&app, Some(&bob), mine, json!({})).await;
    assert_eq!(
        ok(&after)["myAccount"]["poiConfirmations"]["totalCount"],
        1,
        "a deleted answer leaves the list"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_vending_machine_added_in_two_gestures_is_confirmed_or_hidden(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let mut strict = config(media.path());
    strict.trust = Thresholds::default();
    let app_strict = app(&pool, strict);
    let (newcomer, _) = sign_in(&app_strict, &Device::new(9)).await;
    let at = json!({"lat": 47.2678, "lon": -0.0696, "name": "Pizza Suzon"});
    let refused = gql(&app_strict, Some(&newcomer), ADD_VENDING, at.clone()).await;
    assert_eq!(code(&refused), "FORBIDDEN", "level 1 adds a point");
    assert_eq!(refused["errors"][0]["extensions"]["requiredLevel"], 1);

    let app = app(&pool, config(media.path()));
    let (alice, _) = sign_in(&app, &Device::new(1)).await;
    let added = gql(&app, Some(&alice), ADD_VENDING, at.clone()).await;
    let s = &ok(&added)["addVendingMachine"];
    assert_eq!(s["kind"], "POI");
    assert_eq!(s["status"], "ACCEPTED");
    assert_eq!(s["poiId"], Value::Null, "the worker writes it");
    let stats = work(&pool).await;
    assert_eq!(stats.poi_community.vending_added, 1);
    let mine = gql(
        &app,
        Some(&alice),
        "{ myAccount { placeSubmissions { nodes { kind status poiId } } } }",
        json!({}),
    )
    .await;
    let sub = &ok(&mine)["myAccount"]["placeSubmissions"]["nodes"][0];
    assert_eq!(sub["status"], "APPLIED");
    let poi = sub["poiId"].as_str().unwrap().to_owned();
    let shown = gql(
        &app,
        None,
        "query($id: UUID!) { poi(id: $id) { kind name alwaysOpen payment products sources { sourceId } } }",
        json!({"id": poi}),
    )
    .await;
    assert_eq!(
        ok(&shown)["poi"],
        json!({
            "kind": "VENDING_PIZZA", "name": "Pizza Suzon", "alwaysOpen": true,
            "payment": ["cards"], "products": ["pizza"],
            "sources": [{"sourceId": "community"}]
        })
    );

    let twice = gql(&app, Some(&alice), ADD_VENDING, at.clone()).await;
    assert_eq!(code(&twice), "INVALID_INPUT");
    assert_eq!(
        twice["errors"][0]["extensions"]["existingId"], poi,
        "the app offers to confirm the machine already there"
    );
    let not_vending = gql(
        &app,
        Some(&alice),
        r"mutation { addVendingMachine(input: {lat: 47.0, lon: -0.5, kind: BAKERY}) { id } }",
        json!({}),
    )
    .await;
    assert_eq!(code(&not_vending), "INVALID_INPUT");

    let near =
        r"{ nearbyPois(at: {lat: 47.2678, lon: -0.0696}, categories: [VENDING]) { pois { id } } }";
    let shown_near = gql(&app, None, near, json!({})).await;
    assert_eq!(ok(&shown_near)["nearbyPois"][0]["pois"][0]["id"], poi);
    // The tile of z14 that holds it: lon -0.0696, lat 47.2678.
    let tile_uri = |v: i64| format!("/poi/{v}/14/8188/5744.mvt");
    let version = |body: &Value| ok(body)["poiLayer"]["version"].as_i64().unwrap();
    let v = version(&gql(&app, None, "{ poiLayer { version } }", json!({})).await);
    let (status, _) = send(&app, Request::get(tile_uri(v)).body(Body::empty()).unwrap()).await;
    assert_eq!(status, StatusCode::OK, "the machine is on its tile");

    // Three accounts say it is gone: hidden, and queued for a moderator.
    for n in 2..=4 {
        let (t, _) = sign_in(&app, &Device::new(n)).await;
        let answer = gql(
            &app,
            Some(&t),
            CONFIRM_POI,
            json!({"id": poi, "there": false}),
        )
        .await;
        assert_eq!(ok(&answer)["confirmPoi"]["stillThere"], false);
    }
    let layer_before = gql(&app, None, "{ poiLayer { version } }", json!({})).await;
    work(&pool).await;
    let hidden = gql(
        &app,
        None,
        "query($id: UUID!) { poi(id: $id) { id } }",
        json!({"id": poi}),
    )
    .await;
    assert_eq!(ok(&hidden)["poi"], Value::Null);
    let hidden_near = gql(&app, None, near, json!({})).await;
    assert_eq!(
        ok(&hidden_near)["nearbyPois"][0]["pois"],
        json!([]),
        "a hidden point is not around anything"
    );
    let v = version(&gql(&app, None, "{ poiLayer { version } }", json!({})).await);
    // The tile endpoint reads a newer version named in a URL at most every
    // 200 ms (`tiles::VERSION_RECHECK`); the steps above can take less.
    tokio::time::sleep(std::time::Duration::from_millis(250)).await;
    let (status, _) = send(&app, Request::get(tile_uri(v)).body(Body::empty()).unwrap()).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "nor on any tile");
    let layer_after = gql(&app, None, "{ poiLayer { version } }", json!({})).await;
    assert!(
        ok(&layer_after)["poiLayer"]["version"].as_i64()
            > ok(&layer_before)["poiLayer"]["version"].as_i64(),
        "the tiles that showed it get a new URL"
    );
    let queue = lunaway_db::moderation::open(&pool, 10).await.unwrap();
    let check = queue
        .iter()
        .find(|e| e.kind == "poi_check")
        .expect("a check");
    assert!(check.excerpt.as_deref().unwrap().contains("Pizza Suzon"));

    // A moderator finds it there: the "gone" answers are set aside.
    lunaway_db::moderation::decide(
        &pool,
        check.id,
        lunaway_db::moderation::Decision::Approve,
        Some("seen on 6 October"),
    )
    .await
    .unwrap();
    work(&pool).await;
    let back = gql(
        &app,
        None,
        "query($id: UUID!) { poi(id: $id) { id } }",
        json!({"id": poi}),
    )
    .await;
    assert_eq!(ok(&back)["poi"]["id"], poi);

    let unknown = gql(
        &app,
        Some(&alice),
        CONFIRM_POI,
        json!({"id": "0192a0e6-0000-7000-8000-000000000000", "there": true}),
    )
    .await;
    assert_eq!(code(&unknown), "NOT_FOUND");
    let anonymous = gql(&app, None, CONFIRM_POI, json!({"id": poi, "there": true})).await;
    assert_eq!(code(&anonymous), "UNAUTHENTICATED");
}

/// `config` with the account deletion journal in `journal`.
fn journaled(media: &std::path::Path, journal: &std::path::Path) -> ApiConfig {
    let mut c = config(media);
    c.keeping.deletion_journal = Some(journal.to_path_buf());
    c
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_deletion_is_journaled_and_replayed_after_a_restore(pool: PgPool) {
    use lunaway_db::deletions::{self, DeletionJournal};
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let journal_dir = dir.path().join("account-deletions");
    let app = app(&pool, journaled(media.path(), &journal_dir));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let other = place_named(&pool, "Aire Val-du-Layon").await;

    let journal = DeletionJournal::new(&journal_dir);
    // The API's start on a new data volume leaves an empty file for the
    // day: still a journal that was not put back.
    journal.check_writable(Utc::now()).unwrap();
    assert!(
        matches!(
            deletions::replay(&pool, &journal, false, false).await,
            Err(deletions::DeleteError::Journal(
                deletions::JournalError::Empty(_)
            ))
        ),
        "a journal not put back after a restore is refused, not read as no deletion"
    );
    let empty = deletions::replay(&pool, &journal, false, true)
        .await
        .expect("an operator who knows the journal is empty says so");
    assert_eq!((empty.accounts, empty.deleted), (0, 0));
    let (alice, alice_id) = sign_in(&app, &Device::new(1)).await;
    let deleted = gql(
        &app,
        Some(&alice),
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        json!({}),
    )
    .await;
    assert_eq!(ok(&deleted)["deleteAccount"], true);
    let read = journal.read().unwrap();
    assert_eq!(
        read.entries.iter().map(|e| e.account).collect::<Vec<_>>(),
        [alice_id],
        "the deletion is in the journal, outside the database"
    );

    // Bob writes a review and a rating, then a backup taken before his
    // deletion is restored: the database holds him again, the journal
    // says he is gone.
    let (bob, bob_id) = sign_in(&app, &Device::new(2)).await;
    gql(
        &app,
        Some(&bob),
        REVIEW,
        json!({"id": place, "text": "Calme la nuit, quai propre."}),
    )
    .await;
    gql(
        &app,
        Some(&bob),
        "mutation($id: UUID!) { rate(placeId: $id, stars: 3) { id } }",
        json!({"id": other}),
    )
    .await;
    journal.record(bob_id, Utc::now()).await.unwrap();
    let dry = deletions::replay(&pool, &journal, true, false)
        .await
        .unwrap();
    assert_eq!(
        (dry.accounts, dry.deleted),
        (2, 1),
        "a dry run counts the accounts to delete again"
    );
    assert!(
        lunaway_db::accounts::account(&pool, bob_id)
            .await
            .unwrap()
            .is_some()
    );
    let replayed = deletions::replay(&pool, &journal, false, false)
        .await
        .unwrap();
    assert_eq!(
        (replayed.accounts, replayed.deleted, replayed.unreadable),
        (2, 1, 0)
    );
    assert!(
        lunaway_db::accounts::account(&pool, bob_id)
            .await
            .unwrap()
            .is_none(),
        "a restored backup never brings a deleted account back"
    );
    let list = gql(&app, None, REVIEWS, json!({"id": place})).await;
    let node = &ok(&list)["place"]["reviews"]["nodes"][0];
    assert_eq!(
        (&node["text"], &node["authorId"]),
        (&json!("Calme la nuit, quai propre."), &Value::Null),
        "the replay deletes as deleteAccount does: a published review stays without author"
    );
    let ratings: i64 =
        sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM reviews WHERE body IS NULL"#)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(ratings, 0, "a rating alone goes with the account");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_deletion_that_cannot_be_journaled_is_refused(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let dir = tempfile::tempdir().unwrap();
    // A file where the journal's directory should be: nothing can be
    // written under it.
    let blocked = dir.path().join("not-a-directory");
    std::fs::write(&blocked, "x").unwrap();
    let app = app(&pool, journaled(media.path(), &blocked));
    let (token, id) = sign_in(&app, &Device::new(1)).await;
    let refused = gql(
        &app,
        Some(&token),
        r#"mutation { deleteAccount(confirm: "DELETE") }"#,
        json!({}),
    )
    .await;
    assert_eq!(code(&refused), "UNAVAILABLE");
    assert!(
        lunaway_db::accounts::account(&pool, id)
            .await
            .unwrap()
            .is_some(),
        "a deletion missing from the journal would come back with a restore: none is made"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn sign_in_can_refuse_a_key_without_account(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let strict = r#"
    mutation($jwk: String!, $nonce: String!, $sig: String!) {
      signIn(publicKeyJwk: $jwk, nonce: $nonce, signature: $sig, createIfUnknown: false) {
        created account { id }
      }
    }"#;
    let phone = Device::new(7);
    let (nonce, message) = challenge(&app).await;
    let refused = gql(
        &app,
        None,
        strict,
        json!({"jwk": phone.jwk(), "nonce": nonce, "sig": phone.sign(&message)}),
    )
    .await;
    assert_eq!(code(&refused), "NOT_FOUND");
    assert_eq!(
        refused["errors"][0]["extensions"]["reason"], "UNKNOWN_KEY",
        "the app tells an unknown key (its account was deleted or detached elsewhere) from \
         any other missing target"
    );
    let accounts: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM accounts"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(accounts, 0, "no account is created, not even for a moment");

    let (_, id) = sign_in(&app, &phone).await;
    let (nonce, message) = challenge(&app).await;
    let again = gql(
        &app,
        None,
        strict,
        json!({"jwk": phone.jwk(), "nonce": nonce, "sig": phone.sign(&message)}),
    )
    .await;
    let s = &ok(&again)["signIn"];
    assert_eq!(
        (&s["created"], &s["account"]["id"]),
        (&json!(false), &json!(id.to_string())),
        "a known key signs in as before"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_contribution_sent_again_with_its_key_is_stored_once(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let mut c = config(media.path());
    c.quotas.confirmation.count = 2;
    let app = app(&pool, c);
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, account) = sign_in(&app, &Device::new(1)).await;
    let confirm = r"
    mutation($id: UUID!, $key: String) {
      confirm(placeId: $id, status: STILL_OK, idempotencyKey: $key) { id }
    }";
    let key = "01a11084-bd6e-7207-a61e-51d1c09f66dd";
    let first = gql(
        &app,
        Some(&token),
        confirm,
        json!({"id": place, "key": key}),
    )
    .await;
    let again = gql(
        &app,
        Some(&token),
        confirm,
        json!({"id": place, "key": key}),
    )
    .await;
    assert_eq!(
        ok(&again)["confirm"]["id"],
        ok(&first)["confirm"]["id"],
        "the answer a weak network lost is given again"
    );
    let rows = || async {
        sqlx::query!(
            r#"SELECT (SELECT count(*) FROM confirmations) AS "confirmations!",
                      (SELECT count(*) FROM issue_reports) AS "issues!",
                      (SELECT count(*) FROM place_submissions) AS "submissions!",
                      (SELECT count(*) FROM road_event_reports) AS "road_reports!""#
        )
        .fetch_one(&pool)
        .await
        .unwrap()
    };
    assert_eq!(rows().await.confirmations, 1, "stored once");
    let other = gql(
        &app,
        Some(&token),
        r"mutation($id: UUID!, $key: String) {
            confirm(placeId: $id, status: CLOSED, idempotencyKey: $key) { id } }",
        json!({"id": place, "key": key}),
    )
    .await;
    assert_eq!(
        code(&other),
        "INVALID_INPUT",
        "a key reused for another request is a client error"
    );
    // A replay took no quota: the second of two confirmations a day still
    // goes through, the third is refused.
    let second = gql(
        &app,
        Some(&token),
        confirm,
        json!({"id": place, "key": "outbox-entry-2"}),
    )
    .await;
    ok(&second);
    let third = gql(
        &app,
        Some(&token),
        confirm,
        json!({"id": place, "key": "outbox-entry-3"}),
    )
    .await;
    assert_eq!(code(&third), "RATE_LIMITED");

    // The same key from another account is that account's own.
    let (bob, _) = sign_in(&app, &Device::new(2)).await;
    let bobs = gql(&app, Some(&bob), confirm, json!({"id": place, "key": key})).await;
    assert_ne!(ok(&bobs)["confirm"]["id"], ok(&first)["confirm"]["id"]);

    // Two copies sent at once: one is stored, both answer with it.
    let issue = r"
    mutation($id: UUID!, $key: String) {
      reportIssue(placeId: $id, kind: NIGHT_BAN, idempotencyKey: $key) { id }
    }";
    let vars = json!({"id": place, "key": "issue-twins-1"});
    let (a, b) = tokio::join!(
        gql(&app, Some(&token), issue, vars.clone()),
        gql(&app, Some(&token), issue, vars.clone())
    );
    assert_eq!(ok(&a)["reportIssue"]["id"], ok(&b)["reportIssue"]["id"]);
    assert_eq!(rows().await.issues, 1, "twins race to one row");

    // A place edit and a road report, sent twice.
    lunaway_db::accounts::set_granted_level(&pool, account, 3)
        .await
        .unwrap();
    let edit = r#"
    mutation($id: UUID!, $key: String) {
      editPlace(placeId: $id, patch: {priceParkingEur: 8}, idempotencyKey: $key) { id status }
    }"#;
    let vars = json!({"id": place, "key": "edit-key-0001"});
    let e1 = gql(&app, Some(&token), edit, vars.clone()).await;
    let e2 = gql(&app, Some(&token), edit, vars).await;
    assert_eq!(ok(&e1)["editPlace"]["id"], ok(&e2)["editPlace"]["id"]);
    assert_eq!(rows().await.submissions, 1);
    let road = r"
    mutation($key: String) {
      reportRoadEvent(input: {kind: CLOSURE, lat: 47.3, lon: -0.6, headingDeg: 90},
                      idempotencyKey: $key) { reportId eventId confidence }
    }";
    let r1 = gql(&app, Some(&token), road, json!({"key": "road-key-0001"})).await;
    let r2 = gql(&app, Some(&token), road, json!({"key": "road-key-0001"})).await;
    assert_eq!(
        ok(&r1)["reportRoadEvent"]["reportId"],
        ok(&r2)["reportRoadEvent"]["reportId"]
    );
    assert_eq!(rows().await.road_reports, 1);
    let bad = gql(&app, Some(&token), road, json!({"key": "short"})).await;
    assert_eq!(code(&bad), "INVALID_INPUT");

    let keys: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM idempotency_keys"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(keys, 6);
    let soon = Utc::now() + chrono::Duration::seconds(1);
    let road_only =
        lunaway_db::idempotency::purge(&pool, Utc::now() - chrono::Duration::days(1), soon)
            .await
            .unwrap();
    assert_eq!(
        road_only, 1,
        "a road report's key goes with the report, sooner"
    );
    let purged = lunaway_db::idempotency::purge(&pool, soon, soon)
        .await
        .unwrap();
    assert_eq!(purged, 5, "keys answer for a bounded time");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_key_goes_with_what_it_made(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, account) = sign_in(&app, &Device::new(1)).await;
    lunaway_db::accounts::set_granted_level(&pool, account, 3)
        .await
        .unwrap();
    let confirm = r"
    mutation($id: UUID!, $key: String) {
      confirm(placeId: $id, status: STILL_OK, idempotencyKey: $key) { id }
    }";
    let vars = json!({"id": place, "key": "confirm-key-0001"});
    let confirmed = gql(&app, Some(&token), confirm, vars.clone()).await;
    let confirmed = ok(&confirmed)["confirm"]["id"].clone();
    let issue = gql(
        &app,
        Some(&token),
        r"mutation($id: UUID!, $key: String) {
            reportIssue(placeId: $id, kind: NIGHT_BAN, idempotencyKey: $key) { id } }",
        json!({"id": place, "key": "issue-key-0001"}),
    )
    .await;
    let issue = ok(&issue)["reportIssue"]["id"].clone();
    let edit = gql(
        &app,
        Some(&token),
        r"mutation($id: UUID!, $key: String) {
            editPlace(placeId: $id, patch: {priceParkingEur: 8}, idempotencyKey: $key) { id } }",
        json!({"id": place, "key": "edit-key-0001"}),
    )
    .await;
    let edit = ok(&edit)["editPlace"]["id"].clone();
    let keys = || async {
        sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM idempotency_keys"#)
            .fetch_one(&pool)
            .await
            .unwrap()
    };
    assert_eq!(keys().await, 3);

    // Kept, a key would tell which place the account confirmed, reported
    // or edited after the author deleted it (the request's hash).
    for (mutation, id) in [
        ("deleteConfirmation", &confirmed),
        ("deleteIssueReport", &issue),
        ("deletePlaceSubmission", &edit),
    ] {
        let deleted = gql(
            &app,
            Some(&token),
            &format!("mutation($id: UUID!) {{ {mutation}(id: $id) }}"),
            json!({"id": id}),
        )
        .await;
        assert_eq!(ok(&deleted)[mutation], true, "{mutation}");
    }
    assert_eq!(keys().await, 0, "no key outlives the contribution it names");
    let again = gql(&app, Some(&token), confirm, vars).await;
    assert_ne!(
        ok(&again)["confirm"]["id"],
        confirmed,
        "the same request after a deletion is a new contribution"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_new_place_sent_again_with_its_key_is_added_once(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (token, account) = sign_in(&app, &Device::new(1)).await;
    lunaway_db::accounts::set_granted_level(&pool, account, 2)
        .await
        .unwrap();
    let add = r#"
    mutation($key: String) {
      addPlace(input: {kind: NATURE, lat: 47.1, lon: -1.0, details: {name: "Clairière"}},
               idempotencyKey: $key) { id status }
    }"#;
    let a = gql(&app, Some(&token), add, json!({"key": "new-place-0001"})).await;
    let b = gql(&app, Some(&token), add, json!({"key": "new-place-0001"})).await;
    assert_eq!(ok(&a)["addPlace"]["id"], ok(&b)["addPlace"]["id"]);
    let without = gql(&app, Some(&token), add, json!({"key": null})).await;
    assert_ne!(
        ok(&without)["addPlace"]["id"],
        ok(&a)["addPlace"]["id"],
        "without a key, each request is a new one, as before"
    );
    let stored: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM place_submissions"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_edit_clears_what_the_community_stated(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Aire Val-du-Layon").await;
    let (token, account) = sign_in(&app, &Device::new(1)).await;
    lunaway_db::accounts::set_granted_level(&pool, account, 3)
        .await
        .unwrap();
    // The community leads on prices and descriptions: what it states is
    // what the place shows.
    let stated = gql(
        &app,
        Some(&token),
        r#"mutation($id: UUID!) { editPlace(placeId: $id, patch: {
            priceParkingEur: 12, description: {lang: "fr", text: "Calme."}
        }) { status } }"#,
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&stated)["editPlace"]["status"], "ACCEPTED");
    work(&pool).await;
    let read = r"query($id: UUID!) { place(id: $id) {
        priceParkingEur descriptions { sourceId } provenance { field sourceId } } }";
    let community_fields = |body: &Value| -> Vec<String> {
        ok(body)["place"]["provenance"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|p| p["sourceId"] == "community")
            .map(|p| p["field"].as_str().unwrap().to_owned())
            .collect()
    };
    let before = gql(&app, None, read, json!({"id": place})).await;
    assert_eq!(ok(&before)["place"]["priceParkingEur"], 12.0);
    assert!(community_fields(&before).contains(&"priceParkingEur".to_owned()));

    let both = gql(
        &app,
        Some(&token),
        r"mutation($id: UUID!) { editPlace(placeId: $id,
            patch: {priceParkingEur: 10, clear: [PRICE_PARKING]}) { status } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(code(&both), "INVALID_INPUT", "a value and a clear at once");
    let in_new_place = gql(
        &app,
        Some(&token),
        r#"mutation { addPlace(input: {kind: NATURE, lat: 47.1, lon: -1.0,
            details: {name: "Clairière", clear: [WEBSITE]}}) { status } }"#,
        json!({}),
    )
    .await;
    assert_eq!(
        code(&in_new_place),
        "INVALID_INPUT",
        "a new place clears nothing"
    );

    let cleared = gql(
        &app,
        Some(&token),
        r"mutation($id: UUID!) { editPlace(placeId: $id,
            patch: {clear: [PRICE_PARKING, DESCRIPTION]}) { status } }",
        json!({"id": place}),
    )
    .await;
    assert_eq!(ok(&cleared)["editPlace"]["status"], "ACCEPTED");
    work(&pool).await;
    let after = gql(&app, None, read, json!({"id": place})).await;
    let fields = community_fields(&after);
    assert!(
        !fields.contains(&"priceParkingEur".to_owned())
            && !fields.contains(&"description".to_owned()),
        "the community no longer states what it cleared: {fields:?}"
    );
    assert_ne!(
        ok(&after)["place"]["priceParkingEur"],
        12.0,
        "the wrong price is gone"
    );
    assert!(
        ok(&after)["place"]["descriptions"]
            .as_array()
            .unwrap()
            .iter()
            .all(|d| d["sourceId"] != "community")
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_operator_finds_deletes_and_cleans_up_after_an_account(pool: PgPool) {
    use lunaway_db::{accounts, deletions, moderation};
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let place = place_named(&pool, "Camping municipal du Port").await;
    let (token, id) = sign_in(&app, &Device::new(1)).await;
    let confirmed = gql(
        &app,
        Some(&token),
        "mutation($id: UUID!) { confirm(placeId: $id, status: STILL_OK) { id } }",
        json!({"id": place}),
    )
    .await;
    let confirmation: Uuid = ok(&confirmed)["confirm"]["id"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    let name = accounts::account(&pool, id)
        .await
        .unwrap()
        .unwrap()
        .pseudonym;

    let found = accounts::find_by_pseudonym(&pool, &name.to_uppercase())
        .await
        .unwrap();
    assert_eq!(found.len(), 1, "found by its pseudonym, case aside");
    assert_eq!((found[0].account.id, found[0].confirmations), (id, 1));

    let journal = deletions::DeletionJournal::new(dir.path());
    let deleted = deletions::delete_recorded(&pool, Some(&journal), id)
        .await
        .unwrap();
    assert!(deleted.is_some());
    assert_eq!(journal.read().unwrap().entries.len(), 1);
    // Exactly as deleteAccount: the confirmation stays, without author.
    let listed = moderation::confirmations_of_place(&pool, place, 10)
        .await
        .unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(
        (listed[0].id, listed[0].author.clone()),
        (confirmation, None)
    );

    // A test left on a real place: the operator removes it by id.
    assert_eq!(
        moderation::remove_confirmation(&pool, confirmation)
            .await
            .unwrap(),
        Some(place)
    );
    assert!(
        moderation::confirmations_of_place(&pool, place, 10)
            .await
            .unwrap()
            .is_empty()
    );
    let queued: i64 = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM place_refresh_queue WHERE place_id = $1"#,
        place
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(queued, 1, "the worker computes \"last confirmed\" again");
    assert_eq!(
        moderation::remove_confirmation(&pool, confirmation)
            .await
            .unwrap(),
        None
    );
}

/// A place added on a spot taken down, under the takedown secret: the
/// submission is applied, the place waits for a moderator with its author
/// named, and goes live once released.
#[sqlx::test(migrations = "../../migrations")]
async fn a_place_added_on_a_spot_taken_down_waits_for_a_moderator(pool: PgPool) {
    use lunaway_db::moderation::{self, Decision};
    use lunaway_domain::takedown::{TakedownCode, TakedownKey};
    seeded(&pool).await;
    let key = TakedownKey::new(&[9; 32]).unwrap();
    let port = place_named(&pool, "Camping municipal du Port").await;
    let spot = sqlx::query!(
        r#"SELECT ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!" FROM places WHERE id = $1"#,
        port
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let journal = tempfile::tempdir().unwrap();
    let done = lunaway_conflate::takedown::take_down(
        &pool,
        &key,
        &lunaway_db::takedown_journal::TakedownJournal::new(journal.path()),
        lunaway_conflate::takedown::Request {
            place: port,
            code: TakedownCode::PrivateHome,
            with_nearby: false,
        },
        Utc::now(),
    )
    .await
    .unwrap();
    assert!(matches!(done, lunaway_db::takedowns::TakeDown::Done(_)));

    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let (author, author_id) = sign_in(&app, &Device::new(1)).await;
    lunaway_db::accounts::set_granted_level(&pool, author_id, 2)
        .await
        .unwrap();
    let add = r#"mutation($lat: Float!, $lon: Float!) {
      addPlace(input: {kind: CAMPSITE, lat: $lat, lon: $lon, details: {name: "Camping du Port"}})
      { status } }"#;
    let sent = gql(
        &app,
        Some(&author),
        add,
        json!({"lat": spot.lat + 0.0002, "lon": spot.lon}),
    )
    .await;
    assert_eq!(ok(&sent)["addPlace"]["status"], "ACCEPTED");
    let at = Utc.with_ymd_and_hms(2026, 11, 2, 12, 0, 0).unwrap();
    let stats = lunaway_conflate::run(&pool, at, Some(&key)).await.unwrap();
    assert_eq!(
        (
            stats.submissions_applied,
            stats.created,
            stats.held_near_takedown
        ),
        (1, 0, 1),
        "a spot taken down does not come back through the community"
    );
    let mine = "{ myAccount { placeSubmissions { nodes { status placeId } } } }";
    let s = gql(&app, Some(&author), mine, json!({})).await;
    assert_eq!(
        ok(&s)["myAccount"]["placeSubmissions"]["nodes"][0],
        json!({"status": "APPLIED", "placeId": null})
    );
    let entry = moderation::open(&pool, 50)
        .await
        .unwrap()
        .into_iter()
        .find(|e| e.kind == "place_hold")
        .expect("held for a moderator, never dropped");
    assert_eq!(entry.reason, lunaway_db::holds::REASON);
    assert_eq!(entry.account_id, Some(author_id));

    moderation::decide(
        &pool,
        entry.id,
        Decision::Approve,
        Some("campsite reopened"),
    )
    .await
    .unwrap();
    lunaway_conflate::run(&pool, at, Some(&key)).await.unwrap();
    let s = gql(&app, Some(&author), mine, json!({})).await;
    let place = &ok(&s)["myAccount"]["placeSubmissions"]["nodes"][0]["placeId"];
    assert!(place.is_string(), "released, the place goes live: {s}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_banned_account_may_delete_itself_and_its_key_opens_nothing_after(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let app = app(&pool, config(media.path()));
    let phone = Device::new(5);
    let (token, id) = sign_in(&app, &phone).await;
    let made = gql(
        &app,
        Some(&token),
        "mutation { createRecoveryCode { code } }",
        json!({}),
    )
    .await;
    let code_text = ok(&made)["createRecoveryCode"]["code"]
        .as_str()
        .unwrap()
        .to_owned();
    lunaway_db::accounts::ban(&pool, id, "spam, ticket 4")
        .await
        .unwrap()
        .unwrap();

    let deleted = gql(
        &app,
        None,
        "mutation($code: String!) { deleteAccountWithRecoveryCode(code: $code) }",
        json!({"code": code_text}),
    )
    .await;
    assert_eq!(
        ok(&deleted)["deleteAccountWithRecoveryCode"],
        true,
        "a banned account may erase itself"
    );
    let left = sqlx::query!(
        r#"SELECT (SELECT count(*) FROM accounts) AS "accounts!",
                  (SELECT count(*) FROM banned_keys) AS "keys!""#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!((left.accounts, left.keys), (0, 1));

    for create in [true, false] {
        let (nonce, message) = challenge(&app).await;
        let again = gql(
            &app,
            None,
            "mutation($jwk: String!, $nonce: String!, $sig: String!, $create: Boolean!) {
              signIn(publicKeyJwk: $jwk, nonce: $nonce, signature: $sig,
                     createIfUnknown: $create) { created }
            }",
            json!({"jwk": phone.jwk(), "nonce": nonce, "sig": phone.sign(&message),
                   "create": create}),
        )
        .await;
        assert_eq!(
            code(&again),
            "FORBIDDEN",
            "the same key does not open a new account (createIfUnknown {create})"
        );
    }
    let accounts: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM accounts"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(accounts, 0);
    let (other_token, other) = sign_in(&app, &Device::new(6)).await;
    assert_ne!(other, id, "another key is another account");

    // Nor does it join another account through a recovery code.
    let made = gql(
        &app,
        Some(&other_token),
        "mutation { createRecoveryCode { code } }",
        json!({}),
    )
    .await;
    let other_code = ok(&made)["createRecoveryCode"]["code"]
        .as_str()
        .unwrap()
        .to_owned();
    let (nonce, message) = challenge(&app).await;
    let joined = gql(
        &app,
        None,
        "mutation($code: String!, $jwk: String!, $nonce: String!, $sig: String!) {
          recoverAccount(code: $code, publicKeyJwk: $jwk, nonce: $nonce, signature: $sig) {
            token
          }
        }",
        json!({"code": other_code, "jwk": phone.jwk(), "nonce": nonce,
               "sig": phone.sign(&message)}),
    )
    .await;
    assert_eq!(code(&joined), "FORBIDDEN");
}
