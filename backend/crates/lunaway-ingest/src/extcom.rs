//! The external community source (`extcom`): a partner's feed of places,
//! reviews and photos, received under a written agreement. The format is
//! Lunaway's own (`docs/feeds.md`): JSON Lines, gzip accepted, a header
//! line naming the agreement, then one place per line.
//!
//! Nothing is crawled: the feed is a file the partner hands over, or a URL
//! it gives for its export. The feed is untrusted input. Its size, its
//! lines, its places, and the reviews and photos of each are bounded
//! ([`Limits`]); its texts become bounded plain text and its photo URLs
//! must point at a host of the agreement (`lunaway_domain::extcom`); every
//! code it uses goes through a mapping table, and a code the tables do not
//! know is counted and dropped, never guessed.
//!
//! The import is incremental and resumable: records, reviews and photos
//! are written only when the feed says something new of them, and the
//! number of lines stored is kept in the cache after each batch, so a run
//! stopped half way resumes after the last batch it stored.

use std::{
    collections::{BTreeMap, BTreeSet},
    io::{BufRead, BufReader, Read},
    path::{Path, PathBuf},
};

use chrono::{DateTime, NaiveDate, NaiveTime, Utc};
use lunaway_db::{
    PgPool,
    extcom::{self as store, Extras, ExtrasStats, NewPhoto, NewReview},
    records::{self, NewRecord, ReadTarget, UpsertStats},
};
use lunaway_domain::{
    Activity, NormalizedRecord, OvernightStatus, PlaceKind, Position, Service, SourceId,
    UNDETERMINED_LANGUAGE,
    community::VehicleKind,
    extcom::{
        Agreement, AgreementError, RawAgreement, Scope, Terms, normalize_photo_url,
        photo_url_allowed, sanitize_line, sanitize_pseudonym, sanitize_text,
    },
    is_language_tag,
};
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, with_retry},
    store::RETIRE_GUARD_PERCENT,
};

/// The format a feed's header must name.
pub const FORMAT: &str = "lunaway-extcom-1";

/// Bounds on a feed, checked as it is read: a feed past them is broken or
/// hostile, and holding it whole would take the importer down.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// Largest download, bytes (the file as sent, compressed or not).
    pub max_download_bytes: u64,
    /// Longest line, bytes, once inflated: a longer one is dropped.
    pub max_line_bytes: usize,
    /// Most places in a feed: past it the import stops, nothing retired.
    pub max_places: usize,
    /// Most reviews kept per place, the newest.
    pub max_reviews_per_place: usize,
    /// Most photos kept per place, in the feed's order.
    pub max_photos_per_place: usize,
    /// Places stored per batch: one transaction for their records, one for
    /// their reviews and photos, then the progress is saved.
    pub batch: usize,
}

impl Default for Limits {
    /// 8 GiB, 1 MiB a line, 2 million places, 200 reviews and 30 photos a
    /// place: the largest community platforms list a few hundred thousand
    /// spots, and a place card shows the latest reviews.
    fn default() -> Self {
        Self {
            max_download_bytes: 8 * 1024 * 1024 * 1024,
            max_line_bytes: 1024 * 1024,
            max_places: 2_000_000,
            max_reviews_per_place: 200,
            max_photos_per_place: 30,
            batch: 500,
        }
    }
}

/// Longest name kept, characters.
const MAX_NAME_CHARS: usize = 200;
/// Longest description kept per language, characters.
const MAX_DESCRIPTION_CHARS: usize = 8_000;
/// Most languages of description kept per place.
const MAX_LANGUAGES: usize = 12;
/// Longest review text kept, characters (the `external_reviews` bound).
const MAX_REVIEW_CHARS: usize = 4_000;
/// Longest external identifier, bytes.
const MAX_ID_BYTES: usize = 128;
/// How far a pin dropped by a visitor may be from the spot, metres, when
/// the feed does not say: a phone's position or a tap on a map.
const DEFAULT_ACCURACY_M: f64 = 20.0;
/// The most accuracy a feed may claim for a spot, metres.
const MAX_ACCURACY_M: f64 = 200.0;

/// What a feed code of a place's kind becomes. `None` drops the place: it
/// is not a place to stop (a restaurant, a shop).
pub const KINDS: &[(&str, Option<PlaceKind>)] = &[
    ("motorhome_area", Some(PlaceKind::MotorhomeArea)),
    ("motorhome_area_free", Some(PlaceKind::MotorhomeArea)),
    ("motorhome_area_paid", Some(PlaceKind::MotorhomeArea)),
    ("service_area", Some(PlaceKind::ServiceArea)),
    ("campsite", Some(PlaceKind::Campsite)),
    ("parking", Some(PlaceKind::Parking)),
    ("parking_day_only", Some(PlaceKind::Parking)),
    ("parking_day_night", Some(PlaceKind::Parking)),
    ("rest_area", Some(PlaceKind::RestArea)),
    ("picnic_area", Some(PlaceKind::PicnicArea)),
    ("nature", Some(PlaceKind::Nature)),
    ("wild_spot", Some(PlaceKind::Nature)),
    ("off_road", Some(PlaceKind::OffRoad)),
    ("farm", Some(PlaceKind::Farm)),
    ("winery", Some(PlaceKind::Farm)),
    ("homestay", Some(PlaceKind::Homestay)),
    ("private_host", Some(PlaceKind::Homestay)),
    ("extra_service", Some(PlaceKind::ExtraService)),
    ("laundry", Some(PlaceKind::ExtraService)),
    ("lpg_station", Some(PlaceKind::ExtraService)),
    ("vehicle_wash", Some(PlaceKind::ExtraService)),
    ("restaurant", None),
    ("shop", None),
    ("hotel", None),
    ("other", None),
];

/// What a feed code of a service becomes; empty drops it explicitly (no
/// matching service in the taxonomy).
pub const SERVICES: &[(&str, &[Service])] = &[
    ("drinking_water", &[Service::DrinkingWater]),
    ("water", &[Service::DrinkingWater]),
    ("grey_water", &[Service::GreyWater]),
    ("black_water", &[Service::BlackWater]),
    ("dump_station", &[Service::GreyWater, Service::BlackWater]),
    ("waste_bin", &[Service::WasteBin]),
    ("toilets", &[Service::Toilets]),
    ("showers", &[Service::Showers]),
    ("electricity", &[Service::Electricity]),
    ("wifi", &[Service::Wifi]),
    ("laundry", &[Service::Laundry]),
    ("lpg", &[Service::Lpg]),
    ("gas_bottles", &[Service::GasBottles]),
    ("vehicle_wash", &[Service::VehicleWash]),
    ("bakery", &[Service::Bakery]),
    ("swimming_pool", &[Service::SwimmingPool]),
    ("pets_allowed", &[Service::PetsAllowed]),
    ("mobile_data", &[Service::MobileData]),
    ("winter_caravanning", &[Service::WinterCaravanning]),
    ("disabled_access", &[]),
    ("restaurant", &[]),
    ("shop", &[]),
];

/// What a feed code of an activity becomes; empty drops it explicitly.
pub const ACTIVITIES: &[(&str, &[Activity])] = &[
    ("monuments", &[Activity::Monuments]),
    ("windsurf_kitesurf", &[Activity::WindsurfKitesurf]),
    ("mountain_biking", &[Activity::MountainBiking]),
    ("hiking", &[Activity::Hiking]),
    ("climbing", &[Activity::Climbing]),
    ("canoe_kayak", &[Activity::CanoeKayak]),
    ("fishing", &[Activity::Fishing]),
    ("shore_fishing", &[Activity::ShoreFishing]),
    ("swimming", &[Activity::Swimming]),
    ("motorcycling", &[Activity::Motorcycling]),
    ("viewpoint", &[Activity::Viewpoint]),
    ("playground", &[Activity::Playground]),
    ("skiing", &[]),
];

