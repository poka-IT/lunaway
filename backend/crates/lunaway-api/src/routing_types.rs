//! The GraphQL types of routing: what the app sends to ask for a route,
//! and what it gets back. The domain's enums are `#[non_exhaustive]`, so the
//! conversions below end with a catch-all arm; a value added to the domain
//! must be given its own GraphQL value here (`tests/route.rs` reads every
//! kind the check produces). Severity never goes through a catch-all: an
//! unknown one blocks (`crate::routing`).

use async_graphql::{Enum, InputObject, SimpleObject};
use chrono::{DateTime, Utc};
use lunaway_domain::{
    routing::{
        Certainty, FindingKind, RestrictionFeature, RestrictionSource, Severity, TrailerKind,
        VehicleKind, vehicle::bounds,
    },
    speed::{LimitSource, Span},
};

use crate::{
    road_event_types::{RoadEvent, RoadEventSourceStatus, RoadEventWarning},
    routing::{
        CheckedRoute, Met,
        diagnose::{Limit, Place, Unreachable},
        events::{EventHit, Freshness},
        ferries::Ferry,
        valhalla::Constraint,
    },
};

/// What the vehicle is, for its typical dimensions; the route depends on
/// the dimensions only. (`VehicleKind` is the coarser kind a review names.)
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "VehicleType")]
pub enum GqlVehicleType {
    /// A compact campervan on a van base (California class).
    Van,
    /// A panel van conversion ("fourgon aménagé").
    PanelVan,
    /// A low-profile motorhome ("profilé").
    LowProfile,
    /// A motorhome with a bed over the cab ("capucine").
    Overcab,
    /// An integrated (A-class) motorhome ("intégral").
    Integrated,
    /// Anything else.
    Other,
}

impl From<GqlVehicleType> for VehicleKind {
    fn from(k: GqlVehicleType) -> Self {
        match k {
            GqlVehicleType::Van => Self::Van,
            GqlVehicleType::PanelVan => Self::PanelVan,
            GqlVehicleType::LowProfile => Self::LowProfile,
            GqlVehicleType::Overcab => Self::Overcab,
            GqlVehicleType::Integrated => Self::Integrated,
            GqlVehicleType::Other => Self::Other,
        }
    }
}

impl From<VehicleKind> for GqlVehicleType {
    fn from(k: VehicleKind) -> Self {
        match k {
            VehicleKind::Van => Self::Van,
            VehicleKind::PanelVan => Self::PanelVan,
            VehicleKind::LowProfile => Self::LowProfile,
            VehicleKind::Overcab => Self::Overcab,
            VehicleKind::Integrated => Self::Integrated,
            _ => Self::Other,
        }
    }
}

/// A point of a route.
#[derive(InputObject, Debug, Clone, Copy)]
pub struct RoutePointInput {
    /// Latitude, WGS 84.
    pub lat: f64,
    /// Longitude, WGS 84.
    pub lon: f64,
    /// The vehicle's course, degrees from north (0 to 360), for the start
    /// of a recalculation: the route then leaves in that direction.
    pub heading_deg: Option<f64>,
}

/// A trailer behind the vehicle.
#[derive(InputObject, SimpleObject, Debug, Clone, Copy)]
#[graphql(input_name = "TrailerInput", name = "Trailer")]
pub struct TrailerInput {
    /// Length, drawbar included, metres (1 to 12).
    pub length_m: f64,
    /// Maximum authorised mass, tonnes (0.1 to 10).
    pub weight_t: f64,
    /// Height with its load, metres, when it may exceed the vehicle's.
    pub height_m: Option<f64>,
    /// Width, metres, when it may exceed the vehicle's.
    pub width_m: Option<f64>,
}

/// The vehicle, as on its registration document. The bounds refuse typing
/// errors: a height of 1.5 to 4.5 m, a width of 1.5 to 2.6 m without
/// mirrors, a length of 3 to 15 m, a maximum authorised mass (field F.2) of
/// 0.5 to 40 t, an axle load of 0.5 to 13 t.
#[derive(InputObject, SimpleObject, Debug, Clone, Copy)]
#[graphql(input_name = "VehicleProfileInput", name = "VehicleProfile")]
pub struct VehicleProfileInput {
    /// What the vehicle is.
    pub kind: GqlVehicleType,
    /// Overall height, roof equipment included, metres.
    pub height_m: f64,
    /// Overall width without mirrors, metres.
    pub width_m: f64,
    /// Overall length, bike rack included, metres.
    pub length_m: f64,
    /// Maximum authorised mass, tonnes.
    pub weight_t: f64,
    /// Heaviest axle, tonnes, when known: axle load limits are checked only
    /// with it.
    pub axle_load_t: Option<f64>,
    /// The trailer, when towing.
    pub trailer: Option<TrailerInput>,
}

