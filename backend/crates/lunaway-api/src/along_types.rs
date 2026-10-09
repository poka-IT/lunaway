//! The GraphQL types of a search along a route (`alongRoute`): what to
//! look for, places or points of interest, and what lies along the route
//! ahead with the detour each adds.

use async_graphql::{InputObject, SimpleObject};

use crate::{
    external_types::ExternalPhoto,
    poi_types::{GqlPoiKind, Poi},
    routing_types::VehicleProfileInput,
    types::{GqlOvernightStatus, GqlPlaceKind, GqlService, LatLonInput, Place},
};

/// What to look for along a route: points of interest of some kinds,
/// places of some sort, or both.
#[derive(InputObject, Debug, Clone)]
pub struct AlongRouteInput {
    /// The route's line in driving order, as a polyline with six decimals,
    /// as `fuelAlongRoute` takes it (48 000 characters at most). Give
    /// `polyline` or `points`.
    pub polyline: Option<String>,
    /// The route's line as points, in driving order (at most 1 000).
    pub points: Option<Vec<LatLonInput>>,
    /// Points of interest of these kinds; none when absent or empty.
    pub poi_kinds: Option<Vec<GqlPoiKind>>,
    /// Places, those this takes; none when absent.
    pub places: Option<AlongRoutePlacesInput>,
    /// The longest detour accepted, kilometres there and back (0.5 to 30):
    /// what lies farther than half of it from the route is not looked at.
    #[graphql(default = 6.0)]
    pub max_detour_km: f64,
    /// What is reached within this many kilometres of the line's first
    /// point comes first (1 to 1 000): what is near, by the minutes it
    /// adds, then what is farther, the same way.
    #[graphql(default = 50.0)]
    pub near_km: f64,
    /// Items per page (1 to 20).
    #[graphql(default = 20)]
    pub limit: i32,
    /// `next` of the page before, with the same input; null for the first
    /// page.
    pub after: Option<String>,
    /// The vehicle: the detours are measured on the roads it may drive, and
    /// a place whose stated limit (height, width, length, weight) it
    /// exceeds is left out. A car's limits otherwise.
    pub vehicle: Option<VehicleProfileInput>,
}

/// Which places a search along a route takes: every part given must hold.
#[derive(InputObject, Debug, Clone, Default)]
pub struct AlongRoutePlacesInput {
    /// Only these overnight statuses (any when absent; not empty).
    pub overnight: Option<Vec<GqlOvernightStatus>>,
    /// Only these kinds (any when absent; not empty).
    pub kinds: Option<Vec<GqlPlaceKind>>,
    /// At least one of these services (no condition when absent or empty):
    /// water or a dump station, for instance.
    pub any_service: Option<Vec<GqlService>>,
}

/// What reaching an item off the route adds to the trip.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct AlongRouteDetour {
    /// Kilometres more than the route, there and back.
    pub km: f64,
    /// Minutes more than the route.
    pub minutes: f64,
    /// Measured by the routing engine; an estimate from the straight line
    /// otherwise (the engine refused, was busy, is not set up, or did not
    /// answer in time).
    pub measured: bool,
}

/// A place or a point of interest along the route.
#[derive(SimpleObject)]
pub struct AlongRouteItem {
    /// Kilometres from the line's first point to where the item is
    /// reached.
    pub along_km: f64,
    /// Metres from the route, in a straight line.
    pub distance_m: f64,
    /// What reaching it adds.
    pub detour: AlongRouteDetour,
    /// The place, when the item is one.
    pub place: Option<Place>,
    /// The point of interest, when the item is one.
    pub poi: Option<Poi>,
    /// For a place, a photo of another source than Lunaway's community:
    /// the partner's newest, else an open source's photo of the place
    /// itself or facing it, as its card shows them first
    /// (`Place.externalPhotos`, which also reads the places merged into it
    /// and the surroundings); show it with its source. Null without one;
    /// the community's own are in `place.coverPhotos`.
    pub photo: Option<ExternalPhoto>,
}

/// A page of what lies along a route.
#[derive(SimpleObject)]
pub struct AlongRoute {
    /// The page, in the order of `nearKm`: what is near by the minutes it
    /// adds, then what is farther. The detours of a page are measured
    /// together, which may reorder it; an item whose measured detour
    /// exceeds `maxDetourKm`, or that no road reaches, is left out, so a
    /// page may hold fewer items than `limit`, none even while `next`
    /// leads on.
    pub items: Vec<AlongRouteItem>,
    /// The route's length, kilometres.
    pub route_km: f64,
    /// How far along the line the search read, kilometres from its first
    /// point: at most 1 000.
    pub searched_km: f64,
    /// Candidates within half the detour of the line, all pages together.
    pub candidates: i32,
    /// Pass it as `after`, with the same input, for the next page; null on
    /// the last.
    pub next: Option<String>,
    /// Whether every detour of the page was measured by the routing
    /// engine; false on an empty page.
    pub detours_measured: bool,
}
