//! New places and place edits.
//!
//! The API stores a submission (`accepted` when the contributor's level
//! allows it, `proposed` for a moderator otherwise); it never writes the
//! catalogue. The conflation worker, under the writers' lock and with the
//! import role, turns each accepted submission into a record of the
//! `community` source:
//!
//! - a new place gets a record of its own (`submission/<id>`), which the
//!   conflation merges with what other sources say of the same spot, or
//!   makes a place of;
//! - an edit patches the place's community record, or creates one
//!   (`place/<id>`) tied to the place by a `must_link`, so the edit lands on
//!   that place whatever its score against the other records.
//!
//! The rows stay as the revision history: who, from which device key, what,
//! and when it was applied.

use chrono::{DateTime, Utc};
use lunaway_domain::{
    NormalizedRecord, PlaceKind, Position, SourceId,
    community::submission::{self, NewPlace, PlacePatch},
    poi::NewVendingMachine,
};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    community::{enqueue, notify_worker},
    conflation::WriterTx,
    idempotency::{self, Key, Once},
};

/// A submission as stored.
#[derive(Debug, Clone, PartialEq)]
pub struct SubmissionRow {
    /// Its id.
    pub id: Uuid,
    /// `create`, `edit`, or `poi` for a vending machine.
    pub kind: String,
    /// The place an edit targets, or the place a creation became.
    pub place_id: Option<Uuid>,
    /// The point of interest a vending machine became.
    pub poi_id: Option<Uuid>,
    /// `proposed`, `accepted`, `applied`, `rejected` or `withdrawn`.
    pub status: String,
    /// What it says.
    pub payload: serde_json::Value,
    /// When it was sent.
    pub created_at: DateTime<Utc>,
    /// When the worker applied it.
    pub applied_at: Option<DateTime<Utc>>,
}

/// What the API stores.
#[derive(Debug, Clone, Copy)]
pub struct NewSubmission<'a> {
    /// Its author.
    pub account: Uuid,
    /// The device key of the author's session.
    pub device_key: Uuid,
    /// The new place, or the edit and its live place.
    pub what: Submitted<'a>,
    /// Applied without review (the author's level allows it, and the
    /// automatic rules found nothing).
    pub accepted: bool,
    /// Why it waits for a moderator, when it does.
    pub held_for: Option<&'a str>,
}

/// The content of a submission.
#[derive(Debug, Clone, Copy)]
pub enum Submitted<'a> {
    /// A new place.
    Create(&'a NewPlace),
    /// A new vending machine, written as a point of interest.
    Poi(&'a NewVendingMachine),
    /// An edit of a live place.
    Edit {
        /// The place.
        place: Uuid,
        /// The changes.
        patch: &'a PlacePatch,
    },
}

/// Stores a submission; an accepted one wakes the worker, a proposed one
/// enters the moderation queue.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn submit(pool: &PgPool, s: NewSubmission<'_>) -> Result<SubmissionRow, DbError> {
    let mut tx = pool.begin().await?;
    let row = submit_in(&mut tx, s).await?;
    tx.commit().await?;
    Ok(row)
}

/// [`submit`] guarded by an idempotency key: a request sent again with the
/// same key answers with the submission the first one stored.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn submit_once(
    pool: &PgPool,
    key: &Key<'_>,
    s: NewSubmission<'_>,
) -> Result<Once<SubmissionRow>, DbError> {
    let mut tx = match idempotency::begin(pool, key).await? {
        Ok(tx) => tx,
        Err(seen) => return Ok(seen.once()),
    };
    let row = submit_in(&mut tx, s).await?;
    let id = row.id;
    idempotency::finish(pool, tx, key, id, row).await
}

/// `account`'s submission `id`, whatever became of it.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn submission_of(
    pool: &PgPool,
    account: Uuid,
    id: Uuid,
) -> Result<Option<SubmissionRow>, DbError> {
    Ok(sqlx::query_as!(
        SubmissionRow,
        r#"
        SELECT id, kind, place_id, poi_id, status, payload, created_at, applied_at
        FROM place_submissions WHERE id = $1 AND account_id = $2
        "#,
        id,
        account,
    )
    .fetch_optional(pool)
    .await?)
}

