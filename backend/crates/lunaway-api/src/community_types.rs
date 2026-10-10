//! The GraphQL types of accounts and contributions. Enums mirror the
//! domain's with a `remote` conversion, like the taxonomy's; objects map the
//! rows of `lunaway-db` and nothing more.

use async_graphql::{Context, Enum, InputObject, Object, Result, SimpleObject};
use base64::Engine;
use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::{
    community::{ConfirmationRow, IssueRow, Page, PhotoRow, ReviewRow},
    lists::ListRow,
    submissions::SubmissionRow,
    summary::{CoverPhoto, IssueSummary as DbIssueSummary},
};
use lunaway_domain::{
    SourceId,
    community::trust::{NextLevel as DomainNextLevel, Requirement},
};
use uuid::Uuid;

use crate::{
    auth::{self, Viewer},
    error::internal,
    schema::{DB_FIELD_COST, db, state},
};

/// A visitor's answer to "is it still there?".
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::ConfirmationStatus",
    name = "ConfirmationStatus"
)]
pub enum GqlConfirmationStatus {
    /// As described.
    StillOk,
    /// No longer takes visitors.
    Closed,
    /// Exists, but something described changed.
    Changed,
}

/// A problem met at a place.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::community::IssueKind", name = "IssueKind")]
pub enum GqlIssueKind {
    /// Nights are forbidden now.
    NightBan,
    /// A service is out of order.
    ServiceBroken,
    /// The place cannot be reached.
    NoAccess,
    /// Something dangerous.
    Danger,
}

/// A field of a place an edit can clear (`PlaceDetailsInput.clear`): the
/// community stops stating it, and the value shown comes from the next
/// source that does (OpenStreetMap, Atout France), if any.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::submission::PlaceField",
    name = "PlaceField"
)]
pub enum GqlPlaceField {
    /// Every description of the community, in every language.
    Description,
    /// Whether a night may be spent there (back to unknown).
    Overnight,
    /// Services on site.
    Services,
    /// Activities around.
    Activities,
    /// Price of a night.
    PriceParking,
    /// Price of the services.
    PriceServices,
    /// Maximum vehicle height.
    MaxHeight,
    /// Pitches.
    Capacity,
    /// Opening hours.
    OpeningHours,
    /// Website.
    Website,
    /// Phone.
    Phone,
}

/// The vehicle a reviewer travelled in.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::VehicleKind",
    name = "VehicleKind"
)]
pub enum GqlVehicleKind {
    /// A small van.
    Van,
    /// A panel-van conversion.
    Campervan,
    /// A coachbuilt or integrated motorhome.
    Motorhome,
    /// A car towing a caravan.
    Caravan,
    /// Anything else.
    Other,
}

/// What a user may report.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::ReportTarget",
    name = "ReportTarget"
)]
pub enum GqlReportTarget {
    /// A review.
    Review,
    /// A photo.
    Photo,
    /// A place.
    Place,
    /// A review of an external source (`Place.externalReviews`).
    ExternalReview,
    /// A photo of an external source (`Place.externalPhotos`).
    ExternalPhoto,
    /// A review of a point of interest (`Poi.reviews`).
    PoiReview,
}

/// Why a user reports something.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::ReportReason",
    name = "ReportReason"
)]
pub enum GqlReportReason {
    /// Advertising or repeated content.
    Spam,
    /// Insulting, hateful or shocking.
    Offensive,
    /// False or misleading.
    Wrong,
    /// Shows or names a person, a plate, a private address.
    Privacy,
    /// Something else, said in the note.
    Other,
}

/// Whether a place can be trusted to exist as described.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::Verification",
    name = "Verification"
)]
pub enum GqlVerification {
    /// Described by an open source, or confirmed by the community.
    Verified,
    /// Added by a contributor, not yet confirmed by two others.
    ToVerify,
}

/// Where a contribution stands.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::community::ReviewStatus",
    name = "ContributionStatus"
)]
pub enum GqlContributionStatus {
    /// Visible to everyone.
    Published,
    /// Held by the automatic rules until a moderator decides.
    Pending,
    /// Hidden after reports, until a moderator decides.
    Hidden,
    /// Removed by a moderator.
    Removed,
}

pub(crate) fn status_of(code: &str) -> GqlContributionStatus {
    code.parse::<lunaway_domain::community::ReviewStatus>()
        .map_or(GqlContributionStatus::Removed, Into::into)
}

