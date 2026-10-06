//! One pass of the road events poller (`lunaway road-events poll`, every
//! three minutes on the server): each feed read when it is due, resumed
//! from its stored cursor, applied, then the waiting lines matched to the
//! graph and the lifecycle rules applied. A feed that fails is recorded
//! and skipped; it never ends another source's events.
//!
//! | feed | read | complete snapshot |
//! |---|---|---|
//! | DIR aggregate | hourly, conditional on its ETag | yes: missing records end |
//! | DIR increments | every pass, from the next number | no: a situation's new version settles its records |
//! | DiaLog temporary orders | every 15 minutes | yes |
//! | city and département datasets | hourly | yes |
//! | DGT (Spain) | every pass | yes |
//! | NDW planning (Netherlands) | every three hours, only when named (`--only ndw`, its own unit) | yes |

use std::{collections::BTreeMap, time::Duration};

use chrono::{DateTime, Utc};
use lunaway_db::{
    PgPool,
    road_events::{self as db, Missing, NewEvent, UpsertReport},
};
use serde::{Deserialize, Serialize};

use super::{
    dialog, dir, europe,
    fetch::{self, Answer, Ask},
    local::{self, Format, LocalFeed},
    matching::{self, Engine, MatchReport},
};
use crate::{IngestError, cache::Cache, http::RetryPolicy};

/// The DIR feed's directory: `content.xml` and the numbered increments.
pub const DIR_BASE: &str =
    "https://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/Evenementiel-DIR/grt/RRN/";
/// DiaLog's DATEX II export of the temporary orders in force or to come.
pub const DIALOG_TEMPORARY_URL: &str = "https://dialog.beta.gouv.fr/api/regulations/datex.xml?includePermanent=false&includeTemporary=true&includeExpired=false";
/// DiaLog's DATEX II export of the permanent orders.
pub const DIALOG_PERMANENT_URL: &str = "https://dialog.beta.gouv.fr/api/regulations/datex.xml?includePermanent=true&includeTemporary=false&includeExpired=false";

/// Largest DIR aggregate accepted, inflated: 4.3 MB on 2026-10-06.
const DIR_AGGREGATE_MAX: usize = 64 * 1024 * 1024;
/// Largest DIR increment accepted: 4 to 17 kB measured.
const DIR_INCREMENT_MAX: usize = 4 * 1024 * 1024;
/// Largest DiaLog export accepted, inflated: 7.9 MB for the temporary
/// orders, 78 MB for all of them on 2026-10-06.
const DIALOG_MAX: usize = 256 * 1024 * 1024;
/// Largest city dataset accepted: under 1 MB measured.
const LOCAL_MAX: usize = 64 * 1024 * 1024;
/// NDW's planning feed: the gzip file as served (16.5 MB on 2026-10-06),
/// and the XML it holds (204 MB).
const NDW_WIRE_MAX: usize = 96 * 1024 * 1024;
/// 1.6 times the file of 2026-10-06. Its 204 MB of XML took 443 MB at the
/// peak with the events kept (about 2.2 bytes per byte of XML): 320 MiB
/// would take about 730 MB, under the 896 MB where the unit is throttled
/// and the 1 GB where it is stopped
/// (`infra/systemd/lunaway-road-events-ndw.service`). A bigger file is
/// refused as too large rather than killed half-way.
const NDW_XML_MAX: usize = 320 * 1024 * 1024;
/// The DGT's incidents: 6.8 MB of XML on 2026-10-06.
const DGT_MAX: usize = 128 * 1024 * 1024;
/// NDW's planning feed, a gzip file served without `Content-Encoding`.
pub const NDW_URL: &str =
    "https://opendata.ndw.nu/planningsfeed_wegwerkzaamheden_en_evenementen.xml.gz";
/// The DGT's incidents, DATEX II 3.7.
pub const DGT_URL: &str = "https://nap.dgt.es/datex2/v3/dgt/SituationPublication/datex2_v37.xml";
/// How far past a missing DIR increment the poller looks for the next one:
/// the numbers ran without a gap over 24 hours (2 645 files, 3569914 to
/// 3572558), but one file may still be missing.
const GAP_PROBES: u64 = 3;
/// How long the next increment may be missing before the numbers past it
/// are probed: the feed published about 110 an hour, 258 in its busiest
/// hour (research, M3); a quarter of an hour without one is unusual
/// (hypothesis for the night hours).
const GAP_WAIT: chrono::Duration = chrono::Duration::minutes(15);
/// Least wait before the DIR aggregate is asked again after a failure.
const AGGREGATE_RETRY: chrono::Duration = chrono::Duration::minutes(15);
/// How long the increments may be missing before the aggregate's number
/// is trusted over the stored one, even when lower: a bogus number, from
/// the feed or stored, must not stop the increments for good.
const RESYNC_AFTER: chrono::Duration = chrono::Duration::hours(1);

