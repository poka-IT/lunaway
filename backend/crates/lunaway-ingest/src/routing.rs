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
//!   winning (`lunaway_domain::routing::tags`), and the limits mapped on a
//!   node carried by a short stretch of each way through it
//!   ([`crate::node_limits`]);
//! - `restrictions.ndjson.gz`, one [`RestrictionRecord`] per line: every
//!   physical limit and motorhome or trailer ban on a road or a node, from
//!   OpenStreetMap and IGN, with its geometry, for the check after each
//!   route (`lunaway routing load`).
//!
//! The extract is read in three parallel passes, as the place import does
//! (`osm_extract`): the nodes (restricted ones, and those near an IGN
//! section), the ways, then the coordinates of the ways kept; and a fourth
//! over the blocks of relations, for those that name a way cut around a
//! node's limit.

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
use osmpbf::{
    BlobDecode, BlobReader, ByteOffset, Element as PbfElement, ElementReader, RelMemberType,
};
use serde::Serialize;

use crate::{
    IngestError,
    ign::IgnSection,
    local_access,
    node_limits::{self, Limits, Vertex},
};

/// The values of `highway` a motor vehicle may drive on.
pub(crate) const ROUTABLE: [&str; 18] = [
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
    /// Nodes whose limits the graph carries on a stretch of each way
    /// through them ([`node_limits`]).
    pub node_limits_carried: usize,
    /// Ways that carry such a stretch: cut around the node, or given its
    /// limit whole when shorter than the stretch.
    pub node_limit_ways: usize,
    /// Pieces of those ways the change file creates, beside the first,
    /// which keeps the way's id.
    pub node_limit_ways_created: usize,
    /// Cut points the change file creates.
    pub node_limit_nodes_created: usize,
    /// Relations rewritten to name the pieces of a cut way.
    pub node_limit_relations: usize,
    /// Ways through such a node left whole, the limit left to the check: a
    /// ring closed at the node, a turn its pieces could not follow, a
    /// relation not read whole.
    pub node_limit_ways_left_whole: usize,
    /// Ways the change file rewrites for their tags, before the cuts around
    /// the limits of nodes ([`Self::node_limit_ways`]).
    pub fixed_ways: usize,
    /// Nodes the change file rewrites.
    pub fixed_nodes: usize,
    /// Ways whose `maxweight` comes from `maxweightrating`.
    pub weight_rating_copied: usize,
    /// Ways and nodes whose `motorhome` access was copied to `motorcar`.
    pub motorhome_access_copied: usize,
    /// Ways and motorway junctions whose junction reference holds something
    /// other than an exit number (a road's number, `A 411` at the
    /// Thônex-Vallard customs), left out of what Valhalla writes on a
    /// ramp's sign ([`tags::exit_number_fixes`]).
    pub exit_refs_dropped: usize,
    /// Limits whose exception for local access ("sauf desserte") the
    /// change file writes in the form Valhalla reads.
    pub local_access_written: usize,
    /// Exceptions Valhalla would read that a motorhome may not use ("sauf
    /// livraisons", or one on a clearance), removed.
    pub local_access_removed: usize,
    /// IGN sections whose weight limit is set aside: on a motorway or a
    /// ramp, or on a lane closed to the public.
    pub ign_weight_set_aside: usize,
    /// Areas enclosed behind a "sauf desserte" zone given its limit and
    /// plate ([`local_access`]).
    pub local_access_areas: usize,
    /// Roads of those areas the change file marks.
    pub local_access_extended: usize,
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

/// A node, way or relation to rewrite or create, as the change file needs
/// it.
#[derive(Debug, Clone, PartialEq)]
struct Rewrite {
    id: i64,
    version: i32,
    timestamp: DateTime<Utc>,
    /// Whether the extract lacks it: a piece of a cut way, a cut point.
    create: bool,
    /// The node's position, the way's node list or the relation's members.
    shape: RewriteShape,
    tags: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq)]
enum RewriteShape {
    Node(Position),
    Way(Vec<i64>),
    Relation(Vec<node_limits::Member>),
}

