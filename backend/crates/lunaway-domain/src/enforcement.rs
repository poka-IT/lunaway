//! Speed cameras: what each country allows an app to carry, and the danger
//! zones Lunaway serves where positions may not be shown.
//!
//! The rules are a table per country, versioned here with the legal source
//! of each line (`plan/research/28-radars-limites.md`, part 1). A country
//! missing from the table is [`Mode::Off`]. The API applies the table when
//! it builds what it serves and again when it serves it; the app applies it
//! by the country it is in. A line may let a user choose a less strict mode
//! by an explicit setting ([`CountryRule::opt_in`]: France's cameras as
//! points in place of zones); the rules are then read with the user's
//! choices ([`OptIns`]).
//!
//! In a [`Mode::Zones`] country a camera becomes a stretch of road whose
//! length depends on the road, the camera somewhere inside it: its place
//! along the zone comes from a keyed hash of the camera's id, the zone's
//! length and its direction, with a secret of the server
//! ([`zone_fraction`]). It stays the same from one build to the next while
//! the zone keeps its length and direction; a zone that changes either
//! takes another share, so two versions compared narrow the camera down to
//! where they overlap, never closer than 15 % of the shorter zone on each
//! side. The line is drawn with a point every [`ZONE_STEP_M`] from its
//! start, none of them the road's own vertices ([`zone_cut`]).

use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{Position, UnknownCode, taxonomy::coded_enum};

coded_enum! {
    /// What a country allows an app to carry about speed cameras.
    Mode {
        /// Nothing: no data served for a position in the country, nothing
        /// shown, no alert.
        Off => "off",
        /// Positions may be shown, but no alert and no display while
        /// driving: the driver may not use the function on the move.
        OffWhileDriving => "off_while_driving",
        /// Danger zones only: stretches of road, never a camera's point.
        Zones => "zones",
        /// Exact positions of the cameras.
        Exact => "exact",
    }
}

impl Mode {
    /// How strict the mode is: the stricter of two rules applies where they
    /// meet (at a border, the app takes the stricter at once).
    #[must_use]
    pub const fn strictness(self) -> u8 {
        match self {
            Self::Off => 3,
            Self::OffWhileDriving => 2,
            Self::Zones => 1,
            Self::Exact => 0,
        }
    }
}

/// Lengths of a danger zone, metres, by the road it is on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct ZoneLengths {
    /// On a motorway (a camera's limit 110 km/h or above).
    pub motorway_m: u32,
    /// Outside built-up areas.
    pub rural_m: u32,
    /// In a built-up area (a limit of 50 km/h or below).
    pub urban_m: u32,
}

/// The lengths French practice gives a zone since 2011: 4 km on a
/// motorway, 2 km outside built-up areas, 500 m in them. The agreement
/// between the State and the AFFTAC that sets them is not published; these
/// figures come from the press (Le Parisien of 2017-04-27, as Wikipédia
/// "Avertisseur de radar" cites it), not from a text Lunaway read, and stand
/// until a lawyer confirms them.
pub const FRENCH_ZONES: ZoneLengths = ZoneLengths {
    motorway_m: 4_000,
    rural_m: 2_000,
    urban_m: 500,
};

/// One country's rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CountryRule {
    /// ISO 3166-1 alpha-2.
    pub country: &'static str,
    /// What the app may carry, by default.
    pub mode: Mode,
    /// The mode a user may choose in place of [`Self::mode`], by an
    /// explicit setting of the app; `None` where the line offers no choice.
    /// Never stricter than the default: a [`Mode::Zones`] line that lets a
    /// user ask for [`Mode::Exact`].
    pub opt_in: Option<Mode>,
    /// The zones' lengths, in a [`Mode::Zones`] country.
    pub zones: Option<ZoneLengths>,
    /// The texts the rule rests on, and the decision behind its choice.
    pub sources: &'static str,
}

impl CountryRule {
    /// The mode that applies for a user who made the line's choice
    /// (`chosen`) or not: [`Self::opt_in`] when chosen and offered, else
    /// [`Self::mode`].
    #[must_use]
    pub fn mode_for(&self, chosen: bool) -> Mode {
        if chosen {
            self.opt_in.unwrap_or(self.mode)
        } else {
            self.mode
        }
    }
}

/// The table's version: it moves with every change of a line, and the app
/// keeps the version it last read.
pub const RULES_VERSION: u32 = 2;

/// When the table was last checked against its sources.
pub const RULES_REVIEWED: &str = "2026-10-09";

const fn rule(country: &'static str, mode: Mode, sources: &'static str) -> CountryRule {
    CountryRule {
        country,
        mode,
        opt_in: None,
        zones: None,
        sources,
    }
}

const fn zones(country: &'static str, sources: &'static str) -> CountryRule {
    CountryRule {
        country,
        mode: Mode::Zones,
        opt_in: None,
        zones: Some(FRENCH_ZONES),
        sources,
    }
}

/// A zone line whose users may ask for the cameras' positions instead.
const fn zones_or_exact(country: &'static str, sources: &'static str) -> CountryRule {
    CountryRule {
        opt_in: Some(Mode::Exact),
        ..zones(country, sources)
    }
}

