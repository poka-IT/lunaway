//! Regional first-sync packs: what a pack is built from (one consistent
//! snapshot of a region's live places and the feed position it ends at),
//! and the table of the packs built (`region_packs`).

use chrono::{DateTime, Utc};
use sqlx::{PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    places::{FeedHead, PlaceDb, PlaceRow, PlaceSourceRow},
};

/// A read-only transaction that sees one state of the database, whatever
/// commits meanwhile: every pack of a build holds the places of the same
/// instant, and the cursor it gives continues the feed from that instant.
pub struct Snapshot(Transaction<'static, Postgres>);

impl std::fmt::Debug for Snapshot {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Snapshot")
    }
}

impl Snapshot {
    /// Opens the snapshot.
    ///
    /// # Errors
    ///
    /// [`DbError`] when no connection is available.
    pub async fn begin(pool: &PgPool) -> Result<Self, DbError> {
        let mut tx = pool.begin().await?;
        sqlx::query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            .execute(&mut *tx)
            .await?;
        Ok(Self(tx))
    }

    fn conn(&mut self) -> &mut PgConnection {
        &mut self.0
    }

    /// Ends the snapshot.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the database fails.
    pub async fn end(self) -> Result<(), DbError> {
        self.0.rollback().await?;
        Ok(())
    }

    /// The identity and the end of the change feed in the snapshot.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the query fails or the epoch row is missing.
    pub async fn feed_head(&mut self) -> Result<FeedHead, DbError> {
        let r = sqlx::query!(
            r#"
            SELECT e.epoch,
                   d.oid::int8 AS "database!",
                   (SELECT coalesce(max(updated_seq), 0) FROM places) AS "last_seq!"
            FROM sync_epoch e, pg_database d
            WHERE d.datname = current_database()
            "#
        )
        .fetch_one(self.conn())
        .await?;
        Ok(FeedHead {
            epoch: r.epoch,
            database: r.database,
            last_seq: r.last_seq,
        })
    }

    /// Every sync region that holds a live place, with how many, the box
    /// around them and the last change of the feed among its places.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the query fails.
    pub async fn regions(&mut self) -> Result<Vec<RegionExtent>, DbError> {
        let rows = sqlx::query!(
            r#"
            SELECT region AS "region!",
                   count(*) FILTER (WHERE deleted_at IS NULL) AS "places!",
                   greatest(max(updated_seq),
                            (SELECT max(e.seq) FROM place_region_exits e
                             WHERE e.region = places.region)) AS "last_seq!",
                   min(ST_Y(geom::geometry)) FILTER (WHERE deleted_at IS NULL) AS "south!",
                   min(ST_X(geom::geometry)) FILTER (WHERE deleted_at IS NULL) AS "west!",
                   max(ST_Y(geom::geometry)) FILTER (WHERE deleted_at IS NULL) AS "north!",
                   max(ST_X(geom::geometry)) FILTER (WHERE deleted_at IS NULL) AS "east!"
            FROM places
            WHERE region IS NOT NULL
            GROUP BY region
            HAVING count(*) FILTER (WHERE deleted_at IS NULL) > 0
            ORDER BY region
            "#
        )
        .fetch_all(self.conn())
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| RegionExtent {
                region: r.region,
                places: r.places,
                last_seq: r.last_seq,
                south: r.south,
                west: r.west,
                north: r.north,
                east: r.east,
            })
            .collect())
    }

    /// The live places of `region`, by id.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the query fails or a row does not decode.
    pub async fn places(&mut self, region: &str) -> Result<Vec<PlaceRow>, DbError> {
        let rows = sqlx::query_as!(
            PlaceDb,
            r#"
            SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
                   overnight, services, activities, description, street, postcode, city,
                   country_code, price_parking_eur, price_services_eur, max_height_m,
                   max_length_m, max_width_m, max_weight_t, capacity,
                   opening_hours, opening_hours_parsed, opening_intervals,
                   opening_intervals_until, website, phone, stars, last_confirmed_at,
                   updated_at, updated_seq, provenance,
                   deleted_at IS NOT NULL AS "deleted!", merged_into, municipality,
                   descriptions, external_links, rating_avg, rating_count, review_count,
                   photo_count, cover_photos, reported_issues, verification, region,
                   filter_rating
            FROM places
            WHERE region = $1 AND deleted_at IS NULL
            ORDER BY id
            "#,
            region,
        )
        .fetch_all(self.conn())
        .await?;
        rows.into_iter().map(PlaceRow::try_from).collect()
    }

    /// The sources of every place in `ids`, with their terms and without a
    /// hidden source, as `places::sources_of` gives them.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the query fails or a source id is malformed.
    pub async fn sources_of(&mut self, ids: &[Uuid]) -> Result<Vec<PlaceSourceRow>, DbError> {
        let rows = sqlx::query!(
            r#"
            SELECT ps.place_id, ps.match_score, r.external_id, r.external_url,
                   lunaway_read_at('records', r.source_id, r.scope, r.fetched_at, r.deleted_at)
                       AS "fetched_at!",
                   s.id AS "source_id!", s.name AS "name!", s.licence AS "licence!",
                   s.agreement AS "agreement?", s.attribution AS "attribution!",
                   s.url AS "url!"
            FROM place_sources ps
            JOIN source_records r ON r.id = ps.record_id
            JOIN source_terms s ON s.id = r.source_id
            WHERE ps.place_id = ANY($1) AND s.hidden_at IS NULL
            ORDER BY ps.place_id, s.id, r.external_id
            "#,
            ids,
        )
        .fetch_all(self.conn())
        .await?;
        rows.into_iter()
            .map(|r| {
                Ok(PlaceSourceRow {
                    place_id: r.place_id,
                    source_id: lunaway_domain::SourceId::new(&r.source_id)
                        .map_err(|e| DbError::decode("source id", e))?,
                    source_name: r.name,
                    licence: r.licence,
                    agreement: r.agreement,
                    attribution: r.attribution,
                    source_url: r.url,
                    external_id: r.external_id,
                    external_url: r.external_url,
                    fetched_at: r.fetched_at,
                    match_score: r.match_score,
                })
            })
            .collect()
    }
}