impl RewriteShape {
    /// The change file's order: nodes, then ways, then relations.
    const fn rank(&self) -> u8 {
        match self {
            Self::Node(_) => 0,
            Self::Way(_) => 1,
            Self::Relation(_) => 2,
        }
    }
}

/// The outputs of a preparation, before they are written.
#[derive(Debug, Clone, Default)]
pub struct Prepared {
    /// The restrictions.
    pub records: Vec<RestrictionRecord>,
    rewrites: Vec<Rewrite>,
    /// What was done.
    pub report: PrepareReport,
    /// The ways cut in pieces around a node's limit, in order: a route on
    /// one of their later pieces names the piece's new id, never the way's,
    /// so a route test that names one of them proves nothing
    /// (`cut-ways.txt`, which `infra/routing/build-graph.sh` checks the
    /// test cases against).
    pub cut_ways: Vec<i64>,
}

fn tag_map<'a>(tags: impl Iterator<Item = (&'a str, &'a str)>) -> BTreeMap<String, String> {
    tags.map(|(k, v)| (k.to_owned(), v.to_owned())).collect()
}

pub(crate) fn is_routable(tags: &BTreeMap<String, String>) -> bool {
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
    /// The highest node id: the cut points take the ids above it.
    max_id: i64,
    /// Nodes whose `motorhome` access the change file copies to `motorcar`.
    motorcar_copied: usize,
    /// Motorway junctions whose `ref` the change file leaves out, no exit
    /// number ([`tags::exit_number_fixes`]).
    exit_refs_dropped: usize,
}

