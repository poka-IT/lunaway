//! Practical points of interest around a place: shops, vending machines,
//! water, fuel, health, services ("autour de moi").
//!
//! A point of interest is not a place to stay: it is never conflated with
//! the places, has no overnight status, and keeps the one source that
//! describes it (OpenStreetMap, or the community for a vending machine a
//! user added). Values joined from other open sources by an identifier the
//! record carries (fuel prices, La Poste opening days, FINESS) are stored
//! beside it and credited per field.
//!
//! The first six categories and their kinds follow
//! `plan/research/05-poi-sources.md` (C.2): what a traveller looks for, in
//! as few families as possible. Two came later, for the stops of a trip
//! rather than its needs: somewhere to eat ([`PoiCategory::Food`]) and
//! something to see ([`PoiCategory::Sights`]). Codes are stable strings,
//! stored and sent over the API; a released code is never renamed.

use std::{collections::BTreeSet, fmt, str::FromStr};

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};

use crate::{
    UnknownCode, geo::Position, opening::OpeningInterval, record::Address, taxonomy::coded_enum,
};

coded_enum! {
    /// The family a point of interest belongs to, one map chip each.
    PoiCategory {
        /// Food shopping: supermarkets, bakeries, markets, farm shops.
        Groceries => "groceries",
        /// Vending machines selling food: pizza, bread, farm products.
        Vending => "vending",
        /// Water and sanitation: drinking water, dump stations, toilets,
        /// showers.
        Water => "water",
        /// Fuel and energy: fuel stations (with LPG), charging, gas bottles.
        Fuel => "fuel",
        /// Health: pharmacies, doctors, hospitals, vets.
        Health => "health",
        /// Services: laundries, cash machines, post offices, recycling
        /// centres, garages, vehicle washes, motorhome and outdoor shops.
        Services => "services",
        /// Somewhere to eat or drink out: restaurants, cafés, fast food
        /// (food shopping is [`PoiCategory::Groceries`]).
        Food => "food",
        /// Something worth a stop: viewpoints, attractions, museums, and
        /// the tourist offices that tell of them.
        Sights => "sights",
    }
}

coded_enum! {
    /// What a point of interest is. Each kind belongs to one category
    /// ([`PoiKind::category`]).
    PoiKind {
        /// OSM `shop=supermarket`.
        Supermarket => "supermarket",
        /// OSM `shop=convenience`.
        Convenience => "convenience",
        /// OSM `shop=bakery`.
        Bakery => "bakery",
        /// OSM `shop=butcher`.
        Butcher => "butcher",
        /// OSM `shop=greengrocer`.
        Greengrocer => "greengrocer",
        /// Sale at the farm, OSM `shop=farm`.
        FarmShop => "farm_shop",
        /// A market, OSM `amenity=marketplace`; its days are in its opening
        /// hours.
        Marketplace => "marketplace",
        /// A pizza vending machine.
        VendingPizza => "vending_pizza",
        /// A bread vending machine.
        VendingBread => "vending_bread",
        /// A vending machine of farm products (cheese, meat, vegetables,
        /// honey, a farm's lockers).
        VendingFarmProducts => "vending_farm_products",
        /// A vending machine of eggs or milk only.
        VendingEggsMilk => "vending_eggs_milk",
        /// An ice cube vending machine.
        VendingIce => "vending_ice",
        /// Another food vending machine.
        VendingOther => "vending_other",
        /// Drinking water, OSM `amenity=drinking_water`.
        DrinkingWater => "drinking_water",
        /// A water point to fill a tank, OSM `amenity=water_point`.
        WaterPoint => "water_point",
        /// A dump station, OSM `amenity=sanitary_dump_station`.
        DumpStation => "dump_station",
        /// Public toilets, OSM `amenity=toilets`.
        Toilets => "toilets",
        /// Showers, OSM `amenity=shower`.
        Shower => "shower",
        /// A fuel station, OSM `amenity=fuel`.
        FuelStation => "fuel_station",
        /// A charging station for electric vehicles, OSM
        /// `amenity=charging_station`.
        EvCharging => "ev_charging",
        /// Gas bottles for sale or exchange, OSM `shop=gas`.
        GasBottles => "gas_bottles",
        /// OSM `amenity=pharmacy`.
        Pharmacy => "pharmacy",
        /// A doctor's practice, OSM `amenity=doctors`.
        Doctor => "doctor",
        /// OSM `amenity=hospital`.
        Hospital => "hospital",
        /// OSM `amenity=veterinary`.
        Veterinary => "veterinary",
        /// A laundry, OSM `shop=laundry`.
        Laundry => "laundry",
        /// A cash machine, OSM `amenity=atm` or a bank with `atm=yes`.
        Atm => "atm",
        /// A post office or a post partner, OSM `amenity=post_office`.
        PostOffice => "post_office",
        /// A tourist office, OSM `tourism=information` + `information=office`.
        TouristOffice => "tourist_office",
        /// A recycling centre (déchèterie), OSM `amenity=recycling` +
        /// `recycling_type=centre`.
        RecyclingCentre => "recycling_centre",
        /// A garage, OSM `shop=car_repair`.
        CarRepair => "car_repair",
        /// A vehicle wash, OSM `amenity=car_wash`.
        CarWash => "car_wash",
        /// A caravan or motorhome dealer and workshop, OSM `shop=caravan` or
        /// `shop=motorhome`, or a garage whose name says it works on them.
        MotorhomeShop => "motorhome_shop",
        /// Camping and outdoor gear, OSM `shop=outdoor`.
        OutdoorShop => "outdoor_shop",
        /// OSM `amenity=restaurant`.
        Restaurant => "restaurant",
        /// OSM `amenity=cafe`.
        Cafe => "cafe",
        /// OSM `amenity=fast_food`.
        FastFood => "fast_food",
        /// A named viewpoint, OSM `tourism=viewpoint`.
        Viewpoint => "viewpoint",
        /// OSM `tourism=attraction`, a ride or an animal of a park left
        /// out.
        Attraction => "attraction",
        /// OSM `tourism=museum`.
        Museum => "museum",
    }
}

