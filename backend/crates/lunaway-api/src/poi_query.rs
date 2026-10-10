//! The reads of the points of interest: one point, the points around a
//! place, a search, the points of an area for a device to keep offline, and
//! where the map tiles are. Resolvers stay thin: they check the arguments,
//! call `lunaway_db::pois`, and wrap the rows.

use async_graphql::{Context, Result};
use lunaway_db::{poi_search, pois};
use lunaway_domain::{
    BBox, Position,
    poi::{PoiCategory, PoiKind},
};
use uuid::Uuid;

use crate::{
    error::{internal, invalid_input, not_found},
    poi_types::{
        GqlPoiCategory, GqlPoiKind, NearbyPois, Poi, PoiCategoryInfo, PoiConnection, PoiLayer,
    },
    schema::{DB_FIELD_COST, db, state},
    tiles,
    types::{BBoxInput, LatLonInput},
};

/// Most points per category `nearbyPois` returns.
pub(crate) const MAX_NEARBY_PER_CATEGORY: i32 = 10;
/// Farthest `nearbyPois` looks, metres.
pub(crate) const MAX_NEARBY_RADIUS_M: f64 = 20_000.0;
/// Largest page of `pois`.
pub(crate) const MAX_POIS_PAGE: i32 = 1_000;
/// Largest area of `pois`, square degrees: a French département holds in
/// one (about 1 at most), a region in a few.
pub(crate) const MAX_POIS_AREA_DEG2: f64 = 4.0;
/// Most results of `searchPois`.
pub(crate) const MAX_POI_SEARCH_RESULTS: i32 = 50;
const POI_CURSOR: &str = "q1.";

/// The cost of `nearbyPois`: every category asked times the points each
/// may return.
pub(crate) fn nearby_cost(
    per_category: Option<i32>,
    categories: Option<&Vec<GqlPoiCategory>>,
    child: usize,
) -> usize {
    let per =
        usize::try_from(per_category.unwrap_or(1).clamp(1, MAX_NEARBY_PER_CATEGORY)).unwrap_or(1);
    let cats = categories.map_or(PoiCategory::ALL.len(), Vec::len).max(1);
    per.saturating_mul(cats)
        .saturating_mul(child)
        .saturating_add(DB_FIELD_COST)
}

/// Every category with its kinds, in display order.
pub(crate) fn categories() -> Vec<PoiCategoryInfo> {
    PoiCategory::ALL
        .iter()
        .map(|c| PoiCategoryInfo {
            category: (*c).into(),
            kinds: c.kinds().into_iter().map(Into::into).collect(),
            default_radius_m: c.default_radius_m(),
        })
        .collect()
}

pub(crate) async fn poi(ctx: &Context<'_>, id: Uuid) -> Result<Option<Poi>> {
    let (pool, _permit) = db(ctx).await?;
    Ok(pois::by_id(pool, id)
        .await
        .map_err(|e| internal(&e))?
        .map(Poi::new))
}

/// The arguments of `nearbyPois`, as the client sent them.
pub(crate) struct NearbyArgs {
    pub(crate) place_id: Option<Uuid>,
    pub(crate) at: Option<LatLonInput>,
    pub(crate) categories: Option<Vec<GqlPoiCategory>>,
    pub(crate) kinds: Option<Vec<GqlPoiKind>>,
    pub(crate) per_category: Option<i32>,
    pub(crate) radius_m: Option<f64>,
}

