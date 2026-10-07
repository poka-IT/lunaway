//! The roads enclosed behind a "sauf desserte" zone, marked with the
//! zone's limit and plate for the routing engine (`lunaway routing
//! prepare`, `plan/research/65-accroche-et-desserte.md`).
//!
//! Valhalla 3.9.0 grants a trip the right through a limit that spares local
//! access only from the edge the trip starts or ends on, when that edge
//! carries such a limit (`BidirectionalAStar::SetOrigin`,
//! `DynamicCost::GetExemptedAccessRestrictions`). An aire or a campsite on
//! a service road behind a "sauf desserte" street starts from an edge
//! without one: the first pass finds no way in, and the second pass ignores
//! every plate of the network (`thor_worker_t::get_path`, warning 401). Six
//! campsites of France reached that way on the production engine
//! (2026-10-07), Goult's aire behind a 2.5 t street among them.
//!
//! So the roads without a limit of the zone's kind that only the zone
//! leads to, within [`ENCLOSED_REACH_M`] of it, take the zone's limit
//! and plate in the change file: a trip that ends there gets the right from
//! its own edge, on the first pass, and keeps the plates of every other
//! zone. A vehicle under the limit sees no change; one above it may reach
//! these roads only as it may reach the zone, to go there. A component
//! another way leads into for a heavier vehicle (a limit without the plate
//! above the zone's, a road of the general network) is left as it is:
//! marking it would close a way that vehicle may take. Each marked road
//! gets a restriction record flagged `enclosed`: the check after each
//! route joins it to the zone's run of local access and never warns of it,
//! since no sign stands there
//! ([`lunaway_domain::routing::Restriction::enclosed`]).
//!
//! Finding them takes passes over the ways of the extract, one level of
//! roads each: the ways blocks only, remembered by the pass that read the
//! ways first ([`par_blocks`]).

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
    sync::{Mutex, PoisonError},
};

use chrono::{DateTime, Utc};
use lunaway_domain::{
    Position,
    routing::{RestrictionKind, corridor::ENCLOSED_REACH_M, tags},
};
use osmpbf::{BlobDecode, BlobReader, ByteOffset, PrimitiveBlock};

use crate::IngestError;

/// Passes over the ways looking for the roads behind a zone: a level of
/// roads each, the last finding nothing new for a component that is closed.
/// An aire's or a campsite's roads are a few ways deep (six at Les Cytises,
/// 2026-10-07).
pub const MAX_PASSES: usize = 8;
/// Most ways of an enclosed component: more is a district, not a campsite.
pub const MAX_COMPONENT_WAYS: usize = 60;

/// A hasher for OpenStreetMap ids: each pass looks up every node of every
/// road of the extract in the frontier, and the standard hasher, built
/// against crafted keys, spent most of a pass on it (8 to 10 s a pass on
/// France, 2026-10-08). The ids come from the extract the build downloads,
/// not from a client.
#[derive(Default, Clone, Copy)]
struct IdHasher(u64);

impl std::hash::Hasher for IdHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 =
                (self.0.rotate_left(5) ^ u64::from(*b)).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
        }
    }

    fn write_i64(&mut self, i: i64) {
        // The multiplication spreads consecutive ids over the table.
        self.0 =
            (self.0.rotate_left(5) ^ i.cast_unsigned()).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }
}

type Ids = HashSet<i64, std::hash::BuildHasherDefault<IdHasher>>;
type ById<V> = HashMap<i64, V, std::hash::BuildHasherDefault<IdHasher>>;

/// The road classes that belong to the general network: a component that
/// reaches one is not enclosed.
const MAJOR: [&str; 10] = [
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
];

fn pbf_error(path: &Path) -> impl Fn(osmpbf::Error) -> IngestError + '_ {
    move |source| IngestError::Pbf {
        path: path.to_owned(),
        source,
    }
}

