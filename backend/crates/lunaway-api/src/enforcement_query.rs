//! `Query.enforcement`: the danger zones and cameras changed since a
//! cursor, of the countries asked, with the rules of every country and the
//! lists the items come from. No position is sent: a phone keeps the set
//! of the countries it drives in and checks its route itself.
//!
//! Every item is checked again against the rules before it is served, of
//! its country and of every country within a kilometre of its points:
//! never a point where only zones are allowed, nothing where a country is
//! off, whatever the table held when the item was built. An item that
//! fails comes back as a removal.
//!
//! A cursor is `n2.<identity>.<countries>.<revision>`: the copy of the
//! database that issued it, a digest of the countries asked, and the last
//! revision the client holds. A cursor of another copy, of another set of
//! countries, or past the end of the feed, gets the whole set again
//! (`full`): a phone that adds a country receives all of it.
//! The head of the feed and the lists' reads are read at most every five
//! seconds, and first pages of the whole set at the default size are kept
//! while the revision stays.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use async_graphql::{Context, Result};
use chrono::Utc;
use lunaway_db::enforcement::ItemKind;
use lunaway_db::enforcement::{self as db, FeedHead, FeedItem};
use lunaway_domain::enforcement::{Mode, mode_at, mode_near, rule_of, served_form};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    enforcement_types::{EnforcementDelta, EnforcementItem, EnforcementRules, EnforcementSource},
    error::{internal, invalid_input},
    schema::{db as db_share, state},
};

const CURSOR: &str = "n2.";
/// Items per answer when the client does not say.
pub(crate) const DEFAULT_PAGE: i32 = 1_000;
/// Most items in one answer.
pub(crate) const MAX_PAGE: i32 = 2_000;
/// Most countries in one request.
const MAX_COUNTRIES: usize = 60;
/// What the client waits between two polls, seconds: the lists are read
/// once a day.
pub(crate) const POLL_INTERVAL_S: i32 = 6 * 3600;
/// How long the head of the feed is trusted.
const HEAD_TTL: Duration = Duration::from_secs(5);
/// How long a page of the whole set is kept, at most.
const PAGE_TTL: Duration = Duration::from_secs(60);
/// Most first pages kept: a page per set of countries asked.
const MAX_PAGES_HELD: usize = 64;

/// A page of the whole set.
#[derive(Debug)]
struct Page {
    upserts: Vec<EnforcementItem>,
    cursor: i64,
    has_more: bool,
}

/// A first page kept: when it was made, at which revision.
type HeldPage = (Instant, i64, Arc<Page>);

/// What the feed keeps in memory.
#[derive(Debug, Default)]
pub(crate) struct EnforcementCache {
    head: Mutex<Option<(Instant, FeedHead)>>,
    sources: Mutex<Option<(Instant, Arc<Vec<EnforcementSource>>)>>,
    /// First pages of the whole set at [`DEFAULT_PAGE`], by the countries
    /// asked (sorted, joined; empty for every country).
    pages: Mutex<HashMap<String, HeldPage>>,
}

/// A cursor read before the database is asked anything.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Since {
    identity: String,
    countries: String,
    revision: i64,
}

fn parse_cursor(s: &str) -> Result<Since> {
    let malformed = || invalid_input("since is not a cursor this API returned");
    let mut parts = s.strip_prefix(CURSOR).ok_or_else(malformed)?.split('.');
    let (Some(identity), Some(countries), Some(revision), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err(malformed());
    };
    let hex = |t: &str, n: usize| t.len() == n && t.bytes().all(|b| b.is_ascii_hexdigit());
    if !hex(identity, 40) || !hex(countries, 8) {
        return Err(malformed());
    }
    let revision = revision
        .parse::<i64>()
        .ok()
        .filter(|r| *r >= 0)
        .ok_or_else(malformed)?;
    Ok(Since {
        identity: identity.to_ascii_lowercase(),
        countries: countries.to_ascii_lowercase(),
        revision,
    })
}

