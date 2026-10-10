//! Countries and sync regions.
//!
//! Which country a point is in comes from the boundaries the
//! `country-boundaries` crate embeds (derived from OpenStreetMap, ODbL, the
//! licence of the places database): the importers tag each record with it,
//! the opening hours take their time zone and holidays from it, and a place
//! syncs with the region it gives.
//!
//! A sync region is the unit a device downloads: a French region (ISO
//! 3166-2, `FR-BRE`) inside France, a country (ISO 3166-1, `ES`) elsewhere.
//! A microstate goes with the region around it, so a device that keeps
//! Provence also keeps Monaco. The database computes the same mapping
//! (`lunaway_sync_region` in the migrations); a test holds the two together.

use std::{collections::BTreeSet, sync::LazyLock};

use country_boundaries::{BOUNDARIES_ODBL_360X180, CountryBoundaries, LatLon};

use crate::Position;

/// The embedded boundaries, decoded once. `None` only if the embedded file
/// were unreadable, which a test rules out; lookups then find no country.
static BOUNDARIES: LazyLock<Option<CountryBoundaries>> =
    LazyLock::new(|| CountryBoundaries::from_reader(BOUNDARIES_ODBL_360X180).ok());

/// The areas `p` lies in, smallest first: subdivisions (`PT-20` for the
/// Azores, `IC` for the Canary Islands) before their country.
#[must_use]
pub fn areas_at(p: Position) -> Vec<&'static str> {
    let Some(boundaries) = BOUNDARIES.as_ref() else {
        return Vec::new();
    };
    LatLon::new(p.lat(), p.lon())
        .map(|ll| boundaries.ids(ll))
        .unwrap_or_default()
}

/// The ISO 3166-1 alpha-2 code of the country `p` lies in; `None` at sea
/// or outside every boundary. The Canary Islands (`IC`, a code reserved
/// outside ISO 3166-1) read as Spain, whose holidays they keep.
#[must_use]
pub fn country_at(p: Position) -> Option<&'static str> {
    areas_at(p)
        .into_iter()
        .find(|id| id.len() == 2 && id.bytes().all(|b| b.is_ascii_uppercase()) && *id != "IC")
}

/// A box `[south, west, north, east]` cut to the globe; `None` for one
/// that is not a box (a side that is no number, south above north, west
/// past east). Its sides come from files: an infinite one would make a
/// walk over its cells endless.
fn on_globe(south: f64, west: f64, north: f64, east: f64) -> Option<[f64; 4]> {
    let sides = [south, west, north, east];
    (sides.iter().all(|v| v.is_finite()) && south <= north && west <= east).then(|| {
        [
            south.clamp(-90.0, 90.0),
            west.clamp(-180.0, 180.0),
            north.clamp(-90.0, 90.0),
            // The boundaries read a longitude of 180 as -180: a box up to it
            // would wrap to nothing.
            east.clamp(-180.0, 179.999_999),
        ]
    })
}

/// The areas (countries, and subdivisions such as `IC`) a box between
/// `south`, `west`, `north` and `east` may reach, by the one-degree cells
/// of the boundaries: a cell the box touches counts whole, so the answer
/// can hold a neighbour the box misses, never miss one it reaches. Empty
/// for a box that is not one ([`on_globe`]).
#[must_use]
pub fn areas_in_box(south: f64, west: f64, north: f64, east: f64) -> Vec<&'static str> {
    let Some(boundaries) = BOUNDARIES.as_ref() else {
        return Vec::new();
    };
    let Some([south, west, north, east]) = on_globe(south, west, north, east) else {
        return Vec::new();
    };
    let Ok(bounds) = country_boundaries::BoundingBox::new(south, west, north, east) else {
        return Vec::new();
    };
    let mut out: Vec<&'static str> = boundaries.intersecting_ids(bounds).into_iter().collect();
    out.sort_unstable();
    out
}

/// The area a point counts in when a run reads by country: the smallest
/// area of two capital letters that holds it, a country (`FR`, `RE` for
/// Réunion) or an area with a code of its own (`IC`, the Canary Islands).
#[must_use]
pub fn scope_at(p: Position) -> Option<&'static str> {
    areas_at(p)
        .into_iter()
        .find(|id| id.len() == 2 && id.bytes().all(|b| b.is_ascii_uppercase()))
}

/// Intervals a side of a box is checked on: eleven points a side, a tenth
/// of a degree apart in a whole cell (about 11 km, finer than every country
/// of the coverage; a microstate is reached with the country around it),
/// closer in a smaller box such as a row group's.
const CHECK_INTERVALS: u32 = 10;

