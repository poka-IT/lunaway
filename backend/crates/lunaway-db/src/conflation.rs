//! Storage of the conflation: the work list, the candidates, the scored
//! pairs, the constraints, and the places written from them. The logic that
//! drives these calls is `lunaway-conflate`; every function here runs inside
//! a [`WriterTx`], the only transaction that may write places.

use chrono::{DateTime, NaiveDate, Utc};
use futures_util::TryStreamExt;
use lunaway_domain::{
    NormalizedRecord, OpeningInterval, Position, SourceId,
    conflation::{
        ConstraintKind, ExternalLink, FieldProvenance, LocalizedText, MatchScore, PlaceContent,
    },
};
use sqlx::{PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// A transaction that holds the writers' lock (see `begin_writer`), the
/// only way to write `places`.
///
/// The change feed is safe because writers of `places` are serialised: a
/// function that writes a place takes this type, so a write outside the
/// lock does not compile.
pub struct WriterTx(Transaction<'static, Postgres>);

impl std::fmt::Debug for WriterTx {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("WriterTx")
    }
}

impl WriterTx {
    pub(crate) fn conn(&mut self) -> &mut PgConnection {
        &mut self.0
    }

    /// Commits the transaction and releases the lock.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the commit fails; nothing of the transaction is kept.
    pub async fn commit(self) -> Result<(), DbError> {
        self.0.commit().await?;
        Ok(())
    }
}

/// Starts a transaction holding the writers' lock, waiting while another
/// writer (a conflation run, an import batch) holds it.
///
/// # Errors
///
/// [`DbError`] when no connection is available or the lock statement fails.
pub async fn begin_writer(pool: &PgPool) -> Result<WriterTx, DbError> {
    Ok(WriterTx(crate::begin_locked(pool).await?))
}

/// The records flagged for the conflation, locked so an import cannot change
/// one between its scoring and the clearing of its flag.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn dirty(tx: &mut WriterTx) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        "SELECT id FROM source_records WHERE needs_conflation ORDER BY id FOR UPDATE"
    )
    .fetch_all(tx.conn())
    .await?)
}

/// Pairs (dirty record, live record within reach) for the live records of
/// `ids`. `radius_m` is the largest kind radius and `accuracy_cap_m` the
/// largest uncertainty credited to a record: the scorer decides inside that
/// reach, the GiST index finds it.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn candidates(
    tx: &mut WriterTx,
    ids: &[Uuid],
    radius_m: f64,
    accuracy_cap_m: f64,
) -> Result<Vec<(Uuid, Uuid)>, DbError> {
    let mut rows = sqlx::query!(
        r#"
        SELECT a.id AS "a!", b.id AS "b!"
        FROM source_records a
        JOIN source_records b
          ON b.id <> a.id
         AND b.deleted_at IS NULL
         AND ST_DWithin(a.geom, b.geom, $2 + least(a.accuracy_m, $3) + $3)
        WHERE a.id = ANY($1) AND a.deleted_at IS NULL
        "#,
        ids,
        radius_m,
        accuracy_cap_m,
    )
    .fetch(tx.conn());
    // A full rebuild reads hundreds of thousands of pairs; decoding them in
    // one go would hold the async thread for a second, so the stream hands
    // it back every batch of rows.
    let mut out = Vec::new();
    while let Some(r) = rows.try_next().await? {
        out.push((r.a, r.b));
        if out.len() % 4_096 == 0 {
            tokio::task::yield_now().await;
        }
    }
    Ok(out)
}

/// A record as the conflation reads it.
#[derive(Debug, Clone)]
pub struct StoredRecord {
    /// Its id.
    pub id: Uuid,
    /// Its source.
    pub source_id: SourceId,
    /// Its id in the source.
    pub external_id: String,
    /// Its page at the source.
    pub external_url: Option<String>,
    /// When it was read.
    pub fetched_at: DateTime<Utc>,
    /// Whether the source no longer lists it.
    pub deleted: bool,
    /// What it says.
    pub record: NormalizedRecord,
}

