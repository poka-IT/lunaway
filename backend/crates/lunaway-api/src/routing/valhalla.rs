//! The routing engine's HTTP interface, as the API uses it: one `POST
//! /route` with a JSON body, the answer in the OSRM format that Ferrostar's
//! Valhalla adapter reads (`plan/research/07-navigation.md`, C.1 and E).

use std::time::Duration;

use lunaway_domain::{Position, fuel::Leg, routing::RoutingDimensions};
use serde_json::{Value, json};

/// Largest answer read from the engine: three routes across France with
/// their instructions and annotations weigh about 4.5 MB (Lille to Nice,
/// measured 2026-10-06 on the France graph). Parsed, an answer takes several
/// times its size, and four are in flight at once under the API's 1 GB.
pub(crate) const MAX_ANSWER_BYTES: usize = 16 * 1024 * 1024;
/// How far, in metres, the engine may look for a road around a point: a
/// point farther from any road is not a place a motorhome can be routed to,
/// and the default (35 km) snapped a point in the Bay of Biscay onto a
/// ferry line (measured 2026-10-06).
const SEARCH_CUTOFF_M: u32 = 5_000;
/// Heading tolerance sent with a GPS course, degrees, as Ferrostar's
/// adapter does.
const HEADING_TOLERANCE_DEG: u32 = 45;

/// A point of a route request.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Stop {
    /// Where.
    pub(crate) at: Position,
    /// The vehicle's course there, degrees from north, when known.
    pub(crate) heading: Option<u16>,
}

/// What the user asked to avoid.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "four independent switches, as the app shows them"
)]
pub(crate) struct Avoid {
    /// Toll roads.
    pub(crate) tolls: bool,
    /// Motorways.
    pub(crate) motorways: bool,
    /// Ferries.
    pub(crate) ferries: bool,
    /// Unpaved roads.
    pub(crate) unpaved: bool,
}

/// The engine's options for the vehicle and what to avoid: the `auto`
/// costing with the four dimensions always sent (its defaults are those of
/// a small car), `top_speed` above 3.5 t, and avoidance as preferences
/// (`use_*: 0`), so a toll or a ferry stays possible when there is no other
/// way; unpaved roads are excluded outright, except where the trip starts or
/// ends on one.
pub(crate) fn costing_options(dims: &RoutingDimensions, avoid: Avoid) -> Value {
    let mut auto = json!({
        "height": dims.height_m,
        "width": dims.width_m,
        "length": dims.length_m,
        "weight": dims.weight_t,
    });
    if let Some(speed) = dims.top_speed_kph {
        auto["top_speed"] = speed.into();
    }
    if avoid.tolls {
        auto["use_tolls"] = 0.0.into();
    }
    if avoid.motorways {
        auto["use_highways"] = 0.0.into();
    }
    if avoid.ferries {
        auto["use_ferry"] = 0.0.into();
    }
    if avoid.unpaved {
        auto["exclude_unpaved"] = true.into();
    }
    json!({ "auto": auto })
}

