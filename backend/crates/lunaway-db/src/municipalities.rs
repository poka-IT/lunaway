//! The French communes, and the commune of every place.
//!
//! `lunaway ingest municipalities` replaces the whole set in one writer
//! transaction, then gives every live place the commune that covers its
//! point; a place whose commune changes takes a new position in the change
//! feed, so devices receive the name their offline search needs.

use chrono::{DateTime, Utc};

use crate::{DbError, conflation::WriterTx};

/// One commune as the importer read it.
#[derive(Debug, Clone, PartialEq)]
pub struct Municipality {
    /// INSEE code.
    pub code: String,
    /// Name.
    pub name: String,
    /// Its outline: a GeoJSON `Polygon` or `MultiPolygon`, WGS 84.
    pub geometry: serde_json::Value,
}

/// What a load changed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct LoadStats {
    /// Communes stored.
    pub municipalities: u64,
    /// Live places whose commune changed.
    pub places_changed: u64,
}

/// Rows per statement.
const BATCH: usize = 500;

/// Replaces every commune with `all`, then gives every live place the
/// commune that covers it, in the writer transaction `tx`.
///
/// # Errors
///
/// [`DbError`] when a statement fails (a geometry PostGIS refuses included);
/// nothing is kept unless the caller commits.
pub async fn replace_all(
    tx: &mut WriterTx,
    all: &[Municipality],
    fetched_at: DateTime<Utc>,
) -> Result<LoadStats, DbError> {
    sqlx::query!("DELETE FROM municipalities")
        .execute(tx.conn())
        .await?;
    let mut stored = 0;
    for batch in all.chunks(BATCH) {
        let codes: Vec<String> = batch.iter().map(|m| m.code.clone()).collect();
        let names: Vec<String> = batch.iter().map(|m| m.name.clone()).collect();
        let geometries: Vec<String> = batch.iter().map(|m| m.geometry.to_string()).collect();
        let done = sqlx::query!(
            r#"
            INSERT INTO municipalities (code, name, geom, fetched_at)
            SELECT code, name, ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(geometry), 4326)), $4
            FROM UNNEST($1::text[], $2::text[], $3::text[]) AS u(code, name, geometry)
            "#,
            &codes,
            &names,
            &geometries,
            fetched_at,
        )
        .execute(tx.conn())
        .await?;
        stored += done.rows_affected();
    }
    let places_changed = refresh_places(tx).await?;
    Ok(LoadStats {
        municipalities: stored,
        places_changed,
    })
}

/// Gives every live place the commune that covers its point, else, for a
/// French place, the nearest within 0.015 degree (as the conflation does),
/// moving in the change feed only the places whose commune changed. Returns
/// how many.
///
/// # Errors
///
/// [`DbError`] when the statement fails.
pub async fn refresh_places(tx: &mut WriterTx) -> Result<u64, DbError> {
    let done = sqlx::query!(
        r#"
        WITH computed AS (
            SELECT p.id, m.name, m.code
            FROM places p
            LEFT JOIN LATERAL (
                -- As the conflation does: the covering commune, else, for a
                -- French place, the nearest within 0.015 degree.
                SELECT name, code FROM municipalities mm
                WHERE ST_DWithin(mm.geom, p.geom::geometry,
                                 CASE WHEN upper(p.country_code) = 'FR' THEN 0.015 ELSE 0.0 END)
                ORDER BY NOT ST_Covers(mm.geom, p.geom::geometry),
                         ST_Distance(mm.geom, p.geom::geometry), code
                LIMIT 1
            ) m ON true
            WHERE p.deleted_at IS NULL
        )
        UPDATE places p
        SET municipality = c.name, municipality_code = c.code,
            updated_at = now(), updated_seq = nextval('place_change_seq')
        FROM computed c
        WHERE p.id = c.id
          AND (p.municipality IS DISTINCT FROM c.name
               OR p.municipality_code IS DISTINCT FROM c.code)
        "#
    )
    .execute(tx.conn())
    .await?;
    Ok(done.rows_affected())
}
