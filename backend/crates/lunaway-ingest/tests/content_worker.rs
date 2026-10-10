//! The content worker against a real database and a local server that
//! plays the sources: a place whose requests fail waits for the next run,
//! a source that keeps failing is stopped, the tourist offices' texts
//! reach their places, Mangrove is never replaced from part of the map,
//! a review reaches a point of interest by the name it gives, the caps on
//! new reviews count places and points together, a point shows the files
//! its tags name, and two runs never overlap.

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
    http::{StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::any,
};
use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool, content as db,
    pois::{self, NewPoi},
};
use lunaway_domain::{
    Position, SourceId,
    poi::{PoiKind, PoiRecord, PoiRefs},
};
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
/// one repeating, and keeping what it was asked.
#[derive(Clone)]
struct Fake {
    script: Arc<Mutex<Script>>,
    asked: Arc<Mutex<usize>>,
    uris: Arc<Mutex<Vec<String>>>,
}

async fn handle(State(f): State<Fake>, uri: Uri) -> Response {
    *f.asked.lock().unwrap() += 1;
    f.uris.lock().unwrap().push(uri.to_string());
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
        uris: Arc::new(Mutex::new(Vec::new())),
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

    // Without any wait between two asks, a pass still asks each place
    // once: a place it asked is dated after the pass began. The run is
    // bounded so that a pass asking again ends in a failure, not a hang.
    let mut every_time = config(addr);
    every_time.stale_after = chrono::Duration::zero();
    let all = usize::try_from(total).unwrap();
    every_time.max_places = all * 2;
    let once = content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Commons],
        &every_time,
    )
    .await
    .unwrap();
    assert_eq!(
        once[0].1.places, all,
        "each place asked once in a pass with no waiting time"
    );

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
    let subject = format!("geo:{lat},{lon}?u=30");
    let reviews: Vec<(String, String, i64)> = authors
        .iter()
        .map(|(name, iat)| (subject.clone(), name.clone(), *iat))
        .collect();
    mangrove_page(&reviews)
}

