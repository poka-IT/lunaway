//! Migrations run on a populated database, as the production one is: the
//! rows an older release wrote must pass every later migration and come out
//! as the new schema says.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use lunaway_db::{MIGRATOR, PgPool};
use sqlx::{migrate::Migrate, postgres::PgPoolOptions};
use uuid::Uuid;

/// The last migration before reviews and photos got a source of their own.
const BEFORE_REVIEW_SOURCES: i64 = 20_261_006_120_200;
/// The last migration before the places' words for the search.
const BEFORE_SEARCH_WORDS: i64 = 20_261_008_131_100;
/// The last migration before the tiles' low zooms were kept in tables.
const BEFORE_TILE_PYRAMIDS: i64 = 20_261_008_200_000;
/// The filters' rating (`places.filter_rating`) and the towns of the
/// search: applied on the production database before the tiles' tables,
/// which are older migrations.
const RATING_AND_TOWNS: std::ops::RangeInclusive<i64> = 20_261_008_220_000..=20_261_008_220_100;
/// The last migration before the dots carried the season.
const BEFORE_DOTS_SEASON: i64 = 20_261_009_020_010;
/// The last migration before the restaurants and the sights.
const BEFORE_FOOD_SIGHTS: i64 = 20_261_009_090_000;

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

#[sqlx::test(migrations = false)]
async fn existing_places_and_points_fill_the_tiles_low_zooms_and_move_the_versions(pool: PgPool) {
    let (db, name) = database_at(&pool, BEFORE_TILE_PYRAMIDS).await;
    // A place and two points as the release before wrote them: a pharmacy
    // and a pizza machine.
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash)
         VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography,
                 'unknown', 'h')",
    )
    .bind(Uuid::now_v7())
    .execute(&db)
    .await
    .unwrap();
    for (kind, category) in [("pharmacy", "health"), ("vending_pizza", "vending")] {
        sqlx::query(
            "INSERT INTO pois (id, source_id, external_id, category, kind, geom, data, raw,
                               fetched_at)
             VALUES ($1, 'osm', $2, $3, $2, ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography,
                     '{}', '{}', now())",
        )
        .bind(Uuid::now_v7())
        .bind(kind)
        .bind(category)
        .execute(&db)
        .await
        .unwrap();
    }
    let versions = |db: PgPool| async move {
        sqlx::query_as::<_, (i64, i64)>(
            "SELECT p.version, q.version FROM place_layer p, poi_layer q",
        )
        .fetch_one(&db)
        .await
        .unwrap()
    };
    let before = versions(db.clone()).await;

    MIGRATOR.run(&db).await.unwrap();

    let after = versions(db.clone()).await;
    assert_eq!(
        after,
        (before.0 + 2, before.1 + 2),
        "devices hold a year the tiles of the versions before: both move, at the dots' fill and \
         again at the rating's"
    );
    let count = |db: PgPool, sql: &'static str| async move {
        sqlx::query_scalar::<_, i64>(sqlx::AssertSqlSafe(sql))
            .fetch_one(&db)
            .await
            .unwrap()
    };
    assert_eq!(
        count(db.clone(), "SELECT count(DISTINCT z) FROM place_dots").await,
        8,
        "the place is a dot at each zoom from 2 to 9"
    );
    assert_eq!(
        count(
            db.clone(),
            "SELECT (SELECT count(*) FROM (
                         (SELECT * FROM place_dots_computed
                          EXCEPT ALL
                          SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots)
                         UNION ALL
                         (SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots
                          EXCEPT ALL
                          SELECT * FROM place_dots_computed)) dots)
                  + (SELECT count(*) FROM (
                         (SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_sources
                          EXCEPT ALL
                          SELECT place_id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_members)
                         UNION ALL
                         (SELECT place_id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_members
                          EXCEPT ALL
                          SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_sources)) m)"
        )
        .await,
        0,
        "the dots and the members are those of the places, both ways"
    );
    assert_eq!(
        count(db.clone(), "SELECT count(*) FROM poi_cluster_cells").await,
        12,
        "zooms 6 to 9: the pharmacy, the machine in its category, the machine per kind"
    );
    assert_eq!(
        count(db.clone(), "SELECT dots_seq FROM place_layer").await,
        count(db.clone(), "SELECT max(updated_seq) FROM places").await,
        "the dots cover the change feed up to the fill"
    );
    db.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = false)]
