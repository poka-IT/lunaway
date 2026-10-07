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

use std::collections::HashMap;

use super::restriction::RestrictionSource;
use crate::{Position, geo::EARTH_RADIUS_M};

/// How far a restricted node may lie from the route's line: OpenStreetMap
/// nodes the route passes through lie on it (the router's shape is made of
/// the same nodes); a barrier a few metres inside a side entrance does not.
pub const NODE_TOLERANCE_M: f64 = 2.0;
/// How far a line drawn through the router's own nodes may lie from a route
/// that drives it, metres: the route's shape is made of the same nodes,
/// both written to a millionth of a degree (11 cm at most). Four ways of
/// the D 93 and its ramp at Lille lay 0.00 to 0.06 m from the production
/// engine's route that drives them; the restricted branch leaving the same
/// node at 7 degrees (way 871761763), which a tolerance of 3 m took for the
/// route, is half a metre off 4 m after the fork (2026-10-07,
/// `plan/research/65-accroche-et-desserte.md`).
pub const ON_GRAPH_M: f64 = 0.5;
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

    /// Distances from the start where the route stops: its start, each
    /// waypoint ([`Self::with_legs`]), its end.
    #[must_use]
    pub fn stops(&self) -> &[f64] {
        &self.stops
    }

    /// The shape, in driving order.
    #[must_use]
    pub fn points(&self) -> &[Position] {
        &self.points
    }

    /// Distance from the start of each shape point, metres.
    #[must_use]
    pub fn along(&self) -> &[f64] {
        &self.along
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

    /// The nearest point of the line to `p` within `max_m`, if any: where
    /// it lies along the route, how far `p` is from it, and the route's
    /// heading there.
    #[must_use]
    pub fn project(&self, p: Position, max_m: f64) -> Option<Projection> {
        self.project_within(p, max_m, f64::NEG_INFINITY, f64::INFINITY)
    }

    /// [`Self::project`] onto the part of the line from `from_m` to `to_m`
    /// from the start: where a route passing near a point twice passes it
    /// at a known stage.
    #[must_use]
    pub fn project_within(
        &self,
        p: Position,
        max_m: f64,
        from_m: f64,
        to_m: f64,
    ) -> Option<Projection> {
        if from_m.is_nan() || to_m.is_nan() || from_m > to_m {
            return None;
        }
        self.nearest(p, max_m, from_m, to_m)
            .map(|(along_m, distance_m, heading_deg)| Projection {
                along_m,
                distance_m,
                heading_deg: heading_deg.rem_euclid(360.0),
            })
    }

    /// The route's heading `s` metres from the start, degrees from north
    /// (0 to 360), along the segment there.
    #[must_use]
    pub fn heading_at(&self, s: f64) -> f64 {
        let i = self.index_at(s).min(self.points.len().saturating_sub(2));
        heading(self.points[i], self.points[i + 1]).rem_euclid(360.0)
    }

    /// The nearest point of the line to `p` within `max_m`, between `from_m`
    /// and `to_m` from the start: its distance from the start, its distance
    /// to `p`, metres, and the heading of the route's segment there,
    /// degrees.
    fn nearest(&self, p: Position, max_m: f64, from_m: f64, to_m: f64) -> Option<(f64, f64, f64)> {
        let (r, c) = cell(p);
        let mut best: Option<(f64, f64, f64)> = None;
        SEEN.with_borrow_mut(|seen| {
            seen.start(self.points.len());
            for dr in -1..=1 {
                for dc in -1..=1 {
                    let Some(list) = self.grid.get(&(r + dr, c + dc)) else {
                        continue;
                    };
                    for &seg in list {
                        if !seen.first(seg) {
                            continue;
                        }
                        let i = seg as usize;
                        if self.along[i + 1] < from_m || self.along[i] > to_m {
                            continue;
                        }
                        let (a, b) = (self.points[i], self.points[i + 1]);
                        let (ax, ay) = offset(p, a);
                        let (bx, by) = offset(p, b);
                        let (dx, dy) = (bx - ax, by - ay);
                        let len2 = dx * dx + dy * dy;
                        // The part of the segment inside the range asked.
                        let span = self.along[i + 1] - self.along[i];
                        let (t0, t1) = if span > 0.0 {
                            (
                                ((from_m - self.along[i]) / span).clamp(0.0, 1.0),
                                ((to_m - self.along[i]) / span).clamp(0.0, 1.0),
                            )
                        } else {
                            (0.0, 1.0)
                        };
                        let t = if len2 > 0.0 {
                            (-(ax * dx + ay * dy) / len2).clamp(t0, t1)
                        } else {
                            0.0
                        };
                        let (qx, qy) = (ax + t * dx, ay + t * dy);
                        let d = (qx * qx + qy * qy).sqrt();
                        if d <= max_m && best.is_none_or(|(_, bd, _)| d < bd) {
                            let s = self.along[i] + t * span;
                            best = Some((s, d, dx.atan2(dy).to_degrees()));
                        }
                    }
                }
            }
        });
        best
    }
}

