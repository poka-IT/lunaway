//! The country a position lies in, read from the boundaries the server
//! reads (`lunaway_domain::region`, the `country-boundaries` crate), and the
//! speed camera rules the app was built with.
//!
//! The guidance applies the rule of the country the vehicle is in, the
//! stricter one at once near a border: what may be shown of speed cameras
//! changes at a border (France allows danger zones only, Switzerland
//! nothing), so the phone must place itself exactly where the server
//! placed the data, without asking it where it is.

use flutter_rust_bridge::frb;
use lunaway_domain::{
    Position,
    enforcement::{self, BORDER_MARGIN_M, RULES, RULES_REVIEWED, RULES_VERSION},
    region,
};

/// The countries at a position and around it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CountriesAround {
    /// ISO 3166-1 alpha-2 of the country the position lies in; `None` at
    /// sea or outside every boundary.
    pub at: Option<String>,
    /// Every country within [`BORDER_MARGIN_M`] of the position, the one it
    /// lies in included, without repeats.
    pub near: Vec<String>,
}

/// The countries at `lat`, `lon` and within 1 km of it: the point and 16
/// points on circles of 500 m and 1 km around it, as the server reads a
/// border (`lunaway_domain::enforcement::near_country`).
#[frb(sync)]
#[must_use]
pub fn countries_around(lat: f64, lon: f64) -> CountriesAround {
    let Ok(p) = Position::new(lat, lon) else {
        return CountriesAround {
            at: None,
            near: Vec::new(),
        };
    };
    let at = region::country_at(p);
    let mut near: Vec<String> = Vec::new();
    let ring = [BORDER_MARGIN_M / 2.0, BORDER_MARGIN_M]
        .into_iter()
        .flat_map(move |r| {
            (0..8).filter_map(move |k| enforcement::toward(p, f64::from(k) * 45.0, r))
        });
    for c in std::iter::once(p)
        .chain(ring)
        .filter_map(region::country_at)
    {
        if !near.iter().any(|n| n == c) {
            near.push(c.to_owned());
        }
    }
    CountriesAround {
        at: at.map(str::to_owned),
        near,
    }
}

/// One line of the rules table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CountryMode {
    /// ISO 3166-1 alpha-2.
    pub country: String,
    /// `off`, `off_while_driving`, `zones` or `exact`.
    pub mode: String,
}

/// The rules table the app was built with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmbeddedRules {
    /// The table's version (`EnforcementRules.version` of the API).
    pub version: u32,
    /// When it was last checked against its sources.
    pub reviewed_on: String,
    /// Each country named; any other is off.
    pub countries: Vec<CountryMode>,
}

/// The rules table compiled into the app: what it applies before the API
/// has sent its own, or offline.
#[frb(sync)]
#[must_use]
pub fn embedded_rules() -> EmbeddedRules {
    EmbeddedRules {
        version: RULES_VERSION,
        reviewed_on: RULES_REVIEWED.to_owned(),
        countries: RULES
            .iter()
            .map(|r| CountryMode {
                country: r.country.to_owned(),
                mode: r.mode.code().to_owned(),
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_point_in_france_reads_france_and_nothing_else() {
        let c = countries_around(45.8336, 1.2611);
        assert_eq!(c.at.as_deref(), Some("FR"));
        assert_eq!(c.near, vec!["FR".to_owned()]);
    }

    #[test]
    fn a_point_by_the_swiss_border_reads_switzerland_near_it() {
        // Saint-Julien-en-Genevois, 500 m from Geneva (the point the
        // domain's own border test reads).
        let c = countries_around(46.1453, 6.0808);
        assert_eq!(c.at.as_deref(), Some("FR"));
        assert!(c.near.contains(&"CH".to_owned()), "{:?}", c.near);
    }

    #[test]
    fn the_sea_reads_no_country() {
        let c = countries_around(46.0, -6.0);
        assert_eq!(c.at, None);
        assert!(c.near.is_empty());
    }

    #[test]
    fn the_embedded_table_keeps_france_in_zones_and_switzerland_out() {
        let rules = embedded_rules();
        let mode = |c: &str| {
            rules
                .countries
                .iter()
                .find(|m| m.country == c)
                .map(|m| m.mode.clone())
        };
        assert_eq!(mode("FR").as_deref(), Some("zones"));
        assert_eq!(mode("DE").as_deref(), Some("off_while_driving"));
        assert_eq!(mode("ES").as_deref(), Some("exact"));
        assert_eq!(mode("CH").as_deref(), Some("off"));
    }
}
