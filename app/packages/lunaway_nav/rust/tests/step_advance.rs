//! Step advance over a route recorded from the Lunaway API, with fixes as
//! far apart as a vehicle drives in a second, offset as a GPS places them,
//! and positions that jump.
//!
//! Perpignan to Figueres without tolls by the D 900, the route of the
//! second UX audit's frozen guidance (recorded 2026-10-10, 55.9 km, 34
//! steps, six roundabouts in the first 12 km). Its third step, "fork
//! slight right", is 7 m long: with a fix every 25 m none came within 20 m
//! of its end once the step before had ended, and Ferrostar's own advance
//! left the guidance on "Serrez à droite." at 0 m for the rest of the
//! drive.
#![allow(
    clippy::expect_used,
    reason = "the helpers state the preconditions of the recorded fixture"
)]

use std::sync::OnceLock;

use lunaway_domain::Position;
use lunaway_domain::routing::polyline;
use lunaway_nav::api::engine::{Fix, Guidance, GuidanceSettings, GuidanceState, GuidanceStatus};

const FIGUERES: &str = include_str!("fixtures/perpignan_figueres.osrm.json");

/// The recorded route: its line, the distance of each of its points from
/// the start, and where each step ends along it.
struct Route {
    points: Vec<Position>,
    along: Vec<f64>,
    ends: Vec<f64>,
}

impl Route {
    fn get() -> &'static Self {
        static ROUTE: OnceLock<Route> = OnceLock::new();
        ROUTE.get_or_init(|| {
            let answer: serde_json::Value =
                serde_json::from_str(FIGUERES).expect("a recorded answer");
            let decode = |v: &serde_json::Value| {
                polyline::decode(v.as_str().expect("polyline6")).expect("a valid polyline")
            };
            let points = decode(&answer["routes"][0]["geometry"]);
            let mut along = vec![0.0];
            for w in points.windows(2) {
                along.push(along[along.len() - 1] + w[0].distance_m(w[1]));
            }
            // The steps' own lines laid end to end.
            let mut ends = Vec::new();
            let mut total = 0.0;
            for leg in answer["routes"][0]["legs"].as_array().expect("legs") {
                for step in leg["steps"].as_array().expect("steps") {
                    let line = decode(&step["geometry"]);
                    total += line.windows(2).map(|w| w[0].distance_m(w[1])).sum::<f64>();
                    ends.push(total);
                }
            }
            Self {
                points,
                along,
                ends,
            }
        })
    }

    fn length(&self) -> f64 {
        self.along[self.along.len() - 1]
    }

    /// The step that holds `along_m`.
    fn step_at(&self, along_m: f64) -> u32 {
        u32::try_from(self.ends.partition_point(|end| *end <= along_m)).expect("a few dozen")
    }

    fn steps(&self) -> u32 {
        u32::try_from(self.ends.len()).expect("a few dozen")
    }

    /// The point `along_m` metres from the start, and the line's heading
    /// there; past the end, on along the last heading.
    fn at(&self, along_m: f64) -> (Position, f64) {
        let n = self.points.len();
        let i = self
            .along
            .partition_point(|a| *a <= along_m)
            .clamp(1, n - 1);
        let (a, b) = (self.points[i - 1], self.points[i]);
        let h = heading(a, b);
        let span = self.along[i] - self.along[i - 1];
        if along_m >= self.length() {
            return (ahead(b, h, along_m - self.length()), h);
        }
        let t = if span > 0.0 {
            ((along_m - self.along[i - 1]) / span).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let p = Position::new(
            a.lat() + (b.lat() - a.lat()) * t,
            a.lon() + (b.lon() - a.lon()) * t,
        )
        .expect("between two valid points");
        (p, h)
    }
}

fn heading(a: Position, b: Position) -> f64 {
    let east = (b.lon() - a.lon()) * a.lat().to_radians().cos();
    east.atan2(b.lat() - a.lat()).to_degrees().rem_euclid(360.0)
}

/// `p` moved `m` metres towards `heading`.
fn ahead(p: Position, heading: f64, m: f64) -> Position {
    let h = heading.to_radians();
    let m_per_deg = 111_195.0;
    Position::new(
        p.lat() + m * h.cos() / m_per_deg,
        p.lon() + m * h.sin() / (m_per_deg * p.lat().to_radians().cos()),
    )
    .expect("a few metres off a valid point")
}

/// A fix at `p`, taken `second` seconds into the drive.
fn fix(p: Position, heading: f64, speed: f64, second: f64) -> Fix {
    #[allow(clippy::cast_possible_truncation, reason = "a drive of minutes")]
    let ms = (second * 1_000.0).round() as i64;
    Fix {
        lat: p.lat(),
        lon: p.lon(),
        accuracy_m: 8.0,
        course_deg: Some(heading),
        speed_mps: Some(speed),
        timestamp_ms: 1_791_000_000_000 + ms,
    }
}

fn guidance() -> Guidance {
    Guidance::new(FIGUERES.to_owned(), 0, GuidanceSettings::default()).expect("the route")
}