/// What to avoid. Tolls, motorways and ferries are avoided when another way
/// exists; unpaved roads are never used, except where the trip starts or
/// ends on one. An absent switch is off.
#[derive(InputObject, Debug, Clone, Copy, Default)]
pub struct RouteOptionsInput {
    /// Avoid toll roads.
    pub avoid_tolls: Option<bool>,
    /// Avoid motorways.
    pub avoid_motorways: Option<bool>,
    /// Avoid ferries.
    pub avoid_ferries: Option<bool>,
    /// Never use unpaved roads.
    pub avoid_unpaved: Option<bool>,
}

/// What a route avoided, as applied.
#[derive(SimpleObject, Debug, Clone, Copy, Default, PartialEq, Eq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "four independent switches, as the app shows them"
)]
pub struct RouteOptions {
    /// Toll roads avoided.
    pub avoid_tolls: bool,
    /// Motorways avoided.
    pub avoid_motorways: bool,
    /// Ferries avoided.
    pub avoid_ferries: bool,
    /// Unpaved roads never used.
    pub avoid_unpaved: bool,
}

impl From<RouteOptionsInput> for RouteOptions {
    fn from(o: RouteOptionsInput) -> Self {
        Self {
            avoid_tolls: o.avoid_tolls.unwrap_or(false),
            avoid_motorways: o.avoid_motorways.unwrap_or(false),
            avoid_ferries: o.avoid_ferries.unwrap_or(false),
            avoid_unpaved: o.avoid_unpaved.unwrap_or(false),
        }
    }
}

/// The language of the instructions.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq, Default)]
pub enum RouteLanguage {
    /// French.
    #[default]
    Fr,
    /// English.
    En,
}

impl RouteLanguage {
    /// The engine's language tag.
    pub(crate) const fn tag(self) -> &'static str {
        match self {
            Self::Fr => "fr-FR",
            Self::En => "en-US",
        }
    }
}

/// A route request.
#[derive(InputObject, Debug, Clone)]
pub struct RouteInput {
    /// Where the trip starts (the vehicle's position for a recalculation).
    pub origin: RoutePointInput,
    /// Where it ends.
    pub destination: RoutePointInput,
    /// Stops on the way, in order, 5 at most.
    pub waypoints: Option<Vec<RoutePointInput>>,
    /// The vehicle.
    pub vehicle: VehicleProfileInput,
    /// What to avoid.
    pub options: Option<RouteOptionsInput>,
    /// Alternatives wanted besides the best route, 0 to 2; only without
    /// waypoints, one at most beyond 2 000 km in a straight line, none
    /// beyond 3 000 km (the answer's size).
    #[graphql(default = 0)]
    pub alternatives: i32,
    /// The language of the instructions.
    #[graphql(default)]
    pub language: RouteLanguage,
    /// When the trip starts, now when absent, up to 14 days ahead: road
    /// events (closures, works) count at the time the vehicle reaches them.
    pub depart_at: Option<DateTime<Utc>>,
}

/// How a request ended.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RouteStatus {
    /// At least one route the vehicle may drive.
    Ok,
    /// No route between the points: `noRouteReasons` says why (a stop the
    /// vehicle cannot reach, a stop outside the area routing covers, no
    /// road at all).
    NoRoute,
    /// A point is too far from any road: `noRouteReasons` names it.
    OffNetwork,
    /// Roads exist, but each meets a limit the vehicle exceeds:
    /// `blockers` says which, and where.
    NoSafeRoute,
}

/// Why a trip has no route (`RouteResult.noRouteReasons`).
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum NoRouteReasonKind {
    /// The vehicle cannot reach the origin, or leave it: every way passes
    /// a limit it exceeds (`limits` says which).
    OriginUnreachable,
    /// The vehicle cannot reach the destination: every way passes a limit
    /// it exceeds.
    DestinationUnreachable,
    /// The vehicle cannot reach the waypoint at `stopIndex`.
    WaypointUnreachable,
    /// Each stop can be reached, but no way between them was found for the
    /// vehicle: `limits` names those our data finds on the small vehicle's
    /// way, empty when unknown (always on a trip over 1 000 km).
    BlockedOnTheWay,
    /// No road joins the stop at `stopIndex`, or the stops when it is null,
    /// whatever the vehicle (an island without a car ferry).
    NotConnected,
    /// The stop lies outside the area routing covers
    /// (`RoutingInfo.coveredCountries`).
    OutsideCoverage,
    /// No road the vehicle may drive within 5 km of the stop.
    NoRoadNearby,
}

