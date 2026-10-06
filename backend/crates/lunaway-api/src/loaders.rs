//! Batch loading of what a list of places needs, so a page of 500 places
//! costs one query for their sources, not 500.

use std::{collections::HashMap, sync::Arc};

use async_graphql::dataloader::Loader;
use lunaway_db::{DbError, PgPool, places};
use uuid::Uuid;

/// The sources of places, by place id.
pub(crate) struct PlaceSourcesLoader {
    pub(crate) pool: PgPool,
}

impl Loader<Uuid> for PlaceSourcesLoader {
    type Value = Vec<places::PlaceSourceRow>;
    type Error = Arc<DbError>;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let rows = places::sources_of(&self.pool, keys)
            .await
            .map_err(Arc::new)?;
        let mut out: HashMap<Uuid, Self::Value> = HashMap::with_capacity(keys.len());
        for row in rows {
            out.entry(row.place_id).or_default().push(row);
        }
        Ok(out)
    }
}
