//! Where the vehicle is along the route, step by step, from its fixes.
//!
//! Ferrostar's own step advance ends a step once a fix comes close to the
//! step's last point, in a straight line, and a later fix lies a few metres
//! off the step's line. Both halves fail on a real drive. A fix that never
//! comes that close leaves the step current for good: at 25 m/s with a fix
//! a second the fixes are 25 m apart, and a step of 7 m (Valhalla gives
//! such steps between two close forks) is passed between two of them;
//! after a jump of the position (out of a tunnel, a browser placed anew)
//! no fix comes back to it either. The vehicle then lies on a later step,
//! which Ferrostar counts as on the route: no step, no instruction, no new
//! route, "0 m" on the screen while the vehicle drives on. And a fix a few
//! metres beside a small roundabout, its exit close to its entry, ends the
//! roundabout before the vehicle is in it.
//!
//! [`StepTrack`] lays the steps end to end on one line and places each
//! precise fix on it where the drive since the last fix leads: the point of
//! the line nearest the fix, weighed against the distance the vehicle's
//! speed covered, so that a part of the route that runs back beside itself
//! (the far side of a roundabout, the other leg of a hairpin) does not draw
//! the vehicle onto it. The session ends every step the vehicle is past.

use ferrostar::models::RouteStep;
use lunaway_domain::Position;
use lunaway_domain::routing::RouteLine;

/// A fix may land this far ahead of the last one placed, beyond what the
/// fastest drive covers in the time between them: GPS noise, and a fix
/// placed a little behind the vehicle the time before, metres.
const REACH_MARGIN_M: f64 = 40.0;

/// The fastest a vehicle is taken to drive between two fixes, metres per
/// second (252 km/h, twice a motorhome's top speed; the app's bound on a
/// speed worked out between two fixes). Farther than that in the time
/// between them, a fix has jumped.
const MAX_SPEED_MPS: f64 = 70.0;

/// How far the first fix of a route may lie from its start along it,
/// metres: the route starts where the vehicle was when it was asked for,
/// a few seconds ago.
const FIRST_REACH_M: f64 = 1_000.0;

/// How far behind the last place a fix may land, metres: GPS noise along
/// the road, and a vehicle that backs up a little.
const BACK_M: f64 = 50.0;

/// A place reached by a jump stands once a second fix lands near it, this
/// many metres behind it at most, as far ahead as a drive from there goes:
/// one wild fix near the route ahead does not skip its steps.
const CONFIRM_BACK_M: f64 = 40.0;

/// Where the drive leads, from the speed of the fix: within this distance,
/// metres, and this share of the distance driven, a point of the line is
/// as likely as any other.
const SLACK_M: f64 = 15.0;
const SLACK_SHARE: f64 = 0.5;

/// Beyond that slack, each metre between a point of the line and where the
/// drive leads, ahead of it or behind, counts as this many metres off the
/// line: a point 100 m ahead of the vehicle's speed has to lie 40 m nearer
/// the fix than the road the vehicle is on to be taken for it.
const LEAD_WEIGHT: f64 = 0.5;

/// A course counts from this speed on, metres per second: below it a GPS
/// course wanders.
const COURSE_SPEED_MPS: f64 = 3.0;

/// A stretch of the line that runs against the vehicle's course by more
/// than this, degrees, is not where the vehicle drives: the other leg of a
/// hairpin, the other carriageway the route takes back later.
const AGAINST_DEG: f64 = 90.0;

/// The cost of a stretch run against the course, as metres off the line:
/// as far as a fix may lie from the line, so any stretch run the vehicle's
/// way within reach comes first.
const AGAINST_M: f64 = 40.0;

/// How the vehicle moves at a fix, as far as the fix says.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Motion {
    /// Metres per second.
    pub speed_mps: Option<f64>,
    /// Course over ground, degrees from north.
    pub course_deg: Option<f64>,
}

impl Motion {
    fn speed(self) -> Option<f64> {
        self.speed_mps.filter(|v| v.is_finite() && *v >= 0.0)
    }

    /// The course, when the vehicle moves fast enough for it to count.
    fn course(self) -> Option<f64> {
        let fast = self.speed().is_none_or(|v| v >= COURSE_SPEED_MPS);
        self.course_deg.filter(|c| c.is_finite() && fast)
    }

    /// Whether a stretch heading `heading_deg` runs against the course.
    fn against(self, heading_deg: f64) -> bool {
        self.course()
            .is_some_and(|c| angle_between(c, heading_deg) > AGAINST_DEG)
    }
}

