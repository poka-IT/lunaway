//! The GraphQL types of the map's search with addresses
//! (`Query.searchAll`).

use async_graphql::{Enum, SimpleObject};
use lunaway_domain::address::{AddressKind, AddressMatch, AddressSource};

use crate::types::{Place, Source};

/// What an address designates.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(name = "AddressKind")]
pub enum GqlAddressKind {
    /// A house number on a street.
    HouseNumber,
    /// A street, at its middle.
    Street,
    /// A named place smaller than a town: a hamlet, a "lieu-dit", a
    /// district.
    Locality,
    /// A town, a village, a municipality.
    Town,
    /// The area of a postcode: `name` is the postcode, `city` its town.
    Postcode,
    /// A county, a region, a state, a country.
    Region,
}

impl From<AddressKind> for GqlAddressKind {
    fn from(k: AddressKind) -> Self {
        match k {
            AddressKind::HouseNumber => Self::HouseNumber,
            AddressKind::Street => Self::Street,
            AddressKind::Locality => Self::Locality,
            AddressKind::Town => Self::Town,
            AddressKind::Postcode => Self::Postcode,
            AddressKind::Region => Self::Region,
        }
    }
}

/// A postal address, a street, a town or a postcode found by a geocoder.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(name = "AddressMatch")]
pub struct AddressMatchResult {
    /// What it designates.
    pub kind: GqlAddressKind,
    /// The first line: the house number and street, the street, or the
    /// name of the locality, town or area.
    pub name: String,
    /// Its postcode, when known.
    pub postcode: Option<String>,
    /// Its town, when it lies in one (null for a town itself).
    pub city: Option<String>,
    /// The wider area ("77, Seine-et-Marne, Île-de-France").
    pub context: Option<String>,
    /// ISO 3166-1 alpha-2 country code, when known.
    pub country_code: Option<String>,
    /// Latitude.
    pub lat: f64,
    /// Longitude.
    pub lon: f64,
    /// Where it comes from, with the attribution to show with it.
    pub source: Source,
}

impl From<AddressMatch> for AddressMatchResult {
    fn from(m: AddressMatch) -> Self {
        Self {
            kind: m.kind.into(),
            lat: m.position.lat(),
            lon: m.position.lon(),
            name: m.name,
            postcode: m.postcode,
            city: m.city,
            context: m.context,
            country_code: m.country_code,
            source: source(m.source),
        }
    }
}

/// The source of an address, its licence and the text to credit it with.
fn source(s: AddressSource) -> Source {
    match s {
        AddressSource::Ban => Source {
            id: "ban".to_owned(),
            name: "Base Adresse Nationale".to_owned(),
            licence: "Licence Ouverte 2.0".to_owned(),
            attribution: "Base Adresse Nationale, IGN Géoplateforme".to_owned(),
            url: "https://adresse.data.gouv.fr".to_owned(),
        },
        AddressSource::Osm => Source {
            id: "osm".to_owned(),
            name: "OpenStreetMap".to_owned(),
            licence: "ODbL 1.0".to_owned(),
            attribution: "© OpenStreetMap contributors".to_owned(),
            url: "https://www.openstreetmap.org/copyright".to_owned(),
        },
    }
}

/// A town of the map's search: a commune, or another town the places'
/// addresses name, with how many places it holds.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(name = "SearchTown")]
pub struct SearchTown {
    /// Its name, as most of its places write it.
    pub name: String,
    /// The postcode most of its places carry.
    pub postcode: Option<String>,
    /// The French department (`07`, `2A`, `974`), from the commune or the
    /// postcode; null outside France. With the postcode it tells the
    /// homonyms apart (Viviers in Ardèche, in Yonne, in Moselle).
    pub department: Option<String>,
    /// ISO 3166-1 alpha-2 country code, when known.
    pub country_code: Option<String>,
    /// Live places in it, wherever the map looks.
    pub place_count: i32,
    /// The middle of its places, latitude.
    pub lat: f64,
    /// The middle of its places, longitude.
    pub lon: f64,
}

impl From<lunaway_db::towns::TownRow> for SearchTown {
    fn from(t: lunaway_db::towns::TownRow) -> Self {
        Self {
            name: t.name,
            postcode: t.postcode,
            department: t.department,
            country_code: t.country_code,
            place_count: t.places,
            lat: t.lat,
            lon: t.lon,
        }
    }
}

/// The map's search: places, towns, then addresses.
#[derive(SimpleObject)]
#[graphql(name = "SearchAnswer")]
pub struct SearchAnswer {
    /// The places, as `search` ranks them.
    pub places: Vec<Place>,
    /// The towns whose name starts like the text (6 at most): those named
    /// exactly so first, the homonyms of several departments together,
    /// then by how many places they hold. Asked only when selected.
    pub towns: Vec<SearchTown>,
    /// The addresses: in the town the text names first, the exact house
    /// number before its street, otherwise in the geocoders' order, the
    /// answer nearest to `near` first; without the towns `towns` lists.
    pub addresses: Vec<AddressMatchResult>,
    /// False when a geocoder did not answer in time, failed or is paused,
    /// when the client's quota of searches with addresses is spent, or for
    /// a second `searchAll` in the same request: the addresses may be
    /// missing some. Asking again later may give them.
    pub addresses_complete: bool,
}
