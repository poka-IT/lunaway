//! Builds what the API serves about speed cameras from what the sources
//! list (`docs/speed-cameras.md`), under each country's rule
//! ([`lunaway_domain::enforcement::RULES`]):
//!
//! - a country that is off gets nothing;
//! - a country of exact positions, or off while driving, gets its cameras'
//!   points, a section with its road from start to end when the engine
//!   finds it;
//! - a country of danger zones gets stretches of road: the camera's road,
//!   followed through the engine step by step before and after it, cut
//!   with the camera at a secret, stable share of the zone, no vertex near
//!   it.
//!
//! OpenStreetMap completes the official lists: a node within [`MERGE_M`] of
//! an official camera of the same kind gives it its direction, its limit
//! and a section's end, where the list's licence allows the mix (France's,
//! under the CRPA, and the CC0 lists; Catalonia's and Norway's are kept
//! apart, their compatibility with the ODbL not checked). In a country whose
//! official list is national, a node no official camera matches is left
//! out: in France 1 264 nodes of 4 120 had no official camera within 150 m,
//! some of them removed long ago (`plan/research/28-radars-limites.md`,
//! 2.2). Elsewhere OpenStreetMap's cameras stand on their own.
//!
//! An item is built again only when what it is built from changes, or
//! with `full` (a new routing graph). A build that would retire more than a
//! tenth of the live items retires none and says so.

use std::collections::{HashMap, HashSet};

use lunaway_db::{
    PgPool,
    enforcement::{self as db, DeviceRow, Item, ItemKind},
};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{
        Device, DeviceKind, Mode, RULES_VERSION, doubles_back, mode_at, rule_of, toward, zone_cut,
        zone_fraction, zone_length_m,
    },
    routing::{corridor::heading, polyline},
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{IngestError, road_events::matching::Engine};

/// How close an OpenStreetMap camera must be to an official one to be the
/// same, metres: 80 % of France's official cameras had a node within 50 m
/// (`plan/research/28-radars-limites.md`, 2.2).
pub const MERGE_M: f64 = 50.0;
/// The official lists whose licence lets OpenStreetMap's data join theirs.
const ENRICHABLE: [&str; 3] = ["securite-routiere", "pl-canard", "lu-pch-radars"];
/// The countries whose official list covers the whole country.
const NATIONAL_LISTS: [&str; 4] = ["FR", "PL", "LU", "NO"];
/// How far a route reaches for the zone's road, as a multiple of what the
/// zone needs, and at least this much more, metres: a single route to
/// points placed at the zone's ends in a straight line went around by
/// other roads for 12 of the 62 Limousin cameras on the engine's graph
/// (2026-10-06); a route toward a point well beyond only needs to start
/// on the camera's road.
const REACH_FACTOR: f64 = 2.0;
const REACH_EXTRA_M: f64 = 1_000.0;
/// What a road's length is measured beyond what the zone needs, metres:
/// the engine and the zone measure on slightly different spheres.
const SLACK_M: f64 = 100.0;
/// Least distance, as the crow flies, from a zone's end to its camera, as
/// a share of the road between them: below, the road turned back.
const MIN_SPREAD: f64 = 0.2;
/// Directions tried for a camera whose direction no source gives, degrees:
/// a one-way carriageway answers in one of them only.
const PROBES: [f64; 8] = [0.0, 180.0, 90.0, 270.0, 45.0, 225.0, 135.0, 315.0];
/// Most routes asked to follow the camera's road one way.
const MAX_ROUNDS: usize = 4;
/// Least length of a route kept on the camera's road, metres: below, the
/// route is the road's continuation and is kept whole.
const MIN_PROGRESS_M: f64 = 50.0;
/// Aims tried to either side when a route leaves the camera's road at
/// once, degrees.
const BENDS: [f64; 4] = [20.0, -20.0, 40.0, -40.0];
/// A route ahead this close to straight is along the camera's road: no
/// other direction is tried.
const STRAIGHT_ENOUGH: f64 = 1.2;
/// Heading tolerance where a step starts or ends on its road, degrees.
const HEADING_TOLERANCE_DEG: u32 = 45;
/// Heading tolerance of a route's far end, degrees: the road may have
/// turned by then, but never back on itself (the other carriageway).
const AIM_TOLERANCE_DEG: u32 = 90;
/// How far the engine looks for a road around a camera, metres.
const CAMERA_CUTOFF_M: u32 = 35;
/// How far the engine looks for a road around a route's far end, metres.
const AIM_CUTOFF_M: u32 = 2_000;
/// Longest route from a section's start to its end, as a multiple of the
/// straight distance, plus a bend's worth.
const MAX_SECTION_DETOUR: f64 = 2.0;
/// Refusals in a row after which the build stops: one refused camera is
/// that camera's matter, a run of them more likely the engine's.
const REFUSALS_IN_A_ROW: u32 = 10;
/// A build that retires more than this share of the live items retires
/// none.
const MAX_RETIRED_SHARE: f64 = 0.1;
/// Retirements always allowed, whatever the share.
const MIN_RETIRED_ALLOWED: usize = 20;
/// Moves with every change of how items are built: an item of an older
/// build is built again.
const BUILD_VERSION: u32 = 1;

