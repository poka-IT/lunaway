//! Prepares the routing graph's input and the restrictions the API checks
//! routes against, from the France extract and IGN's restricted sections
//! (`lunaway routing prepare`, run by `infra/routing/build-graph.sh`).
//!
//! Two outputs, from one reading of the data:
//!
//! - `fixes.osc.gz`, an OpenStreetMap change file that `osmium
//!   apply-changes` folds into the extract before Valhalla reads it: limits
//!   rewritten in the form Valhalla parses, `maxweightrating` copied into
//!   `maxweight`, `motorhome=*` copied into `motorcar`, IGN limits written
//!   onto the OpenStreetMap ways they match, the most restrictive value
//!   winning (`lunaway_domain::routing::tags`);
//! - `restrictions.ndjson.gz`, one [`RestrictionRecord`] per line: every
//!   physical limit and motorhome or trailer ban on a road or a node, from
//!   OpenStreetMap and IGN, with its geometry, for the check after each
//!   route (`lunaway routing load`).
//!
//! The extract is read in three parallel passes, as the place import does
//! (`osm_extract`): the nodes (restricted ones, and those near an IGN
//! section), the ways, then the coordinates of the ways kept.

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    io::Write as _,
    path::Path,
};

use chrono::{DateTime, TimeZone, Utc};
use lunaway_domain::{
    Position,
    routing::{
        Certainty, RestrictionFeature, RestrictionKind, RestrictionRecord, RestrictionSource,
        RouteLine, match_route, polyline,
        tags::{self, TagValue},
    },
};
use osmpbf::{BlobDecode, BlobReader, Element as PbfElement, ElementReader};
use serde::Serialize;

use crate::{IngestError, ign::IgnSection};

/// The values of `highway` a motor vehicle may drive on.
const ROUTABLE: [&str; 18] = [
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
    "secondary",
    "secondary_link",
    "tertiary",
    "tertiary_link",
    "unclassified",
    "residential",
    "living_street",
    "service",
    "road",
    "track",
    "busway",
    "rest_area",
];

/// How far an IGN section may lie from the OpenStreetMap way it describes:
/// both draw the road's centreline, from different surveys.
const IGN_MATCH_M: f64 = 12.0;
/// Grid cell of the IGN index, degrees: about 110 m of latitude.
const CELL_DEG: f64 = 0.001;
/// A covered way longer than this is a tunnel rather than an underpass.
const TUNNEL_FROM_M: f64 = 100.0;

/// What a preparation did, written next to its outputs (`prepare.json`).
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct PrepareReport {
    /// The extract's replication timestamp, from its header.
    pub osm_data_at: Option<DateTime<Utc>>,
    /// The BD TOPO edition the WFS stated, for the attribution.
    pub ign_edition: Option<chrono::NaiveDate>,
    /// Routable ways read.
    pub routable_ways: usize,
    /// Ways with a restriction for the check.
    pub restricted_ways: usize,
    /// Nodes with a restriction for the check.
    pub restricted_nodes: usize,
    /// Ways the change file rewrites.
    pub fixed_ways: usize,
    /// Nodes the change file rewrites.
    pub fixed_nodes: usize,
    /// Ways whose `maxweight` comes from `maxweightrating`.
    pub weight_rating_copied: usize,
    /// Ways and nodes whose `motorhome` access was copied to `motorcar`.
    pub motorhome_access_copied: usize,
    /// Limit values no sign carries, left for a human.
    pub invalid_values: usize,
    /// IGN sections read.
    pub ign_sections: usize,
    /// IGN sections matched to at least one OpenStreetMap way.
    pub ign_matched: usize,
    /// Ways whose limit the IGN value lowered or set.
    pub ign_applied: usize,
    /// Restrictions where the sources disagree beyond the tolerance.
    pub disputed: usize,
    /// Restriction records written.
    pub records: usize,
}

/// A node or way to rewrite, as the change file needs it.
#[derive(Debug, Clone, PartialEq)]
struct Rewrite {
    id: i64,
    version: i32,
    timestamp: DateTime<Utc>,
    /// The node's position, or the way's node list.
    shape: RewriteShape,
    tags: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq)]
enum RewriteShape {
    Node(Position),
    Way(Vec<i64>),
}

/// The outputs of a preparation, before they are written.
#[derive(Debug, Clone, Default)]
pub struct Prepared {
    /// The restrictions.
    pub records: Vec<RestrictionRecord>,
    rewrites: Vec<Rewrite>,
    /// What was done.
    pub report: PrepareReport,
}