/// What a feed code of a reviewer's vehicle becomes.
pub const VEHICLES: &[(&str, VehicleKind)] = &[
    ("van", VehicleKind::Van),
    ("campervan", VehicleKind::Campervan),
    ("motorhome", VehicleKind::Motorhome),
    ("caravan", VehicleKind::Caravan),
    ("other", VehicleKind::Other),
    ("car", VehicleKind::Other),
    ("tent", VehicleKind::Other),
];

/// What a feed code of an overnight status becomes.
pub const OVERNIGHT: &[(&str, OvernightStatus)] = &[
    ("allowed", OvernightStatus::Allowed),
    ("tolerated", OvernightStatus::Tolerated),
    ("day_only", OvernightStatus::DayOnly),
    ("forbidden", OvernightStatus::Forbidden),
    ("unknown", OvernightStatus::Unknown),
];

fn lookup<T: Copy>(table: &[(&str, T)], code: &str) -> Option<T> {
    table.iter().find(|(c, _)| *c == code).map(|(_, v)| *v)
}

/// The header line.
#[derive(Debug, Clone, Deserialize)]
struct Header {
    format: String,
    generated_at: Option<DateTime<Utc>>,
    /// Whether the feed lists every live item (absent ones are deleted) or
    /// only what changed.
    #[serde(default = "complete_by_default")]
    complete: bool,
    agreement: Option<RawAgreement>,
}

const fn complete_by_default() -> bool {
    true
}

/// A line of the feed, as JSON.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Line {
    Header(Box<Header>),
    Place(Box<FeedPlace>),
}

