//! The GraphQL types of road events: an event as the app receives it (in
//! the change feed and along a route), the freshness of each source, the
//! feed's answer, and the users' reports. The domain's enums are
//! `#[non_exhaustive]`: a value added there gets its own GraphQL value here.

use async_graphql::{Enum, InputObject, SimpleObject};
use chrono::{DateTime, DurationRound as _, Utc};
use lunaway_db::road_events::{EventRow, SourceStatus};
use lunaway_domain::{
    Position,
    road_events::{
        AppliesTo, Carriageway, Confidence, EventClass, EventDirection, EventReason, EventSeverity,
        LimitKind, MatchQuality, SourceGeometry,
        assess::{PLANNED_AGE, UNPLANNED_AGE},
        community::ReportKind,
        schedule::Zone,
    },
    routing::polyline,
};
use uuid::Uuid;

/// What an event does to traffic.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventClass")]
pub enum GqlRoadEventClass {
    /// The road, a carriageway or a slip road is closed to all.
    Closure,
    /// Works without a measure that stops a vehicle.
    Works,
    /// Lanes closed, alternating traffic, narrow lanes, a contraflow.
    LaneRestriction,
    /// A temporary height, width, length or weight limit.
    VehicleLimit,
    /// A diversion signposted or advised for others.
    Detour,
}

impl From<EventClass> for GqlRoadEventClass {
    fn from(c: EventClass) -> Self {
        match c {
            EventClass::Closure => Self::Closure,
            EventClass::Works => Self::Works,
            EventClass::LaneRestriction => Self::LaneRestriction,
            EventClass::VehicleLimit => Self::VehicleLimit,
            EventClass::Detour => Self::Detour,
        }
    }
}

impl From<GqlRoadEventClass> for EventClass {
    fn from(c: GqlRoadEventClass) -> Self {
        match c {
            GqlRoadEventClass::Closure => Self::Closure,
            GqlRoadEventClass::Works => Self::Works,
            GqlRoadEventClass::LaneRestriction => Self::LaneRestriction,
            GqlRoadEventClass::VehicleLimit => Self::VehicleLimit,
            GqlRoadEventClass::Detour => Self::Detour,
        }
    }
}

/// Which part of the road.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventCarriageway")]
pub enum GqlCarriageway {
    /// The main carriageway.
    Main,
    /// An entry slip road of the interchange at `position`.
    Entry,
    /// An exit slip road of the interchange at `position`.
    Exit,
    /// Slip roads of the interchange at `position`, entry and exit.
    Ramps,
    /// Not stated.
    Unknown,
}

impl From<Carriageway> for GqlCarriageway {
    fn from(c: Carriageway) -> Self {
        match c {
            Carriageway::Main => Self::Main,
            Carriageway::Entry => Self::Entry,
            Carriageway::Exit => Self::Exit,
            Carriageway::Ramps => Self::Ramps,
            Carriageway::Unknown => Self::Unknown,
        }
    }
}

/// The direction concerned.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventDirection")]
pub enum GqlDirection {
    /// Both directions.
    Both,
    /// The direction of `sourceLines`' points.
    Forward,
    /// Northbound (the road's general direction: within 100 degrees).
    North,
    /// Southbound.
    South,
    /// Eastbound.
    East,
    /// Westbound.
    West,
    /// Not stated: both.
    Unknown,
}

impl From<EventDirection> for GqlDirection {
    fn from(d: EventDirection) -> Self {
        match d {
            EventDirection::Both => Self::Both,
            EventDirection::Forward => Self::Forward,
            EventDirection::North => Self::North,
            EventDirection::South => Self::South,
            EventDirection::East => Self::East,
            EventDirection::West => Self::West,
            EventDirection::Unknown => Self::Unknown,
        }
    }
}

/// How an event is placed on the routing graph.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventMatch")]
pub enum GqlMatch {
    /// Not placed yet: it warns.
    Pending,
    /// On the roads of `lines`, each in driving order.
    Matched,
    /// The slip roads of the interchange at `position`: a route taking an
    /// exit (or entry) slip road leaving (or joining) `roadNumber` within
    /// 1 km of it, in its direction, meets it. Never the main carriageway.
    Ramp,
    /// The point `position` on `roadNumber`: a route passing within 15 m
    /// of it on that road, in its direction (or `headingDeg` within 60
    /// degrees), meets it.
    Point,
    /// Could not be placed: it warns at its own position.
    Unmatched,
}