/// The segments a query of [`RouteLine::nearest`] has read, by the call
/// that read them last: a segment sits in several of the nine lists a query
/// reads, and skipping it after the first gives the answer of a set
/// without a set's allocation and hashing on every query. Matching the
/// restrictions of 30 production routes took 4.29 s with a set per query,
/// 1.21 s with these marks, the same hits on every route (2026-10-07,
/// `plan/research/48-latence-itineraires.md`). One mark per point of the
/// longest line a thread has read: 800 kB for 200 000 points.
struct Seen {
    call: u32,
    marks: Vec<u32>,
}

impl Seen {
    /// Starts a query of a line of `points` points.
    fn start(&mut self, points: usize) {
        if self.marks.len() < points {
            self.marks.resize(points, 0);
        }
        self.call = self.call.wrapping_add(1);
        if self.call == 0 {
            // Every mark is stale again after four billion queries.
            self.marks.fill(0);
            self.call = 1;
        }
    }

    /// Whether this query meets `segment` for the first time.
    fn first(&mut self, segment: u32) -> bool {
        let mark = &mut self.marks[segment as usize];
        let first = *mark != self.call;
        *mark = self.call;
        first
    }
}

thread_local! {
    static SEEN: std::cell::RefCell<Seen> = const {
        std::cell::RefCell::new(Seen { call: 0, marks: Vec::new() })
    };
}

/// Where a point projects onto a route.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Projection {
    /// Distance from the start of the route, metres.
    pub along_m: f64,
    /// Distance from the point to the route, metres.
    pub distance_m: f64,
    /// The route's heading there, degrees from north, 0 to 360.
    pub heading_deg: f64,
}

/// Heading from `a` to `b`, degrees from north.
#[must_use]
pub fn heading(a: Position, b: Position) -> f64 {
    let (x, y) = offset(a, b);
    x.atan2(y).to_degrees()
}

/// Angle between two headings, ignoring the direction of travel: 0 to 90.
fn angle_between(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(180.0);
    d.min(180.0 - d)
}

/// Angle between two headings in their direction of travel: 0 to 180.
#[must_use]
pub fn turn_between(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
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
            .nearest(
                *node,
                tolerance_m.min(NODE_TOLERANCE_M),
                f64::NEG_INFINITY,
                f64::INFINITY,
            )
            .map(|(s, _, _)| vec![hit(route, s, s)])
            .unwrap_or_default(),
        line => match_line(route, line, tolerance_m, false),
    }
}

/// The places where `route` drives through a restriction of `source` drawn
/// as `geometry`: a node within its source's tolerance, a line within
/// [`RestrictionSource::line_tolerance_m`].
#[must_use]
pub fn match_restriction(
    route: &RouteLine,
    geometry: &[Position],
    source: RestrictionSource,
) -> Vec<Hit> {
    let tolerance = if geometry.len() > 1 {
        source.line_tolerance_m()
    } else {
        source.tolerance_m()
    };
    match_route(route, geometry, tolerance)
}

/// The distance from `p` to `geometry` (one point or a line), metres.
#[must_use]
pub fn distance_to(p: Position, geometry: &[Position]) -> f64 {
    match geometry {
        [] => f64::INFINITY,
        [one] => p.distance_m(*one),
        line => line
            .windows(2)
            .map(|w| {
                let (ax, ay) = offset(p, w[0]);
                let (bx, by) = offset(p, w[1]);
                let (dx, dy) = (bx - ax, by - ay);
                let len2 = dx * dx + dy * dy;
                let t = if len2 > 0.0 {
                    (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
                } else {
                    0.0
                };
                (ax + t * dx).hypot(ay + t * dy)
            })
            .fold(f64::INFINITY, f64::min),
    }
}

/// The places where `route` drives along `line` in the line's own
/// direction (its points in driving order), within `tolerance_m`: a road
/// event on one carriageway of a dual carriageway, or on one direction of a
/// road, concerns a route going that way only. A route driving the line
/// the other way does not count, nor does a crossing.
#[must_use]
pub fn match_route_directed(route: &RouteLine, line: &[Position], tolerance_m: f64) -> Vec<Hit> {
    if line.len() < 2 {
        return Vec::new();
    }
    match_line(route, line, tolerance_m, true)
}

fn match_line(route: &RouteLine, line: &[Position], tolerance_m: f64, directed: bool) -> Vec<Hit> {
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
        match route.nearest(p, tolerance_m, f64::NEG_INFINITY, f64::INFINITY) {
            Some((s, _, route_heading)) => {
                let aligned = if directed {
                    turn_between(towards, route_heading) <= MAX_ANGLE_DEG
                } else {
                    angle_between(towards, route_heading) <= MAX_ANGLE_DEG
                };
                run.push((s, along_line, aligned));
            }
            None => flush(&mut run, &mut hits),
        }
    }
    flush(&mut run, &mut hits);
    hits.sort_by(|a, b| a.start_m.total_cmp(&b.start_m));
    hits
}

