//! The moderation queue, as `lunaway moderation` works it: what waits, and
//! the two decisions. The commands run with the API's role: they write the
//! same contribution tables, never the catalogue.
//!
//! | entry | approve | reject |
//! |---|---|---|
//! | held review | published | removed (counts against the author's level) |
//! | reported review or photo | published again, reports dismissed | removed (counts too; a removed photo's files are deleted) |
//!
//! Content its author withdrew (deleted while held or reported) is never
//! published by an approval; a reject still counts against the author.
//! | reported place | closed (the place is the sources' to change) | closed |
//! | place proposal | accepted, applied by the worker | rejected |
//! | place check (closed or changed) | closed | closed |
//! | road report (a community road event two accounts confirmed) | kept | ended, its reports removed |

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    community::{notify_worker, unserved},
};

/// An open queue entry, with an excerpt of what it is about.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueueEntry {
    /// Its id.
    pub id: Uuid,
    /// `held_review`, `reported_content`, `place_proposal`, `place_check`,
    /// `poi_check`.
    pub kind: String,
    /// `review`, `photo`, `place`, `submission`, `poi`.
    pub target_type: String,
    /// The target.
    pub target_id: Uuid,
    /// The author of the content or of the proposal.
    pub account_id: Option<Uuid>,
    /// Why it is here.
    pub reason: String,
    /// Distinct reporters, for a reported target.
    pub reports: i64,
    /// What the target says: a review's text, a photo's path, a proposal's
    /// JSON, a place's name.
    pub excerpt: Option<String>,
    /// When it entered the queue.
    pub created_at: DateTime<Utc>,
}

/// The open entries, oldest first, at most `limit`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn open(pool: &PgPool, limit: i64) -> Result<Vec<QueueEntry>, DbError> {
    Ok(sqlx::query_as!(
        QueueEntry,
        r#"
        SELECT q.id, q.kind, q.target_type, q.target_id, q.account_id, q.reason, q.created_at,
               (SELECT count(*) FROM content_reports c
                WHERE c.target_type = q.target_type AND c.target_id = q.target_id
                  AND c.dismissed_at IS NULL) AS "reports!",
               CASE q.target_type
                   WHEN 'review' THEN (SELECT left(r.body, 300) FROM reviews r WHERE r.id = q.target_id)
                   WHEN 'photo' THEN (SELECT p.path FROM photos p WHERE p.id = q.target_id)
                   WHEN 'submission' THEN (SELECT left(s.payload::text, 300)
                                           FROM place_submissions s WHERE s.id = q.target_id)
                   WHEN 'place' THEN (SELECT coalesce(p.name, p.kind) FROM places p
                                      WHERE p.id = q.target_id)
                   WHEN 'poi' THEN (SELECT coalesce(p.name, p.kind) || ' (' || p.external_id || ')'
                                    FROM pois p WHERE p.id = q.target_id)
               END AS excerpt
        FROM moderation_queue q
        WHERE q.status = 'open'
        ORDER BY q.created_at, q.id
        LIMIT $1
        "#,
        limit,
    )
    .fetch_all(pool)
    .await?)
}

/// Hides a point (`hidden`) or shows it again, for a moderator: a hidden
/// point stays hidden whatever the answers say; shown again, its "gone"
/// answers are set aside. The worker applies it at its next run.
async fn set_poi_hidden(
    conn: &mut sqlx::PgConnection,
    poi: Uuid,
    hidden: bool,
    note: Option<&str>,
) -> Result<(), DbError> {
    if hidden {
        sqlx::query!(
            "INSERT INTO poi_moderation (poi_id, note) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            poi,
            note,
        )
        .execute(&mut *conn)
        .await?;
    } else {
        sqlx::query!("DELETE FROM poi_moderation WHERE poi_id = $1", poi)
            .execute(&mut *conn)
            .await?;
        sqlx::query!(
            r#"
            UPDATE poi_confirmations SET status = 'dismissed'
            WHERE poi_id = $1 AND NOT still_there AND status = 'published'
            "#,
            poi
        )
        .execute(&mut *conn)
        .await?;
    }
    sqlx::query!(
        "INSERT INTO poi_refresh_queue (poi_id) VALUES ($1) ON CONFLICT DO NOTHING",
        poi
    )
    .execute(&mut *conn)
    .await?;
    notify_worker(conn).await
}

/// Hides the point `poi` (`hidden`) or shows it again, outside the queue:
/// `lunaway moderation hide-poi` and `show-poi`. `false` when no point has
/// this id.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn hide_poi(
    pool: &PgPool,
    poi: Uuid,
    hidden: bool,
    note: Option<&str>,
) -> Result<bool, DbError> {
    let mut tx = pool.begin().await?;
    let exists = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM pois WHERE id = $1) AS "e!""#,
        poi
    )
    .fetch_one(&mut *tx)
    .await?;
    if !exists {
        return Ok(false);
    }
    set_poi_hidden(&mut tx, poi, hidden, note).await?;
    tx.commit().await?;
    Ok(true)
}

/// A moderator's decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    /// The content is fine, or the proposal is accepted.
    Approve,
    /// The content goes, or the proposal is refused.
    Reject,
}

/// What a decision did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decided {
    /// No open entry with this id.
    NotFound,
    /// Applied.
    Done {
        /// The entry's kind.
        kind: String,
        /// The place whose summary changes, if any.
        place: Option<Uuid>,
        /// Media files no published or hidden photo shows any more, for the
        /// caller to remove.
        files: Vec<String>,
    },
}