/// A limit that keeps the vehicle out.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum VehicleLimitKind {
    /// Its height.
    Height,
    /// Its width.
    Width,
    /// Its length.
    Length,
    /// Its weight.
    Weight,
    /// The only roads are unpaved, which the trip avoids.
    Unpaved,
}

impl From<Constraint> for VehicleLimitKind {
    fn from(c: Constraint) -> Self {
        match c {
            Constraint::Height => Self::Height,
            Constraint::Width => Self::Width,
            Constraint::Length => Self::Length,
            Constraint::Weight => Self::Weight,
            Constraint::Unpaved => Self::Unpaved,
        }
    }
}

/// A limit that keeps the vehicle out, with the restriction behind it
/// when our data has it.
#[derive(SimpleObject, Debug, Clone)]
pub struct BlockingLimit {
    /// What it limits.
    pub kind: VehicleLimitKind,
    /// The limit's figure, metres or tonnes, when the restriction is known.
    pub limit: Option<f64>,
    /// The vehicle's figure it was compared with.
    pub vehicle_value: Option<f64>,
    /// The restriction that blocks, when known: its place (`lat`, `lon`),
    /// source, name and identifier, to report a wrong value. Its distance
    /// and geometry index count along a route the engine drew for the
    /// diagnosis, which the app does not receive.
    pub restriction: Option<RouteWarning>,
}

impl From<&Limit> for BlockingLimit {
    fn from(l: &Limit) -> Self {
        let restriction = l.blocker.as_ref().map(RouteWarning::from);
        Self {
            kind: l.constraint.into(),
            limit: restriction.as_ref().and_then(|r| r.limit),
            vehicle_value: l.vehicle_value,
            restriction,
        }
    }
}

/// One reason a trip has no route.
#[derive(SimpleObject, Debug, Clone)]
pub struct NoRouteReason {
    /// What keeps the trip from a route.
    pub kind: NoRouteReasonKind,
    /// The stop concerned: 0 the origin, then the waypoints in order, the
    /// last the destination. Null when the reason is not one stop's.
    pub stop_index: Option<i32>,
    /// The limits that keep the vehicle out; empty when the reason is not
    /// the vehicle's, or when they could not be told.
    pub limits: Vec<BlockingLimit>,
}

impl NoRouteReason {
    /// A reason of the engine's diagnosis, `last` the index of the
    /// destination.
    pub(crate) fn of(u: &Unreachable, last: usize) -> Self {
        let (kind, stop) = match u.place {
            Place::Stop(0) => (NoRouteReasonKind::OriginUnreachable, Some(0)),
            Place::Stop(i) if i == last => (NoRouteReasonKind::DestinationUnreachable, Some(i)),
            Place::Stop(i) => (NoRouteReasonKind::WaypointUnreachable, Some(i)),
            Place::OnTheWay => (NoRouteReasonKind::BlockedOnTheWay, None),
            Place::NotConnected(stop) => (NoRouteReasonKind::NotConnected, stop),
        };
        Self {
            kind,
            stop_index: stop.and_then(|i| i32::try_from(i).ok()),
            limits: u.limits.iter().map(BlockingLimit::from).collect(),
        }
    }

    /// The reason `kind` for each of `stops`; one without a stop when the
    /// stops are not known.
    pub(crate) fn at_stops(kind: NoRouteReasonKind, stops: &[usize], last: usize) -> Vec<Self> {
        if stops.is_empty() {
            return vec![Self {
                kind,
                stop_index: None,
                limits: Vec::new(),
            }];
        }
        stops
            .iter()
            .filter(|i| **i <= last)
            .map(|i| Self {
                kind,
                stop_index: i32::try_from(*i).ok(),
                limits: Vec::new(),
            })
            .collect()
    }
}

/// What the app should tell about a route besides its restrictions and
/// road events.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RouteNoticeKind {
    /// The route takes a ferry (`ferry`): avoiding ferries is a
    /// preference, and the route still crosses when no road leads there.
    RouteUsesFerry,
}

