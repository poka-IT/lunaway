//! `lunaway`: the operator's command.
//!
//! ```text
//! lunaway migrate
//! lunaway ingest osm [--region FR-BRE]... [--refresh]
//! lunaway ingest osm-extract [--extract NAME]... [--europe] [--refresh] [--max-age-hours 20]
//! lunaway ingest atout-france [--refresh]
//! lunaway ingest municipalities [--url URL] [--refresh]
//! lunaway ingest pois [--extract NAME]... [--europe] [--refresh] [--max-age-hours 20]
//! lunaway ingest fuel [--refresh]
//! lunaway ingest laposte [--refresh]
//! lunaway ingest finess [--refresh]
//! lunaway pois hours
//! lunaway pois stats
//! lunaway conflate [--full] [--watch [--every-secs 300]] [--poi-layer-every-mins 360]
//! lunaway stats
//! lunaway packs build --dir DIR [--region FR-BRE]...
//! lunaway packs list
//! lunaway moderation list [--limit 50]
//! lunaway moderation approve|reject <entry-id> [--note TEXT]
//! lunaway moderation ban <account-id> --reason TEXT
//! lunaway moderation dismiss-issues <place-id>
//! lunaway moderation hide-poi|show-poi <poi-id> [--note TEXT]
//! lunaway accounts create-demo [--level 2] [--pseudonym NAME]
//! lunaway accounts set-level <account-id> <level>
//! lunaway routing fetch-ign [--refresh]
//! lunaway routing prepare --pbf FILE --out DIR --graph-id ID --engine TEXT [--no-ign]
//! lunaway routing test-routes --url http://127.0.0.1:8002 --cases FILE
//! lunaway routing load <bundle dir>
//! lunaway routing activate <graph id>
//! lunaway routing graphs
//! lunaway routing disputes [--limit 50]
//! lunaway road-events poll [--only dir,dialog,...] [--force]
//! lunaway road-events dialog-permanent
//! lunaway road-events match [--limit 400]
//! lunaway road-events stats
//! lunaway moderation remove-road-report|end-road-event <id>
//! ```
//!
//! The imports and the conflation run with the import role
//! (`lunaway_ingest`); `moderation` and `accounts` write accounts and
//! contributions, so they run with the API's role (`lunaway_app`), whose
//! `DATABASE_URL` the API uses, and remove photo files under
//! `LUNAWAY_MEDIA_DIR` like the API, so they run as the API's user.
//!
//! The `routing` commands build and publish the motorhome routing graph
//! (docs/deploy.md, "Routing"): `fetch-ign`, `prepare` and `test-routes`
//! need no database, so a build machine runs them without one; `load`,
//! `activate`, `graphs` and `disputes` run with the import role.
//!
//! The `road-events` commands read the feeds of closures and works
//! (`docs/data-sources.md`, "Road events") with the import role; `poll`
//! runs every three minutes on the server and matches the new events on
//! the routing engine at `LUNAWAY_VALHALLA_URL` (loopback only).
//!
//! `DATABASE_URL` points at the database. Raw payloads are cached under
//! `LUNAWAY_DATA_DIR/raw` (default: the repository's gitignored `data/`), so
//! a re-run reads the disk unless `--refresh` is given.
//!
//! An import that stored its records but refused to retire the missing ones
//! (the fetch looked truncated) exits with an error after its report, so a
//! timer or a script sees it.

mod extracts;
mod packs;

use std::{path::PathBuf, time::Duration};

use anyhow::Context;
use clap::{Parser, Subcommand};
use lunaway_ingest::{
    cache::Cache,
    http::{self, RetryPolicy},
    osm::{self, OverpassConfig},
    run,
};
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

