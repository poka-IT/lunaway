//! Accounts without e-mail: device keys, sessions, recovery codes, the
//! pseudonym, trust levels and endorsements, and the deletion of an account.
//!
//! Secrets are never stored: a session is kept as the SHA-256 of its token,
//! a recovery code as its argon2id hash; both are computed by
//! `lunaway-auth` before they reach this module.

use chrono::{DateTime, NaiveDate, Utc};
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{DbError, PgPool};

/// An account as the API sees it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountRow {
    /// Its id.
    pub id: Uuid,
    /// Public display name.
    pub pseudonym: String,
    /// Level the rules last gave it.
    pub trust_level: i16,
    /// Floor set by the administration.
    pub granted_level: i16,
    /// When it was created.
    pub created_at: DateTime<Utc>,
    /// When it was banned, if it was.
    pub banned_at: Option<DateTime<Utc>>,
}

/// A live session and its account.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionRow {
    /// The account.
    pub account: AccountRow,
    /// The device key that opened the session.
    pub device_key_id: Uuid,
    /// When the session was opened (a signed sign-in).
    pub created_at: DateTime<Utc>,
    /// Last use, to slide the expiry at most once in a while.
    pub last_used_at: DateTime<Utc>,
    /// The account's last active day (UTC).
    pub last_active_on: NaiveDate,
}

/// What `create_with_key` stores.
#[derive(Debug, Clone, Copy)]
pub struct NewAccount<'a> {
    /// Generated pseudonym.
    pub pseudonym: &'a str,
    /// RFC 7638 thumbprint of the device key.
    pub thumbprint: &'a str,
    /// The key, SEC1 uncompressed.
    pub public_key: &'a [u8],
    /// SHA-256 of the session token.
    pub session_hash: &'a [u8; 32],
    /// Session lifetime, seconds.
    pub session_ttl_secs: f64,
}

/// A device key known to the server.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DeviceKey {
    /// The key's id.
    pub id: Uuid,
    /// Its account.
    pub account_id: Uuid,
    /// Whether the account is banned.
    pub banned: bool,
}

/// Whether the device key `public_key` (SEC1, uncompressed) belonged to a
/// banned account that deleted itself: it may not open an account again
/// while its record lasts.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn key_banned(pool: &PgPool, public_key: &[u8]) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM banned_keys WHERE key_hash = sha256($1)) AS "banned!""#,
        public_key
    )
    .fetch_one(pool)
    .await?)
}

/// The device key with this thumbprint.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn key_by_thumbprint(
    pool: &PgPool,
    thumbprint: &str,
) -> Result<Option<DeviceKey>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT k.id, k.account_id, a.banned_at IS NOT NULL AS "banned!"
        FROM device_keys k JOIN accounts a ON a.id = k.account_id
        WHERE k.thumbprint = $1
        "#,
        thumbprint,
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| DeviceKey {
        id: r.id,
        account_id: r.account_id,
        banned: r.banned,
    }))
}

