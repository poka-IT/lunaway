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

/// Every source not hidden, by id, with the licence and attribution of its
/// latest agreement when it came under one (`source_terms`).
///
/// # Errors
///
/// [`DbError`] when the query fails or an id is malformed.
pub async fn list(pool: &PgPool) -> Result<Vec<SourceRow>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id AS "id!", name AS "name!", licence AS "licence!",
               licence_url AS "licence_url!", attribution AS "attribution!", url AS "url!"
        FROM source_terms WHERE hidden_at IS NULL ORDER BY id
        "#
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
