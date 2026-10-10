//! A run of `lunaway addresses` against a real database and a local server
//! that plays Photon: a place the geocoder refuses is skipped, a geocoder
//! that refuses every place stops the run with what it answered before
//! written, the budget stops a page under way, the pace holds before each
//! Photon asked, and an error never carries the position asked.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use axum::{
    Router,
    extract::State,
    http::{StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::any,
};
use lunaway_db::{
    PgPool,
    conflation::{self, OpeningEval, PlaceWrite},
    place_addresses,
};
use lunaway_domain::{
    Address, OvernightStatus, PlaceKind, Position, SourceId,
    conflation::{FieldProvenance, PlaceContent},
};
use lunaway_ingest::{
    http::{self, RetryPolicy},
    reverse_geocode::{self, ReverseConfig, RunStats},
};
use uuid::Uuid;

/// Beside the Rhône at Viviers.
const LAT: f64 = 44.4818;
const LON: f64 = 4.6896;

/// Photon's answer at the places' position: a street with a house.
const STREET: &[u8] = br#"{"type":"FeatureCollection","features":[
    {"type":"Feature","properties":{"type":"house","housenumber":"4","street":"Rue de la Gare",
      "city":"Viviers","postcode":"07220","countrycode":"FR"},
     "geometry":{"type":"Point","coordinates":[4.6896,44.4818]}}]}"#;

/// Photon's answer where its database knows nothing.
const NOTHING: &[u8] = br#"{"type":"FeatureCollection","features":[]}"#;