/// A public author: an account's id and pseudonym.
#[derive(SimpleObject, Debug, Clone)]
pub struct Author {
    /// The account (what `muteAuthor` takes).
    pub id: Uuid,
    /// Its public name.
    pub pseudonym: String,
}

/// A rating, with or without text.
pub struct Review(pub ReviewRow);

#[Object]
impl Review {
    /// Stable identifier.
    async fn id(&self) -> Uuid {
        self.0.id
    }

    /// The source it is published under: `community-cc-by` for reviews
    /// written on Lunaway (CC BY 4.0, `Query.sources` gives its licence and
    /// attribution).
    async fn source_id(&self) -> &str {
        &self.0.source_id
    }

    /// The place it was written for (it may since have been merged into
    /// another).
    async fn place_id(&self) -> Uuid {
        self.0.place_id
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

    /// The author's vehicle.
    async fn author_vehicle(&self) -> Option<GqlVehicleKind> {
        self.0
            .vehicle
            .as_deref()
            .and_then(|v| v.parse::<lunaway_domain::community::VehicleKind>().ok())
            .map(Into::into)
    }

    /// The day of the stay.
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

    /// Where it stands: always `PUBLISHED` in a place's list; the author
    /// sees the others in `myAccount`.
    async fn status(&self) -> GqlContributionStatus {
        status_of(&self.0.status)
    }
}

/// A page of reviews, newest first.
#[derive(SimpleObject)]
pub struct ReviewConnection {
    /// The reviews.
    pub nodes: Vec<Review>,
    /// Pass it as `after` for the next page; null on an empty page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Reviews in the whole list.
    pub total_count: i32,
}

/// Cursor prefix of the lists read newest first.
pub(crate) const ITEM_CURSOR: &str = "i1.";

/// Reads an `after` cursor of a list read newest first.
pub(crate) fn parse_item_cursor(after: Option<&str>) -> Result<Option<Uuid>> {
    after
        .map(|s| {
            s.strip_prefix(ITEM_CURSOR)
                .and_then(|u| Uuid::parse_str(u).ok())
                .ok_or_else(|| {
                    crate::error::invalid_input("after is not a cursor this API returned")
                })
        })
        .transpose()
}

fn count(n: i64) -> i32 {
    i32::try_from(n).unwrap_or(i32::MAX)
}

impl From<Page<ReviewRow>> for ReviewConnection {
    fn from(p: Page<ReviewRow>) -> Self {
        Self {
            end_cursor: p.nodes.last().map(|r| format!("{ITEM_CURSOR}{}", r.id)),
            nodes: p.nodes.into_iter().map(Review).collect(),
            has_next_page: p.has_next_page,
            total_count: count(p.total_count),
        }
    }
}

/// A photo of a place.
#[derive(SimpleObject, Debug, Clone)]
pub struct Photo {
    /// Stable identifier.
    pub id: Uuid,
    /// The source it is published under: `community-cc-by` for photos sent
    /// on Lunaway (CC BY 4.0, `Query.sources` gives its licence and
    /// attribution).
    pub source_id: String,
    /// The 512-pixel thumbnail.
    pub thumb_url: String,
    /// The 2048-pixel image.
    pub large_url: String,
    /// Width of the large image, pixels.
    pub width: i32,
    /// Height of the large image, pixels.
    pub height: i32,
    /// ThumbHash of the image, base64: a placeholder while it loads.
    pub thumbhash: String,
    /// The author's account, to hide a muted author's photos offline; null
    /// once the account is deleted.
    pub author_id: Option<Uuid>,
    /// The author's pseudonym; null once the account is deleted.
    pub author_name: Option<String>,
    /// When it was sent; null in a place's summary.
    pub created_at: Option<DateTime<Utc>>,
    /// Where it stands.
    pub status: GqlContributionStatus,
}

impl Photo {
    pub(crate) fn from_row(r: PhotoRow, media: &crate::config::MediaConfig) -> Self {
        Self {
            id: r.id,
            source_id: r.source_id,
            thumb_url: media.url(&r.thumb_path),
            large_url: media.url(&r.path),
            width: r.width,
            height: r.height,
            thumbhash: base64::engine::general_purpose::STANDARD.encode(&r.thumbhash),
            author_id: r.account_id,
            author_name: r.author,
            created_at: Some(r.created_at),
            status: status_of(&r.status),
        }
    }

