//! Fuel for a motorhome: the stations along a route, what the detour to
//! each costs, and the price history a station shows.
//!
//! A station is in a route's corridor when its straight-line distance to
//! the route is at most half the detour the driver accepts: going there and
//! back is at least twice that distance. The candidates are ranked first on
//! an estimate of the detour (the straight line times [`ROAD_FACTOR`]), the
//! best ones measured by the routing engine, and every station is then
//! ranked on its effective price: the price per litre plus the fuel the
//! detour burns, spread over the litres bought.

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, NaiveDate, Utc};

use crate::Position;

/// A price older than this is not offered: on 2026-10-06, 9 of the 9 006
/// diesel prices of the feed and 183 of its 1 513 LPG prices were older,
/// stations that stopped updating rather than prices still charged.
pub const MAX_PRICE_AGE_DAYS: i64 = 90;

/// Days of price history kept per station and fuel.
pub const PRICE_HISTORY_DAYS: i64 = 30;

/// Ratio of the road distance to the straight line, for the estimate that
/// ranks the candidates before the engine measures them.
pub const ROAD_FACTOR: f64 = 1.3;

/// Speed of an estimated detour, km/h: town and secondary roads.
pub const ESTIMATE_SPEED_KPH: f64 = 50.0;

/// How far before and after a station, along the route, its detour is
/// measured from: far enough that the way to the station and back starts
/// and ends on the route, near enough that the engine's direct leg is the
/// route itself.
pub const ANCHOR_REACH_M: f64 = 3_000.0;

/// Metres per degree of latitude.
const METRES_PER_DEGREE: f64 = 111_195.0;

/// Smallest grid cell of a corridor, degrees of latitude (about 550 m): a
/// narrower corridor would index a long route in too many cells.
const MIN_CELL_DEG: f64 = 0.005;

/// `b - a` in metres east and north, on a plane tangent at `a`.
fn offset(a: Position, b: Position) -> (f64, f64) {
    (
        (b.lon() - a.lon()) * METRES_PER_DEGREE * a.lat().to_radians().cos(),
        (b.lat() - a.lat()) * METRES_PER_DEGREE,
    )
}

/// Most degrees a corridor's line may cover, summed over its segments, each
/// counted by its larger span (latitude or longitude): the grid indexes a
/// segment cell by cell, so a line jumping across the antimeridian and back
/// would cost gigabytes while measuring a few kilometres. A 2 500 km route
/// due east at 71° N covers 2 500 / 36.2 = 69° of longitude.
pub const MAX_LINE_SPAN_DEG: f64 = 100.0;

/// Most segments of the line one cell of the grid may list: a station
/// checks every segment of its cell, and a line folding back and forth over
/// one place would make each check scan the whole line. A real route
/// crosses a 15 km cell once or twice, a few hundred segments.
pub const MAX_SEGMENTS_PER_CELL: usize = 5_000;

/// The degrees `points` cover, summed over its segments ([`MAX_LINE_SPAN_DEG`]).
#[must_use]
pub fn line_span_deg(points: &[Position]) -> f64 {
    points
        .windows(2)
        .map(|w| {
            (w[1].lat() - w[0].lat())
                .abs()
                .max((w[1].lon() - w[0].lon()).abs())
        })
        .sum()
}

/// A route and the band around it where a station is a candidate.
#[derive(Debug, Clone)]
pub struct Corridor {
    points: Vec<Position>,
    along: Vec<f64>,
    half_width_m: f64,
    cell_lat: f64,
    cell_lon: f64,
    cells: HashMap<(i64, i64), Vec<u32>>,
}

/// Where a station lies from a route.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Located {
    /// Distance from the route's start to the nearest point, metres.
    pub along_m: f64,
    /// Straight-line distance from that point, metres.
    pub offset_m: f64,
}

/// A point of the route a detour is measured from.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Anchor {
    /// Where.
    pub at: Position,
    /// Distance from the route's start, metres.
    pub along_m: f64,
    /// The route's heading there, degrees from north: it puts the anchor on
    /// the carriageway the route drives.
    pub heading_deg: f64,
}