/// Reads the data blocks of the extract at `path` on every core: `map` for
/// each block, the results combined by `reduce`; with `only`, the blocks
/// at those offsets alone. Also gives the offsets of the blocks that hold
/// ways, for later passes over the ways alone.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file cannot be read or a block decoded.
pub fn par_blocks<T, I, M, R>(
    path: &Path,
    only: Option<&[ByteOffset]>,
    identity: I,
    map: M,
    reduce: R,
) -> Result<(T, Vec<ByteOffset>), IngestError>
where
    T: Send,
    I: Fn() -> T + Sync,
    M: Fn(&PrimitiveBlock) -> T + Sync,
    R: Fn(T, T) -> T + Sync,
{
    let err = pbf_error(path);
    let threads = std::thread::available_parallelism().map_or(4, std::num::NonZero::get);
    let (tx, rx) = std::sync::mpsc::sync_channel::<(Option<ByteOffset>, osmpbf::Blob)>(threads * 2);
    // Each worker holds the receiver: once the last one has stopped, even
    // by a panic, the reader's next send fails instead of waiting forever.
    let rx = std::sync::Arc::new(Mutex::new(rx));
    std::thread::scope(|scope| {
        let reader = scope.spawn(move || -> Result<(), osmpbf::Error> {
            match only {
                None => {
                    for blob in BlobReader::from_path(path)? {
                        let blob = blob?;
                        if tx.send((blob.offset(), blob)).is_err() {
                            break;
                        }
                    }
                }
                Some(offsets) => {
                    let mut reader = BlobReader::seekable_from_path(path)?;
                    for offset in offsets {
                        let blob = reader.blob_from_offset(*offset)?;
                        if tx.send((Some(*offset), blob)).is_err() {
                            break;
                        }
                    }
                }
            }
            Ok(())
        });
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                let rx = std::sync::Arc::clone(&rx);
                let (identity, map, reduce) = (&identity, &map, &reduce);
                scope.spawn(move || {
                    let mut acc = identity();
                    let mut ways = Vec::new();
                    let mut failure = None;
                    loop {
                        let next = rx.lock().unwrap_or_else(PoisonError::into_inner).recv();
                        let Ok((offset, blob)) = next else { break };
                        // After a failure the blocks are still taken off the
                        // channel, so the reader never waits on a full one.
                        if failure.is_some() {
                            continue;
                        }
                        match blob.decode() {
                            Ok(BlobDecode::OsmData(block)) => {
                                if let Some(o) = offset
                                    && block.groups().any(|g| g.ways().next().is_some())
                                {
                                    ways.push(o);
                                }
                                acc = reduce(acc, map(&block));
                            }
                            Ok(_) => {}
                            Err(e) => failure = Some(e),
                        }
                    }
                    (acc, ways, failure)
                })
            })
            .collect();
        drop(rx);
        let mut total = identity();
        let mut ways = Vec::new();
        let mut failure = None;
        for w in workers {
            match w.join() {
                Ok((acc, w_ways, w_failure)) => {
                    total = reduce(total, acc);
                    ways.extend(w_ways);
                    failure = failure.or(w_failure);
                }
                Err(panic) => std::panic::resume_unwind(panic),
            }
        }
        match reader.join() {
            Ok(Ok(())) => {}
            Ok(Err(e)) => return Err(err(e)),
            Err(panic) => std::panic::resume_unwind(panic),
        }
        if let Some(e) = failure {
            return Err(err(e));
        }
        ways.sort_unstable_by_key(|o| o.0);
        Ok((total, ways))
    })
}

/// A road the search met.
#[derive(Debug, Clone, PartialEq)]
pub struct Road {
    /// Its id.
    pub id: i64,
    /// Its version and timestamp, for the change file.
    pub version: i32,
    /// When it was last edited.
    pub timestamp: DateTime<Utc>,
    /// Its nodes.
    pub refs: Vec<i64>,
    /// Its tags.
    pub tags: BTreeMap<String, String>,
}

/// A zone of one kind of limit: the ways whose limit of that kind spares
/// local access, and what the search found around them.
#[derive(Debug)]
struct Zone {
    kind: RestrictionKind,
    /// The ways of the zone, by id: those whose limit carries the plate.
    seeds: Ids,
    /// Their nodes.
    seed_nodes: Ids,
    /// The roads without a limit of this kind met so far, by id, and
    /// whether each belongs to the general network.
    found: ById<(Road, bool)>,
    /// Nodes already searched from.
    searched: Ids,
    /// Nodes to search from on the next pass.
    frontier: Ids,
    /// The roads met with a limit of this kind and no plate, by id: their
    /// nodes and their figure.
    boundaries: ById<(Vec<i64>, f64)>,
}

