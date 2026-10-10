//! The community summary of a place: what the change feed carries of the
//! ratings, reviews, photos, issues and confirmations, so a device offline
//! still shows them. The conflation worker computes it
//! (`community_refresh`); the API only reads it.

use chrono::{DateTime, Utc};
use lunaway_domain::community::{IssueKind, Verification};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{DbError, conflation::WriterTx};

/// How many photos the summary carries.
pub const COVER_PHOTOS: i64 = 3;

/// How far back reported issues count, in days.
pub const ISSUE_WINDOW_DAYS: i32 = 30;

/// A published photo shown on the place's card.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoverPhoto {
    /// The photo.
    pub id: Uuid,
    /// The full image, relative to the media root.
    pub path: String,
    /// The thumbnail, relative to the media root.
    pub thumb_path: String,
    /// Full image width, pixels.
    pub width: i32,
    /// Full image height, pixels.
    pub height: i32,
    /// Thumbhash, base64 (standard alphabet, padded), for a placeholder.
    pub thumbhash: String,
    /// Its author, so a device can hide the photos of an author it muted;
    /// null for a deleted account.
    pub author_id: Option<Uuid>,
}

/// Recent reports of one kind of issue.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueSummary {
    /// What was reported.
    pub kind: IssueKind,
    /// Reports over the window.
    pub count: i64,
    /// The latest.
    pub last_reported_at: DateTime<Utc>,
}

/// What the community says of a place, as stored on it.
#[derive(Debug, Clone, PartialEq)]
pub struct CommunitySummary {
    /// Mean of the published ratings, 1 to 5.
    pub rating_avg: Option<f64>,
    /// Published ratings (with or without text).
    pub rating_count: i32,
    /// Published reviews with text.
    pub review_count: i32,
    /// Published photos.
    pub photo_count: i32,
    /// The latest published photos.
    pub cover_photos: Vec<CoverPhoto>,
    /// Issues reported over the last [`ISSUE_WINDOW_DAYS`] days, each
    /// account counted once per kind, accounts of level 0 and banned ones
    /// left out (a handful of fresh accounts could otherwise stamp "danger"
    /// on every place; their reports stay for moderators).
    pub reported_issues: Vec<IssueSummary>,
    /// Whether the place is confirmed.
    pub verification: Verification,
}

impl Default for CommunitySummary {
    fn default() -> Self {
        Self {
            rating_avg: None,
            rating_count: 0,
            review_count: 0,
            photo_count: 0,
            cover_photos: Vec::new(),
            reported_issues: Vec::new(),
            verification: Verification::Verified,
        }
    }
}

/// Queues `ids` for the summary step of the worker, from a conflation
/// step: they are refreshed even if the run stops between the two steps.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn queue(tx: &mut WriterTx, ids: &[Uuid]) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        INSERT INTO place_refresh_queue (place_id) SELECT UNNEST($1::uuid[])
        ON CONFLICT DO NOTHING
        "#,
        ids
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}

/// Places queued for a refresh by the API, and the queue cleared of them,
/// in the writer transaction `tx`.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn take_queue(tx: &mut WriterTx) -> Result<Vec<Uuid>, DbError> {
    Ok(
        sqlx::query_scalar!("DELETE FROM place_refresh_queue RETURNING place_id")
            .fetch_all(tx.conn())
            .await?,
    )
}

/// Live places whose summary still shows an issue kind whose last report is
/// older than the window: refreshed by each run, or a report would stay on
/// the card for good once nothing else happens at the place.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn with_expired_issues(tx: &mut WriterTx) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT id FROM places
        WHERE deleted_at IS NULL AND reported_issues <> '[]'
          AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(reported_issues) e
              WHERE (e ->> 'lastReportedAt')::timestamptz < now() - make_interval(days => $1))
        "#,
        ISSUE_WINDOW_DAYS,
    )
    .fetch_all(tx.conn())
    .await?)
}

