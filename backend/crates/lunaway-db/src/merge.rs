//! The merge of one account into another (`mergeAccount`): a person who
//! used two accounts keeps one. Everything the absorbed account holds moves
//! to the account it goes into, then the absorbed account is deleted, in
//! one transaction: either both accounts are as they were, or the absorbed
//! one is gone and its history belongs to the other.
//!
//! What moves, and how a conflict ends (the account merged into wins):
//!
//! - favourite lists: a list of the same name (or both default lists, in
//!   any language of the app) becomes one, the other's places and points
//!   added to it; the other lists change owner;
//! - the home: the target's stays when it has one, else the absorbed one's
//!   moves;
//! - public contributions (ratings and reviews of places and of points,
//!   photos, "still there?" answers, issue and road reports, new places and
//!   edits): they change author and show the target's pseudonym. Two
//!   reviews of one place keep the target's; the absorbed one is deleted,
//!   or, under moderation or reported, withdrawn without author, as its
//!   author deleting it would have done;
//! - content reports, mutes in both directions, endorsements, idempotency
//!   keys: moved, a duplicate or a self-reference dropped;
//! - the account's own record: the earliest creation, the most active
//!   days, the highest level granted, the removals by moderation added up;
//!   the level itself is capped by the caller ([`Merged::ceiling`]).
//!
//! Device keys, sessions and the recovery code of the absorbed account go
//! with it; the hash of each key stays in `merged_keys`, pointing at the
//! target, so its other devices learn where it went at their next sign-in.
//! Nothing here logs a list's name, a point or a review.

use std::collections::HashMap;

use lunaway_domain::favorites::DEFAULT_LIST_NAMES;
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{DbError, PgPool};

/// Why a merge was refused; nothing changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MergeRefusal {
    /// One of the two accounts does not exist.
    Missing,
    /// The two are the same account.
    Same,
    /// One of the two is banned: a merge must not wash a ban away.
    Banned,
}

/// What happened to the homes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HomeOutcome {
    /// Neither account had one.
    None,
    /// The target kept its own; the absorbed account's went with it.
    KeptTarget,
    /// The absorbed account's home became the target's.
    Moved,
}

/// What a merge did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Merged {
    /// The level the account merged into may show, at most, until its next
    /// contribution: the higher of the two levels before the merge.
    pub ceiling: i16,
    /// Lists that changed owner or joined one of the target's.
    pub lists: u64,
    /// Ratings and reviews (of places and of points) that changed author.
    pub reviews: u64,
    /// Reviews of the absorbed account dropped for one of the target's.
    pub reviews_dropped: u64,
    /// Photos that changed author.
    pub photos: u64,
    /// What happened to the homes.
    pub home: HomeOutcome,
}

/// The account row as the merge reads it, locked.
struct Locked {
    trust_level: i16,
    banned: bool,
}

