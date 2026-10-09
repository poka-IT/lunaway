//! Speed cameras: the devices each source lists (`enforcement_devices`), and
//! what the API serves under each country's rule (`enforcement_items`, a
//! change feed by revision), each item for every client or only for those
//! that made, or did not make, a country's choice ([`Variant`]).

use chrono::{DateTime, Utc};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, OptIns},
};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// A device to store.
#[derive(Debug, Clone)]
pub struct NewDevice<'a> {
    /// What the source says, read.
    pub device: &'a Device,
    /// Its country: an official list's own, or that of its position.
    pub country: &'a str,
    /// What an import of extracts retires it by
    /// (`lunaway_ingest::osm_extract::scope_of`).
    pub scope: &'a str,
    /// The source's row.
    pub raw: &'a serde_json::Value,
}

/// Inserts or updates `devices` of `source`, all read at `fetched_at`;
/// returns how many rows it wrote: new, changed, or seen again at a later
/// read (their fetch date moves).
///
/// # Errors
///
/// [`DbError`] when a statement fails or a device does not encode.
pub async fn upsert_devices(
    pool: &PgPool,
    source: &SourceId,
    devices: &[NewDevice<'_>],
    fetched_at: DateTime<Utc>,
) -> Result<u64, DbError> {
    let mut written = 0;
    for batch in devices.chunks(2_000) {
        let ids: Vec<&str> = batch
            .iter()
            .map(|d| d.device.external_id.as_str())
            .collect();
        let countries: Vec<&str> = batch.iter().map(|d| d.country).collect();
        let scopes: Vec<&str> = batch.iter().map(|d| d.scope).collect();
        let kinds: Vec<&str> = batch.iter().map(|d| d.device.kind.code()).collect();
        let lats: Vec<f64> = batch.iter().map(|d| d.device.position.lat()).collect();
        let lons: Vec<f64> = batch.iter().map(|d| d.device.position.lon()).collect();
        let data: Vec<serde_json::Value> = batch
            .iter()
            .map(|d| serde_json::to_value(d.device))
            .collect::<Result<_, _>>()
            .map_err(|e| DbError::decode("enforcement device", e))?;
        let raw: Vec<serde_json::Value> = batch.iter().map(|d| d.raw.clone()).collect();
        let done = sqlx::query!(
            r#"
            INSERT INTO enforcement_devices AS d
                (source_id, external_id, country, scope, kind, geom, data, raw, fetched_at)
            SELECT $1, u.external_id, u.country, u.scope, u.kind,
                   ST_SetSRID(ST_MakePoint(u.lon, u.lat), 4326)::geography, u.data, u.raw, $9
            FROM UNNEST($2::text[], $3::text[], $10::text[], $4::text[], $5::float8[],
                        $6::float8[], $7::jsonb[], $8::jsonb[])
                 AS u(external_id, country, scope, kind, lat, lon, data, raw)
            ON CONFLICT (source_id, external_id) DO UPDATE SET
                country = EXCLUDED.country, scope = EXCLUDED.scope, kind = EXCLUDED.kind,
                geom = EXCLUDED.geom,
                data = EXCLUDED.data, raw = EXCLUDED.raw, fetched_at = EXCLUDED.fetched_at,
                changed_at = CASE WHEN d.data IS DISTINCT FROM EXCLUDED.data
                                    OR d.deleted_at IS NOT NULL
                                  THEN now() ELSE d.changed_at END,
                deleted_at = NULL
            WHERE d.data IS DISTINCT FROM EXCLUDED.data OR d.deleted_at IS NOT NULL
               OR d.fetched_at < EXCLUDED.fetched_at
            "#,
            source.as_str(),
            &ids as &[&str],
            &countries as &[&str],
            &kinds as &[&str],
            &lats,
            &lons,
            &data,
            &raw,
            fetched_at,
            &scopes as &[&str],
        )
        .execute(pool)
        .await?;
        written += done.rows_affected();
    }
    Ok(written)
}

/// Live devices of `source`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_count(pool: &PgPool, source: &SourceId) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM enforcement_devices
           WHERE source_id = $1 AND deleted_at IS NULL"#,
        source.as_str()
    )
    .fetch_one(pool)
    .await?)
}

/// Marks as gone the live devices of `source` whose id is not in `seen`;
/// returns how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn retire_missing(
    pool: &PgPool,
    source: &SourceId,
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        UPDATE enforcement_devices SET deleted_at = $3, changed_at = now()
        WHERE source_id = $1 AND deleted_at IS NULL AND NOT (external_id = ANY($2))
        "#,
        source.as_str(),
        seen,
        at,
    )
    .execute(pool)
    .await?
    .rows_affected())
}