    pub(crate) fn from_cover(c: &CoverPhoto, media: &crate::config::MediaConfig) -> Self {
        Self {
            id: c.id,
            // Every photo is a Lunaway user's: the place's summary keeps no
            // source, the photos' rows do.
            source_id: SourceId::COMMUNITY_CC_BY.to_string(),
            thumb_url: media.url(&c.thumb_path),
            large_url: media.url(&c.path),
            width: c.width,
            height: c.height,
            thumbhash: c.thumbhash.clone(),
            author_id: c.author_id,
            author_name: None,
            created_at: None,
            status: GqlContributionStatus::Published,
        }
    }
}

/// A page of photos, newest first.
#[derive(SimpleObject)]
pub struct PhotoConnection {
    /// The photos.
    pub nodes: Vec<Photo>,
    /// Pass it as `after` for the next page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Photos in the whole list.
    pub total_count: i32,
}

/// The ratings of a place by one source.
#[derive(SimpleObject, Debug, Clone)]
pub struct SourceRating {
    /// The source: `community-cc-by` for Lunaway users' ratings, published
    /// with their reviews under CC BY 4.0.
    pub source_id: String,
    /// Mean stars, 1 to 5.
    pub average: f64,
    /// Ratings counted.
    pub count: i32,
}

/// Recent reports of one kind of issue at a place.
#[derive(SimpleObject, Debug, Clone)]
pub struct IssueSummary {
    /// What was reported.
    pub kind: GqlIssueKind,
    /// Reports over the last 30 days.
    pub count: i32,
    /// The latest.
    pub last_reported_at: DateTime<Utc>,
}

impl From<&DbIssueSummary> for IssueSummary {
    fn from(i: &DbIssueSummary) -> Self {
        Self {
            kind: i.kind.into(),
            count: count(i.count),
            last_reported_at: i.last_reported_at,
        }
    }
}

/// A confirmation the account gave.
#[derive(SimpleObject, Debug, Clone)]
pub struct Confirmation {
    /// Stable identifier.
    pub id: Uuid,
    /// The place.
    pub place_id: Uuid,
    /// The answer.
    pub status: GqlConfirmationStatus,
    /// When.
    pub created_at: DateTime<Utc>,
}

impl TryFrom<ConfirmationRow> for Confirmation {
    type Error = async_graphql::Error;

    fn try_from(r: ConfirmationRow) -> Result<Self> {
        let decode = |e: lunaway_domain::UnknownCode| internal(&e);
        Ok(Self {
            id: r.id,
            place_id: r.place_id,
            status: r
                .status
                .parse::<lunaway_domain::community::ConfirmationStatus>()
                .map_err(decode)?
                .into(),
            created_at: r.created_at,
        })
    }
}

/// An issue the account reported.
#[derive(SimpleObject, Debug, Clone)]
pub struct IssueReport {
    /// Stable identifier.
    pub id: Uuid,
    /// The place.
    pub place_id: Uuid,
    /// What was reported.
    pub kind: GqlIssueKind,
    /// When.
    pub created_at: DateTime<Utc>,
}

impl TryFrom<IssueRow> for IssueReport {
    type Error = async_graphql::Error;

    fn try_from(r: IssueRow) -> Result<Self> {
        Ok(Self {
            id: r.id,
            place_id: r.place_id,
            kind: r
                .kind
                .parse::<lunaway_domain::community::IssueKind>()
                .map_err(|e| internal(&e))?
                .into(),
            created_at: r.created_at,
        })
    }
}

/// Whether a submission adds a place or changes one.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum SubmissionKind {
    /// A new place.
    Create,
    /// A change to a place.
    Edit,
    /// A new point of interest (a vending machine).
    Poi,
}

/// Where a submission stands.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum SubmissionStatus {
    /// Waits for a moderator (the author's level is below 3, or the
    /// automatic rules held it).
    Proposed,
    /// Accepted; the server applies it within seconds.
    Accepted,
    /// Part of the places database.
    Applied,
    /// Refused by a moderator, or its place is gone.
    Rejected,
    /// Deleted by its author before it was applied.
    Withdrawn,
}