/// Where a fix lies along the route.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Placed {
    /// Metres from the start of the steps' line.
    pub along_m: f64,
    /// Metres from the fix to the line.
    pub distance_m: f64,
}

/// A place along the line, and the time of the fix placed there.
#[derive(Debug, Clone, Copy)]
struct Mark {
    along_m: f64,
    at_ms: i64,
}

impl Mark {
    /// Seconds from this mark to a fix taken at `at_ms`.
    fn seconds_to(self, at_ms: i64) -> f64 {
        #[allow(
            clippy::cast_precision_loss,
            reason = "milliseconds between two fixes, far below 2^52"
        )]
        let ms = at_ms.saturating_sub(self.at_ms).max(0) as f64;
        ms / 1_000.0
    }

    /// How far ahead of this mark a fix taken at `at_ms` may lie.
    fn reach_m(self, at_ms: i64) -> f64 {
        REACH_MARGIN_M + MAX_SPEED_MPS * self.seconds_to(at_ms)
    }
}

/// The steps of a route laid end to end, and the vehicle's place along
/// them.
pub struct StepTrack {
    line: RouteLine,
    /// Where each step ends, metres from the start of [`Self::line`].
    ends: Vec<f64>,
    /// The last fix placed within reach of the one before.
    placed: Option<Mark>,
    /// A fix placed beyond reach, waiting for a second one.
    jumped: Option<Mark>,
}

impl StepTrack {
    /// The track of `steps`, in driving order; none when they hold fewer
    /// than two distinct points or a point out of range.
    #[must_use]
    pub fn new(steps: &[RouteStep]) -> Option<Self> {
        let mut points: Vec<Position> = Vec::new();
        let mut ends = Vec::with_capacity(steps.len());
        let mut along = 0.0;
        for step in steps {
            for c in &step.geometry {
                let p = Position::new(c.lat, c.lng).ok()?;
                if let Some(last) = points.last() {
                    // Two steps share the point between them, and an arrival
                    // step is that point twice.
                    if *last == p {
                        continue;
                    }
                    along += last.distance_m(p);
                }
                points.push(p);
            }
            ends.push(along);
        }
        Some(Self {
            line: RouteLine::new(points)?,
            ends,
            placed: None,
            jumped: None,
        })
    }

    /// Where step `index` starts, metres along the line.
    #[must_use]
    pub fn start_of(&self, index: usize) -> f64 {
        index
            .checked_sub(1)
            .and_then(|i| self.ends.get(i))
            .copied()
            .unwrap_or(0.0)
    }

    /// The line's length, metres.
    #[must_use]
    pub fn length_m(&self) -> f64 {
        self.line.length_m()
    }

    /// The step `along_m` metres from the start lies in, a step counting as
    /// left `past_m` metres after its end; the step count once past the
    /// last.
    #[must_use]
    pub fn step_at(&self, along_m: f64, past_m: f64) -> usize {
        self.ends.partition_point(|end| end + past_m <= along_m)
    }

    /// Places a fix at `p`, taken at `at_ms` while moving as `motion`
    /// says, on the steps from `first` on, within `max_m` of the line.
    /// Within the stretch the vehicle may have driven since the last fix
    /// placed, the point nearest the fix, weighed against where the drive
    /// leads and against a stretch run the other way; beyond that stretch,
    /// the nearest point farther on, run the vehicle's way, which stands
    /// once a second fix lands where the drive from it leads. None for a
    /// fix off the steps ahead, or whose jump is not confirmed yet.
    pub fn place(
        &mut self,
        p: Position,
        at_ms: i64,
        motion: Motion,
        first: usize,
        max_m: f64,
    ) -> Option<Placed> {
        let start = self.start_of(first);
        let speed = motion.speed();
        let (from, to, lead) = match self.placed {
            Some(mark) => {
                let from = (mark.along_m - BACK_M).max(start);
                let to = mark.along_m.max(start) + mark.reach_m(at_ms);
                // Without a speed, no lead: the nearest point of the reach.
                let lead = speed.map(|v| {
                    let driven = v * mark.seconds_to(at_ms);
                    (mark.along_m + driven, SLACK_M + SLACK_SHARE * driven)
                });
                (from, to, lead)
            }
            None => (start, start + FIRST_REACH_M, None),
        };
        if let Some(near) = self.best(p, max_m, from, to, lead, motion) {
            self.placed = Some(Mark {
                along_m: near.along_m,
                at_ms,
            });
            self.jumped = None;
            return Some(near);
        }
        let far = self.line.project_within(p, max_m, to, f64::INFINITY)?;
        if motion.against(far.heading_deg) {
            return None;
        }
        let confirmed = self.jumped.is_some_and(|mark| {
            let driven = speed.map_or(0.0, |v| v * mark.seconds_to(at_ms));
            far.along_m >= mark.along_m + driven - CONFIRM_BACK_M
                && far.along_m <= mark.along_m + mark.reach_m(at_ms)
        });
        let mark = Mark {
            along_m: far.along_m,
            at_ms,
        };
        if confirmed {
            self.placed = Some(mark);
            self.jumped = None;
            Some(Placed {
                along_m: far.along_m,
                distance_m: far.distance_m,
            })
        } else {
            self.jumped = Some(mark);
            None
        }
    }

