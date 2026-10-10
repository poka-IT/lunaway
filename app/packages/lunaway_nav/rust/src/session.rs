//! The guidance logic behind [`crate::api::engine`]: Ferrostar's
//! controller over one route, its state between fixes, and the translation
//! of its trip state into what the app shows and says.

use std::sync::Arc;
use std::time::{Duration, SystemTime};

use ferrostar::deviation_detection::{DeviationKind, RouteDeviation, RouteDeviationTracking};
use ferrostar::models::{
    CourseOverGround, GeographicCoordinate, Route, Speed, UserLocation, VisualInstruction,
};
use ferrostar::navigation_controller::models::{
    CourseFiltering, NavState, NavigationControllerConfig, TripState, WaypointAdvanceMode,
};
use ferrostar::navigation_controller::step_advance::conditions::ManualStepCondition;
use ferrostar::navigation_controller::{Navigator, create_navigator};
use ferrostar::routing_adapters::RouteResponseParser;
use ferrostar::routing_adapters::osrm::OsrmResponseParser;
use lunaway_domain::Position;
use lunaway_domain::routing::{RouteLine, match_route};
use serde::Serialize;

use crate::api::engine::{
    Banner, EventHit, EventShape, Fix, GuidanceError, GuidanceSettings, GuidanceState,
    GuidanceStatus, Lane, Utterance,
};
use crate::track::{Motion, StepTrack};

/// Valhalla writes its shapes with six decimals (`shape_format: polyline6`).
const POLYLINE_PRECISION: u32 = 6;

/// A waypoint counts as visited within this distance, metres.
const WAYPOINT_RANGE_M: f64 = 100.0;

/// One guidance: the controller, the state it returned last, the route's
/// line for the event check, and its steps laid along one line, which
/// decide when a step ends.
pub struct Session {
    navigator: Arc<dyn Navigator>,
    state: Option<NavState>,
    route: Route,
    line: RouteLine,
    track: StepTrack,
    /// The step Ferrostar is on, counted as [`Session::follow`] moves it:
    /// only that moves it. The step count once the trip is over.
    step: usize,
    settings: GuidanceSettings,
}

impl Session {
    /// A session along route `index` of an OSRM answer.
    ///
    /// # Errors
    ///
    /// [`GuidanceError`] when the answer cannot be read or has no such route.
    pub fn new(
        osrm_json: &[u8],
        index: u32,
        settings: GuidanceSettings,
    ) -> Result<Self, GuidanceError> {
        let mut routes = OsrmResponseParser::new(POLYLINE_PRECISION)
            .parse_response(osrm_json.to_vec())
            .map_err(|e| GuidanceError::invalid_route(e.to_string()))?;
        let count = u32::try_from(routes.len()).unwrap_or(u32::MAX);
        if index >= count {
            return Err(GuidanceError::no_such_route(index, count));
        }
        let route = routes.swap_remove(index as usize);
        let points: Vec<Position> = route
            .geometry
            .iter()
            .filter_map(|c| Position::new(c.lat, c.lng).ok())
            .collect();
        if points.len() != route.geometry.len() {
            return Err(GuidanceError::invalid_route(
                "a point of the route is out of range",
            ));
        }
        let line = RouteLine::new(points)
            .ok_or_else(|| GuidanceError::invalid_route("the route has no line"))?
            .with_legs(&leg_lengths(osrm_json, index as usize));
        let track = StepTrack::new(&route.steps).ok_or_else(|| {
            GuidanceError::invalid_route("the steps hold no line, or a point out of range")
        })?;
        let navigator = create_navigator(route.clone(), config(settings), false);
        Ok(Self {
            navigator,
            state: None,
            route,
            line,
            track,
            step: 0,
            settings,
        })
    }

    /// The route's length, metres, as the router measured it.
    #[must_use]
    pub fn route_length_m(&self) -> f64 {
        self.route.distance
    }

    /// How many steps the route has.
    #[must_use]
    pub fn step_count(&self) -> u32 {
        u32::try_from(self.route.steps.len()).unwrap_or(u32::MAX)
    }

    /// The route's line, indexed for the corridor rule.
    #[must_use]
    pub fn line(&self) -> &RouteLine {
        &self.line
    }

    /// Feeds `fix` to the controller and returns what the app shows.
    pub fn update(&mut self, fix: Fix) -> GuidanceState {
        let location = user_location(fix);
        let next = match self.state.take() {
            None => self.navigator.get_initial_state(location),
            Some(state) => self.navigator.update_user_location(location, state),
        };
        let next = self.follow(next, location, fix);
        let shown = self.describe(&next.trip_state(), fix);
        self.state = Some(next);
        shown
    }

