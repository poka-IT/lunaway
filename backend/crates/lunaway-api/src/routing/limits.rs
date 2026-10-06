//! The speed limit along a route for the vehicle
//! (`lunaway_domain::speed`): the engine describes each edge of the route
//! it computed (`trace_attributes`, `edge_walk` on the route's own shape:
//! the signs OpenStreetMap maps, the road's class, its density, one way or
//! both), and the domain adds the defaults and the vehicle's ceilings.
//!
//! The engine traces at most `trace.max_shape` points (16 000) and
//! `trace.max_distance` metres (200 km) at once (`infra/routing/valhalla.json`):
//! a route is traced in pieces of [`CHUNK_POINTS`] points and [`CHUNK_M`]
//! metres. The Limoges to Brive route (95 km, 1 661 points) took 8 ms on
//! Valhalla 3.9.0 (2026-10-06).

use lunaway_domain::{
    Position,
    routing::polyline,
    speed::{Edge, RoadClass, Stretch},
};
use serde_json::{Value, json};

/// Most shape points of one trace: under the engine's 16 000.
pub(crate) const CHUNK_POINTS: usize = 10_000;
/// Longest piece of one trace, metres: under the engine's 200 km.
pub(crate) const CHUNK_M: f64 = 150_000.0;
/// Most traces for one route: 3 000 km in pieces of 150 km.
pub(crate) const MAX_CHUNKS: usize = 20;

/// The pieces `[first, last]` (shape indices) a route of these distances
/// from its start (`along`) is traced in, each starting where the previous
/// ended; none when the route needs more than [`MAX_CHUNKS`].
pub(crate) fn chunks(along: &[f64]) -> Option<Vec<(usize, usize)>> {
    let mut out = Vec::new();
    let mut first = 0;
    while first + 1 < along.len() {
        let mut last = first + 1;
        while last + 1 < along.len()
            && last + 1 - first < CHUNK_POINTS
            && along[last + 1] - along[first] <= CHUNK_M
        {
            last += 1;
        }
        out.push((first, last));
        if out.len() > MAX_CHUNKS {
            return None;
        }
        first = last;
    }
    Some(out)
}

/// The request tracing `points`, the attributes the limits need only.
pub(crate) fn trace_body(points: &[Position]) -> Value {
    json!({
        "encoded_polyline": polyline::encode(points),
        "shape_format": "polyline6",
        "costing": "auto",
        "shape_match": "edge_walk",
        "filters": {
            "attributes": [
                "edge.speed_limit",
                "edge.road_class",
                "edge.use",
                "edge.density",
                "edge.traversability",
                "edge.begin_shape_index",
                "edge.end_shape_index"
            ],
            "action": "include"
        },
    })
}

/// The edges of a trace answer for the piece starting at shape index
/// `offset`; `None` when the answer holds none.
pub(crate) fn edges_of(answer: &Value, offset: usize) -> Option<Vec<Edge>> {
    let edges = answer.get("edges")?.as_array()?;
    let index = |e: &Value, key: &str| {
        e.get(key)
            .and_then(Value::as_u64)
            .and_then(|i| usize::try_from(i).ok())
            .map(|i| i + offset)
    };
    let out: Vec<Edge> = edges
        .iter()
        .filter_map(|e| {
            let posted_kmh = e
                .get("speed_limit")
                .and_then(Value::as_u64)
                // Under 5 is no sign; Valhalla stores at most 140, and
                // writes "unlimited" where there is none.
                .filter(|v| (5..=150).contains(v))
                .and_then(|v| u16::try_from(v).ok());
            let stretch = Stretch {
                class: RoadClass::of(e.get("road_class").and_then(Value::as_str)?),
                link: matches!(
                    e.get("use").and_then(Value::as_str),
                    Some("ramp" | "turn_channel")
                ),
                posted_kmh,
                oneway: matches!(
                    e.get("traversability").and_then(Value::as_str),
                    Some("forward" | "backward")
                ),
                density: e
                    .get("density")
                    .and_then(Value::as_u64)
                    .and_then(|d| u8::try_from(d).ok())
                    .unwrap_or(0),
            };
            Some(Edge {
                stretch,
                begin: index(e, "begin_shape_index")?,
                end: index(e, "end_shape_index")?,
            })
        })
        .collect();
    (!out.is_empty()).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_long_route_is_traced_in_pieces_within_the_engine_s_limits() {
        // A point every 100 m over 400 km.
        let along: Vec<f64> = (0..=4_000).map(|i| f64::from(i) * 100.0).collect();
        let pieces = chunks(&along).unwrap();
        assert_eq!(pieces.first().map(|p| p.0), Some(0));
        assert_eq!(pieces.last().map(|p| p.1), Some(4_000));
        for w in pieces.windows(2) {
            assert_eq!(w[0].1, w[1].0, "each piece starts where the last ended");
        }
        for (a, b) in &pieces {
            assert!(along[*b] - along[*a] <= CHUNK_M);
            assert!(b - a < CHUNK_POINTS);
        }
        assert_eq!(pieces.len(), 3);
        let dense: Vec<f64> = (0..25_000).map(f64::from).collect();
        assert!(
            chunks(&dense)
                .unwrap()
                .iter()
                .all(|(a, b)| b - a < CHUNK_POINTS)
        );
        let endless: Vec<f64> = (0..=40_000).map(|i| f64::from(i) * 100.0).collect();
        assert_eq!(chunks(&endless), None, "4 000 km: more pieces than allowed");
    }

    #[test]
    fn an_edge_reads_its_sign_class_and_place() {
        let answer = json!({"edges": [
            {"speed_limit": 130, "road_class": "motorway", "use": "road", "density": 2,
             "traversability": "forward", "begin_shape_index": 0, "end_shape_index": 4},
            {"speed_limit": "unlimited", "road_class": "trunk", "use": "ramp", "density": 1,
             "traversability": "both", "begin_shape_index": 4, "end_shape_index": 6},
            {"road_class": "secondary", "use": "road", "begin_shape_index": 6}
        ]});
        let edges = edges_of(&answer, 10).unwrap();
        assert_eq!(edges.len(), 2, "an edge without its end is left out");
        assert_eq!(edges[0].stretch.posted_kmh, Some(130));
        assert!(edges[0].stretch.oneway);
        assert_eq!((edges[0].begin, edges[0].end), (10, 14));
        assert_eq!(edges[1].stretch.posted_kmh, None);
        assert!(edges[1].stretch.link && !edges[1].stretch.oneway);
        assert_eq!(edges_of(&json!({"edges": []}), 0), None);
    }
}