    /// The point of the line between `from_m` and `to_m` that best places
    /// `p`: within `max_m` of it, the least distance to it, plus
    /// [`LEAD_WEIGHT`] for each metre beyond the slack around the place the
    /// drive leads to (`lead`: that place and its slack), plus [`AGAINST_M`]
    /// on a stretch run against the course.
    fn best(
        &self,
        p: Position,
        max_m: f64,
        from_m: f64,
        to_m: f64,
        lead: Option<(f64, f64)>,
        motion: Motion,
    ) -> Option<Placed> {
        let points = self.line.points();
        let along = self.line.along();
        let first = self.line.index_at(from_m);
        let plane = Plane::at(p);
        let mut best: Option<(f64, Placed)> = None;
        for i in first..points.len().saturating_sub(1) {
            if along[i] > to_m {
                break;
            }
            let span = along[i + 1] - along[i];
            let (t0, t1) = if span > 0.0 {
                (
                    ((from_m - along[i]) / span).clamp(0.0, 1.0),
                    ((to_m - along[i]) / span).clamp(0.0, 1.0),
                )
            } else {
                (0.0, 1.0)
            };
            let (ax, ay) = plane.of(points[i]);
            let (bx, by) = plane.of(points[i + 1]);
            let (dx, dy) = (bx - ax, by - ay);
            let len2 = dx * dx + dy * dy;
            let t = if len2 > 0.0 {
                (-(ax * dx + ay * dy) / len2).clamp(t0, t1)
            } else {
                t0
            };
            let distance_m = (ax + t * dx).hypot(ay + t * dy);
            if distance_m > max_m {
                continue;
            }
            let along_m = along[i] + t * span;
            let against = len2 > 0.0 && motion.against(dx.atan2(dy).to_degrees());
            let score = distance_m
                + lead.map_or(0.0, |(at, slack)| {
                    LEAD_WEIGHT * ((along_m - at).abs() - slack).max(0.0)
                })
                + if against { AGAINST_M } else { 0.0 };
            if best.is_none_or(|(s, _)| score < s) {
                best = Some((
                    score,
                    Placed {
                        along_m,
                        distance_m,
                    },
                ));
            }
        }
        best.map(|(_, placed)| placed)
    }
}

/// A plane tangent to the earth at a point, in metres east and north of it:
/// the few hundred metres around a fix, where its curvature is far below a
/// GPS's error.
struct Plane {
    lat: f64,
    lon: f64,
    /// Metres per degree of longitude there.
    east: f64,
}

/// Metres per degree of latitude.
const M_PER_DEG: f64 = 6_371_008.8 * std::f64::consts::PI / 180.0;

impl Plane {
    fn at(p: Position) -> Self {
        Self {
            lat: p.lat(),
            lon: p.lon(),
            east: M_PER_DEG * p.lat().to_radians().cos(),
        }
    }

    /// Metres east and north of `b` from the plane's point.
    fn of(&self, b: Position) -> (f64, f64) {
        (
            (b.lon() - self.lon) * self.east,
            (b.lat() - self.lat) * M_PER_DEG,
        )
    }
}

