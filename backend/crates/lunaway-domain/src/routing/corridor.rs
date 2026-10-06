//! Which restrictions a route drives through, and where along it.
//!
//! The database returns every restriction near the route; most of them are
//! only near it: the road under a bridge the route crosses, a car park
//! barrier a few metres off the street. A restriction counts when the route
//! runs along it: a node within [`NODE_TOLERANCE_M`] of the line, or a stretch
//! of road the route follows, in either direction, at the same heading
//! (within [`MAX_ANGLE_DEG`]) over a real distance. A crossing does not
//! count, square or oblique: the headings differ, and the route's position
//! barely moves while it passes the other road.

use std::collections::{HashMap, HashSet};

use crate::{Position, geo::EARTH_RADIUS_M};

/// How far a restricted node may lie from the route's line: OpenStreetMap
/// nodes the route passes through lie on it (the router's shape is made of
/// the same nodes); a barrier a few metres inside a side entrance does not.
pub const NODE_TOLERANCE_M: f64 = 2.0;
/// Spacing of the points a restricted line is checked at.
const STEP_M: f64 = 4.0;
/// Distance the route must follow a restricted line before it counts; a
/// shorter restriction counts when the route follows most of it.
const FOLLOW_M: f64 = 15.0;
/// Share of a short restriction the route must follow.
const FOLLOW_SHARE: f64 = 0.6;
/// Distance enough at either end of the route, where the router may start
/// or stop inside a restricted stretch (the first-edge gap of
/// `plan/research/07-navigation.md`, A.4).
const END_FOLLOW_M: f64 = 3.0;
/// Grid cell of the route index, degrees: about 220 m of latitude, 140 m
/// of longitude in the north of France; every tolerance is far smaller.
const CELL_DEG: f64 = 0.002;
/// Largest angle between a restricted line and the route that still counts
/// as following it, degrees: a road bends, a crossing at 30 or 45 degrees
/// must not count (an IGN line 12 m wide at 45 degrees would otherwise be
/// "followed" over 20 m).
pub const MAX_ANGLE_DEG: f64 = 25.0;

/// Metres per degree of latitude.
fn metres_per_degree() -> f64 {
    EARTH_RADIUS_M * std::f64::consts::PI / 180.0
}

/// `b - a` in metres east and north, on a plane tangent at `a`.
fn offset(a: Position, b: Position) -> (f64, f64) {
    let k = metres_per_degree();
    (
        (b.lon() - a.lon()) * k * a.lat().to_radians().cos(),
        (b.lat() - a.lat()) * k,
    )
}

#[allow(
    clippy::cast_possible_truncation,
    reason = "a cell index of a valid coordinate is far inside i32"
)]
fn cell(p: Position) -> (i32, i32) {
    (
        (p.lat() / CELL_DEG).floor() as i32,
        (p.lon() / CELL_DEG).floor() as i32,
    )
}

/// A route's line, indexed for the matching.
#[derive(Debug, Clone)]
pub struct RouteLine {
    points: Vec<Position>,
    along: Vec<f64>,
    grid: HashMap<(i32, i32), Vec<u32>>,
    /// Distances from the start where the route stops: its start, each
    /// waypoint, its end. The router applies no limit to the edge a leg
    /// starts or ends on.
    stops: Vec<f64>,
}