impl Corridor {
    /// The band of `half_width_m` metres around the route `points` (in
    /// driving order); none for fewer than two points, a width that is not
    /// a positive number, a line over [`MAX_LINE_SPAN_DEG`], or one folding
    /// over a cell more than [`MAX_SEGMENTS_PER_CELL`] times.
    #[must_use]
    pub fn new(points: Vec<Position>, half_width_m: f64) -> Option<Self> {
        if points.len() < 2
            || !(half_width_m.is_finite() && half_width_m > 0.0)
            || line_span_deg(&points) > MAX_LINE_SPAN_DEG
        {
            return None;
        }
        let mut along = Vec::with_capacity(points.len());
        let mut total = 0.0;
        for (i, p) in points.iter().enumerate() {
            if i > 0 {
                total += points[i - 1].distance_m(*p);
            }
            along.push(total);
        }
        let cell_lat = (half_width_m / METRES_PER_DEGREE).max(MIN_CELL_DEG);
        // A degree of longitude shrinks with the latitude: the cell is as
        // wide in metres as it is high where the route is farthest north,
        // so the eight neighbours of a cell cover the band everywhere.
        let max_lat = points.iter().map(|p| p.lat().abs()).fold(0.0_f64, f64::max);
        let cell_lon = cell_lat / (max_lat + cell_lat).min(85.0).to_radians().cos();
        let mut cells: HashMap<(i64, i64), Vec<u32>> = HashMap::new();
        for (i, pair) in points.windows(2).enumerate() {
            let Ok(segment) = u32::try_from(i) else { break };
            let (a, b) = (pair[0], pair[1]);
            let span =
                ((b.lat() - a.lat()).abs() / cell_lat).max((b.lon() - a.lon()).abs() / cell_lon);
            #[allow(
                clippy::cast_possible_truncation,
                clippy::cast_sign_loss,
                reason = "a positive count of half cells along one segment, bounded by the span budget"
            )]
            let steps = (span * 2.0).ceil() as u32 + 1;
            let mut seen: HashSet<(i64, i64)> = HashSet::new();
            for s in 0..=steps {
                let t = f64::from(s) / f64::from(steps);
                let lat = a.lat() + (b.lat() - a.lat()) * t;
                let lon = a.lon() + (b.lon() - a.lon()) * t;
                let c = Self::cell_of(lat, lon, cell_lat, cell_lon);
                if seen.insert(c) {
                    for dr in -1..=1 {
                        for dc in -1..=1 {
                            let list = cells.entry((c.0 + dr, c.1 + dc)).or_default();
                            if list.last() != Some(&segment) {
                                list.push(segment);
                            }
                        }
                    }
                }
            }
        }
        if cells
            .values()
            .any(|list| list.len() > MAX_SEGMENTS_PER_CELL)
        {
            return None;
        }
        Some(Self {
            points,
            along,
            half_width_m,
            cell_lat,
            cell_lon,
            cells,
        })
    }

    #[allow(
        clippy::cast_possible_truncation,
        reason = "a cell index of a valid coordinate is far inside i64"
    )]
    fn cell_of(lat: f64, lon: f64, cell_lat: f64, cell_lon: f64) -> (i64, i64) {
        (
            (lat / cell_lat).floor() as i64,
            (lon / cell_lon).floor() as i64,
        )
    }

    /// The route's points, in driving order.
    #[must_use]
    pub fn points(&self) -> &[Position] {
        &self.points
    }

    /// Distance from the start of each point, metres.
    #[must_use]
    pub fn along(&self) -> &[f64] {
        &self.along
    }

    /// The route's length, metres.
    #[must_use]
    pub fn length_m(&self) -> f64 {
        self.along.last().copied().unwrap_or(0.0)
    }

    /// Half the band's width, metres.
    #[must_use]
    pub const fn half_width_m(&self) -> f64 {
        self.half_width_m
    }

    /// Where `p` lies from the route, when it is inside the band: the
    /// nearest point of the route, whichever pass of the route it belongs
    /// to.
    #[must_use]
    pub fn locate(&self, p: Position) -> Option<Located> {
        let (r, c) = Self::cell_of(p.lat(), p.lon(), self.cell_lat, self.cell_lon);
        let list = self.cells.get(&(r, c))?;
        let mut best: Option<Located> = None;
        for &seg in list {
            let i = seg as usize;
            let (ax, ay) = offset(p, self.points[i]);
            let (bx, by) = offset(p, self.points[i + 1]);
            let (dx, dy) = (bx - ax, by - ay);
            let len2 = dx * dx + dy * dy;
            let t = if len2 > 0.0 {
                (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let d = (ax + t * dx).hypot(ay + t * dy);
            if d <= self.half_width_m && best.is_none_or(|b| d < b.offset_m) {
                best = Some(Located {
                    along_m: self.along[i] + t * (self.along[i + 1] - self.along[i]),
                    offset_m: d,
                });
            }
        }
        best
    }

    /// The segment `s` metres from the start lies on: the index of its
    /// first point.
    fn segment_at(&self, s: f64) -> usize {
        self.along
            .partition_point(|a| *a <= s)
            .saturating_sub(1)
            .min(self.points.len() - 2)
    }

    /// The point `s` metres from the start (clamped to the route).
    #[must_use]
    pub fn point_at(&self, s: f64) -> Position {
        let i = self.segment_at(s);
        let (a, b) = (self.points[i], self.points[i + 1]);
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
        .unwrap_or(a)
    }

    /// The route's heading `s` metres from the start, degrees from north
    /// (0 to 360).
    #[must_use]
    pub fn heading_at(&self, s: f64) -> f64 {
        let i = self.segment_at(s);
        crate::routing::corridor::heading(self.points[i], self.points[i + 1]).rem_euclid(360.0)
    }

    /// The points before and after `along_m` a detour is measured from,
    /// [`ANCHOR_REACH_M`] away along the route, or the route's ends.
    #[must_use]
    pub fn anchors(&self, along_m: f64) -> (Anchor, Anchor) {
        let length = self.length_m();
        let anchor = |s: f64| {
            let s = s.clamp(0.0, length);
            Anchor {
                at: self.point_at(s),
                along_m: s,
                heading_deg: self.heading_at(s),
            }
        };
        (
            anchor(along_m - ANCHOR_REACH_M),
            anchor(along_m + ANCHOR_REACH_M),
        )
    }
}

/// A leg the engine measured.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Leg {
    /// Kilometres.
    pub km: f64,
    /// Seconds.
    pub seconds: f64,
}