async fn submit_in(
    tx: &mut sqlx::PgConnection,
    s: NewSubmission<'_>,
) -> Result<SubmissionRow, DbError> {
    let (kind, place, payload) = match s.what {
        Submitted::Create(p) => (
            "create",
            None,
            serde_json::to_value(p).map_err(|e| DbError::decode("submission", e))?,
        ),
        Submitted::Edit { place, patch } => (
            "edit",
            Some(place),
            serde_json::to_value(patch).map_err(|e| DbError::decode("submission", e))?,
        ),
        Submitted::Poi(v) => (
            "poi",
            None,
            serde_json::to_value(v).map_err(|e| DbError::decode("submission", e))?,
        ),
    };
    let status = if s.accepted { "accepted" } else { "proposed" };
    let row = sqlx::query_as!(
        SubmissionRow,
        r#"
        INSERT INTO place_submissions (id, account_id, device_key_id, kind, place_id, payload, status)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, kind, place_id, poi_id, status, payload, created_at, applied_at
        "#,
        Uuid::now_v7(),
        s.account,
        s.device_key,
        kind,
        place,
        payload,
        status,
    )
    .fetch_one(&mut *tx)
    .await?;
    if s.accepted {
        notify_worker(&mut *tx).await?;
    } else {
        let reason = s.held_for.unwrap_or("below level 3");
        enqueue(
            &mut *tx,
            "place_proposal",
            "submission",
            row.id,
            Some(s.account),
            reason,
        )
        .await?;
    }
    Ok(row)
}

/// What deleting one's own submission did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Withdrawal {
    /// No such submission of this account.
    NotFound,
    /// It had not been applied: it is withdrawn and will never be.
    Withdrawn,
    /// It is part of the places database already (ODbL): it stays, without
    /// its author.
    Detached,
}

/// Deletes `account`'s submission `id` from its contributions.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn withdraw(pool: &PgPool, account: Uuid, id: Uuid) -> Result<Withdrawal, DbError> {
    let mut tx = pool.begin().await?;
    let status = sqlx::query_scalar!(
        "SELECT status FROM place_submissions WHERE id = $1 AND account_id = $2 FOR UPDATE",
        id,
        account
    )
    .fetch_optional(&mut *tx)
    .await?;
    let outcome = match status.as_deref() {
        None => return Ok(Withdrawal::NotFound),
        Some("proposed" | "accepted") => {
            sqlx::query!(
                "UPDATE place_submissions SET status = 'withdrawn', decided_at = now() WHERE id = $1",
                id
            )
            .execute(&mut *tx)
            .await?;
            sqlx::query!(
                "DELETE FROM moderation_queue WHERE target_id = $1 AND status = 'open'",
                id
            )
            .execute(&mut *tx)
            .await?;
            Withdrawal::Withdrawn
        }
        Some(_) => {
            // The summaries leave out the answers of the account that added
            // a place or a point (`summary::refresh`,
            // `pois::refresh_community`, which also hides the points of a
            // banned author): without its author, those answers count, and
            // the place's verification or the point's date and visibility
            // may change. The worker refreshes them so the change feed and
            // the tiles carry it.
            let places = sqlx::query!(
                r#"
                INSERT INTO place_refresh_queue (place_id)
                SELECT ps.place_id FROM place_submissions s
                JOIN place_sources ps ON ps.record_id = s.record_id
                WHERE s.id = $1 AND s.kind = 'create'
                ON CONFLICT DO NOTHING
                "#,
                id
            )
            .execute(&mut *tx)
            .await?;
            let points = sqlx::query!(
                r#"
                INSERT INTO poi_refresh_queue (poi_id)
                SELECT poi_id FROM place_submissions WHERE id = $1 AND poi_id IS NOT NULL
                ON CONFLICT DO NOTHING
                "#,
                id
            )
            .execute(&mut *tx)
            .await?;
            if places.rows_affected() + points.rows_affected() > 0 {
                crate::community::notify_worker(&mut tx).await?;
            }
            sqlx::query!(
                "UPDATE place_submissions SET account_id = NULL, device_key_id = NULL WHERE id = $1",
                id
            )
            .execute(&mut *tx)
            .await?;
            Withdrawal::Detached
        }
    };
    // Its key would still tie the account to what it sent (the request's
    // hash): the author took it out of their contributions, the key goes.
    // A row deleted outright takes its key by the table's trigger.
    sqlx::query!("DELETE FROM idempotency_keys WHERE result_id = $1", id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(outcome)
}

/// `account`'s submissions, newest first.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn submissions_of_account(
    pool: &PgPool,
    account: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<crate::community::Page<SubmissionRow>, DbError> {
    let mut rows = sqlx::query_as!(
        SubmissionRow,
        r#"
        SELECT id, kind, place_id, poi_id, status, payload, created_at, applied_at
        FROM place_submissions
        WHERE account_id = $1 AND ($2::uuid IS NULL OR id < $2)
        ORDER BY id DESC LIMIT $3
        "#,
        account,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total_count = sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM place_submissions WHERE account_id = $1"#,
        account
    )
    .fetch_one(pool)
    .await?;
    let keep = usize::try_from(first).unwrap_or(0);
    let has_next_page = rows.len() > keep;
    rows.truncate(keep);
    Ok(crate::community::Page {
        nodes: rows,
        has_next_page,
        total_count,
    })
}

