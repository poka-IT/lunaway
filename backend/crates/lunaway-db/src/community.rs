//! Contributions written by the API: ratings and reviews, confirmations,
//! issue reports, photos, mutes and content reports. The catalogue is never
//! written here: each write that changes what a place shows queues the place
//! in `place_refresh_queue`, and the conflation worker recomputes its
//! community summary under the writers' lock.
//!
//! A place merged into another keeps its contributions: they are read for
//! the place that absorbed it (its "family": itself and every tombstone
//! merged into it).

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    Position,
    community::{ConfirmationStatus, IssueKind, ReportReason, ReportTarget, ReviewStatus},
};
use sqlx::{PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    idempotency::{self, Key, Once},
};

/// How many `merged_into` redirects a lookup follows.
const MAX_REDIRECTS: usize = 8;

/// A live place a contribution can attach to.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LivePlace {
    /// The live place (after following merges).
    pub id: Uuid,
    /// Its position.
    pub position: Position,
}

/// The live place `id` names, following merges; `None` when it never
/// existed or was deleted without a successor.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_place(pool: &PgPool, id: Uuid) -> Result<Option<LivePlace>, DbError> {
    let mut id = id;
    for _ in 0..=MAX_REDIRECTS {
        let row = sqlx::query!(
            r#"
            SELECT ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
                   deleted_at IS NOT NULL AS "deleted!", merged_into
            FROM places WHERE id = $1
            "#,
            id,
        )
        .fetch_optional(pool)
        .await?;
        match row {
            None => return Ok(None),
            Some(r) if !r.deleted => {
                return Ok(Some(LivePlace {
                    id,
                    position: Position::new(r.lat, r.lon)
                        .map_err(|e| DbError::decode("place position", e))?,
                }));
            }
            Some(r) => match r.merged_into {
                Some(next) => id = next,
                None => return Ok(None),
            },
        }
    }
    Ok(None)
}

/// Queues `place` for the worker and wakes it.
async fn queue_refresh(conn: &mut PgConnection, place: Uuid) -> Result<(), DbError> {
    sqlx::query!(
        "INSERT INTO place_refresh_queue (place_id) VALUES ($1) ON CONFLICT DO NOTHING",
        place
    )
    .execute(&mut *conn)
    .await?;
    notify_worker(conn).await
}

/// The channel the conflation worker listens on (`lunaway conflate
/// --watch`).
pub const WORK_CHANNEL: &str = "lunaway_work";

/// Wakes the conflation worker once the transaction commits (a NOTIFY is
/// delivered at commit, never for a rolled back transaction).
pub(crate) async fn notify_worker(conn: &mut PgConnection) -> Result<(), DbError> {
    sqlx::query!("SELECT pg_notify($1, '')", WORK_CHANNEL)
        .execute(conn)
        .await?;
    Ok(())
}

async fn begin(pool: &PgPool) -> Result<Transaction<'static, Postgres>, DbError> {
    Ok(pool.begin().await?)
}

// Ratings and reviews.

/// A rating or a review as stored, with its author's public name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewRow {
    /// Its id.
    pub id: Uuid,
    /// The source it is published under (`community-cc-by`): its licence
    /// is that source's.
    pub source_id: String,
    /// The place it was written for.
    pub place_id: Uuid,
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
    /// When the author stayed.
    pub visited_on: Option<NaiveDate>,
    /// The author's vehicle code.
    pub vehicle: Option<String>,
    /// Where it stands.
    pub status: String,
    /// First written.
    pub created_at: DateTime<Utc>,
    /// Last changed.
    pub updated_at: DateTime<Utc>,
}

/// The account's row for `place` among the place and the places merged into
/// it, the live place's first, locked; the others (an account that rated
/// two places later merged into one) are deleted so it counts once.
async fn own_row_in_family(
    conn: &mut PgConnection,
    account: Uuid,
    place: Uuid,
) -> Result<Option<(Uuid, String)>, DbError> {
    let rows = sqlx::query!(
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $2::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        SELECT id, status FROM reviews
        WHERE account_id = $1 AND place_id IN (SELECT id FROM family)
        ORDER BY (place_id = $2) DESC, updated_at DESC, id
        FOR UPDATE
        "#,
        account,
        place,
    )
    .fetch_all(&mut *conn)
    .await?;
    let mut rows = rows.into_iter();
    let Some(keep) = rows.next() else {
        return Ok(None);
    };
    // The kept row takes the most restrictive status of the duplicates, so
    // merging two places never lifts a moderation decision.
    let rank = |s: &str| match s {
        "removed" => 3,
        "hidden" => 2,
        "pending" => 1,
        _ => 0,
    };
    let mut status = keep.status;
    let mut extra = Vec::new();
    for r in rows {
        if rank(&r.status) > rank(&status) {
            status = r.status;
        }
        extra.push(r.id);
    }
    if !extra.is_empty() {
        // Their reports and queue entries follow to the kept row, so a
        // moderator can still act on what they were about.
        sqlx::query!(
            r#"
            INSERT INTO content_reports
                (id, target_type, target_id, reporter_id, reason, note, created_at, dismissed_at)
            SELECT id, target_type, $2, reporter_id, reason, note, created_at, dismissed_at
            FROM content_reports WHERE target_id = ANY($1)
            ON CONFLICT DO NOTHING
            "#,
            &extra,
            keep.id,
        )
        .execute(&mut *conn)
        .await?;
        sqlx::query!(
            r#"
            UPDATE moderation_queue q SET target_id = $2
            WHERE q.target_id = ANY($1) AND NOT (q.status = 'open' AND EXISTS (
                SELECT 1 FROM moderation_queue o
                WHERE o.target_id = $2 AND o.kind = q.kind AND o.status = 'open'))
            "#,
            &extra,
            keep.id,
        )
        .execute(&mut *conn)
        .await?;
        sqlx::query!(
            "DELETE FROM content_reports WHERE target_id = ANY($1)",
            &extra
        )
        .execute(&mut *conn)
        .await?;
        sqlx::query!(
            "DELETE FROM moderation_queue WHERE target_id = ANY($1)",
            &extra
        )
        .execute(&mut *conn)
        .await?;
        sqlx::query!("DELETE FROM reviews WHERE id = ANY($1)", &extra)
            .execute(&mut *conn)
            .await?;
        sqlx::query!(
            "UPDATE reviews SET status = $2 WHERE id = $1",
            keep.id,
            status
        )
        .execute(&mut *conn)
        .await?;
    }
    Ok(Some((keep.id, status)))
}