    /// Moves Ferrostar on to the step the vehicle is in: the fix is placed
    /// along the route ([`StepTrack::place`]), and every step it lies
    /// [`GuidanceSettings::maneuver_left_m`] past the end of ends, several
    /// at once after a jump; the trip ends within the arrival distance of
    /// its end. A fix off the route, or too vague, moves nothing:
    /// Ferrostar's deviation check tells the first, and the app asks for a
    /// new route.
    fn follow(&mut self, state: NavState, location: UserLocation, fix: Fix) -> NavState {
        let total = self.route.steps.len();
        let current = self.step;
        if current >= total {
            return state;
        }
        // Never on a vague fix: one in an urban canyon or a tunnel can be
        // 50 m off. A negative accuracy is iOS's mark of a fix whose
        // coordinates are not valid.
        let precise =
            fix.accuracy_m >= 0.0 && fix.accuracy_m <= f64::from(self.settings.min_accuracy_m);
        if !precise {
            return state;
        }
        let Ok(p) = Position::new(fix.lat, fix.lon) else {
            return state;
        };
        let track = &mut self.track;
        let motion = Motion {
            speed_mps: fix.speed_mps,
            course_deg: fix.course_deg,
        };
        let Some(placed) = track.place(
            p,
            fix.timestamp_ms,
            motion,
            current,
            self.settings.max_deviation_m,
        ) else {
            return state;
        };
        let target = if placed.along_m >= track.length_m() - f64::from(self.settings.arrival_m) {
            total
        } else {
            track.step_at(placed.along_m, f64::from(self.settings.maneuver_left_m))
        };
        if target <= current {
            return state;
        }
        let mut state = state;
        while self.step < target {
            // A step at a time; past the last one, the trip is complete.
            state = self.navigator.advance_to_next_step(state);
            self.step += 1;
            if self.step >= total {
                return state;
            }
        }
        // Once more on the step reached: the vehicle snapped to it, and
        // whether it left the route judged against the steps now ahead.
        self.navigator.update_user_location(location, state)
    }

    fn describe(&self, trip: &TripState, fix: Fix) -> GuidanceState {
        match trip {
            TripState::Navigating {
                snapped_user_location,
                remaining_steps,
                progress,
                deviation,
                visual_instruction,
                spoken_instruction,
                annotation_json,
                ..
            } => {
                let total = self.route.steps.len();
                let step_index = total.saturating_sub(remaining_steps.len());
                GuidanceState {
                    status: GuidanceStatus::Navigating,
                    snapped_lat: snapped_user_location.coordinates.lat,
                    snapped_lon: snapped_user_location.coordinates.lng,
                    course_deg: snapped_user_location
                        .course_over_ground
                        .map(|c| f64::from(c.degrees)),
                    step_index: u32::try_from(step_index).unwrap_or(u32::MAX),
                    distance_to_maneuver_m: progress.distance_to_next_maneuver,
                    distance_remaining_m: progress.distance_remaining,
                    duration_remaining_s: progress.duration_remaining,
                    distance_along_m: (self.route.distance - progress.distance_remaining).max(0.0),
                    off_route_m: off_route(*deviation),
                    banner: visual_instruction.as_ref().map(banner),
                    utterance: spoken_instruction.as_ref().map(|s| Utterance {
                        id: s.utterance_id.to_string(),
                        text: s.text.clone(),
                        ssml: s.ssml.clone(),
                    }),
                    speed_limit_kmh: annotation_json.as_deref().and_then(speed_limit_kmh),
                }
            }
            // A route always has a first step, so Idle only comes from an
            // empty route, which the parser refuses; it reads as arrived.
            TripState::Complete { user_location, .. } => arrived(self, *user_location),
            TripState::Idle { .. } => arrived(self, user_location(fix)),
        }
    }
}

fn arrived(session: &Session, at: UserLocation) -> GuidanceState {
    GuidanceState {
        status: GuidanceStatus::Arrived,
        snapped_lat: at.coordinates.lat,
        snapped_lon: at.coordinates.lng,
        course_deg: at.course_over_ground.map(|c| f64::from(c.degrees)),
        step_index: session.step_count().saturating_sub(1),
        distance_to_maneuver_m: 0.0,
        distance_remaining_m: 0.0,
        duration_remaining_s: 0.0,
        distance_along_m: session.route.distance,
        off_route_m: None,
        banner: None,
        utterance: None,
        speed_limit_kmh: None,
    }
}