/// Live devices of `source` by scope.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_counts_by_scope(
    pool: &PgPool,
    source: &SourceId,
) -> Result<std::collections::BTreeMap<String, i64>, DbError> {
    let rows = sqlx::query!(
        r#"SELECT scope, count(*) AS "n!" FROM enforcement_devices
           WHERE source_id = $1 AND deleted_at IS NULL GROUP BY scope"#,
        source.as_str()
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| (r.scope, r.n)).collect())
}

/// Marks as gone the live devices of `source` in `scopes` whose id is not
/// in `seen`; returns how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn retire_missing_in(
    pool: &PgPool,
    source: &SourceId,
    scopes: &[String],
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        UPDATE enforcement_devices SET deleted_at = $4, changed_at = now()
        WHERE source_id = $1 AND deleted_at IS NULL AND scope = ANY($2)
          AND NOT (external_id = ANY($3))
        "#,
        source.as_str(),
        scopes,
        seen,
        at,
    )
    .execute(pool)
    .await?
    .rows_affected())
}

/// A live device, as the build of the items reads it.
#[derive(Debug, Clone, PartialEq)]
pub struct DeviceRow {
    /// Its source.
    pub source_id: String,
    /// Its country.
    pub country: String,
    /// What the source says.
    pub device: Device,
}

impl DeviceRow {
    /// The key of the item it gives: its source and its id there.
    #[must_use]
    pub fn key(&self) -> String {
        format!("{}/{}", self.source_id, self.device.external_id)
    }
}

/// Every live device, by source and id.
///
/// # Errors
///
/// [`DbError`] when the query fails or a device does not decode.
pub async fn live_devices(pool: &PgPool) -> Result<Vec<DeviceRow>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT source_id, country, data FROM enforcement_devices
        WHERE deleted_at IS NULL
        ORDER BY source_id, external_id
        "#
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(DeviceRow {
                device: serde_json::from_value(r.data)
                    .map_err(|e| DbError::decode("enforcement device", e))?,
                source_id: r.source_id,
                country: r.country,
            })
        })
        .collect()
}

/// What the API serves for one device.
#[derive(Debug, Clone, PartialEq)]
pub struct Item {
    /// A stable id that does not lead back to the device.
    pub id: Uuid,
    /// The device it comes from ([`DeviceRow::key`]); never served.
    pub device_key: String,
    /// Which clients it is for.
    pub variant: Variant,
    /// The choices its form depends on: none for [`Variant::All`], at
    /// least one otherwise.
    pub opt_in_countries: OptIns,
    /// `zone` or `camera`.
    pub kind: ItemKind,
    /// What it covers or controls (`ZoneKind` or `DeviceKind` code).
    pub category: String,
    /// Its country.
    pub country: String,
    /// A zone's line, in driving order.
    pub line: Option<Vec<Position>>,
    /// A camera's point.
    pub point: Option<Position>,
    /// A camera's direction of travel, degrees.
    pub bearing_deg: Option<f64>,
    /// A camera's limit, km/h.
    pub limit_kmh: Option<u16>,
    /// The sources it comes from.
    pub source_ids: Vec<String>,
    /// A digest of what is served, to write only what changed.
    pub content_hash: String,
}

/// A zone or a camera.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItemKind {
    /// A stretch of road without a point.
    Zone,
    /// A point.
    Camera,
}

impl ItemKind {
    /// Its code in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Zone => "zone",
            Self::Camera => "camera",
        }
    }

    fn of(code: &str) -> Result<Self, DbError> {
        match code {
            "zone" => Ok(Self::Zone),
            "camera" => Ok(Self::Camera),
            other => Err(DbError::decode(
                "enforcement item kind",
                std::io::Error::other(format!("unknown kind {other}")),
            )),
        }
    }
}

/// Which clients an item is for: a camera whose form depends on a choice
/// some country offers (France's positions in place of zones) has an item
/// for the clients without the choice and one for those with it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Variant {
    /// Every client: the camera's form depends on no choice.
    All,
    /// The clients that did not make every choice of
    /// [`Item::opt_in_countries`].
    Default,
    /// The clients that made every one of them.
    OptIn,
}

impl Variant {
    /// Its code in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Default => "default",
            Self::OptIn => "opt_in",
        }
    }

    fn of(code: &str) -> Result<Self, DbError> {
        match code {
            "all" => Ok(Self::All),
            "default" => Ok(Self::Default),
            "opt_in" => Ok(Self::OptIn),
            other => Err(DbError::decode(
                "enforcement item variant",
                std::io::Error::other(format!("unknown variant {other}")),
            )),
        }
    }
}

