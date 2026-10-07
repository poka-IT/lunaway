//! Postal addresses found by a geocoder for the map's search: what a match
//! is, and how the matches of several geocoders become one short list under
//! the places.
//!
//! The places always come first; the addresses follow, nearest to the point
//! the search ranks from first, without the towns the place results already
//! show (the app lists those as towns), and without the same address twice.

use crate::{Position, conflation::normalize::fold};

/// What an address match designates, from the most precise to the widest.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AddressKind {
    /// A house number on a street.
    HouseNumber,
    /// A street, at its middle.
    Street,
    /// A named place smaller than a town: a hamlet, a "lieu-dit", a
    /// district.
    Locality,
    /// A town, a village, a municipality.
    Town,
    /// The area of a postcode.
    Postcode,
    /// A county, a region, a state, a country.
    Region,
}

/// Where an address match comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AddressSource {
    /// The Base Adresse Nationale (France), through IGN's Géoplateforme.
    Ban,
    /// OpenStreetMap, through Lunaway's Photon geocoder.
    Osm,
}

/// One match of a geocoder.
#[derive(Debug, Clone, PartialEq)]
pub struct AddressMatch {
    /// What it designates.
    pub kind: AddressKind,
    /// The first line: the house number and street, the street, or the
    /// name of the locality, town or area.
    pub name: String,
    /// Postcode, when known.
    pub postcode: Option<String>,
    /// The town, when the match is inside one (null for a town itself).
    pub city: Option<String>,
    /// The wider area, for telling two matches of the same name apart
    /// ("77, Seine-et-Marne, Île-de-France").
    pub context: Option<String>,
    /// ISO 3166-1 alpha-2 country code, upper case, when known.
    pub country_code: Option<String>,
    /// Where it is.
    pub position: Position,
    /// Its source.
    pub source: AddressSource,
    /// How well it matches the text, 0 to 1, as its geocoder rates it;
    /// null when the geocoder gives no rating.
    pub score: Option<f64>,
}

impl AddressMatch {
    /// The town this match stands for, when it is one: a town, or the area
    /// of a postcode.
    fn as_town(&self) -> Option<&str> {
        match self.kind {
            AddressKind::Town => Some(&self.name),
            AddressKind::Postcode => Some(self.city.as_deref().unwrap_or(&self.name)),
            _ => None,
        }
    }
}

/// A town the place results already show: the municipality of a place
/// whose name starts like the text, as the app lists them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShownTown {
    folded: String,
    postcode: Option<String>,
}

/// The towns the app shows for the place results of `text`: the cities of
/// `places` (city and postcode) whose folded name starts like the folded
/// text, as the app's own list of towns is built.
#[must_use]
pub fn shown_towns<'a>(
    text: &str,
    places: impl IntoIterator<Item = (Option<&'a str>, Option<&'a str>)>,
) -> Vec<ShownTown> {
    let wanted = fold(text);
    let mut towns: Vec<ShownTown> = Vec::new();
    for (city, postcode) in places {
        let Some(city) = city else { continue };
        let folded = fold(city);
        if folded.is_empty() || !folded.starts_with(&wanted) {
            continue;
        }
        let town = ShownTown {
            folded,
            postcode: postcode.map(str::to_owned),
        };
        if !towns.contains(&town) {
            towns.push(town);
        }
    }
    towns
}

/// Two matches closer than this, of the same kind and the same folded
/// name, are the same address told by two sources, metres.
const SAME_ADDRESS_M: f64 = 150.0;

/// A rating below this share of the best rating of the same geocoder is a
/// weak match: the geocoder fills its list with them when the text names
/// one address precisely ("6 Rue de Rome" for "6 rue du Dôme").
const WEAK_SHARE: f64 = 0.75;

/// A rating below this is no match at all, whatever the others: the BAN
/// answers a text naming a street abroad with a French one of a remote
/// likeness ("Neuhof Hinter Den Gaerten, Berling" rated 0.34 for "unter den
/// linden 77 berlin"), while a text still being typed rates its right
/// match low ("Boulevard du Port, Amiens" 0.42 for "bd du po amiens");
/// measured on 2026-10-07.
const MIN_SCORE: f64 = 0.35;

