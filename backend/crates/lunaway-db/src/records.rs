//! What each source says: `source_records`, written by the ingestion.
//!
//! A record is keyed by its source and external id and keeps its UUID
//! across imports, so the places, pairs and human constraints that point to
//! it survive a re-import. It is flagged for the conflation when its
//! normalised content changes, when it disappears from the source, or when a
//! person adds a constraint on it.
//!
//! Every write holds the writers' lock for its transaction, like the
//! conflation: the conflation locks the flagged records in id order, a
//! statement here in its own order, and two such transactions running at
//! once could each wait for the other.

use chrono::{DateTime, Utc};
use lunaway_domain::{NormalizedRecord, SourceId, conflation::ConstraintKind};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// A record to insert or update.
#[derive(Debug, Clone, Copy)]
pub struct NewRecord<'a> {
    /// Identifier in the source.
    pub external_id: &'a str,
    /// Page at the source.
    pub external_url: Option<&'a str>,
    /// Normalised content.
    pub record: &'a NormalizedRecord,
    /// Payload as received.
    pub raw: &'a serde_json::Value,
    /// When it was read.
    pub fetched_at: DateTime<Utc>,
}

/// What an upsert did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct UpsertStats {
    /// New records.
    pub inserted: u64,
    /// Records whose content changed, or that came back after a deletion.
    pub changed: u64,
    /// Records seen again as they were.
    pub unchanged: u64,
}

impl std::ops::AddAssign for UpsertStats {
    fn add_assign(&mut self, o: Self) {
        self.inserted += o.inserted;
        self.changed += o.changed;
        self.unchanged += o.unchanged;
    }
}

/// Rows per statement: large enough to amortise the round trip, small
/// enough to keep each statement's parameter arrays in the low megabytes.
const BATCH: usize = 1_000;

