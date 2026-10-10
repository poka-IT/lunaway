//! Ratings and reviews of the points of interest and the establishments,
//! written by the API under the rules of the reviews of places
//! ([`crate::community`]): one per account and point, a rating alone
//! published at once, a text through the automatic rules, withdrawn rather
//! than deleted while moderation holds it or reports wait on it. A point is
//! never merged, so a row stays with its point; and a point carries no
//! community summary, so its rating is read from these rows when it is
//! served ([`ratings_of`]), one query for a whole list of points.

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::community::ReviewStatus;
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    community::{MissingRow, Page, enqueue, forget_target, page},
};

/// A rating or a review of a point as stored, with its author's public
/// name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PoiReviewRow {
    /// Its id.
    pub id: Uuid,
    /// The source it is published under (`community-cc-by`): its licence
    /// is that source's.
    pub source_id: String,
    /// The point it was written for.
    pub poi_id: Uuid,
    /// Its author; `None` once the account is deleted.
    pub account_id: Option<Uuid>,
    /// The author's pseudonym; `None` once the account is deleted.
    pub author: Option<String>,
    /// Stars, 1 to 5.
    pub stars: i16,
    /// The text; `None` for a rating alone.
    pub body: Option<String>,
    /// The language of the text.
    pub lang: Option<String>,
    /// When the author went there.
    pub visited_on: Option<NaiveDate>,
    /// Where it stands.
    pub status: String,
    /// First written.
    pub created_at: DateTime<Utc>,
    /// Last changed.
    pub updated_at: DateTime<Utc>,
}

/// The account's row for `poi`, locked.
async fn own_row(
    conn: &mut PgConnection,
    account: Uuid,
    poi: Uuid,
) -> Result<Option<(Uuid, String)>, DbError> {
    Ok(sqlx::query!(
        "SELECT id, status FROM poi_reviews WHERE account_id = $1 AND poi_id = $2 FOR UPDATE",
        account,
        poi,
    )
    .fetch_optional(conn)
    .await?
    .map(|r| (r.id, r.status)))
}

/// Whether moderation took the review out of view: the author cannot bring
/// it back by writing again.
fn moderated(status: &str) -> bool {
    matches!(status, "hidden" | "removed")
}

async fn row_in(conn: &mut PgConnection, id: Uuid) -> Result<Option<PoiReviewRow>, DbError> {
    Ok(sqlx::query_as!(
        PoiReviewRow,
        r#"
        SELECT r.id, r.source_id, r.poi_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.status, r.created_at, r.updated_at
        FROM poi_reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.id = $1
        "#,
        id,
    )
    .fetch_optional(conn)
    .await?)
}

/// Sets `account`'s stars for `poi`, keeping any text it wrote. A new
/// rating is published at once.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn rate(
    pool: &PgPool,
    account: Uuid,
    poi: Uuid,
    stars: i16,
) -> Result<PoiReviewRow, DbError> {
    let mut tx = pool.begin().await?;
    let id = match own_row(&mut tx, account, poi).await? {
        Some((id, _)) => {
            sqlx::query!(
                r#"
                UPDATE poi_reviews SET stars = $2, withdrawn_at = NULL, updated_at = now()
                WHERE id = $1
                "#,
                id,
                stars,
            )
            .execute(&mut *tx)
            .await?;
            id
        }
        None => {
            sqlx::query_scalar!(
                r#"
                INSERT INTO poi_reviews (id, poi_id, account_id, stars, status)
                VALUES ($1, $2, $3, $4, 'published')
                ON CONFLICT (account_id, poi_id) WHERE account_id IS NOT NULL
                DO UPDATE SET stars = EXCLUDED.stars, withdrawn_at = NULL, updated_at = now()
                RETURNING id
                "#,
                Uuid::now_v7(),
                poi,
                account,
                stars,
            )
            .fetch_one(&mut *tx)
            .await?
        }
    };
    let row = row_in(&mut tx, id).await?;
    tx.commit().await?;
    row.ok_or_else(|| DbError::decode("point review", MissingRow))
}

/// A review of a point to store.
#[derive(Debug, Clone, Copy)]
pub struct PoiReviewWrite<'a> {
    /// Its author.
    pub account: Uuid,
    /// The point, live.
    pub poi: Uuid,
    /// Stars, 1 to 5.
    pub stars: i16,
    /// The text, already checked for length.
    pub body: &'a str,
    /// Its language (BCP 47).
    pub lang: Option<&'a str>,
    /// When the author went there.
    pub visited_on: Option<NaiveDate>,
    /// Published, or held by the automatic rules.
    pub status: ReviewStatus,
    /// Why the rules held it (codes joined by commas), when they did.
    pub held_for: Option<&'a str>,
}

