//! The open content of the places and of the points of interest: photos,
//! descriptions and reviews read from open sources (`lunaway content
//! refresh`), what an operator hid of them, and what the card reads.
//!
//! These tables hang on `places` (and their photos and reviews on `pois`
//! too, [`ContentTarget`]) but are not the catalogue: no write here
//! changes what a place or a point is, what the change feed carries or
//! what a pack holds, so neither writers' advisory lock is taken. A content
//! row only takes a key-share lock on its place or point, which the
//! updates of their columns do not wait for. Two content runs, on
//! the other hand, exclude each other ([`RunLock`]): they share files and
//! the sources' rate limits.

use std::collections::HashMap;

use chrono::{DateTime, NaiveDate, Utc};
use sqlx::{Connection, PgConnection, PgPool};
use uuid::Uuid;

use crate::DbError;

/// The key of the content runs' advisory lock (`lunacont` in ASCII),
/// distinct from the catalogue writers', the points', the road events'
/// and the pack builds'.
const RUN_LOCK_KEY: i64 = 0x6c75_6e61_636f_6e74;

/// Held while a content run works; a second run does not start. The lock
/// lives on a connection of its own, taken out of the pool: closing it,
/// at [`RunLock::release`] or when the process dies, releases the lock.
#[derive(Debug)]
pub struct RunLock(PgConnection);

impl RunLock {
    /// Takes the lock, or `None` when another run holds it.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the database cannot be reached.
    pub async fn try_acquire(pool: &PgPool) -> Result<Option<Self>, DbError> {
        let mut conn = pool.acquire().await?.detach();
        let got = sqlx::query_scalar!(r#"SELECT pg_try_advisory_lock($1) AS "got!""#, RUN_LOCK_KEY)
            .fetch_one(&mut conn)
            .await?;
        if got {
            Ok(Some(Self(conn)))
        } else {
            conn.close().await?;
            Ok(None)
        }
    }

    /// Releases the lock and closes its connection.
    ///
    /// # Errors
    ///
    /// [`DbError`] when the connection fails; the lock goes with it.
    pub async fn release(self) -> Result<(), DbError> {
        Ok(self.0.close().await?)
    }
}

/// The OpenStreetMap tags and identifiers of a place's records that lead
/// to open content.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PlaceLinks {
    /// `wikimedia_commons` values.
    pub wikimedia_commons: Vec<String>,
    /// `image` values.
    pub image: Vec<String>,
    /// `panoramax` values.
    pub panoramax: Vec<String>,
    /// Wikidata items (`Q42`).
    pub wikidata: Vec<String>,
    /// Wikipedia articles as OpenStreetMap writes them (`fr:Title`).
    pub wikipedia: Vec<String>,
}

/// A place the content worker asks a source about.
#[derive(Debug, Clone, PartialEq)]
pub struct DuePlace {
    /// The place.
    pub id: Uuid,
    /// Its kind code.
    pub kind: String,
    /// Its name.
    pub name: Option<String>,
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
    /// Its country (ISO 3166-1 alpha-2), when known.
    pub country_code: Option<String>,
    /// What its records say that leads to content.
    pub links: PlaceLinks,
    /// When the source was last asked about it; `None` if never.
    pub checked_at: Option<DateTime<Utc>>,
}

impl DuePlace {
    /// Where a run stands once it has been given this place.
    #[must_use]
    pub const fn cursor(&self) -> DueCursor {
        DueCursor {
            checked_at: self.checked_at,
            id: self.id,
        }
    }
}

/// Where a run stands in the order of the places due (never asked first,
/// by id, then the least recently asked, by date and id): the last place
/// it was given. The next batch starts after it, so a place the run tried
/// without marking it asked (a source's failure) is not given again, and
/// no list of the places tried grows with the run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DueCursor {
    /// When that place was last asked; `None` for one never asked.
    pub checked_at: Option<DateTime<Utc>>,
    /// The place.
    pub id: Uuid,
}

fn strings(value: Option<serde_json::Value>) -> Vec<String> {
    let mut out: Vec<String> = value
        .and_then(|v| serde_json::from_value::<Vec<Option<String>>>(v).ok())
        .unwrap_or_default()
        .into_iter()
        .flatten()
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
        .collect();
    out.sort();
    out.dedup();
    out
}

/// A box to work in, degrees: south, west, north, east.
pub type Area = (f64, f64, f64, f64);

/// Which places a source is asked about.
#[derive(Debug, Clone, Copy)]
pub struct DueQuery<'a> {
    /// The source.
    pub source: &'a str,
    /// A place asked about since this is not due.
    pub before: DateTime<Utc>,
    /// Places returned at most.
    pub limit: i64,
    /// Only the places in this box.
    pub area: Option<Area>,
    /// Only the places a live record of this source describes (a source
    /// whose content travels with its records).
    pub with_records_of: Option<&'a str>,
    /// The last place this run was given ([`DuePlace::cursor`]): only the
    /// places after it. `None` for the run's first batch.
    pub after: Option<DueCursor>,
}

/// The lower bound of the places asked before in the order of
/// [`places_due`]: no check is older than the Unix epoch.
const ASKED_FROM: DateTime<Utc> = DateTime::UNIX_EPOCH;

/// Live places the source was never asked about, by id, then those not
/// asked since `before`, least recently asked first, from `q.after` on.
/// Each of the two reads walks an index from where the run stands and
/// stops at the batch's size (the places' key, the checks' source and
/// date), so a batch costs about the same at the run's start and at its
/// end: the list of the places tried this run, compared with every live
/// place, took 94 s a batch after 62 000 of them in production
/// (2026-10-09, `plan/research/82-suites-4.md`). The places are chosen
/// first and their records read after, so a batch reads the records of its
/// own places only.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn places_due(pool: &PgPool, q: DueQuery<'_>) -> Result<Vec<DuePlace>, DbError> {
    // No box at all without an area: a generic plan cannot tell a box of
    // the whole world from a small one, and walked the spatial index
    // instead of the key's (2026-10-09, production).
    let (s, w, n, e) = q.area.map_or((None, None, None, None), |(s, w, n, e)| {
        (Some(s), Some(w), Some(n), Some(e))
    });
    let limit = q.limit.max(0);
    let mut keys: Vec<(Uuid, Option<DateTime<Utc>>)> = Vec::new();
    if q.after.is_none_or(|c| c.checked_at.is_none()) {
        let after = q.after.map_or(Uuid::nil(), |c| c.id);
        keys = sqlx::query_scalar!(
            r#"
            SELECT p.id
            FROM places p
            WHERE p.id > $2
              AND p.deleted_at IS NULL AND p.taken_down_at IS NULL
              AND NOT EXISTS (
                    SELECT 1 FROM content_checks c
                    WHERE c.place_id = p.id AND c.source_id = $1)
              AND ($3::float8 IS NULL OR p.geom::geometry && ST_MakeEnvelope($4, $3, $6, $5, 4326))
              AND ($7::text IS NULL OR EXISTS (
                    SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
                    WHERE ps.place_id = p.id AND r.source_id = $7
                      AND r.deleted_at IS NULL AND r.taken_down_at IS NULL))
            ORDER BY p.id
            LIMIT $8
            "#,
            q.source,
            after,
            s,
            w,
            n,
            e,
            q.with_records_of,
            limit,
        )
        .fetch_all(pool)
        .await?
        .into_iter()
        .map(|id| (id, None))
        .collect();
    }
    let missing = limit.saturating_sub(i64::try_from(keys.len()).unwrap_or(i64::MAX));
    if missing > 0 {
        let (after_at, after_id) = match q.after {
            Some(DueCursor {
                checked_at: Some(at),
                id,
            }) => (at, id),
            _ => (ASKED_FROM, Uuid::nil()),
        };
        let asked = sqlx::query!(
            r#"
            SELECT c.place_id, c.checked_at
            FROM content_checks c
            JOIN places p ON p.id = c.place_id
            WHERE c.source_id = $1 AND c.checked_at < $2
              AND c.checked_at >= $3 AND (c.checked_at, c.place_id) > ($3, $4)
              AND p.deleted_at IS NULL AND p.taken_down_at IS NULL
              AND ($5::float8 IS NULL OR p.geom::geometry && ST_MakeEnvelope($6, $5, $8, $7, 4326))
              AND ($9::text IS NULL OR EXISTS (
                    SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
                    WHERE ps.place_id = p.id AND r.source_id = $9
                      AND r.deleted_at IS NULL AND r.taken_down_at IS NULL))
            ORDER BY c.checked_at, c.place_id
            LIMIT $10
            "#,
            q.source,
            q.before,
            after_at,
            after_id,
            s,
            w,
            n,
            e,
            q.with_records_of,
            missing,
        )
        .fetch_all(pool)
        .await?;
        keys.extend(asked.into_iter().map(|r| (r.place_id, Some(r.checked_at))));
    }
    if keys.is_empty() {
        return Ok(Vec::new());
    }
    let ids: Vec<Uuid> = keys.iter().map(|(id, _)| *id).collect();
    let rows = sqlx::query!(
        r#"
        SELECT p.id, p.kind, p.name, p.country_code,
               ST_Y(p.geom::geometry) AS "lat!", ST_X(p.geom::geometry) AS "lon!",
               l.commons, l.image, l.panoramax, l.wikidata, l.wikipedia
        FROM unnest($1::uuid[]) WITH ORDINALITY AS k(id, n)
        JOIN places p ON p.id = k.id
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(r.raw -> 'tags' ->> 'wikimedia_commons') AS commons,
                   jsonb_agg(r.raw -> 'tags' ->> 'image') AS image,
                   jsonb_agg(r.raw -> 'tags' ->> 'panoramax') AS panoramax,
                   jsonb_agg(r.data ->> 'wikidata') AS wikidata,
                   jsonb_agg(r.data ->> 'wikipedia') AS wikipedia
            FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
            WHERE ps.place_id = p.id AND r.deleted_at IS NULL AND r.taken_down_at IS NULL
        ) l ON true
        ORDER BY k.n
        "#,
        &ids,
    )
    .fetch_all(pool)
    .await?;
    let asked_at: HashMap<Uuid, Option<DateTime<Utc>>> = keys.into_iter().collect();
    Ok(rows
        .into_iter()
        .map(|r| DuePlace {
            checked_at: asked_at.get(&r.id).copied().flatten(),
            id: r.id,
            kind: r.kind,
            name: r.name,
            lat: r.lat,
            lon: r.lon,
            country_code: r.country_code,
            links: PlaceLinks {
                wikimedia_commons: strings(r.commons),
                image: strings(r.image),
                panoramax: strings(r.panoramax),
                wikidata: strings(r.wikidata),
                wikipedia: strings(r.wikipedia),
            },
        })
        .collect())
}

