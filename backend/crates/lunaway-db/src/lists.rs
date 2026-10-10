//! Favourite lists, synced with the account. Every statement is scoped to
//! the owner: a list id of another account behaves as a list that does not
//! exist.
//!
//! A list holds places of the data and points saved outside them (an
//! address, a town, a bare point of the map, a shop): those are the
//! account's own and private, and nothing here writes their names, notes
//! or coordinates to a log.

use chrono::{DateTime, Utc};
use lunaway_domain::{
    Position,
    favorites::{FavoritePointKind, SavedPoi, SavedPoint},
    poi::PoiKind,
};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// Most lists one account keeps.
pub const MAX_LISTS: i64 = 100;
/// Most places one list holds.
pub const MAX_ITEMS: i64 = 5_000;
/// Most saved points one account keeps, all its lists together: each
/// carries texts of its own, so the bound is on the account rather than on
/// each of its lists.
pub const MAX_POINTS: i64 = 2_000;

/// A list with its places and its saved points.
#[derive(Debug, Clone, PartialEq)]
pub struct ListRow {
    /// Its id.
    pub id: Uuid,
    /// Its name.
    pub name: String,
    /// When it was created.
    pub created_at: DateTime<Utc>,
    /// Last change of its name, its places or its points.
    pub updated_at: DateTime<Utc>,
    /// Its places, oldest first, with when each was added.
    pub items: Vec<(Uuid, DateTime<Utc>)>,
    /// Its saved points, oldest first.
    pub points: Vec<PointRow>,
}

/// A point saved in a list.
#[derive(Debug, Clone, PartialEq)]
pub struct PointRow {
    /// Its id, chosen by the device that saved it; unique within its list.
    pub id: Uuid,
    /// What it is, its texts, its position and its point of interest.
    pub point: SavedPoint<Uuid>,
    /// When it was added to the list.
    pub added_at: DateTime<Utc>,
    /// Last change of what it holds.
    pub updated_at: DateTime<Utc>,
}

/// A point to save, with the id its device chose.
#[derive(Debug, Clone, PartialEq)]
pub struct NewPoint {
    /// Its id, unique within a list: saving it again updates it.
    pub id: Uuid,
    /// What it holds, checked.
    pub point: SavedPoint<Uuid>,
}

/// A list kept on a device before the account existed, to import.
#[derive(Debug, Clone, PartialEq)]
pub struct ImportedList {
    /// Its name, already checked.
    pub name: String,
    /// Its places.
    pub places: Vec<Uuid>,
    /// Its saved points.
    pub points: Vec<NewPoint>,
}

/// A row of `favorite_points` as stored.
struct PointDb {
    list_id: Uuid,
    id: Uuid,
    kind: String,
    name: String,
    note: Option<String>,
    address: Option<String>,
    lat: f64,
    lon: f64,
    poi_id: Option<Uuid>,
    poi_kind: Option<String>,
    added_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl TryFrom<PointDb> for PointRow {
    type Error = DbError;

    fn try_from(r: PointDb) -> Result<Self, DbError> {
        let kind: FavoritePointKind = r
            .kind
            .parse()
            .map_err(|e| DbError::decode("saved point kind", e))?;
        // The table's checks keep the id and the kind together.
        let poi = match (r.poi_id, r.poi_kind) {
            (Some(id), Some(code)) => Some(SavedPoi {
                id,
                kind: code
                    .parse::<PoiKind>()
                    .map_err(|e| DbError::decode("saved point's poi kind", e))?,
            }),
            _ => None,
        };
        Ok(Self {
            id: r.id,
            point: SavedPoint {
                kind,
                name: r.name,
                note: r.note,
                address: r.address,
                position: Position::new(r.lat, r.lon)
                    .map_err(|e| DbError::decode("saved point position", e))?,
                poi,
            },
            added_at: r.added_at,
            updated_at: r.updated_at,
        })
    }
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
    /// The account holds [`MAX_POINTS`] saved points.
    TooManyPoints,
}

/// Every list of `account`, by name, with its places and its points.
///
/// # Errors
///
/// [`DbError`] when a query fails or a stored point does not decode.
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
    let points = sqlx::query_as!(
        PointDb,
        r#"
        SELECT list_id, id, kind, name, note, address, lat, lon, poi_id, poi_kind,
               added_at, updated_at
        FROM favorite_points WHERE list_id = ANY($1) ORDER BY list_id, added_at, id
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
    let mut points_by_list: std::collections::HashMap<Uuid, Vec<PointRow>> =
        std::collections::HashMap::with_capacity(heads.len());
    for p in points {
        points_by_list
            .entry(p.list_id)
            .or_default()
            .push(p.try_into()?);
    }
    Ok(heads
        .into_iter()
        .map(|h| ListRow {
            items: by_list.remove(&h.id).unwrap_or_default(),
            points: points_by_list.remove(&h.id).unwrap_or_default(),
            id: h.id,
            name: h.name,
            created_at: h.created_at,
            updated_at: h.updated_at,
        })
        .collect())
}

/// One list of `account`, with its places and its points.
///
/// # Errors
///
/// [`DbError`] when a query fails or a stored point does not decode.
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
    let points = sqlx::query_as!(
        PointDb,
        r#"
        SELECT list_id, id, kind, name, note, address, lat, lon, poi_id, poi_kind,
               added_at, updated_at
        FROM favorite_points WHERE list_id = $1 ORDER BY added_at, id
        "#,
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
        points: points
            .into_iter()
            .map(PointRow::try_from)
            .collect::<Result<_, _>>()?,
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

/// How many points the lists of `account` hold together.
async fn point_count(conn: &mut sqlx::PgConnection, account: Uuid) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM favorite_points p
        JOIN favorite_lists l ON l.id = p.list_id
        WHERE l.account_id = $1
        "#,
        account
    )
    .fetch_one(conn)
    .await?)
}

