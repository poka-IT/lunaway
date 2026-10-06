//! What one source says about one spot, mapped onto the Lunaway taxonomy.
//!
//! Every adapter produces a [`NormalizedRecord`]; the conflation matches
//! records of different sources and resolves each field of the resulting
//! place from them. The record is stored as JSON next to the raw payload, so
//! its serialised form is part of the database: fields are only added, with a
//! serde default, never renamed.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::{Activity, OvernightStatus, PlaceKind, Service, geo::Position};

/// A postal address, every part optional because sources rarely give all of it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Address {
    /// Street with its house number, as the source spells it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub street: Option<String>,
    /// Postcode.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub postcode: Option<String>,
    /// Municipality name.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub city: Option<String>,
    /// ISO 3166-1 alpha-2 country code.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    /// Official municipality code (INSEE code in France). Postcodes span
    /// several municipalities, so this is the sharper "same municipality"
    /// signal when both records have it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub city_code: Option<String>,
}

impl Address {
    /// Whether no part of the address is known.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.street.is_none()
            && self.postcode.is_none()
            && self.city.is_none()
            && self.country_code.is_none()
            && self.city_code.is_none()
    }
}

/// One source's description of one spot, normalised.
///
/// `None` (or an empty set) means the source does not say; it never means
/// "no". A source that states the absence of a service has no way to say it
/// here yet, which is why sets are only ever resolved from a source that
/// lists something.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NormalizedRecord {
    /// What the spot is.
    pub kind: PlaceKind,
    /// Display name as the source gives it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Where the source puts the spot.
    pub position: Position,
    /// How far, in metres, the real spot may be from `position`: half the
    /// diagonal of an area mapped as a polygon, the precision of a geocoded
    /// address, 0 for a point mapped on the spot.
    #[serde(default)]
    pub accuracy_m: f64,
    /// The position is only the municipality's (a geocoder that found the
    /// town and not the address): good enough to list the spot, not to
    /// drive to it.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub position_approximate: bool,
    /// Whether a night may be spent there, `Unknown` when the source does not
    /// say.
    #[serde(default = "unknown_overnight")]
    pub overnight: OvernightStatus,
    /// Services the source lists.
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    pub services: BTreeSet<Service>,
    /// Activities the source lists.
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    pub activities: BTreeSet<Activity>,
    /// Free text.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Every description the source gives, by language: a BCP 47 tag, or
    /// [`UNDETERMINED_LANGUAGE`] when the source does not say.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub descriptions: BTreeMap<String, String>,
    /// Postal address.
    #[serde(default, skip_serializing_if = "Address::is_empty")]
    pub address: Address,
    /// Price of a night, in euros; 0 means free.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_parking_eur: Option<f64>,
    /// Price of the services (water, dump), in euros; 0 means free.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_services_eur: Option<f64>,
    /// Maximum vehicle height, in metres.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_height_m: Option<f64>,
    /// Maximum vehicle length, in metres.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_length_m: Option<f64>,
    /// Maximum vehicle width, in metres.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_width_m: Option<f64>,
    /// Maximum vehicle weight, in tonnes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_weight_t: Option<f64>,
    /// Number of motorhome pitches (or of pitches, for a campsite).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capacity: Option<u32>,
    /// Opening hours in the OSM `opening_hours` syntax.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opening_hours: Option<String>,
    /// Website URL.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub website: Option<String>,
    /// Phone number as the source writes it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    /// Official classification in stars (1 to 5), for a campsite.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stars: Option<u8>,
    /// Wikidata item (`Q123`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wikidata: Option<String>,
    /// OpenStreetMap element the record is, or cites (`node/123`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub osm_ref: Option<String>,
    /// Wikipedia article, as OpenStreetMap writes it (`fr:Lac d'Annecy`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wikipedia: Option<String>,
}

/// The BCP 47 tag of a text whose language the source does not state.
pub const UNDETERMINED_LANGUAGE: &str = "und";

/// Whether `tag` looks like a BCP 47 language tag (`fr`, `pt-BR`): a primary
/// subtag of two or three letters, then subtags of two to eight characters.
/// OpenStreetMap keys such as `description:payment` are not languages.
#[must_use]
pub fn is_language_tag(tag: &str) -> bool {
    let mut parts = tag.split('-');
    let primary_ok = parts
        .next()
        .is_some_and(|p| (2..=3).contains(&p.len()) && p.bytes().all(|b| b.is_ascii_lowercase()));
    primary_ok
        && parts.all(|p| (2..=8).contains(&p.len()) && p.bytes().all(|b| b.is_ascii_alphanumeric()))
}

const fn unknown_overnight() -> OvernightStatus {
    OvernightStatus::Unknown
}

impl NormalizedRecord {
    /// A record that only knows its kind and position; adapters fill the rest.
    #[must_use]
    pub fn new(kind: PlaceKind, position: Position) -> Self {
        Self {
            kind,
            name: None,
            position,
            accuracy_m: 0.0,
            position_approximate: false,
            overnight: OvernightStatus::Unknown,
            services: BTreeSet::new(),
            activities: BTreeSet::new(),
            description: None,
            address: Address::default(),
            price_parking_eur: None,
            price_services_eur: None,
            max_height_m: None,
            max_length_m: None,
            max_width_m: None,
            max_weight_t: None,
            capacity: None,
            opening_hours: None,
            website: None,
            phone: None,
            stars: None,
            wikidata: None,
            osm_ref: None,
            descriptions: BTreeMap::new(),
            wikipedia: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_minimal_record_serialises_compactly_and_reads_back() {
        let r = NormalizedRecord::new(PlaceKind::Parking, Position::new(45.5, 3.25).unwrap());
        let json = serde_json::to_value(&r).unwrap();
        assert_eq!(
            json,
            serde_json::json!({
                "kind": "parking",
                "position": {"lat": 45.5, "lon": 3.25},
                "accuracy_m": 0.0,
                "overnight": "unknown"
            }),
            "absent facts are left out, so the stored JSON stays small"
        );
        let back: NormalizedRecord = serde_json::from_value(json).unwrap();
        assert_eq!(back, r);
    }

    #[test]
    fn language_tags_are_told_from_other_keys() {
        for good in ["fr", "en", "pt-BR", "zh-Hant", "und", "gsw"] {
            assert!(is_language_tag(good), "{good}");
        }
        for bad in ["payment", "FR", "f", "", "fr-", "fr_FR", "de-x"] {
            assert!(!is_language_tag(bad), "{bad}");
        }
    }

    #[test]
    fn a_full_record_round_trips() {
        let mut r = NormalizedRecord::new(PlaceKind::Campsite, Position::new(47.4, -0.56).unwrap());
        r.name = Some("Camping des Varennes".into());
        r.services = [Service::Toilets, Service::DrinkingWater].into();
        r.address.postcode = Some("49610".into());
        r.stars = Some(3);
        r.price_parking_eur = Some(12.5);
        let back: NormalizedRecord =
            serde_json::from_str(&serde_json::to_string(&r).unwrap()).unwrap();
        assert_eq!(back, r);
    }
}
