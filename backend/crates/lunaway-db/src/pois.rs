//! Points of interest: the layer of shops, vending machines, water, fuel,
//! health and services around the places (`pois`), the values other open
//! sources give for them (`poi_join_records`), the version of the map tiles
//! (`poi_layer`) and what the community says of them.
//!
//! Every write holds the POI writers' advisory lock for its transaction
//! ([`PoiWriterTx`]): the importers, the fuel poller and the worker write
//! the same rows. Each marks the layer once it changed what a tile shows
//! (an import of many batches once at its end, [`mark_layer_now`]), and the
//! worker moves the tiles' version at most every few hours
//! ([`publish_layer`]), so neither an import's batches nor the fuel poller
//! make every device fetch its tiles again each time. The lock is not the
//! places' one, so a POI import never waits for a conflation.

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    BBox, OpeningInterval, Position, SourceId,
    poi::{PoiCategory, PoiKind, PoiRecord},
};
use sqlx::{PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::{DbError, PgPool, records::UpsertStats};

/// Key of the advisory lock of the POI writers (`lunapois` in ASCII).
const POI_WRITER_LOCK: i64 = 0x6c75_6e61_706f_6973;

/// A transaction holding the POI writers' lock: the only one that writes
/// points, joined values and the tiles' version.
pub struct PoiWriterTx(Transaction<'static, Postgres>);

impl std::fmt::Debug for PoiWriterTx {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("PoiWriterTx")
    }
}

impl PoiWriterTx {
    pub(crate) fn conn(&mut self) -> &mut PgConnection {
        &mut self.0
    }

    /// Commits the transaction and releases the lock.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the commit fails; nothing of the transaction is kept.
    pub async fn commit(self) -> Result<(), DbError> {
        self.0.commit().await?;
        Ok(())
    }
}

/// Starts a transaction holding the POI writers' lock, waiting up to half
/// an hour while another writer holds it.
///
/// # Errors
///
/// [`DbError`] when no connection is available or the lock statement fails.
pub async fn begin_poi_writer(pool: &PgPool) -> Result<PoiWriterTx, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SET LOCAL statement_timeout = '30min'")
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SELECT pg_advisory_xact_lock($1)", POI_WRITER_LOCK)
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SET LOCAL statement_timeout TO DEFAULT")
        .execute(&mut *tx)
        .await?;
    Ok(PoiWriterTx(tx))
}

/// Marks the layer as changed: a writer changed what a tile shows. The
/// version itself moves later, once for every change of a few hours
/// ([`publish_layer`]): a new version makes every device fetch again each
/// tile it looks at, and the fuel poller alone changed a few tiles every 15
/// minutes (`plan/research/13-basemap.md`, deployment of the points of
/// interest). Tiles are built from the current data whatever the version,
/// so a change shows in any tile built after it.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn mark_layer(tx: &mut PoiWriterTx) -> Result<(), DbError> {
    sqlx::query!("UPDATE poi_layer SET pending_since = coalesce(pending_since, now())")
        .execute(tx.conn())
        .await?;
    Ok(())
}

/// Marks the layer as changed in a transaction of its own: what an import
/// does once at its end, when one of its batches changed what a tile shows.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn mark_layer_now(pool: &PgPool) -> Result<(), DbError> {
    let mut tx = begin_poi_writer(pool).await?;
    mark_layer(&mut tx).await?;
    tx.commit().await
}

/// Moves the tiles' version when a change waits and the version has not
/// moved for `every`: every tile URL changes, so no cache serves the data
/// of before. Returns the new version, `None` when it did not move.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn publish_layer(
    pool: &PgPool,
    every: std::time::Duration,
) -> Result<Option<i64>, DbError> {
    let mut tx = begin_poi_writer(pool).await?;
    let v = sqlx::query_scalar!(
        r#"
        UPDATE poi_layer
        SET version = version + 1, changed_at = now(), pending_since = NULL
        WHERE pending_since IS NOT NULL AND changed_at <= now() - make_interval(secs => $1)
        RETURNING version
        "#,
        every.as_secs_f64(),
    )
    .fetch_optional(tx.conn())
    .await?;
    tx.commit().await?;
    Ok(v)
}

/// The tiles' version and when it last moved.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LayerVersion {
    /// Increases when changes of what a tile shows are published.
    pub version: i64,
    /// When it last moved.
    pub changed_at: DateTime<Utc>,
    /// Since when a change waits for the next version, if one does.
    pub pending_since: Option<DateTime<Utc>>,
}

/// The tiles' current version.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn layer_version(pool: &PgPool) -> Result<LayerVersion, DbError> {
    let r = sqlx::query!("SELECT version, changed_at, pending_since FROM poi_layer")
        .fetch_one(pool)
        .await?;
    Ok(LayerVersion {
        version: r.version,
        changed_at: r.changed_at,
        pending_since: r.pending_since,
    })
}

// Writing points.

/// A point to insert or update.
#[derive(Debug, Clone, Copy)]
pub struct NewPoi<'a> {
    /// Identifier in the source.
    pub external_id: &'a str,
    /// Page at the source.
    pub external_url: Option<&'a str>,
    /// What the source says.
    pub record: &'a PoiRecord,
    /// Payload as received.
    pub raw: &'a serde_json::Value,
    /// When it was read.
    pub fetched_at: DateTime<Utc>,
    /// The country an extract run imported it under, which a later run of
    /// that country may retire it from; `None` for a community point.
    pub scope: Option<&'a str>,
}

/// Rows per statement, as for the records.
const BATCH: usize = 1_000;

/// Whether `opening_hours` says the point never closes.
fn always_open(hours: Option<&str>) -> bool {
    hours.is_some_and(|h| h.trim() == "24/7")
}

