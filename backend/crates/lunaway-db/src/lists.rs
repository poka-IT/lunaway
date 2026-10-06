//! Favourite lists, synced with the account. Every statement is scoped to
//! the owner: a list id of another account behaves as a list that does not
//! exist.

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// Most lists one account keeps.
pub const MAX_LISTS: i64 = 100;
/// Most places one list holds.
pub const MAX_ITEMS: i64 = 5_000;

/// A list with its places.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListRow {
    /// Its id.
    pub id: Uuid,
    /// Its name.
    pub name: String,
    /// When it was created.
    pub created_at: DateTime<Utc>,
    /// Last change of its name or its places.
    pub updated_at: DateTime<Utc>,
    /// Its places, oldest first, with when each was added.
    pub items: Vec<(Uuid, DateTime<Utc>)>,
}

/// Why a list change was refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ListRefusal {
    /// No such list for this account.
    NotFound,
    /// Another list of the account has this name.
    NameTaken,
    /// The account holds [`MAX_LISTS`] lists, or the list [`MAX_ITEMS`]
    /// places.
    Full,
}

/// Every list of `account`, by name, with its places.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn lists(pool: &PgPool, account: Uuid) -> Result<Vec<ListRow>, DbError> {
    let heads = sqlx::query!(
        "SELECT id, name, created_at, updated_at FROM favorite_lists WHERE account_id = $1 ORDER BY name, id",
        account
    )
    .fetch_all(pool)
    .await?;
    let ids: Vec<Uuid> = heads.iter().map(|h| h.id).collect();
    let items = sqlx::query!(
        r#"
        SELECT list_id, place_id, added_at FROM favorite_items
        WHERE list_id = ANY($1) ORDER BY list_id, added_at, place_id
        "#,
        &ids
    )
    .fetch_all(pool)
    .await?;
    let mut by_list: std::collections::HashMap<Uuid, Vec<(Uuid, DateTime<Utc>)>> =
        std::collections::HashMap::with_capacity(heads.len());
    for i in items {
        by_list
            .entry(i.list_id)
            .or_default()
            .push((i.place_id, i.added_at));
    }
    Ok(heads
        .into_iter()
        .map(|h| ListRow {
            items: by_list.remove(&h.id).unwrap_or_default(),
            id: h.id,
            name: h.name,
            created_at: h.created_at,
            updated_at: h.updated_at,
        })
        .collect())
}

/// One list of `account`, with its places.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn list(pool: &PgPool, account: Uuid, id: Uuid) -> Result<Option<ListRow>, DbError> {
    let head = sqlx::query!(
        "SELECT id, name, created_at, updated_at FROM favorite_lists WHERE id = $1 AND account_id = $2",
        id,
        account
    )
    .fetch_optional(pool)
    .await?;
    let Some(h) = head else {
        return Ok(None);
    };
    let items = sqlx::query!(
        "SELECT place_id, added_at FROM favorite_items WHERE list_id = $1 ORDER BY added_at, place_id",
        id
    )
    .fetch_all(pool)
    .await?;
    Ok(Some(ListRow {
        id: h.id,
        name: h.name,
        created_at: h.created_at,
        updated_at: h.updated_at,
        items: items
            .into_iter()
            .map(|i| (i.place_id, i.added_at))
            .collect(),
    }))
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    e.as_database_error()
        .and_then(sqlx::error::DatabaseError::code)
        .as_deref()
        == Some("23505")
}

/// Creates a list.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn create(
    pool: &PgPool,
    account: Uuid,
    name: &str,
) -> Result<Result<Uuid, ListRefusal>, DbError> {
    let mut tx = pool.begin().await?;
    // Serialise the creations of one account so the count holds.
    sqlx::query!("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", account)
        .fetch_optional(&mut *tx)
        .await?;
    let count = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM favorite_lists WHERE account_id = $1"#,
        account
    )
    .fetch_one(&mut *tx)
    .await?;
    if count >= MAX_LISTS {
        return Ok(Err(ListRefusal::Full));
    }
    let id = Uuid::now_v7();
    let done = sqlx::query!(
        "INSERT INTO favorite_lists (id, account_id, name) VALUES ($1, $2, $3)",
        id,
        account,
        name
    )
    .execute(&mut *tx)
    .await;
    match done {
        Ok(_) => {}
        Err(e) if is_unique_violation(&e) => return Ok(Err(ListRefusal::NameTaken)),
        Err(e) => return Err(e.into()),
    }
    tx.commit().await?;
    Ok(Ok(id))
}

