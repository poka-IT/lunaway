//! The GraphQL types. Enums mirror the domain's with a `remote` conversion,
//! so the compiler refuses a variant present on one side only; objects wrap
//! the repository rows and only map them.

use async_graphql::{
    Context, Enum, InputObject, Object, Result, SimpleObject, dataloader::DataLoader,
};
use chrono::{DateTime, Utc};
use lunaway_db::places::{PlaceRow, PlaceSourceRow};
use lunaway_domain::{
    OpeningInterval as DomainInterval, conflation::FieldProvenance as DomainProvenance,
};
use uuid::Uuid;

use crate::{
    auth,
    community_types::{
        GqlVerification, IssueSummary, Photo, Review, ReviewConnection, SourceRating,
        parse_item_cursor,
    },
    error::{internal, invalid_input},
    loaders::PlaceSourcesLoader,
    schema::{DB_FIELD_COST, cost, db, state},
};

/// What a place is.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::PlaceKind", name = "PlaceKind")]
pub enum GqlPlaceKind {
    /// A dedicated motorhome area, with or without services.
    MotorhomeArea,
    /// Motorhome services without overnight parking.
    ServiceArea,
    /// A campsite.
    Campsite,
    /// A general car park that takes motorhomes.
    Parking,
    /// A spot in nature, away from any facility.
    Nature,
    /// A roadside rest area.
    RestArea,
    /// A picnic area.
    PicnicArea,
    /// A farm, vineyard or producer that hosts motorhomes.
    Farm,
    /// A private host who welcomes travellers on their land.
    Homestay,
    /// A spot reachable with a 4x4 only.
    OffRoad,
    /// A useful stop that is not a place to stay.
    ExtraService,
}

/// A facility available at or next to a place.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::Service", name = "Service")]
pub enum GqlService {
    /// Drinking water.
    DrinkingWater,
    /// Grey water disposal.
    GreyWater,
    /// Black water (cassette) disposal.
    BlackWater,
    /// Waste bins.
    WasteBin,
    /// Public toilets.
    Toilets,
    /// Showers.
    Showers,
    /// Electric hook-up.
    Electricity,
    /// Wi-Fi.
    Wifi,
    /// Laundry.
    Laundry,
    /// LPG filling station.
    Lpg,
    /// Bottled gas exchange.
    GasBottles,
    /// Motorhome wash.
    VehicleWash,
    /// A bakery within walking distance.
    Bakery,
    /// Swimming pool.
    SwimmingPool,
    /// Pets allowed.
    PetsAllowed,
    /// Usable mobile data.
    MobileData,
    /// Open for winter caravanning.
    WinterCaravanning,
}

/// Something to do from a place.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::Activity", name = "Activity")]
pub enum GqlActivity {
    /// Monuments and visits.
    Monuments,
    /// Windsurfing or kitesurfing.
    WindsurfKitesurf,
    /// Mountain-bike trails.
    MountainBiking,
    /// Hiking trailheads.
    Hiking,
    /// Climbing.
    Climbing,
    /// Canoe or kayak.
    CanoeKayak,
    /// Fishing.
    Fishing,
    /// Shore fishing.
    ShoreFishing,
    /// Swimming.
    Swimming,
    /// Motorcycle rides.
    Motorcycling,
    /// A viewpoint.
    Viewpoint,
    /// A children's playground.
    Playground,
}

/// Whether a night may be spent at a place.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::OvernightStatus", name = "OvernightStatus")]
pub enum GqlOvernightStatus {
    /// Nights are explicitly allowed.
    Allowed,
    /// Nights are not allowed on paper but tolerated in practice.
    Tolerated,
    /// Parking by day only.
    DayOnly,
    /// Nights are forbidden.
    Forbidden,
    /// Nobody has said yet.
    Unknown,
}

/// A latitude/longitude rectangle, in degrees. It may not cross the
/// antimeridian (`west <= east`).
#[derive(InputObject, Debug, Clone, Copy)]
#[graphql(name = "BBoxInput")]
pub struct BBoxInput {
    /// Southern edge.
    pub south: f64,
    /// Western edge.
    pub west: f64,
    /// Northern edge.
    pub north: f64,
    /// Eastern edge.
    pub east: f64,
}