/// Records `source` was asked about `place` at `at`, `found` items kept.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn mark_checked(
    pool: &PgPool,
    place: Uuid,
    source: &str,
    at: DateTime<Utc>,
    found: usize,
) -> Result<(), DbError> {
    let mut conn = pool.acquire().await?;
    mark_checked_on(&mut conn, place, source, at, found).await
}

async fn mark_checked_on(
    conn: &mut PgConnection,
    place: Uuid,
    source: &str,
    at: DateTime<Utc>,
    found: usize,
) -> Result<(), DbError> {
    let found = i32::try_from(found).unwrap_or(i32::MAX);
    sqlx::query!(
        r#"
        INSERT INTO content_checks (place_id, source_id, checked_at, found)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (place_id, source_id)
        DO UPDATE SET checked_at = excluded.checked_at, found = excluded.found
        "#,
        place,
        source,
        at,
        found,
    )
    .execute(conn)
    .await?;
    Ok(())
}

/// Records `source` was asked about the point of interest `poi` at `at`,
/// `found` items kept.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn mark_poi_checked(
    pool: &PgPool,
    poi: Uuid,
    source: &str,
    at: DateTime<Utc>,
    found: usize,
) -> Result<(), DbError> {
    let mut conn = pool.acquire().await?;
    mark_poi_checked_on(&mut conn, poi, source, at, found).await
}

async fn mark_poi_checked_on(
    conn: &mut PgConnection,
    poi: Uuid,
    source: &str,
    at: DateTime<Utc>,
    found: usize,
) -> Result<(), DbError> {
    let found = i32::try_from(found).unwrap_or(i32::MAX);
    sqlx::query!(
        r#"
        INSERT INTO content_poi_checks (poi_id, source_id, checked_at, found)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (poi_id, source_id)
        DO UPDATE SET checked_at = excluded.checked_at, found = excluded.found
        "#,
        poi,
        source,
        at,
        found,
    )
    .execute(conn)
    .await?;
    Ok(())
}

/// The files of a photo, as the media store wrote them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PhotoFiles {
    /// The large image, relative to the media root.
    pub path: String,
    /// The thumbnail, relative to the media root.
    pub thumb_path: String,
    /// Large image width.
    pub width: i32,
    /// Large image height.
    pub height: i32,
    /// ThumbHash bytes.
    pub thumbhash: Vec<u8>,
}

/// The files already made from `version` of a source's item, so another
/// place showing it, or the next weekly pass, downloads nothing.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn stored_files(
    pool: &PgPool,
    source: &str,
    external_id: &str,
    version: &str,
) -> Result<Option<PhotoFiles>, DbError> {
    Ok(sqlx::query_as!(
        PhotoFiles,
        r#"
        SELECT path, thumb_path, width, height, thumbhash
        FROM content_photos
        WHERE source_id = $1 AND external_id = $2 AND version = $3
        LIMIT 1
        "#,
        source,
        external_id,
        version,
    )
    .fetch_optional(pool)
    .await?)
}

/// A photo to show on a place.
#[derive(Debug, Clone, PartialEq)]
pub struct NewPhoto {
    /// The item at its source (`File:<name>`, a picture's UUID).
    pub external_id: String,
    /// The source's version of it, and of how it was framed.
    pub version: String,
    /// `linked`, `facing` or `nearby` (`lunaway_domain::content::PhotoRelation`).
    pub relation: String,
    /// From the place to where it was taken, metres.
    pub distance_m: Option<f32>,
    /// Where it is published.
    pub page_url: String,
    /// Its title.
    pub title: Option<String>,
    /// Its author, as plain text.
    pub author: Option<String>,
    /// Who published it at the source, when that is not the author.
    pub publisher: Option<String>,
    /// The source's date of its last update.
    pub source_updated_on: Option<NaiveDate>,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// When it was taken.
    pub taken_at: Option<DateTime<Utc>>,
    /// The last day it may be shown.
    pub rights_end_on: Option<NaiveDate>,
    /// Its files.
    pub files: PhotoFiles,
}

/// What replacing a set of items left behind.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Replaced {
    /// Rows written or rewritten.
    pub kept: usize,
    /// Rows removed: the source no longer offers them.
    pub removed: usize,
    /// Files no row points at any more: the caller removes them from the
    /// media store.
    pub orphaned_files: Vec<String>,
}

/// Replaces what `source` shows on `place` with `photos` (in their order)
/// and records the check with `found` items, in one transaction.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn replace_photos(
    pool: &PgPool,
    place: Uuid,
    source: &str,
    photos: &[NewPhoto],
    at: DateTime<Utc>,
    found: usize,
) -> Result<Replaced, DbError> {
    replace_photos_of(pool, ContentTarget::Place(place), source, photos, at, found).await
}

/// Replaces what `source` shows on the point of interest `poi` with
/// `photos` (in their order) and records the check with `found` items
/// ([`pois_due`]), in one transaction.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn replace_poi_photos(
    pool: &PgPool,
    poi: Uuid,
    source: &str,
    photos: &[NewPhoto],
    at: DateTime<Utc>,
    found: usize,
) -> Result<Replaced, DbError> {
    replace_photos_of(pool, ContentTarget::Poi(poi), source, photos, at, found).await
}

/// The files of a photo row that a replacement removes or rewrites: they
/// go from the media store once no row points at them.
struct StoredFiles {
    path: String,
    thumb_path: String,
}

async fn replace_photos_of(
    pool: &PgPool,
    target: ContentTarget,
    source: &str,
    photos: &[NewPhoto],
    at: DateTime<Utc>,
    found: usize,
) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    let keep: Vec<String> = photos.iter().map(|p| p.external_id.clone()).collect();
    // One statement per target column, so each walks its own index.
    let gone = match target {
        ContentTarget::Place(place) => {
            sqlx::query_as!(
                StoredFiles,
                r#"
                DELETE FROM content_photos
                WHERE place_id = $1 AND source_id = $2 AND NOT (external_id = ANY($3))
                RETURNING path, thumb_path
                "#,
                place,
                source,
                &keep,
            )
            .fetch_all(&mut *tx)
            .await?
        }
        ContentTarget::Poi(poi) => {
            sqlx::query_as!(
                StoredFiles,
                r#"
                DELETE FROM content_photos
                WHERE poi_id = $1 AND source_id = $2 AND NOT (external_id = ANY($3))
                RETURNING path, thumb_path
                "#,
                poi,
                source,
                &keep,
            )
            .fetch_all(&mut *tx)
            .await?
        }
    };
    let mut candidates = Vec::new();
    for g in &gone {
        candidates.push(g.path.clone());
        candidates.push(g.thumb_path.clone());
    }
    for (rank, p) in photos.iter().enumerate() {
        let rank = i16::try_from(rank).unwrap_or(i16::MAX);
        let previous = match target {
            ContentTarget::Place(place) => {
                sqlx::query_as!(
                    StoredFiles,
                    r#"
                    SELECT path, thumb_path FROM content_photos
                    WHERE place_id = $1 AND source_id = $2 AND external_id = $3
                    "#,
                    place,
                    source,
                    p.external_id,
                )
                .fetch_optional(&mut *tx)
                .await?
            }
            ContentTarget::Poi(poi) => {
                sqlx::query_as!(
                    StoredFiles,
                    r#"
                    SELECT path, thumb_path FROM content_photos
                    WHERE poi_id = $1 AND source_id = $2 AND external_id = $3
                    "#,
                    poi,
                    source,
                    p.external_id,
                )
                .fetch_optional(&mut *tx)
                .await?
            }
        };
        if let Some(prev) = previous {
            candidates.push(prev.path);
            candidates.push(prev.thumb_path);
        }
        upsert_photo(&mut tx, target, source, p, rank, at).await?;
    }
    match target {
        ContentTarget::Place(place) => mark_checked_on(&mut tx, place, source, at, found).await?,
        ContentTarget::Poi(poi) => mark_poi_checked_on(&mut tx, poi, source, at, found).await?,
    }
    let orphaned_files = unreferenced(&mut tx, candidates).await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: photos.len(),
        removed: gone.len(),
        orphaned_files,
    })
}

