//! La Poste's opening calendar (data.laposte.fr dataset `laposte-ouvertur`,
//! "Calendrier d'ouverture des bureaux de poste, agences postales et
//! relais poste", ODbL), joined to the post offices of the POI layer by
//! the site's id (OSM `ref:FR:LaPoste`, on 95 % of the French post offices
//! in OSM, `plan/research/05-poi-sources.md` A.1).
//!
//! The dataset gives, day by day over three months, the opening ranges of
//! every site, public holidays and closures included: exact where an OSM
//! `opening_hours` is a weekly pattern. The importer reads the days from
//! `today` to `today` + [`DAYS_AHEAD`] through the dataset's `lines` API,
//! filtered by date (287 071 lines for 15 days on 2026-10-06), in pages of
//! [`PAGE_SIZE`] lines one second apart, following the `next` link the API
//! gives, which must stay on [`HOSTS`]. A run that reads fewer lines than
//! the API announced stops before anything is stored, so a truncated
//! answer never retires a site.
//!
//! The pages of the latest run are cached under fixed keys, overwritten by
//! the next run, with a manifest naming the day they were read for.

use std::{collections::BTreeMap, time::Duration};

use chrono::{DateTime, NaiveDate, NaiveTime, Utc};
use lunaway_db::{PgPool, pois::NewJoin};
use lunaway_domain::{
    SourceId,
    poi::{PostDay, PostOfficeDays},
};
use serde::{Deserialize, Serialize};

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    store::{JoinStoreReport, store_joins},
    web::check_host,
};

/// The `lines` endpoint of the dataset.
pub const LINES_URL: &str =
    "https://data.laposte.fr/data-fair/api/v1/datasets/laposte-ouvertur/lines";

/// Hosts the pages may come from: the first page's and every `next` link.
pub const HOSTS: &[&str] = &["data.laposte.fr"];

/// Days read after today: the worker builds the 14-day windows of the
/// POI layer from them.
pub const DAYS_AHEAD: u64 = 14;

/// Lines per page, the most the API serves at once.
pub const PAGE_SIZE: usize = 10_000;

/// The columns read.
const SELECT: &str =
    "identifiant,caracteristique,date_calendrier,plage_horaire_1,plage_horaire_2,plage_horaire_3";

/// Largest page accepted: a page of 10 000 lines weighs about 1.5 MB.
const PAGE_MAX_BYTES: usize = 32 * 1024 * 1024;

/// Pages read at most in one run: 29 are needed for 15 days of every site;
/// a `next` link that never ends is cut here.
const MAX_PAGES: usize = 200;

/// The manifest of the cached pages.
const MANIFEST_KEY: &str = "laposte/ouvertur-latest.json";

/// What the value of a range says when the site is closed that day.
const CLOSED: &str = "FERME";

/// Where and how to read the calendar.
#[derive(Debug, Clone)]
pub struct LaPosteConfig {
    /// The `lines` endpoint ([`LINES_URL`]).
    pub url: String,
    /// Hosts the pages may come from ([`HOSTS`]).
    pub hosts: Vec<String>,
    /// Lines per page.
    pub page_size: usize,
    /// Pause between two pages.
    pub pace: Duration,
    /// Retries on load shedding, per page.
    pub retry: RetryPolicy,
}

impl Default for LaPosteConfig {
    fn default() -> Self {
        Self {
            url: LINES_URL.to_owned(),
            hosts: HOSTS.iter().map(|h| (*h).to_owned()).collect(),
            page_size: PAGE_SIZE,
            pace: Duration::from_secs(1),
            retry: RetryPolicy::PATIENT,
        }
    }
}

/// One line of the calendar: a site on a day.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub struct Line {
    /// The site's id (`00001A`).
    pub identifiant: String,
    /// What the site is (`Bureau de Poste`, `Relais poste`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub caracteristique: Option<String>,
    /// The local date.
    pub date_calendrier: NaiveDate,
    /// First range (`09:00-12:00`), or `FERME`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plage_horaire_1: Option<String>,
    /// Second range.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plage_horaire_2: Option<String>,
    /// Third range.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plage_horaire_3: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Page {
    #[serde(default)]
    total: Option<u64>,
    #[serde(default)]
    next: Option<String>,
    results: Vec<Line>,
}

/// One page of the `lines` API.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedPage {
    /// Lines the whole query matches.
    pub total: Option<u64>,
    /// The next page, absent on the last one.
    pub next: Option<String>,
    /// The lines of this page.
    pub lines: Vec<Line>,
}

