//! The ferry crossings of a route, read from the engine's steps, so the app
//! can say that a route takes a boat even when the user asked to avoid
//! ferries: the engine treats that wish as a preference and still crosses
//! when no road leads there (Corsica, an island, Greece from Germany
//! through Italy).
//!
//! A crossing is one step, or several in a row, in `ferry` mode (Valhalla
//! 3.9.0 writes one, its name the OpenStreetMap ferry line's: `Nice -
//! Ajaccio`, `Tanger; Tarifa / ...; Tánger - Tarifa`, measured 2026-10-07).
//! The line's name orders its ports as the mapper wrote them, not as the
//! route crosses; the countries at either end come from the route's own
//! administrative areas, in driving order.

use lunaway_domain::Position;
use serde_json::Value;

/// One crossing.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Ferry {
    /// The ferry line's name, as mapped.
    pub(crate) name: Option<String>,
    /// The two ports the name gives, in its order; empty when it does not
    /// read as two places.
    pub(crate) ports: Vec<String>,
    /// Where the boat is boarded.
    pub(crate) from: Option<Position>,
    /// Where it is left.
    pub(crate) to: Option<Position>,
    /// ISO 3166-1 alpha-2 country where it is boarded.
    pub(crate) from_country: Option<String>,
    /// Country where it is left.
    pub(crate) to_country: Option<String>,
    /// Metres from the start of the route to the boarding.
    pub(crate) start_m: f64,
    /// Metres on the boat.
    pub(crate) distance_m: f64,
    /// Seconds on the boat, as the engine reckons.
    pub(crate) duration_s: f64,
    /// Index of the route's shape point where it starts.
    pub(crate) geometry_index: Option<usize>,
}

/// Most crossings read from one route: a route of Europe takes a few.
const MAX_CROSSINGS: usize = 20;
/// Longest port name kept, characters.
const MAX_PORT_CHARS: usize = 80;

/// The two ports a ferry line's name gives: of the variants of the name
/// (split on `;` and `/`, the separators OpenStreetMap's multi-language
/// names use), the first that reads as two places joined by a dash.
fn ports(name: &str) -> Vec<String> {
    const DASHES: [&str; 5] = [" - ", " \u{2013} ", " \u{2014} ", " <-> ", " \u{2194} "];
    for variant in name.split([';', '/']).map(str::trim) {
        for dash in DASHES {
            let parts: Vec<&str> = variant.split(dash).map(str::trim).collect();
            if parts.len() == 2 && parts.iter().all(|p| !p.is_empty()) {
                return parts
                    .iter()
                    .map(|p| p.chars().take(MAX_PORT_CHARS).collect())
                    .collect();
            }
        }
    }
    Vec::new()
}

fn position_of(step: &Value) -> Option<Position> {
    let loc = step.get("maneuver")?.get("location")?.as_array()?;
    let lon = loc.first()?.as_f64()?;
    let lat = loc.get(1)?.as_f64()?;
    Position::new(lat, lon).ok()
}

/// The country of a step's first intersection, from its leg's `admins`.
fn country_of(step: &Value, admins: &[Value]) -> Option<String> {
    let i = step
        .get("intersections")?
        .as_array()?
        .first()?
        .get("admin_index")?
        .as_u64()?;
    admins
        .get(usize::try_from(i).ok()?)?
        .get("iso_3166_1")?
        .as_str()
        .filter(|c| c.len() == 2 && c.bytes().all(|b| b.is_ascii_uppercase()))
        .map(str::to_owned)
}

fn geometry_index_of(step: &Value) -> Option<usize> {
    step.get("intersections")?
        .as_array()?
        .first()?
        .get("geometry_index")?
        .as_u64()
        .and_then(|i| usize::try_from(i).ok())
}