impl PoiKind {
    /// The category the kind belongs to.
    #[must_use]
    pub const fn category(self) -> PoiCategory {
        match self {
            Self::Supermarket
            | Self::Convenience
            | Self::Bakery
            | Self::Butcher
            | Self::Greengrocer
            | Self::FarmShop
            | Self::Marketplace => PoiCategory::Groceries,
            Self::VendingPizza
            | Self::VendingBread
            | Self::VendingFarmProducts
            | Self::VendingEggsMilk
            | Self::VendingIce
            | Self::VendingOther => PoiCategory::Vending,
            Self::DrinkingWater
            | Self::WaterPoint
            | Self::DumpStation
            | Self::Toilets
            | Self::Shower => PoiCategory::Water,
            Self::FuelStation | Self::EvCharging | Self::GasBottles => PoiCategory::Fuel,
            Self::Pharmacy | Self::Doctor | Self::Hospital | Self::Veterinary => {
                PoiCategory::Health
            }
            Self::Laundry
            | Self::Atm
            | Self::PostOffice
            | Self::RecyclingCentre
            | Self::CarRepair
            | Self::CarWash
            | Self::MotorhomeShop
            | Self::OutdoorShop => PoiCategory::Services,
            Self::Restaurant | Self::Cafe | Self::FastFood => PoiCategory::Food,
            Self::Viewpoint | Self::Attraction | Self::Museum | Self::TouristOffice => {
                PoiCategory::Sights
            }
        }
    }

    /// Whether the kind is a vending machine, the only kind the community
    /// adds directly.
    #[must_use]
    pub const fn is_vending(self) -> bool {
        matches!(self.category(), PoiCategory::Vending)
    }

    /// The layer of the map tiles that carries the points of the kind.
    ///
    /// The apps released before a kind existed draw every point of `pois`
    /// when no chip is on, and a kind they do not know with the image of
    /// another: so `pois` keeps the kinds the first apps knew (a tourist
    /// office stays there although its category moved), and the kinds added
    /// since go to `pois_more`, which only an app that knows them reads. A
    /// kind added from now on lands there by default.
    #[must_use]
    pub const fn tile_layer(self) -> PoiTileLayer {
        match self {
            Self::Supermarket
            | Self::Convenience
            | Self::Bakery
            | Self::Butcher
            | Self::Greengrocer
            | Self::FarmShop
            | Self::Marketplace
            | Self::VendingPizza
            | Self::VendingBread
            | Self::VendingFarmProducts
            | Self::VendingEggsMilk
            | Self::VendingIce
            | Self::VendingOther
            | Self::DrinkingWater
            | Self::WaterPoint
            | Self::DumpStation
            | Self::Toilets
            | Self::Shower
            | Self::FuelStation
            | Self::EvCharging
            | Self::GasBottles
            | Self::Pharmacy
            | Self::Doctor
            | Self::Hospital
            | Self::Veterinary
            | Self::Laundry
            | Self::Atm
            | Self::PostOffice
            | Self::TouristOffice
            | Self::RecyclingCentre
            | Self::CarRepair
            | Self::CarWash
            | Self::MotorhomeShop => PoiTileLayer::First,
            _ => PoiTileLayer::More,
        }
    }
}

/// A layer of points in the map tiles, from the point zoom on
/// ([`PoiKind::tile_layer`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PoiTileLayer {
    /// `pois`: the kinds the first apps knew.
    First,
    /// `pois_more`: the kinds added since.
    More,
}

impl PoiTileLayer {
    /// The name of the layer in a tile.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::First => "pois",
            Self::More => "pois_more",
        }
    }

    /// The kinds the layer carries, as codes.
    #[must_use]
    pub fn kind_codes(self) -> Vec<&'static str> {
        PoiKind::ALL
            .iter()
            .filter(|k| k.tile_layer() == self)
            .map(|k| k.code())
            .collect()
    }
}

impl PoiCategory {
    /// How far "around this place" looks for the category by default, in
    /// metres: what a traveller walks to or drives a short way for. Fuel and
    /// health are worth a drive (10 km, `05-poi-sources.md` C.2), and so is
    /// something to see; the rest is shown up to 5 km, the app saying "on
    /// foot" below 800 m.
    #[must_use]
    pub const fn default_radius_m(self) -> f64 {
        match self {
            Self::Fuel | Self::Health | Self::Sights => 10_000.0,
            Self::Groceries | Self::Vending | Self::Water | Self::Services | Self::Food => 5_000.0,
        }
    }

    /// The kinds of the category, in declaration order.
    #[must_use]
    pub fn kinds(self) -> Vec<PoiKind> {
        PoiKind::ALL
            .iter()
            .copied()
            .filter(|k| k.category() == self)
            .collect()
    }

    /// Whether a map reads the category's points only when it shows them:
    /// the tiles a map reads by default ([`PoiTileSet::Base`]) leave them
    /// out, and a map showing one of them reads [`PoiTileSet::All`]. The
    /// restaurants and the sights of France doubled the gzip weight of the
    /// tiles of a town at the point zooms (+119 % at zoom 13, +143 % at 14)
    /// and added a third below them (`plan/research/86-categories-poi.md`),
    /// for a map that most of the time shows neither.
    #[must_use]
    pub const fn on_demand(self) -> bool {
        matches!(self, Self::Food | Self::Sights)
    }
}

/// The tiles of the points a map reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PoiTileSet {
    /// What a map reads by default, and all an app released before the
    /// categories read on demand knows: every category but those
    /// ([`PoiCategory::on_demand`]). Its layer `pois` holds the kinds the
    /// first apps knew, whatever their category, so those apps draw the same
    /// points as before; `pois_more` holds the kinds added since.
    Base,
    /// Every category, every point in `pois`: only an app that knows every
    /// kind reads it.
    All,
}

impl PoiTileSet {
    /// The codes of the categories the set leaves out of its clusters.
    #[must_use]
    pub fn left_out(self) -> Vec<&'static str> {
        match self {
            Self::Base => PoiCategory::ALL
                .iter()
                .filter(|c| c.on_demand())
                .map(|c| c.code())
                .collect(),
            Self::All => Vec::new(),
        }
    }

    /// The codes of the kinds the set leaves out of `pois`.
    #[must_use]
    pub fn out_of_pois(self) -> Vec<&'static str> {
        match self {
            Self::Base => PoiTileLayer::More.kind_codes(),
            Self::All => Vec::new(),
        }
    }

    /// The codes of the kinds of `pois_more`: those added since the first
    /// apps, of a category the set carries; none in [`PoiTileSet::All`].
    #[must_use]
    pub fn in_pois_more(self) -> Vec<&'static str> {
        match self {
            Self::Base => PoiKind::ALL
                .iter()
                .filter(|k| k.tile_layer() == PoiTileLayer::More && !k.category().on_demand())
                .map(|k| k.code())
                .collect(),
            Self::All => Vec::new(),
        }
    }
}