/// A digest of the countries asked (`None`: every country), as cursors
/// carry it.
fn countries_digest(countries: Option<&[String]>) -> String {
    let joined = countries.map_or_else(|| "*".to_owned(), |c| c.join(","));
    Sha256::digest(joined.as_bytes())[..4]
        .iter()
        .fold(String::with_capacity(8), |mut s, b| {
            use std::fmt::Write as _;
            let _ = write!(s, "{b:02x}");
            s
        })
}

fn cursor(head: &FeedHead, countries: &str, revision: i64) -> String {
    format!("{CURSOR}{}.{countries}.{revision}", head.identity)
}

/// Where to read from: `None` for the whole set.
fn read_after(since: Option<&Since>, head: &FeedHead, countries: &str) -> Option<i64> {
    let s = since?;
    (s.identity == head.identity && s.countries == countries && s.revision <= head.revision)
        .then_some(s.revision)
}

/// The countries asked, upper case, sorted, each once; `None` for all.
fn countries(asked: Option<Vec<String>>) -> Result<Option<Vec<String>>> {
    let Some(asked) = asked else {
        return Ok(None);
    };
    if asked.is_empty() || asked.len() > MAX_COUNTRIES {
        return Err(invalid_input(format!(
            "countries must hold 1 to {MAX_COUNTRIES} codes"
        )));
    }
    let mut out = Vec::with_capacity(asked.len());
    for c in asked {
        if c.len() != 2 || !c.bytes().all(|b| b.is_ascii_alphabetic()) {
            return Err(invalid_input("a country is an ISO 3166-1 alpha-2 code"));
        }
        out.push(c.to_ascii_uppercase());
    }
    out.sort();
    out.dedup();
    Ok(Some(out))
}

/// Whether the rules allow serving the item now: nothing where its
/// country is off; a zone without a point, none of its points in a
/// country that is off; a camera only where its country, and every country
/// within a kilometre of its point, allow points, and its line only through
/// such countries. A point of a line at sea does not count.
pub(crate) fn allowed(item: &FeedItem) -> bool {
    let rule = rule_of(&item.country).mode;
    let line_through = |ok: fn(Mode) -> bool| {
        item.line
            .as_deref()
            .unwrap_or_default()
            .iter()
            .all(|p| lunaway_domain::region::country_at(*p).is_none() || ok(mode_at(*p)))
    };
    let points = |m: Mode| matches!(m, Mode::Exact | Mode::OffWhileDriving);
    match item.kind {
        _ if rule == Mode::Off => false,
        ItemKind::Zone => item.point.is_none() && line_through(|m| m != Mode::Off),
        ItemKind::Camera => {
            item.point
                .is_some_and(|p| points(served_form([rule, mode_near(p)])))
                && line_through(points)
        }
    }
}

async fn head(ctx: &Context<'_>) -> Result<FeedHead> {
    let cache = &state(ctx).enforcement;
    {
        let held = cache
            .head
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some((at, h)) = held.as_ref()
            && at.elapsed() < HEAD_TTL
        {
            return Ok(h.clone());
        }
    }
    let (pool, _permit) = db_share(ctx).await?;
    let h = db::feed_head(pool).await.map_err(|e| internal(&e))?;
    *cache
        .head
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some((Instant::now(), h.clone()));
    Ok(h)
}

async fn sources(ctx: &Context<'_>) -> Result<Arc<Vec<EnforcementSource>>> {
    let cache = &state(ctx).enforcement;
    let held = cache
        .sources
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
        .filter(|(at, _)| at.elapsed() < HEAD_TTL)
        .map(|(_, s)| Arc::clone(s));
    if let Some(s) = held {
        return Ok(s);
    }
    let (pool, _permit) = db_share(ctx).await?;
    let rows = db::source_reads(pool).await.map_err(|e| internal(&e))?;
    let rows = Arc::new(rows.iter().map(EnforcementSource::from).collect::<Vec<_>>());
    *cache
        .sources
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) =
        Some((Instant::now(), Arc::clone(&rows)));
    Ok(rows)
}

