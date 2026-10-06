//! Guidance along one route, driven by the device's position fixes.
//!
//! Every call is synchronous: an update snaps one fix to the route and walks
//! a few steps, well under a millisecond, cheaper than a hop to a Rust
//! thread and back.

use flutter_rust_bridge::frb;

use crate::session::{self, Session};

/// A position fix of the device.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Fix {
    /// Latitude, WGS 84.
    pub lat: f64,
    /// Longitude, WGS 84.
    pub lon: f64,
    /// Radius of the confidence circle the platform reports, metres.
    pub accuracy_m: f64,
    /// Course over ground, degrees from north, when the device moves.
    pub course_deg: Option<f64>,
    /// Speed over ground, metres per second, when known.
    pub speed_mps: Option<f64>,
    /// When the fix was taken, milliseconds since the Unix epoch.
    pub timestamp_ms: i64,
}

/// The tolerances of the guidance.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GuidanceSettings {
    /// The vehicle is off the route beyond this distance from its line,
    /// metres.
    pub max_deviation_m: f64,
    /// A fix less precise than this, metres, never decides that the vehicle
    /// left the route or reached a maneuver: a fix in an urban canyon or a
    /// tunnel can be 50 m off.
    pub min_accuracy_m: u16,
    /// A step ends when the vehicle comes this close to its maneuver, then
    /// moves on past it, metres.
    pub maneuver_reached_m: u16,
    /// The trip ends this close to the destination, metres.
    pub arrival_m: u16,
}

impl Default for GuidanceSettings {
    fn default() -> Self {
        Self {
            // Ferrostar's own apps use 50 m; streets in a French town centre
            // run closer than that, and a motorhome that took the wrong one
            // should hear about it before the next junction.
            max_deviation_m: 40.0,
            min_accuracy_m: 30,
            maneuver_reached_m: 20,
            arrival_m: 20,
        }
    }
}

/// The settings the app starts with.
#[frb(sync)]
#[must_use]
pub fn default_guidance_settings() -> GuidanceSettings {
    GuidanceSettings::default()
}

/// Where the trip stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GuidanceStatus {
    /// On the way.
    Navigating,
    /// At the destination.
    Arrived,
}

/// One lane at the next intersection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lane {
    /// The directions it allows (`straight`, `left`, `slight right`...).
    pub directions: Vec<String>,
    /// Whether it leads where the route goes.
    pub active: bool,
}

/// What the banner shows.
#[derive(Debug, Clone, PartialEq)]
pub struct Banner {
    /// The main line: the road to take, or what to do.
    pub primary: String,
    /// A second line, when the router gave one.
    pub secondary: Option<String>,
    /// The maneuver, as the OSRM format names it (`turn`, `roundabout`,
    /// `arrive`...).
    pub maneuver_type: Option<String>,
    /// Its direction (`left`, `slight right`, `uturn`...).
    pub modifier: Option<String>,
    /// The exit of a roundabout, degrees, when the router gave it.
    pub roundabout_exit_degrees: Option<u16>,
    /// The lanes, when the router gave them.
    pub lanes: Vec<Lane>,
}

/// An instruction to speak.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Utterance {
    /// Stable for one instruction of one route: speak each once.
    pub id: String,
    /// Plain text.
    pub text: String,
    /// The same as SSML, when the router gave it.
    pub ssml: Option<String>,
}

/// The guidance after a fix.
#[derive(Debug, Clone, PartialEq)]
pub struct GuidanceState {
    /// Navigating or arrived.
    pub status: GuidanceStatus,
    /// The vehicle's position on the route, latitude.
    pub snapped_lat: f64,
    /// The vehicle's position on the route, longitude.
    pub snapped_lon: f64,
    /// The route's heading there, degrees from north.
    pub course_deg: Option<f64>,
    /// Index of the current step in the route's steps (OSRM order).
    pub step_index: u32,
    /// Metres to the next maneuver.
    pub distance_to_maneuver_m: f64,
    /// Metres to the destination.
    pub distance_remaining_m: f64,
    /// Seconds to the destination, at the router's speeds.
    pub duration_remaining_s: f64,
    /// Metres driven along the route: where a warning of the route lies
    /// ahead is its distance from the start minus this.
    pub distance_along_m: f64,
    /// Distance from the route line when the vehicle has left the route,
    /// metres; none while it follows it.
    pub off_route_m: Option<f64>,
    /// What the banner shows now.
    pub banner: Option<Banner>,
    /// The latest instruction to speak; the same one comes back until the
    /// next is due.
    pub utterance: Option<Utterance>,
    /// The speed limit where the vehicle is, km/h, when the map has it.
    pub speed_limit_kmh: Option<f64>,
}

