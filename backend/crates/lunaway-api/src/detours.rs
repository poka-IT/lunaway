//! What the searches along a route share (`fuelAlongRoute`,
//! `alongRoute`): the route's line as the client sends it, checked before
//! the corridor is built, and the routing engine's measure of the detour to
//! each candidate.

use std::time::Duration;

use async_graphql::{Context, Result};
use lunaway_domain::{
    BBox, Position,
    fuel::{Anchor, Corridor, Detour, MAX_LINE_SPAN_DEG, line_span_deg, runs},
    routing::polyline,
};
use serde_json::Value;

use crate::{
    error::{internal, invalid_input},
    routing::{
        RouteError,
        valhalla::{EngineError, MatrixPoint},
    },
    schema::state,
    types::LatLonInput,
};

/// Longest polyline accepted, characters: what fits in the 64 KiB body
/// with the rest of the request.
pub(crate) const MAX_POLYLINE_CHARS: usize = 48_000;
/// Most points accepted as a list.
const MAX_INPUT_POINTS: usize = 1_000;
/// Most points a polyline may decode to: 48 000 characters of six-decimal
/// deltas hold fewer.
const MAX_LINE_POINTS: usize = 20_000;
/// Longest route, kilometres: the longest trip a route is given for
/// (`routing_query::MAX_TRIP_M`, 3 000 km in a straight line) runs to about
/// 4 000 km by road (5 411 km for Tarifa to Tromsø, 4 023 km straight, measured
/// 2026-10-07, before the cap came down to 3 000 km). The
/// search's work grows with the line's points, bounded apart.
const MAX_ROUTE_KM: f64 = 7_000.0;
/// How much of each end of the line a search drops, metres: the start
/// is the device's position when a preview searches from it.
pub(crate) const END_CUT_M: f64 = 2_000.0;
/// Longest run of candidates one matrix call measures, metres along the
/// route: the engine computes every pair of a matrix and reads none but a
/// few short legs, so a call stays local. With the anchors (3 km each side)
/// and the band (15 km each side at most), its points lie less than 60 km
/// apart.
const MAX_RUN_M: f64 = 20_000.0;
/// How far the engine may look for a road around a candidate, metres: a
/// station or a car park sits beside its road, sometimes behind another
/// car park.
const TARGET_CUTOFF_M: u32 = 2_000;
/// How far around a point of the route: it lies on a road.
const ANCHOR_CUTOFF_M: u32 = 500;
/// Longest the engine's measurements of one search may take together:
/// under the API's request timeout (20 s by default), and what is not
/// measured by then is estimated.
const ENGINE_DEADLINE: Duration = Duration::from_secs(8);

/// Refuses a line too large to read before anything is spent: a polyline
/// over [`MAX_POLYLINE_CHARS`], a list over [`MAX_INPUT_POINTS`], or both
/// or neither given.
pub(crate) fn check_size(polyline: Option<&str>, points: Option<&[LatLonInput]>) -> Result<()> {
    match (polyline, points) {
        (Some(p), None) if p.len() > MAX_POLYLINE_CHARS => Err(invalid_input(format!(
            "polyline holds {} characters, more than the {MAX_POLYLINE_CHARS} allowed: \
             simplify the line",
            p.len()
        ))),
        (None, Some(list)) if list.len() > MAX_INPUT_POINTS => Err(invalid_input(format!(
            "at most {MAX_INPUT_POINTS} points, got {}",
            list.len()
        ))),
        (Some(_), None) | (None, Some(_)) => Ok(()),
        _ => Err(invalid_input("give either polyline or points")),
    }
}

