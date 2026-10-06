//! The routing graphs and the restrictions every route is checked against.
//!
//! A graph's restrictions are loaded with it, before it serves
//! ([`load_graph`]); [`activate`] makes it the one the API checks routes
//! against, and drops the rows of every graph but it and the one before it,
//! so a rollback finds its rows still there. The API reads the restrictions
//! near a route with [`restrictions_near`].

use std::fmt::Write as _;

use chrono::{DateTime, Utc};
use lunaway_domain::{
    Position,
    routing::{
        Certainty, Restriction, RestrictionFeature, RestrictionKind, RestrictionRecord,
        RestrictionSource,
    },
};
use sqlx::PgPool;
use uuid::Uuid;

use crate::DbError;

/// Rows per insert statement.
const BATCH: usize = 2_000;
/// Most route points the corridor query takes: a route across France has a
/// few tens of thousands (15 234 from Lille to Nice).
pub const MAX_ROUTE_POINTS: usize = 200_000;

/// A graph as stored.
#[derive(Debug, Clone, PartialEq)]
pub struct GraphRow {
    /// Build name (`20261006T0300Z-fr`).
    pub id: String,
    /// The OpenStreetMap data's date.
    pub osm_data_at: DateTime<Utc>,
    /// When the IGN restrictions were read.
    pub ign_fetched_at: Option<DateTime<Utc>>,
    /// The BD TOPO edition the WFS stated.
    pub ign_edition: Option<chrono::NaiveDate>,
    /// When the graph was built.
    pub built_at: DateTime<Utc>,
    /// Engine, version and image.
    pub engine: String,
    /// When it was loaded.
    pub loaded_at: DateTime<Utc>,
    /// When it last became active.
    pub activated_at: Option<DateTime<Utc>>,
    /// Whether it serves.
    pub active: bool,
}

/// A graph about to be loaded.
#[derive(Debug, Clone, PartialEq)]
pub struct NewGraph {
    /// Build name; see the `routing_graphs.id` check.
    pub id: String,
    /// The OpenStreetMap data's date.
    pub osm_data_at: DateTime<Utc>,
    /// When the IGN restrictions were read.
    pub ign_fetched_at: Option<DateTime<Utc>>,
    /// The BD TOPO edition the WFS stated.
    pub ign_edition: Option<chrono::NaiveDate>,
    /// When the graph was built.
    pub built_at: DateTime<Utc>,
    /// Engine, version and image.
    pub engine: String,
    /// The build's counts.
    pub stats: serde_json::Value,
}

/// A restriction near a route, as the check reads it.
#[derive(Debug, Clone, PartialEq)]
pub struct NearRestriction {
    /// Row id.
    pub id: Uuid,
    /// The restriction.
    pub restriction: Restriction,
    /// `way/<id>`, `node/<id>`, `ign/<cleabs>`.
    pub external_id: String,
    /// The road's name.
    pub name: Option<String>,
    /// Its geometry: one point or a line.
    pub geometry: Vec<Position>,
}

fn wkt(points: &[Position]) -> String {
    let mut s = String::with_capacity(points.len() * 24 + 16);
    match points {
        [p] => {
            let _ = write!(s, "POINT({} {})", p.lon(), p.lat());
        }
        _ => {
            s.push_str("LINESTRING(");
            for (i, p) in points.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                let _ = write!(s, "{} {}", p.lon(), p.lat());
            }
            s.push(')');
        }
    }
    s
}