/// A new place or a place edit, with where it stands.
#[derive(SimpleObject, Debug, Clone)]
pub struct PlaceSubmission {
    /// Stable identifier.
    pub id: Uuid,
    /// A new place or an edit.
    pub kind: SubmissionKind,
    /// The place edited, or the place a new one became (null until the
    /// server placed it).
    pub place_id: Option<Uuid>,
    /// The point of interest a new vending machine became (null until the
    /// server wrote it).
    pub poi_id: Option<Uuid>,
    /// Where it stands.
    pub status: SubmissionStatus,
    /// When it was sent.
    pub created_at: DateTime<Utc>,
    /// When it became part of the places database.
    pub applied_at: Option<DateTime<Utc>>,
}

impl From<SubmissionRow> for PlaceSubmission {
    fn from(r: SubmissionRow) -> Self {
        Self {
            id: r.id,
            kind: match r.kind.as_str() {
                "create" => SubmissionKind::Create,
                "poi" => SubmissionKind::Poi,
                _ => SubmissionKind::Edit,
            },
            place_id: r.place_id,
            poi_id: r.poi_id,
            status: match r.status.as_str() {
                "proposed" => SubmissionStatus::Proposed,
                "accepted" => SubmissionStatus::Accepted,
                "applied" => SubmissionStatus::Applied,
                "withdrawn" => SubmissionStatus::Withdrawn,
                _ => SubmissionStatus::Rejected,
            },
            created_at: r.created_at,
            applied_at: r.applied_at,
        }
    }
}

/// A place in a favourite list.
#[derive(SimpleObject, Debug, Clone)]
pub struct FavoriteItem {
    /// The place.
    pub place_id: Uuid,
    /// When it was added.
    pub added_at: DateTime<Utc>,
}

/// A favourite list, synced with the account.
#[derive(SimpleObject, Debug, Clone)]
pub struct FavoriteList {
    /// Stable identifier.
    pub id: Uuid,
    /// Its name, unique among the account's lists.
    pub name: String,
    /// When it was created.
    pub created_at: DateTime<Utc>,
    /// Last change of its name or places.
    pub updated_at: DateTime<Utc>,
    /// Its places, oldest first.
    pub places: Vec<FavoriteItem>,
}

impl From<ListRow> for FavoriteList {
    fn from(l: ListRow) -> Self {
        Self {
            id: l.id,
            name: l.name,
            created_at: l.created_at,
            updated_at: l.updated_at,
            places: l
                .items
                .into_iter()
                .map(|(place_id, added_at)| FavoriteItem { place_id, added_at })
                .collect(),
        }
    }
}

/// What a level needs.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum RequirementKind {
    /// The account must be older, in days.
    AccountAgeDays,
    /// More confirmations.
    Confirmations,
    /// More published contributions.
    Contributions,
    /// More days of activity.
    ActiveDays,
    /// No contribution removed by moderation (`current` is how many were).
    NoRemoval,
    /// A level-2 account sponsors this one.
    Sponsor,
    /// A level-4 account nominates this one.
    Nomination,
    /// The administration designates this account.
    Administration,
}

/// One requirement of the next level.
#[derive(SimpleObject, Debug, Clone)]
pub struct LevelRequirement {
    /// What is needed.
    pub kind: RequirementKind,
    /// Where the account stands, for a count.
    pub current: Option<i32>,
    /// The count needed.
    pub needed: Option<i32>,
}

impl From<Requirement> for LevelRequirement {
    fn from(r: Requirement) -> Self {
        let n = |v: u32| Some(i32::try_from(v).unwrap_or(i32::MAX));
        let (kind, current, needed) = match r {
            Requirement::AccountAgeDays { current, needed } => {
                (RequirementKind::AccountAgeDays, n(current), n(needed))
            }
            Requirement::Confirmations { current, needed } => {
                (RequirementKind::Confirmations, n(current), n(needed))
            }
            Requirement::Contributions { current, needed } => {
                (RequirementKind::Contributions, n(current), n(needed))
            }
            Requirement::ActiveDays { current, needed } => {
                (RequirementKind::ActiveDays, n(current), n(needed))
            }
            Requirement::NoRemoval { current } => (RequirementKind::NoRemoval, n(current), Some(0)),
            Requirement::Sponsor => (RequirementKind::Sponsor, None, None),
            Requirement::Nomination => (RequirementKind::Nomination, None, None),
            Requirement::Administration => (RequirementKind::Administration, None, None),
        };
        Self {
            kind,
            current,
            needed,
        }
    }
}

