//! The GraphQL types of fuel for a motorhome: stations near a point or
//! along a route, ranked by their price with the detour in it, and the
//! price history of a station.

use async_graphql::{ComplexObject, Context, InputObject, Result, SimpleObject};
use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    fuel::{PRICE_HISTORY_DAYS, PriceDay, price_day, price_span},
    poi::FuelKind,
};
use uuid::Uuid;

use crate::{
    loaders::FuelTrendLoader,
    poi_types::{FuelShortage, GqlFuelKind, OpenNow},
    routing_types::VehicleProfileInput,
    types::LatLonInput,
};

/// Days of the short span of a trend.
const WEEK_DAYS: i64 = 7;

/// What to look for along a route.
#[derive(InputObject, Debug, Clone)]
pub struct FuelAlongRouteInput {
    /// The route's line in driving order, as a polyline with six decimals:
    /// the `geometry` of a route of `route`'s `osrmJson`, or the part of it
    /// still ahead. At most 48 000 characters (the request body is 64 KiB):
    /// simplify a long route first (a few tens of metres of tolerance keep
    /// every station where it is). Give `polyline` or `points`.
    pub polyline: Option<String>,
    /// The route's line as points, in driving order (at most 1 000).
    pub points: Option<Vec<LatLonInput>>,
    /// The fuel.
    pub fuel: GqlFuelKind,
    /// The longest detour accepted, kilometres there and back (0.5 to 30):
    /// stations farther than half of it from the route are not looked at.
    #[graphql(default = 5.0)]
    pub max_detour_km: f64,
    /// The vehicle's consumption, litres per 100 km (2 to 50): it prices
    /// the detour.
    pub litres_per_100km: f64,
    /// Litres the driver means to buy (5 to 300): the detour's fuel is
    /// spread over them in `effectivePriceEur`.
    #[graphql(default = 60.0)]
    pub fill_litres: f64,
    /// Stations returned at most (1 to 20).
    #[graphql(default = 10)]
    pub limit: i32,
    /// The vehicle, so the detours are measured on roads it may drive; a
    /// car's limits otherwise.
    pub vehicle: Option<VehicleProfileInput>,
}

/// A station's address in the fuel feed.
#[derive(SimpleObject, Debug, Clone)]
pub struct FuelStationAddress {
    /// Street and number.
    pub street: Option<String>,
    /// Postcode.
    pub postcode: Option<String>,
    /// Town.
    pub city: Option<String>,
}

/// What reaching a station off the route adds.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct FuelDetour {
    /// Kilometres more than the route, there and back.
    pub km: f64,
    /// Minutes more than the route.
    pub minutes: f64,
    /// Measured by the routing engine; an estimate from the straight line
    /// otherwise (the engine did not answer in time).
    pub measured: bool,
    /// Litres the detour burns at the consumption given.
    pub litres: f64,
    /// What they cost at the station's price, euros.
    pub cost_eur: f64,
}

/// A station to refuel at, for one fuel.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(complex)]
pub struct FuelStop {
    /// The station's id in the fuel feed (OpenStreetMap
    /// `ref:FR:prix-carburants`).
    pub station_id: String,
    /// The point of interest that describes it, when OpenStreetMap has one
    /// (`Query.poi`): name, brand, hours, services.
    pub poi_id: Option<Uuid>,
    /// Its name in OpenStreetMap.
    pub name: Option<String>,
    /// Its brand in OpenStreetMap.
    pub brand: Option<String>,
    /// Latitude the feed gives.
    pub lat: f64,
    /// Longitude the feed gives.
    pub lon: f64,
    /// Its address in the feed.
    pub address: Option<FuelStationAddress>,
    /// The fuel asked.
    pub fuel: GqlFuelKind,
    /// Its price, euros per litre.
    pub price_eur: f64,
    /// When the station last changed it.
    pub price_updated_at: DateTime<Utc>,
    /// Whether it is out of the fuel, for now or for good.
    pub shortage: Option<FuelShortage>,
    /// Whether it is open now, from the hours OpenStreetMap gives (unknown
    /// without them).
    pub open_now: OpenNow,
    /// A card machine sells fuel day and night ("automate CB 24/24"): the
    /// station can serve while closed.
    #[graphql(name = "selfService24h")]
    pub self_service_24h: bool,
    /// On a motorway.
    pub highway: bool,
    /// Metres from the point asked (`fuelNearby`), or from the route
    /// (`fuelAlongRoute`), in a straight line.
    pub distance_m: f64,
    /// Kilometres from the route's start to where the station is reached
    /// (`fuelAlongRoute` only).
    pub along_km: Option<f64>,
    /// What the detour adds (`fuelAlongRoute` only).
    pub detour: Option<FuelDetour>,
    /// The price per litre with the detour's fuel spread over the litres
    /// bought: what the stations are ranked by along a route; the price
    /// itself near a point.
    pub effective_price_eur: f64,
    /// When Lunaway read the feed (every 15 minutes).
    pub fetched_at: DateTime<Utc>,
    /// `prix-carburants`.
    pub source_id: String,
    #[graphql(skip)]
    pub(crate) station_ref: String,
    #[graphql(skip)]
    pub(crate) kind: FuelKind,
}