impl NodePass {
    fn merge(mut self, other: Self) -> Self {
        self.restricted.extend(other.restricted);
        self.rewrites.extend(other.rewrites);
        self.near_ign.extend(other.near_ign);
        self.max_id = self.max_id.max(other.max_id);
        self.motorcar_copied += other.motorcar_copied;
        self.exit_refs_dropped += other.exit_refs_dropped;
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
    /// The highest way id: the pieces of cut ways take the ids above it.
    max_id: i64,
}

impl WayPass {
    fn merge(mut self, other: Self) -> Self {
        self.kept.extend(other.kept);
        self.routable += other.routable;
        self.invalid += other.invalid;
        self.max_id = self.max_id.max(other.max_id);
        self
    }
}

/// Reads one way of pass 2 into `out`: kept when it carries a restriction,
/// may match an IGN section, needs a fix, or goes through a node whose
/// limits the graph will carry.
fn way_element(
    w: &osmpbf::Way<'_>,
    near_ign: &HashSet<i64>,
    limited: &HashMap<i64, Limits>,
    out: &mut WayPass,
) {
    out.max_id = out.max_id.max(w.id());
    // Most ways are not roads: test before copying the tags.
    if !w
        .tags()
        .any(|(k, v)| k == "highway" && ROUTABLE.contains(&v))
    {
        return;
    }
    let tags = tag_map(w.tags());
    if !is_routable(&tags) {
        return;
    }
    out.routable += 1;
    let (restrictions, invalid) = restrictions_of(&tags, false);
    out.invalid += invalid;
    let refs: Vec<i64> = w.refs().collect();
    let ign_candidate = refs.iter().filter(|r| near_ign.contains(r)).count() >= 2;
    let fixes = !tags::graph_fixes(&tags, &BTreeMap::new()).is_empty();
    let through_limit = refs.iter().any(|r| limited.contains_key(r));
    if !restrictions.is_empty() || ign_candidate || fixes || through_limit {
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
    let mut out = NodePass {
        max_id: id,
        ..NodePass::default()
    };
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
    // Valhalla reads no limit on a node; only the access matters there, and
    // the exit number of a motorway junction.
    let exits = tags::exit_number_fixes(&tags);
    fixes.retain(|k, _| k == "motorcar" || exits.contains_key(k));
    if fixes.contains_key("motorcar") {
        out.motorcar_copied += 1;
    }
    if !exits.is_empty() {
        out.exit_refs_dropped += 1;
    }
    if !fixes.is_empty() {
        let mut new_tags = tags.clone();
        tags::apply_fixes(&mut new_tags, fixes);
        out.rewrites.push(Rewrite {
            id,
            version: version.max(0) + 1,
            timestamp: timestamp_of(millis) + chrono::Duration::seconds(1),
            create: false,
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
    // The nodes whose limits the graph will carry on the ways through them.
    let limited: HashMap<i64, Limits> = nodes
        .restricted
        .iter()
        .map(|(id, _, tags)| (*id, node_limits::engine_limits(tags)))
        .filter(|(_, limits)| !limits.is_empty())
        .collect();
    tracing::info!(
        restricted = nodes.restricted.len(),
        limited = limited.len(),
        near_ign = nodes.near_ign.len(),
        "nodes read"
    );

    // Pass 2: routable ways. The blocks that hold ways are remembered for
    // the search behind the "sauf desserte" zones, those that hold
    // relations for the relations of the ways cut around a node.
    let near_ign = &nodes.near_ign;
    let (ways, blocks) = local_access::par_blocks(
        path,
        None,
        WayPass::default,
        |block| {
            let mut out = WayPass::default();
            for group in block.groups() {
                for w in group.ways() {
                    way_element(&w, near_ign, &limited, &mut out);
                }
            }
            out
        },
        WayPass::merge,
    )?;
    report.routable_ways = ways.routable;
    report.invalid_values = ways.invalid;
    tracing::info!(
        routable = ways.routable,
        kept = ways.kept.len(),
        "ways read"
    );

    // The roads behind the "sauf desserte" zones, by passes over the ways.
    let seeds: Vec<(RestrictionKind, i64, Vec<i64>)> = ways
        .kept
        .iter()
        .flat_map(|w| {
            RestrictionKind::LIMITS
                .into_iter()
                .filter(|k| tags::limit_spares_local_access(&w.tags, *k))
                .map(|k| (k, w.id, w.refs.clone()))
        })
        .collect();
    let enclosed = if seeds.is_empty() {
        Vec::new()
    } else {
        local_access::search(path, &blocks.ways, &seeds)?
    };

    // Pass 3: the coordinates of the kept ways and of the enclosed roads.
    let wanted: HashSet<i64> = ways
        .kept
        .iter()
        .flat_map(|w| w.refs.iter().copied())
        .chain(enclosed.iter().flat_map(local_access::Enclosed::nodes))
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
    // Per section, the kept ways it matched.
    let mut section_ways: Vec<Vec<usize>> = vec![Vec::new(); sections.len()];
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
            section_ways[si].push(*wi);
            let limits = extra.entry(*wi).or_default();
            for (kind, value) in ign_limits(s) {
                let e = limits.entry(kind).or_insert((value, si));
                if value < e.0 {
                    *e = (value, si);
                }
            }
        }
    }
    report.ign_matched = section_ways.iter().filter(|w| !w.is_empty()).count();
    report.ign_weight_set_aside = sections
        .iter()
        .filter(|s| s.weight_t.is_some() && !s.weight_concerns_public_traffic())
        .count();

    // Disputes, both ways: (section, kind) -> the OpenStreetMap figure, and
    // (way index, kind) -> the IGN figure.
    let mut ign_disputes: HashMap<(usize, RestrictionKind), f64> = HashMap::new();
    let mut osm_disputes: HashMap<(usize, RestrictionKind), f64> = HashMap::new();
    let mut records = Vec::new();
    let mut rewrites = nodes.rewrites;
    report.fixed_nodes = rewrites.len();
    report.motorhome_access_copied = nodes.motorcar_copied;
    report.exit_refs_dropped = nodes.exit_refs_dropped;

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
            if fixes.keys().any(|k| k.starts_with("junction:ref")) {
                report.exit_refs_dropped += 1;
            }
            let applied_ign = ign.iter().any(|(kind, v)| {
                fixes.get(kind.graph_key()).and_then(Option::as_deref)
                    == Some(tags::canonical(*v).as_str())
            });
            if applied_ign {
                report.ign_applied += 1;
            }
            let conditionals = fixes
                .iter()
                .filter(|(key, _)| key.ends_with(":conditional"))
                .map(|(_, change)| change);
            for change in conditionals {
                match change {
                    Some(_) => report.local_access_written += 1,
                    None => report.local_access_removed += 1,
                }
            }
            let mut new_tags = w.tags.clone();
            tags::apply_fixes(&mut new_tags, fixes);
            rewrites.push(Rewrite {
                id: w.id,
                version: w.version.max(0) + 1,
                timestamp: w.timestamp + chrono::Duration::seconds(1),
                create: false,
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
                except_destination: tags::limit_spares_local_access(&w.tags, *kind),
                enclosed: false,
            });
        }
    }
    records.extend(extend_local_access(
        &enclosed,
        &ways.kept,
        &extra,
        &coords,
        &mut rewrites,
        &mut report,
        observed,
    ));
    report.fixed_ways = rewrites.len() - report.fixed_nodes;
    let cut_ways = carry_node_limits(
        path,
        &blocks.relations,
        &ways.kept,
        &coords,
        &limited,
        (nodes.max_id + 1, ways.max_id + 1),
        &mut rewrites,
        &mut report,
    )?;

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
                except_destination: tags::limit_spares_local_access(tags, kind),
                enclosed: false,
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
                except_destination: ign_spares_local_access(
                    kind,
                    value,
                    &section_ways[si],
                    &ways.kept,
                    &extra,
                ),
                enclosed: false,
            });
        }
    }
    report.disputed = records
        .iter()
        .filter(|r| r.certainty == Certainty::Disputed)
        .count();
    report.records = records.len();
    rewrites.sort_by_key(|r| (r.create, r.shape.rank(), r.id));
    Ok(Prepared {
        records,
        rewrites,
        report,
        cut_ways,
    })
}

