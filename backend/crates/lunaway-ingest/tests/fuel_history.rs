//! The fuel feed as the poller reads it: each column of the export maps to
//! its fuel, on the recorded export of 2026-10-06 near the A20 between
//! Limoges and Brive, and each poll keeps the day's lowest and highest price
//! of every station and fuel.

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
use chrono::{DateTime, Utc};
use lunaway_domain::poi::FuelKind;
use lunaway_ingest::{cache::Cache, fuel, http, http::RetryPolicy};
use sqlx::PgPool;

const A20: &[u8] = include_bytes!("fixtures/fuel_export_a20_sample.json");

/// When the recorded export was read.
const RECORDED_AT: &str = "2026-10-06T13:24:14Z";

const FAST: RetryPolicy = RetryPolicy {
    min_delay: Duration::from_millis(5),
    max_delay: Duration::from_millis(20),
    max_retries: 2,
};

/// The export's column prefix of each fuel, as `docs/data-sources.md`
/// documents it.
const COLUMNS: [(&str, FuelKind); 6] = [
    ("gazole", FuelKind::Diesel),
    ("sp95", FuelKind::Sp95),
    ("e10", FuelKind::E10),
    ("sp98", FuelKind::Sp98),
    ("e85", FuelKind::E85),
    ("gplc", FuelKind::Lpg),
];

fn rows() -> Vec<serde_json::Value> {
    serde_json::from_slice(A20).unwrap()
}

/// The recorded export with its dates moved so it reads as read `now`: a
/// price is offered for 90 days, and the test must not age.
fn as_of_now(rows: &mut [serde_json::Value]) {
    let shift = Utc::now()
        - DateTime::parse_from_rfc3339(RECORDED_AT)
            .unwrap()
            .with_timezone(&Utc);
    for row in rows {
        let obj = row.as_object_mut().unwrap();
        for (key, value) in obj.iter_mut() {
            if (key.ends_with("_maj") || key.ends_with("_rupture_debut"))
                && let Some(text) = value.as_str()
            {
                let moved = DateTime::parse_from_rfc3339(text).unwrap() + shift;
                *value = moved.to_rfc3339().into();
            }
        }
    }
}

#[test]
fn each_column_of_the_feed_maps_to_its_fuel() {
    let raw = rows();
    let parsed = fuel::parse(A20).unwrap();
    assert_eq!(parsed.stations.len(), raw.len());
    let mut prices = 0;
    for row in &raw {
        let key = row["id"].as_i64().unwrap().to_string();
        let station = &parsed
            .stations
            .iter()
            .find(|s| s.key == key)
            .unwrap()
            .station;
        // No price column the mapping does not know.
        for column in row.as_object().unwrap().keys() {
            if let Some(prefix) = column.strip_suffix("_prix") {
                assert!(
                    COLUMNS.iter().any(|(p, _)| *p == prefix),
                    "{column} has no fuel"
                );
            }
        }
        for (prefix, kind) in COLUMNS {
            let price = row[format!("{prefix}_prix")].as_f64();
            assert_eq!(
                station.price_of(kind).map(|p| p.price_eur),
                price,
                "{key}: {prefix} is {kind:?}"
            );
            prices += usize::from(price.is_some());
        }
    }
    assert_eq!(prices, 262, "every price of the 80 stations");
    // Saint-Pardoux-l'Ortigier, beside the A20: named by its address.
    let address = parsed
        .stations
        .iter()
        .find(|s| s.key == "19270004")
        .unwrap()
        .station
        .address
        .clone()
        .unwrap();
    assert_eq!(address.city.as_deref(), Some("Saint-Pardoux-l'Ortigier"));
    assert_eq!(address.postcode.as_deref(), Some("19270"));
    assert!(address.street.is_some());
}

/// A server answering each request with the next scripted body, the last
/// one repeating.
#[derive(Clone)]
struct Fake {
    bodies: Arc<Mutex<Vec<Vec<u8>>>>,
}

async fn handle(State(f): State<Fake>) -> Response {
    let mut bodies = f.bodies.lock().unwrap();
    let body = if bodies.len() > 1 {
        bodies.remove(0)
    } else {
        bodies[0].clone()
    };
    (StatusCode::OK, body).into_response()
}

async fn serve(bodies: Vec<Vec<u8>>) -> SocketAddr {
    let fake = Fake {
        bodies: Arc::new(Mutex::new(bodies)),
    };
    let app = Router::new().fallback(any(handle)).with_state(fake);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    addr
}

/// The feed of now, Masseret's diesel (station 19510002) at `price`.
fn feed_with_masseret_at(price: f64) -> Vec<u8> {
    let mut rows = rows();
    as_of_now(&mut rows);
    for row in &mut rows {
        if row["id"] == 19_510_002 {
            row["gazole_prix"] = price.into();
        }
    }
    serde_json::to_vec(&rows).unwrap()
}

async fn masseret_diesel(pool: &PgPool) -> Vec<(f64, f64)> {
    sqlx::query_as(
        "SELECT low_eur, high_eur FROM fuel_price_days \
         WHERE station_ref = '19510002' AND fuel = 'diesel' ORDER BY day",
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn each_poll_keeps_the_day_s_lowest_and_highest_price(pool: PgPool) {
    let addr = serve(vec![
        feed_with_masseret_at(2.25),
        feed_with_masseret_at(2.19),
        feed_with_masseret_at(2.31),
        feed_with_masseret_at(2.31),
    ])
    .await;
    let client = http::client_allowing_plain_http().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let config = fuel::FuelConfig {
        url: format!("http://{addr}/exports/json"),
        retry: FAST,
    };
    let first = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(
        first.price_days, 260,
        "one day for each price of the export but two, older than 90 days"
    );
    assert_eq!(masseret_diesel(&pool).await, [(2.25, 2.25)]);
    // A day past the 30 kept, and one inside them, counted from the day
    // of the answer.
    let today = lunaway_domain::fuel::price_day(first.fetched_at);
    for (days_ago, price) in [(30, 2.10), (29, 2.20)] {
        sqlx::query(
            "INSERT INTO fuel_price_days (station_ref, fuel, day, low_eur, high_eur) \
             VALUES ('19510002', 'diesel', $1, $2, $2)",
        )
        .bind(today - chrono::Duration::days(days_ago))
        .bind(price)
        .execute(&pool)
        .await
        .unwrap();
    }
    let lower = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(lower.price_days, 1, "only the day that moved is written");
    let higher = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(higher.price_days, 1);
    assert_eq!(
        masseret_diesel(&pool).await,
        [(2.20, 2.20), (2.19, 2.31)],
        "the day past the history is gone, the day's low and high are kept"
    );
    let same = fuel::import(&pool, &client, &cache, &config, true)
        .await
        .unwrap();
    assert_eq!(
        same.price_days, 0,
        "a poll that changes nothing writes nothing"
    );
    let cached = fuel::import(&pool, &client, &cache, &config, false)
        .await
        .unwrap();
    assert!(cached.cached);
    assert_eq!(cached.price_days, 0, "an answer read again is the same day");
}