/// The route's line from the input, checked: its points, the degrees it
/// covers (what the corridor's grid costs) and its length. Linear in the
/// points, which [`check_size`] bounds.
pub(crate) fn line_of(
    polyline: Option<&str>,
    points: Option<&[LatLonInput]>,
) -> Result<Vec<Position>> {
    let points = match (polyline, points) {
        (Some(p), _) => polyline::decode(p).map_err(|e| invalid_input(format!("polyline: {e}")))?,
        (None, Some(list)) => list
            .iter()
            .enumerate()
            .map(|(i, p)| {
                Position::new(p.lat, p.lon).map_err(|e| invalid_input(format!("points[{i}]: {e}")))
            })
            .collect::<Result<_>>()?,
        (None, None) => return Err(invalid_input("give either polyline or points")),
    };
    if points.len() < 2 || points.len() > MAX_LINE_POINTS {
        return Err(invalid_input(format!(
            "the route must hold 2 to {MAX_LINE_POINTS} points, got {}",
            points.len()
        )));
    }
    let span = line_span_deg(&points);
    if span > MAX_LINE_SPAN_DEG {
        return Err(invalid_input(format!(
            "the line covers {span:.0} degrees, more than the {MAX_LINE_SPAN_DEG:.0} a route covers"
        )));
    }
    let km: f64 = points
        .windows(2)
        .map(|w| w[0].distance_m(w[1]))
        .sum::<f64>()
        / 1_000.0;
    if km > MAX_ROUTE_KM {
        return Err(invalid_input(format!(
            "the route is {km:.0} km long, more than the {MAX_ROUTE_KM:.0} km allowed"
        )));
    }
    Ok(points)
}

/// The box around the corridor, for the database's index.
pub(crate) fn corridor_box(corridor: &Corridor) -> Result<BBox> {
    let points = corridor.points();
    let fold = |f: fn(Position) -> f64| {
        points
            .iter()
            .copied()
            .map(f)
            .fold((f64::INFINITY, f64::NEG_INFINITY), |(lo, hi), v| {
                (lo.min(v), hi.max(v))
            })
    };
    let (south, north) = fold(Position::lat);
    let (west, east) = fold(Position::lon);
    let margin_lat = corridor.half_width_m() / 111_195.0;
    let widest = south.abs().max(north.abs()) + margin_lat;
    let margin_lon = margin_lat / widest.min(85.0).to_radians().cos();
    BBox::new(
        (south - margin_lat).max(-90.0),
        (west - margin_lon).max(-180.0),
        (north + margin_lat).min(90.0),
        (east + margin_lon).min(180.0),
    )
    .map_err(|e| internal(&e))
}

#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "a heading between 0 and 360 degrees"
)]
fn heading(deg: f64) -> u16 {
    (deg.rem_euclid(360.0).round() as u16) % 360
}

/// A candidate whose detour the engine measures.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Target {
    /// Where it is.
    pub(crate) at: Position,
    /// Where the route passes it, metres from the corridor's start.
    pub(crate) along_m: f64,
}

/// The detours of `targets`, measured by the engine from the route before
/// each to the route after it, a run of nearby targets per call, in the
/// order given. `None` where the engine did not measure (it refused, was
/// busy, is not set up, or ran out of time): the caller keeps its
/// estimate. An infinite detour where no road leads there and back: not a
/// place to send a driver to. An engine that fails is not asked again for
/// this search.
pub(crate) async fn measure(
    ctx: &Context<'_>,
    corridor: &Corridor,
    costing: &Value,
    targets: &[Target],
) -> Vec<Option<Detour>> {
    let routing = &state(ctx).routing;
    let deadline = tokio::time::Instant::now() + ENGINE_DEADLINE;
    let mut out = vec![None; targets.len()];
    // The runs read the targets in their order along the route.
    let mut order: Vec<usize> = (0..targets.len()).collect();
    order.sort_by(|&a, &b| targets[a].along_m.total_cmp(&targets[b].along_m));
    let alongs: Vec<f64> = order.iter().map(|&i| targets[i].along_m).collect();
    for run in runs(&alongs, MAX_RUN_M) {
        let members = &order[run];
        let k = members.len();
        let anchors: Vec<_> = members
            .iter()
            .map(|&i| corridor.anchors(targets[i].along_m))
            .collect();
        let anchor = |a: &Anchor| MatrixPoint {
            at: a.at,
            heading: Some(heading(a.heading_deg)),
            search_cutoff_m: ANCHOR_CUTOFF_M,
        };
        let target = |&i: &usize| MatrixPoint {
            at: targets[i].at,
            heading: None,
            search_cutoff_m: TARGET_CUTOFF_M,
        };
        // Sources: the anchors before, then the targets. Targets: the
        // targets, then the anchors after. Row i reads before->target and
        // before->after, row k+i target->after.
        let sources: Vec<MatrixPoint> = anchors
            .iter()
            .map(|(before, _)| anchor(before))
            .chain(members.iter().map(target))
            .collect();
        let ends: Vec<MatrixPoint> = members
            .iter()
            .map(target)
            .chain(anchors.iter().map(|(_, after)| anchor(after)))
            .collect();
        let cells =
            match tokio::time::timeout_at(deadline, routing.matrix(&sources, &ends, costing)).await
            {
                Ok(Ok(cells)) => cells,
                Ok(Err(RouteError::NotSetUp)) => break,
                // A target far from any road makes the engine refuse its
                // whole run (Valhalla's 170 and 171): the other runs are
                // still worth measuring.
                Ok(Err(RouteError::Engine(EngineError::Refused { status: 400, code })))
                    if code.starts_with("170:") || code.starts_with("171:") =>
                {
                    tracing::warn!(%code, "a run of detours estimated");
                    continue;
                }
                Ok(Err(error)) => {
                    warn_chain(&error);
                    break;
                }
                Err(_) => {
                    tracing::warn!("detours ran out of time; the rest are estimated");
                    break;
                }
            };
        for (j, &i) in members.iter().enumerate() {
            let get =
                |r: usize, t: usize| cells.get(r).and_then(|row| row.get(t)).copied().flatten();
            out[i] = Some(match (get(j, j), get(k + j, k + j), get(j, k + j)) {
                (Some(to), Some(from), Some(direct)) => Detour::measured(to, from, direct),
                _ => Detour {
                    km: f64::INFINITY,
                    minutes: f64::INFINITY,
                    measured: true,
                },
            });
        }
    }
    out
}

