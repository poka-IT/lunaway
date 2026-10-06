//! Lunaway conflation over the database: records of several sources that
//! describe one spot become one place, incrementally.
//!
//! A run, in one transaction under the writers' lock:
//!
//! 1. takes the records flagged since the last run (new, changed, retired,
//!    or under a new human constraint);
//! 2. scores each of them against the live records within reach (the
//!    domain's [`score`](lunaway_domain::conflation::score)) and stores the
//!    merge and review decisions;
//! 3. grows the set of affected records to whole components: everything
//!    joined to it by a merge decision, a `must_link`, or a shared place;
//! 4. groups that set again (the domain's union-find) and gives each group a
//!    place, keeping the place most of its records already had;
//! 5. resolves each place's fields and writes only the places whose content
//!    or records changed; places left without records become tombstones
//!    pointing to the place that absorbed them;
//! 6. refreshes the opening intervals whose window is not today's.
//!
//! Grouping a whole component again makes the result independent of the
//! history: an incremental run lands where a full rebuild would, and a run
//! with nothing flagged writes nothing.
//!
//! The database work stays on the async runtime; the scoring, the grouping,
//! the field resolution and the opening-hours evaluation (seconds of CPU on
//! a country) run on blocking threads, as pure functions of what was read.

pub mod opening;

use std::collections::{BTreeMap, BTreeSet, HashMap};

use chrono::NaiveDate;
use lunaway_db::{
    DbError, PgPool,
    conflation::{
        self as store, OpeningEval, PairRow, PlaceState, PlaceWrite, StoredRecord, WriterTx,
    },
};
use lunaway_domain::{
    SourceId,
    conflation::{
        Constraint, ConstraintKind, Contribution, Decision, FieldProvenance, MatchCandidate,
        MergeEdge, PlaceContent, cluster, resolve,
        score::{ACCURACY_CAP_M, MAX_KIND_RADIUS_M, score},
    },
};
use sha2::{Digest, Sha256};
use uuid::Uuid;

/// What can go wrong during a run.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ConflateError {
    /// The database failed.
    #[error(transparent)]
    Db(#[from] DbError),
    /// A value could not be serialised for the content digest.
    #[error("cannot serialise a place for its digest")]
    Digest(#[source] serde_json::Error),
    /// A blocking computation panicked or was cancelled.
    #[error("a conflation computation failed")]
    Blocking(#[source] tokio::task::JoinError),
}

/// What a run did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RunStats {
    /// Records flagged at the start.
    pub dirty: usize,
    /// Pairs scored.
    pub scored: usize,
    /// Of which merge decisions.
    pub merges: usize,
    /// Of which review decisions.
    pub reviews: usize,
    /// Records in the components grouped again.
    pub affected: usize,
    /// Places created.
    pub created: usize,
    /// Places rewritten.
    pub updated: usize,
    /// Places whose recomputation changed nothing.
    pub unchanged: usize,
    /// Places turned into tombstones.
    pub tombstoned: usize,
    /// Contradictory human constraints left unapplied.
    pub conflicts: usize,
    /// Places whose opening intervals moved to today's window.
    pub opening_refreshed: usize,
}

/// Runs `f` on a blocking thread: CPU work over a millisecond must not hold
/// an async worker.
async fn blocking<T: Send + 'static>(
    f: impl FnOnce() -> T + Send + 'static,
) -> Result<T, ConflateError> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(ConflateError::Blocking)
}

/// Runs the conflation for the records flagged in `pool`. `today` anchors the
/// opening-hours window (the local date of the run).
///
/// # Errors
///
/// [`ConflateError`] when the database fails; the transaction is rolled back
/// and the flags stay, so the next run retries.
pub async fn run(pool: &PgPool, today: NaiveDate) -> Result<RunStats, ConflateError> {
    let mut tx = store::begin_writer(pool).await?;
    let mut stats = RunStats::default();
    let dirty = store::dirty(&mut tx).await?;
    stats.dirty = dirty.len();
    if !dirty.is_empty() {
        conflate(&mut tx, &dirty, today, &mut stats).await?;
        store::clear_dirty(&mut tx, &dirty).await?;
    }
    stats.opening_refreshed = refresh_opening(&mut tx, today).await?;
    tx.commit().await?;
    tracing::info!(?stats, "conflation done");
    Ok(stats)
}