fn tag_map<'a>(tags: impl Iterator<Item = (&'a str, &'a str)>) -> BTreeMap<String, String> {
    tags.map(|(k, v)| (k.to_owned(), v.to_owned())).collect()
}

fn is_routable(tags: &BTreeMap<String, String>) -> bool {
    tags.get("highway")
        .is_some_and(|h| ROUTABLE.contains(&h.as_str()))
        && tags.get("area").map(String::as_str) != Some("yes")
}

/// The restrictions an element's tags carry, before its geometry is known:
/// `(kind, limit, certainty)`, and how many limit values were unusable.
fn restrictions_of(
    tags: &BTreeMap<String, String>,
    is_node: bool,
) -> (Vec<(RestrictionKind, Option<f64>, Certainty)>, usize) {
    let mut out = Vec::new();
    let mut invalid = 0;
    for kind in RestrictionKind::LIMITS {
        if !tags::has_key(tags, kind) {
            continue;
        }
        match tags::read_limit(tags, kind) {
            TagValue::Limit(v) => out.push((kind, Some(v), Certainty::Known)),
            TagValue::BelowDefault if kind == RestrictionKind::MaxHeight => {
                out.push((kind, None, Certainty::Unknown));
            }
            TagValue::Invalid => invalid += 1,
            _ => {}
        }
    }
    // A height bar without its figure is still a height bar.
    if is_node
        && tags.get("barrier").map(String::as_str) == Some("height_restrictor")
        && !out.iter().any(|(k, _, _)| *k == RestrictionKind::MaxHeight)
    {
        out.push((RestrictionKind::MaxHeight, None, Certainty::Unknown));
    }
    let no = |key: &str| tags.get(key).map(String::as_str) == Some("no");
    if no("motorhome") {
        out.push((RestrictionKind::MotorhomeBan, None, Certainty::Known));
    }
    if no("trailer") {
        out.push((RestrictionKind::TrailerBan, None, Certainty::Known));
    }
    if no("caravan") {
        out.push((RestrictionKind::CaravanBan, None, Certainty::Known));
    }
    (out, invalid)
}

/// What a way or node is, for a warning's wording.
fn feature_of(tags: &BTreeMap<String, String>, is_node: bool, length_m: f64) -> RestrictionFeature {
    let get = |k: &str| tags.get(k).map(String::as_str);
    if is_node {
        return if get("barrier").is_some() {
            RestrictionFeature::Barrier
        } else {
            RestrictionFeature::Road
        };
    }
    match (get("tunnel"), get("covered"), get("bridge")) {
        (Some("building_passage"), _, _) => RestrictionFeature::BuildingPassage,
        (Some(t), _, _) if t != "no" => {
            if length_m >= TUNNEL_FROM_M {
                RestrictionFeature::Tunnel
            } else {
                RestrictionFeature::Underpass
            }
        }
        (_, Some(c), _) if c != "no" => RestrictionFeature::Underpass,
        (_, _, Some(b)) if b != "no" => RestrictionFeature::Bridge,
        _ => RestrictionFeature::Road,
    }
}

fn line_length(points: &[Position]) -> f64 {
    points.windows(2).map(|w| w[0].distance_m(w[1])).sum()
}

#[allow(
    clippy::cast_possible_truncation,
    reason = "a cell index of a valid coordinate is far inside i32"
)]
fn cell(lat: f64, lon: f64) -> (i32, i32) {
    (
        (lat / CELL_DEG).floor() as i32,
        (lon / CELL_DEG).floor() as i32,
    )
}

/// IGN's sections, cut into segments and indexed by grid cell, to find
/// the nodes near one.
#[derive(Default)]
struct IgnIndex {
    segments: Vec<(Position, Position)>,
    cells: HashMap<(i32, i32), Vec<u32>>,
}