/// The table. Decisions of 2026-10-06 (product owner): France in zones by
/// default; Switzerland off with no data served for a Swiss position;
/// Germany off while driving; Morocco off; the others as the research
/// concludes, the stricter mode where it leaves a doubt: Portugal, Italy
/// and Ireland, where an app is legal "with a reserve" (a text broad enough
/// to cover it), take zones like Norway and Finland. The zone countries
/// other than France take the French lengths, which no text of theirs sets.
///
/// Decision of 2026-10-09 (product owner): in France a user may ask, by an
/// explicit setting of the app, for the cameras' exact positions; without
/// it, zones as before. No other line offers a choice.
pub const RULES: &[CountryRule] = &[
    zones_or_exact(
        "FR",
        "Code de la route R413-15 (V), L130-11, L130-12; zone lengths from the press; \
         exact positions on the user's explicit setting: decision of the product owner, \
         2026-10-09",
    ),
    rule(
        "CH",
        Mode::Off,
        "LCR art. 98a; BGer 6B_352/2008 (a preloaded database is covered)",
    ),
    rule(
        "DE",
        Mode::OffWhileDriving,
        "StVO §23 Abs. 1c (apps named since 2020-04-28); OLG Karlsruhe 2 ORbs 35 Ss 9/23",
    ),
    rule("MA", Mode::Off, "loi 52-05 not read"),
    zones(
        "NO",
        "vegtrafikkloven §13 a (equipment that warns of controls)",
    ),
    zones("FI", "laki 546/1998 (revealing a control)"),
    zones("PT", "Código da Estrada art. 84 (\"revelar a presença\")"),
    zones(
        "IT",
        "Codice della strada art. 45 c. 9-bis; Cassazione 3853/2014 not read",
    ),
    zones("IE", "S.I. 50/1991 (broad definition)"),
    rule(
        "AT",
        Mode::Exact,
        "KFG §98a (devices that influence or disturb only)",
    ),
    rule("LU", Mode::Exact, "lois du 1993-08-26 et du 2002-08-02"),
    rule(
        "BE",
        Mode::Exact,
        "loi du 16 mars 1968, art. 62bis (detectors only)",
    ),
    rule(
        "NL",
        Mode::Exact,
        "detectors forbidden since 2004; apps in common use",
    ),
    rule(
        "ES",
        Mode::Exact,
        "RDL 6/2015 art. 13.6 (position warnings excluded)",
    ),
    rule(
        "GB",
        Mode::Exact,
        "RTA 1988 s.41C never in force; Hansard 2005-07-04",
    ),
    rule("SE", Mode::Exact, "lag 1988:15 (radar detectors only)"),
    rule(
        "DK",
        Mode::Exact,
        "BEK 748/1998 (receivers of police waves only)",
    ),
    rule("HR", Mode::Exact, "ZSPC art. 283 (detectors only)"),
    rule("SI", Mode::Exact, "ZPrCP art. 36 (jammers only)"),
    rule(
        "GR",
        Mode::Exact,
        "loi 5209/2025 art. 24 § 11 (detectors only)",
    ),
    rule(
        "PL",
        Mode::Exact,
        "Prawo o ruchu drogowym art. 66 (devices that detect the measurement)",
    ),
    rule(
        "CZ",
        Mode::Exact,
        "zákon 361/2000 (devices that disturb the measurement)",
    ),
];

/// The rule of `country` (ISO 3166-1 alpha-2, any case); a country the
/// table does not name is off.
#[must_use]
pub fn rule_of(country: &str) -> CountryRule {
    RULES
        .iter()
        .copied()
        .find(|r| r.country.eq_ignore_ascii_case(country))
        .unwrap_or(CountryRule {
            country: "",
            mode: Mode::Off,
            opt_in: None,
            zones: None,
            sources: "not in the table",
        })
}

/// The mode at `p`, by the country it lies in; off at sea or where no
/// boundary says.
#[must_use]
pub fn mode_at(p: Position) -> Mode {
    crate::region::country_at(p).map_or(Mode::Off, |c| rule_of(c).mode)
}

/// How far around a point the rule of a neighbouring country counts too,
/// metres. The embedded boundaries are simplified: they strive "to have at
/// least every settlement and major road on the correct side of the
/// border" (country-boundaries 1.2.0, README), so a camera near a border
/// may read on the wrong side of it.
pub const BORDER_MARGIN_M: f64 = 1_000.0;

/// The form the server may serve where several rules meet: nothing when
/// one is off, zones when one allows only zones, points otherwise (off
/// while driving when one says so). This order is about what leaves the
/// server; the app's order at a border is [`Mode::strictness`].
#[must_use]
pub fn served_form(modes: impl IntoIterator<Item = Mode>) -> Mode {
    let rank = |m: Mode| match m {
        Mode::Off => 3,
        Mode::Zones => 2,
        Mode::OffWhileDriving => 1,
        Mode::Exact => 0,
    };
    modes
        .into_iter()
        .max_by_key(|m| rank(*m))
        .unwrap_or(Mode::Off)
}

/// The points around `p` a border check reads: every 45 degrees on circles
/// of half [`BORDER_MARGIN_M`] and of the whole of it, 16 points, none of
/// them more than about 400 m from any point of the disc.
fn ring(p: Position) -> impl Iterator<Item = Position> {
    [BORDER_MARGIN_M / 2.0, BORDER_MARGIN_M]
        .into_iter()
        .flat_map(move |r| (0..8).filter_map(move |k| toward(p, f64::from(k) * 45.0, r)))
}

/// The form the server may serve at `p` to a client that made no choice:
/// the rule of the country it lies in, and of every country within
/// [`BORDER_MARGIN_M`] of it; off where no country holds `p` itself (at
/// sea). The sea around it does not count: a coastal road keeps its
/// country's rule.
#[must_use]
pub fn mode_near(p: Position) -> Mode {
    OptIns::default().mode_near(p)
}