/// The smaller angle between two courses, 0 to 180 degrees.
fn angle_between(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::expect_used, reason = "test preconditions")]

    use ferrostar::models::{GeographicCoordinate, RouteStep};

    use super::*;

    /// A step along `points` (latitude, longitude).
    fn step(points: &[(f64, f64)]) -> RouteStep {
        RouteStep {
            geometry: points
                .iter()
                .map(|&(lat, lng)| GeographicCoordinate { lat, lng })
                .collect(),
            distance: 0.0,
            duration: 0.0,
            road_name: None,
            exits: Vec::new(),
            instruction: String::new(),
            visual_instructions: Vec::new(),
            spoken_instructions: Vec::new(),
            annotations: None,
            incidents: Vec::new(),
            driving_side: None,
            roundabout_exit_number: None,
        }
    }

    /// The point `north_m` north and `east_m` east of 45 N, 5 E.
    fn at(north_m: f64, east_m: f64) -> (f64, f64) {
        (
            45.0 + north_m / M_PER_DEG,
            5.0 + east_m / (M_PER_DEG * 45.0_f64.to_radians().cos()),
        )
    }

    fn pos(north_m: f64, east_m: f64) -> Position {
        let (lat, lon) = at(north_m, east_m);
        Position::new(lat, lon).expect("valid")
    }

    /// Driving at `v` m/s, no course given.
    fn moving(v: f64) -> Motion {
        Motion {
            speed_mps: Some(v),
            course_deg: None,
        }
    }

    /// Driving north at `v` m/s.
    fn north_at(v: f64) -> Motion {
        Motion {
            speed_mps: Some(v),
            course_deg: Some(0.0),
        }
    }

    fn still() -> Motion {
        Motion::default()
    }

    /// A straight road north: steps of 100 m, 7 m and 200 m.
    fn road() -> StepTrack {
        StepTrack::new(&[
            step(&[at(0.0, 0.0), at(100.0, 0.0)]),
            step(&[at(100.0, 0.0), at(107.0, 0.0)]),
            step(&[at(107.0, 0.0), at(307.0, 0.0)]),
        ])
        .expect("a track")
    }

    /// A road 5 km long, north.
    fn long_road() -> StepTrack {
        StepTrack::new(&[step(&[at(0.0, 0.0), at(5_000.0, 0.0)])]).expect("a track")
    }

    /// Up 200 m, a hairpin, back down 200 m 20 m to the east.
    fn hairpin() -> StepTrack {
        StepTrack::new(&[
            step(&[at(0.0, 0.0), at(200.0, 0.0)]),
            step(&[at(200.0, 0.0), at(200.0, 20.0), at(0.0, 20.0)]),
        ])
        .expect("a track")
    }

    #[test]
    fn steps_end_where_their_lines_do() {
        let track = road();
        assert!(
            (track.start_of(1) - 100.0).abs() < 0.1,
            "the 7 m step's start"
        );
        assert!(
            (track.start_of(2) - 107.0).abs() < 0.1,
            "the last step's start"
        );
        assert!((track.length_m() - 307.0).abs() < 0.1, "the whole line");
        assert_eq!(track.step_at(50.0, 5.0), 0, "in the first step");
        assert_eq!(track.step_at(104.0, 5.0), 0, "still 5 m from the end");
        assert_eq!(track.step_at(110.0, 5.0), 1, "5 m past the first step");
        assert_eq!(track.step_at(130.0, 5.0), 2, "the short step is passed");
        assert_eq!(track.step_at(400.0, 5.0), 3, "past the last step");
    }

    #[test]
    fn a_fix_within_reach_is_placed_at_once() {
        let mut track = road();
        let first = track
            .place(pos(10.0, 3.0), 0, still(), 0, 40.0)
            .expect("near the start");
        assert!((first.along_m - 10.0).abs() < 0.5, "10 m along: {first:?}");
        assert!((first.distance_m - 3.0).abs() < 0.5, "3 m off: {first:?}");
        let next = track
            .place(pos(35.0, 0.0), 1_000, north_at(25.0), 0, 40.0)
            .expect("25 m on");
        assert!((next.along_m - 35.0).abs() < 0.5, "35 m along: {next:?}");
    }

    #[test]
    fn a_jump_stands_once_a_second_fix_confirms_it() {
        let mut track = long_road();
        track
            .place(pos(100.0, 0.0), 0, still(), 0, 40.0)
            .expect("near the start");
        assert_eq!(
            track.place(pos(4_000.0, 0.0), 1_000, north_at(25.0), 0, 40.0),
            None,
            "3.9 km in a second: not believed on one fix"
        );
        let confirmed = track
            .place(pos(4_025.0, 0.0), 2_000, north_at(25.0), 0, 40.0)
            .expect("the next fix goes on from there");
        assert!(
            (confirmed.along_m - 4_025.0).abs() < 0.5,
            "where the second fix is: {confirmed:?}"
        );
    }

    #[test]
    fn one_wild_fix_ahead_is_forgotten_when_the_drive_goes_on() {
        let mut track = long_road();
        track
            .place(pos(100.0, 0.0), 0, still(), 0, 40.0)
            .expect("near the start");
        assert_eq!(
            track.place(pos(4_000.0, 0.0), 1_000, still(), 0, 40.0),
            None,
            "a wild fix, not believed"
        );
        let back = track
            .place(pos(125.0, 0.0), 2_000, north_at(25.0), 0, 40.0)
            .expect("the drive");
        assert!(
            (back.along_m - 125.0).abs() < 0.5,
            "the drive goes on: {back:?}"
        );
        assert_eq!(
            track.place(pos(4_050.0, 0.0), 3_000, still(), 0, 40.0),
            None,
            "the wild fix was dropped: another jump waits again"
        );
    }

    #[test]
    fn a_long_gap_widens_the_reach() {
        let mut track = long_road();
        track
            .place(pos(100.0, 0.0), 0, still(), 0, 40.0)
            .expect("near the start");
        // 1.5 km in 60 s, a tunnel at 90 km/h: within reach at once.
        let out = track
            .place(pos(1_600.0, 0.0), 60_000, north_at(25.0), 0, 40.0)
            .expect("out of the tunnel");
        assert!(
            (out.along_m - 1_600.0).abs() < 0.5,
            "out of the tunnel: {out:?}"
        );
    }

    #[test]
    fn a_fix_off_the_line_is_not_placed() {
        let mut track = road();
        assert_eq!(
            track.place(pos(50.0, 79.0), 0, still(), 0, 40.0),
            None,
            "79 m east"
        );
    }

    #[test]
    fn the_far_leg_of_a_hairpin_does_not_draw_a_fix_nearer_it() {
        let mut track = hairpin();
        track
            .place(pos(170.0, 0.0), 0, moving(8.0), 0, 40.0)
            .expect("on the way up");
        // 8 m on, 12 m east of the road up: 8 m from the road down, whose
        // point there lies 64 m farther along, within reach. No course: the
        // speed alone keeps the fix on the road up.
        let noisy = track
            .place(pos(178.0, 12.0), 1_000, moving(8.0), 0, 40.0)
            .expect("placed");
        assert!(
            (noisy.along_m - 178.0).abs() < 1.0,
            "on the road up: {}",
            noisy.along_m
        );
    }

    #[test]
    fn without_a_speed_the_nearest_point_of_the_reach_wins() {
        let mut track = hairpin();
        track
            .place(pos(190.0, 0.0), 0, still(), 0, 40.0)
            .expect("before the hairpin");
        // Round the hairpin and 10 m down: within reach, nearer the road
        // down than the road up.
        let down = track
            .place(pos(190.0, 19.0), 2_000, still(), 0, 40.0)
            .expect("placed");
        assert!(down.along_m > 220.0, "on the road down: {}", down.along_m);
    }

    #[test]
    fn a_course_keeps_a_fix_off_the_leg_run_the_other_way() {
        let heading_north = Motion {
            speed_mps: None,
            course_deg: Some(0.0),
        };
        let mut track = hairpin();
        track
            .place(pos(170.0, 0.0), 0, heading_north, 0, 40.0)
            .expect("on the way up");
        // 6 m from the road down, 14 m from the road up, heading north: on
        // the way up. Without the course the road down would be nearest.
        let up = track
            .place(pos(180.0, 14.0), 1_000, heading_north, 0, 40.0)
            .expect("placed");
        assert!(up.along_m < 200.0, "on the road up: {}", up.along_m);
        let mut blind = hairpin();
        blind
            .place(pos(170.0, 0.0), 0, still(), 0, 40.0)
            .expect("on the way up");
        let down = blind
            .place(pos(180.0, 14.0), 1_000, still(), 0, 40.0)
            .expect("placed");
        assert!(
            down.along_m > 220.0,
            "without a course, the nearest: {}",
            down.along_m
        );
    }

    #[test]
    fn a_jump_onto_a_leg_run_the_other_way_is_never_taken() {
        // Up 400 m, a hairpin, back down 60 m to the east.
        let mut track = StepTrack::new(&[
            step(&[at(0.0, 0.0), at(400.0, 0.0)]),
            step(&[at(400.0, 0.0), at(400.0, 60.0), at(0.0, 60.0)]),
        ])
        .expect("a track");
        track
            .place(pos(100.0, 0.0), 0, north_at(10.0), 0, 40.0)
            .expect("on the way up");
        // Two fixes 45 m east of the road up, 15 m from the road down,
        // driving north: a reflected signal, not the road down.
        for second in 1..=2 {
            assert_eq!(
                track.place(pos(110.0, 45.0), second * 1_000, north_at(10.0), 0, 40.0),
                None,
                "fix {second}: no jump onto the road down"
            );
        }
    }
}