/// The records `ids`, in id order.
///
/// # Errors
///
/// [`DbError`] when the query fails or a stored record does not decode.
pub async fn records(tx: &mut WriterTx, ids: &[Uuid]) -> Result<Vec<StoredRecord>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, source_id, external_id, external_url, fetched_at,
               deleted_at IS NOT NULL AS "deleted!", data
        FROM source_records WHERE id = ANY($1) ORDER BY id
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(StoredRecord {
                id: r.id,
                source_id: SourceId::new(&r.source_id)
                    .map_err(|e| DbError::decode("source id", e))?,
                external_id: r.external_id,
                external_url: r.external_url,
                fetched_at: r.fetched_at,
                deleted: r.deleted,
                record: serde_json::from_value(r.data).map_err(|e| DbError::decode("record", e))?,
            })
        })
        .collect()
}

/// Forgets the stored pairs touching `ids`, before they are scored again.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn delete_pairs(tx: &mut WriterTx, ids: &[Uuid]) -> Result<(), DbError> {
    sqlx::query!(
        "DELETE FROM match_pairs WHERE record_a = ANY($1) OR record_b = ANY($1)",
        ids,
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}

/// A scored pair to store.
#[derive(Debug, Clone)]
pub struct PairRow {
    /// One record.
    pub a: Uuid,
    /// The other.
    pub b: Uuid,
    /// The verdict.
    pub score: MatchScore,
}

/// Stores scored pairs (merges and reviews; distinct pairs are not kept).
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn insert_pairs(tx: &mut WriterTx, pairs: &[PairRow]) -> Result<(), DbError> {
    for chunk in pairs.chunks(1_000) {
        let mut a = Vec::with_capacity(chunk.len());
        let mut b = Vec::with_capacity(chunk.len());
        let mut score = Vec::with_capacity(chunk.len());
        let mut decision = Vec::with_capacity(chunk.len());
        let mut reason = Vec::with_capacity(chunk.len());
        let mut components = Vec::with_capacity(chunk.len());
        for p in chunk {
            let (lo, hi) = if p.a < p.b { (p.a, p.b) } else { (p.b, p.a) };
            a.push(lo);
            b.push(hi);
            score.push(p.score.score.clamp(0.0, 1.0));
            decision.push(p.score.decision.code().to_owned());
            reason.push(p.score.reason.code().to_owned());
            components.push(
                serde_json::to_value(&p.score.components)
                    .map_err(|e| DbError::decode("score components", e))?,
            );
        }
        sqlx::query!(
            r#"
            INSERT INTO match_pairs (record_a, record_b, score, decision, reason, components)
            SELECT * FROM UNNEST($1::uuid[], $2::uuid[], $3::float8[], $4::text[], $5::text[],
                                 $6::jsonb[])
            ON CONFLICT (record_a, record_b) DO UPDATE SET
                score = EXCLUDED.score, decision = EXCLUDED.decision, reason = EXCLUDED.reason,
                components = EXCLUDED.components, computed_at = now()
            "#,
            &a,
            &b,
            &score,
            &decision,
            &reason,
            &components,
        )
        .execute(tx.conn())
        .await?;
    }
    Ok(())
}

/// Stored merge decisions touching `ids`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn merge_edges(
    tx: &mut WriterTx,
    ids: &[Uuid],
) -> Result<Vec<(Uuid, Uuid, f64)>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT record_a, record_b, score FROM match_pairs
        WHERE decision = 'merge' AND (record_a = ANY($1) OR record_b = ANY($1))
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| (r.record_a, r.record_b, r.score))
        .collect())
}

/// Human constraints touching `ids`.
///
/// # Errors
///
/// [`DbError`] when the query fails or a kind is unknown.
pub async fn constraints(
    tx: &mut WriterTx,
    ids: &[Uuid],
) -> Result<Vec<(Uuid, Uuid, ConstraintKind)>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT record_a, record_b, kind FROM conflation_constraints
        WHERE record_a = ANY($1) OR record_b = ANY($1)
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    rows.into_iter()
        .map(|r| {
            let kind = match r.kind.as_str() {
                "must_link" => ConstraintKind::MustLink,
                "cannot_link" => ConstraintKind::CannotLink,
                other => {
                    return Err(DbError::decode(
                        "constraint kind",
                        lunaway_domain::UnknownCode {
                            kind: "ConstraintKind",
                            code: other.to_owned(),
                        },
                    ));
                }
            };
            Ok((r.record_a, r.record_b, kind))
        })
        .collect()
}

