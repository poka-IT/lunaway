//! What lies along a route (`alongRoute`): the points of interest and the
//! places within a band of the route's pieces, then the rows of the few
//! the list shows, with a photo of each place.
//!
//! The route comes as pieces of a few kilometres
//! ([`lunaway_domain::along::pieces`]), each a small box for the spatial
//! index; each piece keeps its nearest candidates when it holds more than
//! its share, so a town on the way cannot crowd out the rest of the route.

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{OvernightStatus, PlaceKind, Position, Service, poi::PoiKind};
use uuid::Uuid;

use crate::{
    DbError, PgPool,
    content::ContentPhotoRow,
    extcom::ExternalPhotoRow,
    places::{PlaceDb, PlaceRow},
};

/// A candidate of the band: what it is and where.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AlongPoint {
    /// The point of interest or the place.
    pub id: Uuid,
    /// Where it is.
    pub position: Position,
}

/// Which places a search along a route takes.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AlongPlaces {
    /// Only these overnight statuses (all when `None`).
    pub overnight: Option<Vec<OvernightStatus>>,
    /// Only these kinds (all when `None`).
    pub kinds: Option<Vec<PlaceKind>>,
    /// At least one of these services (no condition when empty).
    pub any_service: Vec<Service>,
    /// Leave out the places whose known maximum height is below this,
    /// metres.
    pub vehicle_height_m: Option<f64>,
    /// The same for the width, metres.
    pub vehicle_width_m: Option<f64>,
    /// The same for the length, metres.
    pub vehicle_length_m: Option<f64>,
    /// The same for the weight, tonnes.
    pub vehicle_weight_t: Option<f64>,
}

struct PointDb {
    id: Uuid,
    lat: f64,
    lon: f64,
}

fn points(rows: Vec<PointDb>) -> Result<Vec<AlongPoint>, DbError> {
    rows.into_iter()
        .map(|r| {
            Ok(AlongPoint {
                id: r.id,
                position: Position::new(r.lat, r.lon)
                    .map_err(|e| DbError::decode("position along a route", e))?,
            })
        })
        .collect()
}

/// The live points of interest of `kinds` within `half_width_m` of each of
/// `pieces` (well-known text, `LINESTRING(lon lat, ...)`), the nearest
/// `per_piece` of each piece, each point once.
///
/// # Errors
///
/// [`DbError`] when the query fails or a position does not decode.
pub async fn pois(
    pool: &PgPool,
    pieces: &[String],
    kinds: &[PoiKind],
    half_width_m: f64,
    per_piece: i64,
) -> Result<Vec<AlongPoint>, DbError> {
    if pieces.is_empty() || kinds.is_empty() {
        return Ok(Vec::new());
    }
    let kinds: Vec<String> = kinds.iter().map(|k| k.code().to_owned()).collect();
    let rows = sqlx::query_as!(
        PointDb,
        r#"
        SELECT DISTINCT p.id AS "id!", ST_Y(p.geom::geometry) AS "lat!",
               ST_X(p.geom::geometry) AS "lon!"
        FROM (SELECT ST_GeogFromText(w) AS g FROM unnest($1::text[]) AS w) c
        CROSS JOIN LATERAL (
            SELECT q.id, q.geom
            FROM pois q
            WHERE q.deleted_at IS NULL AND NOT q.hidden AND q.kind = ANY($2)
              AND ST_DWithin(q.geom, c.g, $3)
            ORDER BY ST_Distance(q.geom, c.g), q.id
            LIMIT $4
        ) p
        "#,
        pieces,
        &kinds,
        half_width_m,
        per_piece,
    )
    .fetch_all(pool)
    .await?;
    points(rows)
}