/// A GPS's offset at fix `i`, metres to the right of the road: up to 10 m
/// either side, never the same twice in a row.
fn wobble(i: usize) -> f64 {
    [0.0, 7.0, -4.0, 10.0, -9.0, 3.0, -10.0, 6.0][i % 8]
}

fn on_the_line(_: usize) -> f64 {
    0.0
}

/// What a drive at `speed` m/s from `from_m` to `to_m` along the route, a
/// fix a second offset by `offset`, shows at each fix, with where the
/// vehicle truly was. Stops at the arrival.
fn drive(
    speed: f64,
    from_m: f64,
    to_m: f64,
    offset: fn(usize) -> f64,
) -> Vec<(f64, GuidanceState)> {
    let route = Route::get();
    let mut g = guidance();
    let mut shown = Vec::new();
    let mut i = 0;
    loop {
        #[allow(clippy::cast_precision_loss, reason = "a few thousand fixes")]
        let along = from_m + i as f64 * speed;
        let (p, h) = route.at(along);
        #[allow(clippy::cast_precision_loss, reason = "a few thousand fixes")]
        let state = g.update(fix(ahead(p, h + 90.0, offset(i)), h, speed, i as f64));
        let arrived = state.status == GuidanceStatus::Arrived;
        shown.push((along, state));
        if arrived || along > to_m {
            return shown;
        }
        i += 1;
    }
}

/// Whether `s`, shown with the vehicle `along_m` from the start at `speed`
/// m/s, is on the vehicle's step: never ahead of it by more than the GPS's
/// offset, never behind it by more than a fix and the 5 m a step lasts
/// past its maneuver.
fn on_its_step(s: &GuidanceState, along_m: f64, speed: f64) -> bool {
    let route = Route::get();
    s.step_index <= route.step_at(along_m + 15.0)
        && s.step_index >= route.step_at(along_m - speed - 15.0).min(route.steps() - 1)
}

/// Checks what a drive showed: on the route, steps that only move on and
/// keep to the vehicle's ([`on_its_step`]), never pinned at "0 m" while it
/// drives on past the maneuver. `settle` fixes at the start are left out:
/// a drive taken up mid-route.
fn check(label: &str, speed: f64, shown: &[(f64, GuidanceState)], settle: usize) {
    let route = Route::get();
    let mut step = 0;
    let mut zero_since: Option<f64> = None;
    for &(along, ref s) in &shown[settle..] {
        if s.status == GuidanceStatus::Arrived {
            break;
        }
        assert_eq!(s.off_route_m, None, "{label}: on the route at {along} m");
        assert!(s.step_index >= step, "{label}: steps only move on");
        step = s.step_index;
        assert!(
            on_its_step(s, along, speed),
            "{label}: step {} at {along} m, the vehicle's is {}",
            s.step_index,
            route.step_at(along)
        );
        // At the maneuver, then on: 0 m for the 5 m a step lasts past it,
        // and the fix that shows the next one.
        let since = if s.distance_to_maneuver_m < 1.0 {
            *zero_since.get_or_insert(along)
        } else {
            zero_since = None;
            along
        };
        assert!(
            along - since <= speed + 15.0,
            "{label}: at 0 m from {since} m to {along} m"
        );
    }
}

#[test]
fn a_fix_every_25_m_passes_the_seven_metre_step() {
    let shown = drive(25.0, 0.0, 1_000.0, on_the_line);
    assert!(
        shown
            .iter()
            .all(|(along, s)| *along <= 475.0 || s.step_index > 2),
        "the 7 m step after the fork ends once the vehicle is past it"
    );
    let (_, after) = shown
        .iter()
        .find(|(along, _)| *along >= 525.0)
        .expect("a fix past the fork");
    assert!(
        after.step_index >= 3 && after.distance_to_maneuver_m > 1.0,
        "the next maneuver, still ahead: step {}, {} m",
        after.step_index,
        after.distance_to_maneuver_m
    );
}

#[test]
fn every_speed_from_5_to_40_m_s_walks_every_step_and_arrives() {
    let route = Route::get();
    let speeds = [5.0, 10.0, 14.0, 20.0, 25.0, 30.0, 35.0, 40.0];
    for speed in speeds {
        for (name, offset) in [
            ("on the line", on_the_line as fn(usize) -> f64),
            ("wobbling", wobble),
        ] {
            // The first 12.5 km (the forks and six roundabouts), then the
            // last 6 km (a roundabout, its 15 m exit, two turns, the
            // arrival), taken up mid-route: its first fixes are a jump.
            let start = drive(speed, 0.0, 12_500.0, offset);
            check(&format!("{speed} m/s {name}"), speed, &start, 0);
            let end = drive(
                speed,
                route.length() - 6_000.0,
                route.length() + 3.0 * speed,
                offset,
            );
            check(&format!("{speed} m/s {name}, the end"), speed, &end, 2);
            let (_, last) = end.last().expect("fixes");
            assert_eq!(
                last.status,
                GuidanceStatus::Arrived,
                "{speed} m/s {name}: the drive ends at the destination"
            );
        }
    }
}

