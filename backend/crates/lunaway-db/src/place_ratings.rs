//! The rating a place is filtered with (`places.filter_rating`): what the
//! map's "minimum rating" compares, in the tiles (`r`), in the API's
//! `PlaceFilter.minRating` and on the devices that keep places.
//!
//! Lunaway users' average when they rated the place; otherwise the average
//! of the ratings the other sources give it, each source weighted by how
//! many ratings it counts: the external community source's summaries
//! ([`crate::extcom::ratings_of_place`]) and the open sources' reviews
//! ([`crate::content::ratings_of_place`]), with the same exclusions as the
//! place's page (a hidden source, a hide of the source, of the place, of a
//! review or of its author; the reviews of the places merged into it).
//! Rounded to one decimal, as a rating reads; null when nobody rated it.
//!
//! The other sources' ratings change with their imports, which do not
//! write places: the worker computes every place's rating again at most
//! every few minutes and writes those that changed
//! ([`refresh_filter_ratings`]).

use crate::{DbError, conflation::WriterTx};

/// Places written per statement: the statement trigger that keeps the
/// search's words (`lunaway_place_search_words_update`) joins the old and
/// new rows of its statement, which the planner reads in a nested loop. On
/// production on 2026-10-08 one statement of the 98 524 places rated at
/// once ran ten minutes into the role's statement timeout, rereading its
/// spilled rows (911 GB read from the page cache), and failed; in
/// statements of a thousand, the same places were written in about 49 s.
const BATCH: usize = 1_000;

/// Writes the filter rating of every live place whose rating changed, each
/// with a new position in the change feed (the tiles and the devices carry
/// the rating), in the writer transaction `tx`. Returns how many changed.
///
/// The ratings of every place are computed in one read: on production on
/// 2026-10-08 (200 961 live places, 98 525 rating summaries of the external
/// community source, no open-source rating), 1.2 to 1.5 s (`EXPLAIN
/// ANALYZE`, read-only), and 98 525 places had one (83 525 of 3 or more,
/// 51 627 of 4 or more, 24 544 of 4.5 or more). Those that changed are
/// written [`BATCH`] at a time.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn refresh_filter_ratings(tx: &mut WriterTx) -> Result<u64, DbError> {
    let changed = sqlx::query!(
        r#"
        WITH partner AS (
            -- The external community source's summaries of the records of
            -- each place, as `extcom::ratings_of_place` counts them.
            SELECT ps.place_id, sum(t.average * t.count) AS total, sum(t.count) AS n
            FROM place_sources ps
            JOIN external_ratings t ON t.record_id = ps.record_id
            LEFT JOIN source_switches w ON w.source_id = t.source_id
            WHERE w.hidden_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM content_hides h
                  WHERE h.source_id = t.source_id
                    AND ((h.scope = 'place' AND h.key = ps.place_id::text)
                         OR h.scope = 'source'))
            GROUP BY ps.place_id
        ),
        up AS (
            -- From the place an open source's review was written on, up the
            -- merges to the place that shows it: `content::ratings_of_place`
            -- reads a place and the places merged into it that were not
            -- taken down.
            WITH RECURSIVE climb (origin, place) AS (
                SELECT DISTINCT place_id, place_id FROM content_reviews
                WHERE rating IS NOT NULL
                UNION
                SELECT c.origin, p.merged_into
                FROM climb c JOIN places p ON p.id = c.place
                WHERE p.merged_into IS NOT NULL AND p.taken_down_at IS NULL
            )
            SELECT c.origin, c.place AS shown_on
            FROM climb c JOIN places p ON p.id = c.place
            WHERE p.deleted_at IS NULL
        ),
        open AS (
            SELECT u.shown_on AS place_id, sum(c.rating)::float8 AS total, count(*) AS n
            FROM content_reviews c
            JOIN up u ON u.origin = c.place_id
            LEFT JOIN source_switches w ON w.source_id = c.source_id
            WHERE c.rating IS NOT NULL AND w.hidden_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM content_hides h
                  WHERE h.source_id = c.source_id
                    AND ((h.scope = 'review' AND h.key = c.external_id)
                      OR (h.scope = 'author' AND h.key = c.author_key)
                      OR (h.scope = 'place' AND h.key IN (c.place_id::text, u.shown_on::text))
                      OR h.scope = 'source'))
            GROUP BY u.shown_on
        ),
        computed AS (
            SELECT p.id,
                   round((CASE
                       WHEN p.rating_count > 0 AND p.rating_avg IS NOT NULL THEN p.rating_avg
                       ELSE (coalesce(pa.total, 0) + coalesce(op.total, 0))
                            / nullif(coalesce(pa.n, 0) + coalesce(op.n, 0), 0)
                   END)::numeric, 1)::float8 AS rating
            FROM places p
            LEFT JOIN partner pa ON pa.place_id = p.id
            LEFT JOIN open op ON op.place_id = p.id
            WHERE p.deleted_at IS NULL
        )
        SELECT p.id, c.rating
        FROM places p
        JOIN computed c ON c.id = p.id
        WHERE p.filter_rating IS DISTINCT FROM c.rating
        -- In the order of the primary key: each batch touches a run of it.
        ORDER BY p.id
        "#
    )
    .fetch_all(tx.conn())
    .await?;
    let mut written = 0;
    for batch in changed.chunks(BATCH) {
        let ids: Vec<uuid::Uuid> = batch.iter().map(|r| r.id).collect();
        let ratings: Vec<Option<f64>> = batch.iter().map(|r| r.rating).collect();
        written += sqlx::query!(
            r#"
            UPDATE places p
            SET filter_rating = u.rating, updated_at = now(),
                updated_seq = nextval('place_change_seq')
            FROM unnest($1::uuid[], $2::float8[]) AS u(id, rating)
            WHERE p.id = u.id AND p.filter_rating IS DISTINCT FROM u.rating
            "#,
            &ids,
            &ratings as &[Option<f64>],
        )
        .execute(tx.conn())
        .await?
        .rows_affected();
    }
    Ok(written)
}