/// Whether moderation took the review out of view: the author cannot bring
/// it back by writing again.
fn moderated(status: &str) -> bool {
    matches!(status, "hidden" | "removed")
}

/// Sets `account`'s stars for the live `place`, keeping any text it wrote.
/// A new rating is published at once. One row per account across a place
/// and the places merged into it.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn rate(
    pool: &PgPool,
    account: Uuid,
    place: Uuid,
    stars: i16,
) -> Result<ReviewRow, DbError> {
    let mut tx = begin(pool).await?;
    let id = match own_row_in_family(&mut tx, account, place).await? {
        Some((id, _)) => {
            sqlx::query!(
                r#"
                UPDATE reviews SET place_id = $2, stars = $3, withdrawn_at = NULL, updated_at = now()
                WHERE id = $1
                "#,
                id,
                place,
                stars,
            )
            .execute(&mut *tx)
            .await?;
            id
        }
        None => {
            sqlx::query_scalar!(
                r#"
                INSERT INTO reviews (id, place_id, account_id, stars, status)
                VALUES ($1, $2, $3, $4, 'published')
                ON CONFLICT (account_id, place_id) WHERE account_id IS NOT NULL
                DO UPDATE SET stars = EXCLUDED.stars, updated_at = now()
                RETURNING id
                "#,
                Uuid::now_v7(),
                place,
                account,
                stars,
            )
            .fetch_one(&mut *tx)
            .await?
        }
    };
    queue_refresh(&mut tx, place).await?;
    let row = review_in(&mut tx, id).await?;
    tx.commit().await?;
    row.ok_or_else(|| DbError::decode("review", MissingRow))
}

/// A review to store.
#[derive(Debug, Clone, Copy)]
pub struct ReviewWrite<'a> {
    /// Its author.
    pub account: Uuid,
    /// The live place.
    pub place: Uuid,
    /// Stars, 1 to 5.
    pub stars: i16,
    /// The text, already checked for length.
    pub body: &'a str,
    /// Its language (BCP 47).
    pub lang: Option<&'a str>,
    /// When the author stayed.
    pub visited_on: Option<NaiveDate>,
    /// The author's vehicle code.
    pub vehicle: Option<&'a str>,
    /// Published, or held by the automatic rules.
    pub status: ReviewStatus,
    /// Why the rules held it (codes joined by commas), when they did.
    pub held_for: Option<&'a str>,
}

/// Writes `account`'s review of the live `place` (one per account across
/// the place and the places merged into it: a second one replaces the
/// first). A held review enters the moderation queue. A review that
/// moderation hid or removed keeps that status whatever its new text, and
/// the new text goes to a moderator.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn review(pool: &PgPool, w: ReviewWrite<'_>) -> Result<ReviewRow, DbError> {
    let mut tx = begin(pool).await?;
    let existing = own_row_in_family(&mut tx, w.account, w.place).await?;
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
                UPDATE reviews SET place_id = $2, stars = $3, body = $4, lang = $5,
                       visited_on = $6, vehicle = $7, status = $8, withdrawn_at = NULL,
                       updated_at = now()
                WHERE id = $1
                "#,
                id,
                w.place,
                w.stars,
                w.body,
                w.lang,
                w.visited_on,
                w.vehicle,
                status,
            )
            .execute(&mut *tx)
            .await?;
            id
        }
        None => {
            sqlx::query_scalar!(
                r#"
                INSERT INTO reviews
                    (id, place_id, account_id, stars, body, lang, visited_on, vehicle, status)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                ON CONFLICT (account_id, place_id) WHERE account_id IS NOT NULL
                DO UPDATE SET stars = EXCLUDED.stars, body = EXCLUDED.body,
                              lang = EXCLUDED.lang, visited_on = EXCLUDED.visited_on,
                              vehicle = EXCLUDED.vehicle,
                              status = CASE WHEN reviews.status IN ('hidden', 'removed')
                                            THEN reviews.status ELSE EXCLUDED.status END,
                              updated_at = now()
                RETURNING id
                "#,
                Uuid::now_v7(),
                w.place,
                w.account,
                w.stars,
                w.body,
                w.lang,
                w.visited_on,
                w.vehicle,
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
                "review",
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
    queue_refresh(&mut tx, w.place).await?;
    let row = review_in(&mut tx, id).await?;
    tx.commit().await?;
    row.ok_or_else(|| DbError::decode("review", MissingRow))
}

/// A row that a statement of the same transaction just wrote is missing.
#[derive(Debug, thiserror::Error)]
#[error("a row written by this transaction is missing")]
struct MissingRow;

async fn review_in(conn: &mut PgConnection, id: Uuid) -> Result<Option<ReviewRow>, DbError> {
    Ok(sqlx::query_as!(
        ReviewRow,
        r#"
        SELECT r.id, r.source_id, r.place_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.vehicle, r.status, r.created_at, r.updated_at
        FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.id = $1
        "#,
        id,
    )
    .fetch_optional(conn)
    .await?)
}

/// Whether `account` wrote the same text for another place in the last 30
/// days: a review pasted across places is held.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn same_text_elsewhere(
    pool: &PgPool,
    account: Uuid,
    place: Uuid,
    body: &str,
) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM reviews
            WHERE account_id = $1 AND place_id <> $2 AND lower(body) = lower($3)
              AND updated_at > now() - interval '30 days'
        ) AS "e!"
        "#,
        account,
        place,
        body,
    )
    .fetch_one(pool)
    .await?)
}