/// Writes `account`'s review of `poi` (one per account and point: a second
/// one replaces the first). A held review enters the moderation queue. A
/// review that moderation hid or removed keeps that status whatever its new
/// text, and the new text goes to a moderator.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn review(pool: &PgPool, w: PoiReviewWrite<'_>) -> Result<PoiReviewRow, DbError> {
    let mut tx = pool.begin().await?;
    let existing = own_row(&mut tx, w.account, w.poi).await?;
    let (status, reason) = match &existing {
        // A removed review stays removed: nothing for a moderator to decide.
        Some((_, old)) if old == "removed" => (old.clone(), None),
        Some((_, old)) if moderated(old) => (old.clone(), Some("rewritten after moderation")),
        _ => (w.status.code().to_owned(), w.held_for),
    };
    let id = match existing {
        Some((id, _)) => {
            sqlx::query!(
                r#"
                UPDATE poi_reviews SET stars = $2, body = $3, lang = $4, visited_on = $5,
                       status = $6, withdrawn_at = NULL, updated_at = now()
                WHERE id = $1
                "#,
                id,
                w.stars,
                w.body,
                w.lang,
                w.visited_on,
                status,
            )
            .execute(&mut *tx)
            .await?;
            id
        }
        None => {
            sqlx::query_scalar!(
                r#"
                INSERT INTO poi_reviews
                    (id, poi_id, account_id, stars, body, lang, visited_on, status)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                ON CONFLICT (account_id, poi_id) WHERE account_id IS NOT NULL
                DO UPDATE SET stars = EXCLUDED.stars, body = EXCLUDED.body,
                              lang = EXCLUDED.lang, visited_on = EXCLUDED.visited_on,
                              status = CASE WHEN poi_reviews.status IN ('hidden', 'removed')
                                            THEN poi_reviews.status ELSE EXCLUDED.status END,
                              withdrawn_at = NULL, updated_at = now()
                RETURNING id
                "#,
                Uuid::now_v7(),
                w.poi,
                w.account,
                w.stars,
                w.body,
                w.lang,
                w.visited_on,
                status,
            )
            .fetch_one(&mut *tx)
            .await?
        }
    };
    match reason {
        Some(reason) => {
            enqueue(
                &mut tx,
                "held_review",
                "poi_review",
                id,
                Some(w.account),
                reason,
            )
            .await?;
        }
        None if status == "published" => {
            // A clean rewrite of a held text publishes it: the entry about
            // the old text has nothing left to decide.
            sqlx::query!(
                r#"
                DELETE FROM moderation_queue
                WHERE target_id = $1 AND kind = 'held_review' AND status = 'open'
                "#,
                id
            )
            .execute(&mut *tx)
            .await?;
        }
        None => {}
    }
    let row = row_in(&mut tx, id).await?;
    tx.commit().await?;
    row.ok_or_else(|| DbError::decode("point review", MissingRow))
}

/// Whether `account` wrote the same text for another point, or for a
/// place, in the last 30 days: a review pasted across points is held.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn same_text_elsewhere(
    pool: &PgPool,
    account: Uuid,
    poi: Uuid,
    body: &str,
) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM poi_reviews
            WHERE account_id = $1 AND poi_id <> $2 AND lower(body) = lower($3)
              AND updated_at > now() - interval '30 days'
        ) OR EXISTS (
            SELECT 1 FROM reviews
            WHERE account_id = $1 AND lower(body) = lower($3)
              AND updated_at > now() - interval '30 days'
        ) AS "e!"
        "#,
        account,
        poi,
        body,
    )
    .fetch_one(pool)
    .await?)
}