/// Creates an account at level 0 with its first device key and a session,
/// in one transaction. Returns the account and the session's expiry.
///
/// # Errors
///
/// [`DbError`] when a statement fails, including when another request
/// registered the same key a moment before (unique thumbprint).
pub async fn create_with_key(
    pool: &PgPool,
    new: NewAccount<'_>,
) -> Result<(AccountRow, DateTime<Utc>), DbError> {
    let mut tx = pool.begin().await?;
    let account = sqlx::query_as!(
        AccountRow,
        r#"
        INSERT INTO accounts (id, pseudonym) VALUES ($1, $2)
        RETURNING id, pseudonym, trust_level, granted_level, created_at, banned_at
        "#,
        Uuid::now_v7(),
        new.pseudonym,
    )
    .fetch_one(&mut *tx)
    .await?;
    let key_id = Uuid::now_v7();
    sqlx::query!(
        "INSERT INTO device_keys (id, account_id, thumbprint, public_key) VALUES ($1, $2, $3, $4)",
        key_id,
        account.id,
        new.thumbprint,
        new.public_key,
    )
    .execute(&mut *tx)
    .await?;
    let expires = sqlx::query_scalar!(
        r#"
        INSERT INTO sessions (token_hash, account_id, device_key_id, expires_at)
        VALUES ($1, $2, $3, now() + make_interval(secs => $4))
        RETURNING expires_at
        "#,
        &new.session_hash[..],
        account.id,
        key_id,
        new.session_ttl_secs,
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((account, expires))
}

/// Opens a session for a known key, and notes the key's use. Returns the
/// session's expiry.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn open_session(
    pool: &PgPool,
    key: &DeviceKey,
    session_hash: &[u8; 32],
    ttl_secs: f64,
) -> Result<DateTime<Utc>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!(
        "UPDATE device_keys SET last_used_at = now() WHERE id = $1",
        key.id
    )
    .execute(&mut *tx)
    .await?;
    let expires = sqlx::query_scalar!(
        r#"
        INSERT INTO sessions (token_hash, account_id, device_key_id, expires_at)
        VALUES ($1, $2, $3, now() + make_interval(secs => $4))
        RETURNING expires_at
        "#,
        &session_hash[..],
        key.account_id,
        key.id,
        ttl_secs,
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(expires)
}

/// Attaches a new device key to `account` (account recovery) and opens a
/// session with it; returns the session's expiry and the key's id. A key
/// already attached to this account is reused; a key of another account is
/// refused (`Ok(None)`).
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn attach_key_and_open_session(
    pool: &PgPool,
    account: Uuid,
    thumbprint: &str,
    public_key: &[u8],
    session_hash: &[u8; 32],
    ttl_secs: f64,
) -> Result<Option<(DateTime<Utc>, Uuid)>, DbError> {
    let mut tx = pool.begin().await?;
    let existing = sqlx::query!(
        "SELECT id, account_id FROM device_keys WHERE thumbprint = $1 FOR UPDATE",
        thumbprint
    )
    .fetch_optional(&mut *tx)
    .await?;
    let key_id = match existing {
        Some(k) if k.account_id != account => return Ok(None),
        Some(k) => k.id,
        None => {
            let id = Uuid::now_v7();
            sqlx::query!(
                "INSERT INTO device_keys (id, account_id, thumbprint, public_key) VALUES ($1, $2, $3, $4)",
                id,
                account,
                thumbprint,
                public_key,
            )
            .execute(&mut *tx)
            .await?;
            id
        }
    };
    let expires = sqlx::query_scalar!(
        r#"
        INSERT INTO sessions (token_hash, account_id, device_key_id, expires_at)
        VALUES ($1, $2, $3, now() + make_interval(secs => $4))
        RETURNING expires_at
        "#,
        &session_hash[..],
        account,
        key_id,
        ttl_secs,
    )
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Some((expires, key_id)))
}

/// The live session whose token hashes to `hash`, with its account.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn session(pool: &PgPool, hash: &[u8; 32]) -> Result<Option<SessionRow>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT s.device_key_id, s.created_at AS opened_at, s.last_used_at, a.id, a.pseudonym,
               a.trust_level, a.granted_level, a.created_at, a.banned_at, a.last_active_on
        FROM sessions s JOIN accounts a ON a.id = s.account_id
        WHERE s.token_hash = $1 AND s.expires_at > now()
        "#,
        &hash[..],
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| SessionRow {
        account: AccountRow {
            id: r.id,
            pseudonym: r.pseudonym,
            trust_level: r.trust_level,
            granted_level: r.granted_level,
            created_at: r.created_at,
            banned_at: r.banned_at,
        },
        device_key_id: r.device_key_id,
        created_at: r.opened_at,
        last_used_at: r.last_used_at,
        last_active_on: r.last_active_on,
    }))
}