impl RouteLine {
    /// Indexes `points`, the route's shape in driving order; none for a
    /// shape of fewer than two points, which no route has.
    #[must_use]
    pub fn new(points: Vec<Position>) -> Option<Self> {
        if points.len() < 2 {
            return None;
        }
        let mut along = Vec::with_capacity(points.len());
        let mut total = 0.0;
        let mut grid: HashMap<(i32, i32), Vec<u32>> = HashMap::new();
        for (i, p) in points.iter().enumerate() {
            if i > 0 {
                total += points[i - 1].distance_m(*p);
            }
            along.push(total);
        }
        for (i, pair) in points.windows(2).enumerate() {
            let Ok(segment) = u32::try_from(i) else { break };
            let (a, b) = (pair[0], pair[1]);
            let span = (b.lat() - a.lat()).abs().max((b.lon() - a.lon()).abs());
            #[allow(
                clippy::cast_possible_truncation,
                clippy::cast_sign_loss,
                reason = "a positive count of steps along one segment"
            )]
            let steps = (span / (CELL_DEG / 2.0)).ceil() as u32 + 1;
            let mut last = None;
            for s in 0..=steps {
                let t = f64::from(s) / f64::from(steps);
                let Ok(q) = Position::new(
                    a.lat() + (b.lat() - a.lat()) * t,
                    a.lon() + (b.lon() - a.lon()) * t,
                ) else {
                    continue;
                };
                let c = cell(q);
                if last != Some(c) {
                    // The cell and its neighbours: a sample lies within half
                    // a cell of any point of the segment, so the cell of the
                    // point nearest a query is among them, and a query reads
                    // its own cell and its eight neighbours only.
                    for dr in -1..=1 {
                        for dc in -1..=1 {
                            let list = grid.entry((c.0 + dr, c.1 + dc)).or_default();
                            if list.last() != Some(&segment) {
                                list.push(segment);
                            }
                        }
                    }
                    last = Some(c);
                }
            }
        }
        let stops = vec![0.0, total];
        Some(Self {
            points,
            along,
            grid,
            stops,
        })
    }

    /// Marks the route's waypoints: `legs` are the lengths of its legs as
    /// the router reports them; each leg boundary is a stop. The router
    /// measures on another sphere than this line (2 020.3 m against
    /// 2 017.7 m on a real 2 km route), so the boundaries are placed by their
    /// share of the router's total, not by its metres.
    #[must_use]
    pub fn with_legs(mut self, legs: &[f64]) -> Self {
        let total: f64 = legs.iter().sum();
        if !(total.is_finite() && total > 0.0) {
            return self;
        }
        let length = self.length_m();
        let mut at = 0.0;
        for leg in legs.iter().take(legs.len().saturating_sub(1)) {
            at += leg;
            self.stops.push(at / total * length);
        }
        self
    }

    /// Whether `s` metres from the start lies within `tolerance` of a stop.
    fn near_stop(&self, s: f64, tolerance: f64) -> bool {
        self.stops.iter().any(|stop| (s - stop).abs() <= tolerance)
    }

    /// The shape, in driving order.
    #[must_use]
    pub fn points(&self) -> &[Position] {
        &self.points
    }

    /// Length, metres.
    #[must_use]
    pub fn length_m(&self) -> f64 {
        self.along.last().copied().unwrap_or(0.0)
    }

    /// Index of the last shape point at or before `s` metres from the
    /// start: the geometry index Ferrostar and the OSRM format count in.
    #[must_use]
    pub fn index_at(&self, s: f64) -> usize {
        self.along.partition_point(|a| *a <= s).saturating_sub(1)
    }

    /// The point `s` metres from the start.
    #[must_use]
    pub fn point_at(&self, s: f64) -> Position {
        let i = self.index_at(s);
        let last = self.points[self.points.len() - 1];
        let (Some(a), Some(b)) = (self.points.get(i), self.points.get(i + 1)) else {
            return last;
        };
        let len = self.along[i + 1] - self.along[i];
        let t = if len > 0.0 {
            ((s - self.along[i]) / len).clamp(0.0, 1.0)
        } else {
            0.0
        };
        Position::new(
            a.lat() + (b.lat() - a.lat()) * t,
            a.lon() + (b.lon() - a.lon()) * t,
        )
        .unwrap_or(*a)
    }

    /// The nearest point of the line to `p` within `max_m`: its distance
    /// from the start, its distance to `p`, metres, and the heading of the
    /// route's segment there, degrees.
    fn nearest(&self, p: Position, max_m: f64) -> Option<(f64, f64, f64)> {
        let (r, c) = cell(p);
        let mut best: Option<(f64, f64, f64)> = None;
        let mut seen: HashSet<u32> = HashSet::new();
        for dr in -1..=1 {
            for dc in -1..=1 {
                let Some(list) = self.grid.get(&(r + dr, c + dc)) else {
                    continue;
                };
                for &seg in list {
                    if !seen.insert(seg) {
                        continue;
                    }
                    let i = seg as usize;
                    let (a, b) = (self.points[i], self.points[i + 1]);
                    let (ax, ay) = offset(p, a);
                    let (bx, by) = offset(p, b);
                    let (dx, dy) = (bx - ax, by - ay);
                    let len2 = dx * dx + dy * dy;
                    let t = if len2 > 0.0 {
                        (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
                    } else {
                        0.0
                    };
                    let (qx, qy) = (ax + t * dx, ay + t * dy);
                    let d = (qx * qx + qy * qy).sqrt();
                    if d <= max_m && best.is_none_or(|(_, bd, _)| d < bd) {
                        let s = self.along[i] + t * (self.along[i + 1] - self.along[i]);
                        best = Some((s, d, dx.atan2(dy).to_degrees()));
                    }
                }
            }
        }
        best
    }
}

