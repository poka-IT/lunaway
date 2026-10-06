//! The sync region the database gives a place agrees with the domain's
//! rule, and a place on the shore takes the commune next to it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::PgPool;
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
