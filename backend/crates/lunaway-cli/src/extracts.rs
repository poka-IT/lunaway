//! `lunaway ingest osm-extract` and `lunaway ingest pois`: which extracts a
//! run reads, and what it prints.

use std::time::Duration;

use anyhow::Context;
use clap::Args;
use lunaway_ingest::{
    extract_run::{ExtractPlan, RunReport},
    osm_extract::{self, Refresh},
};

/// The extracts of a run and how they are fetched.
#[derive(Args, Debug, Clone)]
pub(crate) struct ExtractArgs {
    /// An extract to read (`france`, `spain`, `luxembourg`...); repeat for
    /// several. `france` when neither this nor `--europe` is given.
    #[arg(long = "extract")]
    extracts: Vec<String>,
    /// Reads every country of the European import (`osm_extract::EUROPE`).
    #[arg(long, conflicts_with = "extracts")]
    europe: bool,
    /// Where the extracts are downloaded from (Geofabrik's layout).
    #[arg(long, default_value = osm_extract::GEOFABRIK)]
    mirror: String,
    /// Downloads an extract again when its cached copy is older than
    /// `--max-age-hours`, instead of reading the cache.
    #[arg(long)]
    refresh: bool,
    /// Age, in hours, under which `--refresh` keeps a cached extract: a run
    /// started again after a failure does not download what it fetched
    /// earlier the same day. Geofabrik publishes once a day.
    #[arg(long, default_value_t = 20)]
    max_age_hours: u64,
}

impl ExtractArgs {
    /// The plan these arguments describe.
    pub(crate) fn plan(&self) -> anyhow::Result<ExtractPlan> {
        let names: Vec<String> = if self.europe {
            osm_extract::EUROPE
                .iter()
                .map(|n| (*n).to_owned())
                .collect()
        } else if self.extracts.is_empty() {
            vec!["france".to_owned()]
        } else {
            self.extracts.clone()
        };
        let extracts = names
            .iter()
            .map(|n| {
                osm_extract::extract(n).with_context(|| {
                    let known: Vec<&str> = osm_extract::CATALOGUE.iter().map(|e| e.name).collect();
                    format!("unknown extract {n}; one of {}", known.join(", "))
                })
            })
            .collect::<anyhow::Result<Vec<_>>>()?;
        Ok(ExtractPlan {
            extracts,
            mirror: self.mirror.clone(),
            retry: lunaway_ingest::http::RetryPolicy::PATIENT,
            refresh: if self.refresh {
                Refresh::OlderThan(Duration::from_secs(self.max_age_hours.saturating_mul(3600)))
            } else {
                Refresh::Never
            },
        })
    }
}

/// Prints a run, one line per extract, then its retirement. Fails when
/// retiring was refused (the run looked truncated), after the report.
pub(crate) fn print_run(r: &RunReport, what: &str) -> anyhow::Result<()> {
    println!(
        "extract                          {what:>8}  inserted  changed  unchanged  duplicates  skipped  dumps  pitches  from"
    );
    let mut total = 0;
    for e in &r.extracts {
        total += e.records;
        println!(
            "{:<30} {:>10}  {:>8}  {:>7}  {:>9}  {:>10}  {:>7}  {:>5}  {:>7}  {}",
            e.name,
            e.records,
            e.upsert.inserted,
            e.upsert.changed,
            e.upsert.unchanged,
            e.duplicates,
            e.skipped,
            e.attached_dump_stations,
            e.folded_pitches,
            if e.resumed {
                "stored by the stopped run"
            } else if e.cached {
                "cache"
            } else {
                "download"
            },
        );
    }
    println!("total {total:>35}");
    match &r.coverage {
        osm_extract::Coverage::Everywhere => println!("countries: all"),
        osm_extract::Coverage::Countries(set) => {
            let codes: Vec<&str> = set.iter().map(String::as_str).collect();
            println!("countries: {}", codes.join(" "));
        }
    }
    println!("retired: {}", r.retirement.retired);
    if !r.retirement.refused.is_empty() {
        anyhow::bail!(
            "retiring refused for the {what} of {}: the run holds less than half of the stored \
             ones there (truncated?); they were stored, none retired there",
            r.retirement.refused.join(", ")
        );
    }
    Ok(())
}
