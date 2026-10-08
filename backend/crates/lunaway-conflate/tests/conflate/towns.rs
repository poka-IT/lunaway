use std::time::Duration;

use lunaway_db::{PgPool, towns};
use uuid::Uuid;

async fn place_in_viviers(pool: &PgPool) {
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, city, postcode, country_code, content_hash) \
         VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(4.68, 44.48), 4326)::geography, \
                 'unknown', 'Viviers', '07220', 'fr', 'x')",
    )
    .bind(Uuid::now_v7())
    .execute(pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_towns_are_built_when_none_are_stored_then_with_the_tiles(pool: PgPool) {
    // A version as fresh as can be: none is due for an hour.
    sqlx::query("UPDATE place_layer SET changed_at = now()")
        .execute(&pool)
        .await
        .unwrap();
    place_in_viviers(&pool).await;
    let hour = Duration::from_secs(3_600);
    assert_eq!(
        lunaway_conflate::publish_place_layer(&pool, hour)
            .await
            .unwrap(),
        None,
        "no version is due"
    );
    let found = towns::search(&pool, "viviers", 6).await.unwrap();
    assert_eq!(
        found.first().map(|t| t.places),
        Some(1),
        "the empty table alone asks for a rebuild"
    );
    place_in_viviers(&pool).await;
    lunaway_conflate::publish_place_layer(&pool, hour)
        .await
        .unwrap();
    assert_eq!(
        towns::search(&pool, "viviers", 6).await.unwrap()[0].places,
        1,
        "without a new version of the tiles, the towns wait"
    );
    lunaway_conflate::publish_place_layer(&pool, Duration::ZERO)
        .await
        .unwrap()
        .expect("a place was written: a new version");
    assert_eq!(
        towns::search(&pool, "viviers", 6).await.unwrap()[0].places,
        2,
        "the new version rebuilds them"
    );
}
