//! The rating a place is filtered with: Lunaway users' when they rated it,
//! else the other sources' as the place's page shows them, and the worker's
//! refresh that writes it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::Utc;
use lunaway_db::{PgPool, conflation, place_ratings};
use uuid::Uuid;

async fn place(pool: &PgPool) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash) \
         VALUES ($1, 'parking', ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography, \
                 'allowed', 'x')",
    )
    .bind(id)
    .execute(pool)
    .await
    .unwrap();
    id
}

/// A record of `source` describing `place`.
async fn record(pool: &PgPool, source: &str, place: Uuid) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO source_records (id, source_id, external_id, kind, geom, data, raw, \
                                     fetched_at) \
         VALUES ($1, $2, $3, 'parking', \
                 ST_SetSRID(ST_MakePoint(6.12, 45.9), 4326)::geography, '{}', '{}', now())",
    )
    .bind(id)
    .bind(source)
    .bind(id.to_string())
    .execute(pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO place_sources (record_id, place_id) VALUES ($1, $2)")
        .bind(id)
        .bind(place)
        .execute(pool)
        .await
        .unwrap();
    id
}

/// The external community source's summary of `count` ratings averaging
/// `average`, on a record of its own for `place`.
async fn partner_rating(pool: &PgPool, place: Uuid, average: f64, count: i32) {
    let r = record(pool, "extcom", place).await;
    sqlx::query(
        "INSERT INTO external_ratings (record_id, source_id, average, count, licence, \
                                       fetched_at) \
         VALUES ($1, 'extcom', $2, $3, 'TEST-AGREEMENT', now())",
    )
    .bind(r)
    .bind(average)
    .bind(count)
    .execute(pool)
    .await
    .unwrap();
}

/// A review with `stars` of an open source on `place`.
async fn open_review(pool: &PgPool, place: Uuid, stars: i16) -> String {
    let external_id = Uuid::now_v7().to_string();
    sqlx::query(
        "INSERT INTO content_reviews (id, place_id, source_id, external_id, rating, \
                                      written_at, page_url, licence, licence_url, fetched_at) \
         VALUES ($1, $2, 'mangrove', $3, $4, now(), 'https://mangrove.reviews/x', 'CC BY 4.0', \
                 'https://creativecommons.org/licenses/by/4.0/', now())",
    )
    .bind(Uuid::now_v7())
    .bind(place)
    .bind(&external_id)
    .bind(stars)
    .execute(pool)
    .await
    .unwrap();
    external_id
}

async fn hide(pool: &PgPool, source: &str, scope: &str, key: &str) {
    sqlx::query("INSERT INTO content_hides (source_id, scope, key) VALUES ($1, $2, $3)")
        .bind(source)
        .bind(scope)
        .bind(key)
        .execute(pool)
        .await
        .unwrap();
}

/// `child` merged into `into`, as the conflation leaves an absorbed place.
async fn merge(pool: &PgPool, child: Uuid, into: Uuid) {
    sqlx::query("UPDATE places SET merged_into = $2, deleted_at = now() WHERE id = $1")
        .bind(child)
        .bind(into)
        .execute(pool)
        .await
        .unwrap();
}

