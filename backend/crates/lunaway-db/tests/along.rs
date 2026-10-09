//! What a search along a route reads from a cell of its band: when a cell
//! holds more than its share, the same candidates whatever plan the
//! database picks, those nearest the cell's centre.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_db::{
    PgPool,
    along::{self, AlongPlaces},
    pois::{self, NewPoi},
};
use lunaway_domain::{
    Position, SourceId,
    fuel::CellBox,
    poi::{PoiKind, PoiRecord},
};
use uuid::Uuid;

/// A cell of 0.02 degrees around (45.0, 1.0).
const CELL: CellBox = CellBox {
    south: 44.99,
    west: 0.99,
    north: 45.01,
    east: 1.01,
};

/// Five points east of the centre, the nearest first, by name.
fn east_of_centre(i: u32) -> Position {
    Position::new(45.0, 1.0 + 0.001 * f64::from(i + 1)).unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_full_cell_keeps_the_points_nearest_its_centre(pool: PgPool) {
    let raw = serde_json::value::to_raw_value(&serde_json::json!({})).unwrap();
    // Written farthest first, so neither the table's order nor the ids'
    // give the answer.
    let records: Vec<(String, PoiRecord)> = (0..5)
        .rev()
        .map(|i| {
            let mut r = PoiRecord::new(PoiKind::Toilets, east_of_centre(i));
            r.name = Some(format!("t{i}"));
            (format!("node/{i}"), r)
        })
        .collect();
    let rows: Vec<NewPoi<'_>> = records
        .iter()
        .map(|(id, r)| NewPoi {
            external_id: id,
            external_url: None,
            record: r,
            raw: &raw,
            fetched_at: Utc.with_ymd_and_hms(2026, 10, 5, 22, 0, 0).unwrap(),
            scope: Some("FR"),
        })
        .collect();
    pois::upsert(&pool, &SourceId::OSM, &rows).await.unwrap();
    let got = along::pois(&pool, &[CELL], &[PoiKind::Toilets], 2)
        .await
        .unwrap();
    let mut at: Vec<f64> = got.iter().map(|p| p.position.lon()).collect();
    at.sort_by(f64::total_cmp);
    assert_eq!(
        at,
        [east_of_centre(0).lon(), east_of_centre(1).lon()],
        "the two nearest the centre"
    );

    for i in (0..5).rev() {
        let p = east_of_centre(i);
        sqlx::query!(
            r#"
            INSERT INTO places (id, kind, geom, overnight, content_hash)
            VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography,
                    'allowed', 'x')
            "#,
            Uuid::now_v7(),
            p.lat(),
            p.lon(),
        )
        .execute(&pool)
        .await
        .unwrap();
    }
    let got = along::places(&pool, &[CELL], &AlongPlaces::default(), 2)
        .await
        .unwrap();
    let mut at: Vec<f64> = got.iter().map(|p| p.position.lon()).collect();
    at.sort_by(f64::total_cmp);
    assert_eq!(
        at,
        [east_of_centre(0).lon(), east_of_centre(1).lon()],
        "the same for the places"
    );
}