/// Stores `graph`, inactive, with its `records` (each already checked, with
/// its points), in one transaction. A graph of the same name is replaced
/// unless it is the active one.
///
/// # Errors
///
/// [`DbError`] when a statement fails, the active graph included; nothing is
/// kept then.
pub async fn load_graph(
    pool: &PgPool,
    graph: &NewGraph,
    records: &[(RestrictionRecord, Vec<Position>)],
) -> Result<u64, DbError> {
    let mut tx = pool.begin().await?;
    let replaced = sqlx::query!(
        "DELETE FROM routing_graphs WHERE id = $1 AND NOT active",
        graph.id
    )
    .execute(&mut *tx)
    .await?;
    if replaced.rows_affected() > 0 {
        tracing::info!(graph = %graph.id, "an inactive graph of the same name was replaced");
    }
    sqlx::query!(
        r#"
        INSERT INTO routing_graphs (id, osm_data_at, ign_fetched_at, ign_edition, built_at,
            engine, stats)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#,
        graph.id,
        graph.osm_data_at,
        graph.ign_fetched_at,
        graph.ign_edition,
        graph.built_at,
        graph.engine,
        graph.stats,
    )
    .execute(&mut *tx)
    .await?;
    let mut stored = 0;
    // Loading 300 000 rows takes longer than a role's statement limit
    // allows one statement; each batch stays well under it.
    for batch in records.chunks(BATCH) {
        let mut ids = Vec::with_capacity(batch.len());
        let mut sources = Vec::with_capacity(batch.len());
        let mut external_ids = Vec::with_capacity(batch.len());
        let mut kinds = Vec::with_capacity(batch.len());
        let mut limits = Vec::with_capacity(batch.len());
        let mut certainties = Vec::with_capacity(batch.len());
        let mut features = Vec::with_capacity(batch.len());
        let mut names = Vec::with_capacity(batch.len());
        let mut others = Vec::with_capacity(batch.len());
        let mut other_sources = Vec::with_capacity(batch.len());
        let mut geometries = Vec::with_capacity(batch.len());
        let mut observed = Vec::with_capacity(batch.len());
        for (r, points) in batch {
            ids.push(Uuid::now_v7());
            sources.push(r.source.code().to_owned());
            external_ids.push(r.external_id.clone());
            kinds.push(r.kind.code().to_owned());
            limits.push(r.limit);
            certainties.push(r.certainty.code().to_owned());
            features.push(r.feature.code().to_owned());
            names.push(r.name.clone());
            others.push(r.other_value);
            other_sources.push(r.other_source.map(|s| s.code().to_owned()));
            geometries.push(wkt(points));
            observed.push(r.observed_at);
        }
        let done = sqlx::query!(
            r#"
            INSERT INTO route_restrictions (id, graph_id, source, external_id, kind,
                limit_value, certainty, feature, name, other_value, other_source, geom,
                observed_at)
            SELECT id, $1, source, external_id, kind, limit_value, certainty, feature, name,
                other_value, other_source, ST_GeomFromText(geometry, 4326)::geography,
                observed_at
            FROM UNNEST($2::uuid[], $3::text[], $4::text[], $5::text[], $6::float8[],
                $7::text[], $8::text[], $9::text[], $10::float8[], $11::text[], $12::text[],
                $13::timestamptz[])
                AS u(id, source, external_id, kind, limit_value, certainty, feature, name,
                     other_value, other_source, geometry, observed_at)
            "#,
            graph.id,
            &ids,
            &sources,
            &external_ids,
            &kinds,
            &limits as &[Option<f64>],
            &certainties,
            &features,
            &names as &[Option<String>],
            &others as &[Option<f64>],
            &other_sources as &[Option<String>],
            &geometries,
            &observed,
        )
        .execute(&mut *tx)
        .await?;
        stored += done.rows_affected();
    }
    tx.commit().await?;
    Ok(stored)
}

/// What an activation did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Activated {
    /// The graph active before, if any.
    pub previous: Option<String>,
    /// Graphs dropped with their rows: every one but the new and the
    /// previous.
    pub dropped: Vec<String>,
}