async fn refresh(pool: &PgPool) -> u64 {
    let mut tx = conflation::begin_writer(pool).await.unwrap();
    let n = place_ratings::refresh_filter_ratings(&mut tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    n
}

async fn rating_and_seq(pool: &PgPool, id: Uuid) -> (Option<f64>, i64) {
    sqlx::query_as("SELECT filter_rating, updated_seq FROM places WHERE id = $1")
        .bind(id)
        .fetch_one(pool)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refresh_of_more_places_than_a_batch_writes_them_all(pool: PgPool) {
    // 2 500 places Lunaway users rated: three statements of a thousand.
    sqlx::query(
        "INSERT INTO places (id, kind, geom, overnight, content_hash, rating_avg, rating_count) \
         SELECT gen_random_uuid(), 'parking', \
                ST_SetSRID(ST_MakePoint(6 + i * 0.0001, 45.9), 4326)::geography, 'allowed', \
                'x', 3 + (i % 20) / 10.0, 1 \
         FROM generate_series(1, 2500) AS i",
    )
    .execute(&pool)
    .await
    .unwrap();
    // Each statement's rows, as the trigger of the search's words sees them.
    sqlx::raw_sql(
        "CREATE TABLE statement_rows (n bigint NOT NULL);
         CREATE FUNCTION count_statement_rows() RETURNS trigger LANGUAGE plpgsql AS $$
         BEGIN INSERT INTO statement_rows SELECT count(*) FROM written; RETURN NULL; END $$;
         CREATE TRIGGER count_statement_rows AFTER UPDATE ON places
             REFERENCING NEW TABLE AS written
             FOR EACH STATEMENT EXECUTE FUNCTION count_statement_rows();",
    )
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(refresh(&pool).await, 2_500);
    let statements: Vec<i64> = sqlx::query_scalar("SELECT n FROM statement_rows ORDER BY n DESC")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(
        statements,
        [1_000, 1_000, 500],
        "a thousand rows a statement: one statement of every place joined its rows quadratically"
    );
    let unrated: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM places \
         WHERE filter_rating IS DISTINCT FROM round(rating_avg::numeric, 1)::float8",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(unrated, 0, "every batch wrote its places");
    assert_eq!(refresh(&pool).await, 0, "and nothing is left to write");
}

#[sqlx::test(migrations = "../../migrations")]
async fn lunaway_users_rating_comes_before_the_other_sources(pool: PgPool) {
    let id = place(&pool).await;
    sqlx::query("UPDATE places SET rating_avg = 4.24, rating_count = 3 WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .unwrap();
    partner_rating(&pool, id, 2.0, 200).await;
    refresh(&pool).await;
    assert_eq!(
        rating_and_seq(&pool, id).await.0,
        Some(4.2),
        "three users' 4.24 beats 200 ratings elsewhere, rounded to one decimal"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_other_sources_count_by_how_many_ratings_each_holds(pool: PgPool) {
    let partner_only = place(&pool).await;
    // Two records of the partner on one place: 10 ratings of 4, 30 of 3.
    partner_rating(&pool, partner_only, 4.0, 10).await;
    partner_rating(&pool, partner_only, 3.0, 30).await;
    let both = place(&pool).await;
    partner_rating(&pool, both, 4.0, 2).await;
    open_review(&pool, both, 5).await;
    open_review(&pool, both, 1).await;
    let nobody = place(&pool).await;
    // A user rating count of 0 is no rating, whatever the average says.
    sqlx::query("UPDATE places SET rating_avg = 5, rating_count = 0 WHERE id = $1")
        .bind(nobody)
        .execute(&pool)
        .await
        .unwrap();
    refresh(&pool).await;
    assert_eq!(
        rating_and_seq(&pool, partner_only).await.0,
        Some(3.3),
        "(10 x 4 + 30 x 3) / 40 = 3.25, rounded half up"
    );
    assert_eq!(
        rating_and_seq(&pool, both).await.0,
        Some(3.5),
        "(2 x 4 + 5 + 1) / 4: each rating weighs the same, whatever its source"
    );
    assert_eq!(
        rating_and_seq(&pool, nobody).await.0,
        None,
        "nobody rated it"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn what_the_page_hides_does_not_rate_the_place(pool: PgPool) {
    let hidden_on_place = place(&pool).await;
    partner_rating(&pool, hidden_on_place, 4.8, 50).await;
    sqlx::query("INSERT INTO content_hides (source_id, scope, key) VALUES ('extcom', 'place', $1)")
        .bind(hidden_on_place.to_string())
        .execute(&pool)
        .await
        .unwrap();
    let by_author = place(&pool).await;
    open_review(&pool, by_author, 1).await;
    sqlx::query("UPDATE content_reviews SET author_key = repeat('a', 64) WHERE place_id = $1")
        .bind(by_author)
        .execute(&pool)
        .await
        .unwrap();
    open_review(&pool, by_author, 5).await;
    sqlx::query(
        "INSERT INTO content_hides (source_id, scope, key) \
         VALUES ('mangrove', 'author', repeat('a', 64))",
    )
    .execute(&pool)
    .await
    .unwrap();
    let kept = place(&pool).await;
    partner_rating(&pool, kept, 4.0, 5).await;
    refresh(&pool).await;
    assert_eq!(
        rating_and_seq(&pool, hidden_on_place).await.0,
        None,
        "the partner is hidden on this place: its rating is not shown, nor filtered on"
    );
    assert_eq!(
        rating_and_seq(&pool, by_author).await.0,
        Some(5.0),
        "the hidden author's review counts for nothing"
    );
    assert_eq!(rating_and_seq(&pool, kept).await.0, Some(4.0));

    // The partner's source hidden: none of its ratings count anywhere.
    sqlx::query("INSERT INTO source_switches (source_id, hidden_at) VALUES ('extcom', now())")
        .execute(&pool)
        .await
        .unwrap();
    refresh(&pool).await;
    assert_eq!(
        rating_and_seq(&pool, kept).await.0,
        None,
        "a hidden source rates no place"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_review_of_a_merged_place_rates_the_place_that_absorbed_it(pool: PgPool) {
    let root = place(&pool).await;
    let merged = place(&pool).await;
    open_review(&pool, merged, 2).await;
    sqlx::query("UPDATE places SET merged_into = $2, deleted_at = now() WHERE id = $1")
        .bind(merged)
        .bind(root)
        .execute(&pool)
        .await
        .unwrap();
    refresh(&pool).await;
    assert_eq!(
        rating_and_seq(&pool, root).await.0,
        Some(2.0),
        "the page of the place shows the reviews of the places merged into it"
    );
    assert_eq!(
        rating_and_seq(&pool, merged).await.0,
        None,
        "a merged place is not live: nothing to filter"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_the_places_whose_rating_changed_move_in_the_feed(pool: PgPool) {
    let a = place(&pool).await;
    let b = place(&pool).await;
    let unrated = place(&pool).await;
    partner_rating(&pool, a, 3.0, 4).await;
    partner_rating(&pool, b, 4.5, 4).await;
    let before = rating_and_seq(&pool, unrated).await.1;
    assert_eq!(refresh(&pool).await, 2, "a and b took a rating");
    let (rating_a, seq_a) = rating_and_seq(&pool, a).await;
    let (_, seq_b) = rating_and_seq(&pool, b).await;
    assert_eq!(rating_a, Some(3.0));
    assert!(
        seq_a > before && seq_b > before,
        "the devices get the new field"
    );
    assert_eq!(
        rating_and_seq(&pool, unrated).await.1,
        before,
        "an unrated place stays where it was"
    );

    assert_eq!(refresh(&pool).await, 0, "nothing changed, nothing written");
    assert_eq!(rating_and_seq(&pool, a).await.1, seq_a);

    // A new import moves a's average by less than the rounding: a stays.
    sqlx::query(
        "UPDATE external_ratings SET average = 3.02, fetched_at = $2 \
         WHERE record_id IN (SELECT record_id FROM place_sources WHERE place_id = $1)",
    )
    .bind(a)
    .bind(Utc::now())
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(refresh(&pool).await, 0, "3.02 still reads 3.0");
    // Then by more: only a moves.
    sqlx::query(
        "UPDATE external_ratings SET average = 3.6 \
         WHERE record_id IN (SELECT record_id FROM place_sources WHERE place_id = $1)",
    )
    .bind(a)
    .execute(&pool)
    .await
    .unwrap();
    assert_eq!(refresh(&pool).await, 1);
    let (rating_a, moved) = rating_and_seq(&pool, a).await;
    assert_eq!(rating_a, Some(3.6));
    assert!(moved > seq_a);
    assert_eq!(rating_and_seq(&pool, b).await.1, seq_b, "b did not change");
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_viewport_query_keeps_the_places_rated_at_least_as_asked(pool: PgPool) {
    use lunaway_db::places::{self, PlaceFilter};
    use lunaway_domain::BBox;
    let low = place(&pool).await;
    let high = place(&pool).await;
    let _unrated = place(&pool).await;
    partner_rating(&pool, low, 3.4, 1).await;
    partner_rating(&pool, high, 4.5, 1).await;
    refresh(&pool).await;
    let bbox = BBox::new(45.8, 6.0, 46.0, 6.3).unwrap();
    let ids = |page: places::PlacePage| -> Vec<Uuid> {
        let mut ids: Vec<Uuid> = page.nodes.iter().map(|p| p.id).collect();
        ids.sort();
        ids
    };
    let at_least = |r: f64| PlaceFilter {
        min_rating: Some(r),
        ..PlaceFilter::default()
    };
    let page = places::in_bbox(&pool, bbox, &at_least(3.0), 50, None)
        .await
        .unwrap();
    assert_eq!(page.total_count, 2, "the unrated place is left out");
    let mut both = vec![low, high];
    both.sort();
    assert_eq!(ids(page), both);
    let page = places::in_bbox(&pool, bbox, &at_least(4.5), 50, None)
        .await
        .unwrap();
    assert_eq!(ids(page), [high], "4.5 is at least 4.5");
    let near = lunaway_domain::Position::new(45.9, 6.12).unwrap();
    let page = places::near_in_bbox(&pool, bbox, &at_least(4.0), near, 50, None)
        .await
        .unwrap();
    assert_eq!((page.total_count, ids(page)), (1, vec![high]));
    let row = places::by_id(&pool, high).await.unwrap().unwrap();
    assert_eq!(
        row.filter_rating,
        Some(4.5),
        "the API serves the stored rating"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_open_source_s_hides_and_a_taken_down_link_keep_its_reviews_out(pool: PgPool) {
    // One review hidden: the other one rates the place.
    let one_hidden = place(&pool).await;
    let bad = open_review(&pool, one_hidden, 1).await;
    open_review(&pool, one_hidden, 5).await;
    hide(&pool, "mangrove", "review", &bad).await;
    // Hidden on the place the review was written on, which was merged.
    let root_a = place(&pool).await;
    let merged_a = place(&pool).await;
    open_review(&pool, merged_a, 2).await;
    merge(&pool, merged_a, root_a).await;
    hide(&pool, "mangrove", "place", &merged_a.to_string()).await;
    // Hidden on the place that shows it.
    let root_b = place(&pool).await;
    let merged_b = place(&pool).await;
    open_review(&pool, merged_b, 2).await;
    merge(&pool, merged_b, root_b).await;
    hide(&pool, "mangrove", "place", &root_b.to_string()).await;
    // A place taken down in the middle of a merge chain cuts it: the page of
    // the root does not reach the reviews below it.
    let root_c = place(&pool).await;
    let middle = place(&pool).await;
    let bottom = place(&pool).await;
    open_review(&pool, bottom, 4).await;
    merge(&pool, middle, root_c).await;
    merge(&pool, bottom, middle).await;
    sqlx::query("UPDATE places SET taken_down_at = now() WHERE id = $1")
        .bind(middle)
        .execute(&pool)
        .await
        .unwrap();
    refresh(&pool).await;
    assert_eq!(
        rating_and_seq(&pool, one_hidden).await.0,
        Some(5.0),
        "a hidden review counts for nothing"
    );
    assert_eq!(
        rating_and_seq(&pool, root_a).await.0,
        None,
        "hidden on the place it was written on"
    );
    assert_eq!(
        rating_and_seq(&pool, root_b).await.0,
        None,
        "hidden on the place that shows it"
    );
    assert_eq!(
        rating_and_seq(&pool, root_c).await.0,
        None,
        "nothing below a place taken down shows on the root"
    );
}
