//! Grouping matched records into places (union-find under constraints).
//!
//! Records connected by `merge` decisions form one place, with three limits
//! that a plain transitive closure would break:
//!
//! - an automatic merge never puts two records of the same source in one
//!   group: a source that lists a spot twice has a duplicate to report, and a
//!   chain A~B~C must not pull two records of one source together through B;
//! - a human `cannot_link` keeps two records apart whatever the scores;
//! - a human `must_link` joins two records whatever the scores and sources.
//!
//! Edges are applied strongest first, ties broken by the record keys, so the
//! result depends only on the input, never on its order.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::source::SourceId;

/// A merge decision between two records.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MergeEdge<K> {
    /// One record.
    pub a: K,
    /// The other record.
    pub b: K,
    /// Its match score.
    pub score: f64,
}

/// What a person decided about two records.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConstraintKind {
    /// They are the same spot.
    MustLink,
    /// They are different spots.
    CannotLink,
}

impl ConstraintKind {
    /// The stable code stored in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::MustLink => "must_link",
            Self::CannotLink => "cannot_link",
        }
    }
}

/// A human decision on a pair of records.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Constraint<K> {
    /// One record.
    pub a: K,
    /// The other record.
    pub b: K,
    /// The decision.
    pub kind: ConstraintKind,
}

/// The groups, and for each grouped record the score that tied it in.
#[derive(Debug, Clone, PartialEq)]
pub struct Clustering<K> {
    /// Every input record exactly once; members sorted, groups sorted by
    /// their first member.
    pub groups: Vec<Vec<K>>,
    /// Best accepted link of each record that is not alone in its group: the
    /// edge score, or 1 for a `must_link`.
    pub link_score: BTreeMap<K, f64>,
    /// `must_link` constraints refused because they would join a
    /// `cannot_link` pair: contradictory human decisions to resolve.
    pub conflicts: Vec<Constraint<K>>,
}

struct Sets<'a> {
    parent: Vec<usize>,
    members: Vec<BTreeSet<usize>>,
    sources: Vec<BTreeSet<&'a SourceId>>,
    /// Nodes each root must never be joined with.
    forbidden: Vec<BTreeSet<usize>>,
}

impl<'a> Sets<'a> {
    fn find(&mut self, mut x: usize) -> usize {
        while self.parent[x] != x {
            self.parent[x] = self.parent[self.parent[x]];
            x = self.parent[x];
        }
        x
    }

    fn forbids(&self, ra: usize, rb: usize) -> bool {
        self.members[rb]
            .iter()
            .any(|m| self.forbidden[ra].contains(m))
    }

    fn share_a_source(&self, ra: usize, rb: usize) -> bool {
        !self.sources[ra].is_disjoint(&self.sources[rb])
    }

    /// Joins the two roots; the smaller index stays the root so the outcome
    /// does not depend on the order of the calls.
    fn union(&mut self, ra: usize, rb: usize) {
        let (keep, gone) = if ra < rb { (ra, rb) } else { (rb, ra) };
        self.parent[gone] = keep;
        let members = std::mem::take(&mut self.members[gone]);
        self.members[keep].extend(members);
        let sources = std::mem::take(&mut self.sources[gone]);
        self.sources[keep].extend(sources);
        let forbidden = std::mem::take(&mut self.forbidden[gone]);
        self.forbidden[keep].extend(forbidden);
    }
}

