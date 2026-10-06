//! `Query.roadEvents`: the changes of the road events since a cursor, for
//! a phone in guidance to keep France's closures and temporary limits and
//! check its remaining route itself, every three minutes, without sending
//! its position; and `Query.roadEventSources`: each feed's freshness.
//!
//! A cursor is `e1.<identity>.<revision>`: the copy of the database that
//! issued it, and the last revision the client holds. A cursor of another
//! copy, past the end of the feed, or older than the newest purged event
//! (whose end the client would miss) gets the whole set again (`full`).
//! The head of the feed and the sources' state are read at most every five
//! seconds, and the first page of the whole set at the default size is kept
//! in memory while the revision stays, so most polls cost no query.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use async_graphql::{Context, Result};
use chrono::Utc;
use lunaway_db::road_events::{self as db, FeedHead, SourceStatus};
use lunaway_domain::road_events::EventClass;
use uuid::Uuid;

use crate::{
    error::{internal, invalid_input},
    road_event_types::{
        GqlRoadEventClass, RoadEvent, RoadEventDelta, RoadEventSourceStatus, can_block,
    },
    schema::{db as db_share, state},
};

const CURSOR: &str = "e1.";
/// Events per answer when the client does not say.
pub(crate) const DEFAULT_PAGE: i32 = 1_000;
/// Most events in one answer.
pub(crate) const MAX_PAGE: i32 = 2_000;
/// What the client waits between two polls, seconds: the DIR's increments
/// come every few minutes, the poller reads them every three.
pub(crate) const POLL_INTERVAL_S: i32 = 180;
/// How long the head of the feed is trusted.
const HEAD_TTL: Duration = Duration::from_secs(5);
/// How long a page of the whole set is kept, at most.
const PAGE_TTL: Duration = Duration::from_secs(60);
/// The classes a phone needs by default: those that can block a route.
const BLOCKING_CLASSES: [GqlRoadEventClass; 2] =
    [GqlRoadEventClass::Closure, GqlRoadEventClass::VehicleLimit];

/// A page of the whole set.
#[derive(Debug)]
struct Page {
    upserts: Vec<RoadEvent>,
    cursor: i64,
    has_more: bool,
}

/// A first page of the whole set kept: when it was made, at which
/// revision.
type HeldPage = (Instant, i64, Arc<Page>);

/// What the feed keeps in memory.
#[derive(Debug, Default)]
pub(crate) struct RoadEventsCache {
    head: Mutex<Option<(Instant, FeedHead)>>,
    /// The sources' state, read as often as the head.
    sources: Mutex<Option<(Instant, Arc<Vec<SourceStatus>>)>>,
    /// The first page of the whole set at [`DEFAULT_PAGE`], by classes:
    /// at most 64 entries (five class bits and the blocking flag), every
    /// one of the current revision. Keying on the page size too would let
    /// a client fill the memory with 2 000 sizes of the same page.
    pages: Mutex<HashMap<u8, HeldPage>>,
}

fn mask(classes: &[EventClass], blocking_only: bool) -> u8 {
    let start = if blocking_only { 32 } else { 0 };
    classes.iter().fold(start, |m, c| {
        m | match c {
            EventClass::Closure => 1,
            EventClass::Works => 2,
            EventClass::LaneRestriction => 4,
            EventClass::VehicleLimit => 8,
            EventClass::Detour => 16,
        }
    })
}

/// A cursor read before the database is asked anything: its identity and
/// revision.
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
    (*identity == head.identity && *revision <= head.revision && *revision >= head.purged_through)
        .then_some(*revision)
}

async fn head(ctx: &Context<'_>) -> Result<FeedHead> {
    let cache = &state(ctx).road_events;
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

async fn sources(ctx: &Context<'_>) -> Result<Vec<RoadEventSourceStatus>> {
    let cache = &state(ctx).road_events;
    let held = cache
        .sources
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
        .filter(|(at, _)| at.elapsed() < HEAD_TTL)
        .map(|(_, s)| Arc::clone(s));
    let rows = match held {
        Some(rows) => rows,
        None => {
            let (pool, _permit) = db_share(ctx).await?;
            let rows = Arc::new(db::sources(pool).await.map_err(|e| internal(&e))?);
            *cache
                .sources
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) =
                Some((Instant::now(), Arc::clone(&rows)));
            rows
        }
    };
    let now = Utc::now();
    Ok(rows
        .iter()
        .map(|s| RoadEventSourceStatus::of(s, now))
        .collect())
}

/// `Query.roadEventSources`.
pub(crate) async fn road_event_sources(ctx: &Context<'_>) -> Result<Vec<RoadEventSourceStatus>> {
    sources(ctx).await
}

