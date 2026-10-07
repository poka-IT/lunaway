//! Positions on the Earth and the distances between them.

use serde::{Deserialize, Serialize};

/// Mean Earth radius (IUGG), in metres. The haversine error against the
/// ellipsoid stays under 0.5 %, far below the radii the conflation works with.
pub const EARTH_RADIUS_M: f64 = 6_371_008.8;

/// A coordinate outside the WGS 84 range, or not a finite number.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[error("invalid position: lat {lat}, lon {lon}")]
pub struct InvalidPosition {
    /// The latitude as received.
    pub lat: f64,
    /// The longitude as received.
    pub lon: f64,
}

/// A WGS 84 point, validated on construction so that no raw pair of floats
/// crosses a boundary unchecked.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "RawPosition", into = "RawPosition")]
pub struct Position {
    lat: f64,
    lon: f64,
}

#[derive(Serialize, Deserialize)]
struct RawPosition {
    lat: f64,
    lon: f64,
}

impl TryFrom<RawPosition> for Position {
    type Error = InvalidPosition;

    fn try_from(raw: RawPosition) -> Result<Self, Self::Error> {
        Self::new(raw.lat, raw.lon)
    }
}

impl From<Position> for RawPosition {
    fn from(p: Position) -> Self {
        Self {
            lat: p.lat,
            lon: p.lon,
        }
    }
}

impl Position {
    /// A position, if `lat` is in [-90, 90] and `lon` in [-180, 180].
    ///
    /// # Errors
    ///
    /// [`InvalidPosition`] when a coordinate is out of range or not finite.
    pub fn new(lat: f64, lon: f64) -> Result<Self, InvalidPosition> {
        if lat.is_finite()
            && lon.is_finite()
            && (-90.0..=90.0).contains(&lat)
            && (-180.0..=180.0).contains(&lon)
        {
            Ok(Self { lat, lon })
        } else {
            Err(InvalidPosition { lat, lon })
        }
    }

    /// Latitude in degrees.
    #[must_use]
    pub const fn lat(self) -> f64 {
        self.lat
    }

    /// Longitude in degrees.
    #[must_use]
    pub const fn lon(self) -> f64 {
        self.lon
    }

    /// Great-circle distance to `other`, in metres (haversine on a sphere).
    #[must_use]
    pub fn distance_m(self, other: Self) -> f64 {
        let (phi1, phi2) = (self.lat.to_radians(), other.lat.to_radians());
        let dphi = (other.lat - self.lat).to_radians();
        let dlambda = (other.lon - self.lon).to_radians();
        let h =
            (dphi / 2.0).sin().powi(2) + phi1.cos() * phi2.cos() * (dlambda / 2.0).sin().powi(2);
        // `min` guards asin against a rounding error just above 1.
        2.0 * EARTH_RADIUS_M * h.sqrt().min(1.0).asin()
    }

    /// The nearest node of the [`COARSE_GRID_DEG`] grid: what the API keeps
    /// of a position a client sends for a search around it, so the promise
    /// "about 5 km" holds whatever the client rounded.
    #[must_use]
    pub fn coarsened(self) -> Self {
        self.snapped(COARSE_STEPS_PER_DEG)
    }

    /// The nearest node of the [`LIST_GRID_DEG`] grid: what the API keeps of
    /// the point a list of places is sorted around (the map's centre), so no
    /// finer position is ever used, whatever the client sent.
    #[must_use]
    pub fn on_list_grid(self) -> Self {
        self.snapped(LIST_STEPS_PER_DEG)
    }

    fn snapped(self, steps_per_deg: f64) -> Self {
        // A multiple of the step within [-90, 90] and [-180, 180] stays in
        // range: the extremes are multiples themselves.
        let snap = |v: f64| (v * steps_per_deg).round() / steps_per_deg;
        Self {
            lat: snap(self.lat),
            lon: snap(self.lon),
        }
    }
}

/// The step of the grid a list of places sorted by distance is anchored
/// on, degrees: 0.01, about 1.1 km of latitude. The map's tiles already
/// tell the server which area is viewed; the anchor adds nothing finer.
pub const LIST_GRID_DEG: f64 = 0.01;

/// Nodes of [`LIST_GRID_DEG`] per degree, for an exact rounding.
const LIST_STEPS_PER_DEG: f64 = 100.0;