/// A sync region that holds places.
#[derive(Debug, Clone, PartialEq)]
pub struct RegionExtent {
    /// Its code (`FR-BRE`, `ES`).
    pub region: String,
    /// Its live places.
    pub places: i64,
    /// The last position of the feed that changed one of its places,
    /// deletions and departures included: a pack built at or after it is
    /// still current.
    pub last_seq: i64,
    /// Southern edge of the box around them.
    pub south: f64,
    /// Western edge.
    pub west: f64,
    /// Northern edge.
    pub north: f64,
    /// Eastern edge.
    pub east: f64,
}

/// A pack as the table keeps it.
#[derive(Debug, Clone, PartialEq)]
pub struct RegionPack {
    /// Its region.
    pub region: String,
    /// The feed position it holds every place up to.
    pub seq: i64,
    /// The identity of the feed it was built from
    /// ([`FeedHead::identity`]).
    pub feed_identity: String,
    /// Places in it.
    pub places: i32,
    /// Southern edge of the box around them.
    pub south: f64,
    /// Western edge.
    pub west: f64,
    /// Northern edge.
    pub north: f64,
    /// Eastern edge.
    pub east: f64,
    /// Its path under the packs directory.
    pub file: String,
    /// Its format.
    pub format: String,
    /// Its size, as downloaded.
    pub bytes: i64,
    /// Its size once decompressed.
    pub raw_bytes: i64,
    /// SHA-256 of the file as downloaded, hexadecimal.
    pub sha256: String,
    /// When it was built.
    pub generated_at: DateTime<Utc>,
    /// What it was built with besides its places (format, fields, the
    /// photos' URL); a pack of another fingerprint is built again.
    pub fingerprint: Option<String>,
}

/// Every pack built, by region.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn all(pool: &PgPool) -> Result<Vec<RegionPack>, DbError> {
    Ok(sqlx::query_as!(
        RegionPack,
        r#"
        SELECT region, seq, feed_identity, places, south, west, north, east, file, format,
               bytes, raw_bytes, sha256, generated_at, fingerprint
        FROM region_packs
        ORDER BY region
        "#
    )
    .fetch_all(pool)
    .await?)
}

