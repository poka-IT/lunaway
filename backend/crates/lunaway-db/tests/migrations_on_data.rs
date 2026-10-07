//! Migrations run on a populated database, as the production one is: the
//! rows an older release wrote must pass every later migration and come out
//! as the new schema says.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::{MIGRATOR, PgPool};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

/// The last migration before reviews and photos got a source of their own.
const BEFORE_REVIEW_SOURCES: i64 = 20_261_006_120_200;
/// The last migration before the places' words for the search.
const BEFORE_SEARCH_WORDS: i64 = 20_261_008_131_100;

/// A database of its own, migrated up to `version`: the test template
/// already holds every migration, so this one starts from `template0`.
async fn database_at(pool: &PgPool, version: i64) -> (PgPool, String) {
    let name = format!("lunaway_mig_{}", Uuid::now_v7().simple());
    // The name is ours, made of a UUID's hex digits.
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "CREATE DATABASE {name} TEMPLATE template0"
    )))
    .execute(pool)
    .await
    .unwrap();
    let db = PgPoolOptions::new()
        .max_connections(2)
        .connect_with((*pool.connect_options()).clone().database(&name))
        .await
        .unwrap();
    MIGRATOR.run_to(version, &db).await.unwrap();
    (db, name)
}

#[sqlx::test(migrations = false)]
async fn existing_reviews_and_photos_move_to_their_cc_by_source(pool: PgPool) {
    let (db, name) = database_at(&pool, BEFORE_REVIEW_SOURCES).await;
    let (place, account) = (Uuid::now_v7(), Uuid::now_v7());
    // Rows as the release before the migration wrote them.
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash)
         VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(6.1, 45.9), 4326)::geography, 'unknown', 'h')",
    )
    .bind(place)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO accounts (id, pseudonym) VALUES ($1, 'Hérisson du Vercors')")
        .bind(account)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO reviews (id, place_id, account_id, stars, body, status)
         VALUES ($1, $2, $3, 4, 'Calme la nuit, quai propre.', 'published'),
                ($4, $2, NULL, 3, NULL, 'published')",
    )
    .bind(Uuid::now_v7())
    .bind(place)
    .bind(account)
    .bind(Uuid::now_v7())
    .execute(&db)
    .await
    .unwrap();
    let path = format!("photos/ab/cd/{}.webp", "e".repeat(64));
    sqlx::query(
        "INSERT INTO photos (id, place_id, account_id, status, path, thumb_path, width, height,
                             thumb_width, thumb_height, thumbhash)
         VALUES ($1, $2, $3, 'published', $4, $4, 2048, 1536, 512, 384, '\\x01')",
    )
    .bind(Uuid::now_v7())
    .bind(place)
    .bind(account)
    .bind(&path)
    .execute(&db)
    .await
    .unwrap();

    MIGRATOR.run(&db).await.unwrap();

    let sources: Vec<(String, i64)> = sqlx::query_as(
        "SELECT source_id, count(*) FROM (
             SELECT source_id FROM reviews UNION ALL SELECT source_id FROM photos) s
         GROUP BY 1",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(
        sources,
        [("community-cc-by".to_owned(), 3)],
        "every review, rating and photo already published is filed under CC BY 4.0"
    );
    let licence: String =
        sqlx::query_scalar("SELECT licence FROM sources WHERE id = 'community-cc-by'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(licence, "CC BY 4.0");
    db.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = false)]
async fn existing_places_get_their_search_words_and_keep_them_current(pool: PgPool) {
    let (db, name) = database_at(&pool, BEFORE_SEARCH_WORDS).await;
    let place = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO places (id, kind, name, city, geom, overnight, content_hash)
         VALUES ($1, 'campsite', 'Camping des Châtaigniers', 'Saint-Étienne',
                 ST_SetSRID(ST_MakePoint(4.39, 45.43), 4326)::geography, 'unknown', 'h')",
    )
    .bind(place)
    .execute(&db)
    .await
    .unwrap();

    MIGRATOR.run(&db).await.unwrap();

    let vector = |db: PgPool| async move {
        sqlx::query_scalar::<_, String>("SELECT search_vector::text FROM places WHERE id = $1")
            .bind(place)
            .fetch_one(&db)
            .await
            .unwrap()
    };
    let words = |db: PgPool| async move {
        sqlx::query_scalar::<_, String>("SELECT word FROM place_search_words ORDER BY word")
            .fetch_all(&db)
            .await
            .unwrap()
    };
    assert_eq!(
        vector(db.clone()).await,
        "'camping':1 'chataigniers':3 'des':2 'etienne':5 'saint':4",
        "folded, split where the query is split, in order for a phrase"
    );
    assert_eq!(
        words(db.clone()).await,
        ["camping", "chataigniers", "des", "etienne", "saint"]
    );
    sqlx::query("UPDATE places SET name = 'Camping des Oliviers' WHERE id = $1")
        .bind(place)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        vector(db.clone()).await,
        "'camping':1 'des':2 'etienne':5 'oliviers':3 'saint':4",
        "a write recomputes the words"
    );
    assert!(
        words(db.clone()).await.contains(&"oliviers".to_owned()),
        "and adds the new ones to those a typo is corrected to"
    );
    db.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&pool)
    .await
    .unwrap();
}