/// Renames a list.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn rename(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
    name: &str,
) -> Result<Result<(), ListRefusal>, DbError> {
    let done = sqlx::query!(
        "UPDATE favorite_lists SET name = $3, updated_at = now() WHERE id = $1 AND account_id = $2",
        id,
        account,
        name
    )
    .execute(pool)
    .await;
    match done {
        Ok(d) if d.rows_affected() == 0 => Ok(Err(ListRefusal::NotFound)),
        Ok(_) => Ok(Ok(())),
        Err(e) if is_unique_violation(&e) => Ok(Err(ListRefusal::NameTaken)),
        Err(e) => Err(e.into()),
    }
}

/// Deletes a list and its places. Returns false when there was no such list.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn delete(pool: &PgPool, account: Uuid, id: Uuid) -> Result<bool, DbError> {
    let done = sqlx::query!(
        "DELETE FROM favorite_lists WHERE id = $1 AND account_id = $2",
        id,
        account
    )
    .execute(pool)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// Adds places to a list (already present ones are kept as they are).
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn add(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
    places: &[Uuid],
) -> Result<Result<(), ListRefusal>, DbError> {
    let mut tx = pool.begin().await?;
    let owned = sqlx::query_scalar!(
        "SELECT id FROM favorite_lists WHERE id = $1 AND account_id = $2 FOR UPDATE",
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    if owned.is_none() {
        return Ok(Err(ListRefusal::NotFound));
    }
    let added = sqlx::query!(
        r#"
        INSERT INTO favorite_items (list_id, place_id)
        SELECT $1, p.id FROM places p WHERE p.id = ANY($2)
        ON CONFLICT DO NOTHING
        "#,
        id,
        places,
    )
    .execute(&mut *tx)
    .await?;
    let count = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM favorite_items WHERE list_id = $1"#,
        id
    )
    .fetch_one(&mut *tx)
    .await?;
    if count > MAX_ITEMS {
        return Ok(Err(ListRefusal::Full));
    }
    if added.rows_affected() > 0 {
        sqlx::query!(
            "UPDATE favorite_lists SET updated_at = now() WHERE id = $1",
            id
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(Ok(()))
}

/// Removes a place from a list.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn remove(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
    place: Uuid,
) -> Result<Result<(), ListRefusal>, DbError> {
    let mut tx = pool.begin().await?;
    let owned = sqlx::query_scalar!(
        "SELECT id FROM favorite_lists WHERE id = $1 AND account_id = $2 FOR UPDATE",
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    if owned.is_none() {
        return Ok(Err(ListRefusal::NotFound));
    }
    let done = sqlx::query!(
        "DELETE FROM favorite_items WHERE list_id = $1 AND place_id = $2",
        id,
        place
    )
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() > 0 {
        sqlx::query!(
            "UPDATE favorite_lists SET updated_at = now() WHERE id = $1",
            id
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(Ok(()))
}

/// Imports lists kept on a device before the account existed: each goes
/// into the account's list of the same name (created when missing), its
/// places added. A place merged since the device synced counts as the place
/// that absorbed it; unknown and deleted places are skipped.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is imported then.
pub async fn import(
    pool: &PgPool,
    account: Uuid,
    imported: &[(String, Vec<Uuid>)],
) -> Result<Result<(), ListRefusal>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", account)
        .fetch_optional(&mut *tx)
        .await?;
    for (name, places) in imported {
        let id = sqlx::query_scalar!(
            r#"
            INSERT INTO favorite_lists (id, account_id, name) VALUES ($1, $2, $3)
            ON CONFLICT (account_id, name) DO UPDATE SET updated_at = now()
            RETURNING id
            "#,
            Uuid::now_v7(),
            account,
            name,
        )
        .fetch_one(&mut *tx)
        .await?;
        sqlx::query!(
            r#"
            INSERT INTO favorite_items (list_id, place_id)
            SELECT DISTINCT $1::uuid, live.id
            FROM places p
            JOIN places live ON live.id = CASE WHEN p.deleted_at IS NULL THEN p.id
                                               ELSE p.merged_into END
            WHERE p.id = ANY($2) AND live.deleted_at IS NULL
            ON CONFLICT DO NOTHING
            "#,
            id,
            places,
        )
        .execute(&mut *tx)
        .await?;
    }
    let lists = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM favorite_lists WHERE account_id = $1"#,
        account
    )
    .fetch_one(&mut *tx)
    .await?;
    let largest = sqlx::query_scalar!(
        r#"
        SELECT coalesce(max(n), 0) AS "n!" FROM (
            SELECT count(*) AS n FROM favorite_items i JOIN favorite_lists l ON l.id = i.list_id
            WHERE l.account_id = $1 GROUP BY i.list_id
        ) c
        "#,
        account
    )
    .fetch_one(&mut *tx)
    .await?;
    if lists > MAX_LISTS || largest > MAX_ITEMS {
        return Ok(Err(ListRefusal::Full));
    }
    tx.commit().await?;
    Ok(Ok(()))
}