impl From<MatchQuality> for GqlMatch {
    fn from(m: MatchQuality) -> Self {
        match m {
            MatchQuality::Pending => Self::Pending,
            MatchQuality::Matched => Self::Matched,
            MatchQuality::Ramp => Self::Ramp,
            MatchQuality::Point => Self::Point,
            MatchQuality::Unmatched => Self::Unmatched,
        }
    }
}

/// How far an event is to be believed.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventConfidence")]
pub enum GqlConfidence {
    /// An official source's record.
    Official,
    /// One user reported it: a warning.
    Reported,
    /// Two users or more reported it.
    Confirmed,
}

impl From<Confidence> for GqlConfidence {
    fn from(c: Confidence) -> Self {
        match c {
            Confidence::Official => Self::Official,
            Confidence::Reported => Self::Reported,
            Confidence::Confirmed => Self::Confirmed,
        }
    }
}

/// Whom a limit concerns.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventAppliesTo")]
pub enum GqlAppliesTo {
    /// Every vehicle.
    All,
    /// Heavy goods vehicles only: a motorhome is told, never stopped.
    GoodsVehicles,
}

/// How an event weighs on a route.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventSeverity")]
pub enum GqlSeverity {
    /// The vehicle may not pass: the route goes around it.
    Blocking,
    /// The vehicle may pass; tell the driver.
    Warning,
    /// Worth knowing.
    Info,
}

impl From<EventSeverity> for GqlSeverity {
    fn from(s: EventSeverity) -> Self {
        match s {
            EventSeverity::Blocking => Self::Blocking,
            EventSeverity::Info => Self::Info,
            // A severity this API does not know yet: the driver is told.
            _ => Self::Warning,
        }
    }
}

/// Why an event weighs the way it does on a route.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventReason")]
pub enum GqlReason {
    /// The road is closed.
    Closed,
    /// A limit below the vehicle's figure.
    LimitExceeded,
    /// A height or width limit passed with little margin.
    NearLimit,
    /// Lanes closed, alternating traffic.
    LaneRestriction,
    /// Works.
    Works,
    /// A detour is signposted for others.
    Detour,
    /// Could not be placed on a road, or a slip road it closes could not
    /// be told apart from the carriageway beside it: it may or may not be
    /// on the route.
    Unmatched,
    /// Its source has not been read for too long.
    Stale,
    /// Outside the hours assumed for a period named without hours.
    OutsideAssumedHours,
    /// A limit for heavy goods vehicles.
    GoodsVehiclesOnly,
    /// A single user's report.
    Unconfirmed,
    /// An open record whose last version is old.
    Aged,
    /// The route starts or ends inside it: no route avoids it.
    AlreadyInside,
}

impl From<EventReason> for GqlReason {
    fn from(r: EventReason) -> Self {
        match r {
            EventReason::Closed => Self::Closed,
            EventReason::LimitExceeded => Self::LimitExceeded,
            EventReason::NearLimit => Self::NearLimit,
            EventReason::LaneRestriction => Self::LaneRestriction,
            EventReason::Works => Self::Works,
            EventReason::Detour => Self::Detour,
            EventReason::Unmatched => Self::Unmatched,
            EventReason::Stale => Self::Stale,
            EventReason::OutsideAssumedHours => Self::OutsideAssumedHours,
            EventReason::GoodsVehiclesOnly => Self::GoodsVehiclesOnly,
            EventReason::Unconfirmed => Self::Unconfirmed,
            EventReason::Aged => Self::Aged,
            EventReason::AlreadyInside => Self::AlreadyInside,
            // A reason this API does not know yet: told as an event that
            // may or may not be on the route.
            _ => Self::Unmatched,
        }
    }
}

/// Which figure of a limit.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventLimitKind")]
pub enum GqlLimitKind {
    /// Height, metres.
    Height,
    /// Width, metres.
    Width,
    /// Length, metres.
    Length,
    /// Total authorised mass, tonnes.
    Weight,
}

impl From<LimitKind> for GqlLimitKind {
    fn from(k: LimitKind) -> Self {
        match k {
            LimitKind::Height => Self::Height,
            LimitKind::Width => Self::Width,
            LimitKind::Length => Self::Length,
            _ => Self::Weight,
        }
    }
}

