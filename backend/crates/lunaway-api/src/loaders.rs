//! Batch loading of what a list of places needs, so a page of 500 places
//! costs one query for their sources, not 500.

use std::{collections::HashMap, sync::Arc};

use async_graphql::dataloader::Loader;
use lunaway_db::{DbError, PgPool, places};
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
