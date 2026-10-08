//! Lunaway conflation over the database: records of several sources that
//! describe one spot become one place, incrementally.
//!
//! A run, under the writers' lock:
//!
//! 0. writes the accepted community submissions (new places, edits) into
//!    records of the `community` source, flagged like any changed record;
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
//! 6. refreshes the opening intervals whose window is not today's;
//! 7. recomputes the community summary (ratings, photos, issues,
//!    verification) of the places the API queued, of the places holding a
//!    community record or waiting for verification that the run wrote, of
//!    the places that absorbed another, and of those showing an issue
//!    whose window passed.
//!
//! A group that would become a new place, or move a live place, inside
//! the cells of a place taken down is held for a moderator instead of
//! written (`lunaway_db::holds`); the key that hashes a position into a
//! cell comes with the run, and without it nothing is held.
//!
//! Steps 0, 1 to 6, and 7 are three writer transactions, so a write of the
//! API never waits for a whole conflation. The points of interest follow
//! ([`pois`]): the vending machines users added and their "still there?"
//! answers, then the opening intervals whose window is not today's, under
//! the POI writers' lock.
//!
//! Grouping a whole component again makes the result independent of the
//! history: an incremental run lands where a full rebuild would, and a run
//! with nothing flagged writes nothing.
//!
//! The database work stays on the async runtime; the scoring, the grouping,
//! the field resolution and the opening-hours evaluation (seconds of CPU on
//! a country) run on blocking threads, as pure functions of what was read.

pub mod opening;
pub mod pois;
pub mod takedown;

use std::collections::{BTreeMap, BTreeSet, HashMap};