/// The submission `id`, whoever sent it.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn submission(pool: &PgPool, id: Uuid) -> Result<Option<SubmissionRow>, DbError> {
    Ok(sqlx::query_as!(
        SubmissionRow,
        r#"
        SELECT id, kind, place_id, poi_id, status, payload, created_at, applied_at
        FROM place_submissions WHERE id = $1
        "#,
        id
    )
    .fetch_optional(pool)
    .await?)
}

/// What the worker did with the accepted submissions.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ApplyStats {
    /// New places written as community records.
    pub created: u64,
    /// Edits written into community records.
    pub edited: u64,
    /// Edits whose place no longer exists.
    pub orphaned: u64,
}

/// Writes every accepted submission into the `community` source, in the
/// writer transaction `tx`, flagging the records for the conflation that
/// follows (the next transaction of the same run).
///
/// # Errors
///
/// [`DbError`] when a statement fails or a stored submission does not
/// decode.
pub async fn apply_accepted(tx: &mut WriterTx) -> Result<ApplyStats, DbError> {
    let pending = sqlx::query!(
        r#"
        SELECT id, kind, place_id, payload, created_at FROM place_submissions
        WHERE status = 'accepted' AND kind IN ('create', 'edit') ORDER BY id FOR UPDATE
        "#
    )
    .fetch_all(tx.conn())
    .await?;
    let mut stats = ApplyStats::default();
    for s in pending {
        let applied = match (s.kind.as_str(), s.place_id) {
            ("create", _) => match serde_json::from_value::<NewPlace>(s.payload.clone())
                .map_err(|e| e.to_string())
                .and_then(|new| submission::validate_new_place(&new).map_err(|e| e.to_string()))
            {
                Ok(new) => {
                    let record = submission::record_of(&new);
                    let id = write_record(
                        tx,
                        &format!("submission/{}", s.id),
                        &record,
                        &s.payload,
                        s.created_at,
                    )
                    .await?;
                    if id.is_some() {
                        stats.created += 1;
                    }
                    id
                }
                Err(error) => {
                    // Written by the API from a checked input, so only a
                    // change of the stored form or a write that bypassed the
                    // API can cause it: the worker checks again, refuses that
                    // one, and goes on with the others.
                    tracing::error!(%error, id = %s.id, "a submission is refused by the worker");
                    None
                }
            },
            (_, Some(place)) => match serde_json::from_value::<PlacePatch>(s.payload.clone())
                .map_err(|e| e.to_string())
                .and_then(|patch| submission::validate_edit(&patch).map_err(|e| e.to_string()))
            {
                Ok(patch) => {
                    let applied = apply_edit(tx, place, &patch, &s.payload, s.created_at).await?;
                    if applied.is_some() {
                        stats.edited += 1;
                    } else {
                        stats.orphaned += 1;
                    }
                    applied
                }
                Err(error) => {
                    tracing::error!(%error, id = %s.id, "a submission is refused by the worker");
                    None
                }
            },
            _ => None,
        };
        let status = if applied.is_some() {
            "applied"
        } else {
            "rejected"
        };
        sqlx::query!(
            r#"
            UPDATE place_submissions SET status = $2, record_id = $3, applied_at = now(),
                   decided_at = coalesce(decided_at, now())
            WHERE id = $1
            "#,
            s.id,
            status,
            applied,
        )
        .execute(tx.conn())
        .await?;
    }
    Ok(stats)
}

/// Inserts or rewrites a community record, flagged for the conflation;
/// `None` when the record was taken down (`takedowns`), which stays empty.
async fn write_record(
    tx: &mut WriterTx,
    external_id: &str,
    record: &NormalizedRecord,
    raw: &serde_json::Value,
    at: DateTime<Utc>,
) -> Result<Option<Uuid>, DbError> {
    let data = serde_json::to_value(record).map_err(|e| DbError::decode("record", e))?;
    Ok(sqlx::query_scalar!(
        r#"
        INSERT INTO source_records AS sr
            (id, source_id, external_id, kind, name, geom, accuracy_m, data, raw, fetched_at)
        VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($7, $6), 4326)::geography, 0, $8,
                $9, $10)
        ON CONFLICT (source_id, external_id) DO UPDATE SET
            kind = EXCLUDED.kind, name = EXCLUDED.name, geom = EXCLUDED.geom,
            data = EXCLUDED.data, raw = EXCLUDED.raw, fetched_at = EXCLUDED.fetched_at,
            changed_at = now(), needs_conflation = true, deleted_at = NULL
        WHERE sr.taken_down_at IS NULL
        RETURNING id
        "#,
        Uuid::now_v7(),
        SourceId::COMMUNITY.as_str(),
        external_id,
        record.kind.code(),
        record.name,
        record.position.lat(),
        record.position.lon(),
        data,
        raw,
        at,
    )
    .fetch_optional(tx.conn())
    .await?)
}

