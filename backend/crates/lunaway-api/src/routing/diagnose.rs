//! Why the engine found no route, in terms the app can show.
//!
//! The engine answers `NoRoute` without a reason. Measured on the Europe
//! graph (`plan/research/35-routage-europe-prod.md`, 4.1), the usual cause
//! is a stop the vehicle cannot legally reach: every way in or out of it
//! passes a limit lower than the vehicle (a 3.2 m IGN height around a
//! gravel yard, a 1.5 t street in Warsaw, a 2.1 m passage before Venice's
//! car ferry). The engine routes there once the dimensions are lifted. So
//! the diagnosis asks the engine a few short questions, each stop against a
//! reference point on a main road at least 30 km away ([`HUBS`]):
//!
//! 1. the stop and its reference for the real vehicle (to the reference
//!    from the origin, from it to the destination, both for a waypoint): a
//!    stop that passes is reachable;
//! 2. a stop that fails, for the smallest vehicle a profile accepts,
//!    unpaved roads allowed: no route then means no road joins the stop at
//!    all (an island without a car ferry);
//! 3. the stop against its second nearest reference, for the real vehicle:
//!    a failure with one reference only is that reference's;
//! 4. on the first, each limit lifted alone (then each kept alone, when
//!    lifting one is not enough): the limits that make the difference.
//!
//! A point of the trip's own route would not do as the reference: on a
//! short trip it can lie inside the closed area itself (the car ferry
//! lanes of Venice, the valley road of Andorra, measured 2026-10-07), and
//! the open end would be blamed. A trip on an island that has no reference
//! and no car ferry is answered `NOT_CONNECTED` for its stops, whatever
//! limit closes it.
//!
//! One diagnosis runs at a time on the server, inside the route's engine
//! slot and within what is left of its deadline (`Routing::explain`).
//!
//! The figure of the limit comes from our own check of the small vehicle's
//! route to the reference against every restriction we know
//! (`match_restrictions`): the blocking restriction of the kind found
//! nearest the stop. When every stop is reachable and the trip still
//! fails, the blocking limits lie on the way between, and only our check
//! of the small vehicle's whole trip names them.

use std::time::Duration;

use lunaway_db::{PgPool, routing as db};
use lunaway_domain::{
    Position,
    routing::{FindingKind, RouteLine, RoutingDimensions, polyline},
};
use serde_json::Value;

use super::{
    CORRIDOR_M, Met, RouteError, RouteRequest,
    valhalla::{self, Answer, Avoid, Constraint, Engine, Stop},
};

/// Longest the diagnosis may take, after the attempt that found no route:
/// a trip without a route is still answered within the route's deadline,
/// unexplained when the questions take longer.
pub(crate) const DIAGNOSIS_DEADLINE: Duration = Duration::from_secs(6);
/// Least distance from a stop to its reference points, metres: farther
/// than the closed areas met (a few kilometres), near enough for a fast
/// answer.
const MIN_REFERENCE_M: f64 = 30_000.0;
/// Longest trip, in a straight line, whose own route for the small vehicle
/// is asked when every stop is reachable, metres: beyond it that question
/// alone would take seconds of the engine, and the answer names the way
/// between without its limits.
const WHOLE_TRIP_M: f64 = 1_000_000.0;