/// Inserts or updates `points` of `source`, a batch per transaction; a
/// point whose hours changed is left for the worker to evaluate again. The
/// caller marks the layer once it is done ([`mark_layer_now`])
/// when a point was inserted or changed.
///
/// # Errors
///
/// [`DbError`] when a statement fails; the batches already written stay.
pub async fn upsert(
    pool: &PgPool,
    source: &SourceId,
    points: &[NewPoi<'_>],
) -> Result<UpsertStats, DbError> {
    let mut stats = UpsertStats::default();
    for batch in points.chunks(BATCH) {
        let mut tx = begin_poi_writer(pool).await?;
        let s = upsert_batch(&mut tx, source, batch).await?;
        tx.commit().await?;
        stats += s;
    }
    Ok(stats)
}

/// Inserts or updates `points` of `source` inside `tx`.
///
/// # Errors
///
/// [`DbError`] when the statement fails or a record does not serialise.
pub async fn upsert_batch(
    tx: &mut PoiWriterTx,
    source: &SourceId,
    points: &[NewPoi<'_>],
) -> Result<UpsertStats, DbError> {
    let n = points.len();
    let mut ids = Vec::with_capacity(n);
    let mut external_ids = Vec::with_capacity(n);
    let mut urls: Vec<Option<String>> = Vec::with_capacity(n);
    let mut categories = Vec::with_capacity(n);
    let mut kinds = Vec::with_capacity(n);
    let mut names: Vec<Option<String>> = Vec::with_capacity(n);
    let mut brands: Vec<Option<String>> = Vec::with_capacity(n);
    let mut lats = Vec::with_capacity(n);
    let mut lons = Vec::with_capacity(n);
    let mut fuel: Vec<Option<String>> = Vec::with_capacity(n);
    let mut laposte: Vec<Option<String>> = Vec::with_capacity(n);
    let mut finess: Vec<Option<String>> = Vec::with_capacity(n);
    let mut hours: Vec<Option<String>> = Vec::with_capacity(n);
    let mut always: Vec<bool> = Vec::with_capacity(n);
    let mut data = Vec::with_capacity(n);
    let mut raws = Vec::with_capacity(n);
    let mut fetched = Vec::with_capacity(n);
    let mut scopes: Vec<Option<String>> = Vec::with_capacity(n);
    for p in points {
        scopes.push(p.scope.map(str::to_owned));
        let r = p.record;
        ids.push(Uuid::now_v7());
        external_ids.push(p.external_id.to_owned());
        urls.push(p.external_url.map(str::to_owned));
        categories.push(r.kind.category().code().to_owned());
        kinds.push(r.kind.code().to_owned());
        names.push(r.name.clone());
        brands.push(r.brand.clone());
        lats.push(r.position.lat());
        lons.push(r.position.lon());
        fuel.push(r.refs.fuel.clone());
        laposte.push(r.refs.laposte.clone());
        finess.push(r.refs.finess.clone());
        hours.push(r.opening_hours.clone());
        always.push(always_open(r.opening_hours.as_deref()));
        data.push(serde_json::to_value(r).map_err(|e| DbError::decode("poi record", e))?);
        raws.push(p.raw.clone());
        fetched.push(p.fetched_at);
    }
    // `now()` is the transaction start: a row whose `changed_at` equals it
    // was inserted or changed by this statement.
    let rows = sqlx::query!(
        r#"
        INSERT INTO pois AS p
            (id, source_id, external_id, external_url, category, kind, name, brand, geom,
             fuel_ref, laposte_ref, finess_ref, opening_hours, always_open, data, raw, fetched_at,
             scope)
        SELECT u.id, $1, u.external_id, u.external_url, u.category, u.kind, u.name, u.brand,
               ST_SetSRID(ST_MakePoint(u.lon, u.lat), 4326)::geography, u.fuel, u.laposte,
               u.finess, u.hours, u.always, u.data, u.raw, u.fetched_at, u.scope
        FROM UNNEST($2::uuid[], $3::text[], $4::text[], $5::text[], $6::text[], $7::text[],
                    $8::text[], $9::float8[], $10::float8[], $11::text[], $12::text[],
                    $13::text[], $14::text[], $15::bool[], $16::jsonb[], $17::jsonb[],
                    $18::timestamptz[], $19::text[])
             AS u(id, external_id, external_url, category, kind, name, brand, lat, lon, fuel,
                  laposte, finess, hours, always, data, raw, fetched_at, scope)
        ON CONFLICT (source_id, external_id) DO UPDATE SET
            external_url = EXCLUDED.external_url,
            category = EXCLUDED.category,
            kind = EXCLUDED.kind,
            name = EXCLUDED.name,
            brand = EXCLUDED.brand,
            geom = EXCLUDED.geom,
            fuel_ref = EXCLUDED.fuel_ref,
            laposte_ref = EXCLUDED.laposte_ref,
            finess_ref = EXCLUDED.finess_ref,
            opening_hours = EXCLUDED.opening_hours,
            always_open = EXCLUDED.always_open,
            data = EXCLUDED.data,
            raw = EXCLUDED.raw,
            fetched_at = EXCLUDED.fetched_at,
            scope = EXCLUDED.scope,
            -- New hours, or a new La Poste id, are evaluated again by the
            -- worker; hours gone from both leave nothing behind, since the
            -- worker no longer looks at such a point.
            opening_window_start = CASE
                WHEN p.opening_hours IS DISTINCT FROM EXCLUDED.opening_hours
                  OR p.laposte_ref IS DISTINCT FROM EXCLUDED.laposte_ref
                THEN NULL ELSE p.opening_window_start END,
            opening_refresh_at = CASE
                WHEN p.opening_hours IS DISTINCT FROM EXCLUDED.opening_hours
                  OR p.laposte_ref IS DISTINCT FROM EXCLUDED.laposte_ref
                THEN NULL ELSE p.opening_refresh_at END,
            opening_hours_parsed = p.opening_hours_parsed
                AND (EXCLUDED.opening_hours IS NOT NULL OR EXCLUDED.laposte_ref IS NOT NULL),
            opening_intervals = CASE
                WHEN EXCLUDED.opening_hours IS NULL AND EXCLUDED.laposte_ref IS NULL
                THEN NULL ELSE p.opening_intervals END,
            opening_intervals_until = CASE
                WHEN EXCLUDED.opening_hours IS NULL AND EXCLUDED.laposte_ref IS NULL
                THEN NULL ELSE p.opening_intervals_until END,
            opening_source = CASE
                WHEN EXCLUDED.opening_hours IS NULL AND EXCLUDED.laposte_ref IS NULL
                THEN NULL ELSE p.opening_source END,
            opening_tile = CASE
                WHEN EXCLUDED.opening_hours IS NULL AND EXCLUDED.laposte_ref IS NULL
                THEN NULL ELSE p.opening_tile END,
            changed_at = CASE
                WHEN p.data IS DISTINCT FROM EXCLUDED.data OR p.deleted_at IS NOT NULL
                THEN now() ELSE p.changed_at END,
            deleted_at = NULL
        RETURNING (xmax = 0) AS "inserted!", (changed_at = now()) AS "touched!"
        "#,
        source.as_str(),
        &ids,
        &external_ids,
        &urls as &[Option<String>],
        &categories,
        &kinds,
        &names as &[Option<String>],
        &brands as &[Option<String>],
        &lats,
        &lons,
        &fuel as &[Option<String>],
        &laposte as &[Option<String>],
        &finess as &[Option<String>],
        &hours as &[Option<String>],
        &always,
        &data,
        &raws,
        &fetched,
        &scopes as &[Option<String>],
    )
    .fetch_all(tx.conn())
    .await?;
    let mut stats = UpsertStats::default();
    for r in rows {
        if r.inserted {
            stats.inserted += 1;
        } else if r.touched {
            stats.changed += 1;
        } else {
            stats.unchanged += 1;
        }
    }
    Ok(stats)
}

/// Live points of `source` in any of `scopes`, or in every scope when
/// `None`. A point imported before scopes existed counts as French.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_count(
    pool: &PgPool,
    source: &SourceId,
    scopes: Option<&[String]>,
) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM pois
        WHERE source_id = $1 AND deleted_at IS NULL
          AND ($2::text[] IS NULL OR coalesce(scope, 'FR') = ANY($2))
        "#,
        source.as_str(),
        scopes,
    )
    .fetch_one(pool)
    .await?)
}

/// Marks as deleted the live points of `source` whose external id is not in
/// `seen`, in any of `scopes` (every scope when `None`): a run of country
/// extracts speaks for those countries only. A point imported before
/// scopes existed counts as French. Returns how many; the caller marks the
/// layer when there are any.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn retire_missing(
    pool: &PgPool,
    source: &SourceId,
    scopes: Option<&[String]>,
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    let mut tx = begin_poi_writer(pool).await?;
    let done = sqlx::query!(
        r#"
        UPDATE pois SET deleted_at = $3, changed_at = now()
        WHERE source_id = $1 AND deleted_at IS NULL AND NOT (external_id = ANY($2))
          AND ($4::text[] IS NULL OR coalesce(scope, 'FR') = ANY($4))
        "#,
        source.as_str(),
        seen,
        at,
        scopes,
    )
    .execute(tx.conn())
    .await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}