/// Heading from `a` to `b`, degrees from north.
fn heading(a: Position, b: Position) -> f64 {
    let (x, y) = offset(a, b);
    x.atan2(y).to_degrees()
}

/// Angle between two headings, ignoring the direction of travel: 0 to 90.
fn angle_between(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(180.0);
    d.min(180.0 - d)
}

/// Where a route drives through a restriction.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Hit {
    /// Distance from the start where the route enters it, metres.
    pub start_m: f64,
    /// Distance from the start where the route leaves it, metres.
    pub end_m: f64,
    /// Index of the shape point at or before the entry.
    pub geometry_index: usize,
    /// The point of the route where it enters.
    pub at: Position,
    /// The point of the route halfway through it: where an exclusion goes,
    /// on the road the route used and away from the crossings at its ends.
    pub middle: Position,
}

fn hit(route: &RouteLine, start_m: f64, end_m: f64) -> Hit {
    Hit {
        start_m,
        end_m,
        geometry_index: route.index_at(start_m),
        at: route.point_at(start_m),
        middle: route.point_at((start_m + end_m) / 2.0),
    }
}

/// The places where `route` drives through a restriction drawn as
/// `geometry` (one point for a node, a line for a way or a road section),
/// within `tolerance_m` of the route's line, in driving order.
#[must_use]
pub fn match_route(route: &RouteLine, geometry: &[Position], tolerance_m: f64) -> Vec<Hit> {
    match geometry {
        [] => Vec::new(),
        [node] => route
            .nearest(*node, tolerance_m.min(NODE_TOLERANCE_M))
            .map(|(s, _, _)| vec![hit(route, s, s)])
            .unwrap_or_default(),
        line => match_line(route, line, tolerance_m),
    }
}

fn match_line(route: &RouteLine, line: &[Position], tolerance_m: f64) -> Vec<Hit> {
    // The line, cut every STEP_M: each point, its distance along the line
    // and the line's heading there.
    let mut samples: Vec<(Position, f64, f64)> = Vec::new();
    let mut length = 0.0;
    for pair in line.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        let d = a.distance_m(b);
        let towards = heading(a, b);
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "a positive count of steps along one segment"
        )]
        let n = ((d / STEP_M).ceil() as u32).max(1);
        for k in 0..n {
            let t = f64::from(k) / f64::from(n);
            if let Ok(p) = Position::new(
                a.lat() + (b.lat() - a.lat()) * t,
                a.lon() + (b.lon() - a.lon()) * t,
            ) {
                samples.push((p, length + d * t, towards));
            }
        }
        length += d;
    }
    if let (Some(last), Some(towards)) = (line.last(), samples.last().map(|s| s.2)) {
        samples.push((*last, length, towards));
    }

    let needed = (FOLLOW_SHARE * length).min(FOLLOW_M);
    let mut hits = Vec::new();
    // Runs of consecutive samples near the route: (distance along the
    // route, distance along the line, whether the route there runs at the
    // line's heading).
    let mut run: Vec<(f64, f64, bool)> = Vec::new();
    let flush = |run: &mut Vec<(f64, f64, bool)>, hits: &mut Vec<Hit>| {
        if run.len() >= 2 {
            let covered = run[run.len() - 1].1 - run[0].1;
            let (lo, hi) = run
                .iter()
                .fold((f64::MAX, f64::MIN), |(lo, hi), (s, _, _)| {
                    (lo.min(*s), hi.max(*s))
                });
            let span = hi - lo;
            let at_a_stop = route.near_stop(lo, tolerance_m) || route.near_stop(hi, tolerance_m);
            let enough = if at_a_stop {
                needed.min(END_FOLLOW_M)
            } else {
                needed
            };
            // Following: the route advances about as much as the line, and
            // where each point of the line meets it, runs at its heading.
            // Crossing: it barely advances, at another heading. The heading
            // is compared point by point, so a bend or a turn back at a
            // waypoint stays a following.
            #[allow(
                clippy::cast_precision_loss,
                reason = "a count of a few thousand samples at most"
            )]
            let aligned = run.iter().filter(|(_, _, a)| *a).count() as f64 / run.len() as f64;
            if span >= enough && span >= 0.5 * covered && aligned >= 0.6 {
                hits.push(hit(route, lo, hi));
            }
        }
        run.clear();
    };
    for (p, along_line, towards) in samples {
        match route.nearest(p, tolerance_m) {
            Some((s, _, route_heading)) => {
                run.push((
                    s,
                    along_line,
                    angle_between(towards, route_heading) <= MAX_ANGLE_DEG,
                ));
            }
            None => flush(&mut run, &mut hits),
        }
    }
    flush(&mut run, &mut hits);
    hits.sort_by(|a, b| a.start_m.total_cmp(&b.start_m));
    hits
}