/// The step of the grid searches are anchored on, degrees: 0.05, about
/// 5.6 km of latitude and 3.9 km of longitude at 45° N. The app rounds to
/// the same grid before it sends (`searchAnchor`, `fuel_feed_providers`).
pub const COARSE_GRID_DEG: f64 = 0.05;

/// Nodes of the grid per degree: rounding `v * 20` is exact where rounding
/// `v / 0.05` is not (0.05 has no exact binary form).
const COARSE_STEPS_PER_DEG: f64 = 20.0;

/// A line with its two ends cut away, and how far along the original line
/// it starts.
#[derive(Debug, Clone, PartialEq)]
pub struct TrimmedLine {
    /// What is left, from the first cut to the second.
    pub points: Vec<Position>,
    /// Metres along the original line before the first point left.
    pub head_m: f64,
    /// Length of the original line, metres.
    pub total_m: f64,
}

/// `line` without its ends: it starts where it first gets `radius_m` away
/// (straight line) from its first point, and ends where it last was
/// `radius_m` away from its last point. A route's ends are where the
/// device is and where it goes: the part of the line that leads out of
/// either circle goes, at least `radius_m` of line at each end (a route
/// that comes back near its start later keeps that later part). `None`
/// when nothing is left: the line never leaves a circle, or the two cuts
/// cross.
#[must_use]
pub fn trim_ends(line: &[Position], radius_m: f64) -> Option<TrimmedLine> {
    let (first, last) = (*line.first()?, *line.last()?);
    let total_m: f64 = line.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    // Half a metre past the circle: a cut point written with six decimals
    // (0.11 m at most) for the routing engine stays outside it.
    let radius_m = radius_m + 0.5;
    let (head_seg, head_t, head_at) = leave_circle(line.iter().copied(), first, radius_m)?;
    let reversed = line.iter().rev().copied();
    let (tail_rseg, tail_rt, tail_at) = leave_circle(reversed, last, radius_m)?;
    // In the forward direction, the tail's cut lies on segment `tail_seg`
    // (from point `tail_seg` to `tail_seg + 1`) at `1 - tail_rt`.
    let tail_seg = line.len() - 2 - tail_rseg;
    let tail_t = 1.0 - tail_rt;
    if (head_seg, head_t) >= (tail_seg, tail_t) {
        return None;
    }
    let head_m = line[..=head_seg]
        .windows(2)
        .map(|w| w[0].distance_m(w[1]))
        .sum::<f64>()
        + line[head_seg].distance_m(head_at);
    let mut points = Vec::with_capacity(tail_seg - head_seg + 2);
    points.push(head_at);
    points.extend_from_slice(&line[head_seg + 1..=tail_seg]);
    points.push(tail_at);
    Some(TrimmedLine {
        points,
        head_m,
        total_m,
    })
}

/// Where the line `points` first leaves the circle of `radius_m` around
/// `centre`: the segment (its first point's index), the fraction along it,
/// and the point, at least `radius_m` from `centre`.
fn leave_circle(
    points: impl Iterator<Item = Position>,
    centre: Position,
    radius_m: f64,
) -> Option<(usize, f64, Position)> {
    let mut prev: Option<Position> = None;
    for (i, p) in points.enumerate() {
        if let Some(a) = prev
            && p.distance_m(centre) >= radius_m
        {
            // `a` is inside, `p` outside: bisect for the crossing, keeping
            // the outer end so the cut is never inside the circle.
            let (mut lo, mut hi) = (0.0_f64, 1.0_f64);
            for _ in 0..40 {
                let mid = f64::midpoint(lo, hi);
                if lerp(a, p, mid).distance_m(centre) >= radius_m {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }
            return Some((i - 1, hi, lerp(a, p, hi)));
        }
        prev = Some(p);
    }
    None
}

/// The point at fraction `t` of the way from `a` to `b`, in degrees: on
/// the segments of a route, a few kilometres long at most, the difference
/// with the great circle is far below a metre.
fn lerp(a: Position, b: Position, t: f64) -> Position {
    Position {
        lat: a.lat + (b.lat - a.lat) * t,
        lon: a.lon + (b.lon - a.lon) * t,
    }
}

/// A latitude/longitude rectangle, south-west to north-east. It never crosses
/// the antimeridian: `west <= east` is part of its validity.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BBox {
    south: f64,
    west: f64,
    north: f64,
    east: f64,
}

/// Why a bounding box was refused.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidBBox {
    /// A corner is outside the WGS 84 range or not finite.
    #[error("a corner of the box is not a valid position")]
    Corner(#[from] InvalidPosition),
    /// South is above north or west is east of east.
    #[error("the box is inverted (south must be <= north and west <= east)")]
    Inverted,
}