/// Deletes `account`'s review `id` (rating and text). Returns its place, or
/// `None` when the account has no such review.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn delete_review(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
) -> Result<Option<Uuid>, DbError> {
    let mut tx = begin(pool).await?;
    let row = sqlx::query!(
        r#"
        SELECT place_id, status,
               EXISTS (SELECT 1 FROM content_reports c
                       WHERE c.target_id = reviews.id AND c.dismissed_at IS NULL) AS "reported!"
        FROM reviews WHERE id = $1 AND account_id = $2 FOR UPDATE
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
        // Withdrawn: the text and the stars stop counting, as the author
        // asked; the row stays with its status, its reports and its queue
        // entry, so posting again at the place does not escape a moderator,
        // and an approval never publishes what the author took back.
        sqlx::query!(
            r#"
            UPDATE reviews SET body = NULL, lang = NULL, visited_on = NULL, vehicle = NULL,
                   withdrawn_at = now(), updated_at = now()
            WHERE id = $1
            "#,
            id
        )
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query!("DELETE FROM reviews WHERE id = $1", id)
            .execute(&mut *tx)
            .await?;
        forget_target(&mut tx, id).await?;
    }
    queue_refresh(&mut tx, row.place_id).await?;
    tx.commit().await?;
    Ok(Some(row.place_id))
}

/// Drops the reports and open queue entries about a contribution its author
/// deleted.
async fn forget_target(conn: &mut PgConnection, id: Uuid) -> Result<(), DbError> {
    sqlx::query!("DELETE FROM content_reports WHERE target_id = $1", id)
        .execute(&mut *conn)
        .await?;
    sqlx::query!(
        "DELETE FROM moderation_queue WHERE target_id = $1 AND status = 'open'",
        id
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// One page of a list read newest first.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Page<T> {
    /// The rows.
    pub nodes: Vec<T>,
    /// Whether more follow.
    pub has_next_page: bool,
    /// Rows in the whole list.
    pub total_count: i64,
}

/// The published reviews with text of `place` and the places merged into it,
/// newest first, after the review `after`; leaving out banned authors and,
/// for `viewer`, the authors it muted.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_place(
    pool: &PgPool,
    place: Uuid,
    viewer: Option<Uuid>,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<ReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        ReviewRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        SELECT r.id, r.source_id, r.place_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.vehicle, r.status, r.created_at, r.updated_at
        FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.place_id IN (SELECT id FROM family)
          AND r.status = 'published' AND r.body IS NOT NULL
          AND a.banned_at IS NULL
          AND ($2::uuid IS NULL OR r.account_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM muted_authors m WHERE m.account_id = $2 AND m.muted_id = r.account_id))
          AND ($3::uuid IS NULL OR r.id < $3)
        ORDER BY r.id DESC
        LIMIT $4
        "#,
        place,
        viewer,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total_count = sqlx::query_scalar!(
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        SELECT count(*) AS "n!"
        FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.place_id IN (SELECT id FROM family)
          AND r.status = 'published' AND r.body IS NOT NULL
          AND a.banned_at IS NULL
          AND ($2::uuid IS NULL OR r.account_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM muted_authors m WHERE m.account_id = $2 AND m.muted_id = r.account_id))
        "#,
        place,
        viewer,
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total_count))
}

pub(crate) fn page<T>(mut rows: Vec<T>, first: i64, total_count: i64) -> Page<T> {
    let keep = usize::try_from(first).unwrap_or(0);
    let has_next_page = rows.len() > keep;
    rows.truncate(keep);
    Page {
        nodes: rows,
        has_next_page,
        total_count,
    }
}

/// `account`'s reviews and ratings, every status, newest first.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_account(
    pool: &PgPool,
    account: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<ReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        ReviewRow,
        r#"
        SELECT r.id, r.source_id, r.place_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.vehicle, r.status, r.created_at, r.updated_at
        FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
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
        r#"SELECT count(*) AS "n!" FROM reviews WHERE account_id = $1 AND withdrawn_at IS NULL"#,
        account
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total))
}

