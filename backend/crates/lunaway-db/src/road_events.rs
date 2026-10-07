//! Road events: what the importers store, what every route is checked
//! against, the change feed the app polls during guidance, and the
//! community's reports (`migrations/*_road_events.sql`).
//!
//! Every writer holds one advisory lock until it commits
//! ([`begin_writer`]): the feed hands out the changes past a client's
//! revision, which is correct only when revisions commit in the order they
//! are taken.

use std::{borrow::Cow, collections::HashMap, fmt::Write as _};

use chrono::{DateTime, Duration, Utc};
use lunaway_domain::{
    Position,
    road_events::{
        AppliesTo, Carriageway, Confidence, EndReason, EventClass, EventDirection, MatchQuality,
        Schedule, SourceGeometry, VehicleLimits,
        community::{self, ReportFacts, ReportKind},
    },
    routing::RestrictionRecord,
};
use sha2::{Digest as _, Sha256};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::DbError;

/// Key of the road events writers' lock: "lunaroad" in ASCII. The same
/// figure is in the trigger of the migration.
const WRITER_LOCK: i64 = 0x6c75_6e61_726f_6164;
/// Events per insert statement.
const BATCH: usize = 500;
/// The source of the users' reports.
pub const COMMUNITY: &str = "community";
/// Most route points a corridor query takes, as for the restrictions.
pub const MAX_ROUTE_POINTS: usize = crate::routing::MAX_ROUTE_POINTS;
/// How far ahead phones receive an event, hours: the feed carries the
/// events in force or starting within this window, and the lifecycle pass
/// ([`lifecycle`]) lets one in once its start comes within it. The figure
/// lives in SQL (`road_events_feed_window()`, read by the revision trigger
/// and by the pass); this copy is for the tests and the documentation.
pub const FEED_WINDOW_HOURS: i64 = 48;

/// A transaction that holds the road events writers' lock.
pub struct EventWriter(Transaction<'static, Postgres>);

impl EventWriter {
    /// Commits.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the commit fails.
    pub async fn commit(self) -> Result<(), DbError> {
        self.0.commit().await?;
        Ok(())
    }
}

/// Starts a transaction holding the writers' lock, waiting for another
/// writer for up to half an hour whatever the role's statement timeout.
///
/// # Errors
///
/// [`DbError`] when the database fails.
pub async fn begin_writer(pool: &PgPool) -> Result<EventWriter, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SET LOCAL statement_timeout = '30min'")
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SELECT pg_advisory_xact_lock($1)", WRITER_LOCK)
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SET LOCAL statement_timeout TO DEFAULT")
        .execute(&mut *tx)
        .await?;
    Ok(EventWriter(tx))
}

/// Starts a transaction holding the writers' lock for a user's request,
/// waiting at most three seconds: a request must not hold one of the API's
/// pooled connections while a feed is written. [`is_busy`] tells that
/// wait's failure apart.
///
/// # Errors
///
/// [`DbError`] when the database fails or the lock is not free in time.
pub async fn begin_writer_now(pool: &PgPool) -> Result<EventWriter, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SET LOCAL lock_timeout = '3s'")
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SELECT pg_advisory_xact_lock($1)", WRITER_LOCK)
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SET LOCAL lock_timeout TO DEFAULT")
        .execute(&mut *tx)
        .await?;
    Ok(EventWriter(tx))
}

/// Whether `error` is the writers' lock not freed in time
/// ([`begin_writer_now`]): `lock_not_available`, SQLSTATE 55P03.
#[must_use]
pub fn is_busy(error: &DbError) -> bool {
    match error {
        DbError::Query(e) => e
            .as_database_error()
            .and_then(|d| d.code())
            .is_some_and(|c| c == "55P03"),
        _ => false,
    }
}

/// An event as an importer hands it over.
#[derive(Debug, Clone, PartialEq)]
pub struct NewEvent {
    /// The source's identifier.
    pub external_id: String,
    /// The source's version; with [`upsert`]'s `ordered`, an older version
    /// never replaces a newer one. Zero-padded, so text order is number
    /// order.
    pub external_version: String,
    /// The situation or order it belongs to.
    pub situation_id: Option<String>,
    /// What it does.
    pub class: EventClass,
    /// The source's own term.
    pub detail: String,
    /// Which part of the road.
    pub carriageway: Carriageway,
    /// The direction it concerns.
    pub direction: EventDirection,
    /// Canonical road number.
    pub road_number: Option<String>,
    /// Road name.
    pub road_name: Option<String>,
    /// Vehicle limits, for a vehicle limit.
    pub limits: VehicleLimits,
    /// Validity start.
    pub valid_from: DateTime<Utc>,
    /// Validity end.
    pub valid_to: Option<DateTime<Utc>>,
    /// When within the validity.
    pub schedule: Schedule,
    /// The geometry as the source gives it.
    pub geometry: SourceGeometry,
    /// How it is placed on the graph so far: `Pending` for lines the
    /// matcher will place, `Ramp` or `Point` for the route-time rules,
    /// `Unmatched` for areas and loose points.
    pub match_quality: MatchQuality,
    /// How far to believe it.
    pub confidence: Confidence,
    /// Public description, in the source's language.
    pub description: Option<String>,
    /// The detour the source describes.
    pub detour: Option<String>,
    /// The source's page of it.
    pub url: Option<String>,
    /// The source's time of this version.
    pub source_updated_at: Option<DateTime<Utc>>,
    /// The source's record as it came.
    pub raw: String,
    /// Why it is already over, when the source says so.
    pub ended: Option<EndReason>,
}

fn push_points(s: &mut String, points: &[Position]) {
    s.push('(');
    for (i, p) in points.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        let _ = write!(s, "{} {}", p.lon(), p.lat());
    }
    s.push(')');
}

/// The WKT of a source geometry.
#[must_use]
pub fn wkt(g: &SourceGeometry) -> String {
    let mut s = String::new();
    match g {
        SourceGeometry::Point(p) => {
            let _ = write!(s, "POINT({} {})", p.lon(), p.lat());
        }
        SourceGeometry::Lines(lines) if lines.len() == 1 => {
            s.push_str("LINESTRING");
            push_points(&mut s, &lines[0]);
        }
        SourceGeometry::Lines(lines) => {
            s.push_str("MULTILINESTRING(");
            for (i, l) in lines.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                push_points(&mut s, l);
            }
            s.push(')');
        }
        SourceGeometry::Polygons(rings) => {
            s.push_str("MULTIPOLYGON(");
            for (i, r) in rings.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                let mut closed = r.clone();
                if closed.first() != closed.last()
                    && let Some(first) = closed.first().copied()
                {
                    closed.push(first);
                }
                s.push('(');
                push_points(&mut s, &closed);
                s.push(')');
            }
            s.push(')');
        }
    }
    s
}

fn multiline_wkt(lines: &[Vec<Position>]) -> String {
    let mut s = String::from("MULTILINESTRING(");
    for (i, l) in lines.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        push_points(&mut s, l);
    }
    s.push(')');
    s
}

/// The digest of what the app receives of an event: a change of it, and
/// only that, moves the event's revision.
fn content_hash(e: &NewEvent) -> String {
    let visible = serde_json::json!([
        e.class.code(),
        e.detail,
        e.carriageway.code(),
        e.direction.code(),
        e.road_number,
        e.road_name,
        e.limits,
        e.valid_from,
        e.valid_to,
        e.schedule,
        wkt(&e.geometry),
        e.confidence.code(),
        e.description,
        e.detour,
        e.url,
    ]);
    digest(&visible.to_string())
}

/// A text cut to `n` characters: the columns bound what a source may
/// write, and a feed's free text has no bound of its own.
fn clip(text: Option<&str>, n: usize) -> Option<String> {
    text.map(|t| t.chars().take(n).collect())
}

fn digest(text: &str) -> String {
    Sha256::digest(text.as_bytes())
        .iter()
        .take(16)
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// What an [`upsert`] did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct UpsertReport {
    /// New events.
    pub inserted: u64,
    /// Events whose content changed.
    pub changed: u64,
    /// Events seen again unchanged.
    pub unchanged: u64,
    /// Updates refused because the stored version is newer.
    pub older: u64,
    /// Records refused before the insert ([`storable`]): an identifier the
    /// table cannot hold, a figure out of range, no drawable geometry, an
    /// end before the start. One such record must not fail its batch, and
    /// with it every closure of the feed.
    pub refused: u64,
    /// Records dropped for a later version of the same identifier in the
    /// same call.
    pub duplicates: u64,
}

/// Largest figure each limit column holds (the migration's checks): a
/// figure beyond is a unit error at the source (a weight in kilograms).
const MAX_HEIGHT_M: f64 = 10.0;
const MAX_WIDTH_M: f64 = 10.0;
const MAX_LENGTH_M: f64 = 50.0;
const MAX_WEIGHT_T: f64 = 100.0;

fn figure_fits(v: Option<f64>, max: f64) -> bool {
    v.is_none_or(|v| v.is_finite() && v > 0.0 && v <= max)
}

/// A road number as the table's check reads it: one to three capitals,
/// one to four digits, an optional capital.
fn road_number_fits(n: &str) -> bool {
    let b = n.as_bytes();
    let letters = b.iter().take_while(|c| c.is_ascii_uppercase()).count();
    let digits = b[letters..]
        .iter()
        .take_while(|c| c.is_ascii_digit())
        .count();
    let rest = &b[letters + digits..];
    (1..=3).contains(&letters)
        && (1..=4).contains(&digits)
        && (rest.is_empty() || (rest.len() == 1 && rest[0].is_ascii_uppercase()))
}