/// Slides the session's expiry to `ttl_secs` from now and counts today as an
/// active day of its account.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn touch_session(pool: &PgPool, hash: &[u8; 32], ttl_secs: f64) -> Result<(), DbError> {
    let mut tx = pool.begin().await?;
    let account = sqlx::query_scalar!(
        r#"
        UPDATE sessions SET last_used_at = now(), expires_at = now() + make_interval(secs => $2)
        WHERE token_hash = $1 AND expires_at > now()
        RETURNING account_id
        "#,
        &hash[..],
        ttl_secs,
    )
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(account) = account {
        sqlx::query!(
            r#"
            UPDATE accounts
            SET active_days = active_days + 1,
                last_active_on = (now() AT TIME ZONE 'UTC')::date
            WHERE id = $1 AND last_active_on < (now() AT TIME ZONE 'UTC')::date
            "#,
            account,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Ends the session whose token hashes to `hash`.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn delete_session(pool: &PgPool, hash: &[u8; 32]) -> Result<bool, DbError> {
    let done = sqlx::query!("DELETE FROM sessions WHERE token_hash = $1", &hash[..])
        .execute(pool)
        .await?;
    Ok(done.rows_affected() > 0)
}

/// Drops the sessions past their expiry. Returns how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn purge_expired_sessions(pool: &PgPool) -> Result<u64, DbError> {
    let done = sqlx::query!("DELETE FROM sessions WHERE expires_at <= now()")
        .execute(pool)
        .await?;
    Ok(done.rows_affected())
}

/// The account `id`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn account(pool: &PgPool, id: Uuid) -> Result<Option<AccountRow>, DbError> {
    Ok(sqlx::query_as!(
        AccountRow,
        r#"
        SELECT id, pseudonym, trust_level, granted_level, created_at, banned_at
        FROM accounts WHERE id = $1
        "#,
        id,
    )
    .fetch_optional(pool)
    .await?)
}

/// Replaces the recovery code of `account` (one per account).
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn set_recovery_code(
    pool: &PgPool,
    account: Uuid,
    hash: &[u8; 32],
) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        INSERT INTO recovery_codes (account_id, code_hash) VALUES ($1, $2)
        ON CONFLICT (account_id) DO UPDATE SET code_hash = EXCLUDED.code_hash, created_at = now()
        "#,
        account,
        &hash[..],
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// The account whose recovery code hashes to `hash`, and whether it is
/// banned.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn account_by_recovery_code(
    pool: &PgPool,
    hash: &[u8; 32],
) -> Result<Option<(Uuid, bool)>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT a.id, a.banned_at IS NOT NULL AS "banned!"
        FROM recovery_codes r JOIN accounts a ON a.id = r.account_id
        WHERE r.code_hash = $1
        "#,
        &hash[..],
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| (r.id, r.banned)))
}

/// Sets the pseudonym of `account`.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn set_pseudonym(pool: &PgPool, account: Uuid, pseudonym: &str) -> Result<(), DbError> {
    sqlx::query!(
        "UPDATE accounts SET pseudonym = $2 WHERE id = $1",
        account,
        pseudonym
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// What the trust rules look at, read from the contributions.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct TrustInputs {
    /// Whole days since creation.
    pub age_days: i64,
    /// Distinct active days.
    pub active_days: i64,
    /// Places confirmed (each place once).
    pub confirmations: i64,
    /// Published contributions, counted once per place and kind (a script
    /// confirming the same place every day earns one).
    pub contributions: i64,
    /// Reviews and photos a moderator removed, counted on the account so
    /// that deleting them does not erase the record.
    pub removals: i64,
    /// Sponsored by a level-2 account.
    pub sponsored: bool,
    /// Nominated by a level-4 account.
    pub nominated: bool,
    /// Floor set by the administration.
    pub granted_level: i16,
}