/// `account`'s rating or review of `place` (or of a place merged into it).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn review_by_account(
    pool: &PgPool,
    account: Uuid,
    place: Uuid,
) -> Result<Option<ReviewRow>, DbError> {
    Ok(sqlx::query_as!(
        ReviewRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $2::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        SELECT r.id, r.source_id, r.place_id, r.account_id, a.pseudonym AS "author?", r.stars,
               r.body, r.lang, r.visited_on, r.vehicle, r.status, r.created_at, r.updated_at
        FROM reviews r LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.account_id = $1 AND r.place_id IN (SELECT id FROM family)
          AND r.withdrawn_at IS NULL
        ORDER BY (r.place_id = $2) DESC, r.updated_at DESC
        LIMIT 1
        "#,
        account,
        place,
    )
    .fetch_optional(pool)
    .await?)
}

// Confirmations and issues.

/// A confirmation as stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfirmationRow {
    /// Its id.
    pub id: Uuid,
    /// The place.
    pub place_id: Uuid,
    /// The answer code.
    pub status: String,
    /// When.
    pub created_at: DateTime<Utc>,
}

/// Stores a confirmation. A closed or changed place opens a check in the
/// moderation queue.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn confirm(
    pool: &PgPool,
    account: Uuid,
    place: Uuid,
    status: ConfirmationStatus,
    note: Option<&str>,
) -> Result<ConfirmationRow, DbError> {
    let mut tx = begin(pool).await?;
    let row = confirm_in(&mut tx, account, place, status, note).await?;
    tx.commit().await?;
    Ok(row)
}

/// [`confirm`] guarded by an idempotency key: a request sent again with the
/// same key answers with the confirmation the first one stored.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn confirm_once(
    pool: &PgPool,
    key: &Key<'_>,
    place: Uuid,
    status: ConfirmationStatus,
    note: Option<&str>,
) -> Result<Once<ConfirmationRow>, DbError> {
    let mut tx = match idempotency::begin(pool, key).await? {
        Ok(tx) => tx,
        Err(seen) => return Ok(seen.once()),
    };
    let row = confirm_in(&mut tx, key.account, place, status, note).await?;
    let id = row.id;
    idempotency::finish(pool, tx, key, id, row).await
}

async fn confirm_in(
    tx: &mut PgConnection,
    account: Uuid,
    place: Uuid,
    status: ConfirmationStatus,
    note: Option<&str>,
) -> Result<ConfirmationRow, DbError> {
    let row = sqlx::query_as!(
        ConfirmationRow,
        r#"
        INSERT INTO confirmations (id, place_id, account_id, status, note)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, place_id, status, created_at
        "#,
        Uuid::now_v7(),
        place,
        account,
        status.code(),
        note,
    )
    .fetch_one(&mut *tx)
    .await?;
    if status != ConfirmationStatus::StillOk {
        enqueue(
            &mut *tx,
            "place_check",
            "place",
            place,
            Some(account),
            status.code(),
        )
        .await?;
    }
    queue_refresh(&mut *tx, place).await?;
    Ok(row)
}

/// `account`'s confirmation `id`, if it still exists.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn confirmation_of(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
) -> Result<Option<ConfirmationRow>, DbError> {
    Ok(sqlx::query_as!(
        ConfirmationRow,
        r#"
        SELECT id, place_id, status, created_at FROM confirmations
        WHERE id = $1 AND account_id = $2
        "#,
        id,
        account,
    )
    .fetch_optional(pool)
    .await?)
}

/// Deletes `account`'s confirmation `id`; returns its place.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn delete_confirmation(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
) -> Result<Option<Uuid>, DbError> {
    let mut tx = begin(pool).await?;
    let place = sqlx::query_scalar!(
        "DELETE FROM confirmations WHERE id = $1 AND account_id = $2 RETURNING place_id",
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(place) = place {
        queue_refresh(&mut tx, place).await?;
    }
    tx.commit().await?;
    Ok(place)
}

/// `account`'s confirmations, newest first.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn confirmations_of_account(
    pool: &PgPool,
    account: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<ConfirmationRow>, DbError> {
    let rows = sqlx::query_as!(
        ConfirmationRow,
        r#"
        SELECT id, place_id, status, created_at FROM confirmations
        WHERE account_id = $1 AND ($2::uuid IS NULL OR id < $2)
        ORDER BY id DESC LIMIT $3
        "#,
        account,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM confirmations WHERE account_id = $1"#,
        account
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total))
}

/// An issue report as stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IssueRow {
    /// Its id.
    pub id: Uuid,
    /// The place.
    pub place_id: Uuid,
    /// The kind code.
    pub kind: String,
    /// When.
    pub created_at: DateTime<Utc>,
}

/// Stores an issue report.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn report_issue(
    pool: &PgPool,
    account: Uuid,
    place: Uuid,
    kind: IssueKind,
    note: Option<&str>,
) -> Result<IssueRow, DbError> {
    let mut tx = begin(pool).await?;
    let row = report_issue_in(&mut tx, account, place, kind, note).await?;
    tx.commit().await?;
    Ok(row)
}

/// [`report_issue`] guarded by an idempotency key.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn report_issue_once(
    pool: &PgPool,
    key: &Key<'_>,
    place: Uuid,
    kind: IssueKind,
    note: Option<&str>,
) -> Result<Once<IssueRow>, DbError> {
    let mut tx = match idempotency::begin(pool, key).await? {
        Ok(tx) => tx,
        Err(seen) => return Ok(seen.once()),
    };
    let row = report_issue_in(&mut tx, key.account, place, kind, note).await?;
    let id = row.id;
    idempotency::finish(pool, tx, key, id, row).await
}

