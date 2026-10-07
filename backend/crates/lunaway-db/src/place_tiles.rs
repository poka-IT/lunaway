//! The map tiles of the places (`GET /places/...` in the API) and their
//! version (`place_layer`).
//!
//! The web app reads the places from these tiles instead of syncing every
//! place into its own database: a tile carries what the map's filters need
//! (kind, overnight status, services, free or paid, height limit) so the app
//! filters with a map expression, without a request. From [`PIN_ZOOM`] a
//! tile holds every place with its id; below it, dots: every place reduced
//! to its pixel of a 512 px tile, a dot kept once per pixel and set of
//! properties, so that no filter can tell the dots from the places they
//! stand for.
//!
//! The version moves at most every few minutes ([`publish_layer`]), when
//! the change feed went past the position the current version covers, and
//! at once after a takedown ([`publish_layer_now`]): a new version makes
//! every device fetch its tiles again.

use chrono::{DateTime, Utc};

use crate::{DbError, PgPool};

/// Zoom from which a tile carries every place as a pin, with its id; below
/// it, [`DOTS_MIN_ZOOM`] up, dots. The densest tile of Europe at this zoom
/// held 197 places on 2026-10-07, 4.1 KB gzip without names.
pub const PIN_ZOOM: i32 = 10;
/// Zoom from which a pin carries its name and its town: names add 60% to a
/// tile at zooms 10 and 11, where a map draws no label anyway
/// (`docs/deploy.md`, "Places layer"). From it the app's list beside the
/// map reads the tiles in view rather than ask the API, so a row needs its
/// town; a town costs a few bytes, the tile holding each once.
pub const NAME_MIN_ZOOM: i32 = 12;
/// Lowest zoom of the dots: Europe in three tiles of 47 KB gzip at most.
pub const DOTS_MIN_ZOOM: i32 = 2;
/// Tile extent of a pin tile, in MVT units: a pin stays within a pixel of
/// its place when maps draw the tiles of zoom 14 up to zoom 18.
pub const EXTENT: i32 = 4096;
/// Buffer around a pin tile, in MVT units: a pin near an edge is drawn
/// whole by both tiles.
pub const BUFFER: i32 = 64;
/// Tile extent of a dots tile: one unit per pixel of a 512 px tile, the
/// size at which MapLibre draws a vector tile. Two places in the same unit
/// are one dot on screen, so a dot is kept once per unit.
pub const DOTS_EXTENT: i32 = 512;
/// The services a dot carries (bits 0 to 8, drinking water to laundry):
/// those the app's filters offer. The others only multiply the distinct
/// dots of a tile.
pub const DOTS_SERVICES: i32 = 0x1ff;

/// The tiles' version and what it covers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LayerVersion {
    /// Increases when the places' changes are published.
    pub version: i64,
    /// When it last moved.
    pub changed_at: DateTime<Utc>,
    /// The change feed's position the version covers: a place written
    /// after it waits for the next version.
    pub published_seq: i64,
}

/// The tiles' current version.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn layer_version(pool: &PgPool) -> Result<LayerVersion, DbError> {
    let r = sqlx::query!("SELECT version, changed_at, published_seq FROM place_layer")
        .fetch_one(pool)
        .await?;
    Ok(LayerVersion {
        version: r.version,
        changed_at: r.changed_at,
        published_seq: r.published_seq,
    })
}

/// Moves the tiles' version when a place was written since the current one
/// and that one is older than `every`. Returns the new version, `None`
/// when it did not move.
///
/// The feed's end is read without the writers' lock: a writer still in
/// flight takes positions above every committed one (`place_change_seq`),
/// so what it writes is past the stored position and makes the next run
/// publish.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn publish_layer(
    pool: &PgPool,
    every: std::time::Duration,
) -> Result<Option<i64>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        WITH head AS (SELECT coalesce(max(updated_seq), 0) AS seq FROM places)
        UPDATE place_layer
        SET version = version + 1, changed_at = now(), published_seq = head.seq
        FROM head
        WHERE head.seq > published_seq AND changed_at <= now() - make_interval(secs => $1)
        RETURNING version
        "#,
        every.as_secs_f64(),
    )
    .fetch_optional(pool)
    .await?)
}

/// Moves the tiles' version now, whatever the interval: after a takedown,
/// so the place leaves every tile without waiting.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn publish_layer_now(pool: &PgPool) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        WITH head AS (SELECT coalesce(max(updated_seq), 0) AS seq FROM places)
        UPDATE place_layer
        SET version = version + 1, changed_at = now(),
            published_seq = greatest(published_seq, head.seq)
        FROM head
        RETURNING version
        "#
    )
    .fetch_one(pool)
    .await?)
}