/// The controller's configuration for a motorhome on French roads.
fn config(settings: GuidanceSettings) -> NavigationControllerConfig {
    NavigationControllerConfig {
        waypoint_advance: WaypointAdvanceMode::WaypointWithinRange(WAYPOINT_RANGE_M),
        // The session ends the steps (`Session::follow`): Ferrostar's own
        // advance waits for a fix close to a step's last point, which fixes
        // far apart or a jump of the position may never give.
        step_advance_condition: Arc::new(ManualStepCondition),
        arrival_step_advance_condition: Arc::new(ManualStepCondition),
        route_deviation_tracking: RouteDeviationTracking::StaticThreshold {
            minimum_horizontal_accuracy: settings.min_accuracy_m,
            max_acceptable_deviation: settings.max_deviation_m,
        },
        // The map turns with the road, not with every wobble of the GPS
        // course.
        snapped_location_course_filtering: CourseFiltering::SnapToRoute,
    }
}

fn user_location(fix: Fix) -> UserLocation {
    let millis = u64::try_from(fix.timestamp_ms).unwrap_or(0);
    UserLocation {
        coordinates: GeographicCoordinate {
            lat: fix.lat,
            lng: fix.lon,
        },
        horizontal_accuracy: fix.accuracy_m.max(0.0),
        course_over_ground: fix
            .course_deg
            .filter(|c| c.is_finite())
            .map(|c| CourseOverGround {
                #[allow(
                    clippy::cast_possible_truncation,
                    clippy::cast_sign_loss,
                    reason = "a course normalised to 0..360"
                )]
                degrees: c.rem_euclid(360.0).round() as u16 % 360,
                accuracy: None,
            }),
        timestamp: SystemTime::UNIX_EPOCH + Duration::from_millis(millis),
        speed: fix
            .speed_mps
            .filter(|s| s.is_finite() && *s >= 0.0)
            .map(|value| Speed {
                value,
                accuracy: None,
            }),
    }
}

fn off_route(deviation: RouteDeviation) -> Option<f64> {
    match deviation {
        RouteDeviation::Deviation {
            kind:
                DeviationKind::CompletelyOffRoute {
                    deviation_from_route_line,
                },
        } => Some(deviation_from_route_line),
        _ => None,
    }
}

fn banner(v: &VisualInstruction) -> Banner {
    let lanes = v
        .sub_content
        .as_ref()
        .and_then(|s| s.lane_info.as_ref())
        .or(v.primary_content.lane_info.as_ref())
        .map(|lanes| {
            lanes
                .iter()
                .map(|l| Lane {
                    directions: l.directions.clone(),
                    active: l.active,
                })
                .collect()
        })
        .unwrap_or_default();
    Banner {
        primary: v.primary_content.text.clone(),
        secondary: v.secondary_content.as_ref().map(|s| s.text.clone()),
        maneuver_type: v.primary_content.maneuver_type.and_then(serde_code),
        modifier: v.primary_content.maneuver_modifier.and_then(serde_code),
        roundabout_exit_degrees: v.primary_content.roundabout_exit_degrees,
        lanes,
    }
}

/// The name the OSRM format gives a value (`slight left`, `end of road`).
fn serde_code<T: Serialize>(value: T) -> Option<String> {
    match serde_json::to_value(value) {
        Ok(serde_json::Value::String(s)) => Some(s),
        _ => None,
    }
}

/// The speed limit in an OSRM annotation of one segment
/// (`{"maxspeed": {"speed": 50, "unit": "km/h"}}`), km/h.
fn speed_limit_kmh(annotation: &str) -> Option<f64> {
    let value: serde_json::Value = serde_json::from_str(annotation).ok()?;
    let max = value.get("maxspeed")?;
    let speed = max.get("speed")?.as_f64()?;
    match max.get("unit").and_then(serde_json::Value::as_str) {
        Some("mph") => Some(speed * 1.609_344),
        _ => Some(speed),
    }
}

/// The lengths of the legs of route `index`, metres, as the router reports
/// them; empty when the answer does not say.
fn leg_lengths(osrm_json: &[u8], index: usize) -> Vec<f64> {
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(osrm_json) else {
        return Vec::new();
    };
    value
        .get("routes")
        .and_then(|r| r.get(index))
        .and_then(|r| r.get("legs"))
        .and_then(serde_json::Value::as_array)
        .map(|legs| {
            legs.iter()
                .filter_map(|l| l.get("distance").and_then(serde_json::Value::as_f64))
                .collect()
        })
        .unwrap_or_default()
}

