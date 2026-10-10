//! What lies along a route (`alongRoute`): the points of interest and the
//! places in the cells of the route's band, then the rows of the few the
//! list shows, with a photo of each place.
//!
//! The band comes as the cells of its corridor's grid
//! ([`lunaway_domain::fuel::Corridor::cell_boxes`]), each once however
//! often the route passes it, each one probe of the planar box index. A
//! cell keeps at most a share of candidates, so a town on the way cannot
//! crowd out the rest of the route: those nearest its centre, then by id,
//! the same whatever plan the database picks, so the pages of one search
//! read one set. Measured on 320 000 points over France with 40 000 more
//! around Paris: 1 000 km looping round Paris, every kind, a band of 15 km
//! each side, 44 ms; a band of 250 m over 1 000 km (5 570 cells), 275 ms;
//! 400 km through Paris, the six kinds of groceries, 3 km each side,
//! 113 ms. The earlier form, a distance to each piece of the line, took
//! 125 s on the loop (`plan/research/84-sur-le-trajet.md`).

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    OvernightStatus, PlaceKind, Position, Service, SourceId, fuel::CellBox, poi::PoiKind,
};
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

/// The edges of `cells`, one array each, as the queries unnest them.
struct Edges {
    west: Vec<f64>,
    south: Vec<f64>,
    east: Vec<f64>,
    north: Vec<f64>,
}

fn edges(cells: &[CellBox]) -> Edges {
    Edges {
        west: cells.iter().map(|c| c.west).collect(),
        south: cells.iter().map(|c| c.south).collect(),
        east: cells.iter().map(|c| c.east).collect(),
        north: cells.iter().map(|c| c.north).collect(),
    }
}

/// The live points of interest of `kinds` in `cells`, `per_cell` at most
/// in each, each point once: those the map's tiles show, which the route
/// pins beside them (the partial index of the tiles serves the walk).
///
/// # Errors
///
/// [`DbError`] when the query fails or a position does not decode.
pub async fn pois(
    pool: &PgPool,
    cells: &[CellBox],
    kinds: &[PoiKind],
    per_cell: i64,
) -> Result<Vec<AlongPoint>, DbError> {
    if cells.is_empty() || kinds.is_empty() {
        return Ok(Vec::new());
    }
    let kinds: Vec<String> = kinds.iter().map(|k| k.code().to_owned()).collect();
    let e = edges(cells);
    let rows = sqlx::query_as!(
        PointDb,
        r#"
        SELECT DISTINCT p.id AS "id!", ST_Y(p.geom::geometry) AS "lat!",
               ST_X(p.geom::geometry) AS "lon!"
        FROM unnest($1::float8[], $2::float8[], $3::float8[], $4::float8[]) AS b(w, s, e, n)
        CROSS JOIN LATERAL (
            SELECT q.id, q.geom
            FROM pois q
            WHERE q.deleted_at IS NULL AND NOT q.hidden AND q.in_tiles AND q.kind = ANY($5)
              AND q.geom::geometry && ST_MakeEnvelope(b.w, b.s, b.e, b.n, 4326)
            ORDER BY q.geom::geometry
                         <-> ST_SetSRID(ST_MakePoint((b.w + b.e) / 2, (b.s + b.n) / 2), 4326),
                     q.id
            LIMIT $6
        ) p
        "#,
        &e.west,
        &e.south,
        &e.east,
        &e.north,
        &kinds,
        per_cell,
    )
    .fetch_all(pool)
    .await?;
    points(rows)
}

/// The live places `filter` takes in `cells`, `per_cell` at most in each,
/// each place once.
///
/// # Errors
///
/// [`DbError`] when the query fails or a position does not decode.
pub async fn places(
    pool: &PgPool,
    cells: &[CellBox],
    filter: &AlongPlaces,
    per_cell: i64,
) -> Result<Vec<AlongPoint>, DbError> {
    if cells.is_empty() {
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
    let e = edges(cells);
    let rows = sqlx::query_as!(
        PointDb,
        r#"
        SELECT DISTINCT p.id AS "id!", ST_Y(p.geom::geometry) AS "lat!",
               ST_X(p.geom::geometry) AS "lon!"
        FROM unnest($1::float8[], $2::float8[], $3::float8[], $4::float8[]) AS b(w, s, e, n)
        CROSS JOIN LATERAL (
            SELECT q.id, q.geom
            FROM places q
            WHERE q.deleted_at IS NULL
              AND q.geom::geometry && ST_MakeEnvelope(b.w, b.s, b.e, b.n, 4326)
              AND ($5::text[] IS NULL OR q.overnight = ANY($5))
              AND ($6::text[] IS NULL OR q.kind = ANY($6))
              AND (cardinality($7::text[]) = 0 OR q.services && $7)
              AND ($8::float8 IS NULL OR q.max_height_m IS NULL OR q.max_height_m >= $8)
              AND ($9::float8 IS NULL OR q.max_width_m IS NULL OR q.max_width_m >= $9)
              AND ($10::float8 IS NULL OR q.max_length_m IS NULL OR q.max_length_m >= $10)
              AND ($11::float8 IS NULL OR q.max_weight_t IS NULL OR q.max_weight_t >= $11)
            ORDER BY q.geom::geometry
                         <-> ST_SetSRID(ST_MakePoint((b.w + b.e) / 2, (b.s + b.n) / 2), 4326),
                     q.id
            LIMIT $12
        ) p
        "#,
        &e.west,
        &e.south,
        &e.east,
        &e.north,
        overnight.as_deref() as Option<&[String]>,
        kinds.as_deref() as Option<&[String]>,
        &services,
        filter.vehicle_height_m,
        filter.vehicle_width_m,
        filter.vehicle_length_m,
        filter.vehicle_weight_t,
        per_cell,
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

/// The open sources whose photos a row shows: those whose terms a credit
/// of source, author and licence beside the photo meets. Another source
/// waits for a review of its terms; DATAtourisme's ask for the update date
/// beside the photo, which the card shows.
const ROW_PHOTO_SOURCES: [SourceId; 2] = [SourceId::WIKIMEDIA_COMMONS, SourceId::PANORAMAX];

/// One photo for each of the places `ids` that has one, under the rules of
/// their cards (`Place.externalPhotos`): without what an operator hid, a
/// hidden source, or a photo whose rights ended. The partner's newest
/// already stored first: a list never makes the photo proxy download, so
/// it spends nothing of the day's budget the cards share. Else an open
/// source's photo of the place itself or facing it, never one of the
/// surroundings, which a row would pass off as the place, nor one of
/// DATAtourisme, whose terms ask for the update date beside the photo and
/// leave it to the card. Only each place's own photos: those of the places
/// merged into it wait for its card.
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
        JOIN external_photos e
          ON e.record_id = ps.record_id AND e.retired_at IS NULL AND e.thumb_path IS NOT NULL
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
    let row_sources = ROW_PHOTO_SOURCES.map(|s| s.as_str().to_owned());
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
          AND c.source_id = ANY($2)
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
        &row_sources,
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