/// Reference points of the diagnosis: a point on a main road 12 km out of
/// each city (20 km for Toulouse), along the route to a neighbouring city,
/// `(name, latitude, longitude)`. Each was reached and left by a large
/// motorhome (3.6 m, 2.55 m, 12 m, 7.5 t) from its neighbour's point on the
/// Europe graph `20261006T2326Z-eu` (2026-10-07).
pub(crate) const HUBS: &[(&str, f64, f64)] = &[
    ("A Coruna", 43.30266, -8.33205),
    ("Aarhus", 56.11828, 10.07403),
    ("Agadir", 30.41243, -9.50701),
    ("Ajaccio", 41.96929, 8.81762),
    ("Amsterdam", 52.28755, 4.94683),
    ("Andorra la Vella", 42.56841, 1.60361),
    ("Athens", 38.01160, 23.61082),
    ("Barcelona", 41.46637, 2.17781),
    ("Bari", 41.09186, 16.78055),
    ("Bastia", 42.59494, 9.43861),
    ("Belfast", 54.51359, -6.01301),
    ("Bergen", 60.46408, 5.32438),
    ("Berlin", 52.48620, 13.25672),
    ("Bern", 47.02557, 7.51884),
    ("Bilbao", 43.26593, -2.83702),
    ("Birmingham", 52.55090, -1.95676),
    ("Bologna", 44.46481, 11.27462),
    ("Bordeaux", 44.76405, -0.54870),
    ("Brno", 49.09346, 16.59514),
    ("Brussels", 50.88388, 4.22193),
    ("Cagliari", 39.29480, 9.06265),
    ("Cardiff", 51.53409, -3.10051),
    ("Casablanca", 33.61265, -7.48556),
    ("Catania", 37.46633, 14.97625),
    ("Chania", 35.48241, 24.08693),
    ("Clermont-Ferrand", 45.79131, 3.20296),
    ("Cologne", 50.91900, 7.08772),
    ("Copenhagen", 55.61561, 12.48777),
    ("Cork", 51.94707, -8.39264),
    ("Dakhla", 23.76657, -15.90727),
    ("Dijon", 47.27675, 5.13780),
    ("Dublin", 53.44740, -6.20425),
    ("Edinburgh", 55.85551, -3.18880),
    ("Faro", 37.09842, -7.88579),
    ("Fes", 33.94906, -5.06552),
    ("Florence", 43.72114, 11.23665),
    ("Frankfurt", 50.11868, 8.54209),
    ("Galway", 53.29572, -8.91164),
    ("Gdansk", 54.27433, 18.59373),
    ("Geneva", 46.15650, 6.17189),
    ("Girona", 41.90644, 2.77266),
    ("Glasgow", 55.85307, -4.08946),
    ("Gothenburg", 57.61867, 12.03987),
    ("Graz", 47.00691, 15.43240),
    ("Hamburg", 53.46661, 10.02452),
    ("Hanover", 52.43139, 9.66899),
    ("Helsinki", 60.25436, 24.88218),
    ("Heraklion", 35.32317, 25.06023),
    ("Innsbruck", 47.27884, 11.53752),
    ("Krakow", 50.11970, 19.87748),
    ("Laayoune", 27.23388, -13.14932),
    ("Las Palmas", 28.04001, -15.41180),
    ("Leipzig", 51.41754, 12.30222),
    ("Lille", 50.60010, 3.19591),
    ("Limoges", 45.76220, 1.32987),
    ("Lisbon", 38.64972, -9.16819),
    ("Ljubljana", 46.00281, 14.57812),
    ("Lleida", 41.69526, 0.70792),
    ("London", 51.57265, -0.22662),
    ("Los Cristianos", 28.05167, -16.61021),
    ("Luxembourg", 49.63456, 5.98441),
    ("Lyon", 45.80647, 4.92743),
    ("Madrid", 40.44129, -3.59229),
    ("Malaga", 36.81571, -4.44834),
    ("Malmo", 55.56544, 12.89584),
    ("Manacor", 39.56286, 3.09588),
    ("Manchester", 53.47668, -2.39860),
    ("Marrakech", 31.68472, -8.03848),
    ("Marseille", 43.37891, 5.31709),
    ("Maspalomas", 27.79430, -15.49290),
    ("Mestre", 45.45369, 12.11028),
    ("Milan", 45.40869, 9.11001),
    ("Montpellier", 43.63413, 3.97046),
    ("Munich", 48.04741, 11.64740),
    ("Nantes", 47.30635, -1.63614),
    ("Naples", 40.91320, 14.32124),
    ("Nuremberg", 49.38264, 11.12881),
    ("Oristano", 39.82922, 8.63006),
    ("Oslo", 59.83552, 10.83949),
    ("Oulu", 65.10935, 25.42893),
    ("Palermo", 38.08163, 13.47039),
    ("Palma", 39.56757, 2.76045),
    ("Paris", 48.87440, 2.43862),
    ("Patras", 38.31595, 21.82973),
    ("Pau", 43.28173, -0.24322),
    ("Perpignan", 42.68377, 2.76786),
    ("Porto", 41.23417, -8.56577),
    ("Poznan", 52.35037, 16.83440),
    ("Prague", 50.01230, 14.53441),
    ("Rabat", 33.94991, -6.91793),
    ("Reggio Calabria", 38.13303, 15.52614),
    ("Rennes", 48.07101, -1.67646),
    ("Rome", 41.92261, 12.61541),
    ("Santa Cruz de Tenerife", 28.40124, -16.34023),
    ("Seville", 37.36098, -5.87268),
    ("Split", 43.55088, 16.53423),
    ("Stockholm", 59.40522, 18.03677),
    ("Strasbourg", 48.65255, 7.73571),
    ("Stuttgart", 48.72972, 9.08544),
    ("Tampere", 61.40373, 23.77241),
    ("Tangier", 35.86084, -5.72558),
    ("Thessaloniki", 40.64933, 22.81150),
    ("Toulouse", 43.46764, 1.56975),
    ("Tromso", 69.63952, 18.96877),
    ("Trondheim", 63.33207, 10.35469),
    ("Turin", 45.12921, 7.72315),
    ("Umea", 63.87165, 20.45453),
    ("Utrecht", 52.03261, 5.13633),
    ("Vaduz", 47.06001, 9.46889),
    ("Valencia", 39.54538, -0.29972),
    ("Vienna", 48.24047, 16.46018),
    ("Warsaw", 52.13627, 20.98886),
    ("Wroclaw", 51.20134, 17.05417),
    ("Zagreb", 45.76450, 15.91548),
    ("Zaragoza", 41.66272, -0.79428),
    ("Zurich", 47.41982, 8.40981),
];