fn has_nul(t: &str) -> bool {
    t.contains('\0')
}

fn no_nul(t: &str) -> String {
    t.replace('\0', "")
}

/// A ring PostGIS accepts once closed: three distinct corners and the
/// first again.
fn ring_fits(r: &[Position]) -> bool {
    let closing = usize::from(r.first() != r.last());
    r.len() + closing >= 4
}

/// The geometry the table can hold: lines of two points or more, rings of
/// three corners or more; `None` when nothing is left.
fn drawable(g: &SourceGeometry) -> Option<Cow<'_, SourceGeometry>> {
    match g {
        SourceGeometry::Point(_) => Some(Cow::Borrowed(g)),
        SourceGeometry::Lines(lines) => {
            if lines.iter().all(|l| l.len() >= 2) {
                return (!lines.is_empty()).then_some(Cow::Borrowed(g));
            }
            let kept: Vec<Vec<Position>> = lines.iter().filter(|l| l.len() >= 2).cloned().collect();
            (!kept.is_empty()).then_some(Cow::Owned(SourceGeometry::Lines(kept)))
        }
        SourceGeometry::Polygons(rings) => {
            if rings.iter().all(|r| ring_fits(r)) {
                return (!rings.is_empty()).then_some(Cow::Borrowed(g));
            }
            let kept: Vec<Vec<Position>> = rings.iter().filter(|r| ring_fits(r)).cloned().collect();
            (!kept.is_empty()).then_some(Cow::Owned(SourceGeometry::Polygons(kept)))
        }
    }
}

/// `e` as the table can hold it, or why not. Texts lose their NUL
/// characters (neither `text` nor `jsonb` holds one), a page that is not
/// `https` is dropped (the app may open it), a road number the check would
/// refuse is dropped; a record without a usable identifier, with a figure
/// out of range, without a drawable geometry, or ending before it starts
/// is refused.
fn storable(e: &NewEvent) -> Result<Cow<'_, NewEvent>, &'static str> {
    let id_len = e.external_id.chars().count();
    if id_len == 0 || id_len > 200 || has_nul(&e.external_id) {
        return Err("identifier");
    }
    if e.external_version.is_empty() || e.detail.trim().is_empty() {
        return Err("version or term");
    }
    let l = &e.limits;
    if !(figure_fits(l.max_height_m, MAX_HEIGHT_M)
        && figure_fits(l.max_width_m, MAX_WIDTH_M)
        && figure_fits(l.max_length_m, MAX_LENGTH_M)
        && figure_fits(l.max_weight_t, MAX_WEIGHT_T))
    {
        return Err("figure out of range");
    }
    if e.valid_to.is_some_and(|to| to < e.valid_from) {
        return Err("ends before it starts");
    }
    let geometry = drawable(&e.geometry).ok_or("geometry")?;
    let texts = [
        Some(e.external_version.as_str()),
        Some(e.detail.as_str()),
        e.situation_id.as_deref(),
        e.road_name.as_deref(),
        e.description.as_deref(),
        e.detour.as_deref(),
        e.url.as_deref(),
        e.schedule.label.as_deref(),
        Some(e.raw.as_str()),
    ];
    let url_ok = e.url.as_deref().is_none_or(|u| u.starts_with("https://"));
    let number_ok = e.road_number.as_deref().is_none_or(road_number_fits);
    if matches!(geometry, Cow::Borrowed(_))
        && url_ok
        && number_ok
        && !texts.iter().flatten().any(|t| has_nul(t))
    {
        return Ok(Cow::Borrowed(e));
    }
    let strip = |t: &Option<String>| t.as_deref().map(no_nul);
    let mut schedule = e.schedule.clone();
    schedule.label = strip(&schedule.label);
    Ok(Cow::Owned(NewEvent {
        external_version: no_nul(&e.external_version),
        situation_id: strip(&e.situation_id),
        detail: no_nul(&e.detail),
        road_number: e.road_number.clone().filter(|n| road_number_fits(n)),
        road_name: strip(&e.road_name),
        schedule,
        geometry: geometry.into_owned(),
        description: strip(&e.description),
        detour: strip(&e.detour),
        url: strip(&e.url).filter(|u| u.starts_with("https://")),
        raw: no_nul(&e.raw),
        ..e.clone()
    }))
}

/// The storable events of `events`, one per identifier (the latest
/// version, the last given among equals), with what was refused or
/// dropped.
fn prepare<'a>(source: &str, events: &'a [NewEvent]) -> (Vec<Cow<'a, NewEvent>>, u64, u64) {
    let mut kept: Vec<Cow<'a, NewEvent>> = Vec::with_capacity(events.len());
    let mut at: HashMap<&'a str, usize> = HashMap::with_capacity(events.len());
    let (mut refused, mut duplicates) = (0, 0);
    for e in events {
        let ok = match storable(e) {
            Ok(ok) => ok,
            Err(why) => {
                tracing::warn!(source, external_id = %e.external_id.chars().take(80).collect::<String>(), why, "road event refused");
                refused += 1;
                continue;
            }
        };
        match at.get(e.external_id.as_str()) {
            Some(&i) => {
                duplicates += 1;
                if kept[i].external_version <= ok.external_version {
                    kept[i] = ok;
                }
            }
            None => {
                at.insert(e.external_id.as_str(), kept.len());
                kept.push(ok);
            }
        }
    }
    (kept, refused, duplicates)
}