/// The level after the account's, and what it still needs.
#[derive(SimpleObject, Debug, Clone)]
pub struct NextLevel {
    /// The level.
    pub level: i32,
    /// Every requirement still unmet.
    pub missing: Vec<LevelRequirement>,
    /// A way to reach it instead of `missing`, when there is one (a sponsor
    /// for level 1).
    pub instead: Option<LevelRequirement>,
}

impl From<DomainNextLevel> for NextLevel {
    fn from(n: DomainNextLevel) -> Self {
        Self {
            level: i32::from(n.level),
            missing: n.missing.into_iter().map(Into::into).collect(),
            instead: n.instead.map(Into::into),
        }
    }
}

/// The signed-in account: its public face, its level, and its own
/// contributions with their status.
pub struct Account {
    pub(crate) viewer: Viewer,
    pub(crate) level: u8,
    pub(crate) next: Option<DomainNextLevel>,
}

/// Largest page of the account's own lists.
const MAX_OWN_PAGE: i32 = 100;

fn own_page(first: Option<i32>) -> Result<i64> {
    let first = first.unwrap_or(50);
    if (1..=MAX_OWN_PAGE).contains(&first) {
        Ok(i64::from(first))
    } else {
        Err(crate::error::invalid_input(format!(
            "first must be between 1 and {MAX_OWN_PAGE}"
        )))
    }
}

#[Object]
impl Account {
    /// Stable identifier (public: it appears on the account's
    /// contributions).
    async fn id(&self) -> Uuid {
        self.viewer.id()
    }

    /// Public display name.
    async fn pseudonym(&self) -> &str {
        &self.viewer.account.pseudonym
    }

    /// Trust level, 0 to 4.
    async fn trust_level(&self) -> i32 {
        i32::from(self.level)
    }

    /// The next level and what it needs; null at level 4.
    async fn next_level(&self) -> Option<NextLevel> {
        self.next.clone().map(Into::into)
    }

    /// When the account was created.
    async fn created_at(&self) -> DateTime<Utc> {
        self.viewer.account.created_at
    }

