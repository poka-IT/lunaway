//! `lunaway`: the operator's command.
//!
//! ```text
//! lunaway migrate [--list]
//! lunaway ingest osm [--region FR-BRE]... [--refresh]
//! lunaway ingest osm-extract [--extract NAME]... [--europe] [--refresh] [--max-age-hours 20]
//! lunaway ingest atout-france [--refresh]
//! lunaway ingest municipalities [--url URL] [--refresh]
//! lunaway ingest pois [--extract NAME]... [--europe] [--refresh] [--max-age-hours 20]
//! lunaway ingest fuel [--refresh]
//! lunaway ingest laposte [--refresh]
//! lunaway ingest finess [--refresh]
//! lunaway ingest datatourisme [--refresh]
//! lunaway content refresh [--source commons,...] [--max-places N] [--area S,W,N,E] [--stale-days 7]
//! lunaway content coverage [--area S,W,N,E] [--source NAME]
//! lunaway content gc
//! lunaway content hide photo|review <id> [--author] [--show]
//! lunaway content hide-place <place> <source> [--show]
//! lunaway content hide-source <source> [--show]
//! lunaway ingest extcom --file <path|url> [--refresh]
//! lunaway extcom status|hide|show [--note TEXT]
//! lunaway extcom purge [--yes] [--note TEXT]
//! lunaway extcom purge-media [--yes]
//! lunaway extcom erase-author <author-id> [--yes]
//! lunaway extcom erasures --out <file>
//! lunaway pois hours
//! lunaway pois stats
//! lunaway conflate [--full] [--watch [--every-secs 300]] [--poi-layer-every-mins 360]
//!                  [--place-layer-every-mins 15]
//! lunaway conflate --take-down <place> --reason-code CODE [--with-nearby] [--yes]
//! lunaway conflate --same|--distinct <source:id> <source:id> --note TEXT
//! lunaway takedowns import < FILE
//! lunaway takedowns replay [--dry-run] [--allow-empty]
//! lunaway stats
//! lunaway packs build --dir DIR [--region FR-BRE]...
//! lunaway packs list
//! lunaway moderation list [--limit 50]
//! lunaway moderation approve|reject <entry-id> [--note TEXT]
//! lunaway moderation ban <account-id> --reason TEXT
//! lunaway moderation dismiss-issues <place-id>
//! lunaway moderation hide-poi|show-poi <poi-id> [--note TEXT]
//! lunaway moderation confirmations <place-id> [--limit 50]
//! lunaway moderation remove-confirmation <confirmation-id>
//! lunaway moderation take-down <place-id> [--yes]
//! lunaway moderation purge-taken-down [--yes]
//! lunaway accounts create-demo [--level 2] [--pseudonym NAME]
//! lunaway accounts set-level <account-id> <level>
//! lunaway accounts find <pseudonym>
//! lunaway accounts delete <account-id> [--yes]
//! lunaway accounts replay-deletions [--dry-run]
//! lunaway retention
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
//! (`lunaway_ingest`); `moderation`, `accounts` and `retention` write
//! accounts and contributions, so they run with the API's role
//! (`lunaway_app`), whose
//! `DATABASE_URL` the API uses, and remove photo files under
//! `LUNAWAY_MEDIA_DIR` like the API, so they run as the API's user.
//! `accounts delete` writes the deletion to the journal under
//! `LUNAWAY_DELETION_JOURNAL` first, as the API does, and `accounts
//! replay-deletions` reads it after a restore (docs/deploy.md, "Backups
//! and restore").
//!
//! The takedown secret (`LUNAWAY_TAKEDOWN_SECRET`) keys the cells of each
//! takedown's exclusion zone: the conflation holds a new or moving place in
//! them, `conflate --take-down` and `takedowns replay` refuse to run
//! without it. `conflate --take-down` writes each takedown to the journal
//! under `LUNAWAY_TAKEDOWN_JOURNAL` before it commits, and `takedowns
//! replay` (import role) then `moderation purge-taken-down` (API role)
//! apply it again after a restore.
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
//! `content` reads the open content of the places with the import role
//! and writes the photos it keeps under `LUNAWAY_MEDIA_DIR/external/`;
//! `ingest datatourisme` needs the free key of the DATAtourisme API in
//! `LUNAWAY_DATATOURISME_KEY` (never an argument: the process list is
//! public on the machine).
//!
//! `DATABASE_URL` points at the database. Raw payloads are cached under
//! `LUNAWAY_DATA_DIR/raw` (default: the repository's gitignored `data/`), so
//! a re-run reads the disk unless `--refresh` is given.
//!
//! An import that stored its records but refused to retire the missing ones
//! (the fetch looked truncated) exits with an error after its report, so a
//! timer or a script sees it.

mod content;
mod extcom;
mod extracts;
mod packs;

use std::{path::PathBuf, time::Duration};