/// A camera to build, its sources merged.
#[derive(Debug, Clone, PartialEq)]
pub struct Planned {
    /// The key of the item ([`DeviceRow::key`] of its first source).
    pub key: String,
    /// Its country.
    pub country: String,
    /// What the sources say together.
    pub device: Device,
    /// The sources, the first one leading.
    pub sources: Vec<String>,
}

/// What [`plan`] did with OpenStreetMap's cameras.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Merged {
    /// Nodes matched to an official camera, which they completed or not.
    pub matched: usize,
    /// Nodes left out: no official camera where the list is national.
    pub left_out: usize,
    /// Nodes that stand on their own.
    pub alone: usize,
}

/// Whether two kinds can be the same camera: the same zone, or a section's
/// start mapped as a fixed camera.
fn same_camera(a: DeviceKind, b: DeviceKind) -> bool {
    a.zone_kind() == b.zone_kind()
        || matches!(
            (a, b),
            (DeviceKind::Fixed, DeviceKind::Section) | (DeviceKind::Section, DeviceKind::Fixed)
        )
}

/// Grid cell of a position, about 1 km.
#[allow(
    clippy::cast_possible_truncation,
    reason = "degrees over a hundredth fit an i32"
)]
fn cell(p: Position) -> (i32, i32) {
    (
        (p.lat() * 100.0).floor() as i32,
        (p.lon() * 100.0).floor() as i32,
    )
}

/// The cameras to build from the live `devices`, OpenStreetMap's merged
/// into the official ones.
#[must_use]
pub fn plan(devices: Vec<DeviceRow>) -> (Vec<Planned>, Merged) {
    let osm = SourceId::OSM;
    let (osm_rows, official): (Vec<DeviceRow>, Vec<DeviceRow>) = devices
        .into_iter()
        .partition(|d| d.source_id == osm.as_str());
    let mut planned: Vec<Planned> = official
        .into_iter()
        .map(|d| Planned {
            key: d.key(),
            country: d.country,
            sources: vec![d.source_id],
            device: d.device,
        })
        .collect();
    let mut grid: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
    for (i, p) in planned.iter().enumerate() {
        grid.entry(cell(p.device.position)).or_default().push(i);
    }
    let mut merged = Merged::default();
    let mut alone = Vec::new();
    for o in osm_rows {
        let (r, c) = cell(o.device.position);
        let nearest = (-1..=1)
            .flat_map(|dr| (-1..=1).map(move |dc| (r + dr, c + dc)))
            .filter_map(|k| grid.get(&k))
            .flatten()
            .copied()
            .filter(|i| same_camera(planned[*i].device.kind, o.device.kind))
            .map(|i| (i, planned[i].device.position.distance_m(o.device.position)))
            .filter(|(_, d)| *d <= MERGE_M)
            .min_by(|a, b| a.1.total_cmp(&b.1));
        if let Some((i, _)) = nearest {
            merged.matched += 1;
            let p = &mut planned[i];
            if ENRICHABLE.contains(&p.sources[0].as_str()) {
                let d = &mut p.device;
                let before = d.clone();
                d.bearing_deg = d.bearing_deg.or(o.device.bearing_deg);
                d.limit_kmh = d.limit_kmh.or(o.device.limit_kmh);
                d.road = d.road.take().or_else(|| o.device.road.clone());
                if d.kind == DeviceKind::Section {
                    d.section_end = d.section_end.or(o.device.section_end);
                }
                if *d != before && !p.sources.iter().any(|s| s == osm.as_str()) {
                    p.sources.push(osm.as_str().to_owned());
                }
            }
        } else if NATIONAL_LISTS.contains(&o.country.as_str()) {
            merged.left_out += 1;
        } else {
            merged.alone += 1;
            alone.push(Planned {
                key: o.key(),
                country: o.country,
                sources: vec![o.source_id],
                device: o.device,
            });
        }
    }
    planned.extend(alone);
    planned.sort_by(|a, b| a.key.cmp(&b.key));
    (planned, merged)
}