// Values joined from other open sources.

/// One row of a joined source, keyed by the identifier points carry.
#[derive(Debug, Clone, Copy)]
pub struct NewJoin<'a> {
    /// The identifier (a feed id, a La Poste id, a FINESS number).
    pub key: &'a str,
    /// The adapter's typed reading, as JSON. What a map tile shows of it
    /// sits under `tile`, so a change there marks the layer.
    pub data: &'a serde_json::Value,
    /// The row as the source sent it.
    pub raw: &'a serde_json::Value,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
}

/// What an upsert of joined rows did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct JoinStats {
    /// Inserted, changed, unchanged.
    pub upsert: UpsertStats,
    /// Keys whose data changed or appeared.
    pub changed_keys: Vec<String>,
    /// Rows whose tile part changed.
    pub tile_changes: u64,
}

/// Inserts or updates the joined rows of `source`, a batch per POI writer
/// transaction. Points whose La Poste days changed are left for the worker
/// to evaluate; the caller marks the layer when a row's tile part
/// changed ([`JoinStats::tile_changes`]).
///
/// # Errors
///
/// [`DbError`] when a statement fails; the batches already written stay.
pub async fn upsert_joins(
    pool: &PgPool,
    source: &SourceId,
    rows: &[NewJoin<'_>],
) -> Result<JoinStats, DbError> {
    let mut stats = JoinStats::default();
    for batch in rows.chunks(BATCH) {
        let keys: Vec<String> = batch.iter().map(|r| r.key.to_owned()).collect();
        let data: Vec<serde_json::Value> = batch.iter().map(|r| r.data.clone()).collect();
        let raws: Vec<serde_json::Value> = batch.iter().map(|r| r.raw.clone()).collect();
        let fetched: Vec<DateTime<Utc>> = batch.iter().map(|r| r.fetched_at).collect();
        let mut tx = begin_poi_writer(pool).await?;
        let written = sqlx::query!(
            r#"
            WITH before AS (
                SELECT ref, data -> 'tile' AS tile, deleted_at IS NOT NULL AS gone
                FROM poi_join_records WHERE source_id = $1 AND ref = ANY($2)
            ),
            up AS (
                INSERT INTO poi_join_records AS j (source_id, ref, data, raw, fetched_at)
                SELECT $1, u.ref, u.data, u.raw, u.fetched_at
                FROM UNNEST($2::text[], $3::jsonb[], $4::jsonb[], $5::timestamptz[])
                     AS u(ref, data, raw, fetched_at)
                ON CONFLICT (source_id, ref) DO UPDATE SET
                    data = EXCLUDED.data,
                    raw = EXCLUDED.raw,
                    fetched_at = EXCLUDED.fetched_at,
                    changed_at = CASE
                        WHEN j.data IS DISTINCT FROM EXCLUDED.data OR j.deleted_at IS NOT NULL
                        THEN now() ELSE j.changed_at END,
                    deleted_at = NULL
                RETURNING ref, data -> 'tile' AS tile, (xmax = 0) AS inserted,
                          (changed_at = now()) AS touched
            )
            SELECT up.ref AS "key!", up.inserted AS "inserted!", up.touched AS "touched!",
                   (up.tile IS DISTINCT FROM CASE WHEN b.gone THEN NULL ELSE b.tile END)
                       AS "tile_changed!"
            FROM up LEFT JOIN before b ON b.ref = up.ref
            "#,
            source.as_str(),
            &keys,
            &data,
            &raws,
            &fetched,
        )
        .fetch_all(tx.conn())
        .await?;
        let mut changed = Vec::new();
        let mut tile_changes = 0;
        for w in written {
            if w.inserted {
                stats.upsert.inserted += 1;
            } else if w.touched {
                stats.upsert.changed += 1;
            } else {
                stats.upsert.unchanged += 1;
            }
            if w.inserted || w.touched {
                changed.push(w.key);
            }
            if w.tile_changed {
                tile_changes += 1;
            }
        }
        if *source == SourceId::LAPOSTE && !changed.is_empty() {
            sqlx::query!(
                r#"
                UPDATE pois SET opening_window_start = NULL, opening_refresh_at = NULL
                WHERE laposte_ref = ANY($1) AND deleted_at IS NULL
                "#,
                &changed,
            )
            .execute(tx.conn())
            .await?;
        }
        tx.commit().await?;
        stats.changed_keys.extend(changed);
        stats.tile_changes += tile_changes;
    }
    Ok(stats)
}

/// Live joined rows of `source`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_join_count(pool: &PgPool, source: &SourceId) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM poi_join_records WHERE source_id = $1 AND deleted_at IS NULL"#,
        source.as_str(),
    )
    .fetch_one(pool)
    .await?)
}

/// Marks as deleted the live joined rows of `source` whose key is not in
/// `seen`, and has the points of a retired La Poste id evaluated again.
/// Returns how many, and whether one of them showed on a tile (the caller
/// then marks the layer).
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn retire_missing_joins(
    pool: &PgPool,
    source: &SourceId,
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<(u64, bool), DbError> {
    let mut tx = begin_poi_writer(pool).await?;
    let gone = sqlx::query!(
        r#"
        UPDATE poi_join_records SET deleted_at = $3, changed_at = now()
        WHERE source_id = $1 AND deleted_at IS NULL AND NOT (ref = ANY($2))
        RETURNING ref AS key, data ? 'tile' AS "on_tile!"
        "#,
        source.as_str(),
        seen,
        at,
    )
    .fetch_all(tx.conn())
    .await?;
    let keys: Vec<String> = gone.iter().map(|g| g.key.clone()).collect();
    if *source == SourceId::LAPOSTE && !keys.is_empty() {
        sqlx::query!(
            "UPDATE pois SET opening_window_start = NULL, opening_refresh_at = NULL \
             WHERE laposte_ref = ANY($1)",
            &keys,
        )
        .execute(tx.conn())
        .await?;
    }
    tx.commit().await?;
    Ok((
        u64::try_from(gone.len()).unwrap_or(u64::MAX),
        gone.iter().any(|g| g.on_tile),
    ))
}

// Opening hours.

/// A point whose opening intervals must be computed again.
#[derive(Debug, Clone, PartialEq)]
pub struct StaleHours {
    /// The point.
    pub id: Uuid,
    /// Its own source, which its `opening_hours` come from.
    pub source_id: SourceId,
    /// Its `opening_hours`.
    pub opening_hours: Option<String>,
    /// Its country, which gives the timezone.
    pub country_code: Option<String>,
    /// Its position, for sun events.
    pub position: Position,
    /// La Poste's calendar for it, as the adapter stored it.
    pub laposte: Option<serde_json::Value>,
}

/// Points with hours (theirs or La Poste's) whose window must move at `now`
/// (its local midnight has passed, or it was never set), at most `limit`,
/// by id.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn stale_hours(
    tx: &mut PoiWriterTx,
    now: DateTime<Utc>,
    limit: i64,
) -> Result<Vec<StaleHours>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT p.id, p.source_id, p.opening_hours,
               p.data -> 'address' ->> 'country_code' AS country_code,
               ST_Y(p.geom::geometry) AS "lat!", ST_X(p.geom::geometry) AS "lon!",
               j.data AS "laposte?"
        FROM pois p
        LEFT JOIN poi_join_records j
          ON j.source_id = 'laposte' AND j.ref = p.laposte_ref AND j.deleted_at IS NULL
        WHERE p.deleted_at IS NULL
          AND (p.opening_hours IS NOT NULL OR p.laposte_ref IS NOT NULL)
          AND (p.opening_refresh_at IS NULL OR p.opening_refresh_at <= $1)
        ORDER BY p.id
        LIMIT $2
        "#,
        now,
        limit,
    )
    .fetch_all(tx.conn())
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(StaleHours {
                id: r.id,
                source_id: SourceId::new(&r.source_id)
                    .map_err(|e| DbError::decode("source id", e))?,
                opening_hours: r.opening_hours,
                country_code: r.country_code,
                position: Position::new(r.lat, r.lon)
                    .map_err(|e| DbError::decode("poi position", e))?,
                laposte: r.laposte,
            })
        })
        .collect()
}

