//! How long the contribution tables keep what they hold. `lunaway
//! retention` runs [`sweep`] once a day with the API's role, which writes
//! these tables; the privacy page states the same durations.
//!
//! | what | kept | then |
//! |---|---|---|
//! | an issue report | [`ISSUE_REPORT_DAYS`] from its creation | deleted (the card reads the last 30 days) |
//! | a report on a review, a photo or a place | [`RESOLVED_DAYS`] from its resolution | deleted |
//! | a decided moderation entry | [`RESOLVED_DAYS`] from its decision | deleted |
//! | a "still there?" answer | [`CONFIRMATION_DAYS`] from its creation | deleted; the place keeps what it gave in `confirmation_tallies`, the account its count |
//! | a refused or withdrawn submission's content | [`SUBMISSION_PAYLOAD_DAYS`] from its decision | emptied (`{}`); the row stays as history |
//! | a banned account's key hash, after it deleted itself | [`BANNED_KEY_DAYS`] from the deletion | deleted |
//!
//! A report is resolved when a moderator dismissed it, or decided the
//! queue entry it opened. A report or an entry still open waits for its
//! moderator. The texts of a banned account's reviews go at the ban
//! (`accounts::ban`), the content of a deleted account's unapplied
//! submissions at the deletion (`accounts::delete_account`).

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// Days an issue report is kept.
pub const ISSUE_REPORT_DAYS: i32 = 90;
/// Days a content report and a moderation entry are kept once resolved.
pub const RESOLVED_DAYS: i32 = 365;
/// Days a confirmation is kept.
pub const CONFIRMATION_DAYS: i32 = 730;
/// Days a refused or withdrawn submission keeps its content.
pub const SUBMISSION_PAYLOAD_DAYS: i32 = 30;
/// Days the key hashes of a banned account that deleted itself are kept.
pub const BANNED_KEY_DAYS: i32 = 730;

/// What one sweep removed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Swept {
    /// Issue reports deleted.
    pub issue_reports: u64,
    /// Content reports deleted.
    pub content_reports: u64,
    /// Decided moderation entries deleted.
    pub moderation_entries: u64,
    /// Confirmations deleted.
    pub confirmations: u64,
    /// Submissions whose content was emptied.
    pub submission_payloads: u64,
    /// Banned key hashes deleted.
    pub banned_keys: u64,
}

/// The instant `days` before `now`.
fn before(now: DateTime<Utc>, days: i32) -> DateTime<Utc> {
    now - chrono::Duration::days(i64::from(days))
}

/// Applies every duration of the module's table as of `now`. Each step
/// commits on its own: a failure leaves the steps before it done, and the
/// next day's sweep takes up the rest.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn sweep(pool: &PgPool, now: DateTime<Utc>) -> Result<Swept, DbError> {
    let issue_reports = sqlx::query!(
        "DELETE FROM issue_reports WHERE created_at < $1",
        before(now, ISSUE_REPORT_DAYS)
    )
    .execute(pool)
    .await?
    .rows_affected();
    let resolved_before = before(now, RESOLVED_DAYS);
    // Before the entries: a report's resolution is read from them.
    let content_reports = sqlx::query!(
        r#"
        DELETE FROM content_reports c
        WHERE coalesce(c.dismissed_at, (
                  SELECT min(q.decided_at) FROM moderation_queue q
                  WHERE q.kind = 'reported_content' AND q.target_type = c.target_type
                    AND q.target_id = c.target_id AND q.status <> 'open'
                    AND q.decided_at >= c.created_at)) < $1
        "#,
        resolved_before
    )
    .execute(pool)
    .await?
    .rows_affected();
    let moderation_entries = sqlx::query!(
        r#"
        DELETE FROM moderation_queue
        WHERE status <> 'open' AND coalesce(decided_at, created_at) < $1
        "#,
        resolved_before
    )
    .execute(pool)
    .await?
    .rows_affected();
    let confirmations = sweep_confirmations(pool, before(now, CONFIRMATION_DAYS)).await?;
    let submission_payloads = sqlx::query!(
        r#"
        UPDATE place_submissions SET payload = '{}'::jsonb
        WHERE status IN ('rejected', 'withdrawn') AND payload <> '{}'::jsonb
          AND coalesce(decided_at, created_at) < $1
        "#,
        before(now, SUBMISSION_PAYLOAD_DAYS)
    )
    .execute(pool)
    .await?
    .rows_affected();
    let banned_keys = sqlx::query!(
        "DELETE FROM banned_keys WHERE deleted_at < $1",
        before(now, BANNED_KEY_DAYS)
    )
    .execute(pool)
    .await?
    .rows_affected();
    Ok(Swept {
        issue_reports,
        content_reports,
        moderation_entries,
        confirmations,
        submission_payloads,
        banned_keys,
    })
}