/// A digest of what an item is built from.
fn digest(p: &Planned, mode: Mode) -> String {
    let input = json!({
        "build": BUILD_VERSION,
        "rules": RULES_VERSION,
        "mode": mode.code(),
        "country": p.country,
        "device": p.device,
        "sources": p.sources,
    });
    let hash = Sha256::digest(input.to_string().as_bytes());
    hash.iter().fold(String::with_capacity(64), |mut s, b| {
        use std::fmt::Write as _;
        let _ = write!(s, "{b:02x}");
        s
    })
}

/// A stable id that does not lead back to the camera without the secret.
fn item_id(secret: &[u8], key: &str) -> Uuid {
    let mut h = Sha256::new();
    h.update((secret.len() as u64).to_be_bytes());
    h.update(secret);
    h.update(b"item:");
    h.update(key.as_bytes());
    let digest = h.finalize();
    let mut bytes = [0u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    uuid::Builder::from_custom_bytes(bytes).into_uuid()
}

/// A location of a route request: where, heading which way within which
/// tolerance, how far the engine looks for its road.
struct Stop {
    at: Position,
    heading: Option<(f64, u32)>,
    cutoff_m: u32,
}

impl Stop {
    /// On the road, heading `h`.
    const fn on_road(at: Position, h: f64) -> Self {
        Self {
            at,
            heading: Some((h, HEADING_TOLERANCE_DEG)),
            cutoff_m: CAMERA_CUTOFF_M,
        }
    }

    /// A route's far end, off the road maybe, the road heading roughly
    /// `h`.
    const fn aim(at: Position, h: f64) -> Self {
        Self {
            at,
            heading: Some((h, AIM_TOLERANCE_DEG)),
            cutoff_m: AIM_CUTOFF_M,
        }
    }
}

fn request(stops: &[Stop]) -> Value {
    let locations: Vec<Value> = stops
        .iter()
        .map(|s| {
            let mut l = json!({
                "lat": s.at.lat(),
                "lon": s.at.lon(),
                "type": "break",
                "search_cutoff": s.cutoff_m,
            });
            if let Some((h, tolerance)) = s.heading {
                #[allow(
                    clippy::cast_possible_truncation,
                    clippy::cast_sign_loss,
                    reason = "a heading between 0 and 360 degrees"
                )]
                let h = h.rem_euclid(360.0).round() as u32 % 360;
                l["heading"] = h.into();
                l["heading_tolerance"] = tolerance.into();
            }
            l
        })
        .collect();
    json!({
        "locations": locations,
        "costing": "auto",
        "format": "osrm",
        "shape_format": "polyline6",
        "language": "en-US",
    })
}

/// [`request`], driving against one-way roads where needed: the road
/// behind a camera is read by driving it backwards from the camera, which
/// keeps to the camera's carriageway where a route from a point behind
/// came by any road that joins it (a camera on the A20 near Brive was
/// reached by 4.7 km of local roads and a roundabout, 2026-10-06).
fn backwards_request(stops: &[Stop]) -> Value {
    let mut body = request(stops);
    body["costing_options"] = json!({ "auto": { "ignore_oneways": true } });
    body
}

/// The first route of an answer: its shape, its length, whether its first
/// step is on a motorway, and each step's end along it with the road it
/// is on.
struct Road {
    shape: Vec<Position>,
    distance_m: f64,
    motorway_start: bool,
    steps: Vec<RoadStep>,
}

/// A step of a route: where it ends along the route, the engine's metres,
/// and the road it is on.
struct RoadStep {
    end_m: f64,
    length_m: f64,
    road: RoadId,
}

/// A road as a route's steps name it: its references and name (`A 20`,
/// `E 09`, `Route de Tulle`), and whether it is a ramp (`on ramp`, `off
/// ramp`), which is never the road a camera stands on unless the camera
/// stands on a ramp.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct RoadId {
    names: Vec<String>,
    ramp: bool,
}

impl RoadId {
    /// Whether `other` is another road than this one: a ramp off this one,
    /// or a road with a reference or a name none of which this one has. A
    /// road without either is never another, nor is any road where this
    /// one has none.
    fn left_for(&self, other: &Self) -> bool {
        (other.ramp && !self.ramp)
            || (!self.names.is_empty()
                && !other.names.is_empty()
                && !other.names.iter().any(|n| self.names.contains(n)))
    }
}