/// A ferry crossing of a route.
#[derive(SimpleObject, Debug, Clone)]
pub struct FerryCrossing {
    /// The ferry line's name, as OpenStreetMap maps it (`Nice - Ajaccio`).
    pub name: Option<String>,
    /// The two ports its name gives, in the name's order (not always the
    /// crossing's); empty when the name does not give them.
    pub ports: Vec<String>,
    /// Where the boat is boarded, latitude.
    pub from_lat: Option<f64>,
    /// Where the boat is boarded, longitude.
    pub from_lon: Option<f64>,
    /// Where it is left, latitude.
    pub to_lat: Option<f64>,
    /// Where it is left, longitude.
    pub to_lon: Option<f64>,
    /// Country where it is boarded (ISO 3166-1 alpha-2).
    pub from_country: Option<String>,
    /// Country where it is left.
    pub to_country: Option<String>,
    /// Distance from the start of the route to the boarding, metres.
    pub distance_from_start_m: f64,
    /// Metres on the boat.
    pub distance_m: f64,
    /// Seconds on the boat, as the engine reckons (the timetable is not
    /// known).
    pub duration_s: f64,
    /// Index of the route's shape point where it starts.
    pub geometry_index: Option<i32>,
}

impl From<&Ferry> for FerryCrossing {
    fn from(f: &Ferry) -> Self {
        let round = |m: f64| (m * 10.0).round() / 10.0;
        Self {
            name: f.name.clone(),
            ports: f.ports.clone(),
            from_lat: f.from.map(|p| p.lat()),
            from_lon: f.from.map(|p| p.lon()),
            to_lat: f.to.map(|p| p.lat()),
            to_lon: f.to.map(|p| p.lon()),
            from_country: f.from_country.clone(),
            to_country: f.to_country.clone(),
            distance_from_start_m: round(f.start_m),
            distance_m: round(f.distance_m),
            duration_s: f.duration_s.round(),
            geometry_index: f.geometry_index.and_then(|i| i32::try_from(i).ok()),
        }
    }
}

/// Something the app should tell about a route.
#[derive(SimpleObject, Debug, Clone)]
pub struct RouteNotice {
    /// What.
    pub kind: RouteNoticeKind,
    /// The crossing, for `ROUTE_USES_FERRY`.
    pub ferry: Option<FerryCrossing>,
}

/// What a restriction means for the vehicle.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RouteWarningKind {
    /// A clearance below the vehicle's height, or close to it ("bridge
    /// 3.20 m in 2 km").
    LowClearance,
    /// A clearance below the standard, figure unknown (a height bar without
    /// its figure, `maxheight=below_default`).
    UnknownClearance,
    /// A width limit below the vehicle's, or close to it.
    Narrow,
    /// A length limit below the vehicle's.
    TooLong,
    /// A weight limit below the vehicle's.
    TooHeavy,
    /// An axle load limit below the vehicle's.
    AxleLoad,
    /// No motorhomes.
    MotorhomeBan,
    /// No trailers, or no caravans and trailers over 250 kg.
    TrailerBan,
    /// A weight limit for heavy goods vehicles the vehicle exceeds (a
    /// DiaLog order): it does not apply to a motorhome, check the signs.
    GoodsVehicleWeight,
}

impl From<FindingKind> for RouteWarningKind {
    fn from(k: FindingKind) -> Self {
        match k {
            FindingKind::LowClearance => Self::LowClearance,
            FindingKind::UnknownClearance => Self::UnknownClearance,
            FindingKind::Narrow => Self::Narrow,
            FindingKind::TooLong => Self::TooLong,
            FindingKind::TooHeavy => Self::TooHeavy,
            FindingKind::AxleLoad => Self::AxleLoad,
            FindingKind::MotorhomeBan => Self::MotorhomeBan,
            FindingKind::GoodsVehicleWeight => Self::GoodsVehicleWeight,
            _ => Self::TrailerBan,
        }
    }
}

/// Whether the vehicle may pass.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum WarningSeverity {
    /// It may not: the route avoids the place (a blocker of
    /// `NO_SAFE_ROUTE`).
    Blocking,
    /// It may, with care.
    Warning,
}

/// Where a restriction comes from.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RestrictionSourceKind {
    /// OpenStreetMap (ODbL, "© OpenStreetMap contributors").
    Osm,
    /// IGN BD TOPO (Licence Ouverte 2.0, "IGN, BD TOPO").
    Ign,
    /// A Lunaway user's report.
    Community,
    /// A permanent traffic order of DiaLog (Licence Ouverte 2.0, "DiaLog
    /// (DGITM), arrêtés de circulation").
    Dialog,
}

/// How sure a figure is.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RestrictionCertainty {
    /// One figure, or two sources that agree.
    Known,
    /// Two sources disagree; the lower figure applies until someone checks.
    Disputed,
    /// Lower than the standard clearance, figure unknown.
    Unknown,
}

