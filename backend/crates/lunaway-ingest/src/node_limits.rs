//! Limits mapped on a node, carried where the routing engine reads them.
//!
//! Valhalla 3.9 reads a clearance, a width, a length or a weight on a way
//! only: its tag script reads access alone on a node (`nodes_proc` in
//! `lua/graph.lua`). A height bar mapped on a node was invisible to it, and
//! every route through one cost a second engine call once the check after
//! the route had found it, 1.2 to 2.6 s on a long trip
//! (`plan/research/48-latence-itineraires.md`, 3.4). The maintainers' way
//! round (valhalla/valhalla#3487) is to cut the way at the node and carry
//! the limit on a short stretch around it, which the change file does here:
//! each routable way through such a node is cut [`CUT_M`] before and after
//! it; the stretch between carries the node's limits, the rest keeps the
//! way's tags. The first piece keeps the way's id; the other pieces and the
//! new cut points take ids above the highest of the extract, and every
//! relation that names the way names its pieces instead.
//!
//! Every way through the node is cut, the road a bar stands at the end of
//! included: the check after each route counts a node on the route's line,
//! whichever way the route follows through it, and a recalculation excluded
//! the whole of each edge through it. The engine now stops at the same
//! node, on its first pass, and a stop beyond the bar on the same way stays
//! reachable.

use std::collections::{BTreeMap, HashMap, HashSet};

use lunaway_domain::{
    Position,
    routing::{
        RestrictionKind,
        restriction::ASSUMED_BAR_HEIGHT_M,
        tags::{self, TagValue},
    },
};

/// How far before and after a limited node a way is cut, metres: the
/// stretch that carries the node's limits is twice as long. Short, so that
/// a stop just beside the bar is not taken for one behind it; longer than
/// the rounding of an edge's length to the metre.
pub(crate) const CUT_M: f64 = 2.0;
/// A cut this close to a node of the way is made at that node, metres.
const SAME_POINT_M: f64 = 0.5;

/// The figure of each limit a node puts on the stretch around it.
pub(crate) type Limits = BTreeMap<RestrictionKind, f64>;

/// The limits of a node the engine applies once a way carries them, as the
/// check after each route blocks on them: a height, width, length or weight
/// with its figure; a bar's clearance without a figure at
/// [`ASSUMED_BAR_HEIGHT_M`], which the check blocks above. Left to the
/// check: a limit that spares local access (the engine's rule for a plate
/// differs from the check's), an axle load (the engine is never given the
/// vehicle's), a ban on trailers, and a clearance of unknown figure on a
/// node that is no barrier, which the check only announces. A ban on
/// motorhomes reaches the engine already, as the node's access
/// (`tags::graph_fixes` copies it into `motorcar`).
pub(crate) fn engine_limits(node_tags: &BTreeMap<String, String>) -> Limits {
    let mut out = Limits::new();
    for kind in [
        RestrictionKind::MaxHeight,
        RestrictionKind::MaxWidth,
        RestrictionKind::MaxLength,
        RestrictionKind::MaxWeight,
    ] {
        if !tags::has_key(node_tags, kind) {
            continue;
        }
        if let TagValue::Limit(v) = tags::read_limit(node_tags, kind)
            && !tags::limit_spares_local_access(node_tags, kind)
        {
            out.insert(kind, v);
        }
    }
    let barrier = node_tags.contains_key("barrier");
    let bar = node_tags.get("barrier").map(String::as_str) == Some("height_restrictor");
    let unknown_height = match tags::read_limit(node_tags, RestrictionKind::MaxHeight) {
        TagValue::BelowDefault => true,
        TagValue::Limit(_) => false,
        // A bar mapped without its figure, or with `default`, is still a bar.
        _ => bar,
    };
    if barrier && unknown_height && !out.contains_key(&RestrictionKind::MaxHeight) {
        out.insert(RestrictionKind::MaxHeight, ASSUMED_BAR_HEIGHT_M);
    }
    out
}

/// A point of a piece: a node of the extract, or a cut point the change
/// file creates.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum Vertex {
    /// A node of the extract, by id.
    Node(i64),
    /// A new node, at this position.
    New(Position),
}

/// One piece of a way cut around its limited nodes.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Piece {
    /// Its points, in the way's order.
    pub vertices: Vec<Vertex>,
    /// The limits it carries beyond the way's own; empty off the stretches.
    pub limits: Limits,
}

