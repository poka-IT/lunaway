//! The season filter of the queries (`lunaway_season_covers`, migration
//! 20261009020000) says what the domain says (`Season::covers`): the API's
//! lists, the tiles and the devices keep the same places.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::PgPool;
use lunaway_domain::season::{LAST_DAY, Season};

fn flat(ranges: &[(u16, u16)]) -> Vec<i16> {
    ranges
        .iter()
        .flat_map(|&(a, b)| [a, b])
        .map(|d| i16::try_from(d).unwrap())
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_database_covers_a_stay_exactly_when_the_domain_does(pool: PgPool) {
    let seasons: Vec<Season> = [
        vec![(1, LAST_DAY)],
        vec![(92, 305)],
        vec![(1, 91), (305, LAST_DAY)],
        vec![(60, 60)],
        vec![(92, 182), (245, 305)],
    ]
    .iter()
    .map(|r| Season::from_ranges(r).unwrap())
    .collect();
    let stays: Vec<Vec<(u16, u16)>> = vec![
        vec![(1, LAST_DAY)],
        vec![(92, 92)],
        vec![(100, 120)],
        vec![(300, 306)],
        vec![(305, 305)],
        vec![(60, 60)],
        vec![(150, 250)],
        vec![(360, LAST_DAY), (1, 3)],
        vec![(1, 3), (360, LAST_DAY)],
        vec![(200, 210), (250, 260)],
    ];
    for season in &seasons {
        for stay in &stays {
            let sql: bool = sqlx::query_scalar("SELECT lunaway_season_covers($1, $2)")
                .bind(flat(season.ranges()))
                .bind(flat(stay))
                .fetch_one(&pool)
                .await
                .unwrap();
            assert_eq!(
                sql,
                season.covers(stay),
                "season {:?}, stay {stay:?}",
                season.ranges()
            );
        }
    }
    for (season, days) in [
        (None, Some(flat(&[(1, 2)]))),
        (Some(flat(&[(92, 305)])), None),
    ] {
        let sql: bool = sqlx::query_scalar("SELECT lunaway_season_covers($1, $2)")
            .bind(season)
            .bind(days)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert!(sql, "an unknown season, or no filter, keeps the place");
    }
}