/// The list shown under the places: `matches` without the weak matches of
/// a rated geocoder (under [`MIN_SCORE`], or far below its best), without
/// the towns already in `towns`, without the same address twice (the first
/// kept), then nearest to `near` first (the order of the geocoders, each
/// already biased towards `near`, when there is no point), at most `max`.
#[must_use]
pub fn rank(
    matches: Vec<AddressMatch>,
    towns: &[ShownTown],
    near: Option<Position>,
    max: usize,
) -> Vec<AddressMatch> {
    let best = |source: AddressSource| {
        matches
            .iter()
            .filter(|m| m.source == source)
            .filter_map(|m| m.score)
            .fold(None, |acc: Option<f64>, s| {
                Some(acc.map_or(s, |a| a.max(s)))
            })
    };
    let best_ban = best(AddressSource::Ban);
    let best_osm = best(AddressSource::Osm);
    let mut kept: Vec<(AddressMatch, String)> = Vec::new();
    for m in matches {
        let top = match m.source {
            AddressSource::Ban => best_ban,
            AddressSource::Osm => best_osm,
        };
        if let Some(score) = m.score
            && (score < MIN_SCORE || top.is_some_and(|top| score < top * WEAK_SHARE))
        {
            continue;
        }
        if let Some(town) = m.as_town() {
            let folded = fold(town);
            let shown = towns.iter().any(|t| {
                t.folded == folded
                    && match (&t.postcode, &m.postcode) {
                        (Some(a), Some(b)) => a == b,
                        _ => true,
                    }
            });
            if shown {
                continue;
            }
        }
        let key = fold(&m.name);
        let twice = kept.iter().any(|(k, kkey)| {
            k.kind == m.kind && *kkey == key && k.position.distance_m(m.position) < SAME_ADDRESS_M
        });
        if !twice {
            kept.push((m, key));
        }
    }
    let mut out: Vec<AddressMatch> = kept.into_iter().map(|(m, _)| m).collect();
    if let Some(near) = near {
        // A stable sort: two matches at the same distance keep the
        // geocoders' order.
        out.sort_by(|a, b| {
            a.position
                .distance_m(near)
                .total_cmp(&b.position.distance_m(near))
        });
    }
    out.truncate(max);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).expect("a valid test position")
    }

    fn town(name: &str, postcode: Option<&str>, p: Position) -> AddressMatch {
        AddressMatch {
            kind: AddressKind::Town,
            name: name.to_owned(),
            postcode: postcode.map(str::to_owned),
            city: None,
            context: None,
            country_code: Some("FR".to_owned()),
            position: p,
            source: AddressSource::Ban,
            score: Some(0.9),
        }
    }

    fn street(name: &str, p: Position, source: AddressSource, score: Option<f64>) -> AddressMatch {
        AddressMatch {
            kind: AddressKind::Street,
            name: name.to_owned(),
            postcode: None,
            city: Some("Somewhere".to_owned()),
            context: None,
            country_code: None,
            position: p,
            source,
            score,
        }
    }

    #[test]
    fn a_town_the_places_already_show_is_left_out() {
        let towns = shown_towns(
            "vaux le",
            [
                (Some("Vaux-le-Pénil"), Some("77000")),
                (Some("Melun"), Some("77000")),
            ],
        );
        assert_eq!(
            towns.len(),
            1,
            "only the cities starting like the text are towns"
        );
        let matches = vec![
            town("Vaux-le-Pénil", Some("77000"), at(48.52, 2.68)),
            town("Vaux-le-Vicomte", None, at(48.56, 2.71)),
        ];
        let out = rank(matches, &towns, None, 5);
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["Vaux-le-Vicomte"],
            "the app lists Vaux-le-Pénil among the towns already"
        );
    }

    #[test]
    fn a_town_of_the_same_name_with_another_postcode_stays() {
        let towns = shown_towns("saint", [(Some("Saint-Denis"), Some("93200"))]);
        let out = rank(
            vec![town("Saint-Denis", Some("97400"), at(-20.88, 55.45))],
            &towns,
            None,
            5,
        );
        assert_eq!(out.len(), 1, "La Réunion's Saint-Denis is another town");
    }

    #[test]
    fn the_nearest_address_comes_first() {
        let near = at(48.85, 2.35);
        let out = rank(
            vec![
                street(
                    "Rue de la Gare",
                    at(43.3, 5.4),
                    AddressSource::Ban,
                    Some(0.9),
                ),
                street(
                    "Rue de la Gare",
                    at(48.8, 2.3),
                    AddressSource::Ban,
                    Some(0.9),
                ),
                street("Rue de la Gare", at(50.8, 4.3), AddressSource::Osm, None),
            ],
            &[],
            Some(near),
            5,
        );
        let lats: Vec<f64> = out.iter().map(|m| m.position.lat()).collect();
        assert_eq!(
            lats,
            [48.8, 50.8, 43.3],
            "nearest first, whatever the source"
        );
    }

    #[test]
    fn without_a_point_the_geocoders_order_stays() {
        let out = rank(
            vec![
                street("B", at(43.3, 5.4), AddressSource::Ban, Some(0.9)),
                street("A", at(48.8, 2.3), AddressSource::Ban, Some(0.9)),
            ],
            &[],
            None,
            5,
        );
        assert_eq!(out[0].name, "B");
    }

    #[test]
    fn weak_matches_of_a_rated_geocoder_are_dropped() {
        let p = at(48.58, 7.75);
        let out = rank(
            vec![
                street("Rue du Dôme", p, AddressSource::Ban, Some(0.83)),
                street("6 Rue de Rome", p, AddressSource::Ban, Some(0.6)),
                street("Rue du Dôme", at(48.0, 7.0), AddressSource::Osm, None),
            ],
            &[],
            None,
            5,
        );
        assert_eq!(
            out.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
            ["Rue du Dôme", "Rue du Dôme"],
            "an unrated match is never judged weak"
        );
    }

    #[test]
    fn a_rating_too_low_is_no_match_even_alone() {
        let out = rank(
            vec![street(
                "Neuhof Hinter Den Gaerten",
                at(49.25, 6.5),
                AddressSource::Ban,
                Some(0.34),
            )],
            &[],
            None,
            5,
        );
        assert!(out.is_empty(), "the best of nothing is still nothing");
    }

    #[test]
    fn the_same_address_from_two_sources_shows_once() {
        let out = rank(
            vec![
                street(
                    "Rue de Siam",
                    at(48.3900, -4.4860),
                    AddressSource::Ban,
                    Some(0.9),
                ),
                street(
                    "Rue de  SIAM",
                    at(48.3905, -4.4862),
                    AddressSource::Osm,
                    None,
                ),
            ],
            &[],
            None,
            5,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].source, AddressSource::Ban, "the first told is kept");
    }

    #[test]
    fn the_list_is_cut_at_its_size() {
        let out = rank(
            (0..9)
                .map(|i| {
                    street(
                        &format!("Rue {i}"),
                        at(45.0, 1.0 + f64::from(i)),
                        AddressSource::Osm,
                        None,
                    )
                })
                .collect(),
            &[],
            None,
            3,
        );
        assert_eq!(out.len(), 3);
    }
}
