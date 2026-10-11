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
//!   added to it; the other lists change owner. The caps of one account
//!   (`lists::MAX_LISTS` and the others) may be passed, twice at most: the
//!   account then adds nothing more until it removes some;
//! - the home: the target's stays when it has one, else the absorbed one's
//!   moves;
//! - public contributions (ratings and reviews of places and of points,
//!   photos, "still there?" answers, issue and road reports, new places and
//!   edits): they change author and show the target's pseudonym. Two
//!   reviews of one place (the places merged into it included) or of one
//!   point keep the target's row, which takes the stricter moderation
//!   status of the two and the reports and queue entries of the other, as
//!   two reviews of one author do when their places merge
//!   (`community::own_row_in_family`): a merge never lifts a moderation
//!   decision, and a decision to come counts against the account kept;
//! - content reports, mutes in both directions, endorsements, idempotency
//!   keys: moved, a duplicate dropped. A report, a mute or an endorsement
//!   between the two accounts is about one person and goes;
//! - the account's own record: the earliest creation, the most active
//!   days, the removals by moderation added up, and a ceiling on its level
//!   (`accounts.level_ceiling`, the higher of the two) until its next
//!   contribution. A level the administration granted is never carried: it
//!   was given to the absorbed account (the store reviewers' demo account,
//!   whose card is shared), not to the one it goes into.
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
    /// Lists that changed owner or joined one of the target's.
    pub lists: u64,
    /// Ratings and reviews (of places and of points) that changed author.
    pub reviews: u64,
    /// Reviews of the absorbed account folded into one of the target's.
    pub reviews_folded: u64,
    /// Photos that changed author.
    pub photos: u64,
    /// What happened to the homes.
    pub home: HomeOutcome,
}

/// The account row as the merge reads it, locked.
struct Locked {
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
    // opposite directions wait for each other instead of deadlocking, and
    // nothing new references either account until the end.
    let rows = sqlx::query!(
        r#"
        SELECT id, banned_at IS NOT NULL AS "banned!"
        FROM accounts WHERE id = ANY($1) ORDER BY id FOR UPDATE
        "#,
        &[absorbed, into][..]
    )
    .fetch_all(&mut *tx)
    .await?;
    let locked: HashMap<Uuid, Locked> = rows
        .into_iter()
        .map(|r| (r.id, Locked { banned: r.banned }))
        .collect();
    let (Some(from), Some(to)) = (locked.get(&absorbed), locked.get(&into)) else {
        return Ok(Err(MergeRefusal::Missing));
    };
    if from.banned || to.banned {
        return Ok(Err(MergeRefusal::Banned));
    }
    forget_reports_between(&mut tx, absorbed, into).await?;
    let lists = merge_lists(&mut tx, absorbed, into).await?;
    let home = merge_home(&mut tx, absorbed, into).await?;
    let (reviews, reviews_folded) = merge_reviews(&mut tx, absorbed, into).await?;
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
    // Last: the queue's rows stay locked until the commit, and taking
    // them first would hold them while the moves wait on other writers.
    queue_summaries(&mut tx, into).await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(Ok(Merged {
        lists,
        reviews,
        reviews_folded,
        photos,
        home,
    }))
}