#[ComplexObject]
impl FuelStop {
    /// The price of this fuel over the last days, as Lunaway saw it.
    async fn price_trend(&self, ctx: &Context<'_>) -> Result<Option<FuelPriceTrend>> {
        price_trend(ctx, &self.station_ref, self.kind).await
    }
}

/// Stations along a route.
#[derive(SimpleObject, Debug, Clone)]
pub struct FuelAlongRoute {
    /// The best stations, by effective price, then by distance along the
    /// route.
    pub stations: Vec<FuelStop>,
    /// The route's length, kilometres.
    pub route_km: f64,
    /// Stations with the fuel within half the detour of the route, before
    /// ranking.
    pub candidates: i32,
    /// Whether every detour returned was measured by the routing engine.
    pub detours_measured: bool,
}

/// One day of a station's price for a fuel (Paris time).
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct FuelPriceDay {
    /// The day.
    pub day: NaiveDate,
    /// Lowest price seen that day, euros per litre.
    pub low_eur: f64,
    /// Highest price seen that day.
    pub high_eur: f64,
}

/// What the days of a span say.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct FuelPriceSpan {
    /// Lowest price of the span.
    pub low_eur: f64,
    /// Highest price of the span.
    pub high_eur: f64,
    /// Days of the span Lunaway saw a price on.
    pub days_known: i32,
    /// The last day's low minus the first day's low: below zero, the price
    /// went down; null with fewer than two days known.
    pub change_eur: Option<f64>,
}

/// A station's price of one fuel over the last days, as the poller saw it
/// every quarter of an hour: nothing is inferred for a day it did not see.
#[derive(SimpleObject, Debug, Clone)]
pub struct FuelPriceTrend {
    /// The fuel.
    pub fuel: GqlFuelKind,
    /// The days known, oldest first, the last 30 at most.
    pub days: Vec<FuelPriceDay>,
    /// The last 7 days, today included.
    pub last7_days: Option<FuelPriceSpan>,
    /// The last 30 days, today included.
    pub last30_days: Option<FuelPriceSpan>,
}

/// The trend of `fuel` at station `station_ref`, from its days: none when
/// none is known.
pub(crate) async fn price_trend(
    ctx: &Context<'_>,
    station_ref: &str,
    fuel: FuelKind,
) -> Result<Option<FuelPriceTrend>> {
    let Some(loader) = ctx.data_opt::<async_graphql::dataloader::DataLoader<FuelTrendLoader>>()
    else {
        return Ok(None);
    };
    let days = loader
        .load_one(station_ref.to_owned())
        .await
        .map_err(|e| crate::error::internal(e.as_ref()))?
        .unwrap_or_default();
    let days: Vec<PriceDay> = days
        .into_iter()
        .filter(|d| d.fuel == fuel)
        .map(|d| d.day)
        .collect();
    Ok(trend_of(fuel, &days, price_day(Utc::now())))
}

fn trend_of(fuel: FuelKind, days: &[PriceDay], today: NaiveDate) -> Option<FuelPriceTrend> {
    let span = |length| {
        price_span(days, today, length).map(|s| FuelPriceSpan {
            low_eur: s.low_eur,
            high_eur: s.high_eur,
            days_known: i32::try_from(s.days_known).unwrap_or(i32::MAX),
            change_eur: s.change_eur,
        })
    };
    let last30_days = span(PRICE_HISTORY_DAYS)?;
    let first = today - chrono::Duration::days(PRICE_HISTORY_DAYS - 1);
    let mut kept: Vec<FuelPriceDay> = days
        .iter()
        .filter(|d| d.day >= first && d.day <= today)
        .map(|d| FuelPriceDay {
            day: d.day,
            low_eur: d.low_eur,
            high_eur: d.high_eur,
        })
        .collect();
    kept.sort_by_key(|d| d.day);
    Some(FuelPriceTrend {
        fuel: fuel.into(),
        days: kept,
        last7_days: span(WEEK_DAYS),
        last30_days: Some(last30_days),
    })
}
