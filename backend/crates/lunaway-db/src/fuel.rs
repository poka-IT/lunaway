//! The fuel feed's stations as places to refuel (`fuelNearby`,
//! `fuelAlongRoute`), and their price history (`fuel_price_days`).
//!
//! The stations are the live rows of `prix-carburants` in
//! `poi_join_records`, with the position the feed gives them: about 10 000,
//! whether an OpenStreetMap element names them or not. The element that
//! does (`pois.fuel_ref`) adds a name, a brand and opening hours.

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    OpeningInterval, Position,
    fuel::PriceDay,
    poi::{FuelKind, FuelStation},
};
use uuid::Uuid;

use crate::{DbError, PgPool};

/// Most stations a box query returns: the feed's whole list fits.
const MAX_IN_BOX: i64 = 20_000;

/// The OpenStreetMap element that names a station.
#[derive(Debug, Clone, PartialEq)]
pub struct StationPoi {
    /// The point of interest.
    pub id: Uuid,
    /// Its name.
    pub name: Option<String>,
    /// Its brand.
    pub brand: Option<String>,
    /// Open day and night.
    pub always_open: bool,
    /// Its opening intervals, as the worker computed them.
    pub opening_intervals: Option<Vec<OpeningInterval>>,
    /// Until when the intervals are known.
    pub opening_intervals_until: Option<DateTime<Utc>>,
}

/// A station of the feed.
#[derive(Debug, Clone, PartialEq)]
pub struct FuelStationRow {
    /// Its id in the feed.
    pub station_ref: String,
    /// What the feed says of it.
    pub station: FuelStation,
    /// When Lunaway read the feed.
    pub fetched_at: DateTime<Utc>,
    /// Where the feed puts it.
    pub position: Position,
    /// Metres from the point asked, for a query around a point.
    pub distance_m: Option<f64>,
    /// The element that names it, if one does.
    pub poi: Option<StationPoi>,
}

/// A station's position and price, for the corridor of a route.
#[derive(Debug, Clone, PartialEq)]
pub struct StationPoint {
    /// Its id in the feed.
    pub station_ref: String,
    /// Where the feed puts it.
    pub position: Position,
    /// Its price of the fuel asked, euros per litre.
    pub price_eur: f64,
    /// The feed says it is out of that fuel.
    pub in_shortage: bool,
}

struct StationDb {
    station_ref: String,
    data: serde_json::Value,
    fetched_at: DateTime<Utc>,
    lat: f64,
    lon: f64,
    distance_m: Option<f64>,
    poi_id: Option<Uuid>,
    poi_name: Option<String>,
    poi_brand: Option<String>,
    always_open: Option<bool>,
    opening_intervals: Option<serde_json::Value>,
    opening_intervals_until: Option<DateTime<Utc>>,
}

impl TryFrom<StationDb> for FuelStationRow {
    type Error = DbError;

    fn try_from(r: StationDb) -> Result<Self, DbError> {
        let poi = match r.poi_id {
            None => None,
            Some(id) => Some(StationPoi {
                id,
                name: r.poi_name,
                brand: r.poi_brand,
                always_open: r.always_open.unwrap_or(false),
                opening_intervals: r
                    .opening_intervals
                    .map(serde_json::from_value)
                    .transpose()
                    .map_err(|e| DbError::decode("opening intervals", e))?,
                opening_intervals_until: r.opening_intervals_until,
            }),
        };
        Ok(Self {
            station: serde_json::from_value(r.data)
                .map_err(|e| DbError::decode("fuel station", e))?,
            position: Position::new(r.lat, r.lon)
                .map_err(|e| DbError::decode("fuel station position", e))?,
            station_ref: r.station_ref,
            fetched_at: r.fetched_at,
            distance_m: r.distance_m,
            poi,
        })
    }
}

