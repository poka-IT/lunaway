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
    /// The sync region it belongs to (`lunaway_domain::region`).
    pub region: Option<String>,
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
    pub(crate) region: Option<String>,
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
            region: r.region,
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
    /// Only these overnight statuses (all when `None`).
    pub overnight: Option<Vec<OvernightStatus>>,
    /// The place must have at least one service of each group.
    pub service_groups: Vec<Vec<Service>>,
    /// Only places whose parking is known to be free.
    pub free_only: bool,
}

impl PlaceFilter {
    fn kind_codes(&self) -> Option<Vec<String>> {
        self.kinds
            .as_ref()
            .map(|k| k.iter().map(|k| k.code().to_owned()).collect())
    }

    fn service_codes(&self) -> Vec<String> {
        self.services.iter().map(|s| s.code().to_owned()).collect()
    }

    fn overnight_codes(&self) -> Option<Vec<String>> {
        self.overnight
            .as_ref()
            .map(|o| o.iter().map(|o| o.code().to_owned()).collect())
    }

    /// One mask per group (`places.services_mask`, `Service::mask`): a
    /// place passes a group when its mask shares a bit with it.
    fn group_masks(&self) -> Vec<i32> {
        self.service_groups
            .iter()
            // 17 services fit 17 bits; were a mask ever too wide, 0 keeps
            // nothing rather than everything.
            .map(|g| i32::try_from(Service::mask(g)).unwrap_or(0))
            .collect()
    }
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
    /// With a list sorted by distance, where the next page starts: the
    /// last place read and its distance from the anchor, as the database
    /// computed it.
    pub end_near: Option<NearAfter>,
}

/// Where a page sorted by distance starts: after this place, at this
/// distance from the anchor.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NearAfter {
    /// The distance of the last place of the previous page, metres, exactly
    /// as [`PlacePage::end_near`] gave it.
    pub distance_m: f64,
    /// That place.
    pub id: Uuid,
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
    let kinds = filter.kind_codes();
    let services = filter.service_codes();
    let overnight = filter.overnight_codes();
    let groups = filter.group_masks();
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
               reported_issues, verification, region
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
          AND ($14::text[] IS NULL OR overnight = ANY($14))
          AND NOT EXISTS (SELECT 1 FROM unnest($15::int[]) AS g(m) WHERE services_mask & g.m = 0)
          AND (NOT $16 OR price_parking_eur = 0)
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
        overnight.as_deref() as Option<&[String]>,
        &groups,
        filter.free_only,
    )
    .fetch_all(pool)
    .await?;
    let total_count = count_in_bbox(pool, bbox, filter).await?;
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
        end_near: None,
    })
}

