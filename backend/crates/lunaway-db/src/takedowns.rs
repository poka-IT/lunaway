//! Taking a place down: a private home listed as a spot, a request under
//! the GDPR, a court order (`docs/deploy.md`, "Taking a place down").
//!
//! Two steps, each under the role allowed to take it. [`take_down`] runs
//! under the writers' lock with the importers' role, the only writer of
//! places and records: the place and the places merged into it become
//! tombstones that keep their id, kind and country and nothing else, every
//! record that described them is emptied, unlinked and marked so that no
//! import writes it again (the retired records near it that name no place
//! only when the moderator asks, since they may be another spot's), and the
//! submissions about them lose their content. The tombstone takes a new position in the change feed, which
//! hands it to every device (`places::changes`). [`purge_community`] then
//! runs with the API's role, which writes the community's content: the
//! reviews, photos, confirmations and issue reports of the emptied place,
//! which accepts no new one, are deleted. The API's role cannot start a
//! takedown: a leak of its credentials must not empty the catalogue.
//!
//! Before the positions go, [`take_down`] keeps the keyed hashes of the
//! cells around them (`takedown_cells`, `lunaway_domain::takedown`): the
//! conflation holds for a moderator any new place, or any place moving,
//! into those cells ([`crate::holds`]), so the spot listed again by another
//! account, element or source does not go live unseen.

use std::collections::BTreeSet;

use lunaway_domain::{
    PlaceKind, Position,
    conflation::score::{MAX_KIND_RADIUS_M, kind_radius_m},
    takedown::{CellHash, TakedownCode, TakedownKey},
};
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{DbError, PgPool, conflation::WriterTx};

/// What a takedown would touch, for the moderator to check before it runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Preview {
    /// The place taken down: the one named, or the place that absorbed it.
    pub place: Uuid,
    /// Its name now; `None` once emptied.
    pub name: Option<String>,
    /// Whether it is live: a tombstone is emptied all the same.
    pub live: bool,
    /// Whether it was taken down already.
    pub taken_down: bool,
    /// Its sync region, whose pack is built again afterwards.
    pub region: Option<String>,
    /// The places merged into it, emptied with it.
    pub merged: i64,
    /// The records emptied with it: linked to it or to a place merged into
    /// it, now or when the conflation last unlinked them, or written from
    /// its submissions.
    pub records: i64,
    /// Retired, unlinked records near it that name no place: unlinked
    /// before Lunaway kept the place a record leaves, they may be its own,
    /// or another spot's. Emptied only when asked (`with_nearby`).
    pub nearby: Vec<Nearby>,
    /// Records near it the conflation has not read yet: a takedown waits
    /// for them, or one of them could become the place again.
    pub unconflated: i64,
    /// Their reviews and ratings, deleted by [`purge_community`].
    pub reviews: i64,
    /// Their photos, deleted with their files.
    pub photos: i64,
    /// Their "still there?" answers.
    pub confirmations: i64,
    /// Their issue reports.
    pub issue_reports: i64,
    /// The submissions about them, emptied.
    pub submissions: i64,
}

/// A retired, unlinked record near a place, for the moderator to judge.
#[derive(Debug, Clone, PartialEq)]
pub struct Nearby {
    /// The record.
    pub id: Uuid,
    /// Its source.
    pub source_id: String,
    /// Its id in the source.
    pub external_id: String,
    /// Its name.
    pub name: Option<String>,
    /// Its kind code.
    pub kind: String,
    /// Its distance to the nearest place of the family, metres.
    pub distance_m: f64,
}

impl Eq for Nearby {}

/// What [`take_down`] did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TakeDown {
    /// No such place.
    NoPlace,
    /// Records near the place wait for the conflation (this many): one of
    /// them could become the place again, so nothing was done.
    Unconflated(i64),
    /// The secret is not the one the earlier takedowns were made with: its
    /// cells would match none of theirs, so nothing was done.
    OtherKey,
    /// Done.
    Done(TakenDown),
}

/// What a takedown emptied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TakenDown {
    /// The place taken down, merges followed.
    pub place: Uuid,
    /// Its sync region before it was emptied: the pack to build again with
    /// `--takedown`.
    pub region: Option<String>,
    /// Places emptied: the place and those merged into it.
    pub places: u64,
    /// Records emptied.
    pub records: u64,
    /// The place, then the places merged into it.
    pub family: Vec<Uuid>,
    /// The hashes of the cells around the positions it emptied, stored in
    /// `takedown_cells` (none when it ran again on what was emptied).
    pub cells: Vec<CellHash>,
}