/// A city or département dataset as the poller reads it.
#[derive(Debug, Clone)]
pub struct LocalConfig {
    /// Source id.
    pub id: String,
    /// URL.
    pub url: String,
    /// Hosts.
    pub hosts: Vec<String>,
    /// Format.
    pub format: Format,
}

impl From<&LocalFeed> for LocalConfig {
    fn from(f: &LocalFeed) -> Self {
        Self {
            id: f.id.to_owned(),
            url: f.url.to_owned(),
            hosts: f.hosts.iter().map(|h| (*h).to_owned()).collect(),
            format: f.format,
        }
    }
}

/// What the poller reads, how often, and how long things last.
#[derive(Debug, Clone)]
pub struct PollConfig {
    /// The DIR directory ([`DIR_BASE`]).
    pub dir_base: String,
    /// The DIR's hosts.
    pub dir_hosts: Vec<String>,
    /// How often the DIR aggregate is read.
    pub dir_aggregate_every: chrono::Duration,
    /// Most increments applied in one pass.
    pub dir_max_increments: u64,
    /// Wait between two increments.
    pub dir_pace: Duration,
    /// DiaLog's temporary orders ([`DIALOG_TEMPORARY_URL`]).
    pub dialog_url: String,
    /// DiaLog's hosts.
    pub dialog_hosts: Vec<String>,
    /// How often DiaLog is read.
    pub dialog_every: chrono::Duration,
    /// The city and département datasets.
    pub local: Vec<LocalConfig>,
    /// How often each is read.
    pub local_every: chrono::Duration,
    /// NDW's planning feed ([`NDW_URL`]): read only when named in `only`,
    /// its size asks for a unit of its own.
    pub ndw_url: String,
    /// NDW's hosts.
    pub ndw_hosts: Vec<String>,
    /// How often NDW is read.
    pub ndw_every: chrono::Duration,
    /// The DGT's incidents ([`DGT_URL`]).
    pub dgt_url: String,
    /// The DGT's hosts.
    pub dgt_hosts: Vec<String>,
    /// How often the DGT is read.
    pub dgt_every: chrono::Duration,
    /// Retries on load shedding: few and short, the next pass comes soon.
    pub retry: RetryPolicy,
    /// An event without an end not seen for this long ends.
    pub expire_after: chrono::Duration,
    /// Ended events kept for audit this long.
    pub keep_ended: chrono::Duration,
    /// Reports kept this long.
    pub keep_reports: chrono::Duration,
    /// Most events matched in one pass.
    pub match_tasks: i64,
    /// Time given to matching in one pass.
    pub match_budget: Duration,
    /// Read only these sources (all when empty); every source is read,
    /// due or not, when `force`.
    pub only: Vec<String>,
    /// Read every selected source now.
    pub force: bool,
}

impl Default for PollConfig {
    fn default() -> Self {
        Self {
            dir_base: DIR_BASE.to_owned(),
            dir_hosts: vec!["tipi.bison-fute.gouv.fr".to_owned()],
            dir_aggregate_every: chrono::Duration::minutes(55),
            dir_max_increments: 300,
            dir_pace: Duration::from_millis(250),
            dialog_url: DIALOG_TEMPORARY_URL.to_owned(),
            dialog_hosts: vec!["dialog.beta.gouv.fr".to_owned()],
            dialog_every: chrono::Duration::minutes(14),
            local: local::FEEDS.iter().map(LocalConfig::from).collect(),
            local_every: chrono::Duration::minutes(58),
            ndw_url: NDW_URL.to_owned(),
            ndw_hosts: vec!["opendata.ndw.nu".to_owned()],
            ndw_every: chrono::Duration::minutes(175),
            dgt_url: DGT_URL.to_owned(),
            dgt_hosts: vec!["nap.dgt.es".to_owned()],
            // The feed is written every minute; every pass of three
            // minutes reads it.
            dgt_every: chrono::Duration::seconds(150),
            retry: RetryPolicy {
                min_delay: Duration::from_secs(5),
                max_delay: Duration::from_secs(60),
                max_retries: 2,
            },
            expire_after: chrono::Duration::hours(6),
            keep_ended: chrono::Duration::days(7),
            keep_reports: chrono::Duration::days(db::REPORT_KEEP_DAYS),
            match_tasks: 400,
            match_budget: Duration::from_secs(90),
            only: Vec::new(),
            force: false,
        }
    }
}

