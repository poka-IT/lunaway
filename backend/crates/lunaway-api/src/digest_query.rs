//! `Query.placeDigests`: what the rows of a list show of their places
//! beyond the summary (the ratings by source, an excerpt of the
//! description, the day Lunaway added the place), for the places a list or
//! a search just received, or for the places of an area the app read from
//! the map's tiles. Resolvers stay thin: they check the arguments, call
//! `lunaway_db::digests`, and cut the excerpts.

use async_graphql::{Context, Result, SimpleObject};
use chrono::{DateTime, Utc};
use lunaway_db::digests::{self, DigestRow};
use lunaway_domain::{
    BBox,
    geo::COARSE_GRID_DEG,
    listing::{EXCERPT_CHARS, excerpt},
};
use uuid::Uuid;

use crate::{
    community_types::SourceRating,
    error::{internal, invalid_input},
    schema::db,
    types::{BBoxInput, LocalizedText},
};

/// Most places of `placeDigests(ids:)`: the longest list the app asks
/// about at once (the nearest 200 of a view, a page of a search).
pub(crate) const MAX_DIGEST_IDS: usize = 200;
/// Most places of `placeDigests(bbox:)`.
pub(crate) const MAX_DIGEST_BBOX_PLACES: i64 = 2_000;
/// Largest area of `placeDigests(bbox:)`, square degrees, once widened to
/// the grid: the view of a large screen at the zoom from which the app
/// lists the places of its tiles (12) holds in a fifth of it.
pub(crate) const MAX_DIGEST_AREA_DEG2: f64 = 1.0;

/// What a row of a list shows of a place beyond its summary. Read by the
/// app for the rows on screen and kept in memory only: the change feed,
/// the packs and the tiles never carry the external source's ratings.
#[derive(SimpleObject, Debug, Clone)]
pub struct PlaceDigest {
    /// The place.
    pub place_id: Uuid,
    /// Its ratings by source, never added together: Lunaway users'
    /// (`community-cc-by`), and the external community source's summary
    /// as the place's card shows it (`Place.externalRatings` without
    /// Mangrove's, which only the card reads).
    pub ratings: Vec<SourceRating>,
    /// The opening of its description in the language asked, else in
    /// English, else the first a source wrote: line breaks as spaces, cut
    /// after a whole word within 140 characters, an ellipsis when cut.
    /// Null for a place without a description.
    pub excerpt: Option<LocalizedText>,
    /// When Lunaway added the place.
    pub added_at: DateTime<Utc>,
}

impl PlaceDigest {
    fn from_row(row: DigestRow) -> Self {
        let ratings = row
            .community
            .into_iter()
            .chain(row.external)
            .map(|r| SourceRating {
                source_id: r.source_id,
                average: r.average,
                count: r.count,
            })
            .collect();
        let excerpt = row.description.and_then(|d| {
            excerpt(&d.text, EXCERPT_CHARS).map(|text| LocalizedText {
                lang: d.lang,
                text,
                source_id: d.source_id,
            })
        });
        Self {
            place_id: row.id,
            ratings,
            excerpt,
            added_at: row.created_at,
        }
    }
}

/// The complexity of `placeDigests`: its places, at most, times the cost of
/// one.
pub(crate) fn digests_cost(ids: Option<&Vec<Uuid>>, child: usize) -> usize {
    let places = ids.map_or(
        usize::try_from(MAX_DIGEST_BBOX_PLACES).unwrap_or(usize::MAX),
        Vec::len,
    );
    places
        .saturating_mul(child)
        .saturating_add(crate::schema::DB_FIELD_COST)
}

/// The digests of `ids` or of the places in `bbox`, exactly one of the two,
/// with their excerpts in `language`.
pub(crate) async fn place_digests(
    ctx: &Context<'_>,
    ids: Option<Vec<Uuid>>,
    bbox: Option<BBoxInput>,
    language: Option<String>,
) -> Result<Vec<PlaceDigest>> {
    let language = language
        .map(|l| l.trim().to_ascii_lowercase())
        .filter(|l| !l.is_empty())
        .unwrap_or_else(|| "en".to_owned());
    if language.len() != 2 || !language.bytes().all(|b| b.is_ascii_lowercase()) {
        return Err(invalid_input("language: two letters, as `fr`"));
    }
    let rows = match (ids, bbox) {
        (Some(ids), None) => {
            if ids.len() > MAX_DIGEST_IDS {
                return Err(invalid_input(format!(
                    "ids: {MAX_DIGEST_IDS} at most, got {}",
                    ids.len()
                )));
            }
            if ids.is_empty() {
                return Ok(Vec::new());
            }
            let (pool, _permit) = db(ctx).await?;
            digests::of_places(pool, &ids, &language).await
        }
        (None, Some(b)) => {
            let area = on_coarse_grid(b)?;
            if area.area_deg2() > MAX_DIGEST_AREA_DEG2 {
                return Err(invalid_input(format!(
                    "bbox covers {:.2} square degrees once on the grid, more than the \
                     {MAX_DIGEST_AREA_DEG2} allowed",
                    area.area_deg2()
                )));
            }
            let (pool, _permit) = db(ctx).await?;
            digests::in_bbox(pool, area, &language, MAX_DIGEST_BBOX_PLACES).await
        }
        _ => return Err(invalid_input("give either ids or bbox")),
    }
    .map_err(|e| internal(&e))?;
    Ok(rows.into_iter().map(PlaceDigest::from_row).collect())
}

/// `input` widened outward to the [`COARSE_GRID_DEG`] grid, as the app
/// widens it before it leaves the device: the server never uses a finer
/// area, whatever the client sent. The error names no coordinate.
fn on_coarse_grid(input: BBoxInput) -> Result<BBox> {
    let steps = 1.0 / COARSE_GRID_DEG;
    // An edge a rounding error away from a line of the grid (4.7 times 20
    // is 94.000000000000014) is on it.
    let down = |v: f64| (v * steps + 1e-6).floor() / steps;
    let up = |v: f64| (v * steps - 1e-6).ceil() / steps;
    BBox::new(
        down(input.south).max(-90.0),
        down(input.west).max(-180.0),
        up(input.north).min(90.0),
        up(input.east).min(180.0),
    )
    .map_err(|_| invalid_input("bbox: not a valid area"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_area_is_widened_to_the_coarse_grid_and_never_narrowed() {
        let b = on_coarse_grid(BBoxInput {
            south: 44.4812,
            west: 4.6612,
            north: 44.4999,
            east: 4.70,
        })
        .unwrap();
        let near = |a: f64, b: f64| (a - b).abs() < 1e-9;
        assert!(near(b.south(), 44.45), "south {}", b.south());
        assert!(near(b.west(), 4.65), "west {}", b.west());
        assert!(near(b.north(), 44.5), "north {}", b.north());
        assert!(
            near(b.east(), 4.70),
            "an edge on the grid stays: {}",
            b.east()
        );
    }

    #[test]
    fn the_cost_follows_the_ids_or_the_largest_area() {
        let base = crate::schema::DB_FIELD_COST;
        assert_eq!(digests_cost(Some(&vec![Uuid::nil(); 3]), 10), base + 30);
        assert_eq!(digests_cost(None, 10), base + 20_000);
    }
}