    /// When the account's current recovery code was made (the date of its
    /// paper card, the same on every device); null when it has none. Only
    /// the account itself reads it: `Account` is always the viewer's.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn recovery_code_created_at(&self, ctx: &Context<'_>) -> Result<Option<DateTime<Utc>>> {
        let (pool, _permit) = db(ctx).await?;
        lunaway_db::accounts::recovery_code_created_at(pool, self.viewer.id())
            .await
            .map_err(|e| internal(&e))
    }

    /// The authors this account mutes.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn muted_authors(&self, ctx: &Context<'_>) -> Result<Vec<Author>> {
        let (pool, _permit) = db(ctx).await?;
        let rows = lunaway_db::community::muted_by(pool, self.viewer.id())
            .await
            .map_err(|e| internal(&e))?;
        Ok(rows
            .into_iter()
            .map(|(id, pseudonym)| Author { id, pseudonym })
            .collect())
    }

    /// The account's ratings and reviews, every status, newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn reviews(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<ReviewConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        Ok(
            lunaway_db::community::reviews_of_account(pool, self.viewer.id(), first, after)
                .await
                .map_err(|e| internal(&e))?
                .into(),
        )
    }

    /// The account's ratings and reviews of points of interest, every
    /// status, newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn poi_reviews(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<crate::poi_review_types::PoiReviewConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        Ok(
            lunaway_db::poi_reviews::reviews_of_account(pool, self.viewer.id(), first, after)
                .await
                .map_err(|e| internal(&e))?
                .into(),
        )
    }

    /// The account's photos, every status, newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn photos(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<PhotoConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let page = lunaway_db::community::photos_of_account(pool, self.viewer.id(), first, after)
            .await
            .map_err(|e| internal(&e))?;
        let media = &state(ctx).config.media;
        Ok(PhotoConnection {
            end_cursor: page.nodes.last().map(|p| format!("{ITEM_CURSOR}{}", p.id)),
            nodes: page
                .nodes
                .into_iter()
                .map(|p| Photo::from_row(p, media))
                .collect(),
            has_next_page: page.has_next_page,
            total_count: count(page.total_count),
        })
    }

    /// The account's confirmations, newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn confirmations(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<ConfirmationConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let page =
            lunaway_db::community::confirmations_of_account(pool, self.viewer.id(), first, after)
                .await
                .map_err(|e| internal(&e))?;
        Ok(ConfirmationConnection {
            end_cursor: page.nodes.last().map(|c| format!("{ITEM_CURSOR}{}", c.id)),
            has_next_page: page.has_next_page,
            total_count: count(page.total_count),
            nodes: page
                .nodes
                .into_iter()
                .map(Confirmation::try_from)
                .collect::<Result<_>>()?,
        })
    }

    /// The account's "still there?" answers about points of interest,
    /// newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn poi_confirmations(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<crate::poi_types::PoiConfirmationConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let page = lunaway_db::pois::confirmations_of_account(pool, self.viewer.id(), first, after)
            .await
            .map_err(|e| internal(&e))?;
        Ok(crate::poi_types::PoiConfirmationConnection {
            end_cursor: page.nodes.last().map(|c| format!("{ITEM_CURSOR}{}", c.id)),
            has_next_page: page.has_next_page,
            total_count: count(page.total_count),
            nodes: page.nodes.into_iter().map(Into::into).collect(),
        })
    }

    /// The account's issue reports, newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn issue_reports(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<IssueReportConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let page = lunaway_db::community::issues_of_account(pool, self.viewer.id(), first, after)
            .await
            .map_err(|e| internal(&e))?;
        Ok(IssueReportConnection {
            end_cursor: page.nodes.last().map(|c| format!("{ITEM_CURSOR}{}", c.id)),
            has_next_page: page.has_next_page,
            total_count: count(page.total_count),
            nodes: page
                .nodes
                .into_iter()
                .map(IssueReport::try_from)
                .collect::<Result<_>>()?,
        })
    }

    /// The account's new places and place edits, newest first.
    #[graphql(complexity = "crate::schema::cost(first, 50, child_complexity)")]
    async fn place_submissions(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 50)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<PlaceSubmissionConnection> {
        let first = own_page(first)?;
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let page =
            lunaway_db::submissions::submissions_of_account(pool, self.viewer.id(), first, after)
                .await
                .map_err(|e| internal(&e))?;
        Ok(PlaceSubmissionConnection {
            end_cursor: page.nodes.last().map(|c| format!("{ITEM_CURSOR}{}", c.id)),
            has_next_page: page.has_next_page,
            total_count: count(page.total_count),
            nodes: page.nodes.into_iter().map(Into::into).collect(),
        })
    }

    /// The device keys attached to the account, most recently used first;
    /// `revokeDevice` detaches one.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn devices(&self, ctx: &Context<'_>) -> Result<Vec<Device>> {
        let (pool, _permit) = db(ctx).await?;
        Ok(lunaway_db::accounts::devices(pool, self.viewer.id())
            .await
            .map_err(|e| internal(&e))?
            .into_iter()
            .map(|d| Device {
                current: d.id == self.viewer.device_key_id,
                id: d.id,
                created_at: d.created_at,
                last_used_at: d.last_used_at,
            })
            .collect())
    }
}

/// A device key attached to the account.
#[derive(SimpleObject, Debug, Clone)]
pub struct Device {
    /// Stable identifier (what `revokeDevice` takes).
    pub id: Uuid,
    /// When it was attached.
    pub created_at: DateTime<Utc>,
    /// Its last sign-in.
    pub last_used_at: DateTime<Utc>,
    /// Whether it is the device of this request.
    pub current: bool,
}

/// A page of the account's confirmations, newest first.
#[derive(SimpleObject)]
pub struct ConfirmationConnection {
    /// The confirmations.
    pub nodes: Vec<Confirmation>,
    /// Pass it as `after` for the next page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Confirmations in the whole list.
    pub total_count: i32,
}

/// A page of the account's issue reports, newest first.
#[derive(SimpleObject)]
pub struct IssueReportConnection {
    /// The reports.
    pub nodes: Vec<IssueReport>,
    /// Pass it as `after` for the next page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Reports in the whole list.
    pub total_count: i32,
}

