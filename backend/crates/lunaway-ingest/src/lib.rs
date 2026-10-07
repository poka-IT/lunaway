//! Lunaway ingestion: one adapter per open source, each fetching (paced,
//! retried, cached), keeping the raw payload and mapping it onto the domain's
//! [`NormalizedRecord`]. Writing to the database is [`store`]'s job.
//!
//! Sources and their terms are listed in `docs/data-sources.md`.

pub mod atout_france;
pub mod cache;
pub mod cameras;
pub mod cameras_osm;
pub mod enforcement;
pub mod extcom;
pub mod extract_run;
pub mod finess;
pub mod fuel;
pub mod geocode;
pub mod graph_check;
pub mod http;
pub mod ign;
pub mod laposte;
pub mod municipalities;
pub mod osm;
pub mod osm_extract;
pub mod poi_osm;
pub mod road_events;
pub mod routing;
pub mod run;
pub mod store;
pub mod web;

use std::path::PathBuf;

use chrono::{DateTime, Utc};
use lunaway_domain::NormalizedRecord;
use reqwest::StatusCode;

/// One record as an adapter produced it, ready to be stored.
#[derive(Debug, Clone, PartialEq)]
pub struct FetchedRecord {
    /// Identifier in the source (`way/123`, `49170:camping-la-bradiere`).
    pub external_id: String,
    /// Page of the record at the source, when it has one.
    pub external_url: Option<String>,
    /// The normalised content.
    pub record: NormalizedRecord,
    /// The payload as the source sent it.
    pub raw: serde_json::Value,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
}

/// What can go wrong while fetching and mapping a source.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum IngestError {
    /// The HTTP client could not be built.
    #[error("cannot build the HTTP client")]
    Client(#[source] reqwest::Error),
    /// A request failed before an answer arrived.
    #[error("request to {url} failed")]
    Http {
        /// The URL asked.
        url: String,
        /// The cause.
        #[source]
        source: reqwest::Error,
    },
    /// The server answered with an error status.
    #[error("{url} answered {status}{}: {body}", retry_note(*.retry_after))]
    Status {
        /// The URL asked.
        url: String,
        /// The status.
        status: StatusCode,
        /// The start of the body.
        body: String,
        /// How long the server asked to wait (`Retry-After`).
        retry_after: Option<std::time::Duration>,
    },
    /// An answer is larger than any real one: refused, not held in memory.
    #[error("{url} sent more than {limit} bytes")]
    TooLarge {
        /// The URL asked.
        url: String,
        /// The most accepted.
        limit: usize,
    },
    /// A URL from a source's metadata points somewhere the adapter does not
    /// fetch from.
    #[error("refusing to fetch {url}: {reason}")]
    UntrustedUrl {
        /// The URL.
        url: String,
        /// Why it is refused.
        reason: &'static str,
    },
    /// Overpass answered but did not finish the query.
    #[error("overpass did not complete the query: {remark}")]
    OverpassIncomplete {
        /// Overpass's explanation.
        remark: String,
    },
    /// The answer's body was cut before its end (the connection dropped,
    /// the length announced was not reached): reqwest reports it as a
    /// decode error, which asking again may cure.
    #[error("the body from {url} was cut off")]
    Body {
        /// The URL asked.
        url: String,
        /// The cause.
        #[source]
        source: reqwest::Error,
    },
    /// A download received nothing for too long.
    #[error("download from {url} stalled")]
    Stalled {
        /// The URL asked.
        url: String,
        /// The elapsed wait.
        #[source]
        source: tokio::time::error::Elapsed,
    },
    /// An answer has fewer rows than the request.
    #[error("{what}: expected {expected} rows, got {got}")]
    Incomplete {
        /// The answer.
        what: String,
        /// Rows sent.
        expected: usize,
        /// Rows received.
        got: usize,
    },
    /// JSON of an unexpected shape.
    #[error("{what} is not the expected JSON")]
    Json {
        /// The payload.
        what: String,
        /// The cause.
        #[source]
        source: serde_json::Error,
    },
    /// CSV of an unexpected shape.
    #[error("{what} is not the expected CSV")]
    Csv {
        /// The payload.
        what: String,
        /// The cause.
        #[source]
        source: csv::Error,
    },
    /// A column the adapter reads is missing.
    #[error("{what} has no column {column:?}")]
    MissingColumn {
        /// The payload.
        what: String,
        /// The folded column name.
        column: String,
    },
    /// No endpoint was configured.
    #[error("no endpoint configured")]
    NoEndpoint,
    /// The dataset no longer lists a CSV resource.
    #[error("data.gouv.fr dataset {dataset} has no CSV resource")]
    NoResource {
        /// The dataset id.
        dataset: String,
    },
    /// The database refused a write.
    #[error(transparent)]
    Db(#[from] lunaway_db::DbError),
    /// An OSM extract could not be read.
    #[error("cannot read the OSM extract {path}")]
    Pbf {
        /// The file.
        path: PathBuf,
        /// The cause.
        #[source]
        source: osmpbf::Error,
    },
    /// A blocking task panicked or was cancelled.
    #[error("blocking task failed")]
    Blocking(#[source] tokio::task::JoinError),
    /// A compressed payload does not inflate.
    #[error("{what} is not readable gzip")]
    Inflate {
        /// The payload.
        what: String,
        /// The cause.
        #[source]
        source: std::io::Error,
    },
    /// A restriction record of a graph bundle does not hold together.
    #[error("restriction record on line {line} refused")]
    InvalidRecord {
        /// Its line in the file.
        line: usize,
        /// Why.
        #[source]
        source: lunaway_domain::routing::InvalidRecord,
    },
    /// A road events feed does not read.
    #[error("{what} does not read")]
    RoadEvents {
        /// The payload.
        what: String,
        /// The cause.
        #[source]
        source: road_events::ParseError,
    },
    /// The routing engine did not answer, or refused too many requests in
    /// a row.
    #[error("the routing engine failed")]
    Engine(#[source] road_events::matching::MatchError),
    /// A payload parses but says something no real answer says.
    #[error("{what}")]
    Implausible {
        /// What is wrong.
        what: String,
    },
    /// The cache directory or one of its files failed.
    #[error("cache file {path}")]
    Cache {
        /// The file.
        path: PathBuf,
        /// The cause.
        #[source]
        source: std::io::Error,
    },
    /// A partner's feed names no agreement, or one not in force: nothing
    /// of it is stored.
    #[error("the feed's agreement is refused")]
    Agreement(#[source] lunaway_domain::extcom::AgreementError),
    /// The source is hidden or purged (`lunaway extcom hide|purge`):
    /// nothing is imported until it is shown again.
    #[error("source {0} is hidden: run `lunaway extcom show` first")]
    SourceHidden(lunaway_domain::SourceId),
}

fn retry_note(retry_after: Option<std::time::Duration>) -> String {
    retry_after.map_or_else(String::new, |d| {
        format!(" (Retry-After: {} s)", d.as_secs())
    })
}

impl IngestError {
    /// Whether waiting and asking again may succeed.
    #[must_use]
    pub fn is_transient(&self) -> bool {
        match self {
            Self::Http { source, .. } => {
                source.is_timeout()
                    || source.is_connect()
                    || source.is_request()
                    || source.is_body()
            }
            Self::Status { status, .. } => http::is_transient_status(*status),
            Self::OverpassIncomplete { .. }
            | Self::Incomplete { .. }
            | Self::Stalled { .. }
            | Self::Body { .. } => true,
            _ => false,
        }
    }
}
