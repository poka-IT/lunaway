//! Where a point of interest lies, for the short line under its name in
//! the map's search and on its page: its town, its French department, its
//! country (`Poi.locality`, `plan/research/113-recherche-historique-villes.md`).
//!
//! The town is the one the point's own address names (`addr:city`, the
//! address of a record), else the French commune whose outline covers it;
//! the department is that commune's, else its postcode's in France. Nothing
//! is guessed: a point abroad without a town in its address has none.

/// The town, the department and the country of a point; each `None` when
/// the data does not say.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Locality {
    /// Its town: its address's, else its French commune's.
    pub town: Option<String>,
    /// The French department (`26`, `2A`, `974`); `None` outside France.
    pub department: Option<String>,
    /// ISO 3166-1 alpha-2 country code, upper case.
    pub country_code: Option<String>,
}

/// The French commune that covers a point: its INSEE code and its name.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Commune<'a> {
    /// INSEE code (`26114`, `2A004`, `97411`).
    pub code: &'a str,
    /// Its name.
    pub name: &'a str,
}

/// The locality of a point whose address gives `city`, `postcode` and
/// `country_code` (any of them missing), inside `commune` when a French
/// commune covers it.
///
/// - The town: the address's, else the commune's. A source's town may be a
///   hamlet the commune holds; it is what the point's own data says.
/// - The country: the address's, else France when a commune covers it.
/// - The department, in France only: the commune's, which its outline
///   decides, else the one of the postcode, its first two digits (three
///   overseas, 2A or 2B in Corsica).
#[must_use]
pub fn locality(
    city: Option<&str>,
    postcode: Option<&str>,
    country_code: Option<&str>,
    commune: Option<Commune<'_>>,
) -> Locality {
    let country = country_code
        .map(str::trim)
        .filter(|c| c.len() == 2)
        .map(str::to_ascii_uppercase)
        .or_else(|| commune.map(|_| "FR".to_owned()));
    let french = country.as_deref() == Some("FR");
    let town = city
        .map(str::trim)
        .filter(|c| !c.is_empty())
        .map(str::to_owned)
        .or_else(|| commune.map(|c| c.name.to_owned()));
    let department = french
        .then(|| {
            commune
                .and_then(|c| department_of_commune(c.code))
                .or_else(|| postcode.and_then(|p| department_of_postcode(p.trim(), Some("FR"))))
        })
        .flatten()
        .map(str::to_owned);
    Locality {
        town,
        department,
        country_code: country,
    }
}

/// The department of a French commune by its INSEE code: its first two
/// characters (`26` for 26114, `2A` for 2A004), three overseas (`974` for
/// 97411). `None` for anything that is no INSEE code.
#[must_use]
pub fn department_of_commune(code: &str) -> Option<&str> {
    let bytes = code.as_bytes();
    let valid = bytes.len() == 5
        && bytes[0].is_ascii_digit()
        && (bytes[1].is_ascii_digit() || matches!(bytes[1], b'A' | b'B'))
        && bytes[2..].iter().all(u8::is_ascii_digit);
    if !valid {
        return None;
    }
    if code.starts_with("97") {
        return code.get(..3);
    }
    code.get(..2)
}

/// The French department of a postcode of five digits in France (or a
/// country unknown): its first two digits, three overseas (97410 La
/// Réunion), 2A or 2B in Corsica (20000 to 20199 the south); `None` for
/// any other postcode.
#[must_use]
pub fn department_of_postcode<'a>(postcode: &'a str, country: Option<&str>) -> Option<&'a str> {
    let french = country.is_none_or(|c| c.eq_ignore_ascii_case("FR"));
    if !french || postcode.len() != 5 || !postcode.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if postcode.starts_with("97") {
        return postcode.get(..3);
    }
    if postcode.starts_with("20") {
        return Some(if postcode < "20200" { "2A" } else { "2B" });
    }
    postcode.get(..2)
}

#[cfg(test)]
mod tests {
    use super::*;

    const DONZERE: Commune<'static> = Commune {
        code: "26116",
        name: "Donzère",
    };

    #[test]
    fn a_point_without_a_town_in_its_address_takes_its_commune_and_department() {
        assert_eq!(
            locality(None, None, Some("fr"), Some(DONZERE)),
            Locality {
                town: Some("Donzère".into()),
                department: Some("26".into()),
                country_code: Some("FR".into()),
            },
            "most points of OpenStreetMap carry no addr:city: the commune names their town"
        );
    }

    #[test]
    fn the_address_names_the_town_and_the_commune_the_department() {
        let l = locality(
            Some("Les Granges"),
            Some("07700"),
            Some("FR"),
            Some(DONZERE),
        );
        assert_eq!(
            l.town.as_deref(),
            Some("Les Granges"),
            "the source's own town"
        );
        assert_eq!(
            l.department.as_deref(),
            Some("26"),
            "the outline decides the department, not a postcode of the next one"
        );
    }

    #[test]
    fn without_a_commune_the_postcode_gives_the_department_in_france_only() {
        let l = locality(Some("Bastia"), Some("20200"), Some("FR"), None);
        assert_eq!(l.department.as_deref(), Some("2B"));
        let l = locality(Some("Saint-Denis"), Some("97400"), Some("FR"), None);
        assert_eq!(l.department.as_deref(), Some("974"));
        let l = locality(Some("München"), Some("80331"), Some("DE"), None);
        assert_eq!(
            l,
            Locality {
                town: Some("München".into()),
                department: None,
                country_code: Some("DE".into()),
            },
            "a German postcode is no French department"
        );
    }

    #[test]
    fn a_point_abroad_without_a_town_has_none() {
        assert_eq!(
            locality(None, None, Some("ES"), None),
            Locality {
                town: None,
                department: None,
                country_code: Some("ES".into()),
            },
            "nothing is guessed: no town rather than a wrong one"
        );
        assert_eq!(locality(Some("  "), None, None, None), Locality::default());
    }

    #[test]
    fn an_insee_code_gives_its_department() {
        assert_eq!(department_of_commune("26116"), Some("26"));
        assert_eq!(department_of_commune("2A004"), Some("2A"));
        assert_eq!(department_of_commune("97411"), Some("974"));
        assert_eq!(department_of_commune("7411"), None);
        assert_eq!(department_of_commune("2C004"), None);
        assert_eq!(department_of_postcode("26290", None), Some("26"));
        assert_eq!(department_of_postcode("20000", Some("fr")), Some("2A"));
        assert_eq!(department_of_postcode("1000", Some("FR")), None);
    }
}