/// A point.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LatLon {
    /// Latitude, WGS 84.
    pub lat: f64,
    /// Longitude, WGS 84.
    pub lon: f64,
}

/// A road event's shape, to check the route against.
#[derive(Debug, Clone, PartialEq)]
pub struct EventShape {
    /// The event's identifier, returned with its hits.
    pub id: String,
    /// One point, or the line of the road it covers.
    pub points: Vec<LatLon>,
    /// The line runs in the direction of traffic it concerns: only a route
    /// that follows it that way meets it (one carriageway of a dual road).
    pub directed: bool,
    /// For a point: the course of the traffic it concerns, degrees from
    /// north. A route that passes it on another course does not meet it.
    pub heading_deg: Option<f64>,
    /// How far the route's course may stray from [`EventShape::heading_deg`]:
    /// 60 degrees for a reported course, 100 for a cardinal direction.
    pub heading_tolerance_deg: f64,
}

/// Where the route ahead drives through an event.
#[derive(Debug, Clone, PartialEq)]
pub struct EventHit {
    /// The event.
    pub id: String,
    /// Metres from the start of the route where the route enters it.
    pub start_m: f64,
    /// Metres from the start where it leaves it.
    pub end_m: f64,
    /// Where the route enters it, latitude.
    pub lat: f64,
    /// Where the route enters it, longitude.
    pub lon: f64,
}

/// Why a guidance could not start.
///
/// A kind and a message rather than an enum with data: the bridge turns an
/// enum with fields into a `freezed` class, a dependency the app does not
/// otherwise need.
#[derive(Debug, thiserror::Error)]
#[error("{message}")]
pub struct GuidanceError {
    /// What went wrong.
    pub kind: GuidanceErrorKind,
    /// The details, for the log.
    pub message: String,
}

/// What went wrong when a guidance started.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GuidanceErrorKind {
    /// The route answer could not be read.
    InvalidRoute,
    /// The answer holds fewer routes than the index asked for.
    NoSuchRoute,
}

impl GuidanceError {
    pub(crate) fn invalid_route(message: impl Into<String>) -> Self {
        Self {
            kind: GuidanceErrorKind::InvalidRoute,
            message: message.into(),
        }
    }

    pub(crate) fn no_such_route(index: u32, count: u32) -> Self {
        Self {
            kind: GuidanceErrorKind::NoSuchRoute,
            message: format!("route {index} asked for, the answer has {count}"),
        }
    }
}

/// Guidance along one route of an answer of the `route` query.
///
/// Bound to that route: a recalculation builds a new one (Ferrostar's
/// controller has no outside trigger to change route).
pub struct Guidance {
    session: Session,
}

impl Guidance {
    /// Guidance along route `route_index` of `osrm_json`, the `osrmJson`
    /// field of the API's answer.
    ///
    /// # Errors
    ///
    /// [`GuidanceError`] when the answer cannot be read or has no such route.
    #[frb(sync)]
    pub fn new(
        osrm_json: String,
        route_index: u32,
        settings: GuidanceSettings,
    ) -> Result<Guidance, GuidanceError> {
        Ok(Self {
            session: Session::new(osrm_json.as_bytes(), route_index, settings)?,
        })
    }

    /// The guidance after `fix`.
    #[frb(sync)]
    pub fn update(&mut self, fix: Fix) -> GuidanceState {
        self.session.update(fix)
    }

    /// The route's length, metres, as the router measured it.
    #[frb(sync, getter)]
    #[must_use]
    pub fn route_length_m(&self) -> f64 {
        self.session.route_length_m()
    }

    /// How many steps the route has.
    #[frb(sync, getter)]
    #[must_use]
    pub fn step_count(&self) -> u32 {
        self.session.step_count()
    }

    /// Where the route, from `from_m` metres from its start onwards, meets
    /// each of `events`, in driving order. A line counts when the route
    /// follows it within `line_tolerance_m` (the server's corridor rule:
    /// along a road, not across it; one way only when it is directed); a
    /// point, when the route passes within `point_tolerance_m` of it.
    #[frb(sync)]
    #[must_use]
    pub fn events_ahead(
        &self,
        from_m: f64,
        events: Vec<EventShape>,
        line_tolerance_m: f64,
        point_tolerance_m: f64,
    ) -> Vec<EventHit> {
        session::events_ahead(
            self.session.line(),
            from_m,
            &events,
            line_tolerance_m,
            point_tolerance_m,
        )
    }
}