/// Makes `id` the active graph and drops every graph but it and the one
/// active before it. `None` when no graph `id` is loaded. Activating the
/// graph already active changes nothing, so a repeated step keeps the
/// previous graph for a rollback.
///
/// # Errors
///
/// [`DbError`] when a statement fails; nothing changes then.
pub async fn activate(pool: &PgPool, id: &str) -> Result<Option<Activated>, DbError> {
    let mut tx = pool.begin().await?;
    let target = sqlx::query!(
        r#"SELECT active FROM routing_graphs WHERE id = $1 FOR UPDATE"#,
        id
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(target) = target else {
        return Ok(None);
    };
    if target.active {
        return Ok(Some(Activated {
            previous: None,
            dropped: Vec::new(),
        }));
    }
    let previous = sqlx::query_scalar!(
        r#"UPDATE routing_graphs SET active = false WHERE active AND id <> $1 RETURNING id AS "id!""#,
        id
    )
    .fetch_optional(&mut *tx)
    .await?;
    sqlx::query!(
        "UPDATE routing_graphs SET active = true, activated_at = now() WHERE id = $1",
        id
    )
    .execute(&mut *tx)
    .await?;
    let keep: Vec<String> = std::iter::once(id.to_owned())
        .chain(previous.clone())
        .collect();
    // The rows go with their graph (ON DELETE CASCADE).
    let dropped = sqlx::query_scalar!(
        r#"DELETE FROM routing_graphs WHERE NOT (id = ANY($1)) RETURNING id AS "id!""#,
        &keep
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Some(Activated { previous, dropped }))
}

/// The active graph, if any.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn active_graph(pool: &PgPool) -> Result<Option<GraphRow>, DbError> {
    Ok(sqlx::query_as!(
        GraphRow,
        r#"
        SELECT id, osm_data_at, ign_fetched_at, ign_edition, built_at, engine, loaded_at,
            activated_at, active
        FROM routing_graphs WHERE active
        "#
    )
    .fetch_optional(pool)
    .await?)
}

/// Every graph loaded, newest build first.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn graphs(pool: &PgPool) -> Result<Vec<GraphRow>, DbError> {
    Ok(sqlx::query_as!(
        GraphRow,
        r#"
        SELECT id, osm_data_at, ign_fetched_at, ign_edition, built_at, engine, loaded_at,
            activated_at, active
        FROM routing_graphs ORDER BY built_at DESC, id DESC
        "#
    )
    .fetch_all(pool)
    .await?)
}

fn decode_row(
    id: Uuid,
    source: &str,
    kind: &str,
    certainty: &str,
    feature: &str,
) -> Result<
    (
        RestrictionSource,
        RestrictionKind,
        Certainty,
        RestrictionFeature,
    ),
    DbError,
> {
    let bad = |what: &'static str, value: &str| {
        DbError::decode(
            what,
            std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("restriction {id}: {value}"),
            ),
        )
    };
    Ok((
        RestrictionSource::from_code(source).ok_or_else(|| bad("restriction source", source))?,
        RestrictionKind::from_code(kind).ok_or_else(|| bad("restriction kind", kind))?,
        Certainty::from_code(certainty).ok_or_else(|| bad("restriction certainty", certainty))?,
        RestrictionFeature::from_code(feature)
            .ok_or_else(|| bad("restriction feature", feature))?,
    ))
}

/// The coordinates of a GeoJSON `Point` or `LineString`.
fn geojson_points(text: &str) -> Option<Vec<Position>> {
    let value: serde_json::Value = serde_json::from_str(text).ok()?;
    let coords = value.get("coordinates")?;
    let pair = |c: &serde_json::Value| -> Option<Position> {
        Position::new(c.get(1)?.as_f64()?, c.get(0)?.as_f64()?).ok()
    };
    match value.get("type")?.as_str()? {
        "Point" => Some(vec![pair(coords)?]),
        "LineString" => coords.as_array()?.iter().map(pair).collect(),
        _ => None,
    }
}

