//! Reading places: the viewport, the sync feed, one place, the search, and
//! the sources of a batch of places.

use chrono::{DateTime, Utc};
use lunaway_domain::{
    Activity, Address, BBox, OpeningInterval, OvernightStatus, PlaceKind, Position, Service,
    SourceId,
    conflation::{ExternalLink, FieldProvenance, LocalizedText},
};
use uuid::Uuid;

use crate::{DbError, PgPool, summary::CommunitySummary};

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
    /// Maximum vehicle length, metres.
    pub max_length_m: Option<f64>,
    /// Maximum vehicle width, metres.
    pub max_width_m: Option<f64>,
    /// Maximum vehicle weight, tonnes.
    pub max_weight_t: Option<f64>,
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
    /// The commune that covers the place.
    pub municipality: Option<String>,
    /// Every description of every source, by language.
    pub descriptions: Vec<LocalizedText>,
    /// Pages about the place elsewhere.
    pub external_links: Vec<ExternalLink>,
    /// What the community says of it.
    pub community: CommunitySummary,
}

/// The columns every place query selects, as `query_as!` reads them.
pub(crate) struct PlaceDb {
    pub(crate) id: Uuid,
    pub(crate) kind: String,
    pub(crate) name: Option<String>,
    pub(crate) lat: f64,
    pub(crate) lon: f64,
    pub(crate) overnight: String,
    pub(crate) services: Vec<String>,
    pub(crate) activities: Vec<String>,
    pub(crate) description: Option<String>,
    pub(crate) street: Option<String>,
    pub(crate) postcode: Option<String>,
    pub(crate) city: Option<String>,
    pub(crate) country_code: Option<String>,
    pub(crate) price_parking_eur: Option<f64>,
    pub(crate) price_services_eur: Option<f64>,
    pub(crate) max_height_m: Option<f64>,
    pub(crate) max_length_m: Option<f64>,
    pub(crate) max_width_m: Option<f64>,
    pub(crate) max_weight_t: Option<f64>,
    pub(crate) capacity: Option<i32>,
    pub(crate) opening_hours: Option<String>,
    pub(crate) opening_hours_parsed: bool,
    pub(crate) opening_intervals: Option<serde_json::Value>,
    pub(crate) opening_intervals_until: Option<DateTime<Utc>>,
    pub(crate) website: Option<String>,
    pub(crate) phone: Option<String>,
    pub(crate) stars: Option<i16>,
    pub(crate) last_confirmed_at: Option<DateTime<Utc>>,
    pub(crate) updated_at: DateTime<Utc>,
    pub(crate) updated_seq: i64,
    pub(crate) provenance: serde_json::Value,
    pub(crate) deleted: bool,
    pub(crate) merged_into: Option<Uuid>,
    pub(crate) municipality: Option<String>,
    pub(crate) descriptions: serde_json::Value,
    pub(crate) external_links: serde_json::Value,
    pub(crate) rating_avg: Option<f64>,
    pub(crate) rating_count: i32,
    pub(crate) review_count: i32,
    pub(crate) photo_count: i32,
    pub(crate) cover_photos: serde_json::Value,
    pub(crate) reported_issues: serde_json::Value,
    pub(crate) verification: String,
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
            max_length_m: r.max_length_m,
            max_width_m: r.max_width_m,
            max_weight_t: r.max_weight_t,
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
            municipality: r.municipality,
            descriptions: serde_json::from_value(r.descriptions)
                .map_err(|e| DbError::decode("descriptions", e))?,
            external_links: serde_json::from_value(r.external_links)
                .map_err(|e| DbError::decode("external links", e))?,
            community: CommunitySummary {
                rating_avg: r.rating_avg,
                rating_count: r.rating_count,
                review_count: r.review_count,
                photo_count: r.photo_count,
                cover_photos: serde_json::from_value(r.cover_photos)
                    .map_err(|e| DbError::decode("cover photos", e))?,
                reported_issues: serde_json::from_value(r.reported_issues)
                    .map_err(|e| DbError::decode("reported issues", e))?,
                verification: r
                    .verification
                    .parse()
                    .map_err(|e| DbError::decode("verification", e))?,
            },
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
    /// Leave out places whose known maximum length is below this, metres.
    pub vehicle_length_m: Option<f64>,
    /// Leave out places whose known maximum width is below this, metres.
    pub vehicle_width_m: Option<f64>,
    /// Leave out places whose known maximum weight is below this, tonnes.
    pub vehicle_weight_t: Option<f64>,
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
               country_code, price_parking_eur, price_services_eur, max_height_m, max_length_m,
               max_width_m, max_weight_t, capacity,
               opening_hours, opening_hours_parsed, opening_intervals, opening_intervals_until,
               website, phone, stars, last_confirmed_at, updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into, municipality, descriptions,
               external_links, rating_avg, rating_count, review_count, photo_count, cover_photos,
               reported_issues, verification
        FROM places
        WHERE deleted_at IS NULL
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
          AND ($5::text[] IS NULL OR kind = ANY($5))
          AND services @> $6::text[]
          AND (NOT $7 OR overnight IN ('allowed', 'tolerated'))
          AND ($8::float8 IS NULL OR max_height_m IS NULL OR max_height_m >= $8)
          AND ($11::float8 IS NULL OR max_length_m IS NULL OR max_length_m >= $11)
          AND ($12::float8 IS NULL OR max_width_m IS NULL OR max_width_m >= $12)
          AND ($13::float8 IS NULL OR max_weight_t IS NULL OR max_weight_t >= $13)
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
        filter.vehicle_length_m,
        filter.vehicle_width_m,
        filter.vehicle_weight_t,
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
          AND ($9::float8 IS NULL OR max_length_m IS NULL OR max_length_m >= $9)
          AND ($10::float8 IS NULL OR max_width_m IS NULL OR max_width_m >= $10)
          AND ($11::float8 IS NULL OR max_weight_t IS NULL OR max_weight_t >= $11)
        "#,
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        kinds.as_deref() as Option<&[String]>,
        &services,
        filter.overnight_ok,
        filter.vehicle_height_m,
        filter.vehicle_length_m,
        filter.vehicle_width_m,
        filter.vehicle_weight_t,
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
               country_code, price_parking_eur, price_services_eur, max_height_m, max_length_m,
               max_width_m, max_weight_t, capacity,
               opening_hours, opening_hours_parsed, opening_intervals, opening_intervals_until,
               website, phone, stars, last_confirmed_at, updated_at, updated_seq, provenance,
               deleted_at IS NOT NULL AS "deleted!", merged_into, municipality, descriptions,
               external_links, rating_avg, rating_count, review_count, photo_count, cover_photos,
               reported_issues, verification
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
                   country_code, price_parking_eur, price_services_eur, max_height_m, max_length_m,
               max_width_m, max_weight_t, capacity,
                   opening_hours, opening_hours_parsed, opening_intervals,
                   opening_intervals_until, website, phone, stars, last_confirmed_at,
                   updated_at, updated_seq, provenance,
                   deleted_at IS NOT NULL AS "deleted!", merged_into, municipality,
                   descriptions, external_links, rating_avg, rating_count, review_count,
                   photo_count, cover_photos, reported_issues, verification
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