/// `(record, place)` for the records of `ids` that belong to a place.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn places_of_records(
    tx: &mut WriterTx,
    ids: &[Uuid],
) -> Result<Vec<(Uuid, Uuid)>, DbError> {
    let rows = sqlx::query!(
        "SELECT record_id, place_id FROM place_sources WHERE record_id = ANY($1)",
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| (r.record_id, r.place_id))
        .collect())
}

/// `(record, place)` for every record of the places `ids`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn records_of_places(
    tx: &mut WriterTx,
    ids: &[Uuid],
) -> Result<Vec<(Uuid, Uuid)>, DbError> {
    let rows = sqlx::query!(
        "SELECT record_id, place_id FROM place_sources WHERE place_id = ANY($1)",
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| (r.record_id, r.place_id))
        .collect())
}

/// What the conflation needs to know of an existing place.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaceState {
    /// Its id.
    pub id: Uuid,
    /// Digest of its content and records.
    pub content_hash: String,
    /// Whether it is a tombstone.
    pub deleted: bool,
}

/// The state of the places `ids`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn place_states(tx: &mut WriterTx, ids: &[Uuid]) -> Result<Vec<PlaceState>, DbError> {
    let rows = sqlx::query!(
        r#"SELECT id, content_hash, deleted_at IS NOT NULL AS "deleted!" FROM places WHERE id = ANY($1)"#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| PlaceState {
            id: r.id,
            content_hash: r.content_hash,
            deleted: r.deleted,
        })
        .collect())
}

/// Opening hours evaluated for a place.
#[derive(Debug, Clone, PartialEq)]
pub struct OpeningEval {
    /// Whether the expression parses.
    pub parsed: bool,
    /// Open intervals, `None` when absent or unparseable.
    pub intervals: Option<Vec<OpeningInterval>>,
    /// Instant up to which `intervals` are complete: the place is closed
    /// between them, and nothing is known after. `None` with no intervals.
    pub until: Option<DateTime<Utc>>,
    /// First local day of the window.
    pub window_start: Option<NaiveDate>,
    /// When the window must move: the next local midnight after its first
    /// day, in the zone of the place. `None` without hours.
    pub refresh_at: Option<DateTime<Utc>>,
}

/// A place to write.
#[derive(Debug, Clone, Copy)]
pub struct PlaceWrite<'a> {
    /// Its id.
    pub id: Uuid,
    /// Resolved values.
    pub content: &'a PlaceContent,
    /// Which source supplied each value.
    pub provenance: &'a [FieldProvenance],
    /// Evaluated opening hours.
    pub opening: &'a OpeningEval,
    /// Every description, by language.
    pub descriptions: &'a [LocalizedText],
    /// Pages about the place elsewhere.
    pub external_links: &'a [ExternalLink],
    /// Digest of content and records.
    pub content_hash: &'a str,
}

fn intervals_json(o: &OpeningEval) -> Result<Option<serde_json::Value>, DbError> {
    o.intervals
        .as_ref()
        .map(serde_json::to_value)
        .transpose()
        .map_err(|e| DbError::decode("opening intervals", e))
}