use chrono::{DateTime, Utc};
use lunaway_db::{
    DbError, PgPool,
    community::WorkListener,
    conflation::{
        self as store, OpeningEval, PairRow, PlaceState, PlaceWrite, StoredRecord, WriterTx,
    },
    holds::{self, HoldKind, NewHold},
    submissions, summary, takedowns,
};
use lunaway_domain::{
    SourceId,
    conflation::{
        Constraint, ConstraintKind, Contribution, Decision, ExternalLink, FieldProvenance,
        LocalizedText, MatchCandidate, MergeEdge, PlaceContent, cluster, resolve,
        score::{ACCURACY_CAP_M, MAX_KIND_RADIUS_M, score},
    },
    takedown::{Exclusion, TakedownKey},
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
    /// Groups held back because their position is only a municipality's.
    pub held_back: usize,
    /// Groups held near a place taken down: a new place, or a live place
    /// moving into its cells.
    pub held_near_takedown: usize,
    /// Of them, holds new to the moderation queue.
    pub new_holds: u64,
    /// Records of holds a moderator released, flagged again.
    pub released_records: u64,
    /// Places whose opening intervals moved to today's window.
    pub opening_refreshed: usize,
    /// Community submissions written into records (new places, edits).
    pub submissions_applied: u64,
    /// Places whose community summary changed.
    pub community_refreshed: u64,
    /// The points of interest's community step.
    pub poi_community: pois::CommunityStats,
    /// The points of interest's opening hours.
    pub poi_hours: pois::HoursStats,
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

/// Runs the conflation for the records flagged in `pool`. `now` anchors the
/// opening-hours windows: each place's starts on its own local date. With
/// `key` (the takedown secret), a new or moving place inside a takedown's
/// cells is held; without it, none is.
///
/// # Errors
///
/// [`ConflateError`] when the database fails; the transaction is rolled back
/// and the flags stay, so the next run retries.
pub async fn run(
    pool: &PgPool,
    now: DateTime<Utc>,
    key: Option<&TakedownKey>,
) -> Result<RunStats, ConflateError> {
    let mut stats = RunStats::default();
    // Three short writer transactions rather than one: the API writes
    // `place_submissions` (a withdrawal, a deletion) and the refresh queue,
    // and must not wait for a whole conflation behind locks on those rows.
    let mut tx = store::begin_writer(pool).await?;
    let applied = submissions::apply_accepted(&mut tx).await?;
    tx.commit().await?;
    stats.submissions_applied = applied.created + applied.edited;

    let mut tx = store::begin_writer(pool).await?;
    stats.released_records = holds::requeue_released(&mut tx).await?;
    let dirty = store::dirty(&mut tx).await?;
    stats.dirty = dirty.len();
    if !dirty.is_empty() {
        let exclusion = match key {
            Some(k) if takedowns::is_takedown_key(&mut tx, k).await? => {
                let cells = takedowns::exclusion_cells(&mut tx).await?;
                (!cells.is_empty()).then(|| Exclusion::new(k.clone(), cells))
            }
            Some(_) => {
                tracing::error!(
                    "LUNAWAY_TAKEDOWN_SECRET is not the secret the takedowns were made with: \
                     no place is held near a place taken down"
                );
                None
            }
            None => None,
        };
        let changed = conflate(&mut tx, &dirty, now, exclusion, &mut stats).await?;
        store::clear_dirty(&mut tx, &dirty).await?;
        submissions::link_created_places(&mut tx).await?;
        let mut queued = changed.heirs;
        queued.extend(submissions::places_to_verify(&mut tx, &changed.written).await?);
        summary::queue(&mut tx, &queued).await?;
    }
    stats.opening_refreshed = refresh_opening(&mut tx, now).await?;
    tx.commit().await?;

    let mut tx = store::begin_writer(pool).await?;
    let mut to_refresh: BTreeSet<Uuid> = summary::take_queue(&mut tx).await?.into_iter().collect();
    to_refresh.extend(summary::with_expired_issues(&mut tx).await?);
    let to_refresh: Vec<Uuid> = to_refresh.into_iter().collect();
    stats.community_refreshed = summary::refresh(&mut tx, &to_refresh).await?;
    tx.commit().await?;

    // The points of interest, under their own lock: what the community
    // added or answered, then the hours whose window is not today's.
    stats.poi_community = pois::community(pool).await?;
    stats.poi_hours = pois::refresh_hours(pool, now).await?;
    tracing::info!(?stats, "conflation done");
    Ok(stats)
}

/// Runs the conflation whenever the API signals work (a contribution, a
/// submission, a moderation decision), and at least every `every` for the
/// imports and the daily opening hours. `now` gives the instant of each
/// run. After each run the points layer gets a new version when a change
/// waits and the last one is older than `poi_layer_every`, and the places
/// layer when a place was written since its version and that one is older
/// than `place_layer_every`. Errors are logged and the loop goes on after
/// `every`: a database restart must not stop the worker.
///
/// # Errors
///
/// [`ConflateError`] only when the first connection to listen fails.
pub async fn watch(
    pool: &PgPool,
    every: std::time::Duration,
    poi_layer_every: std::time::Duration,
    place_layer_every: std::time::Duration,
    now: impl Fn() -> DateTime<Utc>,
    key: Option<&TakedownKey>,
) -> Result<(), ConflateError> {
    let mut listener = WorkListener::connect(pool).await?;
    let settle = std::time::Duration::from_millis(300);
    loop {
        if let Err(error) = run(pool, now(), key).await {
            tracing::error!(%error, "conflation run failed; next attempt later");
        }
        if let Err(error) = pois::publish_layer(pool, poi_layer_every).await {
            tracing::error!(%error, "publishing the points layer failed; next attempt later");
        }
        if let Err(error) = publish_place_layer(pool, place_layer_every).await {
            tracing::error!(%error, "publishing the places layer failed; next attempt later");
        }
        match listener.wait(every, settle).await {
            Ok(woken) => tracing::debug!(woken, "conflation worker wakes"),
            Err(error) => {
                tracing::error!(%error, "listening for work failed");
                tokio::time::sleep(every).await;
            }
        }
    }
}

/// Publishes the places written since the current version of the places'
/// tiles as a new version, when the current one is older than `every`, and
/// then rebuilds the towns of the search from the places (also when none
/// is stored yet). Returns the new version.
///
/// # Errors
///
/// [`ConflateError`] when the database fails.
pub async fn publish_place_layer(
    pool: &PgPool,
    every: std::time::Duration,
) -> Result<Option<i64>, ConflateError> {
    let v = lunaway_db::place_tiles::publish_layer(pool, every).await?;
    if let Some(version) = v {
        tracing::info!(version, "places layer: new tiles version");
    }
    // The towns follow the same rhythm as the tiles: their counts move with
    // the places a new version publishes, and a rebuild reads every place.
    if v.is_some() || lunaway_db::towns::is_empty(pool).await? {
        let started = std::time::Instant::now();
        let s = lunaway_db::towns::refresh(pool).await?;
        tracing::info!(
            written = s.written,
            removed = s.removed,
            ms = started.elapsed().as_millis(),
            "towns of the search rebuilt"
        );
    }
    Ok(v)
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

/// The places a conflation step changed that the community summary may
/// depend on.
struct Changed {
    /// Places that absorbed a tombstoned one.
    heirs: Vec<Uuid>,
    /// Places written.
    written: Vec<Uuid>,
}

/// Conflates the records `dirty`.
async fn conflate(
    tx: &mut WriterTx,
    dirty: &[Uuid],
    now: DateTime<Utc>,
    exclusion: Option<Exclusion>,
    stats: &mut RunStats,
) -> Result<Changed, ConflateError> {
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
    let released: BTreeSet<Uuid> = if exclusion.is_some() {
        holds::released_among(tx, &affected_ids)
            .await?
            .into_iter()
            .collect()
    } else {
        BTreeSet::new()
    };
    let input = PlanInput {
        records,
        edges,
        constraints,
        current,
        states,
        now,
        exclusion,
        released,
    };
    let plan = blocking(move || plan(&input)).await??;
    stats.conflicts = plan.conflicts;
    stats.held_back = plan.held_back;
    stats.held_near_takedown = plan.holds.len();
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
                descriptions: &w.descriptions,
                external_links: &w.external_links,
                content_hash: &w.hash,
            },
        )
        .await?;
    }
    store::relink(tx, &plan.relink_records, &plan.links).await?;
    stats.new_holds = holds::record(tx, &plan.holds).await?;
    let mut heirs = Vec::new();
    for (old, heir) in &plan.tombstones {
        if store::tombstone(tx, *old, *heir).await? {
            stats.tombstoned += 1;
            heirs.extend(*heir);
        }
    }
    Ok(Changed {
        heirs,
        written: plan.writes.iter().map(|w| w.id).collect(),
    })
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
    /// The instant of the run, which gives each place the first day of its
    /// opening-hours window.
    pub now: DateTime<Utc>,
    /// The takedowns' cells and the key that hashes a position into one;
    /// `None` holds nothing.
    pub exclusion: Option<Exclusion>,
    /// Records of the set a moderator released from a hold: a group that
    /// holds one is written wherever it stands.
    pub released: BTreeSet<Uuid>,
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
    /// Every description, by language.
    pub descriptions: Vec<LocalizedText>,
    /// Pages about the place elsewhere.
    pub external_links: Vec<ExternalLink>,
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
    /// Groups placed only at a municipality's point, given no place.
    pub held_back: usize,
    /// Groups held near a place taken down, given no place (a new one) or
    /// left as they were (a move).
    pub holds: Vec<NewHold>,
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
    let mut place_of_group: Vec<Option<Uuid>> = Vec::with_capacity(groups.len());
    let mut group_of_record: HashMap<Uuid, usize> = HashMap::with_capacity(live.len());
    for (gi, g) in groups.iter().enumerate() {
        for r in *g {
            group_of_record.insert(*r, gi);
        }
        // A group placed only at a municipality's point is held back: on
        // 2026-10-06, 195 of the 225 Atout France campsites placed so had a
        // campsite of a close name mapped in OSM in the same commune, a few
        // kilometres from the town hall, too far for the conflation to see
        // the pair. Shown, they would be duplicates; held, the record still
        // enriches the place it merges with once an edit or a better
        // position brings it close enough.
        let approximate_only = g.iter().all(|r| {
            records_by_id
                .get(r)
                .is_some_and(|x| x.record.position_approximate)
        });
        if approximate_only {
            place_of_group.push(None);
            out.held_back += 1;
            continue;
        }
        let mut counts: BTreeMap<Uuid, usize> = BTreeMap::new();
        for r in *g {
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
        place_of_group.push(Some(place));
    }

    out.relink_records = input
        .records
        .iter()
        .filter(|r| r.deleted)
        .map(|r| r.id)
        .collect();
    // Groups held near a place taken down, and the live places their
    // records still describe: a held group changes no place, so it is no
    // heir and none of those places becomes a tombstone because of it.
    let mut held: BTreeSet<usize> = BTreeSet::new();
    let mut kept_live: BTreeSet<Uuid> = BTreeSet::new();
    for (gi, g) in groups.iter().enumerate() {
        let Some(place) = place_of_group[gi] else {
            // Held back: its records lose any place they had.
            out.relink_records.extend(g.iter().copied());
            continue;
        };
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
                external_url: r.external_url.as_deref(),
                record: &r.record,
            })
            .collect();
        let Some(mut resolved) = resolve(&contributions) else {
            continue;
        };
        // A place only the community describes has no address: its country
        // comes from its position (the boundaries `country-boundaries`
        // embeds), so it gets a time zone and a sync region. No source
        // supplied it, so it gets no provenance entry.
        if resolved.content.address.country_code.is_none() {
            resolved.content.address.country_code =
                lunaway_domain::region::country_at(resolved.content.position).map(str::to_owned);
        }
        if let Some(kind) = held_near_takedown(input, place, g, &resolved.content) {
            held.insert(gi);
            for r in *g {
                let Some(cur) = input.current.get(r) else {
                    continue;
                };
                let live = input.states.get(cur).is_some_and(|s| !s.deleted);
                let own = kind == HoldKind::Move && *cur == place;
                if own || (live && !claimed.contains(cur)) {
                    // The moved place, or a live place no other group
                    // takes: it keeps this record, as it was.
                    kept_live.insert(*cur);
                } else {
                    // A tombstone (one a new place would have revived), or
                    // a place another group takes: the record leaves it.
                    out.relink_records.push(*r);
                }
            }
            out.holds.push(NewHold {
                kind,
                place: (kind == HoldKind::Move).then_some(place),
                records: g.to_vec(),
            });
            continue;
        }
        let group_links: Vec<(Uuid, Uuid, Option<f64>)> = g
            .iter()
            .map(|r| (*r, place, clustering.link_score.get(r).copied()))
            .collect();
        let hash = digest(&resolved, &group_links)?;
        match input.states.get(&place) {
            Some(s) if !s.deleted && s.content_hash == hash => {
                out.unchanged += 1;
                continue;
            }
            Some(_) => out.updated += 1,
            None => out.created += 1,
        }
        let opening = opening::evaluate_at(
            resolved.content.opening_hours.as_deref(),
            resolved.content.address.country_code.as_deref(),
            resolved.content.position,
            input.now,
        );
        out.relink_records.extend(g.iter().copied());
        out.links.extend(group_links);
        out.writes.push(PlannedPlace {
            id: place,
            content: resolved.content,
            provenance: resolved.provenance,
            opening,
            descriptions: resolved.descriptions,
            external_links: resolved.external_links,
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
        if let Some(heir) = group_of_record
            .get(record)
            .filter(|gi| !held.contains(*gi))
            .and_then(|gi| place_of_group[*gi])
        {
            *heirs.entry(*old).or_default().entry(heir).or_default() += 1;
        }
    }
    for old in old_places
        .difference(&claimed)
        .filter(|p| !kept_live.contains(*p))
    {
        let heir = heirs.get(old).and_then(|h| {
            h.iter()
                .max_by(|x, y| x.1.cmp(y.1).then(y.0.cmp(x.0)))
                .map(|(p, _)| *p)
        });
        out.tombstones.push((*old, heir));
    }
    Ok(out)
}

