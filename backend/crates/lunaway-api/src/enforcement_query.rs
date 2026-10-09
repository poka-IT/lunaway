//! `Query.enforcement`: the danger zones and cameras changed since a
//! cursor, of the countries asked, with the rules of every country and the
//! lists the items come from. No position is sent: a phone keeps the set
//! of the countries it drives in and checks its route itself.
//!
//! A client may name the countries where its user asked for the cameras'
//! positions in place of zones (`exactIn`, France only,
//! [`OptIns`]): it gets the items for every client and those for its
//! choices, never the form meant for the others. The choice is neither
//! logged nor kept: no log line, error message or metric of this module
//! carries it.
//!
//! Every item is checked again against the rules before it is served, read
//! with the client's choices: its country's, the rules of every country
//! within a kilometre of a camera's point, and those of the countries a
//! line runs through (read every kilometre or so; the build read every
//! 200 m with the margin): never a point where only zones are allowed to
//! this client (in France without its choice), nothing where a country is
//! off, whatever the table held when the item was built or a row says. An
//! item that fails comes back as a removal. The check and the conversion
//! run off the async threads.
//!
//! A cursor is `n3.<identity>.<set>.<revision>`: the copy of the database
//! that issued it, a digest of the countries asked and of the choices, and
//! the last revision the client holds. A cursor of another copy, of
//! another set of countries or choices, of the format before the choices
//! (`n2.`), or past the end of the feed, gets the whole set again
//! (`full`): a phone that adds a country receives all of it, and one
//! whose user changes the setting gets the other form of every camera
//! concerned. The head of the feed and the lists' reads are read at most
//! every five seconds, and first pages of the whole set at the default
//! size are kept while the revision stays.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use async_graphql::{Context, Result};
use chrono::Utc;
use lunaway_db::enforcement::ItemKind;
use lunaway_db::enforcement::{self as db, FeedHead, FeedItem};
use lunaway_domain::{
    SourceId,
    enforcement::{Mode, OptIns},
};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    enforcement_types::{EnforcementDelta, EnforcementItem, EnforcementRules, EnforcementSource},
    error::{internal, invalid_input},
    schema::{db as db_share, state},
};

const CURSOR: &str = "n3.";
/// The format before the choices: a phone that holds one gets the whole
/// set once, read with its choices.
const STALE_CURSOR: &str = "n2.";
/// Items per answer when the client does not say.
pub(crate) const DEFAULT_PAGE: i32 = 1_000;
/// Most items in one answer.
pub(crate) const MAX_PAGE: i32 = 2_000;
/// Most countries in one request.
const MAX_COUNTRIES: usize = 60;
/// Most countries in `exactIn`: more than the table will ever offer a
/// choice in, few enough to stay cheap.
const MAX_EXACT_IN: usize = 8;
/// What the client waits between two polls, seconds: the lists are read
/// once a day.
pub(crate) const POLL_INTERVAL_S: i32 = 6 * 3600;
/// How long the head of the feed is trusted.
const HEAD_TTL: Duration = Duration::from_secs(5);
/// How long a page of the whole set is kept, at most.
const PAGE_TTL: Duration = Duration::from_secs(60);
/// A line's points read by the serve-time check: one in so many.
const LINE_CHECK_STEP: usize = 20;
/// Shortest zone served, metres, of those the server builds: 500 m of road
/// at the least (in a built-up area, `FRENCH_ZONES`). The line served is
/// shorter than its road, its points 50 m apart along it joined by chords
/// and read back rounded to six decimals: the margin covers both. A
/// shorter line around a camera would mark its place, whatever wrote the
/// row.
const MIN_BUILT_ZONE_M: f64 = 400.0;
/// Shortest zone served of those an authority publishes as zones, served
/// as they are: Ireland's Garda zones, 100 m at the least at their import,
/// measured on the full coordinates; a metre less for the six decimals
/// they are read back with.
const MIN_PUBLISHED_ZONE_M: f64 = 99.0;
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
    /// asked and the choices ([`set_key`]).
    pages: Mutex<HashMap<String, HeldPage>>,
}

