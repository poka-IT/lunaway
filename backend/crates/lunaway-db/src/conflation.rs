//! Storage of the conflation: the work list, the candidates, the scored
//! pairs, the constraints, and the places written from them. The logic that
//! drives these calls is `lunaway-conflate`; every function here runs inside
//! a [`WriterTx`], the only transaction that may write places.

use chrono::{DateTime, NaiveDate, Utc};
use futures_util::TryStreamExt;
use lunaway_domain::{
    NormalizedRecord, OpeningInterval, Position, SourceId,
    conflation::{
        ConstraintKind, ExternalLink, FieldProvenance, LocalizedText, MatchScore, MergeEdge,
        PlaceContent,
    },
    season::Season,
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
        r#"
        SELECT id FROM source_records WHERE needs_conflation AND taken_down_at IS NULL
        ORDER BY id FOR UPDATE
        "#
    )
    .fetch_all(tx.conn())
    .await?)
}

/// Pairs (dirty record, live record within reach) for the live records of
/// `ids`. `radius_m` is the largest kind radius and `accuracy_cap_m` the
/// largest uncertainty credited to a record: the scorer decides inside that
/// reach, the GiST index finds it. A record of a hidden source
/// (`source_switches`) is not live.
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
        WITH hidden AS (
            SELECT coalesce(array_agg(source_id), '{}') AS ids
            FROM source_switches WHERE hidden_at IS NOT NULL
        )
        SELECT a.id AS "a!", b.id AS "b!"
        FROM hidden, source_records a
        JOIN source_records b
          ON b.id <> a.id
         AND b.deleted_at IS NULL
         AND ST_DWithin(a.geom, b.geom, $2 + least(a.accuracy_m, $3) + $3)
        WHERE a.id = ANY($1) AND a.deleted_at IS NULL
          AND NOT (a.source_id = ANY(hidden.ids)) AND NOT (b.source_id = ANY(hidden.ids))
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
    /// When it was last read (`lunaway_read_at`): the field resolution
    /// prefers the latest read between sources it trusts alike.
    pub fetched_at: DateTime<Utc>,
    /// Whether the source no longer lists it, or the source is hidden
    /// (`source_switches`): either way it belongs to no place.
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
        SELECT id, source_id, external_id, external_url,
               lunaway_read_at('records', source_id, scope, fetched_at, deleted_at)
                   AS "fetched_at!",
               (deleted_at IS NOT NULL OR EXISTS (
                   SELECT 1 FROM source_switches w
                   WHERE w.source_id = source_records.source_id AND w.hidden_at IS NOT NULL))
                   AS "deleted!",
               data
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

/// Stored merge decisions touching `ids`, with the distance and the name
/// component the grouping breaks ties of score with.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn merge_edges(tx: &mut WriterTx, ids: &[Uuid]) -> Result<Vec<MergeEdge<Uuid>>, DbError> {
    // Every stored decision carries its components; a row without them
    // (none is written so) would rank last among its ties.
    let rows = sqlx::query!(
        r#"
        SELECT record_a, record_b, score,
               coalesce((components->>'distance_m')::float8, 'Infinity') AS "distance_m!",
               coalesce((components->>'name')::float8, 0) AS "name!"
        FROM match_pairs
        WHERE decision = 'merge' AND (record_a = ANY($1) OR record_b = ANY($1))
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| MergeEdge {
            a: r.record_a,
            b: r.record_b,
            score: r.score,
            distance_m: r.distance_m,
            name: r.name,
        })
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
#[derive(Debug, Clone, PartialEq)]
pub struct PlaceState {
    /// Its id.
    pub id: Uuid,
    /// Digest of its content and records.
    pub content_hash: String,
    /// Whether it is a tombstone.
    pub deleted: bool,
    /// Where it is shown, for a live place: a place that moves into a
    /// takedown's cells is held, one already there is not.
    pub position: Option<Position>,
}

/// The state of the places `ids`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn place_states(tx: &mut WriterTx, ids: &[Uuid]) -> Result<Vec<PlaceState>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, content_hash, deleted_at IS NOT NULL AS "deleted!",
               ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!"
        FROM places WHERE id = ANY($1)
        "#,
        ids,
    )
    .fetch_all(tx.conn())
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(PlaceState {
                id: r.id,
                content_hash: r.content_hash,
                deleted: r.deleted,
                position: if r.deleted {
                    None
                } else {
                    Some(
                        Position::new(r.lat, r.lon)
                            .map_err(|e| DbError::decode("place position", e))?,
                    )
                },
            })
        })
        .collect()
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
    /// day, in the zone of the place. `None` without hours, and for a
    /// season.
    pub refresh_at: Option<DateTime<Utc>>,
    /// The days of the year it is open, when its hours are dates without
    /// times (`lunaway_domain::season`); it then has no intervals, no
    /// window and nothing to refresh.
    pub season: Option<Season>,
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

