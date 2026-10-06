//! The speed limit along a route, for a motorhome: the posted limit where
//! OpenStreetMap gives one, the limit a road takes by default otherwise
//! (France only for now), and the lower ceiling of the vehicle on top
//! (`plan/research/28-radars-limites.md`, part 3).
//!
//! France, Code de la route (codes.droit.org, edition of 2026-09-10):
//! - R413-2 and R413-3: 130 on a motorway, 110 on a road with separated
//!   carriageways, 80 elsewhere outside built-up areas, 50 inside them;
//! - R413-8, a gross weight or a train weight above 3.5 t: 90 on a
//!   motorway, 80 on priority roads (90 on separated carriageways up to
//!   12 t), 80 elsewhere, 50 in built-up areas;
//! - R413-8-1, the vehicles of R413-8 "destinés au transport de personnes"
//!   of 3.5 to 12 t gross weight, a motorhome among them: 110 on a
//!   motorway, 100 on separated carriageways, 80 elsewhere.
//!
//! A motorhome of 3.5 t or less towing a trailer that takes the train above
//! 3.5 t falls under R413-8, which counts the train weight, while R413-8-1
//! counts the vehicle's own: 90 and 80 (90 on separated carriageways). A
//! motorhome above 3.5 t that tows also counts as R413-8, the stricter of
//! the two. The open table `osm-legal-default-speeds` gives 90 on a French
//! motorway to every vehicle above 3.5 t, which is wrong for a motorhome.
//!
//! The rain limits (R413-2 II) are not applied: the server cannot know the
//! weather. A road with separated carriageways is read as a one-way
//! OpenStreetMap `trunk` (each carriageway of a dual carriageway is drawn
//! as a one-way way); a `trunk` open both ways gets the limits of an
//! ordinary road.

use serde::{Deserialize, Serialize};

use crate::Position;

/// The class of a road, as the routing engine gives it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RoadClass {
    /// `motorway`.
    Motorway,
    /// `trunk`: separated carriageways, as a rule.
    Trunk,
    /// `primary`.
    Primary,
    /// `secondary`.
    Secondary,
    /// `tertiary`.
    Tertiary,
    /// `unclassified`.
    Unclassified,
    /// `residential`.
    Residential,
    /// Anything else (`service_other`).
    Service,
}

impl RoadClass {
    /// The class the engine names `name`.
    #[must_use]
    pub fn of(name: &str) -> Self {
        match name {
            "motorway" => Self::Motorway,
            "trunk" => Self::Trunk,
            "primary" => Self::Primary,
            "secondary" => Self::Secondary,
            "tertiary" => Self::Tertiary,
            "unclassified" => Self::Unclassified,
            "residential" => Self::Residential,
            _ => Self::Service,
        }
    }
}

/// Urban density from which a road counts as inside a built-up area: the
/// engine's density (0 to 15) of the edges of the Limoges to Brive route
/// (Valhalla 3.9.0, 2026-10-06) was 1 to 4 on the motorway and its rural
/// roads posted 70 to 130, 5 to 14 where the posted limit was 50 or 30.
pub const URBAN_DENSITY: u8 = 6;

/// One stretch of a route, as the engine describes it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stretch {
    /// The road's class.
    pub class: RoadClass,
    /// A ramp or a link (`use` = `ramp`, `turn_channel`): its limit is set
    /// by signs, never by default.
    pub link: bool,
    /// The posted limit, km/h, when OpenStreetMap gives one.
    pub posted_kmh: Option<u16>,
    /// Open in one direction only (`traversability` `forward` or
    /// `backward`).
    pub oneway: bool,
    /// The engine's urban density, 0 to 15.
    pub density: u8,
}

/// The vehicle, for its ceilings.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vehicle {
    /// Gross weight (PTAC), tonnes.
    pub weight_t: f64,
    /// The trailer's gross weight, tonnes, when it tows one.
    pub trailer_weight_t: Option<f64>,
}

impl Vehicle {
    /// Gross train weight (PTRA), tonnes.
    #[must_use]
    pub fn train_weight_t(self) -> f64 {
        self.weight_t + self.trailer_weight_t.unwrap_or(0.0)
    }
}

/// Where a limit comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LimitSource {
    /// A sign, as OpenStreetMap maps it.
    Posted,
    /// The road's default in its country: an estimate.
    Default,
    /// The vehicle's own ceiling, lower than the road's limit.
    Vehicle,
}

/// The limit for the vehicle on a stretch, and where it comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limit {
    /// km/h.
    pub kmh: u16,
    /// Its origin.
    pub source: LimitSource,
}

/// Whether a stretch is inside a built-up area.
const fn urban(s: &Stretch) -> bool {
    s.density >= URBAN_DENSITY
}

/// Whether a stretch is a carriageway of a road with separated
/// carriageways.
fn separated(s: &Stretch) -> bool {
    s.class == RoadClass::Trunk && s.oneway
}

