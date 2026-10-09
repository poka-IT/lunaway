//! The GraphQL types of the speed cameras (`Query.enforcement`): the rules
//! of each country, the danger zones and cameras each one allows, and the
//! lists they come from (`docs/speed-cameras.md`).

use async_graphql::{Enum, SimpleObject};
use chrono::{DateTime, Utc};
use lunaway_db::enforcement::{FeedItem, ItemKind, SourceRead};
use lunaway_domain::{
    enforcement::{CountryRule, Mode, RULES, RULES_REVIEWED, RULES_VERSION, ZoneLengths},
    routing::polyline,
};
use uuid::Uuid;

/// What a country allows an app to carry about speed cameras.
#[derive(Enum, Copy, Clone, Debug, PartialEq, Eq)]
#[graphql(name = "EnforcementMode")]
pub enum GqlMode {
    /// Nothing: no data served for the country, nothing shown, no alert.
    Off,
    /// Cameras may be shown on the map, but nothing while driving: no
    /// alert, no display in guidance.
    OffWhileDriving,
    /// Danger zones only, never a camera's point, on the map as in
    /// guidance.
    Zones,
    /// Cameras at their positions.
    Exact,
}

impl From<Mode> for GqlMode {
    fn from(m: Mode) -> Self {
        match m {
            Mode::Off => Self::Off,
            Mode::OffWhileDriving => Self::OffWhileDriving,
            Mode::Zones => Self::Zones,
            Mode::Exact => Self::Exact,
        }
    }
}

/// Lengths of a danger zone by road, metres.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct EnforcementZoneLengths {
    /// On a motorway.
    pub motorway_m: i32,
    /// Outside built-up areas.
    pub rural_m: i32,
    /// In a built-up area.
    pub urban_m: i32,
}

impl From<ZoneLengths> for EnforcementZoneLengths {
    fn from(z: ZoneLengths) -> Self {
        let m = |v: u32| i32::try_from(v).unwrap_or(i32::MAX);
        Self {
            motorway_m: m(z.motorway_m),
            rural_m: m(z.rural_m),
            urban_m: m(z.urban_m),
        }
    }
}

/// One country's rule.
#[derive(SimpleObject, Debug, Clone)]
pub struct EnforcementCountryRule {
    /// ISO 3166-1 alpha-2.
    pub country: String,
    /// What the app may carry there, by default.
    pub mode: GqlMode,
    /// The mode a user may choose in place of `mode` by an explicit setting
    /// of the app (`EXACT` in France: the cameras' positions where zones
    /// are the default); null where the country offers no choice. The
    /// server serves it only to a client that names the country in
    /// `Query.enforcement(exactIn)`.
    pub opt_in_mode: Option<GqlMode>,
    /// The zones' lengths, in a `ZONES` country.
    pub zone_lengths: Option<EnforcementZoneLengths>,
    /// The texts the rule rests on, and the decision behind its choice.
    pub sources: String,
}

impl From<&CountryRule> for EnforcementCountryRule {
    fn from(r: &CountryRule) -> Self {
        Self {
            country: r.country.to_owned(),
            mode: r.mode.into(),
            opt_in_mode: r.opt_in.map(Into::into),
            zone_lengths: r.zones.map(Into::into),
            sources: r.sources.to_owned(),
        }
    }
}

/// The table of rules, by country.
#[derive(SimpleObject, Debug, Clone)]
pub struct EnforcementRules {
    /// The table's version: it moves with every change of a line.
    pub version: i32,
    /// When the table was last checked against its sources (ISO date).
    pub reviewed_on: String,
    /// The rule of a country the table does not name, and where the
    /// country is not known (at sea, no position): `OFF`.
    pub default_mode: GqlMode,
    /// Each country named.
    pub countries: Vec<EnforcementCountryRule>,
}

impl EnforcementRules {
    /// The table the server applies.
    pub(crate) fn current() -> Self {
        Self {
            version: i32::try_from(RULES_VERSION).unwrap_or(i32::MAX),
            reviewed_on: RULES_REVIEWED.to_owned(),
            default_mode: GqlMode::Off,
            countries: RULES.iter().map(EnforcementCountryRule::from).collect(),
        }
    }
}

/// A danger zone or a camera.
#[derive(Enum, Copy, Clone, Debug, PartialEq, Eq)]
#[graphql(name = "EnforcementItemKind")]
pub enum GqlItemKind {
    /// A stretch of road without a point: the camera is somewhere inside,
    /// never at a known place.
    Zone,
    /// A camera at its position.
    Camera,
}

/// What a camera controls; a zone's is always `DANGER_ZONE`.
#[derive(Enum, Copy, Clone, Debug, PartialEq, Eq)]
#[graphql(name = "EnforcementCategory")]
pub enum GqlCategory {
    /// Speed, at a point.
    Fixed,
    /// A red light (a zone's category also for a level crossing, on
    /// servers before every zone became `DANGER_ZONE`).
    RedLight,
    /// An average speed section.
    SectionControl,
    /// A level crossing (cameras only).
    LevelCrossing,
    /// Every zone, whatever its camera controls: a zone never carries the
    /// kind of its camera.
    DangerZone,
}

impl GqlCategory {
    /// The category stored for an item.
    pub(crate) fn of(code: &str) -> Option<Self> {
        match code {
            "fixed" => Some(Self::Fixed),
            "red_light" => Some(Self::RedLight),
            "section" | "section_control" => Some(Self::SectionControl),
            "level_crossing" => Some(Self::LevelCrossing),
            lunaway_domain::enforcement::ZONE_CATEGORY => Some(Self::DangerZone),
            _ => None,
        }
    }
}

