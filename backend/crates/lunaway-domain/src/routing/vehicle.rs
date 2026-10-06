//! The vehicle a route is computed for: what the user enters once (from the
//! registration document), its bounds, the typical values the app offers
//! before the real ones are known, and the dimensions the router and the
//! check use.
//!
//! Which rules apply to a motorhome. A motorhome is an M1 vehicle "affecté au
//! transport de personnes" (ministerial answer QE 58145, arrêté of
//! 2009-02-09); the B8 sign and its OpenStreetMap forms `goods=no` and
//! `hgv=no` target vehicles carrying goods (IISR part 4, art. 57; the French
//! sign page of the OpenStreetMap wiki says `hgv=no` targets N2 and N3
//! vehicles only), so they never apply to a motorhome, whatever its weight.
//! The physical limits apply to every vehicle: B10a length, B11 width, B12
//! height, B13 total weight, B13a axle load (IISR part 4, art. 59 to 62-1),
//! and B9i bans a vehicle towing a caravan or a trailer over 250 kg
//! (art. 58-8). Sources and reading: `plan/research/07-navigation.md`, A.3.
//! This module therefore carries no goods or HGV notion at all: the router is
//! asked with the `auto` costing and the physical dimensions only.

use std::ops::RangeInclusive;

/// The kinds of vehicle the app names. The kind only chooses the typical
/// values offered as defaults; the route depends on the dimensions alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum VehicleKind {
    /// A compact campervan on a van base, around 5 m (California class).
    Van,
    /// A panel van conversion ("fourgon aménagé"), around 6 m.
    PanelVan,
    /// A low-profile coachbuilt motorhome ("profilé").
    LowProfile,
    /// A coachbuilt motorhome with a bed over the cab ("capucine").
    Overcab,
    /// An integrated (A-class) motorhome ("intégral").
    Integrated,
    /// Any other vehicle: dimensions entered by hand.
    Other,
}

impl VehicleKind {
    /// Every kind, in the order the app lists them.
    pub const ALL: [Self; 6] = [
        Self::Van,
        Self::PanelVan,
        Self::LowProfile,
        Self::Overcab,
        Self::Integrated,
        Self::Other,
    ];
}

/// Bounds a profile must fall in. They refuse typing errors (a height in
/// centimetres, a weight in kilograms), not unusual vehicles: a bus
/// conversion of 13 m and 18 t passes.
pub mod bounds {
    use std::ops::RangeInclusive;

    /// Overall height, metres.
    pub const HEIGHT_M: RangeInclusive<f64> = 1.5..=4.5;
    /// Overall width without mirrors, metres (the EU maximum is 2.55 m,
    /// refrigerated bodies 2.60 m).
    pub const WIDTH_M: RangeInclusive<f64> = 1.5..=2.6;
    /// Overall length of the vehicle alone, bike rack included, metres.
    pub const LENGTH_M: RangeInclusive<f64> = 3.0..=15.0;
    /// Maximum authorised mass (registration document, field F.2), tonnes.
    pub const WEIGHT_T: RangeInclusive<f64> = 0.5..=40.0;
    /// Heaviest axle, tonnes (13 t is the national maximum).
    pub const AXLE_LOAD_T: RangeInclusive<f64> = 0.5..=13.0;
    /// Length of a trailer, drawbar included, metres.
    pub const TRAILER_LENGTH_M: RangeInclusive<f64> = 1.0..=12.0;
    /// Maximum authorised mass of a trailer, tonnes.
    pub const TRAILER_WEIGHT_T: RangeInclusive<f64> = 0.1..=10.0;
    /// Height or width of a trailer, metres.
    pub const TRAILER_SIZE_M: RangeInclusive<f64> = 0.5..=4.5;
    /// Longest vehicle and trailer together, metres.
    pub const COMBINATION_LENGTH_M: f64 = 25.0;
}

/// Mass above which a motorhome is limited to 110 km/h on motorways
/// (Code de la route, art. R413-8-1: passenger vehicles of 3.5 to 12 t).
pub const HEAVY_ABOVE_T: f64 = 3.5;
/// Top speed given to the router for a motorhome over [`HEAVY_ABOVE_T`].
pub const HEAVY_TOP_SPEED_KPH: u32 = 110;
/// Trailer mass above which a B9i sign (`caravan=no`) applies.
pub const CARAVAN_SIGN_ABOVE_T: f64 = 0.25;

