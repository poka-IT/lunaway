//! Identifiers of the data sources a record comes from.

use std::{borrow::Cow, fmt};

use serde::{Deserialize, Serialize};

/// The stable identifier of a source (`osm`, `atout-france`, `community`).
///
/// It is the primary key of the `sources` table, the `Source.id` of the API
/// and the key of the trust priors, so it is validated once here: lower-case
/// ASCII letters, digits and hyphens, 1 to 32 characters.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct SourceId(Cow<'static, str>);

/// A string that is not a valid source identifier.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("invalid source id: {0:?}")]
pub struct InvalidSourceId(pub String);

impl SourceId {
    /// OpenStreetMap.
    pub const OSM: Self = Self(Cow::Borrowed("osm"));
    /// Atout France, classified accommodation.
    pub const ATOUT_FRANCE: Self = Self(Cow::Borrowed("atout-france"));
    /// Contributions of Lunaway users that join the databases under the
    /// ODbL: new places, place edits, the points they add, road reports.
    pub const COMMUNITY: Self = Self(Cow::Borrowed("community"));
    /// Reviews, ratings and photos of Lunaway users, published under
    /// CC BY 4.0 outside the places database.
    pub const COMMUNITY_CC_BY: Self = Self(Cow::Borrowed("community-cc-by"));
    /// The fuel price feed of the French ministry of the economy, joined to
    /// fuel stations by their id in the feed.
    pub const FUEL_PRICES: Self = Self(Cow::Borrowed("prix-carburants"));
    /// La Poste's opening calendar, joined to post offices by their id.
    pub const LAPOSTE: Self = Self(Cow::Borrowed("laposte"));
    /// FINESS, the register of health establishments, joined to pharmacies
    /// by their FINESS number.
    pub const FINESS: Self = Self(Cow::Borrowed("finess"));
    /// France's official list of speed cameras (Sécurité routière).
    pub const SECURITE_ROUTIERE: Self = Self(Cow::Borrowed("securite-routiere"));
    /// Poland's list of speed cameras (GITD CANARD).
    pub const PL_CANARD: Self = Self(Cow::Borrowed("pl-canard"));
    /// Luxembourg's list of speed cameras (Ponts et Chaussées).
    pub const LU_PCH_RADARS: Self = Self(Cow::Borrowed("lu-pch-radars"));
    /// Catalonia's list of speed cameras (Servei Català de Trànsit).
    pub const CAT_SCT_RADARS: Self = Self(Cow::Borrowed("cat-sct-radars"));
    /// Norway's fixed speed cameras (NVDB, object type 162).
    pub const NO_NVDB_ATK: Self = Self(Cow::Borrowed("no-nvdb-atk"));
    /// Wikimedia Commons: photos, each under its own free licence.
    pub const WIKIMEDIA_COMMONS: Self = Self(Cow::Borrowed("wikimedia-commons"));
    /// Wikipedia: the introduction of a place's article (CC BY-SA 4.0).
    pub const WIKIPEDIA: Self = Self(Cow::Borrowed("wikipedia"));
    /// Wikidata (CC0): which article and which image a place's item names.
    pub const WIKIDATA: Self = Self(Cow::Borrowed("wikidata"));
    /// Panoramax: street-level pictures, under each instance's licence.
    pub const PANORAMAX: Self = Self(Cow::Borrowed("panoramax"));
    /// Mangrove Reviews: open reviews (CC BY 4.0).
    pub const MANGROVE: Self = Self(Cow::Borrowed("mangrove"));
    /// DATAtourisme: the descriptions French tourist offices publish
    /// (Licence Ouverte 2.0).
    pub const DATATOURISME: Self = Self(Cow::Borrowed("datatourisme"));
    /// The external community source: a partner's places, reviews and
    /// photos, received as a feed under a written agreement
    /// (`docs/feeds.md`), shown as "Source communautaire externe".
    pub const EXTCOM: Self = Self(Cow::Borrowed("extcom"));

    /// A source id, if `id` follows the format.
    ///
    /// # Errors
    ///
    /// [`InvalidSourceId`] when `id` is empty, too long or has a character
    /// other than `a-z`, `0-9` and `-`.
    pub fn new(id: &str) -> Result<Self, InvalidSourceId> {
        let valid = (1..=32).contains(&id.len())
            && id
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-');
        if valid {
            Ok(Self(Cow::Owned(id.to_owned())))
        } else {
            Err(InvalidSourceId(id.to_owned()))
        }
    }

    /// The identifier as stored.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for SourceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl TryFrom<String> for SourceId {
    type Error = InvalidSourceId;

    fn try_from(s: String) -> Result<Self, Self::Error> {
        Self::new(&s)
    }
}

impl From<SourceId> for String {
    fn from(id: SourceId) -> Self {
        id.0.into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_known_sources_are_valid_ids() {
        for id in [
            SourceId::OSM,
            SourceId::ATOUT_FRANCE,
            SourceId::COMMUNITY,
            SourceId::COMMUNITY_CC_BY,
            SourceId::FUEL_PRICES,
            SourceId::LAPOSTE,
            SourceId::FINESS,
            SourceId::SECURITE_ROUTIERE,
            SourceId::PL_CANARD,
            SourceId::LU_PCH_RADARS,
            SourceId::CAT_SCT_RADARS,
            SourceId::NO_NVDB_ATK,
            SourceId::WIKIMEDIA_COMMONS,
            SourceId::WIKIPEDIA,
            SourceId::WIKIDATA,
            SourceId::PANORAMAX,
            SourceId::MANGROVE,
            SourceId::DATATOURISME,
            SourceId::EXTCOM,
        ] {
            assert_eq!(
                SourceId::new(id.as_str()).unwrap(),
                id,
                "a constant must pass its own validation"
            );
        }
    }

    #[test]
    fn malformed_ids_are_refused() {
        for bad in ["", "OSM", "atout_france", "a b", &"x".repeat(33)] {
            assert!(SourceId::new(bad).is_err(), "{bad:?} must be refused");
        }
    }

    #[test]
    fn serde_validates() {
        let id: SourceId = serde_json::from_str("\"osm\"").unwrap();
        assert_eq!(id, SourceId::OSM);
        assert!(serde_json::from_str::<SourceId>("\"Not Valid\"").is_err());
        assert_eq!(
            serde_json::to_string(&SourceId::ATOUT_FRANCE).unwrap(),
            "\"atout-france\""
        );
    }
}