/// A point, in degrees.
#[derive(InputObject, Debug, Clone, Copy)]
#[graphql(name = "LatLonInput")]
pub struct LatLonInput {
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
}

/// Filters of the viewport query; every filter given must hold.
#[derive(InputObject, Debug, Clone, Default)]
#[graphql(name = "PlaceFilter")]
pub struct PlaceFilterInput {
    /// Only these kinds.
    pub kinds: Option<Vec<GqlPlaceKind>>,
    /// The place must have all of them.
    pub services: Option<Vec<GqlService>>,
    /// `true` keeps only places where a night is allowed or tolerated;
    /// `false` or absent does not filter.
    pub overnight_ok: Option<bool>,
    /// Leaves out places whose known maximum height is below this, in
    /// metres; places of unknown height stay.
    pub vehicle_height_m: Option<f64>,
    /// Leaves out places whose known maximum length is below this, in
    /// metres; places of unknown length stay.
    pub vehicle_length_m: Option<f64>,
    /// Leaves out places whose known maximum width is below this, in
    /// metres; places of unknown width stay.
    pub vehicle_width_m: Option<f64>,
    /// Leaves out places whose known maximum weight is below this, in
    /// tonnes; places of unknown weight stay.
    pub vehicle_weight_t: Option<f64>,
}

/// A data source and its terms.
#[derive(SimpleObject, Debug, Clone)]
pub struct Source {
    /// Stable id: `osm`, `atout-france`, `community`.
    pub id: String,
    /// Display name.
    pub name: String,
    /// Licence of the data.
    pub licence: String,
    /// Text to show wherever the data is shown.
    pub attribution: String,
    /// Home page of the source.
    pub url: String,
}

/// A source of a place: which record of which source describes it.
#[derive(SimpleObject, Debug, Clone)]
pub struct PlaceSource {
    /// The source.
    pub source: Source,
    /// Identifier of the record in the source (`way/123`).
    pub external_id: String,
    /// Page of the record at the source, when it has one.
    pub external_url: Option<String>,
    /// When the source was read.
    pub fetched_at: DateTime<Utc>,
    /// How well the record matched the others of the place (0 to 1); null
    /// when it is the place's only record.
    pub match_score: Option<f64>,
}

impl From<PlaceSourceRow> for PlaceSource {
    fn from(r: PlaceSourceRow) -> Self {
        Self {
            source: Source {
                id: r.source_id.to_string(),
                name: r.source_name,
                licence: r.licence,
                attribution: r.attribution,
                url: r.source_url,
            },
            external_id: r.external_id,
            external_url: r.external_url,
            fetched_at: r.fetched_at,
            match_score: r.match_score,
        }
    }
}

/// A value another source gave for a field, different from the one shown.
#[derive(SimpleObject, Debug, Clone)]
pub struct AlternativeValue {
    /// The source that gave it.
    pub source_id: String,
    /// The value, as text.
    pub value: String,
}

/// Which source supplied a field of a place, and what the others said.
#[derive(SimpleObject, Debug, Clone)]
pub struct FieldProvenance {
    /// Field name as in this schema (`name`, `priceParkingEur`); `position`
    /// stands for `lat` and `lon`, `address` for the whole address.
    pub field: String,
    /// Source of the value shown.
    pub source_id: String,
    /// Differing values from other sources.
    pub alternatives: Vec<AlternativeValue>,
}

impl From<&DomainProvenance> for FieldProvenance {
    fn from(p: &DomainProvenance) -> Self {
        Self {
            field: p.field.clone(),
            source_id: p.source_id.to_string(),
            alternatives: p
                .alternatives
                .iter()
                .map(|a| AlternativeValue {
                    source_id: a.source_id.to_string(),
                    value: a.value.clone(),
                })
                .collect(),
        }
    }
}

/// A postal address.
#[derive(SimpleObject, Debug, Clone)]
pub struct Address {
    /// Street and number.
    pub street: Option<String>,
    /// Postcode.
    pub postcode: Option<String>,
    /// Municipality.
    pub city: Option<String>,
    /// ISO 3166-1 alpha-2 country code.
    pub country_code: Option<String>,
}