/// The countries where a user asked, by an explicit setting of the app,
/// for the mode their line lets them choose ([`CountryRule::opt_in`]):
/// each once, upper case, sorted. A country whose line offers no choice is
/// not kept, so asking for it changes nothing.
#[derive(Debug, Clone, Default, PartialEq, Eq, Hash)]
pub struct OptIns(Vec<&'static str>);

impl OptIns {
    /// The choices among `countries` (ISO 3166-1 alpha-2, any case) that
    /// the table offers.
    #[must_use]
    pub fn new<'a>(countries: impl IntoIterator<Item = &'a str>) -> Self {
        let mut kept: Vec<&'static str> = countries
            .into_iter()
            .filter_map(|c| {
                RULES
                    .iter()
                    .find(|r| r.opt_in.is_some() && r.country.eq_ignore_ascii_case(c))
            })
            .map(|r| r.country)
            .collect();
        kept.sort_unstable();
        kept.dedup();
        Self(kept)
    }

    /// The countries chosen.
    #[must_use]
    pub fn countries(&self) -> &[&'static str] {
        &self.0
    }

    /// Whether no choice was made.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// Whether the user chose `country`'s option (any case).
    #[must_use]
    pub fn contains(&self, country: &str) -> bool {
        self.0.iter().any(|c| c.eq_ignore_ascii_case(country))
    }

    /// The mode in `country` for a user with these choices.
    #[must_use]
    pub fn mode_of(&self, country: &str) -> Mode {
        rule_of(country).mode_for(self.contains(country))
    }

    /// [`mode_near`] for a user with these choices: each country's rule
    /// read with its choice.
    #[must_use]
    pub fn mode_near(&self, p: Position) -> Mode {
        let Some(own) = crate::region::country_at(p) else {
            return Mode::Off;
        };
        served_form(
            std::iter::once(own)
                .chain(ring(p).filter_map(crate::region::country_at))
                .map(|c| self.mode_of(c)),
        )
    }

    /// The form a camera of `country` at `p` takes for a user with these
    /// choices: its country's rule and the rules of every country within
    /// [`BORDER_MARGIN_M`] of it ([`served_form`]).
    #[must_use]
    pub fn form_of(&self, country: &str, p: Position) -> Mode {
        served_form([self.mode_of(country), self.mode_near(p)])
    }
}

/// The choices that can change the form of a camera of `country` at `p`:
/// those the table offers among its country and the countries within
/// [`BORDER_MARGIN_M`] of it. A Spanish camera at Irun depends on France's.
#[must_use]
pub fn choices_near(country: &str, p: Position) -> OptIns {
    let mut around: Vec<&str> = vec![country];
    for c in std::iter::once(p)
        .chain(ring(p))
        .filter_map(crate::region::country_at)
    {
        around.push(c);
    }
    OptIns::new(around)
}

/// Whether `p` lies in `country`, or within [`BORDER_MARGIN_M`] of it.
#[must_use]
pub fn near_country(p: Position, country: &str) -> bool {
    std::iter::once(p)
        .chain(ring(p))
        .filter_map(crate::region::country_at)
        .any(|c| c.eq_ignore_ascii_case(country))
}

coded_enum! {
    /// What a camera controls, as the sources describe it.
    DeviceKind {
        /// A fixed speed camera (France's `fixes`, `discriminants`,
        /// `urbain`).
        Fixed => "fixed",
        /// A red light camera (France's `feux`).
        RedLight => "red_light",
        /// An average speed section: its start (France's `troncons`).
        Section => "section",
        /// A camera at a level crossing (France's `niveaux`).
        LevelCrossing => "level_crossing",
    }
}

coded_enum! {
    /// What a danger zone covers, as the app names it.
    ZoneKind {
        /// A fixed camera.
        Fixed => "fixed",
        /// A red light camera, at a junction or a level crossing.
        RedLight => "red_light",
        /// An average speed section.
        SectionControl => "section_control",
    }
}

impl DeviceKind {
    /// The zone a camera of this kind gives.
    #[must_use]
    pub const fn zone_kind(self) -> ZoneKind {
        match self {
            Self::Fixed => ZoneKind::Fixed,
            Self::RedLight | Self::LevelCrossing => ZoneKind::RedLight,
            Self::Section => ZoneKind::SectionControl,
        }
    }
}

/// The length of a zone around a camera controlling `limit_kmh` (none when
/// unknown) with the country's `lengths`: a motorway's at 110 km/h and
/// above, a built-up area's at 50 and below, the rural length otherwise and
/// when the limit is not known (the longer zone hides more).
#[must_use]
pub fn zone_length_m(lengths: ZoneLengths, limit_kmh: Option<u16>) -> u32 {
    match limit_kmh {
        Some(l) if l >= 110 => lengths.motorway_m,
        Some(l) if l <= 50 => lengths.urban_m,
        _ => lengths.rural_m,
    }
}

/// How a zone lies on its road, whichever way the road is driven: its
/// length, and the half of the compass its road points to when read toward
/// the east (its canonical direction, a heading from 0 to 180 degrees).
///
/// The share of a zone is measured along that canonical direction, so the
/// same road driven either way gives the same zone: a direction tag edited
/// on OpenStreetMap, or a direction guessed the other way, changes nothing.
/// The share also depends on the frame: a zone whose length changes (a
/// limit mapped or removed), or whose road reads in the other half of the
/// compass (a road running north and south, its heading wavering across
/// due north between two graphs, flips its canonical direction), takes
/// another share, so that the old and the new zone do not solve for the
/// camera together. Each version narrows the camera down to where the
/// versions overlap; a camera has at most six (three lengths, two halves).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ZoneFrame {
    /// The zone's length, metres.
    pub length_m: u32,
    /// Whether its canonical direction points to the north-east half
    /// (0 to 90 degrees) rather than the south-east one (90 to 180).
    pub north_east: bool,
}

