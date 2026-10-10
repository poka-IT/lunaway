//! Points of interest from OpenStreetMap (ODbL 1.0, © OpenStreetMap
//! contributors), read from the same France extract as the places
//! ([`crate::osm_extract`]).
//!
//! # Tag mapping
//!
//! The first line that matches decides; an element is one point.
//!
//! | OSM | kind |
//! |---|---|
//! | `amenity=fuel` | `fuel_station` |
//! | `amenity=charging_station` | `ev_charging` |
//! | `amenity=vending_machine` + a food `vending` | `vending_*` ([`vending_kind`]) |
//! | `amenity=marketplace` | `marketplace` |
//! | `amenity=drinking_water` | `drinking_water` |
//! | `amenity=water_point` | `water_point` |
//! | `amenity=sanitary_dump_station` | `dump_station` |
//! | `amenity=toilets` | `toilets` |
//! | `amenity=shower` | `shower` |
//! | `amenity=pharmacy` | `pharmacy` |
//! | `amenity=doctors` | `doctor` |
//! | `amenity=hospital` | `hospital` |
//! | `amenity=veterinary` | `veterinary` |
//! | `amenity=atm`, or `amenity=bank` + `atm=yes` | `atm` |
//! | `amenity=post_office` | `post_office` |
//! | `amenity=recycling` + `recycling_type=centre` | `recycling_centre` |
//! | `amenity=car_wash` | `car_wash` |
//! | `amenity=laundry`, `shop=laundry` | `laundry` |
//! | `shop=supermarket` | `supermarket` |
//! | `shop=convenience` | `convenience` |
//! | `shop=bakery` | `bakery` |
//! | `shop=butcher` | `butcher` |
//! | `shop=greengrocer` | `greengrocer` |
//! | `shop=farm` | `farm_shop` |
//! | `shop=gas` | `gas_bottles` |
//! | `shop=car_repair` whose name says motorhomes (`Garage Camping-car`) | `motorhome_shop` |
//! | `shop=car_repair` | `car_repair` |
//! | `shop=caravan`, `shop=motorhome` | `motorhome_shop` |
//! | `shop=outdoor` | `outdoor_shop` |
//! | `amenity=restaurant` | `restaurant` |
//! | `amenity=cafe` | `cafe` |
//! | `amenity=fast_food` | `fast_food` |
//! | `tourism=information` + `information=office` | `tourist_office` |
//! | `tourism=viewpoint` with a `name` | `viewpoint` |
//! | `tourism=attraction` without `attraction` | `attraction` |
//! | `tourism=museum` | `museum` |
//!
//! Left out: anything `access=no|private`, a vending machine that sells no
//! food (drinks, sweets, tickets), opening hours `closed` or `off`, and the
//! recycling containers, information boards and post boxes the report
//! leaves aside (`plan/research/05-poi-sources.md`, Recommendation 1). A
//! viewpoint without a name is left out too (14,687 of the 18,820 of
//! France in Geofabrik's taginfo of 2026-10-08): a list of what lies along
//! a route would read "Viewpoint" again and again, with nothing to tell one
//! from the next. So is an attraction with an `attraction` tag,
//! which names a ride or an animal's enclosure inside a park (`animal`,
//! `roller_coaster`, `carousel`), not a stop of its own.
//!
//! Fields: `name`, `brand`, `operator`, `opening_hours`,
//! `phone`/`contact:phone`, `website`/`contact:website` (web links only),
//! `addr:*`, `wheelchair`, `check_date` (or `check_date:opening_hours`,
//! `survey:date`), `vending` (split on `;`), `payment:<method>=yes`,
//! `fuel:<fuel>=yes` and `fuel:lpg`, `self_service`, `fee`, `seasonal`,
//! `emergency`; for a vehicle wash or a garage, `motorhome` (or
//! `service:vehicle:motorhome`, `service:vehicle:caravan`), and for a wash
//! `hgv` and `maxheight`, a wash's name saying the motorhomes or the
//! lorries when its tags say nothing; the join keys `ref:FR:prix-carburants`,
//! `ref:FR:LaPoste`, `ref:FR:FINESS`, `ref:FR:SIRET`.

use std::collections::BTreeMap;

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::{
    Position,
    poi::{PoiKind, PoiRecord, names_lorries, names_motorhomes, vending_kind},
};

use crate::{
    IngestError,
    osm::{Element, Skip},
    osm_extract::{self, Selector},
    web,
};