/// Logs why the engine did not measure, with its causes, at warning level:
/// the search answers anyway, with estimates. Never a position.
fn warn_chain(error: &(dyn std::error::Error + 'static)) {
    let mut chain = Vec::new();
    let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(c) = cause {
        chain.push(c.to_string());
        cause = c.source();
    }
    tracing::warn!(error = %chain.join(": "), "detours estimated");
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use super::*;

    fn message<T>(r: Result<T>) -> String {
        r.err().map(|e| e.message).unwrap_or_default()
    }

    fn encoded() -> String {
        polyline::encode(&[
            Position::new(45.0, 1.0).unwrap(),
            Position::new(45.1, 1.0).unwrap(),
        ])
    }

    #[test]
    fn a_line_is_read_and_measured_before_its_corridor_is_built() {
        let line = encoded();
        assert!(check_size(Some(&line), None).is_ok());
        assert!(line_of(Some(&line), None).is_ok());
        assert!(message(line_of(Some("~"), None)).contains("polyline"));
        let points = [LatLonInput {
            lat: 45.0,
            lon: 1.0,
        }; 2];
        assert!(message(check_size(Some(&line), Some(&points))).contains("either"));
        assert!(message(check_size(None, None)).contains("either"));
        let long = "_".repeat(MAX_POLYLINE_CHARS + 1);
        assert!(message(check_size(Some(&long), None)).contains("simplify"));
        // El Hierro to the North Cape and back to Lisbon: 9 900 km.
        let across = polyline::encode(&[
            Position::new(27.7, -18.0).unwrap(),
            Position::new(71.0, 26.0).unwrap(),
            Position::new(38.7, -9.1).unwrap(),
        ]);
        assert!(message(line_of(Some(&across), None)).contains("km long"));
        // Back and forth across the antimeridian: 2.2 km a segment, but
        // 360 degrees of grid each.
        let zigzag: Vec<LatLonInput> = (0..1_000)
            .map(|i| LatLonInput {
                lat: 0.0,
                lon: if i % 2 == 0 { -179.99 } else { 179.99 },
            })
            .collect();
        assert!(check_size(None, Some(&zigzag)).is_ok(), "its size passes");
        assert!(message(line_of(None, Some(&zigzag))).contains("degrees"));
    }

    #[test]
    fn the_box_holds_the_band_on_every_side() {
        let corridor = Corridor::new(line_of(Some(&encoded()), None).unwrap(), 2_500.0).unwrap();
        let b = corridor_box(&corridor).unwrap();
        assert!(b.south() < 45.0 - 2_400.0 / 111_195.0);
        assert!(b.north() > 45.1 + 2_400.0 / 111_195.0);
        let lon_m = (1.0 - b.west()) * 111_195.0 * 45.1_f64.to_radians().cos();
        assert!(lon_m >= 2_500.0, "{lon_m}");
    }
}
