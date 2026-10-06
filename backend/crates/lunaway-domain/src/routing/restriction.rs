//! A limit on the road network, where it comes from, and what it means for
//! one vehicle.

use serde::{Deserialize, Serialize};

use super::vehicle::{CARAVAN_SIGN_ABOVE_T, RoutingDimensions};

/// What a restriction limits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum RestrictionKind {
    /// Clearance, metres (B12).
    MaxHeight,
    /// Width, metres (B11).
    MaxWidth,
    /// Length of the vehicle or combination, metres (B10a).
    MaxLength,
    /// Total authorised mass, tonnes (B13).
    MaxWeight,
    /// Mass on one axle, tonnes (B13a).
    MaxAxleLoad,
    /// No motorhomes (`motorhome=no`).
    MotorhomeBan,
    /// No vehicle towing a trailer (`trailer=no`).
    TrailerBan,
    /// No vehicle towing a caravan or a trailer over 250 kg (B9i,
    /// `caravan=no`).
    CaravanBan,
    /// Total authorised mass of a heavy goods vehicle, tonnes: a DiaLog
    /// order that names goods vehicles. A motorhome is not one, so the
    /// limit is announced, never blocking.
    MaxWeightGoods,
}

impl RestrictionKind {
    /// Every kind.
    pub const ALL: [Self; 9] = [
        Self::MaxHeight,
        Self::MaxWidth,
        Self::MaxLength,
        Self::MaxWeight,
        Self::MaxAxleLoad,
        Self::MotorhomeBan,
        Self::TrailerBan,
        Self::CaravanBan,
        Self::MaxWeightGoods,
    ];

    /// The kinds that carry a figure.
    pub const LIMITS: [Self; 5] = [
        Self::MaxHeight,
        Self::MaxWidth,
        Self::MaxLength,
        Self::MaxWeight,
        Self::MaxAxleLoad,
    ];

    /// The code stored in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::MaxHeight => "max_height",
            Self::MaxWidth => "max_width",
            Self::MaxLength => "max_length",
            Self::MaxWeight => "max_weight",
            Self::MaxAxleLoad => "max_axle_load",
            Self::MotorhomeBan => "motorhome_ban",
            Self::TrailerBan => "trailer_ban",
            Self::CaravanBan => "caravan_ban",
            Self::MaxWeightGoods => "max_weight_goods",
        }
    }

    /// The kind of a stored code.
    #[must_use]
    pub fn from_code(code: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|k| k.code() == code)
    }

    /// The OpenStreetMap keys that carry this limit, the one Valhalla reads
    /// first. A ban has none: it is an access key.
    #[must_use]
    pub const fn osm_keys(self) -> &'static [&'static str] {
        match self {
            Self::MaxHeight => &["maxheight", "maxheight:physical"],
            Self::MaxWidth => &["maxwidth", "maxwidth:physical"],
            Self::MaxLength => &["maxlength"],
            // `maxweightrating` is the French B13 (wiki page "FR:Road signs
            // in France"); Valhalla reads `maxweight` only.
            Self::MaxWeight => &["maxweight", "maxweightrating"],
            Self::MaxAxleLoad => &["maxaxleload"],
            // Not an OpenStreetMap key: read from DiaLog only.
            Self::MotorhomeBan | Self::TrailerBan | Self::CaravanBan | Self::MaxWeightGoods => &[],
        }
    }

    /// The key Valhalla reads for this limit.
    #[must_use]
    pub const fn graph_key(self) -> &'static str {
        match self.osm_keys().first() {
            Some(k) => k,
            None => "",
        }
    }
}

/// Where a restriction comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum RestrictionSource {
    /// OpenStreetMap (ODbL).
    Osm,
    /// IGN BD TOPO (Licence Ouverte 2.0).
    Ign,
    /// A Lunaway user's report, once validated.
    Community,
    /// A permanent traffic order of DiaLog (Licence Ouverte 2.0).
    Dialog,
}

impl RestrictionSource {
    /// Every source.
    pub const ALL: [Self; 4] = [Self::Osm, Self::Ign, Self::Community, Self::Dialog];

    /// The code stored in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Osm => "osm",
            Self::Ign => "ign",
            Self::Community => "community",
            Self::Dialog => "dialog",
        }
    }

    /// The source of a stored code.
    #[must_use]
    pub fn from_code(code: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|s| s.code() == code)
    }

    /// How far, in metres, this source's geometry may lie from the road the
    /// router follows: OpenStreetMap shares its nodes with the graph; IGN
    /// draws its own centrelines, a few metres off.
    #[must_use]
    pub const fn tolerance_m(self) -> f64 {
        match self {
            Self::Osm => 3.0,
            // DiaLog draws its sections from the address and road
            // referentials, a few metres off OpenStreetMap like IGN.
            Self::Ign | Self::Dialog => 12.0,
            Self::Community => 15.0,
        }
    }
}