/// The limits of a vehicle limit event.
#[derive(SimpleObject, Debug, Clone, Copy)]
#[graphql(name = "RoadEventLimits")]
pub struct GqlLimits {
    /// Height, metres.
    pub max_height_m: Option<f64>,
    /// Width, metres.
    pub max_width_m: Option<f64>,
    /// Length, metres.
    pub max_length_m: Option<f64>,
    /// Total authorised mass, tonnes.
    pub max_weight_t: Option<f64>,
    /// Whom they concern.
    pub applies_to: GqlAppliesTo,
}

/// A weekly window of an event: on the `days` it starts (1 Monday to 7
/// Sunday), from `startMinute` to `endMinute` after midnight in `timeZone`,
/// the next day when the end is not after the start.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(name = "RoadEventWindow")]
pub struct GqlWindow {
    /// Days it starts on, 1 Monday to 7 Sunday.
    pub days: Vec<i32>,
    /// Start, minutes after midnight.
    pub start_minute: i32,
    /// End, minutes after midnight.
    pub end_minute: i32,
}

/// A period an event is lifted.
#[derive(SimpleObject, Debug, Clone, Copy)]
#[graphql(name = "RoadEventPeriod")]
pub struct GqlPeriod {
    /// Start.
    pub from: DateTime<Utc>,
    /// End.
    pub to: DateTime<Utc>,
}

/// When, within its validity, an event applies. A client applies it as the
/// server does: every bound widened by `marginMinutes`, every window by
/// `widenMinutes` more, a lifted period counted only well inside it.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(name = "RoadEventSchedule")]
pub struct GqlSchedule {
    /// Weekly windows; none means all the time.
    pub windows: Vec<GqlWindow>,
    /// Periods it is lifted.
    pub exceptions: Vec<GqlPeriod>,
    /// The windows' time zone: `Europe/Paris` or `UTC`.
    pub time_zone: String,
    /// Minutes added on each side of every bound (15).
    pub margin_minutes: i32,
    /// Minutes added on each side of every window, beyond the margin.
    pub widen_minutes: i32,
    /// The period as the source names it ("Uniquement de nuit").
    pub label: Option<String>,
    /// Whether the windows were chosen by Lunaway for a period named
    /// without hours: outside them, the event warns instead of blocking.
    pub assumed: bool,
    /// An incident (accident, obstacle) rather than planned works: open
    /// (no `validTo`), it stops blocking 12 hours after `sourceUpdatedAt`
    /// (or `firstSeenAt`); planned works after 30 days.
    pub unplanned: bool,
}

/// A point, in degrees.
#[derive(SimpleObject, Debug, Clone, Copy)]
#[graphql(name = "RoadEventPosition")]
pub struct GqlPosition {
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
}

impl From<Position> for GqlPosition {
    fn from(p: Position) -> Self {
        Self {
            lat: p.lat(),
            lon: p.lon(),
        }
    }
}

/// A road event: a closure, works, a lane restriction, a temporary vehicle
/// limit or a detour, from an official source or the users.
#[derive(SimpleObject, Debug, Clone)]
pub struct RoadEvent {
    /// Its id.
    pub id: Uuid,
    /// Its source (`roadEventSources`): `dir`, `dialog`, a city, `community`.
    pub source: String,
    /// The source's identifier.
    pub external_id: String,
    /// What it does.
    pub class: GqlRoadEventClass,
    /// The source's own term (`roadClosed`, `doNotUseExit`, `noEntry`).
    pub detail: String,
    /// Which part of the road.
    pub carriageway: GqlCarriageway,
    /// The direction concerned.
    pub direction: GqlDirection,
    /// The course of the users who reported it, degrees from north.
    pub heading_deg: Option<i32>,
    /// Road number (`N165`, `A75`, `D949`).
    pub road_number: Option<String>,
    /// Road name.
    pub road_name: Option<String>,
    /// The limits of a vehicle limit.
    pub limits: Option<GqlLimits>,
    /// Validity start.
    pub valid_from: DateTime<Utc>,
    /// Validity end, when the source gives one.
    pub valid_to: Option<DateTime<Utc>>,
    /// When within the validity.
    pub schedule: GqlSchedule,
    /// The roads it covers on the routing graph, polyline6, each in
    /// driving order: a route meets it when it drives along one of them in
    /// its direction. Empty unless `match` is `MATCHED`.
    pub lines: Vec<String>,
    /// The lines as the source draws them, polyline6, for the map.
    pub source_lines: Vec<String>,
    /// The areas as the source draws them (outer rings, polyline6).
    pub areas: Vec<String>,
    /// A point standing for it.
    pub position: GqlPosition,
    /// How it is placed on the graph.
    #[graphql(name = "match")]
    pub match_quality: GqlMatch,
    /// How far to believe it.
    pub confidence: GqlConfidence,
    /// Whether it can block a route at all: a closure or a vehicle limit
    /// for every vehicle, placed on the graph (`MATCHED`, `RAMP` or
    /// `POINT`), official or confirmed, not an old open record. A client
    /// still checks the time of arrival, the vehicle, its own route and the
    /// source's freshness.
    pub may_block: bool,
    /// Description, in the source's language.
    pub description: Option<String>,
    /// The detour the source describes (for cars; never follow it blindly).
    pub detour: Option<String>,
    /// The source's page of it.
    pub url: Option<String>,
    /// First read by Lunaway.
    pub first_seen_at: DateTime<Utc>,
    /// Last read.
    pub last_seen_at: DateTime<Utc>,
    /// The source's time of its last version.
    pub source_updated_at: Option<DateTime<Utc>>,
}