/// Merges the account `absorbed` into the account `into`, then deletes
/// `absorbed`. `Ok(Err(_))` when the merge is refused, nothing changed.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is changed then.
pub async fn merge_accounts(
    pool: &PgPool,
    absorbed: Uuid,
    into: Uuid,
) -> Result<Result<Merged, MergeRefusal>, DbError> {
    if absorbed == into {
        return Ok(Err(MergeRefusal::Same));
    }
    let mut tx = pool.begin().await?;
    // Both rows locked in one order, so two merges of the same pair in
    // opposite directions wait for each other instead of deadlocking.
    let rows = sqlx::query!(
        r#"
        SELECT id, trust_level, banned_at IS NOT NULL AS "banned!"
        FROM accounts WHERE id = ANY($1) ORDER BY id FOR UPDATE
        "#,
        &[absorbed, into][..]
    )
    .fetch_all(&mut *tx)
    .await?;
    let locked: HashMap<Uuid, Locked> = rows
        .into_iter()
        .map(|r| {
            (
                r.id,
                Locked {
                    trust_level: r.trust_level,
                    banned: r.banned,
                },
            )
        })
        .collect();
    let (Some(from), Some(to)) = (locked.get(&absorbed), locked.get(&into)) else {
        return Ok(Err(MergeRefusal::Missing));
    };
    if from.banned || to.banned {
        return Ok(Err(MergeRefusal::Banned));
    }
    let ceiling = from.trust_level.max(to.trust_level);
    queue_summaries(&mut tx, absorbed, into).await?;
    let lists = merge_lists(&mut tx, absorbed, into).await?;
    let home = merge_home(&mut tx, absorbed, into).await?;
    let (reviews, reviews_dropped) = merge_reviews(&mut tx, absorbed, into).await?;
    let photos = sqlx::query!(
        "UPDATE photos SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    move_contributions(&mut tx, absorbed, into).await?;
    move_relations(&mut tx, absorbed, into).await?;
    merge_account_row(&mut tx, absorbed, into).await?;
    // Its keys point at the target from now on, and so do the keys of the
    // accounts it absorbed before.
    sqlx::query!(
        r#"
        INSERT INTO merged_keys (key_hash, into_account)
        SELECT sha256(public_key), $2 FROM device_keys WHERE account_id = $1
        ON CONFLICT (key_hash) DO UPDATE SET into_account = EXCLUDED.into_account,
                                             merged_at = now()
        "#,
        absorbed,
        into
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE merged_keys SET into_account = $2 WHERE into_account = $1",
        absorbed,
        into
    )
    .execute(&mut *tx)
    .await?;
    // What is left goes with it: keys, sessions, recovery code, its
    // duplicates of what the target held.
    sqlx::query!("DELETE FROM accounts WHERE id = $1", absorbed)
        .execute(&mut *tx)
        .await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(Ok(Merged {
        ceiling,
        lists,
        reviews,
        reviews_dropped,
        photos,
        home,
    }))
}

/// Queues every place and point whose summary counts either account: the
/// rows change author, and the target's level and ban decide what counts.
/// In key order, as `accounts::queue_level_dependents` does.
async fn queue_summaries(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(), DbError> {
    let both = [absorbed, into];
    sqlx::query!(
        r#"
        INSERT INTO place_refresh_queue (place_id)
        SELECT place_id FROM (
            SELECT place_id FROM reviews WHERE account_id = ANY($1)
            UNION SELECT place_id FROM photos WHERE account_id = ANY($1)
            UNION SELECT place_id FROM confirmations WHERE account_id = ANY($1)
            UNION SELECT place_id FROM issue_reports WHERE account_id = ANY($1)
        ) touched
        ORDER BY place_id
        ON CONFLICT DO NOTHING
        "#,
        &both[..]
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO poi_refresh_queue (poi_id)
        SELECT DISTINCT poi_id FROM poi_confirmations WHERE account_id = ANY($1)
        ORDER BY poi_id
        ON CONFLICT DO NOTHING
        "#,
        &both[..]
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// Joins the absorbed account's lists to the target's: a list of the same
/// name, or two default lists, become the target's one; the others change
/// owner. Returns how many lists of the absorbed account moved or joined.
async fn merge_lists(conn: &mut PgConnection, absorbed: Uuid, into: Uuid) -> Result<u64, DbError> {
    let theirs = sqlx::query!(
        "SELECT id, name FROM favorite_lists WHERE account_id = $1 ORDER BY created_at, id",
        absorbed
    )
    .fetch_all(&mut *conn)
    .await?;
    let ours = sqlx::query!(
        "SELECT id, name FROM favorite_lists WHERE account_id = $1 ORDER BY created_at, id",
        into
    )
    .fetch_all(&mut *conn)
    .await?;
    let is_default = |name: &str| DEFAULT_LIST_NAMES.contains(&name);
    let mut moved = 0;
    for list in theirs {
        let same = ours
            .iter()
            .find(|o| o.name == list.name)
            .or_else(|| {
                is_default(&list.name)
                    .then(|| ours.iter().find(|o| is_default(&o.name)))
                    .flatten()
            })
            .map(|o| o.id);
        match same {
            Some(target) => {
                sqlx::query!(
                    r#"
                    INSERT INTO favorite_items (list_id, place_id, added_at)
                    SELECT $2, place_id, added_at FROM favorite_items WHERE list_id = $1
                    ON CONFLICT DO NOTHING
                    "#,
                    list.id,
                    target
                )
                .execute(&mut *conn)
                .await?;
                sqlx::query!(
                    r#"
                    INSERT INTO favorite_points
                        (list_id, id, kind, name, note, address, lat, lon, poi_id, poi_kind,
                         added_at, updated_at)
                    SELECT $2, id, kind, name, note, address, lat, lon, poi_id, poi_kind,
                           added_at, updated_at
                    FROM favorite_points WHERE list_id = $1
                    ON CONFLICT (list_id, id) DO NOTHING
                    "#,
                    list.id,
                    target
                )
                .execute(&mut *conn)
                .await?;
                sqlx::query!(
                    "UPDATE favorite_lists SET updated_at = now() WHERE id = $1",
                    target
                )
                .execute(&mut *conn)
                .await?;
                sqlx::query!("DELETE FROM favorite_lists WHERE id = $1", list.id)
                    .execute(&mut *conn)
                    .await?;
            }
            None => {
                sqlx::query!(
                    "UPDATE favorite_lists SET account_id = $2, updated_at = now() WHERE id = $1",
                    list.id,
                    into
                )
                .execute(&mut *conn)
                .await?;
            }
        }
        moved += 1;
    }
    Ok(moved)
}

/// The target's home stays; without one, the absorbed account's moves.
async fn merge_home(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<HomeOutcome, DbError> {
    let had = sqlx::query!(
        r#"
        SELECT EXISTS (SELECT 1 FROM favorite_homes WHERE account_id = $1) AS "theirs!",
               EXISTS (SELECT 1 FROM favorite_homes WHERE account_id = $2) AS "ours!"
        "#,
        absorbed,
        into
    )
    .fetch_one(&mut *conn)
    .await?;
    if had.ours {
        return Ok(if had.theirs {
            HomeOutcome::KeptTarget
        } else {
            HomeOutcome::None
        });
    }
    if !had.theirs {
        return Ok(HomeOutcome::None);
    }
    sqlx::query!(
        "UPDATE favorite_homes SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    Ok(HomeOutcome::Moved)
}

/// Moves the ratings and reviews of places and of points. Where both
/// accounts reviewed one place (merged places followed) or one point, the
/// target's stays; the absorbed one goes as its author deleting it would:
/// withdrawn and kept without author when a moderator or a report holds
/// it, deleted otherwise. Returns how many moved and how many went.
async fn merge_reviews(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(u64, u64), DbError> {
    let clashing = sqlx::query!(
        r#"
        SELECT r.id AS "id!", r.status IN ('hidden', 'removed') OR EXISTS (
                   SELECT 1 FROM content_reports c
                   WHERE c.target_id = r.id AND c.dismissed_at IS NULL) AS "held!"
        FROM reviews r
        JOIN places p ON p.id = r.place_id
        WHERE r.account_id = $1 AND EXISTS (
            SELECT 1 FROM reviews o JOIN places q ON q.id = o.place_id
            WHERE o.account_id = $2
              AND coalesce(q.merged_into, q.id) = coalesce(p.merged_into, p.id))
        UNION ALL
        SELECT r.id, r.status IN ('hidden', 'removed') OR EXISTS (
                   SELECT 1 FROM content_reports c
                   WHERE c.target_type = 'poi_review' AND c.target_id = r.id
                     AND c.dismissed_at IS NULL)
        FROM poi_reviews r
        WHERE r.account_id = $1 AND EXISTS (
            SELECT 1 FROM poi_reviews o WHERE o.account_id = $2 AND o.poi_id = r.poi_id)
        "#,
        absorbed,
        into
    )
    .fetch_all(&mut *conn)
    .await?;
    let (held, gone): (Vec<_>, Vec<_>) = clashing.into_iter().partition(|r| r.held);
    let held: Vec<Uuid> = held.into_iter().map(|r| r.id).collect();
    let gone: Vec<Uuid> = gone.into_iter().map(|r| r.id).collect();
    sqlx::query!(
        r#"
        UPDATE reviews SET account_id = NULL, body = NULL, lang = NULL, visited_on = NULL,
               vehicle = NULL, withdrawn_at = coalesce(withdrawn_at, now()), updated_at = now()
        WHERE id = ANY($1)
        "#,
        &held
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        UPDATE poi_reviews SET account_id = NULL, body = NULL, lang = NULL, visited_on = NULL,
               withdrawn_at = coalesce(withdrawn_at, now()), updated_at = now()
        WHERE id = ANY($1)
        "#,
        &held
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!("DELETE FROM reviews WHERE id = ANY($1)", &gone)
        .execute(&mut *conn)
        .await?;
    sqlx::query!("DELETE FROM poi_reviews WHERE id = ANY($1)", &gone)
        .execute(&mut *conn)
        .await?;
    sqlx::query!(
        "DELETE FROM content_reports WHERE target_id = ANY($1)",
        &gone
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "DELETE FROM moderation_queue WHERE target_id = ANY($1) AND status = 'open'",
        &gone
    )
    .execute(&mut *conn)
    .await?;
    let moved = sqlx::query!(
        "UPDATE reviews SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?
    .rows_affected()
        + sqlx::query!(
            "UPDATE poi_reviews SET account_id = $2 WHERE account_id = $1",
            absorbed,
            into
        )
        .execute(&mut *conn)
        .await?
        .rows_affected();
    let dropped = u64::try_from(held.len() + gone.len()).unwrap_or(u64::MAX);
    Ok((moved, dropped))
}

/// The contributions with an author and no rule of one per account: they
/// change author.
async fn move_contributions(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(), DbError> {
    sqlx::query!(
        "UPDATE confirmations SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "UPDATE poi_confirmations SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "UPDATE issue_reports SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    // The key that signed a revision goes with the absorbed account
    // (`ON DELETE SET NULL`); the revision keeps its author.
    sqlx::query!(
        "UPDATE place_submissions SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "UPDATE road_event_reports SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "UPDATE moderation_queue SET account_id = $2 WHERE account_id = $1",
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// What ties the absorbed account to others: its content reports, its
/// mutes and the mutes of it, its endorsements both ways, its idempotency
/// keys. Each moves to the target unless the target holds the same, or it
/// would point the target at itself; what stays behind goes with the
/// absorbed account.
async fn move_relations(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(), DbError> {
    // A report of its own content, by either account, is no report: an
    // author does not report itself.
    sqlx::query!(
        r#"
        DELETE FROM content_reports c
        WHERE c.reporter_id = ANY($1) AND (
            EXISTS (SELECT 1 FROM reviews r WHERE r.id = c.target_id AND r.account_id = ANY($1))
            OR EXISTS (SELECT 1 FROM poi_reviews r
                       WHERE r.id = c.target_id AND r.account_id = ANY($1))
            OR EXISTS (SELECT 1 FROM photos p WHERE p.id = c.target_id AND p.account_id = ANY($1)))
        "#,
        &[absorbed, into][..]
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        UPDATE content_reports c SET reporter_id = $2
        WHERE c.reporter_id = $1 AND NOT EXISTS (
            SELECT 1 FROM content_reports o
            WHERE o.reporter_id = $2 AND o.target_type = c.target_type
              AND o.target_id = c.target_id)
        "#,
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO muted_authors (account_id, muted_id, created_at)
        SELECT $2, muted_id, created_at FROM muted_authors
        WHERE account_id = $1 AND muted_id <> $2
        UNION ALL
        SELECT account_id, $2, created_at FROM muted_authors
        WHERE muted_id = $1 AND account_id <> $2
        ON CONFLICT DO NOTHING
        "#,
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO account_endorsements (account_id, kind, by_account_id, created_at)
        SELECT $2, kind, by_account_id, created_at FROM account_endorsements
        WHERE account_id = $1 AND by_account_id <> $2
        UNION ALL
        SELECT account_id, kind, $2, created_at FROM account_endorsements
        WHERE by_account_id = $1 AND account_id <> $2
        ON CONFLICT DO NOTHING
        "#,
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    // A contribution the device sends again after the merge finds what it
    // made under the absorbed account.
    sqlx::query!(
        r#"
        INSERT INTO idempotency_keys (account_id, key, operation, request_hash, result_id, created_at)
        SELECT $2, key, operation, request_hash, result_id, created_at FROM idempotency_keys
        WHERE account_id = $1
        ON CONFLICT DO NOTHING
        "#,
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// The target's record takes what the absorbed account's history earned:
/// its earliest creation, its most active days, the highest level granted,
/// and every removal by moderation, which a merge must not wash away.
async fn merge_account_row(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        UPDATE accounts t SET
            created_at = least(t.created_at, a.created_at),
            active_days = greatest(t.active_days, a.active_days),
            last_active_on = greatest(t.last_active_on, a.last_active_on),
            granted_level = greatest(t.granted_level, a.granted_level),
            moderation_removals = t.moderation_removals + a.moderation_removals,
            archived_confirmations = t.archived_confirmations + a.archived_confirmations,
            level_ceiling = greatest(t.trust_level, a.trust_level)
        FROM accounts a
        WHERE t.id = $2 AND a.id = $1
        "#,
        absorbed,
        into
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// The account the device key `public_key` (SEC1, uncompressed) went into
/// when its own account was merged, with that account's pseudonym.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn merged_into(
    pool: &PgPool,
    public_key: &[u8],
) -> Result<Option<(Uuid, String)>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT a.id, a.pseudonym FROM merged_keys m JOIN accounts a ON a.id = m.into_account
        WHERE m.key_hash = sha256($1)
        "#,
        public_key
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| (r.id, r.pseudonym)))
}
