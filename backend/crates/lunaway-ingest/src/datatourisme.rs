//! DATAtourisme, the national base of the French tourist offices
//! (ADN Tourisme, Licence Ouverte 2.0): the motorhome areas
//! (`CamperVanArea`), service areas (`RVServiceArea`) and campsites
//! (`CampingAndCaravanning` and its subclasses) the offices publish, read
//! through the catalogue API (`api.datatourisme.fr/v1`, a free key sent in
//! `X-API-Key`).
//!
//! Each object becomes a record conflated with the others: a tourist
//! office's motorhome area is usually already in OpenStreetMap, and the
//! record then brings its descriptions and photos to that place. A record
//! carries no description itself: the descriptions and photos stay in its
//! raw payload, and the content worker turns them into the card's
//! content (`content::datatourisme`), so neither the change feed nor the
//! offline packs grow with them.
//!
//! The pages are read one second apart (the API allows 1 000 requests an
//! hour, about 95 are needed), following the `next` link, which must stay
//! on [`HOSTS`]; a run that reads fewer objects than the API announced
//! stops before anything is stored. The key is never logged, never cached
//! and never put in a URL: a `next` link that carries one loses it.

use std::{collections::BTreeMap, fmt, time::Duration};

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{NormalizedRecord, OvernightStatus, PlaceKind, Position, content};
use reqwest::Url;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{
    FetchedRecord, IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    web::{self, check_host},
};

/// The catalogue endpoint.
pub const CATALOG_URL: &str = "https://api.datatourisme.fr/v1/catalog";

/// Hosts the pages may come from.
pub const HOSTS: &[&str] = &["api.datatourisme.fr"];

/// The classes read: every campsite class is a subclass of
/// `CampingAndCaravanning`, motorhome areas included.
pub const FILTER: &str = "type[in]=CamperVanArea,RVServiceArea,CampingAndCaravanning";

/// The fields read; the default selection leaves out the secondary
/// photos (`hasRepresentation`).
pub const FIELDS: &str = "uuid,uri,label,type,isLocatedAt.geo,isLocatedAt.address,\
hasBeenCreatedBy,lastUpdate,lastUpdateDatatourisme,hasContact,hasMainRepresentation,\
hasRepresentation,hasDescription";

/// Objects per page, the most the API serves (2026-07-15).
pub const PAGE_SIZE: usize = 100;

/// Largest page accepted: a page of 100 objects in every language weighs
/// about 1.2 MB.
const PAGE_MAX_BYTES: usize = 32 * 1024 * 1024;

/// Pages read at most: 95 were needed on 2026-10-07 (9 389 objects).
const MAX_PAGES: usize = 400;

/// The manifest of the cached pages.
const MANIFEST_KEY: &str = "datatourisme/catalog-latest.json";

/// Metropolitan France and Corsica, south, west, north, east: the overseas
/// departments are left out, like the overseas OpenStreetMap regions.
const METROPOLE: (f64, f64, f64, f64) = (41.2, -5.5, 51.3, 9.7);

/// The free key of the API (`LUNAWAY_DATATOURISME_KEY`). Its `Debug` says
/// nothing of it, so a configuration printed in a log does not leak it.
#[derive(Clone)]
pub struct ApiKey(String);

impl ApiKey {
    /// A key, trimmed; `None` when empty.
    #[must_use]
    pub fn new(raw: &str) -> Option<Self> {
        let k = raw.trim();
        (!k.is_empty()).then(|| Self(k.to_owned()))
    }
}

impl fmt::Debug for ApiKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("ApiKey([redacted])")
    }
}

/// Where and how to read the catalogue.
#[derive(Debug, Clone)]
pub struct DatatourismeConfig {
    /// The catalogue endpoint ([`CATALOG_URL`]).
    pub url: String,
    /// Hosts the pages may come from ([`HOSTS`]).
    pub hosts: Vec<String>,
    /// The key.
    pub key: ApiKey,
    /// Objects per page.
    pub page_size: usize,
    /// Pause between two pages.
    pub pace: Duration,
    /// Retries on load shedding, per page.
    pub retry: RetryPolicy,
}

