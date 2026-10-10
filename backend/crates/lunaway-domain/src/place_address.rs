//! The postal address a place shows: its sources' address, completed by a
//! reverse geocoding of its position when no source gives a street.
//!
//! Most places come with an address from a source (OpenStreetMap's
//! `addr:*`, the external community source, Atout France, DATAtourisme).
//! The others, an unnamed car park of OpenStreetMap, a rest area, a spot
//! in nature the partner only placed in its town, are asked once of
//! Lunaway's own Photon (OpenStreetMap data, ODbL): the street nearest to
//! the position, the house number when one stands right there, the
//! postcode and the town. The answer is kept with the position asked, and
//! asked again when the place moves by more than [`MOVED_M`].
//!
//! A geocoded address replaces the source's whole, never a part of it: a
//! street of one source beside the postcode of another would make an
//! address nobody wrote, credited to one of them. A private host
//! (`homestay`) never shows a street nor a number, whatever any source
//! says: only its town (`docs/data-sources.md`).

use crate::{
    Address, PlaceKind, Position,
    conflation::{AlternativeValue, FieldProvenance, render_address},
    source::SourceId,
};

/// Farthest a house number may stand from the place to be its address: a
/// car park's entrance beside the building, not the house across the
/// square.
pub const HOUSE_RADIUS_M: f64 = 20.0;
/// Farthest the point Photon gives for a street (the middle of its way)
/// may stand from the place for the street to be its address. On a
/// sample of 400 production places without a street on 2026-10-10, 204
/// found a street within 30 m and 248 within 60 m, against 269 within
/// 100 m, where the street nearest by its middle is often not the one
/// the place opens on.
pub const STREET_RADIUS_M: f64 = 50.0;
/// Farthest a feature may stand for its town and postcode to be the
/// place's: the radius the reverse geocoding asks (Photon's `radius`, in
/// kilometres, is 1).
pub const TOWN_RADIUS_M: f64 = 1_000.0;
/// How far a place may move before its geocoded address is asked again:
/// beyond it, another house number may be the nearest
/// ([`HOUSE_RADIUS_M`] is within it twice over), and a geocoded address
/// no longer applies to the place until it is.
pub const MOVED_M: f64 = 25.0;

/// What a reverse geocoder says of a feature near the position asked.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ReverseFeature {
    /// Photon's `type`: `house`, `street`, `locality`, `district`, `city`.
    pub kind: String,
    /// Where the feature is (the middle of a street).
    pub position: Option<Position>,
    /// Its name: the street's for a street, the town's for a town.
    pub name: Option<String>,
    /// Its house number, for a house.
    pub house_number: Option<String>,
    /// The street it stands on.
    pub street: Option<String>,
    /// Its postcode.
    pub postcode: Option<String>,
    /// Its town.
    pub city: Option<String>,
    /// ISO 3166-1 alpha-2, upper case.
    pub country_code: Option<String>,
}

/// The address a reverse geocoding gave for a position, kept with that
/// position.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Geocoded {
    /// The position asked.
    pub asked: Option<Position>,
    /// The house number, when one stands within [`HOUSE_RADIUS_M`].
    pub house_number: Option<String>,
    /// The street, when one runs within [`STREET_RADIUS_M`].
    pub street: Option<String>,
    /// The postcode of the nearest feature that has one.
    pub postcode: Option<String>,
    /// The town of the nearest feature that names one.
    pub city: Option<String>,
    /// The country of the nearest feature.
    pub country_code: Option<String>,
}

impl Geocoded {
    /// Whether it still describes a place at `position`: asked within
    /// [`MOVED_M`] of it.
    #[must_use]
    pub fn applies_at(&self, position: Position) -> bool {
        self.asked
            .is_some_and(|asked| asked.distance_m(position) <= MOVED_M)
    }

    /// The street line, its house number first, as the place's other
    /// sources write it (`12 Rue de la Gare`).
    #[must_use]
    pub fn street_line(&self) -> Option<String> {
        let street = self.street.as_deref()?;
        Some(match self.house_number.as_deref() {
            Some(n) => format!("{n} {street}"),
            None => street.to_owned(),
        })
    }
}

fn clean(s: Option<&str>) -> Option<String> {
    s.map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}

