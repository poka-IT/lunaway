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
//! - [`corridor`]: which limits a route actually drives through, and where.

pub mod corridor;
pub mod polyline;
pub mod record;
pub mod restriction;
pub mod tags;
pub mod vehicle;

pub use corridor::{Hit, RouteLine, exclusion_ring, match_route};
pub use record::{InvalidRecord, RestrictionRecord};
pub use restriction::{
    Certainty, Finding, FindingKind, Restriction, RestrictionFeature, RestrictionKind,
    RestrictionSource, Severity, assess,
};
pub use vehicle::{
    InvalidVehicle, PRESETS, RoutingDimensions, TRAILER_PRESETS, Trailer, TrailerKind,
    TrailerPreset, VehicleInput, VehicleKind, VehiclePreset, VehicleProfile, routing_dimensions,
};

use crate::{BBox, Position};

/// The area the routing graph covers: metropolitan France and Corsica with
/// a margin, the same box the OpenStreetMap import keeps
/// (`lunaway-ingest`, `osm_extract::AREA`). A point outside is refused
/// before the engine is asked.
///
/// # Panics
///
/// Never: the edges are constants inside the WGS 84 range.
#[must_use]
pub fn covered_area() -> BBox {
    #[allow(
        clippy::expect_used,
        reason = "constant edges, checked by the tests of this module"
    )]
    BBox::new(41.0, -5.8, 51.6, 10.0).expect("the covered area is a valid box")
}

/// Whether the routing graph covers `p`.
#[must_use]
pub fn is_covered(p: Position) -> bool {
    covered_area().contains(p)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_covered_area_holds_france_and_corsica_only() {
        let at = |lat, lon| Position::new(lat, lon).unwrap();
        assert!(is_covered(at(45.8472, 1.2848)), "Limoges");
        assert!(is_covered(at(41.92, 8.74)), "Ajaccio");
        assert!(is_covered(at(51.03, 2.37)), "Dunkerque");
        assert!(!is_covered(at(40.42, -3.70)), "Madrid");
        assert!(!is_covered(at(52.52, 13.40)), "Berlin");
    }
}