/// Writes one photo of `source` on `target`, its row's id kept when it
/// was already shown there (a report names a photo by that id).
async fn upsert_photo(
    conn: &mut PgConnection,
    target: ContentTarget,
    source: &str,
    p: &NewPhoto,
    rank: i16,
    at: DateTime<Utc>,
) -> Result<(), DbError> {
    match target {
        ContentTarget::Place(place) => {
            sqlx::query!(
                r#"
                INSERT INTO content_photos (
                    id, place_id, source_id, external_id, version, relation, distance_m,
                    page_url, title, author, licence, licence_url, taken_at,
                    path, thumb_path, width, height, thumbhash, rank, fetched_at,
                    publisher, source_updated_on, rights_end_on)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                        $14, $15, $16, $17, $18, $19, $20, $21, $22, $23)
                ON CONFLICT (place_id, source_id, external_id) DO UPDATE SET
                    version = excluded.version, relation = excluded.relation,
                    distance_m = excluded.distance_m, page_url = excluded.page_url,
                    title = excluded.title, author = excluded.author,
                    licence = excluded.licence, licence_url = excluded.licence_url,
                    taken_at = excluded.taken_at, path = excluded.path,
                    thumb_path = excluded.thumb_path, width = excluded.width,
                    height = excluded.height, thumbhash = excluded.thumbhash,
                    rank = excluded.rank, fetched_at = excluded.fetched_at,
                    publisher = excluded.publisher, source_updated_on = excluded.source_updated_on,
                    rights_end_on = excluded.rights_end_on
                "#,
                Uuid::now_v7(),
                place,
                source,
                p.external_id,
                p.version,
                p.relation,
                p.distance_m,
                p.page_url,
                p.title,
                p.author,
                p.licence,
                p.licence_url,
                p.taken_at,
                p.files.path,
                p.files.thumb_path,
                p.files.width,
                p.files.height,
                p.files.thumbhash,
                rank,
                at,
                p.publisher,
                p.source_updated_on,
                p.rights_end_on,
            )
            .execute(conn)
            .await?;
        }
        ContentTarget::Poi(poi) => {
            sqlx::query!(
                r#"
                INSERT INTO content_photos (
                    id, poi_id, source_id, external_id, version, relation, distance_m,
                    page_url, title, author, licence, licence_url, taken_at,
                    path, thumb_path, width, height, thumbhash, rank, fetched_at,
                    publisher, source_updated_on, rights_end_on)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                        $14, $15, $16, $17, $18, $19, $20, $21, $22, $23)
                ON CONFLICT (poi_id, source_id, external_id) WHERE poi_id IS NOT NULL
                DO UPDATE SET
                    version = excluded.version, relation = excluded.relation,
                    distance_m = excluded.distance_m, page_url = excluded.page_url,
                    title = excluded.title, author = excluded.author,
                    licence = excluded.licence, licence_url = excluded.licence_url,
                    taken_at = excluded.taken_at, path = excluded.path,
                    thumb_path = excluded.thumb_path, width = excluded.width,
                    height = excluded.height, thumbhash = excluded.thumbhash,
                    rank = excluded.rank, fetched_at = excluded.fetched_at,
                    publisher = excluded.publisher, source_updated_on = excluded.source_updated_on,
                    rights_end_on = excluded.rights_end_on
                "#,
                Uuid::now_v7(),
                poi,
                source,
                p.external_id,
                p.version,
                p.relation,
                p.distance_m,
                p.page_url,
                p.title,
                p.author,
                p.licence,
                p.licence_url,
                p.taken_at,
                p.files.path,
                p.files.thumb_path,
                p.files.width,
                p.files.height,
                p.files.thumbhash,
                rank,
                at,
                p.publisher,
                p.source_updated_on,
                p.rights_end_on,
            )
            .execute(conn)
            .await?;
        }
    }
    Ok(())
}

/// Which of `paths` no photo row points at any more.
async fn unreferenced(
    conn: &mut PgConnection,
    mut paths: Vec<String>,
) -> Result<Vec<String>, DbError> {
    paths.sort();
    paths.dedup();
    if paths.is_empty() {
        return Ok(paths);
    }
    Ok(sqlx::query_scalar!(
        r#"
        SELECT f AS "f!" FROM unnest($1::text[]) AS f
        WHERE NOT EXISTS (SELECT 1 FROM content_photos c WHERE c.path = f OR c.thumb_path = f)
        "#,
        &paths,
    )
    .fetch_all(conn)
    .await?)
}

/// Which of `paths` (files found in the media directory) no photo row
/// points at: what a run that stopped between writing a file and storing
/// its row left behind.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn unreferenced_files(pool: &PgPool, paths: Vec<String>) -> Result<Vec<String>, DbError> {
    let mut conn = pool.acquire().await?;
    unreferenced(&mut conn, paths).await
}

/// A description of a place by a source, in one language.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewDescription {
    /// BCP 47 tag.
    pub lang: String,
    /// The text, plain.
    pub text: String,
    /// The title of the page it comes from.
    pub title: Option<String>,
    /// The page.
    pub page_url: String,
    /// Who wrote it, as the source credits them.
    pub author: Option<String>,
    /// Who published it at the source, when that is not the author.
    pub publisher: Option<String>,
    /// The source's date of its last update.
    pub source_updated_on: Option<NaiveDate>,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
}

/// Replaces what `source` says of `place` with `descriptions` (one per
/// language) and records the check with `found` items, in one
/// transaction.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn replace_descriptions(
    pool: &PgPool,
    place: Uuid,
    source: &str,
    descriptions: &[NewDescription],
    at: DateTime<Utc>,
    found: usize,
) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    let langs: Vec<String> = descriptions.iter().map(|d| d.lang.clone()).collect();
    let removed = sqlx::query!(
        "DELETE FROM content_descriptions WHERE place_id = $1 AND source_id = $2 AND NOT (lang = ANY($3))",
        place,
        source,
        &langs,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    for d in descriptions {
        sqlx::query!(
            r#"
            INSERT INTO content_descriptions (
                place_id, source_id, lang, text, title, page_url, author, licence,
                licence_url, fetched_at, publisher, source_updated_on)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
            ON CONFLICT (place_id, source_id, lang) DO UPDATE SET
                text = excluded.text, title = excluded.title, page_url = excluded.page_url,
                author = excluded.author, licence = excluded.licence,
                licence_url = excluded.licence_url, fetched_at = excluded.fetched_at,
                publisher = excluded.publisher, source_updated_on = excluded.source_updated_on
            "#,
            place,
            source,
            d.lang,
            d.text,
            d.title,
            d.page_url,
            d.author,
            d.licence,
            d.licence_url,
            at,
            d.publisher,
            d.source_updated_on,
        )
        .execute(&mut *tx)
        .await?;
    }
    mark_checked_on(&mut tx, place, source, at, found).await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: descriptions.len(),
        removed: usize::try_from(removed).unwrap_or(usize::MAX),
        orphaned_files: Vec::new(),
    })
}

/// What an open review or photo hangs on: a place, or a point of interest
/// (an establishment among them). One of the two, never both: the tables
/// check it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ContentTarget {
    /// A place.
    Place(Uuid),
    /// A point of interest.
    Poi(Uuid),
}

impl ContentTarget {
    /// The place, for a row's `place_id`.
    #[must_use]
    pub const fn place_id(self) -> Option<Uuid> {
        match self {
            Self::Place(id) => Some(id),
            Self::Poi(_) => None,
        }
    }

    /// The point, for a row's `poi_id`.
    #[must_use]
    pub const fn poi_id(self) -> Option<Uuid> {
        match self {
            Self::Place(_) => None,
            Self::Poi(id) => Some(id),
        }
    }

    /// The target a row's `place_id` and `poi_id` name; `None` when they
    /// name none or both, which the tables refuse.
    #[must_use]
    pub const fn from_columns(place: Option<Uuid>, poi: Option<Uuid>) -> Option<Self> {
        match (place, poi) {
            (Some(id), None) => Some(Self::Place(id)),
            (None, Some(id)) => Some(Self::Poi(id)),
            _ => None,
        }
    }
}