/// How sure the figure is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum Certainty {
    /// One figure, or two sources that agree.
    Known,
    /// Two sources disagree by more than the tolerance: the lower applies
    /// and the place waits for a human check.
    Disputed,
    /// Signposted lower than the standard clearance, figure unknown
    /// (`maxheight=below_default`).
    Unknown,
}

impl Certainty {
    /// Every certainty.
    pub const ALL: [Self; 3] = [Self::Known, Self::Disputed, Self::Unknown];

    /// The code stored in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Known => "known",
            Self::Disputed => "disputed",
            Self::Unknown => "unknown",
        }
    }

    /// The certainty of a stored code.
    #[must_use]
    pub fn from_code(code: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|c| c.code() == code)
    }
}

/// What the restricted place is, for a warning's wording ("bridge 3.20 m in
/// 2 km").
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum RestrictionFeature {
    /// The road passes under a bridge or through a short covered section.
    Underpass,
    /// A tunnel.
    Tunnel,
    /// A passage under a building (a porch).
    BuildingPassage,
    /// A bridge the road crosses (weight limits).
    Bridge,
    /// A barrier across the road: height bar, gate, bollards.
    Barrier,
    /// Any other stretch of road.
    Road,
}

impl RestrictionFeature {
    /// Every feature.
    pub const ALL: [Self; 6] = [
        Self::Underpass,
        Self::Tunnel,
        Self::BuildingPassage,
        Self::Bridge,
        Self::Barrier,
        Self::Road,
    ];

    /// The code stored in the database.
    #[must_use]
    pub const fn code(self) -> &'static str {
        match self {
            Self::Underpass => "underpass",
            Self::Tunnel => "tunnel",
            Self::BuildingPassage => "building_passage",
            Self::Bridge => "bridge",
            Self::Barrier => "barrier",
            Self::Road => "road",
        }
    }

    /// The feature of a stored code.
    #[must_use]
    pub fn from_code(code: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|f| f.code() == code)
    }
}

/// A restriction, without its geometry.
#[derive(Debug, Clone, PartialEq)]
pub struct Restriction {
    /// What it limits.
    pub kind: RestrictionKind,
    /// The figure, metres or tonnes; none for a ban or an unknown clearance.
    pub limit: Option<f64>,
    /// Where it comes from.
    pub source: RestrictionSource,
    /// How sure the figure is.
    pub certainty: Certainty,
    /// What the place is.
    pub feature: RestrictionFeature,
}

/// How a restriction weighs on a route.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum Severity {
    /// The vehicle may not pass: the route is computed again around it.
    Blocking,
    /// The vehicle may pass; the driver is told.
    Warning,
}

/// What a restriction means for the vehicle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum FindingKind {
    /// A clearance too low, or close to the vehicle's height.
    LowClearance,
    /// A clearance below the standard, figure unknown.
    UnknownClearance,
    /// A passage too narrow, or close to the vehicle's width.
    Narrow,
    /// A length limit below the vehicle's.
    TooLong,
    /// A weight limit below the vehicle's.
    TooHeavy,
    /// An axle load limit below the vehicle's.
    AxleLoad,
    /// No motorhomes.
    MotorhomeBan,
    /// No trailers, or no caravans and trailers over 250 kg.
    TrailerBan,
    /// A weight limit for heavy goods vehicles the vehicle exceeds: it
    /// does not apply to a motorhome, but the driver checks the signs.
    GoodsVehicleWeight,
}

/// A restriction weighed against a vehicle.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Finding {
    /// What it means.
    pub kind: FindingKind,
    /// Whether the vehicle may pass.
    pub severity: Severity,
    /// The figure, when there is one.
    pub limit: Option<f64>,
    /// The vehicle's own figure, when it is compared.
    pub vehicle_value: Option<f64>,
}

/// Margin under which a clearance is announced even though the vehicle
/// passes: a B12 sign shows 0.20 to 0.30 m less than the real clearance
/// (IISR part 4, art. 61), and a roof box or a rail is easily forgotten.
pub const HEIGHT_MARGIN_M: f64 = 0.30;
/// Margin under which a width limit is announced.
pub const WIDTH_MARGIN_M: f64 = 0.20;
/// Height assumed for a height bar mapped without its figure
/// (`barrier=height_restrictor` alone): the commonest figures of the bars
/// mapped with one in France are 2, 2.1, 1.9 and 2.2 m
/// (`plan/research/07-navigation.md`, B.1), so a vehicle above the highest
/// of them is stopped rather than sent to find out.
pub const ASSUMED_BAR_HEIGHT_M: f64 = 2.2;