impl ZoneFrame {
    /// The frame of a zone of `length_m` whose road heads `road_heading_deg`
    /// at the camera, in either direction.
    #[must_use]
    pub fn new(length_m: u32, road_heading_deg: f64) -> Self {
        Self {
            length_m,
            north_east: road_heading_deg.rem_euclid(180.0) < 90.0,
        }
    }
}

/// The metres of a zone of `length_m` before and after its camera, in the
/// order its road is driven (heading `road_heading_deg` at the camera), for
/// the camera at `share` of the zone along the road's canonical direction:
/// the road driven the other way gives the same stretch.
#[must_use]
pub fn zone_sides(length_m: f64, share: f64, road_heading_deg: f64) -> (f64, f64) {
    let (canonical_before, canonical_after) = (share * length_m, (1.0 - share) * length_m);
    if road_heading_deg.rem_euclid(360.0) < 180.0 {
        (canonical_before, canonical_after)
    } else {
        (canonical_after, canonical_before)
    }
}

/// Where a zone starts before its camera, as a share of its length: from a
/// keyed hash of the camera's id, the zone's frame (its length and
/// direction, [`ZoneFrame`]) and the server's `secret`, between 15 % and
/// 85 %: the same at every build while the frame stays, another one when it
/// changes.
#[must_use]
pub fn zone_fraction(secret: &[u8], camera: &str, frame: ZoneFrame) -> f64 {
    let mut h = Sha256::new();
    h.update((secret.len() as u64).to_be_bytes());
    h.update(secret);
    // Shares of earlier builds, keyed otherwise, are never reused.
    h.update(b"zone-share-v2:");
    h.update(frame.length_m.to_be_bytes());
    h.update([u8::from(frame.north_east)]);
    h.update(camera.as_bytes());
    let digest = h.finalize();
    let mut first = [0u8; 8];
    first.copy_from_slice(&digest[..8]);
    #[allow(
        clippy::cast_precision_loss,
        reason = "a share of the hash's range, a few bits lost do not matter"
    )]
    let unit = u64::from_be_bytes(first) as f64 / u64::MAX as f64;
    0.15 + 0.7 * unit
}

/// Spacing of a zone's points, metres. A zone is drawn with a point every
/// so many metres along its road from its start, none of them a vertex of
/// the road: the engine cuts its route where the camera snaps, and
/// OpenStreetMap often maps the camera as a node of its road, so a road
/// vertex kept, or a gap where vertices were removed around the camera,
/// would mark its place. A chord of 50 m strays at most 18 m from the road
/// at a right-angled corner.
pub const ZONE_STEP_M: f64 = 50.0;

/// How far a camera may lie from the route a zone is cut from, metres: a
/// camera beside the road (OpenStreetMap maps some on the verge) still
/// projects onto it.
pub const ZONE_SNAP_M: f64 = 30.0;

/// The point `distance_m` metres from `p` heading `bearing_deg` (degrees
/// from north), on a local flat earth: within a metre at the few kilometres
/// of a zone.
#[must_use]
pub fn toward(p: Position, bearing_deg: f64, distance_m: f64) -> Option<Position> {
    // The sphere `Position::distance_m` measures on.
    const M_PER_DEG: f64 = crate::geo::EARTH_RADIUS_M * std::f64::consts::PI / 180.0;
    let b = bearing_deg.to_radians();
    let lat = p.lat() + distance_m * b.cos() / M_PER_DEG;
    let cos = p.lat().to_radians().cos().max(1e-6);
    let lon = p.lon() + distance_m * b.sin() / (M_PER_DEG * cos);
    Position::new(lat, lon).ok()
}

/// The zone of the cameras `cameras` (one, or a section's start and end in
/// driving order), cut out of `road` (an engine route through them, in
/// driving order): from `before_m` metres before the first camera's place
/// on the road to `after_m` after the last's, a point every
/// [`ZONE_STEP_M`] from its start and one at its end. `None` when a camera
/// is not on the road, they come in the wrong order, the road does not
/// reach the whole length on both sides (a zone cut short would put its
/// camera near an end), or the stretch drives some road twice
/// ([`doubles_back`]).
#[must_use]
pub fn zone_cut(
    road: &[Position],
    cameras: &[Position],
    before_m: f64,
    after_m: f64,
) -> Option<Vec<Position>> {
    let line = crate::routing::RouteLine::new(road.to_vec())?;
    let (first, last) = (cameras.first()?, cameras.last()?);
    let start = line.project(*first, ZONE_SNAP_M)?.along_m;
    let end = line
        .project_within(*last, ZONE_SNAP_M, start, f64::INFINITY)?
        .along_m;
    let (from, to) = (start - before_m, end + after_m);
    if from < 0.0 || to > line.length_m() || before_m <= 0.0 || after_m <= 0.0 {
        return None;
    }
    // The road itself between the ends, to tell a road driven twice.
    let mut stretch = vec![line.point_at(from)];
    stretch.extend(
        line.points()
            .iter()
            .zip(line.along())
            .filter(|(_, s)| **s > from && **s < to)
            .map(|(p, _)| *p),
    );
    stretch.push(line.point_at(to));
    if doubles_back(&stretch) {
        return None;
    }
    let mut out = Vec::new();
    let mut s = from;
    while s < to {
        out.push(line.point_at(s));
        s += ZONE_STEP_M;
    }
    out.push(line.point_at(to));
    out.dedup();
    (out.len() >= 2).then_some(out)
}