/// The lowest figure of each kind of `a` and `b`.
fn lowest(mut a: Limits, b: &Limits) -> Limits {
    for (kind, v) in b {
        a.entry(*kind).and_modify(|x| *x = x.min(*v)).or_insert(*v);
    }
    a
}

/// The point `t` of the way along the segment from `a` to `b`.
fn between(a: Position, b: Position, t: f64) -> Option<Position> {
    Position::new(
        a.lat() + (b.lat() - a.lat()) * t,
        a.lon() + (b.lon() - a.lon()) * t,
    )
    .ok()
}

/// The pieces of the way of nodes `refs` once cut around the nodes of
/// `limited` it holds, or `None` when it holds none, when a node's position
/// is missing, or when the node that closes a ring is limited (the stretch
/// would straddle the ring's two ends: left to the check).
pub(crate) fn cut(
    refs: &[i64],
    coords: &HashMap<i64, Position>,
    limited: &HashMap<i64, Limits>,
) -> Option<Vec<Piece>> {
    if refs.len() < 2 {
        return None;
    }
    let points: Vec<Position> = refs
        .iter()
        .map(|r| coords.get(r).copied())
        .collect::<Option<_>>()?;
    let closed = refs.len() > 2 && refs.first() == refs.last();
    let mut along = Vec::with_capacity(points.len());
    let mut s = 0.0;
    along.push(0.0);
    for w in points.windows(2) {
        s += w[0].distance_m(w[1]);
        along.push(s);
    }
    let total = s;
    if total <= 0.0 {
        return None;
    }

    // The stretch around each limited node, merged when they touch.
    let mut zones: Vec<(f64, f64, Limits)> = Vec::new();
    for (i, r) in refs.iter().enumerate() {
        let Some(limits) = limited.get(r) else {
            continue;
        };
        if closed && (i == 0 || i == refs.len() - 1) {
            return None;
        }
        zones.push((
            (along[i] - CUT_M).max(0.0),
            (along[i] + CUT_M).min(total),
            limits.clone(),
        ));
    }
    if zones.is_empty() {
        return None;
    }
    zones.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut merged: Vec<(f64, f64, Limits)> = Vec::new();
    for (start, end, limits) in zones {
        match merged.last_mut() {
            Some(last) if start <= last.1 + SAME_POINT_M => {
                last.1 = last.1.max(end);
                last.2 = lowest(std::mem::take(&mut last.2), &limits);
            }
            _ => merged.push((start, end, limits)),
        }
    }

    // Where the way is cut: each stretch's ends, but never at the way's own.
    let mut breaks: Vec<f64> = merged
        .iter()
        .flat_map(|(a, b, _)| [*a, *b])
        .filter(|x| *x > SAME_POINT_M && *x < total - SAME_POINT_M)
        .collect();
    breaks.sort_by(f64::total_cmp);

    // The way's points with the cut points inserted, and where each cut
    // falls among them (a cut within SAME_POINT_M of a node is made there).
    let mut seq: Vec<(Vertex, f64)> = Vec::with_capacity(refs.len() + breaks.len());
    let mut cuts: Vec<usize> = Vec::with_capacity(breaks.len());
    let mut next = breaks.iter().copied().peekable();
    for (j, r) in refs.iter().enumerate() {
        seq.push((Vertex::Node(*r), along[j]));
        let here = seq.len() - 1;
        while next.peek().is_some_and(|b| *b <= along[j] + SAME_POINT_M) {
            next.next();
            cuts.push(here);
        }
        let Some(&end) = along.get(j + 1) else {
            continue;
        };
        while let Some(b) = next.peek().copied() {
            if b >= end - SAME_POINT_M {
                break;
            }
            next.next();
            let t = (b - along[j]) / (end - along[j]);
            let at = between(points[j], points[j + 1], t)?;
            seq.push((Vertex::New(at), b));
            cuts.push(seq.len() - 1);
        }
    }
    cuts.dedup();
    cuts.retain(|c| *c > 0 && *c < seq.len() - 1);

    let limits_of = |from: f64, to: f64| -> Limits {
        let middle = (from + to) / 2.0;
        merged
            .iter()
            .find(|(a, b, _)| middle >= *a && middle <= *b)
            .map(|(_, _, l)| l.clone())
            .unwrap_or_default()
    };
    let mut pieces: Vec<Piece> = Vec::with_capacity(cuts.len() + 1);
    let mut start = 0;
    for end in cuts.iter().copied().chain(std::iter::once(seq.len() - 1)) {
        if end <= start {
            continue;
        }
        let vertices: Vec<Vertex> = seq[start..=end].iter().map(|(v, _)| *v).collect();
        let limits = limits_of(seq[start].1, seq[end].1);
        match pieces.last_mut() {
            // Two pieces side by side with the same limits are one.
            Some(last) if last.limits == limits => last.vertices.extend(&vertices[1..]),
            _ => pieces.push(Piece { vertices, limits }),
        }
        start = end;
    }
    Some(pieces)
}