use anyhow::Context;
use clap::{Parser, Subcommand};
use lunaway_domain::{SourceId, conflation::ConstraintKind};
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
    /// Directory of the account deletion journal (the API's
    /// `LUNAWAY_DELETION_JOURNAL`, with the same default): `accounts
    /// delete` writes to it, `accounts replay-deletions` reads it after a
    /// restore.
    #[arg(long, env = "LUNAWAY_DELETION_JOURNAL", default_value_os_t = default_data_dir().join("account-deletions"))]
    deletion_journal: PathBuf,
    /// Directory of the takedown journal, outside the database: `conflate
    /// --take-down` writes to it, `takedowns replay` reads it after a
    /// restore.
    #[arg(long, env = "LUNAWAY_TAKEDOWN_JOURNAL", default_value_os_t = default_data_dir().join("place-takedowns"))]
    takedown_journal: PathBuf,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Applies the pending database migrations.
    Migrate {
        /// Prints the version of every migration this release carries, one
        /// a line, without reaching the database: a deploy compares them
        /// with those applied, and pauses the long jobs only when one is
        /// pending (`infra/server/install-release.sh`).
        #[arg(long)]
        list: bool,
    },
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
        /// Shortest time between two versions of the places layer's tiles,
        /// minutes: the places written meanwhile wait for the next one, so
        /// devices fetch their tiles again at most this often
        /// (`place_tiles::publish_layer`). A takedown publishes at once.
        #[arg(long, default_value_t = 15)]
        place_layer_every_mins: u64,
        /// Takes this place down for good instead of conflating: a private
        /// home listed as a spot, a request under the GDPR, a court order.
        /// It, the places merged into it and the records that describe them
        /// are emptied, no later import writes those records again, and the
        /// change feed tells every device. Then `moderation take-down`
        /// deletes its community content, and the region's pack is built
        /// again (both printed). Without `--yes`, prints what it touches.
        #[arg(long, value_name = "PLACE", conflicts_with_all = ["full", "watch"], requires = "reason_code")]
        take_down: Option<Uuid>,
        /// Accepted and ignored, for the scripts written before the codes:
        /// no text of a request is stored, it could name the requester.
        #[arg(long, requires = "take_down", hide = true)]
        reason: Option<String>,
        /// The kind of request, all the database and the journal outside it
        /// keep: private-home, gdpr, court-order or other.
        #[arg(long, requires = "take_down")]
        reason_code: Option<lunaway_domain::takedown::TakedownCode>,
        /// Takes it down for real.
        #[arg(long, requires = "take_down")]
        yes: bool,
        /// Also empties the retired records near the place that name no
        /// place (listed by the preview): they may be its own, unlinked
        /// before Lunaway kept the place a record leaves, or another
        /// spot's. Check the list first.
        #[arg(long, requires = "take_down")]
        with_nearby: bool,
        /// Records that two source records describe one spot, whatever
        /// their scores: the next run of the conflation puts them in one
        /// place (a human `must_link`, docs/conflation.md). Each is named
        /// `source:external_id`, as `osm:node/5327741281`.
        #[arg(
            long,
            num_args = 2,
            action = clap::ArgAction::Set,
            value_names = ["RECORD", "RECORD"],
            group = "decision",
            conflicts_with_all = ["full", "watch", "take_down", "distinct"],
            requires = "note"
        )]
        same: Option<Vec<String>>,
        /// Records that two source records describe two spots: the next
        /// run keeps them in two places (a human `cannot_link`).
        #[arg(
            long,
            num_args = 2,
            action = clap::ArgAction::Set,
            value_names = ["RECORD", "RECORD"],
            group = "decision",
            conflicts_with_all = ["full", "watch", "take_down"],
            requires = "note"
        )]
        distinct: Option<Vec<String>>,
        /// Why, kept with the decision: what was seen on the ground or in
        /// the sources, never who asked.
        #[arg(long, requires = "decision")]
        note: Option<String>,
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
    /// The open content of the places: photos, descriptions and reviews.
    Content {
        #[command(subcommand)]
        action: content::Content,
    },
    /// The takedown journal (with the import role): after a restore, takes
    /// down again what the restored database brought back.
    Takedowns {
        #[command(subcommand)]
        action: Takedowns,
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
    /// Applies the durations the privacy page states to the contribution
    /// tables (`lunaway_db::retention`), with the API's database role:
    /// daily, from a timer.
    Retention,
    /// Gives an address to the places no source gives a street or a town,
    /// by a reverse geocoding of their position on Lunaway's own Photon
    /// (`lunaway_domain::place_address`), with the import role: hourly,
    /// from a timer, until the places due are done. A place is asked once,
    /// and again when it moves.
    Addresses {
        /// Photon's base URLs, asked in order until one knows a feature
        /// near the place (Europe, then Morocco), separated by spaces or
        /// commas.
        #[arg(
            long = "photon",
            env = "LUNAWAY_GEOCODE_PHOTON_URL",
            value_delimiter = ',',
            required = true
        )]
        photon: Vec<String>,
        /// Requests per second at most.
        #[arg(long, default_value_t = 20)]
        rate: u32,
        /// Stops after this many minutes, once its page is written.
        #[arg(long, default_value_t = 50)]
        for_mins: u64,
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
    /// Speed cameras: what the API serves, built from the stored lists
    /// (with the import role).
    Enforcement {
        #[command(subcommand)]
        action: Enforcement,
    },
    /// The switch of the external community source: hide, show or purge
    /// everything it brought (with the import role; `purge-media` with the
    /// API's).
    Extcom {
        #[command(subcommand)]
        action: extcom::Extcom,
    },
}