#[derive(Parser)]
#[command(name = "lunaway", version, about = "Lunaway data operations")]
struct Cli {
    /// Database to work on; every command but the routing build steps needs
    /// one.
    #[arg(long, env = "DATABASE_URL", hide_env_values = true)]
    database_url: Option<String>,
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
        /// Shortest time between two versions of the points layer's tiles,
        /// minutes: changes wait for the next one, so devices fetch their
        /// tiles again at most this often (`pois::publish_layer`).
        #[arg(long, default_value_t = 360)]
        poi_layer_every_mins: u64,
    },
    /// Prints the counts of records, places, merges and the review queue.
    Stats,
    /// The regional first-sync packs.
    Packs {
        #[command(subcommand)]
        action: packs::Packs,
    },
    /// The layer of points of interest around the places.
    Pois {
        #[command(subcommand)]
        action: Pois,
    },
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
    /// The routing graph: its build steps and its publication.
    Routing {
        #[command(subcommand)]
        action: Routing,
    },
    /// Road events: closures, works, temporary limits (with the import
    /// role).
    RoadEvents {
        #[command(subcommand)]
        action: RoadEvents,
    },
}

#[derive(Subcommand)]
enum RoadEvents {
    /// Reads each feed when it is due (the DIR's increments at every run,
    /// its aggregate hourly, DiaLog every 15 minutes, the cities hourly),
    /// matches new events to the routing graph, ends and purges old ones.
    /// Exits with an error when a feed failed, after the others ran.
    Poll {
        /// Only these sources (`dir`, `dialog`, `paris-fermetures`...),
        /// comma separated.
        #[arg(long, value_delimiter = ',')]
        only: Vec<String>,
        /// Reads every selected source now, due or not.
        #[arg(long)]
        force: bool,
        /// An event without an end not seen for this many hours ends.
        #[arg(long, default_value_t = 6)]
        expire_after_hours: i64,
        /// The routing engine for the matching (loopback only); none skips
        /// it.
        #[arg(long, env = "LUNAWAY_VALHALLA_URL")]
        valhalla_url: Option<String>,
    },
    /// Reads DiaLog's permanent orders and replaces their limits among the
    /// restrictions every route is checked against. Weekly.
    DialogPermanent,
    /// Matches waiting events to the routing graph.
    Match {
        /// Events matched at most.
        #[arg(long, default_value_t = 400)]
        limit: i64,
        /// The routing engine (loopback only).
        #[arg(long, env = "LUNAWAY_VALHALLA_URL")]
        valhalla_url: String,
    },
    /// Prints the live events by source, class and placement, and each
    /// feed's freshness.
    Stats,
}

#[derive(Subcommand)]
enum Routing {
    /// Reads IGN BD TOPO's restricted road sections (WFS) into the cache.
    FetchIgn {
        /// Asks IGN again instead of reading the cache.
        #[arg(long)]
        refresh: bool,
    },
    /// Writes the change file, the restrictions and the build's metadata
    /// for a graph, from an extract and the cached IGN sections.
    Prepare {
        /// The OpenStreetMap extract.
        #[arg(long)]
        pbf: PathBuf,
        /// Directory the outputs go to (created when missing).
        #[arg(long)]
        out: PathBuf,
        /// The graph's name (`20261006T0300Z-fr`).
        #[arg(long)]
        graph_id: String,
        /// The engine that builds it: name, version, image.
        #[arg(long)]
        engine: String,
        /// Builds without IGN's sections (a test extract outside France).
        #[arg(long)]
        no_ign: bool,
        /// The data's date, for an extract whose header carries none
        /// (RFC 3339). Without either, the preparation stops: the date is
        /// what the app shows with every route.
        #[arg(long)]
        osm_data_at: Option<chrono::DateTime<chrono::Utc>>,
    },
    /// Runs the route tests against a Valhalla server; fails if one fails.
    TestRoutes {
        /// The server, on loopback.
        #[arg(long, default_value = "http://127.0.0.1:8002")]
        url: String,
        /// The cases (infra/routing/test-routes.json).
        #[arg(long)]
        cases: PathBuf,
    },
    /// Loads a graph bundle's restrictions, inactive.
    Load {
        /// The bundle directory: build.json, prepare.json,
        /// restrictions.ndjson.gz.
        bundle: PathBuf,
    },
    /// Makes a loaded graph the one routes are checked against, and drops
    /// the graphs older than the previous one.
    Activate {
        /// The graph's name.
        id: String,
    },
    /// Lists the loaded graphs.
    Graphs,
    /// Lists the restrictions whose sources disagree (the review queue).
    Disputes {
        /// Rows printed at most.
        #[arg(long, default_value_t = 50)]
        limit: i64,
    },
}