impl DatatourismeConfig {
    /// The defaults, with `key`.
    #[must_use]
    pub fn new(key: ApiKey) -> Self {
        Self {
            url: CATALOG_URL.to_owned(),
            hosts: HOSTS.iter().map(|h| (*h).to_owned()).collect(),
            key,
            page_size: PAGE_SIZE,
            pace: Duration::from_secs(1),
            retry: RetryPolicy::PATIENT,
        }
    }
}

#[derive(Debug, Deserialize)]
struct Page {
    objects: Vec<Value>,
    #[serde(default)]
    meta: Meta,
}

#[derive(Debug, Default, Deserialize)]
struct Meta {
    #[serde(default)]
    total: Option<u64>,
    #[serde(default)]
    next: Option<String>,
}

/// One page of the catalogue.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedPage {
    /// Objects the whole query matches.
    pub total: Option<u64>,
    /// The next page, without any key it carried; absent on the last one.
    pub next: Option<String>,
    /// The objects of this page.
    pub objects: Vec<Value>,
}

/// Reads one page of the catalogue.
///
/// # Errors
///
/// [`IngestError::Json`] when the page is not the API's JSON.
pub fn parse_page(body: &[u8]) -> Result<ParsedPage, IngestError> {
    let page: Page = serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: "datatourisme catalogue page".into(),
        source,
    })?;
    Ok(ParsedPage {
        total: page.meta.total,
        next: page
            .meta
            .next
            .filter(|n| !n.trim().is_empty())
            .map(|n| without_key(&n)),
        objects: page.objects,
    })
}

/// `url` without an `api_key` parameter: the API echoes the key in its
/// `next` links when a client sends it in the query string.
fn without_key(url: &str) -> String {
    let Ok(mut parsed) = Url::parse(url) else {
        return url.to_owned();
    };
    let kept: Vec<(String, String)> = parsed
        .query_pairs()
        .filter(|(k, _)| !k.eq_ignore_ascii_case("api_key"))
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();
    if kept.is_empty() {
        parsed.set_query(None);
    } else {
        parsed.query_pairs_mut().clear().extend_pairs(kept);
    }
    parsed.into()
}

/// The first page's URL.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `base` is not a URL.
pub fn first_page_url(base: &str, page_size: usize) -> Result<String, IngestError> {
    let mut url = Url::parse(base).map_err(|error| {
        tracing::error!(%error, url = base, "the configured URL does not parse");
        IngestError::UntrustedUrl {
            url: base.to_owned(),
            reason: "not a URL",
        }
    })?;
    url.query_pairs_mut()
        .append_pair("page_size", &page_size.to_string())
        .append_pair("filters", FILTER)
        .append_pair("fields", FIELDS)
        .append_pair("lang", "*");
    Ok(url.into())
}

#[derive(Debug, Serialize, Deserialize)]
struct Manifest {
    day: NaiveDate,
    pages: usize,
}

fn page_key(n: usize) -> String {
    format!("datatourisme/catalog-page-{n:03}.json")
}

/// Every object of the classes read, and when they were read.
#[derive(Debug)]
pub struct FetchedObjects {
    /// The objects, in the API's order.
    pub objects: Vec<Value>,
    /// Pages read.
    pub pages: usize,
    /// When the first page was read.
    pub fetched_at: DateTime<Utc>,
    /// Whether they came from the cache.
    pub cached: bool,
}

