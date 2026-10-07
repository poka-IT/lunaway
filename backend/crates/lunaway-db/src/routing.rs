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
        RestrictionSource, polyline,
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
    let stored = insert_restrictions(&mut tx, Some(&graph.id), records).await?;
    tx.commit().await?;
    Ok(stored)
}

/// Inserts `records` (each already checked, with its points) for graph
/// `graph_id`, or outside any graph (`None`: the community's, DiaLog's), in
/// batches inside `tx`. How many were stored.
pub(crate) async fn insert_restrictions(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    graph_id: Option<&str>,
    records: &[(RestrictionRecord, Vec<Position>)],
) -> Result<u64, DbError> {
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
            graph_id,
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
        .execute(&mut **tx)
        .await?;
        stored += done.rows_affected();
    }
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

/// How many restrictions of `source` are stored (DiaLog's, outside any
/// graph).
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn count_source(pool: &PgPool, source: &str) -> Result<i64, DbError> {
    Ok(sqlx::query_scalar!(
        r#"SELECT count(*) AS "n!" FROM route_restrictions WHERE source = $1"#,
        source
    )
    .fetch_one(pool)
    .await?)
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

/// Most points of one piece of a route sent to a corridor query: a few
/// dozen keep each piece's box small, so that its index lookup reads little.
const PIECE_POINTS: usize = 32;
/// Longest segment of a piece, metres: a longer one gets points in between.
/// The index box encloses the piece as great-circle arcs, the distance
/// filter and the API's matcher read it as straight lines in degrees: by
/// the sagitta of the arc, the two stay within 6 cm of each other over a
/// kilometre at 70 degrees north, and part by about 14 m over a 31 km ferry
/// line at 36 degrees.
const PIECE_SEGMENT_M: f64 = 1_000.0;

/// `route` as the corridor queries take it: consecutive pieces of at most
/// [`PIECE_POINTS`] points, each starting where the previous ends, encoded
/// as polyline6. The client cuts the line rather than `ST_Subdivide`, and
/// sends text PostGIS decodes in C rather than two arrays of floats: on a
/// route of 37 197 points the server-side line and subdivision took 0.25 s
/// of the 1.18 s query, the decoded pieces 7 ms (production, 2026-10-07,
/// `plan/research/48-latence-itineraires.md`).
pub(crate) fn corridor_pieces(route: &[Position]) -> Vec<String> {
    let mut dense: Vec<Position> = Vec::with_capacity(route.len());
    for pair in route.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        dense.push(a);
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "a positive count of points in one segment of a route"
        )]
        let n = (a.distance_m(b) / PIECE_SEGMENT_M).ceil() as u32;
        for k in 1..n {
            let t = f64::from(k) / f64::from(n);
            if let Ok(p) = Position::new(
                a.lat() + (b.lat() - a.lat()) * t,
                a.lon() + (b.lon() - a.lon()) * t,
            ) {
                dense.push(p);
            }
        }
    }
    dense.extend(route.last().copied());
    let mut pieces = Vec::with_capacity(dense.len() / (PIECE_POINTS - 1) + 1);
    let mut start = 0;
    while start + 1 < dense.len() {
        let end = (start + PIECE_POINTS).min(dense.len());
        pieces.push(polyline::encode(&dense[start..end]));
        start = end - 1;
    }
    pieces
}

/// The restrictions of graph `graph_id`, and the community's, within
/// `within_m` metres of the line through `route`, and a few more a little
/// farther: the caller matches each against the route with its own
/// tolerance, under `within_m`.
///
/// The line goes as short pieces ([`corridor_pieces`]), so that each
/// piece's index lookup covers a small box whatever the route's length.
/// The index finds the rows in each piece's box widened by `within_m`; the
/// filter after it is a planar distance in degrees, the metres converted at
/// the piece's highest latitude with a margin, which only ever widens the
/// corridor. The exact distance on the spheroid it replaces cost 0.47 ms a
/// piece, 1.18 s for a route of 3 200 km; the planar one 0.21 s, with 846
/// rows instead of 787 and none missing on six routes (production,
/// 2026-10-07, `plan/research/48-latence-itineraires.md`).
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
    let pieces = corridor_pieces(route);
    // `_ST_Expand` on a geography is the box test `ST_DWithin` runs through
    // the index itself; PostGIS has no public name for it.
    let rows = sqlx::query!(
        r#"
        WITH pieces AS (
            SELECT g AS line, g::geography AS piece,
                $3::float8 * 1.05 / (110574.0 * cos(radians(least(89.0,
                    0.01 + greatest(abs(ST_YMin(g)), abs(ST_YMax(g))))))) AS within_deg
            FROM (SELECT ST_LineFromEncodedPolyline(s, 6) AS g FROM UNNEST($2::text[]) AS s) t
        )
        SELECT DISTINCT ON (r.id)
            r.id, r.source, r.external_id, r.kind, r.limit_value, r.certainty, r.feature,
            r.name, ST_AsGeoJSON(r.geom::geometry, 7) AS "shape!"
        FROM pieces p
        JOIN route_restrictions r
            ON r.geom && _ST_Expand(p.piece, $3)
            AND ST_DWithin(r.geom::geometry, p.line, p.within_deg)
        WHERE r.graph_id = $1 OR r.graph_id IS NULL
        ORDER BY r.id
        "#,
        graph_id,
        &pieces,
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

/// What the restrictions a route is checked against were made of at one
/// time: the active graph, and the rows outside any graph (DiaLog's, the
/// community's), which their importers replace without a new graph. Two
/// equal versions hold the same rows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RestrictionsVersion {
    /// The active graph.
    pub graph_id: String,
    /// Rows outside any graph.
    pub outside_rows: i64,
    /// The newest of them (ids are UUID v7, written in time order).
    pub outside_newest: Option<Uuid>,
}