/// Where a trip fails for the vehicle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Place {
    /// The stop at this index (0 the origin, the last the destination).
    Stop(usize),
    /// Between the stops: each is reachable, no way joins them.
    OnTheWay,
    /// No road joins this stop, or the stops when none is named, whatever
    /// the vehicle.
    NotConnected(Option<usize>),
}

/// A limit that blocks the vehicle.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Limit {
    /// What it limits.
    pub(crate) constraint: Constraint,
    /// The vehicle's figure, metres or tonnes (none for unpaved roads).
    pub(crate) vehicle_value: Option<f64>,
    /// The restriction that blocks, when our data has it.
    pub(crate) blocker: Option<Met>,
}

/// One reason a trip has no route.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Unreachable {
    /// Where.
    pub(crate) place: Place,
    /// The limits that make the difference; empty when unknown.
    pub(crate) limits: Vec<Limit>,
}

/// The constraint a finding of our check stands for, if the engine applies
/// one like it.
fn constraint_of(kind: FindingKind) -> Option<Constraint> {
    match kind {
        FindingKind::LowClearance | FindingKind::UnknownClearance => Some(Constraint::Height),
        FindingKind::Narrow => Some(Constraint::Width),
        FindingKind::TooLong => Some(Constraint::Length),
        FindingKind::TooHeavy => Some(Constraint::Weight),
        _ => None,
    }
}

/// The vehicle's figure for `c`.
fn vehicle_value(dims: &RoutingDimensions, c: Constraint) -> Option<f64> {
    match c {
        Constraint::Height => Some(dims.height_m),
        Constraint::Width => Some(dims.width_m),
        Constraint::Length => Some(dims.length_m),
        Constraint::Weight => Some(dims.weight_t),
        Constraint::Unpaved => None,
    }
}

