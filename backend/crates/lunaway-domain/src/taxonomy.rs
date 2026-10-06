//! The taxonomy every source is mapped onto.
//!
//! Codes are stable strings: they are stored in the database, sent over the
//! API and shipped in offline packs, so a released code is never renamed. A
//! new meaning gets a new code. The OSM tag named on a variant is the main tag
//! an OSM feature of that kind carries; the ingestion adapters hold the full
//! mapping of each source.

use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};

/// A code that names no variant of the enum it was parsed into.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("unknown {kind} code: {code:?}")]
pub struct UnknownCode {
    /// The enum the code was parsed into.
    pub kind: &'static str,
    /// The code as received.
    pub code: String,
}

/// Declares an enum whose variants each carry one stable code, used for
/// `Display`, `FromStr` and serde alike, so the three can never disagree.
macro_rules! coded_enum {
    (
        $(#[$meta:meta])*
        $name:ident {
            $( $(#[$vmeta:meta])* $variant:ident => $code:literal, )+
        }
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
        pub enum $name {
            $( $(#[$vmeta])* #[serde(rename = $code)] $variant, )+
        }

        impl $name {
            /// Every variant, in declaration order.
            pub const ALL: &'static [Self] = &[ $( Self::$variant, )+ ];

            /// The stable code of this variant.
            #[must_use]
            pub const fn code(self) -> &'static str {
                match self {
                    $( Self::$variant => $code, )+
                }
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.code())
            }
        }

        impl FromStr for $name {
            type Err = UnknownCode;

            fn from_str(s: &str) -> Result<Self, Self::Err> {
                match s {
                    $( $code => Ok(Self::$variant), )+
                    _ => Err(UnknownCode { kind: stringify!($name), code: s.to_owned() }),
                }
            }
        }
    };
}

// The community codes (confirmation statuses, issue kinds) follow the same
// rule; the macro names `fmt`, `FromStr`, serde's derives and
// `UnknownCode`, which a user module imports.
pub(crate) use coded_enum;

coded_enum! {
    /// What a place is. Whether a night may be spent there is a separate
    /// fact, [`OvernightStatus`], because a car park can be either.
    PlaceKind {
        /// A dedicated motorhome area, with or without services
        /// (OSM `tourism=caravan_site`).
        MotorhomeArea => "motorhome_area",
        /// Motorhome services without overnight parking: water, dump station
        /// (OSM `amenity=sanitary_dump_station`).
        ServiceArea => "service_area",
        /// A campsite (OSM `tourism=camp_site`).
        Campsite => "campsite",
        /// A general car park that takes motorhomes (OSM `amenity=parking`).
        Parking => "parking",
        /// A spot in nature, away from any facility.
        Nature => "nature",
        /// A roadside rest area (OSM `highway=rest_area`).
        RestArea => "rest_area",
        /// A picnic area (OSM `tourism=picnic_site`).
        PicnicArea => "picnic_area",
        /// A farm, vineyard or producer that hosts motorhomes.
        Farm => "farm",
        /// A private host who welcomes travellers on their land.
        Homestay => "homestay",
        /// A spot reachable with a 4x4 only.
        OffRoad => "off_road",
        /// A useful stop that is not a place to stay: laundry, LPG station,
        /// vehicle wash.
        ExtraService => "extra_service",
    }
}

coded_enum! {
    /// A facility available at or next to a place.
    Service {
        /// Drinking water.
        DrinkingWater => "drinking_water",
        /// Grey water disposal.
        GreyWater => "grey_water",
        /// Black water (cassette) disposal.
        BlackWater => "black_water",
        /// Waste bins.
        WasteBin => "waste_bin",
        /// Public toilets.
        Toilets => "toilets",
        /// Showers.
        Showers => "showers",
        /// Electric hook-up.
        Electricity => "electricity",
        /// Wi-Fi.
        Wifi => "wifi",
        /// Laundry.
        Laundry => "laundry",
        /// LPG filling station.
        Lpg => "lpg",
        /// Bottled gas exchange.
        GasBottles => "gas_bottles",
        /// Motorhome wash.
        VehicleWash => "vehicle_wash",
        /// A bakery within walking distance.
        Bakery => "bakery",
        /// Swimming pool.
        SwimmingPool => "swimming_pool",
        /// Pets allowed.
        PetsAllowed => "pets_allowed",
        /// Usable mobile data.
        MobileData => "mobile_data",
        /// Open for winter caravanning (snow, ski).
        WinterCaravanning => "winter_caravanning",
    }
}

coded_enum! {
    /// Something to do from a place.
    Activity {
        /// Monuments and visits.
        Monuments => "monuments",
        /// Windsurfing or kitesurfing.
        WindsurfKitesurf => "windsurf_kitesurf",
        /// Mountain-bike trails.
        MountainBiking => "mountain_biking",
        /// Hiking trailheads.
        Hiking => "hiking",
        /// Climbing.
        Climbing => "climbing",
        /// Canoe or kayak.
        CanoeKayak => "canoe_kayak",
        /// Fishing.
        Fishing => "fishing",
        /// Shore fishing.
        ShoreFishing => "shore_fishing",
        /// Swimming.
        Swimming => "swimming",
        /// Motorcycle rides.
        Motorcycling => "motorcycling",
        /// A viewpoint.
        Viewpoint => "viewpoint",
        /// A children's playground.
        Playground => "playground",
    }
}

coded_enum! {
    /// Whether a night may be spent at a place. The date a ban started and
    /// its source (a sign, a municipal order) are stored with the place.
    OvernightStatus {
        /// Nights are explicitly allowed.
        Allowed => "allowed",
        /// Nights are not allowed on paper but tolerated in practice.
        Tolerated => "tolerated",
        /// Parking by day only.
        DayOnly => "day_only",
        /// Nights are forbidden.
        Forbidden => "forbidden",
        /// Nobody has said yet.
        Unknown => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    fn assert_codes_hold<T>(all: &[T])
    where
        T: Copy + fmt::Display + FromStr<Err = UnknownCode> + PartialEq + fmt::Debug + Serialize,
    {
        let mut seen = HashSet::new();
        for &v in all {
            let code = v.to_string();
            assert!(seen.insert(code.clone()), "duplicate code {code}");
            assert!(
                code.chars().all(|c| c.is_ascii_lowercase() || c == '_'),
                "{code} is not snake_case: codes are stored and must stay portable"
            );
            assert_eq!(code.parse::<T>().unwrap(), v, "FromStr must invert Display");
            assert_eq!(
                serde_json::to_string(&v).unwrap(),
                format!("\"{code}\""),
                "serde must use the same code as Display"
            );
        }
    }

    #[test]
    fn every_code_is_unique_snake_case_and_round_trips() {
        assert_codes_hold(PlaceKind::ALL);
        assert_codes_hold(Service::ALL);
        assert_codes_hold(Activity::ALL);
        assert_codes_hold(OvernightStatus::ALL);
    }

    #[test]
    fn serde_reads_the_code_back() {
        let kind: PlaceKind = serde_json::from_str("\"motorhome_area\"").unwrap();
        assert_eq!(kind, PlaceKind::MotorhomeArea);
    }

    #[test]
    fn an_unknown_code_names_its_enum() {
        let err = "castle".parse::<PlaceKind>().unwrap_err();
        assert_eq!(err.kind, "PlaceKind");
        assert_eq!(err.to_string(), "unknown PlaceKind code: \"castle\"");
    }
}
