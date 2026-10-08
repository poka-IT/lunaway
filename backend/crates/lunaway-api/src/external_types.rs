//! What sources other than Lunaway's community say of a place: the
//! partner's community (the external community source, `extcom`,
//! `docs/feeds.md`) and the open sources (Wikimedia Commons, Panoramax,
//! Wikipedia, DATAtourisme, Mangrove, `docs/data-sources.md`, "Open
//! content"). One set of fields for all of them, each item with its
//! source's id and label, its licence, its author and, for the open
//! sources, a link to where it is published. They are read per place when
//! its card opens, never carried by the change feed, the packs or the map
//! tiles.

use async_graphql::{Enum, Object, SimpleObject};
use base64::Engine as _;
use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::{
    community::Page,
    content::{ContentDescriptionRow, ContentPhotoRow, ContentReviewRow},
    extcom::{ExternalPhotoRow, ExternalReviewRow},
};
use uuid::Uuid;

use crate::community_types::{GqlVehicleKind, ITEM_CURSOR};

/// A review of another source than Lunaway's community.
pub enum ReviewItem {
    /// The partner's community, under its agreement.
    Partner(ExternalReviewRow),
    /// An open source (Mangrove).
    Open(ContentReviewRow),
}

impl ReviewItem {
    /// Its id: a UUID v7 stamped with its date, whatever its source.
    #[must_use]
    pub fn id(&self) -> Uuid {
        match self {
            Self::Partner(r) => r.id,
            Self::Open(r) => r.id,
        }
    }
}

/// A review written elsewhere, shown with its author's pseudonym and its
/// source's label, and the language of its text: the source's, else the
/// one guessed from its words when the page was built
/// ([`ExternalReviewConnection::merge`]).
pub struct ExternalReview(pub ReviewItem, pub Option<String>);

impl ExternalReview {
    /// `item`, with the language its source gave or, when it gave none
    /// (or `und`), the one its words say. The guess reads up to
    /// [`lunaway_domain::translation::DETECTED_CHARS`] characters: call
    /// this off the request's thread.
    #[must_use]
    pub fn with_language(item: ReviewItem) -> Self {
        let (stored, text) = match &item {
            ReviewItem::Partner(r) => (r.lang.as_deref(), r.body.as_str()),
            ReviewItem::Open(r) => (r.lang.as_deref(), r.text.as_str()),
        };
        let lang = lunaway_domain::translation::source_language(stored, text);
        Self(item, lang)
    }
}

#[Object]
impl ExternalReview {
    /// Stable identifier, also what `reportContent(target:
    /// EXTERNAL_REVIEW)` takes.
    async fn id(&self) -> Uuid {
        self.0.id()
    }

    /// The source (`extcom`, `mangrove`); `Query.sources` gives its
    /// licence and attribution.
    async fn source_id(&self) -> &str {
        match &self.0 {
            ReviewItem::Partner(r) => &r.source_id,
            ReviewItem::Open(r) => &r.source_id,
        }
    }

    /// The source's name to show beside the review ("Source communautaire
    /// externe", "Mangrove Reviews"); the app may translate it by
    /// `sourceId`.
    async fn source_label(&self) -> &str {
        match &self.0 {
            ReviewItem::Partner(r) => &r.source_label,
            ReviewItem::Open(r) => &r.source_label,
        }
    }

    /// The author's pseudonym at the source; null when it gave none.
    async fn author_name(&self) -> Option<&str> {
        match &self.0 {
            ReviewItem::Partner(r) => r.author.as_deref(),
            ReviewItem::Open(r) => r.author.as_deref(),
        }
    }

    /// Stars, 1 to 5; null for a text without a rating.
    async fn rating(&self) -> Option<i32> {
        match &self.0 {
            ReviewItem::Partner(r) => r.rating.map(i32::from),
            ReviewItem::Open(r) => r.rating.map(i32::from),
        }
    }

    /// The text, plain.
    async fn text(&self) -> &str {
        match &self.0 {
            ReviewItem::Partner(r) => &r.body,
            ReviewItem::Open(r) => &r.text,
        }
    }