/// The default limit of a stretch in `country` for a car, when no sign
/// says: France only.
#[must_use]
pub fn default_kmh(country: &str, s: &Stretch) -> Option<u16> {
    if !country.eq_ignore_ascii_case("FR") || s.link || s.class == RoadClass::Service {
        return None;
    }
    Some(match s.class {
        RoadClass::Motorway => 130,
        _ if separated(s) => 110,
        _ if urban(s) => 50,
        _ => 80,
    })
}

/// The vehicle's ceiling on a stretch in `country`: France only.
#[must_use]
pub fn vehicle_ceiling_kmh(country: &str, s: &Stretch, v: Vehicle) -> Option<u16> {
    if !country.eq_ignore_ascii_case("FR") {
        return None;
    }
    let heavy = v.weight_t > 3.5;
    let heavy_train = v.train_weight_t() > 3.5;
    if !heavy && !heavy_train {
        return None;
    }
    let motorway = s.class == RoadClass::Motorway;
    if urban(s) && !motorway && !separated(s) {
        return Some(50);
    }
    // R413-8-1: a motorhome of 3.5 to 12 t without a trailer that takes
    // the train above 3.5 t.
    let passenger = heavy && v.weight_t <= 12.0 && v.trailer_weight_t.is_none();
    Some(match (motorway, separated(s), passenger) {
        (true, _, true) => 110,
        (false, true, true) => 100,
        (true, _, false) => 90,
        // R413-8: 90 on separated carriageways up to 12 t.
        (false, true, false) if v.train_weight_t() <= 12.0 => 90,
        _ => 80,
    })
}

/// The limit for `vehicle` on a stretch of `country`: the posted or default
/// limit, lowered to the vehicle's ceiling; none when nothing is known.
#[must_use]
pub fn limit(country: &str, s: &Stretch, vehicle: Vehicle) -> Option<Limit> {
    let road = s
        .posted_kmh
        .map(|kmh| Limit {
            kmh,
            source: LimitSource::Posted,
        })
        .or_else(|| {
            default_kmh(country, s).map(|kmh| Limit {
                kmh,
                source: LimitSource::Default,
            })
        });
    let ceiling = vehicle_ceiling_kmh(country, s, vehicle);
    match (road, ceiling) {
        (Some(r), Some(c)) if c < r.kmh => Some(Limit {
            kmh: c,
            source: LimitSource::Vehicle,
        }),
        (Some(r), _) => Some(r),
        // No sign and no default, but a ceiling: what the vehicle may not
        // exceed is still known.
        (None, Some(c)) => Some(Limit {
            kmh: c,
            source: LimitSource::Vehicle,
        }),
        (None, None) => None,
    }
}

/// One edge of a route, as the engine describes it, and the shape points
/// it runs between.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Edge {
    /// What the engine says of it.
    pub stretch: Stretch,
    /// Index of its first shape point in the route's shape.
    pub begin: usize,
    /// Index of its last shape point.
    pub end: usize,
}

/// A run of a route under one limit for the vehicle.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Span {
    /// Index of its first shape point.
    pub from_index: usize,
    /// Index of its last shape point.
    pub to_index: usize,
    /// Distance from the route's start where it begins, metres.
    pub from_m: f64,
    /// Distance from the route's start where it ends, metres.
    pub to_m: f64,
    /// The limit.
    pub limit: Limit,
}