/// Reads what the trust rules of `account` need, in one query.
///
/// # Errors
///
/// [`DbError`] when the query fails; `Ok(None)` when the account is gone.
pub async fn trust_inputs(pool: &PgPool, account: Uuid) -> Result<Option<TrustInputs>, DbError> {
    // `archived_confirmations` holds the places whose answers aged out
    // (`retention`): a place the account confirms again two years later
    // counts twice, a gain too slow to be worth a record of which places.
    let row = sqlx::query!(
        r#"
        SELECT
            extract(day FROM now() - a.created_at)::int8 AS "age_days!",
            a.active_days::int8 AS "active_days!",
            a.granted_level,
            (SELECT count(DISTINCT c.place_id) FROM confirmations c
             WHERE c.account_id = a.id) + a.archived_confirmations AS "confirmations!",
            (SELECT count(DISTINCT r.place_id) FROM reviews r
             WHERE r.account_id = a.id AND r.status = 'published' AND r.withdrawn_at IS NULL)
              + (SELECT count(DISTINCT p.place_id) FROM photos p
                 WHERE p.account_id = a.id AND p.status = 'published'
                   AND p.withdrawn_at IS NULL)
              + (SELECT count(DISTINCT c.place_id) FROM confirmations c WHERE c.account_id = a.id)
              + a.archived_confirmations
              + (SELECT count(DISTINCT s.place_id) FROM place_submissions s
                 WHERE s.account_id = a.id AND s.status = 'applied') AS "contributions!",
            a.moderation_removals::int8 AS "removals!",
            EXISTS (SELECT 1 FROM account_endorsements e
                    WHERE e.account_id = a.id AND e.kind = 'sponsor') AS "sponsored!",
            EXISTS (SELECT 1 FROM account_endorsements e
                    WHERE e.account_id = a.id AND e.kind = 'nominate') AS "nominated!"
        FROM accounts a WHERE a.id = $1
        "#,
        account,
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| TrustInputs {
        age_days: r.age_days,
        active_days: r.active_days,
        confirmations: r.confirmations,
        contributions: r.contributions,
        removals: r.removals,
        sponsored: r.sponsored,
        nominated: r.nominated,
        granted_level: r.granted_level,
    }))
}

/// Stores the level the rules computed. A new level queues what counts the
/// account's answers by level ([`queue_level_dependents`]).
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn set_trust_level(pool: &PgPool, account: Uuid, level: i16) -> Result<(), DbError> {
    let mut tx = pool.begin().await?;
    let done = sqlx::query!(
        "UPDATE accounts SET trust_level = $2 WHERE id = $1 AND trust_level <> $2",
        account,
        level
    )
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() > 0 {
        queue_level_dependents(&mut tx, account).await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Sets the floor the administration grants `account`, and its level to it
/// at once, upward or downward: a withdrawn grant takes effect now, and the
/// rules raise the level again at the next computation if the account earned
/// more. A new level queues what counts the account's answers by level
/// ([`queue_level_dependents`]). Returns whether the account exists.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn set_granted_level(pool: &PgPool, account: Uuid, level: i16) -> Result<bool, DbError> {
    let mut tx = pool.begin().await?;
    let was = sqlx::query_scalar!(
        r#"
        UPDATE accounts SET granted_level = $2, trust_level = $2
        WHERE id = $1
        RETURNING old.trust_level AS "was!"
        "#,
        account,
        level
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(was) = was else {
        return Ok(false);
    };
    if was != level {
        queue_level_dependents(&mut tx, account).await?;
    }
    tx.commit().await?;
    Ok(true)
}

/// Queues the places and the points whose summary counts `account`'s
/// answers only from a level up, and wakes the worker. The summaries leave
/// out the confirmations and issue reports of accounts below level 1
/// (`summary::refresh`), and the "still there?" answers too when a point is
/// hidden (`pois::refresh_community`): without a refresh, a level that
/// crosses that line would change what the cards should show while the
/// change feed never carries it. Every change of level queues them, not
/// only a crossing, so a threshold moved in those queries needs no change
/// here; a refresh that finds the summary unchanged does not move the place
/// in the feed. The rows go in in key order: two of these inserts at once
/// with places in common then wait on each other in one direction only,
/// never in a deadlock.
async fn queue_level_dependents(conn: &mut PgConnection, account: Uuid) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        INSERT INTO place_refresh_queue (place_id)
        SELECT place_id FROM (
            SELECT place_id FROM confirmations WHERE account_id = $1
            UNION SELECT place_id FROM issue_reports WHERE account_id = $1 AND status = 'published'
        ) counted
        ORDER BY place_id
        ON CONFLICT DO NOTHING
        "#,
        account,
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
        account,
    )
    .execute(&mut *conn)
    .await?;
    crate::community::notify_worker(conn).await
}