/// `Query.enforcement`.
pub(crate) async fn enforcement(
    ctx: &Context<'_>,
    since: Option<String>,
    asked: Option<Vec<String>>,
    first: i32,
) -> Result<EnforcementDelta> {
    if !(1..=MAX_PAGE).contains(&first) {
        return Err(invalid_input(format!(
            "first must be between 1 and {MAX_PAGE}, got {first}"
        )));
    }
    let since = since.as_deref().map(parse_cursor).transpose()?;
    let countries = countries(asked)?;
    let set = countries_digest(countries.as_deref());
    let head = head(ctx).await?;
    let sources = sources(ctx).await?;
    let now = Utc::now();
    let after = read_after(since.as_ref(), &head, &set);
    let delta = |cursor_at: i64, full, upserts, removals, has_more| EnforcementDelta {
        cursor: cursor(&head, &set, cursor_at),
        full,
        as_of: now,
        rules: EnforcementRules::current(),
        upserts,
        removals,
        sources: sources.as_ref().clone(),
        poll_interval_seconds: POLL_INTERVAL_S,
        has_more,
    };
    if after == Some(head.revision) {
        return Ok(delta(head.revision, false, Vec::new(), Vec::new(), false));
    }
    let full = after.is_none();
    let key = countries
        .as_deref()
        .map(|c| c.join(","))
        .unwrap_or_default();
    let cache = &state(ctx).enforcement;
    let cacheable = full && first == DEFAULT_PAGE;
    if cacheable {
        let held = cache
            .pages
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(&key)
            .filter(|(at, revision, _)| *revision == head.revision && at.elapsed() < PAGE_TTL)
            .map(|(_, _, p)| Arc::clone(p));
        if let Some(page) = held {
            return Ok(delta(
                page.cursor,
                true,
                page.upserts.clone(),
                Vec::new(),
                page.has_more,
            ));
        }
    }
    let rows = {
        let (pool, _permit) = db_share(ctx).await?;
        db::changed_since(
            pool,
            after.unwrap_or(0),
            head.revision,
            i64::from(first),
            !full,
            countries.as_deref(),
        )
        .await
        .map_err(|e| internal(&e))?
    };
    let has_more = rows.len() >= usize::try_from(first).unwrap_or(usize::MAX);
    let last = if has_more {
        rows.last().map_or(head.revision, |r| r.revision)
    } else {
        head.revision
    };
    let mut upserts = Vec::new();
    let mut removals: Vec<Uuid> = Vec::new();
    for r in &rows {
        let served = (!r.deleted && allowed(r))
            .then(|| EnforcementItem::of(r))
            .flatten();
        match served {
            Some(item) => upserts.push(item),
            None if !full => removals.push(r.id),
            None => {}
        }
    }
    if cacheable {
        let mut pages = cache
            .pages
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        pages.retain(|_, (_, revision, _)| *revision == head.revision);
        if pages.len() >= MAX_PAGES_HELD {
            pages.clear();
        }
        pages.insert(
            key,
            (
                Instant::now(),
                head.revision,
                Arc::new(Page {
                    upserts: upserts.clone(),
                    cursor: last,
                    has_more,
                }),
            ),
        );
    }
    Ok(delta(last, full, upserts, removals, has_more))
}

#[cfg(test)]
mod tests {
    use lunaway_domain::Position;

    use super::*;

    fn head() -> FeedHead {
        FeedHead {
            identity: "0123456789abcdef0123456789abcdef00004000".to_owned(),
            revision: 100,
        }
    }

    fn item(kind: ItemKind, country: &str, point: Option<(f64, f64)>) -> FeedItem {
        FeedItem {
            id: Uuid::nil(),
            revision: 1,
            deleted: false,
            kind,
            category: "fixed".to_owned(),
            country: country.to_owned(),
            line: None,
            point: point.map(|(lat, lon)| Position::new(lat, lon).unwrap()),
            bearing_deg: None,
            limit_kmh: None,
            source_ids: Vec::new(),
            updated_at: Utc::now(),
        }
    }