/// The vector tile `z/x/y` of the places, as MVT bytes (empty when the tile
/// holds nothing): from [`PIN_ZOOM`], every live place in the layer
/// `places` (at most `max_features`); below it, the dots in `place_dots`.
///
/// Callers bound `z`, `x` and `y`; the query bounds its own time with the
/// pool's statement timeout.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn tile(
    pool: &PgPool,
    z: i32,
    x: i32,
    y: i32,
    max_features: i64,
) -> Result<Vec<u8>, DbError> {
    if z >= PIN_ZOOM {
        let margin = f64::from(BUFFER) / f64::from(EXTENT);
        let bytes = sqlx::query_scalar!(
            r#"
            WITH bounds AS (
                SELECT ST_TileEnvelope($1, $2, $3) AS merc,
                       ST_Transform(ST_TileEnvelope($1, $2, $3, margin => $4), 4326) AS geo
            ),
            features AS (
                SELECT p.id::text AS id, p.kind, p.overnight AS night, p.services_mask AS s,
                       CASE WHEN p.price_parking_eur = 0 THEN 0
                            WHEN p.price_parking_eur > 0 THEN 1 END AS price,
                       -- Capped, so a wrong height in one row cannot overflow
                       -- the integer and fail every tile around it.
                       round(CASE WHEN p.max_height_m > 1000 THEN 1000
                                  ELSE p.max_height_m END * 100)::int AS h,
                       CASE WHEN $1 >= $8 THEN p.name END AS name,
                       -- The town of the address, else of the commune, as
                       -- the app titles a place without a name.
                       CASE WHEN $1 >= $8 THEN coalesce(p.city, p.municipality) END AS city,
                       ST_AsMVTGeom(ST_Transform(p.geom::geometry, 3857), b.merc, $5, $6, true)
                           AS geom
                FROM places p
                CROSS JOIN bounds b
                WHERE p.deleted_at IS NULL AND p.geom::geometry && b.geo
                ORDER BY p.id
                LIMIT $7
            )
            SELECT coalesce(ST_AsMVT(features, 'places', $5, 'geom'), ''::bytea) AS "mvt!"
            FROM features
            "#,
            z,
            x,
            y,
            margin,
            EXTENT,
            BUFFER,
            max_features,
            NAME_MIN_ZOOM,
        )
        .fetch_one(pool)
        .await?;
        return Ok(bytes);
    }
    // Each place goes to its pixel of the tile (y downwards, as MVT counts),
    // computed here rather than by ST_AsMVTGeom so that the points of a
    // MultiPoint keep the order given: row by row, the deltas between
    // consecutive points stay short (a third smaller once compressed at
    // zoom 5). A place on the tile's east or south edge belongs to the next
    // tile only, by the floor.
    let bytes = sqlx::query_scalar!(
        r#"
        WITH bounds AS (
            SELECT ST_TileEnvelope($1, $2, $3) AS merc,
                   ST_Transform(ST_TileEnvelope($1, $2, $3, margin => $6), 4326) AS geo
        ),
        cells AS (
            SELECT DISTINCT p.kind, p.overnight AS night, p.services_mask & $5::int AS s,
                   CASE WHEN p.price_parking_eur = 0 THEN 0
                        WHEN p.price_parking_eur > 0 THEN 1 END AS price,
                   round(CASE WHEN p.max_height_m > 1000 THEN 1000
                              ELSE p.max_height_m END * 100)::int AS h,
                   floor((ST_X(m.g) - ST_XMin(b.merc)) / (ST_XMax(b.merc) - ST_XMin(b.merc))
                         * $4::int)::int AS px,
                   floor((ST_YMax(b.merc) - ST_Y(m.g)) / (ST_YMax(b.merc) - ST_YMin(b.merc))
                         * $4::int)::int AS py
            FROM bounds b
            CROSS JOIN places p
            CROSS JOIN LATERAL (SELECT ST_Transform(p.geom::geometry, 3857) AS g) m
            WHERE p.deleted_at IS NULL AND p.geom::geometry && b.geo
        ),
        features AS (
            SELECT kind, night, s, price, h,
                   ST_Collect(ST_MakePoint(px, py) ORDER BY py, px) AS geom
            FROM cells
            WHERE px BETWEEN 0 AND $4::int - 1 AND py BETWEEN 0 AND $4::int - 1
            GROUP BY kind, night, s, price, h
        )
        SELECT coalesce(ST_AsMVT(features, 'place_dots', $4::int, 'geom'), ''::bytea) AS "mvt!"
        FROM features
        "#,
        z,
        x,
        y,
        DOTS_EXTENT,
        DOTS_SERVICES,
        // A pixel of margin: a place on a tile's edge passes the box test
        // whatever the rounding of the projection back and forth; the
        // pixel range then keeps it in one tile only.
        1.0 / f64::from(DOTS_EXTENT),
    )
    .fetch_one(pool)
    .await?;
    Ok(bytes)
}

/// The dots tiles that hold at least one place, from [`DOTS_MIN_ZOOM`] to
/// the zoom below [`PIN_ZOOM`], lowest zoom first: what the API builds
/// ahead when a version is published, because a tile of a whole region
/// takes the database up to half a second (3 522 tiles, 6 s in all, for
/// Europe on 2026-10-07). The database lists the tiles of the highest dots
/// zoom only; each lower tile is the parent of one of them.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn dots_tiles_with_places(pool: &PgPool) -> Result<Vec<(i32, i32, i32)>, DbError> {
    let top = PIN_ZOOM - 1;
    let rows = sqlx::query!(
        r#"
        SELECT DISTINCT
               floor((ST_X(g) + 20037508.342789244) / (40075016.68557849 / (1 << $1::int)))::int
                   AS "x!",
               floor((20037508.342789244 - ST_Y(g)) / (40075016.68557849 / (1 << $1::int)))::int
                   AS "y!"
        FROM places CROSS JOIN LATERAL (SELECT ST_Transform(geom::geometry, 3857) AS g) m
        WHERE deleted_at IS NULL
          -- Web Mercator ends at 85.05 degrees: a place beyond is in no tile.
          AND geom::geometry && ST_MakeEnvelope(-180, -85.05, 180, 85.05, 4326)
        "#,
        top,
    )
    .fetch_all(pool)
    .await?;
    let mut tiles = std::collections::BTreeSet::new();
    for r in rows {
        for z in DOTS_MIN_ZOOM..=top {
            let up = top - z;
            tiles.insert((z, r.x >> up, r.y >> up));
        }
    }
    Ok(tiles.into_iter().collect())
}
