//! The map tiles of the places (`GET /places/...` in the API) and their
//! version (`place_layer`).
//!
//! The web app reads the places from these tiles instead of syncing every
//! place into its own database: a tile carries what the map's filters need
//! (kind, overnight status, services, free or paid, height limit, rating)
//! so the app filters with a map expression, without a request. From [`PIN_ZOOM`] a
//! tile holds every place with its id; below it, dots: every place reduced
//! to its pixel of a 512 px tile, a dot kept once per pixel and set of
//! properties, so that no filter can tell the dots from the places they
//! stand for.
//!
//! The version moves at most every few minutes ([`publish_layer`]), when
//! the change feed went past the position the current version covers, and
//! at once after a takedown ([`publish_layer_now`]): a new version makes
//! every device fetch its tiles again. The dots are kept in `place_dots`,
//! counted per pixel, and a publication applies to them the places written
//! since the last one, in the transaction that moves the version: a dots
//! tile reads its own rows instead of every place of its square (1.5 s for
//! the tile of zoom 5 over France in production on 2026-10-08, 45 ms from
//! the table on a copy).

use std::time::Duration;

use chrono::{DateTime, Utc};

use crate::{DbError, PgPool};

/// Zoom from which a tile carries every place as a pin, with its id; below
/// it, [`DOTS_MIN_ZOOM`] up, dots. The densest tile of Europe at this zoom
/// held 197 places on 2026-10-07, 4.1 KB gzip without names.
pub const PIN_ZOOM: i32 = 10;
/// Zoom from which a pin carries its name and its town (and, without a
/// name, its street): names add 60% to a
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
/// dots of a tile. `place_dot_sources` (migration `20261008210100`) masks
/// with the same bits.
pub const DOTS_SERVICES: i32 = 0x1ff;
/// How far past its edge a dots tile carries the dots of its neighbours,
/// in units (pixels): coordinates from `-DOTS_MARGIN` to
/// `DOTS_EXTENT - 1 + DOTS_MARGIN`. MapLibre Native cuts what a tile draws
/// at the tile's edge, so a dot of the next tile that spills over is drawn
/// only if this tile has it too; without the margin, a seam ran through the
/// dots at every tile edge on Android and iOS. The largest dot the app
/// draws is 5 px of radius with a rim of 1.4 px, and a tile of zoom z is
/// drawn from 1 px a unit (zoom z) to 2 (zoom z + 0.99): at most 6.4 units
/// beyond the edge, 8 with the pixel of antialiasing. MapLibre GL JS does
/// not cut: on the web such a dot is drawn by both tiles, one over the
/// other, and at the dots' opacity of 0.95 the second changes nothing
/// visible. Written in `lunaway_place_dot_tiles` (the migration) too.
pub const DOTS_MARGIN: i32 = 8;
/// The ratings a dot carries, in tenths: a dot's `r` is the highest of
/// these its places reach (45 for a rating of 4.5 or more, 30 for 3 to
/// 3.9), none below the lowest. The app's minimum rating offers these
/// steps, and a filter at a step keeps a dot exactly when it keeps one of
/// its places; the exact tenths would multiply the distinct dots of a
/// tile. Pins carry the exact tenths. Lowest first.
pub const DOTS_RATING_STEPS: [i32; 3] = [30, 40, 45];
// `place_dot_sources` (migration `20261008230000`) cuts the rating to three
// steps, written there: another count, or other steps, need a migration
// that writes the dots again. `lunaway-db/tests/place_tiles.rs` checks the
// view against these.
const _: () = assert!(DOTS_RATING_STEPS.len() == 3);

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

/// Moves the tiles' version when a place was written since the current one,
/// or since the dots' position, and that version is older than `every`,
/// with the dots of the places written since. Returns the new version,
/// `None` when it did not move.
///
/// The dots' position lags behind the version's after a version published
/// by a release that does not keep the dots (the worker of the release
/// before, until a deploy restarts it, or a rollback): the next run
/// publishes again, so the dots catch up under a version of their own.
///
/// The feed's end is read without the writers' lock: a writer still in
/// flight takes positions above every committed one (`place_change_seq`),
/// so what it writes is past the stored position and makes the next run
/// publish.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing of the publication is kept.
pub async fn publish_layer(pool: &PgPool, every: Duration) -> Result<Option<i64>, DbError> {
    // Most runs of the worker find nothing to publish: they ask without
    // locking the row, which would write to the database each time.
    let pending = sqlx::query_scalar!(
        r#"
        SELECT (SELECT coalesce(max(updated_seq), 0) FROM places) > least(published_seq, dots_seq)
               AND changed_at <= now() - make_interval(secs => $1) AS "pending!"
        FROM place_layer
        "#,
        every.as_secs_f64(),
    )
    .fetch_one(pool)
    .await?;
    if !pending {
        return Ok(None);
    }
    let mut tx = pool.begin().await?;
    let layer = lock_layer(&mut tx, every).await?;
    if layer.head <= layer.published_seq.min(layer.dots_seq) || !layer.due {
        // Another publication came first.
        tx.commit().await?;
        return Ok(None);
    }
    let version = move_version(&mut tx, &layer).await?;
    tx.commit().await?;
    Ok(Some(version))
}