/// What the evaluation of a point's hours gave.
#[derive(Debug, Clone, PartialEq)]
pub struct HoursWrite {
    /// The point.
    pub id: Uuid,
    /// Whether its hours could be read.
    pub parsed: bool,
    /// Open intervals over the window; `None` when nothing is known.
    pub intervals: Option<Vec<OpeningInterval>>,
    /// End of the window the intervals cover.
    pub until: Option<DateTime<Utc>>,
    /// First local day of the window.
    pub window_start: NaiveDate,
    /// When the window must move: the next local midnight after its first
    /// day, in the zone of the point.
    pub refresh_at: DateTime<Utc>,
    /// The source of the intervals, when they exist: La Poste's calendar,
    /// or the point's own source.
    pub source: Option<SourceId>,
    /// The intervals in the tiles' compact form.
    pub tile: Option<String>,
}

/// Writes evaluated hours in one statement. Returns how many points' tile
/// hours changed; the caller marks the layer when there are any.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn set_hours(tx: &mut PoiWriterTx, writes: &[HoursWrite]) -> Result<u64, DbError> {
    if writes.is_empty() {
        return Ok(0);
    }
    let ids: Vec<Uuid> = writes.iter().map(|w| w.id).collect();
    let parsed: Vec<bool> = writes.iter().map(|w| w.parsed).collect();
    let intervals: Vec<Option<serde_json::Value>> = writes
        .iter()
        .map(|w| w.intervals.as_ref().map(serde_json::to_value).transpose())
        .collect::<Result<_, _>>()
        .map_err(|e| DbError::decode("opening intervals", e))?;
    let until: Vec<Option<DateTime<Utc>>> = writes.iter().map(|w| w.until).collect();
    let start: Vec<NaiveDate> = writes.iter().map(|w| w.window_start).collect();
    let source: Vec<Option<String>> = writes
        .iter()
        .map(|w| w.source.as_ref().map(ToString::to_string))
        .collect();
    let tile: Vec<Option<String>> = writes.iter().map(|w| w.tile.clone()).collect();
    let refresh: Vec<DateTime<Utc>> = writes.iter().map(|w| w.refresh_at).collect();
    let changed = sqlx::query_scalar!(
        r#"
        WITH u AS (
            SELECT * FROM UNNEST($1::uuid[], $2::bool[], $3::jsonb[], $4::timestamptz[],
                                 $5::date[], $6::text[], $7::text[], $8::timestamptz[])
                AS u(id, parsed, intervals, until, start, source, tile, refresh)
        ),
        old AS (
            SELECT p.id, p.opening_tile, p.opening_intervals_until
            FROM pois p JOIN u ON u.id = p.id
        )
        UPDATE pois p SET
            opening_hours_parsed = u.parsed, opening_intervals = u.intervals,
            opening_intervals_until = u.until, opening_window_start = u.start,
            opening_source = u.source, opening_tile = u.tile, opening_refresh_at = u.refresh
        FROM u JOIN old ON old.id = u.id
        WHERE p.id = u.id
        RETURNING (old.opening_tile IS DISTINCT FROM u.tile
                   OR old.opening_intervals_until IS DISTINCT FROM u.until) AS "changed!"
        "#,
        &ids,
        &parsed,
        &intervals as &[Option<serde_json::Value>],
        &until as &[Option<DateTime<Utc>>],
        &start,
        &source as &[Option<String>],
        &tile as &[Option<String>],
        &refresh,
    )
    .fetch_all(tx.conn())
    .await?;
    let n = changed.into_iter().filter(|c| *c).count();
    Ok(u64::try_from(n).unwrap_or(u64::MAX))
}

// Reading points.

/// A value another source gives for a point.
#[derive(Debug, Clone, PartialEq)]
pub struct JoinedRow {
    /// The source.
    pub source_id: SourceId,
    /// The key the point carries.
    pub key: String,
    /// The adapter's reading.
    pub data: serde_json::Value,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
}

/// A point as the API serves it.
#[derive(Debug, Clone, PartialEq)]
pub struct PoiRow {
    /// Stable id (UUID v7).
    pub id: Uuid,
    /// Its source.
    pub source_id: SourceId,
    /// Its id in the source.
    pub external_id: String,
    /// Its page at the source.
    pub external_url: Option<String>,
    /// What the source says.
    pub record: PoiRecord,
    /// Whether the hours parse.
    pub opening_hours_parsed: bool,
    /// Open day and night.
    pub always_open: bool,
    /// Open intervals over the window.
    pub opening_intervals: Option<Vec<OpeningInterval>>,
    /// End of that window.
    pub opening_intervals_until: Option<DateTime<Utc>>,
    /// Where the intervals come from (`osm`, `laposte`).
    pub opening_source: Option<SourceId>,
    /// The last "still there" of the community.
    pub last_confirmed_at: Option<DateTime<Utc>>,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
    /// When its content last changed.
    pub changed_at: DateTime<Utc>,
    /// Distance from the point asked about, metres, when one was.
    pub distance_m: Option<f64>,
    /// Values from other sources, filled by [`attach_joins`].
    pub joins: Vec<JoinedRow>,
}

impl PoiRow {
    /// Its category.
    #[must_use]
    pub fn category(&self) -> PoiCategory {
        self.record.kind.category()
    }

    /// The joined value of `source`, if any.
    #[must_use]
    pub fn join(&self, source: &SourceId) -> Option<&JoinedRow> {
        self.joins.iter().find(|j| j.source_id == *source)
    }
}

struct PoiDb {
    id: Uuid,
    source_id: String,
    external_id: String,
    external_url: Option<String>,
    data: serde_json::Value,
    opening_hours_parsed: bool,
    always_open: bool,
    opening_intervals: Option<serde_json::Value>,
    opening_intervals_until: Option<DateTime<Utc>>,
    opening_source: Option<String>,
    last_confirmed_at: Option<DateTime<Utc>>,
    fetched_at: DateTime<Utc>,
    changed_at: DateTime<Utc>,
    distance_m: Option<f64>,
}

impl TryFrom<PoiDb> for PoiRow {
    type Error = DbError;