fn road_of(answer: &Value) -> Option<Road> {
    let route = answer.get("routes")?.get(0)?;
    let shape = polyline::decode(route.get("geometry")?.as_str()?).ok()?;
    let distance_m = route.get("distance").and_then(Value::as_f64)?;
    let raw_steps: Vec<&Value> = route
        .get("legs")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|l| l.get("steps").and_then(Value::as_array))
        .flatten()
        .collect();
    let motorway_start = raw_steps
        .first()
        .and_then(|s| s.get("intersections"))
        .and_then(Value::as_array)
        .and_then(|i| i.first())
        .and_then(|i| i.get("classes"))
        .and_then(Value::as_array)
        .is_some_and(|c| c.iter().any(|c| c == "motorway"));
    let mut end_m = 0.0;
    let steps = raw_steps
        .iter()
        .map(|s| {
            let length_m = s.get("distance").and_then(Value::as_f64).unwrap_or(0.0);
            end_m += length_m;
            let mut names: Vec<String> = s
                .get("ref")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .split(';')
                .map(str::trim)
                .filter(|r| !r.is_empty())
                .map(str::to_owned)
                .collect();
            if let Some(n) = s
                .get("name")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|n| !n.is_empty())
            {
                names.push(n.to_owned());
            }
            let ramp = s
                .get("maneuver")
                .and_then(|m| m.get("type"))
                .and_then(Value::as_str)
                .is_some_and(|t| t == "on ramp" || t == "off ramp");
            RoadStep {
                end_m,
                length_m,
                road: RoadId { names, ramp },
            }
        })
        .collect();
    (shape.len() >= 2).then_some(Road {
        shape,
        distance_m,
        motorway_start,
        steps,
    })
}

impl Road {
    /// The road the route starts on.
    fn start_road(&self) -> RoadId {
        self.steps
            .iter()
            .find(|s| s.length_m > 0.0)
            .map(|s| s.road.clone())
            .unwrap_or_default()
    }

    /// The road the route ends on.
    fn end_road(&self) -> RoadId {
        self.steps
            .iter()
            .rev()
            .find(|s| s.length_m > 0.0)
            .map(|s| s.road.clone())
            .unwrap_or_default()
    }

    /// The route driven the other way: a route read backwards from the
    /// camera becomes the road arriving at it.
    fn reversed(self) -> Self {
        let mut end_m = 0.0;
        let steps = self
            .steps
            .into_iter()
            .rev()
            .map(|s| {
                end_m += s.length_m;
                RoadStep { end_m, ..s }
            })
            .collect();
        let mut shape = self.shape;
        shape.reverse();
        Self {
            shape,
            steps,
            ..self
        }
    }

    /// The metres from the start (`ahead`) or before the end the route
    /// stays on `road`.
    fn kept(&self, road: &RoadId, ahead: bool) -> f64 {
        let left = |s: &&RoadStep| s.length_m > 0.0 && road.left_for(&s.road);
        if ahead {
            self.steps
                .iter()
                .find(left)
                .map_or(self.distance_m, |s| s.end_m - s.length_m)
        } else {
            self.steps
                .iter()
                .rev()
                .find(left)
                .map_or(self.distance_m, |s| self.distance_m - s.end_m)
        }
    }

    /// The shape between `from_m` and `to_m` metres from the start, the
    /// engine's metres placed by their share of the route.
    fn between(&self, from_m: f64, to_m: f64) -> Vec<Position> {
        let Some(line) = lunaway_domain::routing::RouteLine::new(self.shape.clone()) else {
            return self.shape.clone();
        };
        let scale = line.length_m() / self.distance_m.max(1.0);
        let (from, to) = (from_m * scale, to_m * scale);
        let mut out = vec![line.point_at(from)];
        out.extend(
            line.points()
                .iter()
                .zip(line.along())
                .filter(|(_, s)| **s > from && **s < to)
                .map(|(p, _)| *p),
        );
        out.push(line.point_at(to));
        out.dedup();
        out
    }
}

/// What asking the engine for a zone gave.
enum Asked {
    Zone(Vec<Position>),
    Unplaced,
}

/// Counts of the engine's answers during a build.
#[derive(Debug, Default)]
struct Calls {
    made: usize,
    refused_in_a_row: u32,
}

async fn ask(
    engine: &impl Engine,
    calls: &mut Calls,
    body: &Value,
) -> Result<Option<Road>, IngestError> {
    calls.made += 1;
    match engine.route(body).await {
        Ok(answer) => {
            calls.refused_in_a_row = 0;
            Ok(answer.as_ref().and_then(road_of))
        }
        Err(e) if e.is_refusal() => {
            calls.refused_in_a_row += 1;
            if calls.refused_in_a_row >= REFUSALS_IN_A_ROW {
                return Err(IngestError::Engine(e));
            }
            tracing::debug!(error = %e, "the routing engine refused a camera's route");
            Ok(None)
        }
        Err(e) => Err(IngestError::Engine(e)),
    }
}