    /// The language of the text (BCP 47): as the source says, else guessed
    /// from its words (`de`), so the app knows when to offer a
    /// translation; null when the text is too short to tell.
    async fn lang(&self) -> Option<&str> {
        self.1.as_deref()
    }

    /// The author's vehicle, when the source says.
    async fn author_vehicle(&self) -> Option<GqlVehicleKind> {
        match &self.0 {
            ReviewItem::Partner(r) => r
                .vehicle
                .as_deref()
                .and_then(|v| v.parse::<lunaway_domain::community::VehicleKind>().ok())
                .map(Into::into),
            ReviewItem::Open(_) => None,
        }
    }

    /// When it was written.
    async fn written_at(&self) -> DateTime<Utc> {
        match &self.0 {
            ReviewItem::Partner(r) => r.written_at,
            ReviewItem::Open(r) => r.written_at,
        }
    }

    /// Its licence (`CC BY 4.0`), or the reference of the agreement it
    /// came under.
    async fn licence(&self) -> &str {
        match &self.0 {
            ReviewItem::Partner(r) => &r.licence,
            ReviewItem::Open(r) => &r.licence,
        }
    }

    /// The text of its licence; null for a partner's review, which comes
    /// under a written agreement.
    async fn licence_url(&self) -> Option<&str> {
        match &self.0 {
            ReviewItem::Partner(_) => None,
            ReviewItem::Open(r) => Some(&r.licence_url),
        }
    }

    /// Where it is published, to link to; null for a partner's review,
    /// which the app never links out to.
    async fn page_url(&self) -> Option<&str> {
        match &self.0 {
            ReviewItem::Partner(_) => None,
            ReviewItem::Open(r) => Some(&r.page_url),
        }
    }
}

/// A page of reviews of other sources, newest first.
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

impl ExternalReviewConnection {
    /// One page from a page of each kind of source, read with the same
    /// `first` and `after`: both are newest first in id order, so the
    /// newest `first` of the two are the page, and another page follows
    /// when either had more. Each review gets its language
    /// ([`ExternalReview::with_language`]): call this off the request's
    /// thread.
    #[must_use]
    pub fn merge(
        partner: Page<ExternalReviewRow>,
        open: Page<ContentReviewRow>,
        first: usize,
    ) -> Self {
        let has_more = partner.has_next_page || open.has_next_page;
        let mut nodes: Vec<ReviewItem> = partner
            .nodes
            .into_iter()
            .map(ReviewItem::Partner)
            .chain(open.nodes.into_iter().map(ReviewItem::Open))
            .collect();
        nodes.sort_by_key(|r| std::cmp::Reverse(r.id()));
        let over = nodes.len() > first;
        nodes.truncate(first);
        Self {
            end_cursor: nodes.last().map(|r| format!("{ITEM_CURSOR}{}", r.id())),
            nodes: nodes
                .into_iter()
                .map(ExternalReview::with_language)
                .collect(),
            has_next_page: has_more || over,
            total_count: i32::try_from(partner.total_count + open.total_count).unwrap_or(i32::MAX),
        }
    }
}

/// What a photo of another source shows of a place.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "PhotoKind")]
pub enum GqlPhotoKind {
    /// The place itself: a visitor's photo, or one the place's data names.
    Place,
    /// A street-level picture looking at the place ("Vue de la rue").
    StreetView,
    /// A picture taken nearby, in no particular direction ("Aux
    /// alentours").
    Surroundings,
}

impl GqlPhotoKind {
    fn from_relation(code: &str) -> Self {
        match lunaway_domain::content::PhotoRelation::from_code(code) {
            Some(lunaway_domain::content::PhotoRelation::Linked) => Self::Place,
            Some(lunaway_domain::content::PhotoRelation::Facing) => Self::StreetView,
            // The column's CHECK allows nothing else; an unknown code
            // claims the least.
            _ => Self::Surroundings,
        }
    }
}