/// A season as its column holds it: its ranges flattened.
fn season_days(season: Option<&Season>) -> Option<Vec<i16>> {
    season.map(|s| {
        s.ranges()
            .iter()
            .flat_map(|&(a, b)| [a, b])
            .map(|d| i16::try_from(d).unwrap_or(i16::MAX))
            .collect()
    })
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
    let parking_includes: Vec<String> = c
        .price_parking_includes
        .iter()
        .map(|i| i.code().to_owned())
        .collect();
    let capacity = c.capacity.and_then(|v| i32::try_from(v).ok());
    let stars = c.stars.map(i16::from);
    let season = season_days(p.opening.season.as_ref());
    let written = sqlx::query!(
        r#"
        WITH m AS (
            -- The commune that covers the point, else, for a French place,
            -- the nearest within 0.015 degree (1.1 to 1.7 km): the communes
            -- are simplified to 100 m, and a campsite on the shore fell
            -- outside every one (24 of 18 391 French places, all within
            -- 422 m of one, on 2026-10-06). A place across a border gets no
            -- French commune.
            SELECT code, name FROM municipalities
            WHERE ST_DWithin(geom, ST_SetSRID(ST_MakePoint($5, $4), 4326),
                             CASE WHEN upper($13::text) = 'FR' THEN 0.015 ELSE 0.0 END)
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
             municipality_code, max_length_m, max_width_m, max_weight_t, opening_refresh_at,
             price_services_included, price_parking_includes, opening_season)
        SELECT $1, $2, $3, ST_SetSRID(ST_MakePoint($5, $4), 4326)::geography, $6, $7, $8, $9,
               $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25,
               $26, $27, $28, $29, m.name, m.code, $30, $31, $32, $33, $34, $35, $36
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
            price_services_included = EXCLUDED.price_services_included,
            price_parking_includes = EXCLUDED.price_parking_includes,
            max_height_m = EXCLUDED.max_height_m, capacity = EXCLUDED.capacity,
            max_length_m = EXCLUDED.max_length_m, max_width_m = EXCLUDED.max_width_m,
            max_weight_t = EXCLUDED.max_weight_t,
            opening_hours = EXCLUDED.opening_hours,
            opening_hours_parsed = EXCLUDED.opening_hours_parsed,
            opening_intervals = EXCLUDED.opening_intervals,
            opening_intervals_until = EXCLUDED.opening_intervals_until,
            opening_window_start = EXCLUDED.opening_window_start,
            opening_refresh_at = EXCLUDED.opening_refresh_at,
            opening_season = EXCLUDED.opening_season,
            website = EXCLUDED.website, phone = EXCLUDED.phone, stars = EXCLUDED.stars,
            provenance = EXCLUDED.provenance, content_hash = EXCLUDED.content_hash,
            descriptions = EXCLUDED.descriptions, external_links = EXCLUDED.external_links,
            municipality = EXCLUDED.municipality,
            municipality_code = EXCLUDED.municipality_code,
            updated_at = now(), updated_seq = nextval('place_change_seq'),
            deleted_at = NULL, merged_into = NULL
        -- A place taken down stays empty, whatever links to its id.
        WHERE places.taken_down_at IS NULL
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
        c.price_services_included,
        &parking_includes,
        season.as_deref() as Option<&[i16]>,
    )
    .execute(tx.conn())
    .await?;
    if written.rows_affected() == 0 {
        // Only a group that kept the id of a place taken down gets here:
        // its links were removed with the takedown, so this is a bug to
        // see, not a state to repair.
        tracing::warn!(place = %p.id, "a write to a place taken down was refused");
    }
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
/// written. A record left without a place remembers the one it leaves
/// (`source_records.last_place_id`).
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn relink(
    tx: &mut WriterTx,
    record_ids: &[Uuid],
    links: &[(Uuid, Uuid, Option<f64>)],
) -> Result<(), DbError> {
    let left = sqlx::query!(
        "DELETE FROM place_sources WHERE record_id = ANY($1) RETURNING record_id, place_id",
        record_ids
    )
    .fetch_all(tx.conn())
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
    // A record unlinked here (retired by its source, held back) still names
    // its place, which a takedown empties it with (`takedowns::take_down`).
    let relinked: std::collections::HashSet<Uuid> = records.iter().copied().collect();
    let (orphans, homes): (Vec<Uuid>, Vec<Uuid>) = left
        .into_iter()
        .filter(|l| !relinked.contains(&l.record_id))
        .map(|l| (l.record_id, l.place_id))
        .unzip();
    if !orphans.is_empty() {
        sqlx::query!(
            r#"
            UPDATE source_records sr SET last_place_id = l.place_id
            FROM UNNEST($1::uuid[], $2::uuid[]) AS l(record_id, place_id)
            WHERE sr.id = l.record_id AND sr.last_place_id IS DISTINCT FROM l.place_id
            "#,
            &orphans,
            &homes,
        )
        .execute(tx.conn())
        .await?;
    }
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
    /// Its stored season (a release before seasons may have given a
    /// place with one a window too).
    pub season: Option<Season>,
}

/// Live places with opening hours whose window must move at `now` (its
/// local midnight has passed, or it was never set), or whose intervals lack
/// the end of their window (computed before the window end was stored). A
/// place with a season has no window: it is read again only when its hours
/// change, by the conflation, or when a release that knew no season wrote
/// it a window. A change of the season's parser reaches the stored places
/// only with their next change of hours: a parser that reads more needs a
/// pass over the places whose hours it now reads.
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
               opening_intervals_until, opening_season,
               ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!"
        FROM places
        WHERE deleted_at IS NULL AND opening_hours IS NOT NULL
          -- A season has no window; one with a window was written by a
          -- release before seasons (a rollback) and is read again.
          AND (opening_season IS NULL OR opening_window_start IS NOT NULL)
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
                season: r
                    .opening_season
                    .map(|days| crate::places::season_of_days(&days))
                    .transpose()?,
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
    let season = season_days(opening.season.as_ref());
    sqlx::query!(
        r#"
        UPDATE places SET
            opening_hours_parsed = $2, opening_intervals = $3, opening_window_start = $4,
            opening_intervals_until = $6, opening_refresh_at = $7, opening_season = $8,
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
        season.as_deref() as Option<&[i16]>,
    )
    .execute(tx.conn())
    .await?;
    Ok(())
}