/// The identifiers a record carries into other open sources, the only
/// joins Lunaway makes: no fuzzy matching between sources.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PoiRefs {
    /// The station's id in the fuel price feed (OSM
    /// `ref:FR:prix-carburants`), digits only.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fuel: Option<String>,
    /// The site's id at La Poste (OSM `ref:FR:LaPoste`, `13905D`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub laposte: Option<String>,
    /// The establishment's FINESS number (OSM `ref:FR:FINESS`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub finess: Option<String>,
    /// The establishment's SIRET (OSM `ref:FR:SIRET`), kept for a later
    /// closure check against SIRENE.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub siret: Option<String>,
}

impl PoiRefs {
    /// Whether the record carries no identifier.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.fuel.is_none()
            && self.laposte.is_none()
            && self.finess.is_none()
            && self.siret.is_none()
    }
}

/// What one source says about one point of interest. Stored as JSON next to
/// the raw payload: fields are only added, with a serde default.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PoiRecord {
    /// What it is.
    pub kind: PoiKind,
    /// Where it is.
    pub position: Position,
    /// Display name as the source gives it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Brand (`Super U`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub brand: Option<String>,
    /// Who runs it (`Gang of Pizza`, a town).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub operator: Option<String>,
    /// Opening hours in the OSM `opening_hours` syntax.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opening_hours: Option<String>,
    /// Phone number as the source writes it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    /// Website URL.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub website: Option<String>,
    /// Postal address.
    #[serde(default, skip_serializing_if = "Address::is_empty")]
    pub address: Address,
    /// Wheelchair access as OSM says it (`yes`, `limited`, `no`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wheelchair: Option<String>,
    /// The last date someone checked it on the ground (OSM `check_date`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub check_date: Option<NaiveDate>,
    /// What a vending machine sells, as tagged (`pizza`, `bread`, `eggs`).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub products: Vec<String>,
    /// Payment methods accepted (`cash`, `cards`, `contactless`).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub payment: Vec<String>,
    /// Fuels sold (`diesel`, `e10`, `lpg`), as OSM names them.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub fuels: Vec<String>,
    /// Whether LPG is sold, when the source says.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lpg: Option<bool>,
    /// Self-service (a laundry, a vehicle wash).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub self_service: Option<bool>,
    /// Whether it charges a fee (toilets, showers, water).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fee: Option<bool>,
    /// Open only part of the year (a fountain cut off in winter).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seasonal: Option<bool>,
    /// A hospital with an emergency department.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub emergency: Option<bool>,
    /// Whether motorhomes may use it (a vehicle wash, a garage), when the
    /// source says (OSM `motorhome`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub motorhome: Option<bool>,
    /// Whether heavy goods vehicles may use it (a vehicle wash), when the
    /// source says (OSM `hgv`): a wash that takes lorries takes a
    /// motorhome's height.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hgv: Option<bool>,
    /// The highest vehicle it takes, metres (a wash's gantry, OSM
    /// `maxheight`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_height_m: Option<f64>,
    /// The OpenStreetMap element the record is (`node/123`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub osm_ref: Option<String>,
    /// Identifiers into other open sources.
    #[serde(default, skip_serializing_if = "PoiRefs::is_empty")]
    pub refs: PoiRefs,
}

impl PoiRecord {
    /// A record that only knows its kind and position.
    #[must_use]
    pub fn new(kind: PoiKind, position: Position) -> Self {
        Self {
            kind,
            position,
            name: None,
            brand: None,
            operator: None,
            opening_hours: None,
            phone: None,
            website: None,
            address: Address::default(),
            wheelchair: None,
            check_date: None,
            products: Vec::new(),
            payment: Vec::new(),
            fuels: Vec::new(),
            lpg: None,
            self_service: None,
            fee: None,
            seasonal: None,
            emergency: None,
            motorhome: None,
            hgv: None,
            max_height_m: None,
            osm_ref: None,
            refs: PoiRefs::default(),
        }
    }
}

/// Products of a food vending machine, the `vending` values the layer
/// reads (`05-poi-sources.md`, B.2). A machine selling none of them (drinks,
/// sweets, tickets) is not a point of interest.
pub const FOOD_PRODUCTS: &[&str] = &[
    "pizza",
    "bread",
    "baguette",
    "food",
    "meals",
    "eggs",
    "milk",
    "raw_milk",
    "cheese",
    "dairy",
    "butter",
    "yogurt",
    "meat",
    "sausages",
    "vegetables",
    "fruit",
    "potatoes",
    "honey",
    "oysters",
    "farm_products",
    "ice_cubes",
];

/// Products that make a farm-products machine (eggs and milk alone make an
/// eggs-and-milk one).
const FARM_PRODUCTS: &[&str] = &[
    "eggs",
    "milk",
    "raw_milk",
    "cheese",
    "dairy",
    "butter",
    "yogurt",
    "meat",
    "sausages",
    "vegetables",
    "fruit",
    "potatoes",
    "honey",
    "oysters",
    "farm_products",
];

/// Words of a name or an operator that make a `food` machine a farm's
/// lockers ("Aux casiers du terroir", "Ferme des Saules").
const FARM_WORDS: &[&str] = &["ferme", "casier", "terroir", "paysan"];

/// The kind of a food vending machine from its products (the OSM `vending`
/// values, already split) and the words of its name and operator, by the
/// rule of `05-poi-sources.md` B.4: pizza first, then bread, then farm
/// products (eggs and milk alone apart), ice, and `food` alone as "other"
/// unless the name says it is a farm's. `None` for a machine that sells no
/// food.
#[must_use]
pub fn vending_kind(products: &[&str], labels: &[&str]) -> Option<PoiKind> {
    let has = |p: &str| products.contains(&p);
    let any = |list: &[&str]| products.iter().any(|p| list.contains(p));
    if has("pizza") {
        return Some(PoiKind::VendingPizza);
    }
    if has("bread") || has("baguette") {
        return Some(PoiKind::VendingBread);
    }
    if any(FARM_PRODUCTS) {
        let eggs_milk_only = products
            .iter()
            .filter(|p| FOOD_PRODUCTS.contains(p))
            .all(|p| matches!(*p, "eggs" | "milk" | "raw_milk"));
        return Some(if eggs_milk_only {
            PoiKind::VendingEggsMilk
        } else {
            PoiKind::VendingFarmProducts
        });
    }
    if has("ice_cubes") {
        return Some(PoiKind::VendingIce);
    }
    if has("food") || has("meals") {
        let farm = labels.iter().any(|l| {
            let folded = crate::conflation::normalize::fold(l);
            FARM_WORDS.iter().any(|w| folded.contains(w))
        });
        return Some(if farm {
            PoiKind::VendingFarmProducts
        } else {
            PoiKind::VendingOther
        });
    }
    None
}