/// Stores `events` of `source`, published at `published_at` and read at
/// `seen_at`: new ones are inserted, known ones updated (an older version
/// never replaces a newer one when `ordered`), every one marked seen. An
/// ended event the publication carries again is live again only when the
/// publication is newer than its end, or brings a newer version: the DIR's
/// hourly aggregate must not bring back what a later increment ended. A geometry that changed is placed on
/// the graph again. A record the table cannot hold is refused alone
/// ([`UpsertReport::refused`]), and an identifier given twice keeps its
/// latest version: PostgreSQL refuses to update one row twice in one
/// statement.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn upsert(
    w: &mut EventWriter,
    source: &str,
    events: &[NewEvent],
    published_at: DateTime<Utc>,
    seen_at: DateTime<Utc>,
    ordered: bool,
) -> Result<UpsertReport, DbError> {
    let (events, refused, duplicates) = prepare(source, events);
    let mut report = UpsertReport {
        refused,
        duplicates,
        ..UpsertReport::default()
    };
    for batch in events.chunks(BATCH) {
        let rows: Vec<serde_json::Value> = batch
            .iter()
            .map(|e| {
                serde_json::json!({
                    "id": Uuid::now_v7(),
                    "external_id": e.external_id,
                    "external_version": clip(Some(&e.external_version), 100),
                    "situation_id": clip(e.situation_id.as_deref(), 200),
                    "class": e.class.code(),
                    "detail": clip(Some(&e.detail), 100),
                    "carriageway": e.carriageway.code(),
                    "direction": e.direction.code(),
                    "road_number": e.road_number,
                    "road_name": clip(e.road_name.as_deref(), 200),
                    "max_height_m": e.limits.max_height_m,
                    "max_width_m": e.limits.max_width_m,
                    "max_length_m": e.limits.max_length_m,
                    "max_weight_t": e.limits.max_weight_t,
                    "applies_to": e.limits.applies_to.code(),
                    "valid_from": e.valid_from,
                    "valid_to": e.valid_to,
                    "schedule": e.schedule,
                    "schedule_assumed": e.schedule.assumed,
                    "geometry": wkt(&e.geometry),
                    "match_quality": e.match_quality.code(),
                    "confidence": e.confidence.code(),
                    "description": clip(e.description.as_deref(), 2_000),
                    "detour": clip(e.detour.as_deref(), 1_000),
                    "url": e.url.as_deref().filter(|u| u.len() <= 500),
                    "source_updated_at": e.source_updated_at,
                    "end_reason": e.ended.map(EndReason::code),
                    "content_hash": content_hash(e),
                    "raw": clip(Some(&e.raw), 65_536),
                })
            })
            .collect();
        let rows = serde_json::Value::Array(rows);
        let done = sqlx::query!(
            r#"
            INSERT INTO road_events AS r (id, source, external_id, external_version, situation_id,
                class, detail, carriageway, direction, road_number, road_name, max_height_m,
                max_width_m, max_length_m, max_weight_t, applies_to, valid_from, valid_to,
                schedule, schedule_assumed, geom_source, match_quality, confidence, description,
                detour, url, source_updated_at, first_seen_at, last_seen_at, ended_at,
                end_reason, content_hash, raw, revision)
            SELECT e.id, $1, e.external_id, e.external_version, e.situation_id, e.class,
                e.detail, e.carriageway, e.direction, e.road_number, e.road_name,
                e.max_height_m, e.max_width_m, e.max_length_m, e.max_weight_t, e.applies_to,
                e.valid_from, e.valid_to, e.schedule, e.schedule_assumed,
                ST_GeomFromText(e.geometry, 4326)::geography, e.match_quality, e.confidence,
                e.description, e.detour, e.url, e.source_updated_at, $3, $3,
                CASE WHEN e.end_reason IS NULL THEN NULL ELSE $3::timestamptz END,
                e.end_reason, e.content_hash, e.raw, 0
            FROM jsonb_to_recordset($2::jsonb) AS e(id uuid, external_id text,
                external_version text, situation_id text, class text, detail text,
                carriageway text, direction text, road_number text, road_name text,
                max_height_m float8, max_width_m float8, max_length_m float8,
                max_weight_t float8, applies_to text, valid_from timestamptz,
                valid_to timestamptz, schedule jsonb, schedule_assumed boolean, geometry text,
                match_quality text, confidence text, description text, detour text, url text,
                source_updated_at timestamptz, end_reason text, content_hash text, raw text)
            ON CONFLICT (source, external_id) DO UPDATE SET
                external_version = EXCLUDED.external_version,
                situation_id = EXCLUDED.situation_id,
                class = EXCLUDED.class,
                detail = EXCLUDED.detail,
                carriageway = EXCLUDED.carriageway,
                direction = EXCLUDED.direction,
                road_number = EXCLUDED.road_number,
                road_name = EXCLUDED.road_name,
                max_height_m = EXCLUDED.max_height_m,
                max_width_m = EXCLUDED.max_width_m,
                max_length_m = EXCLUDED.max_length_m,
                max_weight_t = EXCLUDED.max_weight_t,
                applies_to = EXCLUDED.applies_to,
                valid_from = EXCLUDED.valid_from,
                valid_to = EXCLUDED.valid_to,
                schedule = EXCLUDED.schedule,
                schedule_assumed = EXCLUDED.schedule_assumed,
                geom_source = EXCLUDED.geom_source,
                -- The same place keeps its match; a new one is matched
                -- again.
                geom_matched = CASE
                    WHEN ST_AsBinary(r.geom_source) = ST_AsBinary(EXCLUDED.geom_source)
                        AND r.direction = EXCLUDED.direction
                        AND r.carriageway = EXCLUDED.carriageway
                    THEN r.geom_matched END,
                match_quality = CASE
                    WHEN ST_AsBinary(r.geom_source) = ST_AsBinary(EXCLUDED.geom_source)
                        AND r.direction = EXCLUDED.direction
                        AND r.carriageway = EXCLUDED.carriageway
                        AND EXCLUDED.match_quality = 'pending'
                        AND r.match_quality IN ('matched', 'unmatched')
                    THEN r.match_quality ELSE EXCLUDED.match_quality END,
                matched_graph_id = CASE
                    WHEN ST_AsBinary(r.geom_source) = ST_AsBinary(EXCLUDED.geom_source)
                        AND r.direction = EXCLUDED.direction
                        AND r.carriageway = EXCLUDED.carriageway
                    THEN r.matched_graph_id END,
                confidence = EXCLUDED.confidence,
                description = EXCLUDED.description,
                detour = EXCLUDED.detour,
                url = EXCLUDED.url,
                source_updated_at = EXCLUDED.source_updated_at,
                last_seen_at = EXCLUDED.last_seen_at,
                -- An event the source carries again is live again, unless
                -- this version ends it or its end is newer than this
                -- publication.
                ended_at = CASE
                    WHEN EXCLUDED.end_reason IS NOT NULL
                        THEN coalesce(r.ended_at, EXCLUDED.ended_at)
                    WHEN r.ended_at IS NULL OR r.ended_at < $5
                        OR ($4 AND EXCLUDED.external_version > r.external_version)
                        THEN NULL
                    ELSE r.ended_at END,
                end_reason = CASE
                    WHEN EXCLUDED.end_reason IS NOT NULL
                        THEN coalesce(r.end_reason, EXCLUDED.end_reason)
                    WHEN r.ended_at IS NULL OR r.ended_at < $5
                        OR ($4 AND EXCLUDED.external_version > r.external_version)
                        THEN NULL
                    ELSE r.end_reason END,
                content_hash = EXCLUDED.content_hash,
                raw = EXCLUDED.raw
            WHERE NOT ($4 AND r.external_version > EXCLUDED.external_version)
            RETURNING old.id IS NULL AS "inserted!",
                (old.content_hash IS DISTINCT FROM new.content_hash
                    OR old.ended_at IS DISTINCT FROM new.ended_at) AS "changed!"
            "#,
            source,
            rows,
            seen_at,
            ordered,
            published_at,
        )
        .fetch_all(&mut *w.0)
        .await?;
        for d in &done {
            if d.inserted {
                report.inserted += 1;
            } else if d.changed {
                report.changed += 1;
            } else {
                report.unchanged += 1;
            }
        }
        report.older += (batch.len() - done.len()) as u64;
    }
    Ok(report)
}

/// The live events of `source`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_count(pool: &PgPool, source: &str) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM road_events WHERE source = $1 AND ended_at IS NULL"#,
        source
    )
    .fetch_one(pool)
    .await?)
}

/// What [`end_missing`] did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Missing {
    /// Ended this many.
    Ended(u64),
    /// The snapshot holds less than half of the live events: it looks
    /// truncated, and nothing was ended.
    Refused {
        /// Live events.
        live: i64,
        /// Events in the snapshot.
        seen: usize,
    },
}

/// Ends the live events of `source` missing from a complete snapshot
/// (`present`, external ids) published at `published_at`: those changed by
/// the source after that time (a DIR increment newer than the aggregate),
/// or read after it when the source gives no version time, are kept. Refuses when the snapshot holds less than half of the live
/// events, from 20 on: an empty or cut answer must not end every closure.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn end_missing(
    w: &mut EventWriter,
    source: &str,
    present: &[String],
    published_at: DateTime<Utc>,
    at: DateTime<Utc>,
) -> Result<Missing, DbError> {
    let live = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM road_events WHERE source = $1 AND ended_at IS NULL"#,
        source
    )
    .fetch_one(&mut *w.0)
    .await?;
    if live >= 20 && i64::try_from(present.len()).unwrap_or(i64::MAX) * 2 < live {
        return Ok(Missing::Refused {
            live,
            seen: present.len(),
        });
    }
    let done = sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = $4, end_reason = 'disappeared'
        WHERE source = $1 AND ended_at IS NULL AND NOT (external_id = ANY($2))
          AND coalesce(source_updated_at, last_seen_at) < $3
        "#,
        source,
        present,
        published_at,
        at,
    )
    .execute(&mut *w.0)
    .await?;
    Ok(Missing::Ended(done.rows_affected()))
}

/// Ends the events of `situation` that its new version, published at
/// `published_at`, no longer carries (`present`), and those it ends
/// (`ended`), kept as events or not. An event changed by the source after
/// that publication, or read after it without a version time, is kept: an
/// older version read again must not end what a newer one added.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn settle_situation(
    w: &mut EventWriter,
    source: &str,
    situation: &str,
    present: &[String],
    ended: &[String],
    published_at: DateTime<Utc>,
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    let dropped = sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = $4, end_reason = 'disappeared'
        WHERE source = $1 AND situation_id = $2 AND ended_at IS NULL
          AND NOT (external_id = ANY($3))
          AND coalesce(source_updated_at, last_seen_at) < $5
        "#,
        source,
        situation,
        present,
        at,
        published_at,
    )
    .execute(&mut *w.0)
    .await?;
    let closed = sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = $3, end_reason = 'source_end'
        WHERE source = $1 AND external_id = ANY($2) AND ended_at IS NULL
        "#,
        source,
        ended,
        at,
    )
    .execute(&mut *w.0)
    .await?;
    Ok(dropped.rows_affected() + closed.rows_affected())
}

/// Ends the events of `source` whose ids are in `ended` (their source's end
/// marker), whatever their situation.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn end_records(
    w: &mut EventWriter,
    source: &str,
    ended: &[String],
    at: DateTime<Utc>,
) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = $3, end_reason = 'source_end'
        WHERE source = $1 AND external_id = ANY($2) AND ended_at IS NULL
        "#,
        source,
        ended,
        at,
    )
    .execute(&mut *w.0)
    .await?
    .rows_affected())
}

/// A feed's state, as its reader resumes from it.
#[derive(Debug, Clone, PartialEq)]
pub struct Feed {
    /// The source.
    pub id: String,
    /// Where the next read resumes.
    pub state: serde_json::Value,
    /// The last read that succeeded.
    pub last_success_at: Option<DateTime<Utc>>,
    /// The last complete snapshot applied.
    pub last_full_at: Option<DateTime<Utc>>,
    /// The last attempt.
    pub last_attempt_at: Option<DateTime<Utc>>,
    /// When its data was last known current.
    pub data_at: Option<DateTime<Utc>>,
}

/// The state of feed `id`, if it is registered.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn feed(pool: &PgPool, id: &str) -> Result<Option<Feed>, DbError> {
    Ok(sqlx::query_as!(
        Feed,
        r#"SELECT id, state, last_success_at, last_full_at, last_attempt_at, data_at
           FROM road_event_sources WHERE id = $1"#,
        id
    )
    .fetch_optional(pool)
    .await?)
}

/// A read of a feed that succeeded.
#[derive(Debug, Clone, Copy)]
pub struct Read<'a> {
    /// Where the next read resumes.
    pub state: &'a serde_json::Value,
    /// Whether a complete snapshot was applied.
    pub full: bool,
    /// When the data read was current, when it brought anything: a
    /// snapshot's time, the last increment applied. `None` keeps the
    /// stored one, so a feed that answers without news grows stale.
    pub data_at: Option<DateTime<Utc>>,
}