impl BBox {
    /// A box from its four edges, in degrees.
    ///
    /// # Errors
    ///
    /// [`InvalidBBox`] when a corner is invalid or the box is inverted.
    pub fn new(south: f64, west: f64, north: f64, east: f64) -> Result<Self, InvalidBBox> {
        Position::new(south, west)?;
        Position::new(north, east)?;
        if south > north || west > east {
            return Err(InvalidBBox::Inverted);
        }
        Ok(Self {
            south,
            west,
            north,
            east,
        })
    }

    /// Southern edge, degrees of latitude.
    #[must_use]
    pub const fn south(self) -> f64 {
        self.south
    }

    /// Western edge, degrees of longitude.
    #[must_use]
    pub const fn west(self) -> f64 {
        self.west
    }

    /// Northern edge, degrees of latitude.
    #[must_use]
    pub const fn north(self) -> f64 {
        self.north
    }

    /// Eastern edge, degrees of longitude.
    #[must_use]
    pub const fn east(self) -> f64 {
        self.east
    }

    /// Area in square degrees: the unit the API bounds viewports with,
    /// because it is what a client can compute without a projection.
    #[must_use]
    pub fn area_deg2(self) -> f64 {
        (self.north - self.south) * (self.east - self.west)
    }

    /// Whether `p` lies inside the box, edges included.
    #[must_use]
    pub fn contains(self, p: Position) -> bool {
        (self.south..=self.north).contains(&p.lat) && (self.west..=self.east).contains(&p.lon)
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn out_of_range_coordinates_are_refused() {
        assert!(Position::new(90.1, 0.0).is_err());
        assert!(Position::new(0.0, -180.5).is_err());
        assert!(Position::new(f64::NAN, 0.0).is_err());
        assert!(Position::new(f64::INFINITY, 0.0).is_err());
        assert!(Position::new(-90.0, 180.0).is_ok());
    }

    #[test]
    fn a_known_distance_is_measured() {
        // Paris Notre-Dame to the Eiffel Tower: 4.1 km on the map.
        let notre_dame = Position::new(48.852_968, 2.349_902).unwrap();
        let eiffel = Position::new(48.858_370, 2.294_481).unwrap();
        let d = notre_dame.distance_m(eiffel);
        assert!((d - 4_100.0).abs() < 60.0, "got {d}");
    }

    #[test]
    fn one_millidegree_of_latitude_is_about_111_metres() {
        let a = Position::new(45.0, 3.0).unwrap();
        let b = Position::new(45.001, 3.0).unwrap();
        assert!((a.distance_m(b) - 111.2).abs() < 0.5);
    }

    #[test]
    fn serde_refuses_an_invalid_position() {
        let ok: Position = serde_json::from_str(r#"{"lat":1.5,"lon":2.5}"#).unwrap();
        assert_eq!((ok.lat(), ok.lon()), (1.5, 2.5));
        assert!(serde_json::from_str::<Position>(r#"{"lat":100.0,"lon":2.5}"#).is_err());
    }

    #[test]
    fn a_bbox_validates_its_edges() {
        assert_eq!(BBox::new(46.0, 3.0, 45.0, 4.0), Err(InvalidBBox::Inverted));
        assert_eq!(BBox::new(45.0, 4.0, 46.0, 3.0), Err(InvalidBBox::Inverted));
        assert!(matches!(
            BBox::new(45.0, 3.0, 91.0, 4.0),
            Err(InvalidBBox::Corner(_))
        ));
        let b = BBox::new(45.0, 3.0, 46.0, 5.0).unwrap();
        assert!((b.area_deg2() - 2.0).abs() < 1e-12);
        assert!(
            b.contains(Position::new(45.0, 5.0).unwrap()),
            "edges are inside"
        );
        assert!(!b.contains(Position::new(46.1, 4.0).unwrap()));
    }

    fn position() -> impl Strategy<Value = Position> {
        (-90.0..=90.0f64, -180.0..=180.0f64).prop_map(|(lat, lon)| Position::new(lat, lon).unwrap())
    }

    #[test]
    fn a_position_snaps_to_the_grid_the_app_uses() {
        let p = Position::new(45.123_456, 4.876_543).unwrap().coarsened();
        assert_eq!((p.lat(), p.lon()), (45.1, 4.9));
        let again = p.coarsened();
        assert_eq!(
            again, p,
            "a position the app already rounded must reach the server unchanged"
        );
        let edge = Position::new(-90.0, 180.0).unwrap().coarsened();
        assert_eq!((edge.lat(), edge.lon()), (-90.0, 180.0));
        let half = Position::new(0.025, -0.025).unwrap().coarsened();
        assert_eq!(
            (half.lat(), half.lon()),
            (0.05, -0.05),
            "half a step rounds away from zero, as Dart's round() does"
        );
    }

    #[test]
    fn a_list_anchor_keeps_a_hundredth_of_a_degree() {
        let p = Position::new(45.123_456, -4.876_543)
            .unwrap()
            .on_list_grid();
        assert_eq!((p.lat(), p.lon()), (45.12, -4.88));
        assert_eq!(p.on_list_grid(), p, "already on the grid, unchanged");
        let edge = Position::new(90.0, -180.0).unwrap().on_list_grid();
        assert_eq!((edge.lat(), edge.lon()), (90.0, -180.0));
    }

    /// A line north from (45, 3), one point every 100 m, `km` long.
    fn north_line(km: u32) -> Vec<Position> {
        (0..=km * 10)
            .map(|i| Position::new(45.0 + f64::from(i) * 0.000_899_3, 3.0).unwrap())
            .collect()
    }

    #[test]
    fn a_line_loses_two_kilometres_at_each_end() {
        let line = north_line(10);
        let t = trim_ends(&line, 2_000.0).unwrap();
        let (first, last) = (line[0], line[line.len() - 1]);
        for p in &t.points {
            assert!(
                p.distance_m(first) >= 2_000.0 && p.distance_m(last) >= 2_000.0,
                "no point of the line sent may lie within 2 km of either end: {p:?}"
            );
        }
        assert!(
            t.points[0].distance_m(first) < 2_001.0,
            "the cut is where the line leaves the circle, not a segment later"
        );
        assert!((t.head_m - 2_000.0).abs() < 1.0, "head {}", t.head_m);
        assert!((t.total_m - 10_000.0).abs() < 10.0, "total {}", t.total_m);
    }

    #[test]
    fn a_long_segment_is_cut_inside_it() {
        let line = [
            Position::new(45.0, 3.0).unwrap(),
            Position::new(45.1, 3.0).unwrap(),
        ];
        let t = trim_ends(&line, 2_000.0).unwrap();
        assert_eq!(t.points.len(), 2);
        assert!((t.points[0].distance_m(line[0]) - 2_000.0).abs() < 1.0);
        assert!((t.points[1].distance_m(line[1]) - 2_000.0).abs() < 1.0);
        assert!(t.points[0].distance_m(line[0]) >= 2_000.0);
    }

    #[test]
    fn a_line_too_short_keeps_nothing() {
        assert_eq!(trim_ends(&north_line(4)[..39], 2_000.0), None);
        assert_eq!(
            trim_ends(&[Position::new(45.0, 3.0).unwrap()], 2_000.0),
            None
        );
    }

    proptest! {
        #[test]
        fn trimmed_ends_are_never_near_the_true_ends(
            start in (44.0..46.0f64, 2.0..4.0f64),
            steps in prop::collection::vec((-0.02..0.02f64, -0.02..0.02f64), 1..60),
        ) {
            let mut line = vec![Position::new(start.0, start.1).unwrap()];
            for (dlat, dlon) in steps {
                let p = line[line.len() - 1];
                line.push(Position::new(p.lat() + dlat, p.lon() + dlon).unwrap());
            }
            if let Some(t) = trim_ends(&line, 2_000.0) {
                let (first, last) = (line[0], line[line.len() - 1]);
                prop_assert!(t.points.len() >= 2);
                prop_assert!(t.points[0].distance_m(first) >= 2_000.0);
                prop_assert!(t.points[t.points.len() - 1].distance_m(last) >= 2_000.0);
                prop_assert!(t.head_m >= 2_000.0 && t.head_m <= t.total_m);
            }
        }
    }

    proptest! {
        #[test]
        fn distance_is_a_symmetric_non_negative_measure(a in position(), b in position()) {
            let d = a.distance_m(b);
            prop_assert!(d >= 0.0);
            prop_assert!((d - b.distance_m(a)).abs() < 1e-6);
            prop_assert!(a.distance_m(a) < 1e-6);
            // Half the circumference is the farthest two points can be.
            prop_assert!(d <= std::f64::consts::PI * EARTH_RADIUS_M + 1.0);
        }
    }
}