async fn report_issue_in(
    tx: &mut PgConnection,
    account: Uuid,
    place: Uuid,
    kind: IssueKind,
    note: Option<&str>,
) -> Result<IssueRow, DbError> {
    let row = sqlx::query_as!(
        IssueRow,
        r#"
        INSERT INTO issue_reports (id, place_id, account_id, kind, note) VALUES ($1, $2, $3, $4, $5)
        RETURNING id, place_id, kind, created_at
        "#,
        Uuid::now_v7(),
        place,
        account,
        kind.code(),
        note,
    )
    .fetch_one(&mut *tx)
    .await?;
    queue_refresh(&mut *tx, place).await?;
    Ok(row)
}

/// `account`'s issue report `id`, if it still exists.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn issue_of(pool: &PgPool, account: Uuid, id: Uuid) -> Result<Option<IssueRow>, DbError> {
    Ok(sqlx::query_as!(
        IssueRow,
        r#"
        SELECT id, place_id, kind, created_at FROM issue_reports
        WHERE id = $1 AND account_id = $2
        "#,
        id,
        account,
    )
    .fetch_optional(pool)
    .await?)
}

/// Deletes `account`'s issue report `id`; returns its place.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn delete_issue(pool: &PgPool, account: Uuid, id: Uuid) -> Result<Option<Uuid>, DbError> {
    let mut tx = begin(pool).await?;
    let place = sqlx::query_scalar!(
        "DELETE FROM issue_reports WHERE id = $1 AND account_id = $2 RETURNING place_id",
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(place) = place {
        queue_refresh(&mut tx, place).await?;
    }
    tx.commit().await?;
    Ok(place)
}

/// `account`'s issue reports, newest first.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn issues_of_account(
    pool: &PgPool,
    account: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<IssueRow>, DbError> {
    let rows = sqlx::query_as!(
        IssueRow,
        r#"
        SELECT id, place_id, kind, created_at FROM issue_reports
        WHERE account_id = $1 AND ($2::uuid IS NULL OR id < $2)
        ORDER BY id DESC LIMIT $3
        "#,
        account,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM issue_reports WHERE account_id = $1"#,
        account
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total))
}

// Photos.

/// A photo as stored, with its author's public name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PhotoRow {
    /// Its id.
    pub id: Uuid,
    /// The source it is published under (`community-cc-by`): its licence
    /// is that source's.
    pub source_id: String,
    /// The place.
    pub place_id: Uuid,
    /// Its author; `None` once the account is deleted.
    pub account_id: Option<Uuid>,
    /// The author's pseudonym.
    pub author: Option<String>,
    /// Where it stands.
    pub status: String,
    /// Full image, relative to the media root.
    pub path: String,
    /// Thumbnail, relative to the media root.
    pub thumb_path: String,
    /// Full image width.
    pub width: i32,
    /// Full image height.
    pub height: i32,
    /// Thumbnail width.
    pub thumb_width: i32,
    /// Thumbnail height.
    pub thumb_height: i32,
    /// Thumbhash bytes.
    pub thumbhash: Vec<u8>,
    /// When.
    pub created_at: DateTime<Utc>,
}

/// A processed photo to store.
#[derive(Debug, Clone, Copy)]
pub struct NewPhoto<'a> {
    /// Its author.
    pub account: Uuid,
    /// The live place.
    pub place: Uuid,
    /// Full image, relative to the media root.
    pub path: &'a str,
    /// Thumbnail, relative to the media root.
    pub thumb_path: &'a str,
    /// Full image size.
    pub size: (i32, i32),
    /// Thumbnail size.
    pub thumb_size: (i32, i32),
    /// Thumbhash bytes.
    pub thumbhash: &'a [u8],
}

/// Stores a published photo.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn add_photo(pool: &PgPool, p: NewPhoto<'_>) -> Result<PhotoRow, DbError> {
    let mut tx = begin(pool).await?;
    let id = Uuid::now_v7();
    sqlx::query!(
        r#"
        INSERT INTO photos (id, place_id, account_id, status, path, thumb_path, width, height,
                            thumb_width, thumb_height, thumbhash)
        VALUES ($1, $2, $3, 'published', $4, $5, $6, $7, $8, $9, $10)
        "#,
        id,
        p.place,
        p.account,
        p.path,
        p.thumb_path,
        p.size.0,
        p.size.1,
        p.thumb_size.0,
        p.thumb_size.1,
        p.thumbhash,
    )
    .execute(&mut *tx)
    .await?;
    queue_refresh(&mut tx, p.place).await?;
    let row = photo_in(&mut tx, id).await?;
    tx.commit().await?;
    row.ok_or_else(|| DbError::decode("photo", MissingRow))
}

async fn photo_in(conn: &mut PgConnection, id: Uuid) -> Result<Option<PhotoRow>, DbError> {
    Ok(sqlx::query_as!(
        PhotoRow,
        r#"
        SELECT p.id, p.source_id, p.place_id, p.account_id, a.pseudonym AS "author?", p.status,
               p.path, p.thumb_path, p.width, p.height, p.thumb_width, p.thumb_height,
               p.thumbhash, p.created_at
        FROM photos p LEFT JOIN accounts a ON a.id = p.account_id
        WHERE p.id = $1
        "#,
        id,
    )
    .fetch_optional(conn)
    .await?)
}

/// Whether `account` already sent this picture (same file), for any place
/// and whatever became of it: the same photo posted again, or sent back
/// after a moderator removed it, is refused.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn photo_already_sent(pool: &PgPool, account: Uuid, path: &str) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM photos WHERE account_id = $1 AND path = $2) AS "e!""#,
        account,
        path,
    )
    .fetch_one(pool)
    .await?)
}

