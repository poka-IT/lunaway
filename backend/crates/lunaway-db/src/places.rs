//! Reading places: the viewport, the sync feed, one place, the search, and
//! the sources of a batch of places.

use chrono::{DateTime, Utc};
use lunaway_domain::{
    Activity, Address, BBox, OpeningInterval, OvernightStatus, PlaceKind, Position, Service,
    SourceId, conflation::FieldProvenance,
};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// A place as the API serves it.
#[derive(Debug, Clone, PartialEq)]
pub struct PlaceRow {
    /// Stable id (UUID v7).
    pub id: Uuid,
    /// Display name.
    pub name: Option<String>,
    /// Kind.
    pub kind: PlaceKind,
    /// Position.
    pub position: Position,
    /// Whether a night may be spent there.
    pub overnight: OvernightStatus,
    /// Services.
    pub services: Vec<Service>,
    /// Activities.
    pub activities: Vec<Activity>,
    /// Free text.
    pub description: Option<String>,
    /// Address (the municipality code is not stored on places).
    pub address: Address,
    /// Price of a night, euros.
    pub price_parking_eur: Option<f64>,
    /// Price of the services, euros.
    pub price_services_eur: Option<f64>,
    /// Maximum vehicle height, metres.
    pub max_height_m: Option<f64>,
    /// Pitches.
    pub capacity: Option<i32>,
    /// OSM `opening_hours`.
    pub opening_hours: Option<String>,
    /// Whether `opening_hours` parses.
    pub opening_hours_parsed: bool,
    /// Open intervals over the next two weeks; `None` when `opening_hours`
    /// is absent or does not parse.
    pub opening_intervals: Option<Vec<OpeningInterval>>,
    /// Instant up to which `opening_intervals` are complete.
    pub opening_intervals_until: Option<DateTime<Utc>>,
    /// Website.
    pub website: Option<String>,
    /// Phone.
    pub phone: Option<String>,
    /// Classification stars.
    pub stars: Option<i16>,
    /// Last time a visitor confirmed the place.
    pub last_confirmed_at: Option<DateTime<Utc>>,
    /// Last change.
    pub updated_at: DateTime<Utc>,
    /// Position in the change feed.
    pub updated_seq: i64,
    /// Which source supplied each field.
    pub provenance: Vec<FieldProvenance>,
}

/// The columns every place query selects, as `query_as!` reads them.
struct PlaceDb {
    id: Uuid,
    kind: String,
    name: Option<String>,
    lat: f64,
    lon: f64,
    overnight: String,
    services: Vec<String>,
    activities: Vec<String>,
    description: Option<String>,
    street: Option<String>,
    postcode: Option<String>,
    city: Option<String>,
    country_code: Option<String>,
    price_parking_eur: Option<f64>,
    price_services_eur: Option<f64>,
    max_height_m: Option<f64>,
    capacity: Option<i32>,
    opening_hours: Option<String>,
    opening_hours_parsed: bool,
    opening_intervals: Option<serde_json::Value>,
    opening_intervals_until: Option<DateTime<Utc>>,
    website: Option<String>,
    phone: Option<String>,
    stars: Option<i16>,
    last_confirmed_at: Option<DateTime<Utc>>,
    updated_at: DateTime<Utc>,
    updated_seq: i64,
    provenance: serde_json::Value,
    deleted: bool,
    merged_into: Option<Uuid>,
}

fn codes<T: std::str::FromStr<Err = lunaway_domain::UnknownCode>>(
    v: &[String],
    what: &'static str,
) -> Result<Vec<T>, DbError> {
    v.iter()
        .map(|c| c.parse().map_err(|e| DbError::decode(what, e)))
        .collect()
}

impl TryFrom<PlaceDb> for PlaceRow {
    type Error = DbError;

    fn try_from(r: PlaceDb) -> Result<Self, DbError> {
        Ok(Self {
            id: r.id,
            name: r.name,
            kind: r
                .kind
                .parse()
                .map_err(|e| DbError::decode("place kind", e))?,
            position: Position::new(r.lat, r.lon)
                .map_err(|e| DbError::decode("place position", e))?,
            overnight: r
                .overnight
                .parse()
                .map_err(|e| DbError::decode("overnight status", e))?,
            services: codes(&r.services, "service")?,
            activities: codes(&r.activities, "activity")?,
            description: r.description,
            address: Address {
                street: r.street,
                postcode: r.postcode,
                city: r.city,
                country_code: r.country_code,
                city_code: None,
            },
            price_parking_eur: r.price_parking_eur,
            price_services_eur: r.price_services_eur,
            max_height_m: r.max_height_m,
            capacity: r.capacity,
            opening_hours: r.opening_hours,
            opening_hours_parsed: r.opening_hours_parsed,
            opening_intervals: r
                .opening_intervals
                .map(serde_json::from_value)
                .transpose()
                .map_err(|e| DbError::decode("opening intervals", e))?,
            opening_intervals_until: r.opening_intervals_until,
            website: r.website,
            phone: r.phone,
            stars: r.stars,
            last_confirmed_at: r.last_confirmed_at,
            updated_at: r.updated_at,
            updated_seq: r.updated_seq,
            provenance: serde_json::from_value(r.provenance)
                .map_err(|e| DbError::decode("provenance", e))?,
        })
    }
}

