//! `lunaway`: the operator's command.
//!
//! ```text
//! lunaway migrate
//! lunaway ingest osm [--region FR-BRE]... [--refresh]
//! lunaway ingest osm-extract [--url URL] [--refresh]
//! lunaway ingest atout-france [--refresh]
//! lunaway ingest municipalities [--url URL] [--refresh]
//! lunaway conflate [--full] [--watch [--every-secs 300]]
//! lunaway stats
//! lunaway moderation list [--limit 50]
//! lunaway moderation approve|reject <entry-id> [--note TEXT]
//! lunaway moderation ban <account-id> --reason TEXT
//! lunaway moderation dismiss-issues <place-id>
//! lunaway accounts create-demo [--level 2] [--pseudonym NAME]
//! lunaway accounts set-level <account-id> <level>
//! ```
//!
//! The imports and the conflation run with the import role
//! (`lunaway_ingest`); `moderation` and `accounts` write accounts and
//! contributions, so they run with the API's role (`lunaway_app`), whose
//! `DATABASE_URL` the API uses, and remove photo files under
//! `LUNAWAY_MEDIA_DIR` like the API, so they run as the API's user.
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
use uuid::Uuid;

#[derive(Parser)]
#[command(name = "lunaway", version, about = "Lunaway data operations")]
struct Cli {
    /// Database to work on.
    #[arg(long, env = "DATABASE_URL", hide_env_values = true)]
    database_url: String,
    /// Directory of the raw payload cache and other local data.
    #[arg(long, env = "LUNAWAY_DATA_DIR", default_value_os_t = default_data_dir())]
    data_dir: PathBuf,
    /// Root of the photo files (the API's `LUNAWAY_MEDIA_DIR`), from which
    /// moderation removes the files of removed photos.
    #[arg(long, env = "LUNAWAY_MEDIA_DIR", default_value_os_t = default_data_dir().join("media"))]
    media_dir: PathBuf,
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
    /// Merges the records changed since the last run into places, applies
    /// the community's submissions and recomputes the community summaries.
    Conflate {
        /// Reconsiders every record, not only the changed ones.
        #[arg(long)]
        full: bool,
        /// Keeps running: a run whenever the API signals work, and at least
        /// every `--every-secs`.
        #[arg(long)]
        watch: bool,
        /// Longest pause between two runs of `--watch`, seconds.
        #[arg(long, default_value_t = 300)]
        every_secs: u64,
    },
    /// Prints the counts of records, places, merges and the review queue.
    Stats,
    /// Works the moderation queue (with the API's database role).
    Moderation {
        #[command(subcommand)]
        action: Moderation,
    },
    /// Account administration (with the API's database role).
    Accounts {
        #[command(subcommand)]
        action: Accounts,
    },
}

#[derive(Subcommand)]
enum Moderation {
    /// Prints the open entries, oldest first.
    List {
        /// Entries printed at most.
        #[arg(long, default_value_t = 50)]
        limit: i64,
    },
    /// Publishes held or reported content, or accepts a place proposal.
    Approve {
        /// The entry.
        id: Uuid,
        /// Why, kept with the decision.
        #[arg(long)]
        note: Option<String>,
    },
    /// Removes held or reported content, or refuses a place proposal.
    Reject {
        /// The entry.
        id: Uuid,
        /// Why, kept with the decision.
        #[arg(long)]
        note: Option<String>,
    },
    /// Bans an account: sessions ended, sign-in refused, reviews and photos
    /// removed (their files deleted), issue reports dismissed.
    Ban {
        /// The account.
        account: Uuid,
        /// Why, kept with the ban.
        #[arg(long)]
        reason: String,
    },
    /// Dismisses every issue reported at a place (a false night ban or
    /// danger), so the change feed stops carrying them.
    DismissIssues {
        /// The place.
        place: Uuid,
    },
}