/// What a relation member is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MemberKind {
    /// A node.
    Node,
    /// A way.
    Way,
    /// A relation.
    Relation,
}

impl MemberKind {
    /// The name the change file writes.
    pub(crate) const fn name(self) -> &'static str {
        match self {
            Self::Node => "node",
            Self::Way => "way",
            Self::Relation => "relation",
        }
    }
}

/// A relation member, as the change file writes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Member {
    /// What it is.
    pub kind: MemberKind,
    /// The member's id.
    pub id: i64,
    /// Its role.
    pub role: String,
}

/// A relation that names a way to cut.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Relation {
    /// Its id.
    pub id: i64,
    /// Its version, for the change file.
    pub version: i32,
    /// When it was last edited.
    pub timestamp: chrono::DateTime<chrono::Utc>,
    /// Its tags.
    pub tags: BTreeMap<String, String>,
    /// Its members, in order.
    pub members: Vec<Member>,
    /// Whether every member's role was read: one that was not would be
    /// written back without it, so the relation is left as it is, and the
    /// ways it names whole.
    pub complete: bool,
}

/// Whether a relation names one way before and one after a point
/// (`restriction`, `connectivity`): the engine reads its `from` and `to`
/// as the way that reaches the `via` node, so each must stay one way.
fn is_turn(r: &Relation) -> bool {
    matches!(
        r.tags.get("type").map(String::as_str),
        Some("restriction" | "connectivity")
    )
}

/// The index of the one piece of `pieces` that holds node `via`, if exactly
/// one does.
fn piece_at(pieces: &[Piece], via: i64) -> Option<usize> {
    let mut found = pieces
        .iter()
        .enumerate()
        .filter(|(_, p)| p.vertices.contains(&Vertex::Node(via)))
        .map(|(i, _)| i);
    let first = found.next()?;
    found.next().is_none().then_some(first)
}

/// Removes from `splits` the ways a relation cannot follow once cut, and
/// returns how many: in a turn, one of its `via` (a turn through several
/// ways: the chain would have to be rebuilt), or a `from` or `to` whose
/// node `via` is not on exactly one of its pieces; any way of a relation
/// not read whole. Those ways stay whole; the check after each route keeps
/// their node's limit.
pub(crate) fn keep_whole(splits: &mut BTreeMap<i64, Vec<Piece>>, relations: &[Relation]) -> usize {
    let mut whole: HashSet<i64> = HashSet::new();
    for r in relations.iter().filter(|r| !r.complete || is_turn(r)) {
        let via_nodes: Vec<i64> = r
            .members
            .iter()
            .filter(|m| m.role == "via" && m.kind == MemberKind::Node)
            .map(|m| m.id)
            .collect();
        let via_way = r
            .members
            .iter()
            .any(|m| m.role == "via" && m.kind == MemberKind::Way);
        for m in r.members.iter().filter(|m| m.kind == MemberKind::Way) {
            let Some(pieces) = splits.get(&m.id) else {
                continue;
            };
            let keep = match (r.complete, via_way, via_nodes.as_slice()) {
                (false, _, _) => true,
                (true, false, [via]) if m.role == "from" || m.role == "to" => {
                    piece_at(pieces, *via).is_none()
                }
                (true, false, _) if m.role != "from" && m.role != "to" && m.role != "via" => false,
                _ => true,
            };
            if keep {
                whole.insert(m.id);
            }
        }
    }
    for id in &whole {
        splits.remove(id);
    }
    whole.len()
}