/// Whether `line` drives some road twice: a vertex within 2 m of one more
/// than 50 m before it along the line, as a route that turns around at a
/// dead end or a roundabout draws it.
#[must_use]
pub fn doubles_back(line: &[Position]) -> bool {
    let mut along = Vec::with_capacity(line.len());
    let mut total = 0.0;
    for (i, p) in line.iter().enumerate() {
        if i > 0 {
            total += line[i - 1].distance_m(*p);
        }
        along.push(total);
    }
    line.iter().enumerate().any(|(i, p)| {
        line[..i]
            .iter()
            .zip(&along[..i])
            .any(|(q, s)| along[i] - s > 50.0 && p.distance_m(*q) < 2.0)
    })
}

/// A camera the server knows, from one source.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Device {
    /// Its id in its source.
    pub external_id: String,
    /// What it controls.
    pub kind: DeviceKind,
    /// Where it stands.
    pub position: Position,
    /// The direction of travel it controls, degrees from north, when the
    /// source says.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bearing_deg: Option<f64>,
    /// The speed it enforces, km/h, when the source says.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit_kmh: Option<u16>,
    /// The road, as the source names it (`A1`, `RN57`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub road: Option<String>,
    /// For a section: its end, when the source gives it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub section_end: Option<Position>,
    /// For a section: its length, metres, when the source gives it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub section_length_m: Option<f64>,
}

/// Parses an OpenStreetMap `direction` (degrees, or a cardinal point
/// `N`, `NE`, `SSW`); none for `forward`, `both` and the rest.
#[must_use]
pub fn bearing_of(direction: &str) -> Option<f64> {
    let d = direction.trim();
    if let Ok(deg) = d.parse::<f64>() {
        return (deg.is_finite()).then_some(deg.rem_euclid(360.0));
    }
    const POINTS: [&str; 16] = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW",
        "NW", "NNW",
    ];
    POINTS
        .iter()
        .position(|p| p.eq_ignore_ascii_case(d))
        .map(|i| f64::from(u32::try_from(i).unwrap_or(0)) * 22.5)
}