/// The live places `filter` takes within `half_width_m` of each of
/// `pieces`, the nearest `per_piece` of each piece, each place once.
///
/// # Errors
///
/// [`DbError`] when the query fails or a position does not decode.
pub async fn places(
    pool: &PgPool,
    pieces: &[String],
    filter: &AlongPlaces,
    half_width_m: f64,
    per_piece: i64,
) -> Result<Vec<AlongPoint>, DbError> {
    if pieces.is_empty() {
        return Ok(Vec::new());
    }
    let overnight: Option<Vec<String>> = filter
        .overnight
        .as_ref()
        .map(|o| o.iter().map(|s| s.code().to_owned()).collect());
    let kinds: Option<Vec<String>> = filter
        .kinds
        .as_ref()
        .map(|k| k.iter().map(|k| k.code().to_owned()).collect());
    let services: Vec<String> = filter
        .any_service
        .iter()
        .map(|s| s.code().to_owned())
        .collect();
    let rows = sqlx::query_as!(
        PointDb,
        r#"
        SELECT DISTINCT p.id AS "id!", ST_Y(p.geom::geometry) AS "lat!",
               ST_X(p.geom::geometry) AS "lon!"
        FROM (SELECT ST_GeogFromText(w) AS g FROM unnest($1::text[]) AS w) c
        CROSS JOIN LATERAL (
            SELECT q.id, q.geom
            FROM places q
            WHERE q.deleted_at IS NULL
              AND ($2::text[] IS NULL OR q.overnight = ANY($2))
              AND ($3::text[] IS NULL OR q.kind = ANY($3))
              AND (cardinality($4::text[]) = 0 OR q.services && $4)
              AND ($5::float8 IS NULL OR q.max_height_m IS NULL OR q.max_height_m >= $5)
              AND ($6::float8 IS NULL OR q.max_width_m IS NULL OR q.max_width_m >= $6)
              AND ($7::float8 IS NULL OR q.max_length_m IS NULL OR q.max_length_m >= $7)
              AND ($8::float8 IS NULL OR q.max_weight_t IS NULL OR q.max_weight_t >= $8)
              AND ST_DWithin(q.geom, c.g, $9)
            ORDER BY ST_Distance(q.geom, c.g), q.id
            LIMIT $10
        ) p
        "#,
        pieces,
        overnight.as_deref() as Option<&[String]>,
        kinds.as_deref() as Option<&[String]>,
        &services,
        filter.vehicle_height_m,
        filter.vehicle_width_m,
        filter.vehicle_length_m,
        filter.vehicle_weight_t,
        half_width_m,
        per_piece,
    )
    .fetch_all(pool)
    .await?;
    points(rows)
}

/// The live places among `ids`, in no particular order: one query for the
/// page of a list.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn places_by_ids(pool: &PgPool, ids: &[Uuid]) -> Result<Vec<PlaceRow>, DbError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let rows = sqlx::query_as!(
        PlaceDb,
        r#"
        SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
               overnight, services, activities, description, street, postcode, city,
               country_code, price_parking_eur, price_services_eur, price_services_included,
               price_parking_includes, max_height_m, max_length_m,
               max_width_m, max_weight_t, capacity,
               opening_hours, opening_hours_parsed, opening_intervals,
               opening_intervals_until, website, phone, stars, last_confirmed_at,
               updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into, municipality,
               descriptions, external_links, rating_avg, rating_count, review_count,
               photo_count, cover_photos, reported_issues, verification, region,
               filter_rating, opening_season
        FROM places WHERE id = ANY($1) AND deleted_at IS NULL
        "#,
        ids,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter().map(PlaceRow::try_from).collect()
}

/// A place's photo as a row of a list shows it: the partner's newest, or
/// else one of the open sources showing the place itself.
#[derive(Debug, Clone, PartialEq)]
pub enum FirstPhoto {
    /// A photo of the external community source.
    Partner(ExternalPhotoRow),
    /// A photo of an open source (Wikimedia Commons, Panoramax,
    /// DATAtourisme).
    Open(ContentPhotoRow),
}

struct PartnerDb {
    place_id: Uuid,
    id: Uuid,
    source_id: String,
    source_label: String,
    author: Option<String>,
    licence: String,
    taken_at: Option<DateTime<Utc>>,
    path: Option<String>,
    thumb_path: Option<String>,
    width: Option<i32>,
    height: Option<i32>,
    thumbhash: Option<Vec<u8>>,
}

struct OpenDb {
    place_id: Uuid,
    id: Uuid,
    source_id: String,
    source_label: String,
    relation: String,
    distance_m: Option<f32>,
    page_url: String,
    title: Option<String>,
    author: Option<String>,
    publisher: Option<String>,
    source_updated_on: Option<NaiveDate>,
    licence: String,
    licence_url: String,
    taken_at: Option<DateTime<Utc>>,
    path: String,
    thumb_path: String,
    width: i32,
    height: i32,
    thumbhash: Vec<u8>,
    fetched_at: DateTime<Utc>,
}