impl IgnIndex {
    fn new(sections: &[IgnSection]) -> Self {
        let mut index = Self::default();
        for s in sections {
            for w in s.geometry.windows(2) {
                let (a, b) = (w[0], w[1]);
                let Ok(n) = u32::try_from(index.segments.len()) else {
                    return index;
                };
                index.segments.push((a, b));
                let span = (b.lat() - a.lat()).abs().max((b.lon() - a.lon()).abs());
                #[allow(
                    clippy::cast_possible_truncation,
                    clippy::cast_sign_loss,
                    reason = "a positive count of steps along one segment"
                )]
                let steps = (span / (CELL_DEG / 2.0)).ceil() as u32 + 1;
                let mut last = None;
                for k in 0..=steps {
                    let t = f64::from(k) / f64::from(steps);
                    let c = cell(
                        a.lat() + (b.lat() - a.lat()) * t,
                        a.lon() + (b.lon() - a.lon()) * t,
                    );
                    if last != Some(c) {
                        let list = index.cells.entry(c).or_default();
                        if list.last() != Some(&n) {
                            list.push(n);
                        }
                        last = Some(c);
                    }
                }
            }
        }
        index
    }

    /// Whether `p` lies within [`IGN_MATCH_M`] of a section. A cell is
    /// wider than that distance, so the segments of the point's cell and of
    /// its eight neighbours are all that can be that close.
    fn near(&self, p: Position) -> bool {
        let (r, c) = cell(p.lat(), p.lon());
        let k = lunaway_domain::geo::EARTH_RADIUS_M.to_radians();
        let cos = p.lat().to_radians().cos();
        for dr in -1..=1 {
            for dc in -1..=1 {
                let Some(list) = self.cells.get(&(r + dr, c + dc)) else {
                    continue;
                };
                for &i in list {
                    let (a, b) = self.segments[i as usize];
                    let (ax, ay) = ((a.lon() - p.lon()) * k * cos, (a.lat() - p.lat()) * k);
                    let (bx, by) = ((b.lon() - p.lon()) * k * cos, (b.lat() - p.lat()) * k);
                    let (dx, dy) = (bx - ax, by - ay);
                    let len2 = dx * dx + dy * dy;
                    let t = if len2 > 0.0 {
                        (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0)
                    } else {
                        0.0
                    };
                    let (qx, qy) = (ax + t * dx, ay + t * dy);
                    if qx * qx + qy * qy <= IGN_MATCH_M * IGN_MATCH_M {
                        return true;
                    }
                }
            }
        }
        false
    }
}

fn timestamp_of(millis: Option<i64>) -> DateTime<Utc> {
    millis
        .and_then(|m| Utc.timestamp_millis_opt(m).single())
        .unwrap_or(DateTime::UNIX_EPOCH)
}

/// The extract's replication timestamp, from its header block.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file cannot be read.
pub fn data_date(path: &Path) -> Result<Option<DateTime<Utc>>, IngestError> {
    let pbf = |source| IngestError::Pbf {
        path: path.to_owned(),
        source,
    };
    let reader = BlobReader::from_path(path).map_err(pbf)?;
    for blob in reader {
        let blob = blob.map_err(pbf)?;
        if let BlobDecode::OsmHeader(header) = blob.decode().map_err(pbf)? {
            return Ok(header
                .osmosis_replication_timestamp()
                .and_then(|s| Utc.timestamp_opt(s, 0).single()));
        }
    }
    Ok(None)
}

#[derive(Default)]
struct NodePass {
    /// Restricted nodes: id, position, tags.
    restricted: Vec<(i64, Position, BTreeMap<String, String>)>,
    /// Nodes whose access the change file rewrites.
    rewrites: Vec<Rewrite>,
    /// The nodes near an IGN section.
    near_ign: HashSet<i64>,
}

impl NodePass {
    fn merge(mut self, other: Self) -> Self {
        self.restricted.extend(other.restricted);
        self.rewrites.extend(other.rewrites);
        self.near_ign.extend(other.near_ign);
        self
    }
}

struct KeptWay {
    id: i64,
    version: i32,
    timestamp: DateTime<Utc>,
    refs: Vec<i64>,
    tags: BTreeMap<String, String>,
    /// The restrictions its tags carry.
    restrictions: Vec<(RestrictionKind, Option<f64>, Certainty)>,
    /// Whether an IGN section may describe it.
    ign_candidate: bool,
}

#[derive(Default)]
struct WayPass {
    kept: Vec<KeptWay>,
    routable: usize,
    invalid: usize,
}

impl WayPass {
    fn merge(mut self, other: Self) -> Self {
        self.kept.extend(other.kept);
        self.routable += other.routable;
        self.invalid += other.invalid;
        self
    }
}