/// A photo from another source than Lunaway's community, stored and
/// served by Lunaway: a device never reaches the source. A partner's photo
/// is downloaded the first time a device asks for it (its URLs lead to the
/// API's photo proxy until then); an open source's is downloaded by the
/// weekly content worker.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalPhoto {
    /// Stable identifier, also what `reportContent(target:
    /// EXTERNAL_PHOTO)` takes.
    pub id: Uuid,
    /// The source (`extcom`, `wikimedia-commons`, `panoramax`,
    /// `datatourisme`).
    pub source_id: String,
    /// The source's name to show with the photo.
    pub source_label: String,
    /// What it shows of the place.
    pub kind: GqlPhotoKind,
    /// The author's pseudonym or credit at the source.
    pub author_name: Option<String>,
    /// Who published it when that is not the author: the tourist office on
    /// DATAtourisme, the Panoramax instance.
    pub publisher: Option<String>,
    /// Its licence (`CC BY-SA 4.0`), or the reference of the agreement it
    /// came under.
    pub licence: String,
    /// The text of its licence; null under a written agreement.
    pub licence_url: Option<String>,
    /// Its page at the source, to link to; null for a partner's photo,
    /// which the app never links out to.
    pub page_url: Option<String>,
    /// Its title at the source.
    pub title: Option<String>,
    /// The source's own date of its last update, which the Licence Ouverte
    /// asks to show (DATAtourisme).
    pub source_updated_on: Option<NaiveDate>,
    /// From the place to where it was taken, metres; null when unknown.
    pub distance_m: Option<f64>,
    /// When it was taken, when the source says.
    pub taken_at: Option<DateTime<Utc>>,
    /// The 512-pixel thumbnail.
    pub thumb_url: String,
    /// The large image (2048 pixels for a partner's, 1280 for an open
    /// source's).
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
            kind: GqlPhotoKind::Place,
            author_name: r.author,
            publisher: None,
            licence: r.licence,
            licence_url: None,
            page_url: None,
            title: None,
            source_updated_on: None,
            distance_m: None,
            taken_at: r.taken_at,
            width: r.width,
            height: r.height,
            thumbhash: r
                .thumbhash
                .map(|h| base64::engine::general_purpose::STANDARD.encode(h)),
        }
    }

    pub(crate) fn from_content(r: ContentPhotoRow, media: &crate::config::MediaConfig) -> Self {
        Self {
            id: r.id,
            source_id: r.source_id,
            source_label: r.source_label,
            kind: GqlPhotoKind::from_relation(&r.relation),
            author_name: r.author,
            publisher: r.publisher,
            licence: r.licence,
            licence_url: Some(r.licence_url),
            page_url: Some(r.page_url),
            title: r.title,
            source_updated_on: r.source_updated_on,
            distance_m: r.distance_m.map(f64::from),
            taken_at: r.taken_at,
            thumb_url: media.url(&r.thumb_path),
            large_url: media.url(&r.path),
            width: Some(r.width),
            height: Some(r.height),
            thumbhash: Some(base64::engine::general_purpose::STANDARD.encode(&r.thumbhash)),
        }
    }
}

/// A description of a place by an open source (Wikipedia, DATAtourisme),
/// in one language: show its source, licence and link with it.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalDescription {
    /// Its source (`wikipedia`, `datatourisme`).
    pub source_id: String,
    /// The source's name to show with the text.
    pub source_label: String,
    /// Its language, BCP 47.
    pub lang: String,
    /// The text, plain; it ends with an ellipsis when Lunaway shortened it.
    pub text: String,
    /// The title of the page it comes from (the article's).
    pub title: Option<String>,
    /// Who wrote it, when the source credits a person.
    pub author: Option<String>,
    /// Who published it: `Wikipedia`, or the tourist office on
    /// DATAtourisme.
    pub publisher: Option<String>,
    /// The source's own date of its last update; null when unknown.
    pub source_updated_on: Option<NaiveDate>,
    /// Its licence's short name.
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// Its page at the source.
    pub page_url: String,
    /// When Lunaway last read it.
    pub fetched_at: DateTime<Utc>,
}

impl From<ContentDescriptionRow> for ExternalDescription {
    fn from(r: ContentDescriptionRow) -> Self {
        Self {
            source_id: r.source_id,
            source_label: r.source_label,
            lang: r.lang,
            text: r.text,
            title: r.title,
            author: r.author,
            publisher: r.publisher,
            source_updated_on: r.source_updated_on,
            licence: r.licence,
            licence_url: r.licence_url,
            page_url: r.page_url,
            fetched_at: r.fetched_at,
        }
    }
}