/// Largest distance, metres, between a stop and the first stretch of a run
/// of local access: the route starts on the limited road itself, or on a
/// road enclosed behind the zone that the graph build marked with its
/// limit (an aire on a service road behind a "sauf desserte" street,
/// [`super::Restriction::enclosed`]), and the hit of that road starts a few
/// sample steps from the stop.
pub const LOCAL_ACCESS_STOP_M: f64 = 20.0;

/// How far behind a "sauf desserte" zone the graph build marks the roads
/// enclosed by it, metres along the roads: six campsites within 150 m of
/// such a street in France lie 113 to 279 m beyond its end (production
/// engine, 2026-10-07, `plan/research/65-accroche-et-desserte.md`).
pub const ENCLOSED_REACH_M: f64 = 500.0;

/// Largest gap, metres, between two stretches of one run of local access:
/// the junctions, squares and stretches a zone's mappers leave without the
/// sign between two that carry it, or a street of a higher limit the
/// vehicle meets no limit on. The D937 at Route du Boutariq leaves 264 m
/// without it between the entry of its 3.5 t "sauf desserte" and the
/// street beyond (ways 116697288 and 174017049, read 2026-10-07).
pub const LOCAL_ACCESS_LINK_M: f64 = 500.0;

/// The parts of a route where limits that spare local access let it
/// through: the runs of `spans` (`(start_m, end_m)` along the route) that
/// join up, each within [`LOCAL_ACCESS_LINK_M`] of the next, and reach a
/// stop within [`LOCAL_ACCESS_STOP_M`]. A run that reaches no stop is
/// through traffic. The spans of the roads enclosed behind a zone
/// ([`super::Restriction::enclosed`]) join a run like the zone's own.
///
/// The engine is more lenient (Valhalla 3.9.0,
/// `DynamicCost::EvaluateRestrictions` and
/// `BidirectionalAStar::SetOrigin`): a trip that starts or ends on a limit
/// marked `except_destination` keeps the right across every road without a
/// limit, gains it on any marked limit the vehicle is under, and loses it
/// on the first road whose limits carry no mark for this kind. So a trip
/// ending in one zone may cross another anywhere on the way. When no route
/// keeps the marks, its second pass ignores them all
/// (`thor_worker_t::get_path`): that is how it reaches a campsite behind a
/// zone, on a road without the plate. The check stops both at the reach of
/// a stop: what it blocks, the engine is asked again around.
#[must_use]
pub fn local_access_runs(stops: &[f64], spans: &[(f64, f64)]) -> Vec<(f64, f64)> {
    let mut sorted: Vec<(f64, f64)> = spans.iter().map(|(a, b)| (a.min(*b), a.max(*b))).collect();
    sorted.sort_by(|x, y| x.0.total_cmp(&y.0));
    let mut runs: Vec<(f64, f64)> = Vec::new();
    for (a, b) in sorted {
        match runs.last_mut() {
            Some(run) if a <= run.1 + LOCAL_ACCESS_LINK_M => run.1 = run.1.max(b),
            _ => runs.push((a, b)),
        }
    }
    runs.retain(|(a, b)| {
        stops
            .iter()
            .any(|s| *s >= a - LOCAL_ACCESS_STOP_M && *s <= b + LOCAL_ACCESS_STOP_M)
    });
    runs
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

    #[test]
    fn local_access_runs_from_a_stop_and_never_across_a_town() {
        // A 10 km trip: stops at 0 and 10 000 m.
        let stops = [0.0, 10_000.0];
        // The last two streets before the destination, end to end, and a
        // "sauf desserte" street crossed at 4 km.
        let spans = [(9_700.0, 9_850.0), (9_858.0, 10_000.0), (4_000.0, 4_200.0)];
        let runs = local_access_runs(&stops, &spans);
        assert_eq!(
            runs,
            vec![(9_700.0, 10_000.0)],
            "the streets reaching the destination are local access, the one crossed at 4 km is not"
        );
        // A run that stops short of the destination left a road without the
        // plate under the stop: the engine gives no right from there.
        assert!(local_access_runs(&stops, &[(9_700.0, 9_900.0)]).is_empty());
        // Unless that road is enclosed behind the zone, and the build gave
        // it the zone's limit: its span joins the run (an aire on a service
        // road 100 m beyond the street, as at Goult).
        assert_eq!(
            local_access_runs(&stops, &[(9_700.0, 9_900.0), (9_900.0, 10_000.0)]),
            vec![(9_700.0, 10_000.0)]
        );
        // From the start too, and around a waypoint.
        assert_eq!(
            local_access_runs(&stops, &[(5.0, 300.0)]),
            vec![(5.0, 300.0)]
        );
        assert_eq!(
            local_access_runs(&[0.0, 5_000.0, 10_000.0], &[(4_900.0, 5_100.0)]),
            vec![(4_900.0, 5_100.0)]
        );
        assert!(local_access_runs(&stops, &[]).is_empty());
    }

    /// The production engine's route from the Lille hub to the centre,
    /// shape points 140 to 175 (2026-10-07, graph `20261006T2326Z-eu`): the
    /// D 93 (way 871761765), then the ramp (way 60840073) from the node at
    /// (50.601383, 3.251952).
    const LILLE_ROUTE: [(f64, f64); 36] = [
        (50.599781, 3.25305),
        (50.599811, 3.253003),
        (50.599839, 3.25297),
        (50.599876, 3.252932),
        (50.599913, 3.252901),
        (50.599964, 3.252861),
        (50.600009, 3.252833),
        (50.600088, 3.252791),
        (50.600445, 3.252621),
        (50.600528, 3.252579),
        (50.600624, 3.252531),
        (50.600697, 3.252488),
        (50.600757, 3.252448),
        (50.600835, 3.252393),
        (50.6009, 3.252343),
        (50.600925, 3.252324),
        (50.600964, 3.252294),
        (50.601383, 3.251952),
        (50.6015, 3.25183),
        (50.601527, 3.251784),
        (50.601558, 3.251717),
        (50.601579, 3.251674),
        (50.601598, 3.251621),
        (50.601612, 3.251563),
        (50.601623, 3.251492),
        (50.601627, 3.251429),
        (50.601625, 3.251359),
        (50.601619, 3.251265),
        (50.60161, 3.251166),
        (50.601594, 3.251068),
        (50.601569, 3.250883),
        (50.60156, 3.250793),
        (50.601543, 3.250614),
        (50.601518, 3.250454),
        (50.601476, 3.250151),
        (50.601465, 3.25005),
    ];
    /// Way 871761763 of the D 93, `maxweight=3.5`, as production's
    /// `route_restrictions` holds it: the branch leaving the ramp's node.
    const LILLE_BRANCH: [(f64, f64); 10] = [
        (50.601383, 3.251952),
        (50.601571, 3.251804),
        (50.601643, 3.251747),
        (50.601747, 3.251669),
        (50.601832, 3.251609),
        (50.601933, 3.251539),
        (50.602011, 3.251488),
        (50.602091, 3.251442),
        (50.602183, 3.251395),
        (50.60225, 3.251363),
    ];
    /// Way 871761765 of the D 93, which the route drives, from the
    /// OpenStreetMap API (2026-10-07).
    const LILLE_D93: [(f64, f64); 17] = [
        (50.599781, 3.253_050_2),
        (50.599_810_7, 3.253_003_2),
        (50.599_838_8, 3.252_969_7),
        (50.599_876_2, 3.252_932_1),
        (50.599_912_8, 3.252_901_3),
        (50.599_963_9, 3.252_861_1),
        (50.600009, 3.252_832_9),
        (50.600_088_2, 3.252_791_3),
        (50.600_444_9, 3.252621),
        (50.600_528_3, 3.252_579_4),
        (50.600_623_6, 3.252_531_1),
        (50.600_696_8, 3.252_488_2),
        (50.600_757_3, 3.252448),
        (50.600_834_7, 3.252393),
        (50.600_900_3, 3.252_343_4),
        (50.600_924_8, 3.252_324_3),
        (50.600_964_1, 3.252_293_8),
    ];

    fn points(lat_lon: &[(f64, f64)]) -> Vec<Position> {
        lat_lon
            .iter()
            .map(|(lat, lon)| Position::new(*lat, *lon).unwrap())
            .collect()
    }

    #[test]
    fn an_openstreetmap_branch_leaving_the_route_s_node_is_not_driven() {
        let route = RouteLine::new(points(&LILLE_ROUTE)).unwrap();
        let branch = points(&LILLE_BRANCH);
        assert!(
            !match_route(&route, &branch, 3.0).is_empty(),
            "within 3 m, the branch that forks at 7 degrees looks driven: the Lille detour"
        );
        assert!(
            match_restriction(&route, &branch, RestrictionSource::Osm).is_empty(),
            "the route takes the ramp; the 3.5 t branch beside it is not on the way"
        );
        let d93 = match_restriction(&route, &points(&LILLE_D93), RestrictionSource::Osm);
        assert_eq!(
            d93.len(),
            1,
            "the way the route drives still counts: {d93:?}"
        );
        assert!(d93[0].end_m - d93[0].start_m > 130.0, "{d93:?}");
        // IGN and DiaLog draw their own centrelines: their tolerance stays.
        for source in [RestrictionSource::Ign, RestrictionSource::Dialog] {
            assert!((source.line_tolerance_m() - source.tolerance_m()).abs() < f64::EPSILON);
        }
    }

    #[test]
    fn a_point_s_distance_to_a_line_or_a_node() {
        let o = limoges();
        let line = [at(o, 0.0, 0.0), at(o, 100.0, 0.0)];
        assert!((distance_to(at(o, 50.0, 30.0), &line) - 30.0).abs() < 0.1);
        assert!((distance_to(at(o, 140.0, 30.0), &line) - 50.0).abs() < 0.1);
        assert!((distance_to(at(o, 0.0, 30.0), &line[..1]) - 30.0).abs() < 0.1);
        assert!(distance_to(o, &[]).is_infinite());
    }

    #[test]
    fn a_short_street_without_the_sign_keeps_a_zone_whole() {
        let stops = [0.0, 10_000.0];
        // The entry of the zone, 264 m left untagged as on the D937, then
        // the destination's street: one run, as the engine drove it.
        assert_eq!(
            local_access_runs(&stops, &[(9_000.0, 9_400.0), (9_664.0, 10_000.0)]),
            vec![(9_000.0, 10_000.0)]
        );
        // 700 m of other streets between them: the first is another zone,
        // crossed on the way.
        assert_eq!(
            local_access_runs(&stops, &[(8_000.0, 8_600.0), (9_300.0, 10_000.0)]),
            vec![(9_300.0, 10_000.0)]
        );
    }

    #[test]
    fn the_marks_of_old_queries_never_hide_a_segment() {
        let mut seen = Seen {
            call: 0,
            marks: Vec::new(),
        };
        seen.start(3);
        assert!(seen.first(1) && !seen.first(1), "once per query");
        seen.start(5);
        assert!(seen.first(1), "a new query meets it again");
        assert!(seen.first(4), "on a longer line too");
        // Four billion queries later the counter starts again: a mark of
        // the query that bore the same number long ago must not count.
        seen.marks[3] = 1;
        seen.call = u32::MAX;
        seen.first(2);
        seen.start(5);
        assert_eq!(seen.call, 1);
        assert!(seen.first(2) && seen.first(3), "{:?}", seen.marks);
    }

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
    fn a_directed_line_counts_only_for_a_route_going_its_way() {
        let route = east_route();
        let eastward = [at(limoges(), 300.0, 0.5), at(limoges(), 500.0, 0.5)];
        let westward = [at(limoges(), 500.0, 0.5), at(limoges(), 300.0, 0.5)];
        assert_eq!(
            match_route_directed(&route, &eastward, 12.0).len(),
            1,
            "the closed carriageway is the one the route drives"
        );
        assert!(
            match_route_directed(&route, &westward, 12.0).is_empty(),
            "a closure of the other carriageway must not send the route around"
        );
        assert_eq!(
            match_route(&route, &westward, 12.0).len(),
            1,
            "undirected matching keeps counting both ways"
        );
    }

    #[test]
    fn a_projection_gives_the_place_along_the_route_and_its_heading() {
        let route = east_route();
        let p = route.project(at(limoges(), 420.0, 4.0), 10.0).unwrap();
        assert!((p.along_m - 420.0).abs() < 1.0, "{p:?}");
        assert!((p.distance_m - 4.0).abs() < 0.5);
        assert!((p.heading_deg - 90.0).abs() < 1.0, "the route heads east");
        assert!(route.project(at(limoges(), 420.0, 40.0), 10.0).is_none());
        assert!((route.heading_at(10.0) - 90.0).abs() < 1.0);
        assert!((turn_between(10.0, 350.0) - 20.0).abs() < 1e-9);
        assert!((turn_between(90.0, 270.0) - 180.0).abs() < 1e-9);
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