/// Where an item stands among a camera's items: a camera has at most one
/// for the clients without the choice ([`Variant::All`] or
/// [`Variant::Default`], the same row whichever) and one for those with it
/// ([`Variant::OptIn`]).
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ItemKey {
    /// The device it comes from ([`DeviceRow::key`]).
    pub device_key: String,
    /// Whether it is the camera's item for the clients with the choice.
    pub opt_in: bool,
}

impl ItemKey {
    /// The key of the item of `device_key` of `variant`.
    #[must_use]
    pub fn new(device_key: &str, variant: Variant) -> Self {
        Self {
            device_key: device_key.to_owned(),
            opt_in: variant == Variant::OptIn,
        }
    }
}

impl Item {
    /// Its key among its camera's items.
    #[must_use]
    pub fn key(&self) -> ItemKey {
        ItemKey::new(&self.device_key, self.variant)
    }
}

/// The live items' keys and digests.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn item_digests(
    pool: &PgPool,
) -> Result<std::collections::HashMap<ItemKey, String>, DbError> {
    let rows = sqlx::query!(
        r#"SELECT device_key, variant = 'opt_in' AS "opt_in!", content_hash
           FROM enforcement_items WHERE deleted_at IS NULL"#
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| {
            (
                ItemKey {
                    device_key: r.device_key,
                    opt_in: r.opt_in,
                },
                r.content_hash,
            )
        })
        .collect())
}

fn wkt_line(points: &[Position]) -> String {
    let coords: Vec<String> = points
        .iter()
        .map(|p| format!("{} {}", p.lon(), p.lat()))
        .collect();
    format!("LINESTRING({})", coords.join(","))
}

/// Writes `items` (new or changed) and retires the live items whose key is
/// in `gone`, in one transaction, each change at a new revision. Returns
/// (written, retired).
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn write_items(
    pool: &PgPool,
    items: &[Item],
    gone: &[ItemKey],
) -> Result<(u64, u64), DbError> {
    let mut tx = pool.begin().await?;
    // One writer at a time: the revisions of a write become visible
    // together and after every earlier one, so a client that read up to a
    // revision never misses a lower one committed later.
    sqlx::query!("LOCK TABLE enforcement_items IN SHARE ROW EXCLUSIVE MODE")
        .execute(&mut *tx)
        .await?;
    let mut written = 0;
    // In the order of their ids, which nothing outside the server can tie
    // to a camera: in the order of their keys, the revisions of a full
    // build would follow the official lists' ids.
    let mut ordered: Vec<&Item> = items.iter().collect();
    ordered.sort_by_key(|i| i.id);
    for item in ordered {
        let line = item.line.as_deref().map(wkt_line);
        let (lat, lon) = item
            .point
            .map_or((None, None), |p| (Some(p.lat()), Some(p.lon())));
        #[allow(
            clippy::cast_possible_truncation,
            reason = "a bearing between 0 and 360 degrees"
        )]
        let bearing = item.bearing_deg.map(|b| b as f32);
        let limit = item.limit_kmh.and_then(|l| i16::try_from(l).ok());
        let opt_in_countries =
            (item.variant != Variant::All).then_some(item.opt_in_countries.countries());
        written += sqlx::query!(
            r#"
            INSERT INTO enforcement_items AS i
                (id, device_key, variant, opt_in_countries, kind, category, country, line, point,
                 bearing_deg, limit_kmh, source_ids, content_hash, revision)
            VALUES ($1, $2, $13, $14, $3, $4, $5, ST_GeogFromText($6),
                    CASE WHEN $7::float8 IS NULL THEN NULL
                         ELSE ST_SetSRID(ST_MakePoint($8, $7), 4326)::geography END,
                    $9, $10, $11, $12, nextval('enforcement_revision_seq'))
            ON CONFLICT (device_key, (variant = 'opt_in')) DO UPDATE SET
                variant = EXCLUDED.variant, opt_in_countries = EXCLUDED.opt_in_countries,
                kind = EXCLUDED.kind, category = EXCLUDED.category, country = EXCLUDED.country,
                line = EXCLUDED.line, point = EXCLUDED.point,
                bearing_deg = EXCLUDED.bearing_deg, limit_kmh = EXCLUDED.limit_kmh,
                source_ids = EXCLUDED.source_ids, content_hash = EXCLUDED.content_hash,
                revision = EXCLUDED.revision, updated_at = now(), deleted_at = NULL
            "#,
            item.id,
            item.device_key,
            item.kind.code(),
            item.category,
            item.country,
            line,
            lat,
            lon,
            bearing,
            limit,
            &item.source_ids,
            item.content_hash,
            item.variant.code(),
            opt_in_countries as Option<&[&str]>,
        )
        .execute(&mut *tx)
        .await?
        .rows_affected();
    }
    let (gone_keys, gone_opt_in): (Vec<&str>, Vec<bool>) = gone
        .iter()
        .map(|k| (k.device_key.as_str(), k.opt_in))
        .unzip();
    let retired = sqlx::query!(
        r#"
        UPDATE enforcement_items
        SET deleted_at = now(), updated_at = now(), revision = nextval('enforcement_revision_seq')
        WHERE deleted_at IS NULL
          AND (device_key, variant = 'opt_in') IN (SELECT * FROM UNNEST($1::text[], $2::bool[]))
        "#,
        &gone_keys as &[&str],
        &gone_opt_in,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    tx.commit().await?;
    Ok((written, retired))
}

