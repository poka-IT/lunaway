//! Imports of several extracts in one run: the places or the points of
//! interest of France and its neighbours, country by country
//! ([`crate::osm_extract::EUROPE`]).
//!
//! One extract is downloaded (or read from the cache), read and stored at a
//! time, so the memory a run needs is the largest country's, not the sum.
//! The same element read from two extracts (Geofabrik cuts each country
//! with a margin) is stored once, from the first. Once every extract is
//! stored, the records of the run's countries it did not see are retired
//! ([`crate::store::retire_in_coverage`]); a country outside the run keeps
//! its records.
//!
//! A run is resumable: after each extract it writes what it stored to the
//! cache (`osm-extract/runs/`), so a run that stopped half way (a crash, a
//! reboot, the memory cap) starts again after the last extract it stored,
//! unless that extract's file changed in between; the downloads resume on
//! their own ([`crate::osm_extract::fetch`]).

use std::collections::HashSet;

use chrono::{DateTime, Utc};
use lunaway_db::{PgPool, records::UpsertStats};
use lunaway_domain::SourceId;
use serde::{Deserialize, Serialize};

use crate::{
    IngestError,
    cache::Cache,
    http::RetryPolicy,
    osm_extract::{self, Area, Coverage, ExtractSpec, Refresh},
    store::{self, Retirement},
};

/// What a run imports from the extracts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Layer {
    /// The places (`ingest osm-extract`).
    Places,
    /// The points of interest (`ingest pois`).
    Pois,
}

impl Layer {
    fn key(self) -> &'static str {
        match self {
            Self::Places => "places",
            Self::Pois => "pois",
        }
    }
}

/// How a run fetches its extracts.
#[derive(Debug, Clone)]
pub struct ExtractPlan {
    /// The extracts, in order: an element in two of them comes from the
    /// first.
    pub extracts: Vec<ExtractSpec>,
    /// Where they are downloaded from ([`osm_extract::GEOFABRIK`]).
    pub mirror: String,
    /// When a cached file is downloaded again.
    pub refresh: Refresh,
}

/// What one extract of a run gave.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtractReport {
    /// The extract.
    pub name: &'static str,
    /// Whether its file came from the cache.
    pub cached: bool,
    /// Whether a run that stopped had already stored it: it was not read
    /// again.
    pub resumed: bool,
    /// Records or points mapped, those of another extract left out.
    pub records: usize,
    /// Elements outside the run's countries, or dropped by the mapping.
    pub skipped: usize,
    /// Elements another extract of the run already gave.
    pub duplicates: usize,
    /// Dump stations folded into their site (places only).
    pub attached_dump_stations: usize,
    /// Pitches folded into their site (places only).
    pub folded_pitches: usize,
    /// What the store did.
    pub upsert: UpsertStats,
}

/// What a run did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunReport {
    /// Each extract, in order.
    pub extracts: Vec<ExtractReport>,
    /// The countries it speaks for.
    pub coverage: Coverage,
    /// What it retired.
    pub retirement: Retirement,
}