async fn the_dots_carry_the_rating_whichever_migration_ran_first(pool: PgPool) {
    // On a new database the dots' tables (20261008210100) come before the
    // rating (20261008220000); production had the rating first, the dots'
    // migrations arriving later with an older version.
    for rating_first in [false, true] {
        let (db, name) = database_at(&pool, BEFORE_TILE_PYRAMIDS).await;
        let rated = Uuid::now_v7();
        if rating_first {
            let mut conn = db.acquire().await.unwrap();
            for m in MIGRATOR
                .iter()
                .filter(|m| RATING_AND_TOWNS.contains(&m.version))
            {
                conn.apply("_sqlx_migrations", m).await.unwrap();
            }
            drop(conn);
            sqlx::query(
                "INSERT INTO places (id, kind, geom, overnight, filter_rating, content_hash)
                 VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography,
                         'unknown', 4.6, 'h')",
            )
            .bind(rated)
            .execute(&db)
            .await
            .unwrap();
        } else {
            sqlx::query(
                "INSERT INTO places (id, kind, geom, overnight, content_hash)
                 VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography,
                         'unknown', 'h')",
            )
            .bind(rated)
            .execute(&db)
            .await
            .unwrap();
        }

        MIGRATOR.run(&db).await.unwrap();

        if !rating_first {
            // The worker rates the place, as `place_ratings` does: a new
            // position in the change feed, then a version.
            sqlx::query(
                "UPDATE places SET filter_rating = 4.6, updated_seq = nextval('place_change_seq')
                 WHERE id = $1",
            )
            .bind(rated)
            .execute(&db)
            .await
            .unwrap();
            lunaway_db::place_tiles::publish_layer_now(&db)
                .await
                .unwrap();
        }
        let steps: Vec<Option<i32>> =
            sqlx::query_scalar("SELECT DISTINCT r FROM place_dots ORDER BY 1")
                .fetch_all(&db)
                .await
                .unwrap();
        assert_eq!(
            steps,
            [Some(45)],
            "rating first: {rating_first}; the dots of a place rated 4.6 stand at 4.5"
        );
        let drift: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM (
                 (SELECT * FROM place_dots_computed
                  EXCEPT ALL
                  SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots)
                 UNION ALL
                 (SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots
                  EXCEPT ALL
                  SELECT * FROM place_dots_computed)) d",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(drift, 0, "rating first: {rating_first}");
        db.close().await;
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DROP DATABASE {name} WITH (FORCE)"
        )))
        .execute(&pool)
        .await
        .unwrap();
    }
}

/// Dots or members that differ from what the live places make, both ways.
async fn dots_drift(db: &PgPool) -> i64 {
    sqlx::query_scalar(
        "SELECT (SELECT count(*) FROM (
                     (SELECT * FROM place_dots_computed
                      EXCEPT ALL
                      SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots)
                     UNION ALL
                     (SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM place_dots
                      EXCEPT ALL
                      SELECT * FROM place_dots_computed)) dots)
              + (SELECT count(*) FROM (
                     (SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_sources
                      EXCEPT ALL
                      SELECT place_id, kind, night, s, price, h, r, o1, o2, gx, gy
                      FROM place_dot_members)
                     UNION ALL
                     (SELECT place_id, kind, night, s, price, h, r, o1, o2, gx, gy
                      FROM place_dot_members
                      EXCEPT ALL
                      SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy
                      FROM place_dot_sources)) members)",
    )
    .fetch_one(db)
    .await
    .unwrap()
}

