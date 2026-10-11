//! The account's home: one saved point per account, synced like the points
//! of the favourite lists and as private. Every statement is scoped to the
//! owner, and nothing here writes the home's name, address or coordinates
//! to a log.

use chrono::{DateTime, Utc};
use lunaway_domain::favorites::SavedPoint;
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    lists::{StoredPoint, saved_point},
};

/// The home of an account.
#[derive(Debug, Clone, PartialEq)]
pub struct HomeRow {
    /// What it is, its texts, its position and its point of interest.
    pub point: SavedPoint<Uuid>,
    /// Last change.
    pub updated_at: DateTime<Utc>,
}

/// The home of `account`, if it has one.
///
/// # Errors
///
/// [`DbError`] when the query fails or the stored point does not decode.
pub async fn home(pool: &PgPool, account: Uuid) -> Result<Option<HomeRow>, DbError> {
    let mut conn = pool.acquire().await?;
    read(&mut conn, account).await
}

async fn read(conn: &mut PgConnection, account: Uuid) -> Result<Option<HomeRow>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT kind, name, address, lat, lon, poi_id, poi_kind, updated_at
        FROM favorite_homes WHERE account_id = $1
        "#,
        account
    )
    .fetch_optional(conn)
    .await?;
    row.map(|r| {
        Ok(HomeRow {
            point: saved_point(StoredPoint {
                kind: r.kind,
                name: r.name,
                note: None,
                address: r.address,
                lat: r.lat,
                lon: r.lon,
                poi_id: r.poi_id,
                poi_kind: r.poi_kind,
            })?,
            updated_at: r.updated_at,
        })
    })
    .transpose()
}

/// Sets the home of `account` to `point` (a note is not kept), in place of
/// any other. The date moves only when something changed. Returns the home
/// as stored.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn set_home(
    pool: &PgPool,
    account: Uuid,
    point: &SavedPoint<Uuid>,
) -> Result<HomeRow, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!(
        r#"
        INSERT INTO favorite_homes AS h
            (account_id, kind, name, address, lat, lon, poi_id, poi_kind)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (account_id) DO UPDATE SET
            kind = EXCLUDED.kind, name = EXCLUDED.name, address = EXCLUDED.address,
            lat = EXCLUDED.lat, lon = EXCLUDED.lon, poi_id = EXCLUDED.poi_id,
            poi_kind = EXCLUDED.poi_kind, updated_at = now()
        WHERE (h.kind, h.name, h.address, h.lat, h.lon, h.poi_id, h.poi_kind)
            IS DISTINCT FROM (EXCLUDED.kind, EXCLUDED.name, EXCLUDED.address, EXCLUDED.lat,
                              EXCLUDED.lon, EXCLUDED.poi_id, EXCLUDED.poi_kind)
        "#,
        account,
        point.kind.code(),
        point.name,
        point.address.as_deref(),
        point.position.lat(),
        point.position.lon(),
        point.poi.map(|poi| poi.id),
        point.poi.map(|poi| poi.kind.code()),
    )
    .execute(&mut *tx)
    .await?;
    let stored = read(&mut tx, account)
        .await?
        .ok_or(DbError::Query(sqlx::Error::RowNotFound))?;
    tx.commit().await?;
    Ok(stored)
}

/// Removes the home of `account`. Returns whether there was one.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn clear_home(pool: &PgPool, account: Uuid) -> Result<bool, DbError> {
    let done = sqlx::query!("DELETE FROM favorite_homes WHERE account_id = $1", account)
        .execute(pool)
        .await?;
    Ok(done.rows_affected() > 0)
}