/// Reads one page of the `lines` API.
///
/// # Errors
///
/// [`IngestError::Json`] when the page is not the API's JSON.
pub fn parse_page(body: &[u8]) -> Result<ParsedPage, IngestError> {
    let page: Page = serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: "la poste calendar page".into(),
        source,
    })?;
    Ok(ParsedPage {
        total: page.total,
        next: page.next.filter(|n| !n.trim().is_empty()),
        lines: page.results,
    })
}

/// A range `HH:MM-HH:MM` in local time; `24:00` reads as the last second
/// of the day. `None` for anything else, or a range that ends before it
/// starts.
fn range(raw: &str) -> Option<[NaiveTime; 2]> {
    let (a, b) = raw.trim().split_once('-')?;
    let time = |s: &str| {
        let s = s.trim();
        if s == "24:00" {
            NaiveTime::from_hms_opt(23, 59, 59)
        } else {
            NaiveTime::parse_from_str(s, "%H:%M").ok()
        }
    };
    let (start, end) = (time(a)?, time(b)?);
    (start < end).then_some([start, end])
}

/// The ranges of a line in order; `None` when one of them does not read,
/// so a day whose hours are unknown is never taken for a closed one.
fn ranges(line: &Line) -> Option<Vec<[NaiveTime; 2]>> {
    let mut out = Vec::new();
    for raw in [
        &line.plage_horaire_1,
        &line.plage_horaire_2,
        &line.plage_horaire_3,
    ]
    .into_iter()
    .flatten()
    {
        let raw = raw.trim();
        if raw.is_empty() || raw.eq_ignore_ascii_case(CLOSED) {
            continue;
        }
        out.push(range(raw)?);
    }
    out.sort();
    Some(out)
}

/// A site's id as OSM writes it: six letters or digits, upper-cased.
fn key(identifiant: &str) -> Option<String> {
    let k = identifiant.trim().to_ascii_uppercase();
    (k.len() == 6 && k.chars().all(|c| c.is_ascii_alphanumeric())).then_some(k)
}

/// One site with its days.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedSite {
    /// The site's id, upper-cased.
    pub key: String,
    /// Its calendar.
    pub days: PostOfficeDays,
    /// Its lines as the API sent them.
    pub raw: serde_json::Value,
}

/// What [`build`] made of the lines.
#[derive(Debug, Default)]
pub struct ParsedSites {
    /// One per site, by id.
    pub sites: Vec<ParsedSite>,
    /// Lines left out: an id of another shape, a range that does not read,
    /// a day listed twice.
    pub skipped_lines: usize,
}

/// Groups the lines by site, each day with its ranges, in date order.
#[must_use]
pub fn build(lines: impl IntoIterator<Item = Line>) -> ParsedSites {
    let mut by_site: BTreeMap<String, (PostOfficeDays, Vec<serde_json::Value>)> = BTreeMap::new();
    let mut skipped_lines = 0;
    for line in lines {
        let Some(k) = key(&line.identifiant) else {
            skipped_lines += 1;
            continue;
        };
        let Some(open) = ranges(&line) else {
            skipped_lines += 1;
            continue;
        };
        let raw = serde_json::to_value(&line).unwrap_or(serde_json::Value::Null);
        let (site, raws) = by_site.entry(k).or_insert_with(|| {
            (
                PostOfficeDays {
                    kind: line.caracteristique.clone(),
                    days: Vec::new(),
                },
                Vec::new(),
            )
        });
        if site.days.iter().any(|d| d.date == line.date_calendrier) {
            skipped_lines += 1;
            continue;
        }
        site.days.push(PostDay {
            date: line.date_calendrier,
            open,
        });
        raws.push(raw);
    }
    let sites = by_site
        .into_iter()
        .map(|(key, (mut days, raws))| {
            days.days.sort_by_key(|d| d.date);
            ParsedSite {
                key,
                days,
                raw: serde_json::json!({ "lines": raws }),
            }
        })
        .collect();
    ParsedSites {
        sites,
        skipped_lines,
    }
}