/// Whether every vertex of `line` lies where the API may serve something:
/// a zone near a border never reaches into a country that is off.
fn servable(line: &[Position]) -> bool {
    line.iter().all(|p| mode_at(*p) != Mode::Off)
}

/// The road's heading at the end of `path`, over its last 30 m or so.
fn end_heading(path: &[Position]) -> Option<f64> {
    let last = *path.last()?;
    let from = path
        .iter()
        .rev()
        .find(|p| p.distance_m(last) >= 30.0)
        .or_else(|| path.first())?;
    (from.distance_m(last) > 1.0).then(|| heading(*from, last).rem_euclid(360.0))
}

/// The road's heading at the start of `path`, over its first 30 m or so.
fn start_heading(path: &[Position]) -> Option<f64> {
    let first = *path.first()?;
    let to = path
        .iter()
        .find(|p| p.distance_m(first) >= 30.0)
        .or_else(|| path.last())?;
    (first.distance_m(*to) > 1.0).then(|| heading(first, *to).rem_euclid(360.0))
}

/// The road through the camera at `p`, heading `h`, over `need_m` metres
/// ahead of it (`ahead`) or behind it: the start (or the end) of a route
/// toward a point farther on that way. Up to the next junction it is the
/// camera's own road; past it, the road a driver heading that way takes.
async fn reach(
    engine: &impl Engine,
    calls: &mut Calls,
    p: Position,
    h: f64,
    need_m: f64,
    ahead: bool,
) -> Result<Option<Road>, IngestError> {
    let far_m = (REACH_FACTOR * need_m).max(need_m + REACH_EXTRA_M);
    let way = if ahead { h } else { h + 180.0 };
    let Some(far) = toward(p, way, far_m) else {
        return Ok(None);
    };
    let stops = [Stop::on_road(p, way), Stop::aim(far, way)];
    let body = if ahead {
        request(&stops)
    } else {
        backwards_request(&stops)
    };
    Ok(ask(engine, calls, &body)
        .await?
        .filter(|r| r.distance_m >= need_m)
        .map(|r| if ahead { r } else { r.reversed() }))
}

/// The road ahead of the camera at `p`, `need_m` metres at least: in the
/// direction the sources give, or in the direction whose route runs the
/// most straight. Returns it and the road's heading at the camera.
async fn ahead_of(
    engine: &impl Engine,
    calls: &mut Calls,
    p: Position,
    bearing: Option<f64>,
    need_m: f64,
) -> Result<Option<(Road, f64)>, IngestError> {
    if let Some(b) = bearing {
        return Ok(reach(engine, calls, p, b, need_m, true)
            .await?
            .map(|r| (r, b)));
    }
    let mut best: Option<(Road, f64)> = None;
    for h in PROBES {
        let Some(road) = reach(engine, calls, p, h, need_m, true).await? else {
            continue;
        };
        let Some(end) = road.shape.last() else {
            continue;
        };
        let ratio = road.distance_m / end.distance_m(p).max(1.0);
        if best.as_ref().is_none_or(|(_, r)| ratio < *r) {
            best = Some((road, ratio));
        }
        if ratio <= STRAIGHT_ENOUGH {
            break;
        }
    }
    Ok(best.and_then(|(r, _)| start_heading(&r.shape).map(|h| (r, h))))
}