/// Why a profile was refused.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum InvalidVehicle {
    /// A value is not a finite number.
    #[error("{field} is not a number")]
    NotFinite {
        /// The field, as the API names it.
        field: &'static str,
    },
    /// A value is outside its bounds.
    #[error("{field} must be between {min} and {max}, got {value}")]
    OutOfRange {
        /// The field, as the API names it.
        field: &'static str,
        /// The value received.
        value: f64,
        /// Least value accepted.
        min: f64,
        /// Greatest value accepted.
        max: f64,
    },
    /// The vehicle and its trailer together are longer than any legal
    /// combination.
    #[error("the vehicle and its trailer are {length} m long together, more than {max} m")]
    CombinationTooLong {
        /// Their length together.
        length: f64,
        /// The bound.
        max: f64,
    },
}

fn check(
    field: &'static str,
    value: f64,
    range: &RangeInclusive<f64>,
) -> Result<f64, InvalidVehicle> {
    if !value.is_finite() {
        return Err(InvalidVehicle::NotFinite { field });
    }
    if range.contains(&value) {
        Ok(value)
    } else {
        Err(InvalidVehicle::OutOfRange {
            field,
            value,
            min: *range.start(),
            max: *range.end(),
        })
    }
}

/// A trailer behind the vehicle: a car trailer, a luggage trailer, a
/// caravan.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Trailer {
    length_m: f64,
    weight_t: f64,
    height_m: Option<f64>,
    width_m: Option<f64>,
}

impl Trailer {
    /// A trailer, its length drawbar included and its maximum authorised
    /// mass; height and width when it is higher or wider than the vehicle
    /// could be (a car on a car trailer).
    ///
    /// # Errors
    ///
    /// [`InvalidVehicle`] when a value is out of [`bounds`].
    pub fn new(
        length_m: f64,
        weight_t: f64,
        height_m: Option<f64>,
        width_m: Option<f64>,
    ) -> Result<Self, InvalidVehicle> {
        Ok(Self {
            length_m: check("trailer.lengthM", length_m, &bounds::TRAILER_LENGTH_M)?,
            weight_t: check("trailer.weightT", weight_t, &bounds::TRAILER_WEIGHT_T)?,
            height_m: height_m
                .map(|h| check("trailer.heightM", h, &bounds::TRAILER_SIZE_M))
                .transpose()?,
            width_m: width_m
                .map(|w| check("trailer.widthM", w, &bounds::TRAILER_SIZE_M))
                .transpose()?,
        })
    }

    /// Length, drawbar included, metres.
    #[must_use]
    pub const fn length_m(self) -> f64 {
        self.length_m
    }

    /// Maximum authorised mass, tonnes.
    #[must_use]
    pub const fn weight_t(self) -> f64 {
        self.weight_t
    }

    /// Height, metres, when given.
    #[must_use]
    pub const fn height_m(self) -> Option<f64> {
        self.height_m
    }

    /// Width, metres, when given.
    #[must_use]
    pub const fn width_m(self) -> Option<f64> {
        self.width_m
    }
}

/// The vehicle as the user describes it, validated.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VehicleProfile {
    kind: VehicleKind,
    height_m: f64,
    width_m: f64,
    length_m: f64,
    weight_t: f64,
    axle_load_t: Option<f64>,
    trailer: Option<Trailer>,
}

/// The raw values of a profile, before validation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VehicleInput {
    /// What the vehicle is.
    pub kind: VehicleKind,
    /// Overall height, roof equipment included, metres.
    pub height_m: f64,
    /// Overall width without mirrors, metres.
    pub width_m: f64,
    /// Overall length, bike rack included, metres.
    pub length_m: f64,
    /// Maximum authorised mass (registration document, F.2), tonnes.
    pub weight_t: f64,
    /// Heaviest axle, tonnes, when known.
    pub axle_load_t: Option<f64>,
    /// The trailer, when towing.
    pub trailer: Option<Trailer>,
}

