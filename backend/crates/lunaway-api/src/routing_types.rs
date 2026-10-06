//! The GraphQL types of routing: what the app sends to ask for a route,
//! and what it gets back. The domain's enums are `#[non_exhaustive]`, so the
//! conversions below end with a catch-all arm; a value added to the domain
//! must be given its own GraphQL value here (`tests/route.rs` reads every
//! kind the check produces). Severity never goes through a catch-all: an
//! unknown one blocks (`crate::routing`).

use async_graphql::{Enum, InputObject, SimpleObject};
use chrono::{DateTime, Utc};
use lunaway_domain::routing::{
    Certainty, FindingKind, RestrictionFeature, RestrictionSource, Severity, TrailerKind,
    VehicleKind, vehicle::bounds,
};

use crate::{
    road_event_types::{RoadEvent, RoadEventSourceStatus, RoadEventWarning},
    routing::{
        CheckedRoute, Met,
        events::{EventHit, Freshness},
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
    /// waypoints.
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
    /// The engine found no road between the points.
    NoRoute,
    /// A point is too far from any road.
    OffNetwork,
    /// Roads exist, but each meets a limit the vehicle exceeds:
    /// `blockers` says which, and where.
    NoSafeRoute,
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
    /// Restrictions the vehicle passes with little margin (under 0.30 m of
    /// height, 0.20 m of width) or whose figure is unknown, in driving
    /// order.
    pub warnings: Vec<RouteWarning>,
    /// Road events met on the way that do not block it (lanes closed,
    /// works, a closure that could not be placed or whose source is stale,
    /// a single user's report), each at the time the vehicle gets there, in
    /// driving order.
    pub road_events: Vec<RoadEventWarning>,
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
            warnings: r.warnings.iter().map(RouteWarning::from).collect(),
            road_events: r
                .events
                .iter()
                .map(|h| road_event_warning(h, fresh, now))
                .collect(),
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

/// The area routes are computed in.
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
    /// The area routes are computed in.
    pub covered_area: CoveredArea,
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