/// What one account says of another.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Endorsement {
    /// A level-2 account sponsors a new one.
    Sponsor,
    /// A level-4 account nominates a level-3 one.
    Nominate,
}

impl Endorsement {
    const fn code(self) -> &'static str {
        match self {
            Self::Sponsor => "sponsor",
            Self::Nominate => "nominate",
        }
    }
}

/// Records that `by` endorses `account`. Returns false when `account` does
/// not exist.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn endorse(
    pool: &PgPool,
    account: Uuid,
    kind: Endorsement,
    by: Uuid,
) -> Result<bool, DbError> {
    let done = sqlx::query!(
        r#"
        INSERT INTO account_endorsements (account_id, kind, by_account_id)
        SELECT id, $2, $3 FROM accounts WHERE id = $1
        ON CONFLICT DO NOTHING
        "#,
        account,
        kind.code(),
        by,
    )
    .execute(pool)
    .await?;
    if done.rows_affected() > 0 {
        return Ok(true);
    }
    account_exists(pool, account).await
}

async fn account_exists(pool: &PgPool, account: Uuid) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM accounts WHERE id = $1) AS "e!""#,
        account
    )
    .fetch_one(pool)
    .await?)
}

/// Creates an account without any device key, at the level the
/// administration grants (the store reviewers' demo account), with its
/// recovery code. A reviewer signs in with the code from any device.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn create_granted(
    pool: &PgPool,
    pseudonym: &str,
    level: i16,
    recovery_hash: &[u8; 32],
) -> Result<AccountRow, DbError> {
    let mut tx = pool.begin().await?;
    let account = sqlx::query_as!(
        AccountRow,
        r#"
        INSERT INTO accounts (id, pseudonym, trust_level, granted_level) VALUES ($1, $2, $3, $3)
        RETURNING id, pseudonym, trust_level, granted_level, created_at, banned_at
        "#,
        Uuid::now_v7(),
        pseudonym,
        level,
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO recovery_codes (account_id, code_hash) VALUES ($1, $2)",
        account.id,
        &recovery_hash[..],
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(account)
}

/// What deleting an account left to do outside the database.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DeletedAccount {
    /// Media files no row refers to any more, relative to the media root.
    pub orphan_files: Vec<String>,
    /// Published reviews kept without their author.
    pub anonymised_reviews: u64,
    /// Photos deleted.
    pub deleted_photos: u64,
}