/// Whether a place of `kind` takes the number of a house beside it: one an
/// operator runs (a campsite, a motorhome or service area, a farm, a
/// service), whose address is the building's. A car park, a rest area or
/// a spot in nature beside a house is not that house: its copied address
/// would lead a driver to a neighbour's door.
#[must_use]
pub fn keeps_house_number(kind: PlaceKind) -> bool {
    matches!(
        kind,
        PlaceKind::Campsite
            | PlaceKind::MotorhomeArea
            | PlaceKind::ServiceArea
            | PlaceKind::Farm
            | PlaceKind::ExtraService
    )
}

/// What the reverse geocoding of `asked` gives a place of `kind`, from
/// `features` (nearest first, as Photon answers): the house number of a
/// house within [`HOUSE_RADIUS_M`] with its street for a place that keeps
/// one ([`keeps_house_number`]), else the nearest street within
/// [`STREET_RADIUS_M`] (a street's own name, or the street a house or a
/// point stands on); the town and postcode of the nearest features within
/// [`TOWN_RADIUS_M`] that name them. A private host gets neither a street
/// nor a number: not even kept aside.
#[must_use]
pub fn pick(kind: PlaceKind, asked: Position, features: &[ReverseFeature]) -> Geocoded {
    let mut out = Geocoded {
        asked: Some(asked),
        ..Geocoded::default()
    };
    let host = kind == PlaceKind::Homestay;
    let mut near: Vec<(f64, &ReverseFeature)> = features
        .iter()
        .filter_map(|f| f.position.map(|p| (p.distance_m(asked), f)))
        .filter(|(d, _)| *d <= TOWN_RADIUS_M)
        .collect();
    near.sort_by(|a, b| a.0.total_cmp(&b.0));
    for (d, f) in near.iter().filter(|_| keeps_house_number(kind)) {
        if f.kind == "house"
            && *d <= HOUSE_RADIUS_M
            && let (Some(n), Some(s)) =
                (clean(f.house_number.as_deref()), clean(f.street.as_deref()))
        {
            out.house_number = Some(n);
            out.street = Some(s);
            break;
        }
    }
    if out.street.is_none() && !host {
        out.street = near
            .iter()
            .filter(|(d, _)| *d <= STREET_RADIUS_M)
            .find_map(|(_, f)| {
                if f.kind == "street" {
                    clean(f.name.as_deref())
                } else {
                    clean(f.street.as_deref())
                }
            });
    }
    out.city = near.iter().find_map(|(_, f)| {
        if f.kind == "city" {
            clean(f.name.as_deref())
        } else {
            clean(f.city.as_deref())
        }
    });
    out.postcode = near.iter().find_map(|(_, f)| clean(f.postcode.as_deref()));
    out.country_code = near.iter().find_map(|(_, f)| {
        clean(f.country_code.as_deref())
            .map(|c| c.to_ascii_uppercase())
            .filter(|c| c.len() == 2)
    });
    out
}

/// Whether a place of `kind` with the address `shown` needs a reverse
/// geocoding, one [`complete`] could use: no street (a private host never
/// gets one), or, without a street, no town and no postcode.
#[must_use]
pub fn wants_geocoding(kind: PlaceKind, shown: &Address) -> bool {
    let host = kind == PlaceKind::Homestay;
    (!host && shown.street.is_none())
        || ((host || shown.street.is_none()) && shown.city.is_none() && shown.postcode.is_none())
}

/// The address a place shows instead of its sources' own, and whether it
/// came from the reverse geocoding (which the provenance then credits,
/// [`credit_geocoder`]).
#[derive(Debug, Clone, PartialEq)]
pub struct Completed {
    /// The address shown.
    pub address: Address,
    /// Whether it is the geocoded one; false for a private host's address
    /// without its street.
    pub geocoded: bool,
}