    fn try_from(r: PoiDb) -> Result<Self, DbError> {
        Ok(Self {
            id: r.id,
            source_id: SourceId::new(&r.source_id).map_err(|e| DbError::decode("source id", e))?,
            external_id: r.external_id,
            external_url: r.external_url,
            record: serde_json::from_value(r.data).map_err(|e| DbError::decode("poi record", e))?,
            opening_hours_parsed: r.opening_hours_parsed,
            always_open: r.always_open,
            opening_intervals: r
                .opening_intervals
                .map(serde_json::from_value)
                .transpose()
                .map_err(|e| DbError::decode("opening intervals", e))?,
            opening_intervals_until: r.opening_intervals_until,
            opening_source: r
                .opening_source
                .map(|s| SourceId::new(&s))
                .transpose()
                .map_err(|e| DbError::decode("opening source", e))?,
            last_confirmed_at: r.last_confirmed_at,
            fetched_at: r.fetched_at,
            changed_at: r.changed_at,
            distance_m: r.distance_m,
            joins: Vec::new(),
        })
    }
}

fn rows(db: Vec<PoiDb>) -> Result<Vec<PoiRow>, DbError> {
    db.into_iter().map(PoiRow::try_from).collect()
}

/// Fills the joined values of `points`, in one query.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn attach_joins(pool: &PgPool, points: &mut [PoiRow]) -> Result<(), DbError> {
    if points.is_empty() {
        return Ok(());
    }
    let ids: Vec<Uuid> = points.iter().map(|p| p.id).collect();
    let joined = sqlx::query!(
        r#"
        SELECT p.id AS "poi!", j.source_id AS "source_id!", j.ref AS "key!", j.data AS "data!",
               j.fetched_at AS "fetched_at!"
        FROM pois p
        JOIN poi_join_records j
          ON j.deleted_at IS NULL AND j.source_id = 'prix-carburants' AND j.ref = p.fuel_ref
        WHERE p.id = ANY($1)
        UNION ALL
        SELECT p.id, j.source_id, j.ref, j.data, j.fetched_at
        FROM pois p
        JOIN poi_join_records j
          ON j.deleted_at IS NULL AND j.source_id = 'laposte' AND j.ref = p.laposte_ref
        WHERE p.id = ANY($1)
        UNION ALL
        SELECT p.id, j.source_id, j.ref, j.data, j.fetched_at
        FROM pois p
        JOIN poi_join_records j
          ON j.deleted_at IS NULL AND j.source_id = 'finess' AND j.ref = p.finess_ref
        WHERE p.id = ANY($1)
        "#,
        &ids,
    )
    .fetch_all(pool)
    .await?;
    for j in joined {
        let source_id = SourceId::new(&j.source_id).map_err(|e| DbError::decode("source id", e))?;
        if let Some(p) = points.iter_mut().find(|p| p.id == j.poi) {
            p.joins.push(JoinedRow {
                source_id,
                key: j.key,
                data: j.data,
                fetched_at: j.fetched_at,
            });
        }
    }
    Ok(())
}

/// The point `id`, live and not hidden; `None` otherwise.
///
/// # Errors
///
/// [`DbError`] when a query fails or the row does not decode.
pub async fn by_id(pool: &PgPool, id: Uuid) -> Result<Option<PoiRow>, DbError> {
    let row = sqlx::query_as!(
        PoiDb,
        r#"
        SELECT id, source_id, external_id, external_url, data, opening_hours_parsed, always_open,
               opening_intervals, opening_intervals_until, opening_source, last_confirmed_at,
               fetched_at, changed_at, NULL::float8 AS distance_m
        FROM pois WHERE id = $1 AND deleted_at IS NULL AND NOT hidden
        "#,
        id,
    )
    .fetch_optional(pool)
    .await?;
    let Some(row) = row else { return Ok(None) };
    let mut out = vec![PoiRow::try_from(row)?];
    attach_joins(pool, &mut out).await?;
    Ok(out.pop())
}

/// The points nearest `at` in each of `categories`, at most `per_category`
/// each, within each category's radius (`radii_m`, in the same order),
/// nearest first, with their distance. `kinds` narrows them when given.
///
/// # Errors
///
/// [`DbError`] when a query fails or a row does not decode.
pub async fn nearby(
    pool: &PgPool,
    at: Position,
    categories: &[PoiCategory],
    radii_m: &[f64],
    kinds: Option<&[PoiKind]>,
    per_category: i64,
) -> Result<Vec<PoiRow>, DbError> {
    let cats: Vec<String> = categories.iter().map(|c| c.code().to_owned()).collect();
    let kinds: Option<Vec<String>> = kinds.map(|k| k.iter().map(|k| k.code().to_owned()).collect());
    let found = sqlx::query_as!(
        PoiDb,
        r#"
        SELECT p.id AS "id!", p.source_id AS "source_id!", p.external_id AS "external_id!",
               p.external_url, p.data AS "data!", p.opening_hours_parsed AS "opening_hours_parsed!",
               p.always_open AS "always_open!", p.opening_intervals, p.opening_intervals_until,
               p.opening_source, p.last_confirmed_at, p.fetched_at AS "fetched_at!",
               p.changed_at AS "changed_at!", p.distance_m
        FROM UNNEST($3::text[], $4::float8[]) AS c(category, radius)
        CROSS JOIN LATERAL (
            SELECT q.*, ST_Distance(q.geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography)
                       AS distance_m
            FROM pois q
            WHERE q.deleted_at IS NULL AND NOT q.hidden AND q.category = c.category
              AND ($5::text[] IS NULL OR q.kind = ANY($5))
              AND ST_DWithin(q.geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, c.radius)
            ORDER BY q.geom <-> ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, q.id
            LIMIT $6
        ) p
        ORDER BY array_position($3, c.category), p.distance_m, p.id
        "#,
        at.lat(),
        at.lon(),
        &cats,
        radii_m,
        kinds.as_deref() as Option<&[String]>,
        per_category,
    )
    .fetch_all(pool)
    .await?;
    let mut out = rows(found)?;
    attach_joins(pool, &mut out).await?;
    Ok(out)
}

/// Points whose name or brand matches `text` (accents and case ignored):
/// names that hold the words first, then typo-tolerant matches; among
/// equal matches the nearest to `near`. `categories` narrows them.
///
/// # Errors
///
/// [`DbError`] when a query fails or a row does not decode.
pub async fn search(
    pool: &PgPool,
    text: &str,
    near: Option<Position>,
    categories: Option<&[PoiCategory]>,
    first: i64,
) -> Result<Vec<PoiRow>, DbError> {
    let cats: Option<Vec<String>> =
        categories.map(|c| c.iter().map(|c| c.code().to_owned()).collect());
    let found = sqlx::query_as!(
        PoiDb,
        r#"
        WITH q AS (SELECT lunaway_fold($1) AS t)
        SELECT p.id, p.source_id, p.external_id, p.external_url, p.data,
               p.opening_hours_parsed, p.always_open, p.opening_intervals,
               p.opening_intervals_until, p.opening_source, p.last_confirmed_at, p.fetched_at,
               p.changed_at,
               CASE WHEN $2::float8 IS NULL THEN NULL ELSE
                    ST_Distance(p.geom, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography) END
                   AS distance_m
        FROM pois p, q
        WHERE p.deleted_at IS NULL AND NOT p.hidden
          AND q.t <% p.search_text
          AND ($4::text[] IS NULL OR p.category = ANY($4))
        ORDER BY (p.search_text LIKE '%' || q.t || '%') DESC,
                 round(word_similarity(q.t, p.search_text)::numeric, 1) DESC,
                 CASE WHEN $2::float8 IS NULL THEN 0 ELSE
                      p.geom <-> ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography END,
                 p.id
        LIMIT $5
        "#,
        text,
        near.map(Position::lat),
        near.map(Position::lon),
        cats.as_deref() as Option<&[String]>,
        first,
    )
    .fetch_all(pool)
    .await?;
    let mut out = rows(found)?;
    attach_joins(pool, &mut out).await?;
    Ok(out)
}