pub(crate) async fn nearby(ctx: &Context<'_>, args: NearbyArgs) -> Result<Vec<NearbyPois>> {
    let per_category = args.per_category.unwrap_or(1);
    if !(1..=MAX_NEARBY_PER_CATEGORY).contains(&per_category) {
        return Err(invalid_input(format!(
            "perCategory must be between 1 and {MAX_NEARBY_PER_CATEGORY}"
        )));
    }
    if let Some(r) = args.radius_m
        && !(r.is_finite() && r > 0.0 && r <= MAX_NEARBY_RADIUS_M)
    {
        return Err(invalid_input(format!(
            "radiusM must be above 0 and at most {MAX_NEARBY_RADIUS_M}"
        )));
    }
    // Without categories, those the apps knew before the establishments:
    // an app of then reads every group it gets.
    let asked: Vec<PoiCategory> = args.categories.map_or_else(PoiCategory::around, |c| {
        c.into_iter().map(Into::into).collect()
    });
    if asked.is_empty() || asked.len() > PoiCategory::ALL.len() {
        return Err(invalid_input(format!(
            "categories must hold 1 to {} categories",
            PoiCategory::ALL.len()
        )));
    }
    // Each category is one search: a repeated one would run twice for the
    // price of one.
    let mut seen = std::collections::BTreeSet::new();
    let cats: Vec<PoiCategory> = asked.into_iter().filter(|c| seen.insert(*c)).collect();
    if args
        .kinds
        .as_ref()
        .is_some_and(|k| k.len() > PoiKind::ALL.len())
    {
        return Err(invalid_input("too many kinds"));
    }
    let kinds: Option<Vec<PoiKind>> = args.kinds.map(|k| k.into_iter().map(Into::into).collect());
    let (pool, _permit) = db(ctx).await?;
    let at = match (args.place_id, args.at) {
        (Some(id), None) => {
            lunaway_db::community::live_place(pool, id)
                .await
                .map_err(|e| internal(&e))?
                .ok_or_else(|| not_found("place"))?
                .position
        }
        // A point the client chose is kept on the grid only: the server
        // never holds where the device is (`Position::coarsened`). The
        // error names no coordinate.
        (None, Some(p)) => Position::new(p.lat, p.lon)
            .map_err(|_| invalid_input("at: not a valid position"))?
            .coarsened(),
        _ => return Err(invalid_input("give either placeId or at")),
    };
    let radii: Vec<f64> = cats
        .iter()
        .map(|c| args.radius_m.unwrap_or_else(|| c.default_radius_m()))
        .collect();
    let rows = pois::nearby(
        pool,
        at,
        &cats,
        &radii,
        kinds.as_deref(),
        i64::from(per_category),
    )
    .await
    .map_err(|e| internal(&e))?;
    let mut out: Vec<NearbyPois> = cats
        .iter()
        .zip(&radii)
        .map(|(c, r)| NearbyPois {
            category: (*c).into(),
            radius_m: *r,
            pois: Vec::new(),
        })
        .collect();
    for row in rows {
        let c: GqlPoiCategory = row.category().into();
        if let Some(group) = out.iter_mut().find(|g| g.category == c) {
            group.pois.push(Poi::new(row));
        }
    }
    Ok(out)
}

pub(crate) async fn search(
    ctx: &Context<'_>,
    text: &str,
    near: Option<LatLonInput>,
    categories: Option<Vec<GqlPoiCategory>>,
    first: i32,
) -> Result<Vec<Poi>> {
    if !(1..=MAX_POI_SEARCH_RESULTS).contains(&first) {
        return Err(invalid_input(format!(
            "first must be between 1 and {MAX_POI_SEARCH_RESULTS}"
        )));
    }
    let text = text.trim();
    if !(2..=100).contains(&text.chars().count()) {
        return Err(invalid_input("text must hold 2 to 100 characters"));
    }
    // On the grid only; the error names no coordinate.
    let near = near
        .map(|p| Position::new(p.lat, p.lon).map(Position::coarsened))
        .transpose()
        .map_err(|_| invalid_input("near: not a valid position"))?;
    let cats: Option<Vec<PoiCategory>> =
        categories.map(|c| c.into_iter().map(Into::into).collect());
    Ok(find(ctx, text, near, cats.as_deref(), i64::from(first))
        .await?
        .rows
        .into_iter()
        .map(Poi::new)
        .collect())
}

/// The points matching `text` near `near` (already on the coarse grid),
/// `first` at most (`lunaway_db::poi_search`).
pub(crate) async fn find(
    ctx: &Context<'_>,
    text: &str,
    near: Option<Position>,
    categories: Option<&[PoiCategory]>,
    first: i64,
) -> Result<poi_search::PoiSearch> {
    let st = state(ctx);
    let (pool, _permit) = db(ctx).await?;
    let stats = st.poi_stats.get(pool).await;
    poi_search::search(
        pool,
        poi_search::PoiAsk {
            text,
            near,
            first,
            categories,
        },
        &stats,
    )
    .await
    .map_err(|e| internal(&e))
}