/// A span of time during which a place is open, in UTC, end excluded.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct OpeningInterval {
    /// Opening time.
    pub start: DateTime<Utc>,
    /// Closing time.
    pub end: DateTime<Utc>,
}

impl From<&DomainInterval> for OpeningInterval {
    fn from(i: &DomainInterval) -> Self {
        Self {
            start: i.start,
            end: i.end,
        }
    }
}

/// A description in one language, with its source.
#[derive(SimpleObject, Debug, Clone)]
pub struct LocalizedText {
    /// BCP 47 tag; `und` when the source does not say.
    pub lang: String,
    /// The text.
    pub text: String,
    /// The source that wrote it.
    pub source_id: String,
}

/// A page about the place elsewhere.
#[derive(SimpleObject, Debug, Clone)]
pub struct ExternalLink {
    /// The source that gave the link.
    pub source_id: String,
    /// An http(s) URL.
    pub url: String,
    /// A short neutral label (`OpenStreetMap`, `Wikidata`, `Wikipedia`).
    pub label: String,
}

/// Most photos `Place.photos` returns.
pub const MAX_PLACE_PHOTOS: i64 = 100;
/// Largest page of `Place.reviews`.
pub const MAX_REVIEWS_PAGE: i32 = 50;
/// Reviews per page when the client does not say.
const DEFAULT_REVIEWS_PAGE: i32 = 20;

/// A place to stop: one real spot, merged from every source that lists it.
pub struct Place(pub PlaceRow);

#[Object]
impl Place {
    /// Stable identifier (UUID v7). A place merged into another keeps
    /// answering `place(id)` with the place that absorbed it.
    async fn id(&self) -> Uuid {
        self.0.id
    }

    /// Name; may be missing (an unnamed car park), the app then shows the
    /// kind and the municipality.
    async fn name(&self) -> Option<&str> {
        self.0.name.as_deref()
    }

    /// What the place is.
    async fn kind(&self) -> GqlPlaceKind {
        self.0.kind.into()
    }

    /// Latitude, WGS 84 degrees.
    async fn lat(&self) -> f64 {
        self.0.position.lat()
    }

    /// Longitude, WGS 84 degrees.
    async fn lon(&self) -> f64 {
        self.0.position.lon()
    }

    /// Whether a night may be spent there.
    async fn overnight(&self) -> GqlOvernightStatus {
        self.0.overnight.into()
    }

    /// Services on site.
    async fn services(&self) -> Vec<GqlService> {
        self.0.services.iter().copied().map(Into::into).collect()
    }

    /// Activities around.
    async fn activities(&self) -> Vec<GqlActivity> {
        self.0.activities.iter().copied().map(Into::into).collect()
    }

    /// Free text.
    async fn description(&self) -> Option<&str> {
        self.0.description.as_deref()
    }

    /// Postal address; null when no part of it is known.
    async fn address(&self) -> Option<Address> {
        let a = &self.0.address;
        (!a.is_empty()).then(|| Address {
            street: a.street.clone(),
            postcode: a.postcode.clone(),
            city: a.city.clone(),
            country_code: a.country_code.clone(),
        })
    }

    /// Price of a night, euros; 0 is free, null unknown.
    async fn price_parking_eur(&self) -> Option<f64> {
        self.0.price_parking_eur
    }

    /// Price of the services (water, dump), euros; 0 is free, null unknown.
    async fn price_services_eur(&self) -> Option<f64> {
        self.0.price_services_eur
    }

    /// Maximum vehicle height, metres.
    async fn max_height_m(&self) -> Option<f64> {
        self.0.max_height_m
    }

    /// Maximum vehicle length, metres.
    async fn max_length_m(&self) -> Option<f64> {
        self.0.max_length_m
    }

    /// Maximum vehicle width, metres.
    async fn max_width_m(&self) -> Option<f64> {
        self.0.max_width_m
    }

    /// Maximum vehicle weight, tonnes.
    async fn max_weight_t(&self) -> Option<f64> {
        self.0.max_weight_t
    }

    /// Number of pitches.
    async fn capacity(&self) -> Option<i32> {
        self.0.capacity
    }

