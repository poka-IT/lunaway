//! Establishments from OpenStreetMap (ODbL 1.0, © OpenStreetMap
//! contributors): every named shop, service, craftsman's workshop, health
//! practice, place to stay and leisure venue the map's search finds, read
//! from the same extracts as the points of interest
//! (`plan/research/98-recherche-commerces.md`). They become points of
//! interest with `in_tiles` false: the map tiles never carry them.
//!
//! An element the points of interest read ([`crate::poi_osm::kind_of`]) is
//! a point of interest, never an establishment; the rest is read here when
//! it bears a name (or a brand) and a key of [`TAGS`]:
//!
//! - every `shop=*` (a value of no kind of [`TAGS`] is the generic
//!   [`PoiKind::Shop`]), but an empty one (`vacant`, `no`, `disused`);
//! - the `amenity=*`, `healthcare=*`, `tourism=*` and `leisure=*` values a
//!   traveller looks for: food and drink, banks, health practices, places
//!   to stay, leisure venues, town halls, libraries, police;
//! - of the craftsmen, the workshops that sell to the public (a winery, a
//!   brewery, a shoemaker, a potter), never the trades that come to a home
//!   (builders, plumbers, electricians), whose address is often the
//!   craftsman's own;
//! - of the offices, only those with a shop window (estate agents, insurers,
//!   travel agents, coworking spaces): no private office.
//!
//! Left out like the points of interest: anything `access=no|private`, or
//! `opening_hours=closed|off`; and here also what serves customers only
//! (`access=customers`, a hotel's pool), and an unnamed element: the search
//! finds an establishment by its name or by its kind near the map, and an
//! unnamed one would read "Shop" in a list.
//!
//! Fields: those of the points of interest ([`crate::poi_osm`]), with the
//! cuisine, diets, takeaway, delivery, terrace and booking of the places
//! to eat and stay, the stars of a hotel, the internet access, and what a
//! garage works on.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use lunaway_domain::poi::PoiKind;

use crate::{
    IngestError,
    osm::{Element, Skip},
    osm_extract::{self, Selector},
    poi_osm::{FetchedPoi, ParsedPois, is, map_with_kind, tag},
};

/// The keys an establishment is read from, in the order they decide: a
/// shop that also serves coffee is a shop, a hotel with a bar is a hotel,
/// a practice that is also a craftsman's is the practice.
const KEYS: &[&str] = &[
    "shop",
    "tourism",
    "amenity",
    "healthcare",
    "craft",
    "office",
    "leisure",
];

