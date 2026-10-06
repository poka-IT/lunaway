//! Writing fetched records to the database.

use lunaway_db::{
    PgPool,
    records::{self, NewRecord, UpsertStats},
};
use lunaway_domain::SourceId;

use crate::{FetchedRecord, IngestError};

/// A run may retire the records it did not see only if it saw at least this
/// percentage of the records already stored for its scope. A truncated
/// answer (an instance returning a partial result without saying so, an
/// empty CSV) would otherwise delete real places.
pub const RETIRE_GUARD_PERCENT: u64 = 50;

/// What a store did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct StoreReport {
    /// Inserted, changed, unchanged.
    pub upsert: UpsertStats,
    /// Records retired because the source no longer lists them.
    pub retired: u64,
    /// Whether retiring was skipped by [`RETIRE_GUARD_PERCENT`].
    pub retire_refused: bool,
}

/// Which stored records a complete fetch speaks for.
#[derive(Debug, Clone, Copy)]
enum Covers<'a> {
    /// The records of one scope (an Overpass region, or no scope).
    Scope(Option<&'a str>),
    /// Every record of the source, whatever its scope (a country extract).
    Source,
}

/// Stores `fetched` as the complete content of `source` in `scope`: records
/// are inserted or updated, and the stored records of that scope the fetch
/// did not contain are retired, unless the fetch looks truncated.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn store_complete(
    pool: &PgPool,
    source: &SourceId,
    scope: Option<&str>,
    fetched: &[FetchedRecord],
) -> Result<StoreReport, IngestError> {
    store(pool, source, scope, Covers::Scope(scope), fetched).await
}

/// Stores `fetched` as the complete content of `source`, tagged with
/// `scope`: the records of any scope the fetch did not contain are retired,
/// unless the fetch looks truncated.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn store_whole_source(
    pool: &PgPool,
    source: &SourceId,
    scope: &str,
    fetched: &[FetchedRecord],
) -> Result<StoreReport, IngestError> {
    store(pool, source, Some(scope), Covers::Source, fetched).await
}

async fn store(
    pool: &PgPool,
    source: &SourceId,
    scope: Option<&str>,
    covers: Covers<'_>,
    fetched: &[FetchedRecord],
) -> Result<StoreReport, IngestError> {
    let before = match covers {
        Covers::Scope(s) => records::live_count(pool, source, s).await?,
        Covers::Source => records::live_count(pool, source, None).await?,
    };
    let rows: Vec<NewRecord<'_>> = fetched
        .iter()
        .map(|f| NewRecord {
            external_id: &f.external_id,
            external_url: f.external_url.as_deref(),
            record: &f.record,
            raw: &f.raw,
            fetched_at: f.fetched_at,
        })
        .collect();
    let upsert = records::upsert(pool, source, scope, &rows).await?;
    if truncated(fetched.len(), before) {
        tracing::warn!(
            source = %source,
            scope,
            seen = fetched.len(),
            stored = before,
            "the fetch holds less than half of the stored records; nothing is retired"
        );
        return Ok(StoreReport {
            upsert,
            retired: 0,
            retire_refused: true,
        });
    }
    let seen: Vec<String> = fetched.iter().map(|f| f.external_id.clone()).collect();
    let at = fetched
        .iter()
        .map(|f| f.fetched_at)
        .max()
        .unwrap_or_else(chrono::Utc::now);
    let retired = match covers {
        Covers::Scope(s) => records::retire_missing(pool, source, s, &seen, at).await?,
        Covers::Source => records::retire_missing_in_source(pool, source, &seen, at).await?,
    };
    Ok(StoreReport {
        upsert,
        retired,
        retire_refused: false,
    })
}