#[sqlx::test(migrations = false)]
async fn the_dots_take_the_season_without_a_rebuild_and_follow_it(pool: PgPool) {
    // A place as the release before wrote it, with its dots.
    let (db, name) = database_at(&pool, BEFORE_TILE_PYRAMIDS).await;
    let place = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash)
         VALUES ($1, 'campsite', ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography,
                 'allowed', 'h')",
    )
    .bind(place)
    .execute(&db)
    .await
    .unwrap();
    MIGRATOR.run_to(BEFORE_DOTS_SEASON, &db).await.unwrap();
    let dots: i64 = sqlx::query_scalar("SELECT count(*) FROM place_dots")
        .fetch_one(&db)
        .await
        .unwrap();

    MIGRATOR.run(&db).await.unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM place_dots")
            .fetch_one(&db)
            .await
            .unwrap(),
        dots,
        "the dots stay as they were: nothing is rebuilt under the API's reads"
    );
    assert_eq!(dots_drift(&db).await, 0, "no place has a season yet");

    // The conflation gives it a season: the next publication moves its dots.
    sqlx::query(
        "UPDATE places SET opening_season = '{92,305}', updated_seq = nextval('place_change_seq')
         WHERE id = $1",
    )
    .bind(place)
    .execute(&db)
    .await
    .unwrap();
    lunaway_db::place_tiles::publish_layer_now(&db)
        .await
        .unwrap();
    let seasons: Vec<Option<i32>> =
        sqlx::query_scalar("SELECT DISTINCT o1 FROM place_dots ORDER BY 1")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(seasons, [Some(92_305)]);
    assert_eq!(dots_drift(&db).await, 0);
    db.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = false)]
async fn the_dots_refuse_a_season_they_would_miss(pool: PgPool) {
    let (db, name) = database_at(&pool, BEFORE_DOTS_SEASON).await;
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, opening_season, content_hash)
         VALUES ($1, 'campsite', ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography,
                 'allowed', '{92,305}', 'h')",
    )
    .bind(Uuid::now_v7())
    .execute(&db)
    .await
    .unwrap();
    let err = MIGRATOR.run(&db).await.unwrap_err();
    assert!(
        err.to_string().contains("places have a season already"),
        "the deploy stops rather than leave dots without their season: {err}"
    );
    db.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&pool)
    .await
    .unwrap();
}

#[sqlx::test(migrations = false)]
async fn the_tourist_offices_stored_move_to_the_sights_and_the_codes_are_checked(pool: PgPool) {
    let (db, name) = database_at(&pool, BEFORE_FOOD_SIGHTS).await;
    let office = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO pois (id, source_id, external_id, category, kind, geom, data, raw,
                           fetched_at, changed_at)
         VALUES ($1, 'osm', 'node/1', 'services', 'tourist_office',
                 ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography, '{}', '{}', now(),
                 now() - interval '1 day')",
    )
    .bind(office)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("UPDATE poi_layer SET pending_since = NULL")
        .execute(&db)
        .await
        .unwrap();

    MIGRATOR.run(&db).await.unwrap();

    let (category, moved) = sqlx::query_as::<_, (String, bool)>(
        "SELECT category, changed_at > now() - interval '1 hour' FROM pois WHERE id = $1",
    )
    .bind(office)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        category, "sights",
        "a tourist office tells of what there is to see"
    );
    assert!(
        moved,
        "a tile shows its new category: the row says it changed"
    );
    let pending = sqlx::query_scalar::<_, bool>("SELECT pending_since IS NOT NULL FROM poi_layer")
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(pending, "the worker publishes tiles with the new category");
    let validated = sqlx::query_scalar::<_, bool>(
        "SELECT bool_and(convalidated) FROM pg_constraint
         WHERE conname IN ('pois_category_check', 'pois_kind_check')",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(validated, "both checks hold for every row");
    let refused = sqlx::query(
        "INSERT INTO pois (id, source_id, external_id, category, kind, geom, data, raw, fetched_at)
         VALUES ($1, 'osm', 'node/2', 'food', 'castle',
                 ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography, '{}', '{}', now())",
    )
    .bind(Uuid::now_v7())
    .execute(&db)
    .await;
    assert!(
        refused.is_err(),
        "a kind the domain does not know is refused"
    );
    db.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&pool)
    .await
    .unwrap();
}