/// Records a read of feed `id` at `at`: its new state and success, or its
/// error (the state, when given, is kept too: a back-off is part of it).
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn record_read(
    pool: &PgPool,
    id: &str,
    at: DateTime<Utc>,
    outcome: Result<Read<'_>, (&str, Option<&serde_json::Value>)>,
) -> Result<(), DbError> {
    match outcome {
        Ok(read) => {
            sqlx::query!(
                r#"
                UPDATE road_event_sources SET state = $2, last_attempt_at = $3,
                    last_success_at = $3, last_error = NULL,
                    last_full_at = CASE WHEN $4 THEN $3 ELSE last_full_at END,
                    data_at = greatest(data_at, $5)
                WHERE id = $1
                "#,
                id,
                read.state,
                at,
                read.full,
                read.data_at,
            )
            .execute(pool)
            .await?;
        }
        Err((error, state)) => {
            let error: String = error.chars().take(2_000).collect();
            sqlx::query!(
                r#"
                UPDATE road_event_sources SET last_attempt_at = $2, last_error = $3,
                    state = coalesce($4, state)
                WHERE id = $1
                "#,
                id,
                at,
                error,
                state,
            )
            .execute(pool)
            .await?;
        }
    }
    Ok(())
}

/// Stores where feed `id` resumes, with the events it describes: the next
/// read starts after what this transaction applied, even when the pass
/// fails later.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn save_state(
    w: &mut EventWriter,
    id: &str,
    state: &serde_json::Value,
    data_at: Option<DateTime<Utc>>,
) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        UPDATE road_event_sources SET state = $2, data_at = greatest(data_at, $3)
        WHERE id = $1
        "#,
        id,
        state,
        data_at,
    )
    .execute(&mut *w.0)
    .await?;
    Ok(())
}

/// An event the matcher places on the graph.
#[derive(Debug, Clone, PartialEq)]
pub struct MatchTask {
    /// Row id.
    pub id: Uuid,
    /// Source.
    pub source: String,
    /// Its lines, in the source's order.
    pub lines: Vec<Vec<Position>>,
    /// The direction it concerns.
    pub direction: EventDirection,
    /// Its road number.
    pub road_number: Option<String>,
    /// A digest of what the match depends on (geometry, direction,
    /// carriageway): [`set_match`] stores nothing when it changed meanwhile.
    pub fingerprint: String,
    /// How many times the engine refused its lines on the graph it was
    /// last tried on.
    pub refusals: i16,
    /// The graph it was last placed or tried on.
    pub graph_id: Option<String>,
}

/// How many days a road report is kept, as the privacy page says; its
/// idempotency key goes with it.
pub const REPORT_KEEP_DAYS: i64 = 14;

/// How many times the engine may refuse an event's lines on one graph
/// before the event waits for the next graph: a refusal can come from a
/// moment of the engine, rarely, so a line is asked again twice.
pub const MAX_REFUSALS: i16 = 3;

/// When an event refused `refusals` times on a graph is asked again: 30
/// minutes after the first refusal, 2 hours after the second, never on this
/// graph after the third.
#[must_use]
pub fn retry_after_refusal(refusals: i16, now: DateTime<Utc>) -> Option<DateTime<Utc>> {
    match refusals {
        ..=1 => Some(now + Duration::minutes(30)),
        2 => Some(now + Duration::hours(2)),
        _ => None,
    }
}

fn decode<T>(what: &'static str, v: &str) -> Result<T, DbError>
where
    T: std::str::FromStr,
    T::Err: std::error::Error + Send + Sync + 'static,
{
    v.parse().map_err(|e| DbError::decode(what, e))
}

fn geojson_value(text: &str) -> Option<serde_json::Value> {
    serde_json::from_str(text).ok()
}

fn positions(c: &serde_json::Value) -> Vec<Position> {
    c.as_array()
        .map(|a| {
            a.iter()
                .filter_map(|p| Position::new(p.get(1)?.as_f64()?, p.get(0)?.as_f64()?).ok())
                .collect()
        })
        .unwrap_or_default()
}

/// A source geometry from its GeoJSON.
fn source_geometry(text: &str) -> Option<SourceGeometry> {
    let v = geojson_value(text)?;
    let c = v.get("coordinates")?;
    match v.get("type")?.as_str()? {
        "Point" => Position::new(c.get(1)?.as_f64()?, c.get(0)?.as_f64()?)
            .ok()
            .map(SourceGeometry::Point),
        "LineString" => Some(SourceGeometry::Lines(vec![positions(c)])),
        "MultiLineString" => Some(SourceGeometry::Lines(
            c.as_array()?.iter().map(positions).collect(),
        )),
        "Polygon" => Some(SourceGeometry::Polygons(vec![positions(c.get(0)?)])),
        "MultiPolygon" => Some(SourceGeometry::Polygons(
            c.as_array()?
                .iter()
                .filter_map(|p| p.get(0).map(positions))
                .collect(),
        )),
        _ => None,
    }
}

/// The lines of a matched geometry's GeoJSON.
fn matched_lines(text: Option<&str>) -> Vec<Vec<Position>> {
    match text.and_then(source_geometry) {
        Some(SourceGeometry::Lines(lines)) => lines,
        _ => Vec::new(),
    }
}

/// The live events made of lines that wait for a match, were matched on
/// another graph than `graph_id`, or were refused by the engine and are
/// due to be asked again: the waiting ones first, closures first, then
/// those in force before those to come (the Dutch feed plans two weeks of
/// works). Only the feeds whose area the graph covers
/// (`road_event_sources.routed`). A line an importer stored unmatched
/// without asking the engine (a Dutch detour, shown with its own route) is
/// never asked: the matcher always records the graph it tried.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn match_tasks(
    pool: &PgPool,
    graph_id: &str,
    limit: i64,
) -> Result<Vec<MatchTask>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, source, direction, road_number, match_attempts, matched_graph_id,
            ST_AsGeoJSON(geom_source::geometry, 7) AS "shape!",
            md5(ST_AsBinary(geom_source) || convert_to(direction || ' ' || carriageway, 'UTF8'))
                AS "fingerprint!"
        FROM road_events
        WHERE ended_at IS NULL
          AND GeometryType(geom_source::geometry) IN ('LINESTRING', 'MULTILINESTRING')
          AND source IN (SELECT id FROM road_event_sources WHERE routed)
          AND (match_quality = 'pending'
               OR (match_quality IN ('matched', 'unmatched')
                   AND matched_graph_id IS NOT NULL AND matched_graph_id <> $1)
               OR (match_quality = 'unmatched' AND match_retry_at <= now()))
        ORDER BY match_quality = 'pending' DESC, class = 'closure' DESC,
            coalesce(valid_from, first_seen_at) > now(), first_seen_at
        LIMIT $2
        "#,
        graph_id,
        limit
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            let lines = match source_geometry(&r.shape) {
                Some(SourceGeometry::Lines(l)) => l,
                _ => Vec::new(),
            };
            Ok(MatchTask {
                id: r.id,
                source: r.source,
                lines,
                direction: decode("road event direction", &r.direction)?,
                road_number: r.road_number,
                fingerprint: r.fingerprint,
                refusals: r.match_attempts,
                graph_id: r.matched_graph_id,
            })
        })
        .collect()
}

/// Records the match of `task` on graph `graph_id`: its lines in driving
/// order, or none when it failed. Whether it was stored: an event that
/// ended, moved, changed direction or carriageway, or was placed by a
/// route-time rule since the task was read keeps its state, so the lines
/// of an old geometry are never stored as matched.
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn set_match(
    w: &mut EventWriter,
    task: &MatchTask,
    lines: Option<&[Vec<Position>]>,
    graph_id: &str,
) -> Result<bool, DbError> {
    let lines = lines.filter(|l| !l.is_empty() && l.iter().all(|x| x.len() >= 2));
    let shape = lines.map(multiline_wkt);
    let done = sqlx::query!(
        r#"
        UPDATE road_events SET
            geom_matched = CASE WHEN $2::text IS NULL THEN NULL
                ELSE ST_GeomFromText($2::text, 4326)::geography END,
            match_quality = CASE WHEN $2::text IS NULL THEN 'unmatched' ELSE 'matched' END,
            matched_graph_id = $3,
            match_error = CASE WHEN $2::text IS NULL
                THEN 'no route on the graph holds together as this line' END,
            match_attempts = 0,
            match_retry_at = NULL
        WHERE id = $1 AND ended_at IS NULL
          AND match_quality IN ('pending', 'matched', 'unmatched')
          AND md5(ST_AsBinary(geom_source) || convert_to(direction || ' ' || carriageway, 'UTF8'))
              = $4
        "#,
        task.id,
        shape,
        graph_id,
        task.fingerprint,
    )
    .execute(&mut *w.0)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// Records that the engine refused to route `task` on graph `graph_id`,
/// for `reason`: the event is left unplaced (it warns at its source
/// position), and asked again as [`retry_after_refusal`] says. Whether it
/// was stored, as for [`set_match`].
///
/// # Errors
///
/// [`DbError`] when the update fails.
pub async fn set_refused(
    w: &mut EventWriter,
    task: &MatchTask,
    reason: &str,
    graph_id: &str,
    now: DateTime<Utc>,
) -> Result<bool, DbError> {
    let refusals = if task.graph_id.as_deref() == Some(graph_id) {
        task.refusals.saturating_add(1).min(100)
    } else {
        1
    };
    let reason: String = reason.chars().take(300).collect();
    let done = sqlx::query!(
        r#"
        UPDATE road_events SET
            geom_matched = NULL,
            match_quality = 'unmatched',
            matched_graph_id = $2,
            match_error = $3,
            match_attempts = $4,
            match_retry_at = $5
        WHERE id = $1 AND ended_at IS NULL
          AND match_quality IN ('pending', 'matched', 'unmatched')
          AND md5(ST_AsBinary(geom_source) || convert_to(direction || ' ' || carriageway, 'UTF8'))
              = $6
        "#,
        task.id,
        graph_id,
        reason,
        refusals,
        retry_after_refusal(refusals, now),
        task.fingerprint,
    )
    .execute(&mut *w.0)
    .await?;
    Ok(done.rows_affected() > 0)
}

/// What a lifecycle pass did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Lifecycle {
    /// Events past their end.
    pub past_end: u64,
    /// Events without an end not seen for the expiry.
    pub expired: u64,
    /// Events whose start came within the feed's window: phones receive
    /// them from now on.
    pub entered_window: u64,
    /// Ended events purged after their audit time.
    pub purged: u64,
    /// Reports purged after their time.
    pub reports_purged: u64,
}