/// One point as the adapter produced it, ready to be stored.
#[derive(Debug, Clone)]
pub struct FetchedPoi {
    /// `node/123`, `way/456`.
    pub external_id: String,
    /// Its page on openstreetmap.org.
    pub external_url: Option<String>,
    /// The normalised content.
    pub record: PoiRecord,
    /// The element as Overpass would write it, as compact JSON text: an
    /// import holds every point of a country at once, and a parsed value
    /// takes several times the room of its text. With the restaurants and
    /// the sights, the import of France peaked at 2.1 GB with parsed
    /// values, 1.1 GB with the text (2026-10-09,
    /// `plan/research/86-categories-poi.md`).
    pub raw: Box<serde_json::value::RawValue>,
    /// When the extract was read.
    pub fetched_at: DateTime<Utc>,
}

/// What a read produced.
#[derive(Debug, Default)]
pub struct ParsedPois {
    /// One point per element kept.
    pub points: Vec<FetchedPoi>,
    /// Elements dropped, with the reason.
    pub skipped: Vec<(String, Skip)>,
}

pub(crate) fn tag<'a>(tags: &'a BTreeMap<String, String>, key: &str) -> Option<&'a str> {
    tags.get(key).map(|v| v.trim()).filter(|v| !v.is_empty())
}

pub(crate) fn is(tags: &BTreeMap<String, String>, key: &str, value: &str) -> bool {
    tag(tags, key) == Some(value)
}

/// Values of a `;`-separated tag, trimmed and lower-cased.
fn values(raw: &str) -> Vec<String> {
    raw.split(';')
        .map(|v| v.trim().to_ascii_lowercase())
        .filter(|v| !v.is_empty())
        .collect()
}

/// The kind of a point, by the table of the module.
#[must_use]
pub fn kind_of(tags: &BTreeMap<String, String>) -> Option<PoiKind> {
    if let Some(amenity) = tag(tags, "amenity") {
        let kind = match amenity {
            "fuel" => Some(PoiKind::FuelStation),
            "charging_station" => Some(PoiKind::EvCharging),
            "vending_machine" => {
                let products = tag(tags, "vending").map(values).unwrap_or_default();
                let products: Vec<&str> = products.iter().map(String::as_str).collect();
                let labels: Vec<&str> = ["name", "operator", "brand"]
                    .iter()
                    .filter_map(|k| tag(tags, k))
                    .collect();
                vending_kind(&products, &labels)
            }
            "marketplace" => Some(PoiKind::Marketplace),
            "drinking_water" => Some(PoiKind::DrinkingWater),
            "water_point" => Some(PoiKind::WaterPoint),
            "sanitary_dump_station" => Some(PoiKind::DumpStation),
            "toilets" => Some(PoiKind::Toilets),
            "shower" => Some(PoiKind::Shower),
            "pharmacy" => Some(PoiKind::Pharmacy),
            "doctors" => Some(PoiKind::Doctor),
            "hospital" => Some(PoiKind::Hospital),
            "veterinary" => Some(PoiKind::Veterinary),
            "atm" => Some(PoiKind::Atm),
            "bank" if is(tags, "atm", "yes") => Some(PoiKind::Atm),
            "post_office" => Some(PoiKind::PostOffice),
            "recycling" if is(tags, "recycling_type", "centre") => Some(PoiKind::RecyclingCentre),
            "car_wash" => Some(PoiKind::CarWash),
            "laundry" => Some(PoiKind::Laundry),
            _ => None,
        };
        if kind.is_some() {
            return kind;
        }
    }
    if let Some(shop) = tag(tags, "shop") {
        let kind = match shop {
            "supermarket" => Some(PoiKind::Supermarket),
            "convenience" => Some(PoiKind::Convenience),
            "bakery" => Some(PoiKind::Bakery),
            "butcher" => Some(PoiKind::Butcher),
            "greengrocer" => Some(PoiKind::Greengrocer),
            "farm" => Some(PoiKind::FarmShop),
            "gas" => Some(PoiKind::GasBottles),
            "laundry" => Some(PoiKind::Laundry),
            // A garage whose name says it works on motorhomes is one of
            // their workshops: the same point, under the kind a traveller
            // looks for (`names_motorhomes`).
            "car_repair" if tag(tags, "name").is_some_and(names_motorhomes) => {
                Some(PoiKind::MotorhomeShop)
            }
            "car_repair" => Some(PoiKind::CarRepair),
            "caravan" | "motorhome" => Some(PoiKind::MotorhomeShop),
            "outdoor" => Some(PoiKind::OutdoorShop),
            _ => None,
        };
        if kind.is_some() {
            return kind;
        }
    }
    // After the shops: a shop that also serves food is listed under the
    // shop, what the traveller comes for. 282 bakeries of the France extract
    // of 2026-10-06 carry `amenity=cafe|restaurant|fast_food` too.
    let food = match tag(tags, "amenity") {
        Some("restaurant") => Some(PoiKind::Restaurant),
        Some("cafe") => Some(PoiKind::Cafe),
        Some("fast_food") => Some(PoiKind::FastFood),
        _ => None,
    };
    if food.is_some() {
        return food;
    }
    match tag(tags, "tourism")? {
        "information" if is(tags, "information", "office") => Some(PoiKind::TouristOffice),
        "viewpoint" if tag(tags, "name").is_some() => Some(PoiKind::Viewpoint),
        "attraction" if tag(tags, "attraction").is_none() => Some(PoiKind::Attraction),
        "museum" => Some(PoiKind::Museum),
        _ => None,
    }
}