/// The stations within `radius_m` of `at` with a price of `fuel` updated
/// since `fresh_since`, at most `limit`: those not out of it first, then
/// the cheapest, then the nearest.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn near(
    pool: &PgPool,
    fuel: FuelKind,
    at: Position,
    radius_m: f64,
    fresh_since: DateTime<Utc>,
    limit: i64,
) -> Result<Vec<FuelStationRow>, DbError> {
    let rows = sqlx::query_as!(
        StationDb,
        r#"
        SELECT j.ref AS "station_ref!", j.data AS "data!", j.fetched_at AS "fetched_at!",
               ST_Y(j.geom::geometry) AS "lat!", ST_X(j.geom::geometry) AS "lon!",
               ST_Distance(j.geom, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography)
                   AS "distance_m?",
               p.id AS "poi_id?", p.name AS "poi_name?", p.brand AS "poi_brand?",
               p.always_open AS "always_open?", p.opening_intervals AS "opening_intervals?",
               p.opening_intervals_until AS "opening_intervals_until?"
        FROM poi_join_records j
        CROSS JOIN LATERAL (
            SELECT (e ->> 'price_eur')::double precision AS eur
            FROM jsonb_array_elements(j.data -> 'prices') e
            WHERE e ->> 'fuel' = $1 AND (e ->> 'updated_at')::timestamptz >= $5
            LIMIT 1
        ) price
        LEFT JOIN LATERAL (
            SELECT id, name, brand, always_open, opening_intervals, opening_intervals_until
            FROM pois
            WHERE fuel_ref = j.ref AND deleted_at IS NULL AND NOT hidden
            ORDER BY id
            LIMIT 1
        ) p ON true
        WHERE j.source_id = 'prix-carburants' AND j.deleted_at IS NULL
          AND ST_DWithin(j.geom, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, $4)
        ORDER BY EXISTS (
                     SELECT 1 FROM jsonb_array_elements(j.data -> 'shortages') s
                     WHERE s ->> 'fuel' = $1),
                 price.eur,
                 ST_Distance(j.geom, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography),
                 j.ref
        LIMIT $6
        "#,
        fuel.code(),
        at.lat(),
        at.lon(),
        radius_m,
        fresh_since,
        limit,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter().map(FuelStationRow::try_from).collect()
}

/// The stations inside the box with a price of `fuel` updated since
/// `fresh_since`: the candidates of a route's corridor, before it is
/// drawn.
///
/// # Errors
///
/// [`DbError`] when the query fails or a position does not decode.
pub async fn in_box(
    pool: &PgPool,
    fuel: FuelKind,
    bbox: lunaway_domain::BBox,
    fresh_since: DateTime<Utc>,
) -> Result<Vec<StationPoint>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT j.ref AS "station_ref!", ST_Y(j.geom::geometry) AS "lat!",
               ST_X(j.geom::geometry) AS "lon!", price.eur AS "price_eur!",
               EXISTS (
                   SELECT 1 FROM jsonb_array_elements(j.data -> 'shortages') s
                   WHERE s ->> 'fuel' = $1) AS "in_shortage!"
        FROM poi_join_records j
        CROSS JOIN LATERAL (
            SELECT (e ->> 'price_eur')::double precision AS eur
            FROM jsonb_array_elements(j.data -> 'prices') e
            WHERE e ->> 'fuel' = $1 AND (e ->> 'updated_at')::timestamptz >= $6
            LIMIT 1
        ) price
        WHERE j.source_id = 'prix-carburants' AND j.deleted_at IS NULL
          AND j.geom && ST_MakeEnvelope($2, $3, $4, $5, 4326)::geography
        ORDER BY j.ref
        LIMIT $7
        "#,
        fuel.code(),
        bbox.west(),
        bbox.south(),
        bbox.east(),
        bbox.north(),
        fresh_since,
        MAX_IN_BOX,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(StationPoint {
                position: Position::new(r.lat, r.lon)
                    .map_err(|e| DbError::decode("fuel station position", e))?,
                station_ref: r.station_ref,
                price_eur: r.price_eur,
                in_shortage: r.in_shortage,
            })
        })
        .collect()
}