fn node_element(
    id: i64,
    lat: f64,
    lon: f64,
    tags: BTreeMap<String, String>,
    version: i32,
    millis: Option<i64>,
    ign: &IgnIndex,
) -> NodePass {
    let mut out = NodePass::default();
    let Ok(at) = Position::new(lat, lon) else {
        return out;
    };
    if ign.near(at) {
        out.near_ign.insert(id);
    }
    if tags.is_empty() {
        return out;
    }
    let mut fixes = tags::graph_fixes(&tags, &BTreeMap::new());
    // Valhalla reads no limit on a node; only the access matters there.
    fixes.retain(|k, _| k == "motorcar");
    if !fixes.is_empty() {
        let mut new_tags = tags.clone();
        new_tags.extend(fixes);
        out.rewrites.push(Rewrite {
            id,
            version: version.max(0) + 1,
            timestamp: timestamp_of(millis) + chrono::Duration::seconds(1),
            shape: RewriteShape::Node(at),
            tags: new_tags,
        });
    }
    if !restrictions_of(&tags, true).0.is_empty() {
        out.restricted.push((id, at, tags));
    }
    out
}

fn pbf_error(path: &Path) -> impl Fn(osmpbf::Error) -> IngestError + '_ {
    move |source| IngestError::Pbf {
        path: path.to_owned(),
        source,
    }
}