/// Deletes `account`'s photo `id`. Returns its place and the files no row
/// refers to any more (the caller removes them), or `None` when the account
/// has no such photo.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn delete_photo(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
) -> Result<Option<(Uuid, Vec<String>)>, DbError> {
    let mut tx = begin(pool).await?;
    let row = sqlx::query!(
        r#"
        SELECT place_id, path, thumb_path, status,
               EXISTS (SELECT 1 FROM content_reports c
                       WHERE c.target_id = photos.id AND c.dismissed_at IS NULL) AS "reported!"
        FROM photos WHERE id = $1 AND account_id = $2 FOR UPDATE
        "#,
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        return Ok(None);
    };
    if row.status == "published" && !row.reported {
        sqlx::query!("DELETE FROM photos WHERE id = $1", id)
            .execute(&mut *tx)
            .await?;
        forget_target(&mut tx, id).await?;
    } else {
        // Withdrawn: the files go, as the author asked, but the row stays
        // with its status and its reports: a moderator's reject still counts
        // the removal, an approval does not publish it, and the same picture
        // cannot be sent again.
        sqlx::query!("UPDATE photos SET withdrawn_at = now() WHERE id = $1", id)
            .execute(&mut *tx)
            .await?;
    }
    let orphans = unserved(&mut tx, &[row.path, row.thumb_path]).await?;
    queue_refresh(&mut tx, row.place_id).await?;
    tx.commit().await?;
    Ok(Some((row.place_id, orphans)))
}

/// The published photos of `place` and the places merged into it, newest
/// first, at most `limit`; leaving out banned authors and, for `viewer`, the
/// authors it muted.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn photos_of_place(
    pool: &PgPool,
    place: Uuid,
    viewer: Option<Uuid>,
    limit: i64,
) -> Result<Vec<PhotoRow>, DbError> {
    Ok(sqlx::query_as!(
        PhotoRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        SELECT p.id, p.source_id, p.place_id, p.account_id, a.pseudonym AS "author?", p.status,
               p.path, p.thumb_path, p.width, p.height, p.thumb_width, p.thumb_height,
               p.thumbhash, p.created_at
        FROM photos p LEFT JOIN accounts a ON a.id = p.account_id
        WHERE p.place_id IN (SELECT id FROM family) AND p.status = 'published'
          AND p.withdrawn_at IS NULL AND a.banned_at IS NULL
          AND ($2::uuid IS NULL OR p.account_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM muted_authors m WHERE m.account_id = $2 AND m.muted_id = p.account_id))
        ORDER BY p.id DESC
        LIMIT $3
        "#,
        place,
        viewer,
        limit,
    )
    .fetch_all(pool)
    .await?)
}

/// `account`'s photos, every status, newest first.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn photos_of_account(
    pool: &PgPool,
    account: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<Page<PhotoRow>, DbError> {
    let rows = sqlx::query_as!(
        PhotoRow,
        r#"
        SELECT p.id, p.source_id, p.place_id, p.account_id, a.pseudonym AS "author?", p.status,
               p.path, p.thumb_path, p.width, p.height, p.thumb_width, p.thumb_height,
               p.thumbhash, p.created_at
        FROM photos p LEFT JOIN accounts a ON a.id = p.account_id
        WHERE p.account_id = $1 AND p.withdrawn_at IS NULL AND ($2::uuid IS NULL OR p.id < $2)
        ORDER BY p.id DESC LIMIT $3
        "#,
        account,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM photos WHERE account_id = $1 AND withdrawn_at IS NULL"#,
        account
    )
    .fetch_one(pool)
    .await?;
    Ok(page(rows, first, total))
}

/// Of `files`, those no published or hidden photo refers to (withdrawn ones
/// left out): they are removed from the media root, so a photo deleted or
/// removed by moderation is no longer served, while a file another photo
/// still shows stays.
pub(crate) async fn unserved(
    conn: &mut PgConnection,
    files: &[String],
) -> Result<Vec<String>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT DISTINCT f AS "f!" FROM UNNEST($1::text[]) AS f
        WHERE NOT EXISTS (
            SELECT 1 FROM photos p
            WHERE (p.path = f OR p.thumb_path = f) AND p.status IN ('published', 'hidden')
              AND p.withdrawn_at IS NULL)
        "#,
        files,
    )
    .fetch_all(conn)
    .await?)
}

// Mutes.

/// `account` mutes `muted`. Returns false when `muted` does not exist.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn mute(pool: &PgPool, account: Uuid, muted: Uuid) -> Result<bool, DbError> {
    let exists = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM accounts WHERE id = $1) AS "e!""#,
        muted
    )
    .fetch_one(pool)
    .await?;
    if !exists {
        return Ok(false);
    }
    sqlx::query!(
        "INSERT INTO muted_authors (account_id, muted_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        account,
        muted
    )
    .execute(pool)
    .await?;
    Ok(true)
}

/// `account` stops muting `muted`.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn unmute(pool: &PgPool, account: Uuid, muted: Uuid) -> Result<(), DbError> {
    sqlx::query!(
        "DELETE FROM muted_authors WHERE account_id = $1 AND muted_id = $2",
        account,
        muted
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// The authors `account` mutes, with their pseudonyms, most recent first.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn muted_by(pool: &PgPool, account: Uuid) -> Result<Vec<(Uuid, String)>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT m.muted_id, a.pseudonym FROM muted_authors m JOIN accounts a ON a.id = m.muted_id
        WHERE m.account_id = $1 ORDER BY m.created_at DESC, m.muted_id
        "#,
        account
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| (r.muted_id, r.pseudonym))
        .collect())
}