/// The starts of the words of a folded name that say a garage or a wash
/// works on motorhomes and caravans (`Camping-Car` folds to `camping car`).
/// `camping` alone is not one: "Garage du Camping" says where it is. In
/// the France extract of 2026-10-06, the 11 garages these name were all
/// motorhome workshops; OpenStreetMap's own key for it
/// (`service:vehicle:motorhome`) had no use in Geofabrik's taginfo of
/// Europe of 2026-10-08 (`plan/research/86-categories-poi.md`).
const MOTORHOME_STEMS: &[&str] = &[
    "camping car",
    "campingcar",
    "camper",
    "caravan",
    "wohnmobil",
    "reisemobil",
    "autocaravan",
    "motorhome",
];

/// The starts of the words of a folded name that say a wash takes lorries
/// (`Lavage poids lourds`, `Truckwash`, `LKW-Waschanlage`): a wash that
/// takes them takes a motorhome's height.
const LORRY_STEMS: &[&str] = &["poids lourd", "truck", "lkw", "vrachtwagen", "vrachtauto"];

/// Whether a word of `folded` starts with one of `stems`.
fn has_stem(folded: &str, stems: &[&str]) -> bool {
    stems.iter().any(|stem| {
        folded
            .match_indices(stem)
            .any(|(i, _)| i == 0 || folded.as_bytes().get(i - 1) == Some(&b' '))
    })
}

/// Whether a name says its garage or wash works on motorhomes
/// ([`MOTORHOME_STEMS`]).
#[must_use]
pub fn names_motorhomes(name: &str) -> bool {
    has_stem(&crate::conflation::normalize::fold(name), MOTORHOME_STEMS)
}

/// Whether a name says its wash takes lorries ([`LORRY_STEMS`]).
#[must_use]
pub fn names_lorries(name: &str) -> bool {
    has_stem(&crate::conflation::normalize::fold(name), LORRY_STEMS)
}

/// Whether a point of interest is open at an instant, from its intervals.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OpenState {
    /// Open; `until` is when it closes, `None` past the known window or for
    /// a place always open.
    Open {
        /// Closing time within the window.
        until: Option<DateTime<Utc>>,
    },
    /// Closed; `opens_at` is the next opening within the window.
    Closed {
        /// Next opening within the window.
        opens_at: Option<DateTime<Utc>>,
    },
    /// Nothing is known at this instant: no hours, hours that do not parse,
    /// or an instant past the computed window.
    Unknown,
}

/// The state at `now` of a point whose opening intervals over the window
/// ending at `until` are `intervals` (sorted, end excluded), or that is
/// always open. Before `until`, an instant in no interval is closed; after
/// it nothing is known: a device offline for longer than the window must
/// not claim a shop is open.
#[must_use]
pub fn open_state(
    always_open: bool,
    intervals: Option<&[OpeningInterval]>,
    until: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
) -> OpenState {
    if always_open {
        return OpenState::Open { until: None };
    }
    let (Some(intervals), Some(until)) = (intervals, until) else {
        return OpenState::Unknown;
    };
    if now >= until {
        return OpenState::Unknown;
    }
    if let Some(i) = intervals.iter().find(|i| i.start <= now && now < i.end) {
        // A closing at the window's end is not a closing: the hours after it
        // are unknown, not closed.
        return OpenState::Open {
            until: (i.end < until).then_some(i.end),
        };
    }
    OpenState::Closed {
        opens_at: intervals.iter().map(|i| i.start).find(|s| *s > now),
    }
}

/// Seconds in a minute, the unit of the compact hours of a map tile.
const MINUTE_S: i64 = 60;

/// Opening intervals as a map tile carries them, in a few dozen bytes:
/// `<start>:<open>,<closed>,<open>,...` where `start` is the first opening in
/// minutes since the Unix epoch, then the lengths in minutes of each open
/// span and of the closed gap after it. Every POI open the same hours in
/// the same week writes the same text, which a tile stores once. An empty
/// list (closed over the whole window) is an empty text.
///
/// The window's end goes beside it, as an integer of minutes since the
/// epoch ([`minutes_since_epoch`]): past it nothing is known.
#[must_use]
pub fn encode_hours(intervals: &[OpeningInterval]) -> String {
    let mut out = String::new();
    let Some(first) = intervals.first() else {
        return out;
    };
    // Every boundary is floored to its minute on its own, and the text
    // carries the differences between floored boundaries: seconds lost on
    // one span never shift the next ones.
    out.push_str(&minutes_since_epoch(first.start).to_string());
    out.push(':');
    let mut previous_end: Option<i64> = None;
    for i in intervals {
        let (start, end) = (minutes_since_epoch(i.start), minutes_since_epoch(i.end));
        if let Some(previous) = previous_end {
            out.push(',');
            out.push_str(&(start - previous).to_string());
            out.push(',');
        }
        out.push_str(&(end - start).to_string());
        previous_end = Some(end);
    }
    out
}

/// Minutes since the Unix epoch, rounded down.
#[must_use]
pub fn minutes_since_epoch(t: DateTime<Utc>) -> i64 {
    t.timestamp().div_euclid(MINUTE_S)
}

/// Reads [`encode_hours`] back; `None` for a text it did not write. The app
/// decodes the same form in Dart; this is its reference.
#[must_use]
pub fn decode_hours(text: &str) -> Option<Vec<OpeningInterval>> {
    if text.is_empty() {
        return Some(Vec::new());
    }
    let (start, rest) = text.split_once(':')?;
    let mut at =
        DateTime::<Utc>::from_timestamp(start.parse::<i64>().ok()?.checked_mul(MINUTE_S)?, 0)?;
    let mut out = Vec::new();
    let mut open = true;
    for part in rest.split(',') {
        let minutes: i64 = part.parse().ok().filter(|m: &i64| *m >= 0)?;
        let next = at.checked_add_signed(chrono::Duration::try_minutes(minutes)?)?;
        if open {
            out.push(OpeningInterval {
                start: at,
                end: next,
            });
        }
        at = next;
        open = !open;
    }
    // A text ends with an open span; a trailing gap is not one this wrote.
    (!open).then_some(out)
}

