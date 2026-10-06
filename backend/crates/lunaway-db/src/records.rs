//! What each source says: `source_records`, written by the ingestion.
//!
//! A record is keyed by its source and external id and keeps its UUID
//! across imports, so the places, pairs and human constraints that point to
//! it survive a re-import. It is flagged for the conflation when its
//! normalised content changes, when it disappears from the source, or when a
//! person adds a constraint on it.
//!
//! An import writes a record only when it changed; the date of each
//! complete read goes to `source_reads` ([`mark_read`]), and every query
//! that serves a record's date reads it through `lunaway_read_at`, which
//! gives a live record the later of the two. A record retired keeps the
//! date of the last read that held it.
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
    /// The slice of the source it belongs to (an Overpass region, a
    /// country of an extract), which a later run of that slice may retire.
    pub scope: Option<&'a str>,
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

/// Inserts or updates `records` of `source`, each tagged with its scope;
/// a record whose content did not change is left as it is, its date too.
/// A run that read a slice of the source whole calls [`mark_read`] once it
/// retired what it did not see (`lunaway_ingest::store` does), or clients
/// see the date of the last change instead of the last read.
///
/// # Errors
///
/// [`DbError`] when a statement fails; the batches already written stay.
pub async fn upsert(
    pool: &PgPool,
    source: &SourceId,
    records: &[NewRecord<'_>],
) -> Result<UpsertStats, DbError> {
    let mut stats = UpsertStats::default();
    for batch in records.chunks(BATCH) {
        stats += upsert_batch(pool, source, batch).await?;
    }
    Ok(stats)
}

async fn upsert_batch(
    pool: &PgPool,
    source: &SourceId,
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
    let mut scopes: Vec<Option<String>> = Vec::with_capacity(n);
    for r in batch {
        scopes.push(r.scope.map(str::to_owned));
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
    // A row is written only when the source says something new of it: a
    // rewrite of every row at each import doubled the table until the next
    // vacuum. The date of the read itself goes to `source_reads` once per
    // slice ([`mark_read`]). A taken-down record is never written again.
    // `now()` is the transaction start: a row whose `changed_at` equals it
    // was inserted or changed by this statement.
    let rows = sqlx::query!(
        r#"
        INSERT INTO source_records AS sr
            (id, source_id, external_id, external_url, kind, name, geom, accuracy_m, data, raw,
             scope, fetched_at)
        SELECT u.id, $1, u.external_id, u.external_url, u.kind, u.name,
               ST_SetSRID(ST_MakePoint(u.lon, u.lat), 4326)::geography, u.accuracy_m, u.data,
               u.raw, u.scope, u.fetched_at
        FROM UNNEST($2::text[], $3::uuid[], $4::text[], $5::text[], $6::text[], $7::text[],
                    $8::float8[], $9::float8[], $10::float8[], $11::jsonb[], $12::jsonb[],
                    $13::timestamptz[])
             AS u(scope, id, external_id, external_url, kind, name, lat, lon, accuracy_m, data,
                  raw, fetched_at)
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
        WHERE sr.taken_down_at IS NULL
          AND (sr.deleted_at IS NOT NULL
               OR sr.data IS DISTINCT FROM EXCLUDED.data
               OR sr.raw IS DISTINCT FROM EXCLUDED.raw
               OR sr.external_url IS DISTINCT FROM EXCLUDED.external_url
               OR sr.scope IS DISTINCT FROM EXCLUDED.scope)
        RETURNING (xmax = 0) AS "inserted!", (changed_at = now()) AS "touched!"
        "#,
        source.as_str(),
        &scopes as &[Option<String>],
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
    Ok(UpsertStats::of(
        n,
        rows.iter().map(|r| (r.inserted, r.touched)),
    ))
}

impl UpsertStats {
    /// The stats of an upsert of `n` rows from the rows it returned
    /// (inserted, content changed): a row it left alone returns nothing,
    /// and one rewritten for its raw payload or scope alone is unchanged.
    pub(crate) fn of(n: usize, returned: impl IntoIterator<Item = (bool, bool)>) -> Self {
        let mut stats = Self::default();
        for (inserted, touched) in returned {
            if inserted {
                stats.inserted += 1;
            } else if touched {
                stats.changed += 1;
            }
        }
        let n = u64::try_from(n).unwrap_or(u64::MAX);
        stats.unchanged = n.saturating_sub(stats.inserted + stats.changed);
        stats
    }
}

/// Which table a read of a source fed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReadTarget {
    /// `source_records`, the places' records.
    Records,
    /// `pois`, the points of interest.
    Pois,
}

impl ReadTarget {
    fn code(self) -> &'static str {
        match self {
            Self::Records => "records",
            Self::Pois => "pois",
        }
    }
}

/// The `source_reads` scope of a read of the whole source.
pub const WHOLE_SOURCE: &str = "*";

/// Records that `source` was read whole, for `target`, in each of `reads`
/// (a scope as its rows carry it, `""` for the rows without one,
/// [`WHOLE_SOURCE`] for all, and the date of that read): every live row of
/// such a scope was in the read, so its clients see that date
/// (`lunaway_read_at` in SQL). Call it once the run retired what it did not
/// see, never for a scope whose retirement was refused. A date never goes
/// back: a run that read an older file changes nothing.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn mark_read(
    pool: &PgPool,
    target: ReadTarget,
    source: &SourceId,
    reads: &[(String, DateTime<Utc>)],
) -> Result<(), DbError> {
    if reads.is_empty() {
        return Ok(());
    }
    let (scopes, dates): (Vec<String>, Vec<DateTime<Utc>>) = reads.iter().cloned().unzip();
    sqlx::query!(
        r#"
        INSERT INTO source_reads AS r (target, source_id, scope, read_at)
        SELECT $1, $2, u.scope, u.read_at
        FROM UNNEST($3::text[], $4::timestamptz[]) AS u(scope, read_at)
        ON CONFLICT (target, source_id, scope) DO UPDATE
        SET read_at = greatest(r.read_at, EXCLUDED.read_at)
        "#,
        target.code(),
        source.as_str(),
        &scopes,
        &dates,
    )
    .execute(pool)
    .await?;
    Ok(())
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
        SET deleted_at = $4, needs_conflation = true, changed_at = now(),
            fetched_at = lunaway_read_at('records', source_id, scope, fetched_at, NULL)
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
        SET deleted_at = $3, needs_conflation = true, changed_at = now(),
            fetched_at = lunaway_read_at('records', source_id, scope, fetched_at, NULL)
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

/// Live records of `source` by scope. A record stored without a scope
/// counts as French, as in [`retire_missing_in_scopes`]: France was the
/// only country imported before scopes, and a run counts what it sees the
/// same way.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_counts_by_scope(
    pool: &PgPool,
    source: &SourceId,
) -> Result<std::collections::BTreeMap<String, i64>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT coalesce(scope, 'FR') AS "scope!", count(*) AS "n!" FROM source_records
        WHERE source_id = $1 AND deleted_at IS NULL
        GROUP BY 1
        "#,
        source.as_str(),
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| (r.scope, r.n)).collect())
}

/// Marks as deleted the live records of `source` in any of `scopes` whose
/// external id is not in `seen`: for a run of several country extracts,
/// which speaks for those countries and no other. A record without a scope
/// counts as French. Returns how many.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn retire_missing_in_scopes(
    pool: &PgPool,
    source: &SourceId,
    scopes: &[String],
    seen: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    let mut tx = crate::begin_locked(pool).await?;
    let done = sqlx::query!(
        r#"
        UPDATE source_records
        SET deleted_at = $4, needs_conflation = true, changed_at = now(),
            fetched_at = lunaway_read_at('records', source_id, scope, fetched_at, NULL)
        WHERE source_id = $1 AND deleted_at IS NULL AND coalesce(scope, 'FR') = ANY($2)
          AND NOT (external_id = ANY($3))
        "#,
        source.as_str(),
        scopes,
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
    // A taken-down record is empty and unlinked for good: nothing to
    // conflate.
    let done = sqlx::query!(
        "UPDATE source_records SET needs_conflation = true \
         WHERE NOT needs_conflation AND taken_down_at IS NULL"
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
        "UPDATE source_records SET needs_conflation = true \
         WHERE id = ANY($1) AND taken_down_at IS NULL",
        &[lo, hi][..],
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}