/// The kind of each `key=value` the establishments read, sorted by key
/// then value (a test holds them so): the table of
/// `plan/research/98-recherche-commerces.md`, section 2.
pub const TAGS: &[(&str, &str, PoiKind)] = &[
    ("amenity", "animal_boarding", PoiKind::AnimalBoarding),
    ("amenity", "arts_centre", PoiKind::ArtsCentre),
    ("amenity", "bank", PoiKind::Bank),
    ("amenity", "bar", PoiKind::Bar),
    ("amenity", "bicycle_rental", PoiKind::BicycleRental),
    ("amenity", "biergarten", PoiKind::Pub),
    ("amenity", "boat_rental", PoiKind::BoatRental),
    ("amenity", "bureau_de_change", PoiKind::MoneyExchange),
    ("amenity", "car_rental", PoiKind::CarRental),
    ("amenity", "casino", PoiKind::Casino),
    ("amenity", "cinema", PoiKind::Cinema),
    ("amenity", "clinic", PoiKind::Clinic),
    ("amenity", "concert_hall", PoiKind::Theatre),
    ("amenity", "conference_centre", PoiKind::EventsVenue),
    ("amenity", "coworking_space", PoiKind::Coworking),
    ("amenity", "dentist", PoiKind::Dentist),
    ("amenity", "driving_school", PoiKind::DrivingSchool),
    ("amenity", "events_venue", PoiKind::EventsVenue),
    ("amenity", "exhibition_centre", PoiKind::EventsVenue),
    ("amenity", "ferry_terminal", PoiKind::FerryTerminal),
    ("amenity", "food_court", PoiKind::FastFood),
    ("amenity", "ice_cream", PoiKind::IceCream),
    ("amenity", "internet_cafe", PoiKind::InternetCafe),
    ("amenity", "library", PoiKind::Library),
    ("amenity", "nightclub", PoiKind::Nightclub),
    ("amenity", "police", PoiKind::Police),
    ("amenity", "pub", PoiKind::Pub),
    ("amenity", "public_bath", PoiKind::Spa),
    ("amenity", "theatre", PoiKind::Theatre),
    ("amenity", "townhall", PoiKind::Townhall),
    ("amenity", "vehicle_inspection", PoiKind::VehicleInspection),
    ("craft", "basket_maker", PoiKind::Craft),
    ("craft", "beekeeper", PoiKind::Beekeeper),
    ("craft", "blacksmith", PoiKind::Craft),
    ("craft", "bookbinder", PoiKind::Craft),
    ("craft", "brewery", PoiKind::Brewery),
    ("craft", "candlemaker", PoiKind::Craft),
    ("craft", "caterer", PoiKind::Deli),
    ("craft", "cheese", PoiKind::Craft),
    ("craft", "clockmaker", PoiKind::RepairShop),
    ("craft", "confectionery", PoiKind::Craft),
    ("craft", "distillery", PoiKind::Distillery),
    ("craft", "dressmaker", PoiKind::Tailor),
    ("craft", "electronics_repair", PoiKind::RepairShop),
    ("craft", "glassblower", PoiKind::Craft),
    ("craft", "hairdresser", PoiKind::Hairdresser),
    ("craft", "handicraft", PoiKind::Craft),
    ("craft", "jeweller", PoiKind::Jewellery),
    ("craft", "key_cutter", PoiKind::Locksmith),
    ("craft", "leather", PoiKind::Craft),
    ("craft", "locksmith", PoiKind::Locksmith),
    ("craft", "luthier", PoiKind::Craft),
    ("craft", "photographer", PoiKind::Photographer),
    ("craft", "pottery", PoiKind::Craft),
    ("craft", "saddler", PoiKind::Craft),
    ("craft", "sculptor", PoiKind::Craft),
    ("craft", "shoemaker", PoiKind::ShoeRepair),
    ("craft", "soap", PoiKind::Craft),
    ("craft", "tailor", PoiKind::Tailor),
    ("craft", "upholsterer", PoiKind::Craft),
    ("craft", "watchmaker", PoiKind::RepairShop),
    ("craft", "weaver", PoiKind::Craft),
    ("craft", "winery", PoiKind::Winery),
    ("craft", "woodcarver", PoiKind::Craft),
    ("healthcare", "alternative", PoiKind::AlternativeMedicine),
    ("healthcare", "audiologist", PoiKind::HearingAids),
    ("healthcare", "blood_donation", PoiKind::Clinic),
    ("healthcare", "centre", PoiKind::Clinic),
    ("healthcare", "clinic", PoiKind::Clinic),
    ("healthcare", "counselling", PoiKind::Psychologist),
    ("healthcare", "dentist", PoiKind::Dentist),
    ("healthcare", "dialysis", PoiKind::Clinic),
    ("healthcare", "doctor", PoiKind::Doctor),
    ("healthcare", "hospital", PoiKind::Hospital),
    ("healthcare", "laboratory", PoiKind::Laboratory),
    ("healthcare", "midwife", PoiKind::Midwife),
    ("healthcare", "nurse", PoiKind::Nurse),
    ("healthcare", "optometrist", PoiKind::Optician),
    ("healthcare", "pharmacy", PoiKind::Pharmacy),
    ("healthcare", "physiotherapist", PoiKind::Physiotherapist),
    ("healthcare", "podiatrist", PoiKind::Podiatrist),
    ("healthcare", "psychotherapist", PoiKind::Psychologist),
    ("healthcare", "speech_therapist", PoiKind::SpeechTherapist),
    ("leisure", "adult_gaming_centre", PoiKind::Casino),
    ("leisure", "amusement_arcade", PoiKind::AmusementArcade),
    ("leisure", "bowling_alley", PoiKind::BowlingAlley),
    ("leisure", "dance", PoiKind::Dance),
    ("leisure", "escape_game", PoiKind::EscapeGame),
    ("leisure", "fitness_centre", PoiKind::FitnessCentre),
    ("leisure", "garden", PoiKind::Park),
    ("leisure", "golf_course", PoiKind::GolfCourse),
    ("leisure", "horse_riding", PoiKind::HorseRiding),
    ("leisure", "ice_rink", PoiKind::IceRink),
    ("leisure", "marina", PoiKind::Marina),
    ("leisure", "miniature_golf", PoiKind::MiniatureGolf),
    ("leisure", "nature_reserve", PoiKind::NatureReserve),
    ("leisure", "park", PoiKind::Park),
    ("leisure", "sauna", PoiKind::Spa),
    ("leisure", "sports_centre", PoiKind::SportsCentre),
    ("leisure", "sports_hall", PoiKind::SportsCentre),
    ("leisure", "stadium", PoiKind::SportsCentre),
    ("leisure", "swimming_pool", PoiKind::SwimmingPool),
    ("leisure", "water_park", PoiKind::WaterPark),
    ("office", "coworking", PoiKind::Coworking),
    ("office", "estate_agent", PoiKind::EstateAgent),
    ("office", "insurance", PoiKind::Insurance),
    ("office", "travel_agent", PoiKind::TravelAgency),
    ("shop", "agrarian", PoiKind::GardenCentre),
    ("shop", "alcohol", PoiKind::WineShop),
    ("shop", "antiques", PoiKind::SecondHand),
    ("shop", "appliance", PoiKind::Electronics),
    ("shop", "art", PoiKind::ArtShop),
    ("shop", "baby_goods", PoiKind::BabyGoods),
    ("shop", "bag", PoiKind::Accessories),
    ("shop", "bathroom_furnishing", PoiKind::Home),
    ("shop", "beauty", PoiKind::Beauty),
    ("shop", "bed", PoiKind::Home),
    ("shop", "beverages", PoiKind::Beverages),
    ("shop", "bicycle", PoiKind::BicycleShop),
    ("shop", "boat", PoiKind::BoatShop),
    ("shop", "books", PoiKind::Books),
    ("shop", "boutique", PoiKind::Clothes),
    ("shop", "building_materials", PoiKind::Hardware),
    ("shop", "camera", PoiKind::Electronics),
    ("shop", "car", PoiKind::CarDealer),
    ("shop", "car_parts", PoiKind::CarParts),
    ("shop", "car_rental", PoiKind::CarRental),
    ("shop", "carpet", PoiKind::Home),
    ("shop", "charity", PoiKind::SecondHand),
    ("shop", "cheese", PoiKind::Cheese),
    ("shop", "chemist", PoiKind::Cosmetics),
    ("shop", "chocolate", PoiKind::Confectionery),
    ("shop", "clothes", PoiKind::Clothes),
    ("shop", "coffee", PoiKind::TeaCoffee),
    ("shop", "collector", PoiKind::ArtShop),
    ("shop", "computer", PoiKind::Electronics),
    ("shop", "confectionery", PoiKind::Confectionery),
    ("shop", "copyshop", PoiKind::Copyshop),
    ("shop", "cosmetics", PoiKind::Cosmetics),
    ("shop", "craft", PoiKind::ArtShop),
    ("shop", "curtain", PoiKind::Home),
    ("shop", "dairy", PoiKind::Cheese),
    ("shop", "deli", PoiKind::Deli),
    ("shop", "department_store", PoiKind::DepartmentStore),
    ("shop", "discount", PoiKind::VarietyStore),
    ("shop", "doityourself", PoiKind::Hardware),
    ("shop", "dry_cleaning", PoiKind::DryCleaning),
    ("shop", "e-cigarette", PoiKind::Tobacco),
    ("shop", "electrical", PoiKind::Hardware),
    ("shop", "electronics", PoiKind::Electronics),
    ("shop", "estate_agent", PoiKind::EstateAgent),
    ("shop", "fabric", PoiKind::Fabric),
    ("shop", "fashion", PoiKind::Clothes),
    ("shop", "fashion_accessories", PoiKind::Accessories),
    ("shop", "fireplace", PoiKind::Home),
    ("shop", "fishing", PoiKind::FishingHunting),
    ("shop", "flooring", PoiKind::Home),
    ("shop", "florist", PoiKind::Florist),
    ("shop", "frame", PoiKind::ArtShop),
    ("shop", "frozen_food", PoiKind::FrozenFood),
    ("shop", "funeral_directors", PoiKind::FuneralDirectors),
    ("shop", "furniture", PoiKind::Home),
    ("shop", "games", PoiKind::Toys),
    ("shop", "garden_centre", PoiKind::GardenCentre),
    ("shop", "general", PoiKind::Convenience),
    ("shop", "gift", PoiKind::Gift),
    ("shop", "grocery", PoiKind::Convenience),
    ("shop", "haberdashery", PoiKind::Fabric),
    ("shop", "hairdresser", PoiKind::Hairdresser),
    ("shop", "hairdresser_supply", PoiKind::Cosmetics),
    ("shop", "hardware", PoiKind::Hardware),
    ("shop", "health_food", PoiKind::OrganicShop),
    ("shop", "hearing_aids", PoiKind::HearingAids),
    ("shop", "herbalist", PoiKind::Cosmetics),
    ("shop", "hifi", PoiKind::Electronics),
    ("shop", "household_linen", PoiKind::Home),
    ("shop", "houseware", PoiKind::Home),
    ("shop", "hunting", PoiKind::FishingHunting),
    ("shop", "ice_cream", PoiKind::IceCream),
    ("shop", "interior_decoration", PoiKind::Home),
    ("shop", "jewelry", PoiKind::Jewellery),
    ("shop", "kiosk", PoiKind::Newsagent),
    ("shop", "kitchen", PoiKind::Home),
    ("shop", "leather", PoiKind::Accessories),
    ("shop", "lighting", PoiKind::Home),
    ("shop", "locksmith", PoiKind::Locksmith),
    ("shop", "lottery", PoiKind::Newsagent),
    ("shop", "mall", PoiKind::DepartmentStore),
    ("shop", "massage", PoiKind::Massage),
    ("shop", "medical_supply", PoiKind::MedicalSupply),
    ("shop", "mobile_phone", PoiKind::Electronics),
    ("shop", "model", PoiKind::Toys),
    ("shop", "motorcycle", PoiKind::MotorcycleShop),
    ("shop", "motorcycle_repair", PoiKind::MotorcycleShop),
    ("shop", "music", PoiKind::MusicShop),
    ("shop", "musical_instrument", PoiKind::MusicShop),
    ("shop", "nails", PoiKind::Beauty),
    ("shop", "newsagent", PoiKind::Newsagent),
    ("shop", "nuts", PoiKind::Deli),
    ("shop", "optician", PoiKind::Optician),
    ("shop", "organic", PoiKind::OrganicShop),
    ("shop", "paint", PoiKind::Hardware),
    ("shop", "pasta", PoiKind::Deli),
    ("shop", "pastry", PoiKind::Pastry),
    ("shop", "perfumery", PoiKind::Cosmetics),
    ("shop", "pet", PoiKind::PetShop),
    ("shop", "pet_grooming", PoiKind::PetGrooming),
    ("shop", "photo", PoiKind::Photographer),
    ("shop", "photo_studio", PoiKind::Photographer),
    ("shop", "piercing", PoiKind::Tattoo),
    ("shop", "pottery", PoiKind::ArtShop),
    ("shop", "rental", PoiKind::Rental),
    ("shop", "repair", PoiKind::RepairShop),
    ("shop", "scuba_diving", PoiKind::Sports),
    ("shop", "seafood", PoiKind::Seafood),
    ("shop", "second_hand", PoiKind::SecondHand),
    ("shop", "sewing", PoiKind::Fabric),
    ("shop", "shoe_repair", PoiKind::ShoeRepair),
    ("shop", "shoes", PoiKind::Shoes),
    ("shop", "ski", PoiKind::Sports),
    ("shop", "souvenir", PoiKind::Gift),
    ("shop", "spa", PoiKind::Spa),
    ("shop", "spices", PoiKind::Deli),
    ("shop", "sports", PoiKind::Sports),
    ("shop", "stationery", PoiKind::Stationery),
    ("shop", "storage_rental", PoiKind::StorageRental),
    ("shop", "surf", PoiKind::Sports),
    ("shop", "tailor", PoiKind::Tailor),
    ("shop", "tattoo", PoiKind::Tattoo),
    ("shop", "tea", PoiKind::TeaCoffee),
    ("shop", "telecommunication", PoiKind::Electronics),
    ("shop", "tiles", PoiKind::Hardware),
    ("shop", "tobacco", PoiKind::Tobacco),
    ("shop", "tool_hire", PoiKind::Rental),
    ("shop", "toys", PoiKind::Toys),
    ("shop", "trade", PoiKind::Hardware),
    ("shop", "travel_agency", PoiKind::TravelAgency),
    ("shop", "tyres", PoiKind::Tyres),
    ("shop", "variety_store", PoiKind::VarietyStore),
    ("shop", "video_games", PoiKind::Electronics),
    ("shop", "watches", PoiKind::Jewellery),
    ("shop", "weapons", PoiKind::FishingHunting),
    ("shop", "window_blind", PoiKind::Home),
    ("shop", "wine", PoiKind::WineShop),
    ("shop", "wool", PoiKind::Fabric),
    ("tourism", "alpine_hut", PoiKind::MountainHut),
    ("tourism", "apartment", PoiKind::HolidayRental),
    ("tourism", "aquarium", PoiKind::Zoo),
    ("tourism", "chalet", PoiKind::HolidayRental),
    ("tourism", "gallery", PoiKind::Gallery),
    ("tourism", "guest_house", PoiKind::GuestHouse),
    ("tourism", "hostel", PoiKind::Hostel),
    ("tourism", "hotel", PoiKind::Hotel),
    ("tourism", "motel", PoiKind::Hotel),
    ("tourism", "theme_park", PoiKind::ThemePark),
    ("tourism", "wilderness_hut", PoiKind::MountainHut),
    ("tourism", "zoo", PoiKind::Zoo),
];