    /// Opening hours in the OSM `opening_hours` syntax.
    async fn opening_hours(&self) -> Option<&str> {
        self.0.opening_hours.as_deref()
    }

    /// Whether `openingHours` parses; false when it is absent.
    async fn opening_hours_parsed(&self) -> bool {
        self.0.opening_hours_parsed
    }

    /// When the place is open over the next two weeks (from local midnight
    /// of the day they were computed, in the place's timezone), as UTC
    /// intervals: what "open now?" needs offline. Null when `openingHours`
    /// is absent or does not parse; empty when the place stays closed over
    /// the whole window.
    async fn opening_intervals(&self) -> Option<Vec<OpeningInterval>> {
        self.0
            .opening_intervals
            .as_ref()
            .map(|v| v.iter().map(OpeningInterval::from).collect())
    }

    /// End of the window `openingIntervals` covers: before it, a time in no
    /// interval is closed; from it on, nothing is known (the device has not
    /// synced since). Null when `openingIntervals` is null.
    async fn opening_intervals_until(&self) -> Option<DateTime<Utc>> {
        self.0.opening_intervals_until
    }

    /// Website.
    async fn website(&self) -> Option<&str> {
        self.0.website.as_deref()
    }

    /// Phone, as the source writes it.
    async fn phone(&self) -> Option<&str> {
        self.0.phone.as_deref()
    }

    /// Official classification, 1 to 5 stars (Atout France for French
    /// campsites); null when unclassified or unknown.
    async fn stars(&self) -> Option<i32> {
        self.0.stars.map(i32::from)
    }

    /// Last time a visitor confirmed the place.
    async fn last_confirmed_at(&self) -> Option<DateTime<Utc>> {
        self.0.last_confirmed_at
    }

    /// Last change of anything the API shows of the place.
    async fn updated_at(&self) -> DateTime<Utc> {
        self.0.updated_at
    }

    /// Every record that describes the place, with its source's licence and
    /// attribution.
    async fn sources(&self, ctx: &Context<'_>) -> Result<Vec<PlaceSource>> {
        let loader = ctx.data_unchecked::<DataLoader<PlaceSourcesLoader>>();
        let rows = loader
            .load_one(self.0.id)
            .await
            .map_err(|e| internal(e.as_ref()))?
            .unwrap_or_default();
        Ok(rows.into_iter().map(PlaceSource::from).collect())
    }

    /// For each field with a value, the source that supplied it.
    async fn provenance(&self) -> Vec<FieldProvenance> {
        self.0
            .provenance
            .iter()
            .map(FieldProvenance::from)
            .collect()
    }

    /// The commune that covers the place (French communes); null outside
    /// them or before they are loaded.
    async fn municipality(&self) -> Option<&str> {
        self.0.municipality.as_deref()
    }

    /// The sync region the place belongs to (`Query.regions`): a French
    /// region (`FR-BRE`) in France, the country code elsewhere. A device
    /// that keeps a region drops the places of that region its pack or
    /// its sync no longer lists.
    async fn region(&self) -> Option<&str> {
        self.0.region.as_deref()
    }

    /// Every description of every source, by language, the source most
    /// trusted for descriptions first.
    async fn descriptions(&self) -> Vec<LocalizedText> {
        self.0
            .descriptions
            .iter()
            .map(|d| LocalizedText {
                lang: d.lang.clone(),
                text: d.text.clone(),
                source_id: d.source_id.to_string(),
            })
            .collect()
    }

    /// Ratings by source: Lunaway users' under `community`; empty while
    /// nobody rated the place.
    async fn ratings(&self) -> Vec<SourceRating> {
        let c = &self.0.community;
        match c.rating_avg {
            Some(average) if c.rating_count > 0 => vec![SourceRating {
                source_id: lunaway_domain::SourceId::COMMUNITY.to_string(),
                average,
                count: c.rating_count,
            }],
            _ => Vec::new(),
        }
    }

    /// Links to the place elsewhere: its OpenStreetMap object, its
    /// Wikidata item, its Wikipedia article.
    async fn external_links(&self) -> Vec<ExternalLink> {
        self.0
            .external_links
            .iter()
            .map(|l| ExternalLink {
                source_id: l.source_id.to_string(),
                url: l.url.clone(),
                label: l.label.clone(),
            })
            .collect()
    }