/// Inserts or rewrites a place, taking the next position in the change feed
/// and clearing any tombstone. The place takes the name of the commune that
/// covers its point, when the communes are loaded. The community summary is
/// left as it is: the worker computes it from the contributions.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn upsert_place(tx: &mut WriterTx, p: PlaceWrite<'_>) -> Result<(), DbError> {
    let c = p.content;
    let services: Vec<String> = c.services.iter().map(|s| s.code().to_owned()).collect();
    let activities: Vec<String> = c.activities.iter().map(|s| s.code().to_owned()).collect();
    let provenance =
        serde_json::to_value(p.provenance).map_err(|e| DbError::decode("provenance", e))?;
    let descriptions =
        serde_json::to_value(p.descriptions).map_err(|e| DbError::decode("descriptions", e))?;
    let links =
        serde_json::to_value(p.external_links).map_err(|e| DbError::decode("external links", e))?;
    let capacity = c.capacity.and_then(|v| i32::try_from(v).ok());
    let stars = c.stars.map(i16::from);
    sqlx::query!(
        r#"
        WITH m AS (
            -- The commune that covers the point, else the nearest within
            -- about a kilometre: the communes are simplified to 100 m, and
            -- a campsite on the shore fell outside every one (24 of 18 391
            -- French places, all within 422 m of one, on 2026-10-06).
            SELECT code, name FROM municipalities
            WHERE ST_DWithin(geom, ST_SetSRID(ST_MakePoint($5, $4), 4326), 0.015)
            ORDER BY NOT ST_Covers(geom, ST_SetSRID(ST_MakePoint($5, $4), 4326)),
                     ST_Distance(geom, ST_SetSRID(ST_MakePoint($5, $4), 4326)), code
            LIMIT 1
        )
        INSERT INTO places
            (id, kind, name, geom, overnight, services, activities, description, street,
             postcode, city, country_code, price_parking_eur, price_services_eur, max_height_m,
             capacity, opening_hours, opening_hours_parsed, opening_intervals,
             opening_window_start, website, phone, stars, provenance, content_hash,
             opening_intervals_until, descriptions, external_links, municipality,
             municipality_code, max_length_m, max_width_m, max_weight_t, opening_refresh_at)
        SELECT $1, $2, $3, ST_SetSRID(ST_MakePoint($5, $4), 4326)::geography, $6, $7, $8, $9,
               $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25,
               $26, $27, $28, $29, m.name, m.code, $30, $31, $32, $33
        FROM (VALUES (1)) AS one (x) LEFT JOIN m ON true
        -- Ends the SELECT before ON CONFLICT: the parser would otherwise
        -- read the conflict clause as part of the join.
        WHERE true
        ON CONFLICT (id) DO UPDATE SET
            kind = EXCLUDED.kind, name = EXCLUDED.name, geom = EXCLUDED.geom,
            overnight = EXCLUDED.overnight, services = EXCLUDED.services,
            activities = EXCLUDED.activities, description = EXCLUDED.description,
            street = EXCLUDED.street, postcode = EXCLUDED.postcode, city = EXCLUDED.city,
            country_code = EXCLUDED.country_code, price_parking_eur = EXCLUDED.price_parking_eur,
            price_services_eur = EXCLUDED.price_services_eur,
            max_height_m = EXCLUDED.max_height_m, capacity = EXCLUDED.capacity,
            max_length_m = EXCLUDED.max_length_m, max_width_m = EXCLUDED.max_width_m,
            max_weight_t = EXCLUDED.max_weight_t,
            opening_hours = EXCLUDED.opening_hours,
            opening_hours_parsed = EXCLUDED.opening_hours_parsed,
            opening_intervals = EXCLUDED.opening_intervals,
            opening_intervals_until = EXCLUDED.opening_intervals_until,
            opening_window_start = EXCLUDED.opening_window_start,
            opening_refresh_at = EXCLUDED.opening_refresh_at,
            website = EXCLUDED.website, phone = EXCLUDED.phone, stars = EXCLUDED.stars,
            provenance = EXCLUDED.provenance, content_hash = EXCLUDED.content_hash,
            descriptions = EXCLUDED.descriptions, external_links = EXCLUDED.external_links,
            municipality = EXCLUDED.municipality,
            municipality_code = EXCLUDED.municipality_code,
            updated_at = now(), updated_seq = nextval('place_change_seq'),
            deleted_at = NULL, merged_into = NULL
        "#,
        p.id,
        c.kind.code(),
        c.name,
        c.position.lat(),
        c.position.lon(),
        c.overnight.code(),
        &services,
        &activities,
        c.description,
        c.address.street,
        c.address.postcode,
        c.address.city,
        c.address.country_code,
        c.price_parking_eur,
        c.price_services_eur,
        c.max_height_m,
        capacity,
        c.opening_hours,
        p.opening.parsed,
        intervals_json(p.opening)?,
        p.opening.window_start,
        c.website,
        c.phone,
        stars,
        provenance,
        p.content_hash,
        p.opening.until,
        descriptions,
        links,
        c.max_length_m,
        c.max_width_m,
        c.max_weight_t,
        p.opening.refresh_at,
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}

/// Turns a live place into a tombstone, pointing to the place that absorbed
/// it if any. A place that is already a tombstone is left as it is.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn tombstone(
    tx: &mut WriterTx,
    id: Uuid,
    merged_into: Option<Uuid>,
) -> Result<bool, DbError> {
    let done = sqlx::query!(
        r#"
        UPDATE places SET deleted_at = now(), merged_into = $2, updated_at = now(),
                          updated_seq = nextval('place_change_seq')
        WHERE id = $1 AND deleted_at IS NULL
        "#,
        id,
        merged_into,
    )
    .execute(tx.conn())
    .await?;
    Ok(done.rows_affected() > 0)
}