/// Reads the extract at `path` and IGN's `sections` into the change file's
/// content and the restriction records. CPU-bound and blocking: run it on a
/// blocking thread. `osm_data_at` dates the OpenStreetMap records (the
/// extract's own date), `ign_fetched_at` the IGN sections IGN gives no
/// change date for.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file is not a readable PBF.
#[allow(
    clippy::too_many_lines,
    reason = "three passes over one file, each short; split, they would share half their state"
)]
pub fn prepare(
    path: &Path,
    sections: &[IgnSection],
    osm_data_at: DateTime<Utc>,
    ign_fetched_at: DateTime<Utc>,
) -> Result<Prepared, IngestError> {
    let mut report = PrepareReport {
        osm_data_at: Some(osm_data_at),
        ign_sections: sections.len(),
        ..PrepareReport::default()
    };
    let observed = osm_data_at;
    let ign = IgnIndex::new(sections);
    let err = pbf_error(path);

    // Pass 1: nodes.
    let nodes = ElementReader::from_path(path)
        .map_err(&err)?
        .par_map_reduce(
            |element| match element {
                PbfElement::Node(n) => node_element(
                    n.id(),
                    n.lat(),
                    n.lon(),
                    tag_map(n.tags()),
                    n.info().version().unwrap_or(0),
                    n.info().milli_timestamp(),
                    &ign,
                ),
                PbfElement::DenseNode(n) => node_element(
                    n.id(),
                    n.lat(),
                    n.lon(),
                    tag_map(n.tags()),
                    n.info().map_or(0, osmpbf::DenseNodeInfo::version),
                    n.info().map(osmpbf::DenseNodeInfo::milli_timestamp),
                    &ign,
                ),
                _ => NodePass::default(),
            },
            NodePass::default,
            NodePass::merge,
        )
        .map_err(&err)?;
    tracing::info!(
        restricted = nodes.restricted.len(),
        near_ign = nodes.near_ign.len(),
        "nodes read"
    );

    // Pass 2: routable ways.
    let near_ign = &nodes.near_ign;
    let ways = ElementReader::from_path(path)
        .map_err(&err)?
        .par_map_reduce(
            |element| {
                let mut out = WayPass::default();
                let PbfElement::Way(w) = element else {
                    return out;
                };
                // Most ways are not roads: test before copying the tags.
                if !w
                    .tags()
                    .any(|(k, v)| k == "highway" && ROUTABLE.contains(&v))
                {
                    return out;
                }
                let tags = tag_map(w.tags());
                if !is_routable(&tags) {
                    return out;
                }
                out.routable = 1;
                let (restrictions, invalid) = restrictions_of(&tags, false);
                out.invalid = invalid;
                let refs: Vec<i64> = w.refs().collect();
                let ign_candidate = refs.iter().filter(|r| near_ign.contains(r)).count() >= 2;
                let fixes = !tags::graph_fixes(&tags, &BTreeMap::new()).is_empty();
                if !restrictions.is_empty() || ign_candidate || fixes {
                    out.kept.push(KeptWay {
                        id: w.id(),
                        version: w.info().version().unwrap_or(0),
                        timestamp: timestamp_of(w.info().milli_timestamp()),
                        refs,
                        tags,
                        restrictions,
                        ign_candidate,
                    });
                }
                out
            },
            WayPass::default,
            WayPass::merge,
        )
        .map_err(&err)?;
    report.routable_ways = ways.routable;
    report.invalid_values = ways.invalid;
    tracing::info!(
        routable = ways.routable,
        kept = ways.kept.len(),
        "ways read"
    );

    // Pass 3: the coordinates of the kept ways.
    let wanted: HashSet<i64> = ways
        .kept
        .iter()
        .flat_map(|w| w.refs.iter().copied())
        .collect();
    let coords: HashMap<i64, Position> = ElementReader::from_path(path)
        .map_err(&err)?
        .par_map_reduce(
            |element| {
                let mut out = HashMap::new();
                let (id, lat, lon) = match element {
                    PbfElement::Node(n) => (n.id(), n.lat(), n.lon()),
                    PbfElement::DenseNode(n) => (n.id(), n.lat(), n.lon()),
                    _ => return out,
                };
                if wanted.contains(&id)
                    && let Ok(p) = Position::new(lat, lon)
                {
                    out.insert(id, p);
                }
                out
            },
            HashMap::new,
            |mut a, b| {
                a.extend(b);
                a
            },
        )
        .map_err(&err)?;

    let geometry = |w: &KeptWay| -> Vec<Position> {
        w.refs
            .iter()
            .filter_map(|r| coords.get(r).copied())
            .collect()
    };

    // IGN sections onto the candidate ways.
    let candidates: Vec<(usize, RouteLine)> = ways
        .kept
        .iter()
        .enumerate()
        .filter(|(_, w)| w.ign_candidate)
        .filter_map(|(i, w)| RouteLine::new(geometry(w)).map(|l| (i, l)))
        .collect();
    let mut by_cell: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
    for (k, (_, line)) in candidates.iter().enumerate() {
        let mut seen = HashSet::new();
        for p in line.points() {
            let c = cell(p.lat(), p.lon());
            if seen.insert(c) {
                by_cell.entry(c).or_default().push(k);
            }
        }
    }
    // Per kept way, the lowest IGN figure of each kind and the section it
    // came from; per section, the OpenStreetMap figure it disagrees with.
    let mut extra: HashMap<usize, BTreeMap<RestrictionKind, (f64, usize)>> = HashMap::new();
    let mut section_matched = vec![false; sections.len()];
    for (si, s) in sections.iter().enumerate() {
        let mut near: HashSet<usize> = HashSet::new();
        for p in &s.geometry {
            let (r, c) = cell(p.lat(), p.lon());
            for dr in -1..=1 {
                for dc in -1..=1 {
                    if let Some(list) = by_cell.get(&(r + dr, c + dc)) {
                        near.extend(list.iter().copied());
                    }
                }
            }
        }
        // Both ways round: the section along a longer way, or a shorter way
        // (a porch, the stretch under a bridge) along the section. A road
        // that only crosses the section matches neither.
        let section_line = RouteLine::new(s.geometry.clone());
        for k in near {
            let (wi, line) = &candidates[k];
            let along_way = !match_route(line, &s.geometry, IGN_MATCH_M).is_empty();
            let along_section = !along_way
                && section_line
                    .as_ref()
                    .is_some_and(|sl| !match_route(sl, line.points(), IGN_MATCH_M).is_empty());
            if !along_way && !along_section {
                continue;
            }
            section_matched[si] = true;
            let limits = extra.entry(*wi).or_default();
            for (kind, value) in ign_limits(s) {
                let e = limits.entry(kind).or_insert((value, si));
                if value < e.0 {
                    *e = (value, si);
                }
            }
        }
    }
    report.ign_matched = section_matched.iter().filter(|m| **m).count();

    // Disputes, both ways: (section, kind) -> the OpenStreetMap figure, and
    // (way index, kind) -> the IGN figure.
    let mut ign_disputes: HashMap<(usize, RestrictionKind), f64> = HashMap::new();
    let mut osm_disputes: HashMap<(usize, RestrictionKind), f64> = HashMap::new();
    let mut records = Vec::new();
    let mut rewrites = nodes.rewrites;
    report.fixed_nodes = rewrites.len();
    report.motorhome_access_copied = rewrites.len();

    for (wi, w) in ways.kept.iter().enumerate() {
        let ign: BTreeMap<RestrictionKind, f64> = extra
            .get(&wi)
            .map(|m| m.iter().map(|(k, (v, _))| (*k, *v)).collect())
            .unwrap_or_default();
        for (kind, (value, si)) in extra.get(&wi).into_iter().flatten() {
            let osm = tags::read_limit(&w.tags, *kind);
            if let Some(m) = tags::merge(*kind, osm, Some(*value))
                && m.disputed
                && let Some(o) = osm.limit()
            {
                ign_disputes.entry((*si, *kind)).or_insert(o);
                osm_disputes.insert((wi, *kind), *value);
            }
        }
        let fixes = tags::graph_fixes(&w.tags, &ign);
        if !fixes.is_empty() {
            if fixes.contains_key("maxweight") && w.tags.contains_key("maxweightrating") {
                report.weight_rating_copied += 1;
            }
            if fixes.contains_key("motorcar") {
                report.motorhome_access_copied += 1;
            }
            let applied_ign = ign.iter().any(|(kind, v)| {
                fixes.get(kind.graph_key()).map(String::as_str)
                    == Some(tags::canonical(*v).as_str())
            });
            if applied_ign {
                report.ign_applied += 1;
            }
            let mut new_tags = w.tags.clone();
            new_tags.extend(fixes);
            rewrites.push(Rewrite {
                id: w.id,
                version: w.version.max(0) + 1,
                timestamp: w.timestamp + chrono::Duration::seconds(1),
                shape: RewriteShape::Way(w.refs.clone()),
                tags: new_tags,
            });
        }
        if w.restrictions.is_empty() {
            continue;
        }
        let points = geometry(w);
        if points.len() < 2 {
            continue;
        }
        report.restricted_ways += 1;
        let feature = feature_of(&w.tags, false, line_length(&points));
        let shape = polyline::encode(&points);
        for (kind, limit, certainty) in &w.restrictions {
            let dispute = osm_disputes.get(&(wi, *kind)).copied();
            records.push(RestrictionRecord {
                source: RestrictionSource::Osm,
                external_id: format!("way/{}", w.id),
                kind: *kind,
                limit: *limit,
                certainty: if dispute.is_some() {
                    Certainty::Disputed
                } else {
                    *certainty
                },
                feature,
                name: name_of(&w.tags),
                other_value: dispute,
                other_source: dispute.map(|_| RestrictionSource::Ign),
                shape: shape.clone(),
                observed_at: observed,
            });
        }
    }
    report.fixed_ways = rewrites.len() - report.fixed_nodes;

    for (id, at, tags) in &nodes.restricted {
        report.restricted_nodes += 1;
        let shape = polyline::encode(&[*at]);
        for (kind, limit, certainty) in restrictions_of(tags, true).0 {
            records.push(RestrictionRecord {
                source: RestrictionSource::Osm,
                external_id: format!("node/{id}"),
                kind,
                limit,
                certainty,
                feature: feature_of(tags, true, 0.0),
                name: name_of(tags),
                other_value: None,
                other_source: None,
                shape: shape.clone(),
                observed_at: observed,
            });
        }
    }

    for (si, s) in sections.iter().enumerate() {
        let length = line_length(&s.geometry);
        let feature = match s.ground {
            Some(g) if g < 0 => {
                if length >= TUNNEL_FROM_M {
                    RestrictionFeature::Tunnel
                } else {
                    RestrictionFeature::Underpass
                }
            }
            Some(g) if g > 0 => RestrictionFeature::Bridge,
            _ => RestrictionFeature::Road,
        };
        let shape = polyline::encode(&s.geometry);
        for (kind, value) in ign_limits(s) {
            let dispute = ign_disputes.get(&(si, kind)).copied();
            records.push(RestrictionRecord {
                source: RestrictionSource::Ign,
                external_id: format!("ign/{}", s.id),
                kind,
                limit: Some(value),
                certainty: if dispute.is_some() {
                    Certainty::Disputed
                } else {
                    Certainty::Known
                },
                feature,
                name: s.name.clone(),
                other_value: dispute,
                other_source: dispute.map(|_| RestrictionSource::Osm),
                shape: shape.clone(),
                observed_at: s.modified_at.unwrap_or(ign_fetched_at),
            });
        }
    }
    report.disputed = records
        .iter()
        .filter(|r| r.certainty == Certainty::Disputed)
        .count();
    report.records = records.len();
    rewrites.sort_by_key(|r| (matches!(r.shape, RewriteShape::Way(_)), r.id));
    Ok(Prepared {
        records,
        rewrites,
        report,
    })
}