/// The body of a route request: OSRM output with banner and voice
/// instructions, the shape attributes Ferrostar reads, and the exclusion
/// rings of the check.
pub(crate) fn route_body(
    stops: &[Stop],
    costing: &Value,
    language: &str,
    alternates: u8,
    exclusions: &[Vec<Position>],
) -> Value {
    let locations: Vec<Value> = stops
        .iter()
        .map(|s| {
            let mut l = json!({
                "lat": s.at.lat(),
                "lon": s.at.lon(),
                "type": "break",
                "search_cutoff": SEARCH_CUTOFF_M,
            });
            if let Some(h) = s.heading {
                l["heading"] = h.into();
                l["heading_tolerance"] = HEADING_TOLERANCE_DEG.into();
            }
            l
        })
        .collect();
    let mut body = json!({
        "locations": locations,
        "costing": "auto",
        "costing_options": costing,
        "format": "osrm",
        "shape_format": "polyline6",
        "banner_instructions": true,
        "voice_instructions": true,
        "language": language,
        "filters": {
            "attributes": [
                "shape_attributes.speed",
                "shape_attributes.speed_limit",
                "shape_attributes.time",
                "shape_attributes.length"
            ],
            "action": "include"
        },
    });
    // The engine computes alternatives between two points only.
    if alternates > 0 && stops.len() == 2 {
        body["alternates"] = alternates.into();
    }
    if !exclusions.is_empty() {
        body["exclude_polygons"] = exclusions
            .iter()
            .map(|ring| {
                ring.iter()
                    .map(|p| json!([p.lon(), p.lat()]))
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>()
            .into();
    }
    body
}

/// What the engine said.
#[derive(Debug)]
pub(crate) enum Answer {
    /// Routes, in the OSRM format.
    Routes(Value),
    /// No route between the points (`NoRoute`).
    NoRoute,
    /// A point is not near any road (`NoSegment`).
    NoSegment,
}

/// Why the engine could not be used.
#[derive(Debug, thiserror::Error)]
pub(crate) enum EngineError {
    /// No answer in time, or no connection.
    #[error("the routing engine did not answer")]
    Unreachable(#[source] reqwest::Error),
    /// An answer the API does not understand, or an error it did not cause
    /// knowingly (invalid options, a limit).
    #[error("the routing engine answered {status}: {code}")]
    Refused {
        /// HTTP status.
        status: u16,
        /// The engine's code and message.
        code: String,
    },
    /// The answer is not JSON.
    #[error("the routing engine answered {status} with something else than JSON")]
    NotJson {
        /// HTTP status.
        status: u16,
        /// Why it does not parse.
        #[source]
        source: serde_json::Error,
    },
    /// The answer is larger than any route.
    #[error("the routing engine's answer exceeds {MAX_ANSWER_BYTES} bytes")]
    TooLarge,
    /// A matrix whose rows or cells do not match the request.
    #[error("the routing engine's matrix does not match the request")]
    MatrixShape,
}

/// A point of a matrix request.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct MatrixPoint {
    /// Where.
    pub(crate) at: Position,
    /// The direction the vehicle drives there, degrees from north: a point
    /// of a route sits on the carriageway the route drives.
    pub(crate) heading: Option<u16>,
    /// How far the engine may look for a road, metres.
    pub(crate) search_cutoff_m: u32,
}

/// The body of a matrix request: the time and distance from each source to
/// each target, in kilometres, one object per cell (`verbose`).
pub(crate) fn matrix_body(
    sources: &[MatrixPoint],
    targets: &[MatrixPoint],
    costing: &Value,
) -> Value {
    let location = |p: &MatrixPoint| {
        let mut l = json!({
            "lat": p.at.lat(),
            "lon": p.at.lon(),
            "search_cutoff": p.search_cutoff_m,
        });
        if let Some(h) = p.heading {
            l["heading"] = h.into();
            l["heading_tolerance"] = HEADING_TOLERANCE_DEG.into();
        }
        l
    };
    json!({
        "sources": sources.iter().map(location).collect::<Vec<_>>(),
        "targets": targets.iter().map(location).collect::<Vec<_>>(),
        "costing": "auto",
        "costing_options": costing,
        "units": "kilometers",
        "verbose": true,
    })
}

/// The cells of a matrix answer, a row per source: none where the engine
/// found no way.
fn matrix_cells(
    value: &Value,
    sources: usize,
    targets: usize,
) -> Result<Vec<Vec<Option<Leg>>>, EngineError> {
    let rows = value
        .get("sources_to_targets")
        .and_then(Value::as_array)
        .filter(|rows| rows.len() == sources)
        .ok_or(EngineError::MatrixShape)?;
    rows.iter()
        .map(|row| {
            let cells = row
                .as_array()
                .filter(|cells| cells.len() == targets)
                .ok_or(EngineError::MatrixShape)?;
            Ok(cells
                .iter()
                .map(|c| {
                    let km = c.get("distance").and_then(Value::as_f64)?;
                    let seconds = c.get("time").and_then(Value::as_f64)?;
                    (km.is_finite() && seconds.is_finite()).then_some(Leg { km, seconds })
                })
                .collect())
        })
        .collect()
}

/// A client of the engine at a loopback URL.
#[derive(Debug, Clone)]
pub(crate) struct Engine {
    http: reqwest::Client,
    base: String,
}

impl Engine {
    /// A client of `base` (`http://127.0.0.1:8002`), each call bounded by
    /// `timeout`. No proxy (a proxy variable in the environment would send
    /// positions off the host), no redirect.
    pub(crate) fn new(base: &str, timeout: Duration) -> Result<Self, reqwest::Error> {
        // reqwest is built without a bundled crypto provider (workspace
        // manifest); the engine is plain HTTP on loopback, but building a
        // client needs one installed. An error means one already is.
        static RING: std::sync::Once = std::sync::Once::new();
        RING.call_once(|| {
            let _ = rustls::crypto::ring::default_provider().install_default();
        });
        let http = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(2))
            .timeout(timeout)
            .build()?;
        Ok(Self {
            http,
            base: base.trim_end_matches('/').to_owned(),
        })
    }

    /// `POST` of `body` to `path`: the status and the JSON answer, read
    /// within [`MAX_ANSWER_BYTES`].
    async fn post(&self, path: &str, body: &Value) -> Result<(u16, Value), EngineError> {
        let mut response = self
            .http
            .post(format!("{}/{path}", self.base))
            .json(body)
            .send()
            .await
            .map_err(EngineError::Unreachable)?;
        let status = response.status().as_u16();
        if response
            .content_length()
            .is_some_and(|n| n > MAX_ANSWER_BYTES as u64)
        {
            return Err(EngineError::TooLarge);
        }
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(EngineError::Unreachable)? {
            bytes.extend_from_slice(&chunk);
            if bytes.len() > MAX_ANSWER_BYTES {
                return Err(EngineError::TooLarge);
            }
        }
        let value: Value = serde_json::from_slice(&bytes)
            .map_err(|source| EngineError::NotJson { status, source })?;
        Ok((status, value))
    }

    /// `POST /sources_to_targets` with `body`, made by [`matrix_body`]
    /// for `sources` and `targets` points: a row per source, a cell per
    /// target.
    pub(crate) async fn matrix(
        &self,
        body: &Value,
        sources: usize,
        targets: usize,
    ) -> Result<Vec<Vec<Option<Leg>>>, EngineError> {
        let (status, value) = self.post("sources_to_targets", body).await?;
        if status != 200 {
            return Err(EngineError::Refused {
                status,
                code: format!(
                    "{}: {}",
                    value
                        .get("error_code")
                        .and_then(Value::as_i64)
                        .unwrap_or_default(),
                    value
                        .get("error")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                ),
            });
        }
        matrix_cells(&value, sources, targets)
    }

    /// `POST /route` with `body`.
    pub(crate) async fn route(&self, body: &Value) -> Result<Answer, EngineError> {
        let (status, value) = self.post("route", body).await?;
        let code = value
            .get("code")
            .and_then(Value::as_str)
            .unwrap_or_default();
        match (status, code) {
            (200, "Ok") => Ok(Answer::Routes(value)),
            (_, "NoRoute") => Ok(Answer::NoRoute),
            (_, "NoSegment") => Ok(Answer::NoSegment),
            _ => Err(EngineError::Refused {
                status,
                code: format!(
                    "{code}: {}",
                    value
                        .get("message")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                ),
            }),
        }
    }

    /// `GET /status`: whether the engine answers.
    pub(crate) async fn alive(&self) -> bool {
        self.http
            .get(format!("{}/status", self.base))
            .send()
            .await
            .is_ok_and(|r| r.status().is_success())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dims(weight_t: f64, top: Option<u32>) -> RoutingDimensions {
        RoutingDimensions {
            height_m: 3.3,
            width_m: 2.3,
            length_m: 7.4,
            weight_t,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: top,
        }
    }

    #[test]
    fn the_dimensions_always_go_and_avoidance_is_a_preference() {
        let c = costing_options(&dims(3.5, None), Avoid::default());
        assert_eq!(
            c,
            json!({"auto": {"height": 3.3, "width": 2.3, "length": 7.4, "weight": 3.5}})
        );
        let c = costing_options(
            &dims(4.5, Some(110)),
            Avoid {
                tolls: true,
                motorways: true,
                ferries: true,
                unpaved: true,
            },
        );
        assert_eq!(c["auto"]["top_speed"], 110);
        assert_eq!(c["auto"]["use_tolls"], 0.0);
        assert_eq!(c["auto"]["use_highways"], 0.0);
        assert_eq!(c["auto"]["use_ferry"], 0.0);
        assert_eq!(c["auto"]["exclude_unpaved"], true);
        assert!(
            c["auto"].get("hgv_no_access_penalty").is_none(),
            "no truck notion"
        );
    }

    #[test]
    fn a_matrix_reads_a_row_per_source_and_a_cell_per_target() {
        let p = |lat: f64| MatrixPoint {
            at: Position::new(lat, 1.0).unwrap(),
            heading: (lat > 45.0).then_some(180),
            search_cutoff_m: 1_000,
        };
        let body = matrix_body(&[p(45.1), p(44.9)], &[p(44.0)], &json!({"auto": {}}));
        assert_eq!(body["verbose"], true);
        assert_eq!(body["units"], "kilometers");
        assert_eq!(body["sources"][0]["heading"], 180);
        assert!(body["sources"][1].get("heading").is_none());
        // Valhalla 3.9.0's verbose answer, an unreachable cell with nulls.
        let answer = json!({"sources_to_targets": [
            [{"distance": 12.5, "time": 600, "from_index": 0, "to_index": 0}],
            [{"distance": null, "time": null, "from_index": 1, "to_index": 0}]
        ]});
        let cells = matrix_cells(&answer, 2, 1).unwrap();
        assert_eq!(
            cells[0][0],
            Some(Leg {
                km: 12.5,
                seconds: 600.0
            })
        );
        assert_eq!(cells[1][0], None);
        assert!(matches!(
            matrix_cells(&answer, 3, 1),
            Err(EngineError::MatrixShape)
        ));
        assert!(matches!(
            matrix_cells(&answer, 2, 2),
            Err(EngineError::MatrixShape)
        ));
    }

    #[test]
    fn the_body_asks_for_what_ferrostar_reads() {
        let a = Stop {
            at: Position::new(45.84719, 1.28476).unwrap(),
            heading: Some(90),
        };
        let b = Stop {
            at: Position::new(45.8451, 1.28637).unwrap(),
            heading: None,
        };
        let ring = vec![a.at, b.at, a.at];
        let body = route_body(&[a, b], &json!({}), "fr-FR", 2, &[ring]);
        assert_eq!(body["format"], "osrm");
        assert_eq!(body["shape_format"], "polyline6");
        assert_eq!(body["banner_instructions"], true);
        assert_eq!(body["voice_instructions"], true);
        assert_eq!(body["alternates"], 2);
        assert_eq!(body["locations"][0]["heading"], 90);
        assert_eq!(body["locations"][0]["search_cutoff"], 5_000);
        assert_eq!(
            body["exclude_polygons"][0][0],
            json!([1.28476, 45.84719]),
            "longitude first"
        );
        let three = route_body(&[a, b, a], &json!({}), "en-US", 2, &[]);
        assert!(
            three.get("alternates").is_none(),
            "no alternatives with waypoints"
        );
        assert!(three.get("exclude_polygons").is_none());
    }
}