/// Ends the events past their end (a margin of an hour), expires those
/// without an end not seen for `expire_after`, lets into the phones' feed
/// the events whose start came within [`FEED_WINDOW_HOURS`] of `now` (a
/// new revision each, so a cursor already past their last change still
/// delivers them), purges the events ended more than `keep_ended` ago and
/// the reports older than `keep_reports`.
/// The community's events are weighed again by the API
/// ([`reweigh_community`]), never here: the importers' role does not read
/// who reported what.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn lifecycle(
    pool: &PgPool,
    now: DateTime<Utc>,
    expire_after: Duration,
    keep_ended: Duration,
    keep_reports: Duration,
) -> Result<Lifecycle, DbError> {
    let mut w = begin_writer(pool).await?;
    let past_end = sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = $1, end_reason = 'past_end'
        WHERE ended_at IS NULL AND valid_to < $1::timestamptz - interval '1 hour'
        "#,
        now
    )
    .execute(&mut *w.0)
    .await?
    .rows_affected();
    let expired = sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = $1, end_reason = 'expired'
        WHERE ended_at IS NULL AND valid_to IS NULL AND last_seen_at < $2
        "#,
        now,
        now - expire_after,
    )
    .execute(&mut *w.0)
    .await?
    .rows_affected();
    let entered_window = sqlx::query!(
        r#"
        UPDATE road_events SET in_window = true
        WHERE ended_at IS NULL AND NOT in_window
          AND valid_from <= $1::timestamptz + road_events_feed_window()
        "#,
        now
    )
    .execute(&mut *w.0)
    .await?
    .rows_affected();
    let purged = sqlx::query_scalar!(
        r#"DELETE FROM road_events WHERE ended_at < $1 RETURNING revision"#,
        now - keep_ended
    )
    .fetch_all(&mut *w.0)
    .await?;
    if let Some(top) = purged.iter().max() {
        sqlx::query!(
            "UPDATE road_event_purges SET purged_through = greatest(purged_through, $1)",
            top
        )
        .execute(&mut *w.0)
        .await?;
    }
    let reports_purged = sqlx::query!(
        "DELETE FROM road_event_reports WHERE created_at < $1",
        now - keep_reports
    )
    .execute(&mut *w.0)
    .await?
    .rows_affected();
    w.commit().await?;
    Ok(Lifecycle {
        past_end,
        expired,
        entered_window,
        purged: purged.len() as u64,
        reports_purged,
    })
}

/// A live event, as the route check and the app read it.
#[derive(Debug, Clone, PartialEq)]
pub struct EventRow {
    /// Row id.
    pub id: Uuid,
    /// Source id.
    pub source: String,
    /// The source's identifier.
    pub external_id: String,
    /// What it does.
    pub class: EventClass,
    /// The source's term.
    pub detail: String,
    /// Which part of the road.
    pub carriageway: Carriageway,
    /// The direction it concerns.
    pub direction: EventDirection,
    /// The heading of a report.
    pub heading_deg: Option<u16>,
    /// Road number.
    pub road_number: Option<String>,
    /// Road name.
    pub road_name: Option<String>,
    /// Vehicle limits.
    pub limits: VehicleLimits,
    /// Validity start.
    pub valid_from: DateTime<Utc>,
    /// Validity end.
    pub valid_to: Option<DateTime<Utc>>,
    /// When within the validity.
    pub schedule: Schedule,
    /// The source's geometry.
    pub geometry: SourceGeometry,
    /// The matched lines, in driving order.
    pub matched: Vec<Vec<Position>>,
    /// How it is placed.
    pub match_quality: MatchQuality,
    /// How far to believe it.
    pub confidence: Confidence,
    /// Description.
    pub description: Option<String>,
    /// Detour text.
    pub detour: Option<String>,
    /// The source's page.
    pub url: Option<String>,
    /// The source's time of its version.
    pub source_updated_at: Option<DateTime<Utc>>,
    /// First read.
    pub first_seen_at: DateTime<Utc>,
    /// Last read.
    pub last_seen_at: DateTime<Utc>,
    /// Its position in the change feed.
    pub revision: i64,
    /// When it ended, if it did.
    pub ended_at: Option<DateTime<Utc>>,
    /// Whether phones receive it: in force, or starting within the feed's
    /// window ([`FEED_WINDOW_HOURS`]).
    pub in_window: bool,
}

/// The raw columns of an event row, as every read selects them.
struct RawRow {
    id: Uuid,
    source: String,
    external_id: String,
    class: String,
    detail: String,
    carriageway: String,
    direction: String,
    heading_deg: Option<i16>,
    road_number: Option<String>,
    road_name: Option<String>,
    max_height_m: Option<f64>,
    max_width_m: Option<f64>,
    max_length_m: Option<f64>,
    max_weight_t: Option<f64>,
    applies_to: String,
    valid_from: DateTime<Utc>,
    valid_to: Option<DateTime<Utc>>,
    schedule: serde_json::Value,
    shape: String,
    matched: Option<String>,
    match_quality: String,
    confidence: String,
    description: Option<String>,
    detour: Option<String>,
    url: Option<String>,
    source_updated_at: Option<DateTime<Utc>>,
    first_seen_at: DateTime<Utc>,
    last_seen_at: DateTime<Utc>,
    revision: i64,
    ended_at: Option<DateTime<Utc>>,
    in_window: bool,
}

impl RawRow {
    fn decode(self) -> Result<EventRow, DbError> {
        let geometry = source_geometry(&self.shape).ok_or_else(|| {
            DbError::decode(
                "road event geometry",
                std::io::Error::new(std::io::ErrorKind::InvalidData, self.id.to_string()),
            )
        })?;
        Ok(EventRow {
            id: self.id,
            source: self.source,
            external_id: self.external_id,
            class: decode("road event class", &self.class)?,
            detail: self.detail,
            carriageway: decode("road event carriageway", &self.carriageway)?,
            direction: decode("road event direction", &self.direction)?,
            heading_deg: self.heading_deg.and_then(|h| u16::try_from(h).ok()),
            road_number: self.road_number,
            road_name: self.road_name,
            limits: VehicleLimits {
                max_height_m: self.max_height_m,
                max_width_m: self.max_width_m,
                max_length_m: self.max_length_m,
                max_weight_t: self.max_weight_t,
                applies_to: decode::<AppliesTo>("road event applies_to", &self.applies_to)?,
            },
            valid_from: self.valid_from,
            valid_to: self.valid_to,
            schedule: serde_json::from_value(self.schedule)
                .map_err(|e| DbError::decode("road event schedule", e))?,
            geometry,
            matched: matched_lines(self.matched.as_deref()),
            match_quality: decode("road event match", &self.match_quality)?,
            confidence: decode("road event confidence", &self.confidence)?,
            description: self.description,
            detour: self.detour,
            url: self.url,
            source_updated_at: self.source_updated_at,
            first_seen_at: self.first_seen_at,
            last_seen_at: self.last_seen_at,
            revision: self.revision,
            ended_at: self.ended_at,
            in_window: self.in_window,
        })
    }
}