/// What [`purge_community`] did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Purge {
    /// No such place.
    NoPlace,
    /// The place is not taken down: the catalogue step comes first, so that
    /// nothing arrives after the purge.
    NotTakenDown,
    /// The community's content is gone.
    Done {
        /// The place, merges followed.
        place: Uuid,
        /// Reviews deleted.
        reviews: u64,
        /// Photos deleted.
        photos: u64,
        /// Answers deleted.
        confirmations: u64,
        /// Issue reports deleted.
        issue_reports: u64,
        /// The photo files no other photo shows, for the caller to remove
        /// from the media root.
        orphan_files: Vec<String>,
    },
}

/// The place `id` ends at, following merges: a place merged into another
/// is taken down through the one that absorbed it. `None` when there is no
/// such place.
async fn end_of_merges(conn: &mut PgConnection, id: Uuid) -> Result<Option<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        WITH RECURSIVE chain(id, next, depth) AS (
            SELECT id, merged_into, 0 FROM places WHERE id = $1
            UNION ALL
            SELECT p.id, p.merged_into, c.depth + 1
            FROM chain c JOIN places p ON p.id = c.next
            WHERE c.depth < 64
        )
        SELECT id AS "id!" FROM chain ORDER BY depth DESC LIMIT 1
        "#,
        id
    )
    .fetch_optional(conn)
    .await?)
}

/// `place` and every place merged into it, however many merges ago,
/// `place` first.
async fn family(conn: &mut PgConnection, place: Uuid) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
        )
        SELECT id AS "id!" FROM family ORDER BY id <> $1, id
        "#,
        place
    )
    .fetch_all(conn)
    .await?)
}

/// The records a takedown of `family` empties for sure: those linked to
/// its places, those the conflation unlinked from them, and the community
/// records of its submissions. Each branch reads an index: this runs under
/// the writers' lock. Records already taken down are left out: they are
/// empty.
async fn records_of(conn: &mut PgConnection, family: &[Uuid]) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT r.id AS "id!" FROM source_records r
        WHERE r.taken_down_at IS NULL AND r.id IN (
            SELECT id FROM source_records WHERE last_place_id = ANY($1)
            UNION
            SELECT record_id FROM place_sources WHERE place_id = ANY($1)
            UNION
            SELECT record_id FROM place_submissions
            WHERE place_id = ANY($1) AND record_id IS NOT NULL)
        "#,
        family,
    )
    .fetch_all(conn)
    .await?)
}

/// The kinds and the conflation's reach of each, for the searches by
/// position.
fn radii() -> (Vec<&'static str>, Vec<f64>) {
    PlaceKind::ALL
        .iter()
        .map(|k| (k.code(), kind_radius_m(*k)))
        .unzip()
}

/// Retired, unlinked records that name no place, within their kind's reach
/// of a place of `family` not yet emptied, nearest first: records unlinked
/// before `last_place_id` existed, which may be the family's or another
/// spot's. A record placed at its commune only (never a place's) is left
/// out.
async fn nearby_of(conn: &mut PgConnection, family: &[Uuid]) -> Result<Vec<Nearby>, DbError> {
    let (kinds, reach) = radii();
    Ok(sqlx::query_as!(
        Nearby,
        r#"
        SELECT r.id AS "id!", r.source_id AS "source_id!", r.external_id AS "external_id!",
               r.name, r.kind AS "kind!", min(ST_Distance(r.geom, p.geom)) AS "distance_m!"
        FROM places p
        JOIN source_records r ON ST_DWithin(r.geom, p.geom, $4)
        JOIN UNNEST($2::text[], $3::float8[]) AS k(kind, reach) ON k.kind = r.kind
        WHERE p.id = ANY($1) AND p.taken_down_at IS NULL
          AND r.taken_down_at IS NULL AND r.deleted_at IS NOT NULL AND r.last_place_id IS NULL
          AND (r.data->>'position_approximate')::boolean IS NOT TRUE
          AND NOT EXISTS (SELECT 1 FROM place_sources ps WHERE ps.record_id = r.id)
          AND ST_DWithin(r.geom, p.geom, k.reach)
        GROUP BY r.id
        ORDER BY 6, r.id
        "#,
        family,
        &kinds as &[&str],
        &reach,
        MAX_KIND_RADIUS_M,
    )
    .fetch_all(conn)
    .await?)
}