#[derive(Subcommand)]
enum Accounts {
    /// Creates an account without a device, at a granted level, and prints
    /// its recovery code: the store reviewers sign in with it.
    CreateDemo {
        /// The level granted.
        #[arg(long, default_value_t = 2, value_parser = clap::value_parser!(i16).range(0..=4))]
        level: i16,
        /// Its pseudonym; generated when absent.
        #[arg(long)]
        pseudonym: Option<String>,
    },
    /// Sets the level the administration grants an account (4 for a
    /// moderator, 0 to withdraw a grant).
    SetLevel {
        /// The account.
        account: Uuid,
        /// The level.
        #[arg(value_parser = clap::value_parser!(i16).range(0..=4))]
        level: i16,
    },
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
    /// The French communes (contours administratifs, data.gouv.fr), then
    /// the commune of every place.
    Municipalities {
        /// File to download.
        #[arg(long, default_value = lunaway_ingest::municipalities::COMMUNES_URL)]
        url: String,
        /// Downloads the file again instead of reading the cache.
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
                Source::Municipalities { url, refresh } => {
                    let r = run::municipalities(&pool, &client, &cache, &url, refresh)
                        .await
                        .context("communes import failed")?;
                    println!(
                        "communes stored: {} ({} municipal districts left out, {} unusable){}",
                        r.municipalities,
                        r.districts,
                        r.skipped,
                        if r.cached {
                            ", file from the cache"
                        } else {
                            ""
                        }
                    );
                    println!("places whose commune changed: {}", r.places_changed);
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
        Command::Conflate {
            full,
            watch,
            every_secs,
        } => {
            if full {
                let n = lunaway_db::records::mark_all_dirty(&pool).await?;
                println!("{n} records flagged for a full rebuild");
            }
            if watch {
                tracing::info!(every_secs, "conflation worker started");
                lunaway_conflate::watch(
                    &pool,
                    Duration::from_secs(every_secs.max(1)),
                    lunaway_conflate::opening::today_in_france,
                )
                .await
                .context("the conflation worker cannot listen")?;
                return Ok(());
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
            println!(
                "community: {} submissions applied, {} summaries changed",
                s.submissions_applied, s.community_refreshed
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
        Command::Moderation { action } => {
            let media = lunaway_media::MediaStore::new(cli.media_dir);
            moderation(&pool, &media, action).await?;
        }
        Command::Accounts { action } => accounts(&pool, action).await?,
    }
    Ok(())
}

/// Removes photo files no published or hidden photo shows any more. Every
/// file is tried; a missing one is reported (a wrong `LUNAWAY_MEDIA_DIR`
/// would leave the real ones served), and any failure fails the command
/// after the others were tried.
async fn remove_files(media: &lunaway_media::MediaStore, files: &[String]) -> anyhow::Result<()> {
    let (mut removed, mut missing, mut failed) = (0, 0, 0);
    for f in files {
        match media.remove(f).await {
            Ok(true) => removed += 1,
            Ok(false) => {
                missing += 1;
                eprintln!("not found under {}: {f}", media.root().display());
            }
            Err(error) => {
                failed += 1;
                eprintln!("cannot remove {f}: {error}");
            }
        }
    }
    if !files.is_empty() {
        println!("photo files: {removed} removed, {missing} not found, {failed} failed");
    }
    anyhow::ensure!(
        failed == 0,
        "{failed} photo files could not be removed: they are still served"
    );
    Ok(())
}

async fn moderation(
    pool: &lunaway_db::PgPool,
    media: &lunaway_media::MediaStore,
    action: Moderation,
) -> anyhow::Result<()> {
    use lunaway_db::moderation::{Decided, Decision, decide, open};
    let (id, decision, note) = match action {
        Moderation::List { limit } => {
            let entries = open(pool, limit.clamp(1, 1_000)).await?;
            if entries.is_empty() {
                println!("the queue is empty");
            }
            for e in entries {
                println!(
                    "{}  {}  {} {}  reports: {}  since {}",
                    e.id,
                    e.kind,
                    e.target_type,
                    e.target_id,
                    e.reports,
                    e.created_at.format("%Y-%m-%d %H:%M")
                );
                println!(
                    "    author: {}  why: {}",
                    e.account_id
                        .map_or_else(|| "none".to_owned(), |a| a.to_string()),
                    e.reason
                );
                if let Some(x) = e.excerpt {
                    println!("    {}", x.replace('\n', " "));
                }
            }
            return Ok(());
        }
        Moderation::Approve { id, note } => (id, Decision::Approve, note),
        Moderation::Reject { id, note } => (id, Decision::Reject, note),
        Moderation::Ban { account, reason } => {
            let files = lunaway_db::accounts::ban(pool, account, &reason)
                .await?
                .with_context(|| format!("no account {account}"))?;
            println!(
                "account {account} banned: sessions ended, reviews and photos removed, \
                 issue reports dismissed"
            );
            return remove_files(media, &files).await;
        }
        Moderation::DismissIssues { place } => {
            let n = lunaway_db::moderation::dismiss_issues(pool, place).await?;
            println!("{n} issue reports dismissed at {place}");
            return Ok(());
        }
    };
    match decide(pool, id, decision, note.as_deref()).await? {
        Decided::NotFound => anyhow::bail!("no open entry {id}"),
        Decided::Done { kind, files, .. } => {
            let verb = if decision == Decision::Approve {
                "approved"
            } else {
                "rejected"
            };
            println!("{kind} {id} {verb}");
            remove_files(media, &files).await?;
        }
    }
    Ok(())
}

async fn accounts(pool: &lunaway_db::PgPool, action: Accounts) -> anyhow::Result<()> {
    match action {
        Accounts::CreateDemo { level, pseudonym } => {
            let pseudonym = match pseudonym {
                Some(p) => lunaway_domain::community::pseudonym::normalize_pseudonym(&p)
                    .map_err(|e| anyhow::anyhow!("pseudonym: {e}"))?,
                None => lunaway_auth::generate_pseudonym(lunaway_auth::Locale::En)?,
            };
            let code = lunaway_auth::RecoveryCode::generate()?;
            let display = code.display();
            let hash = tokio::task::spawn_blocking(move || code.hash()).await??;
            let account = lunaway_db::accounts::create_granted(pool, &pseudonym, level, &hash)
                .await
                .context("cannot create the demo account")?;
            println!("account: {} ({})", account.id, account.pseudonym);
            println!("level: {level}");
            println!("recovery code: {display}");
            println!(
                "sign in from the app with this code (account recovery); it stays valid \
                 until a new one is created"
            );
        }
        Accounts::SetLevel { account, level } => {
            anyhow::ensure!(
                lunaway_db::accounts::set_granted_level(pool, account, level).await?,
                "no account {account}"
            );
            println!("account {account}: level {level} granted");
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