/// Where the DIR reader resumes.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DirState {
    /// The ETag of the last aggregate applied.
    #[serde(default)]
    pub etag: Option<String>,
    /// The next increment to read.
    #[serde(default)]
    pub next: Option<u64>,
    /// When the last aggregate applied was published.
    #[serde(default)]
    pub published_at: Option<DateTime<Utc>>,
    /// Since when the next increment has been missing.
    #[serde(default)]
    pub waiting_since: Option<DateTime<Utc>>,
    /// When reading the aggregate last failed: it is not asked again
    /// before [`AGGREGATE_RETRY`], so a broken file is not downloaded every
    /// three minutes.
    #[serde(default)]
    pub aggregate_failed_at: Option<DateTime<Utc>>,
}

/// What a pass did with one source.
#[derive(Debug, Clone, Default)]
pub struct SourceReport {
    /// Whether it was due and read.
    pub read: bool,
    /// Whether a complete snapshot was applied.
    pub full: bool,
    /// Events in what was read.
    pub events: usize,
    /// DIR increments applied.
    pub increments: u64,
    /// What the store did.
    pub upsert: UpsertReport,
    /// Events ended (missing from a snapshot, ended by their source).
    pub ended: u64,
    /// A snapshot that looked truncated: nothing was ended.
    pub refused: Option<(i64, usize)>,
    /// Records left out, by reason.
    pub skipped: BTreeMap<String, usize>,
    /// When the data read was current, when it brought anything.
    pub data_at: Option<DateTime<Utc>>,
    /// How long it took.
    pub elapsed: Duration,
    /// Why it failed.
    pub error: Option<String>,
}

/// What a pass did.
#[derive(Debug, Clone, Default)]
pub struct PollReport {
    /// Per source.
    pub sources: BTreeMap<String, SourceReport>,
    /// The matching.
    pub matching: Option<MatchReport>,
    /// The lifecycle.
    pub lifecycle: Option<db::Lifecycle>,
}

impl PollReport {
    /// Whether any source failed or refused a snapshot.
    #[must_use]
    pub fn failed(&self) -> bool {
        self.sources
            .values()
            .any(|s| s.error.is_some() || s.refused.is_some())
    }
}

/// An error with its causes, for the feed's record and the operator.
fn chain(error: &(dyn std::error::Error + 'static)) -> String {
    let mut out = error.to_string();
    let mut cause = error.source();
    while let Some(c) = cause {
        out.push_str(": ");
        out.push_str(&c.to_string());
        cause = c.source();
    }
    out
}

fn selected(config: &PollConfig, id: &str) -> bool {
    config.only.is_empty() || named(config, id)
}

fn named(config: &PollConfig, id: &str) -> bool {
    config.only.iter().any(|o| o == id)
}

/// Whether a feed last attempted at `last` is due: attempts, failed or
/// not, are paced, so a failing source is asked at its own pace and not at
/// every pass.
fn due(last: Option<DateTime<Utc>>, every: chrono::Duration, now: DateTime<Utc>) -> bool {
    last.is_none_or(|t| now - t >= every)
}

fn merge(into: &mut BTreeMap<String, usize>, from: &BTreeMap<String, usize>) {
    for (k, v) in from {
        *into.entry(k.clone()).or_default() += v;
    }
}

fn add_upsert(report: &mut SourceReport, up: UpsertReport) {
    let u = &mut report.upsert;
    u.inserted += up.inserted;
    u.changed += up.changed;
    u.unchanged += up.unchanged;
    u.older += up.older;
    u.refused += up.refused;
    u.duplicates += up.duplicates;
}

fn state_json(state: &DirState) -> serde_json::Value {
    serde_json::to_value(state).unwrap_or_default()
}

/// Records how a feed's read went, with the state it resumes from.
async fn record(
    pool: &PgPool,
    id: &str,
    outcome: Result<(), IngestError>,
    state: &serde_json::Value,
    r: &mut SourceReport,
) -> Result<(), IngestError> {
    let at = Utc::now();
    match outcome {
        Ok(()) => {
            let read = db::Read {
                state,
                full: r.full,
                data_at: r.data_at,
            };
            db::record_read(pool, id, at, Ok(read)).await?;
        }
        Err(e) => {
            let e = chain(&e);
            tracing::error!(source = id, error = %e, "road events feed failed");
            db::record_read(pool, id, at, Err((&e, Some(state)))).await?;
            r.error = Some(e);
        }
    }
    Ok(())
}

/// Stores a complete snapshot of `source` in `w`: every event, and the end
/// of those missing from it (unless it looks truncated). The caller
/// commits.
async fn apply_snapshot(
    w: &mut db::EventWriter,
    source: &str,
    events: &[NewEvent],
    published_at: DateTime<Utc>,
    seen_at: DateTime<Utc>,
    ordered: bool,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let up = db::upsert(w, source, events, published_at, seen_at, ordered).await?;
    add_upsert(report, up);
    let present: Vec<String> = events.iter().map(|e| e.external_id.clone()).collect();
    match db::end_missing(w, source, &present, published_at, seen_at).await? {
        Missing::Ended(n) => report.ended += n,
        Missing::Refused { live, seen } => {
            tracing::error!(
                source,
                live,
                seen,
                "a snapshot holds less than half of the live events: none ended"
            );
            report.refused = Some((live, seen));
            return Ok(());
        }
    }
    report.full = true;
    Ok(())
}

/// Stores a complete snapshot of a feed without a resume state, in one
/// transaction.
async fn apply_feed(
    pool: &PgPool,
    source: &str,
    events: &[NewEvent],
    now: DateTime<Utc>,
    ordered: bool,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    apply_publication(pool, source, events, now, now, ordered, report).await
}

/// Stores a complete snapshot of a feed published at `published`, read at
/// `seen_at`, in one transaction; the feed is current as of `published`.
async fn apply_publication(
    pool: &PgPool,
    source: &str,
    events: &[NewEvent],
    published: DateTime<Utc>,
    seen_at: DateTime<Utc>,
    ordered: bool,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let mut w = db::begin_writer(pool).await?;
    apply_snapshot(&mut w, source, events, published, seen_at, ordered, report).await?;
    w.commit().await?;
    if report.full {
        report.data_at = Some(published);
    }
    Ok(())
}

/// Where NDW's reader resumes: the ETag of the last file applied.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NdwState {
    /// The validator of the last file applied.
    #[serde(default)]
    pub etag: Option<String>,
}