/// What the restricted place is, for the wording of a warning.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RestrictionPlace {
    /// Under a bridge or a short covered section.
    Underpass,
    /// A tunnel.
    Tunnel,
    /// A passage under a building.
    BuildingPassage,
    /// A bridge.
    Bridge,
    /// A barrier across the road (height bar, gate, bollards).
    Barrier,
    /// A stretch of road.
    Road,
}

/// A restriction along a route.
#[derive(SimpleObject, Debug, Clone)]
pub struct RouteWarning {
    /// What it means for the vehicle.
    pub kind: RouteWarningKind,
    /// Whether the vehicle may pass.
    pub severity: WarningSeverity,
    /// The figure, metres or tonnes, when there is one.
    pub limit: Option<f64>,
    /// The vehicle's figure it was compared with.
    pub vehicle_value: Option<f64>,
    /// Distance from the start of the route, metres.
    pub distance_from_start_m: f64,
    /// Index of the route's shape point at or before it (the OSRM
    /// geometry's, as Ferrostar counts).
    pub geometry_index: i32,
    /// Where the route meets it, latitude.
    pub lat: f64,
    /// Where the route meets it, longitude.
    pub lon: f64,
    /// Where the figure comes from.
    pub source: RestrictionSourceKind,
    /// How sure it is.
    pub certainty: RestrictionCertainty,
    /// What the place is.
    pub place: RestrictionPlace,
    /// The road's name, when known.
    pub name: Option<String>,
    /// The source's identifier (`way/52984577`, `node/348192004`,
    /// `ign/TRONROUT...`), to report a wrong value.
    pub external_id: String,
}

impl From<&Met> for RouteWarning {
    fn from(m: &Met) -> Self {
        let r = &m.restriction.restriction;
        Self {
            kind: m.finding.kind.into(),
            severity: match m.finding.severity {
                Severity::Warning => WarningSeverity::Warning,
                _ => WarningSeverity::Blocking,
            },
            limit: m.finding.limit,
            vehicle_value: m.finding.vehicle_value,
            distance_from_start_m: (m.hit.start_m * 10.0).round() / 10.0,
            geometry_index: i32::try_from(m.hit.geometry_index).unwrap_or(i32::MAX),
            lat: m.hit.at.lat(),
            lon: m.hit.at.lon(),
            source: match r.source {
                RestrictionSource::Osm => RestrictionSourceKind::Osm,
                RestrictionSource::Ign => RestrictionSourceKind::Ign,
                RestrictionSource::Dialog => RestrictionSourceKind::Dialog,
                _ => RestrictionSourceKind::Community,
            },
            certainty: match r.certainty {
                Certainty::Known => RestrictionCertainty::Known,
                Certainty::Disputed => RestrictionCertainty::Disputed,
                _ => RestrictionCertainty::Unknown,
            },
            place: match r.feature {
                RestrictionFeature::Underpass => RestrictionPlace::Underpass,
                RestrictionFeature::Tunnel => RestrictionPlace::Tunnel,
                RestrictionFeature::BuildingPassage => RestrictionPlace::BuildingPassage,
                RestrictionFeature::Bridge => RestrictionPlace::Bridge,
                RestrictionFeature::Barrier => RestrictionPlace::Barrier,
                _ => RestrictionPlace::Road,
            },
            name: m.restriction.name.clone(),
            external_id: m.restriction.external_id.clone(),
        }
    }
}

/// One route of the answer.
#[derive(SimpleObject, Debug, Clone)]
pub struct RouteSummary {
    /// Its index in `osrmJson.routes`; 0 is the recommended route.
    pub index: i32,
    /// Metres.
    pub distance_m: f64,
    /// Seconds, at the speeds the engine assumes for the vehicle.
    pub duration_s: f64,
    /// Whether it uses a toll road.
    pub has_toll: bool,
    /// Whether it uses a ferry.
    pub has_ferry: bool,
    /// Whether it uses a motorway.
    pub has_motorway: bool,
    /// What to tell besides the restrictions and road events: each ferry
    /// crossing (`ROUTE_USES_FERRY`), in driving order.
    pub notices: Vec<RouteNotice>,
    /// Restrictions the vehicle passes with little margin (under 0.30 m of
    /// height, 0.20 m of width) or whose figure is unknown, in driving
    /// order.
    pub warnings: Vec<RouteWarning>,
    /// Road events met on the way that do not block it (lanes closed,
    /// works, a closure that could not be placed or whose source is stale,
    /// a single user's report), each at the time the vehicle gets there, in
    /// driving order.
    pub road_events: Vec<RoadEventWarning>,
    /// The speed limit for this vehicle along the route, in driving order:
    /// the lower of the road's limit and the vehicle's ceiling in the
    /// country (a motorhome over 3.5 t: 110 on a French motorway). A
    /// stretch where no limit is known has no span. Null when the engine
    /// could not say: the route stands, without limits.
    pub speed_limits: Option<Vec<SpeedLimitSpan>>,
}