// Values other open sources give for a point, joined by an identifier the
// point's record carries. Stored as JSON in `poi_join_records.data`; what a
// map tile shows of a row sits under `tile`, so the tiles' version moves
// only when that part changes.

coded_enum! {
    /// A fuel of the French price feed.
    FuelKind {
        /// Diesel (`Gazole`).
        Diesel => "diesel",
        /// Unleaded 95 (`SP95`).
        Sp95 => "sp95",
        /// Unleaded 95 with up to 10 % ethanol (`E10`).
        E10 => "e10",
        /// Unleaded 98 (`SP98`).
        Sp98 => "sp98",
        /// Superethanol (`E85`).
        E85 => "e85",
        /// LPG for vehicles (`GPLc`).
        Lpg => "lpg",
    }
}

coded_enum! {
    /// How a station is out of a fuel.
    ShortageKind {
        /// For now: the station usually sells it.
        Temporary => "temporary",
        /// For good: the station stopped selling it.
        Definitive => "definitive",
    }
}

/// A price of the feed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FuelPrice {
    /// The fuel.
    pub fuel: FuelKind,
    /// Euros per litre.
    pub price_eur: f64,
    /// When the station last updated it.
    pub updated_at: DateTime<Utc>,
}

/// A fuel the station is out of.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FuelShortage {
    /// The fuel.
    pub fuel: FuelKind,
    /// For now or for good.
    pub kind: ShortageKind,
    /// Since when, if the feed says.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub since: Option<DateTime<Utc>>,
}

/// What the tiles show of a fuel station.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct FuelTile {
    /// The station sells LPG (it may be out of it for now).
    pub lpg: bool,
}

/// A station of the fuel price feed (`prix-carburants`), keyed by its id in
/// the feed (OSM `ref:FR:prix-carburants`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FuelStation {
    /// Prices, one per fuel sold.
    #[serde(default)]
    pub prices: Vec<FuelPrice>,
    /// Fuels it is out of.
    #[serde(default)]
    pub shortages: Vec<FuelShortage>,
    /// Services as the feed names them (`Laverie`, `Vente de gaz domestique
    /// (Butane, Propane)`, `DAB (Distributeur automatique de billets)`).
    #[serde(default)]
    pub services: Vec<String>,
    /// A card machine sells fuel day and night.
    #[serde(default)]
    pub automate_24_24: bool,
    /// On a motorway (`pop` = `A`).
    #[serde(default)]
    pub highway: bool,
    /// Where the feed puts it, for a station no OSM element names.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position: Option<Position>,
    /// Its address as the feed writes it: what names a station no OSM
    /// element describes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub address: Option<FuelAddress>,
    /// What the tiles show.
    #[serde(default)]
    pub tile: FuelTile,
}

/// A station's address in the fuel feed.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct FuelAddress {
    /// Street and number (`adresse`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub street: Option<String>,
    /// Postcode (`cp`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub postcode: Option<String>,
    /// Town (`ville`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub city: Option<String>,
}

/// Days after which a "temporary" shortage reads as the station having
/// stopped: on 2026-10-06, 346 of the 513 stations "temporarily" out of LPG
/// had been so for over a year, one since 2018.
pub const STALE_SHORTAGE_DAYS: i64 = 90;

impl FuelStation {
    /// Its price of `fuel`, if it lists one.
    #[must_use]
    pub fn price_of(&self, fuel: FuelKind) -> Option<&FuelPrice> {
        self.prices.iter().find(|p| p.fuel == fuel)
    }

    /// How it is out of `fuel`, if it is.
    #[must_use]
    pub fn shortage_of(&self, fuel: FuelKind) -> Option<&FuelShortage> {
        self.shortages.iter().find(|s| s.fuel == fuel)
    }

    /// Whether the station sells LPG, its latest price update for clock
    /// ([`FuelStation::sells_lpg_at`]).
    #[must_use]
    pub fn sells_lpg(&self) -> bool {
        self.sells_lpg_at(None)
    }

    /// Whether the station sells LPG: it has an LPG price, or is out of it
    /// for now. A shortage called temporary that began more than
    /// [`STALE_SHORTAGE_DAYS`] before `clock` is read as definitive. The
    /// importer passes the feed's own clock (its latest price update of any
    /// station), so the reading is the same wherever it is made and does
    /// not flap: the station's own latest update came and went with its
    /// other prices, and a 2022 shortage read as current whenever they were
    /// missing (6 of the 11 changes of the map flag over three hours on
    /// 2026-10-06, `plan/research/23-backend-europe-packs.md`). Without a
    /// clock, the station's latest price update.
    #[must_use]
    pub fn sells_lpg_at(&self, clock: Option<DateTime<Utc>>) -> bool {
        let latest = clock.or_else(|| self.prices.iter().map(|p| p.updated_at).max());
        let stale = |s: &FuelShortage| {
            s.kind == ShortageKind::Temporary
                && s.since.zip(latest).is_some_and(|(since, latest)| {
                    latest - since > chrono::Duration::days(STALE_SHORTAGE_DAYS)
                })
        };
        let definitive = self
            .shortages
            .iter()
            .any(|s| s.fuel == FuelKind::Lpg && (s.kind == ShortageKind::Definitive || stale(s)));
        let listed = self.prices.iter().any(|p| p.fuel == FuelKind::Lpg)
            || self
                .shortages
                .iter()
                .any(|s| s.fuel == FuelKind::Lpg && s.kind == ShortageKind::Temporary);
        listed && !definitive
    }
}

/// One day of La Poste's opening calendar.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostDay {
    /// The local date.
    pub date: NaiveDate,
    /// Opening ranges in local time, in order; empty on a closed day.
    #[serde(default)]
    pub open: Vec<[chrono::NaiveTime; 2]>,
}

/// La Poste's calendar of a site (`laposte`), keyed by its id (OSM
/// `ref:FR:LaPoste`), over the days the importer read.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostOfficeDays {
    /// What La Poste calls the site (`Bureau de Poste`, `Relais poste`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    /// The days, in date order.
    pub days: Vec<PostDay>,
}

