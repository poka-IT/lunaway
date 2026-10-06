//! `lunaway`: the operator's command.
//!
//! ```text
//! lunaway migrate
//! lunaway ingest osm [--region FR-BRE]... [--refresh]
//! lunaway ingest osm-extract [--url URL] [--refresh]
//! lunaway ingest atout-france [--refresh]
//! lunaway conflate [--full]
//! lunaway stats
//! ```
//!
//! `DATABASE_URL` points at the database. Raw payloads are cached under
//! `LUNAWAY_DATA_DIR/raw` (default: the repository's gitignored `data/`), so
//! a re-run reads the disk unless `--refresh` is given.
//!
//! An import that stored its records but refused to retire the missing ones
//! (the fetch looked truncated) exits with an error after its report, so a
//! timer or a script sees it.

use std::{path::PathBuf, time::Duration};

use anyhow::Context;
use clap::{Parser, Subcommand};
use lunaway_ingest::{
    cache::Cache,
    http::{self, RetryPolicy},
    osm::{self, OverpassConfig},
    osm_extract, run,
};
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "lunaway", version, about = "Lunaway data operations")]
struct Cli {
    /// Database to work on.
    #[arg(long, env = "DATABASE_URL", hide_env_values = true)]
    database_url: String,
    /// Directory of the raw payload cache and other local data.
    #[arg(long, env = "LUNAWAY_DATA_DIR", default_value_os_t = default_data_dir())]
    data_dir: PathBuf,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Applies the pending database migrations.
    Migrate,
    /// Imports a source.
    Ingest {
        #[command(subcommand)]
        source: Source,
    },
    /// Merges the records changed since the last run into places.
    Conflate {
        /// Reconsiders every record, not only the changed ones.
        #[arg(long)]
        full: bool,
    },
    /// Prints the counts of records, places, merges and the review queue.
    Stats,
}

#[derive(Subcommand)]
enum Source {
    /// OpenStreetMap through Overpass, one region of metropolitan France at a
    /// time.
    Osm {
        /// ISO 3166-2 code of a region (`FR-BRE`); repeat for several; all
        /// thirteen when absent.
        #[arg(long = "region")]
        regions: Vec<String>,
        /// Asks the source again instead of reading the cache.
        #[arg(long)]
        refresh: bool,
        /// Overpass interpreter; repeat for several, tried in turn on
        /// failure. Defaults to public instances that keep an area index.
        #[arg(long = "overpass-url")]
        overpass_urls: Vec<String>,
        /// Seconds to wait between two queries that reached Overpass.
        #[arg(long, default_value_t = 20)]
        pace_secs: u64,
    },
    /// OpenStreetMap from Geofabrik's France extract: the whole country in
    /// one download, without load on a shared Overpass instance.
    OsmExtract {
        /// Extract to download.
        #[arg(long, default_value = osm_extract::FRANCE_EXTRACT_URL)]
        url: String,
        /// Downloads the extract again instead of reading the cache.
        #[arg(long)]
        refresh: bool,
    },
    /// Atout France's classified campsites, geocoded with the BAN.
    AtoutFrance {
        /// Downloads the CSV and geocodes again instead of reading the cache.
        #[arg(long)]
        refresh: bool,
    },
}

/// Fails when an import refused to retire records, naming the slices: the
/// records were stored, but a fetch holding less than half of what is
/// stored looks truncated, and someone must look before the next run.
fn check_retirement(refused: &[&str]) -> anyhow::Result<()> {
    if refused.is_empty() {
        return Ok(());
    }
    anyhow::bail!(
        "retiring refused for {}: the fetch holds less than half of the stored records \
         (truncated?); records were stored, none retired",
        refused.join(", ")
    )
}