/// Reads NDW's planning feed, unless unchanged since its last read.
async fn poll_ndw(
    pass: Pass<'_>,
    state: &mut NdwState,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let Pass {
        pool,
        http,
        cache,
        config,
        now,
    } = pass;
    let ask = Ask {
        hosts: &config.ndw_hosts,
        retry: config.retry,
        max_wire: NDW_WIRE_MAX,
        max_inflated: NDW_WIRE_MAX,
        etag: state.etag.as_deref().filter(|_| !config.force),
    };
    let (bytes, etag) = match fetch::get(http, &config.ndw_url, ask).await? {
        Answer::Body { bytes, etag } => (bytes, etag),
        // Unchanged: the events stand as they were.
        Answer::NotModified => {
            report.full = true;
            return Ok(());
        }
        Answer::NotFound => {
            return Err(IngestError::Implausible {
                what: "NDW's planning feed is missing (404)".into(),
            });
        }
    };
    // The file is kept as served, compressed.
    cache
        .write("road-events/ndw/planning.xml.gz", &bytes)
        .await?;
    let url = config.ndw_url.clone();
    let p = tokio::task::spawn_blocking(move || {
        // Served as a .gz file without `Content-Encoding`.
        let xml = if bytes.starts_with(&[0x1f, 0x8b]) {
            let xml = fetch::inflate(&url, &bytes, NDW_XML_MAX)?;
            // The compressed file is no longer needed while the XML is read.
            drop(bytes);
            xml
        } else {
            bytes
        };
        europe::parse_ndw(&xml, now).map_err(|source| IngestError::RoadEvents {
            what: "NDW's planning feed".into(),
            source,
        })
    })
    .await
    .map_err(IngestError::Blocking)??;
    if p.records == 0 {
        return Err(IngestError::Implausible {
            what: "NDW's planning feed holds no record".into(),
        });
    }
    report.events = p.events.len();
    merge(&mut report.skipped, &p.skipped);
    let published = p.published_at.unwrap_or(now);
    apply_publication(pool, "ndw", &p.events, published, now, true, report).await?;
    // A snapshot refused (too many events gone at once) keeps the old
    // validator: a later 304 must not stand for a read applied in full.
    if report.full {
        state.etag = etag;
    }
    Ok(())
}

/// Reads the DGT's incidents.
async fn poll_dgt(pass: Pass<'_>, report: &mut SourceReport) -> Result<(), IngestError> {
    let Pass {
        pool,
        http,
        cache,
        config,
        now,
    } = pass;
    let ask = Ask {
        hosts: &config.dgt_hosts,
        retry: config.retry,
        max_wire: DGT_MAX,
        max_inflated: DGT_MAX,
        etag: None,
    };
    let Answer::Body { bytes, .. } = fetch::get(http, &config.dgt_url, ask).await? else {
        return Err(IngestError::Implausible {
            what: "the DGT answered without its feed".into(),
        });
    };
    cache.write("road-events/dgt/incidents.xml", &bytes).await?;
    let p = tokio::task::spawn_blocking(move || europe::parse_dgt(&bytes, now))
        .await
        .map_err(IngestError::Blocking)?
        .map_err(|source| IngestError::RoadEvents {
            what: "the DGT's feed".into(),
            source,
        })?;
    if p.records == 0 {
        return Err(IngestError::Implausible {
            what: "the DGT's feed holds no record".into(),
        });
    }
    report.events = p.events.len();
    merge(&mut report.skipped, &p.skipped);
    let published = p.published_at.unwrap_or(now);
    apply_publication(pool, "dgt", &p.events, published, now, true, report).await
}