/// What reaching a station off the route adds to the trip.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Detour {
    /// Kilometres more than the route.
    pub km: f64,
    /// Minutes more than the route.
    pub minutes: f64,
    /// Measured by the engine; an estimate otherwise.
    pub measured: bool,
}

impl Detour {
    /// The detour of a station the engine measured: from the anchor before
    /// to the station, from the station to the anchor after, against the
    /// direct way between the anchors. A station on the route costs nothing
    /// more; the engine's legs can make it slightly negative.
    #[must_use]
    pub fn measured(to_station: Leg, from_station: Leg, direct: Leg) -> Self {
        Self {
            km: (to_station.km + from_station.km - direct.km).max(0.0),
            minutes: ((to_station.seconds + from_station.seconds - direct.seconds) / 60.0).max(0.0),
            measured: true,
        }
    }

    /// The estimate for a station `offset_m` from the route: there and back
    /// in a straight line, times [`ROAD_FACTOR`], at
    /// [`ESTIMATE_SPEED_KPH`].
    #[must_use]
    pub fn estimated(offset_m: f64) -> Self {
        let km = 2.0 * offset_m.max(0.0) * ROAD_FACTOR / 1_000.0;
        Self {
            km,
            minutes: km / ESTIMATE_SPEED_KPH * 60.0,
            measured: false,
        }
    }
}

/// What the driver buys and burns.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Refuel {
    /// Litres per 100 km.
    pub consumption_l_per_100km: f64,
    /// Litres bought at the station.
    pub fill_litres: f64,
}

/// A price with the detour's fuel in it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Effective {
    /// Litres the detour burns.
    pub detour_litres: f64,
    /// What they cost at the station's price, euros.
    pub detour_cost_eur: f64,
    /// The price per litre bought, the detour's fuel spread over the fill.
    pub price_eur: f64,
}

impl Refuel {
    /// The effective price of `price_eur` a litre `detour_km` off the route.
    /// Time is not priced: the detour's minutes are shown beside it.
    #[must_use]
    pub fn effective(&self, price_eur: f64, detour_km: f64) -> Effective {
        let detour_litres = detour_km.max(0.0) * self.consumption_l_per_100km / 100.0;
        let detour_cost_eur = detour_litres * price_eur;
        Effective {
            detour_litres,
            detour_cost_eur,
            price_eur: price_eur + detour_cost_eur / self.fill_litres.max(1.0),
        }
    }
}

/// Splits stations sorted by their distance along the route into runs no
/// longer than `max_span_m` from first to last: one engine call measures a
/// run, and keeping it short keeps the engine's work local (it computes
/// every pair of a matrix).
#[must_use]
pub fn runs(alongs_m: &[f64], max_span_m: f64) -> Vec<std::ops::Range<usize>> {
    let mut out = Vec::new();
    let mut start = 0;
    for i in 1..=alongs_m.len() {
        if i == alongs_m.len() || alongs_m[i] - alongs_m[start] > max_span_m {
            if start < i {
                out.push(start..i);
            }
            start = i;
        }
    }
    out
}