#[derive(Subcommand)]
enum Enforcement {
    /// Builds the danger zones and the points each country allows from the
    /// stored cameras: daily after the lists, with `--full` after a new
    /// routing graph. The zones' secret comes from `LUNAWAY_ZONE_SECRET`
    /// (32 characters at least, never changed once zones are served).
    Build {
        /// Builds every item again, not only those whose cameras changed.
        #[arg(long)]
        full: bool,
        /// Retires the items gone even when they are more than a tenth of
        /// them (a country turned off): the guard against an engine without
        /// its graph is lifted.
        #[arg(long)]
        allow_retire: bool,
        /// The routing engine (loopback only).
        #[arg(long, env = "LUNAWAY_VALHALLA_URL")]
        valhalla_url: String,
    },
    /// Prints each list's last read and the items served by kind and
    /// country.
    Stats,
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
enum Takedowns {
    /// Writes into the takedown journal, each in the day it was made, the
    /// takedowns read from standard input: the lines of the journal's
    /// off-site copy, decrypted. After the loss of the data volume, before
    /// `replay`.
    Import,
    /// After a restore, puts back the cells of every journaled takedown,
    /// conflates what waits, and takes down again every journaled place
    /// the restored database holds alive. Then `moderation
    /// purge-taken-down --yes` (the API's role) deletes their community
    /// content. Run both before the API and the worker serve the restored
    /// database.
    Replay {
        /// Says what it would take down, writing nothing.
        #[arg(long)]
        dry_run: bool,
        /// Accepts a journal that names no takedown; otherwise refused,
        /// since a journal not put back after the loss of the data volume
        /// would bring takedowns back.
        #[arg(long)]
        allow_empty: bool,
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
    /// Prints the "still there?" answers of a place, newest first, with
    /// their author (none once the account is deleted).
    Confirmations {
        /// The place.
        place: Uuid,
        /// Answers printed at most.
        #[arg(long, default_value_t = 50)]
        limit: i64,
    },
    /// Removes a "still there?" answer, whoever wrote it (a false one, a
    /// test left without author); the place's "last confirmed" date is
    /// computed again.
    RemoveConfirmation {
        /// The answer.
        confirmation: Uuid,
    },
    /// The second step of a takedown, after `conflate --take-down` emptied
    /// the place: deletes its reviews, photos (files included), "still
    /// there?" answers and issue reports, and those of the places merged
    /// into it. Without `--yes`, prints what it would delete.
    TakeDown {
        /// The place; a place merged into another names the other.
        place: Uuid,
        /// Deletes for real.
        #[arg(long)]
        yes: bool,
    },
    /// After `takedowns replay`: the second step of every place taken down
    /// whose community content is still there (a restore brought it back).
    /// Without `--yes`, prints how many.
    PurgeTakenDown {
        /// Deletes for real.
        #[arg(long)]
        yes: bool,
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
    /// Prints the accounts of a pseudonym (case aside), with what each
    /// holds.
    Find {
        /// The pseudonym.
        pseudonym: String,
    },
    /// Deletes an account exactly as `deleteAccount` does (published
    /// reviews, confirmations and applied edits stay without author, the
    /// rest goes, photo files included), written first to the deletion
    /// journal. Without `--yes`, prints what it would delete.
    Delete {
        /// The account.
        account: Uuid,
        /// Deletes for real.
        #[arg(long)]
        yes: bool,
    },
    /// Writes into the deletion journal, each in the day it was made, the
    /// deletions read from standard input: the lines of the journal's
    /// off-site copy, decrypted. After the loss of the data volume, before
    /// `replay-deletions`.
    ImportDeletions,
    /// After a restore, deletes again every account the deletion journal
    /// names that the restored database still holds. Run it before the API
    /// serves the restored database.
    ReplayDeletions {
        /// Counts them without deleting.
        #[arg(long)]
        dry_run: bool,
        /// Accepts a journal that names no deletion (none in the days it
        /// keeps); otherwise refused, since a journal not put back after
        /// the loss of the data volume would bring deletions back.
        #[arg(long)]
        allow_empty: bool,
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
    /// The official speed camera lists (`docs/data-sources.md`, "Speed
    /// cameras"). Daily with `--refresh`, then `enforcement build`; each
    /// list is downloaded at its own pace, its cached copy read in between.
    Cameras {
        /// Only these lists (`france`, `poland`, `luxembourg`, `norway`...),
        /// comma separated; all when absent.
        #[arg(long = "list", value_delimiter = ',')]
        lists: Vec<String>,
        /// Downloads each list whose cached copy is as old as its period
        /// (a day, a week or a month) instead of reading the copy.
        #[arg(long)]
        refresh: bool,
        /// Downloads every list asked, whatever the age of its copy.
        #[arg(long, conflicts_with = "refresh")]
        force: bool,
        /// Stores a yearly file that adds and removes more than a tenth of
        /// the cameras stored, which is otherwise refused: once its cause
        /// is known (a new shape read and checked, a wave of new cameras).
        #[arg(long)]
        allow_change: bool,
    },
    /// OpenStreetMap's speed cameras, from the extracts the places import
    /// downloads. Weekly, before the build that follows a new routing
    /// graph.
    CamerasOsm {
        #[command(flatten)]
        extracts: extracts::ExtractArgs,
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
    /// DATAtourisme's motorhome areas, service areas and campsites (the
    /// French tourist offices), as records the conflation merges; their
    /// descriptions and photos reach the card through `content refresh`.
    /// Weekly, before it.
    Datatourisme {
        /// Asks the API again instead of reading today's pages.
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
    /// The external community source: a partner's feed received under a
    /// written agreement (`docs/feeds.md`), JSON Lines, gzip accepted. A
    /// feed without an agreement in force is refused; a stopped run
    /// resumes after the last batch it stored.
    Extcom {
        /// The feed: a file, or the `https://` URL the partner gave.
        #[arg(long)]
        file: String,
        /// Downloads a URL again instead of reading the cache.
        #[arg(long)]
        refresh: bool,
        /// The reference of the signed agreement, set at deploy time: the
        /// feed must name it, and every row stores it as its licence.
        #[arg(long, env = "LUNAWAY_EXTCOM_AGREEMENT_REF", hide_env_values = true)]
        agreement_ref: Option<String>,
        /// The hosts photos may be downloaded from, comma separated.
        #[arg(
            long,
            env = "LUNAWAY_EXTCOM_PHOTO_HOSTS",
            value_delimiter = ',',
            hide_env_values = true
        )]
        photo_hosts: Vec<String>,
    },
}

/// Prints what an import of the external community feed did.
fn print_extcom(r: &lunaway_ingest::extcom::Report) {
    println!(
        "agreement {}, feed {}{}{}",
        r.agreement,
        &r.feed_sha256[..r.feed_sha256.len().min(16)],
        if r.cached { ", from the cache" } else { "" },
        if r.resumed_after > 0 {
            format!(", resumed after line {}", r.resumed_after)
        } else {
            String::new()
        }
    );
    println!(
        "lines: {}, places: {}, dropped: {:?}, reviews dropped: {}, photos dropped: {}",
        r.lines, r.places, r.dropped, r.reviews_dropped, r.photos_dropped
    );
    if !r.unmapped.is_empty() {
        println!(
            "codes no table maps (add them to lunaway_ingest::extcom): {:?}",
            r.unmapped
        );
    }
    println!(
        "{} feed; records: {} inserted, {} changed, {} unchanged; {} marked deleted, {} retired; \
         licences set: {}",
        if r.complete { "complete" } else { "delta" },
        r.records.inserted,
        r.records.changed,
        r.records.unchanged,
        r.marked_deleted,
        r.retired,
        r.licences_set
    );
    let f = &r.forgotten;
    println!(
        "forgotten with the retired spots: {} records emptied, {} reviews, {} ratings, {} \
         photos; skipped of erased authors: {}",
        f.records, f.reviews, f.ratings, f.photos, r.erased_skipped
    );
    let x = &r.extras;
    println!(
        "reviews: {} written, {} removed; rating summaries: {} written; photos: {} written, {} \
         retired",
        x.reviews_written, x.reviews_removed, x.ratings_written, x.photos_written, x.photos_retired
    );
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
/// The journal's directory as the API reads `LUNAWAY_DELETION_JOURNAL`:
/// trimmed, and `off` (how the API runs without a journal) or empty names
/// none, so a deletion is refused rather than journaled into `./off`.
fn journal_dir(raw: PathBuf) -> Option<PathBuf> {
    match raw.to_str().map(str::trim) {
        Some("off" | "") => None,
        Some(trimmed) => Some(PathBuf::from(trimmed)),
        None => Some(raw),
    }
}

fn default_data_dir() -> PathBuf {
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../data"))
}

/// The exit status of a run that failed because the database went away
/// (`EX_TEMPFAIL` of sysexits.h): the import units run it again 15 minutes
/// later (`RestartForceExitStatus=75`, docs/deploy.md, "Data pipeline"), and
/// no other failure. A source that refused us must not be asked again
/// before its next run (`.claude/rules/data-sources.md`).
const EXIT_DATABASE_LOST: u8 = 75;

/// How a failed run exits: [`EXIT_DATABASE_LOST`] when the database went
/// away under it, 1 otherwise.
fn exit_status(error: &anyhow::Error) -> u8 {
    if error.chain().any(lunaway_db::connection_lost) {
        EXIT_DATABASE_LOST
    } else {
        1
    }
}

#[tokio::main]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            // The error and each of its causes, for the journal.
            eprintln!("Error: {error:?}");
            std::process::ExitCode::from(exit_status(&error))
        }
    }
}

async fn run() -> anyhow::Result<()> {
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
        Command::Migrate { list: true } => {
            for version in migration_versions() {
                println!("{version}");
            }
            return Ok(());
        }
        other => other,
    };
    let pool = connect(cli.database_url.as_deref()).await?;