/// What a pass gives for one zone.
type PassFinds = Vec<(usize, Road, Search)>;

/// What a way met by a pass is for a zone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Search {
    /// A road without a limit of the zone's kind: searched on from.
    Road,
    /// A road of the general network: the component is not enclosed.
    Major,
    /// A road with a limit of the zone's kind: a boundary, not entered.
    Boundary,
}

/// The ways of each zone's component behind it, found from `seeds` (each
/// way whose limit of a kind spares local access, with its nodes) by
/// passes over the ways blocks of `path` at `way_blocks`.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the extract cannot be read.
pub fn search(
    path: &Path,
    way_blocks: &[ByteOffset],
    seeds: &[(RestrictionKind, i64, Vec<i64>)],
) -> Result<Vec<Enclosed>, IngestError> {
    let mut zones: Vec<Zone> = Vec::new();
    for (kind, id, refs) in seeds {
        let i = if let Some(i) = zones.iter().position(|z| z.kind == *kind) {
            i
        } else {
            zones.push(Zone {
                kind: *kind,
                seeds: Ids::default(),
                seed_nodes: Ids::default(),
                found: ById::default(),
                searched: Ids::default(),
                frontier: Ids::default(),
                boundaries: ById::default(),
            });
            zones.len() - 1
        };
        let z = &mut zones[i];
        z.seeds.insert(*id);
        z.seed_nodes.extend(refs.iter().copied());
        z.frontier.extend(refs.iter().copied());
    }
    for pass in 0..MAX_PASSES {
        if zones.iter().all(|z| z.frontier.is_empty()) {
            break;
        }
        let zones_ref = &zones;
        let (finds, _) = par_blocks(
            path,
            Some(way_blocks),
            Vec::new,
            |block: &PrimitiveBlock| -> PassFinds {
                let mut out = Vec::new();
                for group in block.groups() {
                    for w in group.ways() {
                        // Most ways are not roads (buildings, land use):
                        // their tags say so before their nodes are read.
                        if !w
                            .tags()
                            .any(|(k, v)| k == "highway" && crate::routing::ROUTABLE.contains(&v))
                        {
                            continue;
                        }
                        // Most roads touch no zone: their nodes are read
                        // without being copied.
                        let touching: Vec<usize> = zones_ref
                            .iter()
                            .enumerate()
                            .filter(|(_, z)| {
                                !z.frontier.is_empty()
                                    && w.refs().any(|r| z.frontier.contains(&r))
                                    && !z.seeds.contains(&w.id())
                                    && !z.found.contains_key(&w.id())
                            })
                            .map(|(i, _)| i)
                            .collect();
                        if touching.is_empty() {
                            continue;
                        }
                        let refs: Vec<i64> = w.refs().collect();
                        let tags: BTreeMap<String, String> = w
                            .tags()
                            .map(|(k, v)| (k.to_owned(), v.to_owned()))
                            .collect();
                        if !crate::routing::is_routable(&tags) {
                            continue;
                        }
                        let major = tags
                            .get("highway")
                            .is_some_and(|h| MAJOR.contains(&h.as_str()));
                        let met = Road {
                            id: w.id(),
                            version: w.info().version().unwrap_or(0),
                            timestamp: w
                                .info()
                                .milli_timestamp()
                                .and_then(|m| {
                                    chrono::TimeZone::timestamp_millis_opt(&Utc, m).single()
                                })
                                .unwrap_or(DateTime::UNIX_EPOCH),
                            refs: refs.clone(),
                            tags,
                        };
                        for i in touching {
                            let search = if tags::read_limit(&met.tags, zones_ref[i].kind)
                                .limit()
                                .is_some()
                            {
                                Search::Boundary
                            } else if major {
                                Search::Major
                            } else {
                                Search::Road
                            };
                            out.push((i, met.clone(), search));
                        }
                    }
                }
                out
            },
            |mut a, b| {
                a.extend(b);
                a
            },
        )?;
        for z in &mut zones {
            let frontier = std::mem::take(&mut z.frontier);
            z.searched.extend(frontier);
        }
        for (i, met, search) in finds {
            let z = &mut zones[i];
            match search {
                Search::Boundary => {
                    if let Some(figure) = tags::read_limit(&met.tags, z.kind).limit() {
                        z.boundaries.insert(met.id, (met.refs, figure));
                    }
                }
                Search::Major => {
                    z.found.insert(met.id, (met, true));
                }
                Search::Road => {
                    for r in &met.refs {
                        if !z.searched.contains(r) {
                            z.frontier.insert(*r);
                        }
                    }
                    z.found.insert(met.id, (met, false));
                }
            }
        }
        // A component that has grown past a campsite's size is the general
        // network: it is searched no further.
        for z in &mut zones {
            for c in components(z) {
                if c.len() > MAX_COMPONENT_WAYS {
                    for id in &c {
                        if let Some((met, major)) = z.found.get_mut(id) {
                            *major = true;
                            for r in &met.refs {
                                z.frontier.remove(r);
                            }
                        }
                    }
                }
            }
        }
        tracing::info!(
            pass,
            found = zones.iter().map(|z| z.found.len()).sum::<usize>(),
            frontier = zones.iter().map(|z| z.frontier.len()).sum::<usize>(),
            "roads behind sauf desserte zones searched"
        );
    }
    let mut out = Vec::new();
    for z in &zones {
        for c in components(z) {
            let open = c.len() > MAX_COMPONENT_WAYS
                || c.iter().any(|id| {
                    z.found.get(id).is_none_or(|(met, major)| {
                        *major || met.refs.iter().any(|r| z.frontier.contains(r))
                    })
                });
            if open {
                continue;
            }
            let ways: Vec<Road> = c
                .iter()
                .filter_map(|id| z.found.get(id).map(|(m, _)| m.clone()))
                .collect();
            let nodes: HashSet<i64> = ways.iter().flat_map(|w| w.refs.iter().copied()).collect();
            let gates: HashSet<i64> = nodes
                .iter()
                .copied()
                .filter(|r| z.seed_nodes.contains(r))
                .collect();
            let boundary_max = z
                .boundaries
                .values()
                .filter(|(refs, _)| refs.iter().any(|r| nodes.contains(r)))
                .map(|(_, figure)| *figure)
                .reduce(f64::max);
            out.push(Enclosed {
                kind: z.kind,
                ways,
                gates,
                boundary_max,
            });
        }
    }
    Ok(out)
}