/// The first page's URL for the window that starts on `today`.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `base` is not a URL.
pub fn first_page_url(
    base: &str,
    page_size: usize,
    today: NaiveDate,
) -> Result<String, IngestError> {
    let mut url = reqwest::Url::parse(base).map_err(|error| {
        tracing::error!(%error, url = base, "the configured URL does not parse");
        IngestError::UntrustedUrl {
            url: base.to_owned(),
            reason: "not a URL",
        }
    })?;
    let last = today
        .checked_add_days(chrono::Days::new(DAYS_AHEAD))
        .unwrap_or(today);
    url.query_pairs_mut()
        .append_pair("size", &page_size.to_string())
        .append_pair("select", SELECT)
        .append_pair("sort", "identifiant,date_calendrier")
        .append_pair("date_calendrier_gte", &today.to_string())
        .append_pair("date_calendrier_lte", &last.to_string());
    Ok(url.into())
}

#[derive(Debug, Serialize, Deserialize)]
struct Manifest {
    today: NaiveDate,
    pages: usize,
}

fn page_key(n: usize) -> String {
    format!("laposte/ouvertur-page-{n:03}.json")
}

/// Every line of the window, and when they were read.
#[derive(Debug)]
pub struct FetchedLines {
    /// The lines, in the API's order.
    pub lines: Vec<Line>,
    /// Pages read.
    pub pages: usize,
    /// When the first page was read.
    pub fetched_at: DateTime<Utc>,
    /// Whether they came from the cache.
    pub cached: bool,
}

/// Reads the lines of the window starting on `today`: from the cache when
/// `refresh` is false and the cached pages are of that day, otherwise page
/// by page from the API, caching each page and then the manifest.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when a `next` link leaves the allowed
/// hosts, [`IngestError::Incomplete`] when fewer lines arrive than the API
/// announced, and the errors of the requests and of the cache.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    config: &LaPosteConfig,
    today: NaiveDate,
    refresh: bool,
) -> Result<FetchedLines, IngestError> {
    if !refresh && let Some(cached) = read_cached(cache, today).await? {
        return Ok(cached);
    }
    let hosts: Vec<&str> = config.hosts.iter().map(String::as_str).collect();
    let mut url = first_page_url(&config.url, config.page_size, today)?;
    let mut lines = Vec::new();
    let mut total = None;
    let mut fetched_at = None;
    let mut pages = 0;
    loop {
        check_host(&url, &hosts)?;
        if pages == MAX_PAGES {
            return Err(IngestError::Implausible {
                what: format!("la poste calendar: more than {MAX_PAGES} pages"),
            });
        }
        tracing::info!(page = pages + 1, "reading la poste's calendar");
        let body = with_retry("la poste calendar", config.retry, || async {
            let response =
                http.get(url.as_str())
                    .send()
                    .await
                    .map_err(|source| IngestError::Http {
                        url: url.clone(),
                        source,
                    })?;
            let response = check_status(&url, response).await?;
            read_capped(&url, response, PAGE_MAX_BYTES).await
        })
        .await?;
        let page = parse_page(&body)?;
        let at = cache.write(&page_key(pages), &body).await?;
        fetched_at.get_or_insert(at);
        total = total.or(page.total);
        pages += 1;
        let empty = page.lines.is_empty();
        lines.extend(page.lines);
        match page.next {
            Some(next) if !empty => {
                url = next;
                tokio::time::sleep(config.pace).await;
            }
            _ => break,
        }
    }
    if let Some(total) = total.and_then(|t| usize::try_from(t).ok())
        && lines.len() < total
    {
        return Err(IngestError::Incomplete {
            what: "la poste calendar".into(),
            expected: total,
            got: lines.len(),
        });
    }
    let manifest =
        serde_json::to_vec(&Manifest { today, pages }).map_err(|source| IngestError::Json {
            what: "la poste manifest".into(),
            source,
        })?;
    cache.write(MANIFEST_KEY, &manifest).await?;
    Ok(FetchedLines {
        lines,
        pages,
        fetched_at: fetched_at.unwrap_or_else(Utc::now),
        cached: false,
    })
}

async fn read_cached(cache: &Cache, today: NaiveDate) -> Result<Option<FetchedLines>, IngestError> {
    let Some(m) = cache.read(MANIFEST_KEY).await? else {
        return Ok(None);
    };
    let Ok(manifest) = serde_json::from_slice::<Manifest>(&m.bytes) else {
        return Ok(None);
    };
    if manifest.today != today {
        return Ok(None);
    }
    let mut lines = Vec::new();
    let mut fetched_at = m.fetched_at;
    for n in 0..manifest.pages {
        let Some(page) = cache.read(&page_key(n)).await? else {
            return Ok(None);
        };
        fetched_at = fetched_at.min(page.fetched_at);
        lines.extend(parse_page(&page.bytes)?.lines);
    }
    tracing::info!(
        pages = manifest.pages,
        "la poste's calendar read from the cache"
    );
    Ok(Some(FetchedLines {
        lines,
        pages: manifest.pages,
        fetched_at,
        cached: true,
    }))
}

