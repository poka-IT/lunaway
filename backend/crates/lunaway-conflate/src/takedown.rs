//! The catalogue's step of a takedown, journaled outside the database, and
//! its replay after a restore (docs/deploy.md, "Taking a place down" and
//! "Backups and restore").
//!
//! [`take_down`] conflates what waits (a record not read yet could become
//! the place again), then, under the writers' lock, empties the place and
//! keeps its exclusion zone (`lunaway_db::takedowns::take_down`), writes
//! the journal's line and syncs it, and only then commits: no takedown is
//! in the database without its line.
//!
//! [`replay`] reads the journal after a restore: it puts every zone's cells
//! back, conflates what waits with them in place, and takes down again
//! each journaled place the restored database holds alive. A place whose
//! family there holds a place the journal does not name (the one it is
//! merged into, or one merged into it) is left for the operator: an older
//! merge may join it to a neighbour, which the replay must not empty.
//! Running it again does nothing more.

use std::collections::BTreeSet;

use chrono::{DateTime, Utc};
use lunaway_db::{
    DbError, PgPool,
    conflation::begin_writer,
    takedown_journal::{Entry, JournalError, TakedownJournal},
    takedowns::{self, TakeDown, TakenDown},
};
use lunaway_domain::takedown::{TakedownCode, TakedownKey};
use uuid::Uuid;

use crate::ConflateError;

/// Why a takedown or its replay stopped.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum TakedownError {
    /// The database failed; nothing of the last transaction is kept.
    #[error(transparent)]
    Db(#[from] DbError),
    /// The conflation before it failed.
    #[error(transparent)]
    Conflate(#[from] ConflateError),
    /// The journal could not be written or read: nothing is taken down.
    #[error(transparent)]
    Journal(#[from] JournalError),
    /// Records near a journaled place arrived between the conflation and
    /// its takedown: run the replay again.
    #[error("{0} records near place {1} wait for the conflation: run the replay again")]
    Unconflated(i64, Uuid),
    /// The secret is not the one the journaled takedowns were made with.
    #[error(
        "LUNAWAY_TAKEDOWN_SECRET is not the secret the takedowns were made with: put the right \
         one back (its encrypted copy is in the backups) before taking anything down"
    )]
    OtherKey,
}

/// A takedown asked for.
#[derive(Debug, Clone, Copy)]
pub struct Request {
    /// The place named; a place merged into another names the other.
    pub place: Uuid,
    /// The kind of request, all the database and the journal keep of it:
    /// a free text could name the requester.
    pub code: TakedownCode,
    /// Also empties the retired records near it that name no place.
    pub with_nearby: bool,
}

/// Takes `request.place` down for good: the conflation of what waits, then
/// the takedown and its exclusion zone under the writers' lock, the
/// journal's line written and synced before the commit.
///
/// # Errors
///
/// [`TakedownError`] when the journal cannot be written (nothing is taken
/// down), the conflation or the database fails.
pub async fn take_down(
    pool: &PgPool,
    key: &TakedownKey,
    journal: &TakedownJournal,
    request: Request,
    now: DateTime<Utc>,
) -> Result<TakeDown, TakedownError> {
    journal.check_writable(now)?;
    crate::run(pool, now, Some(key)).await?;
    let mut tx = begin_writer(pool).await?;
    let done = takedowns::take_down(
        &mut tx,
        request.place,
        request.code,
        request.with_nearby,
        key,
    )
    .await?;
    if let TakeDown::Done(d) = &done {
        journal
            .record(Entry {
                places: d.family.clone(),
                taken_down_at: now,
                code: request.code,
                with_nearby: request.with_nearby,
                cells: d.cells.clone(),
                key_check: Some(key.check()),
            })
            .await?;
        if let Err(error) = tx.commit().await {
            // The journal names it: a replay applies it, and so does the
            // same command run again.
            tracing::error!(%error, "the takedown is journaled but was not committed");
            return Err(error.into());
        }
        publish_places_now(pool).await;
    }
    Ok(done)
}

/// A new version of the places' tiles, so a place taken down leaves every
/// tile at once instead of at the worker's next version. A failure is
/// logged and not returned: the takedown is committed, and the worker
/// publishes the change within `--place-layer-every-mins` anyway.
async fn publish_places_now(pool: &PgPool) {
    match lunaway_db::place_tiles::publish_layer_now(pool).await {
        Ok(version) => tracing::info!(version, "places layer: new tiles version"),
        Err(error) => tracing::error!(
            %error,
            "the places layer could not move to a new version; the worker publishes it later"
        ),
    }
}