/// The camera's road for `need_m` metres ahead of it (`ahead`) or behind
/// it, from `first`, a route that leaves the camera at `at` heading `h`
/// (or reaches it): each route is kept as long as it stays on the
/// camera's road (by its reference or name, never by a ramp); where it
/// leaves it, a new route goes on from there in the road's direction. A
/// route that leaves at once is asked again aiming a little to either side
/// (the road bends); if every one leaves, the road ends there and the
/// route is its continuation, kept whole.
async fn along(
    engine: &impl Engine,
    calls: &mut Calls,
    first: Road,
    at: Position,
    h: f64,
    need_m: f64,
    ahead: bool,
) -> Result<Option<Vec<Position>>, IngestError> {
    let own = if ahead {
        first.start_road()
    } else {
        first.end_road()
    };
    let mut road = first;
    let (mut at, mut h) = (at, h);
    let mut path: Vec<Position> = Vec::new();
    let mut got = 0.0;
    for round in 0..MAX_ROUNDS {
        let mut kept = road.kept(&own, ahead);
        for bend in BENDS {
            if kept >= MIN_PROGRESS_M {
                break;
            }
            if let Some(other) = reach(engine, calls, at, h + bend, need_m - got, ahead).await? {
                let k = other.kept(&own, ahead);
                if k > kept {
                    kept = k;
                    road = other;
                }
            }
        }
        let take = if kept < MIN_PROGRESS_M {
            road.distance_m
        } else {
            kept
        };
        if ahead {
            let piece = road.between(0.0, take);
            if path.is_empty() {
                path = piece;
            } else {
                path.extend(piece.into_iter().skip(1));
            }
        } else {
            let mut piece = road.between(road.distance_m - take, road.distance_m);
            if !path.is_empty() {
                piece.pop();
                piece.extend(path);
            }
            path = piece;
        }
        got += take;
        if got >= need_m {
            return Ok(Some(path));
        }
        if round + 1 == MAX_ROUNDS {
            break;
        }
        let next = if ahead {
            path.last().copied().zip(end_heading(&path))
        } else {
            path.first().copied().zip(start_heading(&path))
        };
        let Some((next_at, next_h)) = next else {
            break;
        };
        (at, h) = (next_at, next_h);
        let Some(more) = reach(engine, calls, at, h, need_m - got, ahead).await? else {
            return Ok(None);
        };
        road = more;
    }
    Ok(None)
}

/// The zone of `p`: its road from before the camera to after it (and a
/// section's end), cut to the zone's length around it.
async fn zone(
    engine: &impl Engine,
    calls: &mut Calls,
    p: &Planned,
    secret: &[u8],
) -> Result<Asked, IngestError> {
    let Some(lengths) = rule_of(&p.country).zones else {
        return Ok(Asked::Unplaced);
    };
    let d = &p.device;
    let end = d.section_end.filter(|e| e.distance_m(d.position) > 50.0);
    let bearing = d
        .bearing_deg
        .or_else(|| end.map(|e| heading(d.position, e).rem_euclid(360.0)));
    let share = zone_fraction(secret, &p.key);
    // Without a limit, the road the camera is on says which length: the
    // road ahead is read for the longest.
    let longest = f64::from(
        d.limit_kmh
            .map_or(lengths.motorway_m, |l| zone_length_m(lengths, Some(l))),
    );
    let need = (1.0 - share) * longest + SLACK_M;
    let Some((first, b)) = ahead_of(engine, calls, d.position, bearing, need).await? else {
        return Ok(Asked::Unplaced);
    };
    let length = f64::from(match d.limit_kmh {
        Some(l) => zone_length_m(lengths, Some(l)),
        None if first.motorway_start => lengths.motorway_m,
        None => lengths.rural_m,
    });
    let (before, after) = (share * length, (1.0 - share) * length);
    let Some(behind) = reach(engine, calls, d.position, b, before + SLACK_M, false).await? else {
        return Ok(Asked::Unplaced);
    };
    let Some(behind) = along(
        engine,
        calls,
        behind,
        d.position,
        b,
        before + SLACK_M,
        false,
    )
    .await?
    else {
        return Ok(Asked::Unplaced);
    };
    // Ahead: from the camera, or from a section's end once the section is
    // driven.
    let ahead = match end {
        None => match along(engine, calls, first, d.position, b, after + SLACK_M, true).await? {
            Some(a) => a,
            None => return Ok(Asked::Unplaced),
        },
        Some(e) => {
            let Some(mut section) = section_road(engine, calls, d.position, Some(b), e).await?
            else {
                return Ok(Asked::Unplaced);
            };
            let (Some(last), Some(h)) = (section.last().copied(), end_heading(&section)) else {
                return Ok(Asked::Unplaced);
            };
            let Some(more) = reach(engine, calls, last, h, after + SLACK_M, true).await? else {
                return Ok(Asked::Unplaced);
            };
            let Some(more) = along(engine, calls, more, last, h, after + SLACK_M, true).await?
            else {
                return Ok(Asked::Unplaced);
            };
            section.extend(more.into_iter().skip(1));
            section
        }
    };
    let mut road = behind;
    road.extend(ahead.into_iter().skip(1));
    let mut cameras = vec![d.position];
    cameras.extend(end);
    let Some(line) = zone_cut(&road, &cameras, before, after) else {
        return Ok(Asked::Unplaced);
    };
    // A road that turns back (a U-turn at a roundabout) brings an end of
    // the zone back near its camera, and the zone covers less road.
    let (Some(first_point), Some(last_point), Some(last_camera)) =
        (line.first(), line.last(), cameras.last())
    else {
        return Ok(Asked::Unplaced);
    };
    let spread = first_point.distance_m(d.position) >= MIN_SPREAD * before
        && last_point.distance_m(*last_camera) >= MIN_SPREAD * after;
    Ok(if spread && !doubles_back(&line) && servable(&line) {
        Asked::Zone(line)
    } else {
        Asked::Unplaced
    })
}