/// Reads the catalogue: from today's cached pages when `refresh` is false
/// and they exist, otherwise page by page from the API, caching each page
/// and then the manifest. `http` must follow no redirect
/// ([`crate::http::client_without_redirects`]): the key travels in a
/// header a redirect would carry to another host.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when a `next` link leaves the allowed
/// hosts, [`IngestError::Incomplete`] when fewer objects arrive than the
/// API announced, and the errors of the requests and of the cache.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    config: &DatatourismeConfig,
    refresh: bool,
) -> Result<FetchedObjects, IngestError> {
    let today = Utc::now().date_naive();
    if !refresh && let Some(cached) = read_cached(cache, today).await? {
        return Ok(cached);
    }
    let hosts: Vec<&str> = config.hosts.iter().map(String::as_str).collect();
    let mut url = first_page_url(&config.url, config.page_size)?;
    let mut objects = Vec::new();
    let mut total = None;
    let mut fetched_at = None;
    let mut pages = 0;
    loop {
        check_host(&url, &hosts)?;
        if pages == MAX_PAGES {
            return Err(IngestError::Implausible {
                what: format!("datatourisme: more than {MAX_PAGES} pages"),
            });
        }
        tracing::info!(page = pages + 1, "reading the datatourisme catalogue");
        let body = with_retry("datatourisme catalogue", config.retry, || async {
            let response = http
                .get(url.as_str())
                .header("X-API-Key", config.key.0.as_str())
                .header(reqwest::header::ACCEPT, "application/json")
                .send()
                .await
                .map_err(|source| IngestError::Http {
                    url: url.clone(),
                    source,
                })?;
            let response = check_status(&url, response).await?;
            read_capped(&url, response, PAGE_MAX_BYTES).await
        })
        .await?;
        let page = parse_page(&body)?;
        let at = cache.write(&page_key(pages), &body).await?;
        fetched_at.get_or_insert(at);
        total = total.or(page.total);
        pages += 1;
        let empty = page.objects.is_empty();
        objects.extend(page.objects);
        match page.next {
            Some(next) if !empty => {
                url = next;
                tokio::time::sleep(config.pace).await;
            }
            _ => break,
        }
    }
    if let Some(total) = total.and_then(|t| usize::try_from(t).ok())
        && objects.len() < total
    {
        return Err(IngestError::Incomplete {
            what: "datatourisme catalogue".into(),
            expected: total,
            got: objects.len(),
        });
    }
    let manifest = serde_json::to_vec(&Manifest { day: today, pages }).map_err(|source| {
        IngestError::Json {
            what: "datatourisme manifest".into(),
            source,
        }
    })?;
    cache.write(MANIFEST_KEY, &manifest).await?;
    Ok(FetchedObjects {
        objects,
        pages,
        fetched_at: fetched_at.unwrap_or_else(Utc::now),
        cached: false,
    })
}

async fn read_cached(cache: &Cache, day: NaiveDate) -> Result<Option<FetchedObjects>, IngestError> {
    let Some(m) = cache.read(MANIFEST_KEY).await? else {
        return Ok(None);
    };
    let Ok(manifest) = serde_json::from_slice::<Manifest>(&m.bytes) else {
        return Ok(None);
    };
    if manifest.day != day {
        return Ok(None);
    }
    let mut objects = Vec::new();
    let mut fetched_at = m.fetched_at;
    for n in 0..manifest.pages {
        let Some(page) = cache.read(&page_key(n)).await? else {
            return Ok(None);
        };
        fetched_at = fetched_at.min(page.fetched_at);
        objects.extend(parse_page(&page.bytes)?.objects);
    }
    Ok(Some(FetchedObjects {
        objects,
        pages: manifest.pages,
        fetched_at,
        cached: true,
    }))
}

/// What a class of the catalogue becomes. The first class of this table
/// an object carries decides; an object that carries a dropped class and
/// none of the kept ones is left out.
pub const CLASSES: &[(&str, Option<PlaceKind>)] = &[
    ("CamperVanArea", Some(PlaceKind::MotorhomeArea)),
    ("RVServiceArea", Some(PlaceKind::ServiceArea)),
    ("Camping", Some(PlaceKind::Campsite)),
    ("NaturalCampingArea", Some(PlaceKind::Campsite)),
    ("FarmCamping", Some(PlaceKind::Campsite)),
    // Mobile-home parks: no pitch for a motorhome.
    ("ResidentialLeisurePark", None),
    // A hiker's tent for a night, out of a vehicle's reach.
    ("BivouacArea", None),
    // A rental offered by a campsite, not a place.
    ("AccommodationProduct", None),
    ("Product", None),
    ("CampingAndCaravanning", Some(PlaceKind::Campsite)),
];

/// Classes that say nothing of an object's kind: the superclasses every
/// object of the query carries, and the facilities an office lists beside
/// the class that decides (toilets, water, a car park, a playground). All
/// the classes of the 9 389 objects read on 2026-10-07 are in this table
/// or in [`CLASSES`]; a new one fails the fixture test until it is placed.
pub const GENERIC_CLASSES: &[&str] = &[
    "PointOfInterest",
    "PlaceOfInterest",
    "Accommodation",
    "LodgingBusiness",
    "ConvenientService",
    "LocalBusiness",
    "ServiceArea",
    "ServiceProvider",
    "Store",
    "BoutiqueOrLocalShop",
    "LocalProductsShop",
    "Bakery",
    "FoodEstablishment",
    "EquipmentRentalShop",
    "CampingCar",
    "CampingPitch",
    "Caravan",
    "Hut",
    "Tent",
    "Tipi",
    "Yurt",
    "RentalAccommodation",
    "Parking",
    "PicnicArea",
    "PublicLavatories",
    "Transport",
    "WaterSource",
    "WifiHotSpot",
    "ElectricVehicleChargingPoint",
    "CarOrBikeWash",
    "PlayArea",
    "CivicStructure",
    "SportsAndLeisurePlace",
];