/// The day a price seen at `at` counts for: the date in Paris, where the
/// feed's stations are.
#[must_use]
pub fn price_day(at: DateTime<Utc>) -> NaiveDate {
    at.with_timezone(&chrono_tz::Europe::Paris).date_naive()
}

/// Whether a price updated at `updated_at` is still offered at `now`
/// ([`MAX_PRICE_AGE_DAYS`]).
#[must_use]
pub fn price_is_current(updated_at: DateTime<Utc>, now: DateTime<Utc>) -> bool {
    now - updated_at <= chrono::Duration::days(MAX_PRICE_AGE_DAYS)
}

/// The lowest and highest price a station showed for a fuel on one day
/// (Paris time), as the importer saw it at each poll.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PriceDay {
    /// The day.
    pub day: NaiveDate,
    /// Lowest price seen that day, euros per litre.
    pub low_eur: f64,
    /// Highest price seen that day.
    pub high_eur: f64,
}

/// What the days of a span say.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PriceSpan {
    /// Lowest price of the span.
    pub low_eur: f64,
    /// Highest price of the span.
    pub high_eur: f64,
    /// Days of the span with a price.
    pub days_known: u32,
    /// The last day's low minus the first day's low; none with fewer than
    /// two days known.
    pub change_eur: Option<f64>,
}

