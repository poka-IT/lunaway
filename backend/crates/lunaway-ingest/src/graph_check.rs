//! The route tests a graph must pass before it serves
//! (`lunaway routing test-routes`, `infra/routing/test-routes.json`): real
//! places where a motorhome must, or must not, be sent, each checked on the
//! OpenStreetMap ways the route actually uses (Valhalla's
//! `trace_attributes` on the route's own shape).
//!
//! The cases come from the measured experiments of
//! `plan/research/07-navigation.md`, A.4 and B.2: the 2.7 m underpass of Rue
//! Maurice Utrillo in Limoges, the 3.5 t bridge of Rue du Pas Redon in
//! Ussel (`maxweightrating` only), the `motorhome=no` of Route de
//! Grandchamp, an `hgv=no` road a motorhome may take, the 3.4 m porch of
//! Rue Braille (an IGN height), and a long trip; and, since the graph
//! covers Europe (`plan/research/35-routage-europe-prod.md`, 3.5), trips
//! across borders and outside France: Spain, Portugal, Italy, Morocco by
//! the Tarifa ferry, Hamburg to Copenhagen, a 1.5 t street in Warsaw, the
//! 2.1 m passage before Venice's car ferry.

use std::time::Duration;

use serde::Deserialize;
use serde_json::{Value, json};

use crate::IngestError;

/// A vehicle, as the router's `auto` costing takes it.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct CaseVehicle {
    /// Metres.
    pub height: f64,
    /// Metres.
    pub width: f64,
    /// Metres.
    pub length: f64,
    /// Tonnes.
    pub weight: f64,
}

/// One case.
#[derive(Debug, Clone, Deserialize)]
pub struct Case {
    /// What it checks, as a sentence.
    pub name: String,
    /// Start, latitude then longitude.
    pub from: [f64; 2],
    /// End, latitude then longitude.
    pub to: [f64; 2],
    /// The vehicle.
    pub vehicle: CaseVehicle,
    /// OpenStreetMap ways the route must not use.
    #[serde(default)]
    pub avoid_ways: Vec<i64>,
    /// OpenStreetMap ways the route must use.
    #[serde(default)]
    pub use_ways: Vec<i64>,
    /// Longest acceptable route, kilometres.
    #[serde(default)]
    pub max_km: Option<f64>,
    /// Shortest acceptable route, kilometres.
    #[serde(default)]
    pub min_km: Option<f64>,
    /// Whether no route at all is acceptable (the only way in is too low).
    #[serde(default)]
    pub no_route_ok: bool,
    /// Whether the route must come from the engine's first pass: its
    /// second pass, taken when the first finds nothing, ignores every
    /// "sauf desserte" plate of the network (warning 401, "Routing failed
    /// on first pass"), so a route that needs it says the graph did not
    /// grant the right where it should.
    #[serde(default)]
    pub first_pass: bool,
}

/// Valhalla's warning for a route found by its second pass, with relaxed
/// restrictions (`thor_worker_t::get_path`).
const RELAXED_PASS: i64 = 401;

/// Whether a route answer came from the engine's relaxed second pass.
fn relaxed(route: &Value) -> bool {
    ["/warnings", "/trip/warnings"]
        .iter()
        .filter_map(|p| route.pointer(p).and_then(Value::as_array))
        .flatten()
        .any(|w| w.get("code").and_then(Value::as_i64) == Some(RELAXED_PASS))
}

/// How a case went.
#[derive(Debug, Clone, PartialEq)]
pub struct Outcome {
    /// The case's name.
    pub name: String,
    /// Whether it passed.
    pub passed: bool,
    /// What was seen.
    pub detail: String,
}

async fn post(
    http: &reqwest::Client,
    url: &str,
    body: &Value,
) -> Result<(u16, Value), IngestError> {
    let response = http
        .post(url)
        .json(body)
        .timeout(Duration::from_secs(60))
        .send()
        .await
        .map_err(|source| IngestError::Http {
            url: url.to_owned(),
            source,
        })?;
    let status = response.status().as_u16();
    let value = response
        .json::<Value>()
        .await
        .map_err(|source| IngestError::Http {
            url: url.to_owned(),
            source,
        })?;
    Ok((status, value))
}