/// Whether an event can block a route at all, `now`.
#[must_use]
pub(crate) fn may_block(e: &EventRow, now: DateTime<Utc>) -> bool {
    let age = if e.schedule.unplanned {
        UNPLANNED_AGE
    } else {
        PLANNED_AGE
    };
    let updated = e.source_updated_at.unwrap_or(e.first_seen_at);
    let aged = e.valid_to.is_none() && now - updated > age;
    can_block(e) && !aged
}

/// Whether an event can block a route whatever the time: a closure or a
/// limit for every vehicle, placed on the graph, official or confirmed.
/// A change of any of these moves the event's revision, so the change feed
/// can filter on it.
#[must_use]
pub(crate) fn can_block(e: &EventRow) -> bool {
    let class = match e.class {
        EventClass::Closure => true,
        EventClass::VehicleLimit => e.limits.applies_to == AppliesTo::All,
        _ => false,
    };
    let placed = matches!(
        e.match_quality,
        MatchQuality::Matched | MatchQuality::Ramp | MatchQuality::Point
    );
    class && placed && e.confidence != Confidence::Reported
}

/// `t` down to its hour.
fn hour_floor(t: DateTime<Utc>) -> DateTime<Utc> {
    t.duration_trunc(chrono::Duration::hours(1)).unwrap_or(t)
}

/// `t` up to the next hour, unless on one.
fn hour_ceil(t: DateTime<Utc>) -> DateTime<Utc> {
    let floor = hour_floor(t);
    if floor == t {
        t
    } else {
        floor + chrono::Duration::hours(1)
    }
}

/// A user's position as the feed publishes it: four decimals, about ten
/// metres, so that the reports of one account do not draw its trip to the
/// metre for anyone who polls.
fn rounded(p: GqlPosition) -> GqlPosition {
    GqlPosition {
        lat: (p.lat * 10_000.0).round() / 10_000.0,
        lon: (p.lon * 10_000.0).round() / 10_000.0,
    }
}