/// Deletes `account`'s review `id` of a point (rating and text). Returns
/// its point, or `None` when the account has no such review. One that
/// moderation hid or removed, or that reports wait on, is withdrawn
/// instead: its text goes and it stops counting, the row stays with its
/// status, reports and queue entry, so posting again does not escape a
/// moderator.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn delete(pool: &PgPool, account: Uuid, id: Uuid) -> Result<Option<Uuid>, DbError> {
    let mut tx = pool.begin().await?;
    let row = sqlx::query!(
        r#"
        SELECT poi_id, status,
               EXISTS (SELECT 1 FROM content_reports c
                       WHERE c.target_type = 'poi_review' AND c.target_id = poi_reviews.id
                         AND c.dismissed_at IS NULL) AS "reported!"
        FROM poi_reviews WHERE id = $1 AND account_id = $2 FOR UPDATE
        "#,
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        return Ok(None);
    };
    if moderated(&row.status) || row.reported {
        sqlx::query!(
            r#"
            UPDATE poi_reviews SET body = NULL, lang = NULL, visited_on = NULL,
                   withdrawn_at = now(), updated_at = now()
            WHERE id = $1
            "#,
            id
        )
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query!("DELETE FROM poi_reviews WHERE id = $1", id)
            .execute(&mut *tx)
            .await?;
        forget_target(&mut tx, id).await?;
    }
    tx.commit().await?;
    Ok(Some(row.poi_id))
}

/// The published reviews with text of `poi`, newest first, after the review
/// `after`; leaving out banned authors and, for `viewer`, the authors it
/// muted.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_poi(
    pool: &PgPool,
    poi: Uuid,
    viewer: Option<Uuid>,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<PoiReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        PoiReviewRow,
        r#"
        SELECT r.id, r.source_id, r.poi_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.status, r.created_at, r.updated_at
        FROM poi_reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.poi_id = $1 AND r.status = 'published' AND r.body IS NOT NULL
          AND a.banned_at IS NULL
          AND ($2::uuid IS NULL OR r.account_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM muted_authors m WHERE m.account_id = $2 AND m.muted_id = r.account_id))
          AND ($3::uuid IS NULL OR r.id < $3)
        ORDER BY r.id DESC
        LIMIT $4
        "#,
        poi,
        viewer,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total_count = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!"
        FROM poi_reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.poi_id = $1 AND r.status = 'published' AND r.body IS NOT NULL
          AND a.banned_at IS NULL
          AND ($2::uuid IS NULL OR r.account_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM muted_authors m WHERE m.account_id = $2 AND m.muted_id = r.account_id))
        "#,
        poi,
        viewer,
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total_count))
}

/// `account`'s reviews and ratings of points, every status, newest first.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_account(
    pool: &PgPool,
    account: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<PoiReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        PoiReviewRow,
        r#"
        SELECT r.id, r.source_id, r.poi_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.status, r.created_at, r.updated_at
        FROM poi_reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.account_id = $1 AND r.withdrawn_at IS NULL AND ($2::uuid IS NULL OR r.id < $2)
        ORDER BY r.id DESC
        LIMIT $3
        "#,
        account,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM poi_reviews WHERE account_id = $1 AND withdrawn_at IS NULL"#,
        account
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total))
}

/// `account`'s rating or review of `poi`, whatever its status.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn review_by_account(
    pool: &PgPool,
    account: Uuid,
    poi: Uuid,
) -> Result<Option<PoiReviewRow>, DbError> {
    Ok(sqlx::query_as!(
        PoiReviewRow,
        r#"
        SELECT r.id, r.source_id, r.poi_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.status, r.created_at, r.updated_at
        FROM poi_reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.account_id = $1 AND r.poi_id = $2 AND r.withdrawn_at IS NULL
        "#,
        account,
        poi,
    )
    .fetch_optional(pool)
    .await?)
}

/// The rating of one point by Lunaway users.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PoiRating {
    /// The point.
    pub poi_id: Uuid,
    /// Mean stars, 1 to 5.
    pub average: f64,
    /// Ratings counted.
    pub count: i64,
}

/// The ratings of `pois` by Lunaway users, in one query: the published
/// ratings and reviews, neither withdrawn nor of a banned account (a
/// deleted account's review with text still counts, without author). A
/// point nobody rated is absent.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn ratings_of(pool: &PgPool, pois: &[Uuid]) -> Result<Vec<PoiRating>, DbError> {
    Ok(sqlx::query_as!(
        PoiRating,
        r#"
        SELECT r.poi_id, avg(r.stars)::float8 AS "average!", count(*) AS "count!"
        FROM poi_reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.poi_id = ANY($1) AND r.status = 'published' AND r.withdrawn_at IS NULL
          AND a.banned_at IS NULL
        GROUP BY r.poi_id
        "#,
        pois,
    )
    .fetch_all(pool)
    .await?)
}