/// Whether a point of the box lies in one of `codes` ([`scope_at`]), on a
/// grid of [`CHECK_INTERVALS`] intervals a side (the box is a cell of a
/// degree or less).
fn box_holds(south: f64, west: f64, north: f64, east: f64, codes: &BTreeSet<String>) -> bool {
    let steps = |from: f64, to: f64| {
        (0..=CHECK_INTERVALS)
            .map(move |i| from + (to - from) * f64::from(i) / f64::from(CHECK_INTERVALS))
    };
    steps(south, north).any(|lat| {
        steps(west, east).any(|lon| {
            Position::new(lat, lon)
                .ok()
                .and_then(scope_at)
                .is_some_and(|s| codes.contains(s))
        })
    })
}

/// Whether the box between `south`, `west`, `north` and `east` reaches one
/// of the areas `codes` names ([`scope_at`]): a cell of a degree it
/// touches names one ([`areas_in_box`]), and a point of that cell lies in
/// it. The boundaries file a territory under its country too (the cells of
/// Réunion name France), so the cell alone would make a run of France read
/// the Caribbean and the Indian Ocean.
#[must_use]
pub fn box_reaches(south: f64, west: f64, north: f64, east: f64, codes: &BTreeSet<String>) -> bool {
    let Some([south, west, north, east]) = on_globe(south, west, north, east) else {
        return false;
    };
    let mut lat = south.floor();
    while lat <= north {
        let mut lon = west.floor();
        while lon <= east {
            let (s, w) = (lat.max(south), lon.max(west));
            let (n, e) = ((lat + 1.0).min(north), (lon + 1.0).min(east));
            let named = areas_in_box(s, w, n, e).iter().any(|a| codes.contains(*a));
            if named && box_holds(s, w, n, e, codes) {
                return true;
            }
            lon += 1.0;
        }
        lat += 1.0;
    }
    false
}

/// A region a device can sync on its own.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SyncRegion {
    /// `FR-BRE` for a French region, the country code elsewhere.
    pub code: &'static str,
    /// The country it belongs to.
    pub country: &'static str,
    /// Its name in English.
    pub name_en: &'static str,
    /// Its name in French.
    pub name_fr: &'static str,
}

const fn region(
    code: &'static str,
    country: &'static str,
    name_en: &'static str,
    name_fr: &'static str,
) -> SyncRegion {
    SyncRegion {
        code,
        country,
        name_en,
        name_fr,
    }
}

/// Every sync region the data covers: the thirteen regions of metropolitan
/// France, then the countries of the European import, by code.
pub const SYNC_REGIONS: &[SyncRegion] = &[
    region(
        "FR-ARA",
        "FR",
        "Auvergne-Rhône-Alpes",
        "Auvergne-Rhône-Alpes",
    ),
    region(
        "FR-BFC",
        "FR",
        "Bourgogne-Franche-Comté",
        "Bourgogne-Franche-Comté",
    ),
    region("FR-BRE", "FR", "Brittany", "Bretagne"),
    region("FR-CVL", "FR", "Centre-Val de Loire", "Centre-Val de Loire"),
    region("FR-20R", "FR", "Corsica", "Corse"),
    region("FR-GES", "FR", "Grand Est", "Grand Est"),
    region("FR-HDF", "FR", "Hauts-de-France", "Hauts-de-France"),
    region("FR-IDF", "FR", "Île-de-France", "Île-de-France"),
    region("FR-NOR", "FR", "Normandy", "Normandie"),
    region("FR-NAQ", "FR", "Nouvelle-Aquitaine", "Nouvelle-Aquitaine"),
    region("FR-OCC", "FR", "Occitania", "Occitanie"),
    region("FR-PDL", "FR", "Pays de la Loire", "Pays de la Loire"),
    region(
        "FR-PAC",
        "FR",
        "Provence-Alpes-Côte d'Azur",
        "Provence-Alpes-Côte d'Azur",
    ),
    region(
        "FR",
        "FR",
        "France, outside any commune",
        "France, hors commune",
    ),
    region("AT", "AT", "Austria", "Autriche"),
    region("BE", "BE", "Belgium", "Belgique"),
    region("CH", "CH", "Switzerland", "Suisse"),
    region("CZ", "CZ", "Czechia", "Tchéquie"),
    region("DE", "DE", "Germany", "Allemagne"),
    region("DK", "DK", "Denmark", "Danemark"),
    region("ES", "ES", "Spain", "Espagne"),
    region("FI", "FI", "Finland", "Finlande"),
    region("GB", "GB", "United Kingdom", "Royaume-Uni"),
    region("GR", "GR", "Greece", "Grèce"),
    region("HR", "HR", "Croatia", "Croatie"),
    region("IE", "IE", "Ireland", "Irlande"),
    region("IT", "IT", "Italy", "Italie"),
    region("LU", "LU", "Luxembourg", "Luxembourg"),
    region("NL", "NL", "Netherlands", "Pays-Bas"),
    region("NO", "NO", "Norway", "Norvège"),
    region("PL", "PL", "Poland", "Pologne"),
    region("PT", "PT", "Portugal", "Portugal"),
    region("SE", "SE", "Sweden", "Suède"),
    region("SI", "SI", "Slovenia", "Slovénie"),
];