/// The live stations among `refs`, in no particular order.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn by_refs(pool: &PgPool, refs: &[String]) -> Result<Vec<FuelStationRow>, DbError> {
    let rows = sqlx::query_as!(
        StationDb,
        r#"
        SELECT j.ref AS "station_ref!", j.data AS "data!", j.fetched_at AS "fetched_at!",
               ST_Y(j.geom::geometry) AS "lat!", ST_X(j.geom::geometry) AS "lon!",
               NULL::double precision AS "distance_m?",
               p.id AS "poi_id?", p.name AS "poi_name?", p.brand AS "poi_brand?",
               p.always_open AS "always_open?", p.opening_intervals AS "opening_intervals?",
               p.opening_intervals_until AS "opening_intervals_until?"
        FROM poi_join_records j
        LEFT JOIN LATERAL (
            SELECT id, name, brand, always_open, opening_intervals, opening_intervals_until
            FROM pois
            WHERE fuel_ref = j.ref AND deleted_at IS NULL AND NOT hidden
            ORDER BY id
            LIMIT 1
        ) p ON true
        WHERE j.source_id = 'prix-carburants' AND j.deleted_at IS NULL
          AND j.ref = ANY($1) AND j.geom IS NOT NULL
        "#,
        refs,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter().map(FuelStationRow::try_from).collect()
}

/// A price the poller saw.
#[derive(Debug, Clone, PartialEq)]
pub struct PriceSeen {
    /// The station's id in the feed.
    pub station_ref: String,
    /// The fuel.
    pub fuel: FuelKind,
    /// Euros per litre.
    pub price_eur: f64,
}

/// Records the prices of one poll under `day`: a new day starts at the
/// price, a known day lowers its low or raises its high. A day that did not
/// move is not written. Returns the days written.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn record_price_days(
    pool: &PgPool,
    seen: &[PriceSeen],
    day: NaiveDate,
) -> Result<u64, DbError> {
    let refs: Vec<&str> = seen.iter().map(|s| s.station_ref.as_str()).collect();
    let fuels: Vec<&str> = seen.iter().map(|s| s.fuel.code()).collect();
    let prices: Vec<f64> = seen.iter().map(|s| s.price_eur).collect();
    let done = sqlx::query!(
        r#"
        INSERT INTO fuel_price_days AS d (station_ref, fuel, day, low_eur, high_eur)
        SELECT u.station_ref, u.fuel, $4, u.eur, u.eur
        FROM UNNEST($1::text[], $2::text[], $3::double precision[]) AS u(station_ref, fuel, eur)
        ON CONFLICT (station_ref, fuel, day) DO UPDATE SET
            low_eur = least(d.low_eur, EXCLUDED.low_eur),
            high_eur = greatest(d.high_eur, EXCLUDED.high_eur)
        WHERE EXCLUDED.low_eur < d.low_eur OR EXCLUDED.high_eur > d.high_eur
        "#,
        &refs as &[&str],
        &fuels as &[&str],
        &prices,
        day,
    )
    .execute(pool)
    .await?;
    Ok(done.rows_affected())
}

/// Removes the days before `first_kept`; returns how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn purge_price_days(pool: &PgPool, first_kept: NaiveDate) -> Result<u64, DbError> {
    let done = sqlx::query!("DELETE FROM fuel_price_days WHERE day < $1", first_kept)
        .execute(pool)
        .await?;
    Ok(done.rows_affected())
}

/// A station's day for one fuel.
#[derive(Debug, Clone, PartialEq)]
pub struct StationPriceDay {
    /// The station's id in the feed.
    pub station_ref: String,
    /// The fuel.
    pub fuel: FuelKind,
    /// The day.
    pub day: PriceDay,
}

/// The days of `refs` from `since` on, in station, fuel and day order.
///
/// # Errors
///
/// [`DbError`] when the query fails or a fuel does not decode.
pub async fn price_days(
    pool: &PgPool,
    refs: &[String],
    since: NaiveDate,
) -> Result<Vec<StationPriceDay>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT station_ref, fuel, day, low_eur, high_eur
        FROM fuel_price_days
        WHERE station_ref = ANY($1) AND day >= $2
        ORDER BY station_ref, fuel, day
        "#,
        refs,
        since,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(StationPriceDay {
                fuel: r
                    .fuel
                    .parse::<FuelKind>()
                    .map_err(|e| DbError::decode("fuel", e))?,
                station_ref: r.station_ref,
                day: PriceDay {
                    day: r.day,
                    low_eur: r.low_eur,
                    high_eur: r.high_eur,
                },
            })
        })
        .collect()
}