    fn with_line(mut i: FeedItem, line: &[(f64, f64)]) -> FeedItem {
        i.line = Some(
            line.iter()
                .map(|(lat, lon)| Position::new(*lat, *lon).unwrap())
                .collect(),
        );
        i
    }

    #[test]
    fn a_cursor_is_honoured_only_by_the_copy_that_issued_it_for_the_same_countries() {
        let h = head();
        let all = countries_digest(None);
        let c = parse_cursor(&cursor(&h, &all, 42)).unwrap();
        assert_eq!(read_after(Some(&c), &h, &all), Some(42));
        let other = FeedHead {
            identity: "f".repeat(40),
            ..h.clone()
        };
        assert_eq!(read_after(Some(&c), &other, &all), None);
        let ahead = parse_cursor(&cursor(&h, &all, 101)).unwrap();
        assert_eq!(read_after(Some(&ahead), &h, &all), None);
        let france = countries_digest(Some(&["FR".to_owned()]));
        let france_spain = countries_digest(Some(&["ES".to_owned(), "FR".to_owned()]));
        let c = parse_cursor(&cursor(&h, &france, 42)).unwrap();
        assert_eq!(read_after(Some(&c), &h, &france), Some(42));
        assert_eq!(
            read_after(Some(&c), &h, &france_spain),
            None,
            "a country added: the whole set, Spain's old items with it"
        );
        for forged in [
            "n2.42",
            "n1.0123456789abcdef0123456789abcdef00004000.1",
            "n2.0123456789abcdef0123456789abcdef00004000.1",
            "n2.0123456789abcdef0123456789abcdef00004000.zzzzzzzz.1",
            "",
        ] {
            assert!(parse_cursor(forged).is_err(), "{forged}");
        }
    }

    #[test]
    fn an_item_is_served_only_in_the_form_its_country_allows() {
        assert!(allowed(&item(ItemKind::Zone, "FR", None)));
        assert!(
            !allowed(&item(ItemKind::Camera, "FR", Some((48.85, 2.35)))),
            "never a point in France"
        );
        assert!(allowed(&item(ItemKind::Camera, "ES", Some((40.41, -3.70)))));
        assert!(
            !allowed(&item(ItemKind::Camera, "ES", Some((46.95, 7.44)))),
            "a point in Switzerland, whatever its row says"
        );
        assert!(
            !allowed(&item(ItemKind::Camera, "ES", Some((43.3399, -1.7808)))),
            "a point in Irun, within a kilometre of France"
        );
        assert!(
            !allowed(&with_line(
                item(ItemKind::Camera, "ES", Some((43.30, -1.85))),
                &[(43.30, -1.85), (43.37, -1.75)]
            )),
            "a section's road that runs into France"
        );
        assert!(
            !allowed(&with_line(
                item(ItemKind::Zone, "FR", None),
                &[(46.20, 6.05), (46.20, 6.14)]
            )),
            "a zone that runs into Switzerland"
        );
        assert!(
            !allowed(&item(ItemKind::Zone, "MA", None)),
            "Morocco is off"
        );
        assert!(allowed(&item(ItemKind::Camera, "DE", Some((52.52, 13.40)))));
        assert!(
            !allowed(&item(ItemKind::Zone, "XX", None)),
            "a country not in the table"
        );
    }
    #[test]
    fn countries_are_codes() {
        assert_eq!(
            countries(Some(vec!["fr".into(), "ES".into(), "FR".into()])).unwrap(),
            Some(vec!["ES".to_owned(), "FR".to_owned()])
        );
        assert!(countries(Some(vec!["FRA".into()])).is_err());
        assert!(countries(Some(Vec::new())).is_err());
        assert_eq!(countries(None).unwrap(), None);
    }
}