/// Applies `decision` to the open entry `id`, with an optional note.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing changes then.
pub async fn decide(
    pool: &PgPool,
    id: Uuid,
    decision: Decision,
    note: Option<&str>,
) -> Result<Decided, DbError> {
    let mut tx = pool.begin().await?;
    let entry = sqlx::query!(
        "SELECT kind, target_type, target_id FROM moderation_queue WHERE id = $1 AND status = 'open' FOR UPDATE",
        id
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(entry) = entry else {
        return Ok(Decided::NotFound);
    };
    let approve = decision == Decision::Approve;
    let mut files = Vec::new();
    let (place, author) = match entry.target_type.as_str() {
        "review" => {
            let status = if approve { "published" } else { "removed" };
            // From a held or hidden state only: a removed review stays
            // removed, and a decision on it changes nothing.
            sqlx::query!(
                r#"
                UPDATE reviews SET status = $2, updated_at = now()
                WHERE id = $1 AND status IN ('pending', 'hidden', 'published')
                  AND status <> $2 AND ($2 = 'removed' OR withdrawn_at IS NULL)
                RETURNING place_id, account_id
                "#,
                entry.target_id,
                status
            )
            .fetch_optional(&mut *tx)
            .await?
            .map_or((None, None), |r| (Some(r.place_id), r.account_id))
        }
        "photo" => {
            let status = if approve { "published" } else { "removed" };
            // A removed photo's files are gone: it is never published again.
            let row = sqlx::query!(
                r#"
                UPDATE photos SET status = $2
                WHERE id = $1 AND status IN ('hidden', 'published') AND status <> $2
                  AND ($2 = 'removed' OR withdrawn_at IS NULL)
                RETURNING place_id, account_id, path, thumb_path
                "#,
                entry.target_id,
                status
            )
            .fetch_optional(&mut *tx)
            .await?;
            match row {
                Some(r) => {
                    if !approve {
                        files = unserved(&mut tx, &[r.path, r.thumb_path]).await?;
                    }
                    (Some(r.place_id), r.account_id)
                }
                None => (None, None),
            }
        }
        "submission" => {
            let status = if approve { "accepted" } else { "rejected" };
            sqlx::query!(
                r#"
                UPDATE place_submissions SET status = $2, decided_at = now()
                WHERE id = $1 AND status = 'proposed'
                "#,
                entry.target_id,
                status
            )
            .execute(&mut *tx)
            .await?;
            if approve {
                notify_worker(&mut tx).await?;
            }
            (None, None)
        }
        "poi" => {
            set_poi_hidden(&mut tx, entry.target_id, !approve, note).await?;
            (None, None)
        }
        "road_event" => {
            // A community road event two accounts confirmed: a reject ends
            // it for everyone and sets its reports aside.
            if !approve {
                sqlx::query!(
                    r#"
                    UPDATE road_events SET ended_at = now(), end_reason = 'moderated'
                    WHERE id = $1 AND source = 'community' AND ended_at IS NULL
                    "#,
                    entry.target_id
                )
                .execute(&mut *tx)
                .await?;
                sqlx::query!(
                    r#"
                    UPDATE road_event_reports SET status = 'removed'
                    WHERE event_id = $1 AND status = 'active'
                    "#,
                    entry.target_id
                )
                .execute(&mut *tx)
                .await?;
            }
            (None, None)
        }
        _ => (None, None),
    };
    if !approve
        && matches!(entry.target_type.as_str(), "review" | "photo")
        && let Some(author) = author
    {
        sqlx::query!(
            "UPDATE accounts SET moderation_removals = moderation_removals + 1 WHERE id = $1",
            author
        )
        .execute(&mut *tx)
        .await?;
    }
    if approve && entry.kind == "reported_content" {
        // Dismissed, not deleted: the same reporters cannot report it again
        // (one report per reporter and target), and dismissed reports no
        // longer count toward hiding.
        sqlx::query!(
            r#"
            UPDATE content_reports SET dismissed_at = now()
            WHERE target_type = $1 AND target_id = $2 AND dismissed_at IS NULL
            "#,
            entry.target_type,
            entry.target_id
        )
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query!(
        r#"
        UPDATE moderation_queue SET status = $2, decided_at = now(), decision_note = $3
        WHERE id = $1
        "#,
        id,
        if approve { "approved" } else { "rejected" },
        note,
    )
    .execute(&mut *tx)
    .await?;
    if let Some(place) = place {
        sqlx::query!(
            "INSERT INTO place_refresh_queue (place_id) VALUES ($1) ON CONFLICT DO NOTHING",
            place
        )
        .execute(&mut *tx)
        .await?;
        notify_worker(&mut tx).await?;
    }
    tx.commit().await?;
    Ok(Decided::Done {
        kind: entry.kind,
        place,
        files,
    })
}

/// Dismisses every published issue report of `place` and of the places
/// merged into it (a false "night ban" or "danger"), so the change feed
/// stops carrying them. Returns how many.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn dismiss_issues(pool: &PgPool, place: Uuid) -> Result<u64, DbError> {
    let mut tx = pool.begin().await?;
    let done = sqlx::query!(
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        UPDATE issue_reports SET status = 'dismissed'
        WHERE place_id IN (SELECT id FROM family) AND status = 'published'
        "#,
        place
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO place_refresh_queue (place_id) VALUES ($1) ON CONFLICT DO NOTHING",
        place
    )
    .execute(&mut *tx)
    .await?;
    notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}