/// The limits of an IGN section, plausible ones only.
fn ign_limits(s: &IgnSection) -> Vec<(RestrictionKind, f64)> {
    [
        (
            RestrictionKind::MaxHeight,
            s.height_m,
            &tags::PLAUSIBLE_LENGTH_M,
        ),
        (
            RestrictionKind::MaxWidth,
            s.width_m,
            &tags::PLAUSIBLE_LENGTH_M,
        ),
        (
            RestrictionKind::MaxLength,
            s.length_m,
            &tags::PLAUSIBLE_VEHICLE_LENGTH_M,
        ),
        (
            RestrictionKind::MaxWeight,
            s.weight_t,
            &tags::PLAUSIBLE_WEIGHT_T,
        ),
    ]
    .into_iter()
    .filter_map(|(k, v, range)| v.filter(|x| range.contains(x)).map(|x| (k, x)))
    .collect()
}

fn name_of(tags: &BTreeMap<String, String>) -> Option<String> {
    tags.get("name")
        .or_else(|| tags.get("ref"))
        .map(|n| n.trim().chars().take(200).collect::<String>())
        .filter(|n| !n.is_empty())
}

/// XML text of an attribute value.
fn xml_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            // Control characters are not allowed in XML 1.0.
            c if (c as u32) < 0x20 && !matches!(c, '\t' | '\n' | '\r') => out.push(' '),
            c => out.push(c),
        }
    }
    out
}