/// `Query.roadEvents`.
pub(crate) async fn road_events(
    ctx: &Context<'_>,
    since: Option<String>,
    classes: Option<Vec<GqlRoadEventClass>>,
    blocking_only: bool,
    first: i32,
) -> Result<RoadEventDelta> {
    if !(1..=MAX_PAGE).contains(&first) {
        return Err(invalid_input(format!(
            "first must be between 1 and {MAX_PAGE}, got {first}"
        )));
    }
    let since = since.as_deref().map(parse_cursor).transpose()?;
    let mut classes: Vec<EventClass> = classes
        .unwrap_or_else(|| BLOCKING_CLASSES.to_vec())
        .into_iter()
        .map(EventClass::from)
        .collect();
    classes.sort();
    classes.dedup();
    let head = head(ctx).await?;
    let now = Utc::now();
    let sources = sources(ctx).await?;
    let after = read_after(since.as_ref(), &head);
    let mut full = after.is_none();
    if after == Some(head.revision) {
        return Ok(RoadEventDelta {
            cursor: cursor(&head, head.revision),
            full: false,
            as_of: now,
            upserts: Vec::new(),
            removals: Vec::new(),
            sources,
            poll_interval_seconds: POLL_INTERVAL_S,
            has_more: false,
        });
    }
    let key = mask(&classes, blocking_only);
    let cache = &state(ctx).road_events;
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
            return Ok(RoadEventDelta {
                cursor: cursor(&head, page.cursor),
                full: true,
                as_of: now,
                upserts: page.upserts.clone(),
                removals: Vec::new(),
                sources,
                poll_interval_seconds: POLL_INTERVAL_S,
                has_more: page.has_more,
            });
        }
    }
    // The whole set reads only the events asked for; changes read every
    // event changed, so that one leaving the selection is removed.
    let rows = {
        let (pool, _permit) = db_share(ctx).await?;
        let changes = match after {
            Some(a) => db::changed_since(pool, a, head.revision, i64::from(first))
                .await
                .map_err(|e| internal(&e))?,
            None => None,
        };
        match changes {
            Some(rows) => rows,
            None => {
                // No cursor, or ends purged since it was issued.
                full = true;
                db::live_events(
                    pool,
                    &classes,
                    blocking_only,
                    0,
                    head.revision,
                    i64::from(first),
                )
                .await
                .map_err(|e| internal(&e))?
            }
        }
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
        if r.ended_at.is_none() && classes.contains(&r.class) && (!blocking_only || can_block(r)) {
            upserts.push(RoadEvent::of(r, now));
        } else if !full {
            removals.push(r.id);
        }
    }
    if cacheable {
        let mut pages = cache
            .pages
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        pages.retain(|_, (_, revision, _)| *revision == head.revision);
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
    Ok(RoadEventDelta {
        cursor: cursor(&head, last),
        full,
        as_of: now,
        upserts,
        removals,
        sources,
        poll_interval_seconds: POLL_INTERVAL_S,
        has_more,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn head() -> FeedHead {
        FeedHead {
            identity: "0123456789abcdef0123456789abcdef00004000".to_owned(),
            revision: 100,
            purged_through: 20,
        }
    }

    #[test]
    fn a_cursor_is_honoured_only_by_the_copy_that_issued_it_and_while_it_is_whole() {
        let h = head();
        let c = parse_cursor(&cursor(&h, 42)).unwrap();
        assert_eq!(read_after(Some(&c), &h), Some(42));
        assert_eq!(read_after(None, &h), None, "no cursor: the whole set");
        let restored = FeedHead {
            identity: "f".repeat(40),
            ..h.clone()
        };
        assert_eq!(
            read_after(Some(&c), &restored),
            None,
            "another copy of the database: the whole set again"
        );
        let old = parse_cursor(&cursor(&h, 10)).unwrap();
        assert_eq!(
            read_after(Some(&old), &h),
            None,
            "older than the newest purged event: its end would be missed"
        );
        let ahead = parse_cursor(&cursor(&h, 101)).unwrap();
        assert_eq!(read_after(Some(&ahead), &h), None);
        for forged in [
            "e1.42",
            "e1.zz.1",
            "c2.0123456789abcdef0123456789abcdef00004000.1",
            "e1.0123456789abcdef0123456789abcdef00004000.-1",
            "",
        ] {
            assert!(parse_cursor(forged).is_err(), "{forged}");
        }
    }

    #[test]
    fn classes_make_a_stable_key() {
        assert_eq!(
            mask(&[EventClass::VehicleLimit, EventClass::Closure], true),
            mask(&[EventClass::Closure, EventClass::VehicleLimit], true)
        );
        assert_ne!(
            mask(&[EventClass::Closure], true),
            mask(&[EventClass::Works], true)
        );
        assert_ne!(
            mask(&[EventClass::Closure], true),
            mask(&[EventClass::Closure], false)
        );
    }
}