/// The head of the items' feed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedHead {
    /// The database's identity: a cursor of another copy starts over.
    pub identity: String,
    /// The highest revision.
    pub revision: i64,
}

/// The head of the items' feed.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn feed_head(pool: &PgPool) -> Result<FeedHead, DbError> {
    let r = sqlx::query!(
        r#"
        SELECT e.epoch, d.oid::int8 AS "database!",
            (SELECT coalesce(max(revision), 0) FROM enforcement_items) AS "revision!"
        FROM sync_epoch e, pg_database d
        WHERE d.datname = current_database()
        "#
    )
    .fetch_one(pool)
    .await?;
    Ok(FeedHead {
        identity: format!("{}{:08x}", r.epoch.simple(), r.database),
        revision: r.revision,
    })
}

/// An item as the feed serves it.
#[derive(Debug, Clone, PartialEq)]
pub struct FeedItem {
    /// Its id.
    pub id: Uuid,
    /// Its revision.
    pub revision: i64,
    /// Gone since that revision.
    pub deleted: bool,
    /// Which clients it is for.
    pub variant: Variant,
    /// Whether it is for a client with the choices asked: one that is not
    /// comes back to it as a removal.
    pub visible: bool,
    /// A zone or a camera.
    pub kind: ItemKind,
    /// What it covers or controls.
    pub category: String,
    /// Its country.
    pub country: String,
    /// A zone's line.
    pub line: Option<Vec<Position>>,
    /// A camera's point.
    pub point: Option<Position>,
    /// A camera's direction of travel.
    pub bearing_deg: Option<f64>,
    /// A camera's limit.
    pub limit_kmh: Option<i16>,
    /// Its sources.
    pub source_ids: Vec<String>,
    /// When it last changed.
    pub updated_at: DateTime<Utc>,
}

/// The items changed after revision `after` up to `upto` (the head the
/// cursor will name), oldest first, at most `limit`, of `countries` when
/// given, for a client that made the choices `chosen`. Without
/// `with_removals`, only the live items
/// for that client; with it, every item changed, gone ones and those for
/// other clients included ([`FeedItem::visible`]), so that a client whose
/// item moved to the other side of a choice drops it.
///
/// # Errors
///
/// [`DbError`] when the query fails or a geometry does not decode.
pub async fn changed_since(
    pool: &PgPool,
    after: i64,
    upto: i64,
    limit: i64,
    with_removals: bool,
    countries: Option<&[String]>,
    chosen: &OptIns,
) -> Result<Vec<FeedItem>, DbError> {
    // An item is for the client when it is for everyone, when it is the
    // form for those without the choices it depends on and the client
    // lacks one of them, or the form for those with them and the client
    // made them all.
    let rows = sqlx::query!(
        r#"
        WITH changed AS (
            -- Named columns: the API's role reads neither device_key nor
            -- content_hash.
            SELECT id, revision, deleted_at, variant, kind, category, country, line, point,
                   bearing_deg, limit_kmh, source_ids, updated_at,
                   variant = 'all'
                   OR (variant = 'default' AND NOT (opt_in_countries <@ $6::text[]))
                   OR (variant = 'opt_in' AND opt_in_countries <@ $6::text[]) AS for_client
            FROM enforcement_items
            WHERE revision > $1 AND revision <= $4
              AND ($5::text[] IS NULL OR country = ANY($5))
        )
        SELECT id, revision, deleted_at IS NOT NULL AS "deleted!", variant,
               for_client AS "visible!", kind, category, country,
               CASE WHEN line IS NULL THEN NULL
                    ELSE ST_AsGeoJSON(line::geometry, 6) END AS "line?",
               ST_Y(point::geometry) AS "lat?", ST_X(point::geometry) AS "lon?",
               bearing_deg, limit_kmh, source_ids, updated_at
        FROM changed
        WHERE $3 OR (deleted_at IS NULL AND for_client)
        ORDER BY revision
        LIMIT $2
        "#,
        after,
        limit,
        with_removals,
        upto,
        countries as Option<&[String]>,
        chosen.countries() as &[&str],
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            let line = r
                .line
                .map(|json| {
                    let v: serde_json::Value =
                        serde_json::from_str(&json).map_err(|e| DbError::decode("zone line", e))?;
                    v["coordinates"]
                        .as_array()
                        .map(|cs| {
                            cs.iter()
                                .filter_map(|c| Position::new(c[1].as_f64()?, c[0].as_f64()?).ok())
                                .collect::<Vec<_>>()
                        })
                        .ok_or_else(|| {
                            DbError::decode("zone line", std::io::Error::other("no coordinates"))
                        })
                })
                .transpose()?;
            let point = r
                .lat
                .zip(r.lon)
                .and_then(|(lat, lon)| Position::new(lat, lon).ok());
            Ok(FeedItem {
                id: r.id,
                revision: r.revision,
                deleted: r.deleted,
                variant: Variant::of(&r.variant)?,
                visible: r.visible,
                kind: ItemKind::of(&r.kind)?,
                category: r.category,
                country: r.country,
                line,
                point,
                bearing_deg: r.bearing_deg.map(f64::from),
                limit_kmh: r.limit_kmh,
                source_ids: r.source_ids,
                updated_at: r.updated_at,
            })
        })
        .collect()
}