/// A section's road from its start `from` to its end `to`, when the engine
/// finds one close to the straight line.
async fn section_road(
    engine: &impl Engine,
    calls: &mut Calls,
    from: Position,
    h: Option<f64>,
    to: Position,
) -> Result<Option<Vec<Position>>, IngestError> {
    let stops = [
        Stop {
            at: from,
            heading: h.map(|h| (h, HEADING_TOLERANCE_DEG)),
            cutoff_m: CAMERA_CUTOFF_M,
        },
        Stop {
            at: to,
            heading: None,
            cutoff_m: CAMERA_CUTOFF_M,
        },
    ];
    let straight = from.distance_m(to);
    Ok(ask(engine, calls, &request(&stops))
        .await?
        .filter(|r| r.distance_m <= MAX_SECTION_DETOUR * straight + SLACK_M)
        .map(|r| r.shape))
}

/// A section's road from its start to its end, for a country of exact
/// positions.
async fn section_line(
    engine: &impl Engine,
    calls: &mut Calls,
    d: &Device,
) -> Result<Option<Vec<Position>>, IngestError> {
    match d.section_end.filter(|e| e.distance_m(d.position) > 50.0) {
        Some(end) => section_road(engine, calls, d.position, d.bearing_deg, end).await,
        None => Ok(None),
    }
}

/// What a build did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BuildReport {
    /// Cameras considered, sources merged.
    pub cameras: usize,
    /// OpenStreetMap's nodes merged, left out, or alone.
    pub merged: Merged,
    /// Items unchanged since the last build.
    pub unchanged: usize,
    /// Points built (exact countries and those off while driving).
    pub points: usize,
    /// Zones built.
    pub zones: usize,
    /// Cameras of a zone country the engine could not place.
    pub unplaced: usize,
    /// Cameras of countries that are off.
    pub off: usize,
    /// Engine calls.
    pub engine_calls: usize,
    /// Items written.
    pub written: u64,
    /// Items retired.
    pub retired: u64,
    /// Whether retiring was refused: more than a tenth would go.
    pub retire_refused: bool,
}

