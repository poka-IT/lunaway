//! The ratings and reviews of the points of interest and the
//! establishments by Lunaway users: the review type, its page, and what the
//! fields of `Poi` read. They follow the reviews of places
//! (`community_types::Review`), without the vehicle.

use async_graphql::{Context, Object, Result, SimpleObject, dataloader::DataLoader};
use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::{community::Page, poi_reviews::PoiReviewRow};
use lunaway_domain::SourceId;
use uuid::Uuid;

use crate::{
    auth,
    community_types::{
        GqlContributionStatus, ITEM_CURSOR, SourceRating, parse_item_cursor, status_of,
    },
    error::{internal, invalid_input},
    loaders::PoiRatingsLoader,
    schema::db,
    types::MAX_REVIEWS_PAGE,
};

/// Reviews per page of `Poi.reviews` when the client does not say.
pub(crate) const DEFAULT_POI_REVIEWS_PAGE: i32 = 20;

/// A rating of a point of interest, with or without text.
pub struct PoiReview(pub PoiReviewRow);

#[Object]
impl PoiReview {
    /// Stable identifier (what `deleteReview` and `reportContent` with
    /// `POI_REVIEW` take).
    async fn id(&self) -> Uuid {
        self.0.id
    }

    /// The source it is published under: `community-cc-by` for reviews
    /// written on Lunaway (CC BY 4.0, `Query.sources` gives its licence and
    /// attribution).
    async fn source_id(&self) -> &str {
        &self.0.source_id
    }

    /// The point it was written for.
    async fn poi_id(&self) -> Uuid {
        self.0.poi_id
    }

    /// Stars, 1 to 5.
    async fn rating(&self) -> i32 {
        i32::from(self.0.stars)
    }

    /// The text; null for a rating alone.
    async fn text(&self) -> Option<&str> {
        self.0.body.as_deref()
    }

    /// The language of the text (BCP 47), as the author's app said.
    async fn lang(&self) -> Option<&str> {
        self.0.lang.as_deref()
    }

    /// The author's pseudonym; null once the account is deleted (the app
    /// shows "Deleted account").
    async fn author_name(&self) -> Option<&str> {
        self.0.author.as_deref()
    }

    /// The author's account, to mute it; null once the account is deleted.
    async fn author_id(&self) -> Option<Uuid> {
        self.0.account_id
    }

    /// The day of the visit.
    async fn visited_at(&self) -> Option<NaiveDate> {
        self.0.visited_on
    }

    /// When it was first written.
    async fn created_at(&self) -> DateTime<Utc> {
        self.0.created_at
    }

    /// When it last changed.
    async fn updated_at(&self) -> DateTime<Utc> {
        self.0.updated_at
    }

    /// Where it stands: always `PUBLISHED` in a point's list; the author
    /// sees the others in `myAccount` and `Poi.myReview`.
    async fn status(&self) -> GqlContributionStatus {
        status_of(&self.0.status)
    }
}

/// A page of reviews of points, newest first.
#[derive(SimpleObject)]
pub struct PoiReviewConnection {
    /// The reviews.
    pub nodes: Vec<PoiReview>,
    /// Pass it as `after` for the next page; null on an empty page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Reviews in the whole list.
    pub total_count: i32,
}

impl From<Page<PoiReviewRow>> for PoiReviewConnection {
    fn from(p: Page<PoiReviewRow>) -> Self {
        Self {
            end_cursor: p.nodes.last().map(|r| format!("{ITEM_CURSOR}{}", r.id)),
            nodes: p.nodes.into_iter().map(PoiReview).collect(),
            has_next_page: p.has_next_page,
            total_count: i32::try_from(p.total_count).unwrap_or(i32::MAX),
        }
    }
}

/// Lunaway users' rating of point `poi`, through the request's loader: a
/// list of points costs one query.
pub(crate) async fn ratings(ctx: &Context<'_>, poi: Uuid) -> Result<Vec<SourceRating>> {
    let rating = match ctx.data_opt::<DataLoader<PoiRatingsLoader>>() {
        Some(loader) => loader
            .load_one(poi)
            .await
            .map_err(|e| internal(e.as_ref()))?,
        None => {
            let (pool, _permit) = db(ctx).await?;
            lunaway_db::poi_reviews::ratings_of(pool, &[poi])
                .await
                .map_err(|e| internal(&e))?
                .pop()
        }
    };
    Ok(rating
        .into_iter()
        .map(|r| SourceRating {
            source_id: SourceId::COMMUNITY_CC_BY.to_string(),
            average: r.average,
            count: i32::try_from(r.count).unwrap_or(i32::MAX),
        })
        .collect())
}

/// One page of the published reviews with text of point `poi`, without the
/// authors the caller muted.
pub(crate) async fn reviews(
    ctx: &Context<'_>,
    poi: Uuid,
    first: Option<i32>,
    after: Option<String>,
) -> Result<PoiReviewConnection> {
    let first = first.unwrap_or(DEFAULT_POI_REVIEWS_PAGE);
    if !(1..=MAX_REVIEWS_PAGE).contains(&first) {
        return Err(invalid_input(format!(
            "first must be between 1 and {MAX_REVIEWS_PAGE}"
        )));
    }
    let after = parse_item_cursor(after.as_deref())?;
    let viewer = auth::viewer(ctx).await?;
    let (pool, _permit) = db(ctx).await?;
    Ok(lunaway_db::poi_reviews::reviews_of_poi(
        pool,
        poi,
        viewer.as_ref().map(auth::Viewer::id),
        i64::from(first),
        after,
    )
    .await
    .map_err(|e| internal(&e))?
    .into())
}

/// The caller's own rating or review of point `poi`, whatever its status;
/// `None` when anonymous or when there is none.
pub(crate) async fn my_review(ctx: &Context<'_>, poi: Uuid) -> Result<Option<PoiReview>> {
    let Some(viewer) = auth::viewer(ctx).await? else {
        return Ok(None);
    };
    let (pool, _permit) = db(ctx).await?;
    Ok(
        lunaway_db::poi_reviews::review_by_account(pool, viewer.id(), poi)
            .await
            .map_err(|e| internal(&e))?
            .map(PoiReview),
    )
}