/// The sync region with this code, case-insensitive.
#[must_use]
pub fn sync_region(code: &str) -> Option<&'static SyncRegion> {
    SYNC_REGIONS
        .iter()
        .find(|r| r.code.eq_ignore_ascii_case(code))
}

/// The microstates and territories that sync with the region around them,
/// and that region.
pub const ATTACHED: &[(&str, &str)] = &[
    ("MC", "FR-PAC"),
    ("AD", "ES"),
    ("GI", "ES"),
    ("SM", "IT"),
    ("VA", "IT"),
    ("LI", "CH"),
    ("SJ", "NO"),
    ("AX", "FI"),
];

/// The French region of a department (`74`, `2A`), by the 2016 map.
#[must_use]
pub fn french_region_of_department(department: &str) -> Option<&'static str> {
    Some(match department {
        "01" | "03" | "07" | "15" | "26" | "38" | "42" | "43" | "63" | "69" | "73" | "74" => {
            "FR-ARA"
        }
        "21" | "25" | "39" | "58" | "70" | "71" | "89" | "90" => "FR-BFC",
        "22" | "29" | "35" | "56" => "FR-BRE",
        "18" | "28" | "36" | "37" | "41" | "45" => "FR-CVL",
        "2A" | "2B" => "FR-20R",
        "08" | "10" | "51" | "52" | "54" | "55" | "57" | "67" | "68" | "88" => "FR-GES",
        "02" | "59" | "60" | "62" | "80" => "FR-HDF",
        "75" | "77" | "78" | "91" | "92" | "93" | "94" | "95" => "FR-IDF",
        "14" | "27" | "50" | "61" | "76" => "FR-NOR",
        "16" | "17" | "19" | "23" | "24" | "33" | "40" | "47" | "64" | "79" | "86" | "87" => {
            "FR-NAQ"
        }
        "09" | "11" | "12" | "30" | "31" | "32" | "34" | "46" | "48" | "65" | "66" | "81"
        | "82" => "FR-OCC",
        "44" | "49" | "53" | "72" | "85" => "FR-PDL",
        "04" | "05" | "06" | "13" | "83" | "84" => "FR-PAC",
        _ => return None,
    })
}