/// Marks the roads enclosed behind each "sauf desserte" zone, within reach
/// of it, with the zone's limit and plate ([`local_access`]), and gives
/// their restriction records, flagged `enclosed`. The figure is the lowest
/// among the zone's ways at the gates that keep their plate once IGN is
/// read. Left as it is: a component on which IGN puts a limit of the kind
/// (that limit is its own), one a limit without the plate above that
/// figure also leads into (a vehicle between the two may come in that way
/// and pass through), and a road whose tags already carry an exception of
/// the kind (a time, a vehicle class), which the plate would replace.
fn extend_local_access(
    enclosed: &[local_access::Enclosed],
    kept: &[KeptWay],
    extra: &HashMap<usize, BTreeMap<RestrictionKind, (f64, usize)>>,
    coords: &HashMap<i64, Position>,
    rewrites: &mut Vec<Rewrite>,
    report: &mut PrepareReport,
    observed: DateTime<Utc>,
) -> Vec<RestrictionRecord> {
    let kept_index: HashMap<i64, usize> = kept.iter().enumerate().map(|(i, w)| (w.id, i)).collect();
    let mut by_node: HashMap<i64, Vec<usize>> = HashMap::new();
    for (wi, w) in kept.iter().enumerate() {
        for r in &w.refs {
            by_node.entry(*r).or_default().push(wi);
        }
    }
    let ign_lowest = |wi: usize, kind: RestrictionKind| {
        extra.get(&wi).and_then(|m| m.get(&kind)).map(|(v, _)| *v)
    };
    let mut by_way: HashMap<i64, usize> = rewrites
        .iter()
        .enumerate()
        .filter(|(_, r)| matches!(r.shape, RewriteShape::Way(_)))
        .map(|(i, r)| (r.id, i))
        .collect();
    let mut marked: HashSet<i64> = HashSet::new();
    let mut marks: HashMap<(i64, RestrictionKind), (&local_access::Road, f64)> = HashMap::new();
    for e in enclosed {
        if e.kind.conditional_keys().is_empty() {
            continue;
        }
        if e.ways.iter().any(|w| {
            kept_index
                .get(&w.id)
                .is_some_and(|wi| ign_lowest(*wi, e.kind).is_some())
        }) {
            continue;
        }
        // The zone's ways at the gates, with the figure the graph gives them.
        let mut at_gates: Vec<usize> = e
            .gates
            .iter()
            .flat_map(|g| by_node.get(g).into_iter().flatten().copied())
            .collect();
        at_gates.sort_unstable();
        at_gates.dedup();
        let value = at_gates
            .into_iter()
            .filter(|wi| {
                tags::spares_local_access_with(&kept[*wi].tags, e.kind, ign_lowest(*wi, e.kind))
            })
            .filter_map(|wi| {
                let osm = tags::read_limit(&kept[wi].tags, e.kind).limit()?;
                Some(ign_lowest(wi, e.kind).map_or(osm, |ign| osm.min(ign)))
            })
            .reduce(f64::min);
        let Some(value) = value else {
            continue;
        };
        if e.boundary_max.is_some_and(|b| b > value) {
            continue;
        }
        let reached: Vec<&local_access::Road> = e
            .within_reach(coords)
            .into_iter()
            .filter(|road| {
                !e.kind
                    .conditional_keys()
                    .iter()
                    .any(|k| road.tags.contains_key(*k))
            })
            .collect();
        if reached.is_empty() {
            continue;
        }
        report.local_access_areas += 1;
        for road in reached {
            // Two zones of different figures around one road: the lower.
            marks
                .entry((road.id, e.kind))
                .and_modify(|(_, v)| *v = v.min(value))
                .or_insert((road, value));
        }
    }
    let mut marks: Vec<_> = marks.into_iter().collect();
    marks.sort_unstable_by_key(|((id, kind), _)| (*id, *kind));
    let mut records = Vec::new();
    for ((_, kind), (road, value)) in marks {
        let Some(conditional) = kind.conditional_keys().first() else {
            continue;
        };
        if marked.insert(road.id) {
            report.local_access_extended += 1;
        }
        let i = *by_way.entry(road.id).or_insert_with(|| {
            rewrites.push(Rewrite {
                id: road.id,
                version: road.version.max(0) + 1,
                timestamp: road.timestamp + chrono::Duration::seconds(1),
                create: false,
                shape: RewriteShape::Way(road.refs.clone()),
                tags: road.tags.clone(),
            });
            rewrites.len() - 1
        });
        let tags = &mut rewrites[i].tags;
        tags.insert(kind.graph_key().to_owned(), tags::canonical(value));
        tags.insert((*conditional).to_owned(), tags::LOCAL_ACCESS.to_owned());
        let points: Vec<Position> = road
            .refs
            .iter()
            .filter_map(|r| coords.get(r).copied())
            .collect();
        if points.len() < 2 {
            continue;
        }
        records.push(RestrictionRecord {
            source: RestrictionSource::Osm,
            external_id: format!("way/{}", road.id),
            kind,
            limit: Some(value),
            certainty: Certainty::Known,
            feature: RestrictionFeature::Road,
            name: name_of(&road.tags),
            other_value: None,
            other_source: None,
            shape: polyline::encode(&points),
            observed_at: observed,
            except_destination: true,
            enclosed: true,
        });
    }
    records
}