/// What a graph bundle says about itself (`build.json`).
#[derive(serde::Serialize, serde::Deserialize)]
struct BuildInfo {
    id: String,
    osm_data_at: chrono::DateTime<chrono::Utc>,
    ign_fetched_at: Option<chrono::DateTime<chrono::Utc>>,
    #[serde(default)]
    ign_edition: Option<chrono::NaiveDate>,
    built_at: chrono::DateTime<chrono::Utc>,
    engine: String,
}

#[derive(Subcommand)]
enum Pois {
    /// Evaluates the opening intervals whose window is not today's (the
    /// worker does it at each run; this runs it now).
    Hours,
    /// Prints the counts of the layer and of its joins.
    Stats,
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
    /// Hides a point of interest (spam, gone for good) whatever the
    /// community answers, until `show-poi`.
    HidePoi {
        /// The point.
        poi: Uuid,
        /// Why, kept with the decision.
        #[arg(long)]
        note: Option<String>,
    },
    /// Shows a point of interest again, setting its "gone" answers aside.
    ShowPoi {
        /// The point.
        poi: Uuid,
    },
    /// Removes a user's road report: the community event it supported is
    /// weighed again without it, and ends when none is left.
    RemoveRoadReport {
        /// The report.
        report: Uuid,
    },
    /// Ends a community road event and removes its reports.
    EndRoadEvent {
        /// The event.
        event: Uuid,
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
    /// OpenStreetMap from Geofabrik's extracts: France, or France and its
    /// neighbours country by country, without load on a shared Overpass
    /// instance.
    OsmExtract {
        #[command(flatten)]
        extracts: extracts::ExtractArgs,
    },
    /// Atout France's classified campsites, geocoded with the BAN.
    AtoutFrance {
        /// Downloads the CSV and geocodes again instead of reading the cache.
        #[arg(long)]
        refresh: bool,
    },
    /// The points of interest (shops, vending machines, water, fuel,
    /// health, services) from the extracts the places import downloads,
    /// then their opening hours.
    Pois {
        #[command(flatten)]
        extracts: extracts::ExtractArgs,
    },
    /// The French fuel price feed (prices, LPG, shortages, services),
    /// joined to the fuel stations by their id in the feed. Meant to run
    /// every 15 minutes with `--refresh`, the pace at which the feed is
    /// published.
    Fuel {
        /// Asks the feed again instead of reading the last answer.
        #[arg(long)]
        refresh: bool,
    },
    /// La Poste's opening calendar for the next two weeks, joined to the
    /// post offices by their id, then their opening hours. Daily.
    Laposte {
        /// Asks La Poste again instead of reading today's pages.
        #[arg(long)]
        refresh: bool,
    },
    /// FINESS's monthly snapshot, for the pharmacies and health
    /// establishments the points carry a number of (closures). Monthly,
    /// after the points import.
    Finess {
        /// Downloads the snapshot again instead of reading the cache.
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

/// Prints what a store of joined rows did.
fn print_join_store(s: &lunaway_ingest::store::JoinStoreReport) {
    println!(
        "stored: {} inserted, {} changed, {} unchanged, {} retired, {} changed on the map{}",
        s.upsert.upsert.inserted,
        s.upsert.upsert.changed,
        s.upsert.upsert.unchanged,
        s.retired,
        s.upsert.tile_changes,
        if s.retire_refused {
            " (retiring refused: truncated?)"
        } else {
            ""
        }
    );
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
    let cache = Cache::new(cli.data_dir.join("raw"));
    let command = match cli.command {
        Command::Routing { action } => {
            return routing(cli.database_url.as_deref(), &cache, action).await;
        }
        other => other,
    };
    let pool = connect(cli.database_url.as_deref()).await?;

    match command {
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
                Source::OsmExtract { extracts } => {
                    let plan = extracts.plan()?;
                    let r = lunaway_ingest::extract_run::run(
                        &pool,
                        &client,
                        &cache,
                        &plan,
                        lunaway_ingest::extract_run::Layer::Places,
                    )
                    .await
                    .context("osm extract import failed")?;
                    extracts::print_run(&r, "records")?;
                }
                Source::Pois { extracts } => {
                    let plan = extracts.plan()?;
                    let r = lunaway_ingest::extract_run::run(
                        &pool,
                        &client,
                        &cache,
                        &plan,
                        lunaway_ingest::extract_run::Layer::Pois,
                    )
                    .await
                    .context("points of interest import failed")?;
                    let h = lunaway_conflate::pois::refresh_hours(&pool, chrono::Utc::now())
                        .await
                        .context("opening hours of the points failed")?;
                    println!(
                        "opening hours evaluated: {} ({} from La Poste), {} changed on the map",
                        h.evaluated, h.from_laposte, h.changed
                    );
                    extracts::print_run(&r, "points")?;
                }
                Source::Fuel { refresh } => {
                    let r = lunaway_ingest::fuel::import(
                        &pool,
                        &client,
                        &cache,
                        &lunaway_ingest::fuel::FuelConfig::default(),
                        refresh,
                    )
                    .await
                    .context("fuel price import failed")?;
                    println!(
                        "stations: {} of {} rows ({} skipped), {} selling LPG, feed of {}{}",
                        r.stations,
                        r.rows,
                        r.skipped,
                        r.lpg,
                        r.fetched_at,
                        if r.cached { ", from the cache" } else { "" }
                    );
                    print_join_store(&r.store);
                    check_retirement(if r.store.retire_refused {
                        &["fuel prices"]
                    } else {
                        &[]
                    })?;
                }
                Source::Laposte { refresh } => {
                    let today = lunaway_conflate::opening::today_in_france();
                    let r = lunaway_ingest::laposte::import(
                        &pool,
                        &client,
                        &cache,
                        &lunaway_ingest::laposte::LaPosteConfig::default(),
                        today,
                        refresh,
                    )
                    .await
                    .context("la poste import failed")?;
                    println!(
                        "sites: {} from {} lines in {} pages ({} lines skipped){}",
                        r.sites,
                        r.lines,
                        r.pages,
                        r.skipped_lines,
                        if r.cached { ", from the cache" } else { "" }
                    );
                    print_join_store(&r.store);
                    let h = lunaway_conflate::pois::refresh_hours(&pool, chrono::Utc::now())
                        .await
                        .context("opening hours of the points failed")?;
                    println!(
                        "opening hours evaluated: {} ({} from La Poste), {} changed on the map",
                        h.evaluated, h.from_laposte, h.changed
                    );
                    check_retirement(if r.store.retire_refused {
                        &["la poste"]
                    } else {
                        &[]
                    })?;
                }
                Source::Finess { refresh } => {
                    let r = lunaway_ingest::finess::import(
                        &pool,
                        &client,
                        &cache,
                        &lunaway_ingest::finess::FinessConfig::default(),
                        refresh,
                    )
                    .await
                    .context("finess import failed")?;
                    println!(
                        "{}: {} numbers wanted, {} structures read, {} kept, {} closed{}",
                        r.file,
                        r.wanted,
                        r.structures,
                        r.kept,
                        r.closed,
                        if r.cached { ", from the cache" } else { "" }
                    );
                    print_join_store(&r.store);
                    check_retirement(if r.store.retire_refused {
                        &["finess"]
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
                        "first geocoding pass dropped: {} not found, {} low score, {} municipality only",
                        r.drops.not_found, r.drops.low_score, r.drops.municipality_only
                    );
                    println!(
                        "second pass placed: {} by a simplified address, {} by a campsite toponym, \
                         {} at their municipality (approximate); {} still dropped",
                        r.second_pass.by_address,
                        r.second_pass.by_toponym,
                        r.second_pass.by_municipality,
                        r.second_pass.still_dropped
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
            poi_layer_every_mins,
        } => {
            let poi_layer_every = Duration::from_secs(poi_layer_every_mins.saturating_mul(60));
            if full {
                let n = lunaway_db::records::mark_all_dirty(&pool).await?;
                println!("{n} records flagged for a full rebuild");
            }
            if watch {
                tracing::info!(every_secs, "conflation worker started");
                lunaway_conflate::watch(
                    &pool,
                    Duration::from_secs(every_secs.max(1)),
                    poi_layer_every,
                    chrono::Utc::now,
                )
                .await
                .context("the conflation worker cannot listen")?;
                return Ok(());
            }
            let s = lunaway_conflate::run(&pool, chrono::Utc::now())
                .await
                .context("conflation failed")?;
            if let Some(v) = lunaway_conflate::pois::publish_layer(&pool, poi_layer_every)
                .await
                .context("publishing the points layer failed")?
            {
                println!("points layer: tiles version {v}");
            }
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
            println!(
                "points of interest: {} vending machines added, {} community states changed, \
                 {} hours evaluated ({} changed on the map)",
                s.poi_community.vending_added,
                s.poi_community.refreshed,
                s.poi_hours.evaluated,
                s.poi_hours.changed
            );
            if s.conflicts > 0 {
                println!(
                    "contradictory human constraints left unapplied: {}",
                    s.conflicts
                );
            }
            if s.held_back > 0 {
                println!(
                    "groups held back, placed only at their municipality: {}",
                    s.held_back
                );
            }
        }
        Command::Packs { action } => packs::run(&pool, action).await?,
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
        Command::Pois { action } => match action {
            Pois::Hours => {
                let h = lunaway_conflate::pois::refresh_hours(&pool, chrono::Utc::now())
                    .await
                    .context("opening hours of the points failed")?;
                println!(
                    "opening hours evaluated: {} ({} from La Poste), {} changed on the map",
                    h.evaluated, h.from_laposte, h.changed
                );
            }
            Pois::Stats => {
                let s = lunaway_db::pois::layer_stats(&pool).await?;
                let v = lunaway_db::pois::layer_version(&pool).await?;
                println!(
                    "tiles version {} (moved {}){}",
                    v.version,
                    v.changed_at,
                    v.pending_since
                        .map(|t| format!(", changes waiting since {t}"))
                        .unwrap_or_default()
                );
                println!("source        category   kind                    points");
                let mut total = 0;
                for (source, category, kind, n) in &s.by_kind {
                    println!("{source:<13} {category:<10} {kind:<22} {n:>7}");
                    total += n;
                }
                println!("total {total:>49}");
                println!(
                    "opening hours: {} points, {} parsed, {} from La Poste",
                    s.hours.0, s.hours.1, s.hours.2
                );
                println!(
                    "fuel feed id: {} points, {} found in the feed",
                    s.fuel_joined.0, s.fuel_joined.1
                );
                println!(
                    "La Poste id: {} points, {} found in the calendar",
                    s.laposte_joined.0, s.laposte_joined.1
                );
                println!(
                    "FINESS number: {} points, {} found in FINESS",
                    s.finess_joined.0, s.finess_joined.1
                );
                println!("hidden by the community: {}", s.hidden);
            }
        },
        Command::Moderation { action } => {
            let media = lunaway_media::MediaStore::new(cli.media_dir);
            moderation(&pool, &media, action).await?;
        }
        Command::Accounts { action } => accounts(&pool, action).await?,
        Command::RoadEvents { action } => road_events(&pool, &cache, action).await?,
        Command::Routing { .. } => unreachable!("handled before connecting"),
    }
    Ok(())
}

fn print_poll(report: &lunaway_ingest::road_events::poll::PollReport) {
    println!(
        "source             read  events  inserted  changed  unchanged  older  ended  increments  seconds"
    );
    for (id, r) in &report.sources {
        println!(
            "{:<18} {:<5} {:>6}  {:>8}  {:>7}  {:>9}  {:>5}  {:>5}  {:>10}  {:>7.2}{}{}",
            id,
            r.read,
            r.events,
            r.upsert.inserted,
            r.upsert.changed,
            r.upsert.unchanged,
            r.upsert.older,
            r.ended,
            r.increments,
            r.elapsed.as_secs_f64(),
            r.refused
                .map(|(live, seen)| format!(
                    "  (snapshot of {seen} against {live} live: nothing ended)"
                ))
                .unwrap_or_default(),
            r.error
                .as_ref()
                .map(|e| format!("  FAILED: {e}"))
                .unwrap_or_default(),
        );
        if !r.skipped.is_empty() {
            println!("  left out: {:?}", r.skipped);
        }
        if r.upsert.refused > 0 || r.upsert.duplicates > 0 {
            println!(
                "  refused by the store: {}, given twice: {}",
                r.upsert.refused, r.upsert.duplicates
            );
        }
    }
    if let Some(m) = &report.matching {
        println!(
            "matched {}, could not place {}, refused by the engine {}, changed meanwhile {}{}",
            m.matched,
            m.unmatched,
            m.refused,
            m.stale,
            if m.more { ", more waiting" } else { "" }
        );
    }
    if let Some(l) = &report.lifecycle {
        println!(
            "lifecycle: {} community events weighed again, {} past their end, {} expired, \
             {} purged, {} reports purged",
            l.reweighed, l.past_end, l.expired, l.purged, l.reports_purged
        );
    }
}

async fn road_events(
    pool: &lunaway_db::PgPool,
    cache: &Cache,
    action: RoadEvents,
) -> anyhow::Result<()> {
    use lunaway_ingest::road_events::{
        matching::{self, Valhalla},
        poll::{self, PollConfig},
    };
    let engine_of = |url: &str| {
        Valhalla::new(url, Duration::from_secs(10))
            .context("the routing engine must be a loopback http URL")
    };
    match action {
        RoadEvents::Poll {
            only,
            force,
            expire_after_hours,
            valhalla_url,
        } => {
            let client = http::client().context("cannot build the HTTP client")?;
            let config = PollConfig {
                only,
                force,
                expire_after: chrono::Duration::hours(expire_after_hours.max(1)),
                ..PollConfig::default()
            };
            let engine = valhalla_url.as_deref().map(engine_of).transpose()?;
            let report = poll::poll(pool, &client, cache, &config, engine.as_ref())
                .await
                .context("road events poll failed")?;
            print_poll(&report);
            if report.failed() {
                anyhow::bail!("a road events feed failed or looked truncated; the others ran");
            }
        }
        RoadEvents::DialogPermanent => {
            let client = http::client().context("cannot build the HTTP client")?;
            let r = poll::dialog_permanent(
                pool,
                &client,
                cache,
                poll::DIALOG_PERMANENT_URL,
                &["dialog.beta.gouv.fr".to_owned()],
                RetryPolicy::PATIENT,
            )
            .await
            .context("DiaLog permanent orders failed")?;
            println!(
                "DiaLog permanent orders: {} read, {} restrictions stored; left out: {:?}",
                r.orders, r.stored, r.skipped
            );
        }
        RoadEvents::Match {
            limit,
            valhalla_url,
        } => {
            let engine = engine_of(&valhalla_url)?;
            let r = matching::match_pending(pool, &engine, limit, Duration::from_secs(3_600))
                .await
                .context("matching failed")?;
            println!(
                "matched {}, could not place {}, refused by the engine {}, changed meanwhile {}{}",
                r.matched,
                r.unmatched,
                r.refused,
                r.stale,
                if r.more { ", more waiting" } else { "" }
            );
        }
        RoadEvents::Stats => {
            let now = chrono::Utc::now();
            for s in lunaway_db::road_events::sources(pool).await? {
                let age = s.last_success_at.map_or_else(
                    || "never read".to_owned(),
                    |t| format!("read {} s ago", (now - t).num_seconds()),
                );
                println!("{:<18} {age}, stale after {} s", s.id, s.stale_after_s);
            }
            println!("source             class             placement  live");
            for (source, class, quality, n) in lunaway_db::road_events::live_counts(pool).await? {
                println!("{source:<18} {class:<17} {quality:<10} {n:>5}");
            }
        }
    }
    Ok(())
}

/// Whether `id` names a graph as the database accepts it:
/// `<YYYYMMDD>T<HHMM>Z-<area>`, the area 2 to 16 lower-case letters or
/// digits (the check of `routing_graphs.id`).
fn is_graph_id(id: &str) -> bool {
    let b = id.as_bytes();
    let digits =
        |r: std::ops::Range<usize>| b.get(r).is_some_and(|s| s.iter().all(u8::is_ascii_digit));
    let area = id.get(15..).unwrap_or_default();
    b.len() >= 17
        && digits(0..8)
        && b[8] == b'T'
        && digits(9..13)
        && b[13] == b'Z'
        && b[14] == b'-'
        && (2..=16).contains(&area.len())
        && area
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

async fn connect(url: Option<&str>) -> anyhow::Result<lunaway_db::PgPool> {
    let url = url.context("DATABASE_URL is not set")?;
    lunaway_db::connect(url, 4)
        .await
        .context("cannot reach the database (DATABASE_URL)")
}

#[allow(
    clippy::too_many_lines,
    reason = "one arm per subcommand, each a few prints"
)]
async fn routing(database_url: Option<&str>, cache: &Cache, action: Routing) -> anyhow::Result<()> {
    use lunaway_ingest::{graph_check, ign, routing as prep};
    match action {
        Routing::FetchIgn { refresh } => {
            let client = http::client().context("cannot build the HTTP client")?;
            let f = ign::fetch(&client, cache, refresh)
                .await
                .context("BD TOPO fetch failed")?;
            println!(
                "BD TOPO sections with a restriction: {} ({} skipped){}",
                f.sections.len(),
                f.skipped,
                if f.cached { ", from the cache" } else { "" }
            );
        }
        Routing::Prepare {
            pbf,
            out,
            graph_id,
            engine,
            no_ign,
            osm_data_at,
        } => {
            anyhow::ensure!(
                is_graph_id(&graph_id),
                "--graph-id must read like 20261006T0300Z-fr (the build's UTC time, then the area)"
            );
            // The data's date first: without it the long reading is wasted.
            // An explicit date wins over the header's.
            let header = prep::data_date(&pbf).context("cannot read the extract's header")?;
            let osm_data_at = osm_data_at
                .or(header)
                .context("the extract's header carries no date: give it with --osm-data-at")?;
            std::fs::create_dir_all(&out)
                .with_context(|| format!("cannot create {}", out.display()))?;
            let (sections, ign_fetched_at, ign_edition) = if no_ign {
                (Vec::new(), None, None)
            } else {
                // From the cache when `fetch-ign` filled it just before (the
                // build script does); from IGN otherwise.
                let client = http::client().context("cannot build the HTTP client")?;
                let f = ign::fetch(&client, cache, false)
                    .await
                    .context("BD TOPO sections unavailable")?;
                (f.sections, Some(f.fetched_at), f.edition)
            };
            let now = chrono::Utc::now();
            let path = pbf.clone();
            let ign_date = ign_fetched_at.unwrap_or(now);
            let mut prepared = tokio::task::spawn_blocking(move || {
                prep::prepare(&path, &sections, osm_data_at, ign_date)
            })
            .await
            .context("the preparation stopped")??;
            prepared.report.ign_edition = ign_edition;
            prep::write(&prepared, &out).context("cannot write the outputs")?;
            let info = BuildInfo {
                id: graph_id,
                osm_data_at,
                ign_fetched_at,
                ign_edition,
                built_at: now,
                engine,
            };
            std::fs::write(out.join("build.json"), serde_json::to_vec_pretty(&info)?)
                .context("cannot write build.json")?;
            println!("{}", serde_json::to_string_pretty(&prepared.report)?);
        }
        Routing::TestRoutes { url, cases } => {
            let client =
                http::client_allowing_plain_http().context("cannot build the HTTP client")?;
            let body = std::fs::read(&cases)
                .with_context(|| format!("cannot read {}", cases.display()))?;
            let outcomes = graph_check::run_all(&client, url.trim_end_matches('/'), &body)
                .await
                .context("the route tests could not run")?;
            let failed = outcomes.iter().filter(|o| !o.passed).count();
            for o in &outcomes {
                println!(
                    "{} {}: {}",
                    if o.passed { "pass" } else { "FAIL" },
                    o.name,
                    o.detail
                );
            }
            anyhow::ensure!(
                failed == 0,
                "{failed} of {} route tests failed",
                outcomes.len()
            );
            println!("all {} route tests passed", outcomes.len());
        }
        Routing::Load { bundle } => {
            let pool = connect(database_url).await?;
            let info: BuildInfo = serde_json::from_slice(
                &std::fs::read(bundle.join("build.json")).context("cannot read build.json")?,
            )
            .context("build.json is not a build description")?;
            let stats: serde_json::Value = serde_json::from_slice(
                &std::fs::read(bundle.join("prepare.json")).context("cannot read prepare.json")?,
            )
            .context("prepare.json is not JSON")?;
            let file = bundle.join("restrictions.ndjson.gz");
            let records = tokio::task::spawn_blocking(move || prep::read_records(&file))
                .await
                .context("reading the restrictions stopped")??;
            let n = lunaway_db::routing::load_graph(
                &pool,
                &lunaway_db::routing::NewGraph {
                    id: info.id.clone(),
                    osm_data_at: info.osm_data_at,
                    ign_fetched_at: info.ign_fetched_at,
                    ign_edition: info.ign_edition,
                    built_at: info.built_at,
                    engine: info.engine,
                    stats,
                },
                &records,
            )
            .await
            .context("cannot load the graph's restrictions")?;
            println!("graph {} loaded, inactive: {n} restrictions", info.id);
        }
        Routing::Activate { id } => {
            let pool = connect(database_url).await?;
            let done = lunaway_db::routing::activate(&pool, &id)
                .await?
                .with_context(|| format!("no graph {id} is loaded"))?;
            println!(
                "graph {id} active (before: {}); dropped: {}",
                done.previous.as_deref().unwrap_or("none"),
                if done.dropped.is_empty() {
                    "none".to_owned()
                } else {
                    done.dropped.join(", ")
                }
            );
        }
        Routing::Graphs => {
            let pool = connect(database_url).await?;
            for g in lunaway_db::routing::graphs(&pool).await? {
                println!(
                    "{}{}  data {}  built {}  {}",
                    g.id,
                    if g.active { " (active)" } else { "" },
                    g.osm_data_at.format("%Y-%m-%d %H:%M"),
                    g.built_at.format("%Y-%m-%d %H:%M"),
                    g.engine
                );
            }
        }
        Routing::Disputes { limit } => {
            let pool = connect(database_url).await?;
            let graph = lunaway_db::routing::active_graph(&pool)
                .await?
                .context("no active graph")?;
            for d in lunaway_db::routing::disputed(&pool, &graph.id, limit.clamp(1, 10_000)).await?
            {
                println!(
                    "{}  {:?}  applies {:?}, other source {:?}  {}  at {:.6},{:.6}",
                    d.external_id,
                    d.kind,
                    d.limit,
                    d.other_value,
                    d.name.unwrap_or_default(),
                    d.at.0,
                    d.at.1
                );
            }
        }
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
        Moderation::HidePoi { poi, note } => {
            if !lunaway_db::moderation::hide_poi(pool, poi, true, note.as_deref()).await? {
                anyhow::bail!("no point of interest {poi}");
            }
            println!("point {poi} hidden; the worker applies it within seconds");
            return Ok(());
        }
        Moderation::ShowPoi { poi } => {
            if !lunaway_db::moderation::hide_poi(pool, poi, false, None).await? {
                anyhow::bail!("no point of interest {poi}");
            }
            println!("point {poi} shown again; the worker applies it within seconds");
            return Ok(());
        }
        Moderation::RemoveRoadReport { report } => {
            if !lunaway_db::road_events::remove_report(pool, report).await? {
                anyhow::bail!("no active road report {report}");
            }
            println!("road report {report} removed; its event weighed again");
            return Ok(());
        }
        Moderation::EndRoadEvent { event } => {
            if !lunaway_db::road_events::end_community_event(pool, event).await? {
                anyhow::bail!("no live community road event {event}");
            }
            println!("community road event {event} ended, its reports removed");
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
    fn a_graph_name_is_checked_before_the_long_preparation() {
        assert!(is_graph_id("20261006T0300Z-fr"));
        assert!(is_graph_id("20261006T0000Z-e2e"));
        for bad in [
            "latest",
            "20261006T0300Z",
            "20261006T0300Z-FR",
            "2026106T0300Z-fr",
            "20261006T0300Z-f",
        ] {
            assert!(!is_graph_id(bad), "{bad}");
        }
    }

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
