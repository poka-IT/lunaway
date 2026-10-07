//! Restrictions excluded from the first engine call of a trip, found from
//! public data only.
//!
//! The engine lets some routes through a restriction the check then finds
//! (a height bar mapped on a node, a lane of a ferry terminal): each such
//! trip costs a second engine call and a second check, 1.2 to 2.6 s on the
//! backend, and every trip to Morocco met the same bar at Tarifa port
//! (`plan/research/48-latence-itineraires.md`). Knowing those places ahead
//! spares the second call, but the restriction table alone cannot tell
//! which of them routes meet: 67 119 barriers of the active graph and
//! restrictions outside the graphs may stop a 3.3 m motorhome, the engine
//! applying none of them, 15 469 in the box of a trip from Lille to Guelmim, where
//! the Tarifa bar comes 5 346th by its distance from the trip's straight
//! line, and 200 rings sent with a call cost 0.3 s of engine time when its
//! tiles are in memory, 3.7 s when they are not
//! (`plan/research/53-obstacles-publics.md`).
//!
//! So the engine is asked, from public data only: routes between the
//! capitals of the countries the graph covers ([`SEEDS`]), for a typical
//! vehicle of each class ([`CLASSES`]), are matched against those
//! restrictions ([`db::ring_candidates`]), and computed again around the
//! ones they meet, as a trip is. What they meet away from their ends is
//! kept for the class, with the number of pairs of capitals that met it.
//! A trip's first call then excludes the kept restrictions that lie in its
//! box, away from its stops, and stop its vehicle.
//!
//! Nothing here comes from a request: the list depends on the graph, the
//! restriction table and this file, and is computed again when the graph
//! or the rows outside it change (`Routing::refresh_public`), never while
//! a route is asked. On 2026-10-07 a prototype of this search (268 pairs,
//! its distances a little shorter than [`Position::distance_m`]) took 410 s
//! of engine time for the 3.3 m motorhome, one call at a time, and met 13
//! such restrictions, Tarifa's bar first (15 pairs).

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::{Duration, Instant},
};

use lunaway_db::{PgPool, routing as db};
use lunaway_domain::{
    Position,
    routing::{
        Restriction, RouteLine, RoutingDimensions, Severity, assess, exclusion_ring, match_route,
        polyline,
    },
};
use serde_json::Value;
use tokio::sync::SemaphorePermit;

use super::{
    RING_M, RouteError, Routing,
    valhalla::{self, Answer, Avoid, Engine, Stop},
};

/// A class of vehicles, and the typical vehicle whose routes find its
/// restrictions: the tallest, widest and longest of the class, so that a
/// restriction that stops any vehicle of the class stops it too. A trip
/// excludes only those that stop its own vehicle ([`blocks`]).
#[derive(Debug, Clone, Copy)]
pub(crate) struct Class {
    /// For the logs.
    pub(crate) name: &'static str,
    /// The typical vehicle.
    pub(crate) dims: RoutingDimensions,
}

const fn class(name: &'static str, height_m: f64, width_m: f64, length_m: f64) -> Class {
    Class {
        name,
        dims: RoutingDimensions {
            height_m,
            width_m,
            length_m,
            // Most motorhomes are licensed at 3.5 t: a heavier vehicle
            // still excludes the weight limits it exceeds once the check
            // finds them.
            weight_t: 3.5,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: None,
        },
    }
}

/// The classes, by height: vans up to 2.6 m, low motorhomes up to 3.0 m,
/// the rest (`lunaway_domain::routing::PRESETS`: 1.99 to 3.14 m).
pub(crate) const CLASSES: [Class; 3] = [
    class("van", 2.6, 2.1, 6.0),
    class("low", 3.0, 2.35, 7.5),
    class("high", 3.6, 2.55, 9.0),
];

/// The class of a vehicle of `dims`: the first whose typical vehicle is at
/// least as tall, the last for a taller one.
pub(crate) fn class_for(dims: &RoutingDimensions) -> usize {
    CLASSES
        .iter()
        .position(|c| c.dims.height_m >= dims.height_m)
        .unwrap_or(CLASSES.len() - 1)
}