/// A cursor read before the database is asked anything.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Since {
    identity: String,
    set: String,
    revision: i64,
}

/// The cursor `s`: `None` for one of the format before the choices, which
/// gets the whole set again.
fn parse_cursor(s: &str) -> Result<Option<Since>> {
    let malformed = || invalid_input("since is not a cursor this API returned");
    let (rest, stale) = match (s.strip_prefix(CURSOR), s.strip_prefix(STALE_CURSOR)) {
        (Some(rest), _) => (rest, false),
        (None, Some(rest)) => (rest, true),
        (None, None) => return Err(malformed()),
    };
    let mut parts = rest.split('.');
    let (Some(identity), Some(set), Some(revision), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return Err(malformed());
    };
    let hex = |t: &str, n: usize| t.len() == n && t.bytes().all(|b| b.is_ascii_hexdigit());
    if !hex(identity, 40) || !hex(set, 8) {
        return Err(malformed());
    }
    let revision = revision
        .parse::<i64>()
        .ok()
        .filter(|r| *r >= 0)
        .ok_or_else(malformed)?;
    Ok((!stale).then(|| Since {
        identity: identity.to_ascii_lowercase(),
        set: set.to_ascii_lowercase(),
        revision,
    }))
}

/// The countries asked (`None`: every country) and the choices, joined:
/// the key of a page kept, and what a cursor digests.
fn set_key(countries: Option<&[String]>, chosen: &OptIns) -> String {
    let countries = countries.map_or_else(|| "*".to_owned(), |c| c.join(","));
    format!("{countries}|{}", chosen.countries().join(","))
}

/// A digest of [`set_key`], as cursors carry it.
fn set_digest(key: &str) -> String {
    Sha256::digest(key.as_bytes())[..4]
        .iter()
        .fold(String::with_capacity(8), |mut s, b| {
            use std::fmt::Write as _;
            let _ = write!(s, "{b:02x}");
            s
        })
}

fn cursor(head: &FeedHead, set: &str, revision: i64) -> String {
    format!("{CURSOR}{}.{set}.{revision}", head.identity)
}

/// Where to read from: `None` for the whole set.
fn read_after(since: Option<&Since>, head: &FeedHead, set: &str) -> Option<i64> {
    let s = since?;
    (s.identity == head.identity && s.set == set && s.revision <= head.revision)
        .then_some(s.revision)
}