/// The ids the pieces of each cut way take: the first keeps the way's, the
/// others follow `next_way`.
pub(crate) fn piece_ids(
    splits: &BTreeMap<i64, Vec<Piece>>,
    mut next_way: i64,
) -> BTreeMap<i64, Vec<i64>> {
    let mut out = BTreeMap::new();
    for (way, pieces) in splits {
        let mut ids = Vec::with_capacity(pieces.len());
        ids.push(*way);
        for _ in 1..pieces.len() {
            ids.push(next_way);
            next_way += 1;
        }
        out.insert(*way, ids);
    }
    out
}

/// The members of `r` once its cut ways name their pieces: a turn's `from`
/// or `to` the piece at its `via` node, any other member every piece in
/// the way's order. `None` when no member is a cut way.
pub(crate) fn remap(
    r: &Relation,
    splits: &BTreeMap<i64, Vec<Piece>>,
    ids: &BTreeMap<i64, Vec<i64>>,
) -> Option<Vec<Member>> {
    if !r.complete
        || !r
            .members
            .iter()
            .any(|m| m.kind == MemberKind::Way && splits.contains_key(&m.id))
    {
        return None;
    }
    let turn = is_turn(r);
    let via = r
        .members
        .iter()
        .find(|m| m.role == "via" && m.kind == MemberKind::Node)
        .map(|m| m.id);
    let mut out = Vec::with_capacity(r.members.len() + 2);
    for m in &r.members {
        let (Some(pieces), Some(piece_ids), MemberKind::Way) =
            (splits.get(&m.id), ids.get(&m.id), m.kind)
        else {
            out.push(m.clone());
            continue;
        };
        let one = (turn && (m.role == "from" || m.role == "to"))
            .then(|| via.and_then(|v| piece_at(pieces, v)))
            .flatten();
        match one {
            Some(i) => out.push(Member {
                kind: MemberKind::Way,
                id: piece_ids[i],
                role: m.role.clone(),
            }),
            None => out.extend(piece_ids.iter().map(|id| Member {
                kind: MemberKind::Way,
                id: *id,
                role: m.role.clone(),
            })),
        }
    }
    Some(out)
}