/// Whether the point is closed to the public, or says it never opens.
pub(crate) fn left_out(tags: &BTreeMap<String, String>) -> bool {
    matches!(tag(tags, "access"), Some("no" | "private"))
        || matches!(tag(tags, "opening_hours"), Some("closed" | "off"))
}

fn yes_no(tags: &BTreeMap<String, String>, key: &str) -> Option<bool> {
    match tag(tags, key)? {
        "yes" | "only" | "designated" => Some(true),
        "no" => Some(false),
        _ => None,
    }
}

/// A date as OSM's `check_date` writes it: `2025-06-14`, or `2025-06` for
/// the first of the month.
fn check_date(raw: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(raw, "%Y-%m-%d")
        .ok()
        .or_else(|| NaiveDate::parse_from_str(&format!("{raw}-01"), "%Y-%m-%d").ok())
}

/// The suffixes of the `<prefix><suffix>=yes` keys (`payment:cash=yes`),
/// at most twelve.
fn yes_suffixes(tags: &BTreeMap<String, String>, prefix: &str) -> Vec<String> {
    let from = (
        std::ops::Bound::Included(prefix),
        std::ops::Bound::Unbounded,
    );
    tags.range::<str, _>(from)
        .take_while(|(k, _)| k.starts_with(prefix))
        .filter(|(k, v)| v.trim() == "yes" && !k[prefix.len()..].contains(':'))
        .map(|(k, _)| k[prefix.len()..].to_owned())
        .filter(|s| !s.is_empty() && s.len() <= 32)
        .take(12)
        .collect()
}

/// The first value of a reference tag, kept when it has the expected shape
/// (`len` characters of the allowed set), upper-cased.
fn reference(
    raw: Option<&str>,
    len: std::ops::RangeInclusive<usize>,
    digits_only: bool,
) -> Option<String> {
    let first = raw?.split(';').next()?.trim().to_ascii_uppercase();
    let ok = len.contains(&first.len())
        && first.chars().all(|c| {
            if digits_only {
                c.is_ascii_digit()
            } else {
                c.is_ascii_alphanumeric()
            }
        });
    ok.then_some(first)
}

/// Maps one element; `Err` says why it is left out.
///
/// # Errors
///
/// [`Skip`] when the element is not a point the layer reads, or has no
/// usable coordinates.
pub(crate) fn map_element(element: &Element) -> Result<PoiRecord, Skip> {
    let kind = kind_of(&element.tags).ok_or(Skip::OutOfScope)?;
    map_with_kind(element, kind)
}

/// The diets a menu says it caters for (OSM `diet:<diet>`).
const DIETS: &[&str] = &[
    "vegetarian",
    "vegan",
    "gluten_free",
    "halal",
    "kosher",
    "lactose_free",
];