/// The capitals of the countries the Europe graph covers
/// (`infra/routing/europe-extracts.txt`), their centres: public points
/// spread over the whole area, whose trips cross the straits, the Alps and
/// the borders that long trips cross.
pub(crate) const SEEDS: [(&str, f64, f64); 24] = [
    ("Amsterdam", 52.3676, 4.9041),
    ("Andorra la Vella", 42.5063, 1.5218),
    ("Athens", 37.9838, 23.7275),
    ("Berlin", 52.52, 13.405),
    ("Bern", 46.948, 7.4474),
    ("Brussels", 50.8503, 4.3517),
    ("Copenhagen", 55.6761, 12.5683),
    ("Dublin", 53.3498, -6.2603),
    ("Helsinki", 60.1699, 24.9384),
    ("Lisbon", 38.7223, -9.1393),
    ("Ljubljana", 46.0569, 14.5058),
    ("London", 51.5074, -0.1278),
    ("Luxembourg", 49.6116, 6.1319),
    ("Madrid", 40.4168, -3.7038),
    ("Oslo", 59.9139, 10.7522),
    ("Paris", 48.8566, 2.3522),
    ("Prague", 50.0755, 14.4378),
    ("Rabat", 34.0209, -6.8416),
    ("Rome", 41.9028, 12.4964),
    ("Stockholm", 59.3293, 18.0686),
    ("Vaduz", 47.141, 9.5215),
    ("Vienna", 48.2082, 16.3738),
    ("Warsaw", 52.2297, 21.0122),
    ("Zagreb", 45.815, 15.9819),
];

/// Engine calls for one pair of seeds at most: the first, and two more
/// around what it met.
const PAIR_ATTEMPTS: usize = 3;
/// How far a restriction met must lie from both ends of a pair to be kept,
/// and from every stop of a trip to be excluded from its first call,
/// metres: a ring within reach of a stop's snapping (5 km) could move the
/// stop to another road unnoticed, and a restriction next to a capital's
/// centre is met by the trips that start there, not by the trips across.
pub(crate) const CLEAR_OF_STOPS_M: f64 = 10_000.0;
/// How far beyond the box of its stops a trip may run, degrees: Lille to
/// Guelmim leaves it by 0.6 degree to take the ferry at Tarifa.
const TRIP_MARGIN_DEG: f64 = 1.0;
/// Restrictions excluded from a first call at most, under
/// `MAX_EXCLUSIONS`: each ring costs the engine 1 to 2 ms, more when its
/// tiles are not in memory.
const AHEAD_RINGS: usize = 50;
/// How long a refresh waits between two calls when the engine is busy:
/// the trips of the clients go first.
const BUSY_WAIT: Duration = Duration::from_millis(250);

/// A restriction routes between seeds met.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Kept {
    /// Where its ring goes: the middle of the stretch the route met.
    pub(crate) at: Position,
    /// The restriction.
    pub(crate) restriction: Restriction,
    /// Pairs of seeds whose routes met it.
    pub(crate) met: u32,
}

/// The kept restrictions of each class, for one version of the
/// restrictions.
#[derive(Debug)]
pub(crate) struct Lists {
    /// What they were computed from.
    pub(crate) version: db::RestrictionsVersion,
    /// For each of [`CLASSES`], the most met first.
    pub(crate) classes: Vec<Vec<Kept>>,
}

/// What a refresh did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refreshed {
    /// The graph the lists belong to.
    pub graph_id: String,
    /// Restrictions kept for each class.
    pub kept: Vec<usize>,
    /// Engine calls made.
    pub calls: usize,
}

/// Whether `restriction` stops a vehicle of `dims`: a finding that is not
/// a warning.
fn blocks(restriction: &Restriction, dims: &RoutingDimensions) -> bool {
    assess(restriction, dims).is_some_and(|f| f.severity != Severity::Warning)
}

/// The pairs of `seeds` a trip may join: within the longest trip asked.
fn pairs(seeds: &[Position]) -> Vec<(Position, Position)> {
    let mut out = Vec::new();
    for (i, a) in seeds.iter().enumerate() {
        for b in &seeds[i + 1..] {
            if a.distance_m(*b) <= crate::routing_query::MAX_TRIP_M {
                out.push((*a, *b));
            }
        }
    }
    out
}