/// Records that `source`'s list was read at `fetched_at`, holds `devices`
/// live devices, and was last updated at `list_updated_at` by its own
/// account (kept from an earlier read when this one does not say).
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn record_read(
    pool: &PgPool,
    source: &SourceId,
    fetched_at: DateTime<Utc>,
    devices: i64,
    list_updated_at: Option<DateTime<Utc>>,
) -> Result<(), DbError> {
    let devices = i32::try_from(devices).unwrap_or(i32::MAX);
    sqlx::query!(
        r#"
        INSERT INTO enforcement_sources AS s (source_id, fetched_at, devices, list_updated_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (source_id) DO UPDATE SET
            fetched_at = EXCLUDED.fetched_at, devices = EXCLUDED.devices, updated_at = now(),
            list_updated_at = coalesce(EXCLUDED.list_updated_at, s.list_updated_at)
        "#,
        source.as_str(),
        fetched_at,
        devices,
        list_updated_at,
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// How many live items of a kind, a variant and a country.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemCount {
    /// A zone or a camera.
    pub kind: ItemKind,
    /// Which clients they are for.
    pub variant: Variant,
    /// The country.
    pub country: String,
    /// How many.
    pub n: i64,
}

/// The live items by kind, variant and country.
///
/// # Errors
///
/// [`DbError`] when the query fails or a code is unknown.
pub async fn item_counts(pool: &PgPool) -> Result<Vec<ItemCount>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT kind, variant, country, count(*) AS "n!" FROM enforcement_items
        WHERE deleted_at IS NULL
        GROUP BY kind, variant, country ORDER BY kind, variant, country
        "#
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(ItemCount {
                kind: ItemKind::of(&r.kind)?,
                variant: Variant::of(&r.variant)?,
                country: r.country,
                n: r.n,
            })
        })
        .collect()
}

/// A camera list as the API cites it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceRead {
    /// The source.
    pub source: crate::sources::SourceRow,
    /// When its list was last read.
    pub fetched_at: DateTime<Utc>,
    /// Its live devices then.
    pub devices: i32,
    /// When the list says it was last updated, when it says.
    pub list_updated_at: Option<DateTime<Utc>>,
}

/// Every camera list read, with its terms, by source id.
///
/// # Errors
///
/// [`DbError`] when the query fails or a source id is malformed.
pub async fn source_reads(pool: &PgPool) -> Result<Vec<SourceRead>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT s.id, s.name, s.licence, s.licence_url, s.attribution, s.url,
               r.fetched_at, r.devices, r.list_updated_at
        FROM enforcement_sources r JOIN sources s ON s.id = r.source_id
        ORDER BY s.id
        "#
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(SourceRead {
                source: crate::sources::SourceRow {
                    id: SourceId::new(&r.id).map_err(|e| DbError::decode("source id", e))?,
                    name: r.name,
                    licence: r.licence,
                    licence_url: r.licence_url,
                    attribution: r.attribution,
                    url: r.url,
                },
                fetched_at: r.fetched_at,
                devices: r.devices,
                list_updated_at: r.list_updated_at,
            })
        })
        .collect()
}