/// Live places inside `bbox` that pass `filter`, nearest to `near` first
/// (the GiST index's ordering, `geom <-> point`, metres on the sphere),
/// ties by id, after `after`.
///
/// # Errors
///
/// [`DbError`] when a query fails or a row does not decode.
pub async fn near_in_bbox(
    pool: &PgPool,
    bbox: BBox,
    filter: &PlaceFilter,
    near: Position,
    first: i64,
    after: Option<NearAfter>,
) -> Result<PlacePage, DbError> {
    let kinds = filter.kind_codes();
    let services = filter.service_codes();
    let overnight = filter.overnight_codes();
    let groups = filter.group_masks();
    let order = sqlx::query!(
        r#"
        WITH anchor AS (
            SELECT ST_SetSRID(ST_MakePoint($14, $15), 4326)::geography AS p
        )
        SELECT id, geom <-> anchor.p AS "distance_m!"
        FROM places CROSS JOIN anchor
        WHERE deleted_at IS NULL
          AND geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
          AND ($5::text[] IS NULL OR kind = ANY($5))
          AND services @> $6::text[]
          AND (NOT $7 OR overnight IN ('allowed', 'tolerated'))
          AND ($8::float8 IS NULL OR max_height_m IS NULL OR max_height_m >= $8)
          AND ($11::float8 IS NULL OR max_length_m IS NULL OR max_length_m >= $11)
          AND ($12::float8 IS NULL OR max_width_m IS NULL OR max_width_m >= $12)
          AND ($13::float8 IS NULL OR max_weight_t IS NULL OR max_weight_t >= $13)
          AND ($16::text[] IS NULL OR overnight = ANY($16))
          AND NOT EXISTS (SELECT 1 FROM unnest($17::int[]) AS g(m) WHERE services_mask & g.m = 0)
          AND (NOT $18 OR price_parking_eur = 0)
          AND ($9::float8 IS NULL
               OR geom <-> anchor.p > $9
               OR (geom <-> anchor.p = $9 AND id > $19))
        ORDER BY geom <-> anchor.p, id
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
        after.map(|a| a.distance_m),
        first + 1,
        filter.vehicle_length_m,
        filter.vehicle_width_m,
        filter.vehicle_weight_t,
        near.lon(),
        near.lat(),
        overnight.as_deref() as Option<&[String]>,
        &groups,
        filter.free_only,
        after.map(|a| a.id),
    )
    .fetch_all(pool)
    .await?;
    let has_next_page = i64::try_from(order.len()).unwrap_or(i64::MAX) > first;
    let order: Vec<(Uuid, f64)> = order
        .into_iter()
        .take(usize::try_from(first).unwrap_or(0))
        .map(|r| (r.id, r.distance_m))
        .collect();
    let ids: Vec<Uuid> = order.iter().map(|(id, _)| *id).collect();
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
               reported_issues, verification, region
        FROM places
        WHERE id = ANY($1)
        "#,
        &ids,
    )
    .fetch_all(pool)
    .await?;
    let mut by_id: std::collections::HashMap<Uuid, PlaceDb> =
        rows.into_iter().map(|r| (r.id, r)).collect();
    // A place deleted between the two reads is left out of this page; the
    // cursor still follows the order read.
    let nodes = ids
        .iter()
        .filter_map(|id| by_id.remove(id))
        .filter(|r| !r.deleted)
        .map(PlaceRow::try_from)
        .collect::<Result<_, _>>()?;
    let total_count = count_in_bbox(pool, bbox, filter).await?;
    Ok(PlacePage {
        nodes,
        has_next_page,
        total_count,
        end_near: order
            .last()
            .map(|&(id, distance_m)| NearAfter { distance_m, id }),
    })
}

/// How many live places inside `bbox` pass `filter`.
async fn count_in_bbox(pool: &PgPool, bbox: BBox, filter: &PlaceFilter) -> Result<i64, DbError> {
    let kinds = filter.kind_codes();
    let services = filter.service_codes();
    let overnight = filter.overnight_codes();
    let groups = filter.group_masks();
    Ok(sqlx::query_scalar!(
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
          AND ($12::text[] IS NULL OR overnight = ANY($12))
          AND NOT EXISTS (SELECT 1 FROM unnest($13::int[]) AS g(m) WHERE services_mask & g.m = 0)
          AND (NOT $14 OR price_parking_eur = 0)
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
        overnight.as_deref() as Option<&[String]>,
        &groups,
        filter.free_only,
    )
    .fetch_one(pool)
    .await?)
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
    /// Moved to another sync region: still a place, gone from this one.
    Left {
        /// The place.
        id: Uuid,
        /// The position at which it left.
        seq: i64,
    },
}

impl Change {
    /// Its position in the feed.
    #[must_use]
    pub fn seq(&self) -> i64 {
        match self {
            Self::Upsert(p) => p.updated_seq,
            Self::Delete { seq, .. } | Self::Left { seq, .. } => *seq,
        }
    }
}

/// Places inside `bbox` changed after `since`, in feed order, at most
/// `first`; plus whether more follow. Deletions are left out when
/// `with_deletions` is false (a first sync has nothing to delete). A place
/// taken down keeps no position: its tombstone goes to every box, a
/// deletion of a place a device never held being a no-op for it.
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
               reported_issues, verification, region
        FROM places
        WHERE updated_seq > $5
          AND (geom::geometry && ST_MakeEnvelope($1, $2, $3, $4, 4326)
               OR taken_down_at IS NOT NULL)
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
    page_of_changes(rows, first)
}

