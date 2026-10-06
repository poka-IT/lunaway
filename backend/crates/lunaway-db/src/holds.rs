//! Places held near a place taken down (`place_holds`).
//!
//! The conflation hashes the cell of each place it would create, and of
//! each live place it would move out of the takedowns' cells into them,
//! with the takedown secret; when the hash is one of a takedown's cells
//! (`takedown_cells`), it writes no place and records the group of records
//! here, with an entry in the moderation queue ("near a taken-down place").
//! Nothing is dropped: the records stay, and the hold names them.
//!
//! A moderator who releases the hold (`lunaway moderation approve`: an
//! owner who now welcomes vans) journals the release
//! (`place_hold_releases`); the worker's next run flags the hold's records
//! for the conflation ([`requeue_released`]), and a group holding a
//! released record is no longer held ([`released_among`]); both read a
//! release only through its journal row. A rejected hold stays held, and
//! its queue entry is not opened again: records that join it later wait
//! with it.

use lunaway_domain::SourceId;
use uuid::Uuid;

use crate::{DbError, PgPool, conflation::WriterTx};

/// The reason of a hold's queue entry.
pub const REASON: &str = "near a taken-down place";

/// Why a group is held.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HoldKind {
    /// It would become a new place.
    Create,
    /// It would move a live place into a takedown's cells.
    Move,
}

impl HoldKind {
    const fn code(self) -> &'static str {
        match self {
            Self::Create => "create",
            Self::Move => "move",
        }
    }
}

/// A group the conflation held.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewHold {
    /// Why.
    pub kind: HoldKind,
    /// The live place a move would have moved.
    pub place: Option<Uuid>,
    /// The group's live records.
    pub records: Vec<Uuid>,
}

/// Flags for the conflation the records of every hold released since the
/// worker last looked, so the run that follows writes the place. Returns
/// how many records.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn requeue_released(tx: &mut WriterTx) -> Result<u64, DbError> {
    let done = sqlx::query!(
        r#"
        WITH due AS (
            UPDATE place_holds h SET requeued_at = now()
            WHERE h.status = 'released' AND h.requeued_at IS NULL
              AND EXISTS (SELECT 1 FROM place_hold_releases r WHERE r.hold_id = h.id)
            RETURNING h.records
        )
        UPDATE source_records SET needs_conflation = true
        WHERE id IN (SELECT unnest(records) FROM due) AND taken_down_at IS NULL
        "#
    )
    .execute(tx.conn())
    .await?;
    Ok(done.rows_affected())
}

/// Of `ids`, the records a moderator released.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn released_among(tx: &mut WriterTx, ids: &[Uuid]) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT DISTINCT r AS "r!" FROM place_holds h, unnest(h.records) AS r
        WHERE h.status = 'released' AND h.records && $1::uuid[] AND r = ANY($1)
          AND EXISTS (SELECT 1 FROM place_hold_releases x WHERE x.hold_id = h.id)
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?)
}

/// Records the groups the conflation held. A hold that shares a record
/// with the group takes its records and kind: an open one stays in the
/// queue, a rejected one stays out of it. Otherwise a new hold enters the
/// queue, with the author of a community record of the group when there
/// is one. Returns how many holds are new.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn record(tx: &mut WriterTx, holds: &[NewHold]) -> Result<u64, DbError> {
    let mut new = 0;
    for h in holds {
        // Locked, so a moderator's decision lands before or after the
        // rewrite of its records, never in between.
        let existing = sqlx::query_scalar!(
            r#"
            SELECT id FROM place_holds
            WHERE records && $1::uuid[] AND status <> 'released'
            ORDER BY status = 'held' DESC, id
            LIMIT 1
            FOR UPDATE
            "#,
            &h.records,
        )
        .fetch_optional(tx.conn())
        .await?;
        if let Some(id) = existing {
            sqlx::query!(
                r#"
                UPDATE place_holds SET kind = $2, place_id = $3, records = $4, updated_at = now()
                WHERE id = $1 AND status <> 'released'
                "#,
                id,
                h.kind.code(),
                h.place,
                &h.records,
            )
            .execute(tx.conn())
            .await?;
            continue;
        }
        let id = Uuid::now_v7();
        sqlx::query!(
            r#"
            INSERT INTO place_holds (id, kind, place_id, records) VALUES ($1, $2, $3, $4)
            "#,
            id,
            h.kind.code(),
            h.place,
            &h.records,
        )
        .execute(tx.conn())
        .await?;
        sqlx::query!(
            r#"
            INSERT INTO moderation_queue (id, kind, target_type, target_id, account_id, reason)
            SELECT $1, 'place_hold', 'place_hold', $2,
                   (SELECT s.account_id FROM place_submissions s
                    JOIN source_records r ON r.id = s.record_id
                    WHERE s.record_id = ANY($3) AND r.source_id = $4
                    ORDER BY s.id LIMIT 1),
                   $5
            ON CONFLICT DO NOTHING
            "#,
            Uuid::now_v7(),
            id,
            &h.records,
            SourceId::COMMUNITY.as_str(),
            REASON,
        )
        .execute(tx.conn())
        .await?;
        new += 1;
    }
    Ok(new)
}

/// Holds waiting for a moderator.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn open_count(pool: &PgPool) -> Result<i64, DbError> {
    Ok(
        sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM place_holds WHERE status = 'held'"#)
            .fetch_one(pool)
            .await?,
    )
}
