//! Batch loading of what a list of places needs, so a page of 500 places
//! costs one query for their sources, not 500.

use std::{collections::HashMap, sync::Arc};

use async_graphql::dataloader::Loader;
use lunaway_db::{DbError, PgPool, fuel, places, poi_reviews, pois};
use lunaway_domain::poi::FuelKind;
use uuid::Uuid;

/// The sources of places, by place id: read from the database, or handed
/// over already read (a pack, built from one snapshot of the database).
pub(crate) enum PlaceSourcesLoader {
    /// Read from the pool.
    Pool(PgPool),
    /// Read beforehand, every place's.
    Read(HashMap<Uuid, Vec<places::PlaceSourceRow>>),
}

impl Loader<Uuid> for PlaceSourcesLoader {
    type Value = Vec<places::PlaceSourceRow>;
    type Error = Arc<DbError>;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let pool = match self {
            Self::Pool(pool) => pool,
            Self::Read(read) => {
                return Ok(keys
                    .iter()
                    .filter_map(|k| read.get(k).map(|v| (*k, v.clone())))
                    .collect());
            }
        };
        let rows = places::sources_of(pool, keys).await.map_err(Arc::new)?;
        let mut out: HashMap<Uuid, Self::Value> = HashMap::with_capacity(keys.len());
        for row in rows {
            out.entry(row.place_id).or_default().push(row);
        }
        Ok(out)
    }
}

/// The price history of a fuel at a station, by the station's id in the
/// feed and the fuel: the last [`lunaway_domain::fuel::PRICE_HISTORY_DAYS`]
/// days.
pub(crate) struct FuelTrendLoader(pub(crate) PgPool);

impl Loader<(String, FuelKind)> for FuelTrendLoader {
    type Value = Vec<lunaway_domain::fuel::PriceDay>;
    type Error = Arc<DbError>;

    async fn load(
        &self,
        keys: &[(String, FuelKind)],
    ) -> Result<HashMap<(String, FuelKind), Self::Value>, Self::Error> {
        let today = lunaway_domain::fuel::price_day(chrono::Utc::now());
        let since = today - chrono::Duration::days(lunaway_domain::fuel::PRICE_HISTORY_DAYS - 1);
        let rows = fuel::price_days(&self.0, keys, since)
            .await
            .map_err(Arc::new)?;
        let mut out: HashMap<(String, FuelKind), Self::Value> = HashMap::with_capacity(keys.len());
        for row in rows {
            out.entry((row.station_ref, row.fuel))
                .or_default()
                .push(row.day);
        }
        Ok(out)
    }
}

/// The points of interest by id, for the account's "still there?" answers:
/// a page of them costs one query.
pub(crate) struct PoiLoader(pub(crate) PgPool);

impl Loader<Uuid> for PoiLoader {
    type Value = pois::PoiRow;
    type Error = Arc<DbError>;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let rows = pois::by_ids(&self.0, keys).await.map_err(Arc::new)?;
        Ok(rows.into_iter().map(|r| (r.id, r)).collect())
    }
}

/// Lunaway users' rating of points of interest, by id: a page of search
/// results asking for it costs one query.
pub(crate) struct PoiRatingsLoader(pub(crate) PgPool);

impl Loader<Uuid> for PoiRatingsLoader {
    type Value = poi_reviews::PoiRating;
    type Error = Arc<DbError>;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let rows = poi_reviews::ratings_of(&self.0, keys)
            .await
            .map_err(Arc::new)?;
        Ok(rows.into_iter().map(|r| (r.poi_id, r)).collect())
    }
}
