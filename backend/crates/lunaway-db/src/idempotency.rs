//! Idempotency keys of the contributions a device may send twice.
//!
//! The app keeps a contribution in its outbox until the server accepts it;
//! an answer lost on a weak network makes it send the same contribution
//! again. With a key (the outbox entry's id), the write stores the key with
//! what it made, in its own transaction, and a request that comes again
//! with the same key gets what the first one made instead of a second copy.
//! A key belongs to an account; the same key with other arguments is a
//! client error ([`Seen::Reused`]). A key goes with what it made: a
//! trigger drops it when that row is deleted, and a withdrawal drops it
//! (`submissions::withdraw`), so no key outlives the contribution it names.

use chrono::{DateTime, Utc};
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{DbError, PgPool};

/// The writes a key may guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Operation {
    /// `addPlace`.
    AddPlace,
    /// `editPlace`.
    EditPlace,
    /// `confirm`.
    Confirm,
    /// `reportIssue`.
    ReportIssue,
    /// `reportRoadEvent`.
    ReportRoadEvent,
}

impl Operation {
    /// The code stored (the migration's CHECK list).
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::AddPlace => "add_place",
            Self::EditPlace => "edit_place",
            Self::Confirm => "confirm",
            Self::ReportIssue => "report_issue",
            Self::ReportRoadEvent => "report_road_event",
        }
    }
}

/// Whether `key` is one the table accepts: 8 to 128 characters of
/// `A-Z a-z 0-9 . _ : -` (a UUID is).
#[must_use]
pub fn is_valid_key(key: &str) -> bool {
    (8..=128).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b':' | b'-'))
}

/// A request's key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Key<'a> {
    /// The account sending it.
    pub account: Uuid,
    /// The key the client chose ([`is_valid_key`]).
    pub key: &'a str,
    /// The write it guards.
    pub operation: Operation,
    /// SHA-256 of the request's arguments.
    pub request: [u8; 32],
}

impl<'a> Key<'a> {
    /// The key `key` of `account` for `operation`, with the request's
    /// arguments as JSON (their SHA-256 is kept, not the arguments).
    #[must_use]
    pub fn of(
        account: Uuid,
        key: &'a str,
        operation: Operation,
        arguments: &serde_json::Value,
    ) -> Self {
        use sha2::{Digest as _, Sha256};
        Self {
            account,
            key,
            operation,
            request: Sha256::digest(arguments.to_string().as_bytes()).into(),
        }
    }
}

/// What a key says of a request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Seen {
    /// Never used: do the write.
    New,
    /// The same request came before and made this row.
    Replay(Uuid),
    /// The key was used for another request.
    Reused,
}

/// What a write guarded by a key did.
#[derive(Debug, Clone, PartialEq)]
pub enum Once<T> {
    /// Done now.
    Done(T),
    /// Done before by the same request: this row.
    Replay(Uuid),
    /// The key was used for another request: nothing done.
    Reused,
}

/// Looks `key` up on `conn`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn seen(conn: &mut PgConnection, key: &Key<'_>) -> Result<Seen, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT operation, request_hash, result_id FROM idempotency_keys
        WHERE account_id = $1 AND key = $2
        "#,
        key.account,
        key.key,
    )
    .fetch_optional(conn)
    .await?;
    Ok(match row {
        None => Seen::New,
        Some(r) if r.operation == key.operation.code() && r.request_hash == key.request => {
            Seen::Replay(r.result_id)
        }
        Some(_) => Seen::Reused,
    })
}

/// Looks `key` up, outside any write: a replay is answered without taking
/// a quota.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn lookup(pool: &PgPool, key: &Key<'_>) -> Result<Seen, DbError> {
    let mut conn = pool.acquire().await?;
    seen(&mut conn, key).await
}