/// Moves the tiles' version now, whatever the interval, with the dots of
/// the places written since the last one: after a takedown, so the place
/// leaves every tile without waiting.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing of the publication is kept.
pub async fn publish_layer_now(pool: &PgPool) -> Result<i64, DbError> {
    let mut tx = pool.begin().await?;
    let layer = lock_layer(&mut tx, Duration::ZERO).await?;
    let version = move_version(&mut tx, &layer).await?;
    tx.commit().await?;
    Ok(version)
}

type Tx = sqlx::Transaction<'static, sqlx::Postgres>;

/// What a publication reads of the layer, its row locked.
struct LockedLayer {
    published_seq: i64,
    dots_seq: i64,
    /// Whether the version is older than the interval asked.
    due: bool,
    /// The change feed's end.
    head: i64,
}

/// Locks the layer's row and reads it with the feed's end. Two
/// publications (the worker's, a takedown's) take turns on the row, and
/// the second one reads what the first one stored.
async fn lock_layer(tx: &mut Tx, every: Duration) -> Result<LockedLayer, DbError> {
    let layer = sqlx::query!(
        r#"
        SELECT published_seq, dots_seq,
               changed_at <= now() - make_interval(secs => $1) AS "due!"
        FROM place_layer FOR UPDATE
        "#,
        every.as_secs_f64(),
    )
    .fetch_one(&mut **tx)
    .await?;
    let head = sqlx::query_scalar!(r#"SELECT coalesce(max(updated_seq), 0) AS "seq!" FROM places"#)
        .fetch_one(&mut **tx)
        .await?;
    Ok(LockedLayer {
        published_seq: layer.published_seq,
        dots_seq: layer.dots_seq,
        due: layer.due,
        head,
    })
}

/// Applies the places written since the dots' position and moves the
/// version, in the caller's transaction.
async fn move_version(tx: &mut Tx, layer: &LockedLayer) -> Result<i64, DbError> {
    apply_dots(tx, layer.dots_seq, layer.head).await?;
    Ok(sqlx::query_scalar!(
        r#"
        UPDATE place_layer
        SET version = version + 1, changed_at = now(),
            published_seq = greatest(published_seq, $1), dots_seq = greatest(dots_seq, $1)
        RETURNING version
        "#,
        layer.head,
    )
    .fetch_one(&mut **tx)
    .await?)
}

/// Brings `place_dots` from the places as they were at feed position
/// `from` to their state now, for those written up to `to`: each one's dots
/// as `place_dot_members` remembers them go, those of its live state come,
/// and the members follow. One statement, so the dots and the members come
/// from the same snapshot of the places; a place written again meanwhile
/// is past `to` and waits for the next publication, which starts from the
/// members this one left.
async fn apply_dots(tx: &mut Tx, from: i64, to: i64) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        WITH changed AS (
            SELECT id FROM places WHERE updated_seq > $1 AND updated_seq <= $2
        ),
        now_state AS MATERIALIZED (
            SELECT s.id, s.kind, s.night, s.s, s.price, s.h, s.r, s.o1, s.o2, s.gx, s.gy
            FROM place_dot_sources s JOIN changed c ON c.id = s.id
        ),
        before AS (
            SELECT m.kind, m.night, m.s, m.price, m.h, m.r, m.o1, m.o2, m.gx, m.gy
            FROM place_dot_members m JOIN changed c ON c.id = m.place_id
        ),
        gone AS (
            DELETE FROM place_dot_members m USING changed c
            WHERE m.place_id = c.id AND NOT EXISTS (SELECT 1 FROM now_state n WHERE n.id = c.id)
        ),
        kept AS (
            INSERT INTO place_dot_members (place_id, kind, night, s, price, h, r, o1, o2, gx, gy)
            SELECT id, kind, night, s, price, h, r, o1, o2, gx, gy FROM now_state
            ON CONFLICT (place_id) DO UPDATE
            SET kind = excluded.kind, night = excluded.night, s = excluded.s,
                price = excluded.price, h = excluded.h, r = excluded.r, o1 = excluded.o1,
                o2 = excluded.o2, gx = excluded.gx, gy = excluded.gy
        ),
        deltas AS (
            SELECT t.z, t.tx, t.ty, d.kind, d.night, d.s, d.price, d.h, d.r, d.o1, d.o2, t.py, t.px,
                   sum(d.n)::integer AS n
            FROM (SELECT kind, night, s, price, h, r, o1, o2, gx, gy, -1 AS n FROM before
                  UNION ALL
                  SELECT kind, night, s, price, h, r, o1, o2, gx, gy, 1 FROM now_state) d
            CROSS JOIN LATERAL lunaway_place_dot_tiles(d.gx, d.gy) t
            GROUP BY t.z, t.tx, t.ty, t.py, t.px, d.s, d.price, d.h, d.r, d.o1, d.o2, d.kind,
                     d.night
            HAVING sum(d.n) <> 0
        )
        INSERT INTO place_dots AS p (z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n)
        SELECT z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px, n FROM deltas
        ON CONFLICT (z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px)
        DO UPDATE SET n = p.n + excluded.n
        "#,
        from,
        to,
    )
    .execute(&mut **tx)
    .await?;
    // A dot whose last place went; the readers never see it, the same
    // transaction removes it.
    sqlx::query!("DELETE FROM place_dots WHERE n <= 0")
        .execute(&mut **tx)
        .await?;
    Ok(())
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
                       -- The filter rating in tenths (33 for 3.3).
                       round(p.filter_rating * 10)::int AS r,
                       -- The season's ranges, each as first day * 1000 +
                       -- last day (92305 for 1 April to 31 October), absent
                       -- when the hours are no season.
                       p.opening_season[1] * 1000 + p.opening_season[2] AS o1,
                       p.opening_season[3] * 1000 + p.opening_season[4] AS o2,
                       CASE WHEN $1 >= $8 THEN p.name END AS name,
                       -- The town of the address, else of the commune, as
                       -- the app titles a place without a name.
                       CASE WHEN $1 >= $8 THEN coalesce(p.city, p.municipality) END AS city,
                       -- The street of a place without a name, which the
                       -- app titles by it (`Parking · Rue de la Gare`); never
                       -- a private host's, whose title is its town.
                       CASE WHEN $1 >= $8 AND p.name IS NULL AND p.kind <> 'homestay'
                            THEN p.street END AS st,
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
    // The dots of the tile and of its margin, as the last publication left
    // them (`place_dots`), in the key's order: one MultiPoint per set of
    // properties, its points row by row, so the deltas between consecutive
    // points stay short (a third smaller once compressed at zoom 5). The
    // points are written as they are (no ST_AsMVTGeom), which keeps that
    // order and the margin's coordinates past the edge.
    let bytes = sqlx::query_scalar!(
        r#"
        SELECT coalesce(ST_AsMVT(f, 'place_dots', $4::int, 'geom'), ''::bytea) AS "mvt!"
        FROM (
            SELECT kind, night, s, price, h, r, o1, o2,
                   ST_Collect(ST_MakePoint(px, py) ORDER BY py, px) AS geom
            FROM place_dots
            WHERE z = $1::int AND tx = $2 AND ty = $3
            GROUP BY kind, night, s, price, h, r, o1, o2
        ) f
        "#,
        z,
        x,
        y,
        DOTS_EXTENT,
    )
    .fetch_one(pool)
    .await?;
    Ok(bytes)
}

/// The dots tiles that hold at least one dot, their margin included, from
/// [`DOTS_MIN_ZOOM`] to the zoom below [`PIN_ZOOM`], lowest zoom first:
/// what the API builds ahead when a version is published, so that the
/// first view of a region finds its tiles in memory.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn dots_tiles_with_places(pool: &PgPool) -> Result<Vec<(i32, i32, i32)>, DbError> {
    Ok(sqlx::query!(
        r#"
        SELECT DISTINCT z::int AS "z!", tx AS "x!", ty AS "y!" FROM place_dots
        ORDER BY 1, 2, 3
        "#
    )
    .fetch_all(pool)
    .await?
    .into_iter()
    .map(|r| (r.z, r.x, r.y))
    .collect())
}