/// The span of the `length_days` days ending with `today`, from `days` in
/// any order; none when no day of the span is known.
#[must_use]
pub fn price_span(days: &[PriceDay], today: NaiveDate, length_days: i64) -> Option<PriceSpan> {
    let first = today - chrono::Duration::days(length_days - 1);
    let mut inside: Vec<&PriceDay> = days
        .iter()
        .filter(|d| d.day >= first && d.day <= today)
        .collect();
    inside.sort_by_key(|d| d.day);
    let (oldest, newest) = (inside.first()?, inside.last()?);
    Some(PriceSpan {
        low_eur: inside
            .iter()
            .map(|d| d.low_eur)
            .fold(f64::INFINITY, f64::min),
        high_eur: inside
            .iter()
            .map(|d| d.high_eur)
            .fold(f64::NEG_INFINITY, f64::max),
        days_known: u32::try_from(inside.len()).unwrap_or(u32::MAX),
        change_eur: (inside.len() > 1).then_some(newest.low_eur - oldest.low_eur),
    })
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use super::*;

    fn p(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    #[test]
    fn a_station_is_in_the_band_up_to_its_half_width() {
        // A straight route of about 11 km due east at 45° N.
        let c = Corridor::new(vec![p(45.0, 1.0), p(45.0, 1.14)], 2_000.0).unwrap();
        let near = c.locate(p(45.017, 1.07)).unwrap();
        assert!((near.offset_m - 1_890.0).abs() < 10.0, "{near:?}");
        assert!((near.along_m - c.length_m() / 2.0).abs() < 50.0);
        assert!(c.locate(p(45.02, 1.07)).is_none(), "2.2 km off is outside");
        assert!(
            c.locate(p(45.0, 1.168)).is_none(),
            "past the end, 2.2 km away"
        );
        let (a, b) = c.anchors(near.along_m);
        assert!((b.along_m - a.along_m - 2.0 * ANCHOR_REACH_M).abs() < 1.0);
        assert!((a.heading_deg - 90.0).abs() < 1.0, "the route drives east");
        let (start, _) = c.anchors(500.0);
        assert!(start.along_m.abs() < 1e-9, "clamped to the route's start");
    }

    #[test]
    fn the_band_holds_far_north_where_a_degree_of_longitude_is_short() {
        // Near Tromsø, a degree of longitude is about 39 km: a route due
        // north, and a station 4.9 km east of it.
        let c = Corridor::new(vec![p(69.4, 18.0), p(69.8, 18.0)], 5_000.0).unwrap();
        let east_deg = 4_900.0 / (METRES_PER_DEGREE * 69.6_f64.to_radians().cos());
        let east = c.locate(p(69.6, 18.0 + east_deg)).unwrap();
        assert!((east.offset_m - 4_900.0).abs() < 5.0, "{east:?}");
        assert!(c.locate(p(69.6, 18.0 + 1.1 * east_deg)).is_none());
    }

    #[test]
    fn a_line_across_the_globe_and_back_is_refused() {
        let mut zigzag = Vec::new();
        for i in 0..1_000 {
            zigzag.push(p(0.0, if i % 2 == 0 { -179.99 } else { 179.99 }));
        }
        assert!(line_span_deg(&zigzag) > MAX_LINE_SPAN_DEG);
        assert!(
            Corridor::new(zigzag, 250.0).is_none(),
            "the grid of such a line would take gigabytes"
        );
    }

    #[test]
    fn a_line_folding_over_one_place_is_refused() {
        // 6 000 segments back and forth over 125 m: 750 m of span, a
        // grid of one cell listing every segment.
        let folded: Vec<Position> = (0..6_001)
            .map(|i| p(45.0, if i % 2 == 0 { 1.0 } else { 1.0016 }))
            .collect();
        assert!(line_span_deg(&folded) < MAX_LINE_SPAN_DEG);
        assert!(Corridor::new(folded, 15_000.0).is_none());
    }

    #[test]
    fn the_detour_s_fuel_is_spread_over_the_fill() {
        let r = Refuel {
            consumption_l_per_100km: 12.0,
            fill_litres: 60.0,
        };
        let e = r.effective(2.0, 10.0);
        assert!((e.detour_litres - 1.2).abs() < 1e-9);
        assert!((e.detour_cost_eur - 2.4).abs() < 1e-9);
        assert!((e.price_eur - 2.04).abs() < 1e-9);
        assert!((r.effective(2.0, -1.0).price_eur - 2.0).abs() < 1e-9);
    }

    #[test]
    fn a_detour_is_the_way_there_and_back_less_the_direct_way() {
        let d = Detour::measured(
            Leg {
                km: 4.0,
                seconds: 300.0,
            },
            Leg {
                km: 5.0,
                seconds: 360.0,
            },
            Leg {
                km: 6.0,
                seconds: 240.0,
            },
        );
        assert!((d.km - 3.0).abs() < 1e-9 && (d.minutes - 7.0).abs() < 1e-9);
        let on_route = Detour::measured(
            Leg {
                km: 3.0,
                seconds: 100.0,
            },
            Leg {
                km: 2.99,
                seconds: 99.0,
            },
            Leg {
                km: 6.0,
                seconds: 200.0,
            },
        );
        assert!(on_route.km.abs() < 1e-9 && on_route.minutes.abs() < 1e-9);
        let e = Detour::estimated(1_000.0);
        assert!((e.km - 2.6).abs() < 1e-9 && !e.measured);
    }

    #[test]
    fn a_price_counts_for_its_day_in_paris() {
        let late = DateTime::parse_from_rfc3339("2026-10-06T22:30:00Z")
            .unwrap()
            .with_timezone(&Utc);
        assert_eq!(
            price_day(late),
            NaiveDate::from_ymd_opt(2026, 10, 7).unwrap(),
            "half past midnight in Paris"
        );
    }

    #[test]
    fn runs_stay_within_their_span() {
        let alongs = [0.0, 10.0, 350.0, 420.0, 900.0];
        assert_eq!(runs(&alongs, 400.0), [0..3, 3..4, 4..5]);
        assert_eq!(runs(&[], 400.0), Vec::<std::ops::Range<usize>>::new());
    }

    #[test]
    fn a_span_reads_its_own_days_only() {
        let d = |day: u32, low: f64, high: f64| PriceDay {
            day: NaiveDate::from_ymd_opt(2026, 10, day).unwrap(),
            low_eur: low,
            high_eur: high,
        };
        let days = [
            d(6, 2.30, 2.35),
            d(1, 2.40, 2.40),
            d(3, 2.20, 2.45),
            d(5, 2.25, 2.25),
        ];
        let today = NaiveDate::from_ymd_opt(2026, 10, 6).unwrap();
        let week = price_span(&days, today, 7).unwrap();
        assert_eq!(week.days_known, 4);
        assert!((week.low_eur - 2.20).abs() < 1e-9 && (week.high_eur - 2.45).abs() < 1e-9);
        assert!(
            (week.change_eur.unwrap() + 0.10).abs() < 1e-9,
            "2.40 to 2.30"
        );
        let two = price_span(&days, today, 2).unwrap();
        assert_eq!(two.days_known, 2);
        assert!((two.change_eur.unwrap() - 0.05).abs() < 1e-9);
        let one = price_span(&days, today, 1).unwrap();
        assert_eq!(one.change_eur, None);
        let later = NaiveDate::from_ymd_opt(2026, 11, 30).unwrap();
        assert_eq!(price_span(&days, later, 30), None);
    }
}