/// What the tiles show of a FINESS establishment.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct FinessTile {
    /// FINESS lists it as closed.
    pub closed: bool,
}

/// An establishment of FINESS (`finess`), keyed by its FINESS number (OSM
/// `ref:FR:FINESS`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FinessEstablishment {
    /// False only when FINESS lists it as inactive.
    pub open: bool,
    /// The date FINESS gives for its closure.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub closed_on: Option<NaiveDate>,
    /// Its category as FINESS writes it (`620`, pharmacie d'officine).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    /// Its name in FINESS.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// What the tiles show.
    #[serde(default)]
    pub tile: FinessTile,
}

/// Longest name, brand or operator a contributor may give, in characters.
pub const MAX_LABEL_CHARS: usize = 100;
/// Most products or payment methods a contribution lists.
pub const MAX_LIST_ITEMS: usize = 12;

/// Payment methods a contribution may name, as OSM writes them after
/// `payment:`.
pub const PAYMENT_METHODS: &[&str] = &[
    "cash",
    "coins",
    "notes",
    "cards",
    "credit_cards",
    "debit_cards",
    "contactless",
    "app",
];

/// A vending machine a user adds in two gestures: where, and what it sells.
/// The rest is optional.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NewVendingMachine {
    /// Kind; a vending kind.
    pub kind: PoiKind,
    /// Where it stands.
    pub position: Position,
    /// Its name, if it has one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Who runs it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub operator: Option<String>,
    /// Its brand.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub brand: Option<String>,
    /// What it sells beyond its kind, among [`FOOD_PRODUCTS`].
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub products: Vec<String>,
    /// Payment methods, among [`PAYMENT_METHODS`].
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub payment: Vec<String>,
    /// Open day and night, as most machines are.
    #[serde(default)]
    pub always_open: bool,
}

/// Why a contributed vending machine is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidContribution {
    /// The kind is not a vending machine.
    #[error("{0} is not a vending machine")]
    NotVending(PoiKind),
    /// A text is empty after trimming or too long.
    #[error("{field} must hold 1 to {MAX_LABEL_CHARS} characters")]
    Label {
        /// The field.
        field: &'static str,
    },
    /// A list is too long or holds an unknown value.
    #[error("{field}: unknown or too many values")]
    List {
        /// The field.
        field: &'static str,
    },
}

fn clean_label(
    v: Option<&str>,
    field: &'static str,
) -> Result<Option<String>, InvalidContribution> {
    let Some(v) = v else { return Ok(None) };
    let v: String = v.split_whitespace().collect::<Vec<_>>().join(" ");
    if v.is_empty() || v.chars().count() > MAX_LABEL_CHARS || v.chars().any(char::is_control) {
        return Err(InvalidContribution::Label { field });
    }
    Ok(Some(v))
}

fn clean_list(
    v: &[String],
    allowed: &[&str],
    field: &'static str,
) -> Result<Vec<String>, InvalidContribution> {
    if v.len() > MAX_LIST_ITEMS {
        return Err(InvalidContribution::List { field });
    }
    let set: BTreeSet<String> = v.iter().map(|s| s.trim().to_ascii_lowercase()).collect();
    if set.iter().any(|s| !allowed.contains(&s.as_str())) {
        return Err(InvalidContribution::List { field });
    }
    Ok(set.into_iter().collect())
}

/// Checks a contributed vending machine and returns it with its texts
/// trimmed and its lists sorted.
///
/// # Errors
///
/// [`InvalidContribution`] when the kind is not a vending machine, a text
/// is empty or too long, or a list holds an unknown value.
pub fn validate_vending(v: &NewVendingMachine) -> Result<NewVendingMachine, InvalidContribution> {
    if !v.kind.is_vending() {
        return Err(InvalidContribution::NotVending(v.kind));
    }
    Ok(NewVendingMachine {
        kind: v.kind,
        position: v.position,
        name: clean_label(v.name.as_deref(), "name")?,
        operator: clean_label(v.operator.as_deref(), "operator")?,
        brand: clean_label(v.brand.as_deref(), "brand")?,
        products: clean_list(&v.products, FOOD_PRODUCTS, "products")?,
        payment: clean_list(&v.payment, PAYMENT_METHODS, "payment")?,
        always_open: v.always_open,
    })
}

/// The record a contributed vending machine becomes: OSM's tags in Lunaway's
/// form, so the point could be sent to OpenStreetMap later without a
/// conversion.
#[must_use]
pub fn record_of_vending(v: &NewVendingMachine) -> PoiRecord {
    let mut r = PoiRecord::new(v.kind, v.position);
    r.name.clone_from(&v.name);
    r.operator.clone_from(&v.operator);
    r.brand.clone_from(&v.brand);
    let mut products: BTreeSet<String> = v.products.iter().cloned().collect();
    if let Some(p) = main_product(v.kind) {
        products.insert(p.to_owned());
    }
    r.products = products.into_iter().collect();
    r.payment.clone_from(&v.payment);
    if v.always_open {
        r.opening_hours = Some("24/7".to_owned());
    }
    r
}