/// Applies a DIR publication, the aggregate as a snapshot or an increment
/// situation by situation, and stores `state`, where the next read
/// resumes, in the same transaction: a pass that fails later does not read
/// it again.
async fn apply_dir(
    pool: &PgPool,
    mut p: dir::Publication,
    state: &DirState,
    seen_at: DateTime<Utc>,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    report.events += p.situations.iter().map(|s| s.events.len()).sum::<usize>();
    merge(&mut report.skipped, &p.skipped);
    let published = p.published_at.unwrap_or(seen_at);
    let mut w = db::begin_writer(pool).await?;
    if p.snapshot {
        let events: Vec<NewEvent> = p
            .situations
            .iter_mut()
            .flat_map(|s| std::mem::take(&mut s.events))
            .collect();
        apply_snapshot(&mut w, "dir", &events, published, seen_at, true, report).await?;
        let ended: Vec<String> = p.situations.iter().flat_map(|s| s.ended.clone()).collect();
        report.ended += db::end_records(&mut w, "dir", &ended, seen_at).await?;
    } else {
        for s in &p.situations {
            let up = db::upsert(&mut w, "dir", &s.events, published, seen_at, true).await?;
            add_upsert(report, up);
            report.ended += db::settle_situation(
                &mut w,
                "dir",
                &s.id,
                &s.record_ids,
                &s.ended,
                published,
                seen_at,
            )
            .await?;
        }
    }
    // An aggregate that looked cut ended nothing: its time does not make
    // the feed current.
    let data_at = (!p.snapshot || report.refused.is_none()).then_some(published);
    db::save_state(&mut w, "dir", &state_json(state), data_at).await?;
    w.commit().await?;
    report.data_at = report.data_at.max(data_at);
    Ok(())
}

fn dir_ask<'a>(config: &'a PollConfig, max: usize, etag: Option<&'a str>) -> Ask<'a> {
    Ask {
        hosts: &config.dir_hosts,
        retry: config.retry,
        max_wire: max,
        max_inflated: max,
        etag,
    }
}

/// Where the aggregate's feed number leaves the next increment to read:
/// never backwards while the increments flow, the aggregate's number once
/// they have been missing for [`RESYNC_AFTER`].
fn resume_at(state: &DirState, feed_number: Option<u64>, now: DateTime<Utc>) -> Option<u64> {
    let stuck = state
        .waiting_since
        .is_some_and(|since| now - since >= RESYNC_AFTER);
    match (state.next, feed_number) {
        (Some(_), Some(f)) if stuck => Some(f),
        (Some(n), Some(f)) => Some(n.max(f)),
        (n, f) => f.or(n),
    }
}

/// What one pass reads with.
#[derive(Clone, Copy)]
struct Pass<'a> {
    pool: &'a PgPool,
    http: &'a reqwest::Client,
    cache: &'a Cache,
    config: &'a PollConfig,
    now: DateTime<Utc>,
}

/// Reads the DIR feed from `state`, which follows every publication
/// applied: the caller stores it whatever the outcome.
async fn poll_dir(
    pass: Pass<'_>,
    state: &mut DirState,
    last_full: Option<DateTime<Utc>>,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let Pass {
        pool,
        http,
        cache,
        config,
        now,
    } = pass;
    let aggregate_due = config.force
        || ((state.next.is_none() || due(last_full, config.dir_aggregate_every, now))
            && due(state.aggregate_failed_at, AGGREGATE_RETRY, now));
    if aggregate_due {
        let read = read_aggregate(pass, state, last_full, report).await;
        match read {
            Ok(()) => state.aggregate_failed_at = None,
            Err(e) => {
                state.aggregate_failed_at = Some(now);
                return Err(e);
            }
        }
    }
    let Some(mut next) = state.next else {
        return Ok(());
    };
    let mut applied = 0;
    'increments: while applied < config.dir_max_increments {
        let url = format!("{}{next}.xml", config.dir_base);
        let mut found =
            match fetch::get(http, &url, dir_ask(config, DIR_INCREMENT_MAX, None)).await? {
                Answer::Body { bytes, .. } => Some((next, bytes)),
                Answer::NotModified | Answer::NotFound => None,
            };
        if found.is_none() {
            // The next number is most likely not published yet. Only when
            // it stays missing longer than the feed ever pauses are the
            // numbers past it probed: a file may be missing for good.
            let waiting = *state.waiting_since.get_or_insert(now);
            if now - waiting < GAP_WAIT {
                break 'increments;
            }
            for probe in 1..=GAP_PROBES {
                tokio::time::sleep(config.dir_pace).await;
                let url = format!("{}{}.xml", config.dir_base, next + probe);
                if let Answer::Body { bytes, .. } =
                    fetch::get(http, &url, dir_ask(config, DIR_INCREMENT_MAX, None)).await?
                {
                    tracing::warn!(
                        missing = next,
                        found = next + probe,
                        "a DIR increment is missing; skipped"
                    );
                    found = Some((next + probe, bytes));
                    break;
                }
            }
        }
        let Some((n, bytes)) = found else {
            break 'increments;
        };
        cache
            .write("road-events/dir/increment-latest.xml", &bytes)
            .await?;
        let p = dir::parse(&bytes, Utc::now()).map_err(|source| IngestError::RoadEvents {
            what: format!("DIR increment {n}"),
            source,
        })?;
        let after = DirState {
            next: Some(n + 1),
            waiting_since: None,
            ..state.clone()
        };
        apply_dir(pool, p, &after, Utc::now(), report).await?;
        *state = after;
        applied += 1;
        next = n + 1;
        tokio::time::sleep(config.dir_pace).await;
    }
    report.increments = applied;
    Ok(())
}