// Reports and the moderation queue.

/// Opens a queue entry, or adds `reason` to the open entry for the same
/// target.
pub(crate) async fn enqueue(
    conn: &mut PgConnection,
    kind: &str,
    target_type: &str,
    target: Uuid,
    account: Option<Uuid>,
    reason: &str,
) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        INSERT INTO moderation_queue (id, kind, target_type, target_id, account_id, reason)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (kind, target_type, target_id) WHERE status = 'open'
        DO UPDATE SET reason = CASE
            WHEN position(EXCLUDED.reason IN moderation_queue.reason) > 0 THEN moderation_queue.reason
            ELSE left(moderation_queue.reason || ', ' || EXCLUDED.reason, 2000) END
        "#,
        Uuid::now_v7(),
        kind,
        target_type,
        target,
        account,
        reason,
    )
    .execute(conn)
    .await?;
    Ok(())
}

/// What a content report did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportOutcome {
    /// The target does not exist, or is the reporter's own.
    NoTarget,
    /// Stored; the target stays visible.
    Queued,
    /// Stored, and the reports reached the threshold: the target is hidden
    /// until a moderator decides.
    Hidden,
}

/// Records that `reporter` reports a published or hidden review, a photo or
/// a place, once per reporter and target. At `hide_after` distinct
/// reporters of level 1 or more (not banned), one of them at least of level
/// 2, a published review or photo is hidden: fresh accounts, or accounts
/// grown to level 1 by a script, cannot hide what others wrote; their
/// reports still reach the queue.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn report_content(
    pool: &PgPool,
    reporter: Uuid,
    target: ReportTarget,
    id: Uuid,
    reason: ReportReason,
    note: Option<&str>,
    hide_after: i64,
) -> Result<ReportOutcome, DbError> {
    let mut tx = begin(pool).await?;
    let (author, place) = match target {
        ReportTarget::Review => {
            let r = sqlx::query!(
                r#"
                SELECT account_id, place_id FROM reviews
                WHERE id = $1 AND body IS NOT NULL AND status IN ('published', 'hidden')
                  AND withdrawn_at IS NULL
                FOR UPDATE
                "#,
                id
            )
            .fetch_optional(&mut *tx)
            .await?;
            match r {
                Some(r) => (r.account_id, Some(r.place_id)),
                None => return Ok(ReportOutcome::NoTarget),
            }
        }
        ReportTarget::Photo => {
            let r = sqlx::query!(
                r#"
                SELECT account_id, place_id FROM photos
                WHERE id = $1 AND status IN ('published', 'hidden') AND withdrawn_at IS NULL
                FOR UPDATE
                "#,
                id
            )
            .fetch_optional(&mut *tx)
            .await?;
            match r {
                Some(r) => (r.account_id, Some(r.place_id)),
                None => return Ok(ReportOutcome::NoTarget),
            }
        }
        ReportTarget::Place => {
            let exists = sqlx::query_scalar!(
                r#"SELECT EXISTS (SELECT 1 FROM places WHERE id = $1 AND deleted_at IS NULL) AS "e!""#,
                id
            )
            .fetch_one(&mut *tx)
            .await?;
            if !exists {
                return Ok(ReportOutcome::NoTarget);
            }
            (None, None)
        }
    };
    if author == Some(reporter) {
        return Ok(ReportOutcome::NoTarget);
    }
    sqlx::query!(
        r#"
        INSERT INTO content_reports (id, target_type, target_id, reporter_id, reason, note)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (target_type, target_id, reporter_id) DO NOTHING
        "#,
        Uuid::now_v7(),
        target.code(),
        id,
        reporter,
        reason.code(),
        note,
    )
    .execute(&mut *tx)
    .await?;
    enqueue(
        &mut tx,
        "reported_content",
        target.code(),
        id,
        author,
        reason.code(),
    )
    .await?;
    let reporters = sqlx::query!(
        r#"
        SELECT count(*) AS "trusted!", count(*) FILTER (WHERE a.trust_level >= 2) AS "senior!"
        FROM content_reports c JOIN accounts a ON a.id = c.reporter_id
        WHERE c.target_type = $1 AND c.target_id = $2 AND a.trust_level >= 1
          AND a.banned_at IS NULL AND c.dismissed_at IS NULL
        "#,
        target.code(),
        id
    )
    .fetch_one(&mut *tx)
    .await?;
    let mut outcome = ReportOutcome::Queued;
    if reporters.trusted >= hide_after && reporters.senior >= 1 {
        let hidden = match target {
            ReportTarget::Review => sqlx::query!(
                "UPDATE reviews SET status = 'hidden', updated_at = now() WHERE id = $1 AND status = 'published'",
                id
            )
            .execute(&mut *tx)
            .await?
            .rows_affected(),
            ReportTarget::Photo => sqlx::query!(
                "UPDATE photos SET status = 'hidden' WHERE id = $1 AND status = 'published'",
                id
            )
            .execute(&mut *tx)
            .await?
            .rows_affected(),
            ReportTarget::Place => 0,
        };
        if hidden > 0 {
            outcome = ReportOutcome::Hidden;
            if let Some(place) = place {
                queue_refresh(&mut tx, place).await?;
            }
        }
    }
    tx.commit().await?;
    Ok(outcome)
}