/// The limits along a route of shape `points` (`along`: each point's
/// distance from the start) for `vehicle`, from the engine's `edges` in
/// driving order: one span per run of the same limit, none where no limit
/// is known. Each edge takes the rules of the country its first point lies
/// in.
#[must_use]
pub fn spans(points: &[Position], along: &[f64], edges: &[Edge], vehicle: Vehicle) -> Vec<Span> {
    let mut out: Vec<Span> = Vec::new();
    for e in edges {
        let (Some(at), Some(from_m), Some(to_m)) =
            (points.get(e.begin), along.get(e.begin), along.get(e.end))
        else {
            continue;
        };
        if e.end < e.begin {
            continue;
        }
        let country = crate::region::country_at(*at).unwrap_or("");
        let Some(l) = limit(country, &e.stretch, vehicle) else {
            continue;
        };
        match out.last_mut() {
            Some(last) if last.limit == l && last.to_index == e.begin => {
                last.to_index = e.end;
                last.to_m = *to_m;
            }
            _ => out.push(Span {
                from_index: e.begin,
                to_index: e.end,
                from_m: *from_m,
                to_m: *to_m,
                limit: l,
            }),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(class: RoadClass, posted: Option<u16>, density: u8) -> Stretch {
        Stretch {
            class,
            link: false,
            posted_kmh: posted,
            oneway: matches!(class, RoadClass::Motorway | RoadClass::Trunk),
            density,
        }
    }

    const CAR: Vehicle = Vehicle {
        weight_t: 3.5,
        trailer_weight_t: None,
    };
    const HEAVY: Vehicle = Vehicle {
        weight_t: 4.5,
        trailer_weight_t: None,
    };
    const TOWING: Vehicle = Vehicle {
        weight_t: 3.0,
        trailer_weight_t: Some(1.2),
    };

    fn kmh(country: &str, st: Stretch, v: Vehicle) -> Option<(u16, LimitSource)> {
        limit(country, &st, v).map(|l| (l.kmh, l.source))
    }

    #[test]
    fn a_motorhome_over_3_5_t_keeps_its_own_ceilings_in_france() {
        use LimitSource::{Default, Posted, Vehicle as Own};
        let motorway = s(RoadClass::Motorway, Some(130), 2);
        assert_eq!(kmh("FR", motorway, CAR), Some((130, Posted)));
        assert_eq!(kmh("FR", motorway, HEAVY), Some((110, Own)), "R413-8-1");
        assert_eq!(
            kmh("FR", motorway, TOWING),
            Some((90, Own)),
            "R413-8, the train"
        );
        let trunk = s(RoadClass::Trunk, None, 3);
        assert_eq!(kmh("FR", trunk, CAR), Some((110, Default)));
        assert_eq!(kmh("FR", trunk, HEAVY), Some((100, Own)));
        assert_eq!(kmh("FR", trunk, TOWING), Some((90, Own)));
        let rural = s(RoadClass::Secondary, None, 3);
        assert_eq!(kmh("FR", rural, CAR), Some((80, Default)));
        assert_eq!(kmh("FR", rural, HEAVY), Some((80, Default)));
        let town = s(RoadClass::Secondary, None, 10);
        assert_eq!(kmh("FR", town, HEAVY), Some((50, Default)));
        let zone30 = s(RoadClass::Residential, Some(30), 14);
        assert_eq!(
            kmh("FR", zone30, HEAVY),
            Some((30, Posted)),
            "a lower sign wins"
        );
        let ninety = s(RoadClass::Primary, Some(90), 3);
        assert_eq!(kmh("FR", ninety, HEAVY), Some((80, Own)));
        let single = Stretch {
            oneway: false,
            ..s(RoadClass::Trunk, None, 3)
        };
        assert_eq!(
            kmh("FR", single, CAR),
            Some((80, Default)),
            "one carriageway both ways"
        );
        let heavier = Vehicle {
            weight_t: 13.0,
            trailer_weight_t: None,
        };
        assert_eq!(kmh("FR", motorway, heavier), Some((90, Own)), "above 12 t");
    }

    #[test]
    fn elsewhere_only_the_sign_is_known_for_now() {
        let motorway = s(RoadClass::Motorway, None, 2);
        assert_eq!(kmh("DE", motorway, HEAVY), None);
        let signed = s(RoadClass::Primary, Some(70), 3);
        assert_eq!(kmh("ES", signed, HEAVY), Some((70, LimitSource::Posted)));
        let ramp = Stretch {
            link: true,
            ..s(RoadClass::Motorway, None, 2)
        };
        assert_eq!(
            kmh("FR", ramp, CAR),
            None,
            "a link's limit is never guessed"
        );
        assert_eq!(kmh("FR", ramp, HEAVY), Some((110, LimitSource::Vehicle)));
    }

    #[test]
    fn runs_of_one_limit_make_one_span_and_unknown_stretches_none() {
        #[allow(
            clippy::unwrap_used,
            reason = "a test states its preconditions with unwrap"
        )]
        let points: Vec<Position> = (0..6)
            .map(|i| Position::new(45.8, 1.3 + f64::from(i) * 0.01).unwrap())
            .collect();
        let along: Vec<f64> = (0..6).map(|i| f64::from(i) * 780.0).collect();
        let edge = |class, posted, begin, end| Edge {
            stretch: s(class, posted, 3),
            begin,
            end,
        };
        let edges = [
            edge(RoadClass::Motorway, Some(130), 0, 1),
            edge(RoadClass::Motorway, None, 1, 2),
            edge(RoadClass::Service, None, 2, 3),
            edge(RoadClass::Primary, Some(70), 3, 5),
        ];
        let got = spans(&points, &along, &edges, HEAVY);
        let summary: Vec<(usize, usize, u16, LimitSource)> = got
            .iter()
            .map(|s| (s.from_index, s.to_index, s.limit.kmh, s.limit.source))
            .collect();
        assert_eq!(
            summary,
            [
                (0, 2, 110, LimitSource::Vehicle),
                (2, 3, 80, LimitSource::Vehicle),
                (3, 5, 70, LimitSource::Posted)
            ],
            "posted 130 and no sign on a motorway are both 110 for a heavy motorhome"
        );
        assert!((got[2].from_m - 2_340.0).abs() < 1e-9 && (got[2].to_m - 3_900.0).abs() < 1e-9);
        let car = spans(&points, &along, &edges, CAR);
        assert_eq!(
            car.iter()
                .map(|s| (s.limit.kmh, s.limit.source))
                .collect::<Vec<_>>(),
            [
                (130, LimitSource::Posted),
                (130, LimitSource::Default),
                (70, LimitSource::Posted)
            ],
            "a car: the sign, the motorway's default apart, nothing on a service road"
        );
    }
}