/// Groups `records` (key and source) along `edges` under `constraints`.
/// Edges and constraints naming an unknown key are ignored.
#[must_use]
pub fn cluster<K: Ord + Copy>(
    records: &[(K, &SourceId)],
    edges: &[MergeEdge<K>],
    constraints: &[Constraint<K>],
) -> Clustering<K> {
    let mut sorted: Vec<(K, &SourceId)> = records.to_vec();
    sorted.sort_by_key(|(k, _)| *k);
    sorted.dedup_by_key(|(k, _)| *k);
    let index: BTreeMap<K, usize> = sorted
        .iter()
        .enumerate()
        .map(|(i, (k, _))| (*k, i))
        .collect();
    let n = sorted.len();
    let mut sets = Sets {
        parent: (0..n).collect(),
        members: (0..n).map(|i| BTreeSet::from([i])).collect(),
        sources: sorted.iter().map(|(_, s)| BTreeSet::from([*s])).collect(),
        forbidden: vec![BTreeSet::new(); n],
    };
    let mut link_score: BTreeMap<K, f64> = BTreeMap::new();
    let mut note = |k: K, s: f64| {
        let e = link_score.entry(k).or_insert(s);
        *e = e.max(s);
    };

    let pairs = |kind: ConstraintKind| {
        let mut v: Vec<(usize, usize)> = constraints
            .iter()
            .filter(|c| c.kind == kind)
            .filter_map(|c| Some((*index.get(&c.a)?, *index.get(&c.b)?)))
            .filter(|(a, b)| a != b)
            .map(|(a, b)| (a.min(b), a.max(b)))
            .collect();
        v.sort_unstable();
        v.dedup();
        v
    };
    for (a, b) in pairs(ConstraintKind::CannotLink) {
        sets.forbidden[a].insert(b);
        sets.forbidden[b].insert(a);
    }

    let mut conflicts = Vec::new();
    for (a, b) in pairs(ConstraintKind::MustLink) {
        let (ra, rb) = (sets.find(a), sets.find(b));
        if ra == rb {
            note(sorted[a].0, 1.0);
            note(sorted[b].0, 1.0);
            continue;
        }
        if sets.forbids(ra, rb) {
            conflicts.push(Constraint {
                a: sorted[a].0,
                b: sorted[b].0,
                kind: ConstraintKind::MustLink,
            });
            continue;
        }
        sets.union(ra, rb);
        note(sorted[a].0, 1.0);
        note(sorted[b].0, 1.0);
    }

    let mut ordered: Vec<(f64, usize, usize)> = edges
        .iter()
        .filter_map(|e| Some((e.score, *index.get(&e.a)?, *index.get(&e.b)?)))
        .filter(|(_, a, b)| a != b)
        .map(|(s, a, b)| (s, a.min(b), a.max(b)))
        .collect();
    ordered.sort_by(|x, y| y.0.total_cmp(&x.0).then(x.1.cmp(&y.1)).then(x.2.cmp(&y.2)));
    for (score, a, b) in ordered {
        let (ra, rb) = (sets.find(a), sets.find(b));
        if ra == rb {
            // Already together: this edge still describes how well the two
            // records match, so it counts towards their link score.
            note(sorted[a].0, score);
            note(sorted[b].0, score);
            continue;
        }
        if sets.share_a_source(ra, rb) || sets.forbids(ra, rb) {
            continue;
        }
        sets.union(ra, rb);
        note(sorted[a].0, score);
        note(sorted[b].0, score);
    }

    let mut groups: BTreeMap<usize, Vec<K>> = BTreeMap::new();
    for (i, (key, _)) in sorted.iter().enumerate() {
        let r = sets.find(i);
        groups.entry(r).or_default().push(*key);
    }
    let mut groups: Vec<Vec<K>> = groups.into_values().collect();
    for g in &mut groups {
        g.sort_unstable();
    }
    groups.sort_by(|a, b| a[0].cmp(&b[0]));
    // One pass over the groups, not one per scored record: a country-wide
    // rebuild has tens of thousands of both.
    let grouped: BTreeSet<K> = groups
        .iter()
        .filter(|g| g.len() > 1)
        .flatten()
        .copied()
        .collect();
    link_score.retain(|k, _| grouped.contains(k));
    Clustering {
        groups,
        link_score,
        conflicts,
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    const OSM: SourceId = SourceId::OSM;
    const AF: SourceId = SourceId::ATOUT_FRANCE;
    const COM: SourceId = SourceId::COMMUNITY;

    fn e(a: u32, b: u32, score: f64) -> MergeEdge<u32> {
        MergeEdge { a, b, score }
    }

    fn c(a: u32, b: u32, kind: ConstraintKind) -> Constraint<u32> {
        Constraint { a, b, kind }
    }

    #[test]
    fn merge_edges_group_records_of_different_sources() {
        let records = [(1, &OSM), (2, &AF), (3, &COM), (4, &OSM)];
        let out = cluster(&records, &[e(1, 2, 0.9), e(2, 3, 0.95)], &[]);
        assert_eq!(out.groups, vec![vec![1, 2, 3], vec![4]]);
        assert_eq!(out.link_score.get(&1), Some(&0.9));
        assert_eq!(out.link_score.get(&2), Some(&0.95));
        assert_eq!(
            out.link_score.get(&4),
            None,
            "a record alone has no link score"
        );
    }

    #[test]
    fn a_chain_never_joins_two_records_of_one_source() {
        // 1 and 3 are both OSM: through 2 they would end in one place. The
        // stronger edge wins, the weaker one is refused.
        let records = [(1, &OSM), (2, &AF), (3, &OSM)];
        let out = cluster(&records, &[e(1, 2, 0.9), e(2, 3, 0.95)], &[]);
        assert_eq!(out.groups, vec![vec![1], vec![2, 3]]);
    }

    #[test]
    fn a_cannot_link_keeps_records_apart() {
        let records = [(1, &OSM), (2, &AF), (3, &COM)];
        let out = cluster(
            &records,
            &[e(1, 2, 0.99), e(2, 3, 0.9)],
            &[c(1, 3, ConstraintKind::CannotLink)],
        );
        assert_eq!(
            out.groups,
            vec![vec![1, 2], vec![3]],
            "3 may not join 1 through 2"
        );
    }

    #[test]
    fn a_must_link_joins_even_the_same_source() {
        let records = [(1, &OSM), (2, &OSM), (3, &AF)];
        let out = cluster(&records, &[], &[c(2, 1, ConstraintKind::MustLink)]);
        assert_eq!(out.groups, vec![vec![1, 2], vec![3]]);
        assert_eq!(out.link_score.get(&1), Some(&1.0));
    }

    #[test]
    fn contradictory_constraints_are_reported_not_applied() {
        let records = [(1, &OSM), (2, &AF), (3, &COM)];
        let out = cluster(
            &records,
            &[],
            &[
                c(1, 2, ConstraintKind::MustLink),
                c(2, 3, ConstraintKind::MustLink),
                c(1, 3, ConstraintKind::CannotLink),
            ],
        );
        assert_eq!(out.groups, vec![vec![1, 2], vec![3]]);
        assert_eq!(out.conflicts, vec![c(2, 3, ConstraintKind::MustLink)]);
    }

    #[test]
    fn unknown_keys_and_self_loops_are_ignored() {
        let records = [(1, &OSM), (2, &AF)];
        let out = cluster(
            &records,
            &[e(1, 9, 0.99), e(1, 1, 0.99)],
            &[c(2, 8, ConstraintKind::MustLink)],
        );
        assert_eq!(out.groups, vec![vec![1], vec![2]]);
    }

    #[test]
    fn a_country_sized_input_groups_in_near_linear_time() {
        // France has about 20 000 records in 15 000 places; a full rebuild
        // groups them all at once. 40 000 records in 20 000 pairs took tens
        // of seconds when the link scores were matched group by group.
        let n: u32 = 40_000;
        let records: Vec<(u32, &SourceId)> = (0..n)
            .map(|i| (i, if i % 2 == 0 { &OSM } else { &AF }))
            .collect();
        let edges: Vec<MergeEdge<u32>> = (0..n / 2).map(|i| e(2 * i, 2 * i + 1, 0.9)).collect();
        let started = std::time::Instant::now();
        let out = cluster(&records, &edges, &[]);
        let took = started.elapsed();
        assert_eq!(out.groups.len(), 20_000);
        assert_eq!(out.link_score.len(), 40_000);
        assert!(
            took < std::time::Duration::from_secs(5),
            "grouping a country must stay near linear: {took:?}"
        );
    }

    fn sources() -> [SourceId; 3] {
        [SourceId::OSM, SourceId::ATOUT_FRANCE, SourceId::COMMUNITY]
    }

    proptest! {
        #[test]
        fn groups_respect_the_rules_whatever_the_input_order(
            src in proptest::collection::vec(0usize..3, 1..12),
            raw_edges in proptest::collection::vec((0u32..12, 0u32..12, 0.85..1.0f64), 0..30),
            raw_cannot in proptest::collection::vec((0u32..12, 0u32..12), 0..4),
            seed: u64,
        ) {
            let all = sources();
            let records: Vec<(u32, &SourceId)> = src
                .iter()
                .enumerate()
                .map(|(i, s)| (u32::try_from(i).unwrap(), &all[*s]))
                .collect();
            let cannot: Vec<Constraint<u32>> = raw_cannot
                .iter()
                .map(|(a, b)| c(*a, *b, ConstraintKind::CannotLink))
                .collect();
            let edges: Vec<MergeEdge<u32>> = raw_edges.iter().map(|(a, b, s)| e(*a, *b, *s)).collect();
            let out = cluster(&records, &edges, &cannot);

            // Every record exactly once.
            let mut seen: Vec<u32> = out.groups.iter().flatten().copied().collect();
            seen.sort_unstable();
            let mut keys: Vec<u32> = records.iter().map(|(k, _)| *k).collect();
            keys.sort_unstable();
            prop_assert_eq!(seen, keys);

            for g in &out.groups {
                let mut srcs: Vec<&SourceId> = g.iter().map(|k| records[*k as usize].1).collect();
                let len = srcs.len();
                srcs.sort();
                srcs.dedup();
                prop_assert_eq!(srcs.len(), len, "an automatic group holds one record per source");
                for con in &cannot {
                    prop_assert!(!(con.a != con.b && g.contains(&con.a) && g.contains(&con.b)));
                }
            }

            // Shuffling the edges changes nothing.
            let mut shuffled = edges.clone();
            let len = shuffled.len();
            if len > 1 {
                let mut x = seed;
                for i in (1..len).rev() {
                    x = x.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1);
                    shuffled.swap(i, usize::try_from(x % (i as u64 + 1)).unwrap());
                }
            }
            for edge in &mut shuffled {
                std::mem::swap(&mut edge.a, &mut edge.b);
            }
            prop_assert_eq!(cluster(&records, &shuffled, &cannot), out);
        }
    }
}