/// The choices of `exactIn`: at most [`MAX_EXACT_IN`] codes of two
/// letters, of which only those the table offers a choice in count. The
/// error never repeats a value: the choice is not logged, and an error
/// message may be.
fn exact_in(asked: Option<Vec<String>>) -> Result<OptIns> {
    let asked = asked.unwrap_or_default();
    if asked.len() > MAX_EXACT_IN {
        return Err(invalid_input(format!(
            "exactIn must hold {MAX_EXACT_IN} codes at most"
        )));
    }
    if !asked
        .iter()
        .all(|c| c.len() == 2 && c.bytes().all(|b| b.is_ascii_alphabetic()))
    {
        return Err(invalid_input("exactIn holds ISO 3166-1 alpha-2 codes only"));
    }
    Ok(OptIns::new(asked.iter().map(String::as_str)))
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

/// Whether the rules, read with the client's choices `chosen`, allow
/// serving the item now: nothing where its country is off; a zone without
/// a point, as long as a zone is ([`zone_long_enough`]), none of its points
/// in a country that is off; a camera only
/// where its country, and every country within a kilometre of its point,
/// allow points to this client, and its line only through such countries.
/// A point of a line at sea does not count. Whichever clients a row says
/// the item is for, a French point never reaches a client that did not
/// choose France's positions.
pub(crate) fn allowed(item: &FeedItem, chosen: &OptIns) -> bool {
    let rule = chosen.mode_of(&item.country);
    // Every 20th point of a zone (one a kilometre) and the last: the build
    // read them every 200 m, with the border margin.
    let line_through = |ok: fn(Mode) -> bool| {
        let line = item.line.as_deref().unwrap_or_default();
        line.iter()
            .step_by(LINE_CHECK_STEP)
            .chain(line.last())
            .all(|p| lunaway_domain::region::country_at(*p).is_none_or(|c| ok(chosen.mode_of(c))))
    };
    let points = |m: Mode| matches!(m, Mode::Exact | Mode::OffWhileDriving);
    match item.kind {
        _ if rule == Mode::Off => false,
        ItemKind::Zone => {
            item.point.is_none() && zone_long_enough(item) && line_through(|m| m != Mode::Off)
        }
        ItemKind::Camera => {
            item.point
                .is_some_and(|p| points(chosen.form_of(&item.country, p)))
                && line_through(points)
        }
    }
}

/// Whether a zone's line is as long as a zone of its kind: one the server
/// builds, [`MIN_BUILT_ZONE_M`]; one an authority publishes,
/// [`MIN_PUBLISHED_ZONE_M`]. Every zone, in any country: a zone stands in
/// for a point that may not be shown.
fn zone_long_enough(item: &FeedItem) -> bool {
    // A zone the Garda publishes: Ireland's, and its list its only source.
    let garda = SourceId::IE_GARDA;
    let published = item.country == "IE"
        && item
            .source_ids
            .iter()
            .map(String::as_str)
            .eq([garda.as_str()]);
    let floor = if published {
        MIN_PUBLISHED_ZONE_M
    } else {
        MIN_BUILT_ZONE_M
    };
    let mut length = 0.0;
    item.line
        .as_deref()
        .unwrap_or_default()
        .windows(2)
        .any(|w| {
            length += w[0].distance_m(w[1]);
            length >= floor
        })
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
    exact: Option<Vec<String>>,
    first: i32,
) -> Result<EnforcementDelta> {
    if !(1..=MAX_PAGE).contains(&first) {
        return Err(invalid_input(format!(
            "first must be between 1 and {MAX_PAGE}, got {first}"
        )));
    }
    let since = since.as_deref().map(parse_cursor).transpose()?.flatten();
    let countries = countries(asked)?;
    let chosen = exact_in(exact)?;
    let key = set_key(countries.as_deref(), &chosen);
    let set = set_digest(&key);
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
            &chosen,
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
    // Border lookups and polyline encoding for up to 2 000 items: off the
    // async threads.
    let (upserts, removals) = tokio::task::spawn_blocking(move || {
        let mut upserts = Vec::new();
        let mut removals: Vec<Uuid> = Vec::new();
        for r in &rows {
            // An item now for the clients on the other side of a choice
            // comes back as a removal: this client may hold it from when
            // it served everyone.
            let served = (!r.deleted && r.visible && allowed(r, &chosen))
                .then(|| EnforcementItem::of(r))
                .flatten();
            match served {
                Some(item) => upserts.push(item),
                None if !full => removals.push(r.id),
                None => {}
            }
        }
        (upserts, removals)
    })
    .await
    .map_err(|e| internal(&e))?;
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
    use lunaway_db::enforcement::Variant;
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
            variant: Variant::All,
            visible: true,
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

    fn set(countries: Option<&[&str]>, chosen: &[&str]) -> String {
        let countries: Option<Vec<String>> =
            countries.map(|c| c.iter().map(|s| (*s).to_owned()).collect());
        set_digest(&set_key(
            countries.as_deref(),
            &OptIns::new(chosen.iter().copied()),
        ))
    }

    #[test]
    fn a_cursor_is_honoured_only_by_the_copy_that_issued_it_for_the_same_set() {
        let h = head();
        let all = set(None, &[]);
        let since = |s: &str| parse_cursor(s).unwrap().unwrap();
        let c = since(&cursor(&h, &all, 42));
        assert_eq!(read_after(Some(&c), &h, &all), Some(42));
        let other = FeedHead {
            identity: "f".repeat(40),
            ..h.clone()
        };
        assert_eq!(read_after(Some(&c), &other, &all), None);
        let ahead = since(&cursor(&h, &all, 101));
        assert_eq!(read_after(Some(&ahead), &h, &all), None);
        let france = set(Some(&["FR"]), &[]);
        let france_spain = set(Some(&["ES", "FR"]), &[]);
        let c = since(&cursor(&h, &france, 42));
        assert_eq!(read_after(Some(&c), &h, &france), Some(42));
        assert_eq!(
            read_after(Some(&c), &h, &france_spain),
            None,
            "a country added: the whole set, Spain's old items with it"
        );
        let france_exact = set(Some(&["FR"]), &["FR"]);
        assert_eq!(
            read_after(Some(&c), &h, &france_exact),
            None,
            "the setting turned on: the whole set, in the other form"
        );
        let c = since(&cursor(&h, &france_exact, 42));
        assert_eq!(
            read_after(Some(&c), &h, &france),
            None,
            "the setting turned off: the whole set, zones again"
        );
        assert_eq!(
            set(Some(&["FR"]), &["ES", "CH", "IT"]),
            france,
            "choices no country offers change nothing, not even the cursor"
        );
        assert_eq!(
            parse_cursor("n2.0123456789abcdef0123456789abcdef00004000.0a1b2c3d.42").unwrap(),
            None,
            "a cursor of the format before the choices gets the whole set"
        );
        for forged in [
            "n3.42",
            "n2.42",
            "n1.0123456789abcdef0123456789abcdef00004000.1",
            "n3.0123456789abcdef0123456789abcdef00004000.1",
            "n3.0123456789abcdef0123456789abcdef00004000.zzzzzzzz.1",
            "",
        ] {
            assert!(parse_cursor(forged).is_err(), "{forged}");
        }
    }

    /// A zone of `metres` along a meridian of `country`'s, from `sources`.
    fn zone_in(country: &str, start: (f64, f64), metres: f64, sources: &[&str]) -> FeedItem {
        let start = Position::new(start.0, start.1).unwrap();
        let end = lunaway_domain::enforcement::toward(start, 0.0, metres).unwrap();
        let mut z = with_line(
            item(ItemKind::Zone, country, None),
            &[(start.lat(), start.lon()), (end.lat(), end.lon())],
        );
        z.source_ids = sources.iter().map(|s| (*s).to_owned()).collect();
        z
    }

    /// A French zone of `metres` in the Limousin.
    fn zone_of(metres: f64, sources: &[&str]) -> FeedItem {
        zone_in("FR", (45.8, 1.26), metres, sources)
    }

    /// An Irish zone of `metres` by Dublin.
    fn irish_zone(metres: f64, sources: &[&str]) -> FeedItem {
        zone_in("IE", (53.33, -6.40), metres, sources)
    }

    #[test]
    fn a_zone_shorter_than_any_zone_is_never_served() {
        let none = OptIns::default();
        let built = ["securite-routiere", "osm"];
        assert!(allowed(&zone_of(500.0, &built), &none));
        assert!(allowed(&zone_of(405.0, &built), &none));
        assert!(!allowed(&zone_of(395.0, &built), &none));
        assert!(
            !allowed(&zone_of(1.0, &built), &none),
            "two points a metre apart around a camera mark its place"
        );
        let garda = ["ie-garda"];
        assert!(
            allowed(&irish_zone(104.0, &garda), &none),
            "a zone the Garda publishes, as it is"
        );
        assert!(!allowed(&irish_zone(94.0, &garda), &none));
        assert!(
            !allowed(&irish_zone(150.0, &["ie-garda", "osm"]), &none),
            "a built zone, whatever list it names among others"
        );
        assert!(
            !allowed(&zone_of(150.0, &garda), &none),
            "the Garda's list publishes no zone outside Ireland"
        );
        assert!(!allowed(&irish_zone(150.0, &[]), &none));
    }

    #[test]
    fn an_item_is_served_only_in_the_form_its_country_allows() {
        let none = OptIns::default();
        assert!(allowed(&zone_of(2_000.0, &["securite-routiere"]), &none));
        assert!(
            !allowed(&item(ItemKind::Camera, "FR", Some((48.85, 2.35))), &none),
            "never a point in France without the user's choice"
        );
        assert!(allowed(
            &item(ItemKind::Camera, "ES", Some((40.41, -3.70))),
            &none
        ));
        assert!(
            !allowed(&item(ItemKind::Camera, "ES", Some((46.95, 7.44))), &none),
            "a point in Switzerland, whatever its row says"
        );
        assert!(
            !allowed(
                &item(ItemKind::Camera, "ES", Some((43.3399, -1.7808))),
                &none
            ),
            "a point in Irun, within a kilometre of France"
        );
        assert!(
            !allowed(
                &with_line(
                    item(ItemKind::Camera, "ES", Some((43.30, -1.85))),
                    &[(43.30, -1.85), (43.37, -1.75)]
                ),
                &none
            ),
            "a section's road that runs into France"
        );
        assert!(
            !allowed(
                &with_line(
                    item(ItemKind::Zone, "FR", None),
                    &[(46.20, 6.05), (46.20, 6.14)]
                ),
                &none
            ),
            "a zone that runs into Switzerland"
        );
        // A zone long enough, its line in a country that is open: only its
        // own country's rule refuses it.
        assert!(
            !allowed(&zone_in("MA", (45.8, 1.26), 2_000.0, &["osm"]), &none),
            "Morocco is off"
        );
        assert!(allowed(
            &item(ItemKind::Camera, "DE", Some((52.52, 13.40))),
            &none
        ));
        assert!(
            !allowed(&zone_in("XX", (45.8, 1.26), 2_000.0, &["osm"]), &none),
            "a country not in the table"
        );
    }

    #[test]
    fn a_choice_lets_france_s_points_through_and_nothing_that_is_off() {
        let fr = OptIns::new(["FR"]);
        assert!(allowed(
            &item(ItemKind::Camera, "FR", Some((48.85, 2.35))),
            &fr
        ));
        assert!(
            allowed(&item(ItemKind::Camera, "ES", Some((43.3399, -1.7808))), &fr),
            "Irun, by France, for a client that chose France's positions"
        );
        assert!(
            allowed(
                &with_line(
                    item(ItemKind::Camera, "ES", Some((43.30, -1.85))),
                    &[(43.30, -1.85), (43.37, -1.75)]
                ),
                &fr
            ),
            "a section's road that runs into France"
        );
        assert!(
            !allowed(&item(ItemKind::Camera, "FR", Some((46.1453, 6.0808))), &fr),
            "a French point within a kilometre of Switzerland"
        );
        assert!(
            !allowed(&item(ItemKind::Camera, "FR", Some((43.7430, 7.4210))), &fr),
            "a French point within a kilometre of Monaco"
        );
        assert!(
            !allowed(
                &item(ItemKind::Camera, "PT", Some((38.7223, -9.1393))),
                &OptIns::new(["PT", "FR"])
            ),
            "Portugal offers no choice: zones only"
        );
        assert!(
            !allowed(
                &item(ItemKind::Camera, "FR", Some((48.85, 2.35))),
                &OptIns::new(["ES", "CH", "IT"])
            ),
            "choices France does not take let no French point through"
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

    #[test]
    fn exact_in_takes_a_few_codes_and_never_repeats_one_in_its_error() {
        assert!(exact_in(None).unwrap().is_empty());
        assert!(exact_in(Some(Vec::new())).unwrap().is_empty());
        assert_eq!(
            exact_in(Some(vec!["fr".into()])).unwrap().countries(),
            ["FR"]
        );
        assert!(
            exact_in(Some(vec!["ES".into(), "CH".into(), "IT".into()]))
                .unwrap()
                .is_empty(),
            "a country that offers no choice is ignored"
        );
        let nine: Vec<String> = (0..9).map(|_| "FR".to_owned()).collect();
        assert!(exact_in(Some(nine)).is_err(), "8 codes at most");
        let refused = exact_in(Some(vec!["Q7".into()])).unwrap_err();
        assert!(
            !refused.message.contains("Q7"),
            "the choice is never logged, and an error may be: {}",
            refused.message
        );
    }
}