/// The change file: every rewritten node and way, whole (`osmium
/// apply-changes` replaces an object by the newer version), with a version
/// one above the extract's so the change wins.
fn osc(rewrites: &[Rewrite]) -> String {
    use std::fmt::Write as _;
    let mut out = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osmChange version=\"0.6\" generator=\"lunaway routing prepare\">\n<modify>\n",
    );
    for r in rewrites {
        let ts = r.timestamp.format("%Y-%m-%dT%H:%M:%SZ");
        match &r.shape {
            RewriteShape::Node(p) => {
                let _ = writeln!(
                    out,
                    "<node id=\"{}\" version=\"{}\" timestamp=\"{ts}\" lat=\"{:.7}\" lon=\"{:.7}\">",
                    r.id,
                    r.version,
                    p.lat(),
                    p.lon()
                );
            }
            RewriteShape::Way(refs) => {
                let _ = writeln!(
                    out,
                    "<way id=\"{}\" version=\"{}\" timestamp=\"{ts}\">",
                    r.id, r.version
                );
                for n in refs {
                    let _ = writeln!(out, "<nd ref=\"{n}\"/>");
                }
            }
        }
        for (k, v) in &r.tags {
            let _ = writeln!(
                out,
                "<tag k=\"{}\" v=\"{}\"/>",
                xml_escape(k),
                xml_escape(v)
            );
        }
        out.push_str(match r.shape {
            RewriteShape::Node(_) => "</node>\n",
            RewriteShape::Way(_) => "</way>\n",
        });
    }
    out.push_str("</modify>\n</osmChange>\n");
    out
}

fn write_gz(path: &Path, bytes: &[u8]) -> Result<(), IngestError> {
    let io = |source| IngestError::Cache {
        path: path.to_owned(),
        source,
    };
    let file = std::fs::File::create(path).map_err(io)?;
    let mut gz = flate2::write::GzEncoder::new(
        std::io::BufWriter::new(file),
        flate2::Compression::default(),
    );
    gz.write_all(bytes).map_err(io)?;
    gz.finish().map_err(io)?.flush().map_err(io)
}

/// Writes `fixes.osc.gz`, `restrictions.ndjson.gz` and `prepare.json` into
/// `dir`, which must exist.
///
/// # Errors
///
/// [`IngestError::Cache`] when a file cannot be written,
/// [`IngestError::Json`] when a record does not serialise.
pub fn write(prepared: &Prepared, dir: &Path) -> Result<(), IngestError> {
    write_gz(
        &dir.join("fixes.osc.gz"),
        osc(&prepared.rewrites).as_bytes(),
    )?;
    let json = |source| IngestError::Json {
        what: "restriction record".into(),
        source,
    };
    let mut lines = Vec::with_capacity(prepared.records.len() * 160);
    for r in &prepared.records {
        serde_json::to_writer(&mut lines, r).map_err(json)?;
        lines.push(b'\n');
    }
    write_gz(&dir.join("restrictions.ndjson.gz"), &lines)?;
    let report = serde_json::to_vec_pretty(&prepared.report).map_err(json)?;
    let path = dir.join("prepare.json");
    std::fs::write(&path, report).map_err(|source| IngestError::Cache { path, source })
}