/// The restrictions among `candidates` each route of `shapes` drives
/// through: the candidate's index and the middle of the stretch met.
/// `None` when a route meets none: the trip has a way through. Each route
/// matched off the async threads by the caller.
fn met_by(
    shapes: &[String],
    candidates: &[db::NearRestriction],
) -> Result<Option<Vec<(usize, Position)>>, RouteError> {
    let mut all = Vec::new();
    for shape in shapes {
        let points = polyline::decode(shape).map_err(RouteError::Shape)?;
        let (mut south, mut west, mut north, mut east) = (
            f64::INFINITY,
            f64::INFINITY,
            f64::NEG_INFINITY,
            f64::NEG_INFINITY,
        );
        for p in &points {
            south = south.min(p.lat());
            north = north.max(p.lat());
            west = west.min(p.lon());
            east = east.max(p.lon());
        }
        let line = RouteLine::new(points).ok_or(RouteError::Malformed("a route of one point"))?;
        // Only the restrictions whose box meets the route's, widened by a
        // hundredth of a degree (a kilometre, more than any tolerance), are
        // matched: the others cannot lie on it.
        let mut here = Vec::new();
        for (i, c) in candidates.iter().enumerate() {
            let outside = c.geometry.iter().all(|p| p.lat() < south - 0.01)
                || c.geometry.iter().all(|p| p.lat() > north + 0.01)
                || c.geometry.iter().all(|p| p.lon() < west - 0.01)
                || c.geometry.iter().all(|p| p.lon() > east + 0.01);
            if outside {
                continue;
            }
            if let Some(hit) =
                match_route(&line, &c.geometry, c.restriction.source.tolerance_m()).first()
            {
                here.push((i, hit.middle));
            }
        }
        if here.is_empty() {
            return Ok(None);
        }
        all.extend(here);
    }
    Ok(Some(all))
}

impl Routing {
    /// The kept restrictions graph `graph_id` holds that a trip through
    /// `stops` for a vehicle of `dims` may meet: in the box of its stops,
    /// away from each of them, stopping the vehicle; the most met first,
    /// [`AHEAD_RINGS`] at most. None while no list of that graph is ready.
    pub(crate) fn ahead(
        &self,
        graph_id: &str,
        stops: &[Stop],
        dims: &RoutingDimensions,
    ) -> Vec<Position> {
        let lists = self
            .public
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let Some(lists) = lists.filter(|l| l.version.graph_id == graph_id) else {
            return Vec::new();
        };
        if stops.is_empty() {
            return Vec::new();
        }
        let (mut south, mut west, mut north, mut east) =
            (90.0_f64, 180.0_f64, -90.0_f64, -180.0_f64);
        for s in stops {
            south = south.min(s.at.lat());
            north = north.max(s.at.lat());
            west = west.min(s.at.lon());
            east = east.max(s.at.lon());
        }
        lists.classes[class_for(dims)]
            .iter()
            .filter(|k| {
                (south - TRIP_MARGIN_DEG..=north + TRIP_MARGIN_DEG).contains(&k.at.lat())
                    && (west - TRIP_MARGIN_DEG..=east + TRIP_MARGIN_DEG).contains(&k.at.lon())
                    && stops
                        .iter()
                        .all(|s| s.at.distance_m(k.at) > CLEAR_OF_STOPS_M)
                    && blocks(&k.restriction, dims)
            })
            .map(|k| k.at)
            .take(AHEAD_RINGS)
            .collect()
    }