impl std::fmt::Display for ContentTarget {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Place(id) => write!(f, "place {id}"),
            Self::Poi(id) => write!(f, "point {id}"),
        }
    }
}

/// A review read from an open source, already matched to a place or a
/// point.
#[derive(Debug, Clone, PartialEq)]
pub struct NewReview {
    /// The place or the point it is about.
    pub target: ContentTarget,
    /// The review at its source (its signature).
    pub external_id: String,
    /// Stars, 1 to 5.
    pub rating: Option<i16>,
    /// Its text.
    pub text: Option<String>,
    /// The language of the text.
    pub lang: Option<String>,
    /// The reviewer's pseudonym.
    pub author: Option<String>,
    /// The SHA-256 of the key that signed it, hexadecimal.
    pub author_key: Option<String>,
    /// When it was written.
    pub written_at: DateTime<Utc>,
    /// Where it is published.
    pub page_url: String,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// From the place to where the review says it is, metres.
    pub distance_m: Option<f32>,
}

/// The keys of `source` whose reviews Lunaway kept, with when it first
/// kept one. A key absent from it is new, and so is a key one of whose
/// reviews stands hidden (`content_review_strikes`). The key of a review
/// stored now and absent from `content_review_keys` counts too, from the
/// last run that fetched the review: a release older than that table
/// stored reviews without recording their keys, and the next run must not
/// take those reviewers for new ones.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn review_keys(
    pool: &PgPool,
    source: &str,
) -> Result<HashMap<String, DateTime<Utc>>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT author_key AS "author_key!", min(since) AS "since!"
        FROM (
            SELECT author_key, first_kept_at AS since
            FROM content_review_keys WHERE source_id = $1
            UNION ALL
            SELECT r.author_key, r.fetched_at
            FROM content_reviews r
            WHERE r.source_id = $1 AND r.author_key IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM content_review_keys k
                  WHERE k.source_id = r.source_id AND k.author_key = r.author_key)
        ) known
        WHERE NOT EXISTS (
            SELECT 1 FROM content_review_strikes s
            JOIN content_hides h
              ON h.source_id = s.source_id AND h.scope = 'review' AND h.key = s.external_id
            WHERE s.source_id = $1 AND s.author_key = known.author_key)
        GROUP BY author_key
        "#,
        source,
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| (r.author_key, r.since)).collect())
}

/// Records a strike against the key of each stored review of `source`
/// that a hide names: its author could sign the same review again under a
/// new signature, which the hide does not match, and the key ranks with
/// the new ones while the hide stands. Run before [`replace_reviews`],
/// while the hidden review is still stored. Returns the strikes recorded
/// by this call.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn record_review_strikes(pool: &PgPool, source: &str) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        INSERT INTO content_review_strikes (source_id, author_key, external_id)
        SELECT r.source_id, r.author_key, r.external_id
        FROM content_reviews r
        JOIN content_hides h
          ON h.source_id = r.source_id AND h.scope = 'review' AND h.key = r.external_id
        WHERE r.source_id = $1 AND r.author_key IS NOT NULL
        ON CONFLICT DO NOTHING
        "#,
        source,
    )
    .execute(pool)
    .await?
    .rows_affected())
}

/// The places and points each key of `source` has a review shown on now,
/// as `(target, key)` pairs: a review there takes no new room. A hidden
/// review shows nowhere, so its key gains no pair from it.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn review_pairs(
    pool: &PgPool,
    source: &str,
) -> Result<std::collections::HashSet<(ContentTarget, String)>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT DISTINCT r.place_id, r.poi_id, r.author_key AS "author_key!"
        FROM content_reviews r
        WHERE r.source_id = $1 AND r.author_key IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = r.source_id AND h.scope = 'review' AND h.key = r.external_id)
        "#,
        source,
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .filter_map(|r| {
            Some((
                ContentTarget::from_columns(r.place_id, r.poi_id)?,
                r.author_key,
            ))
        })
        .collect())
}

/// When Lunaway first read each review of `signatures`, recording `at`
/// for those read now for the first time; the sightings of reviews no
/// longer read go.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn sight_reviews(
    pool: &PgPool,
    source: &str,
    signatures: &[String],
    at: DateTime<Utc>,
) -> Result<HashMap<String, DateTime<Utc>>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!(
        r#"
        DELETE FROM content_review_sightings
        WHERE source_id = $1 AND NOT (external_id = ANY($2))
        "#,
        source,
        signatures,
    )
    .execute(&mut *tx)
    .await?;
    sqlx::query!(
        r#"
        INSERT INTO content_review_sightings (source_id, external_id, first_seen_at)
        SELECT $1, s, $3 FROM unnest($2::text[]) AS s
        ON CONFLICT DO NOTHING
        "#,
        source,
        signatures,
        at,
    )
    .execute(&mut *tx)
    .await?;
    let rows = sqlx::query!(
        "SELECT external_id, first_seen_at FROM content_review_sightings WHERE source_id = $1",
        source,
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(rows
        .into_iter()
        .map(|r| (r.external_id, r.first_seen_at))
        .collect())
}

/// Replaces every review of `source` with `reviews`, the whole of what the
/// source holds, places and points together, in one transaction, and
/// records the keys of the reviews
/// kept. A review gone from the source goes from Lunaway, except one the
/// reports hid while a moderator has not decided: never shown, it stays
/// until the decision, so the moderator still finds it by its id once its
/// author signed it anew, and keeping it lifts the strike on its key
/// (`review_keys`). A moderator's or the operator's hide is final and
/// needs no row: the strike and the hide stand without it.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn replace_reviews(
    pool: &PgPool,
    source: &str,
    reviews: &[NewReview],
    at: DateTime<Utc>,
) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    let keep: Vec<String> = reviews.iter().map(|r| r.external_id.clone()).collect();
    let removed = sqlx::query!(
        r#"
        DELETE FROM content_reviews r
        WHERE r.source_id = $1 AND NOT (r.external_id = ANY($2))
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = r.source_id AND h.scope = 'review' AND h.key = r.external_id
                AND h.origin = 'reports')
        "#,
        source,
        &keep,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    for r in reviews {
        sqlx::query!(
            r#"
            INSERT INTO content_reviews (
                id, place_id, source_id, external_id, rating, text, lang, author,
                written_at, page_url, licence, licence_url, distance_m, fetched_at, author_key,
                poi_id)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
            ON CONFLICT (source_id, external_id) DO UPDATE SET
                place_id = excluded.place_id, poi_id = excluded.poi_id, rating = excluded.rating,
                text = excluded.text, lang = excluded.lang, author = excluded.author,
                written_at = excluded.written_at, page_url = excluded.page_url,
                licence = excluded.licence, licence_url = excluded.licence_url,
                distance_m = excluded.distance_m, fetched_at = excluded.fetched_at,
                author_key = excluded.author_key
            "#,
            crate::extcom::review_id(r.written_at),
            r.target.place_id(),
            source,
            r.external_id,
            r.rating,
            r.text,
            r.lang,
            r.author,
            r.written_at,
            r.page_url,
            r.licence,
            r.licence_url,
            r.distance_m,
            at,
            r.author_key,
            r.target.poi_id(),
        )
        .execute(&mut *tx)
        .await?;
    }
    // A key earns its history by a kept review, and keeps it when the
    // review goes (`content_review_keys`).
    let keys: Vec<String> = reviews
        .iter()
        .filter_map(|r| r.author_key.clone())
        .collect();
    sqlx::query!(
        r#"
        INSERT INTO content_review_keys (source_id, author_key, first_kept_at)
        SELECT $1, k, $3 FROM unnest($2::text[]) AS k
        ON CONFLICT (source_id, author_key) DO NOTHING
        "#,
        source,
        &keys,
        at,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: reviews.len(),
        removed: usize::try_from(removed).unwrap_or(usize::MAX),
        orphaned_files: Vec::new(),
    })
}

/// A live place near a point, for matching what a source places there.
#[derive(Debug, Clone, PartialEq)]
pub struct NearPlace {
    /// The place.
    pub id: Uuid,
    /// Its kind code.
    pub kind: String,
    /// Its name.
    pub name: Option<String>,
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
}

/// Live places within `radius_m` of a point, nearest first, at most 20.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn places_near(
    pool: &PgPool,
    lat: f64,
    lon: f64,
    radius_m: f64,
) -> Result<Vec<NearPlace>, DbError> {
    Ok(sqlx::query_as!(
        NearPlace,
        r#"
        SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!"
        FROM places
        WHERE deleted_at IS NULL AND taken_down_at IS NULL
          AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)
        ORDER BY geom <-> ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        LIMIT 20
        "#,
        lat,
        lon,
        radius_m,
    )
    .fetch_all(pool)
    .await?)
}