/// What `restriction` means for a vehicle of `dims`: blocking when the
/// vehicle exceeds the limit (a limit equal to the vehicle's figure lets it
/// pass, as the router does), a warning when it passes with little margin
/// or the clearance is unknown, nothing otherwise. A weight or length limit
/// the vehicle respects is not announced: those signs are legal limits, not
/// a physical risk, and a 3.5 t motorhome meets a 3.5 t limit on many roads.
#[must_use]
pub fn assess(restriction: &Restriction, dims: &RoutingDimensions) -> Option<Finding> {
    let limit = restriction.limit;
    let compare = |kind: FindingKind, vehicle: f64, margin: Option<f64>| {
        let l = limit?;
        let severity = if vehicle > l + 1e-9 {
            Severity::Blocking
        } else if margin.is_some_and(|m| l - vehicle < m) {
            Severity::Warning
        } else {
            return None;
        };
        Some(Finding {
            kind,
            severity,
            limit: Some(l),
            vehicle_value: Some(vehicle),
        })
    };
    let ban = |kind: FindingKind| {
        Some(Finding {
            kind,
            severity: Severity::Blocking,
            limit: None,
            vehicle_value: None,
        })
    };
    match restriction.kind {
        RestrictionKind::MaxHeight if limit.is_none() => Some(Finding {
            kind: FindingKind::UnknownClearance,
            severity: if restriction.feature == RestrictionFeature::Barrier
                && dims.height_m > ASSUMED_BAR_HEIGHT_M
            {
                Severity::Blocking
            } else {
                Severity::Warning
            },
            limit: None,
            vehicle_value: Some(dims.height_m),
        }),
        RestrictionKind::MaxHeight => compare(
            FindingKind::LowClearance,
            dims.height_m,
            Some(HEIGHT_MARGIN_M),
        ),
        RestrictionKind::MaxWidth => {
            compare(FindingKind::Narrow, dims.width_m, Some(WIDTH_MARGIN_M))
        }
        RestrictionKind::MaxLength => compare(FindingKind::TooLong, dims.length_m, None),
        RestrictionKind::MaxWeight => compare(FindingKind::TooHeavy, dims.weight_t, None),
        RestrictionKind::MaxAxleLoad => match dims.axle_load_t {
            Some(a) => compare(FindingKind::AxleLoad, a, None),
            // The router does not read axle limits for this vehicle, so the
            // check is the only one. No axle carries more than the whole
            // vehicle: under the limit in total, it passes; above it, the
            // driver is told to check the axle loads.
            None => limit
                .filter(|l| dims.weight_t > *l + 1e-9)
                .map(|l| Finding {
                    kind: FindingKind::AxleLoad,
                    severity: Severity::Warning,
                    limit: Some(l),
                    vehicle_value: None,
                }),
        },
        RestrictionKind::MotorhomeBan => ban(FindingKind::MotorhomeBan),
        RestrictionKind::TrailerBan => dims
            .trailer_weight_t
            .and_then(|_| ban(FindingKind::TrailerBan)),
        RestrictionKind::CaravanBan => dims
            .trailer_weight_t
            .filter(|w| *w > CARAVAN_SIGN_ABOVE_T)
            .and_then(|_| ban(FindingKind::TrailerBan)),
        // An order for goods vehicles: told, never blocking.
        RestrictionKind::MaxWeightGoods => {
            limit
                .filter(|l| dims.weight_t > *l + 1e-9)
                .map(|l| Finding {
                    kind: FindingKind::GoodsVehicleWeight,
                    severity: Severity::Warning,
                    limit: Some(l),
                    vehicle_value: Some(dims.weight_t),
                })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dims(height_m: f64, weight_t: f64) -> RoutingDimensions {
        RoutingDimensions {
            height_m,
            width_m: 2.3,
            length_m: 7.4,
            weight_t,
            axle_load_t: None,
            trailer_weight_t: None,
            top_speed_kph: None,
        }
    }

    fn limit(kind: RestrictionKind, value: Option<f64>) -> Restriction {
        Restriction {
            kind,
            limit: value,
            source: RestrictionSource::Osm,
            certainty: Certainty::Known,
            feature: RestrictionFeature::Underpass,
        }
    }

    #[test]
    fn a_vehicle_higher_than_the_bridge_is_blocked_and_never_merely_warned() {
        let bridge = limit(RestrictionKind::MaxHeight, Some(3.0));
        let f = assess(&bridge, &dims(3.3, 3.5)).unwrap();
        assert_eq!(
            f.severity,
            Severity::Blocking,
            "3.3 m under 3.0 m must never pass"
        );
        assert_eq!(f.kind, FindingKind::LowClearance);
        let close = assess(&bridge, &dims(2.8, 3.5)).unwrap();
        assert_eq!(
            close.severity,
            Severity::Warning,
            "20 cm of margin is announced"
        );
        let equal = assess(&bridge, &dims(3.0, 3.5)).unwrap();
        assert_eq!(
            equal.severity,
            Severity::Warning,
            "equal passes, as in the router"
        );
        assert_eq!(assess(&bridge, &dims(2.5, 3.5)), None);
        let unknown = assess(&limit(RestrictionKind::MaxHeight, None), &dims(2.5, 3.5)).unwrap();
        assert_eq!(unknown.kind, FindingKind::UnknownClearance);
        assert_eq!(unknown.severity, Severity::Warning);
    }

    #[test]
    fn a_weight_limit_blocks_above_it_and_says_nothing_below() {
        let bridge = limit(RestrictionKind::MaxWeight, Some(3.5));
        assert_eq!(
            assess(&bridge, &dims(3.0, 4.5)).map(|f| f.severity),
            Some(Severity::Blocking)
        );
        assert_eq!(assess(&bridge, &dims(3.0, 3.5)), None);
    }

    #[test]
    fn trailer_bans_concern_a_towing_vehicle_only() {
        let mut d = dims(3.0, 3.5);
        let trailer = limit(RestrictionKind::TrailerBan, None);
        let caravan = limit(RestrictionKind::CaravanBan, None);
        assert_eq!(assess(&trailer, &d), None);
        d.trailer_weight_t = Some(0.2);
        assert_eq!(
            assess(&trailer, &d).map(|f| f.severity),
            Some(Severity::Blocking)
        );
        assert_eq!(
            assess(&caravan, &d),
            None,
            "B9i spares a trailer of 250 kg or less"
        );
        d.trailer_weight_t = Some(1.5);
        assert_eq!(
            assess(&caravan, &d).map(|f| f.kind),
            Some(FindingKind::TrailerBan)
        );
        assert_eq!(
            assess(&limit(RestrictionKind::MotorhomeBan, None), &dims(2.0, 2.0))
                .map(|f| f.severity),
            Some(Severity::Blocking)
        );
    }

    #[test]
    fn a_height_bar_without_its_figure_stops_a_tall_vehicle() {
        let bar = Restriction {
            feature: RestrictionFeature::Barrier,
            ..limit(RestrictionKind::MaxHeight, None)
        };
        assert_eq!(
            assess(&bar, &dims(3.3, 3.5)).map(|f| f.severity),
            Some(Severity::Blocking),
            "a car park bar is about 2 m: a motorhome is not sent to find out"
        );
        assert_eq!(
            assess(&bar, &dims(1.99, 2.9)).map(|f| f.severity),
            Some(Severity::Warning)
        );
    }

    #[test]
    fn an_axle_limit_needs_the_vehicle_s_axle_load() {
        let r = limit(RestrictionKind::MaxAxleLoad, Some(6.0));
        let mut d = dims(3.0, 7.5);
        assert_eq!(
            assess(&r, &d).map(|f| f.severity),
            Some(Severity::Warning),
            "7.5 t in total may put more than 6 t on an axle: the driver checks"
        );
        assert_eq!(assess(&r, &dims(3.0, 5.0)), None, "5 t in total cannot");
        d.axle_load_t = Some(6.5);
        assert_eq!(assess(&r, &d).map(|f| f.severity), Some(Severity::Blocking));
    }

    #[test]
    fn a_goods_vehicle_weight_limit_warns_a_heavy_motorhome_and_never_blocks() {
        let order = limit(RestrictionKind::MaxWeightGoods, Some(3.5));
        let heavy = assess(&order, &dims(3.0, 4.5)).unwrap();
        assert_eq!(heavy.kind, FindingKind::GoodsVehicleWeight);
        assert_eq!(
            heavy.severity,
            Severity::Warning,
            "a motorhome is not a goods vehicle: the order cannot close the road to it"
        );
        assert_eq!(assess(&order, &dims(3.0, 3.5)), None);
    }

    #[test]
    fn codes_read_back() {
        for k in RestrictionKind::ALL {
            assert_eq!(RestrictionKind::from_code(k.code()), Some(k));
        }
        for s in RestrictionSource::ALL {
            assert_eq!(RestrictionSource::from_code(s.code()), Some(s));
        }
        for c in Certainty::ALL {
            assert_eq!(Certainty::from_code(c.code()), Some(c));
        }
        for f in RestrictionFeature::ALL {
            assert_eq!(RestrictionFeature::from_code(f.code()), Some(f));
        }
        assert_eq!(RestrictionKind::MaxWeight.graph_key(), "maxweight");
    }
}