/// Deletes `account`: its keys, sessions, recovery code, lists, mutes,
/// endorsements, content and issue reports go; its photos go (the caller
/// removes the files listed); its published reviews, confirmations and
/// place submissions other than pending proposals stay without author
/// (their notes dropped); ratings without text, reviews that were never
/// published and pending proposals go. The places whose community summary
/// changes are queued for the worker. `Ok(None)` when the account does not
/// exist.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is deleted then.
pub async fn delete_account(
    pool: &PgPool,
    account: Uuid,
) -> Result<Option<DeletedAccount>, DbError> {
    let mut tx = pool.begin().await?;
    let found = sqlx::query_scalar!(
        "SELECT banned_at FROM accounts WHERE id = $1 FOR UPDATE",
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(banned_at) = found else {
        return Ok(None);
    };
    // A banned account may erase itself, but its keys must not open a new
    // account at once: their hashes stay, without the account, its reason
    // or anything it wrote (`retention::BANNED_KEY_DAYS`).
    if let Some(banned_at) = banned_at {
        sqlx::query!(
            r#"
            INSERT INTO banned_keys (key_hash, banned_at)
            SELECT sha256(public_key), $2 FROM device_keys WHERE account_id = $1
            ON CONFLICT (key_hash) DO NOTHING
            "#,
            account,
            banned_at,
        )
        .execute(&mut *tx)
        .await?;
    }
    // Every place whose summary may change, before the rows go.
    sqlx::query!(
        r#"
        INSERT INTO place_refresh_queue (place_id)
        SELECT place_id FROM reviews WHERE account_id = $1
        UNION SELECT place_id FROM photos WHERE account_id = $1
        UNION SELECT place_id FROM confirmations WHERE account_id = $1
        UNION SELECT place_id FROM issue_reports WHERE account_id = $1
        ON CONFLICT DO NOTHING
        "#,
        account,
    )
    .execute(&mut *tx)
    .await?;
    // The "still there?" answers go with the account (ON DELETE CASCADE):
    // the points they spoke of are counted again.
    sqlx::query!(
        r#"
        INSERT INTO poi_refresh_queue (poi_id)
        SELECT DISTINCT poi_id FROM poi_confirmations WHERE account_id = $1
        ON CONFLICT DO NOTHING
        "#,
        account,
    )
    .execute(&mut *tx)
    .await?;
    let photos = sqlx::query!(
        "DELETE FROM photos WHERE account_id = $1 RETURNING id, path, thumb_path",
        account
    )
    .fetch_all(&mut *tx)
    .await?;
    let photo_ids: Vec<Uuid> = photos.iter().map(|p| p.id).collect();
    let mut files: Vec<String> = photos
        .into_iter()
        .flat_map(|p| [p.path, p.thumb_path])
        .collect();
    files.sort();
    files.dedup();
    let orphan_files = crate::community::unserved(&mut tx, &files).await?;
    let anonymised = sqlx::query!(
        r#"
        UPDATE reviews SET account_id = NULL
        WHERE account_id = $1 AND status = 'published' AND body IS NOT NULL
        "#,
        account,
    )
    .execute(&mut *tx)
    .await?;
    let dropped_reviews = sqlx::query_scalar!(
        "DELETE FROM reviews WHERE account_id = $1 RETURNING id",
        account
    )
    .fetch_all(&mut *tx)
    .await?;
    if banned_at.is_some() {
        // A ban took its answers out of every summary; kept without author
        // they would count again, so they go. The points it added stay
        // hidden, which its ban did until now.
        sqlx::query!("DELETE FROM confirmations WHERE account_id = $1", account)
            .execute(&mut *tx)
            .await?;
        sqlx::query!(
            r#"
            INSERT INTO poi_moderation (poi_id, note)
            SELECT DISTINCT poi_id, 'added by a banned account, deleted since'
            FROM place_submissions WHERE account_id = $1 AND poi_id IS NOT NULL
            ON CONFLICT DO NOTHING
            "#,
            account
        )
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query!(
            "UPDATE confirmations SET account_id = NULL, note = NULL WHERE account_id = $1",
            account
        )
        .execute(&mut *tx)
        .await?;
    }
    // Issue reports go with the account: kept without author they could no
    // longer be counted once per account, and an account deleted after
    // fifty reports would leave fifty on the card.
    sqlx::query!("DELETE FROM issue_reports WHERE account_id = $1", account)
        .execute(&mut *tx)
        .await?;
    let dropped_submissions = sqlx::query_scalar!(
        "DELETE FROM place_submissions WHERE account_id = $1 AND status = 'proposed' RETURNING id",
        account
    )
    .fetch_all(&mut *tx)
    .await?;
    // What never became part of the places database goes with its author:
    // an accepted one is withdrawn before the worker applies it, and no
    // refused or withdrawn one keeps its content (a new place's position
    // above all). An applied one is ODbL data now and stays, unsigned.
    sqlx::query!(
        r#"
        UPDATE place_submissions SET
            status = CASE WHEN status = 'accepted' THEN 'withdrawn' ELSE status END,
            decided_at = CASE WHEN status = 'accepted' THEN now() ELSE decided_at END,
            payload = CASE WHEN status = 'applied' THEN payload ELSE '{}'::jsonb END,
            account_id = NULL, device_key_id = NULL
        WHERE account_id = $1
        "#,
        account
    )
    .execute(&mut *tx)
    .await?;
    // What pointed at the content that is gone: reports and queue entries.
    let gone: Vec<Uuid> = photo_ids
        .iter()
        .chain(&dropped_reviews)
        .chain(&dropped_submissions)
        .copied()
        .collect();
    sqlx::query!(
        "DELETE FROM content_reports WHERE target_id = ANY($1)",
        &gone
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "DELETE FROM moderation_queue WHERE target_id = ANY($1)",
        &gone
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!("DELETE FROM accounts WHERE id = $1", account)
        .execute(&mut *tx)
        .await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(Some(DeletedAccount {
        orphan_files,
        anonymised_reviews: anonymised.rows_affected(),
        deleted_photos: u64::try_from(photo_ids.len()).unwrap_or(u64::MAX),
    }))
}

/// Bans `account`: its sessions end, it cannot sign in again, the texts of
/// its reviews are deleted (each stays a rating without text), its photos
/// are removed (the files of those photos are returned for removal), its
/// issue reports are dismissed, and its ratings and confirmations stop
/// counting (the summary leaves banned accounts out). `None` when the
/// account does not exist.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn ban(
    pool: &PgPool,
    account: Uuid,
    reason: &str,
) -> Result<Option<Vec<String>>, DbError> {
    let mut tx = pool.begin().await?;
    let done = sqlx::query!(
        "UPDATE accounts SET banned_at = now(), ban_reason = $2 WHERE id = $1",
        account,
        reason
    )
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() == 0 {
        return Ok(None);
    }
    sqlx::query!("DELETE FROM sessions WHERE account_id = $1", account)
        .execute(&mut *tx)
        .await?;
    // The texts go, the ratings stay as ratings without text: the summary
    // leaves a banned account's ratings out, and a text kept "removed"
    // would still be stored.
    sqlx::query!(
        r#"
        UPDATE reviews SET body = NULL, lang = NULL, updated_at = now()
        WHERE account_id = $1 AND body IS NOT NULL
        "#,
        account
    )
    .execute(&mut *tx)
    .await?;
    let photos = sqlx::query!(
        r#"
        UPDATE photos SET status = 'removed' WHERE account_id = $1 AND status <> 'removed'
        RETURNING path, thumb_path
        "#,
        account
    )
    .fetch_all(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE issue_reports SET status = 'dismissed' WHERE account_id = $1",
        account
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO place_refresh_queue (place_id)
        SELECT place_id FROM reviews WHERE account_id = $1
        UNION SELECT place_id FROM photos WHERE account_id = $1
        UNION SELECT place_id FROM confirmations WHERE account_id = $1
        UNION SELECT place_id FROM issue_reports WHERE account_id = $1
        ON CONFLICT DO NOTHING
        "#,
        account,
    )
    .execute(&mut *tx)
    .await?;
    // A banned account's "gone" no longer hides a point, and the points
    // it added are hidden.
    sqlx::query!(
        r#"
        INSERT INTO poi_refresh_queue (poi_id)
        SELECT poi_id FROM poi_confirmations WHERE account_id = $1
        UNION SELECT poi_id FROM place_submissions WHERE account_id = $1 AND poi_id IS NOT NULL
        ON CONFLICT DO NOTHING
        "#,
        account,
    )
    .execute(&mut *tx)
    .await?;
    let files: Vec<String> = photos
        .into_iter()
        .flat_map(|p| [p.path, p.thumb_path])
        .collect();
    let unserved = crate::community::unserved(&mut tx, &files).await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(Some(unserved))
}

/// A device key of an account, as its owner sees it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceRow {
    /// The key's id.
    pub id: Uuid,
    /// When it was attached.
    pub created_at: DateTime<Utc>,
    /// Its last sign-in.
    pub last_used_at: DateTime<Utc>,
}