/// Where the route from `from_m` metres onwards drives through each event,
/// in driving order.
#[must_use]
pub fn events_ahead(
    line: &RouteLine,
    from_m: f64,
    events: &[EventShape],
    line_tolerance_m: f64,
    point_tolerance_m: f64,
) -> Vec<EventHit> {
    let mut hits: Vec<EventHit> = Vec::new();
    for event in events {
        let shape: Vec<Position> = event
            .points
            .iter()
            .filter_map(|p| Position::new(p.lat, p.lon).ok())
            .collect();
        let found: Vec<(f64, f64, Position)> = match shape.as_slice() {
            [] => Vec::new(),
            // A point event (a closed slip road placed on its axis, a
            // report): the route passes by it, as the server's point rule
            // says, farther than the corridor's 2 m for a mapped node.
            [point] => nearest_on_route(line, *point, from_m, point_tolerance_m)
                .filter(|s| {
                    event.heading_deg.is_none_or(|h| {
                        angle_between(course_at(line, *s), h) <= event.heading_tolerance_deg
                    })
                })
                .map(|s| vec![(s, s, line.point_at(s))])
                .unwrap_or_default(),
            _ => match_route(line, &shape, line_tolerance_m)
                .into_iter()
                .filter(|h| !event.directed || same_way(line, &shape, h.start_m, h.end_m))
                .map(|h| (h.start_m, h.end_m, h.at))
                .collect(),
        };
        // An event the vehicle is inside of still lies ahead: its end does.
        hits.extend(found.into_iter().filter(|(_, end, _)| *end >= from_m).map(
            |(start, end, at)| EventHit {
                id: event.id.clone(),
                start_m: start,
                end_m: end,
                lat: at.lat(),
                lon: at.lon(),
            },
        ));
    }
    hits.sort_by(|a, b| a.start_m.total_cmp(&b.start_m));
    hits
}

/// The route's course at `at_m` metres from its start, degrees from north,
/// over the ten metres around it.
fn course_at(line: &RouteLine, at_m: f64) -> f64 {
    let (east, north) = offset(
        line.point_at((at_m - 5.0).max(0.0)),
        line.point_at(at_m + 5.0),
    );
    east.atan2(north).to_degrees().rem_euclid(360.0)
}

/// The smaller angle between two courses, 0 to 180 degrees.
fn angle_between(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

/// Metres east and north of `b` from `a`, on a plane tangent at `a`.
fn offset(a: Position, b: Position) -> (f64, f64) {
    const M_PER_DEG: f64 = 6_371_008.8 * std::f64::consts::PI / 180.0;
    (
        (b.lon() - a.lon()) * M_PER_DEG * a.lat().to_radians().cos(),
        (b.lat() - a.lat()) * M_PER_DEG,
    )
}

/// The distance from the start of the route of its point nearest to `p`,
/// from `from_m` onwards, when that point is within `max_m` of `p`.
fn nearest_on_route(line: &RouteLine, p: Position, from_m: f64, max_m: f64) -> Option<f64> {
    let points = line.points();
    let mut along = 0.0;
    let mut best: Option<(f64, f64)> = None;
    for pair in points.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        let length = a.distance_m(b);
        if along + length >= from_m {
            let (ax, ay) = offset(p, a);
            let (bx, by) = offset(p, b);
            let (dx, dy) = (bx - ax, by - ay);
            let len2 = dx * dx + dy * dy;
            let t = if len2 > 0.0 {
                (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let d = (ax + t * dx).hypot(ay + t * dy);
            let s = along + t * length;
            if d <= max_m && s >= from_m && best.is_none_or(|(_, bd)| d < bd) {
                best = Some((s, d));
            }
        }
        along += length;
    }
    best.map(|(s, _)| s)
}

/// Whether the route, between `start_m` and `end_m`, runs along `shape` in
/// the shape's direction: the shape's first point projects nearer the
/// route's start than its last.
fn same_way(line: &RouteLine, shape: &[Position], start_m: f64, end_m: f64) -> bool {
    let (Some(first), Some(last)) = (shape.first(), shape.last()) else {
        return true;
    };
    // Ten metres either side of the stretch the route follows.
    let window = (start_m - 10.0).max(0.0);
    let reach = end_m - window + 10.0 + 200.0;
    let at = |p: Position| nearest_on_route(line, p, window, reach.max(50.0));
    match (at(*first), at(*last)) {
        (Some(a), Some(b)) => b >= a,
        // An end of the shape far from the route: judge on the stretch the
        // route follows, by the shape's own heading against the route's.
        _ => {
            let (sx, sy) = offset(*first, *last);
            let (rx, ry) = offset(
                line.point_at(start_m),
                line.point_at(end_m.max(start_m + 1.0)),
            );
            sx * rx + sy * ry >= 0.0
        }
    }
}