/// Whether the group `g`, resolved into `content` for `place`, is held near
/// a place taken down, and why: it lands inside a takedown's cells as a new
/// place (or a tombstone coming back), or moves a live place into one of
/// them, from outside or from another cell (a neighbour's element dragged
/// onto the spot). A live place that stays in its cell (a neighbour the
/// takedown left, edited) is not held, nor a group a moderator released.
fn held_near_takedown(
    input: &PlanInput,
    place: Uuid,
    g: &[Uuid],
    content: &PlaceContent,
) -> Option<HoldKind> {
    let ex = input.exclusion.as_ref()?;
    if !ex.covers(content.position) || g.iter().any(|r| input.released.contains(r)) {
        return None;
    }
    match input.states.get(&place).filter(|s| !s.deleted) {
        None => Some(HoldKind::Create),
        Some(s)
            if s.position
                .is_some_and(|old| ex.covers(old) && ex.same_cell(old, content.position)) =>
        {
            None
        }
        Some(_) => Some(HoldKind::Move),
    }
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

/// Digest of what a client sees of a place: its values, their provenance,
/// its descriptions and links, and its records with their scores.
fn digest(
    resolved: &lunaway_domain::conflation::ResolvedPlace,
    links: &[(Uuid, Uuid, Option<f64>)],
) -> Result<String, ConflateError> {
    let mut sorted: Vec<(Uuid, Option<f64>)> = links.iter().map(|l| (l.0, l.2)).collect();
    sorted.sort_by_key(|l| l.0);
    let json = serde_json::to_vec(&(
        &resolved.content,
        &resolved.provenance,
        &resolved.descriptions,
        &resolved.external_links,
        sorted,
    ))
    .map_err(ConflateError::Digest)?;
    Ok(Sha256::digest(&json)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

async fn refresh_opening(tx: &mut WriterTx, now: DateTime<Utc>) -> Result<usize, ConflateError> {
    let stale = store::stale_openings(tx, now).await?;
    let evaluated = blocking(move || {
        stale
            .into_iter()
            .map(|s| {
                let eval = opening::evaluate_at(
                    Some(&s.opening_hours),
                    s.country_code.as_deref(),
                    s.position,
                    now,
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