/// Records within the conflation's widest reach of a place of `family` not
/// yet emptied that it has not read yet.
async fn unconflated_near(conn: &mut PgConnection, family: &[Uuid]) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT count(DISTINCT r.id) AS "n!"
        FROM places p
        JOIN source_records r ON ST_DWithin(r.geom, p.geom, $2)
        WHERE p.id = ANY($1) AND p.taken_down_at IS NULL
          AND r.needs_conflation AND r.taken_down_at IS NULL
        "#,
        family,
        MAX_KIND_RADIUS_M,
    )
    .fetch_one(conn)
    .await?)
}

/// What taking down `place` would touch; `None` when there is no such
/// place. Readable by both roles.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn preview(pool: &PgPool, place: Uuid) -> Result<Option<Preview>, DbError> {
    let mut conn = pool.acquire().await?;
    let Some(root) = end_of_merges(&mut conn, place).await? else {
        return Ok(None);
    };
    let family = family(&mut conn, root).await?;
    let records = records_of(&mut conn, &family).await?;
    let nearby = nearby_of(&mut conn, &family).await?;
    let unconflated = unconflated_near(&mut conn, &family).await?;
    let r = sqlx::query!(
        r#"
        SELECT p.name, p.deleted_at IS NULL AS "live!", p.taken_down_at IS NOT NULL AS "taken!",
               p.region,
            (SELECT count(*) FROM reviews WHERE place_id = ANY($2)) AS "reviews!",
            (SELECT count(*) FROM photos WHERE place_id = ANY($2)) AS "photos!",
            (SELECT count(*) FROM confirmations WHERE place_id = ANY($2)) AS "confirmations!",
            (SELECT count(*) FROM issue_reports WHERE place_id = ANY($2)) AS "issues!",
            (SELECT count(*) FROM place_submissions WHERE place_id = ANY($2))
                AS "submissions!"
        FROM places p WHERE p.id = $1
        "#,
        root,
        &family,
    )
    .fetch_one(&mut *conn)
    .await?;
    let count = |n: usize| i64::try_from(n).unwrap_or(i64::MAX);
    Ok(Some(Preview {
        place: root,
        name: r.name,
        live: r.live,
        taken_down: r.taken,
        region: r.region,
        merged: count(family.len()) - 1,
        records: count(records.len()),
        nearby,
        unconflated,
        reviews: r.reviews,
        photos: r.photos,
        confirmations: r.confirmations,
        issue_reports: r.issues,
        submissions: r.submissions,
    }))
}

/// Where `place` stands, merges followed: `None` when there is no such
/// place.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Standing {
    /// The place it ends at, merges followed.
    pub root: Uuid,
    /// Whether that place is taken down.
    pub taken_down: bool,
    /// The root and every place merged into it, which a takedown of the
    /// root empties.
    pub family: Vec<Uuid>,
}

/// Where `place` stands, merges followed: what the replay of the journal
/// checks before it takes a place down again.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn standing(pool: &PgPool, place: Uuid) -> Result<Option<Standing>, DbError> {
    let mut conn = pool.acquire().await?;
    let Some(root) = end_of_merges(&mut conn, place).await? else {
        return Ok(None);
    };
    let taken_down = sqlx::query_scalar!(
        r#"SELECT taken_down_at IS NOT NULL AS "taken!" FROM places WHERE id = $1"#,
        root
    )
    .fetch_one(&mut *conn)
    .await?;
    let family = family(&mut conn, root).await?;
    Ok(Some(Standing {
        root,
        taken_down,
        family,
    }))
}

/// The positions about to be emptied: the places of `family` and the
/// records `records` not emptied yet, without the records placed at their
/// commune only (a town hall is nobody's home).
async fn positions_of(
    conn: &mut PgConnection,
    family: &[Uuid],
    records: &[Uuid],
) -> Result<Vec<Position>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!"
        FROM places WHERE id = ANY($1) AND taken_down_at IS NULL
        UNION
        SELECT ST_Y(geom::geometry), ST_X(geom::geometry)
        FROM source_records
        WHERE id = ANY($2) AND taken_down_at IS NULL
          AND (data->>'position_approximate')::boolean IS NOT TRUE
        "#,
        family,
        records,
    )
    .fetch_all(conn)
    .await?;
    rows.into_iter()
        .map(|r| Position::new(r.lat, r.lon).map_err(|e| DbError::decode("position", e)))
        .collect()
}