/// Replaces the links of the records `record_ids`: they are removed from
/// whatever place held them, then `links` (record, place, score) are
/// written.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn relink(
    tx: &mut WriterTx,
    record_ids: &[Uuid],
    links: &[(Uuid, Uuid, Option<f64>)],
) -> Result<(), DbError> {
    sqlx::query!(
        "DELETE FROM place_sources WHERE record_id = ANY($1)",
        record_ids
    )
    .execute(tx.conn())
    .await?;
    let records: Vec<Uuid> = links.iter().map(|l| l.0).collect();
    let places: Vec<Uuid> = links.iter().map(|l| l.1).collect();
    let scores: Vec<Option<f64>> = links.iter().map(|l| l.2).collect();
    sqlx::query!(
        r#"
        INSERT INTO place_sources (record_id, place_id, match_score)
        SELECT * FROM UNNEST($1::uuid[], $2::uuid[], $3::float8[])
        "#,
        &records,
        &places,
        &scores as &[Option<f64>],
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}

/// Clears the conflation flag of `ids`.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn clear_dirty(tx: &mut WriterTx, ids: &[Uuid]) -> Result<(), DbError> {
    sqlx::query!(
        "UPDATE source_records SET needs_conflation = false WHERE id = ANY($1)",
        ids,
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}

/// A live place whose opening window must move.
#[derive(Debug, Clone)]
pub struct StaleOpening {
    /// The place.
    pub id: Uuid,
    /// Its `opening_hours`.
    pub opening_hours: String,
    /// Its country, which gives the timezone.
    pub country_code: Option<String>,
    /// Its position, for sun events.
    pub position: Position,
    /// Its current intervals.
    pub intervals: Option<Vec<OpeningInterval>>,
    /// End of its current window.
    pub until: Option<DateTime<Utc>>,
}

/// Live places with opening hours whose window must move at `now` (its
/// local midnight has passed, or it was never set), or whose intervals lack
/// the end of their window (computed before the window end was stored).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn stale_openings(
    tx: &mut WriterTx,
    now: DateTime<Utc>,
) -> Result<Vec<StaleOpening>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, opening_hours AS "opening_hours!", country_code, opening_intervals,
               opening_intervals_until,
               ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!"
        FROM places
        WHERE deleted_at IS NULL AND opening_hours IS NOT NULL
          AND (opening_window_start IS NULL OR opening_refresh_at IS NULL
               OR opening_refresh_at <= $1
               OR (opening_intervals IS NOT NULL AND opening_intervals_until IS NULL))
        ORDER BY id
        "#,
        now,
    )
    .fetch_all(tx.conn())
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(StaleOpening {
                id: r.id,
                opening_hours: r.opening_hours,
                country_code: r.country_code,
                position: Position::new(r.lat, r.lon)
                    .map_err(|e| DbError::decode("place position", e))?,
                intervals: r
                    .opening_intervals
                    .map(serde_json::from_value)
                    .transpose()
                    .map_err(|e| DbError::decode("opening intervals", e))?,
                until: r.opening_intervals_until,
            })
        })
        .collect()
}

/// Stores freshly evaluated opening hours. The place takes a new position in
/// the change feed only when its intervals or their window end changed, so
/// devices download it again only then.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn set_opening(
    tx: &mut WriterTx,
    id: Uuid,
    opening: &OpeningEval,
    changed: bool,
) -> Result<(), DbError> {
    sqlx::query!(
        r#"
        UPDATE places SET
            opening_hours_parsed = $2, opening_intervals = $3, opening_window_start = $4,
            opening_intervals_until = $6, opening_refresh_at = $7,
            updated_at = CASE WHEN $5 THEN now() ELSE updated_at END,
            updated_seq = CASE WHEN $5 THEN nextval('place_change_seq') ELSE updated_seq END
        WHERE id = $1
        "#,
        id,
        opening.parsed,
        intervals_json(opening)?,
        opening.window_start,
        changed,
        opening.until,
        opening.refresh_at,
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}