/// Removes the content of places that are gone (deleted, taken down or
/// merged into another) and their checks; the place a gone one was merged
/// into is asked again at the next pass, since it may now carry the
/// links its records brought.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn purge_gone_places(pool: &PgPool) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!(
        r#"
        DELETE FROM content_checks c
        WHERE c.place_id IN (
            SELECT p.merged_into FROM places p
            WHERE p.merged_into IS NOT NULL
              AND EXISTS (SELECT 1 FROM content_checks g WHERE g.place_id = p.id))
        "#
    )
    .execute(&mut *tx)
    .await?;
    let gone = sqlx::query!(
        r#"
        DELETE FROM content_photos c USING places p
        WHERE p.id = c.place_id AND (p.deleted_at IS NOT NULL OR p.taken_down_at IS NOT NULL)
        RETURNING c.path, c.thumb_path
        "#
    )
    .fetch_all(&mut *tx)
    .await?;
    let descriptions = sqlx::query!(
        r#"
        DELETE FROM content_descriptions c USING places p
        WHERE p.id = c.place_id AND (p.deleted_at IS NOT NULL OR p.taken_down_at IS NOT NULL)
        "#
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let reviews = sqlx::query!(
        r#"
        DELETE FROM content_reviews c USING places p
        WHERE p.id = c.place_id AND (p.deleted_at IS NOT NULL OR p.taken_down_at IS NOT NULL)
        "#
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    sqlx::query!(
        r#"
        DELETE FROM content_checks c USING places p
        WHERE p.id = c.place_id AND (p.deleted_at IS NOT NULL OR p.taken_down_at IS NOT NULL)
        "#
    )
    .execute(&mut *tx)
    .await?;
    let mut candidates = Vec::new();
    for g in &gone {
        candidates.push(g.path.clone());
        candidates.push(g.thumb_path.clone());
    }
    let orphaned_files = unreferenced(&mut tx, candidates).await?;
    tx.commit().await?;
    let removed = gone.len()
        + usize::try_from(descriptions).unwrap_or(usize::MAX)
        + usize::try_from(reviews).unwrap_or(usize::MAX);
    Ok(Replaced {
        kept: 0,
        removed,
        orphaned_files,
    })
}

/// A record's payload as its source sent it.
#[derive(Debug, Clone, PartialEq)]
pub struct Payload {
    /// The record's id at its source.
    pub external_id: String,
    /// What the source sent.
    pub raw: serde_json::Value,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
}

/// The payloads of the live records of `source` that describe `place`.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn payloads(pool: &PgPool, place: Uuid, source: &str) -> Result<Vec<Payload>, DbError> {
    Ok(sqlx::query_as!(
        Payload,
        r#"
        SELECT r.external_id, r.raw, r.fetched_at
        FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
        WHERE ps.place_id = $1 AND r.source_id = $2
          AND r.deleted_at IS NULL AND r.taken_down_at IS NULL
        ORDER BY r.external_id
        "#,
        place,
        source,
    )
    .fetch_all(pool)
    .await?)
}

/// Removes the photos and descriptions of `source` from the places no
/// live record of `source` describes any more (its record was retired, or
/// moved to another place), and their checks.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn purge_unlinked(pool: &PgPool, source: &str) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    let gone = sqlx::query!(
        r#"
        DELETE FROM content_photos c
        WHERE c.source_id = $1 AND c.place_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
            WHERE ps.place_id = c.place_id AND r.source_id = $1
              AND r.deleted_at IS NULL AND r.taken_down_at IS NULL)
        RETURNING c.path, c.thumb_path
        "#,
        source,
    )
    .fetch_all(&mut *tx)
    .await?;
    let descriptions = sqlx::query!(
        r#"
        DELETE FROM content_descriptions c
        WHERE c.source_id = $1 AND NOT EXISTS (
            SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
            WHERE ps.place_id = c.place_id AND r.source_id = $1
              AND r.deleted_at IS NULL AND r.taken_down_at IS NULL)
        "#,
        source,
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    sqlx::query!(
        r#"
        DELETE FROM content_checks c
        WHERE c.source_id = $1 AND NOT EXISTS (
            SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
            WHERE ps.place_id = c.place_id AND r.source_id = $1
              AND r.deleted_at IS NULL AND r.taken_down_at IS NULL)
        "#,
        source,
    )
    .execute(&mut *tx)
    .await?;
    let mut candidates = Vec::new();
    for g in &gone {
        candidates.push(g.path.clone());
        candidates.push(g.thumb_path.clone());
    }
    let orphaned_files = unreferenced(&mut tx, candidates).await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: 0,
        removed: gone.len() + usize::try_from(descriptions).unwrap_or(usize::MAX),
        orphaned_files,
    })
}

/// Whether an item of a source is a photo or a review. A hide and a
/// report name it, because a source may give a photo and a review the
/// same id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItemKind {
    /// A photo.
    Photo,
    /// A review.
    Review,
}

impl ItemKind {
    /// The scope of its hides in `content_hides`.
    #[must_use]
    pub const fn scope(self) -> &'static str {
        match self {
            Self::Photo => "photo",
            Self::Review => "review",
        }
    }
}

/// What an operator hides.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Hide {
    /// One photo or review, by its kind and its id at the source,
    /// wherever it shows.
    Item(ItemKind, String),
    /// Every review signed by one key, by the SHA-256 of the key.
    Author(String),
    /// Everything the source shows on one place or one point of interest,
    /// by its id (the two never share one: both are UUID v7 made in Rust).
    Place(Uuid),
    /// The whole source.
    Source,
}

impl Hide {
    fn scope_and_key(&self) -> (&'static str, String) {
        match self {
            Self::Item(kind, id) => (kind.scope(), id.clone()),
            Self::Author(key) => ("author", key.clone()),
            Self::Place(id) => ("place", id.to_string()),
            Self::Source => ("source", "*".to_owned()),
        }
    }
}

/// Hides what `hide` names of `source` (or shows it again); `false` when
/// nothing changed. A refresh never undoes it: the card reads every row
/// through the hides. An operator's hide over one the reports made becomes
/// the operator's, so a moderator who keeps the item does not lift it.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn set_hidden(
    pool: &PgPool,
    source: &str,
    hide: &Hide,
    hidden: bool,
) -> Result<bool, DbError> {
    let (scope, key) = hide.scope_and_key();
    let done = if hidden {
        sqlx::query!(
            r#"
            INSERT INTO content_hides (source_id, scope, key) VALUES ($1, $2, $3)
            ON CONFLICT (source_id, scope, key) DO UPDATE SET origin = 'operator'
            WHERE content_hides.origin <> 'operator'
            "#,
            source,
            scope,
            key,
        )
        .execute(pool)
        .await?
    } else {
        sqlx::query!(
            "DELETE FROM content_hides WHERE source_id = $1 AND scope = $2 AND key = $3",
            source,
            scope,
            key,
        )
        .execute(pool)
        .await?
    };
    Ok(done.rows_affected() > 0)
}

/// The review ids and author keys hidden of `source`, so a refresh leaves
/// hidden reviews out before it counts what a place may show.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn hidden_keys(
    pool: &PgPool,
    source: &str,
) -> Result<(Vec<String>, Vec<String>), DbError> {
    let rows = sqlx::query!(
        "SELECT scope, key FROM content_hides WHERE source_id = $1 AND scope IN ('review', 'author')",
        source,
    )
    .fetch_all(pool)
    .await?;
    let (items, authors): (Vec<_>, Vec<_>) = rows.into_iter().partition(|r| r.scope == "review");
    Ok((
        items.into_iter().map(|r| r.key).collect(),
        authors.into_iter().map(|r| r.key).collect(),
    ))
}

/// What a content row is, for an operator who names it by its id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemRef {
    /// Its source.
    pub source_id: String,
    /// Its id at the source.
    pub external_id: String,
    /// Its author's key hash, for a review.
    pub author_key: Option<String>,
}

/// The photo or review `id` (`ExternalPhoto.id`, `ExternalReview.id`), of
/// the kind named.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn item(pool: &PgPool, kind: ItemKind, id: Uuid) -> Result<Option<ItemRef>, DbError> {
    Ok(match kind {
        ItemKind::Photo => {
            sqlx::query_as!(
                ItemRef,
                r#"
                SELECT source_id, external_id, NULL::text AS author_key
                FROM content_photos WHERE id = $1
                "#,
                id,
            )
            .fetch_optional(pool)
            .await?
        }
        ItemKind::Review => {
            sqlx::query_as!(
                ItemRef,
                "SELECT source_id, external_id, author_key FROM content_reviews WHERE id = $1",
                id,
            )
            .fetch_optional(pool)
            .await?
        }
    })
}