/// The tags of a piece: the way's, with each of `limits` lowered to the
/// piece's figure under the key the engine reads. A plate for local access
/// on that key goes when the node's figure is the lower or the same: the
/// node's own limit carries none, and the check blocks a vehicle above it
/// whatever its destination. When the way's figure under a plate is the
/// lower, the stretch keeps it and its plate: one key holds one figure, and
/// the check after each route still blocks the node's.
pub(crate) fn piece_tags(
    way: &BTreeMap<String, String>,
    limits: &Limits,
) -> BTreeMap<String, String> {
    let mut out = way.clone();
    for (kind, figure) in limits {
        let current = tags::read_limit(way, *kind).limit();
        let value = current.map_or(*figure, |c| c.min(*figure));
        out.insert(kind.graph_key().to_owned(), tags::canonical(value));
        if current.is_none_or(|c| *figure <= c) {
            for key in kind.conditional_keys() {
                out.remove(*key);
            }
        }
    }
    out
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

    /// Nodes 1 to `n` every 10 m going east along the equator.
    fn straight(n: i64) -> (Vec<i64>, HashMap<i64, Position>) {
        let step = 10.0 / 111_195.0;
        let refs: Vec<i64> = (1..=n).collect();
        let coords = refs
            .iter()
            .map(|r| {
                #[allow(clippy::cast_precision_loss, reason = "a few nodes")]
                let lon = step * (*r - 1) as f64;
                (*r, Position::new(0.0, lon).unwrap())
            })
            .collect();
        (refs, coords)
    }

    fn height(v: f64) -> Limits {
        Limits::from([(RestrictionKind::MaxHeight, v)])
    }

    fn length_m(p: &Piece, coords: &HashMap<i64, Position>) -> f64 {
        let pos = |v: &Vertex| match v {
            Vertex::Node(id) => coords[id],
            Vertex::New(p) => *p,
        };
        p.vertices
            .windows(2)
            .map(|w| pos(&w[0]).distance_m(pos(&w[1])))
            .sum()
    }

    #[test]
    fn a_bar_in_the_middle_of_a_way_gets_a_stretch_of_four_metres() {
        let (refs, coords) = straight(5);
        let limited = HashMap::from([(3, height(2.1))]);
        let pieces = cut(&refs, &coords, &limited).unwrap();
        assert_eq!(pieces.len(), 3, "{pieces:?}");
        assert!(pieces[0].limits.is_empty() && pieces[2].limits.is_empty());
        assert_eq!(pieces[1].limits, height(2.1));
        assert!(
            pieces[1].vertices.contains(&Vertex::Node(3)),
            "the bar is on the stretch that carries its limit"
        );
        let stretch = length_m(&pieces[1], &coords);
        assert!((stretch - 2.0 * CUT_M).abs() < 0.05, "{stretch}");
        let whole: f64 = pieces.iter().map(|p| length_m(p, &coords)).sum();
        assert!(
            (whole - 40.0).abs() < 0.05,
            "the way keeps its length: {whole}"
        );
        assert_eq!(pieces[0].vertices.first(), Some(&Vertex::Node(1)));
        assert_eq!(pieces[2].vertices.last(), Some(&Vertex::Node(5)));
        assert_eq!(
            pieces[0].vertices.last(),
            pieces[1].vertices.first(),
            "consecutive pieces share their cut point"
        );
    }

    #[test]
    fn a_bar_at_the_end_of_a_way_is_cut_on_one_side_only() {
        let (refs, coords) = straight(3);
        let limited = HashMap::from([(3, height(2.0))]);
        let pieces = cut(&refs, &coords, &limited).unwrap();
        assert_eq!(pieces.len(), 2, "{pieces:?}");
        assert_eq!(pieces[1].limits, height(2.0));
        assert_eq!(pieces[1].vertices.last(), Some(&Vertex::Node(3)));
        assert!((length_m(&pieces[1], &coords) - CUT_M).abs() < 0.05);
    }

    #[test]
    fn a_cut_next_to_a_node_is_made_at_the_node() {
        // Nodes 10 m apart, the second at 1.8 m from the bar: the cut at
        // 2 m falls 0.2 m from it.
        let step = 1.0 / 111_195.0;
        let refs = vec![1, 2, 3, 4];
        let coords = HashMap::from([
            (1, Position::new(0.0, 0.0).unwrap()),
            (2, Position::new(0.0, step * 8.2).unwrap()),
            (3, Position::new(0.0, step * 10.0).unwrap()),
            (4, Position::new(0.0, step * 30.0).unwrap()),
        ]);
        let pieces = cut(&refs, &coords, &HashMap::from([(3, height(2.5))])).unwrap();
        assert_eq!(pieces.len(), 3, "{pieces:?}");
        assert_eq!(pieces[1].vertices.first(), Some(&Vertex::Node(2)));
        assert!(matches!(pieces[1].vertices.last(), Some(Vertex::New(_))));
    }

    #[test]
    fn two_bars_close_together_share_one_stretch_with_the_lower_figures() {
        let step = 1.0 / 111_195.0;
        let refs = vec![1, 2, 3, 4];
        let coords = HashMap::from([
            (1, Position::new(0.0, 0.0).unwrap()),
            (2, Position::new(0.0, step * 20.0).unwrap()),
            (3, Position::new(0.0, step * 23.0).unwrap()),
            (4, Position::new(0.0, step * 50.0).unwrap()),
        ]);
        let limited = HashMap::from([
            (2, height(2.5)),
            (
                3,
                Limits::from([
                    (RestrictionKind::MaxHeight, 2.2),
                    (RestrictionKind::MaxWidth, 2.0),
                ]),
            ),
        ]);
        let pieces = cut(&refs, &coords, &limited).unwrap();
        assert_eq!(pieces.len(), 3, "{pieces:?}");
        assert_eq!(
            pieces[1].limits,
            Limits::from([
                (RestrictionKind::MaxHeight, 2.2),
                (RestrictionKind::MaxWidth, 2.0)
            ])
        );
        assert!((length_m(&pieces[1], &coords) - 7.0).abs() < 0.05);
    }

    #[test]
    fn a_short_way_within_the_stretch_takes_the_limit_whole() {
        let step = 1.0 / 111_195.0;
        let refs = vec![1, 2, 3];
        let coords = HashMap::from([
            (1, Position::new(0.0, 0.0).unwrap()),
            (2, Position::new(0.0, step * 1.5).unwrap()),
            (3, Position::new(0.0, step * 3.0).unwrap()),
        ]);
        let pieces = cut(&refs, &coords, &HashMap::from([(2, height(2.0))])).unwrap();
        assert_eq!(pieces.len(), 1, "{pieces:?}");
        assert_eq!(
            pieces[0].vertices,
            vec![Vertex::Node(1), Vertex::Node(2), Vertex::Node(3)]
        );
        assert_eq!(pieces[0].limits, height(2.0));
    }

    #[test]
    fn a_ring_closed_at_its_bar_is_left_whole() {
        let (mut refs, coords) = straight(4);
        refs.push(1);
        assert!(cut(&refs, &coords, &HashMap::from([(1, height(2.0))])).is_none());
        let pieces = cut(&refs, &coords, &HashMap::from([(3, height(2.0))])).unwrap();
        assert_eq!(pieces.iter().filter(|p| !p.limits.is_empty()).count(), 1);
    }

    #[test]
    fn the_limits_a_node_hands_the_engine() {
        assert_eq!(
            engine_limits(&tags(&[("barrier", "height_restrictor")])),
            height(ASSUMED_BAR_HEIGHT_M),
            "a bar without its figure is stopped above the assumed height, as the check does"
        );
        assert_eq!(
            engine_limits(&tags(&[
                ("barrier", "height_restrictor"),
                ("maxheight", "default")
            ])),
            height(ASSUMED_BAR_HEIGHT_M),
            "the bar of the port of Tarifa"
        );
        assert_eq!(
            engine_limits(&tags(&[
                ("barrier", "height_restrictor"),
                ("maxheight", "3,1")
            ])),
            height(3.1)
        );
        assert!(
            engine_limits(&tags(&[("maxheight", "below_default")])).is_empty(),
            "an unknown clearance off a barrier is only announced"
        );
        assert!(
            engine_limits(&tags(&[
                ("barrier", "gate"),
                ("maxweight", "3.5"),
                ("maxweight:conditional", "none @ destination")
            ]))
            .is_empty(),
            "a plate for local access stays with the check"
        );
        assert!(engine_limits(&tags(&[("maxaxleload", "2")])).is_empty());
        assert_eq!(
            engine_limits(&tags(&[("barrier", "bollard"), ("maxwidth", "1.8")])),
            Limits::from([(RestrictionKind::MaxWidth, 1.8)])
        );
    }

    fn relation(id: i64, kind: &str, members: &[(&str, i64, &str)]) -> Relation {
        Relation {
            id,
            version: 3,
            timestamp: chrono::DateTime::UNIX_EPOCH,
            tags: tags(&[("type", kind)]),
            members: members
                .iter()
                .map(|(k, id, role)| Member {
                    kind: match *k {
                        "node" => MemberKind::Node,
                        "way" => MemberKind::Way,
                        _ => MemberKind::Relation,
                    },
                    id: *id,
                    role: (*role).to_owned(),
                })
                .collect(),
            complete: true,
        }
    }

    #[test]
    fn relations_name_the_pieces_and_a_turn_the_piece_at_its_node() {
        let (refs, coords) = straight(5);
        let pieces = cut(&refs, &coords, &HashMap::from([(3, height(2.1))])).unwrap();
        let mut splits = BTreeMap::from([(100, pieces)]);
        let turn = relation(
            7,
            "restriction",
            &[("way", 100, "from"), ("node", 5, "via"), ("way", 200, "to")],
        );
        let route = relation(8, "route", &[("way", 50, ""), ("way", 100, "forward")]);
        let through = relation(
            9,
            "restriction",
            &[
                ("way", 300, "from"),
                ("way", 100, "via"),
                ("way", 200, "to"),
            ],
        );
        assert_eq!(keep_whole(&mut splits, &[turn.clone(), route.clone()]), 0);
        let ids = piece_ids(&splits, 1_000);
        assert_eq!(ids[&100], vec![100, 1_000, 1_001]);
        let members = remap(&turn, &splits, &ids).unwrap();
        assert_eq!(
            members[0].id, 1_001,
            "the turn starts from the piece that reaches node 5"
        );
        let members = remap(&route, &splits, &ids).unwrap();
        let named: Vec<(i64, &str)> = members.iter().map(|m| (m.id, m.role.as_str())).collect();
        assert_eq!(
            named,
            vec![
                (50, ""),
                (100, "forward"),
                (1_000, "forward"),
                (1_001, "forward")
            ]
        );
        assert!(remap(&relation(10, "route", &[("way", 60, "")]), &splits, &ids).is_none());
        assert_eq!(
            keep_whole(&mut splits, &[through]),
            1,
            "a turn through the way keeps it whole"
        );
        assert!(splits.is_empty());
    }

    #[test]
    fn a_turn_whose_node_is_no_end_of_a_piece_keeps_the_way_whole() {
        let (refs, coords) = straight(5);
        let pieces = cut(&refs, &coords, &HashMap::from([(3, height(2.1))])).unwrap();
        let mut splits = BTreeMap::from([(100, pieces)]);
        let turn = relation(
            7,
            "restriction",
            &[
                ("way", 100, "from"),
                ("node", 42, "via"),
                ("way", 200, "to"),
            ],
        );
        assert_eq!(keep_whole(&mut splits, &[turn]), 1);
    }

    #[test]
    fn a_turn_at_a_cut_made_on_a_node_of_the_way_keeps_the_way_whole() {
        // The bar at 10 m, a node at 8.2 m where the cut is made: that node
        // ends one piece and starts the next, so a turn through it cannot
        // name one piece as its `from`.
        let step = 1.0 / 111_195.0;
        let refs = vec![1, 2, 3, 4];
        let coords = HashMap::from([
            (1, Position::new(0.0, 0.0).unwrap()),
            (2, Position::new(0.0, step * 8.2).unwrap()),
            (3, Position::new(0.0, step * 10.0).unwrap()),
            (4, Position::new(0.0, step * 30.0).unwrap()),
        ]);
        let pieces = cut(&refs, &coords, &HashMap::from([(3, height(2.5))])).unwrap();
        let mut splits = BTreeMap::from([(100, pieces)]);
        let turn = relation(
            7,
            "restriction",
            &[("way", 100, "from"), ("node", 2, "via"), ("way", 200, "to")],
        );
        assert_eq!(keep_whole(&mut splits, &[turn]), 1);
        assert!(splits.is_empty());
    }

    #[test]
    fn a_relation_not_read_whole_keeps_its_ways_whole() {
        let (refs, coords) = straight(5);
        let pieces = cut(&refs, &coords, &HashMap::from([(3, height(2.1))])).unwrap();
        let mut splits = BTreeMap::from([(100, pieces)]);
        let mut route = relation(8, "route", &[("way", 100, "")]);
        route.complete = false;
        assert!(remap(&route, &splits, &piece_ids(&splits, 1_000)).is_none());
        assert_eq!(keep_whole(&mut splits, &[route]), 1);
    }

    #[test]
    fn a_plate_goes_when_the_node_figure_equals_the_way_figure() {
        // The node's 3.5 t has no plate: a vehicle above it is blocked by
        // the check whatever its destination, so the engine must not let
        // one bound for a place behind it through.
        let way = tags(&[
            ("highway", "residential"),
            ("maxweight", "3.5"),
            ("maxweight:conditional", "none @ destination"),
        ]);
        let piece = piece_tags(&way, &Limits::from([(RestrictionKind::MaxWeight, 3.5)]));
        assert_eq!(piece.get("maxweight").map(String::as_str), Some("3.5"));
        assert!(!piece.contains_key("maxweight:conditional"), "{piece:?}");
    }

    #[test]
    fn a_piece_takes_the_lower_figure_and_loses_the_plate_under_it() {
        let way = tags(&[
            ("highway", "residential"),
            ("maxweight", "7.5"),
            ("maxweight:conditional", "none @ destination"),
            ("maxheight", "2.0"),
        ]);
        let piece = piece_tags(
            &way,
            &Limits::from([
                (RestrictionKind::MaxWeight, 3.5),
                (RestrictionKind::MaxHeight, 2.5),
            ]),
        );
        assert_eq!(piece.get("maxweight").map(String::as_str), Some("3.5"));
        assert!(!piece.contains_key("maxweight:conditional"));
        assert_eq!(
            piece.get("maxheight").map(String::as_str),
            Some("2"),
            "the way's lower clearance stays"
        );
        assert_eq!(
            piece.get("highway").map(String::as_str),
            Some("residential")
        );
    }
}
