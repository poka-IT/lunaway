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

/// Writes the filter rating of every live place whose rating changed, each
/// with a new position in the change feed (the tiles and the devices carry
/// the rating), in the writer transaction `tx`. Returns how many changed.
///
/// One statement over every place: on production on 2026-10-08 (200 961
/// live places, 98 525 rating summaries of the external community source,
/// no open-source rating), computing every rating took 1.2 to 1.5 s
/// (`EXPLAIN ANALYZE` of the `computed` part, read-only), and 98 525
/// places had one (83 525 of 3 or more, 51 627 of 4 or more, 24 544 of
/// 4.5 or more).
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn refresh_filter_ratings(tx: &mut WriterTx) -> Result<u64, DbError> {
    let done = sqlx::query!(
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
        UPDATE places p
        SET filter_rating = c.rating, updated_at = now(),
            updated_seq = nextval('place_change_seq')
        FROM computed c
        WHERE p.id = c.id AND p.filter_rating IS DISTINCT FROM c.rating
        "#
    )
    .execute(tx.conn())
    .await?;
    Ok(done.rows_affected())
}