/// A photo as the card shows it.
#[derive(Debug, Clone, PartialEq)]
pub struct ContentPhotoRow {
    /// Its id.
    pub id: Uuid,
    /// Its source.
    pub source_id: String,
    /// The source's display name.
    pub source_label: String,
    /// `linked`, `facing` or `nearby`.
    pub relation: String,
    /// From the place to where it was taken, metres.
    pub distance_m: Option<f32>,
    /// Where it is published.
    pub page_url: String,
    /// Its title.
    pub title: Option<String>,
    /// Its author.
    pub author: Option<String>,
    /// Who published it at the source.
    pub publisher: Option<String>,
    /// The source's date of its last update.
    pub source_updated_on: Option<NaiveDate>,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// When it was taken.
    pub taken_at: Option<DateTime<Utc>>,
    /// The large image, relative to the media root.
    pub path: String,
    /// The thumbnail, relative to the media root.
    pub thumb_path: String,
    /// Large image width.
    pub width: i32,
    /// Large image height.
    pub height: i32,
    /// ThumbHash bytes.
    pub thumbhash: Vec<u8>,
    /// When Lunaway last read it.
    pub fetched_at: DateTime<Utc>,
}

/// The photos of `place` and of the places merged into it (not those
/// taken down), linked ones first, at most `limit`, without what an
/// operator hid or what may no longer be shown.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn photos_of_place(
    pool: &PgPool,
    place: Uuid,
    limit: i64,
) -> Result<Vec<ContentPhotoRow>, DbError> {
    Ok(sqlx::query_as!(
        ContentPhotoRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
                  WHERE p.taken_down_at IS NULL
        )
        SELECT c.id, c.source_id, s.name AS source_label, c.relation, c.distance_m, c.page_url,
               c.title, c.author, c.publisher, c.source_updated_on, c.licence, c.licence_url,
               c.taken_at, c.path, c.thumb_path, c.width, c.height, c.thumbhash, c.fetched_at
        FROM content_photos c
        JOIN sources s ON s.id = c.source_id
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.place_id IN (SELECT id FROM family) AND w.hidden_at IS NULL
          AND (c.rights_end_on IS NULL OR c.rights_end_on >= current_date)
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'photo' AND h.key = c.external_id)
                  OR (h.scope = 'place' AND h.key IN (c.place_id::text, $1::text))
                  OR h.scope = 'source'))
        ORDER BY CASE c.relation WHEN 'linked' THEN 0 WHEN 'facing' THEN 1 ELSE 2 END,
                 c.rank, c.id
        LIMIT $2
        "#,
        place,
        limit,
    )
    .fetch_all(pool)
    .await?)
}

/// A description as the card shows it.
#[derive(Debug, Clone, PartialEq)]
pub struct ContentDescriptionRow {
    /// Its source.
    pub source_id: String,
    /// The source's display name.
    pub source_label: String,
    /// BCP 47 tag.
    pub lang: String,
    /// The text.
    pub text: String,
    /// The title of its page.
    pub title: Option<String>,
    /// Its page.
    pub page_url: String,
    /// Who wrote it.
    pub author: Option<String>,
    /// Who published it at the source.
    pub publisher: Option<String>,
    /// The source's date of its last update.
    pub source_updated_on: Option<NaiveDate>,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// When Lunaway last read it.
    pub fetched_at: DateTime<Utc>,
}

/// The descriptions of `place` and of the places merged into it (not
/// those taken down), one per source and language, the place's own first,
/// without what an operator hid.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn descriptions_of_place(
    pool: &PgPool,
    place: Uuid,
) -> Result<Vec<ContentDescriptionRow>, DbError> {
    Ok(sqlx::query_as!(
        ContentDescriptionRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
                  WHERE p.taken_down_at IS NULL
        )
        SELECT DISTINCT ON (c.source_id, c.lang)
               c.source_id, s.name AS source_label, c.lang, c.text, c.title, c.page_url, c.author,
               c.publisher, c.source_updated_on, c.licence, c.licence_url, c.fetched_at
        FROM content_descriptions c
        JOIN sources s ON s.id = c.source_id
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.place_id IN (SELECT id FROM family) AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'place' AND h.key IN (c.place_id::text, $1::text)) OR h.scope = 'source'))
        ORDER BY c.source_id, c.lang, (c.place_id = $1) DESC, c.fetched_at DESC
        "#,
        place,
    )
    .fetch_all(pool)
    .await?)
}

/// A review with text as the card shows it.
#[derive(Debug, Clone, PartialEq)]
pub struct ContentReviewRow {
    /// Its id, a UUID v7 stamped with its date: the newest first in id
    /// order, as the community's and the partner's reviews.
    pub id: Uuid,
    /// Its source.
    pub source_id: String,
    /// The source's display name.
    pub source_label: String,
    /// Stars, 1 to 5.
    pub rating: Option<i16>,
    /// Its text.
    pub text: String,
    /// The language of the text.
    pub lang: Option<String>,
    /// The reviewer's pseudonym.
    pub author: Option<String>,
    /// When it was written.
    pub written_at: DateTime<Utc>,
    /// Where it is published.
    pub page_url: String,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
}

/// The reviews with text of `place` and of the places merged into it (not
/// those taken down), newest first, after the review `after`, without
/// what an operator or the reports hid. A rating without text counts in
/// [`ratings_of_place`] only.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_place(
    pool: &PgPool,
    place: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<crate::community::Page<ContentReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        ContentReviewRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
                  WHERE p.taken_down_at IS NULL
        )
        SELECT c.id, c.source_id, s.name AS source_label, c.rating, c.text AS "text!", c.lang,
               c.author, c.written_at, c.page_url, c.licence, c.licence_url
        FROM content_reviews c
        JOIN sources s ON s.id = c.source_id
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.place_id IN (SELECT id FROM family) AND c.text IS NOT NULL
          AND w.hidden_at IS NULL
          AND ($2::uuid IS NULL OR c.id < $2)
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key IN (c.place_id::text, $1::text))
                  OR h.scope = 'source'))
        ORDER BY c.id DESC
        LIMIT $3
        "#,
        place,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total = sqlx::query_scalar!(
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
                  WHERE p.taken_down_at IS NULL
        )
        SELECT count(*) AS "n!"
        FROM content_reviews c
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.place_id IN (SELECT id FROM family) AND c.text IS NOT NULL
          AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key IN (c.place_id::text, $1::text))
                  OR h.scope = 'source'))
        "#,
        place,
    )
    .fetch_one(pool)
    .await?;
    Ok(crate::community::page(rows, first, total))
}

/// What the reviews of a source say of a place as a whole.
#[derive(Debug, Clone, PartialEq)]
pub struct ContentRatingRow {
    /// Its source.
    pub source_id: String,
    /// Mean stars.
    pub average: f64,
    /// Ratings counted.
    pub count: i32,
}

/// The mean of the ratings of the reviews of each source on `place` and
/// the places merged into it, without the hidden ones.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn ratings_of_place(
    pool: &PgPool,
    place: Uuid,
) -> Result<Vec<ContentRatingRow>, DbError> {
    Ok(sqlx::query_as!(
        ContentRatingRow,
        r#"
        WITH RECURSIVE family(id) AS (
            SELECT $1::uuid
            UNION SELECT p.id FROM places p JOIN family f ON p.merged_into = f.id
                  WHERE p.taken_down_at IS NULL
        )
        SELECT c.source_id, avg(c.rating)::float8 AS "average!", count(*)::int4 AS "count!"
        FROM content_reviews c
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.place_id IN (SELECT id FROM family) AND c.rating IS NOT NULL
          AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key IN (c.place_id::text, $1::text))
                  OR h.scope = 'source'))
        GROUP BY c.source_id
        ORDER BY c.source_id
        "#,
        place,
    )
    .fetch_all(pool)
    .await?)
}

/// How much content the places have, for the coverage report.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Coverage {
    /// Live places.
    pub places: i64,
    /// Places with at least one photo.
    pub with_photo: i64,
    /// Places with at least one photo that shows the place itself (linked
    /// or facing).
    pub with_own_photo: i64,
    /// Places with at least one description.
    pub with_description: i64,
    /// Places with at least one review.
    pub with_review: i64,
    /// Places with any of the three.
    pub with_any: i64,
}