/// The pairs worth storing among `candidate_pairs`, and how many were
/// scored, merged and sent to review.
fn score_pairs(
    by_id: &BTreeMap<Uuid, StoredRecord>,
    candidate_pairs: &[(Uuid, Uuid)],
) -> (Vec<PairRow>, usize, usize, usize) {
    let prepared: BTreeMap<Uuid, MatchCandidate> = by_id
        .iter()
        .map(|(id, r)| (*id, MatchCandidate::new(&r.source_id, &r.record)))
        .collect();
    let unique_pairs: BTreeSet<(Uuid, Uuid)> = candidate_pairs
        .iter()
        .map(|&(a, b)| if a < b { (a, b) } else { (b, a) })
        .collect();
    let (mut scored, mut merges, mut reviews) = (0, 0, 0);
    let mut kept = Vec::new();
    for (a, b) in unique_pairs {
        let (Some(ca), Some(cb)) = (prepared.get(&a), prepared.get(&b)) else {
            continue;
        };
        scored += 1;
        let s = score(ca, cb);
        match s.decision {
            Decision::Merge => merges += 1,
            Decision::Review => reviews += 1,
            Decision::Distinct => continue,
        }
        kept.push(PairRow { a, b, score: s });
    }
    (kept, scored, merges, reviews)
}

async fn conflate(
    tx: &mut WriterTx,
    dirty: &[Uuid],
    today: NaiveDate,
    stats: &mut RunStats,
) -> Result<(), ConflateError> {
    // 2. Score the flagged records against everything within reach.
    let dirty_records = store::records(tx, dirty).await?;
    let live_dirty: Vec<Uuid> = dirty_records
        .iter()
        .filter(|r| !r.deleted)
        .map(|r| r.id)
        .collect();
    let candidate_pairs =
        store::candidates(tx, &live_dirty, MAX_KIND_RADIUS_M, ACCURACY_CAP_M).await?;
    let mut involved: BTreeSet<Uuid> = live_dirty.iter().copied().collect();
    involved.extend(candidate_pairs.iter().map(|(_, b)| *b));
    let involved: Vec<Uuid> = involved.into_iter().collect();
    let by_id: BTreeMap<Uuid, StoredRecord> = store::records(tx, &involved)
        .await?
        .into_iter()
        .map(|r| (r.id, r))
        .collect();
    let (kept, scored, merges, reviews) =
        blocking(move || score_pairs(&by_id, &candidate_pairs)).await?;
    stats.scored = scored;
    stats.merges = merges;
    stats.reviews = reviews;
    store::delete_pairs(tx, dirty).await?;
    store::insert_pairs(tx, &kept).await?;

    // 3. Grow to whole components.
    let affected = component_closure(tx, dirty).await?;
    stats.affected = affected.len();
    let affected_ids: Vec<Uuid> = affected.iter().copied().collect();

    // 4. Read what grouping again needs, then group and resolve.
    let records = store::records(tx, &affected_ids).await?;
    let edges: Vec<MergeEdge<Uuid>> = store::merge_edges(tx, &affected_ids)
        .await?
        .into_iter()
        .filter(|(a, b, _)| affected.contains(a) && affected.contains(b))
        .map(|(a, b, score)| MergeEdge { a, b, score })
        .collect();
    let constraints: Vec<Constraint<Uuid>> = store::constraints(tx, &affected_ids)
        .await?
        .into_iter()
        .filter(|(a, b, _)| affected.contains(a) && affected.contains(b))
        .map(|(a, b, kind)| Constraint { a, b, kind })
        .collect();
    // Which place each affected record belongs to today.
    let current: BTreeMap<Uuid, Uuid> = store::places_of_records(tx, &affected_ids)
        .await?
        .into_iter()
        .collect();
    let old_place_ids: Vec<Uuid> = current
        .values()
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    let states: BTreeMap<Uuid, PlaceState> = store::place_states(tx, &old_place_ids)
        .await?
        .into_iter()
        .map(|s| (s.id, s))
        .collect();
    let input = PlanInput {
        records,
        edges,
        constraints,
        current,
        states,
        today,
    };
    let plan = blocking(move || plan(&input)).await??;
    stats.conflicts = plan.conflicts;
    stats.created = plan.created;
    stats.updated = plan.updated;
    stats.unchanged = plan.unchanged;

    // 5. Write what changed.
    for w in &plan.writes {
        store::upsert_place(
            tx,
            PlaceWrite {
                id: w.id,
                content: &w.content,
                provenance: &w.provenance,
                opening: &w.opening,
                content_hash: &w.hash,
            },
        )
        .await?;
    }
    store::relink(tx, &plan.relink_records, &plan.links).await?;
    for (old, heir) in &plan.tombstones {
        if store::tombstone(tx, *old, *heir).await? {
            stats.tombstoned += 1;
        }
    }
    Ok(())
}