/// Recomputes the community summary of the live places `ids` stand for
/// (a tombstone stands for the place that absorbed it), each over its
/// family, and moves in the change feed the places whose summary changed.
/// Returns how many changed.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn refresh(tx: &mut WriterTx, ids: &[Uuid]) -> Result<u64, DbError> {
    let live: Vec<Uuid> = sqlx::query_scalar!(
        r#"
        WITH RECURSIVE heirs(id, live, depth) AS (
            SELECT p.id, p.deleted_at IS NULL, 0 FROM places p WHERE p.id = ANY($1)
            UNION ALL
            SELECT p.id, p.deleted_at IS NULL, h.depth + 1
            FROM heirs h JOIN places q ON q.id = h.id JOIN places p ON p.id = q.merged_into
            WHERE NOT h.live AND h.depth < 8
        )
        SELECT DISTINCT id AS "id!" FROM heirs WHERE live ORDER BY 1
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    let mut changed = 0;
    for id in live {
        let done = sqlx::query!(
            r#"
            WITH RECURSIVE family(id) AS (
                SELECT $1::uuid
                UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
            ),
            rated AS (
                -- One row per account across the family (an account that
                -- rated two places since merged counts once), the live
                -- place's first; anonymised reviews count each.
                SELECT avg(o.stars)::float8 AS avg, count(*)::int4 AS n,
                       (count(*) FILTER (WHERE o.body IS NOT NULL))::int4 AS reviews
                FROM (
                    SELECT DISTINCT ON (coalesce(r.account_id, r.id)) r.stars, r.body
                    FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
                    WHERE r.place_id IN (SELECT id FROM family) AND r.status = 'published'
                      AND r.withdrawn_at IS NULL AND a.banned_at IS NULL
                    ORDER BY coalesce(r.account_id, r.id), (r.place_id = $1) DESC,
                             r.updated_at DESC
                ) o
            ),
            shown AS (
                SELECT ph.id, ph.path, ph.thumb_path, ph.width, ph.height, ph.thumbhash,
                       ph.account_id
                FROM photos ph LEFT JOIN accounts a ON a.id = ph.account_id
                WHERE ph.place_id IN (SELECT id FROM family) AND ph.status = 'published'
                  AND ph.withdrawn_at IS NULL AND a.banned_at IS NULL
            ),
            cover AS (
                SELECT coalesce(jsonb_agg(jsonb_build_object(
                           'id', c.id, 'path', c.path, 'thumbPath', c.thumb_path,
                           'width', c.width, 'height', c.height,
                           'thumbhash', encode(c.thumbhash, 'base64'),
                           'authorId', c.account_id) ORDER BY c.id DESC), '[]') AS photos
                FROM (SELECT * FROM shown ORDER BY id DESC LIMIT $2) c
            ),
            issues AS (
                SELECT coalesce(jsonb_agg(jsonb_build_object(
                           'kind', i.kind, 'count', i.n, 'lastReportedAt', i.last)
                           ORDER BY i.kind), '[]') AS list
                FROM (
                    SELECT ir.kind,
                           count(DISTINCT ir.account_id) AS n,
                           max(ir.created_at) AS last
                    FROM issue_reports ir LEFT JOIN accounts a ON a.id = ir.account_id
                    WHERE ir.place_id IN (SELECT id FROM family) AND ir.status = 'published'
                      AND ir.created_at > now() - make_interval(days => $3)
                      AND a.banned_at IS NULL AND a.trust_level >= 1
                    GROUP BY ir.kind
                ) i
            ),
            records AS (
                SELECT r.id, r.source_id FROM place_sources ps
                JOIN source_records r ON r.id = ps.record_id
                WHERE ps.place_id = $1 AND r.deleted_at IS NULL
            ),
            authors AS (
                SELECT s.account_id FROM place_submissions s
                WHERE s.record_id IN (SELECT id FROM records) AND s.kind = 'create'
                  AND s.account_id IS NOT NULL
            ),
            confirmed AS (
                SELECT max(c.created_at) FILTER (WHERE c.status = 'still_ok') AS last_ok,
                       count(DISTINCT c.account_id) FILTER (
                           WHERE c.status = 'still_ok'
                             AND c.account_id NOT IN (SELECT account_id FROM authors)
                             AND a.trust_level >= 1) AS confirmers
                FROM confirmations c LEFT JOIN accounts a ON a.id = c.account_id
                WHERE c.place_id IN (SELECT id FROM family) AND a.banned_at IS NULL
            ),
            -- What the confirmations deleted after two years gave
            -- (`retention`): the accounts they counted have no answer left
            -- here, so they add to those counted above.
            tallied AS (
                SELECT max(t.last_ok) AS last_ok, coalesce(sum(t.confirmers), 0) AS confirmers
                FROM confirmation_tallies t WHERE t.place_id IN (SELECT id FROM family)
            ),
            summary AS (
                SELECT rated.avg, rated.n, rated.reviews,
                       (SELECT count(*)::int4 FROM shown) AS photo_n,
                       cover.photos, issues.list,
                       greatest(confirmed.last_ok, tallied.last_ok) AS last_ok,
                       CASE WHEN EXISTS (SELECT 1 FROM records)
                                 AND NOT EXISTS (SELECT 1 FROM records WHERE source_id <> 'community')
                                 AND confirmed.confirmers + tallied.confirmers < $4
                            THEN 'to_verify' ELSE 'verified' END AS verification
                FROM rated, cover, issues, confirmed, tallied
            )
            UPDATE places p SET
                rating_avg = s.avg, rating_count = s.n, review_count = s.reviews,
                photo_count = s.photo_n, cover_photos = s.photos, reported_issues = s.list,
                last_confirmed_at = s.last_ok, verification = s.verification,
                -- The filters' rating (`place_ratings`) takes Lunaway
                -- users' new ratings at once, beside what the worker's last
                -- pass read of the other sources.
                filter_rating = lunaway_filter_rating(s.avg, s.n, o.total, o.n),
                updated_at = now(), updated_seq = nextval('place_change_seq')
            FROM summary s
            LEFT JOIN place_other_ratings o ON o.place_id = $1
            WHERE p.id = $1 AND p.deleted_at IS NULL
              AND (p.rating_avg IS DISTINCT FROM s.avg OR p.rating_count <> s.n
                   OR p.review_count <> s.reviews OR p.photo_count <> s.photo_n
                   OR p.cover_photos <> s.photos OR p.reported_issues <> s.list
                   OR p.last_confirmed_at IS DISTINCT FROM s.last_ok
                   OR p.verification <> s.verification)
            "#,
            id,
            COVER_PHOTOS,
            ISSUE_WINDOW_DAYS,
            lunaway_domain::community::CONFIRMATIONS_TO_VERIFY,
        )
        .execute(tx.conn())
        .await?;
        changed += done.rows_affected();
    }
    Ok(changed)
}