/// The restrictions' version ([`RestrictionsVersion`]); `None` without an
/// active graph.
///
/// # Errors
///
/// [`DbError`] when the query fails.
pub async fn restrictions_version(pool: &PgPool) -> Result<Option<RestrictionsVersion>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT g.id AS "graph_id!",
            (SELECT count(*) FROM route_restrictions WHERE graph_id IS NULL) AS "outside_rows!",
            (SELECT id FROM route_restrictions WHERE graph_id IS NULL
             ORDER BY id DESC LIMIT 1) AS outside_newest
        FROM routing_graphs g WHERE g.active
        "#
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| RestrictionsVersion {
        graph_id: r.graph_id,
        outside_rows: r.outside_rows,
        outside_newest: r.outside_newest,
    }))
}

/// Dimensions a restriction is weighed against when the rows that may stop
/// a vehicle are read ([`ring_candidates`]).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Envelope {
    /// Metres.
    pub height_m: f64,
    /// Metres.
    pub width_m: f64,
    /// Metres.
    pub length_m: f64,
    /// Tonnes.
    pub weight_t: f64,
}

/// The restrictions of graph `graph_id`, and those outside any graph, that
/// a ring of a few metres excludes without closing another road (a
/// barrier, or a limit of a road other than its clearance: a ring under a
/// bridge would also cut the road above it), and that may stop a vehicle
/// of `envelope`: a limit below its figure, a clearance unknown, a ban of
/// motorhomes. The caller weighs each one against the vehicle exactly
/// (`lunaway_domain::routing::assess`); this only narrows the rows read.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn ring_candidates(
    pool: &PgPool,
    graph_id: &str,
    envelope: Envelope,
) -> Result<Vec<NearRestriction>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT id, source, external_id, kind, limit_value, certainty, feature, name,
            ST_AsGeoJSON(geom::geometry, 7) AS "shape!"
        FROM route_restrictions
        WHERE (graph_id = $1 OR graph_id IS NULL)
          AND (feature = 'barrier' OR (feature = 'road' AND kind <> 'max_height'))
          AND ((kind = 'max_height' AND (limit_value IS NULL OR limit_value < $2))
            OR (kind = 'max_width' AND limit_value < $3)
            OR (kind = 'max_length' AND limit_value < $4)
            OR (kind = 'max_weight' AND limit_value < $5)
            OR kind = 'motorhome_ban')
        "#,
        graph_id,
        envelope.height_m,
        envelope.width_m,
        envelope.length_m,
        envelope.weight_t,
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
    fn the_corridor_pieces_join_up_and_follow_the_route() {
        // 100 points 100 m apart, then one segment of 3.5 km.
        let mut route: Vec<Position> = (0..100)
            .map(|i| Position::new(45.0 + f64::from(i) * 0.0009, 1.0).unwrap())
            .collect();
        route.push(Position::new(45.0891 + 0.0315, 1.0).unwrap());
        let pieces: Vec<Vec<Position>> = corridor_pieces(&route)
            .iter()
            .map(|p| polyline::decode(p).unwrap())
            .collect();
        assert!(
            pieces.iter().all(|p| (2..=PIECE_POINTS).contains(&p.len())),
            "every piece is a line of a few dozen points"
        );
        assert!(
            pieces.windows(2).all(|w| w[0].last() == w[1].first()),
            "each piece starts where the previous ends: no gap in the corridor"
        );
        let joined: Vec<Position> = pieces
            .iter()
            .enumerate()
            .flat_map(|(i, p)| p.iter().skip(usize::from(i > 0)).copied())
            .collect();
        assert_eq!(joined.first(), route.first());
        assert_eq!(joined.last(), route.last());
        assert!(
            route.iter().all(|p| joined.contains(p)),
            "every point of the route is in a piece"
        );
        assert!(
            joined
                .windows(2)
                .all(|w| w[0].distance_m(w[1]) <= PIECE_SEGMENT_M + 1.0),
            "the long segment is cut, so arcs and straight lines agree"
        );
        assert_eq!(joined.len(), 100 + 4, "3.5 km in four segments");
        assert!(corridor_pieces(&route[..1]).is_empty());
    }

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