/// Records a new pack of its region, replacing the previous one, and
/// returns the previous one's file, if another.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn record(pool: &PgPool, p: &RegionPack) -> Result<Option<String>, DbError> {
    let mut tx = pool.begin().await?;
    let previous = sqlx::query_scalar!(
        "SELECT file FROM region_packs WHERE region = $1 FOR UPDATE",
        p.region
    )
    .fetch_optional(&mut *tx)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO region_packs (region, seq, feed_identity, places, south, west, north, east,
                                  file, format, bytes, raw_bytes, sha256, generated_at,
                                  fingerprint)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
        ON CONFLICT (region) DO UPDATE SET
            seq = EXCLUDED.seq, feed_identity = EXCLUDED.feed_identity,
            places = EXCLUDED.places, south = EXCLUDED.south, west = EXCLUDED.west,
            north = EXCLUDED.north, east = EXCLUDED.east, file = EXCLUDED.file,
            format = EXCLUDED.format, bytes = EXCLUDED.bytes, raw_bytes = EXCLUDED.raw_bytes,
            sha256 = EXCLUDED.sha256, generated_at = EXCLUDED.generated_at,
            fingerprint = EXCLUDED.fingerprint
        "#,
        p.region,
        p.seq,
        p.feed_identity,
        p.places,
        p.south,
        p.west,
        p.north,
        p.east,
        p.file,
        p.format,
        p.bytes,
        p.raw_bytes,
        p.sha256,
        p.generated_at,
        p.fingerprint,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(previous.filter(|f| *f != p.file))
}

/// Forgets the packs of `regions`; returns how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn forget(pool: &PgPool, regions: &[String]) -> Result<u64, DbError> {
    Ok(
        sqlx::query!("DELETE FROM region_packs WHERE region = ANY($1)", regions)
            .execute(pool)
            .await?
            .rows_affected(),
    )
}

/// Forgets the packs of the regions not in `keep` (a region left without
/// places); returns how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn forget_others(pool: &PgPool, keep: &[String]) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        "DELETE FROM region_packs WHERE NOT (region = ANY($1))",
        keep
    )
    .execute(pool)
    .await?
    .rows_affected())
}

/// Key of the advisory lock that serialises pack builds (`lunapack` in
/// ASCII).
const BUILD_LOCK: i64 = 0x6c75_6e61_7061_636b;

/// The pack builders' lock, held for a whole build: a daily build that took
/// its snapshot before a takedown would otherwise record, after it, a pack
/// that still holds the place taken down.
#[must_use = "the lock is held while this value lives"]
pub struct BuildLock(PgConnection);

impl std::fmt::Debug for BuildLock {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("BuildLock")
    }
}

impl BuildLock {
    /// Waits for the lock, on a connection taken out of the pool: a
    /// session lock on a pooled connection would outlive a build that
    /// failed, while a process that dies closes this connection and frees
    /// the lock. It waits up to half an hour whatever the role's
    /// `statement_timeout` (10 minutes for the import role): a takedown
    /// started during a build waits for it rather than failing.
    ///
    /// # Errors
    ///
    /// [`DbError`] when no connection is available or the lock fails.
    pub async fn acquire(pool: &PgPool) -> Result<Self, DbError> {
        let mut conn = pool.acquire().await?.detach();
        // The connection is closed after the build: no need to restore it.
        sqlx::query!("SET statement_timeout = '30min'")
            .execute(&mut conn)
            .await?;
        sqlx::query!("SELECT pg_advisory_lock($1)", BUILD_LOCK)
            .execute(&mut conn)
            .await?;
        Ok(Self(conn))
    }

    /// Whether this session still holds the lock: a session the server
    /// ended (a restart, `pg_terminate_backend`) lost it, and another build
    /// may have run since.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the connection is gone.
    pub async fn held(&mut self) -> Result<bool, DbError> {
        Ok(sqlx::query_scalar!(
            r#"
            SELECT EXISTS (
                SELECT 1 FROM pg_locks
                WHERE locktype = 'advisory' AND granted AND pid = pg_backend_pid()
            ) AS "held!"
            "#
        )
        .fetch_one(&mut self.0)
        .await?)
    }

    /// Frees the lock and closes its connection.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the server cannot be told; the lock then goes
    /// with the connection.
    pub async fn release(mut self) -> Result<(), DbError> {
        sqlx::query_scalar!("SELECT pg_advisory_unlock($1)", BUILD_LOCK)
            .fetch_one(&mut self.0)
            .await?;
        sqlx::Connection::close(self.0).await?;
        Ok(())
    }
}