/// The repository's `data/` directory, known at build time: a development
/// default. A deployment sets `LUNAWAY_DATA_DIR`.
fn default_data_dir() -> PathBuf {
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../data"))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with_writer(std::io::stderr)
        .init();
    let cli = Cli::parse();
    let pool = lunaway_db::connect(&cli.database_url, 4)
        .await
        .context("cannot reach the database (DATABASE_URL)")?;
    let cache = Cache::new(cli.data_dir.join("raw"));

    match cli.command {
        Command::Migrate => {
            lunaway_db::migrate(&pool)
                .await
                .context("migration failed")?;
            println!("migrations applied");
        }
        Command::Ingest { source } => {
            let client = http::client().context("cannot build the HTTP client")?;
            match source {
                Source::Osm {
                    regions,
                    refresh,
                    overpass_urls,
                    pace_secs,
                } => {
                    let regions = if regions.is_empty() {
                        osm::REGIONS.to_vec()
                    } else {
                        regions
                            .iter()
                            .map(|code| {
                                osm::region(code).with_context(|| {
                                    format!("unknown region {code}; one of the ISO codes of osm::REGIONS")
                                })
                            })
                            .collect::<anyhow::Result<_>>()?
                    };
                    let urls = if overpass_urls.is_empty() {
                        OverpassConfig::DEFAULT_URLS
                            .iter()
                            .map(|u| (*u).to_owned())
                            .collect()
                    } else {
                        overpass_urls
                    };
                    let config = OverpassConfig {
                        urls,
                        pace: Duration::from_secs(pace_secs),
                        retry: RetryPolicy::PATIENT,
                    };
                    let reports =
                        run::osm_regions(&pool, &client, &cache, &config, &regions, refresh)
                            .await
                            .context("osm import failed")?;
                    println!(
                        "region   records  inserted  changed  unchanged  retired  dump stations folded  cached"
                    );
                    for r in &reports {
                        println!(
                            "{:<8} {:>7}  {:>8}  {:>7}  {:>9}  {:>7}  {:>20}  {}{}",
                            r.region.code,
                            r.records,
                            r.store.upsert.inserted,
                            r.store.upsert.changed,
                            r.store.upsert.unchanged,
                            r.store.retired,
                            r.attached_dump_stations,
                            r.cached,
                            if r.store.retire_refused {
                                "  (retiring refused: truncated?)"
                            } else {
                                ""
                            },
                        );
                    }
                    let total: usize = reports.iter().map(|r| r.records).sum();
                    println!("total    {total:>7}");
                    let refused: Vec<&str> = reports
                        .iter()
                        .filter(|r| r.store.retire_refused)
                        .map(|r| r.region.code)
                        .collect();
                    check_retirement(&refused)?;
                }
                Source::OsmExtract { url, refresh } => {
                    let r = run::osm_extract(&pool, &client, &cache, &url, refresh)
                        .await
                        .context("osm extract import failed")?;
                    println!("records mapped: {}", r.records);
                    println!(
                        "dump stations folded into their site: {}",
                        r.attached_dump_stations
                    );
                    println!(
                        "elements skipped (outside the area, no coordinates): {}",
                        r.skipped
                    );
                    println!(
                        "stored: {} inserted, {} changed, {} unchanged, {} retired{}{}",
                        r.store.upsert.inserted,
                        r.store.upsert.changed,
                        r.store.upsert.unchanged,
                        r.store.retired,
                        if r.store.retire_refused {
                            " (retiring refused: truncated?)"
                        } else {
                            ""
                        },
                        if r.cached {
                            ", extract from the cache"
                        } else {
                            ""
                        }
                    );
                    check_retirement(if r.store.retire_refused {
                        &["osm extract"]
                    } else {
                        &[]
                    })?;
                }
                Source::AtoutFrance { refresh } => {
                    let r = run::atout_france(
                        &pool,
                        &client,
                        &cache,
                        &run::AtoutFranceConfig::default(),
                        refresh,
                    )
                    .await
                    .context("atout france import failed")?;
                    println!("campsites in the CSV (metropolitan): {}", r.campsites);
                    println!(
                        "other accommodation skipped: {}, overseas: {}, duplicates: {}",
                        r.other_kinds, r.overseas, r.duplicates
                    );
                    println!(
                        "geocoding dropped: {} not found, {} low score, {} municipality only",
                        r.drops.not_found, r.drops.low_score, r.drops.municipality_only
                    );
                    println!(
                        "records stored: {} ({} inserted, {} changed, {} unchanged, {} retired{}){}",
                        r.records,
                        r.store.upsert.inserted,
                        r.store.upsert.changed,
                        r.store.upsert.unchanged,
                        r.store.retired,
                        if r.store.retire_refused {
                            ", retiring refused: truncated?"
                        } else {
                            ""
                        },
                        if r.cached { ", csv from the cache" } else { "" }
                    );
                    check_retirement(if r.store.retire_refused {
                        &["atout-france"]
                    } else {
                        &[]
                    })?;
                }
            }
        }
        Command::Conflate { full } => {
            if full {
                let n = lunaway_db::records::mark_all_dirty(&pool).await?;
                println!("{n} records flagged for a full rebuild");
            }
            let today = lunaway_conflate::opening::today_in_france();
            let s = lunaway_conflate::run(&pool, today)
                .await
                .context("conflation failed")?;
            println!("records flagged: {}", s.dirty);
            println!(
                "pairs scored: {} ({} merge, {} review)",
                s.scored, s.merges, s.reviews
            );
            println!("records regrouped: {}", s.affected);
            println!(
                "places: {} created, {} updated, {} unchanged, {} deleted",
                s.created, s.updated, s.unchanged, s.tombstoned
            );
            println!(
                "opening hours moved to today's window: {}",
                s.opening_refreshed
            );
            if s.conflicts > 0 {
                println!(
                    "contradictory human constraints left unapplied: {}",
                    s.conflicts
                );
            }
        }
        Command::Stats => {
            let s = lunaway_db::stats::read(&pool).await?;
            println!("source         live  deleted  waiting");
            for c in &s.sources {
                println!(
                    "{:<12} {:>6}  {:>7}  {:>7}",
                    c.source_id, c.live, c.deleted, c.dirty
                );
            }
            println!("places: {} live, {} deleted", s.places, s.tombstones);
            println!("kind              places  with 2+ sources");
            for k in &s.kinds {
                println!("{:<16} {:>7}  {:>15}", k.kind, k.places, k.merged);
            }
            println!("places by sources:");
            for set in &s.source_sets {
                println!("  {:<20} {:>7}", set.sources, set.places);
            }
            println!("merge decisions: {}", s.merge_pairs);
            for r in &s.review {
                println!(
                    "review queue, {}: {}",
                    if r.same_source {
                        "same-source duplicates"
                    } else {
                        "cross-source pairs"
                    },
                    r.pairs
                );
            }
            println!("human constraints: {}", s.constraints);
            println!(
                "opening hours: {} places, {} parsed",
                s.opening_hours.0, s.opening_hours.1
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_refused_retirement_fails_the_command() {
        assert!(check_retirement(&[]).is_ok());
        let err = check_retirement(&["FR-BRE", "FR-PDL"]).unwrap_err();
        assert!(
            err.to_string().contains("FR-BRE, FR-PDL"),
            "the error names the slices to look at: {err}"
        );
    }
}