/// Queues every place and point whose summary counts the target: its rows,
/// those it received included, now count under its level and ban. In key
/// order, as `accounts::queue_level_dependents` does.
async fn queue_summaries(conn: &mut PgConnection, into: Uuid) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        INSERT INTO place_refresh_queue (place_id)
        SELECT place_id FROM (
            SELECT place_id FROM reviews WHERE account_id = $1
            UNION SELECT place_id FROM photos WHERE account_id = $1
            UNION SELECT place_id FROM confirmations WHERE account_id = $1
            UNION SELECT place_id FROM issue_reports WHERE account_id = $1
        ) touched
        ORDER BY place_id
        ON CONFLICT DO NOTHING
        "#,
        into
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO poi_refresh_queue (poi_id)
        SELECT DISTINCT poi_id FROM poi_confirmations WHERE account_id = $1
        ORDER BY poi_id
        ON CONFLICT DO NOTHING
        "#,
        into
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// Drops the reports either account made of what either account wrote:
/// one person does not report itself, and such a report would hold a
/// review the merge folds. A report entry of the queue left with no report
/// goes with them.
async fn forget_reports_between(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(), DbError> {
    let both = [absorbed, into];
    let targets = sqlx::query_scalar!(
        r#"
        DELETE FROM content_reports c
        WHERE c.reporter_id = ANY($1) AND (
            EXISTS (SELECT 1 FROM reviews r WHERE r.id = c.target_id AND r.account_id = ANY($1))
            OR EXISTS (SELECT 1 FROM poi_reviews r
                       WHERE r.id = c.target_id AND r.account_id = ANY($1))
            OR EXISTS (SELECT 1 FROM photos p WHERE p.id = c.target_id AND p.account_id = ANY($1)))
        RETURNING c.target_id
        "#,
        &both[..]
    )
    .fetch_all(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        DELETE FROM moderation_queue q
        WHERE q.kind = 'reported_content' AND q.status = 'open' AND q.target_id = ANY($1)
          AND NOT EXISTS (SELECT 1 FROM content_reports c
                          WHERE c.target_id = q.target_id AND c.dismissed_at IS NULL)
        "#,
        &targets
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// Joins the absorbed account's lists to the target's: a list of the same
/// name, or two default lists, become the target's one; the others change
/// owner. Returns how many lists of the absorbed account moved or joined.
async fn merge_lists(conn: &mut PgConnection, absorbed: Uuid, into: Uuid) -> Result<u64, DbError> {
    // Locked: a place saved to one of them meanwhile waits, and lands in
    // the list it joins or follows it.
    let theirs = sqlx::query!(
        r#"
        SELECT id, name FROM favorite_lists WHERE account_id = $1
        ORDER BY created_at, id FOR UPDATE
        "#,
        absorbed
    )
    .fetch_all(&mut *conn)
    .await?;
    let ours = sqlx::query!(
        r#"
        SELECT id, name FROM favorite_lists WHERE account_id = $1
        ORDER BY created_at, id FOR UPDATE
        "#,
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
/// accounts reviewed one place (its whole family of merged places, as
/// `community::own_row_in_family` walks it) or one point, the absorbed
/// row folds into the target's ([`fold_review`], [`fold_poi_review`]).
/// Returns how many moved and how many folded.
async fn merge_reviews(
    conn: &mut PgConnection,
    absorbed: Uuid,
    into: Uuid,
) -> Result<(u64, u64), DbError> {
    // Each review's live place: up the chain of merges to the place that
    // absorbed the others. Two reviews of one family share it.
    let pairs = sqlx::query!(
        r#"
        WITH RECURSIVE up (review_id, account_id, place_id, depth) AS (
            SELECT id, account_id, place_id, 0 FROM reviews WHERE account_id = ANY($1)
            UNION ALL
            SELECT u.review_id, u.account_id, p.merged_into, u.depth + 1
            FROM up u JOIN places p ON p.id = u.place_id
            WHERE p.merged_into IS NOT NULL AND u.depth < 64
        ), live AS (
            SELECT DISTINCT ON (review_id) review_id, account_id, place_id
            FROM up ORDER BY review_id, depth DESC
        )
        SELECT DISTINCT ON (a.review_id) a.review_id AS "absorbed!", b.review_id AS "kept!"
        FROM live a JOIN live b ON b.place_id = a.place_id AND b.account_id = $3
        WHERE a.account_id = $2
        ORDER BY a.review_id, b.review_id
        "#,
        &[absorbed, into][..],
        absorbed,
        into
    )
    .fetch_all(&mut *conn)
    .await?;
    let mut folded = 0;
    for p in pairs {
        fold_review(conn, p.absorbed, p.kept).await?;
        folded += 1;
    }
    let point_pairs = sqlx::query!(
        r#"
        SELECT a.id AS absorbed, b.id AS kept
        FROM poi_reviews a JOIN poi_reviews b ON b.poi_id = a.poi_id AND b.account_id = $2
        WHERE a.account_id = $1
        "#,
        absorbed,
        into
    )
    .fetch_all(&mut *conn)
    .await?;
    for p in point_pairs {
        fold_poi_review(conn, p.absorbed, p.kept).await?;
        folded += 1;
    }
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
    Ok((moved, folded))
}

/// Folds the review `absorbed` into the review `kept`: `kept` takes the
/// stricter status of the two, the reports and queue entries of `absorbed`
/// follow it, and `absorbed` goes.
async fn fold_review(conn: &mut PgConnection, absorbed: Uuid, kept: Uuid) -> Result<(), DbError> {
    move_moderation(conn, absorbed, kept).await?;
    sqlx::query!(
        r#"
        UPDATE reviews k SET status = CASE
            WHEN (CASE a.status WHEN 'removed' THEN 3 WHEN 'hidden' THEN 2
                                WHEN 'pending' THEN 1 ELSE 0 END)
               > (CASE k.status WHEN 'removed' THEN 3 WHEN 'hidden' THEN 2
                                WHEN 'pending' THEN 1 ELSE 0 END)
            THEN a.status ELSE k.status END
        FROM reviews a WHERE k.id = $2 AND a.id = $1
        "#,
        absorbed,
        kept
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!("DELETE FROM reviews WHERE id = $1", absorbed)
        .execute(&mut *conn)
        .await?;
    Ok(())
}

/// [`fold_review`] for the reviews of a point of interest.
async fn fold_poi_review(
    conn: &mut PgConnection,
    absorbed: Uuid,
    kept: Uuid,
) -> Result<(), DbError> {
    move_moderation(conn, absorbed, kept).await?;
    sqlx::query!(
        r#"
        UPDATE poi_reviews k SET status = CASE
            WHEN (CASE a.status WHEN 'removed' THEN 3 WHEN 'hidden' THEN 2
                                WHEN 'pending' THEN 1 ELSE 0 END)
               > (CASE k.status WHEN 'removed' THEN 3 WHEN 'hidden' THEN 2
                                WHEN 'pending' THEN 1 ELSE 0 END)
            THEN a.status ELSE k.status END
        FROM poi_reviews a WHERE k.id = $2 AND a.id = $1
        "#,
        absorbed,
        kept
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!("DELETE FROM poi_reviews WHERE id = $1", absorbed)
        .execute(&mut *conn)
        .await?;
    Ok(())
}

/// The reports and queue entries about the review `from` now speak of the
/// review `to`: a reporter who reported both keeps one report, and an open
/// entry of a kind `to` already has open stays that one.
async fn move_moderation(conn: &mut PgConnection, from: Uuid, to: Uuid) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        UPDATE content_reports c SET target_id = $2
        WHERE c.target_id = $1 AND NOT EXISTS (
            SELECT 1 FROM content_reports o
            WHERE o.target_id = $2 AND o.target_type = c.target_type
              AND o.reporter_id = c.reporter_id)
        "#,
        from,
        to
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!("DELETE FROM content_reports WHERE target_id = $1", from)
        .execute(&mut *conn)
        .await?;
    sqlx::query!(
        r#"
        UPDATE moderation_queue q SET target_id = $2
        WHERE q.target_id = $1 AND NOT (q.status = 'open' AND EXISTS (
            SELECT 1 FROM moderation_queue o
            WHERE o.target_id = $2 AND o.kind = q.kind AND o.status = 'open'))
        "#,
        from,
        to
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!("DELETE FROM moderation_queue WHERE target_id = $1", from)
        .execute(&mut *conn)
        .await?;
    Ok(())
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
/// its earliest creation, its most active days, and every removal by
/// moderation, which a merge must not wash away. Its level shows no more
/// than the higher of the two until its next contribution. A granted
/// level stays the target's own.
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

/// The account a device key went into when its own account was merged.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergedInto {
    /// The account.
    pub account: Uuid,
    /// Its pseudonym.
    pub pseudonym: String,
    /// Whether it is banned.
    pub banned: bool,
}

/// The account the device key `public_key` (SEC1, uncompressed) went into
/// when its own account was merged.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn merged_into(pool: &PgPool, public_key: &[u8]) -> Result<Option<MergedInto>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT a.id, a.pseudonym, a.banned_at IS NOT NULL AS "banned!"
        FROM merged_keys m JOIN accounts a ON a.id = m.into_account
        WHERE m.key_hash = sha256($1)
        "#,
        public_key
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| MergedInto {
        account: r.id,
        pseudonym: r.pseudonym,
        banned: r.banned,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_default_list_names_are_the_app_s() {
        // The app names its default list on the account in the language it
        // runs in (`favorites.defaultList`); a merge must recognise each.
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../app/lib/i18n");
        let mut names: Vec<String> = ["fr", "en", "de", "es", "it", "nl"]
            .iter()
            .map(|lang| {
                let text = std::fs::read_to_string(format!("{dir}/{lang}.i18n.json"))
                    .expect("the app's translations are in the repository");
                let json: serde_json::Value = serde_json::from_str(&text).expect("valid JSON");
                json["favorites"]["defaultList"]
                    .as_str()
                    .expect("every language names the default list")
                    .to_owned()
            })
            .collect();
        names.sort();
        let mut known: Vec<String> = DEFAULT_LIST_NAMES.iter().map(|n| (*n).to_owned()).collect();
        known.sort();
        assert_eq!(
            names, known,
            "DEFAULT_LIST_NAMES follows the app's languages"
        );
    }
}