impl RoadEvent {
    /// The event of a row, as the app receives it `now`. A community event
    /// is published coarser than it is stored: its position to about ten
    /// metres, its times to the hour (its end rounded up, so a client
    /// checking it keeps it a little longer), without the reports' own
    /// times. The route check reads the stored figures.
    pub(crate) fn of(e: &EventRow, now: DateTime<Utc>) -> Self {
        let community = e.source == lunaway_db::road_events::COMMUNITY;
        let (source_lines, areas) = match &e.geometry {
            SourceGeometry::Lines(lines) => (
                lines.iter().map(|l| polyline::encode(l)).collect(),
                Vec::new(),
            ),
            SourceGeometry::Polygons(rings) => (
                Vec::new(),
                rings.iter().map(|l| polyline::encode(l)).collect(),
            ),
            SourceGeometry::Point(_) => (Vec::new(), Vec::new()),
        };
        let position = e
            .geometry
            .representative()
            .map_or(GqlPosition { lat: 0.0, lon: 0.0 }, GqlPosition::from);
        let position = if community {
            rounded(position)
        } else {
            position
        };
        let limits = (!e.limits.is_empty()).then_some(GqlLimits {
            max_height_m: e.limits.max_height_m,
            max_width_m: e.limits.max_width_m,
            max_length_m: e.limits.max_length_m,
            max_weight_t: e.limits.max_weight_t,
            applies_to: match e.limits.applies_to {
                AppliesTo::All => GqlAppliesTo::All,
                AppliesTo::GoodsVehicles => GqlAppliesTo::GoodsVehicles,
            },
        });
        let s = &e.schedule;
        Self {
            id: e.id,
            source: e.source.clone(),
            external_id: e.external_id.clone(),
            class: e.class.into(),
            detail: e.detail.clone(),
            carriageway: e.carriageway.into(),
            direction: e.direction.into(),
            heading_deg: e.heading_deg.map(i32::from),
            road_number: e.road_number.clone(),
            road_name: e.road_name.clone(),
            limits,
            valid_from: if community {
                hour_floor(e.valid_from)
            } else {
                e.valid_from
            },
            valid_to: if community {
                e.valid_to.map(hour_ceil)
            } else {
                e.valid_to
            },
            schedule: GqlSchedule {
                windows: s
                    .windows
                    .iter()
                    .map(|w| GqlWindow {
                        days: (0..7)
                            .filter(|d| w.days & (1 << d) != 0)
                            .map(|d| d + 1)
                            .collect(),
                        start_minute: i32::from(w.start_min),
                        end_minute: i32::from(w.end_min),
                    })
                    .collect(),
                exceptions: s
                    .exceptions
                    .iter()
                    .map(|p| GqlPeriod {
                        from: p.from,
                        to: p.to,
                    })
                    .collect(),
                time_zone: match s.zone {
                    Zone::Utc => "UTC".to_owned(),
                    _ => "Europe/Paris".to_owned(),
                },
                margin_minutes: i32::try_from(lunaway_domain::road_events::schedule::MARGIN_MIN)
                    .unwrap_or(15),
                widen_minutes: i32::from(s.widen_min),
                label: s.label.clone(),
                assumed: s.assumed,
                unplanned: s.unplanned,
            },
            lines: e.matched.iter().map(|l| polyline::encode(l)).collect(),
            source_lines,
            areas,
            position,
            match_quality: e.match_quality.into(),
            confidence: e.confidence.into(),
            may_block: may_block(e, now),
            description: e.description.clone(),
            detour: e.detour.clone(),
            url: e.url.clone(),
            first_seen_at: if community {
                hour_floor(e.first_seen_at)
            } else {
                e.first_seen_at
            },
            last_seen_at: if community {
                hour_floor(e.last_seen_at)
            } else {
                e.last_seen_at
            },
            source_updated_at: e.source_updated_at.filter(|_| !community),
        }
    }
}

/// A source of road events, and how fresh its data is.
#[derive(SimpleObject, Debug, Clone)]
pub struct RoadEventSourceStatus {
    /// Its id (`dir`, `dialog`, `paris-fermetures`, `community`...).
    pub id: String,
    /// Its name.
    pub name: String,
    /// Its licence.
    pub licence: String,
    /// The text to credit it with, on the map and with a route.
    pub attribution: String,
    /// Its page.
    pub url: String,
    /// When it was last read with success, news or not: the poller is
    /// alive.
    pub last_read_at: Option<DateTime<Utc>>,
    /// Seconds since then.
    pub age_seconds: Option<i32>,
    /// When its data was last known current: a complete snapshot read, or
    /// for the DIR the newer of its aggregate's publication and the last
    /// increment applied.
    pub data_at: Option<DateTime<Utc>>,
    /// After this many seconds past `dataAt`, none of its events blocks.
    pub stale_after_seconds: i32,
    /// Whether its events may block now.
    pub fresh: bool,
}

impl RoadEventSourceStatus {
    /// The status of a source `now`. The community's reports age by their
    /// own lifetime, so the community is always fresh.
    pub(crate) fn of(s: &SourceStatus, now: DateTime<Utc>) -> Self {
        let age = s.last_success_at.map(|t| (now - t).num_seconds().max(0));
        let fresh = s.id == lunaway_db::road_events::COMMUNITY
            || s.data_at
                .is_some_and(|t| (now - t).num_seconds() <= i64::from(s.stale_after_s));
        Self {
            id: s.id.clone(),
            name: s.name.clone(),
            licence: s.licence.clone(),
            attribution: s.attribution.clone(),
            url: s.url.clone(),
            last_read_at: s.last_success_at,
            age_seconds: age.map(|a| i32::try_from(a).unwrap_or(i32::MAX)),
            data_at: s.data_at,
            stale_after_seconds: s.stale_after_s,
            fresh,
        }
    }
}