/// What the grouping of a set of records starts from.
#[derive(Debug, Clone)]
pub struct PlanInput {
    /// The records of the set, live and retired.
    pub records: Vec<StoredRecord>,
    /// Stored merge decisions between records of the set.
    pub edges: Vec<MergeEdge<Uuid>>,
    /// Human constraints between records of the set.
    pub constraints: Vec<Constraint<Uuid>>,
    /// The place each record of the set belongs to now.
    pub current: BTreeMap<Uuid, Uuid>,
    /// The state of those places.
    pub states: BTreeMap<Uuid, PlaceState>,
    /// The first day of the opening-hours window.
    pub today: NaiveDate,
}

/// A place to write.
#[derive(Debug, Clone)]
pub struct PlannedPlace {
    /// Its id, kept from an existing place or new.
    pub id: Uuid,
    /// Resolved values.
    pub content: PlaceContent,
    /// Which source supplied each value.
    pub provenance: Vec<FieldProvenance>,
    /// Evaluated opening hours.
    pub opening: OpeningEval,
    /// Digest of content and records.
    pub hash: String,
}

/// What a grouping decided: the writes, the links and the tombstones.
#[derive(Debug, Clone, Default)]
pub struct Plan {
    /// Places whose content or records changed.
    pub writes: Vec<PlannedPlace>,
    /// Records whose links are replaced: the retired ones and the members
    /// of every written place.
    pub relink_records: Vec<Uuid>,
    /// New links: record, place, score.
    pub links: Vec<(Uuid, Uuid, Option<f64>)>,
    /// Places no group kept, with the place that absorbed most of their
    /// records, if any.
    pub tombstones: Vec<(Uuid, Option<Uuid>)>,
    /// Places created.
    pub created: usize,
    /// Places rewritten.
    pub updated: usize,
    /// Places left as they were.
    pub unchanged: usize,
    /// Contradictory human constraints left unapplied.
    pub conflicts: usize,
}

/// Groups `input`'s records and resolves each group into a place: a pure
/// function of what was read, run on a blocking thread.
///
/// # Errors
///
/// [`ConflateError::Digest`] when a place cannot be serialised for its
/// digest.
pub fn plan(input: &PlanInput) -> Result<Plan, ConflateError> {
    let live: Vec<&StoredRecord> = input.records.iter().filter(|r| !r.deleted).collect();
    let nodes: Vec<(Uuid, &SourceId)> = live.iter().map(|r| (r.id, &r.source_id)).collect();
    let clustering = cluster(&nodes, &input.edges, &input.constraints);
    let mut out = Plan {
        conflicts: clustering.conflicts.len(),
        ..Plan::default()
    };
    for c in &clustering.conflicts {
        tracing::warn!(a = %c.a, b = %c.b, "must_link refused: it would join a cannot_link pair");
    }
    let old_places: BTreeSet<Uuid> = input.current.values().copied().collect();

    // Bigger groups choose first: when a place splits, its id stays with the
    // part that kept most of its records.
    let mut groups: Vec<&Vec<Uuid>> = clustering.groups.iter().collect();
    groups.sort_by(|x, y| y.len().cmp(&x.len()).then(x[0].cmp(&y[0])));
    let records_by_id: BTreeMap<Uuid, &StoredRecord> = live.iter().map(|r| (r.id, *r)).collect();
    let mut claimed: BTreeSet<Uuid> = BTreeSet::new();
    let mut place_of_group: Vec<Uuid> = Vec::with_capacity(groups.len());
    let mut group_of_record: HashMap<Uuid, usize> = HashMap::with_capacity(live.len());
    for (gi, g) in groups.iter().enumerate() {
        let mut counts: BTreeMap<Uuid, usize> = BTreeMap::new();
        for r in *g {
            group_of_record.insert(*r, gi);
            if let Some(p) = input.current.get(r) {
                *counts.entry(*p).or_default() += 1;
            }
        }
        let mut options: Vec<(usize, Uuid)> = counts
            .into_iter()
            .filter(|(p, _)| !claimed.contains(p))
            .map(|(p, n)| (n, p))
            .collect();
        options.sort_by(|x, y| y.0.cmp(&x.0).then(x.1.cmp(&y.1)));
        let place = options.first().map_or_else(Uuid::now_v7, |(_, p)| *p);
        claimed.insert(place);
        place_of_group.push(place);
    }

    out.relink_records = input
        .records
        .iter()
        .filter(|r| r.deleted)
        .map(|r| r.id)
        .collect();
    for (gi, g) in groups.iter().enumerate() {
        let place = place_of_group[gi];
        let members: Vec<&StoredRecord> = g
            .iter()
            .filter_map(|id| records_by_id.get(id).copied())
            .collect();
        let contributions: Vec<Contribution<'_>> = members
            .iter()
            .map(|r| Contribution {
                source: &r.source_id,
                external_id: &r.external_id,
                fetched_at: r.fetched_at,
                record: &r.record,
            })
            .collect();
        let Some(resolved) = resolve(&contributions) else {
            continue;
        };
        let group_links: Vec<(Uuid, Uuid, Option<f64>)> = g
            .iter()
            .map(|r| (*r, place, clustering.link_score.get(r).copied()))
            .collect();
        let hash = digest(&resolved.content, &resolved.provenance, &group_links)?;
        match input.states.get(&place) {
            Some(s) if !s.deleted && s.content_hash == hash => {
                out.unchanged += 1;
                continue;
            }
            Some(_) => out.updated += 1,
            None => out.created += 1,
        }
        let opening = opening::evaluate(
            resolved.content.opening_hours.as_deref(),
            resolved.content.address.country_code.as_deref(),
            resolved.content.position,
            input.today,
        );
        out.relink_records.extend(g.iter().copied());
        out.links.extend(group_links);
        out.writes.push(PlannedPlace {
            id: place,
            content: resolved.content,
            provenance: resolved.provenance,
            opening,
            hash,
        });
    }

    // Places that no group kept: absorbed by the group that took most of
    // their records, or gone with them. One pass over the records, not one
    // per vanished place.
    let mut heirs: BTreeMap<Uuid, BTreeMap<Uuid, usize>> = BTreeMap::new();
    for (record, old) in &input.current {
        if claimed.contains(old) {
            continue;
        }
        if let Some(gi) = group_of_record.get(record) {
            *heirs
                .entry(*old)
                .or_default()
                .entry(place_of_group[*gi])
                .or_default() += 1;
        }
    }
    for old in old_places.difference(&claimed) {
        let heir = heirs.get(old).and_then(|h| {
            h.iter()
                .max_by(|x, y| x.1.cmp(y.1).then(y.0.cmp(x.0)))
                .map(|(p, _)| *p)
        });
        out.tombstones.push((*old, heir));
    }
    Ok(out)
}