/// Why an object is left out.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Skip {
    /// Its classes say it is no place for a motorhome.
    Class,
    /// It has no position, or one outside metropolitan France.
    Position,
    /// It has no identifier.
    Identifier,
}

/// The kind of an object from its classes; `Err` when it is left out.
///
/// # Errors
///
/// [`Skip::Class`] when a dropped class decides, or when no class maps.
pub fn kind_of(types: &[&str]) -> Result<PlaceKind, Skip> {
    if types.contains(&"Product") || types.contains(&"AccommodationProduct") {
        return Err(Skip::Class);
    }
    for (class, kind) in CLASSES {
        if types.contains(class) {
            return kind.ok_or(Skip::Class);
        }
    }
    Err(Skip::Class)
}

fn strings(v: Option<&Value>) -> Vec<&str> {
    match v {
        Some(Value::String(s)) => vec![s.as_str()],
        Some(Value::Array(a)) => a.iter().filter_map(Value::as_str).collect(),
        _ => Vec::new(),
    }
}

fn first_object(v: Option<&Value>) -> Option<&Value> {
    match v {
        Some(Value::Array(a)) => a.first(),
        Some(o @ Value::Object(_)) => Some(o),
        _ => None,
    }
}

/// A multilingual text (`{"@fr": "...", "@en": "..."}`), by BCP 47 tag.
fn localized(v: Option<&Value>) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    if let Some(Value::Object(map)) = v {
        for (k, text) in map {
            let tag = k.trim_start_matches('@');
            let text = match text {
                Value::String(s) => s.trim().to_owned(),
                Value::Array(a) => a
                    .iter()
                    .filter_map(Value::as_str)
                    .next()
                    .unwrap_or_default()
                    .trim()
                    .to_owned(),
                _ => String::new(),
            };
            if let Some(lang) = content::content_language(tag)
                && !text.is_empty()
            {
                out.insert(lang, text);
            }
        }
    }
    out
}

/// The French text if any, else English, else the first.
fn preferred(texts: &BTreeMap<String, String>) -> Option<&str> {
    texts
        .get("fr")
        .or_else(|| texts.get("en"))
        .or_else(|| texts.values().next())
        .map(String::as_str)
}

/// What [`to_records`] made of the objects.
#[derive(Debug, Default)]
pub struct Parsed {
    /// One per object kept.
    pub records: Vec<FetchedRecord>,
    /// Objects left out, by reason.
    pub skipped: BTreeMap<Skip, usize>,
}

/// The records of the objects, each with the object as its raw payload.
#[must_use]
pub fn to_records(objects: Vec<Value>, fetched_at: DateTime<Utc>) -> Parsed {
    let mut out = Parsed::default();
    let mut seen = std::collections::BTreeSet::new();
    for o in objects {
        match record_of(&o, fetched_at) {
            Ok(r) if seen.insert(r.external_id.clone()) => {
                out.records.push(FetchedRecord { raw: o, ..r })
            }
            Ok(_) => *out.skipped.entry(Skip::Identifier).or_default() += 1,
            Err(skip) => *out.skipped.entry(skip).or_default() += 1,
        }
    }
    out
}

