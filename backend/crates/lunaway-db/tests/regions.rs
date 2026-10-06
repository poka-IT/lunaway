//! The sync region the database gives a place agrees with the domain's
//! rule, and a place on the shore takes the commune next to it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::PgPool;
use lunaway_db::places::{Change, changes_in_region};
use lunaway_domain::region::{ATTACHED, french_region_of_department, sync_region_of};

#[sqlx::test(migrations = "../../migrations")]
async fn the_database_and_the_domain_give_the_same_region(pool: PgPool) {
    let mut cases: Vec<(Option<String>, Option<String>)> = (1..=95)
        .filter(|n| *n != 20)
        .map(|n| (Some("FR".to_owned()), Some(format!("{n:02}001"))))
        .collect();
    cases.extend([
        (Some("FR".into()), Some("2A004".into())),
        (Some("FR".into()), Some("2B033".into())),
        (Some("FR".into()), None),
        (Some("fr".into()), Some("74010".into())),
        (Some("DE".into()), None),
        (Some("es".into()), None),
        (None, Some("74010".into())),
    ]);
    cases.extend(ATTACHED.iter().map(|(c, _)| (Some((*c).to_owned()), None)));
    for (country, commune) in cases {
        let from_db: Option<String> = sqlx::query_scalar("SELECT lunaway_sync_region($1, $2)")
            .bind(&country)
            .bind(&commune)
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(
            from_db,
            sync_region_of(country.as_deref(), commune.as_deref()),
            "{country:?} {commune:?}: the packs and the feed must cut regions as the domain does"
        );
    }
    assert!(french_region_of_department("74").is_some());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_place_on_the_shore_takes_the_nearest_commune(pool: PgPool) {
    // A square commune near Brest, and two places: one inside, one 300 m
    // out to sea, and one 5 km out, which no commune should claim.
    sqlx::query(
        "INSERT INTO municipalities (code, name, geom, fetched_at) VALUES \
         ('29019', 'Brest', ST_Multi(ST_MakeEnvelope(-4.50, 48.38, -4.45, 48.42, 4326)), now())",
    )
    .execute(&pool)
    .await
    .unwrap();
    // The fourth is as close as the second, but foreign: a place across a
    // border must not take a French commune.
    for (id, lon, country) in [
        (1, -4.47, "FR"),
        (2, -4.446, "FR"),
        (3, -4.38, "FR"),
        (4, -4.446, "DE"),
    ] {
        sqlx::query(
            "INSERT INTO places (id, kind, geom, overnight, services, activities, country_code, \
                                 provenance, content_hash, updated_seq) \
             VALUES ($1, 'campsite', ST_SetSRID(ST_MakePoint($2, 48.40), 4326)::geography, \
                     'unknown', '{}', '{}', $3, '[]', 'x', nextval('place_change_seq'))",
        )
        .bind(uuid::Uuid::from_u128(id))
        .bind(lon)
        .bind(country)
        .execute(&pool)
        .await
        .unwrap();
    }
    let mut tx = lunaway_db::conflation::begin_writer(&pool).await.unwrap();
    lunaway_db::municipalities::refresh_places(&mut tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let rows: Vec<(uuid::Uuid, Option<String>, Option<String>)> =
        sqlx::query_as("SELECT id, municipality, region FROM places ORDER BY id")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(
        rows,
        [
            (
                uuid::Uuid::from_u128(1),
                Some("Brest".into()),
                Some("FR-BRE".into())
            ),
            (
                uuid::Uuid::from_u128(2),
                Some("Brest".into()),
                Some("FR-BRE".into())
            ),
            (uuid::Uuid::from_u128(3), None, Some("FR".into())),
            (uuid::Uuid::from_u128(4), None, Some("DE".into())),
        ],
        "the shore's campsite syncs with Brittany; a point far out stays outside every commune"
    );
}

async fn insert_place(pool: &PgPool, id: u128, country: &str) {
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, services, activities, country_code, \
                             provenance, content_hash, updated_seq) \
         VALUES ($1, 'campsite', ST_SetSRID(ST_MakePoint(10.0, 50.0), 4326)::geography, \
                 'unknown', '{}', '{}', $2, '[]', 'x', nextval('place_change_seq'))",
    )
    .bind(uuid::Uuid::from_u128(id))
    .bind(country)
    .execute(pool)
    .await
    .unwrap();
}

async fn move_place(pool: &PgPool, id: u128, country: &str) {
    sqlx::query(
        "UPDATE places SET country_code = $2, updated_seq = nextval('place_change_seq') \
         WHERE id = $1",
    )
    .bind(uuid::Uuid::from_u128(id))
    .bind(country)
    .execute(pool)
    .await
    .unwrap();
}

fn summary(changes: &[Change]) -> Vec<(char, u128)> {
    changes
        .iter()
        .map(|c| match c {
            Change::Upsert(p) => ('u', p.id.as_u128()),
            Change::Delete { id, .. } => ('d', id.as_u128()),
            Change::Left { id, .. } => ('l', id.as_u128()),
        })
        .collect()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_region_feed_pages_its_departures_and_skips_the_places_that_came_back(pool: PgPool) {
    for id in 1..=5 {
        insert_place(&pool, id, "DE").await;
    }
    let since: i64 = sqlx::query_scalar("SELECT max(updated_seq) FROM places")
        .fetch_one(&pool)
        .await
        .unwrap();
    move_place(&pool, 1, "AT").await;
    move_place(&pool, 2, "AT").await;
    move_place(&pool, 3, "AT").await;
    move_place(&pool, 3, "DE").await;
    move_place(&pool, 5, "AT").await;
    move_place(&pool, 5, "DE").await;
    move_place(&pool, 5, "AT").await;
    move_place(&pool, 4, "DE").await;

    // One change per page: more departures than a page holds cut it at the
    // last one it lists, and the cursor resumes after it.
    let mut pages = Vec::new();
    let mut cursor = since;
    loop {
        let (page, more) = changes_in_region(&pool, "DE", cursor, 1, true)
            .await
            .unwrap();
        cursor = page.last().map_or(cursor, Change::seq);
        pages.push(summary(&page));
        if !more {
            break;
        }
        assert!(pages.len() < 10, "the walk must end");
    }
    assert_eq!(
        pages,
        [
            vec![('l', 1)],
            vec![('l', 2), ('u', 3)],
            vec![('l', 5)],
            vec![('l', 5), ('u', 4)],
        ],
        "every departure reaches the device, and a place back in the region is not removed"
    );

    // One page: a place that left twice is listed once, at its last departure.
    let (all, more) = changes_in_region(&pool, "DE", since, 100, true)
        .await
        .unwrap();
    assert!(!more);
    assert_eq!(
        summary(&all),
        [('l', 1), ('l', 2), ('u', 3), ('l', 5), ('u', 4)]
    );
    let seqs: Vec<i64> = all.iter().map(Change::seq).collect();
    assert!(
        seqs.windows(2).all(|w| w[0] < w[1]),
        "a page is in feed order, so its last position is the cursor"
    );
}