/// The constraints that apply to this request.
fn constraints(avoid: Avoid) -> Vec<Constraint> {
    Constraint::ALL
        .into_iter()
        .filter(|c| *c != Constraint::Unpaved || avoid.unpaved)
        .collect()
}

/// What a probe gave.
enum Probe {
    /// A route.
    Route(Value),
    /// No route.
    None,
    /// A point did not snap: the probe says nothing.
    Unsure,
}

async fn probe(engine: &Engine, stops: &[Stop], costing: &Value) -> Result<Probe, RouteError> {
    Ok(
        match engine.route(&valhalla::probe_body(stops, costing)).await? {
            Answer::Routes(v) => Probe::Route(v),
            Answer::NoRoute => Probe::None,
            Answer::NoSegment => Probe::Unsure,
        },
    )
}

/// The stops of the engine's answer that do not snap to any road: each
/// asked alone (a trip from the stop to itself).
///
/// # Errors
///
/// [`RouteError`] when the engine fails.
pub(crate) async fn off_network(
    engine: &Engine,
    request: &RouteRequest,
    costing: &Value,
) -> Result<Vec<usize>, RouteError> {
    let mut out = Vec::new();
    for (i, s) in request.stops.iter().enumerate() {
        if matches!(probe(engine, &[*s, *s], costing).await?, Probe::Unsure) {
            out.push(i);
        }
    }
    Ok(out)
}

/// The two reference points nearest `at` and at least [`MIN_REFERENCE_M`]
/// away, nearest first.
fn references(at: Position) -> Vec<Stop> {
    let mut near: Vec<(f64, Position)> = HUBS
        .iter()
        .filter_map(|(_, lat, lon)| Position::new(*lat, *lon).ok())
        .map(|p| (at.distance_m(p), p))
        .filter(|(d, _)| *d >= MIN_REFERENCE_M)
        .collect();
    near.sort_by(|a, b| a.0.total_cmp(&b.0));
    near.into_iter().take(2).map(|(_, p)| Stop::at(p)).collect()
}

/// The trip that tests stop `i` of `last + 1` against `reference`: leaving
/// it for the origin, reaching it for the destination, both for a
/// waypoint.
fn around(stop: Stop, i: usize, last: usize, reference: Stop) -> Vec<Stop> {
    if i == 0 {
        vec![stop, reference]
    } else if i == last {
        vec![reference, stop]
    } else {
        vec![reference, stop, reference]
    }
}

/// The shape and the legs' lengths of the first route of an answer.
fn line_of(osrm: &Value) -> Result<(Vec<Position>, Vec<f64>), RouteError> {
    let route = osrm
        .get("routes")
        .and_then(|r| r.get(0))
        .ok_or(RouteError::Malformed("no routes"))?;
    let shape = route
        .get("geometry")
        .and_then(Value::as_str)
        .ok_or(RouteError::Malformed("no geometry"))?;
    let points = polyline::decode(shape).map_err(RouteError::Shape)?;
    if points.len() > db::MAX_ROUTE_POINTS {
        return Err(RouteError::TooLarge);
    }
    let legs = route
        .get("legs")
        .and_then(Value::as_array)
        .map(|legs| {
            legs.iter()
                .map(|l| l.get("distance").and_then(Value::as_f64).unwrap_or(0.0))
                .collect()
        })
        .unwrap_or_default();
    Ok((points, legs))
}

/// A route of the small vehicle, as our check reads it.
struct Checked {
    /// Its length, metres.
    length_m: f64,
    /// Where its first leg ends, metres from its start.
    first_leg_m: f64,
    /// The restrictions of the kinds the engine applies that block the
    /// vehicle on it, by our data, in driving order.
    blockers: Vec<Met>,
}

