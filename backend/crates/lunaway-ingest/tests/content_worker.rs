//! The content worker against a real database and a local server that
//! plays the sources: a place whose requests fail waits for the next run,
//! a source that keeps failing is stopped, the tourist offices' texts
//! reach their places, Mangrove is never replaced from part of the map,
//! and two runs never overlap.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Router,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::any,
};
use chrono::{TimeZone, Utc};
use lunaway_db::{PgPool, content as db};
use lunaway_domain::SourceId;
use lunaway_ingest::{
    IngestError,
    content::{self, ContentConfig, ContentSource, Endpoints},
    datatourisme,
    http::{self, RetryPolicy},
    osm,
    store::store_complete,
};
use lunaway_media::MediaStore;

const OVERPASS: &[u8] = include_bytes!("fixtures/overpass_sample.json");
const DATATOURISME: &[u8] = include_bytes!("fixtures/content/datatourisme_objects.json");

/// An answer of the action API with no file: a place asked gets nothing,
/// and no picture is downloaded.
const NO_FILE: &[u8] = br#"{"batchcomplete":true,"query":{"pages":[]}}"#;

/// Replies a fake server gives, in order: status and body.
type Script = Vec<(StatusCode, Vec<u8>)>;

/// A server answering each request with the next scripted reply, the last
/// one repeating, and counting what it was asked.
#[derive(Clone)]
struct Fake {
    script: Arc<Mutex<Script>>,
    asked: Arc<Mutex<usize>>,
}

async fn handle(State(f): State<Fake>) -> Response {
    *f.asked.lock().unwrap() += 1;
    let mut script = f.script.lock().unwrap();
    let (status, body) = if script.len() > 1 {
        script.remove(0)
    } else {
        script[0].clone()
    };
    (status, body).into_response()
}

async fn serve(script: Script) -> (Fake, SocketAddr) {
    let fake = Fake {
        script: Arc::new(Mutex::new(script)),
        asked: Arc::new(Mutex::new(0)),
    };
    let app = Router::new().fallback(any(handle)).with_state(fake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (fake, addr)
}

fn config(addr: SocketAddr) -> ContentConfig {
    let base = format!("http://{addr}");
    ContentConfig {
        endpoints: Endpoints {
            commons: format!("{base}/commons/w/api.php"),
            wikidata: format!("{base}/wikidata/w/api.php"),
            wikipedia: format!("{base}/{{lang}}/w/api.php"),
            panoramax: format!("{base}/panoramax/api/search"),
            mangrove: format!("{base}/mangrove/reviews"),
        },
        retry: RetryPolicy {
            min_delay: Duration::from_millis(1),
            max_delay: Duration::from_millis(2),
            max_retries: 0,
        },
        wikimedia_pace: Duration::ZERO,
        panoramax_pace: Duration::ZERO,
        media_pace: Duration::ZERO,
        mangrove_pace: Duration::ZERO,
        max_failures: 3,
        ..ContentConfig::default()
    }
}

/// The places of the OpenStreetMap fixture, and those of the tourist
/// offices' objects (their photos taken out: no test reaches a real host).
async fn seeded(pool: &PgPool) {
    let at = Utc.with_ymd_and_hms(2026, 10, 7, 12, 0, 0).unwrap();
    let o = osm::parse(OVERPASS, at).unwrap();
    store_complete(pool, &SourceId::OSM, Some("FR-PDL"), &o.records)
        .await
        .unwrap();
    let mut objects = datatourisme::parse_page(DATATOURISME).unwrap().objects;
    for o in &mut objects {
        let o = o.as_object_mut().unwrap();
        o.remove("hasMainRepresentation");
        o.remove("hasRepresentation");
    }
    let parsed = datatourisme::to_records(objects, at);
    store_complete(pool, &SourceId::DATATOURISME, None, &parsed.records)
        .await
        .unwrap();
    lunaway_conflate::run(pool, at, None).await.unwrap();
}

async fn places(pool: &PgPool) -> i64 {
    sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM places WHERE deleted_at IS NULL"#)
        .fetch_one(pool)
        .await
        .unwrap()
}

async fn checked(pool: &PgPool, source: &str) -> i64 {
    sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM content_checks WHERE source_id = $1"#,
        source
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failing_place_waits_for_the_next_run_and_a_failing_source_stops(pool: PgPool) {
    seeded(&pool).await;
    let total = places(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    // Two answers fail, then every answer is empty.
    let (fake, addr) = serve(vec![
        (StatusCode::BAD_GATEWAY, b"down".to_vec()),
        (StatusCode::BAD_GATEWAY, b"down".to_vec()),
        (StatusCode::OK, NO_FILE.to_vec()),
    ])
    .await;
    let reports = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Commons],
        &config(addr),
    )
    .await
    .unwrap();
    let r = &reports[0].1;
    assert_eq!(r.failures, 2, "{r:?}");
    assert_eq!(r.stopped, None, "two failures are below the breaker");
    assert_eq!(
        checked(&pool, "wikimedia-commons").await,
        total - 2,
        "a place whose request failed is not marked asked"
    );
    let again = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Commons],
        &config(addr),
    )
    .await
    .unwrap();
    assert_eq!(
        again[0].1.places, 2,
        "the next run asks only the two that failed"
    );
    assert_eq!(checked(&pool, "wikimedia-commons").await, total);

    let (_, down) = serve(vec![(StatusCode::SERVICE_UNAVAILABLE, b"down".to_vec())]).await;
    let mut stale = config(down);
    stale.stale_after = chrono::Duration::zero();
    let stopped = content::refresh(&pool, &client, &store, &[ContentSource::Commons], &stale)
        .await
        .unwrap();
    let s = &stopped[0].1;
    assert_eq!(s.failures, 3);
    assert!(
        s.stopped.is_some(),
        "three failures in a row stop the source for the run: {s:?}"
    );
    assert!(*fake.asked.lock().unwrap() > 0);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_tourist_offices_texts_reach_their_places(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let (fake, addr) = serve(vec![(StatusCode::OK, NO_FILE.to_vec())]).await;
    let reports = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Datatourisme],
        &config(addr),
    )
    .await
    .unwrap();
    let r = &reports[0].1;
    assert!(r.places > 0 && r.with_content > 0, "{r:?}");
    assert_eq!(
        *fake.asked.lock().unwrap(),
        0,
        "the offices' texts come from the records: no request"
    );
    let place: uuid::Uuid = sqlx::query_scalar!(
        "SELECT place_id FROM content_descriptions WHERE source_id = 'datatourisme' LIMIT 1"
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let d = db::descriptions_of_place(&pool, place).await.unwrap();
    assert!(d.iter().all(|d| d.licence == "Licence Ouverte 2.0"));
    assert!(
        d.iter()
            .all(|d| d.publisher.is_some() && d.source_updated_on.is_some()),
        "the office and its update date travel with each text, as the licence asks"
    );
    let second = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Datatourisme],
        &config(addr),
    )
    .await
    .unwrap();
    assert_eq!(second[0].1.places, 0, "a place asked this week waits");
}