/// One page of the points of an area, by id: what a device downloads to
/// have them offline.
#[derive(Debug, Clone, PartialEq)]
pub struct PoiPage {
    /// The points.
    pub nodes: Vec<PoiRow>,
    /// Whether more follow the last one.
    pub has_next_page: bool,
}

/// Live points inside `bbox` in `categories` (all when `None`), by id,
/// after `after`.
///
/// # Errors
///
/// [`DbError`] when a query fails or a row does not decode.
pub async fn in_bbox(
    pool: &PgPool,
    bbox: BBox,
    categories: Option<&[PoiCategory]>,
    first: i64,
    after: Option<Uuid>,
) -> Result<PoiPage, DbError> {
    let cats: Option<Vec<String>> =
        categories.map(|c| c.iter().map(|c| c.code().to_owned()).collect());
    let found = sqlx::query_as!(
        PoiDb,
        r#"
        SELECT id, source_id, external_id, external_url, data, opening_hours_parsed, always_open,
               opening_intervals, opening_intervals_until, opening_source, last_confirmed_at,
               fetched_at, changed_at, NULL::float8 AS distance_m
        FROM pois
        WHERE deleted_at IS NULL AND NOT hidden
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
          AND ($5::text[] IS NULL OR category = ANY($5))
          AND ($6::uuid IS NULL OR id > $6)
        ORDER BY id
        LIMIT $7
        "#,
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        cats.as_deref() as Option<&[String]>,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let has_next_page = i64::try_from(found.len()).unwrap_or(i64::MAX) > first;
    let mut nodes = rows(found)?;
    nodes.truncate(usize::try_from(first).unwrap_or(0));
    attach_joins(pool, &mut nodes).await?;
    Ok(PoiPage {
        nodes,
        has_next_page,
    })
}

// Map tiles.

/// Zoom from which a tile carries every point; below it, a tile carries one
/// cluster per category and grid cell.
pub const POINT_MIN_ZOOM: i32 = 13;
/// Cells per tile side in a cluster tile.
pub const CLUSTER_GRID: i32 = 32;
/// Tile extent, in MVT units.
pub const EXTENT: i32 = 4096;
/// Buffer around a point tile, in MVT units: a symbol near an edge is drawn
/// whole by both tiles.
pub const BUFFER: i32 = 64;

/// The vector tile `z/x/y` of the layer, as MVT bytes (empty when the tile
/// holds nothing): every live point from [`POINT_MIN_ZOOM`], in the layer
/// `pois`, at most `max_features`; clusters below it, in `poi_clusters`.
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
    if z >= POINT_MIN_ZOOM {
        let margin = f64::from(BUFFER) / f64::from(EXTENT);
        let bytes = sqlx::query_scalar!(
            r#"
            WITH bounds AS (
                SELECT ST_TileEnvelope($1, $2, $3) AS merc,
                       ST_Transform(ST_TileEnvelope($1, $2, $3, margin => $4), 4326) AS geo
            ),
            features AS (
                SELECT p.id::text AS id, p.category, p.kind, p.name,
                       CASE WHEN p.always_open THEN true END AS "alwaysOpen",
                       CASE WHEN NOT p.always_open THEN p.opening_tile END AS hours,
                       CASE WHEN NOT p.always_open AND p.opening_tile IS NOT NULL
                            THEN floor(extract(epoch FROM p.opening_intervals_until) / 60)::bigint
                       END AS "hoursUntil",
                       CASE WHEN coalesce((f.data -> 'tile' ->> 'lpg')::boolean,
                                          (p.data ->> 'lpg')::boolean)
                            THEN true END AS lpg,
                       CASE WHEN (h.data -> 'tile' ->> 'closed')::boolean THEN true END
                           AS "maybeClosed",
                       ST_AsMVTGeom(ST_Transform(p.geom::geometry, 3857), b.merc, $5, $6, true)
                           AS geom
                FROM pois p
                CROSS JOIN bounds b
                LEFT JOIN poi_join_records f ON f.source_id = 'prix-carburants'
                     AND f.ref = p.fuel_ref AND f.deleted_at IS NULL
                LEFT JOIN poi_join_records h ON h.source_id = 'finess'
                     AND h.ref = p.finess_ref AND h.deleted_at IS NULL
                WHERE p.deleted_at IS NULL AND NOT p.hidden AND p.geom::geometry && b.geo
                ORDER BY p.id
                LIMIT $7
            )
            SELECT coalesce(ST_AsMVT(features, 'pois', $5, 'geom'), ''::bytea) AS "mvt!"
            FROM features
            "#,
            z,
            x,
            y,
            margin,
            EXTENT,
            BUFFER,
            max_features,
        )
        .fetch_one(pool)
        .await?;
        return Ok(bytes);
    }
    let cell_m =
        40_075_016.685_578_5 / f64::from(1_i32 << z.clamp(0, 30)) / f64::from(CLUSTER_GRID);
    let bytes = sqlx::query_scalar!(
        r#"
        WITH bounds AS (
            SELECT ST_TileEnvelope($1, $2, $3) AS merc,
                   ST_Transform(ST_TileEnvelope($1, $2, $3), 4326) AS geo
        ),
        cells AS (
            SELECT p.category, count(*)::int AS count,
                   ST_Centroid(ST_Collect(ST_Transform(p.geom::geometry, 3857))) AS c
            FROM pois p, bounds b
            WHERE p.deleted_at IS NULL AND NOT p.hidden AND p.geom::geometry && b.geo
            GROUP BY p.category, ST_SnapToGrid(ST_Transform(p.geom::geometry, 3857), $4)
        ),
        features AS (
            SELECT c.category, c.count, ST_AsMVTGeom(c.c, b.merc, $5, 0, true) AS geom
            FROM cells c, bounds b
        )
        SELECT coalesce(ST_AsMVT(features, 'poi_clusters', $5, 'geom'), ''::bytea) AS "mvt!"
        FROM features
        "#,
        z,
        x,
        y,
        cell_m,
        EXTENT,
    )
    .fetch_one(pool)
    .await?;
    Ok(bytes)
}

// The community.

/// Stores `account`'s answer to "still there?" about `poi` and queues the
/// point for the worker, which counts the answers under its lock and opens
/// a moderation check for a point it hides.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn confirm(
    pool: &PgPool,
    account: Uuid,
    poi: Uuid,
    still_there: bool,
) -> Result<(Uuid, DateTime<Utc>), DbError> {
    let mut tx = pool.begin().await?;
    let row = sqlx::query!(
        r#"
        INSERT INTO poi_confirmations (id, poi_id, account_id, still_there)
        VALUES ($1, $2, $3, $4) RETURNING id, created_at
        "#,
        Uuid::now_v7(),
        poi,
        account,
        still_there,
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        "INSERT INTO poi_refresh_queue (poi_id) VALUES ($1) ON CONFLICT DO NOTHING",
        poi
    )
    .execute(&mut *tx)
    .await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok((row.id, row.created_at))
}