/// Where a speed limit comes from.
#[derive(Enum, Copy, Clone, Debug, PartialEq, Eq)]
#[graphql(name = "SpeedLimitSource")]
pub enum GqlLimitSource {
    /// A sign, as OpenStreetMap maps it.
    Posted,
    /// The road's default in its country, read from its class and its
    /// surroundings: an estimate, to show as one.
    Default,
    /// The vehicle's own ceiling, lower than the road's limit.
    Vehicle,
}

impl From<LimitSource> for GqlLimitSource {
    fn from(s: LimitSource) -> Self {
        match s {
            LimitSource::Posted => Self::Posted,
            LimitSource::Default => Self::Default,
            LimitSource::Vehicle => Self::Vehicle,
        }
    }
}

/// A stretch of a route under one speed limit for the vehicle.
#[derive(SimpleObject, Debug, Clone, PartialEq)]
pub struct SpeedLimitSpan {
    /// Where it begins, metres from the start of the route.
    pub from_m: f64,
    /// Where it ends, metres from the start.
    pub to_m: f64,
    /// Index of its first point in the route's geometry (polyline6 of
    /// `osrmJson`).
    pub from_index: i32,
    /// Index of its last point.
    pub to_index: i32,
    /// The limit, km/h.
    pub kmh: i32,
    /// Where it comes from.
    pub source: GqlLimitSource,
}

impl From<&Span> for SpeedLimitSpan {
    fn from(s: &Span) -> Self {
        let index = |i: usize| i32::try_from(i).unwrap_or(i32::MAX);
        Self {
            from_m: (s.from_m * 10.0).round() / 10.0,
            to_m: (s.to_m * 10.0).round() / 10.0,
            from_index: index(s.from_index),
            to_index: index(s.to_index),
            kmh: i32::from(s.limit.kmh),
            source: s.limit.source.into(),
        }
    }
}

impl RouteSummary {
    /// The summary of a checked route, the age of its road events' data
    /// read from `fresh`.
    pub(crate) fn of(r: &CheckedRoute, fresh: &Freshness, now: DateTime<Utc>) -> Self {
        Self {
            index: i32::try_from(r.index).unwrap_or(0),
            distance_m: r.distance_m,
            duration_s: r.duration_s,
            has_toll: r.has_toll,
            has_ferry: r.has_ferry,
            has_motorway: r.has_motorway,
            notices: r
                .ferries
                .iter()
                .map(|f| RouteNotice {
                    kind: RouteNoticeKind::RouteUsesFerry,
                    ferry: Some(f.into()),
                })
                .collect(),
            warnings: r.warnings.iter().map(RouteWarning::from).collect(),
            road_events: r
                .events
                .iter()
                .map(|h| road_event_warning(h, fresh, now))
                .collect(),
            speed_limits: None,
        }
    }
}

/// An event met along a route, as the app receives it.
pub(crate) fn road_event_warning(
    h: &EventHit,
    fresh: &Freshness,
    now: DateTime<Utc>,
) -> RoadEventWarning {
    let read_at = fresh.read_at(&h.event.source);
    RoadEventWarning {
        event: RoadEvent::of(&h.event, now),
        severity: h.finding.severity.into(),
        reason: h.finding.reason.into(),
        distance_from_start_m: (h.start_m * 10.0).round() / 10.0,
        length_m: ((h.end_m - h.start_m).max(0.0) * 10.0).round() / 10.0,
        geometry_index: i32::try_from(h.geometry_index).unwrap_or(i32::MAX),
        lat: h.at.lat(),
        lon: h.at.lon(),
        arrival_at: h.arrival,
        limit_kind: h.finding.limit.map(|(k, _)| k.into()),
        limit: h.finding.limit.map(|(_, v)| v),
        vehicle_value: h.finding.vehicle_value,
        data_read_at: read_at,
        data_age_seconds: read_at
            .map(|t| i32::try_from((now - t).num_seconds().max(0)).unwrap_or(i32::MAX)),
    }
}