/// What an import of the calendar did.
#[derive(Debug, Clone)]
pub struct LaPosteReport {
    /// Whether the pages came from the cache.
    pub cached: bool,
    /// Pages read.
    pub pages: usize,
    /// Lines read.
    pub lines: usize,
    /// Sites stored.
    pub sites: usize,
    /// Lines left out.
    pub skipped_lines: usize,
    /// What the store did.
    pub store: JoinStoreReport,
}

/// Reads the calendar of the window starting on `today` and stores every
/// site as a joined row of `laposte`; the post offices whose days changed
/// are evaluated again by the worker, and sites La Poste no longer lists
/// are retired.
///
/// # Errors
///
/// [`IngestError`] when the fetch or a write fails.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &LaPosteConfig,
    today: NaiveDate,
    refresh: bool,
) -> Result<LaPosteReport, IngestError> {
    let fetched = fetch(http, cache, config, today, refresh).await?;
    let line_count = fetched.lines.len();
    let parsed = build(fetched.lines);
    let data: Vec<serde_json::Value> = parsed
        .sites
        .iter()
        .map(|s| serde_json::to_value(&s.days))
        .collect::<Result<_, _>>()
        .map_err(|source| IngestError::Json {
            what: "la poste site".into(),
            source,
        })?;
    let rows: Vec<NewJoin<'_>> = parsed
        .sites
        .iter()
        .zip(&data)
        .map(|(s, data)| NewJoin {
            key: &s.key,
            data,
            raw: &s.raw,
            fetched_at: fetched.fetched_at,
        })
        .collect();
    let store = store_joins(pool, &SourceId::LAPOSTE, &rows).await?;
    tracing::info!(
        sites = parsed.sites.len(),
        changed = store.upsert.upsert.changed,
        retired = store.retired,
        "la poste's calendar stored"
    );
    Ok(LaPosteReport {
        cached: fetched.cached,
        pages: fetched.pages,
        lines: line_count,
        sites: parsed.sites.len(),
        skipped_lines: parsed.skipped_lines,
        store,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(h: u32, m: u32) -> NaiveTime {
        NaiveTime::from_hms_opt(h, m, 0).unwrap()
    }

    #[test]
    fn ranges_read_the_calendar_s_forms() {
        assert_eq!(range("09:00-12:00"), Some([t(9, 0), t(12, 0)]));
        assert_eq!(
            range("20:00-24:00"),
            Some([t(20, 0), NaiveTime::from_hms_opt(23, 59, 59).unwrap()])
        );
        assert_eq!(
            range("12:00-09:00"),
            None,
            "a range that ends before it starts"
        );
        assert_eq!(range("matin"), None);
    }

    #[test]
    fn a_day_with_an_unread_range_is_unknown_not_closed() {
        let line = |p1: Option<&str>, p2: Option<&str>| Line {
            identifiant: "00001a".into(),
            caracteristique: None,
            date_calendrier: NaiveDate::from_ymd_opt(2026, 10, 6).unwrap(),
            plage_horaire_1: p1.map(str::to_owned),
            plage_horaire_2: p2.map(str::to_owned),
            plage_horaire_3: None,
        };
        assert_eq!(ranges(&line(Some("FERME"), None)), Some(Vec::new()));
        assert_eq!(
            ranges(&line(Some("14:00-18:00"), Some("09:00-12:00"))),
            Some(vec![[t(9, 0), t(12, 0)], [t(14, 0), t(18, 0)]]),
            "ranges in order"
        );
        assert_eq!(
            ranges(&line(Some("09:00-12:00"), Some("sur rendez-vous"))),
            None
        );
        assert_eq!(key("00001a").as_deref(), Some("00001A"));
        assert_eq!(key("0001A"), None);
    }

    #[test]
    fn the_first_page_asks_for_the_window() {
        let url = first_page_url(
            LINES_URL,
            10_000,
            NaiveDate::from_ymd_opt(2026, 10, 6).unwrap(),
        )
        .unwrap();
        assert!(url.starts_with(LINES_URL));
        assert!(url.contains("date_calendrier_gte=2026-10-06"), "{url}");
        assert!(url.contains("date_calendrier_lte=2026-10-20"), "{url}");
        assert!(url.contains("size=10000"), "{url}");
    }
}