/// Filters of the viewport query.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct PlaceFilter {
    /// Only these kinds (all when `None`).
    pub kinds: Option<Vec<PlaceKind>>,
    /// The place must have all of them.
    pub services: Vec<Service>,
    /// Only places where a night is allowed or tolerated.
    pub overnight_ok: bool,
    /// Leave out places whose known maximum height is below this, metres.
    pub vehicle_height_m: Option<f64>,
}

/// One page of the viewport query.
#[derive(Debug, Clone, PartialEq)]
pub struct PlacePage {
    /// The places, by id.
    pub nodes: Vec<PlaceRow>,
    /// Whether more places follow the last one.
    pub has_next_page: bool,
    /// Places matching in the whole viewport.
    pub total_count: i64,
}

/// Live places inside `bbox` that pass `filter`, by id, after `after`.
///
/// # Errors
///
/// [`DbError`] when a query fails or a row does not decode.
pub async fn in_bbox(
    pool: &PgPool,
    bbox: BBox,
    filter: &PlaceFilter,
    first: i64,
    after: Option<Uuid>,
) -> Result<PlacePage, DbError> {
    let kinds: Option<Vec<String>> = filter
        .kinds
        .as_ref()
        .map(|k| k.iter().map(|k| k.code().to_owned()).collect());
    let services: Vec<String> = filter
        .services
        .iter()
        .map(|s| s.code().to_owned())
        .collect();
    let rows = sqlx::query_as!(
        PlaceDb,
        r#"
        SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
               overnight, services, activities, description, street, postcode, city,
               country_code, price_parking_eur, price_services_eur, max_height_m, capacity,
               opening_hours, opening_hours_parsed, opening_intervals, opening_intervals_until,
               website, phone, stars, last_confirmed_at, updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into
        FROM places
        WHERE deleted_at IS NULL
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
          AND ($5::text[] IS NULL OR kind = ANY($5))
          AND services @> $6::text[]
          AND (NOT $7 OR overnight IN ('allowed', 'tolerated'))
          AND ($8::float8 IS NULL OR max_height_m IS NULL OR max_height_m >= $8)
          AND ($9::uuid IS NULL OR id > $9)
        ORDER BY id
        LIMIT $10
        "#,
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        kinds.as_deref() as Option<&[String]>,
        &services,
        filter.overnight_ok,
        filter.vehicle_height_m,
        after,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let total_count = sqlx::query_scalar!(
        r#"
        SELECT count(*) AS "n!" FROM places
        WHERE deleted_at IS NULL
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
          AND ($5::text[] IS NULL OR kind = ANY($5))
          AND services @> $6::text[]
          AND (NOT $7 OR overnight IN ('allowed', 'tolerated'))
          AND ($8::float8 IS NULL OR max_height_m IS NULL OR max_height_m >= $8)
        "#,
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        kinds.as_deref() as Option<&[String]>,
        &services,
        filter.overnight_ok,
        filter.vehicle_height_m,
    )
    .fetch_one(pool)
    .await?;
    let has_next_page = i64::try_from(rows.len()).unwrap_or(i64::MAX) > first;
    let nodes = rows
        .into_iter()
        .take(usize::try_from(first).unwrap_or(0))
        .map(PlaceRow::try_from)
        .collect::<Result<_, _>>()?;
    Ok(PlacePage {
        nodes,
        has_next_page,
        total_count,
    })
}

/// One entry of the change feed.
#[derive(Debug, Clone, PartialEq)]
pub enum Change {
    /// Created or modified.
    Upsert(Box<PlaceRow>),
    /// Deleted (or merged into another place, which is an upsert of its own).
    Delete {
        /// The deleted place.
        id: Uuid,
        /// Its position in the feed.
        seq: i64,
    },
}

impl Change {
    /// Its position in the feed.
    #[must_use]
    pub fn seq(&self) -> i64 {
        match self {
            Self::Upsert(p) => p.updated_seq,
            Self::Delete { seq, .. } => *seq,
        }
    }
}

/// Places inside `bbox` changed after `since`, in feed order, at most
/// `first`; plus whether more follow. Deletions are left out when
/// `with_deletions` is false (a first sync has nothing to delete).
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn changes(
    pool: &PgPool,
    bbox: BBox,
    since: i64,
    first: i64,
    with_deletions: bool,
) -> Result<(Vec<Change>, bool), DbError> {
    let rows = sqlx::query_as!(
        PlaceDb,
        r#"
        SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
               overnight, services, activities, description, street, postcode, city,
               country_code, price_parking_eur, price_services_eur, max_height_m, capacity,
               opening_hours, opening_hours_parsed, opening_intervals, opening_intervals_until,
               website, phone, stars, last_confirmed_at, updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into
        FROM places
        WHERE updated_seq > $5
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
          AND ($6 OR deleted_at IS NULL)
        ORDER BY updated_seq
        LIMIT $7
        "#,
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        since,
        with_deletions,
        first + 1,
    )
    .fetch_all(pool)
    .await?;
    let has_more = i64::try_from(rows.len()).unwrap_or(i64::MAX) > first;
    let changes = rows
        .into_iter()
        .take(usize::try_from(first).unwrap_or(0))
        .map(|r| {
            if r.deleted {
                Ok(Change::Delete {
                    id: r.id,
                    seq: r.updated_seq,
                })
            } else {
                PlaceRow::try_from(r).map(|p| Change::Upsert(Box::new(p)))
            }
        })
        .collect::<Result<_, DbError>>()?;
    Ok((changes, has_more))
}

/// How many `merged_into` redirects a lookup follows: merges chain only when
/// a place absorbed by another is absorbed again, a handful of times at most.
const MAX_REDIRECTS: usize = 8;

/// The place `id`, following merge redirects to the place that absorbed it;
/// `None` when it never existed or was deleted without a successor.
///
/// # Errors
///
/// [`DbError`] when the query fails or the row does not decode.
pub async fn by_id(pool: &PgPool, id: Uuid) -> Result<Option<PlaceRow>, DbError> {
    let mut id = id;
    for _ in 0..=MAX_REDIRECTS {
        let row = sqlx::query_as!(
            PlaceDb,
            r#"
            SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
                   overnight, services, activities, description, street, postcode, city,
                   country_code, price_parking_eur, price_services_eur, max_height_m, capacity,
                   opening_hours, opening_hours_parsed, opening_intervals,
                   opening_intervals_until, website, phone, stars, last_confirmed_at,
                   updated_at, updated_seq, provenance,
                   deleted_at IS NOT NULL AS "deleted!", merged_into
            FROM places WHERE id = $1
            "#,
            id,
        )
        .fetch_optional(pool)
        .await?;
        match row {
            None => return Ok(None),
            Some(r) if !r.deleted => return PlaceRow::try_from(r).map(Some),
            Some(r) => match r.merged_into {
                Some(next) => id = next,
                None => return Ok(None),
            },
        }
    }
    tracing::warn!(%id, "merge redirects form a chain too long to follow");
    Ok(None)
}

/// Trigram word similarity a search result needs. One missing letter in an
/// eight-letter word scores 0.55, so longer queries accept 0.5; a query of
/// four letters or fewer keeps pg_trgm's default of 0.6, or "lac" would
/// match every name holding "la".
#[must_use]
pub fn search_threshold(text: &str) -> f64 {
    let letters = text.chars().filter(|c| c.is_alphanumeric()).count();
    if letters <= 4 { 0.6 } else { 0.5 }
}

/// Live places whose folded name and municipality match `text` (accents and
/// case ignored, typos tolerated by trigram word similarity), best match
/// first; among matches of similar quality, the nearest to `near` first.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn search(
    pool: &PgPool,
    text: &str,
    near: Option<Position>,
    first: i64,
) -> Result<Vec<PlaceRow>, DbError> {
    let mut tx = pool.begin().await?;
    // `<%` reads its threshold from this setting; `set_config(.., true)`
    // scopes it to the transaction, and the GIN index still serves the
    // operator.
    sqlx::query_scalar!(
        "SELECT set_config('pg_trgm.word_similarity_threshold', $1, true)",
        search_threshold(text).to_string(),
    )
    .fetch_one(&mut *tx)
    .await?;
    // Similarities are bucketed to one decimal before the distance breaks
    // the tie: "Camping du Lac" 2 km away beats the same name 300 km away,
    // a much better name match still wins.
    let rows = sqlx::query_as!(
        PlaceDb,
        r#"
        SELECT id, kind, name, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
               overnight, services, activities, description, street, postcode, city,
               country_code, price_parking_eur, price_services_eur, max_height_m, capacity,
               opening_hours, opening_hours_parsed, opening_intervals, opening_intervals_until,
               website, phone, stars, last_confirmed_at, updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into
        FROM places
        WHERE deleted_at IS NULL AND lunaway_fold($1) <% search_text
        ORDER BY round(word_similarity(lunaway_fold($1), search_text)::numeric, 1) DESC,
                 CASE WHEN $2::float8 IS NULL OR $3::float8 IS NULL THEN 0
                      ELSE ST_Distance(geom, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography)
                 END,
                 word_similarity(lunaway_fold($1), search_text) DESC,
                 id
        LIMIT $4
        "#,
        text,
        near.map(Position::lat),
        near.map(Position::lon),
        first,
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    rows.into_iter().map(PlaceRow::try_from).collect()
}

/// A source of a place, with what the API shows of it.
#[derive(Debug, Clone, PartialEq)]
pub struct PlaceSourceRow {
    /// The place.
    pub place_id: Uuid,
    /// The source.
    pub source_id: SourceId,
    /// Its display name.
    pub source_name: String,
    /// Its licence.
    pub licence: String,
    /// Its attribution text.
    pub attribution: String,
    /// Its home page.
    pub source_url: String,
    /// Identifier of the record in the source.
    pub external_id: String,
    /// Page of the record at the source.
    pub external_url: Option<String>,
    /// When the record was read.
    pub fetched_at: DateTime<Utc>,
    /// Score that tied the record to the place.
    pub match_score: Option<f64>,
}

/// The sources of every place in `ids`, in one query.
///
/// # Errors
///
/// [`DbError`] when the query fails or a source id is malformed.
pub async fn sources_of(pool: &PgPool, ids: &[Uuid]) -> Result<Vec<PlaceSourceRow>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT ps.place_id, ps.match_score, r.external_id, r.external_url, r.fetched_at,
               s.id AS source_id, s.name, s.licence, s.attribution, s.url
        FROM place_sources ps
        JOIN source_records r ON r.id = ps.record_id
        JOIN sources s ON s.id = r.source_id
        WHERE ps.place_id = ANY($1)
        ORDER BY ps.place_id, s.id, r.external_id
        "#,
        ids,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(PlaceSourceRow {
                place_id: r.place_id,
                source_id: SourceId::new(&r.source_id)
                    .map_err(|e| DbError::decode("source id", e))?,
                source_name: r.name,
                licence: r.licence,
                attribution: r.attribution,
                source_url: r.url,
                external_id: r.external_id,
                external_url: r.external_url,
                fetched_at: r.fetched_at,
                match_score: r.match_score,
            })
        })
        .collect()
}