    /// Computes the kept restrictions again from `seeds` when the
    /// restrictions changed since the last time (a new graph, an import of
    /// the rows outside the graphs); what it did, or `None` when nothing
    /// changed, no graph is active, no engine is set up, or another refresh
    /// runs. The lists of the previous version serve until the new ones
    /// replace them, those of another graph never.
    ///
    /// # Errors
    ///
    /// [`RouteError`] when the database fails, or the engine does not
    /// answer: the lists stay as they were.
    pub(crate) async fn refresh_public(
        &self,
        pool: &PgPool,
        seeds: &[Position],
    ) -> Result<Option<Refreshed>, RouteError> {
        let Some(engine) = self.engine.as_ref() else {
            return Ok(None);
        };
        let Ok(_one) = self.refreshing.try_lock() else {
            return Ok(None);
        };
        let Some(version) = db::restrictions_version(pool).await? else {
            return Ok(None);
        };
        let current = self
            .public
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if current.is_some_and(|c| c.version == version) {
            return Ok(None);
        }
        let started = Instant::now();
        let pairs = pairs(seeds);
        let mut classes = Vec::with_capacity(CLASSES.len());
        let mut calls = 0;
        for class in &CLASSES {
            let (kept, n) = self
                .discover(engine, pool, &version.graph_id, class, &pairs)
                .await?;
            tracing::info!(
                class = class.name,
                kept = kept.len(),
                calls = n,
                "restrictions kept ahead for a class of vehicles"
            );
            classes.push(kept);
            calls += n;
        }
        let refreshed = Refreshed {
            graph_id: version.graph_id.clone(),
            kept: classes.iter().map(Vec::len).collect(),
            calls,
        };
        tracing::info!(
            graph = %refreshed.graph_id,
            pairs = pairs.len(),
            calls,
            seconds = started.elapsed().as_secs(),
            "restrictions kept ahead computed again"
        );
        // Rows changed while the routes ran are seen by the next refresh:
        // the version read at the start is the one these lists answer.
        *self
            .public
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner) =
            Some(Arc::new(Lists { version, classes }));
        Ok(Some(refreshed))
    }

    /// An engine slot, taken only while another one stays free for the
    /// clients' trips.
    async fn spare_slot(&self) -> SemaphorePermit<'_> {
        let keep_free = usize::from(self.concurrency > 1);
        loop {
            if self.slots.available_permits() > keep_free
                && let Ok(permit) = self.slots.try_acquire()
            {
                return permit;
            }
            tokio::time::sleep(BUSY_WAIT).await;
        }
    }

    /// The restrictions routes between `pairs` meet for `class`, the most
    /// met first, and the engine calls it took.
    async fn discover(
        &self,
        engine: &Engine,
        pool: &PgPool,
        graph_id: &str,
        class: &Class,
        pairs: &[(Position, Position)],
    ) -> Result<(Vec<Kept>, usize), RouteError> {
        let dims = class.dims;
        let candidates: Vec<db::NearRestriction> = db::ring_candidates(
            pool,
            graph_id,
            db::Envelope {
                height_m: dims.height_m,
                width_m: dims.width_m,
                length_m: dims.length_m,
                weight_t: dims.weight_t,
            },
        )
        .await?
        .into_iter()
        .filter(|c| blocks(&c.restriction, &dims))
        .collect();
        if candidates.is_empty() {
            return Ok((Vec::new(), 0));
        }
        let candidates = Arc::new(candidates);
        let costing = valhalla::costing_options(&dims, Avoid::default());
        let mut kept: HashMap<uuid::Uuid, Kept> = HashMap::new();
        let mut calls = 0;
        for &(a, b) in pairs {
            let stops = [
                Stop {
                    at: a,
                    heading: None,
                },
                Stop {
                    at: b,
                    heading: None,
                },
            ];
            let alternates = valhalla::alternates_for(2, a.distance_m(b));
            let mut exclusions: Vec<Vec<Position>> = Vec::new();
            let mut centres: Vec<Position> = Vec::new();
            let mut counted: HashSet<uuid::Uuid> = HashSet::new();
            for _ in 0..PAIR_ATTEMPTS {
                let body = valhalla::discovery_body(&stops, &costing, alternates, &exclusions);
                let answer = {
                    let _slot = self.spare_slot().await;
                    engine.route(&body).await
                };
                calls += 1;
                let osrm = match answer {
                    Ok(Answer::Routes(v)) => v,
                    Ok(Answer::NoRoute | Answer::NoSegment) => break,
                    // A refusal concerns this pair: the others are asked.
                    Err(error @ valhalla::EngineError::Refused { .. }) => {
                        tracing::warn!(%error, "a route between seeds was refused");
                        break;
                    }
                    Err(error) => return Err(error.into()),
                };
                let shapes: Vec<String> = osrm
                    .get("routes")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(|r| r.get("geometry").and_then(Value::as_str))
                    .map(str::to_owned)
                    .collect();
                let shared = Arc::clone(&candidates);
                let met = tokio::task::spawn_blocking(move || met_by(&shapes, &shared))
                    .await
                    .map_err(RouteError::Blocking)??;
                let Some(met) = met else {
                    break;
                };
                let before = exclusions.len();
                for (i, middle) in met {
                    let c = &candidates[i];
                    // Kept only away from the pair's ends; excluded from
                    // the next call wherever it is, as a trip does.
                    if a.distance_m(middle) > CLEAR_OF_STOPS_M
                        && b.distance_m(middle) > CLEAR_OF_STOPS_M
                        && counted.insert(c.id)
                    {
                        kept.entry(c.id)
                            .or_insert_with(|| Kept {
                                at: middle,
                                restriction: c.restriction.clone(),
                                met: 0,
                            })
                            .met += 1;
                    }
                    if centres.iter().all(|x| x.distance_m(middle) >= RING_M / 2.0) {
                        centres.push(middle);
                        exclusions.push(exclusion_ring(middle, RING_M));
                    }
                }
                if exclusions.len() == before {
                    break;
                }
            }
        }
        let mut kept: Vec<Kept> = kept.into_values().collect();
        // The most met first; the same order from one run to the next.
        kept.sort_by(|x, y| {
            y.met
                .cmp(&x.met)
                .then(x.at.lat().total_cmp(&y.at.lat()))
                .then(x.at.lon().total_cmp(&y.at.lon()))
        });
        Ok((kept, calls))
    }
}

