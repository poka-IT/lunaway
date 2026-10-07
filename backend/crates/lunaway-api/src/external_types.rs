//! What a partner's community says of a place (the external community
//! source, `extcom`, `docs/feeds.md`): its reviews, rating summaries and
//! photos. They are read per place when its card opens, never carried by
//! the change feed, the packs or the map tiles: they belong to their
//! authors and come under an agreement that may end, so no device keeps a
//! copy beyond its image cache.

use async_graphql::{Object, SimpleObject};
use chrono::{DateTime, Utc};
use lunaway_db::{
    community::Page,
    extcom::{ExternalPhotoRow, ExternalReviewRow},
};
use uuid::Uuid;

use crate::community_types::{GqlVehicleKind, ITEM_CURSOR};

/// A review written on a partner's platform, shown with its author's
/// pseudonym and the source's label.
pub struct ExternalReview(pub ExternalReviewRow);

#[Object]
impl ExternalReview {
    /// Stable identifier.
    async fn id(&self) -> Uuid {
        self.0.id
    }

    /// The source (`extcom`); `Query.sources` gives its licence and the
    /// attribution its agreement words.
    async fn source_id(&self) -> &str {
        &self.0.source_id
    }

    /// The source's name to show beside the review ("Source communautaire
    /// externe"); the app may translate it by `sourceId`.
    async fn source_label(&self) -> &str {
        &self.0.source_label
    }

    /// The author's pseudonym on the partner's platform; null when the
    /// partner gave none.
    async fn author_name(&self) -> Option<&str> {
        self.0.author.as_deref()
    }

    /// Stars, 1 to 5; null for a text without a rating.
    async fn rating(&self) -> Option<i32> {
        self.0.rating.map(i32::from)
    }

    /// The text, plain.
    async fn text(&self) -> &str {
        &self.0.body
    }

    /// The language of the text (BCP 47), when the partner says.
    async fn lang(&self) -> Option<&str> {
        self.0.lang.as_deref()
    }

    /// The author's vehicle, when the partner says.
    async fn author_vehicle(&self) -> Option<GqlVehicleKind> {
        self.0
            .vehicle
            .as_deref()
            .and_then(|v| v.parse::<lunaway_domain::community::VehicleKind>().ok())
            .map(Into::into)
    }

    /// When it was written.
    async fn written_at(&self) -> DateTime<Utc> {
        self.0.written_at
    }

    /// The reference of the agreement it came under.
    async fn licence(&self) -> &str {
        &self.0.licence
    }
}

/// A page of a partner's reviews, newest first.
#[derive(SimpleObject)]
pub struct ExternalReviewConnection {
    /// The reviews.
    pub nodes: Vec<ExternalReview>,
    /// Pass it as `after` for the next page; null on an empty page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Reviews in the whole list.
    pub total_count: i32,
}

impl From<Page<ExternalReviewRow>> for ExternalReviewConnection {
    fn from(p: Page<ExternalReviewRow>) -> Self {
        Self {
            end_cursor: p.nodes.last().map(|r| format!("{ITEM_CURSOR}{}", r.id)),
            nodes: p.nodes.into_iter().map(ExternalReview).collect(),
            has_next_page: p.has_next_page,
            total_count: i32::try_from(p.total_count).unwrap_or(i32::MAX),
        }
    }
}

/// A photo from a partner's platform. Lunaway downloads it the first time
/// a device asks for it (the URLs below lead to the API's photo proxy
/// until then), re-encodes it without its metadata and serves it from its
/// own host: a device never reaches the partner.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalPhoto {
    /// Stable identifier.
    pub id: Uuid,
    /// The source (`extcom`).
    pub source_id: String,
    /// The source's name to show with the photo.
    pub source_label: String,
    /// The author's pseudonym on the partner's platform.
    pub author_name: Option<String>,
    /// The photo's licence, or the reference of the agreement it came
    /// under.
    pub licence: String,
    /// When it was taken, when the partner says.
    pub taken_at: Option<DateTime<Utc>>,
    /// The 512-pixel thumbnail.
    pub thumb_url: String,
    /// The 2048-pixel image.
    pub large_url: String,
    /// Width of the large image, pixels; null until first downloaded.
    pub width: Option<i32>,
    /// Height of the large image, pixels; null until first downloaded.
    pub height: Option<i32>,
    /// ThumbHash of the image, base64; null until first downloaded.
    pub thumbhash: Option<String>,
}

/// The proxy's path of photo `id` at `size` (`thumb` or `large`).
#[must_use]
pub fn proxy_path(id: Uuid, size: &str) -> String {
    format!("/external-photos/{id}/{size}")
}

impl ExternalPhoto {
    pub(crate) fn from_row(
        r: ExternalPhotoRow,
        media: &crate::config::MediaConfig,
        public_url: &str,
    ) -> Self {
        use base64::Engine as _;
        let url = |stored: Option<&str>, size: &str| match stored {
            Some(path) => media.url(path),
            None => format!("{public_url}{}", proxy_path(r.id, size)),
        };
        Self {
            id: r.id,
            thumb_url: url(r.thumb_path.as_deref(), "thumb"),
            large_url: url(r.path.as_deref(), "large"),
            source_id: r.source_id,
            source_label: r.source_label,
            author_name: r.author,
            licence: r.licence,
            taken_at: r.taken_at,
            width: r.width,
            height: r.height,
            thumbhash: r
                .thumbhash
                .map(|h| base64::engine::general_purpose::STANDARD.encode(h)),
        }
    }
}