#[sqlx::test(migrations = "../../migrations")]
async fn mangrove_is_never_replaced_from_part_of_the_map(pool: PgPool) {
    seeded(&pool).await;
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let (fake, addr) = serve(vec![(StatusCode::OK, br#"{"reviews":[]}"#.to_vec())]).await;
    let mut in_area = config(addr);
    in_area.area = Some((47.0, -1.0, 48.0, 0.0));
    let reports = content::refresh(&pool, &client, &store, &[ContentSource::Mangrove], &in_area)
        .await
        .unwrap();
    assert!(reports[0].1.stopped.is_some());
    assert_eq!(*fake.asked.lock().unwrap(), 0);

    let (_, broken) = serve(vec![(StatusCode::BAD_GATEWAY, b"down".to_vec())]).await;
    let reports = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Mangrove],
        &config(broken),
    )
    .await
    .unwrap();
    assert!(
        reports[0].1.stopped.is_some(),
        "a page that fails replaces nothing and says so"
    );
}

/// A page of Mangrove reviews about the point `(lat, lon)`, one per name
/// of `authors`, written at its date and signed by a key made from the
/// name, as the API lists them. Returns the page and the keys' hashes,
/// as Lunaway stores them.
fn mangrove_reviews(
    lat: f64,
    lon: f64,
    authors: &[(String, i64)],
) -> (serde_json::Value, Vec<(String, String)>) {
    use base64::{
        Engine,
        engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    };
    use p256::ecdsa::{Signature, SigningKey, signature::Signer};
    use sha2::{Digest, Sha256};
    // The DER prefix of a P-256 SubjectPublicKeyInfo.
    const SPKI: [u8; 26] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08,
        0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ];
    let mut kids = Vec::new();
    let reviews: Vec<serde_json::Value> = authors
        .iter()
        .map(|(name, iat)| {
            let key = SigningKey::from_slice(&Sha256::digest(name.as_bytes())).unwrap();
            let mut der = SPKI.to_vec();
            der.extend_from_slice(&key.verifying_key().to_sec1_bytes());
            let kid = format!(
                "-----BEGIN PUBLIC KEY-----{}-----END PUBLIC KEY-----",
                STANDARD.encode(der)
            );
            let author_key: String = Sha256::digest(kid.as_bytes())
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect();
            let payload = serde_json::json!({
                "sub": format!("geo:{lat},{lon}?u=30"),
                "rating": 80,
                "opinion": format!("Avis de {name}."),
                "iat": iat,
                "metadata": {"nickname": name}
            });
            let header = URL_SAFE_NO_PAD.encode(serde_json::json!({"alg": "ES256"}).to_string());
            let body = URL_SAFE_NO_PAD.encode(payload.to_string());
            let sig: Signature = key.sign(format!("{header}.{body}").as_bytes());
            let sig = URL_SAFE_NO_PAD.encode(sig.to_bytes());
            kids.push((author_key, sig.clone()));
            serde_json::json!({
                "signature": sig,
                "kid": kid,
                "jwt": format!("{header}.{body}.{sig}"),
                "payload": payload
            })
        })
        .collect();
    (serde_json::json!({ "reviews": reviews }), kids)
}