/// Runs one case against the Valhalla server at `base`.
///
/// # Errors
///
/// [`IngestError`] when the server cannot be reached or answers what is not
/// JSON; a wrong route is an [`Outcome`] that did not pass.
pub async fn run_case(
    http: &reqwest::Client,
    base: &str,
    case: &Case,
) -> Result<Outcome, IngestError> {
    let costing = json!({"auto": {
        "height": case.vehicle.height,
        "width": case.vehicle.width,
        "length": case.vehicle.length,
        "weight": case.vehicle.weight,
    }});
    let body = json!({
        "locations": [
            {"lat": case.from[0], "lon": case.from[1]},
            {"lat": case.to[0], "lon": case.to[1]},
        ],
        "costing": "auto",
        "costing_options": costing,
        "units": "kilometers",
    });
    let (status, route) = post(http, &format!("{base}/route"), &body).await?;
    let outcome = |passed: bool, detail: String| Outcome {
        name: case.name.clone(),
        passed,
        detail,
    };
    if status != 200 {
        let code = route.get("error_code").and_then(Value::as_i64);
        return Ok(outcome(
            case.no_route_ok && code == Some(442),
            format!("no route (HTTP {status}, Valhalla error {code:?})"),
        ));
    }
    let km = route
        .pointer("/trip/summary/length")
        .and_then(Value::as_f64)
        .unwrap_or(f64::NAN);
    let shape = route
        .pointer("/trip/legs/0/shape")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let (_, trace) = post(
        http,
        &format!("{base}/trace_attributes"),
        &json!({
            "encoded_polyline": shape,
            "costing": "auto",
            "costing_options": costing,
            "shape_match": "edge_walk",
            "filters": {"attributes": ["edge.way_id"], "action": "include"},
        }),
    )
    .await?;
    let ways: Vec<i64> = trace
        .get("edges")
        .and_then(Value::as_array)
        .map(|edges| {
            edges
                .iter()
                .filter_map(|e| e.get("way_id").and_then(Value::as_i64))
                .collect()
        })
        .unwrap_or_default();
    let used: Vec<i64> = case
        .avoid_ways
        .iter()
        .copied()
        .filter(|w| ways.contains(w))
        .collect();
    let missing: Vec<i64> = case
        .use_ways
        .iter()
        .copied()
        .filter(|w| !ways.contains(w))
        .collect();
    let long_enough = case.min_km.is_none_or(|m| km >= m);
    let short_enough = case.max_km.is_none_or(|m| km <= m);
    let second_pass = relaxed(&route);
    let passed = used.is_empty()
        && missing.is_empty()
        && long_enough
        && short_enough
        && !ways.is_empty()
        && !(case.first_pass && second_pass);
    Ok(outcome(
        passed,
        format!(
            "{km:.2} km, {} edges; forbidden ways used: {used:?}; required ways missing: {missing:?}{}",
            ways.len(),
            if second_pass {
                "; found by the relaxed second pass"
            } else {
                ""
            }
        ),
    ))
}

/// Runs every case of `cases_json` (a JSON array of [`Case`]).
///
/// # Errors
///
/// [`IngestError::Json`] when the file is not a list of cases, or the first
/// failure to reach the server.
pub async fn run_all(
    http: &reqwest::Client,
    base: &str,
    cases_json: &[u8],
) -> Result<Vec<Outcome>, IngestError> {
    let cases: Vec<Case> =
        serde_json::from_slice(cases_json).map_err(|source| IngestError::Json {
            what: "route test cases".into(),
            source,
        })?;
    let mut out = Vec::with_capacity(cases.len());
    for case in &cases {
        out.push(run_case(http, base, case).await?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_route_of_the_relaxed_second_pass_is_told_apart() {
        // Goult's aire for a 3.5 t motorhome on the production engine
        // (2026-10-07): the native answer carries the warning in the trip,
        // the OSRM one at its top.
        let native = json!({"trip": {"warnings": [{"code": 401,
            "text": "Routing failed on first pass, retrying with relaxed restrictions"}]}});
        let osrm = json!({"code": "Ok", "warnings": [{"code": 401, "text": "..."}]});
        assert!(relaxed(&native) && relaxed(&osrm));
        assert!(!relaxed(&json!({"trip": {"legs": []}})));
        assert!(!relaxed(&json!({"trip": {"warnings": [{"code": 400}]}})));
        let case: Case = serde_json::from_value(json!({
            "name": "x", "from": [0.0, 0.0], "to": [0.0, 0.0],
            "vehicle": {"height": 3.2, "width": 2.3, "length": 7.0, "weight": 3.5},
            "first_pass": true
        }))
        .unwrap();
        assert!(case.first_pass);
    }
}