/// Deletes the confirmations made before `cutoff`, in one transaction,
/// after writing down what they gave.
///
/// - On the live place each row's place has become (merges followed), in
///   `confirmation_tallies`: the latest "still ok" among them, and how many
///   accounts they add to its confirmers, by the summary's rules (a level
///   of 1 at least, not banned, not an author of the place), counting only
///   the accounts left with no "still ok" in the place's family, the only
///   answers the summary counts. The
///   summary (`summary::refresh`) adds that number to the accounts it still
///   counts, so neither "last confirmed" nor the verification moves back,
///   and an account is counted once whichever of its rows goes first.
/// - On each account, the places it no longer has any answer about
///   (`accounts.archived_confirmations`), which its trust level counts.
///
/// An account counted in a tally that confirms the place again later is
/// counted twice, which takes two years between its answers; a ban after
/// the rows went does not take its old answers back out.
async fn sweep_confirmations(pool: &PgPool, cutoff: DateTime<Utc>) -> Result<u64, DbError> {
    let mut tx = pool.begin().await?;
    // Accounts first, then their rows: the order `accounts::delete_account`
    // takes them in, so the two never wait on each other in a cycle.
    sqlx::query!(
        r#"
        SELECT a.id FROM accounts a
        WHERE a.id IN (SELECT account_id FROM confirmations WHERE created_at < $1)
        ORDER BY a.id FOR NO KEY UPDATE
        "#,
        cutoff
    )
    .fetch_all(&mut *tx)
    .await?;
    // Then the rows: an author deleting one meanwhile waits, so the tallies
    // count exactly the rows deleted.
    let old: Vec<Uuid> = sqlx::query_scalar!(
        "SELECT id FROM confirmations WHERE created_at < $1 ORDER BY id FOR UPDATE",
        cutoff
    )
    .fetch_all(&mut *tx)
    .await?;
    if old.is_empty() {
        return Ok(0);
    }
    sqlx::query!(
        r#"
        WITH RECURSIVE
        gone AS (
            SELECT c.id, c.place_id, c.account_id, c.status, c.created_at
            FROM confirmations c WHERE c.id = ANY($1)
        ),
        -- The same depth as the summary's walk to the live place.
        chain(start, id, depth) AS (
            SELECT DISTINCT g.place_id, g.place_id, 0 FROM gone g
            UNION ALL
            SELECT c.start, p.merged_into, c.depth + 1
            FROM chain c JOIN places p ON p.id = c.id
            WHERE p.merged_into IS NOT NULL AND c.depth < 8
        ),
        roots AS (
            SELECT DISTINCT ON (start) start, id AS root FROM chain ORDER BY start, depth DESC
        ),
        family(root, id) AS (
            SELECT DISTINCT root, root FROM roots
            UNION
            SELECT f.root, p.id FROM places p JOIN family f ON p.merged_into = f.id
        ),
        authors AS (
            SELECT DISTINCT r.root, s.account_id
            FROM (SELECT DISTINCT root FROM roots) r
            JOIN place_sources ps ON ps.place_id = r.root
            JOIN source_records sr ON sr.id = ps.record_id AND sr.deleted_at IS NULL
            JOIN place_submissions s ON s.record_id = sr.id
            WHERE s.kind = 'create' AND s.account_id IS NOT NULL
        ),
        counted AS (
            SELECT r.root, g.account_id, g.status, g.created_at,
                   g.status = 'still_ok' AND a.trust_level >= 1
                   AND NOT EXISTS (SELECT 1 FROM authors au
                                   WHERE au.root = r.root AND au.account_id = g.account_id)
                   AND NOT EXISTS (SELECT 1 FROM confirmations k
                                   JOIN family f ON f.root = r.root AND f.id = k.place_id
                                   WHERE k.account_id = g.account_id AND k.status = 'still_ok'
                                     AND k.id <> ALL($1))
                       AS confirms
            FROM gone g
            JOIN roots r ON r.start = g.place_id
            LEFT JOIN accounts a ON a.id = g.account_id
            WHERE a.banned_at IS NULL
        )
        INSERT INTO confirmation_tallies (place_id, last_ok, confirmers)
        SELECT root,
               max(created_at) FILTER (WHERE status = 'still_ok'),
               (count(DISTINCT account_id) FILTER (WHERE confirms))::int4
        FROM counted
        GROUP BY root
        ON CONFLICT (place_id) DO UPDATE SET
            last_ok = greatest(confirmation_tallies.last_ok, EXCLUDED.last_ok),
            confirmers = confirmation_tallies.confirmers + EXCLUDED.confirmers,
            updated_at = now()
        "#,
        &old
    )
    .execute(&mut *tx)
    .await?;
    // The trust rules count the distinct places an account confirmed: a
    // place whose last answer from the account goes counts on the account.
    sqlx::query!(
        r#"
        UPDATE accounts a SET archived_confirmations = a.archived_confirmations + n.places::int4
        FROM (
            SELECT c.account_id, count(DISTINCT c.place_id) AS places
            FROM confirmations c
            WHERE c.id = ANY($1) AND c.account_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM confirmations k
                  WHERE k.account_id = c.account_id AND k.place_id = c.place_id
                    AND k.id <> ALL($1))
            GROUP BY c.account_id
        ) n
        WHERE a.id = n.account_id
        "#,
        &old
    )
    .execute(&mut *tx)
    .await?;
    let deleted = sqlx::query!("DELETE FROM confirmations WHERE id = ANY($1)", &old)
        .execute(&mut *tx)
        .await?
        .rows_affected();
    tx.commit().await?;
    Ok(deleted)
}