/// A ring around `center` of about `radius_m`, for the router's
/// `exclude_polygons`: an octagon, closed (the last point repeats the
/// first).
#[must_use]
pub fn exclusion_ring(center: Position, radius_m: f64) -> Vec<Position> {
    let k = metres_per_degree();
    let dlat = radius_m / k;
    let dlon = radius_m / (k * center.lat().to_radians().cos().max(0.01));
    let mut ring: Vec<Position> = (0..8)
        .filter_map(|i| {
            let a = f64::from(i) * std::f64::consts::FRAC_PI_4;
            Position::new(center.lat() + dlat * a.sin(), center.lon() + dlon * a.cos()).ok()
        })
        .collect();
    if let Some(first) = ring.first().copied() {
        ring.push(first);
    }
    ring
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A point `east` and `north` metres from `origin`.
    fn at(origin: Position, east: f64, north: f64) -> Position {
        let k = metres_per_degree();
        Position::new(
            origin.lat() + north / k,
            origin.lon() + east / (k * origin.lat().to_radians().cos()),
        )
        .unwrap()
    }

    fn limoges() -> Position {
        Position::new(45.8472, 1.2848).unwrap()
    }

    /// A straight route 1 km east, a point every 50 m.
    fn east_route() -> RouteLine {
        RouteLine::new(
            (0..=20)
                .map(|i| at(limoges(), f64::from(i) * 50.0, 0.0))
                .collect(),
        )
        .unwrap()
    }

    #[test]
    fn a_stretch_the_route_follows_counts_with_its_position() {
        let route = east_route();
        // A 30 m tunnel way on the route, from 400 m to 430 m.
        let tunnel = [at(limoges(), 400.0, 0.5), at(limoges(), 430.0, 0.5)];
        let hits = match_route(&route, &tunnel, 3.0);
        assert_eq!(hits.len(), 1, "{hits:?}");
        let h = hits[0];
        assert!((h.start_m - 400.0).abs() < 2.0, "{h:?}");
        assert!((h.end_m - 430.0).abs() < 2.0);
        assert_eq!(h.geometry_index, 8, "the shape point at 400 m");
        assert!(h.middle.distance_m(at(limoges(), 415.0, 0.0)) < 2.0);
    }

    #[test]
    fn a_road_the_route_crosses_does_not_count() {
        let route = east_route();
        // The road under a bridge the route takes: 20 m long, crossing at a
        // right angle at 500 m, its middle exactly under the route.
        let under = [at(limoges(), 500.0, -10.0), at(limoges(), 500.0, 10.0)];
        assert!(
            match_route(&route, &under, 3.0).is_empty(),
            "the route on the bridge must not be sent around the low road under it"
        );
        assert!(
            match_route(&route, &under, 12.0).is_empty(),
            "nor with the wider tolerance of IGN lines"
        );
        // A parallel street 30 m away does not count either.
        let parallel = [at(limoges(), 100.0, 30.0), at(limoges(), 300.0, 30.0)];
        assert!(match_route(&route, &parallel, 12.0).is_empty());
    }

    #[test]
    fn an_oblique_crossing_does_not_count() {
        let route = east_route();
        for angle in [30.0_f64, 45.0, 60.0] {
            // A 30 m line crossing the route at 500 m.
            let (dx, dy) = (
                15.0 * angle.to_radians().cos(),
                15.0 * angle.to_radians().sin(),
            );
            let line = [
                at(limoges(), 500.0 - dx, -dy),
                at(limoges(), 500.0 + dx, dy),
            ];
            assert!(
                match_route(&route, &line, 12.0).is_empty(),
                "a crossing at {angle} degrees is not followed"
            );
        }
        // A road that bends away by 10 degrees is still followed.
        let bent = [at(limoges(), 300.0, 0.0), at(limoges(), 400.0, 17.6)];
        assert_eq!(match_route(&route, &bent, 12.0).len(), 1);
    }

    #[test]
    fn a_waypoint_inside_a_restricted_stretch_is_caught() {
        // Out to a waypoint 10 m into a 60 m restricted way, and back: two
        // legs of 500 m. The router applies no limit to the edges a leg
        // starts and ends on.
        let points: Vec<Position> = (0..=50)
            .map(|i| at(limoges(), f64::from(i) * 10.0, 0.0))
            .chain(
                (0..50)
                    .rev()
                    .map(|i| at(limoges(), f64::from(i) * 10.0, 0.0)),
            )
            .collect();
        let way = [at(limoges(), 490.0, 0.0), at(limoges(), 550.0, 0.0)];
        let without = RouteLine::new(points.clone()).unwrap();
        assert!(
            match_route(&without, &way, 3.0).is_empty(),
            "10 m of a 60 m way in the middle of a trip does not count"
        );
        // The router's own lengths, 0.13 % longer than this line's.
        let with = RouteLine::new(points)
            .unwrap()
            .with_legs(&[3_000.0 * 1.0013, 3_000.0 * 1.0013]);
        assert_eq!(
            match_route(&with, &way, 3.0).len(),
            1,
            "10 m at a waypoint counts, whatever sphere the router measures on"
        );
    }

    #[test]
    fn an_ign_line_a_few_metres_off_the_road_counts() {
        let route = east_route();
        let ign = [at(limoges(), 600.0, 7.0), at(limoges(), 700.0, 8.0)];
        assert!(
            match_route(&route, &ign, 3.0).is_empty(),
            "too far for an OSM way"
        );
        let hits = match_route(&route, &ign, 12.0);
        assert_eq!(hits.len(), 1);
        assert!((hits[0].end_m - hits[0].start_m - 100.0).abs() < 5.0);
    }

    #[test]
    fn a_node_counts_on_the_line_and_not_beside_it() {
        let route = east_route();
        let barrier = [at(limoges(), 260.0, 0.3)];
        let hits = match_route(&route, &barrier, 3.0);
        assert_eq!(hits.len(), 1);
        assert!((hits[0].start_m - 260.0).abs() < 1.0);
        let off = [at(limoges(), 260.0, 6.0)];
        assert!(
            match_route(&route, &off, 3.0).is_empty(),
            "a barrier inside a side entrance is not on the route"
        );
    }

    #[test]
    fn a_route_starting_inside_a_restricted_stretch_is_caught() {
        // The first-edge gap: Valhalla does not apply a limit to the edge a
        // route starts on. The route starts 8 m before the tunnel's end.
        let route = east_route();
        let tunnel = [at(limoges(), -40.0, 0.0), at(limoges(), 8.0, 0.0)];
        let hits = match_route(&route, &tunnel, 3.0);
        assert_eq!(hits.len(), 1, "{hits:?}");
        assert!(hits[0].start_m < 1.0);
    }

    #[test]
    fn a_long_restricted_road_counts_where_the_route_joins_it() {
        let route = east_route();
        // A 2 km road with a weight limit, of which the route uses 150 m.
        let road = [at(limoges(), 850.0, 0.0), at(limoges(), 2_850.0, 0.0)];
        let hits = match_route(&route, &road, 3.0);
        assert_eq!(hits.len(), 1);
        assert!((hits[0].start_m - 850.0).abs() < 4.0);
    }

    #[test]
    fn positions_along_the_route_interpolate() {
        let route = east_route();
        assert!((route.length_m() - 1_000.0).abs() < 1.0);
        assert_eq!(route.index_at(0.0), 0);
        assert_eq!(route.index_at(75.0), 1);
        assert_eq!(route.index_at(5_000.0), 20);
        assert!(route.point_at(75.0).distance_m(at(limoges(), 75.0, 0.0)) < 0.5);
    }

    #[test]
    fn an_exclusion_ring_is_closed_and_of_the_asked_size() {
        let ring = exclusion_ring(limoges(), 5.0);
        assert_eq!(ring.len(), 9);
        assert_eq!(ring.first(), ring.last());
        for p in &ring {
            assert!((p.distance_m(limoges()) - 5.0).abs() < 0.1);
        }
    }
}