/// The position of UTM coordinates north of the equator in `zone`, on the
/// GRS80 ellipsoid (ETRS89, within a metre of WGS84 in Europe); none when
/// they fall outside the globe. Catalonia's camera list is in zone 31.
#[must_use]
pub fn from_utm_north(zone: u8, easting: f64, northing: f64) -> Option<Position> {
    let k0: f64 = 0.9996;
    let a: f64 = 6_378_137.0;
    let f: f64 = 1.0 / 298.257_222_101;
    let e2 = f * (2.0 - f);
    let root = (1.0 - e2).sqrt();
    let e1 = (1.0 - root) / (1.0 + root);
    let x = easting - 500_000.0;
    let mu =
        northing / k0 / (a * (1.0 - e2 / 4.0 - 3.0 * e2.powi(2) / 64.0 - 5.0 * e2.powi(3) / 256.0));
    let p1 = mu
        + (3.0 * e1 / 2.0 - 27.0 * e1.powi(3) / 32.0) * (2.0 * mu).sin()
        + (21.0 * e1.powi(2) / 16.0 - 55.0 * e1.powi(4) / 32.0) * (4.0 * mu).sin()
        + (151.0 * e1.powi(3) / 96.0) * (6.0 * mu).sin()
        + (1097.0 * e1.powi(4) / 512.0) * (8.0 * mu).sin();
    let ep2 = e2 / (1.0 - e2);
    let c1 = ep2 * p1.cos().powi(2);
    let t1 = p1.tan().powi(2);
    let s2 = 1.0 - e2 * p1.sin().powi(2);
    let n1 = a / s2.sqrt();
    let r1 = a * (1.0 - e2) / s2.powf(1.5);
    let d = x / (n1 * k0);
    let lat = p1
        - (n1 * p1.tan() / r1)
            * (d.powi(2) / 2.0
                - (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1.powi(2) - 9.0 * ep2) * d.powi(4) / 24.0
                + (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1.powi(2)
                    - 252.0 * ep2
                    - 3.0 * c1.powi(2))
                    * d.powi(6)
                    / 720.0);
    let lon = (d - (1.0 + 2.0 * t1 + c1) * d.powi(3) / 6.0
        + (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1.powi(2) + 8.0 * ep2 + 24.0 * t1.powi(2))
            * d.powi(5)
            / 120.0)
        / p1.cos();
    let central = f64::from(zone) * 6.0 - 183.0;
    Position::new(lat.to_degrees(), central + lon.to_degrees()).ok()
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use super::*;

    #[test]
    fn the_table_holds_the_owner_s_decisions() {
        assert_eq!(rule_of("FR").mode, Mode::Zones);
        assert_eq!(rule_of("FR").zones, Some(FRENCH_ZONES));
        assert_eq!(rule_of("ch").mode, Mode::Off);
        assert_eq!(rule_of("DE").mode, Mode::OffWhileDriving);
        assert_eq!(rule_of("MA").mode, Mode::Off);
        assert_eq!(rule_of("ES").mode, Mode::Exact);
        for doubtful in ["PT", "IT", "IE", "NO", "FI"] {
            assert_eq!(rule_of(doubtful).mode, Mode::Zones, "{doubtful}");
        }
        assert_eq!(rule_of("TR").mode, Mode::Off, "a country not in the table");
        assert_eq!(rule_of("").mode, Mode::Off);
        let mut seen = std::collections::BTreeSet::new();
        for r in RULES {
            assert!(seen.insert(r.country), "{} twice", r.country);
            assert!(!r.sources.is_empty(), "{} has its source", r.country);
            assert_eq!(r.zones.is_some(), r.mode == Mode::Zones, "{}", r.country);
        }
    }

    #[test]
    fn only_france_lets_a_user_ask_for_the_cameras_positions() {
        let france = rule_of("fr");
        assert_eq!(france.opt_in, Some(Mode::Exact));
        assert_eq!(france.mode_for(false), Mode::Zones, "zones by default");
        assert_eq!(france.mode_for(true), Mode::Exact, "positions once asked");
        assert!(
            france.sources.contains("2026-10-09"),
            "the line names the decision behind its choice"
        );
        for r in RULES.iter().filter(|r| r.country != "FR") {
            assert_eq!(r.opt_in, None, "{}: no choice", r.country);
            assert_eq!(
                r.mode_for(true),
                r.mode,
                "{}: a choice changes nothing",
                r.country
            );
        }
        for r in RULES {
            if let Some(o) = r.opt_in {
                // The server builds two forms of a camera, the default and the
                // chosen one; a choice only ever turns zones into points, so a
                // client that made some of the choices near a camera and not
                // all of them gets its default form.
                assert_eq!((r.mode, o), (Mode::Zones, Mode::Exact), "{}", r.country);
            }
        }
        assert_eq!(rule_of("CH").mode_for(true), Mode::Off);
        assert_eq!(rule_of("TR").mode_for(true), Mode::Off, "not in the table");
    }

    #[test]
    fn the_mode_follows_the_country_a_point_is_in() {
        let p = |lat, lon| Position::new(lat, lon).unwrap();
        assert_eq!(mode_at(p(48.8566, 2.3522)), Mode::Zones, "Paris");
        assert_eq!(mode_at(p(46.948, 7.447)), Mode::Off, "Bern");
        assert_eq!(mode_at(p(52.52, 13.405)), Mode::OffWhileDriving, "Berlin");
        assert_eq!(mode_at(p(40.4168, -3.7038)), Mode::Exact, "Madrid");
        assert_eq!(mode_at(p(45.0, -20.0)), Mode::Off, "the Atlantic");
        assert!(Mode::Off.strictness() > Mode::Zones.strictness());
        // Near a border, every rule within a kilometre counts: Saint-Julien,
        // France, 500 m from Geneva; Kehl, Germany, by Strasbourg; a
        // Biarritz beach road, the sea beside it.
        assert_eq!(mode_near(p(46.1453, 6.0808)), Mode::Off, "by Switzerland");
        assert!(near_country(p(46.1453, 6.0808), "CH"));
        assert_eq!(mode_near(p(48.5705, 7.8055)), Mode::Zones, "by France");
        assert_eq!(mode_near(p(43.4832, -1.5586)), Mode::Zones, "the coast");
        assert_eq!(mode_near(p(40.4168, -3.7038)), Mode::Exact, "Madrid");
        assert_eq!(
            served_form([Mode::OffWhileDriving, Mode::Zones]),
            Mode::Zones,
            "never a point where France's zones meet Germany's rule"
        );
    }

    #[test]
    fn a_zone_s_length_follows_the_limit_and_its_camera_never_sits_at_an_end() {
        assert_eq!(zone_length_m(FRENCH_ZONES, Some(130)), 4_000);
        assert_eq!(zone_length_m(FRENCH_ZONES, Some(110)), 4_000);
        assert_eq!(zone_length_m(FRENCH_ZONES, Some(80)), 2_000);
        assert_eq!(zone_length_m(FRENCH_ZONES, Some(50)), 500);
        assert_eq!(zone_length_m(FRENCH_ZONES, None), 2_000);
        let rural = ZoneFrame::new(2_000, 45.0);
        let a = zone_fraction(b"secret", "fr/60004", rural);
        assert_eq!(a, zone_fraction(b"secret", "fr/60004", rural), "stable");
        assert_ne!(a, zone_fraction(b"other", "fr/60004", rural), "keyed");
        assert_eq!(
            a,
            zone_fraction(b"secret", "fr/60004", ZoneFrame::new(2_000, 225.0)),
            "the same frame for the road driven the other way"
        );
        let shares: Vec<f64> = (0..1_000)
            .map(|i| zone_fraction(b"secret", &format!("fr/{i}"), rural))
            .collect();
        assert!(shares.iter().all(|f| (0.15..=0.85).contains(f)));
        let mean = shares.iter().sum::<f64>() / 1_000.0;
        assert!(
            (0.45..0.55).contains(&mean),
            "spread over the range: {mean}"
        );
    }

    #[test]
    fn utm_reads_as_degrees() {
        // On the central meridian of zone 31, 42° N lies 4 649 776.22 m north.
        let p = from_utm_north(31, 500_000.0, 4_649_776.22).unwrap();
        assert!((p.lat() - 42.0).abs() < 1e-6 && (p.lon() - 3.0).abs() < 1e-9);
        // The first camera of Catalonia's list: the A-2 at PK 445,35, by
        // Fraga.
        let a2 = from_utm_north(31, 288_075.464_3, 4_601_625.063).unwrap();
        assert!((a2.lat() - 41.538_23).abs() < 1e-4, "{a2:?}");
        assert!((a2.lon() - 0.459_46).abs() < 1e-4, "{a2:?}");
    }

    #[test]
    fn two_versions_of_a_zone_do_not_solve_for_its_camera() {
        // A camera 2 000 m along a straight road; its zone drawn at 2 000 m
        // (no limit), then at 500 m (a limit of 50 mapped in between). With
        // one share for both, the starts give it: s = (start2 - start1) /
        // (2000 - 500), and the camera at start1 + 2000 s.
        let p = |lat, lon| Position::new(lat, lon).unwrap();
        let start = p(45.0, 1.0);
        let road: Vec<Position> = (0..=60)
            .map(|i| toward(start, 90.0, f64::from(i) * 100.0).unwrap())
            .collect();
        let camera = road[30];
        let along = |q: Position| q.distance_m(start);
        let mut misses = 0;
        for i in 0..200 {
            let key = format!("securite-routiere/{i}");
            let zone = |length: u32| {
                let s = zone_fraction(b"secret", &key, ZoneFrame::new(length, 45.0));
                let l = f64::from(length);
                zone_cut(&road, &[camera], s * l, (1.0 - s) * l).unwrap()
            };
            let (long, short) = (zone(2_000), zone(500));
            let (a, b) = (along(long[0]), along(short[0]));
            let s = (b - a) / 1_500.0;
            let guess = a + 2_000.0 * s;
            if (guess - along(camera)).abs() > 50.0 {
                misses += 1;
            }
        }
        // With one share for both lengths every guess lands on the camera;
        // with a share per length, within 50 m only when the two shares
        // differ by less than 0.075 (about one time in five).
        assert!(
            misses > 100,
            "the camera must not follow from two lengths: {misses} of 200 missed"
        );
    }

    #[test]
    fn a_road_driven_either_way_gives_the_same_zone() {
        // A road running north, a camera 3 000 m along it; a direction tag
        // edited from 10 to 170 degrees (an attack the reviews of
        // 2026-10-06 found) reverses the route, never the zone.
        let p = |lat, lon| Position::new(lat, lon).unwrap();
        let start = p(45.0, 1.0);
        let north: Vec<Position> = (0..=60)
            .map(|i| toward(start, 0.3, f64::from(i) * 100.0).unwrap())
            .collect();
        let camera = north[30];
        let zone = |road: &[Position]| {
            let heading = crate::routing::corridor::heading(road[29], road[31]);
            let frame = ZoneFrame::new(2_000, heading);
            let share = zone_fraction(b"secret", "fr/1", frame);
            let (before, after) = zone_sides(2_000.0, share, heading);
            zone_cut(road, &[camera], before, after).unwrap()
        };
        let northward = zone(&north);
        let mut south = north.clone();
        south.reverse();
        let southward = zone(&south);
        let (n0, n1) = (northward[0], northward[northward.len() - 1]);
        let (s0, s1) = (southward[0], southward[southward.len() - 1]);
        assert!(
            n0.distance_m(s1) < 0.5 && n1.distance_m(s0) < 0.5,
            "the same stretch either way: {n0:?} {n1:?} against {s1:?} {s0:?}"
        );
        assert_eq!(
            ZoneFrame::new(2_000, 359.5),
            ZoneFrame::new(2_000, 179.5),
            "a road and its reverse share a frame"
        );
        assert_ne!(
            ZoneFrame::new(2_000, 0.5),
            ZoneFrame::new(2_000, 359.5),
            "a heading wavering across due north takes another frame"
        );
    }

    #[test]
    fn a_zone_holds_its_camera_inside_drawn_at_even_steps() {
        let p = |lat, lon| Position::new(lat, lon).unwrap();
        // A road heading east, a vertex every 100 m, the camera on the
        // vertex at 2 000 m.
        let start = p(45.0, 1.0);
        let road: Vec<Position> = (0..=40)
            .map(|i| toward(start, 90.0, f64::from(i) * 100.0).unwrap())
            .collect();
        let camera = road[20];
        let zone = zone_cut(&road, &[camera], 600.0, 1_400.0).unwrap();
        let length: f64 = zone.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        assert!((length - 2_000.0).abs() < 2.0, "{length}");
        assert!((zone[0].distance_m(camera) - 600.0).abs() < 1.0);
        let steps: Vec<f64> = zone.windows(2).map(|w| w[0].distance_m(w[1])).collect();
        assert!(
            steps[..steps.len() - 1]
                .iter()
                .all(|d| (d - ZONE_STEP_M).abs() < 0.5),
            "every point a step from the last, none of them the road's: {steps:?}"
        );
        let line = crate::routing::RouteLine::new(zone).unwrap();
        assert!(
            line.project(camera, 1.0).is_some(),
            "the zone still runs past the camera"
        );
        assert_eq!(
            zone_cut(&road, &[camera], 2_500.0, 1_000.0),
            None,
            "the road does not reach far enough back"
        );
        assert_eq!(
            zone_cut(&road, &[p(45.01, 1.02)], 500.0, 500.0),
            None,
            "a camera away from the road"
        );
        let section = zone_cut(&road, &[road[10], road[25]], 500.0, 500.0).unwrap();
        let length: f64 = section.windows(2).map(|w| w[0].distance_m(w[1])).sum();
        assert!(
            (length - 2_500.0).abs() < 2.0,
            "a section's zone runs end to end: {length}"
        );
        assert_eq!(
            zone_cut(&road, &[road[25], road[10]], 500.0, 500.0),
            None,
            "a section's end before its start"
        );
        assert!(!doubles_back(&road));
        let mut there_and_back = road[..10].to_vec();
        there_and_back.extend(road[..9].iter().rev());
        assert!(doubles_back(&there_and_back), "a road driven out and back");
        let east = toward(start, 90.0, 1_000.0).unwrap();
        assert!((east.distance_m(start) - 1_000.0).abs() < 1.0);
    }

    #[test]
    fn the_choice_of_france_turns_its_zones_into_points_and_nothing_else() {
        let p = |lat, lon| Position::new(lat, lon).unwrap();
        let none = OptIns::default();
        let fr = OptIns::new(["fr", "FR"]);
        assert_eq!(fr.countries(), ["FR"]);
        assert!(
            OptIns::new(["ES", "CH", "IT", "XX", "france"]).is_empty(),
            "a country whose line offers no choice is ignored"
        );
        assert_eq!(
            mode_near(p(48.8566, 2.3522)),
            none.mode_near(p(48.8566, 2.3522))
        );
        let cases = [
            (
                "Paris",
                "FR",
                p(48.8566, 2.3522),
                Mode::Zones,
                Mode::Exact,
                true,
            ),
            // Within a kilometre of France: zones by default.
            (
                "Irun",
                "ES",
                p(43.3399, -1.7808),
                Mode::Zones,
                Mode::Exact,
                true,
            ),
            (
                "Madrid",
                "ES",
                p(40.4168, -3.7038),
                Mode::Exact,
                Mode::Exact,
                false,
            ),
            (
                "Berlin",
                "DE",
                p(52.52, 13.405),
                Mode::OffWhileDriving,
                Mode::OffWhileDriving,
                false,
            ),
            // A country that is off within a kilometre wins over any choice:
            // Saint-Julien by Geneva, Beausoleil by Monaco, the N22 by the
            // Pas de la Casa.
            (
                "Saint-Julien",
                "FR",
                p(46.1453, 6.0808),
                Mode::Off,
                Mode::Off,
                true,
            ),
            (
                "Beausoleil",
                "FR",
                p(43.7430, 7.4210),
                Mode::Off,
                Mode::Off,
                true,
            ),
            ("N22", "FR", p(42.5440, 1.7440), Mode::Off, Mode::Off, true),
            (
                "Ventimiglia",
                "IT",
                p(43.79, 7.608),
                Mode::Zones,
                Mode::Zones,
                false,
            ),
            ("Rabat", "MA", p(34.02, -6.84), Mode::Off, Mode::Off, false),
            ("Bern", "CH", p(46.948, 7.447), Mode::Off, Mode::Off, false),
        ];
        for (name, country, at, without, with, depends) in cases {
            assert_eq!(
                none.form_of(country, at),
                without,
                "{name} without the choice"
            );
            assert_eq!(fr.form_of(country, at), with, "{name} with France's choice");
            assert_eq!(
                choices_near(country, at) == fr,
                depends,
                "{name}: France's choice is near"
            );
        }
        assert_eq!(
            OptIns::new(["ES", "CH", "IT"]).form_of("FR", p(48.8566, 2.3522)),
            Mode::Zones,
            "choices France does not take change nothing"
        );
    }

    /// What the embedded boundaries read at enclaves and microstates, and
    /// the form a camera there takes without and with France's choice.
    #[test]
    fn enclaves_and_microstates_keep_their_country_s_rule() {
        let fr = OptIns::new(["FR"]);
        let cases = [
            (
                "Llívia, Spain inside France",
                42.4637,
                1.9814,
                "ES",
                Mode::Zones,
                Mode::Exact,
            ),
            (
                "Büsingen, Germany inside Switzerland",
                47.6969,
                8.6897,
                "DE",
                Mode::Off,
                Mode::Off,
            ),
            (
                "Campione d'Italia, inside Switzerland",
                45.9686,
                8.9711,
                "IT",
                Mode::Off,
                Mode::Off,
            ),
            ("Monaco", 43.7384, 7.4246, "MC", Mode::Off, Mode::Off),
            ("San Marino", 43.9424, 12.4578, "SM", Mode::Off, Mode::Off),
            ("Vatican", 41.9029, 12.4534, "VA", Mode::Off, Mode::Off),
            (
                "Andorra la Vella",
                42.5063,
                1.5218,
                "AD",
                Mode::Off,
                Mode::Off,
            ),
            // The town is split: the given point reads Belgian, 500 m north
            // Dutch; both allow points.
            (
                "Baarle-Hertog",
                51.4383,
                4.9294,
                "BE",
                Mode::Exact,
                Mode::Exact,
            ),
            (
                "Baarle-Nassau",
                51.4428,
                4.9294,
                "NL",
                Mode::Exact,
                Mode::Exact,
            ),
        ];
        for (name, lat, lon, country, without, with) in cases {
            let at = Position::new(lat, lon).unwrap();
            assert_eq!(crate::region::country_at(at), Some(country), "{name}");
            assert_eq!(OptIns::default().form_of(country, at), without, "{name}");
            assert_eq!(fr.form_of(country, at), with, "{name} with France's choice");
        }
    }

    #[test]
    fn a_direction_reads_as_degrees_or_a_cardinal_point() {
        assert_eq!(bearing_of("300"), Some(300.0));
        assert_eq!(bearing_of("-90"), Some(270.0));
        assert_eq!(bearing_of("SW"), Some(225.0));
        assert_eq!(bearing_of("nne"), Some(22.5));
        assert_eq!(bearing_of("forward"), None);
        assert_eq!(bearing_of("both"), None);
    }
}