/// A zone or a camera, as the country it lies in allows.
#[derive(SimpleObject, Debug, Clone)]
pub struct EnforcementItem {
    /// A stable id, which does not lead back to a camera.
    pub id: Uuid,
    /// A zone or a camera.
    pub kind: GqlItemKind,
    /// What a camera controls; `DANGER_ZONE` for every zone.
    pub category: GqlCategory,
    /// ISO 3166-1 alpha-2 of the country whose rule it follows.
    pub country: String,
    /// A zone's road, polyline6: the alert holds while the vehicle drives
    /// along it, in either direction. For a camera of an average speed
    /// section, the road from its start to its end when it is known.
    pub line: Option<String>,
    /// A camera's latitude.
    pub lat: Option<f64>,
    /// A camera's longitude.
    pub lon: Option<f64>,
    /// A camera's direction of travel, degrees from north, when known.
    pub bearing_deg: Option<f64>,
    /// A camera's limit, km/h, when known.
    pub limit_kmh: Option<i32>,
    /// The lists it comes from (`EnforcementSource.id`).
    pub source_ids: Vec<String>,
    /// When it last changed.
    pub updated_at: DateTime<Utc>,
}

impl EnforcementItem {
    /// The item as served, `None` for a category the API does not know. A
    /// zone is served as `DANGER_ZONE`, whatever its row says.
    pub(crate) fn of(f: &FeedItem) -> Option<Self> {
        let (kind, category) = match f.kind {
            ItemKind::Zone => (GqlItemKind::Zone, GqlCategory::DangerZone),
            ItemKind::Camera => (GqlItemKind::Camera, GqlCategory::of(&f.category)?),
        };
        Some(Self {
            id: f.id,
            kind,
            category,
            country: f.country.clone(),
            line: f.line.as_deref().map(polyline::encode),
            lat: f.point.map(|p| p.lat()),
            lon: f.point.map(|p| p.lon()),
            bearing_deg: f.bearing_deg.map(|b| (b * 10.0).round() / 10.0),
            limit_kmh: f.limit_kmh.map(i32::from),
            source_ids: f.source_ids.clone(),
            updated_at: f.updated_at,
        })
    }
}

/// A list the items come from, its terms and its last read: the source
/// and its date are cited with the data (the CRPA asks it of the French
/// list).
#[derive(SimpleObject, Debug, Clone)]
pub struct EnforcementSource {
    /// Its id.
    pub id: String,
    /// Its name.
    pub name: String,
    /// Its licence.
    pub licence: String,
    /// The licence's text.
    pub licence_url: String,
    /// The text to credit it with.
    pub attribution: String,
    /// Its page.
    pub url: String,
    /// When the list was last read.
    pub fetched_at: DateTime<Utc>,
    /// When the list says it was last updated (its `Last-Modified`), to
    /// cite with it; null when it does not say, the read date standing for
    /// it.
    pub list_updated_at: Option<DateTime<Utc>>,
    /// Cameras it listed then (in every country, served or not).
    pub cameras: i32,
}

impl From<&SourceRead> for EnforcementSource {
    fn from(s: &SourceRead) -> Self {
        Self {
            id: s.source.id.as_str().to_owned(),
            name: s.source.name.clone(),
            licence: s.source.licence.clone(),
            licence_url: s.source.licence_url.clone(),
            attribution: s.source.attribution.clone(),
            url: s.source.url.clone(),
            fetched_at: s.fetched_at,
            list_updated_at: s.list_updated_at,
            cameras: s.devices,
        }
    }
}

/// The changes since a cursor.
#[derive(SimpleObject, Debug, Clone)]
pub struct EnforcementDelta {
    /// The cursor to send next time.
    pub cursor: String,
    /// Whether `upserts` is the whole set (no cursor, or one from another
    /// copy of the database): replace what is held.
    pub full: bool,
    /// When the answer was made.
    pub as_of: DateTime<Utc>,
    /// The rules of every country: the app applies the rule of the
    /// country it is in, the stricter at once at a border.
    pub rules: EnforcementRules,
    /// Items new or changed.
    pub upserts: Vec<EnforcementItem>,
    /// Ids of items gone, or no longer allowed where they lie: drop them.
    pub removals: Vec<Uuid>,
    /// The lists, their terms and their last read.
    pub sources: Vec<EnforcementSource>,
    /// How long to wait before asking again, seconds.
    pub poll_interval_seconds: i32,
    /// Whether more changes wait: ask again at once with `cursor`.
    pub has_more: bool,
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use lunaway_db::enforcement::Variant;
    use lunaway_domain::Position;

    use super::*;

    #[test]
    fn a_zone_is_served_without_its_camera_s_kind_whatever_its_row_says() {
        let zone = FeedItem {
            id: Uuid::nil(),
            revision: 1,
            deleted: false,
            variant: Variant::All,
            visible: true,
            kind: ItemKind::Zone,
            category: "red_light".to_owned(),
            country: "FR".to_owned(),
            line: Some(vec![
                Position::new(45.0, 1.0).unwrap(),
                Position::new(45.01, 1.0).unwrap(),
            ]),
            point: None,
            bearing_deg: None,
            limit_kmh: None,
            source_ids: Vec::new(),
            updated_at: Utc::now(),
        };
        let served = EnforcementItem::of(&zone).unwrap();
        assert_eq!(served.category, GqlCategory::DangerZone);
        let camera = FeedItem {
            kind: ItemKind::Camera,
            line: None,
            point: Some(Position::new(40.4, -3.7).unwrap()),
            country: "ES".to_owned(),
            ..zone
        };
        assert_eq!(
            EnforcementItem::of(&camera).unwrap().category,
            GqlCategory::RedLight,
            "a camera keeps its kind"
        );
    }
}