/// Our check of the first route of `osrm` for `dims`.
async fn blockers_on(
    pool: &PgPool,
    graph_id: &str,
    osrm: &Value,
    dims: &RoutingDimensions,
) -> Result<Checked, RouteError> {
    let (points, legs) = line_of(osrm)?;
    let near = db::restrictions_near(pool, graph_id, &points, CORRIDOR_M).await?;
    let Some(line) = RouteLine::new(points).map(|l| l.with_legs(&legs)) else {
        return Ok(Checked {
            length_m: 0.0,
            first_leg_m: 0.0,
            blockers: Vec::new(),
        });
    };
    let total: f64 = legs.iter().sum();
    let first_leg_m = match legs.first() {
        Some(first) if total > 0.0 => first * line.length_m() / total,
        _ => line.length_m(),
    };
    let (_, blocking) = super::match_restrictions(&line, near, dims);
    Ok(Checked {
        length_m: line.length_m(),
        first_leg_m,
        blockers: blocking
            .into_iter()
            .filter(|m| constraint_of(m.finding.kind).is_some())
            .collect(),
    })
}

/// The constraints of `all` that keep the vehicle off the trip `stops`.
async fn limits_of(
    engine: &Engine,
    stops: &[Stop],
    dims: &RoutingDimensions,
    avoid: Avoid,
    all: &[Constraint],
) -> Result<Vec<Constraint>, RouteError> {
    let mut found = Vec::new();
    for c in all {
        let costing = valhalla::relaxed_costing(dims, avoid, &[*c]);
        if matches!(probe(engine, stops, &costing).await?, Probe::Route(_)) {
            found.push(*c);
        }
    }
    if found.is_empty() {
        // No limit alone opens a way: those that close every way alone are
        // the cause.
        for c in all {
            let others: Vec<Constraint> = all.iter().copied().filter(|o| o != c).collect();
            let costing = valhalla::relaxed_costing(dims, avoid, &others);
            if matches!(probe(engine, stops, &costing).await?, Probe::None) {
                found.push(*c);
            }
        }
    }
    Ok(found)
}