/// The dirty records plus everything joined to them by a merge decision, a
/// `must_link` or a shared place, transitively.
async fn component_closure(
    tx: &mut WriterTx,
    seeds: &[Uuid],
) -> Result<BTreeSet<Uuid>, ConflateError> {
    let mut all: BTreeSet<Uuid> = seeds.iter().copied().collect();
    let mut frontier: Vec<Uuid> = seeds.to_vec();
    while !frontier.is_empty() {
        let mut next: BTreeSet<Uuid> = BTreeSet::new();
        for (a, b, _) in store::merge_edges(tx, &frontier).await? {
            next.extend([a, b]);
        }
        for (a, b, kind) in store::constraints(tx, &frontier).await? {
            if kind == ConstraintKind::MustLink {
                next.extend([a, b]);
            }
        }
        let places: Vec<Uuid> = store::places_of_records(tx, &frontier)
            .await?
            .into_iter()
            .map(|(_, p)| p)
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        for (r, _) in store::records_of_places(tx, &places).await? {
            next.insert(r);
        }
        frontier = next.into_iter().filter(|r| all.insert(*r)).collect();
    }
    Ok(all)
}

/// Digest of what a client sees of a place: its values, their provenance
/// and its records with their scores.
fn digest(
    content: &PlaceContent,
    provenance: &[FieldProvenance],
    links: &[(Uuid, Uuid, Option<f64>)],
) -> Result<String, ConflateError> {
    let mut sorted: Vec<(Uuid, Option<f64>)> = links.iter().map(|l| (l.0, l.2)).collect();
    sorted.sort_by_key(|l| l.0);
    let json = serde_json::to_vec(&(content, provenance, sorted)).map_err(ConflateError::Digest)?;
    Ok(Sha256::digest(&json)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

async fn refresh_opening(tx: &mut WriterTx, today: NaiveDate) -> Result<usize, ConflateError> {
    let stale = store::stale_openings(tx, today).await?;
    let evaluated = blocking(move || {
        stale
            .into_iter()
            .map(|s| {
                let eval = opening::evaluate(
                    Some(&s.opening_hours),
                    s.country_code.as_deref(),
                    s.position,
                    today,
                );
                let differs = s.intervals != eval.intervals || s.until != eval.until;
                (s.id, eval, differs)
            })
            .collect::<Vec<_>>()
    })
    .await?;
    let mut changed = 0;
    for (id, eval, differs) in &evaluated {
        store::set_opening(tx, *id, eval, *differs).await?;
        if *differs {
            changed += 1;
        }
    }
    Ok(changed)
}