/// The relations in the blocks at `blocks` that name one of `ways`.
fn read_relations(
    path: &Path,
    blocks: &[ByteOffset],
    ways: &HashSet<i64>,
) -> Result<Vec<node_limits::Relation>, IngestError> {
    let (mut found, _) = local_access::par_blocks(
        path,
        Some(blocks),
        Vec::new,
        |block| {
            let mut out = Vec::new();
            for group in block.groups() {
                for r in group.relations() {
                    if !r
                        .members()
                        .any(|m| m.member_type == RelMemberType::Way && ways.contains(&m.member_id))
                    {
                        continue;
                    }
                    let mut complete = true;
                    let members = r
                        .members()
                        .map(|m| node_limits::Member {
                            kind: match m.member_type {
                                RelMemberType::Node => node_limits::MemberKind::Node,
                                RelMemberType::Way => node_limits::MemberKind::Way,
                                RelMemberType::Relation => node_limits::MemberKind::Relation,
                            },
                            id: m.member_id,
                            role: m.role().map_or_else(
                                |_| {
                                    complete = false;
                                    String::new()
                                },
                                str::to_owned,
                            ),
                        })
                        .collect();
                    // The tag reader stops at a string it cannot read: a
                    // relation written back without the rest would lose it.
                    let tags = tag_map(r.tags());
                    let complete = complete && tags.len() == r.raw_tags().count();
                    out.push(node_limits::Relation {
                        id: r.id(),
                        version: r.info().version().unwrap_or(0),
                        timestamp: timestamp_of(r.info().milli_timestamp()),
                        tags,
                        members,
                        complete,
                    });
                }
            }
            out
        },
        |mut a, b| {
            a.extend(b);
            a
        },
    )?;
    found.sort_unstable_by_key(|r| r.id);
    Ok(found)
}