/// Saves a point in a list, or updates the point of the same id there: the
/// last write wins, and when it was added stays. The list's own date moves
/// only when something changed.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn save_point(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
    point: &NewPoint,
) -> Result<Result<(), ListRefusal>, DbError> {
    let mut tx = pool.begin().await?;
    // Serialise the account's saves, so its count of points holds across
    // its lists.
    sqlx::query!("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", account)
        .fetch_optional(&mut *tx)
        .await?;
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
    let known = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM favorite_points WHERE list_id = $1 AND id = $2) AS "known!""#,
        id,
        point.id
    )
    .fetch_one(&mut *tx)
    .await?;
    // An update adds nothing to the count.
    if !known && point_count(&mut tx, account).await? >= MAX_POINTS {
        return Ok(Err(ListRefusal::TooManyPoints));
    }
    let p = &point.point;
    let changed = sqlx::query!(
        r#"
        INSERT INTO favorite_points AS f
            (list_id, id, kind, name, note, address, lat, lon, poi_id, poi_kind)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (list_id, id) DO UPDATE SET
            kind = EXCLUDED.kind, name = EXCLUDED.name, note = EXCLUDED.note,
            address = EXCLUDED.address, lat = EXCLUDED.lat, lon = EXCLUDED.lon,
            poi_id = EXCLUDED.poi_id, poi_kind = EXCLUDED.poi_kind, updated_at = now()
        WHERE (f.kind, f.name, f.note, f.address, f.lat, f.lon, f.poi_id, f.poi_kind)
            IS DISTINCT FROM (EXCLUDED.kind, EXCLUDED.name, EXCLUDED.note, EXCLUDED.address,
                              EXCLUDED.lat, EXCLUDED.lon, EXCLUDED.poi_id, EXCLUDED.poi_kind)
        "#,
        id,
        point.id,
        p.kind.code(),
        p.name,
        p.note.as_deref(),
        p.address.as_deref(),
        p.position.lat(),
        p.position.lon(),
        p.poi.map(|poi| poi.id),
        p.poi.map(|poi| poi.kind.code()),
    )
    .execute(&mut *tx)
    .await?;
    if changed.rows_affected() > 0 {
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

/// Removes a point from a list; a point the list does not hold is already
/// removed.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn remove_point(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
    point: Uuid,
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
        "DELETE FROM favorite_points WHERE list_id = $1 AND id = $2",
        id,
        point
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

/// Adds `points` to the list `id`, keeping the copy of a point the list
/// already holds: the device that imports reconciles both afterwards.
async fn import_points(
    conn: &mut sqlx::PgConnection,
    id: Uuid,
    points: &[NewPoint],
) -> Result<(), DbError> {
    if points.is_empty() {
        return Ok(());
    }
    let ids: Vec<Uuid> = points.iter().map(|p| p.id).collect();
    let kinds: Vec<&str> = points.iter().map(|p| p.point.kind.code()).collect();
    let names: Vec<&str> = points.iter().map(|p| p.point.name.as_str()).collect();
    let notes: Vec<Option<&str>> = points.iter().map(|p| p.point.note.as_deref()).collect();
    let addresses: Vec<Option<&str>> = points.iter().map(|p| p.point.address.as_deref()).collect();
    let lats: Vec<f64> = points.iter().map(|p| p.point.position.lat()).collect();
    let lons: Vec<f64> = points.iter().map(|p| p.point.position.lon()).collect();
    let poi_ids: Vec<Option<Uuid>> = points
        .iter()
        .map(|p| p.point.poi.map(|poi| poi.id))
        .collect();
    let poi_kinds: Vec<Option<&str>> = points
        .iter()
        .map(|p| p.point.poi.map(|poi| poi.kind.code()))
        .collect();
    sqlx::query!(
        r#"
        INSERT INTO favorite_points
            (list_id, id, kind, name, note, address, lat, lon, poi_id, poi_kind)
        SELECT $1, u.id, u.kind, u.name, u.note, u.address, u.lat, u.lon, u.poi_id, u.poi_kind
        FROM UNNEST($2::uuid[], $3::text[], $4::text[], $5::text[], $6::text[],
                    $7::float8[], $8::float8[], $9::uuid[], $10::text[])
             AS u (id, kind, name, note, address, lat, lon, poi_id, poi_kind)
        ON CONFLICT (list_id, id) DO NOTHING
        "#,
        id,
        &ids,
        &kinds as &[&str],
        &names as &[&str],
        &notes as &[Option<&str>],
        &addresses as &[Option<&str>],
        &lats,
        &lons,
        &poi_ids as &[Option<Uuid>],
        &poi_kinds as &[Option<&str>],
    )
    .execute(conn)
    .await?;
    Ok(())
}

/// Imports lists kept on a device before the account existed: each goes
/// into the account's list of the same name (created when missing), its
/// places and its points added. A place merged since the device synced
/// counts as the place that absorbed it; unknown and deleted places are
/// skipped. A point the account's list already holds keeps its copy there.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing is imported then.
pub async fn import(
    pool: &PgPool,
    account: Uuid,
    imported: &[ImportedList],
) -> Result<Result<(), ListRefusal>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", account)
        .fetch_optional(&mut *tx)
        .await?;
    for ImportedList {
        name,
        places,
        points,
    } in imported
    {
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
        import_points(&mut tx, id, points).await?;
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
    if point_count(&mut tx, account).await? > MAX_POINTS {
        return Ok(Err(ListRefusal::TooManyPoints));
    }
    tx.commit().await?;
    Ok(Ok(()))
}