/// Counts the live places with content, within `area` when given, by
/// source when `source` is given. Hidden items are counted: the report
/// measures what the sources give.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn coverage(
    pool: &PgPool,
    area: Option<Area>,
    source: Option<&str>,
) -> Result<Coverage, DbError> {
    let (s, w, n, e) = area.unwrap_or((-90.0, -180.0, 90.0, 180.0));
    let r = sqlx::query!(
        r#"
        WITH live AS (
            SELECT id FROM places
            WHERE deleted_at IS NULL AND taken_down_at IS NULL
              AND geom::geometry && ST_MakeEnvelope($2, $1, $4, $3, 4326)
        ), flags AS (
            SELECT l.id,
                   EXISTS (SELECT 1 FROM content_photos c WHERE c.place_id = l.id
                           AND ($5::text IS NULL OR c.source_id = $5)) AS photo,
                   EXISTS (SELECT 1 FROM content_photos c WHERE c.place_id = l.id
                           AND ($5::text IS NULL OR c.source_id = $5)
                           AND c.relation <> 'nearby') AS own_photo,
                   EXISTS (SELECT 1 FROM content_descriptions c WHERE c.place_id = l.id
                           AND ($5::text IS NULL OR c.source_id = $5)) AS description,
                   EXISTS (SELECT 1 FROM content_reviews c WHERE c.place_id = l.id
                           AND ($5::text IS NULL OR c.source_id = $5)) AS review
            FROM live l
        )
        SELECT count(*) AS "places!",
               count(*) FILTER (WHERE photo) AS "with_photo!",
               count(*) FILTER (WHERE own_photo) AS "with_own_photo!",
               count(*) FILTER (WHERE description) AS "with_description!",
               count(*) FILTER (WHERE review) AS "with_review!",
               count(*) FILTER (WHERE photo OR description OR review) AS "with_any!"
        FROM flags
        "#,
        s,
        w,
        n,
        e,
        source,
    )
    .fetch_one(pool)
    .await?;
    Ok(Coverage {
        places: r.places,
        with_photo: r.with_photo,
        with_own_photo: r.with_own_photo,
        with_description: r.with_description,
        with_review: r.with_review,
        with_any: r.with_any,
    })
}

/// A photo or a review of an external source, as a report names it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalItem {
    /// Its source.
    pub source_id: String,
    /// Its id at the source.
    pub external_id: String,
}

/// The external photo or review `id` (`ExternalPhoto.id`,
/// `ExternalReview.id`) of the kind named, whichever source it came from:
/// a report of a review never reaches a photo, whatever their ids.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn external_item_on(
    conn: &mut PgConnection,
    kind: ItemKind,
    id: Uuid,
) -> Result<Option<ExternalItem>, DbError> {
    Ok(match kind {
        ItemKind::Photo => {
            sqlx::query_as!(
                ExternalItem,
                r#"
                SELECT source_id AS "source_id!", external_id AS "external_id!"
                FROM (
                    SELECT source_id, external_id FROM content_photos WHERE id = $1
                    UNION ALL
                    SELECT source_id, external_id FROM external_photos
                    WHERE id = $1 AND retired_at IS NULL
                ) i
                LIMIT 1
                "#,
                id,
            )
            .fetch_optional(conn)
            .await?
        }
        ItemKind::Review => {
            sqlx::query_as!(
                ExternalItem,
                r#"
                SELECT source_id AS "source_id!", external_id AS "external_id!"
                FROM (
                    SELECT source_id, external_id FROM content_reviews WHERE id = $1
                    UNION ALL
                    SELECT source_id, external_id FROM external_reviews WHERE id = $1
                ) i
                LIMIT 1
                "#,
                id,
            )
            .fetch_optional(conn)
            .await?
        }
    })
}

/// Who hides an item.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HideOrigin {
    /// The users' reports, until a moderator decides.
    Reports,
    /// A moderator's rejection.
    Moderator,
}

/// Hides one photo or review of a source wherever it shows; a moderator's
/// hide replaces one the reports made, and neither replaces an operator's.
/// Returns the rows written. The API's role writes no hide directly: this
/// goes through `content_hide_reported`, which can write nothing else.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn hide_item_on(
    conn: &mut PgConnection,
    source: &str,
    kind: ItemKind,
    external_id: &str,
    origin: HideOrigin,
) -> Result<u64, DbError> {
    let origin = match origin {
        HideOrigin::Reports => "reports",
        HideOrigin::Moderator => "moderator",
    };
    let written = sqlx::query_scalar!(
        r#"SELECT content_hide_reported($1, $2, $3, $4) AS "written!""#,
        source,
        kind.scope(),
        external_id,
        origin,
    )
    .fetch_one(conn)
    .await?;
    Ok(u64::try_from(written).unwrap_or(0))
}

/// Lifts the hide the reports put on one photo or review; an operator's
/// or a moderator's stays (`content_unhide_reported`).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn unhide_reported_on(
    conn: &mut PgConnection,
    source: &str,
    kind: ItemKind,
    external_id: &str,
) -> Result<u64, DbError> {
    let removed = sqlx::query_scalar!(
        r#"SELECT content_unhide_reported($1, $2, $3) AS "removed!""#,
        source,
        kind.scope(),
        external_id,
    )
    .fetch_one(conn)
    .await?;
    Ok(u64::try_from(removed).unwrap_or(0))
}

// The points of interest, establishments included. A point shows only what
// its own record names (its Commons file, Wikidata item or Panoramax
// picture) and the reviews that give its name: the content worker asks
// the sources about the points whose OpenStreetMap tags name something,
// never about the others, and never searches around a point.

/// A live, named point of interest near a point, for matching a review.
#[derive(Debug, Clone, PartialEq)]
pub struct NearPoi {
    /// The point.
    pub id: Uuid,
    /// Its name.
    pub name: String,
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
}

/// Live named points of interest within `radius_m` of a point, nearest
/// first, at most 20. A point without a name is never one: a review goes
/// to a point only by the name it gives.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn pois_near(
    pool: &PgPool,
    lat: f64,
    lon: f64,
    radius_m: f64,
) -> Result<Vec<NearPoi>, DbError> {
    Ok(sqlx::query_as!(
        NearPoi,
        r#"
        SELECT id, name AS "name!", ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!"
        FROM pois
        WHERE deleted_at IS NULL AND NOT hidden AND name IS NOT NULL
          AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)
        ORDER BY geom <-> ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        LIMIT 20
        "#,
        lat,
        lon,
        radius_m,
    )
    .fetch_all(pool)
    .await?)
}

/// What a point's record names that leads to open content (the `refs` of
/// `lunaway_domain::poi::PoiRecord`).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PoiLinks {
    /// A Commons file or category (`File:...`, `Category:...`).
    pub commons: Option<String>,
    /// A Wikidata item (`Q42`).
    pub wikidata: Option<String>,
    /// A Panoramax picture's id.
    pub panoramax: Option<String>,
}

/// A point of interest the content worker asks a source about.
#[derive(Debug, Clone, PartialEq)]
pub struct DuePoi {
    /// The point.
    pub id: Uuid,
    /// Its name.
    pub name: Option<String>,
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
    /// What its record names.
    pub links: PoiLinks,
    /// When the source was last asked about it; `None` if never.
    pub checked_at: Option<DateTime<Utc>>,
}

impl DuePoi {
    /// Where a run stands once it has been given this point.
    #[must_use]
    pub const fn cursor(&self) -> DueCursor {
        DueCursor {
            checked_at: self.checked_at,
            id: self.id,
        }
    }
}

/// Which points of interest a source is asked about.
#[derive(Debug, Clone, Copy)]
pub struct PoiDueQuery<'a> {
    /// The source.
    pub source: &'a str,
    /// The keys of `refs` the source reads (`commons`, `wikidata`,
    /// `panoramax`): only the points that carry one of them.
    pub refs: &'a [String],
    /// A point asked about since this is not due.
    pub before: DateTime<Utc>,
    /// Points returned at most.
    pub limit: i64,
    /// Only the points in this box.
    pub area: Option<Area>,
    /// The last point this run was given ([`DuePoi::cursor`]): only the
    /// points after it. `None` for the run's first batch.
    pub after: Option<DueCursor>,
}