/// Carries the limits mapped on nodes onto the ways through them
/// ([`node_limits`]): each way cut around its limited nodes, its pieces in
/// the change file (the first, under the way's id, a modification of the
/// way; the others and the cut points created with the ids from
/// `next_ids`, nodes then ways), and each relation that names a cut way
/// rewritten to name its pieces. The pieces start from the way's tags as
/// the change file already rewrites them. A way shorter than the stretch
/// takes the limit whole, and keeps its nodes. Returns the ways cut in
/// pieces.
#[allow(
    clippy::too_many_arguments,
    reason = "the state of prepare it completes, passed as it stands"
)]
fn carry_node_limits(
    path: &Path,
    relation_blocks: &[ByteOffset],
    kept: &[KeptWay],
    coords: &HashMap<i64, Position>,
    limited: &HashMap<i64, Limits>,
    next_ids: (i64, i64),
    rewrites: &mut Vec<Rewrite>,
    report: &mut PrepareReport,
) -> Result<Vec<i64>, IngestError> {
    let (mut next_node, next_way) = next_ids;
    let mut whole: BTreeMap<i64, Vec<node_limits::Piece>> = BTreeMap::new();
    let mut splits: BTreeMap<i64, Vec<node_limits::Piece>> = BTreeMap::new();
    for w in kept
        .iter()
        .filter(|w| w.refs.iter().any(|r| limited.contains_key(r)))
    {
        match node_limits::cut(&w.refs, coords, limited) {
            Some(pieces) if pieces.len() == 1 => {
                whole.insert(w.id, pieces);
            }
            Some(pieces) => {
                splits.insert(w.id, pieces);
            }
            None => report.node_limit_ways_left_whole += 1,
        }
    }
    let relations = if splits.is_empty() {
        Vec::new()
    } else {
        let ids: HashSet<i64> = splits.keys().copied().collect();
        read_relations(path, relation_blocks, &ids)?
    };
    report.node_limit_ways_left_whole += node_limits::keep_whole(&mut splits, &relations);
    let piece_ids = node_limits::piece_ids(&splits, next_way);

    let kept_index: HashMap<i64, &KeptWay> = kept.iter().map(|w| (w.id, w)).collect();
    let by_way: HashMap<i64, usize> = rewrites
        .iter()
        .enumerate()
        .filter(|(_, r)| !r.create && matches!(r.shape, RewriteShape::Way(_)))
        .map(|(i, r)| (r.id, i))
        .collect();
    let mut carried: HashSet<i64> = HashSet::new();
    for (way, pieces) in whole.iter().chain(splits.iter()) {
        let Some(w) = kept_index.get(way) else {
            continue;
        };
        carried.extend(w.refs.iter().filter(|r| limited.contains_key(r)));
        let base = by_way
            .get(way)
            .map_or(&w.tags, |i| &rewrites[*i].tags)
            .clone();
        let timestamp = w.timestamp + chrono::Duration::seconds(1);
        // A cut point ends one piece and starts the next: one node.
        let mut previous_end: Option<i64> = None;
        for (k, piece) in pieces.iter().enumerate() {
            let mut refs = Vec::with_capacity(piece.vertices.len());
            for (j, v) in piece.vertices.iter().enumerate() {
                let id = match (j, previous_end, v) {
                    (0, Some(end), _) => end,
                    (_, _, Vertex::Node(id)) => *id,
                    (_, _, Vertex::New(at)) => {
                        let id = next_node;
                        next_node += 1;
                        rewrites.push(Rewrite {
                            id,
                            version: 1,
                            timestamp,
                            create: true,
                            shape: RewriteShape::Node(*at),
                            tags: BTreeMap::new(),
                        });
                        report.node_limit_nodes_created += 1;
                        id
                    }
                };
                refs.push(id);
            }
            previous_end = refs.last().copied();
            let tags = if piece.limits.is_empty() {
                base.clone()
            } else {
                node_limits::piece_tags(&base, &piece.limits)
            };
            if k == 0 {
                match by_way.get(way) {
                    Some(i) => {
                        rewrites[*i].shape = RewriteShape::Way(refs);
                        rewrites[*i].tags = tags;
                    }
                    None => rewrites.push(Rewrite {
                        id: *way,
                        version: w.version.max(0) + 1,
                        timestamp,
                        create: false,
                        shape: RewriteShape::Way(refs),
                        tags,
                    }),
                }
            } else if let Some(id) = piece_ids.get(way).and_then(|ids| ids.get(k)) {
                rewrites.push(Rewrite {
                    id: *id,
                    version: 1,
                    timestamp,
                    create: true,
                    shape: RewriteShape::Way(refs),
                    tags,
                });
                report.node_limit_ways_created += 1;
            }
        }
    }
    for r in &relations {
        if let Some(members) = node_limits::remap(r, &splits, &piece_ids) {
            rewrites.push(Rewrite {
                id: r.id,
                version: r.version.max(0) + 1,
                timestamp: r.timestamp + chrono::Duration::seconds(1),
                create: false,
                shape: RewriteShape::Relation(members),
                tags: r.tags.clone(),
            });
            report.node_limit_relations += 1;
        }
    }
    report.node_limits_carried = carried.len();
    report.node_limit_ways = whole.len() + splits.len();
    tracing::info!(
        nodes = report.node_limits_carried,
        ways = report.node_limit_ways,
        pieces = report.node_limit_ways_created,
        cut_points = report.node_limit_nodes_created,
        relations = report.node_limit_relations,
        left_whole = report.node_limit_ways_left_whole,
        "node limits carried by the ways through them"
    );
    Ok(splits.into_keys().collect())
}