/// One photo for each of the places `ids` that has one, by the rules of
/// their cards (`Place.externalPhotos`): the partner's newest first, else
/// an open source's photo of the place itself or facing it (never one of
/// the surroundings, which a row would pass off as the place), without
/// what an operator hid, a hidden source, or a photo whose rights ended.
/// Only each place's own photos: those of the places merged into it wait
/// for its card.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub async fn first_photos(pool: &PgPool, ids: &[Uuid]) -> Result<Vec<(Uuid, FirstPhoto)>, DbError> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let partner = sqlx::query_as!(
        PartnerDb,
        r#"
        SELECT DISTINCT ON (ps.place_id) ps.place_id AS "place_id!", e.id, e.source_id,
               s.name AS source_label, e.author, e.licence, e.taken_at, e.path, e.thumb_path,
               e.width, e.height, e.thumbhash
        FROM place_sources ps
        JOIN external_photos e ON e.record_id = ps.record_id AND e.retired_at IS NULL
        JOIN sources s ON s.id = e.source_id
        LEFT JOIN source_switches w ON w.source_id = e.source_id
        WHERE ps.place_id = ANY($1) AND w.hidden_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = e.source_id
                AND ((h.scope = 'photo' AND h.key = e.external_id)
                  OR (h.scope = 'place' AND h.key = ps.place_id::text)
                  OR h.scope = 'source'))
        ORDER BY ps.place_id, e.taken_at DESC NULLS LAST, e.id DESC
        "#,
        ids,
    )
    .fetch_all(pool)
    .await?;
    let mut out: Vec<(Uuid, FirstPhoto)> = partner
        .into_iter()
        .map(|r| {
            (
                r.place_id,
                FirstPhoto::Partner(ExternalPhotoRow {
                    id: r.id,
                    source_id: r.source_id,
                    source_label: r.source_label,
                    author: r.author,
                    licence: r.licence,
                    taken_at: r.taken_at,
                    path: r.path,
                    thumb_path: r.thumb_path,
                    width: r.width,
                    height: r.height,
                    thumbhash: r.thumbhash,
                }),
            )
        })
        .collect();
    let rest: Vec<Uuid> = ids
        .iter()
        .copied()
        .filter(|id| !out.iter().any(|(p, _)| p == id))
        .collect();
    if rest.is_empty() {
        return Ok(out);
    }
    let open = sqlx::query_as!(
        OpenDb,
        r#"
        SELECT DISTINCT ON (c.place_id) c.place_id AS "place_id!", c.id, c.source_id,
               s.name AS source_label, c.relation, c.distance_m, c.page_url, c.title, c.author,
               c.publisher, c.source_updated_on, c.licence, c.licence_url, c.taken_at, c.path,
               c.thumb_path, c.width, c.height, c.thumbhash, c.fetched_at
        FROM content_photos c
        JOIN sources s ON s.id = c.source_id
        LEFT JOIN source_switches w ON w.source_id = c.source_id
        WHERE c.place_id = ANY($1) AND c.relation IN ('linked', 'facing')
          AND w.hidden_at IS NULL
          AND (c.rights_end_on IS NULL OR c.rights_end_on >= current_date)
          AND NOT EXISTS (
              SELECT 1 FROM content_hides h
              WHERE h.source_id = c.source_id
                AND ((h.scope = 'photo' AND h.key = c.external_id)
                  OR (h.scope = 'place' AND h.key = c.place_id::text)
                  OR h.scope = 'source'))
        ORDER BY c.place_id, CASE c.relation WHEN 'linked' THEN 0 ELSE 1 END, c.rank, c.id
        "#,
        &rest,
    )
    .fetch_all(pool)
    .await?;
    out.extend(open.into_iter().map(|r| {
        (
            r.place_id,
            FirstPhoto::Open(ContentPhotoRow {
                id: r.id,
                source_id: r.source_id,
                source_label: r.source_label,
                relation: r.relation,
                distance_m: r.distance_m,
                page_url: r.page_url,
                title: r.title,
                author: r.author,
                publisher: r.publisher,
                source_updated_on: r.source_updated_on,
                licence: r.licence,
                licence_url: r.licence_url,
                taken_at: r.taken_at,
                path: r.path,
                thumb_path: r.thumb_path,
                width: r.width,
                height: r.height,
                thumbhash: r.thumbhash,
                fetched_at: r.fetched_at,
            }),
        )
    }));
    Ok(out)
}