/// One object as a record, its raw payload left empty for the caller.
///
/// # Errors
///
/// The [`Skip`] that leaves it out.
pub fn record_of(o: &Value, fetched_at: DateTime<Utc>) -> Result<FetchedRecord, Skip> {
    let types: Vec<&str> = strings(o.get("type"));
    let kind = kind_of(&types)?;
    let uuid = o
        .get("uuid")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|u| content::lowercase_uuid(u).is_some())
        .ok_or(Skip::Identifier)?;
    let located = first_object(o.get("isLocatedAt"));
    let geo = located.and_then(|l| l.get("geo"));
    let lat = geo.and_then(|g| g.get("latitude")).and_then(Value::as_f64);
    let lon = geo.and_then(|g| g.get("longitude")).and_then(Value::as_f64);
    let (Some(lat), Some(lon)) = (lat, lon) else {
        return Err(Skip::Position);
    };
    let (s, w, n, e) = METROPOLE;
    if !(s..=n).contains(&lat) || !(w..=e).contains(&lon) {
        return Err(Skip::Position);
    }
    let position = Position::new(lat, lon).map_err(|_| Skip::Position)?;
    let mut r = NormalizedRecord::new(kind, position);
    r.name = preferred(&localized(o.get("label")))
        .map(|n| content::truncate_chars(n, content::MAX_LABEL_CHARS));
    r.overnight = match kind {
        PlaceKind::MotorhomeArea | PlaceKind::Campsite => OvernightStatus::Allowed,
        _ => OvernightStatus::Unknown,
    };
    let address = located.and_then(|l| first_object(l.get("address")));
    if let Some(a) = address {
        r.address.street = strings(a.get("streetAddress"))
            .first()
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty());
        r.address.postcode = a
            .get("postalCode")
            .and_then(Value::as_str)
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty());
        r.address.city = a
            .get("addressLocality")
            .and_then(Value::as_str)
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty());
        r.address.city_code = a
            .get("hasAddressCity")
            .and_then(|c| c.get("insee"))
            .and_then(Value::as_str)
            .map(|s| s.trim().to_owned())
            .filter(|s| s.len() == 5);
        r.address.country_code = Some("FR".into());
    }
    let contact = first_object(o.get("hasContact"));
    r.website = contact
        .map(|c| strings(c.get("homepage")))
        .unwrap_or_default()
        .into_iter()
        .find_map(web::website);
    r.phone = contact
        .map(|c| strings(c.get("telephone")))
        .unwrap_or_default()
        .first()
        .map(|p| p.trim().to_owned())
        .filter(|p| !p.is_empty());
    let external_url = o
        .get("uri")
        .and_then(Value::as_str)
        .filter(|u| u.starts_with("https://data.datatourisme.fr/"))
        .map(str::to_owned);
    Ok(FetchedRecord {
        external_id: uuid.to_ascii_lowercase(),
        external_url,
        record: r,
        raw: Value::Null,
        fetched_at,
    })
}

/// A description an object gives, in one language.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ObjectDescription {
    /// BCP 47 tag.
    pub lang: String,
    /// The text, cut to [`content::MAX_DESCRIPTION_CHARS`].
    pub text: String,
}

/// The descriptions of an object (its raw payload), one per language: the
/// long description, else the short one.
#[must_use]
pub fn descriptions_of(raw: &Value) -> Vec<ObjectDescription> {
    let Some(d) = first_object(raw.get("hasDescription")) else {
        return Vec::new();
    };
    let long = localized(d.get("description"));
    let short = localized(d.get("shortDescription"));
    let mut langs: Vec<&String> = long.keys().chain(short.keys()).collect();
    langs.sort();
    langs.dedup();
    langs
        .into_iter()
        .filter_map(|lang| {
            let text = long.get(lang).or_else(|| short.get(lang))?;
            let text = content::plain_text(text, content::MAX_DESCRIPTION_CHARS)?;
            Some(ObjectDescription {
                lang: lang.clone(),
                text,
            })
        })
        .collect()
}

/// A photo an object links to, with what its reuse requires.
#[derive(Debug, Clone, PartialEq)]
pub struct ObjectPhoto {
    /// Where the file is.
    pub url: String,
    /// The credit to show beside it.
    pub credits: String,
    /// Its title.
    pub title: Option<String>,
    /// Its licence.
    pub licence: content::Licence,
    /// The last day it may be shown, when the office says.
    pub rights_end: Option<NaiveDate>,
}

/// Why a photo of an object is left out.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum PhotoSkip {
    /// No credit: the CGU ask for it beside the picture.
    NoCredit,
    /// A licence that forbids a use (`By-NC-ND 4.0`) or that is unknown.
    Licence,
    /// Its rights end before the next weekly refresh could remove it.
    RightsEnd,
    /// Not an `https` URL.
    Url,
}

/// Days of rights a photo must have left: the weekly refresh removes it
/// within that time once they are gone.
const RIGHTS_MARGIN_DAYS: u64 = 8;