/// Builds the items from the live devices, the zones through `engine`,
/// keyed with `secret`; every item again with `full`.
///
/// # Errors
///
/// [`IngestError::Db`] when the database fails; [`IngestError::Engine`]
/// when the engine does not answer or refuses a run of cameras: nothing is
/// written then.
pub async fn build(
    pool: &PgPool,
    engine: &impl Engine,
    secret: &[u8],
    full: bool,
) -> Result<BuildReport, IngestError> {
    let (planned, merged) = plan(db::live_devices(pool).await?);
    let known = db::item_digests(pool).await?;
    let mut report = BuildReport {
        cameras: planned.len(),
        merged,
        ..BuildReport::default()
    };
    let mut calls = Calls::default();
    let mut items = Vec::new();
    let mut kept: HashSet<String> = HashSet::new();
    for p in &planned {
        let mode = rule_of(&p.country).mode;
        if mode == Mode::Off || mode_at(p.device.position) == Mode::Off {
            report.off += 1;
            continue;
        }
        let hash = digest(p, mode);
        if !full && known.get(&p.key) == Some(&hash) {
            report.unchanged += 1;
            kept.insert(p.key.clone());
            continue;
        }
        let d = &p.device;
        let item = match mode {
            Mode::Zones => match zone(engine, &mut calls, p, secret).await? {
                Asked::Zone(line) => {
                    report.zones += 1;
                    Item {
                        id: item_id(secret, &p.key),
                        device_key: p.key.clone(),
                        kind: ItemKind::Zone,
                        category: d.kind.zone_kind().code().to_owned(),
                        country: p.country.clone(),
                        line: Some(line),
                        point: None,
                        bearing_deg: None,
                        limit_kmh: None,
                        source_ids: p.sources.clone(),
                        content_hash: hash,
                    }
                }
                Asked::Unplaced => {
                    report.unplaced += 1;
                    continue;
                }
            },
            Mode::Exact | Mode::OffWhileDriving => {
                report.points += 1;
                let line = if d.kind == DeviceKind::Section {
                    section_line(engine, &mut calls, d)
                        .await?
                        .filter(|l| servable(l))
                } else {
                    None
                };
                Item {
                    id: item_id(secret, &p.key),
                    device_key: p.key.clone(),
                    kind: ItemKind::Camera,
                    category: d.kind.code().to_owned(),
                    country: p.country.clone(),
                    line,
                    point: Some(d.position),
                    bearing_deg: d.bearing_deg,
                    limit_kmh: d.limit_kmh,
                    source_ids: p.sources.clone(),
                    content_hash: hash,
                }
            }
            Mode::Off => continue,
        };
        kept.insert(p.key.clone());
        items.push(item);
    }
    report.engine_calls = calls.made;
    let gone: Vec<String> = known
        .keys()
        .filter(|k| !kept.contains(*k))
        .cloned()
        .collect();
    #[allow(clippy::cast_precision_loss, reason = "counts of a few thousand items")]
    let allowed = MIN_RETIRED_ALLOWED.max((known.len() as f64 * MAX_RETIRED_SHARE) as usize);
    let gone = if gone.len() > allowed {
        tracing::warn!(
            gone = gone.len(),
            live = known.len(),
            "the build would retire more than a tenth of the items; none retired"
        );
        report.retire_refused = true;
        Vec::new()
    } else {
        gone
    };
    let (written, retired) = db::write_items(pool, &items, &gone).await?;
    report.written = written;
    report.retired = retired;
    tracing::info!(
        zones = report.zones,
        points = report.points,
        unplaced = report.unplaced,
        written,
        retired,
        "speed camera items built"
    );
    Ok(report)
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use super::*;

    fn row(
        source: &str,
        id: &str,
        country: &str,
        kind: DeviceKind,
        lat: f64,
        lon: f64,
    ) -> DeviceRow {
        DeviceRow {
            source_id: source.to_owned(),
            country: country.to_owned(),
            device: Device {
                external_id: id.to_owned(),
                kind,
                position: Position::new(lat, lon).unwrap(),
                bearing_deg: None,
                limit_kmh: None,
                road: None,
                section_end: None,
                section_length_m: None,
            },
        }
    }

    #[test]
    fn openstreetmap_completes_an_official_list_and_adds_nothing_where_it_is_national() {
        let mut node = row("osm", "node/1", "FR", DeviceKind::Fixed, 45.000_2, 1.0);
        node.device.bearing_deg = Some(90.0);
        node.device.limit_kmh = Some(80);
        let stray = row("osm", "node/2", "FR", DeviceKind::Fixed, 45.1, 1.0);
        let spanish = row("osm", "node/3", "ES", DeviceKind::Fixed, 40.0, -3.0);
        let mut catalan_twin = row("osm", "node/4", "ES", DeviceKind::Fixed, 41.538_3, 0.459_5);
        catalan_twin.device.bearing_deg = Some(270.0);
        let (planned, merged) = plan(vec![
            row(
                "securite-routiere",
                "60004",
                "FR",
                DeviceKind::Fixed,
                45.0,
                1.0,
            ),
            row(
                "cat-sct-radars",
                "A-2@445,35",
                "ES",
                DeviceKind::Fixed,
                41.538_23,
                0.459_46,
            ),
            node,
            stray,
            spanish,
            catalan_twin,
        ]);
        assert_eq!(
            merged,
            Merged {
                matched: 2,
                left_out: 1,
                alone: 1
            }
        );
        let french = planned
            .iter()
            .find(|p| p.key == "securite-routiere/60004")
            .unwrap();
        assert_eq!(french.device.bearing_deg, Some(90.0));
        assert_eq!(french.device.limit_kmh, Some(80));
        assert_eq!(french.sources, ["securite-routiere", "osm"]);
        let catalan = planned
            .iter()
            .find(|p| p.key.starts_with("cat-sct"))
            .unwrap();
        assert_eq!(
            catalan.device.bearing_deg, None,
            "Catalonia's list takes nothing from OpenStreetMap"
        );
        assert_eq!(catalan.sources, ["cat-sct-radars"]);
        assert!(planned.iter().any(|p| p.key == "osm/node/3"));
        assert!(
            !planned.iter().any(|p| p.key == "osm/node/2"),
            "a French node without an official camera makes no zone"
        );
    }

    #[test]
    fn an_item_id_is_stable_and_keyed() {
        let a = item_id(b"secret", "securite-routiere/60004");
        assert_eq!(a, item_id(b"secret", "securite-routiere/60004"));
        assert_ne!(a, item_id(b"other", "securite-routiere/60004"));
        assert_ne!(a, item_id(b"secret", "securite-routiere/60005"));
    }
}