/// Reads and applies the DIR aggregate, unless unchanged since its last
/// read.
async fn read_aggregate(
    pass: Pass<'_>,
    state: &mut DirState,
    last_full: Option<DateTime<Utc>>,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let Pass {
        pool,
        http,
        cache,
        config,
        now,
    } = pass;
    let url = format!("{}content.xml", config.dir_base);
    let held = state
        .etag
        .clone()
        .filter(|_| last_full.is_some() && !config.force);
    let answer = fetch::get(
        http,
        &url,
        dir_ask(config, DIR_AGGREGATE_MAX, held.as_deref()),
    )
    .await?;
    match answer {
        Answer::Body { bytes, etag } => {
            cache.write("road-events/dir/content.xml", &bytes).await?;
            let p = tokio::task::spawn_blocking(move || dir::parse(&bytes, Utc::now()))
                .await
                .map_err(IngestError::Blocking)?
                .map_err(|source| IngestError::RoadEvents {
                    what: "the DIR aggregate".into(),
                    source,
                })?;
            if !p.snapshot {
                return Err(IngestError::Implausible {
                    what: "the DIR aggregate is not a snapshot".into(),
                });
            }
            let next = resume_at(state, p.feed_number, now);
            let after = DirState {
                etag,
                published_at: p.published_at,
                waiting_since: state.waiting_since.filter(|_| next == state.next),
                next,
                aggregate_failed_at: None,
            };
            apply_dir(pool, p, &after, now, report).await?;
            *state = after;
            Ok(())
        }
        // Unchanged: the events stand as they were, and nothing tells the
        // data is newer than the last publication applied.
        Answer::NotModified => {
            report.full = true;
            Ok(())
        }
        Answer::NotFound => Err(IngestError::Implausible {
            what: "the DIR aggregate is missing (404)".into(),
        }),
    }
}

async fn poll_dialog(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &PollConfig,
    now: DateTime<Utc>,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let ask = Ask {
        hosts: &config.dialog_hosts,
        retry: config.retry,
        max_wire: DIALOG_MAX,
        max_inflated: DIALOG_MAX,
        etag: None,
    };
    let Answer::Body { bytes, .. } = fetch::get(http, &config.dialog_url, ask).await? else {
        return Err(IngestError::Implausible {
            what: "DiaLog answered without its export".into(),
        });
    };
    cache
        .write("road-events/dialog/temporary.xml", &bytes)
        .await?;
    let p = tokio::task::spawn_blocking(move || dialog::parse_temporary(&bytes, Utc::now()))
        .await
        .map_err(IngestError::Blocking)?
        .map_err(|source| IngestError::RoadEvents {
            what: "the DiaLog export".into(),
            source,
        })?;
    if p.orders == 0 {
        return Err(IngestError::Implausible {
            what: "the DiaLog export holds no order".into(),
        });
    }
    report.events = p.events.len();
    merge(&mut report.skipped, &p.skipped);
    apply_feed(pool, "dialog", &p.events, now, true, report).await
}