    /// Published reviews with text.
    async fn review_count(&self) -> i32 {
        self.0.community.review_count
    }

    /// Published photos.
    async fn photo_count(&self) -> i32 {
        self.0.community.photo_count
    }

    /// The latest published photos (three at most), for the card and the
    /// offline copy; each carries its author, so a device hides the photos
    /// of an author it muted.
    async fn cover_photos(&self, ctx: &Context<'_>) -> Vec<Photo> {
        let media = &state(ctx).config.media;
        self.0
            .community
            .cover_photos
            .iter()
            .map(|c| Photo::from_cover(c, media))
            .collect()
    }

    /// Issues visitors reported over the last 30 days, by kind.
    async fn reported_issues(&self) -> Vec<IssueSummary> {
        self.0
            .community
            .reported_issues
            .iter()
            .map(IssueSummary::from)
            .collect()
    }

    /// `TO_VERIFY` while a place only the community describes has not been
    /// confirmed by two accounts other than its author.
    async fn verification(&self) -> GqlVerification {
        self.0.community.verification.into()
    }

    /// The published photos, newest first (100 at most), without the
    /// authors the caller muted. Read per place: it costs a database query.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn photos(&self, ctx: &Context<'_>) -> Result<Vec<Photo>> {
        let viewer = auth::viewer(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        let rows = lunaway_db::community::photos_of_place(
            pool,
            self.0.id,
            viewer.as_ref().map(auth::Viewer::id),
            MAX_PLACE_PHOTOS,
        )
        .await
        .map_err(|e| internal(&e))?;
        let media = &state(ctx).config.media;
        Ok(rows
            .into_iter()
            .map(|r| Photo::from_row(r, media))
            .collect())
    }

    /// The published reviews with text, newest first (50 per page at most),
    /// without the authors the caller muted. Read per place.
    #[graphql(complexity = "cost(first, DEFAULT_REVIEWS_PAGE, child_complexity)")]
    async fn reviews(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 20)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<ReviewConnection> {
        let first = first.unwrap_or(DEFAULT_REVIEWS_PAGE);
        if !(1..=MAX_REVIEWS_PAGE).contains(&first) {
            return Err(invalid_input(format!(
                "first must be between 1 and {MAX_REVIEWS_PAGE}"
            )));
        }
        let after = parse_item_cursor(after.as_deref())?;
        let viewer = auth::viewer(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        Ok(lunaway_db::community::reviews_of_place(
            pool,
            self.0.id,
            viewer.as_ref().map(auth::Viewer::id),
            i64::from(first),
            after,
        )
        .await
        .map_err(|e| internal(&e))?
        .into())
    }

    /// The caller's own rating or review of the place, whatever its status;
    /// null when anonymous or when there is none.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn my_review(&self, ctx: &Context<'_>) -> Result<Option<Review>> {
        let Some(viewer) = auth::viewer(ctx).await? else {
            return Ok(None);
        };
        let (pool, _permit) = db(ctx).await?;
        Ok(
            lunaway_db::community::review_by_account(pool, viewer.id(), self.0.id)
                .await
                .map_err(|e| internal(&e))?
                .map(Review),
        )
    }
}

/// Places created or changed since a cursor, and the ids deleted since.
#[derive(SimpleObject)]
pub struct ChangeSet {
    /// Created or changed places, oldest change first.
    pub places: Vec<Place>,
    /// Places deleted (or merged into another, which then appears in
    /// `places`) since the cursor; empty on a first sync.
    pub deleted: Vec<Uuid>,
    /// Pass it as `since` to get what follows. Opaque.
    pub cursor: String,
    /// Whether more changes follow this page.
    pub has_more: bool,
}

/// A page of places.
#[derive(SimpleObject)]
pub struct PlaceConnection {
    /// The places, in a stable order.
    pub nodes: Vec<Place>,
    /// Pass it as `after` to get the next page; null on an empty page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
    /// Places matching in the whole viewport.
    pub total_count: i32,
}

/// What the app must know of the server's policy.
#[derive(SimpleObject, Debug, Clone)]
pub struct AppConfig {
    /// Oldest app version this server serves.
    pub min_app_version: String,
}