/// The address a place of `kind` at `position` shows, from its sources'
/// `source` address and its `geocoded` one; `None` when it shows the
/// source's as it is.
///
/// The geocoded address replaces the source's whole when it has a street
/// the source lacks, or, without a street on either side, when the source
/// names neither a town nor a postcode; a private host takes at most its
/// town and postcode from it, and loses a street a source gave. A geocoded
/// address asked farther than [`MOVED_M`] from `position` is not used.
#[must_use]
pub fn complete(
    kind: PlaceKind,
    position: Position,
    source: &Address,
    geocoded: Option<&Geocoded>,
) -> Option<Completed> {
    let host = kind == PlaceKind::Homestay;
    let g = geocoded.filter(|g| g.applies_at(position));
    let no_town = source.city.is_none() && source.postcode.is_none();
    let country = || {
        source
            .country_code
            .clone()
            .or_else(|| g.and_then(|g| g.country_code.clone()))
    };
    if let Some(g) = g {
        if !host
            && source.street.is_none()
            && let Some(street) = g.street_line()
        {
            return Some(Completed {
                address: Address {
                    street: Some(street),
                    postcode: g.postcode.clone(),
                    city: g.city.clone(),
                    country_code: country(),
                    city_code: None,
                },
                geocoded: true,
            });
        }
        if no_town
            && (host || source.street.is_none())
            && (g.city.is_some() || g.postcode.is_some())
        {
            return Some(Completed {
                address: Address {
                    street: None,
                    postcode: g.postcode.clone(),
                    city: g.city.clone(),
                    country_code: country(),
                    city_code: None,
                },
                geocoded: true,
            });
        }
    }
    (host && source.street.is_some()).then(|| Completed {
        address: Address {
            street: None,
            ..source.clone()
        },
        geocoded: false,
    })
}

/// The source credited for a geocoded address: Photon serves
/// OpenStreetMap's data, under the ODbL.
#[must_use]
pub fn geocoder_source() -> SourceId {
    SourceId::OSM
}