/// Replies the fake Photon gives, in order: status and body.
type Script = Vec<(StatusCode, &'static [u8])>;

/// A server answering each request with the next scripted reply, the last
/// one repeating, and keeping the paths it was asked.
#[derive(Clone)]
struct Fake {
    script: Arc<Mutex<Script>>,
    paths: Arc<Mutex<Vec<String>>>,
}

impl Fake {
    fn asked(&self) -> usize {
        self.paths.lock().unwrap().len()
    }
}

async fn handle(State(f): State<Fake>, uri: Uri) -> Response {
    f.paths.lock().unwrap().push(uri.path().to_owned());
    let mut script = f.script.lock().unwrap();
    let (status, body) = if script.len() > 1 {
        script.remove(0)
    } else {
        script[0]
    };
    (status, body).into_response()
}

async fn serve(script: Script) -> (Fake, SocketAddr) {
    let fake = Fake {
        script: Arc::new(Mutex::new(script)),
        paths: Arc::new(Mutex::new(Vec::new())),
    };
    let app = Router::new().fallback(any(handle)).with_state(fake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (fake, addr)
}

/// Photon's Europe at `addr`, no retry, no pace.
fn config(addr: SocketAddr) -> ReverseConfig {
    ReverseConfig {
        urls: vec![format!("http://{addr}/photon/europe")],
        pace: Duration::ZERO,
        timeout: Duration::from_secs(5),
        retry: RetryPolicy {
            min_delay: Duration::from_millis(1),
            max_delay: Duration::from_millis(2),
            max_retries: 0,
        },
    }
}

/// `n` car parks at Viviers whose sources give their town and no street,
/// in the order of their ids.
async fn car_parks(pool: &PgPool, n: usize) -> Vec<Uuid> {
    let content = PlaceContent {
        name: None,
        kind: PlaceKind::Parking,
        position: Position::new(LAT, LON).unwrap(),
        overnight: OvernightStatus::Unknown,
        services: Vec::new(),
        activities: Vec::new(),
        description: None,
        address: Address {
            postcode: Some("07220".into()),
            city: Some("Viviers".into()),
            country_code: Some("FR".into()),
            ..Address::default()
        },
        price_parking_eur: None,
        price_services_eur: None,
        price_services_included: false,
        price_parking_includes: Vec::new(),
        max_height_m: None,
        max_length_m: None,
        max_width_m: None,
        max_weight_t: None,
        capacity: None,
        opening_hours: None,
        website: None,
        phone: None,
        stars: None,
    };
    let provenance = vec![FieldProvenance {
        field: "address".to_owned(),
        source_id: SourceId::EXTCOM,
        alternatives: Vec::new(),
    }];
    let opening = OpeningEval {
        parsed: false,
        intervals: None,
        until: None,
        window_start: None,
        refresh_at: None,
        season: None,
    };
    let mut ids = Vec::with_capacity(n);
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    for _ in 0..n {
        let id = Uuid::now_v7();
        conflation::upsert_place(
            &mut tx,
            PlaceWrite {
                id,
                content: &content,
                provenance: &provenance,
                opening: &opening,
                descriptions: &[],
                external_links: &[],
                content_hash: "h",
            },
        )
        .await
        .unwrap();
        ids.push(id);
    }
    tx.commit().await.unwrap();
    ids.sort();
    ids
}

/// The places that show a street, in the order of their ids.
async fn with_street(pool: &PgPool) -> Vec<Uuid> {
    sqlx::query_scalar("SELECT id FROM places WHERE street IS NOT NULL ORDER BY id")
        .fetch_all(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_the_geocoder_refuses_is_skipped_and_the_run_goes_on(pool: PgPool) {
    let ids = car_parks(&pool, 3).await;
    let (fake, addr) = serve(vec![
        (StatusCode::OK, STREET),
        (StatusCode::INTERNAL_SERVER_ERROR, b"busy"),
        (StatusCode::OK, STREET),
    ])
    .await;
    let http = http::loopback_client().unwrap();
    let stats = reverse_geocode::run(&pool, &http, &config(addr), Duration::from_secs(60))
        .await
        .unwrap();
    assert_eq!(
        stats,
        RunStats {
            asked: 2,
            with_street: 2,
            with_town: 2,
            written: 2,
            failed: 1,
        }
    );
    assert_eq!(fake.asked(), 3, "one request a place, no retry");
    assert_eq!(with_street(&pool).await, [ids[0], ids[2]]);
    let due = place_addresses::due(&pool, Uuid::nil(), 100).await.unwrap();
    assert_eq!(
        due.iter().map(|d| d.id).collect::<Vec<_>>(),
        [ids[1]],
        "the place skipped is asked again at the next run"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_geocoder_that_refuses_every_place_stops_the_run(pool: PgPool) {
    let ids = car_parks(&pool, 30).await;
    let (fake, addr) = serve(vec![
        (StatusCode::OK, STREET),
        (StatusCode::OK, STREET),
        (StatusCode::INTERNAL_SERVER_ERROR, b"down"),
    ])
    .await;
    let http = http::loopback_client().unwrap();
    let error = reverse_geocode::run(&pool, &http, &config(addr), Duration::from_secs(60))
        .await
        .unwrap_err();
    assert_eq!(
        fake.asked(),
        22,
        "two places served, then twenty refused in a row and no more"
    );
    assert_eq!(
        with_street(&pool).await,
        ids[..2],
        "what the geocoder answered before it failed is written"
    );
    let shown = format!("{error:?} {error}");
    assert!(shown.contains("/photon/europe/reverse"), "{shown}");
    assert!(
        !shown.contains("lat=") && !shown.contains("44.48"),
        "an error never names the position asked: {shown}"
    );
}

#[tokio::test]
async fn an_unreachable_geocoder_is_named_without_the_position() {
    // A port nothing listens on: bound, then released.
    let addr = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .unwrap()
        .local_addr()
        .unwrap();
    let error = reverse_geocode::geocode(
        &http::loopback_client().unwrap(),
        &config(addr),
        PlaceKind::Parking,
        Position::new(LAT, LON).unwrap(),
        &mut None,
    )
    .await
    .unwrap_err();
    let shown = format!("{error:?} {error}");
    assert!(
        !shown.contains("lat=") && !shown.contains("44.48"),
        "a connection error never names the position asked: {shown}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_budget_stops_a_page_under_way_and_keeps_its_answers(pool: PgPool) {
    car_parks(&pool, 10).await;
    let (fake, addr) = serve(vec![(StatusCode::OK, STREET)]).await;
    let config = ReverseConfig {
        pace: Duration::from_millis(100),
        ..config(addr)
    };
    let http = http::loopback_client().unwrap();
    // At one request every 100 ms at most, requests leave at 0, 100, 200
    // and 300 ms, and the fifth would leave at 400, past the 350 ms
    // budget: four at most (fewer when a loaded machine reads the page
    // late). Finishing the page would ask all ten.
    let stats = reverse_geocode::run(&pool, &http, &config, Duration::from_millis(350))
        .await
        .unwrap();
    assert!(stats.asked <= 4, "{stats:?}");
    assert_eq!(fake.asked() as u64, stats.asked);
    assert_eq!(with_street(&pool).await.len() as u64, stats.written);
    assert_eq!(stats.written, stats.asked, "every answer is written");
    let due = place_addresses::due(&pool, Uuid::nil(), 100).await.unwrap();
    assert_eq!(due.len() as u64, 10 - stats.asked);
}

#[tokio::test]
async fn morocco_is_asked_where_europe_knows_nothing_at_the_same_pace() {
    let (fake, addr) = serve(vec![(StatusCode::OK, NOTHING), (StatusCode::OK, STREET)]).await;
    let config = ReverseConfig {
        urls: vec![
            format!("http://{addr}/photon/europe"),
            format!("http://{addr}/photon/morocco"),
        ],
        pace: Duration::from_millis(150),
        ..config(addr)
    };
    let started = Instant::now();
    let g = reverse_geocode::geocode(
        &http::loopback_client().unwrap(),
        &config,
        PlaceKind::Parking,
        Position::new(LAT, LON).unwrap(),
        &mut None,
    )
    .await
    .unwrap();
    assert!(
        started.elapsed() >= Duration::from_millis(150),
        "the second Photon waits its turn like the first: {:?}",
        started.elapsed()
    );
    assert_eq!(
        *fake.paths.lock().unwrap(),
        ["/photon/europe/reverse", "/photon/morocco/reverse"]
    );
    assert_eq!(g.street.as_deref(), Some("Rue de la Gare"));
    assert_eq!(g.house_number, None, "a car park takes no house number");
}