/// A page of the account's submissions, newest first.
#[derive(SimpleObject)]
pub struct PlaceSubmissionConnection {
    /// The submissions.
    pub nodes: Vec<PlaceSubmission>,
    /// Pass it as `after` for the next page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Submissions in the whole list.
    pub total_count: i32,
}

impl Account {
    /// The account behind `viewer`, with its level computed again.
    pub(crate) async fn load(ctx: &Context<'_>, viewer: Viewer) -> Result<Self> {
        let (pool, _permit) = db(ctx).await?;
        let (level, next) = auth::compute_level(pool, &state(ctx).config.trust, viewer.id())
            .await
            .map_err(|e| internal(&e))?
            .unwrap_or((viewer.level(), None));
        Ok(Self {
            viewer,
            level,
            next,
        })
    }
}

/// A sign-in challenge.
#[derive(SimpleObject, Debug, Clone)]
pub struct AuthChallenge {
    /// 32 bytes, base64url (random bytes, the expiry and a server tag):
    /// opaque, single use.
    pub nonce: String,
    /// The exact text to sign (`lunaway-auth:v1:` and the nonce), UTF-8.
    pub message: String,
    /// The challenge must be answered before this.
    pub expires_at: DateTime<Utc>,
}

/// A session handed out by `signIn` or `recoverAccount`.
#[derive(SimpleObject)]
pub struct SignInResult {
    /// The bearer token: send `Authorization: Bearer <token>`. Shown once;
    /// the server keeps only its hash.
    pub token: String,
    /// The session ends then unless used before: each use pushes it back.
    pub expires_at: DateTime<Utc>,
    /// Whether this sign-in created the account.
    pub created: bool,
    /// The account.
    pub account: Account,
}

/// A recovery code, shown once.
#[derive(SimpleObject, Debug, Clone)]
pub struct RecoveryCodeResult {
    /// The code to write down (groups of four, a check symbol at the end);
    /// it replaces any earlier one.
    pub code: String,
}

/// A description in one language.
#[derive(InputObject, Debug, Clone)]
pub struct LocalizedTextInput {
    /// BCP 47 tag (`fr`, `en`).
    pub lang: String,
    /// The text, 1 to 2000 characters.
    pub text: String,
}

/// What a contributor knows of a place; an absent field says nothing.
#[derive(InputObject, Debug, Clone, Default)]
pub struct PlaceDetailsInput {
    /// Display name, 2 to 120 characters.
    pub name: Option<String>,
    /// What the place is.
    pub kind: Option<crate::types::GqlPlaceKind>,
    /// Whether a night may be spent there.
    pub overnight: Option<crate::types::GqlOvernightStatus>,
    /// Services on site (the whole set).
    pub services: Option<Vec<crate::types::GqlService>>,
    /// Activities around (the whole set).
    pub activities: Option<Vec<crate::types::GqlActivity>>,
    /// A description in one language.
    pub description: Option<LocalizedTextInput>,
    /// Price of a night, euros (0 is free).
    pub price_parking_eur: Option<f64>,
    /// Price of the services, euros.
    pub price_services_eur: Option<f64>,
    /// Maximum vehicle height, metres.
    pub max_height_m: Option<f64>,
    /// Pitches for motorhomes.
    pub capacity: Option<i32>,
    /// Opening hours, OSM syntax.
    pub opening_hours: Option<String>,
    /// Website, http(s).
    pub website: Option<String>,
    /// Phone.
    pub phone: Option<String>,
    /// Fields to clear, in an edit only: the community stops stating them
    /// (a wrong phone, a closed website). A field cannot be given a value
    /// and cleared at once (`INVALID_INPUT`).
    pub clear: Option<Vec<GqlPlaceField>>,
}

/// A new place.
#[derive(InputObject, Debug, Clone)]
pub struct NewPlaceInput {
    /// What it is.
    pub kind: crate::types::GqlPlaceKind,
    /// Latitude, degrees.
    pub lat: f64,
    /// Longitude, degrees.
    pub lon: f64,
    /// Its name and what else is known; a name is required.
    pub details: PlaceDetailsInput,
}

/// A favourite list kept on a device before the account existed.
#[derive(InputObject, Debug, Clone)]
pub struct FavoriteListInput {
    /// Its name; merged into the account's list of the same name.
    pub name: String,
    /// Its places.
    pub place_ids: Vec<Uuid>,
}