#[derive(Debug, Clone, Default, Deserialize)]
struct FeedAddress {
    street: Option<String>,
    postcode: Option<String>,
    city: Option<String>,
    country_code: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct FeedPrice {
    amount: f64,
    currency: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct FeedPrices {
    parking: Option<FeedPrice>,
    services: Option<FeedPrice>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct FeedLimits {
    max_height_m: Option<f64>,
    max_length_m: Option<f64>,
}

#[derive(Debug, Clone, Deserialize)]
struct FeedPeriod {
    from: String,
    to: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct FeedOpening {
    #[serde(default)]
    periods: Vec<FeedPeriod>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct FeedOvernight {
    status: Option<String>,
    #[serde(default)]
    reports_allowed: u32,
    #[serde(default)]
    reports_forbidden: u32,
}

#[derive(Debug, Clone, Deserialize)]
struct FeedRating {
    average: f64,
    count: i64,
}

/// A date or a date-time: a day reads as its noon in UTC.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(untagged)]
enum FeedDate {
    At(DateTime<Utc>),
    Day(NaiveDate),
}

impl FeedDate {
    fn at(self) -> DateTime<Utc> {
        match self {
            Self::At(t) => t,
            Self::Day(d) => d.and_time(NaiveTime::MIN).and_utc() + chrono::Duration::hours(12),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct FeedReview {
    id: String,
    author_id: Option<String>,
    author: Option<String>,
    date: Option<FeedDate>,
    lang: Option<String>,
    rating: Option<f64>,
    text: Option<String>,
    vehicle: Option<String>,
    #[serde(default)]
    deleted: bool,
}

#[derive(Debug, Clone, Deserialize)]
struct FeedPhoto {
    id: String,
    url: String,
    author_id: Option<String>,
    author: Option<String>,
    licence: Option<String>,
    taken_at: Option<FeedDate>,
    #[serde(default)]
    deleted: bool,
}

/// A place line. Its reviews and photos are read one by one
/// ([`reviews_of`], [`photos_of`]): one malformed review must not drop the
/// spot.
#[derive(Debug, Clone, Deserialize)]
struct FeedPlace {
    id: String,
    #[serde(default)]
    deleted: bool,
    kind: Option<String>,
    name: Option<String>,
    #[serde(default)]
    descriptions: BTreeMap<String, String>,
    lat: Option<f64>,
    lon: Option<f64>,
    accuracy_m: Option<f64>,
    address: Option<FeedAddress>,
    #[serde(default)]
    services: Vec<String>,
    #[serde(default)]
    activities: Vec<String>,
    prices: Option<FeedPrices>,
    limits: Option<FeedLimits>,
    opening: Option<FeedOpening>,
    overnight: Option<FeedOvernight>,
    rating: Option<FeedRating>,
    #[serde(default)]
    reviews: Vec<serde_json::Value>,
    #[serde(default)]
    photos: Vec<serde_json::Value>,
    website: Option<String>,
    phone: Option<String>,
}

/// The authors erased at the partner's request, by `author_hash`, as the
/// import read them at its start: their reviews and photos are left out
/// before the bounds of a place are applied, so a place keeps its 200
/// newest reviews of authors still there. Each batch's store reads the
/// erasures again under the writers' lock
/// (`lunaway_db::extcom::store_extras`), which is what holds an erasure
/// that lands while the import runs.
#[derive(Debug, Clone, Default)]
pub struct Erasures {
    hashes: BTreeSet<String>,
}

impl Erasures {
    /// The erasures of the hashes `hashes`.
    #[must_use]
    pub fn new(hashes: BTreeSet<String>) -> Self {
        Self { hashes }
    }

    fn erased(&self, author_id: Option<&str>) -> bool {
        !self.hashes.is_empty()
            && author_id.is_some_and(|id| {
                self.hashes
                    .contains(&lunaway_domain::extcom::author_hash(id))
            })
    }
}

/// Why a line of the feed was dropped, for the report.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Dropped {
    /// Not JSON, or not a place of the format.
    Malformed,
    /// Longer than [`Limits::max_line_bytes`].
    TooLong,
    /// An identifier empty, too long or with spaces or controls.
    BadId,
    /// A position outside the Earth, or at 0, 0.
    BadPosition,
    /// A kind the table maps to no place (a restaurant, a shop).
    NotAPlace,
    /// A kind the table does not know.
    UnknownKind,
    /// The same identifier as an earlier line.
    Duplicate,
}

/// One place of the feed, mapped.
#[derive(Debug, Clone, PartialEq)]
pub struct Mapped {
    /// Its record.
    pub record: crate::FetchedRecord,
    /// Its reviews, summary and photos.
    pub extras: Extras,
}

/// What mapping a line found besides the place.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LineNotes {
    /// Codes no table knows, by table (`service:sauna`), with how often;
    /// at most [`MAX_UNMAPPED`] distinct ones, each cut to
    /// [`MAX_CODE_BYTES`]: a hostile feed must not grow the report.
    pub unmapped: BTreeMap<String, usize>,
    /// Occurrences of codes past [`MAX_UNMAPPED`] distinct ones.
    pub unmapped_more: usize,
    /// Reviews dropped (no rating nor text, a bad id or date, over the
    /// bound).
    pub reviews_dropped: usize,
    /// Photos dropped (a URL outside the agreement's hosts, a bad id, over
    /// the bound).
    pub photos_dropped: usize,
    /// Reviews and photos of an erased author the feed still carried,
    /// skipped.
    pub erased_skipped: usize,
}

/// Lines read at most per place allowed ([`Limits::max_places`]), dropped
/// lines included.
const MAX_LINES_PER_PLACE: u64 = 4;

/// Most distinct unknown codes a report keeps.
pub const MAX_UNMAPPED: usize = 1_000;
/// Longest unknown code a report keeps, bytes.
pub const MAX_CODE_BYTES: usize = 64;

/// Counts `n` occurrences of `key` in `map`, a new key only while `map`
/// holds fewer than [`MAX_UNMAPPED`]; the others go to `more`.
fn count_capped(map: &mut BTreeMap<String, usize>, more: &mut usize, key: String, n: usize) {
    if let Some(c) = map.get_mut(&key) {
        *c += n;
    } else if map.len() < MAX_UNMAPPED {
        map.insert(key, n);
    } else {
        *more += n;
    }
}

impl LineNotes {
    /// Notes a code `table` does not know.
    fn unknown(&mut self, table: &str, code: &str) {
        let mut cut = MAX_CODE_BYTES.min(code.len());
        while !code.is_char_boundary(cut) {
            cut -= 1;
        }
        let key = format!("{table}:{}", &code[..cut]);
        count_capped(&mut self.unmapped, &mut self.unmapped_more, key, 1);
    }
}

/// What a place line says, under `agreement`, read at `fetched_at`.
///
/// # Errors
///
/// [`Dropped`] when the line makes no place.
fn map_place(
    p: FeedPlace,
    raw: serde_json::Value,
    ctx: &MapContext<'_>,
    notes: &mut LineNotes,
) -> Result<Mapped, Dropped> {
    let MapContext {
        agreement,
        limits,
        erasures,
        fetched_at,
    } = *ctx;
    if !valid_id(&p.id) {
        return Err(Dropped::BadId);
    }
    let code = p.kind.as_deref().unwrap_or_default();
    let kind = match KINDS.iter().find(|(c, _)| *c == code) {
        Some((_, Some(k))) => *k,
        Some((_, None)) => return Err(Dropped::NotAPlace),
        None => {
            notes.unknown("kind", code);
            return Err(Dropped::UnknownKind);
        }
    };
    let (Some(lat), Some(lon)) = (p.lat, p.lon) else {
        return Err(Dropped::BadPosition);
    };
    let position = Position::new(lat, lon).map_err(|_| Dropped::BadPosition)?;
    if lat == 0.0 && lon == 0.0 {
        return Err(Dropped::BadPosition);
    }
    let mut r = NormalizedRecord::new(kind, position);
    r.accuracy_m = p
        .accuracy_m
        .filter(|a| a.is_finite())
        .map_or(DEFAULT_ACCURACY_M, |a| a.clamp(0.0, MAX_ACCURACY_M));
    r.name = p
        .name
        .as_deref()
        .and_then(|n| sanitize_line(n, MAX_NAME_CHARS));
    for (lang, text) in p.descriptions.iter().take(MAX_LANGUAGES) {
        let lang = if is_language_tag(lang) {
            lang.clone()
        } else {
            UNDETERMINED_LANGUAGE.to_owned()
        };
        if let Some(t) = sanitize_text(text, MAX_DESCRIPTION_CHARS) {
            r.descriptions.entry(lang).or_insert(t);
        }
    }
    r.description = ["fr", "en"]
        .iter()
        .find_map(|l| r.descriptions.get(*l))
        .or_else(|| r.descriptions.values().next())
        .cloned();
    if let Some(a) = &p.address {
        r.address.street = a.street.as_deref().and_then(|s| sanitize_line(s, 200));
        r.address.postcode = a.postcode.as_deref().and_then(|s| sanitize_line(s, 16));
        r.address.city = a.city.as_deref().and_then(|s| sanitize_line(s, 100));
        r.address.country_code = a
            .country_code
            .as_deref()
            .map(str::trim)
            .filter(|c| c.len() == 2 && c.bytes().all(|b| b.is_ascii_alphabetic()))
            .map(str::to_ascii_uppercase);
    }
    for code in &p.services {
        match SERVICES.iter().find(|(c, _)| c == code) {
            Some((_, services)) => r.services.extend(services.iter().copied()),
            None => notes.unknown("service", code),
        }
    }
    for code in &p.activities {
        match ACTIVITIES.iter().find(|(c, _)| c == code) {
            Some((_, activities)) => r.activities.extend(activities.iter().copied()),
            None => notes.unknown("activity", code),
        }
    }
    if let Some(prices) = &p.prices {
        r.price_parking_eur = prices.parking.as_ref().and_then(euros);
        r.price_services_eur = prices.services.as_ref().and_then(euros);
    }
    if let Some(l) = &p.limits {
        r.max_height_m = l.max_height_m.filter(|h| (1.5..=6.0).contains(h));
        r.max_length_m = l.max_length_m.filter(|h| (3.0..=30.0).contains(h));
    }
    r.opening_hours = p.opening.as_ref().and_then(|o| opening_hours(&o.periods));
    r.overnight = overnight(p.overnight.as_ref(), code, notes);
    r.website = p.website.as_deref().and_then(crate::web::website);
    r.phone = p.phone.as_deref().and_then(|s| sanitize_line(s, 40));

    let reviews = agreement
        .covers(Scope::Reviews)
        .then(|| reviews_of(&p.reviews, limits, erasures, notes));
    let rating = if agreement.covers(Scope::Reviews) {
        p.rating.as_ref().and_then(|f| {
            let count = i32::try_from(f.count).ok().filter(|c| *c > 0)?;
            (f.average.is_finite() && (1.0..=5.0).contains(&f.average))
                .then_some((f.average, count))
        })
    } else {
        None
    };
    let photos = agreement
        .covers(Scope::Photos)
        .then(|| photos_of(&p.photos, agreement, limits, erasures, notes));
    Ok(Mapped {
        record: crate::FetchedRecord {
            external_id: p.id.clone(),
            external_url: None,
            record: r,
            raw,
            fetched_at,
        },
        extras: Extras {
            external_id: p.id,
            reviews,
            rating,
            photos,
        },
    })
}

/// What mapping a line needs besides the line.
#[derive(Clone, Copy)]
struct MapContext<'a> {
    agreement: &'a Agreement,
    limits: &'a Limits,
    erasures: &'a Erasures,
    fetched_at: DateTime<Utc>,
}

fn valid_id(id: &str) -> bool {
    (1..=MAX_ID_BYTES).contains(&id.len())
        && id.chars().all(|c| !c.is_control() && !c.is_whitespace())
}

fn euros(p: &FeedPrice) -> Option<f64> {
    (p.currency.eq_ignore_ascii_case("EUR")
        && p.amount.is_finite()
        && (0.0..=500.0).contains(&p.amount))
    .then_some(p.amount)
}

const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// The OSM `opening_hours` of seasonal periods (`MM-DD` to `MM-DD`, a
/// period may cross the new year): `Apr 01-Oct 31`. Malformed periods are
/// dropped; none left is no opening hours.
fn opening_hours(periods: &[FeedPeriod]) -> Option<String> {
    let day = |s: &str| -> Option<String> {
        let (m, d) = s.split_once('-')?;
        let (m, d): (usize, u32) = (m.parse().ok()?, d.parse().ok()?);
        NaiveDate::from_ymd_opt(2024, u32::try_from(m).ok()?, d)?;
        Some(format!("{} {d:02}", MONTHS.get(m.checked_sub(1)?)?))
    };
    let rules: Vec<String> = periods
        .iter()
        .take(12)
        .filter_map(|p| Some(format!("{}-{}", day(&p.from)?, day(&p.to)?)))
        .collect();
    (!rules.is_empty()).then(|| rules.join(","))
}

/// The overnight status: the feed's own when it states one; otherwise the
/// visitors' reports, when at least two agree and outnumber the others; a
/// day-only car park says so by its kind.
fn overnight(o: Option<&FeedOvernight>, kind: &str, notes: &mut LineNotes) -> OvernightStatus {
    if let Some(status) = o.and_then(|o| o.status.as_deref()) {
        match lookup(OVERNIGHT, status) {
            Some(s) if s != OvernightStatus::Unknown => return s,
            Some(_) => {}
            None => notes.unknown("overnight", status),
        }
    }
    if let Some(o) = o {
        let (yes, no) = (o.reports_allowed, o.reports_forbidden);
        if no >= 2 && no > yes {
            return OvernightStatus::Forbidden;
        }
        if yes >= 2 && yes > no {
            return OvernightStatus::Allowed;
        }
    }
    if kind == "parking_day_only" {
        OvernightStatus::DayOnly
    } else {
        OvernightStatus::Unknown
    }
}

/// The partner's id of an author, as kept for erasures: one token of at
/// most 128 bytes, or nothing.
fn author_id_of(raw: Option<&str>) -> Option<String> {
    raw.map(str::trim)
        .filter(|id| valid_id(id))
        .map(str::to_owned)
}

/// The reviews of a place line, each read on its own: a malformed one is
/// dropped, not the spot. A review marked deleted is left out, as is one
/// by an erased author; what the line leaves out is deleted on store.
fn reviews_of(
    reviews: &[serde_json::Value],
    limits: &Limits,
    erasures: &Erasures,
    notes: &mut LineNotes,
) -> Vec<NewReview> {
    let mut seen = BTreeSet::new();
    let mut out: Vec<NewReview> = Vec::with_capacity(reviews.len());
    for value in reviews {
        let Ok(r) = FeedReview::deserialize(value) else {
            notes.reviews_dropped += 1;
            continue;
        };
        if r.deleted {
            continue;
        }
        if erasures.erased(r.author_id.as_deref()) {
            notes.erased_skipped += 1;
            continue;
        }
        match review_of(&r, notes) {
            Some(review) if seen.insert(review.external_id.clone()) => out.push(review),
            _ => notes.reviews_dropped += 1,
        }
    }
    out.sort_by(|a, b| {
        b.written_at
            .cmp(&a.written_at)
            .then(a.external_id.cmp(&b.external_id))
    });
    if out.len() > limits.max_reviews_per_place {
        notes.reviews_dropped += out.len() - limits.max_reviews_per_place;
        out.truncate(limits.max_reviews_per_place);
    }
    out
}

fn review_of(r: &FeedReview, notes: &mut LineNotes) -> Option<NewReview> {
    if !valid_id(&r.id) {
        return None;
    }
    let written_at = r.date?.at();
    let rating = r
        .rating
        .filter(|x| x.is_finite() && (1.0..=5.0).contains(x))
        // Half stars round to the nearer whole one, halves up.
        .map(|x| (x + 0.5).floor())
        .and_then(|x| {
            // `x` is a whole number from 1 to 5 here.
            #[allow(clippy::cast_possible_truncation, reason = "a whole number from 1 to 5")]
            let stars = x as i16;
            (1..=5).contains(&stars).then_some(stars)
        });
    let body = r
        .text
        .as_deref()
        .and_then(|t| sanitize_text(t, MAX_REVIEW_CHARS));
    if rating.is_none() && body.is_none() {
        return None;
    }
    let vehicle = r.vehicle.as_deref().and_then(|v| {
        let found = lookup(VEHICLES, v);
        if found.is_none() {
            notes.unknown("vehicle", v);
        }
        found.map(|k| k.code().to_owned())
    });
    Some(NewReview {
        external_id: r.id.clone(),
        author_id: author_id_of(r.author_id.as_deref()),
        author: r.author.as_deref().and_then(sanitize_pseudonym),
        written_at,
        lang: r.lang.clone().filter(|l| is_language_tag(l)),
        rating,
        body,
        vehicle,
    })
}

/// The photos of a place line, each read on its own, as [`reviews_of`]
/// reads the reviews; a URL outside the agreement's hosts is dropped.
fn photos_of(
    photos: &[serde_json::Value],
    agreement: &Agreement,
    limits: &Limits,
    erasures: &Erasures,
    notes: &mut LineNotes,
) -> Vec<NewPhoto> {
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for value in photos {
        let Ok(p) = FeedPhoto::deserialize(value) else {
            notes.photos_dropped += 1;
            continue;
        };
        if p.deleted {
            continue;
        }
        if erasures.erased(p.author_id.as_deref()) {
            notes.erased_skipped += 1;
            continue;
        }
        let url =
            normalize_photo_url(&p.url).filter(|u| photo_url_allowed(u, &agreement.photo_hosts));
        let ok = valid_id(&p.id)
            && url.is_some()
            && out.len() < limits.max_photos_per_place
            && seen.insert(p.id.clone());
        let (true, Some(url)) = (ok, url) else {
            notes.photos_dropped += 1;
            continue;
        };
        out.push(NewPhoto {
            external_id: p.id.clone(),
            url,
            author_id: author_id_of(p.author_id.as_deref()),
            author: p.author.as_deref().and_then(sanitize_pseudonym),
            licence: p
                .licence
                .as_deref()
                .and_then(|l| sanitize_line(l, 64))
                .unwrap_or_else(|| agreement.reference.clone()),
            taken_at: p.taken_at.map(FeedDate::at),
        });
    }
    out
}

/// The payload kept with a record: the line as sent, without its reviews
/// and photos (each kept in its own table with its provenance), with how
/// many it held.
fn raw_of(mut line: serde_json::Value) -> serde_json::Value {
    if let Some(obj) = line.as_object_mut() {
        for key in ["reviews", "photos"] {
            if let Some(serde_json::Value::Array(items)) = obj.remove(key) {
                obj.insert(format!("{key}_count"), items.len().into());
            }
        }
    }
    line
}

/// Where the feed is read from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Input {
    /// A file on this machine.
    File(PathBuf),
    /// An `https` URL the partner gave for its export.
    Url(String),
}

impl Input {
    /// `path_or_url` as an input: an `https://` URL, or a path.
    #[must_use]
    pub fn parse(path_or_url: &str) -> Self {
        if path_or_url.starts_with("https://") || path_or_url.starts_with("http://") {
            Self::Url(path_or_url.to_owned())
        } else {
            Self::File(PathBuf::from(path_or_url))
        }
    }
}

/// What an import of the feed did.
#[derive(Debug, Clone, Default)]
pub struct Report {
    /// The agreement the feed came under.
    pub agreement: String,
    /// The feed's SHA-256, which keys its progress.
    pub feed_sha256: String,
    /// Whether a downloaded feed came from the cache.
    pub cached: bool,
    /// Lines a stopped run had stored already, skipped.
    pub resumed_after: u64,
    /// Lines read, the header included.
    pub lines: u64,
    /// Places mapped.
    pub places: usize,
    /// Lines dropped, by reason.
    pub dropped: BTreeMap<Dropped, usize>,
    /// Codes no table knows, with how often ([`MAX_UNMAPPED`] at most).
    pub unmapped: BTreeMap<String, usize>,
    /// Occurrences of the unknown codes past [`MAX_UNMAPPED`] distinct ones.
    pub unmapped_more: usize,
    /// Reviews dropped.
    pub reviews_dropped: usize,
    /// Photos dropped.
    pub photos_dropped: usize,
    /// What the records upsert did.
    pub records: UpsertStats,
    /// Records whose licence changed to the agreement's.
    pub licences_set: u64,
    /// What the reviews, summaries and photos stores did.
    pub extras: ExtrasStats,
    /// Whether the feed listed every live item (absent ones deleted) or
    /// only what changed.
    pub complete: bool,
    /// Places the feed marked deleted.
    pub marked_deleted: usize,
    /// Records retired: absent from a complete feed, or marked deleted.
    pub retired: u64,
    /// Whether retiring the absent ones was refused: the feed held less
    /// than half of the stored records.
    pub retire_refused: bool,
    /// What was forgotten of the retired records: their content, reviews,
    /// ratings and photos.
    pub forgotten: store::Forgotten,
    /// Reviews and photos of erased authors the feed still carried,
    /// skipped.
    pub erased_skipped: usize,
}

/// What an import runs with besides the feed.
#[derive(Debug, Clone)]
pub struct Options {
    /// The server's agreement reference and photo hosts.
    pub terms: Terms,
    /// The bounds on the feed.
    pub limits: Limits,
    /// Downloads a URL again instead of reading the cache.
    pub refresh: bool,
    /// The day of the import, which the agreement must be in force on.
    pub today: NaiveDate,
}

/// Imports the feed at `input` with `http` for a URL, keeping a download
/// and the progress under `cache`, under `options`.
///
/// # Errors
///
/// [`IngestError::Agreement`] for a feed without an agreement, naming
/// another than the server's, or not in force; [`IngestError::SourceHidden`]
/// when the source is hidden; [`IngestError::Implausible`] for a feed that
/// is not of the format or holds more places than [`Limits::max_places`];
/// and the errors of the download, the cache and the database. Batches
/// stored before an error stay, and the next run resumes after them.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    input: &Input,
    options: &Options,
) -> Result<Report, IngestError> {
    let source = SourceId::EXTCOM;
    if store::switch(pool, &source).await?.hidden_at.is_some() {
        return Err(IngestError::SourceHidden(source));
    }
    let (limits, refresh, today) = (options.limits, options.refresh, options.today);
    let erasures = Erasures::new(store::erased_authors(pool, &source).await?);
    let mut report = Report::default();
    let path = match input {
        Input::File(p) => p.clone(),
        Input::Url(url) => {
            if !url.starts_with("https://") {
                // The feed holds pseudonyms and author ids, and a complete
                // feed deletes what it leaves out: never over plain HTTP.
                return Err(IngestError::UntrustedUrl {
                    url: url.clone(),
                    reason: "a feed is downloaded over HTTPS only",
                });
            }
            let (p, cached) =
                download(http, cache, url, limits.max_download_bytes, refresh).await?;
            report.cached = cached;
            p
        }
    };
    let sha = {
        let path = path.clone();
        tokio::task::spawn_blocking(move || file_sha256(&path))
            .await
            .map_err(IngestError::Blocking)??
    };
    report.feed_sha256.clone_from(&sha);
    let progress_key = format!("extcom/progress-{}.json", &sha[..16]);
    let done_lines = read_progress(cache, &progress_key).await?;
    report.resumed_after = done_lines;
    let fetched_at = Utc::now();

    let (tx, mut rx) = tokio::sync::mpsc::channel::<Event>(2);
    let reader = {
        let path = path.clone();
        let read = ReadContext {
            limits,
            terms: options.terms.clone(),
            erasures,
            today,
            fetched_at,
        };
        tokio::task::spawn_blocking(move || read_feed(&path, &read, &tx))
    };
    let mut agreement: Option<Agreement> = None;
    let mut seen: Vec<String> = Vec::new();
    while let Some(event) = rx.recv().await {
        match event {
            Event::Agreement(a, complete) => {
                store::upsert_agreement(pool, &source, &a, fetched_at).await?;
                report.agreement.clone_from(&a.reference);
                report.complete = complete;
                agreement = Some(a);
            }
            Event::Batch(batch) => {
                let Some(a) = &agreement else {
                    return Err(IngestError::Agreement(AgreementError::Missing));
                };
                for (reason, n) in &batch.dropped {
                    *report.dropped.entry(*reason).or_insert(0) += n;
                }
                report.unmapped_more += batch.notes.unmapped_more;
                for (code, n) in &batch.notes.unmapped {
                    count_capped(
                        &mut report.unmapped,
                        &mut report.unmapped_more,
                        code.clone(),
                        *n,
                    );
                }
                report.reviews_dropped += batch.notes.reviews_dropped;
                report.photos_dropped += batch.notes.photos_dropped;
                report.erased_skipped += batch.notes.erased_skipped;
                report.places += batch.places.len();
                report.marked_deleted += batch.deleted.len();
                seen.extend(batch.seen.iter().cloned());
                if batch.last_line <= done_lines {
                    continue;
                }
                store_batch(pool, &source, a, &batch, fetched_at, &mut report).await?;
                write_progress(cache, &progress_key, batch.last_line).await?;
            }
            Event::Done(lines) => report.lines = lines,
        }
    }
    reader.await.map_err(IngestError::Blocking)??;
    if agreement.is_none() {
        return Err(IngestError::Agreement(AgreementError::Missing));
    }
    if report.complete {
        retire_absent(pool, &source, &seen, fetched_at, &mut report).await?;
    }
    report.forgotten = store::forget_retired(pool, &source).await?;
    cache.remove(&progress_key).await?;
    if matches!(input, Input::Url(_)) {
        // A downloaded feed holds pseudonyms, author ids and reviews that
        // an erasure or a purge must not leave behind: kept only while a
        // stopped run may need it to resume.
        tokio::fs::remove_file(&path)
            .await
            .map_err(|source| IngestError::Cache {
                path: path.clone(),
                source,
            })?;
    }
    tracing::info!(
        agreement = report.agreement,
        places = report.places,
        inserted = report.records.inserted,
        changed = report.records.changed,
        retired = report.retired,
        "extcom feed stored"
    );
    Ok(report)
}

async fn store_batch(
    pool: &PgPool,
    source: &SourceId,
    agreement: &Agreement,
    batch: &Batch,
    fetched_at: DateTime<Utc>,
    report: &mut Report,
) -> Result<(), IngestError> {
    if !batch.deleted.is_empty() {
        report.retired += store::retire_records(pool, source, &batch.deleted).await?;
    }
    let places = &batch.places;
    let rows: Vec<NewRecord<'_>> = places
        .iter()
        .map(|m| NewRecord {
            external_id: &m.record.external_id,
            external_url: m.record.external_url.as_deref(),
            record: &m.record.record,
            raw: &m.record.raw,
            fetched_at: m.record.fetched_at,
            scope: None,
        })
        .collect();
    let Some(stats) = records::upsert_unless_hidden(pool, source, &rows).await? else {
        return Err(IngestError::SourceHidden(source.clone()));
    };
    report.records += stats;
    let ids: Vec<String> = places
        .iter()
        .map(|m| m.record.external_id.clone())
        .collect();
    report.licences_set +=
        store::set_record_licence(pool, source, &ids, &agreement.reference).await?;
    let extras: Vec<Extras> = places.iter().map(|m| m.extras.clone()).collect();
    let Some(stats) =
        store::store_extras(pool, source, &agreement.reference, fetched_at, &extras).await?
    else {
        return Err(IngestError::SourceHidden(source.clone()));
    };
    report.erased_skipped += usize::try_from(stats.erased_skipped).unwrap_or(usize::MAX);
    report.extras += stats;
    Ok(())
}

/// Retires the records of a complete feed's source that the feed did not
/// list, unless it listed less than [`RETIRE_GUARD_PERCENT`] of them (a
/// truncated file), and dates the read.
async fn retire_absent(
    pool: &PgPool,
    source: &SourceId,
    seen: &[String],
    at: DateTime<Utc>,
    report: &mut Report,
) -> Result<(), IngestError> {
    let stored = records::live_count(pool, source, None).await?;
    let seen_n = u64::try_from(seen.len()).unwrap_or(u64::MAX);
    let stored_n = u64::try_from(stored).unwrap_or(0);
    if seen_n.saturating_mul(100) < stored_n.saturating_mul(RETIRE_GUARD_PERCENT) {
        tracing::warn!(
            seen = seen.len(),
            stored,
            "the feed holds less than half of the stored records; nothing is retired"
        );
        report.retire_refused = true;
        return Ok(());
    }
    report.retired += records::retire_missing(pool, source, None, seen, at).await?;
    records::mark_read(pool, ReadTarget::Records, source, &[(String::new(), at)]).await?;
    Ok(())
}

/// What the reading thread hands the writer.
enum Event {
    /// The header's agreement, checked, and whether the feed is complete:
    /// first, before any batch.
    Agreement(Agreement, bool),
    /// A batch of places.
    Batch(Batch),
    /// The end, with the number of lines read.
    Done(u64),
}

struct Batch {
    places: Vec<Mapped>,
    /// The ids a complete feed keeps: its places, and the lines whose
    /// content was refused (an unknown kind, a bad position) whose spot
    /// stays as last stored rather than being deleted for a mapping gap.
    seen: Vec<String>,
    /// The ids the feed marks deleted.
    deleted: Vec<String>,
    dropped: BTreeMap<Dropped, usize>,
    notes: LineNotes,
    /// The number of the last line it holds (1 is the header).
    last_line: u64,
}

impl Batch {
    fn new(size: usize) -> Self {
        Self {
            places: Vec::with_capacity(size),
            seen: Vec::with_capacity(size),
            deleted: Vec::new(),
            dropped: BTreeMap::new(),
            notes: LineNotes::default(),
            last_line: 0,
        }
    }

    fn is_empty(&self) -> bool {
        self.places.is_empty()
            && self.seen.is_empty()
            && self.deleted.is_empty()
            && self.dropped.is_empty()
    }
}

/// What the reading thread works with.
struct ReadContext {
    limits: Limits,
    terms: Terms,
    erasures: Erasures,
    today: NaiveDate,
    fetched_at: DateTime<Utc>,
}

/// Reads the feed at `path` on a blocking thread, handing the agreement,
/// then batches of places, to `tx`. A line longer than the bound is
/// skipped, not held.
fn read_feed(
    path: &Path,
    ctx: &ReadContext,
    tx: &tokio::sync::mpsc::Sender<Event>,
) -> Result<(), IngestError> {
    let limits = &ctx.limits;
    let what = || path.display().to_string();
    let file = std::fs::File::open(path).map_err(|source| IngestError::Cache {
        path: path.to_owned(),
        source,
    })?;
    let mut reader = BufReader::new(file);
    let gzip = reader
        .fill_buf()
        .map_err(|source| IngestError::Cache {
            path: path.to_owned(),
            source,
        })?
        .starts_with(&[0x1f, 0x8b]);
    let mut input: Box<dyn BufRead> = if gzip {
        Box::new(BufReader::new(flate2::bufread::MultiGzDecoder::new(reader)))
    } else {
        Box::new(reader)
    };
    let mut line_no: u64 = 0;
    let mut agreement: Option<Agreement> = None;
    let mut seen_ids: BTreeSet<String> = BTreeSet::new();
    let mut batch = Batch::new(limits.batch);
    let mut buf = Vec::new();
    let read_error = |source| IngestError::Inflate {
        what: what(),
        source,
    };
    loop {
        let Some(fits) =
            read_line(&mut input, &mut buf, limits.max_line_bytes).map_err(read_error)?
        else {
            break;
        };
        line_no += 1;
        // Malformed and overlong lines count too: a feed of nothing but
        // them must end, not keep the import inflating a bomb.
        let max_lines = MAX_LINES_PER_PLACE
            .saturating_mul(u64::try_from(limits.max_places).unwrap_or(u64::MAX));
        if line_no > max_lines {
            return Err(IngestError::Implausible {
                what: format!("{}: more than {max_lines} lines", what()),
            });
        }
        if !fits {
            if agreement.is_none() {
                return Err(IngestError::Implausible {
                    what: format!("{}: the header line is longer than allowed", what()),
                });
            }
            *batch.dropped.entry(Dropped::TooLong).or_insert(0) += 1;
            continue;
        }
        let text = buf.trim_ascii();
        if text.is_empty() {
            continue;
        }
        let Some(a) = &agreement else {
            let (a, complete) = header(text, &ctx.terms, ctx.today, &what)?;
            if tx
                .blocking_send(Event::Agreement(a.clone(), complete))
                .is_err()
            {
                return Ok(());
            }
            agreement = Some(a);
            continue;
        };
        let value: serde_json::Value = match serde_json::from_slice(text) {
            Ok(v) => v,
            Err(_) => {
                *batch.dropped.entry(Dropped::Malformed).or_insert(0) += 1;
                continue;
            }
        };
        let place = match serde_json::from_value::<Line>(value.clone()) {
            Ok(Line::Place(p)) => *p,
            Ok(Line::Header(_)) | Err(_) => {
                *batch.dropped.entry(Dropped::Malformed).or_insert(0) += 1;
                continue;
            }
        };
        batch.last_line = line_no;
        // Checked before it is kept: an id of a megabyte, line after line,
        // would otherwise fill the memory the bounds are meant to hold.
        if !valid_id(&place.id) {
            *batch.dropped.entry(Dropped::BadId).or_insert(0) += 1;
            continue;
        }
        if !seen_ids.insert(place.id.clone()) {
            *batch.dropped.entry(Dropped::Duplicate).or_insert(0) += 1;
            continue;
        }
        if seen_ids.len() > limits.max_places {
            return Err(IngestError::Implausible {
                what: format!("{}: more than {} places", what(), limits.max_places),
            });
        }
        if place.deleted {
            batch.deleted.push(place.id);
        } else {
            let id = place.id.clone();
            let map = MapContext {
                agreement: a,
                limits,
                erasures: &ctx.erasures,
                fetched_at: ctx.fetched_at,
            };
            match map_place(place, raw_of(value), &map, &mut batch.notes) {
                Ok(m) => {
                    batch.seen.push(id);
                    batch.places.push(m);
                }
                Err(reason) => {
                    if matches!(reason, Dropped::UnknownKind | Dropped::BadPosition) {
                        batch.seen.push(id);
                    }
                    *batch.dropped.entry(reason).or_insert(0) += 1;
                }
            }
        }
        if batch.places.len() + batch.deleted.len() >= limits.batch {
            let full = std::mem::replace(&mut batch, Batch::new(limits.batch));
            if tx.blocking_send(Event::Batch(full)).is_err() {
                return Ok(());
            }
        }
    }
    if agreement.is_none() {
        return Err(IngestError::Agreement(AgreementError::Missing));
    }
    if !batch.is_empty() {
        batch.last_line = batch.last_line.max(line_no);
        let _ = tx.blocking_send(Event::Batch(batch));
    }
    let _ = tx.blocking_send(Event::Done(line_no));
    Ok(())
}

/// The header line: the format, then the agreement, checked against the
/// server's `terms` on `today`; and whether the feed is complete.
fn header(
    text: &[u8],
    terms: &Terms,
    today: NaiveDate,
    what: &impl Fn() -> String,
) -> Result<(Agreement, bool), IngestError> {
    let implausible = |why: &str| IngestError::Implausible {
        what: format!("{}: {why}", what()),
    };
    let header = match serde_json::from_slice::<Line>(text) {
        Ok(Line::Header(h)) => h,
        Ok(Line::Place(_)) => {
            return Err(IngestError::Agreement(AgreementError::Missing));
        }
        Err(e) => {
            return Err(IngestError::Json {
                what: format!("{}: the header line", what()),
                source: e,
            });
        }
    };
    if header.format != FORMAT {
        return Err(implausible(&format!(
            "the format is {:?}, not {FORMAT:?}",
            header.format
        )));
    }
    if header.generated_at.is_none() {
        return Err(implausible("the header has no generated_at"));
    }
    let raw = header
        .agreement
        .ok_or(IngestError::Agreement(AgreementError::Missing))?;
    let agreement = Agreement::check(&raw, terms, today).map_err(IngestError::Agreement)?;
    Ok((agreement, header.complete))
}

/// Reads one line into `buf` (its end of line left out). `Some(true)`: a
/// line within `max` bytes; `Some(false)`: a longer one, skipped to its end
/// and not kept; `None`: the end of the input.
fn read_line(
    input: &mut dyn BufRead,
    buf: &mut Vec<u8>,
    max: usize,
) -> std::io::Result<Option<bool>> {
    buf.clear();
    let mut fits = true;
    let mut read_any = false;
    loop {
        let available = input.fill_buf()?;
        if available.is_empty() {
            return Ok(read_any.then_some(fits));
        }
        read_any = true;
        let (chunk, found) = match available.iter().position(|&b| b == b'\n') {
            Some(i) => (&available[..i], Some(i)),
            None => (available, None),
        };
        if fits && buf.len() + chunk.len() <= max {
            buf.extend_from_slice(chunk);
        } else {
            fits = false;
            buf.clear();
        }
        let consumed = found.map_or(chunk.len(), |i| i + 1);
        input.consume(consumed);
        if found.is_some() {
            return Ok(Some(fits));
        }
    }
}

fn file_sha256(path: &Path) -> Result<String, IngestError> {
    let io_err = |source| IngestError::Cache {
        path: path.to_owned(),
        source,
    };
    let mut file = std::fs::File::open(path).map_err(io_err)?;
    let mut hasher = Sha256::new();
    let mut chunk = vec![0_u8; 1 << 20];
    loop {
        let n = file.read(&mut chunk).map_err(io_err)?;
        if n == 0 {
            break;
        }
        hasher.update(&chunk[..n]);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

#[derive(serde::Serialize, Deserialize)]
struct Progress {
    lines_stored: u64,
}

async fn read_progress(cache: &Cache, key: &str) -> Result<u64, IngestError> {
    Ok(cache
        .read(key)
        .await?
        .and_then(|c| serde_json::from_slice::<Progress>(&c.bytes).ok())
        .map_or(0, |p| p.lines_stored))
}

async fn write_progress(cache: &Cache, key: &str, lines_stored: u64) -> Result<(), IngestError> {
    let bytes =
        serde_json::to_vec(&Progress { lines_stored }).map_err(|source| IngestError::Json {
            what: "extcom progress".to_owned(),
            source,
        })?;
    cache.write(key, &bytes).await?;
    Ok(())
}

/// Downloads the feed at `url` into the cache, streamed to disk and
/// refused past `max` bytes; a download already there is read again
/// unless `refresh`. Returns its path and whether it came from the cache.
async fn download(
    http: &reqwest::Client,
    cache: &Cache,
    url: &str,
    max: u64,
    refresh: bool,
) -> Result<(PathBuf, bool), IngestError> {
    use tokio::io::AsyncWriteExt;

    let key = format!("extcom/feed-{}", crate::cache::short_hash(url.as_bytes()));
    let path = cache.root().join(&key);
    if !refresh && tokio::fs::try_exists(&path).await.unwrap_or(false) {
        return Ok((path, true));
    }
    let io_err = |p: &Path| {
        let p = p.to_owned();
        move |source| IngestError::Cache { path: p, source }
    };
    if let Some(dir) = path.parent() {
        tokio::fs::create_dir_all(dir).await.map_err(io_err(dir))?;
    }
    let partial = path.with_extension(format!("{}.partial", std::process::id()));
    with_retry("extcom feed", RetryPolicy::PATIENT, || async {
        let response = http
            .get(url)
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: url.to_owned(),
                source,
            })?;
        let mut response = check_status(url, response).await?;
        if response.content_length().is_some_and(|n| n > max) {
            return Err(IngestError::TooLarge {
                url: url.to_owned(),
                limit: usize::try_from(max).unwrap_or(usize::MAX),
            });
        }
        let mut file = tokio::fs::File::create(&partial)
            .await
            .map_err(io_err(&partial))?;
        let mut written: u64 = 0;
        while let Some(chunk) = response.chunk().await.map_err(|source| IngestError::Body {
            url: url.to_owned(),
            source,
        })? {
            written += u64::try_from(chunk.len()).unwrap_or(u64::MAX);
            if written > max {
                return Err(IngestError::TooLarge {
                    url: url.to_owned(),
                    limit: usize::try_from(max).unwrap_or(usize::MAX),
                });
            }
            file.write_all(&chunk).await.map_err(io_err(&partial))?;
        }
        file.sync_all().await.map_err(io_err(&partial))?;
        Ok(())
    })
    .await
    .inspect_err(|_| {
        // The partial file of a failed download is ours; a failure to
        // remove it leaves a file the next download truncates.
        let _ = std::fs::remove_file(&partial);
    })?;
    tokio::fs::rename(&partial, &path)
        .await
        .map_err(io_err(&path))?;
    Ok((path, false))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn agreement(scope: &[&str]) -> Agreement {
        Agreement::check(
            &RawAgreement {
                reference: "EXTCOM-TEST-1".into(),
                grantor: "Partner".into(),
                grantee: "Lunaway".into(),
                signed_on: NaiveDate::from_ymd_opt(2026, 1, 1),
                valid_until: None,
                scope: scope.iter().map(|s| (*s).to_owned()).collect(),
                attribution: "Source communautaire externe".into(),
                licence_url: None,
            },
            &Terms::new("EXTCOM-TEST-1", &["img.partner.example".into()]).unwrap(),
            NaiveDate::from_ymd_opt(2026, 10, 7).unwrap(),
        )
        .unwrap()
    }

    #[test]
    fn unknown_codes_are_cut_and_capped() {
        let mut notes = LineNotes::default();
        notes.unknown("service", &"é".repeat(100));
        let key = notes.unmapped.keys().next().unwrap();
        assert_eq!(
            key.len(),
            "service:".len() + 64,
            "cut at a character boundary"
        );
        for i in 0..MAX_UNMAPPED + 10 {
            notes.unknown("kind", &i.to_string());
        }
        assert_eq!(notes.unmapped.len(), MAX_UNMAPPED);
        assert_eq!(notes.unmapped_more, 11, "the rest is only counted");
    }

    #[test]
    fn a_line_longer_than_the_bound_is_skipped_whole() {
        let input = b"short\n0123456789abcdef\nnext\nlast";
        let mut r: &[u8] = input;
        let mut buf = Vec::new();
        assert_eq!(read_line(&mut r, &mut buf, 8).unwrap(), Some(true));
        assert_eq!(buf, b"short");
        assert_eq!(read_line(&mut r, &mut buf, 8).unwrap(), Some(false));
        assert!(buf.is_empty(), "nothing of a long line is kept");
        assert_eq!(read_line(&mut r, &mut buf, 8).unwrap(), Some(true));
        assert_eq!(buf, b"next");
        assert_eq!(read_line(&mut r, &mut buf, 8).unwrap(), Some(true));
        assert_eq!(buf, b"last");
        assert_eq!(read_line(&mut r, &mut buf, 8).unwrap(), None);
    }

    #[test]
    fn seasonal_periods_become_opening_hours() {
        let p = |from: &str, to: &str| FeedPeriod {
            from: from.into(),
            to: to.into(),
        };
        assert_eq!(
            opening_hours(&[p("04-01", "10-31")]).as_deref(),
            Some("Apr 01-Oct 31")
        );
        assert_eq!(
            opening_hours(&[p("12-15", "01-15"), p("13-01", "14-01")]).as_deref(),
            Some("Dec 15-Jan 15"),
            "a period may cross the new year; a malformed one is dropped"
        );
        assert_eq!(opening_hours(&[p("02-30", "03-01")]), None);
    }

    #[test]
    fn night_reports_decide_only_when_two_agree_and_outnumber() {
        let mut notes = LineNotes::default();
        let o = |status: Option<&str>, yes, no| FeedOvernight {
            status: status.map(str::to_owned),
            reports_allowed: yes,
            reports_forbidden: no,
        };
        assert_eq!(
            overnight(Some(&o(Some("tolerated"), 0, 9)), "parking", &mut notes),
            OvernightStatus::Tolerated,
            "the feed's own status wins"
        );
        assert_eq!(
            overnight(Some(&o(None, 1, 3)), "parking", &mut notes),
            OvernightStatus::Forbidden
        );
        assert_eq!(
            overnight(Some(&o(None, 2, 2)), "parking", &mut notes),
            OvernightStatus::Unknown
        );
        assert_eq!(
            overnight(None, "parking_day_only", &mut notes),
            OvernightStatus::DayOnly
        );
        assert_eq!(
            overnight(Some(&o(Some("sometimes"), 0, 0)), "parking", &mut notes),
            OvernightStatus::Unknown
        );
        assert_eq!(
            notes.unmapped,
            BTreeMap::from([("overnight:sometimes".to_owned(), 1)])
        );
    }

    #[test]
    fn photos_outside_the_agreement_s_hosts_are_dropped() {
        let a = agreement(&["places", "photos"]);
        let photo = |id: &str, url: &str| {
            serde_json::json!({
                "id": id, "url": url, "author_id": "u-1", "author": "jean@example.org"
            })
        };
        let mut notes = LineNotes::default();
        let out = photos_of(
            &[
                photo("1", "https://img.partner.example/1.jpg"),
                photo("2", "https://169.254.169.254/latest/meta-data"),
                photo("3", "http://img.partner.example/3.jpg"),
                photo("1", "https://img.partner.example/1b.jpg"),
                serde_json::json!({"id": "4", "url": 7}),
                serde_json::json!({"id": "5", "url": "https://img.partner.example/5.jpg",
                                   "deleted": true}),
            ],
            &a,
            &Limits::default(),
            &Erasures::default(),
            &mut notes,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(
            out[0].licence, "EXTCOM-TEST-1",
            "the agreement is the default licence"
        );
        assert_eq!(out[0].author, None, "an address is not a pseudonym");
        assert_eq!(out[0].author_id.as_deref(), Some("u-1"));
        assert_eq!(
            notes.photos_dropped, 4,
            "off-host, plain HTTP, a duplicate and a malformed one; a deleted one is just absent"
        );
    }

    #[test]
    fn reviews_keep_the_newest_within_the_bound() {
        let review = |id: &str, day: u32| {
            serde_json::json!({
                "id": id, "author_id": format!("u-{id}"), "author": "Ana",
                "date": format!("2026-05-{day:02}"), "lang": "es", "rating": 4.5,
                "text": "Muy tranquilo", "vehicle": "hovercraft"
            })
        };
        let limits = Limits {
            max_reviews_per_place: 2,
            ..Limits::default()
        };
        let mut notes = LineNotes::default();
        let out = reviews_of(
            &[
                review("a", 1),
                review("b", 3),
                review("c", 2),
                review("b", 4),
                serde_json::json!({"id": "d", "rating": "five"}),
            ],
            &limits,
            &Erasures::default(),
            &mut notes,
        );
        let ids: Vec<&str> = out.iter().map(|r| r.external_id.as_str()).collect();
        assert_eq!(ids, ["b", "c"]);
        assert_eq!(out[0].rating, Some(5), "half stars round up");
        assert_eq!(out[0].vehicle, None);
        assert_eq!(
            notes.reviews_dropped, 3,
            "a duplicate, a malformed one and one over the bound"
        );
        assert!(notes.unmapped.keys().all(|u| u == "vehicle:hovercraft"));
    }

    #[test]
    fn an_erased_author_s_reviews_and_photos_are_skipped() {
        let erasures = Erasures::new(
            [lunaway_domain::extcom::author_hash("u-gone")]
                .into_iter()
                .collect(),
        );
        let mut notes = LineNotes::default();
        let reviews = reviews_of(
            &[
                serde_json::json!({"id": "1", "author_id": "u-gone", "date": "2026-05-01",
                                   "rating": 3}),
                serde_json::json!({"id": "2", "author_id": "u-here", "date": "2026-05-01",
                                   "rating": 4}),
            ],
            &Limits::default(),
            &erasures,
            &mut notes,
        );
        assert_eq!(reviews.len(), 1);
        assert_eq!(reviews[0].external_id, "2");
        let photos = photos_of(
            &[
                serde_json::json!({"id": "p", "url": "https://img.partner.example/p.jpg",
                                 "author_id": " u-gone "}),
            ],
            &agreement(&["places", "photos"]),
            &Limits::default(),
            &erasures,
            &mut notes,
        );
        assert!(photos.is_empty());
        assert_eq!(notes.erased_skipped, 2);
    }

    #[test]
    fn the_stored_payload_counts_reviews_and_photos_instead_of_holding_them() {
        let raw = raw_of(serde_json::json!({
            "type": "place", "id": "1", "reviews": [{}, {}], "photos": [{}]
        }));
        assert_eq!(
            raw,
            serde_json::json!({"type": "place", "id": "1", "reviews_count": 2, "photos_count": 1})
        );
    }

    #[test]
    fn every_mapping_table_lists_a_code_once() {
        fn unique<T>(table: &[(&str, T)]) -> bool {
            let codes: BTreeSet<&str> = table.iter().map(|(c, _)| *c).collect();
            codes.len() == table.len()
        }
        assert!(unique(KINDS));
        assert!(unique(SERVICES));
        assert!(unique(ACTIVITIES));
        assert!(unique(VEHICLES));
        assert!(unique(OVERNIGHT));
        for kind in PlaceKind::ALL {
            assert!(
                KINDS
                    .iter()
                    .any(|(c, k)| *k == Some(*kind) && *c == kind.code()),
                "{kind:?}: a feed may always use the taxonomy's own code"
            );
        }
        for s in Service::ALL {
            assert_eq!(lookup(SERVICES, s.code()), Some(&[*s][..]), "{s:?}");
        }
        for a in Activity::ALL {
            assert_eq!(lookup(ACTIVITIES, a.code()), Some(&[*a][..]), "{a:?}");
        }
    }
}