/// The places of the sync region `region` changed after `since`, in feed
/// order, at most `first`, and the places that left it within the same
/// positions, at most `first` too; plus whether more follow. A place keeps
/// its region in its tombstone, so its deletion reaches the devices that
/// keep the region; a place that left the region (its commune or its
/// country changed) comes as [`Change::Left`], once, at the position it last
/// left at (`place_region_exits`). Deletions and departures are left out
/// when `with_deletions` is false. Both reads see one snapshot: a writer
/// committing between them could otherwise give a departure whose position
/// passes changes the first read did not see, and the cursor would skip
/// them.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn changes_in_region(
    pool: &PgPool,
    region: &str,
    since: i64,
    first: i64,
    with_deletions: bool,
) -> Result<(Vec<Change>, bool), DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *tx)
        .await?;
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
               reported_issues, verification, region
        FROM places
        WHERE region = $1 AND updated_seq > $2 AND ($3 OR deleted_at IS NULL)
        ORDER BY updated_seq
        LIMIT $4
        "#,
        region,
        since,
        with_deletions,
        first + 1,
    )
    .fetch_all(&mut *tx)
    .await?;
    let (mut changes, mut has_more) = page_of_changes(rows, first)?;
    if !with_deletions {
        tx.rollback().await?;
        return Ok((changes, has_more));
    }
    // The departures within the page: up to its last change when more
    // follow, all of them otherwise, at most `first`. A place that came back
    // to the region is not a departure.
    let upto = if has_more {
        changes.last().map_or(since, Change::seq)
    } else {
        i64::MAX
    };
    let exits = sqlx::query!(
        r#"
        SELECT e.place_id, e.seq FROM place_region_exits e
        WHERE e.region = $1 AND e.seq > $2 AND e.seq <= $3
          AND NOT EXISTS (SELECT 1 FROM places p WHERE p.id = e.place_id AND p.region = e.region)
        ORDER BY e.seq
        LIMIT $4
        "#,
        region,
        since,
        upto,
        first + 1,
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.rollback().await?;
    let mut exits: Vec<Change> = exits
        .into_iter()
        .map(|e| Change::Left {
            id: e.place_id,
            seq: e.seq,
        })
        .collect();
    if i64::try_from(exits.len()).unwrap_or(i64::MAX) > first {
        // Too many for one page: it ends at the last departure it holds.
        exits.truncate(usize::try_from(first).unwrap_or(0));
        let cut = exits.last().map_or(since, Change::seq);
        changes.retain(|c| c.seq() <= cut);
        has_more = true;
    }
    // A place that left, came back and left again is listed once, at its
    // last departure.
    let mut listed = std::collections::HashSet::new();
    exits.reverse();
    exits.retain(|c| match c {
        Change::Left { id, .. } => listed.insert(*id),
        _ => true,
    });
    changes.extend(exits);
    changes.sort_by_key(Change::seq);
    Ok((changes, has_more))
}

fn page_of_changes(rows: Vec<PlaceDb>, first: i64) -> Result<(Vec<Change>, bool), DbError> {
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
                   photo_count, cover_photos, reported_issues, verification, region
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
    /// Its licence, as a reader sees it.
    pub licence: String,
    /// The reference of the written agreement its records came under, when
    /// they did (`source_terms.agreement`): a pack's licence names it, a
    /// screen does not.
    pub agreement: Option<String>,
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

/// The sources of every place in `ids`, in one query, each with the
/// licence and attribution of its latest agreement when it came under one
/// (`source_terms`); a hidden source's records are left out, before the
/// conflation unlinks them.
///
/// # Errors
///
/// [`DbError`] when the query fails or a source id is malformed.
pub async fn sources_of(pool: &PgPool, ids: &[Uuid]) -> Result<Vec<PlaceSourceRow>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT ps.place_id, ps.match_score, r.external_id, r.external_url,
               lunaway_read_at('records', r.source_id, r.scope, r.fetched_at, r.deleted_at)
                   AS "fetched_at!",
               s.id AS "source_id!", s.name AS "name!", s.licence AS "licence!",
               s.agreement AS "agreement?", s.attribution AS "attribution!", s.url AS "url!"
        FROM place_sources ps
        JOIN source_records r ON r.id = ps.record_id
        JOIN source_terms s ON s.id = r.source_id
        WHERE ps.place_id = ANY($1) AND s.hidden_at IS NULL
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
                agreement: r.agreement,
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