async fn poll_local(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &PollConfig,
    feed: &LocalConfig,
    now: DateTime<Utc>,
    report: &mut SourceReport,
) -> Result<(), IngestError> {
    let ask = |etag| Ask {
        hosts: &feed.hosts,
        retry: config.retry,
        max_wire: LOCAL_MAX,
        max_inflated: LOCAL_MAX,
        etag,
    };
    let body = |a: Answer| match a {
        Answer::Body { bytes, .. } => Ok(bytes),
        _ => Err(IngestError::Implausible {
            what: format!("{} answered without its dataset", feed.id),
        }),
    };
    let url = if feed.format == Format::CifsDataGouv {
        let meta = body(fetch::get(http, &feed.url, ask(None)).await?)?;
        local::cifs_resource(&meta).map_err(|source| IngestError::RoadEvents {
            what: format!("{} metadata", feed.id),
            source,
        })?
    } else {
        local::url_for(&feed.url, now)
    };
    let bytes = body(fetch::get(http, &url, ask(None)).await?)?;
    cache
        .write(&format!("road-events/local/{}.json", feed.id), &bytes)
        .await?;
    let p = match feed.format {
        Format::CifsDataGouv => local::parse_cifs(&feed.id, &bytes, now),
        f => local::parse_geojson(&feed.id, f, &bytes, now),
    }
    .map_err(|source| IngestError::RoadEvents {
        what: feed.id.clone(),
        source,
    })?;
    if feed.format == Format::CotesDArmorOrders && p.features >= local::COTES_D_ARMOR_PAGE {
        return Err(IngestError::Implausible {
            what: format!(
                "{} filled its page of {} orders: more may follow, nothing applied",
                feed.id,
                local::COTES_D_ARMOR_PAGE
            ),
        });
    }
    report.events = p.events.len();
    merge(&mut report.skipped, &p.skipped);
    apply_feed(pool, &feed.id, &p.events, now, false, report).await
}

/// Runs one pass: each selected feed when due (all of them with `force`),
/// the matching when an engine is given, the lifecycle rules.
///
/// # Errors
///
/// [`IngestError::Db`] when the database fails outside a feed's own step;
/// a feed's failure is recorded in its report and the pass goes on.
pub async fn poll(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &PollConfig,
    engine: Option<&impl Engine>,
) -> Result<PollReport, IngestError> {
    let mut out = PollReport::default();
    let now = Utc::now();
    if selected(config, "dir") {
        let started = std::time::Instant::now();
        let mut r = SourceReport {
            read: true,
            ..SourceReport::default()
        };
        let feed = db::feed(pool, "dir").await?;
        let mut state: DirState = feed
            .as_ref()
            .and_then(|f| serde_json::from_value(f.state.clone()).ok())
            .unwrap_or_default();
        let last_full = feed.as_ref().and_then(|f| f.last_full_at);
        let pass = Pass {
            pool,
            http,
            cache,
            config,
            now,
        };
        let outcome = poll_dir(pass, &mut state, last_full, &mut r).await;
        r.elapsed = started.elapsed();
        let state = state_json(&state);
        record(pool, "dir", outcome, &state, &mut r).await?;
        out.sources.insert("dir".into(), r);
    }
    let dialog_tried = db::feed(pool, "dialog")
        .await?
        .and_then(|f| f.last_attempt_at);
    if selected(config, "dialog") && (config.force || due(dialog_tried, config.dialog_every, now)) {
        let started = std::time::Instant::now();
        let mut r = SourceReport {
            read: true,
            ..SourceReport::default()
        };
        let outcome = poll_dialog(pool, http, cache, config, now, &mut r).await;
        r.elapsed = started.elapsed();
        record(pool, "dialog", outcome, &serde_json::json!({}), &mut r).await?;
        out.sources.insert("dialog".into(), r);
    }
    for feed in &config.local {
        let tried = db::feed(pool, &feed.id)
            .await?
            .and_then(|f| f.last_attempt_at);
        if !selected(config, &feed.id) || !(config.force || due(tried, config.local_every, now)) {
            continue;
        }
        let started = std::time::Instant::now();
        let mut r = SourceReport {
            read: true,
            ..SourceReport::default()
        };
        let outcome = poll_local(pool, http, cache, config, feed, now, &mut r).await;
        r.elapsed = started.elapsed();
        record(pool, &feed.id, outcome, &serde_json::json!({}), &mut r).await?;
        out.sources.insert(feed.id.clone(), r);
    }
    let pass = Pass {
        pool,
        http,
        cache,
        config,
        now,
    };
    let dgt_tried = db::feed(pool, "dgt").await?.and_then(|f| f.last_attempt_at);
    if selected(config, "dgt") && (config.force || due(dgt_tried, config.dgt_every, now)) {
        let started = std::time::Instant::now();
        let mut r = SourceReport {
            read: true,
            ..SourceReport::default()
        };
        let outcome = poll_dgt(pass, &mut r).await;
        r.elapsed = started.elapsed();
        record(pool, "dgt", outcome, &serde_json::json!({}), &mut r).await?;
        out.sources.insert("dgt".into(), r);
    }
    // NDW's file is read by its own unit, which names it (`--only ndw`):
    // 200 MB of XML would not fit the memory of the three-minute pass.
    let ndw = db::feed(pool, "ndw").await?;
    let ndw_tried = ndw.as_ref().and_then(|f| f.last_attempt_at);
    if named(config, "ndw") && (config.force || due(ndw_tried, config.ndw_every, now)) {
        let started = std::time::Instant::now();
        let mut r = SourceReport {
            read: true,
            ..SourceReport::default()
        };
        let mut state: NdwState = ndw
            .as_ref()
            .and_then(|f| serde_json::from_value(f.state.clone()).ok())
            .unwrap_or_default();
        let outcome = poll_ndw(pass, &mut state, &mut r).await;
        r.elapsed = started.elapsed();
        let state = serde_json::to_value(&state).unwrap_or_default();
        record(pool, "ndw", outcome, &state, &mut r).await?;
        out.sources.insert("ndw".into(), r);
    }
    if let Some(engine) = engine {
        out.matching = Some(
            matching::match_pending(pool, engine, config.match_tasks, config.match_budget).await?,
        );
    }
    out.lifecycle = Some(
        db::lifecycle(
            pool,
            Utc::now(),
            config.expire_after,
            config.keep_ended,
            config.keep_reports,
        )
        .await?,
    );
    Ok(out)
}