/// The live events near a route: those whose matched lines lie within
/// `within_m` of it, and those whose own geometry lies within `wide_m`
/// (slip road events are placed on the main road up to a kilometre from
/// the slip roads; unmatched events warn from a little farther).
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn events_near(
    pool: &PgPool,
    route: &[Position],
    within_m: f64,
    wide_m: f64,
) -> Result<Vec<EventRow>, DbError> {
    if route.len() < 2 {
        return Ok(Vec::new());
    }
    if route.len() > MAX_ROUTE_POINTS {
        return Err(DbError::TooLarge {
            what: "route shape points",
            limit: MAX_ROUTE_POINTS,
        });
    }
    let lons: Vec<f64> = route.iter().map(|p| p.lon()).collect();
    let lats: Vec<f64> = route.iter().map(|p| p.lat()).collect();
    let rows = sqlx::query_as!(
        RawRow,
        r#"
        WITH line AS (
            SELECT ST_SetSRID(ST_MakeLine(ARRAY(
                SELECT ST_MakePoint(lon, lat)
                FROM UNNEST($1::float8[], $2::float8[]) WITH ORDINALITY AS u(lon, lat, n)
                ORDER BY n
            )), 4326) AS geom
        ), pieces AS (
            SELECT ST_Subdivide(geom, 32)::geography AS piece FROM line
        )
        SELECT DISTINCT ON (e.id)
            e.id, e.source, e.external_id, e.class, e.detail, e.carriageway, e.direction,
            e.heading_deg, e.road_number, e.road_name, e.max_height_m, e.max_width_m,
            e.max_length_m, e.max_weight_t, e.applies_to, e.valid_from, e.valid_to,
            e.schedule, ST_AsGeoJSON(e.geom_source::geometry, 7) AS "shape!",
            ST_AsGeoJSON(e.geom_matched::geometry, 7) AS matched, e.match_quality,
            e.confidence, e.description, e.detour, e.url, e.source_updated_at,
            e.first_seen_at, e.last_seen_at, e.revision, e.ended_at, e.in_window
        FROM pieces p
        JOIN road_events e ON e.ended_at IS NULL AND (
            ST_DWithin(e.geom_matched, p.piece, $3) OR ST_DWithin(e.geom_source, p.piece, $4))
        ORDER BY e.id
        "#,
        &lons,
        &lats,
        within_m,
        wide_m,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter().map(RawRow::decode).collect()
}

/// A source of road events and how fresh it is.
#[derive(Debug, Clone, PartialEq)]
pub struct SourceStatus {
    /// Its id (`dir`, `dialog`, `community`...).
    pub id: String,
    /// Its name.
    pub name: String,
    /// Its licence.
    pub licence: String,
    /// The text to credit it with.
    pub attribution: String,
    /// Its page.
    pub url: String,
    /// How long after its data was last known current its events stop
    /// blocking, seconds.
    pub stale_after_s: i32,
    /// The last read that succeeded.
    pub last_success_at: Option<DateTime<Utc>>,
    /// The last complete snapshot.
    pub last_full_at: Option<DateTime<Utc>>,
    /// When its data was last known current: its events block while this
    /// is within `stale_after_s`.
    pub data_at: Option<DateTime<Utc>>,
}

/// Every source of road events, in a stable order.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn sources(pool: &PgPool) -> Result<Vec<SourceStatus>, DbError> {
    Ok(sqlx::query_as!(
        SourceStatus,
        r#"
        SELECT id, name, licence, attribution, url, stale_after_s, last_success_at,
            last_full_at, data_at
        FROM road_event_sources
        ORDER BY CASE id WHEN 'dir' THEN 0 WHEN 'dialog' THEN 1 WHEN 'community' THEN 3 ELSE 2 END,
            id
        "#
    )
    .fetch_all(pool)
    .await?)
}

/// The live events by source, class and placement: (source, class,
/// placement, count).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn live_counts(pool: &PgPool) -> Result<Vec<(String, String, String, i64)>, DbError> {
    Ok(sqlx::query!(
        r#"
        SELECT source, class, match_quality, count(*) AS "n!"
        FROM road_events WHERE ended_at IS NULL
        GROUP BY 1, 2, 3 ORDER BY 1, 2, 3
        "#
    )
    .fetch_all(pool)
    .await?
    .into_iter()
    .map(|r| (r.source, r.class, r.match_quality, r.n))
    .collect())
}

/// The head of the change feed: the copy of the database it belongs to,
/// its last revision, and the newest revision purged.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedHead {
    /// The database's identity: a cursor of another copy is refused.
    pub identity: String,
    /// The highest revision committed.
    pub revision: i64,
    /// The newest revision of a purged event: a cursor older than it
    /// missed an end.
    pub purged_through: i64,
}

/// The head of the change feed.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn feed_head(pool: &PgPool) -> Result<FeedHead, DbError> {
    let r = sqlx::query!(
        r#"
        SELECT e.epoch, d.oid::int8 AS "database!",
            (SELECT coalesce(max(revision), 0) FROM road_events) AS "revision!",
            (SELECT purged_through FROM road_event_purges) AS "purged!"
        FROM sync_epoch e, pg_database d
        WHERE d.datname = current_database()
        "#
    )
    .fetch_one(pool)
    .await?;
    Ok(FeedHead {
        identity: format!("{}{:08x}", r.epoch.simple(), r.database),
        revision: r.revision,
        purged_through: r.purged,
    })
}

/// The live events of `classes` past revision `after` up to `until`,
/// oldest revision first, at most `limit`: the pages of the whole set a
/// client starts from. With `blocking_only`, only those that can block a
/// route: a closure, or a vehicle limit for every vehicle, placed on the
/// graph, official or confirmed (the API's `can_block`, kept in step).
/// Lines are simplified to about 4 m: a phone checks its route against them
/// within 12 m, and their points are most of the feed's weight. Only the
/// feeds the routing graph covers (`road_event_sources.routed`): a phone
/// in guidance has nothing to do with 17 000 Dutch events, and the changes
/// of [`changed_since`] leave them out too. Only the events in the window
/// (`in_window`, [`FEED_WINDOW_HOURS`]): an event starting later reaches
/// the phones through [`changed_since`] when it enters it.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn live_events(
    pool: &PgPool,
    classes: &[EventClass],
    blocking_only: bool,
    after: i64,
    until: i64,
    limit: i64,
) -> Result<Vec<EventRow>, DbError> {
    let classes: Vec<String> = classes.iter().map(|c| c.code().to_owned()).collect();
    let rows = sqlx::query_as!(
        RawRow,
        r#"
        SELECT e.id, e.source, e.external_id, e.class, e.detail, e.carriageway, e.direction,
            e.heading_deg, e.road_number, e.road_name, e.max_height_m, e.max_width_m,
            e.max_length_m, e.max_weight_t, e.applies_to, e.valid_from, e.valid_to,
            e.schedule,
            ST_AsGeoJSON(ST_SimplifyPreserveTopology(e.geom_source::geometry, 0.00004), 6) AS "shape!",
            ST_AsGeoJSON(ST_SimplifyPreserveTopology(e.geom_matched::geometry, 0.00004), 6) AS matched,
            e.match_quality, e.confidence, e.description, e.detour, e.url,
            e.source_updated_at, e.first_seen_at, e.last_seen_at, e.revision, e.ended_at,
            e.in_window
        FROM road_events e
        WHERE e.ended_at IS NULL AND e.in_window AND e.class = ANY($1)
          AND e.revision > $3 AND e.revision <= $4
          AND e.source IN (SELECT id FROM road_event_sources WHERE routed)
          AND (NOT $2 OR (
              e.match_quality IN ('matched', 'ramp', 'point')
              AND e.confidence <> 'reported'
              AND (e.class = 'closure' OR (e.class = 'vehicle_limit' AND e.applies_to = 'all'))))
        ORDER BY e.revision
        LIMIT $5
        "#,
        &classes,
        blocking_only,
        after,
        until,
        limit,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter().map(RawRow::decode).collect()
}

/// The events changed since revision `since`, live or ended, up to
/// `until` (the head read with them), oldest first, at most `limit`, lines
/// simplified as in [`live_events`]. A live event outside the window
/// (`in_window` false) is here only when it left it (its start moved
/// later): the phones that hold it drop it. One that enters the window
/// takes a new revision, so it is here even when nothing else changed.
/// `None` when events ended after `since` were purged meanwhile: their
/// ends are lost, and the client takes the whole set again. The horizon
/// and the rows are read in one snapshot, so a purge between them cannot
/// hide an end.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn changed_since(
    pool: &PgPool,
    since: i64,
    until: i64,
    limit: i64,
) -> Result<Option<Vec<EventRow>>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *tx)
        .await?;
    let purged = sqlx::query_scalar!("SELECT purged_through FROM road_event_purges")
        .fetch_one(&mut *tx)
        .await?;
    if since < purged {
        return Ok(None);
    }
    let rows = sqlx::query_as!(
        RawRow,
        r#"
        SELECT e.id, e.source, e.external_id, e.class, e.detail, e.carriageway, e.direction,
            e.heading_deg, e.road_number, e.road_name, e.max_height_m, e.max_width_m,
            e.max_length_m, e.max_weight_t, e.applies_to, e.valid_from, e.valid_to,
            e.schedule,
            ST_AsGeoJSON(ST_SimplifyPreserveTopology(e.geom_source::geometry, 0.00004), 6) AS "shape!",
            ST_AsGeoJSON(ST_SimplifyPreserveTopology(e.geom_matched::geometry, 0.00004), 6) AS matched,
            e.match_quality, e.confidence, e.description, e.detour, e.url,
            e.source_updated_at, e.first_seen_at, e.last_seen_at, e.revision, e.ended_at,
            e.in_window
        FROM road_events e
        WHERE e.revision > $1 AND e.revision <= $2
          AND e.source IN (SELECT id FROM road_event_sources WHERE routed)
        ORDER BY e.revision
        LIMIT $3
        "#,
        since,
        until,
        limit
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    rows.into_iter()
        .map(RawRow::decode)
        .collect::<Result<_, _>>()
        .map(Some)
}