/// Maps one element as a point of `kind`, the fields every kind may carry
/// and those of its kind; `Err` says why it is left out.
///
/// # Errors
///
/// [`Skip`] when the element is closed to the public, or has no usable
/// coordinates.
pub(crate) fn map_with_kind(element: &Element, kind: PoiKind) -> Result<PoiRecord, Skip> {
    let tags = &element.tags;
    if left_out(tags) {
        return Err(Skip::OutOfScope);
    }
    let position = match (element.lat, element.lon, element.bounds) {
        (Some(lat), Some(lon), _) => Position::new(lat, lon)?,
        // The centre of the outline at OSM's own precision (1e-7 degree),
        // so the stored JSON does not change with a rounding tail.
        (_, _, Some(b)) => Position::new(
            ((b.minlat + b.maxlat) / 2.0 * 1e7).round() / 1e7,
            ((b.minlon + b.maxlon) / 2.0 * 1e7).round() / 1e7,
        )?,
        _ => return Err(Skip::NoCoordinates),
    };
    let mut r = PoiRecord::new(kind, position);
    r.name = tag(tags, "name").map(str::to_owned);
    r.brand = tag(tags, "brand").map(str::to_owned);
    r.operator = tag(tags, "operator").map(str::to_owned);
    r.opening_hours = tag(tags, "opening_hours").map(str::to_owned);
    r.phone = ["phone", "contact:phone", "contact:mobile"]
        .iter()
        .find_map(|k| tag(tags, k))
        .map(str::to_owned);
    r.website = ["website", "contact:website", "url"]
        .iter()
        .find_map(|k| tag(tags, k).and_then(web::website));
    r.address.street = match (tag(tags, "addr:housenumber"), tag(tags, "addr:street")) {
        (Some(n), Some(s)) => Some(format!("{n} {s}")),
        (None, Some(s)) => Some(s.to_owned()),
        _ => None,
    };
    r.address.postcode = tag(tags, "addr:postcode").map(str::to_owned);
    r.address.city = tag(tags, "addr:city").map(str::to_owned);
    r.address.country_code = crate::osm::country_of(element, position, tags);
    r.wheelchair = tag(tags, "wheelchair")
        .filter(|w| matches!(*w, "yes" | "limited" | "no"))
        .map(str::to_owned);
    r.check_date = ["check_date", "check_date:opening_hours", "survey:date"]
        .iter()
        .find_map(|k| tag(tags, k).and_then(check_date));
    if kind.is_vending() {
        r.products = tag(tags, "vending")
            .map(values)
            .unwrap_or_default()
            .into_iter()
            .take(12)
            .collect();
    }
    r.payment = yes_suffixes(tags, "payment:");
    if kind == PoiKind::FuelStation {
        r.fuels = yes_suffixes(tags, "fuel:");
        r.lpg = yes_no(tags, "fuel:lpg");
    }
    r.self_service = yes_no(tags, "self_service");
    r.fee = yes_no(tags, "fee");
    r.seasonal = match tag(tags, "seasonal") {
        Some("no") => Some(false),
        Some(_) => Some(true),
        None => None,
    };
    if matches!(kind, PoiKind::Hospital | PoiKind::Clinic | PoiKind::Doctor) {
        r.emergency = yes_no(tags, "emergency");
    }
    if matches!(
        kind.category(),
        lunaway_domain::poi::PoiCategory::Food | lunaway_domain::poi::PoiCategory::Lodging
    ) {
        r.cuisine = tag(tags, "cuisine")
            .map(values)
            .unwrap_or_default()
            .into_iter()
            .filter(|c| c.len() <= 32)
            .take(6)
            .collect();
        let from = (
            std::ops::Bound::Included("diet:"),
            std::ops::Bound::Unbounded,
        );
        r.diets = tags
            .range::<str, _>(from)
            .take_while(|(k, _)| k.starts_with("diet:"))
            .filter(|(_, v)| matches!(v.trim(), "yes" | "only"))
            .filter_map(|(k, _)| DIETS.iter().find(|d| **d == &k["diet:".len()..]))
            .map(|d| (*d).to_owned())
            .collect();
        r.takeaway = yes_no(tags, "takeaway");
        r.delivery = yes_no(tags, "delivery");
        r.outdoor_seating = yes_no(tags, "outdoor_seating");
        r.reservation = tag(tags, "reservation")
            .filter(|v| matches!(*v, "yes" | "no" | "required" | "recommended" | "only"))
            .map(str::to_owned);
    }
    if kind.category() == lunaway_domain::poi::PoiCategory::Lodging {
        r.stars = tag(tags, "stars").and_then(stars);
    }
    r.internet_access = match tag(tags, "internet_access") {
        Some("wlan" | "yes" | "terminal" | "wired") => Some(true),
        Some("no") => Some(false),
        _ => None,
    };
    if matches!(
        kind,
        PoiKind::CarRepair
            | PoiKind::MotorhomeShop
            | PoiKind::Tyres
            | PoiKind::CarDealer
            | PoiKind::MotorcycleShop
    ) {
        r.vehicle_services = yes_suffixes(tags, "service:vehicle:");
    }
    if matches!(kind, PoiKind::CarWash | PoiKind::CarRepair | PoiKind::Tyres) {
        r.motorhome = [
            "motorhome",
            "service:vehicle:motorhome",
            "service:vehicle:caravan",
        ]
        .iter()
        .find_map(|k| yes_no(tags, k));
    }
    if kind == PoiKind::CarWash {
        // The tags first; a name that says it only when they say nothing
        // ("Lavage poids lourds"): 2 of the 6,775 washes of the France
        // extract of 2026-10-06 carried `hgv`, none `motorhome`.
        let name = tag(tags, "name");
        r.motorhome = r
            .motorhome
            .or_else(|| name.is_some_and(names_motorhomes).then_some(true));
        r.hgv = yes_no(tags, "hgv").or_else(|| name.is_some_and(names_lorries).then_some(true));
        r.max_height_m = tag(tags, "maxheight").and_then(crate::osm::parse_maxheight);
    }
    r.osm_ref = Some(format!("{}/{}", element.kind, element.id));
    r.refs.fuel = reference(tag(tags, "ref:FR:prix-carburants"), 5..=9, true)
        // The feed's ids are numbers: a leading zero is not part of one.
        .map(|v| v.trim_start_matches('0').to_owned())
        .filter(|v| !v.is_empty());
    r.refs.laposte = reference(tag(tags, "ref:FR:LaPoste"), 6..=6, false);
    r.refs.finess = reference(tag(tags, "ref:FR:FINESS"), 9..=9, false);
    r.refs.siret = reference(tag(tags, "ref:FR:SIRET"), 14..=14, true);
    r.refs.wikidata = tag(tags, "wikidata")
        .and_then(|v| v.split(';').next())
        .map(str::trim)
        .filter(|v| {
            v.len() <= 16
                && v.strip_prefix('Q')
                    .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
        })
        .map(str::to_owned);
    r.refs.commons = tag(tags, "wikimedia_commons")
        .and_then(commons_page)
        .or_else(|| tag(tags, "image").and_then(commons_page));
    r.refs.panoramax = tag(tags, "panoramax")
        .and_then(|v| v.split(';').next())
        .map(str::trim)
        .filter(|v| v.len() == 36 && v.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-'))
        .map(str::to_ascii_lowercase);
    Ok(r)
}

/// A hotel's stars from OSM `stars` (`3`, `3S` for superior), 1 to 5.
fn stars(raw: &str) -> Option<u8> {
    let digits: String = raw
        .trim()
        .chars()
        .take_while(char::is_ascii_digit)
        .collect();
    digits.parse::<u8>().ok().filter(|n| (1..=5).contains(n))
}

/// A Wikimedia Commons page an OSM tag names: `File:...` or `Category:...`
/// as written, or the file of a Commons URL (`image`); `None` for anything
/// else, whose licence nobody states (`docs/data-sources.md`).
fn commons_page(raw: &str) -> Option<String> {
    let first = raw.split(';').next()?.trim();
    let page = if let Some(rest) = first
        .strip_prefix("https://commons.wikimedia.org/wiki/")
        .or_else(|| first.strip_prefix("http://commons.wikimedia.org/wiki/"))
    {
        // A page copied from the browser's bar names its accents encoded
        // (`%C3%A9`); the page is its decoded name.
        percent_decoded(rest)?.replace('_', " ")
    } else {
        first.to_owned()
    };
    let ok = (page.starts_with("File:") || page.starts_with("Category:"))
        && page.chars().count() <= 240
        && !page.contains(['<', '>', '[', ']', '{', '}', '|', '#']);
    ok.then_some(page)
}

/// `text` with its `%XX` escapes decoded; `None` when an escape is broken
/// or the bytes are not UTF-8.
fn percent_decoded(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while let Some(&b) = bytes.get(i) {
        if b == b'%' {
            let hex = std::str::from_utf8(bytes.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(b);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// Maps elements (with their raw JSON) onto points.
///
/// # Errors
///
/// [`IngestError::Json`] when a raw payload does not write as JSON text,
/// which a value read from JSON or made of strings always does.
pub(crate) fn build(
    elements: impl IntoIterator<Item = (Element, serde_json::Value)>,
    fetched_at: DateTime<Utc>,
) -> Result<ParsedPois, IngestError> {
    let mut out = ParsedPois::default();
    for (element, raw) in elements {
        let id = format!("{}/{}", element.kind, element.id);
        match map_element(&element) {
            Ok(record) => {
                let raw =
                    serde_json::value::to_raw_value(&raw).map_err(|source| IngestError::Json {
                        what: format!("the payload of {id}"),
                        source,
                    })?;
                out.points.push(FetchedPoi {
                    external_url: Some(format!("https://www.openstreetmap.org/{id}")),
                    external_id: id,
                    record,
                    raw,
                    fetched_at,
                });
            }
            Err(reason) => out.skipped.push((id, reason)),
        }
    }
    Ok(out)
}

/// Maps an Overpass answer (`out tags bb`) onto points: the same mapping as
/// the extract, for a region read through Overpass or a recorded sample.
///
/// # Errors
///
/// [`IngestError`] when the body is not an Overpass JSON answer.
pub fn parse(body: &[u8], fetched_at: DateTime<Utc>) -> Result<ParsedPois, IngestError> {
    build(crate::osm::parse_response(body)?, fetched_at)
}

/// The points of interest, by [`kind_of`].
struct Pois;

/// Values of `amenity` that may make a point.
const AMENITIES: &[&str] = &[
    "fuel",
    "charging_station",
    "vending_machine",
    "marketplace",
    "drinking_water",
    "water_point",
    "sanitary_dump_station",
    "toilets",
    "shower",
    "pharmacy",
    "doctors",
    "hospital",
    "veterinary",
    "atm",
    "bank",
    "post_office",
    "recycling",
    "car_wash",
    "laundry",
    "restaurant",
    "cafe",
    "fast_food",
];

/// Values of `shop` that make a point.
const SHOPS: &[&str] = &[
    "supermarket",
    "convenience",
    "bakery",
    "butcher",
    "greengrocer",
    "farm",
    "gas",
    "laundry",
    "car_repair",
    "caravan",
    "motorhome",
    "outdoor",
];

impl Selector for Pois {
    fn candidate<'a>(&self, mut tags: impl Iterator<Item = (&'a str, &'a str)>) -> bool {
        tags.any(|(k, v)| match k {
            "amenity" => AMENITIES.contains(&v),
            "shop" => SHOPS.contains(&v),
            "tourism" => matches!(v, "information" | "viewpoint" | "attraction" | "museum"),
            _ => false,
        })
    }

    fn keep(&self, tags: &BTreeMap<String, String>) -> bool {
        kind_of(tags).is_some()
    }
}

/// Reads the extract at `path` into points, those of `area` only.
/// CPU-bound and blocking: run it on a blocking thread.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file is not a readable PBF.
pub fn read(
    path: &std::path::Path,
    fetched_at: DateTime<Utc>,
    area: osm_extract::Area,
) -> Result<ParsedPois, IngestError> {
    let (elements, outside) = osm_extract::read_selected(path, &Pois, area)?;
    let mut parsed = build(osm_extract::with_raw(elements), fetched_at)?;
    parsed
        .skipped
        .extend(outside.into_iter().map(|id| (id, Skip::OutsideArea)));
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn a_commons_page_is_read_from_its_name_or_its_address() {
        assert_eq!(
            commons_page("File:Église.jpg").as_deref(),
            Some("File:Église.jpg")
        );
        assert_eq!(
            commons_page("https://commons.wikimedia.org/wiki/File:%C3%89glise_Saint_Jean.jpg")
                .as_deref(),
            Some("File:Église Saint Jean.jpg"),
            "the page's name, as the photos' refresh asks Commons for it"
        );
        assert_eq!(
            commons_page("https://commons.wikimedia.org/wiki/File:Broken%ZZ.jpg"),
            None
        );
        assert_eq!(commons_page("Photo.jpg"), None);
    }

    #[test]
    fn every_kind_is_reachable_from_osm() {
        let reached: std::collections::BTreeSet<PoiKind> = [
            vec![("amenity", "fuel")],
            vec![("amenity", "charging_station")],
            vec![("amenity", "vending_machine"), ("vending", "pizza")],
            vec![("amenity", "vending_machine"), ("vending", "bread")],
            vec![("amenity", "vending_machine"), ("vending", "eggs;cheese")],
            vec![("amenity", "vending_machine"), ("vending", "eggs")],
            vec![("amenity", "vending_machine"), ("vending", "ice_cubes")],
            vec![("amenity", "vending_machine"), ("vending", "food")],
            vec![("amenity", "marketplace")],
            vec![("amenity", "drinking_water")],
            vec![("amenity", "water_point")],
            vec![("amenity", "sanitary_dump_station")],
            vec![("amenity", "toilets")],
            vec![("amenity", "shower")],
            vec![("amenity", "pharmacy")],
            vec![("amenity", "doctors")],
            vec![("amenity", "hospital")],
            vec![("amenity", "veterinary")],
            vec![("amenity", "atm")],
            vec![("amenity", "post_office")],
            vec![("amenity", "recycling"), ("recycling_type", "centre")],
            vec![("amenity", "car_wash")],
            vec![("shop", "laundry")],
            vec![("shop", "supermarket")],
            vec![("shop", "convenience")],
            vec![("shop", "bakery")],
            vec![("shop", "butcher")],
            vec![("shop", "greengrocer")],
            vec![("shop", "farm")],
            vec![("shop", "gas")],
            vec![("shop", "car_repair")],
            vec![("shop", "caravan")],
            vec![("shop", "outdoor")],
            vec![("amenity", "restaurant")],
            vec![("amenity", "cafe")],
            vec![("amenity", "fast_food")],
            vec![("tourism", "information"), ("information", "office")],
            vec![("tourism", "viewpoint"), ("name", "Belvédère")],
            vec![("tourism", "attraction")],
            vec![("tourism", "museum")],
        ]
        .iter()
        .filter_map(|t| kind_of(&tags(t)))
        .collect();
        assert_eq!(
            reached.len(),
            PoiKind::ALL.iter().filter(|k| k.tiled()).count(),
            "every kind of the tiles must come from a tag, or its chip stays empty; the \
             establishments come from theirs (establishments_osm)"
        );
        assert!(
            reached.iter().all(|k| k.tiled()),
            "this layer writes only kinds of the tiles"
        );
    }

    #[test]
    fn what_the_layer_leaves_out() {
        let k = |t: &[(&str, &str)]| kind_of(&tags(t));
        assert_eq!(
            k(&[("amenity", "vending_machine"), ("vending", "drinks")]),
            None
        );
        assert_eq!(
            k(&[("amenity", "bank")]),
            None,
            "a bank without a cash machine"
        );
        assert_eq!(
            k(&[("amenity", "bank"), ("atm", "yes")]),
            Some(PoiKind::Atm)
        );
        assert_eq!(
            k(&[("amenity", "recycling"), ("recycling_type", "container")]),
            None
        );
        assert_eq!(
            k(&[("tourism", "information"), ("information", "board")]),
            None
        );
        assert_eq!(k(&[("amenity", "post_box")]), None);
        assert_eq!(
            k(&[("amenity", "fuel"), ("shop", "gas")]),
            Some(PoiKind::FuelStation),
            "a fuel station that sells gas bottles is a fuel station"
        );
        assert_eq!(
            k(&[("tourism", "viewpoint")]),
            None,
            "a viewpoint without a name"
        );
        assert_eq!(
            k(&[("tourism", "viewpoint"), ("name", "  ")]),
            None,
            "a name of spaces is no name"
        );
        assert_eq!(
            k(&[("tourism", "attraction"), ("attraction", "animal")]),
            None,
            "an enclosure inside a zoo"
        );
        assert_eq!(
            k(&[("tourism", "attraction"), ("historic", "castle")]),
            Some(PoiKind::Attraction)
        );
        assert_eq!(
            k(&[("amenity", "restaurant"), ("tourism", "attraction")]),
            Some(PoiKind::Restaurant),
            "a famous restaurant is a restaurant"
        );
        assert_eq!(
            k(&[("shop", "bakery"), ("amenity", "cafe")]),
            Some(PoiKind::Bakery),
            "a bakery that serves coffee stays under the bakeries"
        );
        assert_eq!(
            k(&[("shop", "pastry"), ("amenity", "cafe")]),
            Some(PoiKind::Cafe),
            "a shop the layer does not read leaves the café its point"
        );

        let element = |t: &[(&str, &str)]| Element {
            kind: "node".into(),
            id: 1,
            lat: Some(47.0),
            lon: Some(-0.5),
            bounds: None,
            tags: tags(t),
            country: None,
        };
        assert!(map_element(&element(&[("amenity", "toilets"), ("access", "private")])).is_err());
        assert!(map_element(&element(&[("shop", "bakery"), ("opening_hours", "closed")])).is_err());
    }

    #[test]
    fn fields_and_join_keys_are_read() {
        let e = Element {
            kind: "way".into(),
            id: 42,
            lat: None,
            lon: None,
            bounds: Some(crate::osm::Bounds {
                minlat: 47.0,
                minlon: -0.6,
                maxlat: 47.002,
                maxlon: -0.598,
            }),
            tags: tags(&[
                ("amenity", "fuel"),
                ("name", "Total Access"),
                ("brand", "TotalEnergies"),
                ("opening_hours", "24/7"),
                ("fuel:diesel", "yes"),
                ("fuel:lpg", "yes"),
                ("fuel:e85", "no"),
                ("payment:cards", "yes"),
                ("payment:cash", "no"),
                ("ref:FR:prix-carburants", "01120009"),
                ("check_date", "2025-06"),
                ("website", "javascript:alert(1)"),
            ]),
            country: None,
        };
        let r = map_element(&e).unwrap();
        assert_eq!(r.kind, PoiKind::FuelStation);
        assert_eq!(r.position, Position::new(47.001, -0.599).unwrap());
        assert_eq!(r.fuels, vec!["diesel", "lpg"]);
        assert_eq!(r.lpg, Some(true));
        assert_eq!(r.payment, vec!["cards"]);
        assert_eq!(
            r.refs.fuel.as_deref(),
            Some("1120009"),
            "the feed's ids have no leading zero"
        );
        assert_eq!(r.check_date, NaiveDate::from_ymd_opt(2025, 6, 1));
        assert_eq!(r.website, None, "only web links");
        assert_eq!(r.osm_ref.as_deref(), Some("way/42"));
        let post = Element {
            tags: tags(&[("amenity", "post_office"), ("ref:FR:LaPoste", "13905d")]),
            country: None,
            ..e.clone()
        };
        assert_eq!(
            map_element(&post).unwrap().refs.laposte.as_deref(),
            Some("13905D")
        );
        let pharmacy = Element {
            tags: tags(&[
                ("amenity", "pharmacy"),
                ("ref:FR:FINESS", "860000017;2A0000123"),
            ]),
            ..e
        };
        assert_eq!(
            map_element(&pharmacy).unwrap().refs.finess.as_deref(),
            Some("860000017"),
            "the first of a list"
        );
    }

    #[test]
    fn a_wash_says_which_vehicles_it_takes() {
        let element = |t: &[(&str, &str)]| Element {
            kind: "node".into(),
            id: 7,
            lat: Some(47.0),
            lon: Some(-0.5),
            bounds: None,
            tags: tags(t),
            country: None,
        };
        let wash = map_element(&element(&[
            ("amenity", "car_wash"),
            ("motorhome", "yes"),
            ("hgv", "designated"),
            ("maxheight", "4.2"),
        ]))
        .unwrap();
        assert_eq!(wash.motorhome, Some(true));
        assert_eq!(wash.hgv, Some(true));
        assert_eq!(wash.max_height_m, Some(4.2));
        let car_only =
            map_element(&element(&[("amenity", "car_wash"), ("motorhome", "no")])).unwrap();
        assert_eq!(car_only.motorhome, Some(false), "a no is kept: it is said");
        assert_eq!(car_only.hgv, None, "nothing said is unknown, not no");
        let named = map_element(&element(&[
            ("amenity", "car_wash"),
            ("name", "Lavage poids lourds"),
        ]))
        .unwrap();
        assert_eq!(
            named.hgv,
            Some(true),
            "the name says it when the tags do not"
        );
        let tagged = map_element(&element(&[
            ("amenity", "car_wash"),
            ("name", "Truck wash"),
            ("hgv", "no"),
        ]))
        .unwrap();
        assert_eq!(tagged.hgv, Some(false), "the tags win over the name");
        assert_eq!(
            kind_of(&tags(&[
                ("shop", "car_repair"),
                ("name", "Garage Camping-car")
            ])),
            Some(PoiKind::MotorhomeShop),
            "a garage named for motorhomes is their workshop, one point"
        );
        assert_eq!(
            kind_of(&tags(&[
                ("shop", "car_repair"),
                ("name", "Garage du Camping")
            ])),
            Some(PoiKind::CarRepair)
        );
        let garage = map_element(&element(&[
            ("shop", "car_repair"),
            ("service:vehicle:caravan", "yes"),
            ("hgv", "yes"),
        ]))
        .unwrap();
        assert_eq!(garage.motorhome, Some(true));
        assert_eq!(garage.hgv, None, "only a wash says which lorries it takes");
        let shop = map_element(&element(&[("shop", "supermarket"), ("motorhome", "yes")])).unwrap();
        assert_eq!(
            shop.motorhome, None,
            "a supermarket's car park is not the shop"
        );
    }
}