/// The photos of an object, main one first, each with its credit and
/// licence, and what was left out. The DATAtourisme CGU put every
/// published file under the Licence Ouverte unless its annotation says
/// otherwise (`isCoveredBy`, "Les droits applicables sur le media"); a
/// credit is required beside each picture and a rights end date is
/// honoured (`plan/research/46-contenus-ouverts.md`).
#[must_use]
pub fn photos_of(raw: &Value, today: NaiveDate) -> (Vec<ObjectPhoto>, Vec<PhotoSkip>) {
    let mut kept = Vec::new();
    let mut skipped = Vec::new();
    let reps = ["hasMainRepresentation", "hasRepresentation"]
        .into_iter()
        .filter_map(|k| raw.get(k).and_then(Value::as_array))
        .flatten();
    for rep in reps {
        let annotation = first_object(rep.get("hasAnnotation"));
        let credits: Vec<&str> = annotation
            .map(|a| strings(a.get("credits")))
            .unwrap_or_default();
        let credits = credits
            .iter()
            .map(|c| c.trim())
            .filter(|c| !c.is_empty())
            .collect::<Vec<_>>()
            .join(", ");
        let Some(credits) = content::plain_text(&credits, content::MAX_LABEL_CHARS) else {
            skipped.push(PhotoSkip::NoCredit);
            continue;
        };
        let covered = annotation
            .and_then(|a| a.get("isCoveredBy"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|c| !c.is_empty());
        let licence = match covered {
            None => content::accepted_licence("etalab-2.0"),
            Some(name) => content::accepted_licence(name),
        };
        let Some(licence) = licence else {
            skipped.push(PhotoSkip::Licence);
            continue;
        };
        let rights_end = annotation
            .and_then(|a| a.get("rightsEndDate"))
            .and_then(Value::as_str)
            .and_then(|d| NaiveDate::parse_from_str(d.get(..10)?, "%Y-%m-%d").ok());
        let margin = today
            .checked_add_days(chrono::Days::new(RIGHTS_MARGIN_DAYS))
            .unwrap_or(today);
        if rights_end.is_some_and(|end| end <= margin) {
            skipped.push(PhotoSkip::RightsEnd);
            continue;
        }
        let url = rep
            .get("hasRelatedResource")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .flat_map(|r| strings(r.get("locator")))
            .find(|u| u.starts_with("https://"));
        let Some(url) = url else {
            skipped.push(PhotoSkip::Url);
            continue;
        };
        let title = annotation
            .and_then(|a| preferred(&localized(a.get("title"))).map(str::to_owned))
            .and_then(|t| content::plain_text(&t, content::MAX_LABEL_CHARS));
        kept.push(ObjectPhoto {
            url: url.to_owned(),
            credits,
            title,
            licence,
            rights_end,
        });
    }
    (kept, skipped)
}

/// The tourist office that published an object (`hasBeenCreatedBy`), which
/// the licence asks to credit.
#[must_use]
pub fn publisher_of(raw: &Value) -> Option<String> {
    raw.get("hasBeenCreatedBy")
        .and_then(|c| c.get("legalName"))
        .and_then(Value::as_str)
        .and_then(|n| content::plain_text(n, content::MAX_LABEL_CHARS))
}

/// The date the producer last updated an object (`lastUpdate`), which the
/// licence asks to show.
#[must_use]
pub fn updated_on(raw: &Value) -> Option<NaiveDate> {
    raw.get("lastUpdate")
        .and_then(Value::as_str)
        .and_then(|d| NaiveDate::parse_from_str(d.get(..10)?, "%Y-%m-%d").ok())
}

/// The object's page on DATAtourisme.
#[must_use]
pub fn page_url(raw: &Value) -> Option<String> {
    raw.get("uri")
        .and_then(Value::as_str)
        .filter(|u| u.starts_with("https://data.datatourisme.fr/"))
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_key_never_shows_in_a_debug_print() {
        let config = DatatourismeConfig::new(ApiKey::new(" secret-123 ").unwrap());
        let printed = format!("{config:?}");
        assert!(!printed.contains("secret-123"), "{printed}");
        assert!(ApiKey::new("  ").is_none());
    }

    #[test]
    fn a_next_link_loses_the_key_it_echoes() {
        assert_eq!(
            without_key("https://api.datatourisme.fr/v1/catalog?api_key=abc&page=2&crs=x"),
            "https://api.datatourisme.fr/v1/catalog?page=2&crs=x"
        );
        assert_eq!(
            without_key("https://api.datatourisme.fr/v1/catalog?API_KEY=abc"),
            "https://api.datatourisme.fr/v1/catalog"
        );
    }

    #[test]
    fn classes_decide_the_kind_in_the_table_s_order() {
        assert_eq!(
            kind_of(&["CampingAndCaravanning", "CamperVanArea"]),
            Ok(PlaceKind::MotorhomeArea)
        );
        assert_eq!(
            kind_of(&["Camping", "ResidentialLeisurePark"]),
            Ok(PlaceKind::Campsite)
        );
        assert_eq!(kind_of(&["ResidentialLeisurePark"]), Err(Skip::Class));
        assert_eq!(
            kind_of(&["AccommodationProduct", "Camping", "Product"]),
            Err(Skip::Class),
            "a rental offer is not a place"
        );
        assert_eq!(kind_of(&["CampingAndCaravanning"]), Ok(PlaceKind::Campsite));
        assert_eq!(kind_of(&["PointOfInterest"]), Err(Skip::Class));
    }

    #[test]
    fn photos_need_a_credit_an_open_licence_and_rights_left() {
        let today = NaiveDate::from_ymd_opt(2026, 10, 7).unwrap();
        let raw = serde_json::json!({
            "hasMainRepresentation": [
                {"hasAnnotation": [{"credits": ["M Clavaud"], "isCoveredBy": "By-NC-ND 4.0"}],
                 "hasRelatedResource": [{"locator": ["https://cdt24.media.tourinsoft.eu/a.jpg"]}]},
                {"hasAnnotation": [{"credits": ["OT Treignac"]}],
                 "hasRelatedResource": [{"locator": ["https://cdt24.media.tourinsoft.eu/b.jpg"]}]}
            ],
            "hasRepresentation": [
                {"hasAnnotation": [{"title": {"@fr": "Sans crédit"}}],
                 "hasRelatedResource": [{"locator": ["https://cdt24.media.tourinsoft.eu/c.jpg"]}]},
                {"hasAnnotation": [{"credits": ["X"], "rightsEndDate": "2026-10-10"}],
                 "hasRelatedResource": [{"locator": ["https://cdt24.media.tourinsoft.eu/d.jpg"]}]},
                {"hasAnnotation": [{"credits": ["Y"], "isCoveredBy": "CC BY-SA 4.0"}],
                 "hasRelatedResource": [{"locator": ["http://cdt24.media.tourinsoft.eu/e.jpg"]}]},
                {"hasAnnotation": [{"credits": ["Z"], "isCoveredBy": "CC BY 4.0", "rightsEndDate": "2030-01-01"}],
                 "hasRelatedResource": [{"locator": ["https://cdt24.media.tourinsoft.eu/f.jpg"]}]}
            ]
        });
        let (kept, skipped) = photos_of(&raw, today);
        let urls: Vec<&str> = kept.iter().map(|p| p.url.as_str()).collect();
        assert_eq!(
            urls,
            [
                "https://cdt24.media.tourinsoft.eu/b.jpg",
                "https://cdt24.media.tourinsoft.eu/f.jpg"
            ]
        );
        assert_eq!(
            kept[0].licence.name, "Licence Ouverte 2.0",
            "the CGU's default"
        );
        assert_eq!(kept[1].licence.name, "CC BY 4.0");
        assert_eq!(
            skipped,
            [
                PhotoSkip::Licence,
                PhotoSkip::NoCredit,
                PhotoSkip::RightsEnd,
                PhotoSkip::Url
            ]
        );
    }

    #[test]
    fn descriptions_prefer_the_long_text_per_language() {
        let raw = serde_json::json!({"hasDescription": [{
            "description": {"@fr": "Longue <b>description</b>", "@en": ""},
            "shortDescription": {"@fr": "Courte", "@en": "Short", "@not a tag": "?"}
        }]});
        let d = descriptions_of(&raw);
        assert_eq!(
            d,
            [
                ObjectDescription {
                    lang: "en".into(),
                    text: "Short".into()
                },
                ObjectDescription {
                    lang: "fr".into(),
                    text: "Longue description".into()
                },
            ]
        );
    }
}