/// Accounts saying "gone" that hide a point (`05-poi-sources.md` B.4).
pub const GONE_TO_HIDE: i64 = 3;
/// How long an answer counts, in days; older ones are purged.
const ANSWER_DAYS: i32 = 365;

/// Takes the points the API queued, emptying the queue.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn take_refresh_queue(tx: &mut PoiWriterTx) -> Result<Vec<Uuid>, DbError> {
    Ok(
        sqlx::query_scalar!("DELETE FROM poi_refresh_queue RETURNING poi_id")
            .fetch_all(tx.conn())
            .await?,
    )
}

/// Recomputes the community state of `points`, and opens a moderation
/// check for each point the answers hide; the layer is marked when a
/// point appears or disappears. Returns how many points changed.
///
/// A point is hidden while three accounts of level 1 and up, not banned,
/// say it is gone (their latest answer of the year) after the latest
/// "still there" of an account of level 1 and up; while a moderator hides
/// it; or when the account that added it is banned. Counting only level 1
/// and up on both sides keeps a crowd of new accounts from hiding a point,
/// or from keeping a spammer's points up; the answers of the account that
/// added a point do not count on it, so its author cannot hold it up
/// against everyone. `last_confirmed_at`, shown on the card, is the latest
/// "still there" of any account not banned. The check opens only when the
/// answers hide the point: one a moderator hid or a ban took down has
/// nothing to decide, and approving it would undo the decision.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn refresh_community(tx: &mut PoiWriterTx, points: &[Uuid]) -> Result<u64, DbError> {
    if points.is_empty() {
        return Ok(0);
    }
    let changed = sqlx::query!(
        r#"
        WITH answers AS (
            SELECT DISTINCT ON (c.poi_id, c.account_id) c.poi_id, c.account_id, c.still_there,
                   c.created_at, a.trust_level
            FROM poi_confirmations c JOIN accounts a ON a.id = c.account_id
            WHERE c.poi_id = ANY($1) AND c.status = 'published' AND a.banned_at IS NULL
              AND c.created_at > now() - make_interval(days => $2)
              AND NOT EXISTS (SELECT 1 FROM place_submissions s
                              WHERE s.poi_id = c.poi_id AND s.account_id = c.account_id)
            ORDER BY c.poi_id, c.account_id, c.created_at DESC
        ),
        there AS (
            SELECT poi_id, max(created_at) AS last_there,
                   max(created_at) FILTER (WHERE trust_level >= 1) AS last_trusted
            FROM answers WHERE still_there GROUP BY poi_id
        ),
        old AS (
            SELECT id, hidden FROM pois WHERE id = ANY($1)
        ),
        causes AS (
            SELECT ids.id, t.last_there,
                   (SELECT count(*) FROM answers g
                    WHERE g.poi_id = ids.id AND NOT g.still_there AND g.trust_level >= 1
                      AND g.created_at > coalesce(t.last_trusted, '-infinity')) >= $3
                       AS by_answers,
                   EXISTS (SELECT 1 FROM poi_moderation m WHERE m.poi_id = ids.id)
                       AS by_moderator,
                   EXISTS (SELECT 1 FROM place_submissions s
                           JOIN accounts a ON a.id = s.account_id
                           WHERE s.poi_id = ids.id AND a.banned_at IS NOT NULL) AS by_ban
            FROM unnest($1::uuid[]) AS ids(id)
            LEFT JOIN there t ON t.poi_id = ids.id
        ),
        state AS (
            SELECT id, last_there, by_answers, by_moderator, by_ban,
                   by_answers OR by_moderator OR by_ban AS hidden
            FROM causes
        )
        UPDATE pois p SET last_confirmed_at = s.last_there, hidden = s.hidden
        FROM state s JOIN old o ON o.id = s.id
        WHERE p.id = s.id
          AND (p.last_confirmed_at IS DISTINCT FROM s.last_there OR p.hidden <> s.hidden)
        RETURNING p.id, (o.hidden <> s.hidden) AS "flipped!", s.hidden AS "hidden!",
                  (s.by_answers AND NOT s.by_moderator AND NOT s.by_ban) AS "by_answers!"
        "#,
        points,
        ANSWER_DAYS,
        GONE_TO_HIDE,
    )
    .fetch_all(tx.conn())
    .await?;
    let checked: Vec<Uuid> = changed
        .iter()
        .filter(|c| c.flipped && c.hidden && c.by_answers)
        .map(|c| c.id)
        .collect();
    if !checked.is_empty() {
        let ids: Vec<Uuid> = checked.iter().map(|_| Uuid::now_v7()).collect();
        // One open check per point (the queue's unique index): a point
        // hidden again while its check is open adds nothing.
        sqlx::query!(
            r#"
            INSERT INTO moderation_queue (id, kind, target_type, target_id, reason)
            SELECT u.id, 'poi_check', 'poi', u.poi, 'hidden by the community: gone'
            FROM unnest($1::uuid[], $2::uuid[]) AS u(id, poi)
            ON CONFLICT DO NOTHING
            "#,
            &ids,
            &checked,
        )
        .execute(tx.conn())
        .await?;
    }
    if changed.iter().any(|c| c.flipped) {
        mark_layer(tx).await?;
    }
    Ok(u64::try_from(changed.len()).unwrap_or(u64::MAX))
}

/// Deletes the "still there?" answers past their year: they no longer
/// count, and a dated list of where an account was is not kept for
/// nothing. Returns the points they spoke of, whose state may change.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn purge_old_answers(tx: &mut PoiWriterTx) -> Result<Vec<Uuid>, DbError> {
    let mut points = sqlx::query_scalar!(
        r#"
        DELETE FROM poi_confirmations WHERE created_at < now() - make_interval(days => $1)
        RETURNING poi_id
        "#,
        ANSWER_DAYS
    )
    .fetch_all(tx.conn())
    .await?;
    points.sort_unstable();
    points.dedup();
    Ok(points)
}

/// Whether `id` is a point the source still lists, shown or hidden: a
/// hidden point can still be confirmed by someone who finds it.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn exists(pool: &PgPool, id: Uuid) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM pois WHERE id = $1 AND deleted_at IS NULL) AS "e!""#,
        id
    )
    .fetch_one(pool)
    .await?)
}

/// A "still there?" answer as stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PoiConfirmationRow {
    /// Its id.
    pub id: Uuid,
    /// The point.
    pub poi_id: Uuid,
    /// The answer.
    pub still_there: bool,
    /// When.
    pub created_at: DateTime<Utc>,
}

/// Deletes one of `account`'s answers and queues its point; `false` when
/// there is no such answer.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn delete_confirmation(pool: &PgPool, account: Uuid, id: Uuid) -> Result<bool, DbError> {
    let mut tx = pool.begin().await?;
    let poi = sqlx::query_scalar!(
        "DELETE FROM poi_confirmations WHERE id = $1 AND account_id = $2 RETURNING poi_id",
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(poi) = poi else { return Ok(false) };
    sqlx::query!(
        "INSERT INTO poi_refresh_queue (poi_id) VALUES ($1) ON CONFLICT DO NOTHING",
        poi
    )
    .execute(&mut *tx)
    .await?;
    crate::community::notify_worker(&mut tx).await?;
    tx.commit().await?;
    Ok(true)
}