/// What a replay found and did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Replayed {
    /// Takedowns the journal names.
    pub takedowns: usize,
    /// Lines that did not read.
    pub unreadable: usize,
    /// Cells put back (with `dry_run`, none).
    pub cells: u64,
    /// Places taken down again (with `dry_run`, those that would be).
    pub taken_down: Vec<TakenDown>,
    /// With `dry_run`, the places that would be taken down again.
    pub would_take_down: Vec<Uuid>,
    /// Journaled places already taken down.
    pub already: usize,
    /// Journaled places the restored database does not hold.
    pub absent: usize,
    /// Journaled places whose family in the restored database holds a
    /// place the journal does not name (the place it is merged into, or one
    /// merged into it), with that place: left for the operator.
    pub to_check: Vec<(Uuid, Uuid)>,
}

/// After a restore, puts back every journaled zone and takes down again
/// every journaled place the database holds alive, as the takedown did
/// (`--with-nearby` when it had it). With `dry_run`, writes nothing and
/// says what it would take down. A journal that names nothing is refused
/// unless `allow_empty`.
///
/// # Errors
///
/// [`TakedownError`] when the journal cannot be read or names nothing, the
/// conflation or the database fails, or records arrive meanwhile; what was
/// done stays, and running it again finishes the work.
pub async fn replay(
    pool: &PgPool,
    key: &TakedownKey,
    journal: &TakedownJournal,
    dry_run: bool,
    allow_empty: bool,
    now: DateTime<Utc>,
) -> Result<Replayed, TakedownError> {
    let read = journal.read_for_replay(allow_empty)?;
    let check = key.check();
    if read
        .entries
        .iter()
        .any(|e| e.key_check.is_some_and(|c| c != check))
    {
        return Err(TakedownError::OtherKey);
    }
    let mut out = Replayed {
        takedowns: read.entries.len(),
        unreadable: read.unreadable,
        ..Replayed::default()
    };
    if !dry_run {
        let mut tx = begin_writer(pool).await?;
        if !takedowns::adopt_key(&mut tx, key).await? {
            return Err(TakedownError::OtherKey);
        }
        for e in &read.entries {
            if let Some(root) = e.places.first() {
                out.cells += takedowns::insert_cells(&mut tx, *root, &e.cells).await?;
            }
        }
        tx.commit().await?;
        // With the cells back, a record restored unconflated near a spot
        // is held instead of made a place the journal cannot name.
        crate::run(pool, now, Some(key)).await?;
    }
    let mut seen = BTreeSet::new();
    for e in &read.entries {
        for id in &e.places {
            if !seen.insert(*id) {
                continue;
            }
            let Some(standing) = takedowns::standing(pool, *id).await? else {
                out.absent += 1;
                continue;
            };
            if standing.taken_down {
                out.already += 1;
                continue;
            }
            if let Some(stranger) = standing.family.iter().find(|p| !e.places.contains(p)) {
                out.to_check.push((*id, *stranger));
                continue;
            }
            if dry_run {
                out.would_take_down.push(standing.root);
                continue;
            }
            let mut tx = begin_writer(pool).await?;
            // The worker may have merged a place into the root since the
            // family was read: checked again under the writers' lock.
            if takedowns::family_in(&mut tx, standing.root).await? != standing.family {
                out.to_check.push((*id, standing.root));
                continue;
            }
            match takedowns::take_down(&mut tx, standing.root, e.code, e.with_nearby, key).await? {
                TakeDown::Done(d) => {
                    tx.commit().await?;
                    out.taken_down.push(d);
                }
                TakeDown::NoPlace => out.absent += 1,
                TakeDown::Unconflated(n) => {
                    publish_if_any(pool, &out).await;
                    return Err(TakedownError::Unconflated(n, *id));
                }
                TakeDown::OtherKey => {
                    publish_if_any(pool, &out).await;
                    return Err(TakedownError::OtherKey);
                }
            }
        }
    }
    publish_if_any(pool, &out).await;
    Ok(out)
}

/// One new version of the places' tiles for every place a replay took down
/// again, however many: each version makes devices fetch their tiles anew.
async fn publish_if_any(pool: &PgPool, out: &Replayed) {
    if !out.taken_down.is_empty() {
        publish_places_now(pool).await;
    }
}