/// A page of Mangrove reviews, one per `(subject, author, date)`, signed
/// by a key made from the author's name: one key for each name.
fn mangrove_page(reviews: &[(String, String, i64)]) -> (serde_json::Value, Vec<(String, String)>) {
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
    let reviews: Vec<serde_json::Value> = reviews
        .iter()
        .map(|(sub, name, iat)| {
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
                "sub": sub,
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
            target: db::ContentTarget::Place(place),
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
    assert_eq!(r.held_new_pairs, 8, "the others wait for a later run");
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

/// Stores a bakery of OpenStreetMap, as the establishments' import writes
/// it, and returns its id.
async fn point(
    pool: &PgPool,
    external_id: &str,
    name: Option<&str>,
    at: (f64, f64),
    refs: PoiRefs,
) -> uuid::Uuid {
    point_of(pool, external_id, PoiKind::Bakery, name, at, refs).await
}

/// Stores a point of OpenStreetMap of `kind` and returns its id.
async fn point_of(
    pool: &PgPool,
    external_id: &str,
    kind: PoiKind,
    name: Option<&str>,
    (lat, lon): (f64, f64),
    refs: PoiRefs,
) -> uuid::Uuid {
    let mut r = PoiRecord::new(kind, Position::new(lat, lon).unwrap());
    r.name = name.map(str::to_owned);
    r.refs = refs;
    let raw = serde_json::value::to_raw_value(&serde_json::json!({})).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 7, 12, 0, 0).unwrap();
    pois::upsert(
        pool,
        &SourceId::OSM,
        &[NewPoi {
            external_id,
            external_url: None,
            record: &r,
            raw: &raw,
            fetched_at: at,
            scope: Some("FR"),
            in_tiles: false,
        }],
    )
    .await
    .unwrap();
    sqlx::query_scalar!(
        "SELECT id FROM pois WHERE source_id = 'osm' AND external_id = $1",
        external_id
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

/// Reviews stored with their place or point, by author.
async fn stored_reviews(pool: &PgPool) -> Vec<(String, Option<uuid::Uuid>, Option<uuid::Uuid>)> {
    sqlx::query_as(
        "SELECT author, place_id, poi_id FROM content_reviews \
         WHERE source_id = 'mangrove' ORDER BY author",
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_mangrove_review_reaches_the_point_whose_name_it_gives(pool: PgPool) {
    // No place stands in this part of the map: only points.
    let bakery = point(
        &pool,
        "node/1",
        Some("Boulangerie Dupont"),
        (45.0, 5.0),
        PoiRefs::default(),
    )
    .await;
    let nameless = point(&pool, "node/2", None, (45.01, 5.0), PoiRefs::default()).await;
    let doctor = point_of(
        &pool,
        "node/3",
        PoiKind::Doctor,
        Some("Docteur Martin"),
        (45.02, 5.0),
        PoiRefs::default(),
    )
    .await;
    // About 11 m north of the bakery, then about 445 m north of it.
    let near = "45.0001,5.0";
    let far = "45.004,5.0";
    let reviews = [
        (format!("geo:{near}?q=Boulangerie%20Dupont&u=30"), "named"),
        (
            format!("geo:{near}?q=Pharmacie%20Martin&u=30"),
            "other-name",
        ),
        (format!("geo:{near}?u=30"), "no-name"),
        (
            format!("geo:{far}?q=Boulangerie%20Dupont&u=1000"),
            "too-far",
        ),
        (
            "geo:45.01,5.0?q=Chez%20Paul&u=30".to_owned(),
            "at-the-nameless-point",
        ),
        (
            "geo:45.02,5.0?q=Docteur%20Martin&u=30".to_owned(),
            "at-the-doctor",
        ),
    ];
    let reviews: Vec<(String, String, i64)> = reviews
        .into_iter()
        .zip(1_790_000_000..)
        .map(|((sub, author), iat)| (sub, author.to_owned(), iat))
        .collect();
    let (page, _) = mangrove_page(&reviews);
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let (_, addr) = serve(vec![
        (StatusCode::OK, page.to_string().into_bytes()),
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
    assert_eq!(
        stored_reviews(&pool).await,
        [("named".to_owned(), None, Some(bakery))],
        "only the review that gives the bakery's name, within its uncertainty and 300 m, \
         reaches it; never one without a name, nor one at a point without a name \
         ({nameless}), nor one of a person's health practice ({doctor})"
    );
    assert_eq!((r.places, r.pois), (0, 1), "{r:?}");
    assert_eq!(r.skipped.get("\"NoPlace\""), Some(&4), "{r:?}");
    assert_eq!(
        r.skipped.get("\"HealthPractice\""),
        Some(&1),
        "a review that names a person's practice is kept nowhere: {r:?}"
    );
    let shown = db::reviews_of_poi(&pool, bakery, 20, None).await.unwrap();
    assert_eq!(shown.nodes[0].author.as_deref(), Some("named"));
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_caps_on_new_reviews_count_places_and_points_together(pool: PgPool) {
    seeded(&pool).await;
    let places: Vec<(uuid::Uuid, f64, f64)> = sqlx::query_as(
        "SELECT id, ST_Y(geom::geometry), ST_X(geom::geometry) FROM places \
         WHERE deleted_at IS NULL ORDER BY id LIMIT 2",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    let shop = point(
        &pool,
        "node/1",
        Some("Boulangerie Dupont"),
        (45.0, 5.0),
        PoiRefs::default(),
    )
    .await;
    let cafe = point(
        &pool,
        "node/2",
        Some("Café de la Gare"),
        (45.1, 5.0),
        PoiRefs::default(),
    )
    .await;
    // One new key reviews two points and two places, read in this order:
    // it reaches three new targets this run, places and points together,
    // the places first.
    let at_place = |(_, lat, lon): (uuid::Uuid, f64, f64)| format!("geo:{lat},{lon}?u=30");
    let reviews: Vec<(String, String, i64)> = [
        "geo:45.0,5.0?q=Boulangerie%20Dupont&u=30".to_owned(),
        at_place(places[0]),
        "geo:45.1,5.0?q=Caf%C3%A9%20de%20la%20Gare&u=30".to_owned(),
        at_place(places[1]),
    ]
    .into_iter()
    .zip(1_790_000_000..)
    .map(|(sub, iat)| (sub, "roamer".to_owned(), iat))
    .collect();
    let (page, _) = mangrove_page(&reviews);
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let (_, addr) = serve(vec![
        (StatusCode::OK, page.to_string().into_bytes()),
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
    let mut kept: Vec<_> = stored_reviews(&pool)
        .await
        .into_iter()
        .map(|(_, place, poi)| (place, poi))
        .collect();
    kept.sort();
    let mut expected = vec![
        (Some(places[0].0), None),
        (None, Some(shop)),
        (Some(places[1].0), None),
    ];
    expected.sort();
    assert_eq!(
        kept, expected,
        "three new targets for a key in a run, places and points together; the places \
         before the points, though read after them: the café ({cafe}) waits"
    );
    assert_eq!((r.places, r.pois), (2, 1));
    assert_eq!(r.held_new_pairs, 1, "{r:?}");
    assert_eq!(r.new_keys, 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_gone_from_its_source_keeps_a_reported_review_and_its_key_is_struck(pool: PgPool) {
    let shop = point(
        &pool,
        "node/1",
        Some("Boulangerie Dupont"),
        (45.0, 5.0),
        PoiRefs::default(),
    )
    .await;
    let key = "ab".repeat(32);
    db::replace_reviews(
        &pool,
        "mangrove",
        &[db::NewReview {
            target: db::ContentTarget::Poi(shop),
            external_id: "sig-spam".into(),
            rating: Some(1),
            text: Some("Publicité.".into()),
            lang: None,
            author: Some("spammer".into()),
            author_key: Some(key.clone()),
            written_at: Utc::now(),
            page_url: "https://mangrove.reviews/list?signature=sig-spam".into(),
            licence: "CC BY 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by/4.0/".into(),
            distance_m: Some(2.0),
        }],
        Utc::now(),
    )
    .await
    .unwrap();
    // Three reports hid it; then its point left OpenStreetMap before the
    // weekly run, which reads no Mangrove page today.
    let mut conn = pool.acquire().await.unwrap();
    db::hide_item_on(
        &mut conn,
        "mangrove",
        db::ItemKind::Review,
        "sig-spam",
        db::HideOrigin::Reports,
    )
    .await
    .unwrap();
    drop(conn);
    sqlx::query("UPDATE pois SET deleted_at = now() WHERE id = $1")
        .bind(shop)
        .execute(&pool)
        .await
        .unwrap();
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let client = http::client_allowing_plain_http().unwrap();
    let (_, addr) = serve(vec![(StatusCode::OK, NO_FILE.to_vec())]).await;
    content::refresh(
        &pool,
        &client,
        &store,
        &[ContentSource::Commons],
        &config(addr),
    )
    .await
    .unwrap();
    let struck: i64 =
        sqlx::query_scalar("SELECT count(*) FROM content_review_strikes WHERE author_key = $1")
            .bind(&key)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(struck, 1, "the key ranks as new while the hide stands");
    let kept: i64 =
        sqlx::query_scalar("SELECT count(*) FROM content_reviews WHERE external_id = 'sig-spam'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(kept, 1, "the moderator still finds what was reported");
}

/// A client whose requests to the sources' media hosts reach the
/// loopback, where nothing listens on 443: a test that would download a
/// picture fails there, and never reaches the real host.
fn client_without_media() -> reqwest::Client {
    // Building the crate's client installs the TLS crypto provider, which
    // reqwest needs to build any client.
    let _ = http::client_allowing_plain_http().unwrap();
    let nowhere: SocketAddr = "127.0.0.1:443".parse().unwrap();
    let mut b = reqwest::Client::builder();
    for host in [
        "upload.wikimedia.org",
        "thumb.wikimedia.org",
        "panoramax.openstreetmap.fr",
        "panoramax.ign.fr",
    ] {
        b = b.resolve(host, nowhere);
    }
    b.build().unwrap()
}

/// The answer of Commons about one file, as its action API gives it.
fn commons_file(title: &str, sha1: &str) -> Vec<u8> {
    let name = title.trim_start_matches("File:").replace(' ', "_");
    serde_json::json!({
        "batchcomplete": true,
        "query": {"pages": [{
            "ns": 6,
            "title": title,
            "imageinfo": [{
                "thumburl": format!("https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/{name}/1280px-{name}"),
                "url": format!("https://upload.wikimedia.org/wikipedia/commons/a/ab/{name}"),
                "descriptionurl": format!("https://commons.wikimedia.org/wiki/{}", title.replace(' ', "_")),
                "width": 4000,
                "height": 3000,
                "mime": "image/jpeg",
                "sha1": sha1,
                "extmetadata": {
                    "LicenseShortName": {"value": "CC BY-SA 4.0"},
                    "Artist": {"value": "<a href=\"//commons.wikimedia.org/wiki/User:Pierre\">Pierre</a>"}
                }
            }],
            "coordinates": [{"lat": 45.5001, "lon": 1.8, "primary": true}]
        }]}
    })
    .to_string()
    .into_bytes()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_shows_the_commons_file_its_tags_name(pool: PgPool) {
    let file = "File:Mairie de Treignac.jpg";
    let sha1 = "0123456789abcdef0123456789abcdef01234567";
    let named = |f: &str| PoiRefs {
        commons: Some(f.to_owned()),
        ..PoiRefs::default()
    };
    let town_hall = point(&pool, "node/1", Some("Mairie"), (45.5, 1.8), named(file)).await;
    let shop = point(
        &pool,
        "node/2",
        Some("Épicerie"),
        (45.6, 1.8),
        PoiRefs::default(),
    )
    .await;
    // Another point of the same building shows the file already: the
    // town hall reuses its files, and the test downloads nothing.
    let twin = point(
        &pool,
        "node/3",
        Some("Mairie annexe"),
        (45.5, 1.8001),
        named(file),
    )
    .await;
    let stored = db::PhotoFiles {
        path: format!("external/ab/cd/{}.webp", "ab".repeat(32)),
        thumb_path: format!("external/ab/cd/{}-t.webp", "ab".repeat(32)),
        width: 1280,
        height: 960,
        thumbhash: vec![1, 2, 3],
    };
    db::replace_poi_photos(
        &pool,
        twin,
        "wikimedia-commons",
        &[db::NewPhoto {
            external_id: file.to_owned(),
            version: sha1.to_owned(),
            relation: "linked".into(),
            distance_m: Some(7.0),
            page_url: "https://commons.wikimedia.org/wiki/File:Mairie_de_Treignac.jpg".into(),
            title: None,
            author: Some("Pierre".into()),
            publisher: None,
            source_updated_on: None,
            licence: "CC BY-SA 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
            taken_at: None,
            rights_end_on: None,
            files: stored.clone(),
        }],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let (fake, addr) = serve(vec![(StatusCode::OK, commons_file(file, sha1))]).await;
    let reports = content::refresh(
        &pool,
        &client_without_media(),
        &store,
        &[ContentSource::Commons],
        &config(addr),
    )
    .await
    .unwrap();
    let r = &reports[0].1;
    assert_eq!(r.stopped, None, "{r:?}");
    assert_eq!(
        (r.pois, r.pois_with_content, r.reused, r.downloaded),
        (1, 1, 1, 0),
        "the town hall alone is asked: its twin was asked this week, the shop names nothing; {r:?}"
    );
    let photos = db::photos_of_poi(&pool, town_hall, 4).await.unwrap();
    assert_eq!(photos.len(), 1);
    let p = &photos[0];
    assert_eq!(p.source_id, "wikimedia-commons");
    assert_eq!(p.relation, "linked");
    assert_eq!(p.licence, "CC BY-SA 4.0");
    assert_eq!(p.author.as_deref(), Some("Pierre"));
    assert_eq!(p.path, stored.path, "the file already made is shown again");
    let uris = fake.uris.lock().unwrap().clone();
    assert!(
        uris.iter()
            .any(|u| u.starts_with("/commons/")
                && u.contains("titles=File%3AMairie+de+Treignac.jpg")),
        "Commons is asked for the file the tag names: {uris:?}"
    );
    assert!(
        !uris.iter().any(|u| u.contains("geosearch")),
        "nothing is searched around a point: {uris:?}"
    );
    let shop_checks: i64 =
        sqlx::query_scalar("SELECT count(*) FROM content_poi_checks WHERE poi_id = $1")
            .bind(shop)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(shop_checks, 0, "a point that names nothing is never asked");
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_asks_panoramax_for_its_picture_and_nothing_around_it(pool: PgPool) {
    let picture = "d8dc9efb-d1b4-4a64-b948-f28bde76b202";
    let named = PoiRefs {
        panoramax: Some(picture.to_owned()),
        ..PoiRefs::default()
    };
    let cafe = point(
        &pool,
        "node/1",
        Some("Café du Port"),
        (48.11, -1.68),
        named.clone(),
    )
    .await;
    let twin = point(
        &pool,
        "node/2",
        Some("Café du Port, terrasse"),
        (48.11, -1.6801),
        named,
    )
    .await;
    db::replace_poi_photos(
        &pool,
        twin,
        "panoramax",
        &[db::NewPhoto {
            external_id: picture.to_owned(),
            version: picture.to_owned(),
            relation: "linked".into(),
            distance_m: Some(12.0),
            page_url: format!("https://panoramax.openstreetmap.fr/?focus=pic&pic={picture}"),
            title: None,
            author: Some("PanierAvide".into()),
            publisher: Some("Panoramax OpenStreetMap France".into()),
            source_updated_on: None,
            licence: "CC BY-SA 4.0".into(),
            licence_url: "https://creativecommons.org/licenses/by-sa/4.0/".into(),
            taken_at: None,
            rights_end_on: None,
            files: db::PhotoFiles {
                path: format!("external/cd/ef/{}.webp", "cd".repeat(32)),
                thumb_path: format!("external/cd/ef/{}-t.webp", "cd".repeat(32)),
                width: 1280,
                height: 960,
                thumbhash: vec![1, 2, 3],
            },
        }],
        Utc::now(),
        1,
    )
    .await
    .unwrap();
    let answer = serde_json::json!({
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "id": picture,
            "geometry": {"type": "Point", "coordinates": [-1.6801, 48.1101]},
            "properties": {
                "view:azimuth": 120.0,
                "license": "CC-BY-SA-4.0",
                "datetime": "2025-06-01T10:00:00+00:00"
            },
            "assets": {"sd": {"href": format!("https://panoramax.openstreetmap.fr/api/pictures/{picture}/sd.jpg")}},
            "providers": [{"name": "PanierAvide", "roles": ["producer"]}],
            "links": []
        }]
    });
    let media = tempfile::tempdir().unwrap();
    let store = MediaStore::new(media.path());
    let (fake, addr) = serve(vec![(StatusCode::OK, answer.to_string().into_bytes())]).await;
    let reports = content::refresh(
        &pool,
        &client_without_media(),
        &store,
        &[ContentSource::Panoramax],
        &config(addr),
    )
    .await
    .unwrap();
    let r = &reports[0].1;
    assert_eq!(r.stopped, None, "{r:?}");
    assert_eq!((r.pois, r.pois_with_content), (1, 1), "{r:?}");
    let photos = db::photos_of_poi(&pool, cafe, 4).await.unwrap();
    assert_eq!(photos.len(), 1);
    assert_eq!(
        photos[0].publisher.as_deref(),
        Some("Panoramax OpenStreetMap France")
    );
    let uris = fake.uris.lock().unwrap().clone();
    assert!(!uris.is_empty());
    assert!(
        uris.iter()
            .all(|u| u.contains(&format!("ids={picture}")) && !u.contains("place_position")),
        "only the picture the tag names, never a search around the point: {uris:?}"
    );
}