/// The OSM `vending` value a vending kind stands for.
#[must_use]
pub const fn main_product(kind: PoiKind) -> Option<&'static str> {
    match kind {
        PoiKind::VendingPizza => Some("pizza"),
        PoiKind::VendingBread => Some("bread"),
        PoiKind::VendingFarmProducts => Some("farm_products"),
        PoiKind::VendingEggsMilk => Some("eggs"),
        PoiKind::VendingIce => Some("ice_cubes"),
        PoiKind::VendingOther => Some("food"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;

    #[test]
    fn every_kind_has_a_category_and_every_category_kinds() {
        for c in PoiCategory::ALL {
            assert!(
                !c.kinds().is_empty(),
                "{c} has no kind: its chip would show nothing"
            );
        }
        let vending: Vec<_> = PoiKind::ALL.iter().filter(|k| k.is_vending()).collect();
        assert_eq!(
            vending.len(),
            6,
            "the six vending kinds of 05-poi-sources.md B.4"
        );
        for k in PoiKind::ALL {
            assert_eq!(
                main_product(*k).is_some(),
                k.is_vending(),
                "{k}: a vending kind must name its OSM product"
            );
        }
    }

    #[test]
    fn the_first_tile_layer_keeps_the_kinds_the_first_apps_knew() {
        // The 33 codes of the first release (migration 20261006090200): an
        // app of that release draws every point of `pois` when no chip is
        // on, so a kind it does not know must never be there.
        let first = [
            "supermarket",
            "convenience",
            "bakery",
            "butcher",
            "greengrocer",
            "farm_shop",
            "marketplace",
            "vending_pizza",
            "vending_bread",
            "vending_farm_products",
            "vending_eggs_milk",
            "vending_ice",
            "vending_other",
            "drinking_water",
            "water_point",
            "dump_station",
            "toilets",
            "shower",
            "fuel_station",
            "ev_charging",
            "gas_bottles",
            "pharmacy",
            "doctor",
            "hospital",
            "veterinary",
            "laundry",
            "atm",
            "post_office",
            "tourist_office",
            "recycling_centre",
            "car_repair",
            "car_wash",
            "motorhome_shop",
        ];
        assert_eq!(
            PoiTileLayer::First.kind_codes(),
            first,
            "`pois` holds the first release's kinds, and only them"
        );
        let more = PoiTileLayer::More.kind_codes();
        assert_eq!(more.len() + first.len(), PoiKind::ALL.len());
        assert!(more.contains(&"restaurant") && more.contains(&"viewpoint"));
        assert_eq!(
            PoiKind::TouristOffice.category(),
            PoiCategory::Sights,
            "the tourist offices tell of what there is to see"
        );
        assert_eq!(PoiTileSet::Base.left_out(), ["food", "sights"]);
        assert_eq!(
            PoiTileSet::Base.in_pois_more(),
            ["outdoor_shop"],
            "the default tiles carry the kinds added since apart, those of the restaurants and sights not at all"
        );
        assert!(
            PoiTileSet::All.out_of_pois().is_empty() && PoiTileSet::All.in_pois_more().is_empty(),
            "every point in `pois`: only an app that knows every kind reads these tiles"
        );
    }

    #[test]
    fn a_name_tells_motorhome_workshops_and_lorry_washes() {
        for name in [
            "Garage Camping-car",
            "L'atelier Du Camping-Car By Gemelli",
            "XB Loisirs - camping-car et caravane",
            "Campervans Montblanc",
            "Wohnmobil-Werkstatt Müller",
            "Reisemobile Center",
            "Autocaravanas del Sur",
        ] {
            assert!(names_motorhomes(name), "{name}");
        }
        for name in [
            "Garage du Camping",
            "Camping Le Club Farret",
            "Scamper",
            "Renault Trucks",
        ] {
            assert!(!names_motorhomes(name), "{name}: no motorhome in it");
        }
        for name in [
            "Station de lavage poids lourds",
            "A63 Truckwash",
            "LKW-Waschanlage",
        ] {
            assert!(names_lorries(name), "{name}");
        }
        assert!(!names_lorries("Lavage du Centre"));
        assert!(!names_lorries("Struck"), "a word that only contains one");
    }

    #[test]
    fn vending_products_follow_the_rule_of_the_report() {
        let k = |p: &[&str], l: &[&str]| vending_kind(p, l);
        assert_eq!(k(&["pizza"], &[]), Some(PoiKind::VendingPizza));
        assert_eq!(
            k(&["food", "pizza"], &[]),
            Some(PoiKind::VendingPizza),
            "pizza first"
        );
        assert_eq!(k(&["baguette"], &[]), Some(PoiKind::VendingBread));
        assert_eq!(k(&["bread", "eggs"], &[]), Some(PoiKind::VendingBread));
        assert_eq!(k(&["eggs"], &[]), Some(PoiKind::VendingEggsMilk));
        assert_eq!(
            k(&["eggs", "raw_milk"], &[]),
            Some(PoiKind::VendingEggsMilk)
        );
        assert_eq!(
            k(&["eggs", "cheese"], &[]),
            Some(PoiKind::VendingFarmProducts),
            "eggs with anything else is a farm's machine"
        );
        assert_eq!(k(&["ice_cubes"], &[]), Some(PoiKind::VendingIce));
        assert_eq!(k(&["food"], &[]), Some(PoiKind::VendingOther));
        assert_eq!(
            k(&["food"], &["Aux Casiers du Terroir"]),
            Some(PoiKind::VendingFarmProducts)
        );
        assert_eq!(
            k(&["food"], &["La Ferme des Saules"]),
            Some(PoiKind::VendingFarmProducts)
        );
        assert_eq!(k(&["drinks", "sweets"], &[]), None, "drinks are not food");
        assert_eq!(k(&["parking_tickets"], &[]), None);
    }

    fn at(d: u32, h: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 11, d, h, 0, 0).unwrap()
    }

    fn iv(a: DateTime<Utc>, b: DateTime<Utc>) -> OpeningInterval {
        OpeningInterval { start: a, end: b }
    }

    #[test]
    fn the_open_state_reads_the_intervals_and_their_window() {
        let ivs = [iv(at(2, 8), at(2, 12)), iv(at(2, 14), at(2, 18))];
        let until = Some(at(16, 0));
        assert_eq!(
            open_state(false, Some(&ivs), until, at(2, 9)),
            OpenState::Open {
                until: Some(at(2, 12))
            }
        );
        assert_eq!(
            open_state(false, Some(&ivs), until, at(2, 13)),
            OpenState::Closed {
                opens_at: Some(at(2, 14))
            }
        );
        assert_eq!(
            open_state(false, Some(&ivs), until, at(3, 9)),
            OpenState::Closed { opens_at: None },
            "closed for the rest of the window"
        );
        assert_eq!(
            open_state(false, Some(&ivs), until, at(16, 1)),
            OpenState::Unknown,
            "past the window nothing is known"
        );
        assert_eq!(open_state(false, None, None, at(2, 9)), OpenState::Unknown);
        assert_eq!(
            open_state(true, None, None, at(2, 9)),
            OpenState::Open { until: None }
        );
        let to_end = [iv(at(2, 8), at(16, 0))];
        assert_eq!(
            open_state(false, Some(&to_end), until, at(2, 9)),
            OpenState::Open { until: None },
            "an opening that runs to the window's end does not close there"
        );
    }

    #[test]
    fn tile_hours_are_short_and_read_back() {
        let ivs = [
            iv(at(2, 7), at(2, 11)),
            iv(at(2, 13), at(2, 18)),
            iv(at(3, 7), at(3, 11)),
        ];
        let text = encode_hours(&ivs);
        assert_eq!(
            text,
            format!("{}:240,120,300,780,240", minutes_since_epoch(at(2, 7))),
            "start, then open and closed lengths in minutes"
        );
        assert_eq!(decode_hours(&text).unwrap(), ivs.to_vec());
        assert_eq!(encode_hours(&[]), "");
        assert_eq!(decode_hours("").unwrap(), Vec::new());
        assert_eq!(decode_hours("x:1"), None);
        assert_eq!(
            decode_hours("10:5,3"),
            None,
            "a trailing gap is not a valid text"
        );
        assert_eq!(decode_hours("10:-5"), None);
        assert_eq!(
            decode_hours("10:9223372036854775807"),
            None,
            "a length past any date is refused, not a panic"
        );
    }

    proptest::proptest! {
        #[test]
        fn tile_hours_read_back_to_the_minute(
            start in 0i64..4_000_000_000,
            spans in proptest::collection::vec((0i64..100_000, 1i64..100_000), 0..40),
        ) {
            let mut at = start;
            let mut ivs = Vec::new();
            for (gap, open) in spans {
                let s = at + gap;
                let e = s + open;
                ivs.push(OpeningInterval {
                    start: DateTime::<Utc>::from_timestamp(s, 0).unwrap(),
                    end: DateTime::<Utc>::from_timestamp(e, 0).unwrap(),
                });
                at = e;
            }
            let floor = |t: DateTime<Utc>| {
                DateTime::<Utc>::from_timestamp(minutes_since_epoch(t) * 60, 0).unwrap()
            };
            let expected: Vec<OpeningInterval> = ivs
                .iter()
                .map(|i| OpeningInterval { start: floor(i.start), end: floor(i.end) })
                .collect();
            proptest::prop_assert_eq!(
                decode_hours(&encode_hours(&ivs)).unwrap(),
                expected,
                "each boundary floored to its minute, none drifting"
            );
        }

        #[test]
        fn decoding_never_panics(text in "\\PC{0,60}") {
            let _ = decode_hours(&text);
        }
    }

    #[test]
    fn a_contributed_machine_is_checked_and_tagged_as_osm_would() {
        let new = NewVendingMachine {
            kind: PoiKind::VendingPizza,
            position: Position::new(47.47, -0.55).unwrap(),
            name: Some("  Pizza   Suzon ".into()),
            operator: None,
            brand: None,
            products: vec!["Food".into()],
            payment: vec!["cards".into(), "cash".into()],
            always_open: true,
        };
        let ok = validate_vending(&new).unwrap();
        assert_eq!(ok.name.as_deref(), Some("Pizza Suzon"));
        assert_eq!(ok.products, vec!["food"]);
        assert_eq!(ok.payment, vec!["cards", "cash"]);
        let r = record_of_vending(&ok);
        assert_eq!(r.products, vec!["food", "pizza"]);
        assert_eq!(r.opening_hours.as_deref(), Some("24/7"));
        assert!(matches!(
            validate_vending(&NewVendingMachine {
                kind: PoiKind::Bakery,
                ..new.clone()
            }),
            Err(InvalidContribution::NotVending(_))
        ));
        assert!(matches!(
            validate_vending(&NewVendingMachine {
                payment: vec!["bitcoin".into()],
                ..new.clone()
            }),
            Err(InvalidContribution::List { .. })
        ));
        assert!(matches!(
            validate_vending(&NewVendingMachine {
                name: Some("x".repeat(101)),
                ..new
            }),
            Err(InvalidContribution::Label { .. })
        ));
    }

    #[test]
    fn a_station_sells_lpg_unless_it_stopped_for_good() {
        let at = Utc.with_ymd_and_hms(2026, 10, 6, 8, 0, 0).unwrap();
        let price = |fuel| FuelPrice {
            fuel,
            price_eur: 1.0,
            updated_at: at,
        };
        let short = |fuel, kind| FuelShortage {
            fuel,
            kind,
            since: None,
        };
        let station = |prices, shortages| FuelStation {
            prices,
            shortages,
            services: Vec::new(),
            automate_24_24: false,
            highway: false,
            position: None,
            address: None,
            tile: FuelTile::default(),
        };
        assert!(station(vec![price(FuelKind::Lpg)], vec![]).sells_lpg());
        assert!(
            station(vec![], vec![short(FuelKind::Lpg, ShortageKind::Temporary)]).sells_lpg(),
            "out of it for now is still a station that sells it"
        );
        assert!(!station(vec![], vec![short(FuelKind::Lpg, ShortageKind::Definitive)]).sells_lpg());
        assert!(!station(vec![price(FuelKind::Diesel)], vec![]).sells_lpg());
        let since = |days: i64| FuelShortage {
            fuel: FuelKind::Lpg,
            kind: ShortageKind::Temporary,
            since: Some(at - chrono::Duration::days(days)),
        };
        assert!(
            station(vec![price(FuelKind::Diesel)], vec![since(10)]).sells_lpg(),
            "out of LPG for ten days while diesel prices move: for now"
        );
        assert!(
            !station(vec![price(FuelKind::Diesel)], vec![since(400)]).sells_lpg(),
            "\"temporarily\" out of LPG for over a year: stopped"
        );
        // Station 67210004 on 2026-10-06: LPG "temporarily" out since 2023,
        // its other prices present at 10:01 UTC and gone at 12:28.
        let gone_prices = station(vec![], vec![since(1_340)]);
        assert!(
            gone_prices.sells_lpg(),
            "without a price the station's own clock cannot tell the shortage is old"
        );
        assert!(
            !gone_prices.sells_lpg_at(Some(at)),
            "the feed's clock can, whether the station's prices are there or not"
        );
        assert_eq!(
            gone_prices.sells_lpg_at(Some(at)),
            station(vec![price(FuelKind::Diesel)], vec![since(1_340)]).sells_lpg_at(Some(at)),
            "a station's other prices coming and going does not change the reading"
        );
    }

    #[test]
    fn records_serialise_compactly() {
        let r = PoiRecord::new(PoiKind::Toilets, Position::new(45.0, 3.0).unwrap());
        assert_eq!(
            serde_json::to_value(&r).unwrap(),
            serde_json::json!({"kind": "toilets", "position": {"lat": 45.0, "lon": 3.0}}),
            "absent facts are left out of the stored JSON"
        );
    }
}