/// What the weekly read of DiaLog's permanent orders did.
#[derive(Debug, Clone, Default)]
pub struct PermanentReport {
    /// Permanent orders read.
    pub orders: usize,
    /// Restrictions stored.
    pub stored: u64,
    /// Regulations left out, by reason.
    pub skipped: BTreeMap<String, usize>,
}

/// Reads DiaLog's permanent orders and replaces their restrictions in
/// `route_restrictions`. Refuses an export with fewer restrictions than
/// half of those stored: a cut answer must not drop the limits.
///
/// # Errors
///
/// [`IngestError`] when the export cannot be read or the store fails.
pub async fn dialog_permanent(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    url: &str,
    hosts: &[String],
    retry: RetryPolicy,
) -> Result<PermanentReport, IngestError> {
    let ask = Ask {
        hosts,
        retry,
        max_wire: DIALOG_MAX,
        max_inflated: DIALOG_MAX,
        etag: None,
    };
    let Answer::Body { bytes, .. } = fetch::get(http, url, ask).await? else {
        return Err(IngestError::Implausible {
            what: "DiaLog answered without its export".into(),
        });
    };
    {
        use std::io::Write as _;
        let mut z = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        let _ = z.write_all(&bytes);
        if let Ok(gz) = z.finish() {
            cache
                .write("road-events/dialog/permanent.xml.gz", &gz)
                .await?;
        }
    }
    let fetched_at = Utc::now();
    let p = tokio::task::spawn_blocking(move || dialog::parse_permanent(&bytes, fetched_at))
        .await
        .map_err(IngestError::Blocking)?
        .map_err(|source| IngestError::RoadEvents {
            what: "the DiaLog permanent export".into(),
            source,
        })?;
    let stored_before = lunaway_db::routing::count_source(pool, "dialog").await?;
    let read = i64::try_from(p.records.len()).unwrap_or(i64::MAX);
    if stored_before >= 100 && read.saturating_mul(2) < stored_before {
        return Err(IngestError::Implausible {
            what: format!(
                "the DiaLog export gives {} restrictions against {stored_before} stored: refused",
                p.records.len()
            ),
        });
    }
    let stored = db::replace_dialog_restrictions(pool, &p.records).await?;
    Ok(PermanentReport {
        orders: p.orders,
        stored,
        skipped: p.skipped,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_aggregate_number_moves_the_cursor_back_only_when_the_increments_stopped() {
        let now = Utc::now();
        let flowing = DirState {
            next: Some(5_000_000),
            ..DirState::default()
        };
        assert_eq!(
            resume_at(&flowing, Some(3_572_540), now),
            Some(5_000_000),
            "while the increments flow, the cursor never goes back"
        );
        assert_eq!(resume_at(&flowing, Some(5_000_010), now), Some(5_000_010));
        let stuck = DirState {
            waiting_since: Some(now - chrono::Duration::hours(2)),
            ..flowing
        };
        assert_eq!(
            resume_at(&stuck, Some(3_572_540), now),
            Some(3_572_540),
            "a bogus cursor must not stop the increments for good"
        );
        assert_eq!(
            resume_at(&DirState::default(), Some(3_572_540), now),
            Some(3_572_540)
        );
    }

    #[test]
    fn a_feed_is_asked_at_its_pace_whether_it_failed_or_not() {
        let now = Utc::now();
        let every = chrono::Duration::minutes(14);
        assert!(due(None, every, now));
        assert!(!due(Some(now - chrono::Duration::minutes(3)), every, now));
        assert!(due(Some(now - chrono::Duration::minutes(15)), every, now));
    }
}
