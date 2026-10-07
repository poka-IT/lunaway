//! The open content of a place as the card shows it: photos, descriptions
//! and reviews read from open sources by the content worker, each with
//! its author, its licence and its link. Read per place on demand: the
//! change feed and the offline packs never carry them.

use async_graphql::{Enum, SimpleObject};
use base64::Engine;
use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::content::{ContentDescriptionRow, ContentPhotoRow, ContentReviewRow};
use uuid::Uuid;

use crate::config::MediaConfig;

/// Why a photo of an open source is shown on a place.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "PhotoRelation")]
pub enum GqlPhotoRelation {
    /// The place's own data names it (OpenStreetMap, Wikidata, the tourist
    /// office's record): it shows the place.
    Linked,
    /// A street-level picture taken near the place, its camera pointing at
    /// it.
    Facing,
    /// A picture taken near the place, in no particular direction: the
    /// app labels it as the surroundings.
    Nearby,
}

impl GqlPhotoRelation {
    fn from_code(code: &str) -> Self {
        match lunaway_domain::content::PhotoRelation::from_code(code) {
            Some(lunaway_domain::content::PhotoRelation::Linked) => Self::Linked,
            Some(lunaway_domain::content::PhotoRelation::Facing) => Self::Facing,
            // The CHECK of the column allows nothing else; an unknown code
            // claims the least.
            _ => Self::Nearby,
        }
    }
}

/// A photo of a place from an open source (Wikimedia Commons, Panoramax,
/// DATAtourisme), stored and served by Lunaway: show its author and
/// licence with it, and link to its page.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalPhoto {
    /// Stable while the source offers it.
    pub id: Uuid,
    /// Its source (`wikimedia-commons`, `panoramax`, `datatourisme`):
    /// `Query.sources` gives its name.
    pub source_id: String,
    /// Why it is shown on this place.
    pub relation: GqlPhotoRelation,
    /// From the place to where it was taken, metres; null when unknown.
    pub distance_m: Option<f64>,
    /// The 512-pixel thumbnail, on Lunaway's media host.
    pub thumb_url: String,
    /// The image, 1280 pixels on its long side at most, on Lunaway's
    /// media host.
    pub large_url: String,
    /// Width of the large image, pixels.
    pub width: i32,
    /// Height of the large image, pixels.
    pub height: i32,
    /// ThumbHash of the image, base64: a placeholder while it loads.
    pub thumbhash: String,
    /// Its title at the source.
    pub title: Option<String>,
    /// Its author as the source credits them (a name, a pseudonym, a
    /// photographer's credit); null when the source names none (public
    /// domain).
    pub author: Option<String>,
    /// Who published it when that is not the author: the tourist office
    /// on DATAtourisme, the Panoramax instance.
    pub publisher: Option<String>,
    /// The source's own date of its last update, which the Licence
    /// Ouverte asks to show; null when the source gives none.
    pub source_updated_on: Option<NaiveDate>,
    /// Its licence's short name (`CC BY-SA 4.0`, `Licence Ouverte 2.0`).
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// Its page at the source: open it from the photo.
    pub page_url: String,
    /// When it was taken; null when unknown.
    pub taken_at: Option<DateTime<Utc>>,
    /// When Lunaway last read it.
    pub fetched_at: DateTime<Utc>,
}

impl ExternalPhoto {
    pub(crate) fn from_row(r: ContentPhotoRow, media: &MediaConfig) -> Self {
        Self {
            id: r.id,
            source_id: r.source_id,
            relation: GqlPhotoRelation::from_code(&r.relation),
            distance_m: r.distance_m.map(f64::from),
            thumb_url: media.url(&r.thumb_path),
            large_url: media.url(&r.path),
            width: r.width,
            height: r.height,
            thumbhash: base64::engine::general_purpose::STANDARD.encode(&r.thumbhash),
            title: r.title,
            author: r.author,
            publisher: r.publisher,
            source_updated_on: r.source_updated_on,
            licence: r.licence,
            licence_url: r.licence_url,
            page_url: r.page_url,
            taken_at: r.taken_at,
            fetched_at: r.fetched_at,
        }
    }
}

/// A description of a place from an open source (Wikipedia, DATAtourisme),
/// in one language: show its source, licence and link with it.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalDescription {
    /// Its source (`wikipedia`, `datatourisme`).
    pub source_id: String,
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

/// A review published elsewhere under an open licence (Mangrove Reviews):
/// show its author's pseudonym, its source and its licence with it.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalReview {
    /// Stable while the source offers it.
    pub id: Uuid,
    /// Its source (`mangrove`).
    pub source_id: String,
    /// Stars, 1 to 5; null for a text alone.
    pub rating: Option<i32>,
    /// The text; null for a rating alone.
    pub text: Option<String>,
    /// The language of the text (BCP 47), when the source says.
    pub lang: Option<String>,
    /// The pseudonym the reviewer chose at the source; null when none.
    pub author_name: Option<String>,
    /// When it was written.
    pub written_at: DateTime<Utc>,
    /// Its licence's short name (`CC BY 4.0`).
    pub licence: String,
    /// Its licence's text.
    pub licence_url: String,
    /// Its page at the source.
    pub page_url: String,
}

impl From<ContentReviewRow> for ExternalReview {
    fn from(r: ContentReviewRow) -> Self {
        Self {
            id: r.id,
            source_id: r.source_id,
            rating: r.rating.map(i32::from),
            text: r.text,
            lang: r.lang,
            author_name: r.author,
            written_at: r.written_at,
            licence: r.licence,
            licence_url: r.licence_url,
            page_url: r.page_url,
        }
    }
}