/// The routing data a route was computed on.
#[derive(SimpleObject, Debug, Clone)]
pub struct RoutingGraph {
    /// The graph's name (`20261006T0300Z-fr`).
    pub id: String,
    /// The date of the OpenStreetMap data: the date to show with the
    /// disclaimer.
    pub osm_data_at: DateTime<Utc>,
    /// When IGN's restrictions were read, if the graph has them.
    pub ign_fetched_at: Option<DateTime<Utc>>,
    /// The BD TOPO edition they come from, for the attribution "IGN,
    /// BD TOPO" with its date.
    pub ign_edition: Option<chrono::NaiveDate>,
    /// When the graph was built.
    pub built_at: DateTime<Utc>,
}

impl From<lunaway_db::routing::GraphRow> for RoutingGraph {
    fn from(g: lunaway_db::routing::GraphRow) -> Self {
        Self {
            id: g.id,
            osm_data_at: g.osm_data_at,
            ign_fetched_at: g.ign_fetched_at,
            ign_edition: g.ign_edition,
            built_at: g.built_at,
        }
    }
}

/// What the app sends again to recalculate (from the vehicle's position):
/// the profile and options the route was computed with.
#[derive(SimpleObject, Debug, Clone)]
pub struct RerouteParameters {
    /// The vehicle, as received.
    pub vehicle: VehicleProfileInput,
    /// What to avoid, as applied.
    pub options: RouteOptions,
    /// The language.
    pub language: RouteLanguage,
    /// The engine's costing options the route was computed with, as JSON:
    /// for display and support, not to call the engine directly (it is not
    /// reachable from outside).
    pub costing_options_json: String,
}

/// Key of the disclaimer text the app shows with every route (its
/// translations hold the text): the data may be incomplete or wrong, the
/// signs and the highway code come first, the driver stays responsible,
/// with the data's date (`plan/research/07-navigation.md`, F.3).
pub const DISCLAIMER_KEY: &str = "routing.disclaimer.v1";

/// The answer to a route request.
#[derive(SimpleObject, Debug, Clone)]
pub struct RouteResult {
    /// How it ended.
    pub status: RouteStatus,
    /// When `status` is `NO_ROUTE` or `OFF_NETWORK`: why, one reason per
    /// stop concerned, or one for the trip. Empty when the cause could not
    /// be told in time.
    pub no_route_reasons: Vec<NoRouteReason>,
    /// The engine's answer in the OSRM format (as Valhalla writes it with
    /// `format: osrm`, banner and voice instructions, polyline6 geometry),
    /// with only the routes the vehicle may drive: what Ferrostar's OSRM
    /// parser reads. Null unless `status` is `OK`.
    pub osrm_json: Option<String>,
    /// The routes, in the order of `osrmJson.routes`.
    pub routes: Vec<RouteSummary>,
    /// When `status` is `NO_SAFE_ROUTE`: the limits that stopped every
    /// route, in driving order of the last route tried.
    pub blockers: Vec<RouteWarning>,
    /// When `status` is `NO_SAFE_ROUTE`: the road events that stopped every
    /// route (a closure, a temporary limit), in driving order of the last
    /// route tried.
    pub road_event_blockers: Vec<RoadEventWarning>,
    /// The road events an earlier computation met and the routes go
    /// around: "2 closures avoided".
    pub avoided_road_events: Vec<RoadEvent>,
    /// The sources of road events and the age of their data, to show with
    /// the route ("travaux : données de 13 h 05").
    pub road_event_sources: Vec<RoadEventSourceStatus>,
    /// How many times the route was computed again around a limit the
    /// vehicle exceeds.
    pub recalculations: i32,
    /// What to send again for a recalculation.
    pub reroute: RerouteParameters,
    /// The data the route was computed on.
    pub graph: RoutingGraph,
    /// The disclaimer's translation key.
    pub disclaimer_key: String,
}

/// Typical dimensions of a kind of vehicle, offered before the user enters
/// the real ones.
#[derive(SimpleObject, Debug, Clone)]
pub struct VehiclePreset {
    /// A stable name (`panel-van`, `integrated-heavy`).
    pub id: String,
    /// The kind.
    pub kind: GqlVehicleType,
    /// Metres.
    pub height_m: f64,
    /// Metres, without mirrors.
    pub width_m: f64,
    /// Metres.
    pub length_m: f64,
    /// Tonnes.
    pub weight_t: f64,
    /// The model the values come from.
    pub source: String,
}