/// The device keys of `account`, most recently used first.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn devices(pool: &PgPool, account: Uuid) -> Result<Vec<DeviceRow>, DbError> {
    Ok(sqlx::query_as!(
        DeviceRow,
        r#"
        SELECT id, created_at, last_used_at FROM device_keys
        WHERE account_id = $1 ORDER BY last_used_at DESC, id
        "#,
        account
    )
    .fetch_all(pool)
    .await?)
}

/// Detaches device keys of `account` and ends their sessions: the key `id`,
/// or every key but `keep` when `id` is `None`. Returns how many went.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn revoke_devices(
    pool: &PgPool,
    account: Uuid,
    id: Option<Uuid>,
    keep: Uuid,
) -> Result<u64, DbError> {
    let done = sqlx::query!(
        r#"
        DELETE FROM device_keys
        WHERE account_id = $1 AND id <> $3 AND ($2::uuid IS NULL OR id = $2)
        "#,
        account,
        id,
        keep,
    )
    .execute(pool)
    .await?;
    Ok(done.rows_affected())
}

/// Ends every session of `account` but the one whose token hashes to
/// `keep`. Returns how many ended.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn end_other_sessions(
    pool: &PgPool,
    account: Uuid,
    keep: &[u8; 32],
) -> Result<u64, DbError> {
    let done = sqlx::query!(
        "DELETE FROM sessions WHERE account_id = $1 AND token_hash <> $2",
        account,
        &keep[..]
    )
    .execute(pool)
    .await?;
    Ok(done.rows_affected())
}

