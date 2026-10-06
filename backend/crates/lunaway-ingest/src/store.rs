//! Writing fetched records to the database.

use std::collections::BTreeMap;

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

/// A scope of an extract run holding fewer live records than this is
/// retired without the guard: a share of so few says nothing (a microstate
/// with one campsite that closes goes from 100% to 0%), and refusing it would
/// fail every later run. A truncated file shows in the scopes that hold
/// more.
pub const RETIRE_GUARD_MIN: i64 = 10;

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
            scope,
        })
        .collect();
    let upsert = records::upsert(pool, source, &rows).await?;
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

/// The scope of a record of an extract run: its country, or the part of
/// it another extract holds ([`crate::osm_extract::SPLIT_AREAS`]).
fn country_scope(r: &lunaway_domain::NormalizedRecord) -> Option<String> {
    crate::osm_extract::scope_of(r.position, r.address.country_code.as_deref())
}

/// Inserts or updates the records of one extract of a run, each under the
/// scope of its country, without retiring anything: the run retires once
/// every extract is read ([`retire_in_coverage`]).
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn upsert_by_country(
    pool: &PgPool,
    source: &SourceId,
    fetched: &[FetchedRecord],
) -> Result<records::UpsertStats, IngestError> {
    let scopes: Vec<Option<String>> = fetched.iter().map(|f| country_scope(&f.record)).collect();
    let rows: Vec<NewRecord<'_>> = fetched
        .iter()
        .zip(&scopes)
        .map(|(f, scope)| NewRecord {
            external_id: &f.external_id,
            external_url: f.external_url.as_deref(),
            record: &f.record,
            raw: &f.raw,
            fetched_at: f.fetched_at,
            scope: scope.as_deref(),
        })
        .collect();
    Ok(records::upsert(pool, source, &rows).await?)
}

/// What a retirement at the end of a run did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Retirement {
    /// Records or points retired.
    pub retired: u64,
    /// The scopes left alone by [`RETIRE_GUARD_PERCENT`]: the run saw less
    /// than half of what is stored there (a truncated file?).
    pub refused: Vec<String>,
}

/// The scopes `coverage` speaks for whose share of the run passes the
/// truncation guard, and those that do not. Each country is judged on its
/// own: France as one extract of twenty-four would otherwise hide behind
/// the others. A scope below [`RETIRE_GUARD_MIN`] always passes.
fn guarded(
    coverage: &crate::osm_extract::Coverage,
    seen_by_scope: &BTreeMap<String, usize>,
    stored: &BTreeMap<String, i64>,
) -> (Vec<String>, Vec<String>) {
    let scopes: Vec<String> = coverage
        .scopes()
        .unwrap_or_else(|| stored.keys().chain(seen_by_scope.keys()).cloned().collect());
    let scopes: std::collections::BTreeSet<String> = scopes.into_iter().collect();
    scopes.into_iter().partition(|s| {
        let stored = stored.get(s).copied().unwrap_or(0);
        stored < RETIRE_GUARD_MIN || !truncated(seen_by_scope.get(s).copied().unwrap_or(0), stored)
    })
}

/// Retires the records of `source` in the scopes `coverage` speaks for that
/// the run did not see, scope by scope, unless the run saw less than
/// [`RETIRE_GUARD_PERCENT`] of what is stored in a scope.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn retire_in_coverage(
    pool: &PgPool,
    source: &SourceId,
    coverage: &crate::osm_extract::Coverage,
    seen: &[String],
    seen_by_scope: &BTreeMap<String, usize>,
    at: chrono::DateTime<chrono::Utc>,
) -> Result<Retirement, IngestError> {
    let stored = records::live_counts_by_scope(pool, source).await?;
    let (passing, refused) = guarded(coverage, seen_by_scope, &stored);
    warn_refused(source, &refused, seen_by_scope, &stored);
    let retired = if passing.is_empty() {
        0
    } else if refused.is_empty() && coverage.scopes().is_none() {
        // A continent speaks for the whole source, whatever scope a record
        // was stored under.
        records::retire_missing_in_source(pool, source, seen, at).await?
    } else {
        records::retire_missing_in_scopes(pool, source, &passing, seen, at).await?
    };
    Ok(Retirement { retired, refused })
}

fn warn_refused(
    source: &SourceId,
    refused: &[String],
    seen_by_scope: &BTreeMap<String, usize>,
    stored: &BTreeMap<String, i64>,
) {
    for scope in refused {
        tracing::warn!(
            source = %source,
            scope,
            seen = seen_by_scope.get(scope).copied().unwrap_or(0),
            stored = stored.get(scope).copied().unwrap_or(0),
            "the run holds less than half of the stored ones of this scope; none retired there"
        );
    }
}

