//! `Query.enforcement`: the danger zones and cameras changed since a
//! cursor, of the countries asked, with the rules of every country and the
//! lists the items come from. No position is sent: a phone keeps the set
//! of the countries it drives in and checks its route itself.
//!
//! Every item is checked again against the rule of its country before it
//! is served: never a point where only zones are allowed, nothing where the
//! country is off, whatever the table held when the item was built. An
//! item that fails comes back as a removal.
//!
//! A cursor is `n1.<identity>.<revision>`: the copy of the database that
//! issued it, and the last revision the client holds. A cursor of another
//! copy, or past the end of the feed, gets the whole set again (`full`).
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
use lunaway_db::enforcement::{self as db, FeedHead, FeedItem};
use lunaway_domain::enforcement::{Mode, mode_at, rule_of};
use uuid::Uuid;

use crate::{
    enforcement_types::{EnforcementDelta, EnforcementItem, EnforcementRules, EnforcementSource},
    error::{internal, invalid_input},
    schema::{db as db_share, state},
};

const CURSOR: &str = "n1.";
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

fn parse_cursor(s: &str) -> Result<(String, i64)> {
    let malformed = || invalid_input("since is not a cursor this API returned");
    let (identity, revision) = s
        .strip_prefix(CURSOR)
        .and_then(|rest| rest.split_once('.'))
        .ok_or_else(malformed)?;
    if identity.len() != 40 || !identity.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(malformed());
    }
    let revision = revision
        .parse::<i64>()
        .ok()
        .filter(|r| *r >= 0)
        .ok_or_else(malformed)?;
    Ok((identity.to_ascii_lowercase(), revision))
}

fn cursor(head: &FeedHead, revision: i64) -> String {
    format!("{CURSOR}{}.{revision}", head.identity)
}

/// Where to read from: `None` for the whole set.
fn read_after(since: Option<&(String, i64)>, head: &FeedHead) -> Option<i64> {
    let (identity, revision) = since?;
    (*identity == head.identity && *revision <= head.revision).then_some(*revision)
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

/// Whether the rule of the item's country allows serving it now: never a
/// point where only zones may be shown, nothing where the country is off,
/// a point only where its own position's country allows points.
pub(crate) fn allowed(item: &FeedItem) -> bool {
    match (rule_of(&item.country).mode, item.kind.as_str()) {
        (Mode::Off, _) => false,
        (Mode::Zones, "zone") => item.point.is_none(),
        (Mode::Exact | Mode::OffWhileDriving, "zone") => true,
        (Mode::Exact | Mode::OffWhileDriving, "camera") => item
            .point
            .is_some_and(|p| matches!(mode_at(p), Mode::Exact | Mode::OffWhileDriving)),
        _ => false,
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
    let head = head(ctx).await?;
    let sources = sources(ctx).await?;
    let now = Utc::now();
    let after = read_after(since.as_ref(), &head);
    let delta = |cursor_at: i64, full, upserts, removals, has_more| EnforcementDelta {
        cursor: cursor(&head, cursor_at),
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

    fn item(kind: &str, country: &str, point: Option<(f64, f64)>) -> FeedItem {
        FeedItem {
            id: Uuid::nil(),
            revision: 1,
            deleted: false,
            kind: kind.to_owned(),
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

    #[test]
    fn a_cursor_is_honoured_only_by_the_copy_that_issued_it() {
        let h = head();
        let c = parse_cursor(&cursor(&h, 42)).unwrap();
        assert_eq!(read_after(Some(&c), &h), Some(42));
        let other = FeedHead {
            identity: "f".repeat(40),
            ..h.clone()
        };
        assert_eq!(read_after(Some(&c), &other), None);
        let ahead = parse_cursor(&cursor(&h, 101)).unwrap();
        assert_eq!(read_after(Some(&ahead), &h), None);
        for forged in ["n1.42", "e1.0123456789abcdef0123456789abcdef00004000.1", ""] {
            assert!(parse_cursor(forged).is_err(), "{forged}");
        }
    }

    #[test]
    fn an_item_is_served_only_in_the_form_its_country_allows() {
        assert!(allowed(&item("zone", "FR", None)));
        assert!(
            !allowed(&item("camera", "FR", Some((48.85, 2.35)))),
            "never a point in France"
        );
        assert!(allowed(&item("camera", "ES", Some((40.41, -3.70)))));
        assert!(
            !allowed(&item("camera", "ES", Some((46.95, 7.44)))),
            "a point in Switzerland, whatever its row says"
        );
        assert!(!allowed(&item("zone", "MA", None)), "Morocco is off");
        assert!(allowed(&item("camera", "DE", Some((52.52, 13.40)))));
        assert!(
            !allowed(&item("zone", "XX", None)),
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