/// `shop` values that say there is no shop.
const NO_SHOP: &[&str] = &["vacant", "no", "disused", "closed", "empty", "abandoned"];

/// The kind `key=value` names, by [`TAGS`].
fn kind_in_table(key: &str, value: &str) -> Option<PoiKind> {
    TAGS.binary_search_by(|(k, v, _)| (*k, *v).cmp(&(key, value)))
        .ok()
        .map(|i| TAGS[i].2)
}

/// The kind of an establishment, by the rules of the module: `None` for a
/// point of interest (it stays one), an element of no kind read here, or
/// one without a name or a brand.
#[must_use]
pub fn kind_of(tags: &BTreeMap<String, String>) -> Option<PoiKind> {
    if crate::poi_osm::kind_of(tags).is_some() {
        return None;
    }
    if tag(tags, "name").is_none() && tag(tags, "brand").is_none() {
        return None;
    }
    if is(tags, "access", "customers") {
        return None;
    }
    for key in KEYS {
        let Some(value) = tag(tags, key) else {
            continue;
        };
        // `shop=bakery;cafe`: the first value decides.
        let value = value.split(';').next().unwrap_or(value).trim();
        if let Some(kind) = kind_in_table(key, value) {
            return Some(kind);
        }
        if *key == "shop" && !NO_SHOP.contains(&value) {
            return Some(PoiKind::Shop);
        }
    }
    None
}