/// The changes of the road events since a cursor (`Query.roadEvents`).
#[derive(SimpleObject, Debug, Clone)]
pub struct RoadEventDelta {
    /// The cursor to send next time.
    pub cursor: String,
    /// Whether `upserts` is the whole set (no cursor, an expired one, or
    /// one from another copy of the database): replace what is held.
    pub full: bool,
    /// When the answer was made.
    pub as_of: DateTime<Utc>,
    /// Events new or changed, of the classes asked.
    pub upserts: Vec<RoadEvent>,
    /// Ids of events ended, no longer of the classes asked, or postponed
    /// past the 48 hours the feed carries: drop them.
    pub removals: Vec<Uuid>,
    /// Every source and its freshness.
    pub sources: Vec<RoadEventSourceStatus>,
    /// How long to wait before asking again, seconds (180).
    pub poll_interval_seconds: i32,
    /// Whether more changes wait: ask again at once with `cursor`.
    pub has_more: bool,
}

/// An event met along a route.
#[derive(SimpleObject, Debug, Clone)]
pub struct RoadEventWarning {
    /// The event.
    pub event: RoadEvent,
    /// How it weighs on this route.
    pub severity: GqlSeverity,
    /// Why.
    pub reason: GqlReason,
    /// Distance from the start of the route where it begins, metres.
    pub distance_from_start_m: f64,
    /// Length of the route inside it, metres (0 for a point).
    pub length_m: f64,
    /// Index of the route's shape point at or before it.
    pub geometry_index: i32,
    /// Where the route meets it, latitude.
    pub lat: f64,
    /// Where the route meets it, longitude.
    pub lon: f64,
    /// When the vehicle gets there, as the engine estimates.
    pub arrival_at: DateTime<Utc>,
    /// The figure compared, for a vehicle limit.
    pub limit_kind: Option<GqlLimitKind>,
    /// Its value, metres or tonnes.
    pub limit: Option<f64>,
    /// The vehicle's figure.
    pub vehicle_value: Option<f64>,
    /// When its source's data was last known current
    /// (`RoadEventSourceStatus.dataAt`).
    pub data_read_at: Option<DateTime<Utc>>,
    /// Seconds since then.
    pub data_age_seconds: Option<i32>,
}

/// What a user reports on the road.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "RoadEventReportKind")]
pub enum GqlReportKind {
    /// The road is closed.
    Closure,
    /// Works on the road.
    Works,
    /// A narrow passage, with its width when measured.
    NarrowPassage,
    /// A low clearance, with its height.
    LowClearance,
}

impl From<GqlReportKind> for ReportKind {
    fn from(k: GqlReportKind) -> Self {
        match k {
            GqlReportKind::Closure => Self::Closure,
            GqlReportKind::Works => Self::Works,
            GqlReportKind::NarrowPassage => Self::NarrowPassage,
            GqlReportKind::LowClearance => Self::LowClearance,
        }
    }
}

/// A report made on the road.
#[derive(InputObject, Debug, Clone, Copy)]
pub struct RoadEventReportInput {
    /// What is seen.
    pub kind: GqlReportKind,
    /// Where, latitude.
    pub lat: f64,
    /// Where, longitude.
    pub lon: f64,
    /// The vehicle's course, degrees from north (0 to 359), when moving:
    /// a report concerns the direction it was made in.
    pub heading_deg: Option<i32>,
    /// The height of a low clearance (1.5 to 6 m, required) or the width of
    /// a narrow passage (1.5 to 5 m), as signed or measured.
    pub value_m: Option<f64>,
}

/// What a "it is over" did.
#[derive(Enum, Debug, Clone, Copy, PartialEq, Eq)]
#[graphql(name = "RoadEventCleared")]
pub enum GqlRoadEventCleared {
    /// The event ended: its only reporter took it back, or two accounts of
    /// level 1 or more said it is over.
    Ended,
    /// The event no longer blocks routes; it warns until two accounts of
    /// level 1 or more confirm it again.
    Warning,
    /// Recorded: the event still blocks until a second account of level 1
    /// or more, or a moderator, says it is over.
    Noted,
}

/// What a report did.
#[derive(SimpleObject, Debug, Clone)]
pub struct RoadEventReportResult {
    /// The report.
    pub report_id: Uuid,
    /// The community event it supports.
    pub event_id: Uuid,
    /// The event's confidence: `REPORTED` warns others, `CONFIRMED` (two
    /// accounts of level 1 or more within two hours) blocks their routes.
    pub confidence: GqlConfidence,
    /// When the event ends without a new report.
    pub expires_at: DateTime<Utc>,
}