/// The restrictions of graph `graph_id`, and the community's, within
/// `within_m` metres of the line through `route`. The line is cut into
/// pieces of a few dozen points so each piece's index lookup covers a small
/// box, whatever the route's length.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn restrictions_near(
    pool: &PgPool,
    graph_id: &str,
    route: &[Position],
    within_m: f64,
) -> Result<Vec<NearRestriction>, DbError> {
    if route.len() < 2 {
        return Ok(Vec::new());
    }
    // Checking a prefix would leave the rest of the route unchecked.
    if route.len() > MAX_ROUTE_POINTS {
        return Err(DbError::TooLarge {
            what: "route shape points",
            limit: MAX_ROUTE_POINTS,
        });
    }
    let lons: Vec<f64> = route.iter().map(|p| p.lon()).collect();
    let lats: Vec<f64> = route.iter().map(|p| p.lat()).collect();
    let rows = sqlx::query!(
        r#"
        WITH line AS (
            SELECT ST_SetSRID(ST_MakeLine(ARRAY(
                SELECT ST_MakePoint(lon, lat)
                FROM UNNEST($2::float8[], $3::float8[]) WITH ORDINALITY AS u(lon, lat, n)
                ORDER BY n
            )), 4326) AS geom
        ), pieces AS (
            SELECT ST_Subdivide(geom, 32)::geography AS piece FROM line
        )
        SELECT DISTINCT ON (r.id)
            r.id, r.source, r.external_id, r.kind, r.limit_value, r.certainty, r.feature,
            r.name, ST_AsGeoJSON(r.geom::geometry, 7) AS "shape!"
        FROM pieces p
        JOIN route_restrictions r ON ST_DWithin(r.geom, p.piece, $4)
        WHERE r.graph_id = $1 OR r.graph_id IS NULL
        ORDER BY r.id
        "#,
        graph_id,
        &lons,
        &lats,
        within_m,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            let (source, kind, certainty, feature) =
                decode_row(r.id, &r.source, &r.kind, &r.certainty, &r.feature)?;
            let geometry = geojson_points(&r.shape).ok_or_else(|| {
                DbError::decode(
                    "restriction geometry",
                    std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("restriction {}", r.id),
                    ),
                )
            })?;
            Ok(NearRestriction {
                id: r.id,
                restriction: Restriction {
                    kind,
                    limit: r.limit_value,
                    source,
                    certainty,
                    feature,
                },
                external_id: r.external_id,
                name: r.name,
                geometry,
            })
        })
        .collect()
}

/// A disputed restriction: two sources disagree beyond the tolerance.
#[derive(Debug, Clone, PartialEq)]
pub struct Disputed {
    /// `way/<id>`, `node/<id>`, `ign/<cleabs>`.
    pub external_id: String,
    /// What it limits.
    pub kind: RestrictionKind,
    /// The figure that applies (the lower).
    pub limit: Option<f64>,
    /// The other source's figure.
    pub other_value: Option<f64>,
    /// The road's name.
    pub name: Option<String>,
    /// A point of it, latitude then longitude.
    pub at: (f64, f64),
}

/// The disputed restrictions of graph `graph_id`, the review queue, the
/// largest gaps first.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn disputed(pool: &PgPool, graph_id: &str, limit: i64) -> Result<Vec<Disputed>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, external_id, kind, limit_value, other_value, name,
            ST_Y(ST_PointOnSurface(geom::geometry)) AS "lat!",
            ST_X(ST_PointOnSurface(geom::geometry)) AS "lon!"
        FROM route_restrictions
        WHERE graph_id = $1 AND certainty = 'disputed'
        ORDER BY abs(other_value - limit_value) DESC NULLS LAST, external_id
        LIMIT $2
        "#,
        graph_id,
        limit
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            let kind = RestrictionKind::from_code(&r.kind).ok_or_else(|| {
                DbError::decode(
                    "restriction kind",
                    std::io::Error::new(std::io::ErrorKind::InvalidData, r.id.to_string()),
                )
            })?;
            Ok(Disputed {
                external_id: r.external_id,
                kind,
                limit: r.limit_value,
                other_value: r.other_value,
                name: r.name,
                at: (r.lat, r.lon),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn geometries_travel_as_wkt_and_come_back_as_geojson() {
        let a = Position::new(45.8466, 1.2852).unwrap();
        let b = Position::new(45.8462, 1.2855).unwrap();
        assert_eq!(wkt(&[a]), "POINT(1.2852 45.8466)");
        assert_eq!(wkt(&[a, b]), "LINESTRING(1.2852 45.8466,1.2855 45.8462)");
        assert_eq!(
            geojson_points(r#"{"type":"Point","coordinates":[1.2852,45.8466]}"#),
            Some(vec![a])
        );
        assert_eq!(
            geojson_points(
                r#"{"type":"LineString","coordinates":[[1.2852,45.8466],[1.2855,45.8462]]}"#
            ),
            Some(vec![a, b])
        );
        assert_eq!(
            geojson_points(r#"{"type":"Polygon","coordinates":[]}"#),
            None
        );
    }
}