/// Live points of interest that carry one of `q.refs`, those the source
/// was never asked about first, by id, then those not asked since
/// `q.before`, least recently asked first, from `q.after` on, as
/// [`places_due`] walks the places. The first read walks the partial index
/// of the points that name any open content (`pois_content_refs_idx`),
/// whose predicate it repeats, so the establishments without such a tag
/// are never read.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn pois_due(pool: &PgPool, q: PoiDueQuery<'_>) -> Result<Vec<DuePoi>, DbError> {
    let (s, w, n, e) = q.area.map_or((None, None, None, None), |(s, w, n, e)| {
        (Some(s), Some(w), Some(n), Some(e))
    });
    let limit = q.limit.max(0);
    let mut keys: Vec<(Uuid, Option<DateTime<Utc>>)> = Vec::new();
    if q.after.is_none_or(|c| c.checked_at.is_none()) {
        let after = q.after.map_or(Uuid::nil(), |c| c.id);
        keys = sqlx::query_scalar!(
            r#"
            SELECT p.id
            FROM pois p
            WHERE p.id > $2
              AND p.deleted_at IS NULL AND NOT p.hidden
              AND (p.data -> 'refs') ?| ARRAY['commons', 'wikidata', 'panoramax']
              AND (p.data -> 'refs') ?| $3::text[]
              AND NOT EXISTS (
                    SELECT 1 FROM content_poi_checks c
                    WHERE c.poi_id = p.id AND c.source_id = $1)
              AND ($4::float8 IS NULL OR p.geom::geometry && ST_MakeEnvelope($5, $4, $7, $6, 4326))
            ORDER BY p.id
            LIMIT $8
            "#,
            q.source,
            after,
            q.refs,
            s,
            w,
            n,
            e,
            limit,
        )
        .fetch_all(pool)
        .await?
        .into_iter()
        .map(|id| (id, None))
        .collect();
    }
    let missing = limit.saturating_sub(i64::try_from(keys.len()).unwrap_or(i64::MAX));
    if missing > 0 {
        let (after_at, after_id) = match q.after {
            Some(DueCursor {
                checked_at: Some(at),
                id,
            }) => (at, id),
            _ => (ASKED_FROM, Uuid::nil()),
        };
        let asked = sqlx::query!(
            r#"
            SELECT c.poi_id, c.checked_at
            FROM content_poi_checks c
            JOIN pois p ON p.id = c.poi_id
            WHERE c.source_id = $1 AND c.checked_at < $2
              AND c.checked_at >= $3 AND (c.checked_at, c.poi_id) > ($3, $4)
              AND p.deleted_at IS NULL AND NOT p.hidden
              AND (p.data -> 'refs') ?| $5::text[]
              AND ($6::float8 IS NULL OR p.geom::geometry && ST_MakeEnvelope($7, $6, $9, $8, 4326))
            ORDER BY c.checked_at, c.poi_id
            LIMIT $10
            "#,
            q.source,
            q.before,
            after_at,
            after_id,
            q.refs,
            s,
            w,
            n,
            e,
            missing,
        )
        .fetch_all(pool)
        .await?;
        keys.extend(asked.into_iter().map(|r| (r.poi_id, Some(r.checked_at))));
    }
    if keys.is_empty() {
        return Ok(Vec::new());
    }
    let ids: Vec<Uuid> = keys.iter().map(|(id, _)| *id).collect();
    let rows = sqlx::query!(
        r#"
        SELECT p.id, p.name, ST_Y(p.geom::geometry) AS "lat!", ST_X(p.geom::geometry) AS "lon!",
               p.data -> 'refs' ->> 'commons' AS commons,
               p.data -> 'refs' ->> 'wikidata' AS wikidata,
               p.data -> 'refs' ->> 'panoramax' AS panoramax
        FROM unnest($1::uuid[]) WITH ORDINALITY AS k(id, n)
        JOIN pois p ON p.id = k.id
        ORDER BY k.n
        "#,
        &ids,
    )
    .fetch_all(pool)
    .await?;
    let asked_at: HashMap<Uuid, Option<DateTime<Utc>>> = keys.into_iter().collect();
    Ok(rows
        .into_iter()
        .map(|r| DuePoi {
            checked_at: asked_at.get(&r.id).copied().flatten(),
            id: r.id,
            name: r.name,
            lat: r.lat,
            lon: r.lon,
            links: PoiLinks {
                commons: r.commons,
                wikidata: r.wikidata,
                panoramax: r.panoramax,
            },
        })
        .collect())
}

/// Removes the photos of `source` from the points that are gone or whose
/// record no longer names any of `refs` (a tag removed on OpenStreetMap;
/// a record that names nothing stores no `refs` at all): no pass asks
/// about such a point again, so its photos would stay. Their checks go
/// with them.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn purge_unlinked_pois(
    pool: &PgPool,
    source: &str,
    refs: &[String],
) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    let gone = sqlx::query_as!(
        StoredFiles,
        r#"
        DELETE FROM content_photos c USING pois p
        WHERE c.poi_id = p.id AND c.source_id = $1
          AND (p.deleted_at IS NOT NULL OR NOT coalesce((p.data -> 'refs') ?| $2::text[], false))
        RETURNING c.path, c.thumb_path
        "#,
        source,
        refs,
    )
    .fetch_all(&mut *tx)
    .await?;
    sqlx::query!(
        r#"
        DELETE FROM content_poi_checks c USING pois p
        WHERE c.poi_id = p.id AND c.source_id = $1
          AND (p.deleted_at IS NOT NULL OR NOT coalesce((p.data -> 'refs') ?| $2::text[], false))
        "#,
        source,
        refs,
    )
    .execute(&mut *tx)
    .await?;
    let candidates = gone
        .iter()
        .flat_map(|g| [g.path.clone(), g.thumb_path.clone()])
        .collect();
    let orphaned_files = unreferenced(&mut tx, candidates).await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: 0,
        removed: gone.len(),
        orphaned_files,
    })
}

/// Removes the reviews, photos and checks of the points of interest that
/// are gone (their source no longer lists them). A point hidden by the
/// community or a moderator keeps them: it may be shown again.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn purge_gone_pois(pool: &PgPool) -> Result<Replaced, DbError> {
    let mut tx = pool.begin().await?;
    let gone = sqlx::query_as!(
        StoredFiles,
        r#"
        DELETE FROM content_photos c USING pois p
        WHERE p.id = c.poi_id AND p.deleted_at IS NOT NULL
        RETURNING c.path, c.thumb_path
        "#
    )
    .fetch_all(&mut *tx)
    .await?;
    let reviews = sqlx::query!(
        r#"
        DELETE FROM content_reviews c USING pois p
        WHERE p.id = c.poi_id AND p.deleted_at IS NOT NULL
        "#
    )
    .execute(&mut *tx)
    .await?
    .rows_affected();
    sqlx::query!(
        r#"
        DELETE FROM content_poi_checks c USING pois p
        WHERE p.id = c.poi_id AND p.deleted_at IS NOT NULL
        "#
    )
    .execute(&mut *tx)
    .await?;
    let candidates = gone
        .iter()
        .flat_map(|g| [g.path.clone(), g.thumb_path.clone()])
        .collect();
    let orphaned_files = unreferenced(&mut tx, candidates).await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: 0,
        removed: gone.len() + usize::try_from(reviews).unwrap_or(usize::MAX),
        orphaned_files,
    })
}

/// The photos of the point of interest `poi`, linked ones first, at most
/// `limit`, without what an operator or the reports hid, what a hidden
/// source shows, or what may no longer be shown.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn photos_of_poi(
    pool: &PgPool,
    poi: Uuid,
    limit: i64,
) -> Result<Vec<ContentPhotoRow>, DbError> {
    Ok(sqlx::query_as!(
        ContentPhotoRow,
        r#"
        SELECT c.id, c.source_id, s.name AS source_label, c.relation, c.distance_m, c.page_url,
               c.title, c.author, c.publisher, c.source_updated_on, c.licence, c.licence_url,
               c.taken_at, c.path, c.thumb_path, c.width, c.height, c.thumbhash, c.fetched_at
        FROM content_photos c
        JOIN sources s ON s.id = c.source_id
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.poi_id = $1 AND w.hidden_at IS NULL
          AND (c.rights_end_on IS NULL OR c.rights_end_on >= current_date)
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'photo' AND h.key = c.external_id)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        ORDER BY CASE c.relation WHEN 'linked' THEN 0 WHEN 'facing' THEN 1 ELSE 2 END,
                 c.rank, c.id
        LIMIT $2
        "#,
        poi,
        limit,
    )
    .fetch_all(pool)
    .await?)
}

/// The reviews with text of the point of interest `poi`, newest first,
/// after the review `after`, without what an operator or the reports hid,
/// as [`reviews_of_place`] reads a place's. A rating without text counts in
/// [`ratings_of_poi`] only.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn reviews_of_poi(
    pool: &PgPool,
    poi: Uuid,
    first: i64,
    after: Option<Uuid>,
) -> Result<crate::community::Page<ContentReviewRow>, DbError> {
    let rows = sqlx::query_as!(
        ContentReviewRow,
        r#"
        SELECT c.id, c.source_id, s.name AS source_label, c.rating, c.text AS "text!", c.lang,
               c.author, c.written_at, c.page_url, c.licence, c.licence_url
        FROM content_reviews c
        JOIN sources s ON s.id = c.source_id
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.poi_id = $1 AND c.text IS NOT NULL
          AND w.hidden_at IS NULL
          AND ($2::uuid IS NULL OR c.id < $2)
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        ORDER BY c.id DESC
        LIMIT $3
        "#,
        poi,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!"
        FROM content_reviews c
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.poi_id = $1 AND c.text IS NOT NULL
          AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        "#,
        poi,
    )
    .fetch_one(pool)
    .await?;
    Ok(crate::community::page(rows, first, total))
}

/// The mean of the ratings of the reviews of each source on the point of
/// interest `poi`, without the hidden ones.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn ratings_of_poi(pool: &PgPool, poi: Uuid) -> Result<Vec<ContentRatingRow>, DbError> {
    Ok(sqlx::query_as!(
        ContentRatingRow,
        r#"
        SELECT c.source_id, avg(c.rating)::float8 AS "average!", count(*)::int4 AS "count!"
        FROM content_reviews c
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.poi_id = $1 AND c.rating IS NOT NULL
          AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'review' AND h.key = c.external_id)
                  OR (h.scope = 'author' AND h.key = c.author_key)
                  OR (h.scope = 'place' AND h.key = $1::text)
                  OR h.scope = 'source'))
        GROUP BY c.source_id
        ORDER BY c.source_id
        "#,
        poi,
    )
    .fetch_all(pool)
    .await?)
}
