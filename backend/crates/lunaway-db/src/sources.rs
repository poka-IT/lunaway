//! The data sources and their terms.

use lunaway_domain::SourceId;

use crate::{DbError, PgPool};

/// A source as the `sources` table describes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceRow {
    /// Stable id.
    pub id: SourceId,
    /// Display name.
    pub name: String,
    /// Licence name.
    pub licence: String,
    /// Licence text URL.
    pub licence_url: String,
    /// Attribution to show with the data.
    pub attribution: String,
    /// Home page of the source.
    pub url: String,
}

/// Every source, by id.
///
/// # Errors
///
/// [`DbError`] when the query fails or an id is malformed.
pub async fn list(pool: &PgPool) -> Result<Vec<SourceRow>, DbError> {
    let rows = sqlx::query!(
        "SELECT id, name, licence, licence_url, attribution, url FROM sources ORDER BY id"
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(SourceRow {
                id: SourceId::new(&r.id).map_err(|e| DbError::decode("source id", e))?,
                name: r.name,
                licence: r.licence,
                licence_url: r.licence_url,
                attribution: r.attribution,
                url: r.url,
            })
        })
        .collect()
}