/// Stores `cells` as the exclusion zone of `place`; those already there
/// stay. Returns how many were new.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn insert_cells(
    tx: &mut WriterTx,
    place: Uuid,
    cells: &[CellHash],
) -> Result<u64, DbError> {
    let bytes: Vec<Vec<u8>> = cells.iter().map(|c| c.as_bytes().to_vec()).collect();
    let done = sqlx::query!(
        r#"
        INSERT INTO takedown_cells (cell, place_id)
        SELECT c, $2 FROM UNNEST($1::bytea[]) AS c
        ON CONFLICT DO NOTHING
        "#,
        &bytes,
        place,
    )
    .execute(tx.conn())
    .await?;
    Ok(done.rows_affected())
}

/// Whether `key` is the secret the takedowns were made with: `true` when
/// it is, or when no takedown stored a check value yet (`record` stores
/// it then, in the transaction).
async fn same_key(tx: &mut WriterTx, key: &TakedownKey, record: bool) -> Result<bool, DbError> {
    let check = key.check().as_bytes().to_vec();
    let stored = sqlx::query_scalar!("SELECT key_check FROM takedown_key")
        .fetch_optional(tx.conn())
        .await?;
    match stored {
        Some(s) => Ok(s == check),
        None => {
            if record {
                sqlx::query!(
                    "INSERT INTO takedown_key (key_check) VALUES ($1) ON CONFLICT DO NOTHING",
                    check
                )
                .execute(tx.conn())
                .await?;
            }
            Ok(true)
        }
    }
}

/// Whether `key` is the secret the takedowns were made with (or none was
/// made yet): the conflation holds nothing under another one, and says so.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn is_takedown_key(tx: &mut WriterTx, key: &TakedownKey) -> Result<bool, DbError> {
    same_key(tx, key, false).await
}

/// Like [`is_takedown_key`], storing `key`'s check value when none is
/// stored yet: the replay of the journal does, so a later worker under
/// another secret is told apart even when nothing was taken down again.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn adopt_key(tx: &mut WriterTx, key: &TakedownKey) -> Result<bool, DbError> {
    same_key(tx, key, true).await
}

/// `place`'s family as the writer transaction sees it, `place` first.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn family_in(tx: &mut WriterTx, place: Uuid) -> Result<Vec<Uuid>, DbError> {
    family(tx.conn(), place).await
}

/// Every cell of every takedown's zone, for the conflation to check its
/// new and moved places against.
///
/// # Errors
///
/// [`DbError`] when the query fails or a stored cell is not 32 bytes.
pub async fn exclusion_cells(tx: &mut WriterTx) -> Result<Vec<CellHash>, DbError> {
    let rows = sqlx::query_scalar!(r#"SELECT DISTINCT cell AS "cell!" FROM takedown_cells"#)
        .fetch_all(tx.conn())
        .await?;
    rows.iter()
        .map(|b| {
            CellHash::from_slice(b).ok_or_else(|| {
                DbError::decode(
                    "takedown cell",
                    lunaway_domain::UnknownCode {
                        kind: "CellHash",
                        code: format!("{} bytes", b.len()),
                    },
                )
            })
        })
        .collect()
}

/// Takes `place` down, merges followed: keeps the hashes of the cells
/// around its positions and its records' (`key`), empties it, the places
/// merged into it and their records (and the nearby retired records
/// [`Preview`] lists, when `with_nearby`), and logs it with the kind of
/// request `code`, never a text that could name the requester; the first
/// code stays when it runs again, which empties what was missed. Refused
/// while records near the place wait for the conflation.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn take_down(
    tx: &mut WriterTx,
    place: Uuid,
    code: TakedownCode,
    with_nearby: bool,
    key: &TakedownKey,
) -> Result<TakeDown, DbError> {
    let Some(root) = end_of_merges(tx.conn(), place).await? else {
        return Ok(TakeDown::NoPlace);
    };
    if !same_key(tx, key, true).await? {
        return Ok(TakeDown::OtherKey);
    }
    let family = family(tx.conn(), root).await?;
    let waiting = unconflated_near(tx.conn(), &family).await?;
    if waiting > 0 {
        return Ok(TakeDown::Unconflated(waiting));
    }
    let region = sqlx::query_scalar!("SELECT region FROM places WHERE id = $1", root)
        .fetch_one(tx.conn())
        .await?;
    let mut records = records_of(tx.conn(), &family).await?;
    if with_nearby {
        records.extend(
            nearby_of(tx.conn(), &family)
                .await?
                .into_iter()
                .map(|n| n.id),
        );
    }
    // The cells go in before the positions go: the zone is made of where
    // the place and its records stood.
    let cells: Vec<CellHash> = positions_of(tx.conn(), &family, &records)
        .await?
        .into_iter()
        .flat_map(|p| key.zone(p))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    insert_cells(tx, root, &cells).await?;
    empty(tx.conn(), &family, &records).await?;
    sqlx::query!(
        r#"
        INSERT INTO place_takedowns (place_id, reason) VALUES ($1, $2)
        ON CONFLICT (place_id) DO NOTHING
        "#,
        root,
        code.code(),
    )
    .execute(tx.conn())
    .await?;
    Ok(TakeDown::Done(TakenDown {
        place: root,
        region,
        places: u64::try_from(family.len()).unwrap_or(u64::MAX),
        records: u64::try_from(records.len()).unwrap_or(u64::MAX),
        family,
        cells,
    }))
}