#[cfg(test)]
mod tests {
    use lunaway_domain::routing::{
        Certainty, RestrictionFeature, RestrictionKind, RestrictionSource,
    };

    use super::*;

    #[test]
    fn every_preset_falls_in_a_class_whose_vehicle_is_at_least_as_large() {
        for preset in lunaway_domain::routing::PRESETS {
            let dims = RoutingDimensions {
                height_m: preset.height_m,
                width_m: preset.width_m,
                length_m: preset.length_m,
                weight_t: preset.weight_t,
                axle_load_t: None,
                trailer_weight_t: None,
                top_speed_kph: None,
            };
            let c = CLASSES[class_for(&dims)].dims;
            assert!(
                c.height_m >= dims.height_m && c.width_m >= dims.width_m,
                "{}: the class's routes must meet what stops the preset",
                preset.id
            );
        }
    }

    #[test]
    fn pairs_stay_within_the_longest_trip() {
        let seeds: Vec<Position> = SEEDS
            .iter()
            .map(|&(_, lat, lon)| Position::new(lat, lon).unwrap())
            .collect();
        let all = pairs(&seeds);
        assert_eq!(
            all.len(),
            271,
            "the pairs of capitals within the longest trip"
        );
        assert!(
            all.iter()
                .all(|(a, b)| a.distance_m(*b) <= crate::routing_query::MAX_TRIP_M)
        );
    }

    #[test]
    fn a_kept_restriction_goes_ahead_only_where_it_may_stop_the_trip() {
        let routing = Routing::new(&crate::config::RoutingConfig::default());
        let g = "20261006T2326Z-eu";
        let tarifa = Position::new(36.011_235, -5.604_291).unwrap();
        let bar = Restriction {
            kind: RestrictionKind::MaxHeight,
            limit: None,
            source: RestrictionSource::Osm,
            certainty: Certainty::Unknown,
            feature: RestrictionFeature::Barrier,
        };
        let kept = |met| Kept {
            at: tarifa,
            restriction: bar.clone(),
            met,
        };
        *routing.public.write().unwrap() = Some(Arc::new(Lists {
            version: db::RestrictionsVersion {
                graph_id: g.to_owned(),
                outside_rows: 0,
                outside_newest: None,
            },
            classes: vec![vec![kept(15)], vec![kept(15)], vec![kept(15)]],
        }));
        let stop = |lat, lon| Stop {
            at: Position::new(lat, lon).unwrap(),
            heading: None,
        };
        let lille_guelmim = [stop(50.6292, 3.0573), stop(28.9870, -10.0574)];
        let dims = |height_m| RoutingDimensions {
            height_m,
            width_m: 2.3,
            length_m: 7.4,
            weight_t: 3.5,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: None,
        };
        assert_eq!(routing.ahead(g, &lille_guelmim, &dims(3.3)), [tarifa]);
        assert!(
            routing.ahead(g, &lille_guelmim, &dims(2.0)).is_empty(),
            "a van under the bars' assumed height is not kept from it"
        );
        assert!(
            routing
                .ahead("20261013T0300Z-eu", &lille_guelmim, &dims(3.3))
                .is_empty(),
            "lists of another graph are never used"
        );
        assert!(
            routing
                .ahead(g, &[stop(48.39, -4.49), stop(50.06, 19.94)], &dims(3.3))
                .is_empty(),
            "a trip from Brest to Krakow cannot meet Tarifa"
        );
        assert!(
            routing
                .ahead(g, &[stop(36.06, -5.65), stop(37.39, -5.98)], &dims(3.3))
                .is_empty(),
            "a trip starting near it: a ring there could move the stop"
        );
    }
}