/// The crossings of one route of an OSRM answer, in driving order.
pub(crate) fn crossings(route: &Value) -> Vec<Ferry> {
    let mut out: Vec<Ferry> = Vec::new();
    let mut along = 0.0;
    let legs = route
        .get("legs")
        .and_then(Value::as_array)
        .map_or(&[][..], Vec::as_slice);
    for leg in legs {
        let admins = leg
            .get("admins")
            .and_then(Value::as_array)
            .map_or(&[][..], Vec::as_slice);
        let steps = leg
            .get("steps")
            .and_then(Value::as_array)
            .map_or(&[][..], Vec::as_slice);
        let mut open = false;
        for step in steps {
            let distance = step.get("distance").and_then(Value::as_f64).unwrap_or(0.0);
            let duration = step.get("duration").and_then(Value::as_f64).unwrap_or(0.0);
            let ferry = step.get("mode").and_then(Value::as_str) == Some("ferry");
            if ferry {
                if open && let Some(last) = out.last_mut() {
                    last.distance_m += distance;
                    last.duration_s += duration;
                } else if out.len() < MAX_CROSSINGS {
                    let name = step
                        .get("name")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|n| !n.is_empty())
                        .map(|n| n.chars().take(200).collect::<String>());
                    out.push(Ferry {
                        ports: name.as_deref().map(ports).unwrap_or_default(),
                        name,
                        from: position_of(step),
                        to: None,
                        from_country: country_of(step, admins),
                        to_country: None,
                        start_m: along,
                        distance_m: distance,
                        duration_s: duration,
                        geometry_index: geometry_index_of(step),
                    });
                    open = true;
                }
            } else if open {
                // The step after the boat starts where it lands.
                if let Some(last) = out.last_mut() {
                    last.to = position_of(step);
                    last.to_country = country_of(step, admins);
                }
                open = false;
            }
            along += distance;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn a_line_s_name_gives_its_two_ports() {
        assert_eq!(ports("Nice - Ajaccio"), ["Nice", "Ajaccio"]);
        assert_eq!(
            ports("Tanger; Tarifa / \u{637}\u{646}\u{62c}\u{629}; Tánger - Tarifa"),
            ["Tánger", "Tarifa"],
            "the first variant that names two places"
        );
        assert_eq!(
            ports("Dover (UK); Calais (F); Douvres - Calais"),
            ["Douvres", "Calais"]
        );
        assert_eq!(
            ports("Piombino \u{2013} Portoferraio"),
            ["Piombino", "Portoferraio"]
        );
        assert!(ports("Bac de Lormont").is_empty());
        assert!(ports("A - B - C").is_empty());
    }

    #[test]
    fn consecutive_ferry_steps_are_one_crossing_between_two_countries() {
        let route = json!({"legs": [{
            "admins": [{"iso_3166_1": "FR"}, {"iso_3166_1": "IT"}],
            "steps": [
                {"mode": "driving", "distance": 500.0, "duration": 60.0,
                 "maneuver": {"location": [5.37, 43.29]},
                 "intersections": [{"admin_index": 0, "geometry_index": 0}]},
                {"mode": "ferry", "name": "Nice - Ajaccio", "distance": 200_000.0, "duration": 20_000.0,
                 "maneuver": {"location": [7.28, 43.69]},
                 "intersections": [{"admin_index": 0, "geometry_index": 12}]},
                {"mode": "ferry", "name": "Nice - Ajaccio", "distance": 52_580.0, "duration": 3_615.0,
                 "maneuver": {"location": [8.0, 42.5]},
                 "intersections": [{"admin_index": 0, "geometry_index": 30}]},
                {"mode": "driving", "distance": 49.0, "duration": 7.0,
                 "maneuver": {"location": [8.74, 41.92]},
                 "intersections": [{"admin_index": 1, "geometry_index": 42}]}
            ]
        }]});
        let c = crossings(&route);
        assert_eq!(c.len(), 1, "one boat, however many steps");
        let f = &c[0];
        assert_eq!(f.name.as_deref(), Some("Nice - Ajaccio"));
        assert_eq!(f.ports, ["Nice", "Ajaccio"]);
        assert!((f.distance_m - 252_580.0).abs() < 1e-6);
        assert!((f.start_m - 500.0).abs() < 1e-6);
        assert_eq!(f.geometry_index, Some(12));
        assert_eq!(f.from_country.as_deref(), Some("FR"));
        assert_eq!(f.to_country.as_deref(), Some("IT"));
        let to = f.to.unwrap();
        assert!((to.lat() - 41.92).abs() < 1e-9 && (to.lon() - 8.74).abs() < 1e-9);
        assert!(crossings(&json!({"legs": [{"steps": [{"mode": "driving"}]}]})).is_empty());
    }
}