/// Typical dimensions of a trailer.
#[derive(SimpleObject, Debug, Clone)]
pub struct TrailerPreset {
    /// What it carries (`car-trailer`).
    pub id: String,
    /// Length, drawbar included, metres.
    pub length_m: f64,
    /// Width, metres.
    pub width_m: f64,
    /// Maximum authorised mass, tonnes.
    pub weight_t: f64,
    /// The product the values come from.
    pub source: String,
}

/// A range of accepted values.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct Bounds {
    /// Least accepted.
    pub min: f64,
    /// Greatest accepted.
    pub max: f64,
}

impl From<std::ops::RangeInclusive<f64>> for Bounds {
    fn from(r: std::ops::RangeInclusive<f64>) -> Self {
        Self {
            min: *r.start(),
            max: *r.end(),
        }
    }
}

/// The bounds of a vehicle profile.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct VehicleBounds {
    /// Height, metres.
    pub height_m: Bounds,
    /// Width, metres.
    pub width_m: Bounds,
    /// Length of the vehicle, metres.
    pub length_m: Bounds,
    /// Maximum authorised mass, tonnes.
    pub weight_t: Bounds,
    /// Axle load, tonnes.
    pub axle_load_t: Bounds,
    /// Trailer length, metres.
    pub trailer_length_m: Bounds,
    /// Trailer mass, tonnes.
    pub trailer_weight_t: Bounds,
}

impl VehicleBounds {
    /// The domain's bounds.
    pub(crate) fn current() -> Self {
        Self {
            height_m: bounds::HEIGHT_M.into(),
            width_m: bounds::WIDTH_M.into(),
            length_m: bounds::LENGTH_M.into(),
            weight_t: bounds::WEIGHT_T.into(),
            axle_load_t: bounds::AXLE_LOAD_T.into(),
            trailer_length_m: bounds::TRAILER_LENGTH_M.into(),
            trailer_weight_t: bounds::TRAILER_WEIGHT_T.into(),
        }
    }
}

/// A box around the area routes are computed in. A point inside may still
/// lie outside it (`RoutingInfo.coveredCountries`): the route then answers
/// `NO_ROUTE` with the reason `OUTSIDE_COVERAGE`.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct CoveredArea {
    /// Southern edge.
    pub south: f64,
    /// Western edge.
    pub west: f64,
    /// Northern edge.
    pub north: f64,
    /// Eastern edge.
    pub east: f64,
}

/// What the app needs to know before asking for a route: whether routing
/// works now, on which data, within which bounds.
#[derive(SimpleObject, Debug, Clone)]
pub struct RoutingInfo {
    /// Whether a route can be computed now: a graph is active and the
    /// engine answers.
    pub available: bool,
    /// The active graph, if any.
    pub graph: Option<RoutingGraph>,
    /// The disclaimer's translation key.
    pub disclaimer_key: String,
    /// A box around the area routes are computed in.
    pub covered_area: CoveredArea,
    /// The countries routes are computed in (ISO 3166-1 alpha-2), sorted.
    pub covered_countries: Vec<String>,
    /// The countries where road events may be reported (ISO 3166-1
    /// alpha-2): those with an official feed of road events.
    pub road_event_report_countries: Vec<String>,
    /// Longest trip accepted, kilometres in a straight line from stop to
    /// stop.
    pub max_trip_km: f64,
    /// Waypoints accepted at most.
    pub max_waypoints: i32,
    /// Alternatives accepted at most.
    pub max_alternatives: i32,
    /// The bounds of a vehicle profile.
    pub vehicle_bounds: VehicleBounds,
    /// Typical vehicles.
    pub vehicle_presets: Vec<VehiclePreset>,
    /// Typical trailers.
    pub trailer_presets: Vec<TrailerPreset>,
}

/// The presets of the domain.
pub(crate) fn presets() -> (Vec<VehiclePreset>, Vec<TrailerPreset>) {
    let vehicles = lunaway_domain::routing::PRESETS
        .iter()
        .map(|p| VehiclePreset {
            id: p.id.to_owned(),
            kind: p.kind.into(),
            height_m: p.height_m,
            width_m: p.width_m,
            length_m: p.length_m,
            weight_t: p.weight_t,
            source: p.source.to_owned(),
        })
        .collect();
    let trailers = lunaway_domain::routing::TRAILER_PRESETS
        .iter()
        .map(|t| TrailerPreset {
            id: match t.kind {
                TrailerKind::CarTrailer => "car-trailer".to_owned(),
                _ => "trailer".to_owned(),
            },
            length_m: t.length_m,
            width_m: t.width_m,
            weight_t: t.weight_t,
            source: t.source.to_owned(),
        })
        .collect();
    (vehicles, trailers)
}