/// A user's report as the API hands it over.
#[derive(Debug, Clone, PartialEq)]
pub struct NewReport {
    /// The reporting account.
    pub account: Uuid,
    /// What is reported (not `Cleared`: see [`clear`]).
    pub kind: ReportKind,
    /// Where.
    pub at: Position,
    /// The reporter's course.
    pub heading_deg: Option<u16>,
    /// The measured height or width.
    pub value_m: Option<f64>,
}

/// What a report did.
#[derive(Debug, Clone, PartialEq)]
pub struct Reported {
    /// The report.
    pub report_id: Uuid,
    /// The community event it supports.
    pub event_id: Uuid,
    /// The event's confidence now.
    pub confidence: Confidence,
    /// Whether this report made it blocking for everyone (a second
    /// account): a moderator is told.
    pub confirmed_now: bool,
    /// When the event ends without a new report.
    pub expires_at: DateTime<Utc>,
}

fn community_event_json(e: &community::CommunityEvent, kind: ReportKind) -> serde_json::Value {
    serde_json::json!({
        "kind": kind.code(),
        "confidence": e.confidence.code(),
        "limits": e.limits,
        "first_report_at": e.first_report_at,
        "last_report_at": e.last_report_at,
        "disputed": e.disputed,
    })
}

/// Stores a report: it joins the live community event of the same kind at
/// the same spot (within 100 m, heading the same way, of the same measured
/// figure within [`community::AGREE_M`]), or starts one, and the event is
/// weighed again from its reports ([`community::summarize`]). A figure
/// further off starts its own event, a warning until confirmed, so one
/// account cannot lower a confirmed limit. A report that confirms the
/// event queues it for a moderator.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn report(pool: &PgPool, r: &NewReport, now: DateTime<Utc>) -> Result<Reported, DbError> {
    // The writers' lock serialises every writer of road events (the
    // migration's trigger takes it too): no row lock is needed to read the
    // community's events and update one.
    let mut w = begin_writer_now(pool).await?;
    let done = report_in(&mut w, r, now).await?;
    w.commit().await?;
    Ok(done)
}

/// [`report`] guarded by an idempotency key: a request sent again with the
/// same key answers with the report the first one stored. The key's
/// account is the reporter.
///
/// # Errors
///
/// [`DbError`] when a statement fails or the writers' lock is not free in
/// time ([`is_busy`]).
pub async fn report_once(
    pool: &PgPool,
    key: &crate::idempotency::Key<'_>,
    r: &NewReport,
    now: DateTime<Utc>,
) -> Result<crate::idempotency::Once<Reported>, DbError> {
    use crate::idempotency::{self, Once, Seen};
    let mut w = begin_writer_now(pool).await?;
    // The writers' lock orders two requests with the same key: the second
    // sees the first's key here.
    match idempotency::seen(&mut w.0, key).await? {
        Seen::New => {}
        Seen::Replay(id) => return Ok(Once::Replay(id)),
        Seen::Reused => return Ok(Once::Reused),
    }
    let done = report_in(&mut w, r, now).await?;
    if idempotency::store(&mut w.0, key, done.report_id).await? {
        w.commit().await?;
        Ok(Once::Done(done))
    } else {
        w.0.rollback().await?;
        idempotency::after_lost_race(pool, key).await
    }
}

/// What report `id` of `account` stands for now, for a request sent again:
/// its event, the event's confidence and when it ends (or ended).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn report_of(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
) -> Result<Option<Reported>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT r.id, r.event_id AS "event_id!", e.confidence,
            coalesce(e.ended_at, e.valid_to, e.last_seen_at) AS "until!"
        FROM road_event_reports r JOIN road_events e ON e.id = r.event_id
        WHERE r.id = $1 AND r.account_id = $2
        "#,
        id,
        account,
    )
    .fetch_optional(pool)
    .await?;
    row.map(|r| {
        Ok(Reported {
            report_id: r.id,
            event_id: r.event_id,
            confidence: decode("road event confidence", &r.confidence)?,
            confirmed_now: false,
            expires_at: r.until,
        })
    })
    .transpose()
}

async fn report_in(
    w: &mut EventWriter,
    r: &NewReport,
    now: DateTime<Utc>,
) -> Result<Reported, DbError> {
    let candidates = sqlx::query!(
        r#"
        SELECT id, heading_deg, confidence, max_height_m, max_width_m,
            ST_Y(geom_source::geometry) AS "lat!", ST_X(geom_source::geometry) AS "lon!"
        FROM road_events
        WHERE source = 'community' AND ended_at IS NULL AND detail = $1
          AND ST_DWithin(geom_source, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)
        ORDER BY geom_source <-> ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography
        "#,
        r.kind.code(),
        r.at.lon(),
        r.at.lat(),
        community::SAME_SPOT_M,
    )
    .fetch_all(&mut *w.0)
    .await?;
    let existing = candidates.into_iter().find(|c| {
        let figure = match r.kind {
            ReportKind::LowClearance => c.max_height_m,
            ReportKind::NarrowPassage => c.max_width_m,
            _ => None,
        };
        community::same_figure(figure, r.value_m)
            && Position::new(c.lat, c.lon).is_ok_and(|p| {
                community::same_spot(
                    p,
                    c.heading_deg.and_then(|h| u16::try_from(h).ok()),
                    r.at,
                    r.heading_deg,
                )
            })
    });
    let event_id = existing.as_ref().map_or_else(Uuid::now_v7, |e| e.id);
    let previous = existing
        .as_ref()
        .and_then(|e| e.confidence.parse::<Confidence>().ok());
    let report_id = Uuid::now_v7();
    if existing.is_none() {
        // The event row first: the report points at it. It keeps the
        // published position and no heading: the importers' role reads it
        // with the reports' accounts and times (`community::coarse`).
        let placeholder = serde_json::json!({});
        let at = community::coarse(r.at);
        sqlx::query!(
            r#"
            INSERT INTO road_events (id, source, external_id, external_version, class, detail,
                carriageway, direction, heading_deg, valid_from, valid_to, geom_source,
                match_quality, confidence, first_seen_at, last_seen_at, content_hash, raw,
                revision)
            VALUES ($1, 'community', $7, '0000000001', 'closure', $2, 'unknown',
                'unknown', NULL, $3, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography,
                'point', 'reported', $3, $3, 'new', $6, 0)
            "#,
            event_id,
            r.kind.code(),
            now,
            at.lon(),
            at.lat(),
            placeholder.to_string(),
            event_id.to_string(),
        )
        .execute(&mut *w.0)
        .await?;
    }
    sqlx::query!(
        r#"
        INSERT INTO road_event_reports (id, account_id, kind, geom, heading_deg, value_m,
            event_id, created_at)
        VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, $6, $7, $8, $9)
        "#,
        report_id,
        r.account,
        r.kind.code(),
        r.at.lon(),
        r.at.lat(),
        r.heading_deg.map(|h| i16::try_from(h).unwrap_or(0)),
        r.value_m,
        event_id,
        now,
    )
    .execute(&mut *w.0)
    .await?;
    let summary = summarize_event(w, event_id, r.kind, "moderated").await?;
    let Some(summary) = summary else {
        // Cannot happen: the report just stored supports the event.
        return Err(DbError::decode(
            "community event",
            std::io::Error::new(std::io::ErrorKind::InvalidData, event_id.to_string()),
        ));
    };
    let confirmed_now =
        summary.confidence == Confidence::Confirmed && previous != Some(Confidence::Confirmed);
    if confirmed_now {
        sqlx::query!(
            r#"
            INSERT INTO moderation_queue (id, kind, target_type, target_id, account_id, reason)
            VALUES ($1, 'road_report', 'road_event', $2, $3, 'confirmed by two trusted accounts: blocks routes')
            ON CONFLICT DO NOTHING
            "#,
            Uuid::now_v7(),
            event_id,
            r.account,
        )
        .execute(&mut *w.0)
        .await?;
    }
    Ok(Reported {
        report_id,
        event_id,
        confidence: summary.confidence,
        confirmed_now,
        expires_at: summary.expires_at,
    })
}

/// Weighs community event `event_id` again from its active reports and
/// stores the result; ends it, for `end_reason`, when none is left or it
/// is over ([`community::summarize`]). The reports of banned accounts are
/// left out; an account counts as trusted from level 1. The event's new
/// state.
async fn summarize_event(
    w: &mut EventWriter,
    event_id: Uuid,
    kind: ReportKind,
    end_reason: &str,
) -> Result<Option<community::CommunityEvent>, DbError> {
    // Through the view without accounts: the rule needs one key per account
    // and event, never an account id, so nothing that weighs the reports
    // handles who made them.
    let reports = sqlx::query!(
        r#"
        SELECT reporter AS "reporter!", kind AS "kind!", value_m, created_at AS "created_at!",
            trusted AS "trusted!"
        FROM road_event_report_facts
        WHERE event_id = $1 AND status = 'active' AND (kind = $2 OR kind = 'cleared')
          AND NOT banned
        ORDER BY created_at
        "#,
        event_id,
        kind.code(),
    )
    .fetch_all(&mut *w.0)
    .await?;
    let facts: Vec<ReportFacts<String>> = reports
        .into_iter()
        .filter_map(|r| {
            Some(ReportFacts {
                account: r.reporter,
                kind: r.kind.parse().ok()?,
                value_m: r.value_m,
                created_at: r.created_at,
                trusted: r.trusted,
            })
        })
        .collect();
    let Some(summary) = community::summarize(&facts) else {
        sqlx::query!(
            r#"
            UPDATE road_events SET ended_at = now(), end_reason = $2
            WHERE id = $1 AND ended_at IS NULL
            "#,
            event_id,
            end_reason,
        )
        .execute(&mut *w.0)
        .await?;
        return Ok(None);
    };
    let raw = community_event_json(&summary, kind);
    let hash = digest(&raw.to_string());
    // An ended event stays as it ended: rewriting it would move its
    // revision and send it again to every phone.
    sqlx::query!(
        r#"
        UPDATE road_events SET class = $2, confidence = $3, max_height_m = $4,
            max_width_m = $5, valid_from = $6, valid_to = $7, last_seen_at = $8,
            content_hash = $9, raw = $10
        WHERE id = $1 AND ended_at IS NULL
        "#,
        event_id,
        summary.class.code(),
        summary.confidence.code(),
        summary.limits.max_height_m,
        summary.limits.max_width_m,
        summary.first_report_at,
        summary.expires_at,
        summary.last_report_at,
        hash,
        raw.to_string(),
    )
    .execute(&mut *w.0)
    .await?;
    Ok(Some(summary))
}