/// Longest time the worker gathers notifications before it runs.
pub const MAX_SETTLE: std::time::Duration = std::time::Duration::from_secs(2);

/// A connection listening on [`WORK_CHANNEL`], for the conflation worker.
#[derive(Debug)]
pub struct WorkListener(sqlx::postgres::PgListener);

impl WorkListener {
    /// Listens on [`WORK_CHANNEL`] over a connection of `pool`'s settings.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the connection or the LISTEN fails.
    pub async fn connect(pool: &PgPool) -> Result<Self, DbError> {
        let mut listener = sqlx::postgres::PgListener::connect_with(pool).await?;
        listener.listen(WORK_CHANNEL).await?;
        Ok(Self(listener))
    }

    /// Waits until a notification arrives (true) or `timeout` passes
    /// (false). After a notification, the ones that follow within
    /// `settle` are taken too, so a burst of writes wakes the worker once;
    /// never for longer than [`MAX_SETTLE`], or a steady stream of writes
    /// would keep the worker asleep.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the connection fails (sqlx reconnects on the next
    /// call).
    pub async fn wait(
        &mut self,
        timeout: std::time::Duration,
        settle: std::time::Duration,
    ) -> Result<bool, DbError> {
        gather(&mut self.0, timeout, settle).await
    }
}

/// Where the worker's wake-ups come from: the database's notifications in
/// production, a channel on a paused clock in the tests of [`gather`].
trait Signals {
    /// The next wake-up.
    async fn next(&mut self) -> Result<(), DbError>;
}

impl Signals for sqlx::postgres::PgListener {
    async fn next(&mut self) -> Result<(), DbError> {
        self.recv().await?;
        Ok(())
    }
}

/// [`WorkListener::wait`] over any source of wake-ups.
async fn gather(
    signals: &mut impl Signals,
    timeout: std::time::Duration,
    settle: std::time::Duration,
) -> Result<bool, DbError> {
    match tokio::time::timeout(timeout, signals.next()).await {
        Err(_) => return Ok(false),
        Ok(n) => n?,
    }
    let deadline = tokio::time::Instant::now() + MAX_SETTLE;
    loop {
        let until = (tokio::time::Instant::now() + settle).min(deadline);
        match tokio::time::timeout_at(until, signals.next()).await {
            Ok(n) => n?,
            Err(_) => break,
        }
        if tokio::time::Instant::now() >= deadline {
            break;
        }
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use tokio::{sync::mpsc, time::Instant};

    use super::*;

    impl Signals for mpsc::Receiver<()> {
        async fn next(&mut self) -> Result<(), DbError> {
            match self.recv().await {
                Some(()) => Ok(()),
                // Every sender gone: no wake-up will ever come, as on a
                // listener nobody notifies.
                None => std::future::pending().await,
            }
        }
    }

    /// Sends a wake-up every `every`, `count` times (forever when `None`).
    fn writes(every: Duration, count: Option<u32>) -> mpsc::Receiver<()> {
        let (tx, rx) = mpsc::channel(1_024);
        tokio::spawn(async move {
            let mut sent = 0;
            while count.is_none_or(|c| sent < c) {
                if tx.send(()).await.is_err() {
                    return;
                }
                sent += 1;
                tokio::time::sleep(every).await;
            }
            // Keeps the channel open: a closed one is not silence.
            std::future::pending::<()>().await;
        });
        rx
    }

    // The clock is tokio's, paused: it moves only when every task waits,
    // so these bounds hold to the millisecond on a loaded machine too.

    #[tokio::test(start_paused = true)]
    async fn a_steady_stream_of_writes_wakes_the_worker_at_the_settle_bound() {
        let mut rx = writes(Duration::from_millis(100), None);
        let started = Instant::now();
        let gathered = gather(&mut rx, Duration::from_secs(60), Duration::from_millis(300));
        // Without the bound the stream would hold it for good: a minute of
        // the paused clock fails the test instead.
        let woken = tokio::time::timeout(Duration::from_secs(60), gathered)
            .await
            .expect("the worker wakes while the writes go on")
            .unwrap();
        let took = started.elapsed();
        assert!(woken);
        assert!(
            took >= MAX_SETTLE && took < MAX_SETTLE + Duration::from_millis(100),
            "writes every 100 ms never leave a 300 ms gap, so the worker runs at MAX_SETTLE \
             after the first: {took:?}"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn a_burst_of_writes_wakes_the_worker_once_after_it() {
        let mut rx = writes(Duration::from_millis(50), Some(5));
        let started = Instant::now();
        let woken = gather(&mut rx, Duration::from_secs(60), Duration::from_millis(300))
            .await
            .unwrap();
        assert!(woken);
        assert_eq!(
            started.elapsed(),
            Duration::from_millis(200 + 300),
            "the last of five writes 50 ms apart, then one settle period of silence"
        );
        assert!(rx.try_recv().is_err(), "the burst was taken whole");
    }

    #[tokio::test(start_paused = true)]
    async fn without_a_write_the_worker_waits_its_period() {
        let mut rx = writes(Duration::from_millis(100), Some(0));
        let started = Instant::now();
        let woken = gather(&mut rx, Duration::from_secs(5), Duration::from_millis(300))
            .await
            .unwrap();
        assert!(!woken);
        assert_eq!(started.elapsed(), Duration::from_secs(5));
    }
}
