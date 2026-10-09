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

/// Longest piece of the line the database is asked about at once, metres:
/// each piece is a small box for the spatial index, and the nearest points
/// of each are kept when a piece holds too many.
pub const PIECE_M: f64 = 10_000.0;

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

/// `points` cut into pieces of at most `max_m` metres, each starting where
/// the one before ends; a segment longer than `max_m` is cut inside, so a
/// straight stretch of motorway is several small pieces too. Empty for a
/// line of fewer than two points or a length that is not a positive number.
#[must_use]
pub fn pieces(points: &[Position], max_m: f64) -> Vec<Vec<Position>> {
    if points.len() < 2 || !(max_m.is_finite() && max_m > 0.0) {
        return Vec::new();
    }
    let mut out = Vec::new();
    let mut piece = vec![points[0]];
    let mut length = 0.0;
    for w in points.windows(2) {
        let (a, b) = (w[0], w[1]);
        let step = a.distance_m(b);
        // The segment in parts no longer than a piece.
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "a small positive count: a segment of a route over a piece's length"
        )]
        let parts = (step / max_m).ceil().max(1.0) as u32;
        for k in 1..=parts {
            let to = between(a, b, f64::from(k) / f64::from(parts));
            let part = step / f64::from(parts);
            if length + part > max_m && piece.len() > 1 {
                let last = piece[piece.len() - 1];
                out.push(std::mem::replace(&mut piece, vec![last]));
                length = 0.0;
            }
            piece.push(to);
            length += part;
        }
    }
    if piece.len() > 1 {
        out.push(piece);
    }
    out
}

/// The well-known text of a piece, longitude first, as PostGIS reads it.
#[must_use]
pub fn wkt(piece: &[Position]) -> String {
    let mut out = String::from("LINESTRING(");
    for (i, p) in piece.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&p.lon().to_string());
        out.push(' ');
        out.push_str(&p.lat().to_string());
    }
    out.push(')');
    out
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

    #[test]
    fn pieces_share_their_ends_and_stay_short() {
        // 30 km due north in one segment, then 3 km east.
        let line = [p(45.0, 1.0), p(45.27, 1.0), p(45.27, 1.04)];
        let cut = pieces(&line, 10_000.0);
        assert!(cut.len() >= 3, "{}", cut.len());
        for (i, piece) in cut.iter().enumerate() {
            assert!(length_m(piece) <= 10_000.0 + 1.0, "piece {i}");
            if i > 0 {
                assert_eq!(
                    piece[0],
                    *cut[i - 1].last().unwrap(),
                    "piece {i} starts where the last ends"
                );
            }
        }
        let total: f64 = cut.iter().map(|c| length_m(c)).sum();
        assert!((total - length_m(&line)).abs() < 1.0, "nothing lost");
        assert!(pieces(&line[..1], 10_000.0).is_empty());
    }

    #[test]
    fn a_piece_reads_as_well_known_text_longitude_first() {
        assert_eq!(
            wkt(&[p(45.5, 1.25), p(45.75, 1.5)]),
            "LINESTRING(1.25 45.5,1.5 45.75)"
        );
    }
}