/// The progress of a run, kept in the cache between its extracts.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
struct RunState {
    /// The extracts of the run, in order: another list starts over.
    extracts: Vec<String>,
    /// The mirror they come from.
    mirror: String,
    /// The extracts stored so far.
    done: Vec<Done>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct Done {
    name: String,
    /// The modification time of the file it was read from: a file
    /// downloaded again since is read again.
    file_at: DateTime<Utc>,
    records: usize,
}

fn state_key(layer: Layer) -> String {
    format!("osm-extract/runs/{}.json", layer.key())
}

fn seen_key(layer: Layer, name: &str) -> String {
    format!("osm-extract/runs/{}-{name}.seen", layer.key())
}

async fn load_state(
    cache: &Cache,
    layer: Layer,
    plan: &ExtractPlan,
) -> Result<RunState, IngestError> {
    let names: Vec<String> = plan.extracts.iter().map(|e| e.name.to_owned()).collect();
    let fresh = RunState {
        extracts: names.clone(),
        mirror: plan.mirror.clone(),
        done: Vec::new(),
    };
    let Some(cached) = cache.read(&state_key(layer)).await? else {
        return Ok(fresh);
    };
    match serde_json::from_slice::<RunState>(&cached.bytes) {
        Ok(state) if state.extracts == names && state.mirror == plan.mirror => Ok(state),
        _ => Ok(fresh),
    }
}

async fn save_state(cache: &Cache, layer: Layer, state: &RunState) -> Result<(), IngestError> {
    let bytes = serde_json::to_vec_pretty(state).map_err(|source| IngestError::Json {
        what: "extract run state".into(),
        source,
    })?;
    cache.write(&state_key(layer), &bytes).await?;
    Ok(())
}

/// The ids an earlier attempt of the run stored for `name`, if it stored
/// that extract from the same file.
async fn resumed_ids(
    cache: &Cache,
    layer: Layer,
    state: &RunState,
    name: &str,
    file_at: DateTime<Utc>,
) -> Result<Option<(Vec<String>, usize)>, IngestError> {
    let Some(done) = state
        .done
        .iter()
        .find(|d| d.name == name && d.file_at == file_at)
    else {
        return Ok(None);
    };
    let Some(cached) = cache.read(&seen_key(layer, name)).await? else {
        return Ok(None);
    };
    let ids: Vec<String> = String::from_utf8_lossy(&cached.bytes)
        .lines()
        .filter(|l| !l.is_empty())
        .map(str::to_owned)
        .collect();
    Ok(Some((ids, done.records)))
}

/// Imports `layer` from every extract of `plan`, then retires what the
/// run's countries no longer hold.
///
/// # Errors
///
/// [`IngestError`] when a download, a read or a write fails; the extracts
/// stored before stay, and the next run resumes after them.
pub async fn run(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    plan: &ExtractPlan,
    layer: Layer,
) -> Result<RunReport, IngestError> {
    let coverage = Coverage::of(&plan.extracts);
    let mut state = load_state(cache, layer, plan).await?;
    let mut seen: HashSet<String> = HashSet::new();
    let mut seen_order: Vec<String> = Vec::new();
    let mut latest: Option<DateTime<Utc>> = None;
    let mut reports = Vec::with_capacity(plan.extracts.len());
    for spec in &plan.extracts {
        let file = osm_extract::fetch(
            http,
            cache,
            &spec.url(&plan.mirror),
            &spec.cache_key(&plan.mirror),
            RetryPolicy::PATIENT,
            plan.refresh,
        )
        .await?;
        latest = latest.max(Some(file.fetched_at));
        if let Some((ids, records)) =
            resumed_ids(cache, layer, &state, spec.name, file.fetched_at).await?
        {
            tracing::info!(extract = spec.name, records, "already stored by this run");
            for id in ids {
                if seen.insert(id.clone()) {
                    seen_order.push(id);
                }
            }
            reports.push(ExtractReport {
                name: spec.name,
                cached: file.cached,
                resumed: true,
                records,
                skipped: 0,
                duplicates: 0,
                attached_dump_stations: 0,
                folded_pitches: 0,
                upsert: UpsertStats::default(),
            });
            continue;
        }
        tracing::info!(extract = spec.name, path = %file.path.display(), "reading the extract");
        let mut report = match layer {
            Layer::Places => {
                store_places(pool, &file, spec, &coverage, &mut seen, &mut seen_order).await?
            }
            Layer::Pois => {
                store_pois(pool, &file, spec, &coverage, &mut seen, &mut seen_order).await?
            }
        };
        report.cached = file.cached;
        // The ids this extract added, for a run that starts again.
        let added = &seen_order[seen_order.len() - report.records..];
        let mut text = added.join("\n");
        text.push('\n');
        cache
            .write(&seen_key(layer, spec.name), text.as_bytes())
            .await?;
        state.done.retain(|d| d.name != spec.name);
        state.done.push(Done {
            name: spec.name.to_owned(),
            file_at: file.fetched_at,
            records: report.records,
        });
        save_state(cache, layer, &state).await?;
        tracing::info!(
            extract = spec.name,
            records = report.records,
            inserted = report.upsert.inserted,
            changed = report.upsert.changed,
            "extract stored"
        );
        reports.push(report);
    }
    let at = latest.unwrap_or_else(Utc::now);
    let retirement = match layer {
        Layer::Places => {
            store::retire_in_coverage(pool, &SourceId::OSM, &coverage, &seen_order, at).await?
        }
        Layer::Pois => {
            store::retire_pois_in_coverage(pool, &SourceId::OSM, &coverage, &seen_order, at).await?
        }
    };
    // The run is complete: the next one starts over.
    cache.remove(&state_key(layer)).await?;
    for spec in &plan.extracts {
        cache.remove(&seen_key(layer, spec.name)).await?;
    }
    Ok(RunReport {
        extracts: reports,
        coverage,
        retirement,
    })
}

/// Reads one extract's places on a blocking thread and stores those no
/// earlier extract of the run gave.
async fn store_places(
    pool: &PgPool,
    file: &osm_extract::Extract,
    spec: &ExtractSpec,
    coverage: &Coverage,
    seen: &mut HashSet<String>,
    seen_order: &mut Vec<String>,
) -> Result<ExtractReport, IngestError> {
    let path = file.path.clone();
    let at = file.fetched_at;
    let (coverage_owned, spec_owned) = (coverage.clone(), *spec);
    let parsed = tokio::task::spawn_blocking(move || {
        osm_extract::read(&path, at, Area::of(&spec_owned, &coverage_owned))
    })
    .await
    .map_err(IngestError::Blocking)??;
    let total = parsed.records.len();
    let fresh: Vec<crate::FetchedRecord> = parsed
        .records
        .into_iter()
        .filter(|r| seen.insert(r.external_id.clone()))
        .collect();
    seen_order.extend(fresh.iter().map(|r| r.external_id.clone()));
    let upsert = store::upsert_by_country(pool, &SourceId::OSM, &fresh).await?;
    Ok(ExtractReport {
        name: spec.name,
        cached: false,
        resumed: false,
        records: fresh.len(),
        skipped: parsed.skipped.len(),
        duplicates: total - fresh.len(),
        attached_dump_stations: parsed.attached_dump_stations,
        folded_pitches: parsed.folded_pitches,
        upsert,
    })
}

/// Reads one extract's points on a blocking thread and stores those no
/// earlier extract of the run gave.
async fn store_pois(
    pool: &PgPool,
    file: &osm_extract::Extract,
    spec: &ExtractSpec,
    coverage: &Coverage,
    seen: &mut HashSet<String>,
    seen_order: &mut Vec<String>,
) -> Result<ExtractReport, IngestError> {
    let path = file.path.clone();
    let at = file.fetched_at;
    let (coverage_owned, spec_owned) = (coverage.clone(), *spec);
    let parsed = tokio::task::spawn_blocking(move || {
        crate::poi_osm::read(&path, at, Area::of(&spec_owned, &coverage_owned))
    })
    .await
    .map_err(IngestError::Blocking)??;
    let total = parsed.points.len();
    let fresh: Vec<crate::poi_osm::FetchedPoi> = parsed
        .points
        .into_iter()
        .filter(|p| seen.insert(p.external_id.clone()))
        .collect();
    seen_order.extend(fresh.iter().map(|p| p.external_id.clone()));
    let upsert = store::upsert_pois_by_country(pool, &SourceId::OSM, &fresh).await?;
    Ok(ExtractReport {
        name: spec.name,
        cached: false,
        resumed: false,
        records: fresh.len(),
        skipped: parsed.skipped.len(),
        duplicates: total - fresh.len(),
        attached_dump_stations: 0,
        folded_pitches: 0,
        upsert,
    })
}