impl VehicleProfile {
    /// A profile, each value within [`bounds`].
    ///
    /// # Errors
    ///
    /// [`InvalidVehicle`] naming the first value out of its bounds.
    pub fn new(input: VehicleInput) -> Result<Self, InvalidVehicle> {
        let profile = Self {
            kind: input.kind,
            height_m: check("heightM", input.height_m, &bounds::HEIGHT_M)?,
            width_m: check("widthM", input.width_m, &bounds::WIDTH_M)?,
            length_m: check("lengthM", input.length_m, &bounds::LENGTH_M)?,
            weight_t: check("weightT", input.weight_t, &bounds::WEIGHT_T)?,
            axle_load_t: input
                .axle_load_t
                .map(|a| check("axleLoadT", a, &bounds::AXLE_LOAD_T))
                .transpose()?,
            trailer: input.trailer,
        };
        let length = profile.routing().length_m;
        if length > bounds::COMBINATION_LENGTH_M {
            return Err(InvalidVehicle::CombinationTooLong {
                length,
                max: bounds::COMBINATION_LENGTH_M,
            });
        }
        Ok(profile)
    }

    /// What the vehicle is.
    #[must_use]
    pub const fn kind(&self) -> VehicleKind {
        self.kind
    }

    /// Overall height, metres.
    #[must_use]
    pub const fn height_m(&self) -> f64 {
        self.height_m
    }

    /// Overall width, metres.
    #[must_use]
    pub const fn width_m(&self) -> f64 {
        self.width_m
    }

    /// Overall length of the vehicle alone, metres.
    #[must_use]
    pub const fn length_m(&self) -> f64 {
        self.length_m
    }

    /// Maximum authorised mass of the vehicle alone, tonnes.
    #[must_use]
    pub const fn weight_t(&self) -> f64 {
        self.weight_t
    }

    /// Heaviest axle, tonnes, when known.
    #[must_use]
    pub const fn axle_load_t(&self) -> Option<f64> {
        self.axle_load_t
    }

    /// The trailer, when towing.
    #[must_use]
    pub const fn trailer(&self) -> Option<Trailer> {
        self.trailer
    }

    /// The dimensions a route must respect.
    #[must_use]
    pub fn routing(&self) -> RoutingDimensions {
        routing_dimensions(self)
    }
}

/// What a route must respect, the trailer counted in: the highest and widest
/// element, the length and mass of the whole combination (a B13 sign limits
/// the total authorised mass of a vehicle or of a combination, IISR part 4,
/// art. 62).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RoutingDimensions {
    /// Metres.
    pub height_m: f64,
    /// Metres.
    pub width_m: f64,
    /// Metres, trailer included.
    pub length_m: f64,
    /// Tonnes, trailer included.
    pub weight_t: f64,
    /// Tonnes, when known: an axle load limit cannot be checked otherwise.
    pub axle_load_t: Option<f64>,
    /// Maximum authorised mass of the trailer, when towing: any trailer is
    /// banned by `trailer=no`, one over [`CARAVAN_SIGN_ABOVE_T`] by
    /// `caravan=no` too.
    pub trailer_weight_t: Option<f64>,
    /// Speed the router must not assume above, km/h.
    pub top_speed_kph: Option<u32>,
}

/// The dimensions of `profile` as a route must respect them.
#[must_use]
pub fn routing_dimensions(profile: &VehicleProfile) -> RoutingDimensions {
    let trailer = profile.trailer;
    RoutingDimensions {
        height_m: trailer
            .and_then(Trailer::height_m)
            .map_or(profile.height_m, |h| h.max(profile.height_m)),
        width_m: trailer
            .and_then(Trailer::width_m)
            .map_or(profile.width_m, |w| w.max(profile.width_m)),
        length_m: profile.length_m + trailer.map_or(0.0, Trailer::length_m),
        weight_t: profile.weight_t + trailer.map_or(0.0, Trailer::weight_t),
        axle_load_t: profile.axle_load_t,
        trailer_weight_t: trailer.map(Trailer::weight_t),
        // The vehicle's own mass decides (R413-8-1); the speed of a light
        // motorhome towing a heavy trailer is not settled here
        // (plan/research/15-navigation-backend.md, open items).
        top_speed_kph: (profile.weight_t > HEAVY_ABOVE_T).then_some(HEAVY_TOP_SPEED_KPH),
    }
}