#[sqlx::test(migrations = "../../migrations")]
async fn fresh_mangrove_keys_cannot_push_the_reviews_shown_off_a_place(pool: PgPool) {
    seeded(&pool).await;
    let (place, lat, lon): (uuid::Uuid, f64, f64) = sqlx::query_as(
        "SELECT id, ST_Y(geom::geometry), ST_X(geom::geometry) FROM places \
         WHERE deleted_at IS NULL ORDER BY id LIMIT 1",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    // Five reviewers shown on the place since May; ten keys never seen,
    // whose reviews say they are newer.
    let old: Vec<(String, i64)> = (0..5)
        .map(|n| (format!("old-key-{n}"), 1_778_000_000 + n))
        .collect();
    let fresh: Vec<(String, i64)> = (0..10)
        .map(|n| (format!("fresh-key-{n}"), 1_790_000_000 + n))
        .collect();
    let all: Vec<(String, i64)> = old.iter().chain(&fresh).cloned().collect();
    let (page, keys) = mangrove_reviews(lat, lon, &all);
    let may = Utc.with_ymd_and_hms(2026, 5, 1, 0, 0, 0).unwrap();
    let shown: Vec<db::NewReview> = old
        .iter()
        .zip(&keys)
        .map(|((name, iat), (key, sig))| db::NewReview {
            place_id: place,
            external_id: sig.clone(),
            rating: Some(4),
            text: Some(format!("Avis de {name}.")),
            lang: None,
            author: Some(name.clone()),
            author_key: Some(key.clone()),
            written_at: chrono::DateTime::from_timestamp(*iat, 0).unwrap(),
            page_url: format!("https://mangrove.reviews/list?signature={sig}"),
            licence: "CC BY 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
            distance_m: Some(0.0),
        })
        .collect();
    db::replace_reviews(&pool, "mangrove", &shown, may)
        .await
        .unwrap();
    let page = page.to_string().into_bytes();
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let (_, addr) = serve(vec![
        (StatusCode::OK, page),
        (StatusCode::OK, br#"{"reviews":[]}"#.to_vec()),
    ])
    .await;
    let reports = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Mangrove],
        &config(addr),
    )
    .await
    .unwrap();
    let r = &reports[0].1;
    assert_eq!(r.stopped, None, "{r:?}");
    let mut kept: Vec<String> = sqlx::query_scalar(
        "SELECT author FROM content_reviews WHERE source_id = 'mangrove' AND place_id = $1",
    )
    .bind(place)
    .fetch_all(&pool)
    .await
    .unwrap();
    kept.sort();
    assert_eq!(
        kept,
        [
            "fresh-key-0",
            "fresh-key-1",
            "old-key-0",
            "old-key-1",
            "old-key-2",
            "old-key-3",
            "old-key-4"
        ],
        "every reviewer shown stays, and the place gains two new keys this run, \
         in the order they were read, whatever date they claim"
    );
    assert_eq!(r.new_keys, 2);
    assert_eq!(r.held_new_keys, 8, "the others wait for a later run");
    let known: i64 =
        sqlx::query_scalar("SELECT count(*) FROM content_review_keys WHERE source_id = 'mangrove'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(known, 7, "a key kept once is no longer new");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_second_refresh_does_not_start_beside_the_first(pool: PgPool) {
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let held = db::RunLock::try_acquire(&pool).await.unwrap().unwrap();
    let (_, addr) = serve(vec![(StatusCode::OK, NO_FILE.to_vec())]).await;
    let busy = content::refresh(&pool, &client, &store, &ContentSource::ALL, &config(addr)).await;
    assert!(matches!(busy, Err(IngestError::Busy { .. })), "{busy:?}");
    held.release().await.unwrap();
}
