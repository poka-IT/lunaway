//! What lies along a route besides fuel: places to stay and points of
//! interest in a band around the route ahead, listed by the time their
//! detour adds.
//!
//! The band, the estimate and the measure of a detour are those of fuel
//! ([`crate::fuel`]). The order differs: a driver looking for water or a
//! night wants what costs the fewest minutes, but not at the far end of a
//! long trip before what lies a few kilometres ahead. So what lies within a
//! distance of the start comes first, by the whole minutes its detour adds,
//! then by its distance along the route; the rest follows in the same
//! order.

use std::cmp::Ordering;

use crate::Position;

/// Where a candidate stands in the list.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Standing {
    /// Metres from the route's start to where the candidate is reached.
    pub along_m: f64,
    /// Minutes its detour adds; infinite when no road leads there.
    pub minutes: f64,
}

/// Orders two candidates: those reached within `near_m` of the start
/// before the others, then by the whole minutes their detour adds (a
/// minute is what the list shows), then by their distance along the route.
#[must_use]
pub fn order(a: Standing, b: Standing, near_m: f64) -> Ordering {
    let far = |s: Standing| s.along_m > near_m;
    far(a)
        .cmp(&far(b))
        .then(a.minutes.round().total_cmp(&b.minutes.round()))
        .then(a.along_m.total_cmp(&b.along_m))
}

/// The first `max_m` metres of `points`, the last segment cut where it
/// reaches them; the whole line when it is shorter.
#[must_use]
pub fn head(points: &[Position], max_m: f64) -> Vec<Position> {
    let mut out = Vec::new();
    let mut along = 0.0;
    for (i, p) in points.iter().enumerate() {
        if i > 0 {
            let a = points[i - 1];
            let step = a.distance_m(*p);
            if along + step >= max_m {
                let t = if step > 0.0 {
                    (max_m - along) / step
                } else {
                    0.0
                };
                out.push(between(a, *p, t));
                return out;
            }
            along += step;
        }
        out.push(*p);
    }
    out
}

/// The point at `t` (0 to 1) between `a` and `b`, in degrees: the line's
/// segments are short enough for that.
fn between(a: Position, b: Position, t: f64) -> Position {
    Position::new(
        a.lat() + (b.lat() - a.lat()) * t,
        a.lon() + (b.lon() - a.lon()) * t,
    )
    .unwrap_or(a)
}

/// The length of `points`, metres.
#[must_use]
pub fn length_m(points: &[Position]) -> f64 {
    points.windows(2).map(|w| w[0].distance_m(w[1])).sum()
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

    fn s(along_km: f64, minutes: f64) -> Standing {
        Standing {
            along_m: along_km * 1_000.0,
            minutes,
        }
    }

    #[test]
    fn what_is_near_comes_first_by_the_minutes_it_adds() {
        let near = 50_000.0;
        let mut list = [
            s(120.0, 0.0),
            s(30.0, 4.0),
            s(40.0, 0.2),
            s(10.0, 0.4),
            s(20.0, 3.6),
            s(60.0, f64::INFINITY),
            s(70.0, 1.0),
        ];
        list.sort_by(|a, b| order(*a, *b, near));
        let got: Vec<(f64, f64)> = list
            .iter()
            .map(|x| (x.along_m / 1_000.0, x.minutes))
            .collect();
        assert_eq!(
            got,
            vec![
                (10.0, 0.4),
                (40.0, 0.2),
                (20.0, 3.6),
                (30.0, 4.0),
                (120.0, 0.0),
                (70.0, 1.0),
                (60.0, f64::INFINITY),
            ],
            "within 50 km by whole minutes then along, then the rest the same way"
        );
    }

    #[test]
    fn the_head_of_a_line_is_cut_inside_its_segment() {
        // About 11.1 km due north.
        let line = [p(45.0, 1.0), p(45.05, 1.0), p(45.1, 1.0)];
        let h = head(&line, 8_000.0);
        assert_eq!(h.len(), 3);
        assert!((length_m(&h) - 8_000.0).abs() < 1.0, "{}", length_m(&h));
        assert_eq!(head(&line, 50_000.0), line.to_vec(), "a shorter line whole");
    }
}