/// An account as an operator sees it before deleting it: who, and what it
/// holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountSummary {
    /// The account.
    pub account: AccountRow,
    /// Its device keys.
    pub devices: i64,
    /// Its ratings and reviews.
    pub reviews: i64,
    /// Its photos.
    pub photos: i64,
    /// Its "still there?" answers.
    pub confirmations: i64,
    /// Its issue reports.
    pub issues: i64,
    /// Its new places and edits.
    pub submissions: i64,
    /// Its road reports.
    pub road_reports: i64,
}

/// What [`summary`] and [`find_by_pseudonym`] read: one account with its
/// counts.
async fn summaries(pool: &PgPool, filter: Summarized<'_>) -> Result<Vec<AccountSummary>, DbError> {
    let (id, pseudonym) = match filter {
        Summarized::Id(id) => (Some(id), None),
        Summarized::Pseudonym(p) => (None, Some(p)),
    };
    let rows = sqlx::query!(
        r#"
        SELECT a.id, a.pseudonym, a.trust_level, a.granted_level, a.created_at, a.banned_at,
            (SELECT count(*) FROM device_keys WHERE account_id = a.id) AS "devices!",
            (SELECT count(*) FROM reviews WHERE account_id = a.id) AS "reviews!",
            (SELECT count(*) FROM photos WHERE account_id = a.id) AS "photos!",
            (SELECT count(*) FROM confirmations WHERE account_id = a.id) AS "confirmations!",
            (SELECT count(*) FROM issue_reports WHERE account_id = a.id) AS "issues!",
            (SELECT count(*) FROM place_submissions WHERE account_id = a.id) AS "submissions!",
            (SELECT count(*) FROM road_event_reports WHERE account_id = a.id) AS "road_reports!"
        FROM accounts a
        WHERE ($1::uuid IS NULL OR a.id = $1)
          AND ($2::text IS NULL OR lower(a.pseudonym) = lower($2))
        ORDER BY a.created_at
        LIMIT 20
        "#,
        id,
        pseudonym,
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| AccountSummary {
            account: AccountRow {
                id: r.id,
                pseudonym: r.pseudonym,
                trust_level: r.trust_level,
                granted_level: r.granted_level,
                created_at: r.created_at,
                banned_at: r.banned_at,
            },
            devices: r.devices,
            reviews: r.reviews,
            photos: r.photos,
            confirmations: r.confirmations,
            issues: r.issues,
            submissions: r.submissions,
            road_reports: r.road_reports,
        })
        .collect())
}

enum Summarized<'a> {
    Id(Uuid),
    Pseudonym(&'a str),
}

/// Account `id` with what it holds.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn summary(pool: &PgPool, id: Uuid) -> Result<Option<AccountSummary>, DbError> {
    Ok(summaries(pool, Summarized::Id(id))
        .await?
        .into_iter()
        .next())
}

/// The accounts named `pseudonym` (case aside; pseudonyms are not unique),
/// oldest first, 20 at most.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn find_by_pseudonym(
    pool: &PgPool,
    pseudonym: &str,
) -> Result<Vec<AccountSummary>, DbError> {
    summaries(pool, Summarized::Pseudonym(pseudonym.trim())).await
}