/// Whether an IGN section's limit of `kind` at `value` spares local access.
/// IGN has no exception, so the section takes that of the OpenStreetMap
/// ways it matched when every one of them carries the same figure with the
/// plate, and the graph kept it there ([`tags::spares_local_access_with`]):
/// one "sauf desserte" street seen by two sources must not close what the
/// graph lets a trip reach.
fn ign_spares_local_access(
    kind: RestrictionKind,
    value: f64,
    matched: &[usize],
    kept: &[KeptWay],
    extra: &HashMap<usize, BTreeMap<RestrictionKind, (f64, usize)>>,
) -> bool {
    !matched.is_empty()
        && matched.iter().all(|wi| {
            let Some(w) = kept.get(*wi) else {
                return false;
            };
            let lowest = extra.get(wi).and_then(|m| m.get(&kind)).map(|(v, _)| *v);
            tags::spares_local_access_with(&w.tags, kind, lowest)
                && tags::read_limit(&w.tags, kind)
                    .limit()
                    .is_some_and(|osm| (osm - value).abs() <= tags::tolerance(kind))
        })
}

/// The limits of an IGN section, plausible ones only, without a weight that
/// does not concern the public road
/// ([`IgnSection::weight_concerns_public_traffic`]).
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
    .filter(|(k, _, _)| *k != RestrictionKind::MaxWeight || s.weight_concerns_public_traffic())
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