/// Patches the community record of `place` (following merges), creating it
/// tied to the place when it has none. `None` when the place is gone.
async fn apply_edit(
    tx: &mut WriterTx,
    place: Uuid,
    patch: &PlacePatch,
    raw: &serde_json::Value,
    at: DateTime<Utc>,
) -> Result<Option<Uuid>, DbError> {
    let live = sqlx::query!(
        r#"
        WITH RECURSIVE chain(id, deleted, next, depth) AS (
            SELECT id, deleted_at IS NOT NULL, merged_into, 0 FROM places WHERE id = $1
            UNION ALL
            SELECT p.id, p.deleted_at IS NOT NULL, p.merged_into, c.depth + 1
            FROM chain c JOIN places p ON p.id = c.next
            WHERE c.deleted AND c.depth < 8
        )
        SELECT c.id AS "id!", p.kind, ST_Y(p.geom::geometry) AS "lat!",
               ST_X(p.geom::geometry) AS "lon!"
        FROM chain c JOIN places p ON p.id = c.id
        WHERE NOT c.deleted
        LIMIT 1
        "#,
        place,
    )
    .fetch_optional(tx.conn())
    .await?;
    let Some(live) = live else {
        return Ok(None);
    };
    let existing = sqlx::query!(
        r#"
        SELECT r.external_id, r.data FROM place_sources ps
        JOIN source_records r ON r.id = ps.record_id
        WHERE ps.place_id = $1 AND r.source_id = $2 AND r.deleted_at IS NULL
        ORDER BY r.id LIMIT 1
        "#,
        live.id,
        SourceId::COMMUNITY.as_str(),
    )
    .fetch_optional(tx.conn())
    .await?;
    if let Some(e) = existing {
        let mut record: NormalizedRecord =
            serde_json::from_value(e.data).map_err(|err| DbError::decode("record", err))?;
        submission::apply(&mut record, patch);
        return write_record(tx, &e.external_id, &record, raw, at).await;
    }
    let kind: PlaceKind = live
        .kind
        .parse()
        .map_err(|e| DbError::decode("place kind", e))?;
    let position =
        Position::new(live.lat, live.lon).map_err(|e| DbError::decode("place position", e))?;
    let mut record = NormalizedRecord::new(kind, position);
    submission::apply(&mut record, patch);
    let Some(id) = write_record(tx, &format!("place/{}", live.id), &record, raw, at).await? else {
        return Ok(None);
    };
    // Tie the new record to the place: one of the place's live records, the
    // oldest, becomes its must_link partner.
    let anchor = sqlx::query_scalar!(
        r#"
        SELECT r.id FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
        WHERE ps.place_id = $1 AND r.deleted_at IS NULL AND r.id <> $2
        ORDER BY r.id LIMIT 1
        "#,
        live.id,
        id,
    )
    .fetch_optional(tx.conn())
    .await?;
    if let Some(anchor) = anchor {
        let (a, b) = if anchor < id {
            (anchor, id)
        } else {
            (id, anchor)
        };
        sqlx::query!(
            r#"
            INSERT INTO conflation_constraints (id, record_a, record_b, kind, reason)
            VALUES ($1, $2, $3, 'must_link', 'community edit of this place')
            ON CONFLICT (record_a, record_b) DO NOTHING
            "#,
            Uuid::now_v7(),
            a,
            b,
        )
        .execute(tx.conn())
        .await?;
    }
    Ok(Some(id))
}

/// Notes on each applied new place the place its record became, once the
/// conflation of the same transaction placed it.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn link_created_places(tx: &mut WriterTx) -> Result<u64, DbError> {
    let done = sqlx::query!(
        r#"
        UPDATE place_submissions s SET place_id = ps.place_id
        FROM place_sources ps
        WHERE ps.record_id = s.record_id AND s.kind = 'create'
          AND s.place_id IS DISTINCT FROM ps.place_id
        "#
    )
    .execute(tx.conn())
    .await?;
    Ok(done.rows_affected())
}

/// Of the places `written` by a conflation run, those whose verification
/// may have changed: they hold a community record, or were to verify (a
/// record of another source joined or left them).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn places_to_verify(tx: &mut WriterTx, written: &[Uuid]) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT p.id FROM places p
        WHERE p.id = ANY($1) AND p.deleted_at IS NULL
          AND (p.verification = 'to_verify' OR EXISTS (
                SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
                WHERE ps.place_id = p.id AND r.source_id = $2))
        "#,
        written,
        SourceId::COMMUNITY.as_str(),
    )
    .fetch_all(tx.conn())
    .await?)
}