/// The drive at 25 m/s from the start up to `from_m`, then from `to_m` on:
/// a jump.
fn jump(from_m: f64, to_m: f64) -> Vec<(f64, GuidanceState)> {
    let route = Route::get();
    let mut g = guidance();
    let mut shown = Vec::new();
    let mut second = 0.0;
    let mut along = 0.0;
    while along <= to_m + 500.0 {
        let (p, h) = route.at(along);
        shown.push((along, g.update(fix(p, h, 25.0, second))));
        second += 1.0;
        along = if along < from_m && along + 25.0 >= from_m {
            to_m
        } else {
            along + 25.0
        };
    }
    shown
}

#[test]
fn a_jump_of_900_m_lands_on_the_step_of_the_new_position() {
    let route = Route::get();
    // 3.2 km to 4.1 km, over the roundabout of the Route du Perthus: the
    // bench's jump that froze the guidance on it.
    let shown = jump(3_200.0, 4_100.0);
    let landed = shown
        .iter()
        .position(|(along, _)| *along >= 4_100.0)
        .expect("the jump");
    for (along, s) in &shown[landed + 1..] {
        assert_eq!(
            s.step_index,
            route.step_at(*along),
            "on the step of the vehicle from the fix after the jump, at {along} m"
        );
        assert_eq!(s.off_route_m, None);
    }
}

#[test]
fn a_jump_of_4_km_skips_the_steps_between() {
    let route = Route::get();
    let shown = jump(3_300.0, 7_300.0);
    let landed = shown
        .iter()
        .position(|(along, _)| *along >= 7_300.0)
        .expect("the jump");
    let (along, after) = &shown[landed + 1];
    assert_eq!(
        after.step_index,
        route.step_at(*along),
        "steps 6 to 9 skipped"
    );
    assert!(
        (after.distance_along_m - along).abs() < 100.0,
        "the distance along follows the vehicle: {} for {along}",
        after.distance_along_m
    );
    assert!(after.banner.is_some(), "an instruction again");
}

#[test]
fn one_wild_fix_ahead_does_not_skip_steps() {
    let route = Route::get();
    let mut g = guidance();
    let mut second = 0.0;
    for k in 0..160 {
        let along = f64::from(k) * 25.0;
        let (p, h) = route.at(along);
        let s = g.update(fix(p, h, 25.0, second));
        second += 1.0;
        if k == 100 {
            // On the route 5 km ahead, for one fix: a reflected signal.
            let (far, fh) = route.at(7_500.0);
            g.update(fix(far, fh, 25.0, second));
            second += 1.0;
        }
        assert!(
            on_its_step(&s, along, 25.0),
            "step {} at {along} m, the vehicle's is {}",
            s.step_index,
            route.step_at(along)
        );
    }
}

#[test]
fn a_jump_off_the_route_is_off_the_route_and_skips_nothing() {
    let route = Route::get();
    let mut g = guidance();
    let mut last = None;
    for k in 0..20 {
        let along = 3_000.0 + f64::from(k) * 25.0;
        let (p, h) = route.at(along);
        last = Some(g.update(fix(p, h, 25.0, f64::from(k))));
    }
    let before = last.expect("20 fixes").step_index;
    // 2 km east of the D 900: no road of the route.
    let (p, h) = route.at(3_500.0);
    let away = Position::new(p.lat(), p.lon() + 0.025).expect("valid");
    g.update(fix(away, h, 25.0, 20.0));
    let second = g.update(fix(away, h, 25.0, 21.0));
    assert!(
        second.off_route_m.is_some_and(|d| d > 1_000.0),
        "off the route: {:?}",
        second.off_route_m
    );
    assert_eq!(
        second.step_index, before,
        "no step taken for a fix off the route"
    );
}

#[test]
fn fixes_40_m_apart_that_overshoot_the_destination_arrive() {
    let route = Route::get();
    let mut g = guidance();
    let mut arrived = false;
    // From 3 km before the end, 40 m a fix, the last one 25 m beyond it on
    // the road's heading.
    let mut along = route.length() - 3_000.0 + 15.0;
    let mut second = 0.0;
    while along < route.length() + 30.0 {
        let (p, h) = route.at(along);
        if g.update(fix(p, h, 40.0, second)).status == GuidanceStatus::Arrived {
            arrived = true;
            break;
        }
        along += 40.0;
        second += 1.0;
    }
    assert!(
        arrived,
        "the vehicle that drove past the destination arrived"
    );
}

#[test]
fn a_vague_fix_never_ends_a_step() {
    let route = Route::get();
    let mut g = guidance();
    for k in 0..16 {
        let along = f64::from(k) * 25.0;
        let (p, h) = route.at(along);
        g.update(fix(p, h, 25.0, f64::from(k)));
    }
    // Past the fork and the 7 m step, but 60 m uncertain: as in a tunnel.
    let (p, h) = route.at(530.0);
    let mut vague = fix(p, h, 25.0, 16.0);
    vague.accuracy_m = 60.0;
    let s = g.update(vague);
    assert_eq!(
        s.step_index, 1,
        "still before the fork, as far as one knows"
    );
}