/// Stores `points` as the complete content of `source` in the POI layer:
/// points are inserted or updated, and the stored points the fetch did not
/// contain are retired, unless the fetch looks truncated
/// ([`RETIRE_GUARD_PERCENT`]).
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn store_pois(
    pool: &PgPool,
    source: &SourceId,
    points: &[crate::poi_osm::FetchedPoi],
) -> Result<StoreReport, IngestError> {
    let before = lunaway_db::pois::live_count(pool, source).await?;
    let rows: Vec<lunaway_db::pois::NewPoi<'_>> = points
        .iter()
        .map(|p| lunaway_db::pois::NewPoi {
            external_id: &p.external_id,
            external_url: p.external_url.as_deref(),
            record: &p.record,
            raw: &p.raw,
            fetched_at: p.fetched_at,
        })
        .collect();
    let upsert = lunaway_db::pois::upsert(pool, source, &rows).await?;
    if truncated(points.len(), before) {
        if upsert.inserted + upsert.changed > 0 {
            lunaway_db::pois::bump_layer_now(pool).await?;
        }
        tracing::warn!(
            source = %source,
            seen = points.len(),
            stored = before,
            "the fetch holds less than half of the stored points; nothing is retired"
        );
        return Ok(StoreReport {
            upsert,
            retired: 0,
            retire_refused: true,
        });
    }
    let seen: Vec<String> = points.iter().map(|p| p.external_id.clone()).collect();
    let at = points
        .iter()
        .map(|p| p.fetched_at)
        .max()
        .unwrap_or_else(chrono::Utc::now);
    let retired = lunaway_db::pois::retire_missing(pool, source, &seen, at).await?;
    // Once for the whole import: every device fetches its tiles again.
    if upsert.inserted + upsert.changed + retired > 0 {
        lunaway_db::pois::bump_layer_now(pool).await?;
    }
    Ok(StoreReport {
        upsert,
        retired,
        retire_refused: false,
    })
}

/// What a store of joined rows did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct JoinStoreReport {
    /// Inserted, changed, unchanged, and the rows whose tile part changed.
    pub upsert: lunaway_db::pois::JoinStats,
    /// Rows retired because the source no longer lists them.
    pub retired: u64,
    /// Whether retiring was skipped by [`RETIRE_GUARD_PERCENT`].
    pub retire_refused: bool,
}

/// Stores `rows` as the complete content of the joined `source`: rows are
/// inserted or updated, and the stored rows the fetch did not contain are
/// retired, unless the fetch looks truncated ([`RETIRE_GUARD_PERCENT`]).
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn store_joins(
    pool: &PgPool,
    source: &SourceId,
    rows: &[lunaway_db::pois::NewJoin<'_>],
) -> Result<JoinStoreReport, IngestError> {
    let before = lunaway_db::pois::live_join_count(pool, source).await?;
    let upsert = lunaway_db::pois::upsert_joins(pool, source, rows).await?;
    if truncated(rows.len(), before) {
        if upsert.tile_changes > 0 {
            lunaway_db::pois::bump_layer_now(pool).await?;
        }
        tracing::warn!(
            source = %source,
            seen = rows.len(),
            stored = before,
            "the fetch holds less than half of the stored rows; nothing is retired"
        );
        return Ok(JoinStoreReport {
            upsert,
            retired: 0,
            retire_refused: true,
        });
    }
    let seen: Vec<String> = rows.iter().map(|r| r.key.to_owned()).collect();
    let at = rows
        .iter()
        .map(|r| r.fetched_at)
        .max()
        .unwrap_or_else(chrono::Utc::now);
    let (retired, retired_on_tile) =
        lunaway_db::pois::retire_missing_joins(pool, source, &seen, at).await?;
    if upsert.tile_changes > 0 || retired_on_tile {
        lunaway_db::pois::bump_layer_now(pool).await?;
    }
    Ok(JoinStoreReport {
        upsert,
        retired,
        retire_refused: false,
    })
}

/// Whether a fetch of `seen` rows against `stored` live ones looks
/// truncated.
fn truncated(seen: usize, stored: i64) -> bool {
    let seen = u64::try_from(seen).unwrap_or(u64::MAX);
    let stored = u64::try_from(stored).unwrap_or(0);
    seen.saturating_mul(100) < stored.saturating_mul(RETIRE_GUARD_PERCENT)
}