/// The change file: every rewritten node, way and relation, whole
/// (`osmium apply-changes` replaces an object by the newer version), with a
/// version one above the extract's so the change wins; then the nodes and
/// ways the extract lacks, version 1.
fn osc(rewrites: &[Rewrite]) -> String {
    use std::fmt::Write as _;
    let mut out = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osmChange version=\"0.6\" generator=\"lunaway routing prepare\">\n",
    );
    for (section, create) in [("modify", false), ("create", true)] {
        let _ = writeln!(out, "<{section}>");
        for r in rewrites.iter().filter(|r| r.create == create) {
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
                RewriteShape::Relation(members) => {
                    let _ = writeln!(
                        out,
                        "<relation id=\"{}\" version=\"{}\" timestamp=\"{ts}\">",
                        r.id, r.version
                    );
                    for m in members {
                        let _ = writeln!(
                            out,
                            "<member type=\"{}\" ref=\"{}\" role=\"{}\"/>",
                            m.kind.name(),
                            m.id,
                            xml_escape(&m.role)
                        );
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
                RewriteShape::Relation(_) => "</relation>\n",
            });
        }
        let _ = writeln!(out, "</{section}>");
    }
    out.push_str("</osmChange>\n");
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

/// Writes `fixes.osc.gz`, `restrictions.ndjson.gz`, `prepare.json` and
/// `cut-ways.txt` (one way id a line, [`Prepared::cut_ways`]) into `dir`,
/// which must exist.
///
/// # Errors
///
/// [`IngestError::Cache`] when a file cannot be written,
/// [`IngestError::Json`] when a record does not serialise.
pub fn write(prepared: &Prepared, dir: &Path) -> Result<(), IngestError> {
    use std::fmt::Write as _;
    let mut cut = String::with_capacity(prepared.cut_ways.len() * 11);
    for id in &prepared.cut_ways {
        let _ = writeln!(cut, "{id}");
    }
    let path = dir.join("cut-ways.txt");
    std::fs::write(&path, cut).map_err(|source| IngestError::Cache { path, source })?;
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
        if matches!(
            record.source,
            RestrictionSource::Community | RestrictionSource::Dialog
        ) {
            return Err(IngestError::Implausible {
                what: format!(
                    "line {}: a graph bundle carries no community report nor DiaLog order",
                    n + 1
                ),
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
        let at = Utc.with_ymd_and_hms(2026, 10, 5, 20, 0, 1).unwrap();
        let rewrite = Rewrite {
            id: 42,
            version: 3,
            timestamp: at,
            create: false,
            shape: RewriteShape::Way(vec![1, 2]),
            tags: tags(&[("name", "Rue \"A\" & <B>"), ("maxweight", "3.5")]),
        };
        let piece = Rewrite {
            id: 900,
            version: 1,
            timestamp: at,
            create: true,
            shape: RewriteShape::Way(vec![2, 3]),
            tags: tags(&[("highway", "service")]),
        };
        let relation = Rewrite {
            id: 7,
            version: 2,
            timestamp: at,
            create: false,
            shape: RewriteShape::Relation(vec![node_limits::Member {
                kind: node_limits::MemberKind::Way,
                id: 900,
                role: "a \"b\"".to_owned(),
            }]),
            tags: tags(&[("type", "route")]),
        };
        let text = osc(&[rewrite, piece, relation]);
        assert!(text.contains(r#"<way id="42" version="3" timestamp="2026-10-05T20:00:01Z">"#));
        assert!(text.contains(r#"<tag k="name" v="Rue &quot;A&quot; &amp; &lt;B&gt;"/>"#));
        assert!(text.contains("<nd ref=\"1\"/>\n<nd ref=\"2\"/>"));
        assert!(text.contains(r#"<member type="way" ref="900" role="a &quot;b&quot;"/>"#));
        let create = text.find("<create>").unwrap();
        assert!(
            text.find(r#"<way id="900""#).unwrap() > create
                && text.find(r#"<way id="42""#).unwrap() < create,
            "a piece the extract lacks is created, the way it comes from modified: {text}"
        );
    }
}