/// Typical values for a kind, offered before the user enters the vehicle's
/// own. Each comes from the manufacturer's sheet of one representative model
/// named in `source` (read on 2026-10-06); they are defaults to correct,
/// never a substitute for the registration document. Heights are the
/// published ones, which leave out a roof antenna or an added air
/// conditioner: the app asks for the height with them.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VehiclePreset {
    /// A stable name for the app (`panel-van`, `integrated-heavy`).
    pub id: &'static str,
    /// The kind.
    pub kind: VehicleKind,
    /// Overall height, metres.
    pub height_m: f64,
    /// Overall width without mirrors, metres.
    pub width_m: f64,
    /// Overall length, metres.
    pub length_m: f64,
    /// Maximum authorised mass, tonnes.
    pub weight_t: f64,
    /// The model the values come from, and where they were read.
    pub source: &'static str,
}

/// The typical vehicle of each kind but [`VehicleKind::Other`], and a heavy
/// integrated motorhome.
#[allow(
    clippy::approx_constant,
    reason = "3.14 is the Sunlight A 70's height in metres, not pi"
)]
pub const PRESETS: [VehiclePreset; 6] = [
    VehiclePreset {
        id: "van",
        kind: VehicleKind::Van,
        height_m: 1.99,
        width_m: 1.94,
        length_m: 5.17,
        weight_t: 2.98,
        source: "Volkswagen California Ocean (2024): 5.173 x 1.941 m, 1.990 m with the roof \
                 down, 2.98 t eHybrid; vw-nutzfahrzeuge.at/california/california/technische-daten/ocean \
                 and the launch release on nfz.vwpress.ch",
    },
    VehiclePreset {
        id: "panel-van",
        kind: VehicleKind::PanelVan,
        height_m: 2.58,
        width_m: 2.05,
        length_m: 6.0,
        weight_t: 3.5,
        source: "Pössl Summit 600 on a Fiat Ducato: 5.998 x 2.050 x 2.580 m, 3.5 t; \
                 poessl-group.de/de/marken/poessl/summit/summit-600",
    },
    VehiclePreset {
        id: "low-profile",
        kind: VehicleKind::LowProfile,
        height_m: 2.9,
        width_m: 2.35,
        length_m: 7.2,
        weight_t: 3.5,
        source: "Rapido 686F, 2026 collection: 7.20 x 2.35 x 2.90 m (45 mm more on 16-inch \
                 rims), 3.5 t; Rapido technical guide 2026, page 11",
    },
    VehiclePreset {
        id: "overcab",
        kind: VehicleKind::Overcab,
        height_m: 3.14,
        width_m: 2.32,
        length_m: 7.26,
        weight_t: 3.5,
        source: "Sunlight A 70: 7.26 x 2.32 x 3.14 m, 3.5 t; \
                 sunlight.de/en-int/models/motorhomes/coachbuilts/a-70/",
    },
    VehiclePreset {
        id: "integrated",
        kind: VehicleKind::Integrated,
        height_m: 2.91,
        width_m: 2.35,
        length_m: 7.49,
        weight_t: 3.5,
        source: "Rapido 8096dF, 2026 collection: 7.49 x 2.35 x 2.91 m (45 mm more on the heavy \
                 chassis or 16-inch rims), 3.5 t; Rapido technical guide 2026, page 19",
    },
    VehiclePreset {
        id: "integrated-heavy",
        kind: VehicleKind::Integrated,
        height_m: 2.98,
        width_m: 2.35,
        length_m: 8.99,
        weight_t: 5.5,
        source: "Hymer B-ML I 880 on a Mercedes-Benz Sprinter: 8.99 x 2.35 x 2.98 m (roof \
                 antenna not included), 5.5 t; Hymer price list 2027, page 52",
    },
];

/// What a trailer carries, for its typical values.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum TrailerKind {
    /// A car trailer with a small car on it.
    CarTrailer,
}

/// Typical values of a trailer.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TrailerPreset {
    /// The kind.
    pub kind: TrailerKind,
    /// Length, drawbar included, metres.
    pub length_m: f64,
    /// Width, metres.
    pub width_m: f64,
    /// Maximum authorised mass, tonnes.
    pub weight_t: f64,
    /// The product the values come from, and where they were read.
    pub source: &'static str,
}

/// The typical trailers behind a motorhome. Its height with a car on it is
/// not published: the motorhome stays the highest element.
pub const TRAILER_PRESETS: [TrailerPreset; 1] = [TrailerPreset {
    kind: TrailerKind::CarTrailer,
    length_m: 4.78,
    width_m: 2.1,
    weight_t: 1.5,
    source: "Debon Roadster Auto, 3.5 m deck: 4.780 m overall, 2.095 m wide, 1500 kg; \
             debon-trailers.fr/remorque/remorque-porte-mini-voiture/",
}];