/// `provenance` with its `address` entry crediting the reverse geocoding,
/// the sources' own address kept among the alternatives when there was
/// one. Called only when [`complete`] took the geocoded address.
pub fn credit_geocoder(provenance: &mut Vec<FieldProvenance>, source: &Address) {
    let field = "address";
    let previous = provenance.iter().position(|p| p.field == field);
    let mut alternatives = Vec::new();
    if let Some(i) = previous {
        let old = provenance.remove(i);
        let rendered = render_address(source);
        if !rendered.is_empty() && old.source_id != geocoder_source() {
            alternatives.push(AlternativeValue {
                source_id: old.source_id.clone(),
                value: rendered,
            });
        }
        alternatives.extend(
            old.alternatives
                .into_iter()
                .filter(|a| a.source_id != geocoder_source()),
        );
    }
    let entry = FieldProvenance {
        field: field.to_owned(),
        source_id: geocoder_source(),
        alternatives,
    };
    match previous {
        Some(i) => provenance.insert(i, entry),
        None => provenance.push(entry),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    /// A point `metres` north of `p`.
    fn north(p: Position, metres: f64) -> Position {
        at(p.lat() + metres / 111_195.0, p.lon())
    }

    fn feature(kind: &str, p: Position) -> ReverseFeature {
        ReverseFeature {
            kind: kind.to_owned(),
            position: Some(p),
            ..ReverseFeature::default()
        }
    }

    const VIVIERS: (f64, f64) = (44.4818, 4.6896);

    fn viviers() -> Position {
        at(VIVIERS.0, VIVIERS.1)
    }

    #[test]
    fn a_house_beside_the_place_gives_its_number_and_street() {
        let p = viviers();
        let house = ReverseFeature {
            house_number: Some("22".into()),
            street: Some("Grande Rue".into()),
            city: Some("Viviers".into()),
            postcode: Some("07220".into()),
            country_code: Some("fr".into()),
            ..feature("house", north(p, 8.0))
        };
        let g = pick(PlaceKind::MotorhomeArea, p, &[house]);
        assert_eq!(g.street_line().as_deref(), Some("22 Grande Rue"));
        assert_eq!(g.postcode.as_deref(), Some("07220"));
        assert_eq!(g.city.as_deref(), Some("Viviers"));
        assert_eq!(g.country_code.as_deref(), Some("FR"));
    }

    #[test]
    fn a_car_park_beside_a_house_takes_its_street_not_its_number() {
        let p = viviers();
        let house = ReverseFeature {
            house_number: Some("22".into()),
            street: Some("Grande Rue".into()),
            city: Some("Viviers".into()),
            ..feature("house", north(p, 8.0))
        };
        let g = pick(PlaceKind::Parking, p, std::slice::from_ref(&house));
        assert_eq!(
            g.street_line().as_deref(),
            Some("Grande Rue"),
            "the neighbour's door is not the car park's address"
        );
        assert_eq!(g.city.as_deref(), Some("Viviers"));
    }

    #[test]
    fn a_private_host_gets_its_town_and_no_street_at_all() {
        let p = viviers();
        let house = ReverseFeature {
            house_number: Some("22".into()),
            street: Some("Grande Rue".into()),
            city: Some("Viviers".into()),
            postcode: Some("07220".into()),
            ..feature("house", north(p, 8.0))
        };
        let street = ReverseFeature {
            name: Some("Rue de la Gare".into()),
            ..feature("street", north(p, 15.0))
        };
        let g = pick(PlaceKind::Homestay, p, &[house, street]);
        assert_eq!(g.street, None, "not even kept aside for a host");
        assert_eq!(g.house_number, None);
        assert_eq!(g.city.as_deref(), Some("Viviers"));
        assert_eq!(g.postcode.as_deref(), Some("07220"));
    }

    #[test]
    fn a_house_across_the_square_gives_its_street_without_its_number() {
        let p = viviers();
        let house = ReverseFeature {
            house_number: Some("35".into()),
            street: Some("Grande Rue".into()),
            ..feature("house", north(p, 40.0))
        };
        let g = pick(PlaceKind::MotorhomeArea, p, &[house]);
        assert_eq!(
            g.street_line().as_deref(),
            Some("Grande Rue"),
            "a number 40 m away is not the place's address, its street is"
        );
    }

    #[test]
    fn a_street_too_far_gives_only_the_town() {
        let p = viviers();
        let street = ReverseFeature {
            name: Some("Route du Barrage".into()),
            city: Some("Saint-Agnan".into()),
            postcode: Some("58230".into()),
            ..feature("street", north(p, 190.0))
        };
        let g = pick(PlaceKind::MotorhomeArea, p, &[street]);
        assert_eq!(g.street, None, "a street 190 m away is not the place's");
        assert_eq!(g.city.as_deref(), Some("Saint-Agnan"));
        assert_eq!(g.postcode.as_deref(), Some("58230"));
    }

    #[test]
    fn the_nearest_feature_wins_whatever_order_the_geocoder_gives() {
        let p = viviers();
        let far = ReverseFeature {
            name: Some("Rue Lointaine".into()),
            ..feature("street", north(p, 45.0))
        };
        let near = ReverseFeature {
            name: Some("Chemin Proche".into()),
            ..feature("street", north(p, 10.0))
        };
        assert_eq!(
            pick(PlaceKind::MotorhomeArea, p, &[far, near])
                .street
                .as_deref(),
            Some("Chemin Proche")
        );
    }

    #[test]
    fn a_town_feature_names_the_town_and_nothing_beyond_a_kilometre_counts() {
        let p = viviers();
        let town = ReverseFeature {
            name: Some("Viviers".into()),
            ..feature("city", north(p, 600.0))
        };
        let beyond = ReverseFeature {
            city: Some("Le Teil".into()),
            postcode: Some("07400".into()),
            ..feature("street", north(p, 1_500.0))
        };
        let g = pick(PlaceKind::MotorhomeArea, p, &[beyond, town]);
        assert_eq!(g.city.as_deref(), Some("Viviers"));
        assert_eq!(g.postcode, None, "a postcode 1.5 km away is not asked for");
    }

    fn geocoded(p: Position) -> Geocoded {
        Geocoded {
            asked: Some(p),
            house_number: Some("4".into()),
            street: Some("Rue de la Gare".into()),
            postcode: Some("07220".into()),
            city: Some("Viviers".into()),
            country_code: Some("FR".into()),
        }
    }

    #[test]
    fn a_street_the_sources_lack_replaces_their_whole_address() {
        let p = viviers();
        let source = Address {
            postcode: Some("07200".into()),
            city: Some("Aubenas".into()),
            country_code: Some("FR".into()),
            ..Address::default()
        };
        let shown = complete(PlaceKind::Parking, p, &source, Some(&geocoded(p))).unwrap();
        assert!(shown.geocoded);
        let shown = shown.address;
        assert_eq!(shown.street.as_deref(), Some("4 Rue de la Gare"));
        assert_eq!(
            (shown.postcode.as_deref(), shown.city.as_deref()),
            (Some("07220"), Some("Viviers")),
            "never one source's town beside another's street"
        );
    }

    #[test]
    fn a_source_s_street_stays() {
        let p = viviers();
        let source = Address {
            street: Some("12 Avenue Mazarin".into()),
            ..Address::default()
        };
        assert_eq!(
            complete(PlaceKind::Parking, p, &source, Some(&geocoded(p))),
            None
        );
    }

    #[test]
    fn a_geocoding_of_another_position_is_not_used() {
        let p = viviers();
        let source = Address::default();
        let old = geocoded(north(p, 30.0));
        assert_eq!(
            complete(PlaceKind::Parking, p, &source, Some(&old)),
            None,
            "a place moved by 30 m waits for its new address"
        );
        assert!(geocoded(north(p, 20.0)).applies_at(p));
    }

    #[test]
    fn a_private_host_never_shows_a_street() {
        let p = viviers();
        let only_country = Address {
            country_code: Some("FR".into()),
            ..Address::default()
        };
        let shown = complete(PlaceKind::Homestay, p, &only_country, Some(&geocoded(p)))
            .unwrap()
            .address;
        assert_eq!(shown.street, None, "a host's street is never shown");
        assert_eq!(shown.city.as_deref(), Some("Viviers"));
        let with_street = Address {
            street: Some("3 Impasse des Lilas".into()),
            city: Some("Viviers".into()),
            ..Address::default()
        };
        let shown = complete(PlaceKind::Homestay, p, &with_street, None).unwrap();
        assert!(!shown.geocoded, "the source's town, not the geocoder's");
        let shown = shown.address;
        assert_eq!(shown.street, None, "even when a source gives one");
        assert_eq!(shown.city.as_deref(), Some("Viviers"));
    }

    #[test]
    fn a_town_without_a_street_comes_only_when_the_source_names_none() {
        let p = viviers();
        let mut g = geocoded(p);
        g.street = None;
        g.house_number = None;
        let source_town = Address {
            city: Some("Viviers".into()),
            ..Address::default()
        };
        assert_eq!(complete(PlaceKind::Nature, p, &source_town, Some(&g)), None);
        let only_country = Address {
            country_code: Some("IT".into()),
            ..Address::default()
        };
        let shown = complete(PlaceKind::RestArea, p, &only_country, Some(&g))
            .unwrap()
            .address;
        assert_eq!(shown.city.as_deref(), Some("Viviers"));
        assert_eq!(
            shown.country_code.as_deref(),
            Some("IT"),
            "the source's country stays"
        );
    }

    #[test]
    fn who_needs_a_geocoding() {
        let none = Address::default();
        let town = Address {
            city: Some("Viviers".into()),
            ..Address::default()
        };
        assert!(wants_geocoding(PlaceKind::Parking, &none));
        assert!(
            wants_geocoding(PlaceKind::Parking, &town),
            "a street is still missing"
        );
        assert!(
            !wants_geocoding(PlaceKind::Homestay, &town),
            "a host never gets a street"
        );
        assert!(wants_geocoding(PlaceKind::Homestay, &none));
        let street_only = Address {
            street: Some("12 Avenue Mazarin".into()),
            ..Address::default()
        };
        assert!(
            !wants_geocoding(PlaceKind::Parking, &street_only),
            "a source's street never takes another's town"
        );
    }

    #[test]
    fn the_geocoder_is_credited_and_the_source_s_address_kept_as_another_value() {
        let mut provenance = vec![
            FieldProvenance {
                field: "name".into(),
                source_id: SourceId::EXTCOM,
                alternatives: vec![],
            },
            FieldProvenance {
                field: "address".into(),
                source_id: SourceId::EXTCOM,
                alternatives: vec![],
            },
        ];
        let source = Address {
            postcode: Some("30270".into()),
            city: Some("Saint-Jean-du-Gard".into()),
            ..Address::default()
        };
        credit_geocoder(&mut provenance, &source);
        assert_eq!(provenance[1].field, "address", "the entry keeps its place");
        assert_eq!(provenance[1].source_id, SourceId::OSM);
        assert_eq!(provenance[1].alternatives[0].source_id, SourceId::EXTCOM);
        assert_eq!(
            provenance[1].alternatives[0].value,
            "30270 Saint-Jean-du-Gard"
        );
    }
}