    match command {
        Command::Migrate { .. } => {
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
                Source::Cameras {
                    lists,
                    refresh,
                    force,
                    allow_change,
                } => {
                    use lunaway_ingest::cameras::{self, CameraList, ChangeGuard, Refresh};
                    let guard = if allow_change {
                        ChangeGuard::Lift
                    } else {
                        ChangeGuard::Hold
                    };
                    let refresh = match (force, refresh) {
                        (true, _) => Refresh::Always,
                        (false, true) => Refresh::WhenDue,
                        (false, false) => Refresh::Never,
                    };
                    let chosen: Vec<CameraList> = if lists.is_empty() {
                        CameraList::ALL.to_vec()
                    } else {
                        lists
                            .iter()
                            .map(|n| {
                                CameraList::named(n).with_context(|| {
                                    let names: Vec<&str> =
                                        CameraList::ALL.iter().map(|l| l.name()).collect();
                                    format!("unknown list {n}; one of {}", names.join(", "))
                                })
                            })
                            .collect::<anyhow::Result<_>>()?
                    };
                    let mut refused = Vec::new();
                    let mut failed = Vec::new();
                    println!(
                        "list                  rows  cameras  skipped  not stored  written  retired  read"
                    );
                    for list in chosen {
                        match cameras::import(&pool, &client, &cache, list, refresh, guard).await {
                            Ok(r) => {
                                println!(
                                    "{:<20} {:>5}  {:>7}  {:>7}  {:>10}  {:>7}  {:>7}  {}{}",
                                    list.source().as_str(),
                                    r.rows,
                                    r.devices,
                                    r.skipped,
                                    r.not_stored,
                                    r.written,
                                    r.retired,
                                    r.fetched_at,
                                    if r.cached { " (cache)" } else { "" }
                                );
                                if r.retire_refused {
                                    refused.push(list.source().as_str().to_owned());
                                }
                            }
                            // One list down does not stop the others.
                            Err(e) => {
                                tracing::error!(source = %list.source(), error = %e, "camera list failed");
                                failed.push(list.source().as_str().to_owned());
                            }
                        }
                    }
                    let refused: Vec<&str> = refused.iter().map(String::as_str).collect();
                    check_retirement(&refused)?;
                    anyhow::ensure!(
                        failed.is_empty(),
                        "camera lists failed: {}",
                        failed.join(", ")
                    );
                }
                Source::CamerasOsm { extracts } => {
                    let plan = extracts.plan()?;
                    let r = lunaway_ingest::cameras_osm::import(
                        &pool,
                        &client,
                        &cache,
                        &plan.extracts,
                        &plan.mirror,
                        plan.refresh,
                        plan.retry,
                    )
                    .await
                    .context("OpenStreetMap camera import failed")?;
                    for (name, n) in &r.extracts {
                        println!("{name:<30} {n:>6} cameras");
                    }
                    println!("written: {}, retired: {}", r.written, r.retired);
                    let refused: Vec<&str> = r.refused.iter().map(String::as_str).collect();
                    check_retirement(&refused)?;
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
                Source::Datatourisme { refresh } => {
                    content::ingest_datatourisme(&pool, &cache, refresh).await?;
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
                Source::Extcom {
                    file,
                    refresh,
                    agreement_ref,
                    photo_hosts,
                } => {
                    let reference = agreement_ref.context(
                        "LUNAWAY_EXTCOM_AGREEMENT_REF is not set: a feed is imported only under \
                         the agreement the server is configured with",
                    )?;
                    let hosts: Vec<String> = photo_hosts
                        .into_iter()
                        .filter(|h| !h.trim().is_empty())
                        .collect();
                    let terms = lunaway_domain::extcom::Terms::new(&reference, &hosts)
                        .context("LUNAWAY_EXTCOM_AGREEMENT_REF or LUNAWAY_EXTCOM_PHOTO_HOSTS")?;
                    let options = lunaway_ingest::extcom::Options {
                        terms,
                        limits: lunaway_ingest::extcom::Limits::default(),
                        refresh,
                        today: chrono::Utc::now().date_naive(),
                    };
                    let r = lunaway_ingest::extcom::import(
                        &pool,
                        &client,
                        &cache,
                        &lunaway_ingest::extcom::Input::parse(&file),
                        &options,
                    )
                    .await
                    .context("extcom import failed")?;
                    print_extcom(&r);
                    check_retirement(if r.retire_refused { &["extcom"] } else { &[] })?;
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
            take_down: Some(place),
            reason,
            reason_code,
            yes,
            with_nearby,
            ..
        } => {
            if reason.is_some() {
                // Never echoed: the text is what must not be kept.
                eprintln!("--reason is ignored: only --reason-code is stored");
            }
            let code = reason_code.context(
                "--take-down needs --reason-code: private-home, gdpr, court-order or other",
            )?;
            let journal = journal_dir(cli.takedown_journal)
                .map(lunaway_db::takedown_journal::TakedownJournal::new);
            take_down(
                &pool,
                journal.as_ref(),
                lunaway_conflate::takedown::Request {
                    place,
                    code,
                    with_nearby,
                },
                yes,
            )
            .await?;
        }
        Command::Conflate {
            same: Some(pair),
            note,
            ..
        } => {
            let note = note.context("--same needs --note")?;
            link(&pool, pair, ConstraintKind::MustLink, &note).await?;
        }
        Command::Conflate {
            distinct: Some(pair),
            note,
            ..
        } => {
            let note = note.context("--distinct needs --note")?;
            link(&pool, pair, ConstraintKind::CannotLink, &note).await?;
        }
        Command::Takedowns { action } => {
            let journal = journal_dir(cli.takedown_journal)
                .map(lunaway_db::takedown_journal::TakedownJournal::new);
            takedowns(&pool, journal.as_ref(), action).await?;
        }
        Command::Conflate {
            full,
            watch,
            every_secs,
            poi_layer_every_mins,
            place_layer_every_mins,
            ..
        } => {
            let poi_layer_every = Duration::from_secs(poi_layer_every_mins.saturating_mul(60));
            let place_layer_every = Duration::from_secs(place_layer_every_mins.saturating_mul(60));
            if full {
                let n = lunaway_db::records::mark_all_dirty(&pool).await?;
                println!("{n} records flagged for a full rebuild");
            }
            let key = takedown_key_or_warn()?;
            if watch {
                tracing::info!(every_secs, "conflation worker started");
                lunaway_conflate::watch(
                    &pool,
                    Duration::from_secs(every_secs.max(1)),
                    poi_layer_every,
                    place_layer_every,
                    chrono::Utc::now,
                    key.as_ref(),
                )
                .await
                .context("the conflation worker cannot listen")?;
                return Ok(());
            }
            let s = lunaway_conflate::run(&pool, chrono::Utc::now(), key.as_ref())
                .await
                .context("conflation failed")?;
            if let Some(v) = lunaway_conflate::pois::publish_layer(&pool, poi_layer_every)
                .await
                .context("publishing the points layer failed")?
            {
                println!("points layer: tiles version {v}");
            }
            let rated = lunaway_conflate::refresh_filter_ratings(&pool)
                .await
                .context("the filter ratings failed")?;
            println!("filter ratings changed: {rated}");
            if let Some(v) = lunaway_conflate::publish_place_layer(&pool, place_layer_every)
                .await
                .context("publishing the places layer failed")?
            {
                println!("places layer: tiles version {v}");
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
            if s.held_near_takedown > 0 {
                println!(
                    "groups held near a place taken down: {} ({} new in the moderation queue)",
                    s.held_near_takedown, s.new_holds
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
            if s.takedowns_unpurged > 0 {
                println!(
                    "places taken down whose community content is still there: {} \
                     (`moderation take-down <place> --yes`)",
                    s.takedowns_unpurged
                );
            }
            if s.holds_open > 0 {
                println!(
                    "places held near a place taken down, waiting for a moderator: {} \
                     (`moderation list`)",
                    s.holds_open
                );
            }
            println!(
                "opening hours: {} places, {} parsed",
                s.opening_hours.0, s.opening_hours.1
            );
        }
        Command::Content { action } => {
            let client = http::client().context("cannot build the HTTP client")?;
            content::run(&pool, &client, &cli.media_dir, action).await?;
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
        Command::Accounts { action } => {
            let media = lunaway_media::MediaStore::new(cli.media_dir);
            let journal =
                journal_dir(cli.deletion_journal).map(lunaway_db::deletions::DeletionJournal::new);
            accounts(&pool, &media, journal.as_ref(), action).await?;
        }
        Command::Addresses {
            photon,
            rate,
            for_mins,
        } => {
            let config = lunaway_ingest::reverse_geocode::ReverseConfig {
                urls: photon
                    .iter()
                    .flat_map(|u| u.split_whitespace())
                    .map(str::to_owned)
                    .collect(),
                pace: Duration::from_secs(1) / rate.max(1),
                ..lunaway_ingest::reverse_geocode::ReverseConfig::default()
            };
            let client = http::loopback_client().context("cannot build the HTTP client")?;
            let s = lunaway_ingest::reverse_geocode::run(
                &pool,
                &client,
                &config,
                Duration::from_secs(for_mins * 60),
            )
            .await
            .context("the reverse geocoding of the places failed")?;
            println!(
                "addresses: {} places asked, {} with a street, {} with a town, {} written",
                s.asked, s.with_street, s.with_town, s.written
            );
        }
        Command::Retention => {
            let s = lunaway_db::retention::sweep(&pool, chrono::Utc::now()).await?;
            println!(
                "retention: {} issue reports, {} content reports, {} moderation entries, \
                 {} confirmations deleted; {} submissions emptied; {} banned key hashes, \
                 {} stale translations deleted",
                s.issue_reports,
                s.content_reports,
                s.moderation_entries,
                s.confirmations,
                s.submission_payloads,
                s.banned_keys,
                s.translations
            );
        }
        Command::RoadEvents { action } => road_events(&pool, &cache, action).await?,
        Command::Enforcement { action } => enforcement(&pool, action).await?,
        Command::Extcom { action } => {
            let media = lunaway_media::MediaStore::new(cli.media_dir);
            extcom::run(&pool, &media, &cache.root().join("extcom"), action).await?;
        }
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
            "lifecycle: {} past their end, {} expired, {} entered the phones' window, \
             {} purged, {} reports purged",
            l.past_end, l.expired, l.entered_window, l.purged, l.reports_purged
        );
    }
}

/// Shortest secret accepted for the zones.
const MIN_ZONE_SECRET: usize = 32;

async fn enforcement(pool: &lunaway_db::PgPool, action: Enforcement) -> anyhow::Result<()> {
    use lunaway_db::enforcement as db;
    match action {
        Enforcement::Build {
            full,
            allow_retire,
            valhalla_url,
        } => {
            let secret =
                std::env::var("LUNAWAY_ZONE_SECRET").context("LUNAWAY_ZONE_SECRET is not set")?;
            anyhow::ensure!(
                secret.len() >= MIN_ZONE_SECRET,
                "LUNAWAY_ZONE_SECRET must hold {MIN_ZONE_SECRET} characters at least"
            );
            let engine = lunaway_ingest::road_events::matching::Valhalla::new(
                &valhalla_url,
                Duration::from_secs(10),
            )
            .context("the routing engine must be a loopback http URL")?;
            let r = lunaway_ingest::enforcement::build(
                pool,
                &engine,
                secret.as_bytes(),
                full,
                allow_retire,
            )
            .await
            .context("speed camera build failed")?;
            println!(
                "cameras: {} ({} OpenStreetMap nodes merged, {} left out, {} alone; France's \
                 yearly file: {} rows merged into the map, {} the map retired, {} alone)",
                r.cameras,
                r.merged.matched,
                r.merged.left_out,
                r.merged.alone,
                r.merged.dsr_matched,
                r.merged.dsr_left_out,
                r.merged.dsr_alone
            );
            println!(
                "built: {} zones, {} points ({} for the clients that chose positions), {} unplaced, \
                 {} unchanged, {} in countries that are off",
                r.zones, r.points, r.opt_in, r.unplaced, r.unchanged, r.off
            );
            println!(
                "engine calls: {}; items written: {}, retired: {}",
                r.engine_calls, r.written, r.retired
            );
            if r.retire_refused {
                anyhow::bail!(
                    "retiring refused: the build would drop more than a tenth of the items, for \
                     the clients without a choice or for those with one (an engine without the \
                     graph?); new and changed items were written"
                );
            }
        }
        Enforcement::Stats => {
            for s in db::source_reads(pool).await? {
                println!(
                    "{:<20} {:>6} cameras, read {}",
                    s.source.id.as_str(),
                    s.devices,
                    s.fetched_at
                );
            }
            for c in db::item_counts(pool).await? {
                println!(
                    "{:<7} {:<8} {} {:>6}",
                    c.kind.code(),
                    c.variant.code(),
                    c.country,
                    c.n
                );
            }
        }
    }
    Ok(())
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

/// The versions of the migrations this release carries, in order.
fn migration_versions() -> Vec<i64> {
    lunaway_db::MIGRATOR.iter().map(|m| m.version).collect()
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
        Moderation::Confirmations { place, limit } => {
            let rows =
                lunaway_db::moderation::confirmations_of_place(pool, place, limit.clamp(1, 1_000))
                    .await?;
            if rows.is_empty() {
                println!("no confirmation of {place}");
            }
            for c in rows {
                println!(
                    "{}  {}  {:<8}  {}  by {}",
                    c.id,
                    c.created_at.format("%Y-%m-%d %H:%M:%S UTC"),
                    c.status,
                    c.place_id,
                    match (&c.author, c.account_id) {
                        (Some(name), Some(id)) => format!("{name} ({id})"),
                        _ => "a deleted account".to_owned(),
                    }
                );
            }
            return Ok(());
        }
        Moderation::TakeDown { place, yes } => {
            return purge_taken_down(pool, media, place, yes).await;
        }
        Moderation::PurgeTakenDown { yes } => {
            return purge_every_taken_down(pool, media, yes).await;
        }
        Moderation::RemoveConfirmation { confirmation } => {
            let Some(place) =
                lunaway_db::moderation::remove_confirmation(pool, confirmation).await?
            else {
                anyhow::bail!("no confirmation {confirmation}");
            };
            println!("confirmation {confirmation} removed; place {place} queued for the worker");
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

fn print_preview(asked: Uuid, p: &lunaway_db::takedowns::Preview) {
    println!(
        "{}{}  {}  {}  region {}",
        p.place,
        if p.place == asked {
            String::new()
        } else {
            format!(" (which absorbed {asked})")
        },
        p.name.as_deref().unwrap_or("(no name)"),
        match (p.taken_down, p.live) {
            (true, _) => "taken down",
            (false, true) => "live",
            (false, false) => "a tombstone",
        },
        p.region.as_deref().unwrap_or("none"),
    );
    println!(
        "    merged places {}  records {}  reviews {}  photos {}  confirmations {}  \
         issues {}  submissions {}",
        p.merged, p.records, p.reviews, p.photos, p.confirmations, p.issue_reports, p.submissions
    );
    if p.unconflated > 0 {
        println!(
            "    {} records near it wait for the conflation (conflated first with --yes)",
            p.unconflated
        );
    }
    if !p.nearby.is_empty() {
        println!(
            "    retired records near it that name no place (emptied with --with-nearby only):"
        );
        for n in &p.nearby {
            println!(
                "      {} {}  {}  {}  {:.0} m",
                n.source_id,
                n.external_id,
                n.kind,
                n.name.as_deref().unwrap_or("(no name)"),
                n.distance_m
            );
        }
    }
}

/// The takedown secret from `LUNAWAY_TAKEDOWN_SECRET`; `None` when unset.
/// A value that is not UTF-8 is an error, never taken for an unset one.
fn takedown_key() -> anyhow::Result<Option<lunaway_domain::takedown::TakedownKey>> {
    let value = match std::env::var("LUNAWAY_TAKEDOWN_SECRET") {
        Ok(v) => Some(v),
        Err(std::env::VarError::NotPresent) => None,
        Err(std::env::VarError::NotUnicode(_)) => {
            anyhow::bail!("LUNAWAY_TAKEDOWN_SECRET is not UTF-8")
        }
    };
    lunaway_domain::takedown::TakedownKey::from_env_value(value.as_deref())
        .context("LUNAWAY_TAKEDOWN_SECRET")
}

/// [`takedown_key`] for the conflation, which runs without it and says so
/// once: nothing is held near the places taken down.
fn takedown_key_or_warn() -> anyhow::Result<Option<lunaway_domain::takedown::TakedownKey>> {
    let key = takedown_key()?;
    if key.is_none() {
        tracing::warn!(
            "LUNAWAY_TAKEDOWN_SECRET is not set: no place is held near a place taken down"
        );
    }
    Ok(key)
}

/// [`takedown_key`] for a takedown or its replay, which refuse to run
/// without it: the positions go, and the zone cannot be made later.
fn takedown_key_required() -> anyhow::Result<lunaway_domain::takedown::TakedownKey> {
    takedown_key()?.context(
        "LUNAWAY_TAKEDOWN_SECRET is not set: a takedown keeps the hashes of the cells around \
         the place, keyed by it, and cannot make them once the positions are gone \
         (docs/deploy.md, \"Private settings\")",
    )
}

/// `conflate --take-down`: the catalogue's step of a takedown, under the
/// writers' lock with the importers' role, after a conflation of what
/// waits (a record not read yet could become the place again), journaled
/// outside the database before it commits.
async fn take_down(
    pool: &lunaway_db::PgPool,
    journal: Option<&lunaway_db::takedown_journal::TakedownJournal>,
    request: lunaway_conflate::takedown::Request,
    yes: bool,
) -> anyhow::Result<()> {
    use lunaway_db::takedowns::{self, TakeDown};
    let place = request.place;
    let Some(p) = takedowns::preview(pool, place).await? else {
        anyhow::bail!("no place {place}");
    };
    print_preview(place, &p);
    if !yes {
        println!("not taken down: run again with --yes to empty it for good");
        return Ok(());
    }
    let key = takedown_key_required()?;
    let journal = journal.context(
        "LUNAWAY_TAKEDOWN_JOURNAL is off: a takedown must be journaled outside the database \
         (--takedown-journal DIR)",
    )?;
    let done = match lunaway_conflate::takedown::take_down(
        pool,
        &key,
        journal,
        request,
        chrono::Utc::now(),
    )
    .await?
    {
        TakeDown::Done(done) => done,
        TakeDown::NoPlace => anyhow::bail!("place {place} disappeared meanwhile"),
        TakeDown::Unconflated(n) => anyhow::bail!(
            "{n} records near the place arrived since the conflation; nothing done, run again"
        ),
        TakeDown::OtherKey => anyhow::bail!(
            "LUNAWAY_TAKEDOWN_SECRET is not the secret the earlier takedowns were made with: \
             nothing done; put the right one back (its encrypted copy is in the backups)"
        ),
    };
    println!(
        "{} taken down: {} places and {} records emptied, {} cells around it kept as hashes; \
         the change feed tells every device",
        done.place,
        done.places,
        done.records,
        done.cells.len()
    );
    println!(
        "next, at once (its photos stay served until then): \
         lunaway moderation take-down {} --yes",
        done.place
    );
    if let Some(region) = done.region {
        println!("then: lunaway packs build --region {region} --takedown");
    }
    Ok(())
}

/// `takedowns import` and `takedowns replay`.
async fn takedowns(
    pool: &lunaway_db::PgPool,
    journal: Option<&lunaway_db::takedown_journal::TakedownJournal>,
    action: Takedowns,
) -> anyhow::Result<()> {
    let journal = journal.context(
        "LUNAWAY_TAKEDOWN_JOURNAL is off: name the journal's directory (--takedown-journal DIR)",
    )?;
    match action {
        Takedowns::Import => {
            let lines = tokio::task::spawn_blocking(|| {
                let mut lines = String::new();
                std::io::Read::read_to_string(&mut std::io::stdin(), &mut lines).map(|_| lines)
            })
            .await?
            .context("reading the takedowns from standard input")?;
            let copy = journal.clone();
            let imported =
                tokio::task::spawn_blocking(move || copy.import_blocking(&lines)).await??;
            println!(
                "journal {}: {} takedowns written into their days, {} unreadable lines",
                journal.dir().display(),
                imported.written,
                imported.unreadable
            );
        }
        Takedowns::Replay {
            dry_run,
            allow_empty,
        } => {
            let key = takedown_key_required()?;
            let r = lunaway_conflate::takedown::replay(
                pool,
                &key,
                journal,
                dry_run,
                allow_empty,
                chrono::Utc::now(),
            )
            .await?;
            println!(
                "journal {}: {} takedowns, {} unreadable lines; {} places already taken down, \
                 {} not in this database",
                journal.dir().display(),
                r.takedowns,
                r.unreadable,
                r.already,
                r.absent
            );
            if dry_run {
                println!(
                    "would take down again (nothing written: dry run): {}",
                    r.would_take_down.len()
                );
                for p in &r.would_take_down {
                    println!("  {p}");
                }
            } else {
                println!(
                    "cells put back: {}; places taken down again: {}",
                    r.cells,
                    r.taken_down.len()
                );
                for d in &r.taken_down {
                    println!("  {} ({} places, {} records)", d.place, d.places, d.records);
                    if let Some(region) = &d.region {
                        println!("  then: lunaway packs build --region {region} --takedown");
                    }
                }
                if !r.taken_down.is_empty() {
                    println!("next, at once: lunaway moderation purge-taken-down --yes");
                }
            }
            for (id, stranger) in &r.to_check {
                println!(
                    "{id} is merged with {stranger} in this database, which the journal does not \
                     name: nothing done; check them and take the spot down by hand \
                     (lunaway conflate --take-down)"
                );
            }
        }
    }
    Ok(())
}

/// `moderation take-down`: the community's step of a takedown, with the
/// API's role, once the place is emptied.
async fn purge_taken_down(
    pool: &lunaway_db::PgPool,
    media: &lunaway_media::MediaStore,
    place: Uuid,
    yes: bool,
) -> anyhow::Result<()> {
    use lunaway_db::takedowns::{self, Purge};
    let Some(p) = takedowns::preview(pool, place).await? else {
        anyhow::bail!("no place {place}");
    };
    print_preview(place, &p);
    anyhow::ensure!(
        p.taken_down,
        "{} is not taken down: run `lunaway conflate --take-down {} --reason TEXT --yes` \
         first (the importers' role), so that nothing arrives after this step",
        p.place,
        p.place
    );
    if !yes {
        println!("nothing deleted: run again with --yes");
        return Ok(());
    }
    match takedowns::purge_community(pool, place).await? {
        Purge::NoPlace => anyhow::bail!("no place {place}"),
        Purge::NotTakenDown => anyhow::bail!("{place} is not taken down"),
        Purge::Done {
            place,
            reviews,
            photos,
            confirmations,
            issue_reports,
            orphan_files,
        } => {
            println!(
                "{place}: {reviews} reviews, {photos} photos, {confirmations} confirmations and \
                 {issue_reports} issue reports deleted"
            );
            remove_files(media, &orphan_files).await
        }
    }
}

/// `moderation purge-taken-down`: the community's step of every place
/// taken down whose content is still there, after a restore and
/// `takedowns replay`.
async fn purge_every_taken_down(
    pool: &lunaway_db::PgPool,
    media: &lunaway_media::MediaStore,
    yes: bool,
) -> anyhow::Result<()> {
    use lunaway_db::takedowns::{self, Purge};
    let places = takedowns::unpurged(pool).await?;
    println!(
        "places taken down whose community content is still there: {}",
        places.len()
    );
    if !yes {
        if !places.is_empty() {
            println!("nothing deleted: run again with --yes");
        }
        return Ok(());
    }
    for place in places {
        if let Purge::Done {
            place,
            reviews,
            photos,
            confirmations,
            issue_reports,
            orphan_files,
        } = takedowns::purge_community(pool, place).await?
        {
            println!(
                "{place}: {reviews} reviews, {photos} photos, {confirmations} confirmations and \
                 {issue_reports} issue reports deleted"
            );
            remove_files(media, &orphan_files).await?;
        }
    }
    Ok(())
}

fn print_summary(s: &lunaway_db::accounts::AccountSummary) {
    let a = &s.account;
    println!(
        "{}  {}  created {}  level {} (granted {}){}",
        a.id,
        a.pseudonym,
        a.created_at.format("%Y-%m-%d %H:%M UTC"),
        a.trust_level,
        a.granted_level,
        a.banned_at
            .map(|b| format!("  banned {}", b.format("%Y-%m-%d")))
            .unwrap_or_default()
    );
    println!(
        "    devices {}  reviews {}  photos {}  confirmations {}  issues {}  \
         submissions {}  road reports {}",
        s.devices, s.reviews, s.photos, s.confirmations, s.issues, s.submissions, s.road_reports
    );
}

async fn accounts(
    pool: &lunaway_db::PgPool,
    media: &lunaway_media::MediaStore,
    journal: Option<&lunaway_db::deletions::DeletionJournal>,
    action: Accounts,
) -> anyhow::Result<()> {
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
        Accounts::Find { pseudonym } => {
            let found = lunaway_db::accounts::find_by_pseudonym(pool, &pseudonym).await?;
            if found.is_empty() {
                println!("no account named {pseudonym:?}");
            }
            for s in &found {
                print_summary(s);
            }
        }
        Accounts::Delete { account, yes } => {
            let Some(summary) = lunaway_db::accounts::summary(pool, account).await? else {
                anyhow::bail!("no account {account}");
            };
            print_summary(&summary);
            if !yes {
                println!(
                    "not deleted: run again with --yes to delete it as deleteAccount does \
                     (published reviews, confirmations and applied edits stay without author)"
                );
                return Ok(());
            }
            // A deletion missing from the journal would come back with the
            // next restore: on the server the journal is required.
            let journal = journal.context(
                "LUNAWAY_DELETION_JOURNAL is off: a deletion must be journaled \
                 (--deletion-journal DIR)",
            )?;
            let deleted =
                lunaway_db::deletions::delete_recorded(pool, Some(journal), account).await?;
            let Some(d) = deleted else {
                anyhow::bail!("account {account} disappeared meanwhile");
            };
            println!(
                "account {account} deleted: {} published reviews kept without author, \
                 {} photos deleted",
                d.anonymised_reviews, d.deleted_photos
            );
            remove_files(media, &d.orphan_files).await?;
        }
        Accounts::ImportDeletions => {
            let journal = journal.context(
                "LUNAWAY_DELETION_JOURNAL is off: name the journal's directory \
                 (--deletion-journal DIR)",
            )?;
            let lines = tokio::task::spawn_blocking(|| {
                let mut lines = String::new();
                std::io::Read::read_to_string(&mut std::io::stdin(), &mut lines).map(|_| lines)
            })
            .await?
            .context("reading the deletions from standard input")?;
            let imported = journal.import(lines).await?;
            println!(
                "journal {}: {} deletions written into their days, {} unreadable lines",
                journal.dir().display(),
                imported.written,
                imported.unreadable
            );
        }
        Accounts::ReplayDeletions {
            dry_run,
            allow_empty,
        } => {
            let journal = journal.context(
                "LUNAWAY_DELETION_JOURNAL is off: name the journal's directory \
                 (--deletion-journal DIR)",
            )?;
            let r = lunaway_db::deletions::replay(pool, journal, dry_run, allow_empty).await?;
            if dry_run {
                println!(
                    "journal {}: {} accounts, {} of them still in this database \
                     (nothing deleted: dry run), {} unreadable lines",
                    journal.dir().display(),
                    r.accounts,
                    r.deleted,
                    r.unreadable
                );
            } else {
                println!(
                    "journal {}: {} accounts, {} deleted again, {} unreadable lines",
                    journal.dir().display(),
                    r.accounts,
                    r.deleted,
                    r.unreadable
                );
                remove_files(media, &r.orphan_files).await?;
            }
        }
    }
    Ok(())
}

/// A source record named `source:external_id` (`osm:node/5327741281`,
/// `datatourisme:<uuid>`): the source before the first colon, the id after
/// it, colons included.
fn record_ref(text: &str) -> anyhow::Result<(SourceId, &str)> {
    let (source, external) = text
        .split_once(':')
        .filter(|(_, external)| !external.is_empty())
        .with_context(|| format!("{text:?}: a record is named `source:external_id`"))?;
    let source = SourceId::new(source).with_context(|| format!("{text:?}: not a source id"))?;
    Ok((source, external))
}

/// The id of the record `text` names ([`record_ref`]).
async fn record_id(pool: &lunaway_db::PgPool, text: &str) -> anyhow::Result<Uuid> {
    let (source, external) = record_ref(text)?;
    lunaway_db::records::id_of(pool, &source, external)
        .await?
        .with_context(|| format!("{text}: no such record"))
}

/// Records a human decision on the two records of `pair`, which have none
/// yet: the conflation worker applies it on its next run. A decision already
/// recorded on the pair stays; replacing one is the database owner's
/// (`lunaway_db::records::set_constraint`).
async fn link(
    pool: &lunaway_db::PgPool,
    pair: Vec<String>,
    kind: ConstraintKind,
    note: &str,
) -> anyhow::Result<()> {
    let [a, b] = <[String; 2]>::try_from(pair)
        .map_err(|_| anyhow::anyhow!("two records, each `source:external_id`"))?;
    let (a, b) = (record_id(pool, &a).await?, record_id(pool, &b).await?);
    if a == b {
        anyhow::bail!("the same record twice");
    }
    if let Some(decided) = lunaway_db::records::add_constraint(pool, a, b, kind, Some(note))
        .await
        .context("recording the decision failed")?
    {
        // The same decision again (a script run twice): nothing to do.
        if decided.kind == kind.code() {
            println!(
                "{} recorded already, its note kept: {}",
                kind.code(),
                decided.reason.as_deref().unwrap_or("none")
            );
            return Ok(());
        }
        anyhow::bail!(
            "the pair has a decision already: {} ({}); replacing one is the database owner's",
            decided.kind,
            decided.reason.as_deref().unwrap_or("no note")
        );
    }
    println!(
        "{} recorded: the conflation worker applies it on its next run (or `lunaway conflate`)",
        kind.code()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_release_lists_the_migrations_it_carries_in_order() {
        let versions = migration_versions();
        assert!(
            versions.windows(2).all(|w| w[0] < w[1]),
            "a deploy compares them with the applied ones as a set of versions"
        );
        assert!(
            versions.contains(&20_261_009_090_000),
            "the translations' migration, one of those applied in production"
        );
        assert_eq!(versions.len(), lunaway_db::MIGRATOR.iter().count());
    }

    #[tokio::test]
    async fn only_a_run_the_database_left_exits_to_be_run_again() {
        // The server down while it restarts: nothing listens. The cause
        // sits under the command's context.
        let config = lunaway_db::PoolConfig {
            acquire_timeout: Duration::from_millis(500),
            ..lunaway_db::PoolConfig::new(1)
        };
        let lost = lunaway_db::connect_with("postgres://lunaway@127.0.0.1:9/lunaway", config)
            .await
            .map(|_| ())
            .context("cannot reach the database (DATABASE_URL)")
            .unwrap_err();
        assert_eq!(exit_status(&lost), EXIT_DATABASE_LOST, "{lost:?}");
        // A source that refused us, or anything else: not run again before
        // its timer.
        let refused = anyhow::anyhow!("the source asks to wait 2 h (Retry-After)")
            .context("La Poste import failed");
        assert_eq!(exit_status(&refused), 1);
        let constraint = anyhow::Error::from(lunaway_db::DbError::TooLarge {
            what: "route shape points",
            limit: 1,
        });
        assert_eq!(exit_status(&constraint), 1);
    }

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
    fn a_record_is_named_by_its_source_and_its_id() {
        let (source, id) = record_ref("osm:node/5327741281").unwrap();
        assert_eq!(
            (source.as_str(), id),
            ("osm", "node/5327741281"),
            "an OSM element keeps its type"
        );
        let (source, id) = record_ref("atout-france:49170:x:y").unwrap();
        assert_eq!(
            (source.as_str(), id),
            ("atout-france", "49170:x:y"),
            "an Atout France id holds colons of its own"
        );
        for bad in ["459126", "osm:", ":node/1", "No Source:1"] {
            assert!(
                record_ref(bad).is_err(),
                "{bad}: a source and an id are both needed, the source as the database names it"
            );
        }
    }

    #[test]
    fn a_decision_on_two_records_needs_both_and_a_note() {
        let parsed = Cli::try_parse_from([
            "lunaway",
            "conflate",
            "--distinct",
            "datatourisme:a",
            "extcom:1",
            "--note",
            "800 m",
        ])
        .unwrap();
        let Command::Conflate {
            distinct,
            same,
            note,
            ..
        } = parsed.command
        else {
            panic!("not the conflation");
        };
        assert_eq!(distinct.unwrap(), ["datatourisme:a", "extcom:1"]);
        assert!(same.is_none());
        assert_eq!(note.as_deref(), Some("800 m"));
        for args in [
            &["lunaway", "conflate", "--same", "osm:node/1", "extcom:1"][..],
            &["lunaway", "conflate", "--same", "osm:node/1", "--note", "x"],
            &[
                "lunaway",
                "conflate",
                "--same",
                "a:1",
                "b:2",
                "--distinct",
                "a:1",
                "b:2",
                "--note",
                "x",
            ],
            &[
                "lunaway", "conflate", "--full", "--same", "a:1", "b:2", "--note", "x",
            ],
            &["lunaway", "conflate", "--note", "x"],
            &[
                "lunaway", "conflate", "--same", "a:1", "b:2", "--same", "c:3", "d:4", "--note",
                "x",
            ],
        ] {
            assert!(
                Cli::try_parse_from(args).is_err(),
                "{args:?}: a decision names two records, alone, with its note, and a note \
                 alone would run a conflation that drops it"
            );
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