/// The highest position of the change feed, 0 when no place exists.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn last_seq(pool: &PgPool) -> Result<i64, DbError> {
    Ok(
        sqlx::query_scalar!(r#"SELECT coalesce(max(updated_seq), 0) AS "seq!" FROM places"#)
            .fetch_one(pool)
            .await?,
    )
}

/// Where the change feed of this database stands, for the sync cursors.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FeedHead {
    /// The random epoch of `sync_epoch`, regenerated by a restore.
    pub epoch: Uuid,
    /// The database's own identifier, which a restore into a new database
    /// changes without any step.
    pub database: i64,
    /// The highest position of the feed, 0 when no place exists.
    pub last_seq: i64,
}

impl FeedHead {
    /// The identity a cursor carries: two copies of the feed with the same
    /// identity agree on every position.
    #[must_use]
    pub fn identity(&self) -> String {
        format!("{}{:08x}", self.epoch.simple(), self.database)
    }
}

/// The identity and the end of this database's change feed, in one query.
///
/// # Errors
///
/// [`DbError`] when the query fails or the epoch row is missing.
pub async fn feed_head(pool: &PgPool) -> Result<FeedHead, DbError> {
    let r = sqlx::query!(
        r#"
        SELECT e.epoch,
               d.oid::int8 AS "database!",
               (SELECT coalesce(max(updated_seq), 0) FROM places) AS "last_seq!"
        FROM sync_epoch e, pg_database d
        WHERE d.datname = current_database()
        "#
    )
    .fetch_one(pool)
    .await?;
    Ok(FeedHead {
        epoch: r.epoch,
        database: r.database,
        last_seq: r.last_seq,
    })
}
