//! Routing for motorhomes and vans: the vehicle's dimensions, the physical
//! limits of the road network, and the check of a computed route against
//! both.
//!
//! The routing engine (Valhalla, behind the API) already refuses most
//! restricted roads, but not all of them: it ignores limits mapped on nodes
//! (car park barriers), does not apply a limit to the first and last edge of
//! a route, and does not read every tag French mappers use
//! (`plan/research/07-navigation.md`, A.4). So every route is checked again
//! here, against every limit we know of, and the engine is asked again with
//! the conflicting places excluded:
//!
//! - [`vehicle`]: the profile the user enters, its bounds, typical presets;
//! - [`tags`]: how an OpenStreetMap value or access key reads for a
//!   motorhome, and the most-restrictive rule between two sources;
//! - [`restriction`]: a limit with its source, place and certainty, and what
//!   it means for one vehicle;
//! - [`record`]: a restriction as the graph build hands it to the database;
//! - [`polyline`]: the route geometry as the engine encodes it;
//! - [`corridor`]: which limits a route actually drives through, and where;
//! - [`coverage`]: the area the graph covers, the cuts of its extracts.

pub mod corridor;
pub mod coverage;
pub mod polyline;
pub mod record;
pub mod restriction;
pub mod tags;
pub mod vehicle;

pub use corridor::{
    Hit, Projection, RouteLine, exclusion_ring, heading, match_route, match_route_directed,
    turn_between,
};
pub use record::{InvalidRecord, RestrictionRecord};
pub use restriction::{
    Certainty, Finding, FindingKind, Restriction, RestrictionFeature, RestrictionKind,
    RestrictionSource, Severity, assess,
};
pub use vehicle::{
    InvalidVehicle, PRESETS, RoutingDimensions, TRAILER_PRESETS, Trailer, TrailerKind,
    TrailerPreset, VehicleInput, VehicleKind, VehiclePreset, VehicleProfile, legal_top_speed_kph,
    routing_dimensions,
};