/// Inserts or updates `records` of `source`, each tagged with `scope`.
///
/// # Errors
///
/// [`DbError`] when a statement fails; the batches already written stay.
pub async fn upsert(
    pool: &PgPool,
    source: &SourceId,
    scope: Option<&str>,
    records: &[NewRecord<'_>],
) -> Result<UpsertStats, DbError> {
    let mut stats = UpsertStats::default();
    for batch in records.chunks(BATCH) {
        stats += upsert_batch(pool, source, scope, batch).await?;
    }
    Ok(stats)
}

async fn upsert_batch(
    pool: &PgPool,
    source: &SourceId,
    scope: Option<&str>,
    batch: &[NewRecord<'_>],
) -> Result<UpsertStats, DbError> {
    let n = batch.len();
    let mut ids = Vec::with_capacity(n);
    let mut external_ids = Vec::with_capacity(n);
    let mut urls: Vec<Option<String>> = Vec::with_capacity(n);
    let mut kinds = Vec::with_capacity(n);
    let mut names: Vec<Option<String>> = Vec::with_capacity(n);
    let mut lats = Vec::with_capacity(n);
    let mut lons = Vec::with_capacity(n);
    let mut accuracies = Vec::with_capacity(n);
    let mut data = Vec::with_capacity(n);
    let mut raws = Vec::with_capacity(n);
    let mut fetched = Vec::with_capacity(n);
    for r in batch {
        ids.push(Uuid::now_v7());
        external_ids.push(r.external_id.to_owned());
        urls.push(r.external_url.map(str::to_owned));
        kinds.push(r.record.kind.code().to_owned());
        names.push(r.record.name.clone());
        lats.push(r.record.position.lat());
        lons.push(r.record.position.lon());
        accuracies.push(r.record.accuracy_m.max(0.0));
        data.push(serde_json::to_value(r.record).map_err(|e| DbError::decode("record", e))?);
        raws.push(r.raw.clone());
        fetched.push(r.fetched_at);
    }
    let mut tx = crate::begin_locked(pool).await?;
    // `now()` is the transaction start: a row whose `changed_at` equals it
    // was inserted or changed by this statement.
    let rows = sqlx::query!(
        r#"
        INSERT INTO source_records AS sr
            (id, source_id, external_id, external_url, kind, name, geom, accuracy_m, data, raw,
             scope, fetched_at)
        SELECT u.id, $1, u.external_id, u.external_url, u.kind, u.name,
               ST_SetSRID(ST_MakePoint(u.lon, u.lat), 4326)::geography, u.accuracy_m, u.data,
               u.raw, $2, u.fetched_at
        FROM UNNEST($3::uuid[], $4::text[], $5::text[], $6::text[], $7::text[], $8::float8[],
                    $9::float8[], $10::float8[], $11::jsonb[], $12::jsonb[], $13::timestamptz[])
             AS u(id, external_id, external_url, kind, name, lat, lon, accuracy_m, data, raw,
                  fetched_at)
        ON CONFLICT (source_id, external_id) DO UPDATE SET
            external_url = EXCLUDED.external_url,
            kind = EXCLUDED.kind,
            name = EXCLUDED.name,
            geom = EXCLUDED.geom,
            accuracy_m = EXCLUDED.accuracy_m,
            data = EXCLUDED.data,
            raw = EXCLUDED.raw,
            scope = EXCLUDED.scope,
            fetched_at = EXCLUDED.fetched_at,
            changed_at = CASE
                WHEN sr.data IS DISTINCT FROM EXCLUDED.data OR sr.deleted_at IS NOT NULL
                THEN now() ELSE sr.changed_at END,
            needs_conflation = sr.needs_conflation
                OR sr.data IS DISTINCT FROM EXCLUDED.data
                OR sr.deleted_at IS NOT NULL,
            deleted_at = NULL
        RETURNING (xmax = 0) AS "inserted!", (changed_at = now()) AS "touched!"
        "#,
        source.as_str(),
        scope,
        &ids,
        &external_ids,
        &urls as &[Option<String>],
        &kinds,
        &names as &[Option<String>],
        &lats,
        &lons,
        &accuracies,
        &data,
        &raws,
        &fetched,
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
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

/// Live records of `source` in `scope` (all scopes when `None`).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_count(
    pool: &PgPool,
    source: &SourceId,
    scope: Option<&str>,
) -> Result<i64, DbError> {
    let n = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM source_records
        WHERE source_id = $1 AND deleted_at IS NULL AND ($2::text IS NULL OR scope = $2)
        "#,
        source.as_str(),
        scope,
    )
    .fetch_one(pool)
    .await?;
    Ok(n)
}

/// Marks as deleted the live records of `source` in `scope` (or with no
/// scope, when `None`) whose external id is not in `seen`: the source no
/// longer lists them. Returns how many.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn retire_missing(
    pool: &PgPool,
    source: &SourceId,
    scope: Option<&str>,
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let done = sqlx::query!(
        r#"
        UPDATE source_records
        SET deleted_at = $4, needs_conflation = true, changed_at = now()
        WHERE source_id = $1
          AND deleted_at IS NULL
          AND (($2::text IS NULL AND scope IS NULL) OR scope = $2)
          AND NOT (external_id = ANY($3))
        "#,
        source.as_str(),
        scope,
        seen,
        at,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}

/// Marks as deleted the live records of `source`, in any scope, whose
/// external id is not in `seen`: for a fetch that covers the whole source
/// (a country extract), whatever slices earlier runs used. Returns how many.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn retire_missing_in_source(
    pool: &PgPool,
    source: &SourceId,
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let done = sqlx::query!(
        r#"
        UPDATE source_records
        SET deleted_at = $3, needs_conflation = true, changed_at = now()
        WHERE source_id = $1 AND deleted_at IS NULL AND NOT (external_id = ANY($2))
        "#,
        source.as_str(),
        seen,
        at,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}

/// Flags every record for the conflation, for a full rebuild.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn mark_all_dirty(pool: &PgPool) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let done = sqlx::query!(
        "UPDATE source_records SET needs_conflation = true WHERE NOT needs_conflation"
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(done.rows_affected())
}

/// The id of a record, by source and external id.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn id_of(
    pool: &PgPool,
    source: &SourceId,
    external_id: &str,
) -> Result<Option<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        "SELECT id FROM source_records WHERE source_id = $1 AND external_id = $2",
        source.as_str(),
        external_id,
    )
    .fetch_optional(pool)
    .await?)
}

/// Records a human decision on two records, replacing an earlier one on the
/// same pair, and flags both for the conflation.
///
/// # Errors
///
/// [`DbError`] when a statement fails or a record does not exist.
pub async fn set_constraint(
    pool: &PgPool,
    a: Uuid,
    b: Uuid,
    kind: ConstraintKind,
    reason: Option<&str>,
) -> Result<(), DbError> {
    let (lo, hi) = if a < b { (a, b) } else { (b, a) };
    let mut tx = crate::begin_locked(pool).await?;
    sqlx::query!(
        r#"
        INSERT INTO conflation_constraints (id, record_a, record_b, kind, reason)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (record_a, record_b) DO UPDATE
        SET kind = EXCLUDED.kind, reason = EXCLUDED.reason, created_at = now()
        "#,
        Uuid::now_v7(),
        lo,
        hi,
        kind.code(),
        reason,
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE source_records SET needs_conflation = true WHERE id = ANY($1)",
        &[lo, hi][..],
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}
