//! The places' tiles at the database: the services mask the tiles carry,
//! the version's cadence, and the dots tiles built ahead.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::time::Duration;

use lunaway_db::{PgPool, place_tiles};
use lunaway_domain::Service;
use uuid::Uuid;

async fn place(pool: &PgPool, lat: f64, lon: f64, services: &[Service]) -> Uuid {
    let id = Uuid::now_v7();
    let codes: Vec<String> = services.iter().map(|s| s.code().to_owned()).collect();
    sqlx::query!(
        r#"
        INSERT INTO places (id, kind, geom, overnight, services, content_hash)
        VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, 'unknown', $4, 'x')
        "#,
        id,
        lat,
        lon,
        &codes,
    )
    .execute(pool)
    .await
    .unwrap();
    id
}

async fn mask_of(pool: &PgPool, id: Uuid) -> i32 {
    sqlx::query_scalar!(
        r#"SELECT services_mask AS "m!" FROM places WHERE id = $1"#,
        id
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_stored_mask_uses_the_domain_s_bits(pool: PgPool) {
    // The tiles carry this column and the app reads it with the domain's
    // bits: the SQL list of the migration must be the domain's order.
    for s in Service::ALL {
        let id = place(&pool, 47.0, 2.0, &[*s]).await;
        assert_eq!(
            mask_of(&pool, id).await,
            1 << s.bit(),
            "{s}: the database and the domain disagree on its bit"
        );
    }
    let all = place(&pool, 47.0, 2.0, Service::ALL).await;
    assert_eq!(
        i64::from(mask_of(&pool, all).await),
        i64::from(Service::mask(Service::ALL))
    );
    let none = place(&pool, 47.0, 2.0, &[]).await;
    assert_eq!(mask_of(&pool, none).await, 0);
    let id = place(&pool, 47.0, 2.0, &[Service::Wifi]).await;
    sqlx::query!(
        "UPDATE places SET services = '{grey_water,black_water}' WHERE id = $1",
        id
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(
        mask_of(&pool, id).await,
        0b110,
        "the mask follows every write of the services"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_version_moves_when_places_changed_and_no_sooner_than_asked(pool: PgPool) {
    // The version's date is the migration's, so as old as the test
    // template: dated a minute ago here, the interval below is measured
    // from the test and not from when the template was migrated.
    sqlx::query!("UPDATE place_layer SET changed_at = now() - interval '1 minute'")
        .execute(&pool)
        .await
        .unwrap();
    let start = place_tiles::layer_version(&pool).await.unwrap();
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::ZERO)
            .await
            .unwrap(),
        None,
        "nothing written since the version: devices keep their tiles"
    );
    place(&pool, 47.0, 2.0, &[]).await;
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::from_secs(900))
            .await
            .unwrap(),
        None,
        "a version younger than the interval stays"
    );
    let moved = place_tiles::publish_layer(&pool, Duration::ZERO)
        .await
        .unwrap();
    assert_eq!(moved, Some(start.version + 1));
    let v = place_tiles::layer_version(&pool).await.unwrap();
    let head: i64 = sqlx::query_scalar!(r#"SELECT max(updated_seq) AS "s!" FROM places"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(v.published_seq, head, "the version covers the feed's end");
    assert_eq!(
        place_tiles::publish_layer(&pool, Duration::ZERO)
            .await
            .unwrap(),
        None,
        "published once"
    );
    assert_eq!(
        place_tiles::publish_layer_now(&pool).await.unwrap(),
        start.version + 2,
        "a takedown moves it whatever the interval"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_tiles_built_ahead_are_every_dots_tile_holding_a_place(pool: PgPool) {
    // Annecy and Brest: two tiles at zoom 9, one at zoom 2.
    place(&pool, 45.899, 6.129, &[]).await;
    place(&pool, 48.39, -4.49, &[]).await;
    let tiles = place_tiles::dots_tiles_with_places(&pool).await.unwrap();
    let zooms = place_tiles::DOTS_MIN_ZOOM..place_tiles::PIN_ZOOM;
    for z in zooms.clone() {
        let n = tiles.iter().filter(|t| t.0 == z).count();
        assert!((1..=2).contains(&n), "zoom {z}: {n} tiles");
    }
    assert!(tiles.iter().all(|t| zooms.contains(&t.0)));
    assert_eq!(
        tiles
            .iter()
            .filter(|t| t.0 == place_tiles::PIN_ZOOM - 1)
            .count(),
        2
    );
    assert!(
        tiles.windows(2).all(|w| w[0].0 <= w[1].0),
        "the lowest zooms first: they cost the most"
    );
    // Each listed tile holds its place: a dots tile built for it is not
    // empty.
    for &(z, x, y) in &tiles {
        let mvt = place_tiles::tile(&pool, z, x, y, 4_000).await.unwrap();
        assert!(!mvt.is_empty(), "{z}/{x}/{y} is listed but empty");
    }
}