/// The components of a zone's roads: the ways that share a node, by id.
fn components(z: &Zone) -> Vec<Vec<i64>> {
    let mut by_node: HashMap<i64, Vec<i64>> = HashMap::new();
    for (id, (met, _)) in &z.found {
        for r in &met.refs {
            by_node.entry(*r).or_default().push(*id);
        }
    }
    let mut seen: HashSet<i64> = HashSet::new();
    let mut out = Vec::new();
    let mut ids: Vec<i64> = z.found.keys().copied().collect();
    ids.sort_unstable();
    for start in ids {
        if !seen.insert(start) {
            continue;
        }
        let mut component = vec![start];
        let mut stack = vec![start];
        while let Some(id) = stack.pop() {
            let Some((met, _)) = z.found.get(&id) else {
                continue;
            };
            for r in &met.refs {
                for next in by_node.get(r).into_iter().flatten() {
                    if seen.insert(*next) {
                        component.push(*next);
                        stack.push(*next);
                    }
                }
            }
        }
        out.push(component);
    }
    out
}

/// Roads enclosed behind a zone of one kind of limit.
#[derive(Debug, Clone, PartialEq)]
pub struct Enclosed {
    /// The kind of limit.
    pub kind: RestrictionKind,
    /// The roads, none with a limit of that kind.
    pub ways: Vec<Road>,
    /// Their nodes shared with the zone's ways: where a trip comes in.
    pub gates: HashSet<i64>,
    /// The highest figure of the limits without the plate that also lead
    /// into them, if any: a vehicle under it may come in that way.
    pub boundary_max: Option<f64>,
}