/// How long the planner's statistics of the points' words are kept: they
/// move with the nightly imports, and reading their thousand words costs
/// a millisecond or two a search.
const STATS_FOR: std::time::Duration = std::time::Duration::from_secs(600);

/// The statistics of the search of points, read at most every
/// [`STATS_FOR`].
#[derive(Default)]
pub(crate) struct PoiStatsCache(
    tokio::sync::Mutex<Option<(std::time::Instant, std::sync::Arc<poi_search::PoiStats>)>>,
);

impl PoiStatsCache {
    /// The statistics, read again once they are older than [`STATS_FOR`];
    /// when that read fails, the last ones (or none: every word then rare),
    /// logged.
    pub(crate) async fn get(
        &self,
        pool: &lunaway_db::PgPool,
    ) -> std::sync::Arc<poi_search::PoiStats> {
        let mut held = self.0.lock().await;
        if let Some((at, stats)) = held.as_ref()
            && at.elapsed() < STATS_FOR
        {
            return stats.clone();
        }
        match poi_search::statistics(pool).await {
            Ok(stats) => {
                let stats = std::sync::Arc::new(stats);
                *held = Some((std::time::Instant::now(), stats.clone()));
                stats
            }
            Err(error) => {
                tracing::error!(%error, "the statistics of the search of points did not read");
                held.as_ref().map(|(_, s)| s.clone()).unwrap_or_default()
            }
        }
    }
}

pub(crate) async fn in_area(
    ctx: &Context<'_>,
    bbox: BBoxInput,
    categories: Option<Vec<GqlPoiCategory>>,
    first: i32,
    after: Option<&str>,
) -> Result<PoiConnection> {
    if !(1..=MAX_POIS_PAGE).contains(&first) {
        return Err(invalid_input(format!(
            "first must be between 1 and {MAX_POIS_PAGE}"
        )));
    }
    let area = BBox::new(bbox.south, bbox.west, bbox.north, bbox.east)
        .map_err(|e| invalid_input(format!("bbox: {e}")))?;
    if area.area_deg2() > MAX_POIS_AREA_DEG2 {
        return Err(invalid_input(format!(
            "bbox covers {:.1} square degrees, more than the {MAX_POIS_AREA_DEG2} allowed",
            area.area_deg2()
        )));
    }
    let after = after
        .map(|s| {
            s.strip_prefix(POI_CURSOR)
                .and_then(|u| Uuid::parse_str(u).ok())
                .ok_or_else(|| invalid_input("after is not a cursor this API returned"))
        })
        .transpose()?;
    let cats: Option<Vec<PoiCategory>> =
        categories.map(|c| c.into_iter().map(Into::into).collect());
    let (pool, _permit) = db(ctx).await?;
    let page = pois::in_bbox(pool, area, cats.as_deref(), i64::from(first), after)
        .await
        .map_err(|e| internal(&e))?;
    Ok(PoiConnection {
        end_cursor: page.nodes.last().map(|p| format!("{POI_CURSOR}{}", p.id)),
        has_next_page: page.has_next_page,
        nodes: page.nodes.into_iter().map(Poi::new).collect(),
    })
}

pub(crate) async fn layer(ctx: &Context<'_>) -> Result<PoiLayer> {
    let (pool, _permit) = db(ctx).await?;
    let v = pois::layer_version(pool).await.map_err(|e| internal(&e))?;
    let base = &state(ctx).config.tiles.public_url;
    Ok(PoiLayer {
        version: v.version,
        updated_at: v.changed_at,
        tiles_url: tiles::tile_template(base, v.version),
        tile_json_url: format!("{base}{}", tiles::TILE_JSON_PATH),
        min_zoom: tiles::MIN_ZOOM,
        point_min_zoom: pois::POINT_MIN_ZOOM,
        max_zoom: tiles::MAX_ZOOM,
        attribution: tiles::ATTRIBUTION.to_owned(),
    })
}
