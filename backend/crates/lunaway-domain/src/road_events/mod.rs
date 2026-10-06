//! Road events: closures, works, lane restrictions, temporary vehicle
//! limits and detours, each bounded in time, from the open feeds (the DIR's
//! DATEX II, DiaLog, city and département datasets) and from the
//! community's reports (`plan/research/20-travaux-temps-reel.md`).
//!
//! The ingestion normalises every source into the same few facts; the route
//! check weighs them against a vehicle at the time it gets there:
//!
//! - [`schedule`]: when an event applies, named periods without hours
//!   included ("de nuit"), mapped wide and flagged as assumed;
//! - [`assess`]: what an event met on a route means for a vehicle at its
//!   arrival: blocking, a warning, or information;
//! - [`along`]: where a route meets an event that has no matched line: a
//!   slip road closure (never the main carriageway), a point on a numbered
//!   road, a community report;
//! - [`road`]: road numbers as the feeds and the engine write them;
//! - [`community`]: the rules of the users' reports.

pub mod along;
pub mod assess;
pub mod community;
pub mod road;
pub mod schedule;

use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};

pub use assess::{
    EventContext, EventFacts, EventFinding, EventReason, EventSeverity, LimitKind, assess,
};
pub use schedule::{Activity, Schedule, Window};

use crate::{Position, UnknownCode, taxonomy::coded_enum};

coded_enum! {
    /// What an event does to traffic.
    EventClass {
        /// The road, a carriageway or a slip road is closed to all.
        Closure => "closure",
        /// Works without a measure that stops a vehicle.
        Works => "works",
        /// A lane closed, alternating traffic, narrow lanes, a contraflow.
        LaneRestriction => "lane_restriction",
        /// A height, width, length or weight limit for a time.
        VehicleLimit => "vehicle_limit",
        /// A diversion is signposted or advised.
        Detour => "detour",
    }
}

coded_enum! {
    /// Which part of the road an event is on. A slip road event is located
    /// on the main road by the DIR feed (Cerema guide, part 1, section 7.1),
    /// and must never close the main carriageway.
    Carriageway {
        /// The main carriageway.
        Main => "main",
        /// An entry slip road.
        Entry => "entry",
        /// An exit slip road.
        Exit => "exit",
        /// Slip roads, entry and exit alike.
        Ramps => "ramps",
        /// Not stated.
        Unknown => "unknown",
    }
}

coded_enum! {
    /// The direction an event concerns: relative to the order of its
    /// source geometry's points, or a compass label the source gives for a
    /// point.
    EventDirection {
        /// Both directions.
        Both => "both",
        /// The direction of the geometry's points (a DIR section from its
        /// start to its end).
        Forward => "forward",
        /// Northbound.
        North => "north",
        /// Southbound.
        South => "south",
        /// Eastbound.
        East => "east",
        /// Westbound.
        West => "west",
        /// Not stated: both are concerned.
        Unknown => "unknown",
    }
}

impl EventDirection {
    /// The heading of a compass label, degrees from north.
    #[must_use]
    pub const fn compass_deg(self) -> Option<f64> {
        match self {
            Self::North => Some(0.0),
            Self::East => Some(90.0),
            Self::South => Some(180.0),
            Self::West => Some(270.0),
            Self::Both | Self::Forward | Self::Unknown => None,
        }
    }
}

coded_enum! {
    /// Whom a vehicle limit concerns.
    AppliesTo {
        /// Every vehicle (a B12 clearance, a B13 weight).
        All => "all",
        /// Heavy goods vehicles: a motorhome is not one, the limit warns.
        GoodsVehicles => "goods_vehicles",
    }
}

coded_enum! {
    /// How far an event is to be believed.
    Confidence {
        /// The record of an official source.
        Official => "official",
        /// One user reported it.
        Reported => "reported",
        /// Two users or more reported it.
        Confirmed => "confirmed",
    }
}

coded_enum! {
    /// How an event was placed on the routing graph.
    MatchQuality {
        /// Not tried yet.
        Pending => "pending",
        /// Lines of the graph, in driving order, one per direction.
        Matched => "matched",
        /// A slip road event: the route check finds the slip roads of the
        /// interchange from the route itself ([`along::ramp_hits`]).
        Ramp => "ramp",
        /// A point on a numbered road or a report: the route check finds it
        /// along the route ([`along::point_hit`]).
        Point => "point",
        /// Tried and failed: a warning at its own position, never a block.
        Unmatched => "unmatched",
    }
}

coded_enum! {
    /// Why an event ended.
    EndReason {
        /// The source said it ended (a DATEX end marker).
        SourceEnd => "source_end",
        /// It is missing from a complete snapshot of its source.
        Disappeared => "disappeared",
        /// No end date, and not seen for longer than the expiry.
        Expired => "expired",
        /// Its end date is past.
        PastEnd => "past_end",
        /// A user said it is over (community events).
        Cleared => "cleared",
        /// A moderator removed it.
        Moderated => "moderated",
    }
}

/// The vehicle limits of an event, for the vehicles it names.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct VehicleLimits {
    /// Height, metres.
    pub max_height_m: Option<f64>,
    /// Width, metres.
    pub max_width_m: Option<f64>,
    /// Length, metres.
    pub max_length_m: Option<f64>,
    /// Total authorised mass, tonnes.
    pub max_weight_t: Option<f64>,
    /// Whom they concern.
    pub applies_to: AppliesTo,
}

impl Default for VehicleLimits {
    fn default() -> Self {
        Self {
            max_height_m: None,
            max_width_m: None,
            max_length_m: None,
            max_weight_t: None,
            applies_to: AppliesTo::All,
        }
    }
}

impl VehicleLimits {
    /// Whether no figure is set.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.max_height_m.is_none()
            && self.max_width_m.is_none()
            && self.max_length_m.is_none()
            && self.max_weight_t.is_none()
    }
}

/// Whether two road numbers name the same road, once normalised
/// ([`road::normalize`]).
#[must_use]
pub fn same_road(a: &str, b: &str) -> bool {
    match (road::normalize(a), road::normalize(b)) {
        (Some(x), Some(y)) => x == y,
        _ => false,
    }
}

/// The geometry of an event as its source gives it.
#[derive(Debug, Clone, PartialEq)]
pub enum SourceGeometry {
    /// A point: a DIR point location, a user's report.
    Point(Position),
    /// Lines in the source's order: a DIR section from its start to its
    /// end (two points), DiaLog's street sections.
    Lines(Vec<Vec<Position>>),
    /// Areas, each by its outer ring: the works zones of some cities.
    Polygons(Vec<Vec<Position>>),
}

impl SourceGeometry {
    /// A point that stands for it: the point, the first point of the first
    /// line, the first vertex of the first ring.
    #[must_use]
    pub fn representative(&self) -> Option<Position> {
        match self {
            Self::Point(p) => Some(*p),
            Self::Lines(lines) | Self::Polygons(lines) => {
                lines.first().and_then(|l| l.first()).copied()
            }
        }
    }

    /// Whether it holds no point.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        match self {
            Self::Point(_) => false,
            Self::Lines(lines) | Self::Polygons(lines) => lines.iter().all(Vec::is_empty),
        }
    }
}