/// Empties the places `family`, the records `records` and the submissions
/// about them. The point (0, 0) stands for "no position" in the NOT NULL
/// geometry columns: no spot of the catalogue lies there, in the Gulf of
/// Guinea.
async fn empty(conn: &mut PgConnection, family: &[Uuid], records: &[Uuid]) -> Result<(), DbError> {
    // A record keeps its source, its external id (the key that keeps the
    // next import out of it, `records::upsert`) and its kind (so the
    // conflation can still read it).
    sqlx::query!(
        r#"
        UPDATE source_records SET
            name = NULL, external_url = NULL,
            geom = ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, accuracy_m = 0,
            data = jsonb_build_object('kind', data->'kind',
                                      'position', jsonb_build_object('lat', 0, 'lon', 0)),
            raw = '{}', deleted_at = coalesce(deleted_at, now()),
            taken_down_at = coalesce(taken_down_at, now()), needs_conflation = false,
            changed_at = now()
        WHERE id = ANY($1)
        "#,
        records
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "DELETE FROM place_sources WHERE record_id = ANY($1) OR place_id = ANY($2)",
        records,
        family
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "DELETE FROM match_pairs WHERE record_a = ANY($1) OR record_b = ANY($1)",
        records
    )
    .execute(&mut *conn)
    .await?;
    // The country stays, so the sync region does too for a country synced
    // whole; a French place loses its commune, and the trigger of
    // `place_region_exits` reports it gone from its region's feed.
    sqlx::query!(
        r#"
        UPDATE places SET
            name = NULL, geom = ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography,
            overnight = 'unknown', services = '{}', activities = '{}', description = NULL,
            street = NULL, postcode = NULL, city = NULL, municipality = NULL,
            municipality_code = NULL, price_parking_eur = NULL, price_services_eur = NULL,
            max_height_m = NULL, max_length_m = NULL, max_width_m = NULL, max_weight_t = NULL,
            capacity = NULL, opening_hours = NULL, opening_hours_parsed = false,
            opening_intervals = NULL, opening_intervals_until = NULL,
            opening_window_start = NULL, opening_refresh_at = NULL, website = NULL,
            phone = NULL, stars = NULL, last_confirmed_at = NULL, provenance = '[]',
            descriptions = '[]', external_links = '[]', rating_avg = NULL, rating_count = 0,
            review_count = 0, photo_count = 0, cover_photos = '[]', reported_issues = '[]',
            content_hash = 'taken-down', deleted_at = coalesce(deleted_at, now()),
            taken_down_at = coalesce(taken_down_at, now()), updated_at = now(),
            updated_seq = nextval('place_change_seq')
        WHERE id = ANY($1)
        "#,
        family
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        r#"
        UPDATE place_submissions SET
            payload = '{}',
            status = CASE WHEN status IN ('proposed', 'accepted') THEN 'rejected'
                          ELSE status END,
            decided_at = coalesce(decided_at, now())
        WHERE place_id = ANY($1) OR record_id = ANY($2)
        "#,
        family,
        records
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "DELETE FROM place_refresh_queue WHERE place_id = ANY($1)",
        family
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// The places taken down whose reviews, photos, answers or issue reports
/// are still there: the second step was not run, or a restore brought the
/// content back. Readable by both roles.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn unpurged(pool: &PgPool) -> Result<Vec<Uuid>, DbError> {
    Ok(sqlx::query_scalar!(
        r#"
        SELECT p.id FROM places p
        WHERE p.taken_down_at IS NOT NULL
          AND (EXISTS (SELECT 1 FROM reviews WHERE place_id = p.id)
               OR EXISTS (SELECT 1 FROM photos WHERE place_id = p.id)
               OR EXISTS (SELECT 1 FROM confirmations WHERE place_id = p.id)
               OR EXISTS (SELECT 1 FROM issue_reports WHERE place_id = p.id))
        ORDER BY p.id
        "#
    )
    .fetch_all(pool)
    .await?)
}

/// Deletes the community's content of `place` (merges followed) and of the
/// places merged into it, once it is taken down: reviews, photos (their
/// files are the caller's to remove), "still there?" answers, issue
/// reports, and the content reports and queue entries about them.
///
/// # Errors
///
/// [`DbError`] when a statement fails.
pub async fn purge_community(pool: &PgPool, place: Uuid) -> Result<Purge, DbError> {
    let mut tx = pool.begin().await?;
    let Some(root) = end_of_merges(&mut tx, place).await? else {
        return Ok(Purge::NoPlace);
    };
    let taken = sqlx::query_scalar!(
        r#"SELECT taken_down_at IS NOT NULL AS "taken!" FROM places WHERE id = $1"#,
        root
    )
    .fetch_one(&mut *tx)
    .await?;
    if !taken {
        return Ok(Purge::NotTakenDown);
    }
    let family = family(&mut tx, root).await?;
    let photos = sqlx::query!(
        "DELETE FROM photos WHERE place_id = ANY($1) RETURNING id, path, thumb_path",
        &family
    )
    .fetch_all(&mut *tx)
    .await?;
    let mut gone: Vec<Uuid> = photos.iter().map(|p| p.id).collect();
    let mut files: Vec<String> = photos
        .into_iter()
        .flat_map(|p| [p.path, p.thumb_path])
        .collect();
    files.sort();
    files.dedup();
    let orphan_files = crate::community::unserved(&mut tx, &files).await?;
    let reviews = sqlx::query_scalar!(
        "DELETE FROM reviews WHERE place_id = ANY($1) RETURNING id",
        &family
    )
    .fetch_all(&mut *tx)
    .await?;
    let confirmations = sqlx::query_scalar!(
        "DELETE FROM confirmations WHERE place_id = ANY($1) RETURNING id",
        &family
    )
    .fetch_all(&mut *tx)
    .await?;
    // What the deleted answers left on the place goes with them.
    sqlx::query!(
        "DELETE FROM confirmation_tallies WHERE place_id = ANY($1)",
        &family
    )
    .execute(&mut *tx)
    .await?;
    let issue_reports = sqlx::query_scalar!(
        "DELETE FROM issue_reports WHERE place_id = ANY($1) RETURNING id",
        &family
    )
    .fetch_all(&mut *tx)
    .await?;
    let submissions = sqlx::query_scalar!(
        "SELECT id FROM place_submissions WHERE place_id = ANY($1)",
        &family
    )
    .fetch_all(&mut *tx)
    .await?;
    let count = |ids: &[Uuid]| u64::try_from(ids.len()).unwrap_or(u64::MAX);
    let done = Purge::Done {
        place: root,
        photos: count(&gone),
        reviews: count(&reviews),
        confirmations: count(&confirmations),
        issue_reports: count(&issue_reports),
        orphan_files,
    };
    gone.extend(reviews);
    gone.extend(confirmations);
    gone.extend(issue_reports);
    gone.extend(submissions);
    gone.extend(&family);
    // Reports and queue entries about what is gone: a moderator has
    // nothing left to decide, and their excerpts would keep the text.
    sqlx::query!(
        "DELETE FROM content_reports WHERE target_id = ANY($1)",
        &gone
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        "DELETE FROM moderation_queue WHERE target_id = ANY($1)",
        &gone
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(done)
}
