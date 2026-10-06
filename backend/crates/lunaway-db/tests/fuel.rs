//! The fuel stations as places to refuel: their position read from the
//! feed's row, the order of a search around a point, a stale price left
//! out, and the days of price history.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{DateTime, Duration, NaiveDate, Utc};
use lunaway_db::{
    PgPool,
    fuel::{self, PriceSeen},
};
use lunaway_domain::{
    BBox, Position,
    poi::{FuelKind, FuelPrice, FuelShortage, FuelStation, FuelTile, ShortageKind},
};

fn station(lat: f64, lon: f64, diesel: Option<(f64, DateTime<Utc>)>, out: bool) -> FuelStation {
    FuelStation {
        prices: diesel
            .map(|(price_eur, updated_at)| FuelPrice {
                fuel: FuelKind::Diesel,
                price_eur,
                updated_at,
            })
            .into_iter()
            .collect(),
        shortages: out
            .then_some(FuelShortage {
                fuel: FuelKind::Diesel,
                kind: ShortageKind::Temporary,
                since: None,
            })
            .into_iter()
            .collect(),
        services: Vec::new(),
        automate_24_24: false,
        highway: false,
        position: Some(Position::new(lat, lon).unwrap()),
        address: None,
        tile: FuelTile::default(),
    }
}

async fn put(pool: &PgPool, key: &str, s: &FuelStation) {
    sqlx::query(
        "INSERT INTO poi_join_records (source_id, ref, data, raw, fetched_at) \
         VALUES ('prix-carburants', $1, $2, '{}', now())",
    )
    .bind(key)
    .bind(serde_json::to_value(s).unwrap())
    .execute(pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_search_around_a_point_puts_the_cheapest_first_and_a_stale_price_nowhere(pool: PgPool) {
    let now = Utc::now();
    let fresh = Some((2.30, now - Duration::hours(2)));
    // Around Brive: two at the same price, one cheaper but out of diesel,
    // one cheaper still but not updated for half a year, one too far.
    put(&pool, "1", &station(45.160, 1.530, fresh, false)).await;
    put(&pool, "2", &station(45.150, 1.530, fresh, false)).await;
    put(&pool, "3", &station(45.158, 1.532, Some((2.10, now)), true)).await;
    put(
        &pool,
        "4",
        &station(
            45.158,
            1.532,
            Some((1.90, now - Duration::days(180))),
            false,
        ),
    )
    .await;
    put(
        &pool,
        "5",
        &station(45.158, 1.532, Some((2.20, now)), false),
    )
    .await;
    put(
        &pool,
        "6",
        &station(45.400, 1.532, Some((1.80, now)), false),
    )
    .await;
    let at = Position::new(45.158, 1.532).unwrap();
    let since = now - Duration::days(90);
    let found = fuel::near(&pool, FuelKind::Diesel, at, 5_000.0, since, 10)
        .await
        .unwrap();
    let order: Vec<&str> = found.iter().map(|s| s.station_ref.as_str()).collect();
    assert_eq!(
        order,
        ["5", "1", "2", "3"],
        "the cheapest, equal prices by distance, a shortage last; a stale price and a far \
         station left out"
    );
    assert!(found[0].distance_m.unwrap() < 1.0);
    assert!(found[0].poi.is_none(), "no OpenStreetMap element names it");

    let area = BBox::new(45.0, 1.4, 45.2, 1.6).unwrap();
    let mut boxed: Vec<(String, f64, bool)> = fuel::in_box(&pool, FuelKind::Diesel, area, since)
        .await
        .unwrap()
        .into_iter()
        .map(|p| (p.station_ref, p.price_eur, p.in_shortage))
        .collect();
    boxed.sort_by(|a, b| a.0.cmp(&b.0));
    assert_eq!(
        boxed,
        [
            ("1".to_owned(), 2.30, false),
            ("2".to_owned(), 2.30, false),
            ("3".to_owned(), 2.10, true),
            ("5".to_owned(), 2.20, false),
        ]
    );
    let read = fuel::by_refs(&pool, &["3".to_owned(), "9".to_owned()])
        .await
        .unwrap();
    assert_eq!(read.len(), 1);
    assert_eq!(read[0].position, Position::new(45.158, 1.532).unwrap());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_day_keeps_its_low_and_high_and_the_history_its_30_days(pool: PgPool) {
    let day = NaiveDate::from_ymd_opt(2026, 10, 6).unwrap();
    let seen = |price_eur| {
        vec![
            PriceSeen {
                station_ref: "19510002".to_owned(),
                fuel: FuelKind::Diesel,
                price_eur,
            },
            PriceSeen {
                station_ref: "19510002".to_owned(),
                fuel: FuelKind::Lpg,
                price_eur: 1.05,
            },
        ]
    };
    assert_eq!(
        fuel::record_price_days(&pool, &seen(2.25), day)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        fuel::record_price_days(&pool, &seen(2.25), day)
            .await
            .unwrap(),
        0,
        "the same prices rewrite nothing"
    );
    assert_eq!(
        fuel::record_price_days(&pool, &seen(2.19), day)
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        fuel::record_price_days(&pool, &seen(2.31), day)
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        fuel::record_price_days(&pool, &seen(2.22), day)
            .await
            .unwrap(),
        0
    );
    let next = day.succ_opt().unwrap();
    assert_eq!(
        fuel::record_price_days(&pool, &seen(2.22), next)
            .await
            .unwrap(),
        2
    );

    let days = fuel::price_days(&pool, &["19510002".to_owned()], day)
        .await
        .unwrap();
    let diesel: Vec<(NaiveDate, f64, f64)> = days
        .iter()
        .filter(|d| d.fuel == FuelKind::Diesel)
        .map(|d| (d.day.day, d.day.low_eur, d.day.high_eur))
        .collect();
    assert_eq!(diesel, [(day, 2.19, 2.31), (next, 2.22, 2.22)]);
    assert_eq!(
        fuel::price_days(&pool, &["19510002".to_owned()], next)
            .await
            .unwrap()
            .len(),
        2,
        "from the next day on: both fuels of that day"
    );
    assert_eq!(fuel::purge_price_days(&pool, next).await.unwrap(), 2);
    assert_eq!(
        fuel::price_days(&pool, &["19510002".to_owned()], day)
            .await
            .unwrap()
            .len(),
        2
    );
}
