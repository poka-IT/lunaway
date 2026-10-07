//! The open content of the places: photos, descriptions and reviews read
//! from open sources (`lunaway content refresh`), what an operator hid of
//! them, and what the card reads.
//!
//! These tables hang on `places` but are not the catalogue: no write here
//! changes what a place is, what the change feed carries or what a pack
//! holds, so the catalogue writers' advisory lock is not taken. A content
//! row only takes a key-share lock on its place, which the conflation's
//! updates of the place's columns do not wait for. Two content runs, on
//! the other hand, exclude each other ([`RunLock`]): they share files and
//! the sources' rate limits.

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
    /// Places left out: those already tried in this run.
    pub skip: &'a [Uuid],
}

/// Live places the source was never asked about, or not since `before`,
/// least recently asked first. The places are chosen first and their
/// records read after, so a batch reads the records of its own places
/// only.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn places_due(pool: &PgPool, q: DueQuery<'_>) -> Result<Vec<DuePlace>, DbError> {
    let (s, w, n, e) = q.area.unwrap_or((-90.0, -180.0, 90.0, 180.0));
    let rows = sqlx::query!(
        r#"
        WITH due AS (
            SELECT p.id, c.checked_at
            FROM places p
            LEFT JOIN content_checks c ON c.place_id = p.id AND c.source_id = $1
            WHERE p.deleted_at IS NULL AND p.taken_down_at IS NULL
              AND (c.checked_at IS NULL OR c.checked_at < $2)
              AND p.geom::geometry && ST_MakeEnvelope($5, $4, $7, $6, 4326)
              AND NOT (p.id = ANY($9))
              AND ($8::text IS NULL OR EXISTS (
                    SELECT 1 FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
                    WHERE ps.place_id = p.id AND r.source_id = $8
                      AND r.deleted_at IS NULL AND r.taken_down_at IS NULL))
            ORDER BY c.checked_at NULLS FIRST, p.id
            LIMIT $3
        )
        SELECT p.id, p.kind, p.name, p.country_code,
               ST_Y(p.geom::geometry) AS "lat!", ST_X(p.geom::geometry) AS "lon!",
               l.commons, l.image, l.panoramax, l.wikidata, l.wikipedia
        FROM due d
        JOIN places p ON p.id = d.id
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(r.raw -> 'tags' ->> 'wikimedia_commons') AS commons,
                   jsonb_agg(r.raw -> 'tags' ->> 'image') AS image,
                   jsonb_agg(r.raw -> 'tags' ->> 'panoramax') AS panoramax,
                   jsonb_agg(r.data ->> 'wikidata') AS wikidata,
                   jsonb_agg(r.data ->> 'wikipedia') AS wikipedia
            FROM place_sources ps JOIN source_records r ON r.id = ps.record_id
            WHERE ps.place_id = p.id AND r.deleted_at IS NULL AND r.taken_down_at IS NULL
        ) l ON true
        ORDER BY d.checked_at NULLS FIRST, p.id
        "#,
        q.source,
        q.before,
        q.limit,
        s,
        w,
        n,
        e,
        q.with_records_of,
        q.skip,
    )
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(|r| DuePlace {
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
    let mut tx = pool.begin().await?;
    let keep: Vec<String> = photos.iter().map(|p| p.external_id.clone()).collect();
    let gone = sqlx::query!(
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
    .await?;
    let mut candidates = Vec::new();
    for g in &gone {
        candidates.push(g.path.clone());
        candidates.push(g.thumb_path.clone());
    }
    for (rank, p) in photos.iter().enumerate() {
        let rank = i16::try_from(rank).unwrap_or(i16::MAX);
        let previous = sqlx::query!(
            r#"
            SELECT path, thumb_path FROM content_photos
            WHERE place_id = $1 AND source_id = $2 AND external_id = $3
            "#,
            place,
            source,
            p.external_id,
        )
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(prev) = previous {
            candidates.push(prev.path);
            candidates.push(prev.thumb_path);
        }
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
        .execute(&mut *tx)
        .await?;
    }
    mark_checked_on(&mut tx, place, source, at, found).await?;
    let orphaned_files = unreferenced(&mut tx, candidates).await?;
    tx.commit().await?;
    Ok(Replaced {
        kept: photos.len(),
        removed: gone.len(),
        orphaned_files,
    })
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

/// A review read from an open source, already matched to a place.
#[derive(Debug, Clone, PartialEq)]
pub struct NewReview {
    /// The place it is about.
    pub place_id: Uuid,
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

/// Replaces every review of `source` with `reviews`, the whole of what the
/// source holds (a review gone from it goes from Lunaway), in one
/// transaction.
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
        "DELETE FROM content_reviews WHERE source_id = $1 AND NOT (external_id = ANY($2))",
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
                written_at, page_url, licence, licence_url, distance_m, fetched_at, author_key)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            ON CONFLICT (source_id, external_id) DO UPDATE SET
                place_id = excluded.place_id, rating = excluded.rating,
                text = excluded.text, lang = excluded.lang, author = excluded.author,
                written_at = excluded.written_at, page_url = excluded.page_url,
                licence = excluded.licence, licence_url = excluded.licence_url,
                distance_m = excluded.distance_m, fetched_at = excluded.fetched_at,
                author_key = excluded.author_key
            "#,
            crate::extcom::review_id(r.written_at),
            r.place_id,
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
        )
        .execute(&mut *tx)
        .await?;
    }
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
        WHERE c.source_id = $1 AND NOT EXISTS (
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

/// What an operator hides.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Hide {
    /// One photo or review, by its id at the source, wherever it shows.
    Item(String),
    /// Every review signed by one key, by the SHA-256 of the key.
    Author(String),
    /// Everything the source shows on one place.
    Place(Uuid),
    /// The whole source.
    Source,
}

impl Hide {
    fn scope_and_key(&self) -> (&'static str, String) {
        match self {
            Self::Item(id) => ("item", id.clone()),
            Self::Author(key) => ("author", key.clone()),
            Self::Place(id) => ("place", id.to_string()),
            Self::Source => ("source", "*".to_owned()),
        }
    }
}

/// Hides what `hide` names of `source` (or shows it again); `false` when
/// nothing changed. A refresh never undoes it: the card reads every row
/// through the hides.
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
            ON CONFLICT DO NOTHING
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

/// The ids and author keys an operator hid of `source`, so a refresh
/// leaves hidden reviews out before it counts what a place may show.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn hidden_keys(
    pool: &PgPool,
    source: &str,
) -> Result<(Vec<String>, Vec<String>), DbError> {
    let rows = sqlx::query!(
        "SELECT scope, key FROM content_hides WHERE source_id = $1 AND scope IN ('item', 'author')",
        source,
    )
    .fetch_all(pool)
    .await?;
    let (items, authors): (Vec<_>, Vec<_>) = rows.into_iter().partition(|r| r.scope == "item");
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

/// The photo or review `id` (`ExternalPhoto.id`, `ExternalReview.id`).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn item(pool: &PgPool, id: Uuid) -> Result<Option<ItemRef>, DbError> {
    Ok(sqlx::query_as!(
        ItemRef,
        r#"
        SELECT source_id AS "source_id!", external_id AS "external_id!", author_key
        FROM (
            SELECT source_id, external_id, NULL::text AS author_key FROM content_photos WHERE id = $1
            UNION ALL
            SELECT source_id, external_id, author_key FROM content_reviews WHERE id = $1
        ) i
        LIMIT 1
        "#,
        id,
    )
    .fetch_optional(pool)
    .await?)
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
                AND ((h.scope = 'item' AND h.key = c.external_id)
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
                AND ((h.scope = 'item' AND h.key = c.external_id)
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
                AND ((h.scope = 'item' AND h.key = c.external_id)
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
                AND ((h.scope = 'item' AND h.key = c.external_id)
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
    /// A review rather than a photo.
    pub is_review: bool,
}

/// The external photo or review `id` (`ExternalPhoto.id`,
/// `ExternalReview.id`), whichever source it came from.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn external_item_on(
    conn: &mut PgConnection,
    id: Uuid,
) -> Result<Option<ExternalItem>, DbError> {
    Ok(sqlx::query_as!(
        ExternalItem,
        r#"
        SELECT source_id AS "source_id!", external_id AS "external_id!", is_review AS "is_review!"
        FROM (
            SELECT source_id, external_id, false AS is_review FROM content_photos WHERE id = $1
            UNION ALL
            SELECT source_id, external_id, true FROM content_reviews WHERE id = $1
            UNION ALL
            SELECT source_id, external_id, false FROM external_photos
            WHERE id = $1 AND retired_at IS NULL
            UNION ALL
            SELECT source_id, external_id, true FROM external_reviews WHERE id = $1
        ) i
        LIMIT 1
        "#,
        id,
    )
    .fetch_optional(conn)
    .await?)
}

/// Who hides an item.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HideOrigin {
    /// The users' reports, until a moderator decides.
    Reports,
    /// A moderator's rejection.
    Moderator,
}

/// Hides one item of a source wherever it shows; a moderator's hide
/// replaces one the reports made. Returns the rows written.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn hide_item_on(
    conn: &mut PgConnection,
    source: &str,
    external_id: &str,
    origin: HideOrigin,
) -> Result<u64, DbError> {
    let origin = match origin {
        HideOrigin::Reports => "reports",
        HideOrigin::Moderator => "moderator",
    };
    Ok(sqlx::query!(
        r#"
        INSERT INTO content_hides (source_id, scope, key, origin) VALUES ($1, 'item', $2, $3)
        ON CONFLICT (source_id, scope, key) DO UPDATE SET origin = excluded.origin
        WHERE content_hides.origin = 'reports'
        "#,
        source,
        external_id,
        origin,
    )
    .execute(conn)
    .await?
    .rows_affected())
}

/// Lifts the hide the reports put on an item; an operator's or a
/// moderator's stays.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn unhide_reported_on(
    conn: &mut PgConnection,
    source: &str,
    external_id: &str,
) -> Result<u64, DbError> {
    Ok(sqlx::query!(
        r#"
        DELETE FROM content_hides
        WHERE source_id = $1 AND scope = 'item' AND key = $2 AND origin = 'reports'
        "#,
        source,
        external_id,
    )
    .execute(conn)
    .await?
    .rows_affected())
}