/// Reads a `restrictions.ndjson.gz` back, checking each record: a line that
/// does not parse or does not hold together stops the load, naming it.
///
/// # Errors
///
/// [`IngestError::Inflate`] or [`IngestError::Json`], or
/// [`IngestError::Incomplete`] for a refused record.
pub fn read_records(path: &Path) -> Result<Vec<(RestrictionRecord, Vec<Position>)>, IngestError> {
    use std::io::BufRead as _;
    let io = |source| IngestError::Inflate {
        what: path.display().to_string(),
        source,
    };
    let file = std::fs::File::open(path).map_err(io)?;
    let reader = std::io::BufReader::new(flate2::read::GzDecoder::new(file));
    let mut out = Vec::new();
    for (n, line) in reader.lines().enumerate() {
        let line = line.map_err(io)?;
        if line.trim().is_empty() {
            continue;
        }
        let record: RestrictionRecord =
            serde_json::from_str(&line).map_err(|source| IngestError::Json {
                what: format!("{} line {}", path.display(), n + 1),
                source,
            })?;
        if record.source == RestrictionSource::Community {
            return Err(IngestError::Implausible {
                what: format!("line {}: a graph bundle carries no community report", n + 1),
            });
        }
        let points = record
            .check()
            .map_err(|source| IngestError::InvalidRecord {
                line: n + 1,
                source,
            })?;
        out.push((record, points));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn a_height_bar_without_its_figure_is_an_unknown_clearance() {
        let (r, _) = restrictions_of(&tags(&[("barrier", "height_restrictor")]), true);
        assert_eq!(
            r,
            vec![(RestrictionKind::MaxHeight, None, Certainty::Unknown)]
        );
        let (r, _) = restrictions_of(
            &tags(&[("barrier", "height_restrictor"), ("maxheight", "1.9")]),
            true,
        );
        assert_eq!(
            r,
            vec![(RestrictionKind::MaxHeight, Some(1.9), Certainty::Known)]
        );
    }

    #[test]
    fn hgv_and_goods_bans_are_not_restrictions_for_a_motorhome() {
        let (r, invalid) = restrictions_of(
            &tags(&[
                ("highway", "residential"),
                ("hgv", "no"),
                ("goods", "no"),
                ("maxheight", "default"),
            ]),
            false,
        );
        assert!(r.is_empty(), "{r:?}");
        assert_eq!(invalid, 0);
        let (r, invalid) = restrictions_of(
            &tags(&[
                ("motorhome", "no"),
                ("caravan", "no"),
                ("maxweight", "120"),
                ("maxweightrating", "3,5"),
            ]),
            false,
        );
        assert_eq!(invalid, 0, "120 is dropped, but 3,5 gives the figure");
        assert!(r.contains(&(RestrictionKind::MaxWeight, Some(3.5), Certainty::Known)));
        assert!(r.contains(&(RestrictionKind::MotorhomeBan, None, Certainty::Known)));
        assert!(r.contains(&(RestrictionKind::CaravanBan, None, Certainty::Known)));
    }

    #[test]
    fn the_wording_follows_the_structure() {
        let f = |pairs: &[(&str, &str)], len| feature_of(&tags(pairs), false, len);
        assert_eq!(f(&[("tunnel", "yes")], 30.0), RestrictionFeature::Underpass);
        assert_eq!(f(&[("tunnel", "yes")], 400.0), RestrictionFeature::Tunnel);
        assert_eq!(
            f(&[("tunnel", "building_passage")], 12.0),
            RestrictionFeature::BuildingPassage
        );
        assert_eq!(f(&[("bridge", "yes")], 50.0), RestrictionFeature::Bridge);
        assert_eq!(f(&[], 50.0), RestrictionFeature::Road);
        assert_eq!(
            feature_of(&tags(&[("barrier", "gate")]), true, 0.0),
            RestrictionFeature::Barrier
        );
    }

    #[test]
    fn the_change_file_escapes_values_and_bumps_versions() {
        let rewrite = Rewrite {
            id: 42,
            version: 3,
            timestamp: Utc.with_ymd_and_hms(2026, 10, 5, 20, 0, 1).unwrap(),
            shape: RewriteShape::Way(vec![1, 2]),
            tags: tags(&[("name", "Rue \"A\" & <B>"), ("maxweight", "3.5")]),
        };
        let text = osc(&[rewrite]);
        assert!(text.contains(r#"<way id="42" version="3" timestamp="2026-10-05T20:00:01Z">"#));
        assert!(text.contains(r#"<tag k="name" v="Rue &quot;A&quot; &amp; &lt;B&gt;"/>"#));
        assert!(text.contains("<nd ref=\"1\"/>\n<nd ref=\"2\"/>"));
    }
}