/// The reasons the trip of `request` has no route for its vehicle.
///
/// # Errors
///
/// [`RouteError`] when the engine or the database fails, or a route of
/// the small vehicle does not decode.
pub(crate) async fn diagnose(
    engine: &Engine,
    pool: &PgPool,
    graph_id: &str,
    request: &RouteRequest,
) -> Result<Vec<Unreachable>, RouteError> {
    let dims = request.vehicle.routing();
    let avoid = request.avoid;
    let all = constraints(avoid);
    let full = valhalla::costing_options(&dims, avoid);
    let small = valhalla::relaxed_costing(&dims, avoid, &all);
    let last = request.stops.len().saturating_sub(1);
    let mut out = Vec::new();
    for (i, stop) in request.stops.iter().enumerate() {
        let refs = references(stop.at);
        let Some(first) = refs.first().copied() else {
            continue;
        };
        let trip = around(*stop, i, last, first);
        if !matches!(probe(engine, &trip, &full).await?, Probe::None) {
            continue;
        }
        let small_route = match probe(engine, &trip, &small).await? {
            Probe::Route(v) => v,
            Probe::None => {
                out.push(Unreachable {
                    place: Place::NotConnected(Some(i)),
                    limits: Vec::new(),
                });
                continue;
            }
            Probe::Unsure => continue,
        };
        if let Some(second) = refs.get(1).copied()
            && matches!(
                probe(engine, &around(*stop, i, last, second), &full).await?,
                Probe::Route(_)
            )
        {
            // The first reference is out of this vehicle's reach, not the
            // stop.
            continue;
        }
        let found = limits_of(engine, &trip, &dims, avoid, &all).await?;
        let checked = blockers_on(pool, graph_id, &small_route, &dims).await?;
        // Where the stop lies along the small vehicle's trip.
        let here = match i {
            0 => 0.0,
            i if i == last => checked.length_m,
            _ => checked.first_leg_m,
        };
        let limits = found
            .into_iter()
            .map(|c| Limit {
                constraint: c,
                vehicle_value: vehicle_value(&dims, c),
                blocker: checked
                    .blockers
                    .iter()
                    .filter(|m| constraint_of(m.finding.kind) == Some(c))
                    .min_by(|a, b| {
                        (a.hit.start_m - here)
                            .abs()
                            .total_cmp(&(b.hit.start_m - here).abs())
                    })
                    .cloned(),
            })
            .collect();
        out.push(Unreachable {
            place: Place::Stop(i),
            limits,
        });
    }
    if !out.is_empty() {
        return Ok(out);
    }
    // Every stop is reachable: the trip itself, for the small vehicle.
    if request.straight_m() > WHOLE_TRIP_M {
        return Ok(vec![Unreachable {
            place: Place::OnTheWay,
            limits: Vec::new(),
        }]);
    }
    let osrm = match probe(engine, &request.stops, &small).await? {
        Probe::Route(v) => v,
        Probe::None | Probe::Unsure => {
            return Ok(vec![Unreachable {
                place: Place::NotConnected(None),
                limits: Vec::new(),
            }]);
        }
    };
    let mut limits: Vec<Limit> = Vec::new();
    for m in blockers_on(pool, graph_id, &osrm, &dims).await?.blockers {
        let Some(c) = constraint_of(m.finding.kind) else {
            continue;
        };
        if !limits.iter().any(|l| l.constraint == c) {
            limits.push(Limit {
                constraint: c,
                vehicle_value: vehicle_value(&dims, c),
                blocker: Some(m),
            });
        }
    }
    Ok(vec![Unreachable {
        place: Place::OnTheWay,
        limits,
    }])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_reference_point_lies_in_the_graph() {
        for (name, lat, lon) in HUBS {
            let p = Position::new(*lat, *lon).unwrap();
            assert!(
                lunaway_domain::routing::coverage::covers(p),
                "{name}: a reference outside the graph would blame every stop near it"
            );
        }
        let limoges = Position::new(45.8336, 1.2611).unwrap();
        let refs = references(limoges);
        assert_eq!(refs.len(), 2);
        assert!(
            refs.iter()
                .all(|r| r.at.distance_m(limoges) >= MIN_REFERENCE_M)
        );
        assert!(refs[0].at.distance_m(limoges) <= refs[1].at.distance_m(limoges));
        assert!(
            refs[0].at.distance_m(limoges) < 200_000.0,
            "a reference within a short drive: {:?}",
            refs[0]
        );
    }

    #[test]
    fn a_stop_is_tested_in_the_direction_it_is_driven() {
        let s = |lat| Stop::at(Position::new(lat, 1.0).unwrap());
        let (stop, reference) = (s(45.0), s(46.0));
        assert_eq!(
            around(stop, 0, 2, reference),
            [stop, reference],
            "leave the origin"
        );
        assert_eq!(
            around(stop, 2, 2, reference),
            [reference, stop],
            "reach the destination"
        );
        assert_eq!(
            around(stop, 1, 2, reference),
            [reference, stop, reference],
            "reach and leave a waypoint"
        );
    }

    #[test]
    fn each_kind_the_engine_applies_names_its_constraint() {
        assert_eq!(
            constraint_of(FindingKind::LowClearance),
            Some(Constraint::Height)
        );
        assert_eq!(
            constraint_of(FindingKind::UnknownClearance),
            Some(Constraint::Height)
        );
        assert_eq!(constraint_of(FindingKind::Narrow), Some(Constraint::Width));
        assert_eq!(
            constraint_of(FindingKind::TooLong),
            Some(Constraint::Length)
        );
        assert_eq!(
            constraint_of(FindingKind::TooHeavy),
            Some(Constraint::Weight)
        );
        assert_eq!(
            constraint_of(FindingKind::MotorhomeBan),
            None,
            "the engine does not know it: never the reason it finds no route"
        );
        assert_eq!(
            constraints(Avoid::default()),
            [
                Constraint::Height,
                Constraint::Weight,
                Constraint::Width,
                Constraint::Length
            ]
        );
        assert!(
            constraints(Avoid {
                unpaved: true,
                ..Avoid::default()
            })
            .contains(&Constraint::Unpaved)
        );
    }
}