/// What a "it is over" did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Cleared {
    /// The community event ended: its only reporter took it back, or two
    /// trusted accounts said it is over.
    Ended,
    /// Recorded: a trusted account's makes a confirmed event a warning
    /// again; a level-0 account's waits for a moderator when the event
    /// blocks.
    Noted(Confidence),
    /// No live event of that id.
    NotFound,
    /// An official event: it ends with its source.
    Official,
}

/// A user says community event `event_id` is over. The report is kept with
/// the event, which is weighed again ([`community::summarize`]): it ends
/// when its only reporter says so or two trusted accounts have; a trusted
/// account alone makes it a warning. A "it is over" on an event that
/// blocked goes to a moderator.
///
/// # Errors
///
/// [`DbError`] when a statement fails, [`DbError::Busy`] when the writers'
/// lock is not free within a few seconds.
pub async fn clear(
    pool: &PgPool,
    account: Uuid,
    event_id: Uuid,
    now: DateTime<Utc>,
) -> Result<Cleared, DbError> {
    let mut w = begin_writer_now(pool).await?;
    // Read before locking: the API's role may lock community rows only
    // (row security), and an official event must answer `Official`.
    let source = sqlx::query_scalar!(
        "SELECT source FROM road_events WHERE id = $1 AND ended_at IS NULL",
        event_id
    )
    .fetch_optional(&mut *w.0)
    .await?;
    match source.as_deref() {
        None => return Ok(Cleared::NotFound),
        Some(COMMUNITY) => {}
        Some(_) => return Ok(Cleared::Official),
    }
    let row = sqlx::query!(
        r#"
        SELECT detail, confidence,
            ST_Y(geom_source::geometry) AS "lat!", ST_X(geom_source::geometry) AS "lon!"
        FROM road_events WHERE id = $1 AND source = 'community' AND ended_at IS NULL
        FOR UPDATE
        "#,
        event_id
    )
    .fetch_optional(&mut *w.0)
    .await?;
    let Some(row) = row else {
        return Ok(Cleared::NotFound);
    };
    let Ok(kind) = row.detail.parse::<ReportKind>() else {
        return Ok(Cleared::NotFound);
    };
    sqlx::query!(
        r#"
        INSERT INTO road_event_reports (id, account_id, kind, geom, event_id, created_at)
        VALUES ($1, $2, 'cleared',
            ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5, $6)
        "#,
        Uuid::now_v7(),
        account,
        row.lon,
        row.lat,
        event_id,
        now,
    )
    .execute(&mut *w.0)
    .await?;
    let summary = summarize_event(&mut w, event_id, kind, "cleared").await?;
    if row.confidence == Confidence::Confirmed.code() {
        sqlx::query!(
            r#"
            INSERT INTO moderation_queue (id, kind, target_type, target_id, account_id, reason)
            VALUES ($1, 'road_report', 'road_event', $2, $3, 'said over while it blocked routes')
            ON CONFLICT DO NOTHING
            "#,
            Uuid::now_v7(),
            event_id,
            account,
        )
        .execute(&mut *w.0)
        .await?;
    }
    w.commit().await?;
    Ok(summary.map_or(Cleared::Ended, |s| Cleared::Noted(s.confidence)))
}

/// Weighs every live community event again ([`community::summarize`]): a
/// banned or deleted account's reports no longer count, so two accounts
/// that confirmed a closure and then left do not keep it blocking; a level
/// gained counts. How many changed or ended. Run by the API every few
/// minutes, with the writers' lock waited for three seconds at most
/// ([`is_busy`] tells that wait's failure apart: the next round does it).
///
/// # Errors
///
/// [`DbError`] when a statement fails or the lock is not free in time.
pub async fn reweigh_community(pool: &PgPool) -> Result<u64, DbError> {
    let mut w = begin_writer_now(pool).await?;
    let changed = reweigh(&mut w).await?;
    w.commit().await?;
    Ok(changed)
}

/// Weighs every live community event again. How many changed or ended.
async fn reweigh(w: &mut EventWriter) -> Result<u64, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, detail, confidence, class, max_height_m, max_width_m, valid_to
        FROM road_events WHERE source = 'community' AND ended_at IS NULL
        "#
    )
    .fetch_all(&mut *w.0)
    .await?;
    let mut changed = 0;
    for row in rows {
        let Ok(kind) = row.detail.parse::<ReportKind>() else {
            continue;
        };
        let after = summarize_event(w, row.id, kind, "moderated").await?;
        if after.is_none_or(|a| {
            a.confidence.code() != row.confidence
                || a.class.code() != row.class
                || a.limits.max_height_m != row.max_height_m
                || a.limits.max_width_m != row.max_width_m
                || Some(a.expires_at) != row.valid_to
        }) {
            changed += 1;
        }
    }
    Ok(changed)
}

/// A moderator removes report `report_id`: the community event it
/// supported is weighed again without it, and ends when nothing is left.
/// Whether the report existed.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn remove_report(pool: &PgPool, report_id: Uuid) -> Result<bool, DbError> {
    let mut w = begin_writer(pool).await?;
    let row = sqlx::query!(
        r#"
        UPDATE road_event_reports SET status = 'removed'
        WHERE id = $1 AND status = 'active'
        RETURNING event_id, kind
        "#,
        report_id
    )
    .fetch_optional(&mut *w.0)
    .await?;
    let Some(row) = row else {
        return Ok(false);
    };
    if let (Some(event), Ok(kind)) = (row.event_id, row.kind.parse::<ReportKind>())
        && kind != ReportKind::Cleared
    {
        summarize_event(&mut w, event, kind, "moderated").await?;
    }
    w.commit().await?;
    Ok(true)
}

/// A moderator ends community event `event_id` and removes its reports.
/// Whether a live community event of that id existed.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn end_community_event(pool: &PgPool, event_id: Uuid) -> Result<bool, DbError> {
    let mut w = begin_writer(pool).await?;
    let ended = sqlx::query!(
        r#"
        UPDATE road_events SET ended_at = now(), end_reason = 'moderated'
        WHERE id = $1 AND source = 'community' AND ended_at IS NULL
        "#,
        event_id
    )
    .execute(&mut *w.0)
    .await?
    .rows_affected();
    sqlx::query!(
        "UPDATE road_event_reports SET status = 'removed' WHERE event_id = $1 AND status = 'active'",
        event_id
    )
    .execute(&mut *w.0)
    .await?;
    w.commit().await?;
    Ok(ended > 0)
}

/// Replaces the restrictions of DiaLog's permanent orders by `records`, in
/// one transaction. How many are stored.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing changes then.
pub async fn replace_dialog_restrictions(
    pool: &PgPool,
    records: &[(RestrictionRecord, Vec<Position>)],
) -> Result<u64, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("DELETE FROM route_restrictions WHERE source = 'dialog'")
        .execute(&mut *tx)
        .await?;
    let stored = crate::routing::insert_restrictions(&mut tx, None, records).await?;
    tx.commit().await?;
    Ok(stored)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn geometries_travel_as_wkt_and_come_back() {
        let a = Position::new(45.8466, 1.2852).unwrap();
        let b = Position::new(45.8462, 1.2855).unwrap();
        let c = Position::new(45.8460, 1.2850).unwrap();
        assert_eq!(wkt(&SourceGeometry::Point(a)), "POINT(1.2852 45.8466)");
        let line = SourceGeometry::Lines(vec![vec![a, b]]);
        assert_eq!(wkt(&line), "LINESTRING(1.2852 45.8466,1.2855 45.8462)");
        assert!(
            wkt(&SourceGeometry::Lines(vec![vec![a, b], vec![b, c]]))
                .starts_with("MULTILINESTRING((")
        );
        let area = wkt(&SourceGeometry::Polygons(vec![vec![a, b, c]]));
        assert!(
            area.ends_with("1.2852 45.8466)))"),
            "the ring is closed: {area}"
        );
        assert_eq!(
            source_geometry(
                r#"{"type":"LineString","coordinates":[[1.2852,45.8466],[1.2855,45.8462]]}"#
            ),
            Some(line)
        );
        assert_eq!(matched_lines(None), Vec::<Vec<Position>>::new());
    }
}