/// Maps one element; `Err` says why it is left out.
///
/// # Errors
///
/// [`Skip`] when the element is not an establishment, or has no usable
/// coordinates.
pub(crate) fn map_element(element: &Element) -> Result<lunaway_domain::poi::PoiRecord, Skip> {
    let kind = kind_of(&element.tags).ok_or(Skip::OutOfScope)?;
    map_with_kind(element, kind)
}

/// Maps elements (with their raw JSON) onto establishments.
///
/// # Errors
///
/// [`IngestError::Json`] when a raw payload does not write as JSON text.
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

/// The establishments, by [`kind_of`].
struct Establishments;

impl Selector for Establishments {
    fn candidate<'a>(&self, mut tags: impl Iterator<Item = (&'a str, &'a str)>) -> bool {
        tags.any(|(k, v)| {
            KEYS.contains(&k)
                && (k == "shop"
                    || kind_in_table(k, v.split(';').next().unwrap_or(v).trim()).is_some())
        })
    }

    fn keep(&self, tags: &BTreeMap<String, String>) -> bool {
        kind_of(tags).is_some()
    }
}

/// Reads the extract at `path` into establishments, those of `area` only.
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
    let (elements, outside) = osm_extract::read_selected(path, &Establishments, area)?;
    let mut parsed = build(osm_extract::with_raw(elements), fetched_at)?;
    parsed
        .skipped
        .extend(outside.into_iter().map(|id| (id, Skip::OutsideArea)));
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use lunaway_domain::poi::PoiCategory;

    use super::*;

    fn tags(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    fn element(pairs: &[(&str, &str)]) -> Element {
        Element {
            kind: "node".into(),
            id: 98,
            lat: Some(45.76),
            lon: Some(4.83),
            bounds: None,
            tags: tags(pairs),
            country: None,
        }
    }

    #[test]
    fn the_table_is_sorted_and_names_each_tag_once() {
        assert!(
            TAGS.windows(2).all(|w| (w[0].0, w[0].1) < (w[1].0, w[1].1)),
            "the lookup is a binary search"
        );
        for (key, _, _) in TAGS {
            assert!(
                KEYS.contains(key),
                "{key}: a key the reader does not look at"
            );
        }
    }

    #[test]
    fn every_establishment_kind_comes_from_a_tag() {
        let reached: std::collections::BTreeSet<PoiKind> = TAGS
            .iter()
            .map(|(_, _, k)| *k)
            .chain([PoiKind::Shop])
            .collect();
        for k in PoiKind::ALL {
            if !k.tiled() {
                assert!(
                    reached.contains(k),
                    "{k}: no tag makes it, the search would never find one"
                );
            }
        }
    }

    #[test]
    fn named_shops_and_services_are_read_points_of_interest_are_not() {
        let k = |t: &[(&str, &str)]| kind_of(&tags(t));
        assert_eq!(
            k(&[("shop", "hairdresser"), ("name", "Coiff'Annie")]),
            Some(PoiKind::Hairdresser)
        );
        assert_eq!(
            k(&[("shop", "hairdresser")]),
            None,
            "an unnamed one would read Hairdresser in a list"
        );
        assert_eq!(
            k(&[("shop", "hairdresser"), ("brand", "Franck Provost")]),
            Some(PoiKind::Hairdresser),
            "a brand names it"
        );
        assert_eq!(
            k(&[("amenity", "restaurant"), ("name", "Chez Marcel")]),
            None,
            "a restaurant is a point of interest of the tiles, read by the other import"
        );
        assert_eq!(
            k(&[("shop", "bakery"), ("name", "Paul")]),
            None,
            "so is a bakery"
        );
        assert_eq!(
            k(&[("shop", "grocery"), ("name", "Épicerie du coin")]),
            Some(PoiKind::Convenience),
            "a kind of the tiles, read here and kept out of them"
        );
        assert_eq!(
            k(&[("healthcare", "doctor"), ("name", "Dr Martin")]),
            Some(PoiKind::Doctor)
        );
        assert_eq!(
            k(&[("shop", "kitesurf"), ("name", "Kite Shop")]),
            Some(PoiKind::Shop),
            "any other shop is a shop"
        );
        assert_eq!(
            k(&[("shop", "vacant"), ("name", "Ancienne boulangerie")]),
            None
        );
        assert_eq!(
            k(&[("craft", "plumber"), ("name", "Plomberie Dupont")]),
            None,
            "a trade that comes to a home: its address is often the craftsman's own"
        );
        assert_eq!(
            k(&[("craft", "winery"), ("name", "Domaine des Tours")]),
            Some(PoiKind::Winery)
        );
        assert_eq!(
            k(&[("office", "company"), ("name", "Acme SAS")]),
            None,
            "no private office"
        );
        assert_eq!(
            k(&[("office", "estate_agent"), ("name", "Agence du Centre")]),
            Some(PoiKind::EstateAgent)
        );
        assert_eq!(
            k(&[
                ("leisure", "swimming_pool"),
                ("name", "Piscine de l'hôtel"),
                ("access", "customers")
            ]),
            None,
            "a pool for the customers only"
        );
        assert_eq!(
            k(&[("leisure", "pitch"), ("name", "Terrain B")]),
            None,
            "a pitch is no venue"
        );
        assert_eq!(
            k(&[("amenity", "school"), ("name", "École Jules Ferry")]),
            None
        );
        assert_eq!(
            k(&[("shop", "clothes;shoes"), ("name", "Mode et pieds")]),
            Some(PoiKind::Clothes),
            "the first value decides"
        );
        assert_eq!(
            k(&[
                ("tourism", "hotel"),
                ("amenity", "bar"),
                ("name", "Hôtel du Lac")
            ]),
            Some(PoiKind::Hotel),
            "a hotel with a bar is a hotel"
        );
        assert_eq!(PoiKind::Bar.category(), PoiCategory::Food);
    }

    #[test]
    fn a_restaurant_hotel_and_garage_carry_their_fields() {
        let bar = map_element(&element(&[
            ("amenity", "pub"),
            ("name", "The Old Pub"),
            ("cuisine", "burger;Regional"),
            ("diet:vegetarian", "yes"),
            ("diet:vegan", "no"),
            ("diet:halal", "only"),
            ("takeaway", "yes"),
            ("outdoor_seating", "no"),
            ("reservation", "recommended"),
            ("internet_access", "wlan"),
            ("wikidata", "Q42"),
            (
                "image",
                "https://commons.wikimedia.org/wiki/File:Old_Pub.jpg",
            ),
        ]))
        .unwrap();
        assert_eq!(bar.kind, PoiKind::Pub);
        assert_eq!(bar.cuisine, vec!["burger", "regional"]);
        assert_eq!(bar.diets, vec!["halal", "vegetarian"]);
        assert_eq!(bar.takeaway, Some(true));
        assert_eq!(bar.outdoor_seating, Some(false), "a no is kept: it is said");
        assert_eq!(bar.reservation.as_deref(), Some("recommended"));
        assert_eq!(bar.internet_access, Some(true));
        assert_eq!(bar.refs.wikidata.as_deref(), Some("Q42"));
        assert_eq!(
            bar.refs.commons.as_deref(),
            Some("File:Old Pub.jpg"),
            "a Commons file the image tag links to"
        );
        let hotel = map_element(&element(&[
            ("tourism", "hotel"),
            ("name", "Hôtel des Alpes"),
            ("stars", "3S"),
            ("image", "https://example.org/photo.jpg"),
        ]))
        .unwrap();
        assert_eq!(hotel.kind, PoiKind::Hotel);
        assert_eq!(hotel.stars, Some(3));
        assert_eq!(
            hotel.refs.commons, None,
            "an image of no known licence is not kept"
        );
        let tyres = map_element(&element(&[
            ("shop", "tyres"),
            ("name", "Pneus Express"),
            ("service:vehicle:tyres", "yes"),
            ("service:vehicle:brakes", "yes"),
            ("service:vehicle:glass", "no"),
            ("motorhome", "yes"),
        ]))
        .unwrap();
        assert_eq!(tyres.vehicle_services, vec!["brakes", "tyres"]);
        assert_eq!(tyres.motorhome, Some(true));
        assert!(
            map_element(&element(&[
                ("shop", "florist"),
                ("name", "Fleurs"),
                ("access", "private")
            ]))
            .is_err()
        );
    }
}