/// A live point of a vending kind within `radius_m` of `at`, if any: a
/// contribution that duplicates it is refused.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn vending_near(
    pool: &PgPool,
    at: Position,
    kind: PoiKind,
    radius_m: f64,
) -> Result<Option<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT id FROM pois
        WHERE deleted_at IS NULL AND NOT hidden AND kind = $3
          AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $4)
        ORDER BY geom <-> ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        LIMIT 1
        "#,
        at.lat(),
        at.lon(),
        kind.code(),
        radius_m,
    )
    .fetch_optional(pool)
    .await?)
}

/// What the worker did with the accepted vending machines.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PoiSubmissionStats {
    /// Points written.
    pub applied: u64,
    /// Submissions refused by the worker's own check.
    pub refused: u64,
}

/// Writes every accepted vending machine as a point of the `community`
/// source (`submission/<id>`), in the POI writer transaction `tx`.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn apply_submissions(tx: &mut PoiWriterTx) -> Result<PoiSubmissionStats, DbError> {
    let pending = sqlx::query!(
        r#"
        SELECT id, payload, created_at FROM place_submissions
        WHERE status = 'accepted' AND kind = 'poi' ORDER BY id FOR UPDATE
        "#
    )
    .fetch_all(tx.conn())
    .await?;
    let mut stats = PoiSubmissionStats::default();
    for s in pending {
        let checked =
            serde_json::from_value::<lunaway_domain::poi::NewVendingMachine>(s.payload.clone())
                .map_err(|e| e.to_string())
                .and_then(|v| lunaway_domain::poi::validate_vending(&v).map_err(|e| e.to_string()));
        let poi = match checked {
            Ok(v) => {
                let record = lunaway_domain::poi::record_of_vending(&v);
                let external_id = format!("submission/{}", s.id);
                upsert_batch(
                    tx,
                    &SourceId::COMMUNITY,
                    &[NewPoi {
                        external_id: &external_id,
                        external_url: None,
                        record: &record,
                        raw: &s.payload,
                        fetched_at: s.created_at,
                        scope: None,
                    }],
                )
                .await?;
                stats.applied += 1;
                sqlx::query_scalar!(
                    "SELECT id FROM pois WHERE source_id = $1 AND external_id = $2",
                    SourceId::COMMUNITY.as_str(),
                    external_id,
                )
                .fetch_optional(tx.conn())
                .await?
            }
            Err(error) => {
                // Written by the API from a checked input: only a change of
                // the stored form or a write that bypassed the API gets
                // here. That one is refused, the others go on.
                tracing::error!(%error, id = %s.id, "a vending machine is refused by the worker");
                stats.refused += 1;
                None
            }
        };
        sqlx::query!(
            r#"
            UPDATE place_submissions SET status = $2, poi_id = $3, applied_at = now(),
                   decided_at = coalesce(decided_at, now())
            WHERE id = $1
            "#,
            s.id,
            if poi.is_some() { "applied" } else { "rejected" },
            poi,
        )
        .execute(tx.conn())
        .await?;
    }
    if stats.applied > 0 {
        mark_layer(tx).await?;
    }
    Ok(stats)
}

/// Counts of the layer, for the operator.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LayerStats {
    /// Live points by source, category and kind.
    pub by_kind: Vec<(String, String, String, i64)>,
    /// Points with hours, with parsed hours, and with intervals from La
    /// Poste.
    pub hours: (i64, i64, i64),
    /// Points carrying a fuel feed id, and those that found their station.
    pub fuel_joined: (i64, i64),
    /// Points carrying a La Poste id, and those that found their site.
    pub laposte_joined: (i64, i64),
    /// Points carrying a FINESS number, and those that found it.
    pub finess_joined: (i64, i64),
    /// Points hidden by the community.
    pub hidden: i64,
}

/// The layer's counts.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn layer_stats(pool: &PgPool) -> Result<LayerStats, DbError> {
    let by_kind = sqlx::query!(
        r#"
        SELECT source_id, category, kind, count(*) AS "n!" FROM pois
        WHERE deleted_at IS NULL GROUP BY 1, 2, 3 ORDER BY 1, 2, 3
        "#
    )
    .fetch_all(pool)
    .await?
    .into_iter()
    .map(|r| (r.source_id, r.category, r.kind, r.n))
    .collect();
    let c = sqlx::query!(
        r#"
        SELECT count(*) FILTER (WHERE opening_hours IS NOT NULL) AS "hours!",
               count(*) FILTER (WHERE opening_hours_parsed) AS "parsed!",
               count(*) FILTER (WHERE opening_source = 'laposte') AS "laposte_hours!",
               count(*) FILTER (WHERE fuel_ref IS NOT NULL) AS "fuel!",
               count(*) FILTER (WHERE fuel_ref IS NOT NULL AND EXISTS (
                   SELECT 1 FROM poi_join_records j WHERE j.source_id = 'prix-carburants'
                     AND j.ref = pois.fuel_ref AND j.deleted_at IS NULL)) AS "fuel_found!",
               count(*) FILTER (WHERE laposte_ref IS NOT NULL) AS "laposte!",
               count(*) FILTER (WHERE laposte_ref IS NOT NULL AND EXISTS (
                   SELECT 1 FROM poi_join_records j WHERE j.source_id = 'laposte'
                     AND j.ref = pois.laposte_ref AND j.deleted_at IS NULL)) AS "laposte_found!",
               count(*) FILTER (WHERE finess_ref IS NOT NULL) AS "finess!",
               count(*) FILTER (WHERE finess_ref IS NOT NULL AND EXISTS (
                   SELECT 1 FROM poi_join_records j WHERE j.source_id = 'finess'
                     AND j.ref = pois.finess_ref AND j.deleted_at IS NULL)) AS "finess_found!",
               count(*) FILTER (WHERE hidden) AS "hidden!"
        FROM pois WHERE deleted_at IS NULL
        "#
    )
    .fetch_one(pool)
    .await?;
    Ok(LayerStats {
        by_kind,
        hours: (c.hours, c.parsed, c.laposte_hours),
        fuel_joined: (c.fuel, c.fuel_found),
        laposte_joined: (c.laposte, c.laposte_found),
        finess_joined: (c.finess, c.finess_found),
        hidden: c.hidden,
    })
}

/// The keys of `source` that live points carry (their fuel feed ids, La
/// Poste ids or FINESS numbers): what an importer of that source keeps.
///
/// # Errors
///
/// [`DbError`] when the query fails, or `source` is not a joined source.
pub async fn join_keys(pool: &PgPool, source: &SourceId) -> Result<Vec<String>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT DISTINCT k AS "k!" FROM (
            SELECT CASE $1
                WHEN 'prix-carburants' THEN fuel_ref
                WHEN 'laposte' THEN laposte_ref
                WHEN 'finess' THEN finess_ref
            END AS k
            FROM pois WHERE deleted_at IS NULL
        ) keys
        WHERE k IS NOT NULL
        ORDER BY 1
        "#,
        source.as_str(),
    )
    .fetch_all(pool)
    .await?)
}

/// Whether `id` is a live point the map shows.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn is_live(pool: &PgPool, id: Uuid) -> Result<bool, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM pois WHERE id = $1 AND deleted_at IS NULL AND NOT hidden) AS "live!""#,
        id
    )
    .fetch_one(pool)
    .await?)
}