impl Enclosed {
    /// Every node of its roads.
    pub fn nodes(&self) -> impl Iterator<Item = i64> + '_ {
        self.ways.iter().flat_map(|w| w.refs.iter().copied())
    }

    /// The roads whose every node lies within [`ENCLOSED_REACH_M`] of a
    /// gate along the roads, given the nodes' positions.
    #[must_use]
    pub fn within_reach(&self, coords: &HashMap<i64, Position>) -> Vec<&Road> {
        let mut edges: HashMap<i64, Vec<(i64, f64)>> = HashMap::new();
        for w in &self.ways {
            for pair in w.refs.windows(2) {
                let (Some(a), Some(b)) = (coords.get(&pair[0]), coords.get(&pair[1])) else {
                    continue;
                };
                let d = a.distance_m(*b);
                edges.entry(pair[0]).or_default().push((pair[1], d));
                edges.entry(pair[1]).or_default().push((pair[0], d));
            }
        }
        // Dijkstra from every gate at once; a few hundred nodes at most.
        let mut best: HashMap<i64, f64> = self.gates.iter().map(|g| (*g, 0.0)).collect();
        let mut queue: Vec<(f64, i64)> = self.gates.iter().map(|g| (0.0, *g)).collect();
        while let Some(i) = queue
            .iter()
            .enumerate()
            .min_by(|a, b| a.1.0.total_cmp(&b.1.0))
            .map(|(i, _)| i)
        {
            let (d, n) = queue.swap_remove(i);
            if best.get(&n).is_some_and(|b| *b < d) {
                continue;
            }
            for (m, len) in edges.get(&n).into_iter().flatten() {
                let next = d + len;
                if next <= ENCLOSED_REACH_M && best.get(m).is_none_or(|b| next < *b) {
                    best.insert(*m, next);
                    queue.push((next, *m));
                }
            }
        }
        self.ways
            .iter()
            .filter(|w| w.refs.iter().all(|r| best.contains_key(r)))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn road(id: i64, refs: &[i64]) -> Road {
        Road {
            id,
            version: 1,
            timestamp: DateTime::UNIX_EPOCH,
            refs: refs.to_vec(),
            tags: BTreeMap::new(),
        }
    }

    fn zone(found: &[(Road, bool)]) -> Zone {
        Zone {
            kind: RestrictionKind::MaxWeight,
            seeds: Ids::default(),
            seed_nodes: Ids::default(),
            found: found.iter().map(|(r, m)| (r.id, (r.clone(), *m))).collect(),
            searched: Ids::default(),
            frontier: Ids::default(),
            boundaries: ById::default(),
        }
    }

    #[test]
    fn roads_that_share_a_node_are_one_component() {
        let z = zone(&[
            (road(1, &[10, 11]), false),
            (road(2, &[11, 12]), false),
            (road(3, &[20, 21]), false),
        ]);
        let mut c: Vec<Vec<i64>> = components(&z)
            .into_iter()
            .map(|mut c| {
                c.sort_unstable();
                c
            })
            .collect();
        c.sort();
        assert_eq!(c, vec![vec![1, 2], vec![3]]);
    }

    #[test]
    fn only_the_roads_within_reach_of_a_gate_are_marked() {
        // A service road north from the gate, 111 m, then a track to 667 m.
        let at = |north: f64| Position::new(45.0 + north, 1.0).unwrap();
        let coords: HashMap<i64, Position> = [
            (1, at(0.0)),
            (2, at(0.000_5)),
            (3, at(0.001)),
            (4, at(0.004)),
            (5, at(0.006)),
        ]
        .into_iter()
        .collect();
        let e = Enclosed {
            kind: RestrictionKind::MaxWeight,
            ways: vec![road(500, &[1, 2, 3]), road(800, &[3, 4, 5])],
            gates: [1].into_iter().collect(),
            boundary_max: None,
        };
        let reached: Vec<i64> = e.within_reach(&coords).iter().map(|r| r.id).collect();
        assert_eq!(reached, [500], "the track ends 667 m from the gate");
        let none = Enclosed {
            gates: HashSet::new(),
            ..e
        };
        assert!(none.within_reach(&coords).is_empty(), "no gate, no way in");
    }
}