/// Stores `key` with the row its write made, in the write's transaction.
/// `false` when another request with the same key committed first (the
/// insert waited for it): the caller rolls back and answers with that one
/// ([`after_lost_race`]).
pub(crate) async fn store(
    conn: &mut PgConnection,
    key: &Key<'_>,
    result: Uuid,
) -> Result<bool, DbError> {
    let stored = sqlx::query_scalar!(
        r#"
        INSERT INTO idempotency_keys (account_id, key, operation, request_hash, result_id)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT DO NOTHING
        RETURNING true AS "stored!"
        "#,
        key.account,
        key.key,
        key.operation.code(),
        &key.request[..],
        result,
    )
    .fetch_optional(conn)
    .await?;
    Ok(stored.is_some())
}

/// What a request that lost the race to its twin answers.
async fn settled(pool: &PgPool, key: &Key<'_>) -> Result<Once<Uuid>, DbError> {
    match lookup(pool, key).await? {
        Seen::Replay(id) => Ok(Once::Replay(id)),
        Seen::Reused => Ok(Once::Reused),
        Seen::New => Err(DbError::decode(
            "idempotency key",
            std::io::Error::other("a key that blocked an insert is gone"),
        )),
    }
}

/// What a key seen before answers instead of a write.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Answered {
    /// The same request made this row.
    Replay(Uuid),
    /// The key was used for another request.
    Reused,
}

impl Answered {
    /// The answer, for a write whose row type is `T`.
    pub(crate) const fn once<T>(self) -> Once<T> {
        match self {
            Self::Replay(id) => Once::Replay(id),
            Self::Reused => Once::Reused,
        }
    }
}

/// Begins the transaction of a write guarded by `key`: `Err` with the
/// answer when the key was seen, the open transaction otherwise.
///
/// # Errors
///
/// [`DbError`] when the database fails.
pub(crate) async fn begin(
    pool: &PgPool,
    key: &Key<'_>,
) -> Result<Result<sqlx::Transaction<'static, sqlx::Postgres>, Answered>, DbError> {
    let mut tx = pool.begin().await?;
    Ok(match seen(&mut tx, key).await? {
        Seen::New => Ok(tx),
        Seen::Replay(id) => Err(Answered::Replay(id)),
        Seen::Reused => Err(Answered::Reused),
    })
}

/// Ends the transaction of a write guarded by `key` that made `result`:
/// commits with the key stored, or, when a twin request committed first,
/// rolls back and answers with what the twin made.
///
/// # Errors
///
/// [`DbError`] when the database fails.
pub(crate) async fn finish<T>(
    pool: &PgPool,
    mut tx: sqlx::Transaction<'_, sqlx::Postgres>,
    key: &Key<'_>,
    result: Uuid,
    done: T,
) -> Result<Once<T>, DbError> {
    if store(&mut tx, key, result).await? {
        tx.commit().await?;
        return Ok(Once::Done(done));
    }
    tx.rollback().await?;
    Ok(match settled(pool, key).await? {
        Once::Replay(id) => Once::Replay(id),
        _ => Once::Reused,
    })
}

/// The answer of a write whose key a twin request stored first.
///
/// # Errors
///
/// [`DbError`] when the database fails.
pub(crate) async fn after_lost_race<T>(pool: &PgPool, key: &Key<'_>) -> Result<Once<T>, DbError> {
    Ok(match settled(pool, key).await? {
        Once::Replay(id) => Once::Replay(id),
        _ => Once::Reused,
    })
}

/// Drops the keys stored before `before`, and those of road reports
/// stored before `road_reports_before` (a report is erased after 14 days,
/// its key with it); returns how many.
///
/// # Errors
///
/// [`DbError`] when the delete fails.
pub async fn purge(
    pool: &PgPool,
    before: DateTime<Utc>,
    road_reports_before: DateTime<Utc>,
) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        DELETE FROM idempotency_keys
        WHERE created_at < $1 OR (operation = 'report_road_event' AND created_at < $2)
        "#,
        before,
        road_reports_before,
    )
    .execute(pool)
    .await?
    .rows_affected())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_uuid_is_a_key_and_odd_text_is_not() {
        assert!(is_valid_key("01a11084-bd6e-7207-a61e-51d1c09f66dd"));
        assert!(is_valid_key("outbox:42.retry_1"));
        for bad in [
            "short",
            "with space here",
            "accentué-12345",
            &"x".repeat(129),
        ] {
            assert!(!is_valid_key(bad), "{bad:?}");
        }
    }
}