/// Inserts or updates the points of one extract of a run, each under the
/// scope of its country, without retiring anything; marks the layer when a
/// point changed.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn upsert_pois_by_country(
    pool: &PgPool,
    source: &SourceId,
    points: &[crate::poi_osm::FetchedPoi],
) -> Result<records::UpsertStats, IngestError> {
    let scopes: Vec<Option<String>> = points
        .iter()
        .map(|p| {
            crate::osm_extract::scope_of(
                p.record.position,
                p.record.address.country_code.as_deref(),
            )
        })
        .collect();
    let rows: Vec<lunaway_db::pois::NewPoi<'_>> = points
        .iter()
        .zip(&scopes)
        .map(|(p, scope)| lunaway_db::pois::NewPoi {
            external_id: &p.external_id,
            external_url: p.external_url.as_deref(),
            record: &p.record,
            raw: &p.raw,
            fetched_at: p.fetched_at,
            scope: scope.as_deref(),
        })
        .collect();
    let upsert = lunaway_db::pois::upsert(pool, source, &rows).await?;
    if upsert.inserted + upsert.changed > 0 {
        lunaway_db::pois::mark_layer_now(pool).await?;
    }
    Ok(upsert)
}

/// Retires the points of `source` in the countries `coverage` speaks for
/// that the run did not see, unless the run saw less than
/// [`RETIRE_GUARD_PERCENT`] of what is stored there; marks the layer when
/// a point went.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn retire_pois_in_coverage(
    pool: &PgPool,
    source: &SourceId,
    coverage: &crate::osm_extract::Coverage,
    seen: &[String],
    seen_by_scope: &BTreeMap<String, usize>,
    at: chrono::DateTime<chrono::Utc>,
) -> Result<Retirement, IngestError> {
    let stored = lunaway_db::pois::live_counts_by_scope(pool, source).await?;
    let (passing, refused) = guarded(coverage, seen_by_scope, &stored);
    warn_refused(source, &refused, seen_by_scope, &stored);
    let retired = if passing.is_empty() {
        0
    } else if refused.is_empty() && coverage.scopes().is_none() {
        lunaway_db::pois::retire_missing(pool, source, None, seen, at).await?
    } else {
        lunaway_db::pois::retire_missing(pool, source, Some(&passing), seen, at).await?
    };
    if retired > 0 {
        lunaway_db::pois::mark_layer_now(pool).await?;
    }
    Ok(Retirement { retired, refused })
}

/// The scope of each point, as an extract run stores it.
#[must_use]
pub fn poi_scope(p: &crate::poi_osm::FetchedPoi) -> Option<String> {
    crate::osm_extract::scope_of(p.record.position, p.record.address.country_code.as_deref())
}

/// The scope of each record, as an extract run stores it.
#[must_use]
pub fn record_scope(r: &FetchedRecord) -> Option<String> {
    country_scope(&r.record)
}

/// How many of `scopes` fall in each scope (no scope counts as French, as
/// for the points imported before scopes existed).
#[must_use]
pub fn count_scopes(scopes: impl IntoIterator<Item = Option<String>>) -> BTreeMap<String, usize> {
    let mut out = BTreeMap::new();
    for s in scopes {
        *out.entry(s.unwrap_or_else(|| "FR".to_owned())).or_insert(0) += 1;
    }
    out
}

/// Stores `points` as the complete content of `source` in the POI layer,
/// whatever their countries: points are inserted or updated, and the stored
/// points the fetch did not contain are retired, unless the fetch looks
/// truncated ([`RETIRE_GUARD_PERCENT`]). An extract run retires by country
/// instead ([`crate::extract_run`]).
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn store_pois(
    pool: &PgPool,
    source: &SourceId,
    points: &[crate::poi_osm::FetchedPoi],
) -> Result<StoreReport, IngestError> {
    let upsert = upsert_pois_by_country(pool, source, points).await?;
    let seen: Vec<String> = points.iter().map(|p| p.external_id.clone()).collect();
    let at = points
        .iter()
        .map(|p| p.fetched_at)
        .max()
        .unwrap_or_else(chrono::Utc::now);
    let by_scope = count_scopes(points.iter().map(poi_scope));
    let r = retire_pois_in_coverage(
        pool,
        source,
        &crate::osm_extract::Coverage::Everywhere,
        &seen,
        &by_scope,
        at,
    )
    .await?;
    Ok(StoreReport {
        upsert,
        retired: r.retired,
        retire_refused: !r.refused.is_empty(),
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
            lunaway_db::pois::mark_layer_now(pool).await?;
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
        lunaway_db::pois::mark_layer_now(pool).await?;
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::osm_extract::Coverage;

    #[test]
    fn a_scope_too_small_for_a_share_is_retired_without_the_guard() {
        let coverage = Coverage::Countries(["FR", "GI", "DE"].map(String::from).into());
        let seen = BTreeMap::from([("FR".to_owned(), 3), ("DE".to_owned(), 9)]);
        let stored = BTreeMap::from([
            ("FR".to_owned(), 10),
            ("GI".to_owned(), 1),
            ("DE".to_owned(), 10),
        ]);
        let (passing, refused) = guarded(&coverage, &seen, &stored);
        assert_eq!(
            refused,
            ["FR"],
            "3 of 10 looks truncated; Gibraltar's only campsite closing does not"
        );
        assert_eq!(passing, ["DE", "GI"]);
    }
}