/// The sync region of a place: the French region of its commune (INSEE
/// code, `74010`) in France, `FR` for a French place outside every commune,
/// the region around a microstate, the country elsewhere; `None` without a
/// country.
#[must_use]
pub fn sync_region_of(country: Option<&str>, commune: Option<&str>) -> Option<String> {
    let country = country?.to_ascii_uppercase();
    if country == "FR" {
        let department = commune.and_then(|c| c.get(..2));
        return Some(
            department
                .and_then(french_region_of_department)
                .unwrap_or("FR")
                .to_owned(),
        );
    }
    if let Some((_, around)) = ATTACHED.iter().find(|(c, _)| *c == country) {
        return Some((*around).to_owned());
    }
    Some(country)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    #[test]
    fn the_embedded_boundaries_load() {
        assert!(
            BOUNDARIES.is_some(),
            "without the boundaries no record would get a country"
        );
    }

    #[test]
    fn a_box_reaches_the_countries_it_touches_and_no_far_one() {
        let paris = areas_in_box(48.8, 2.3, 48.9, 2.4);
        assert!(paris.contains(&"FR"), "{paris:?}");
        assert!(!paris.contains(&"ES") && !paris.contains(&"MA"));
        let canaries = areas_in_box(27.6, -18.2, 29.4, -13.4);
        assert!(
            canaries.contains(&"IC"),
            "the Canary Islands, a scope of their own: {canaries:?}"
        );
        let atlantic = areas_in_box(44.0, -20.0, 45.0, -19.0);
        assert!(atlantic.is_empty(), "the open sea: {atlantic:?}");
        assert!(
            areas_in_box(50.0, 0.0, 40.0, 1.0).is_empty(),
            "south above north"
        );
    }

    #[test]
    fn a_box_reaches_a_country_by_its_land_not_by_its_territories() {
        let codes =
            |c: &[&str]| -> BTreeSet<String> { c.iter().map(|s| (*s).to_owned()).collect() };
        let france = codes(&["FR", "MC"]);
        // The boxes of four files of Overture's release 2026-09-23.1, from
        // its catalogue, as south, west, north, east.
        assert!(box_reaches(
            40.384_407, -1.587_778, 62.686_97, 6.285_976, &france
        ));
        for (name, [s, w, n, e]) in [
            (
                "French Guiana, Guadeloupe and Martinique",
                [-20.134_12, -76.505_836, 40.384_41, 6.285_98],
            ),
            (
                "Réunion and Mayotte",
                [-84.979_88, 42.149_162, 18.112_114, 106.662_58],
            ),
            (
                "French Polynesia",
                [-84.990_11, -179.998_06, 28.646_18, -76.505_836],
            ),
        ] {
            assert!(
                !box_reaches(s, w, n, e, &france),
                "{name}: an overseas territory is not the France of the extracts"
            );
        }
        assert!(
            box_reaches(43.72, 7.40, 43.76, 7.44, &codes(&["MC"])),
            "a row group's box over a microstate is checked on points closer than its size"
        );
        assert!(
            box_reaches(27.6, -18.2, 29.4, -13.4, &codes(&["IC"])),
            "the Canary Islands by their own code"
        );
        assert!(
            !box_reaches(44.0, -20.0, 45.0, -19.0, &france),
            "the open sea"
        );
        assert!(
            box_reaches(f64::MIN, -1.0, 46.0, 1.0, &france),
            "a side past the globe is cut to it, and the walk ends"
        );
        assert!(!box_reaches(f64::NEG_INFINITY, -1.0, 46.0, 1.0, &france));
        assert!(!box_reaches(45.0, f64::NAN, 46.0, 1.0, &france));
        assert!(areas_in_box(-1e300, -1e300, 1e300, 1e300).contains(&"FR"));
        assert_eq!(scope_at(at(28.1, -15.43)), Some("IC"));
        assert_eq!(
            scope_at(at(-21.1, 55.5)),
            Some("RE"),
            "Réunion is not France here"
        );
    }

    #[test]
    fn points_read_as_their_country() {
        let cases = [
            ((48.8566, 2.3522), Some("FR")),
            ((42.0, 9.0), Some("FR")),
            ((43.7384, 7.4246), Some("MC")),
            ((40.4168, -3.7038), Some("ES")),
            ((28.1, -15.43), Some("ES")),
            ((37.74, -25.67), Some("PT")),
            ((32.65, -16.91), Some("PT")),
            ((47.71193375, 7.548_061_15), Some("DE")),
            ((46.2044, 6.1432), Some("CH")),
            ((60.1, 19.94), Some("AX")),
            ((78.22, 15.65), Some("SJ")),
            ((46.0, -10.0), None),
        ];
        for ((lat, lon), country) in cases {
            assert_eq!(country_at(at(lat, lon)), country, "{lat}, {lon}");
        }
    }

    #[test]
    fn islands_with_their_own_zone_are_told_apart() {
        assert!(areas_at(at(28.1, -15.43)).contains(&"IC"), "Canary Islands");
        assert!(areas_at(at(37.74, -25.67)).contains(&"PT-20"), "Azores");
        assert!(areas_at(at(32.65, -16.91)).contains(&"PT-30"), "Madeira");
    }

    #[test]
    fn every_department_has_one_region_and_every_region_departments() {
        let mut departments: Vec<String> = (1..=95)
            .filter(|n| *n != 20)
            .map(|n| format!("{n:02}"))
            .collect();
        departments.extend(["2A".into(), "2B".into()]);
        for d in &departments {
            let r = french_region_of_department(d);
            assert!(r.is_some(), "department {d} must belong to a region");
        }
        for r in SYNC_REGIONS.iter().filter(|r| r.code.starts_with("FR-")) {
            assert!(
                departments
                    .iter()
                    .any(|d| french_region_of_department(d) == Some(r.code)),
                "{} has no department",
                r.code
            );
        }
        assert_eq!(french_region_of_department("97"), None, "overseas");
    }

    #[test]
    fn places_sync_with_their_region() {
        assert_eq!(
            sync_region_of(Some("FR"), Some("74010")).as_deref(),
            Some("FR-ARA")
        );
        assert_eq!(
            sync_region_of(Some("FR"), Some("2A004")).as_deref(),
            Some("FR-20R")
        );
        assert_eq!(sync_region_of(Some("FR"), None).as_deref(), Some("FR"));
        assert_eq!(sync_region_of(Some("mc"), None).as_deref(), Some("FR-PAC"));
        assert_eq!(sync_region_of(Some("DE"), None).as_deref(), Some("DE"));
        assert_eq!(sync_region_of(None, Some("74010")), None);
        for (_, around) in ATTACHED {
            assert!(
                sync_region(around).is_some(),
                "{around} must be a sync region"
            );
        }
    }
}