#[cfg(test)]
mod tests {
    use super::*;

    fn input() -> VehicleInput {
        VehicleInput {
            kind: VehicleKind::Overcab,
            height_m: 3.3,
            width_m: 2.3,
            length_m: 7.4,
            weight_t: 3.5,
            axle_load_t: None,
            trailer: None,
        }
    }

    #[test]
    fn a_typing_error_is_refused_with_the_field_named() {
        let cm = VehicleProfile::new(VehicleInput {
            height_m: 330.0,
            ..input()
        });
        assert!(
            matches!(
                cm,
                Err(InvalidVehicle::OutOfRange {
                    field: "heightM",
                    ..
                })
            ),
            "a height in centimetres must not reach the router: {cm:?}"
        );
        let kg = VehicleProfile::new(VehicleInput {
            weight_t: 3_500.0,
            ..input()
        });
        assert!(matches!(
            kg,
            Err(InvalidVehicle::OutOfRange {
                field: "weightT",
                ..
            })
        ));
        let nan = VehicleProfile::new(VehicleInput {
            width_m: f64::NAN,
            ..input()
        });
        assert_eq!(nan, Err(InvalidVehicle::NotFinite { field: "widthM" }));
        assert!(Trailer::new(5.0, 50.0, None, None).is_err());
    }

    #[test]
    fn the_trailer_adds_its_length_and_mass_and_raises_the_envelope() {
        let trailer = Trailer::new(5.0, 2.0, Some(2.0), Some(2.4)).unwrap();
        let p = VehicleProfile::new(VehicleInput {
            trailer: Some(trailer),
            ..input()
        })
        .unwrap();
        let d = p.routing();
        assert!((d.length_m - 12.4).abs() < 1e-9, "7.4 m plus 5 m");
        assert!(
            (d.weight_t - 5.5).abs() < 1e-9,
            "a B13 sign limits the combination"
        );
        assert!(
            (d.height_m - 3.3).abs() < 1e-9,
            "the motorhome stays the highest"
        );
        assert!(
            (d.width_m - 2.4).abs() < 1e-9,
            "the wider trailer sets the width"
        );
        assert_eq!(d.trailer_weight_t, Some(2.0));
        let too_long = VehicleProfile::new(VehicleInput {
            length_m: 14.0,
            trailer: Some(Trailer::new(12.0, 2.0, None, None).unwrap()),
            ..input()
        });
        assert!(matches!(
            too_long,
            Err(InvalidVehicle::CombinationTooLong { .. })
        ));
    }

    #[test]
    fn only_a_vehicle_over_three_and_a_half_tonnes_gets_the_110_cap() {
        let light = VehicleProfile::new(input()).unwrap();
        assert_eq!(
            light.routing().top_speed_kph,
            None,
            "3.5 t exactly is a light vehicle"
        );
        let heavy = VehicleProfile::new(VehicleInput {
            weight_t: 4.5,
            ..input()
        })
        .unwrap();
        assert_eq!(heavy.routing().top_speed_kph, Some(110), "R413-8-1");
    }

    #[test]
    fn every_preset_is_a_valid_profile_and_every_kind_but_other_has_one() {
        for preset in PRESETS {
            let p = VehicleProfile::new(VehicleInput {
                kind: preset.kind,
                height_m: preset.height_m,
                width_m: preset.width_m,
                length_m: preset.length_m,
                weight_t: preset.weight_t,
                axle_load_t: None,
                trailer: None,
            });
            assert!(p.is_ok(), "{preset:?}: {p:?}");
            assert!(!preset.source.is_empty());
        }
        for kind in VehicleKind::ALL {
            let has = PRESETS.iter().any(|p| p.kind == kind);
            assert_eq!(has, kind != VehicleKind::Other, "{kind:?}");
        }
        for t in TRAILER_PRESETS {
            assert!(
                Trailer::new(t.length_m, t.weight_t, None, Some(t.width_m)).is_ok(),
                "{t:?}"
            );
        }
        let mut ids: Vec<&str> = PRESETS.iter().map(|p| p.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), PRESETS.len(), "preset ids are unique");
    }
}
