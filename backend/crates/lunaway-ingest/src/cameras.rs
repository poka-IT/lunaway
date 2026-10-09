//! Speed cameras from the open official lists (`docs/data-sources.md`,
//! "Speed cameras"): France's map (Sécurité routière, reused under the CRPA
//! with its source and date) and its yearly file on data.gouv.fr (the
//! Délégation à la sécurité routière, Licence Ouverte 2.0), Poland's (GITD
//! CANARD, CC0), Luxembourg's (Ponts et Chaussées, CC0), Brussels' (Bruxelles
//! Mobilité, CC0), Norway's (NVDB, NLOD) and Ireland's mobile camera zones
//! (An Garda Síochána, CC BY). Catalonia's list is suspended: its host's
//! robots.txt refuses every robot.
//!
//! Each list is checked every day and downloaded at its own pace
//! ([`CameraList::period`]), its cached copy read in between; it stores its
//! devices with their source, and a device the list no longer gives is
//! retired, unless the list lost more than half of them (a truncated
//! answer), or, for a list that changes little, more than a tenth
//! ([`CameraList::max_change`]: nothing is stored then). Each list's
//! cameras take the list's country; none within a kilometre of Switzerland
//! is stored.

use std::time::Duration;

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::{
    PgPool,
    enforcement::{self as db, NewDevice},
};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, DeviceKind, near_country},
    routing::RouteLine,
};

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
};

/// Largest answer of a list: France's weighed 2.1 MB on 2026-10-06.
const MAX_BYTES: usize = 16 * 1024 * 1024;
/// Pages of the Norwegian API read at most (1 000 objects a page; 461
/// cameras on 2026-10-06).
const MAX_PAGES: usize = 20;
/// A day's list is read again after this long: a run started again after a
/// failure the same day reads its cached copy.
const DAILY: Duration = Duration::from_secs(20 * 3600);
/// A week's list, less a few hours for the timer's drift.
const WEEKLY: Duration = Duration::from_secs(7 * 24 * 3600 - 4 * 3600);
/// A month's list, likewise.
const MONTHLY: Duration = Duration::from_secs(30 * 24 * 3600 - 4 * 3600);
/// Shortest line of a published zone kept, metres: a shorter piece of a
/// Garda zone is a joint between two roads, not a stretch to watch.
const MIN_ZONE_M: f64 = 100.0;

/// An official list of cameras.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CameraList {
    /// France, Sécurité routière's map, the authority on which cameras are
    /// in service.
    France,
    /// France, the Délégation à la sécurité routière's yearly file on
    /// data.gouv.fr: the type of each camera and its limit.
    FranceDsr,
    /// Poland, GITD CANARD, its latest snapshot.
    Poland,
    /// Luxembourg, Ponts et Chaussées.
    Luxembourg,
    /// Brussels, Bruxelles Mobilité: the regional and municipal cameras.
    Brussels,
    /// Norway, NVDB (fixed cameras, type 162).
    Norway,
    /// Ireland, An Garda Síochána: the zones of the mobile cameras.
    IrelandGarda,
}

impl CameraList {
    /// Every list.
    pub const ALL: [Self; 7] = [
        Self::France,
        Self::FranceDsr,
        Self::Poland,
        Self::Luxembourg,
        Self::Brussels,
        Self::Norway,
        Self::IrelandGarda,
    ];

    /// Its name on the command line.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::France => "france",
            Self::FranceDsr => "france-dsr",
            Self::Poland => "poland",
            Self::Luxembourg => "luxembourg",
            Self::Brussels => "brussels",
            Self::Norway => "norway",
            Self::IrelandGarda => "ireland",
        }
    }

    /// The list a command line names ([`Self::name`], any case).
    #[must_use]
    pub fn named(name: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|l| l.name().eq_ignore_ascii_case(name.trim()))
    }

    /// Its source in the database.
    #[must_use]
    pub const fn source(self) -> SourceId {
        match self {
            Self::France => SourceId::SECURITE_ROUTIERE,
            Self::FranceDsr => SourceId::FR_DSR,
            Self::Poland => SourceId::PL_CANARD,
            Self::Luxembourg => SourceId::LU_PCH_RADARS,
            Self::Brussels => SourceId::BE_BRU_RADARS,
            Self::Norway => SourceId::NO_NVDB_ATK,
            Self::IrelandGarda => SourceId::IE_GARDA,
        }
    }

    /// The country the list is the authority of: its cameras are that
    /// country's, wherever the simplified boundaries put a camera near a
    /// border, the overseas departments of France included.
    #[must_use]
    pub const fn country(self) -> &'static str {
        match self {
            Self::France | Self::FranceDsr => "FR",
            Self::Poland => "PL",
            Self::Luxembourg => "LU",
            Self::Brussels => "BE",
            Self::Norway => "NO",
            Self::IrelandGarda => "IE",
        }
    }

    /// How often the list is downloaded; in between, its cached copy is
    /// read. France's map daily (it says which cameras are in service);
    /// the yearly file of data.gouv.fr, Poland's half-yearly snapshots and
    /// Brussels' list weekly; the Garda's zones, updated a few times a
    /// year, monthly.
    #[must_use]
    pub const fn period(self) -> Duration {
        match self {
            Self::France | Self::Luxembourg | Self::Norway => DAILY,
            Self::FranceDsr | Self::Poland | Self::Brussels => WEEKLY,
            Self::IrelandGarda => MONTHLY,
        }
    }

    /// Largest share of the stored cameras a read may add or remove; past
    /// it, nothing is stored and the list fails. Only for the yearly
    /// French file, whose rows moved by 7 % from 2024 to 2025 (94 retired,
    /// 135 added): more is a file of another shape.
    #[must_use]
    pub const fn max_change(self) -> Option<f64> {
        match self {
            Self::FranceDsr => Some(0.1),
            _ => None,
        }
    }

    /// Where it is read (the first request of a list read in several).
    #[must_use]
    pub const fn url(self) -> &'static str {
        match self {
            Self::France => "https://radars.securite-routiere.gouv.fr/radars/all",
            // The dataset's record: each year's file is a new resource.
            Self::FranceDsr => "https://www.data.gouv.fr/api/1/datasets/6712583387af110196942793/",
            // The resources of dataset 4364, the latest first: each
            // half-yearly snapshot is a new resource.
            Self::Poland => {
                "https://api.dane.gov.pl/1.4/datasets/4364/resources?sort=-data_date&per_page=50"
            }
            Self::Luxembourg => "https://data.geoportail.lu/radar",
            Self::Brussels => {
                "https://data.mobility.brussels/geoserver/bm_security/wfs?service=wfs&version=1.1.0&request=GetFeature&typeName=bm_security:speedcameras&outputFormat=json&srsName=EPSG:4326"
            }
            Self::Norway => {
                "https://nvdbapiles.atlas.vegvesen.no/vegobjekter/162?inkluder=egenskaper,geometri,lokasjon&srid=4326&antall=1000"
            }
            Self::IrelandGarda => {
                "https://www.garda.ie/en/roads-policing/safety-cameras-save-lives/mobile-safety-camera-detection/current_zones.kmz"
            }
        }
    }

    /// Its key in the cache.
    #[must_use]
    pub const fn cache_key(self) -> &'static str {
        match self {
            Self::France => "cameras/securite-routiere.json",
            Self::FranceDsr => "cameras/fr-dsr.csv",
            Self::Poland => "cameras/pl-canard.csv",
            Self::Luxembourg => "cameras/lu-pch.geojson",
            Self::Brussels => "cameras/be-bru.json",
            Self::Norway => "cameras/no-nvdb-162.json",
            Self::IrelandGarda => "cameras/ie-garda.json",
        }
    }

    /// Reads a body of this list.
    ///
    /// # Errors
    ///
    /// [`IngestError::Json`] when a JSON list does not read;
    /// [`IngestError::Implausible`] when a list is not of its shape.
    pub fn parse(self, body: &[u8]) -> Result<Parsed, IngestError> {
        match self {
            Self::France => parse_france(body),
            Self::FranceDsr => parse_france_dsr(body),
            Self::Poland => Ok(parse_poland(body)),
            Self::Luxembourg => parse_luxembourg(body),
            Self::Brussels => parse_brussels(body),
            Self::Norway => parse_norway(body),
            Self::IrelandGarda => parse_garda(body),
        }
    }
}
/// A device and the source's row.
#[derive(Debug, Clone, PartialEq)]
pub struct Listed {
    /// What the list says, read.
    pub device: Device,
    /// The row as the list gave it.
    pub raw: serde_json::Value,
}

/// What a list gave.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Parsed {
    /// Rows read.
    pub rows: usize,
    /// The devices.
    pub devices: Vec<Listed>,
    /// Rows left out: no position, a mobile route, a kind not known.
    pub skipped: usize,
}

fn device(id: String, kind: DeviceKind, position: Position) -> Device {
    Device {
        external_id: id,
        kind,
        position,
        bearing_deg: None,
        limit_kmh: None,
        road: None,
        section_end: None,
        section_length_m: None,
        zone_line: None,
    }
}

/// France's list: a JSON array of `{id, type, lat, lng}`. The routes of the
/// radar cars (`itineraire`, a line of up to 106 km) are mobile and left
/// out.
fn parse_france(body: &[u8]) -> Result<Parsed, IngestError> {
    let rows: Vec<serde_json::Value> =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "French camera list".into(),
            source,
        })?;
    let mut out = Parsed {
        rows: rows.len(),
        ..Parsed::default()
    };
    for row in rows {
        let kind = match row["type"].as_str() {
            Some("fixes" | "discriminants" | "urbain") => Some(DeviceKind::Fixed),
            Some("feux") => Some(DeviceKind::RedLight),
            Some("niveaux") => Some(DeviceKind::LevelCrossing),
            Some("troncons") => Some(DeviceKind::Section),
            _ => None,
        };
        let id = row["id"]
            .as_str()
            .map(str::to_owned)
            .or_else(|| row["id"].as_i64().map(|n| n.to_string()));
        let position = row["lat"]
            .as_f64()
            .zip(row["lng"].as_f64())
            .and_then(|(lat, lon)| Position::new(lat, lon).ok());
        match (kind, id, position) {
            (Some(kind), Some(id), Some(position)) => out.devices.push(Listed {
                device: device(id, kind, position),
                raw: row,
            }),
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// A decimal with a comma or a point.
fn decimal(text: &str) -> Option<f64> {
    text.trim()
        .replace(',', ".")
        .parse()
        .ok()
        .filter(|v: &f64| v.is_finite())
}

/// Poland's list: a CSV in Windows-1250, `;`-separated, a header line. The
/// fields read are ASCII: the kind (`punktowe`, `odcinkowy …`, `czerwone
/// …`, `… kolejowe` at level crossings), the road, the location code, the
/// section's lengths and its start and end.
fn parse_poland(body: &[u8]) -> Parsed {
    let mut out = Parsed::default();
    for line in body.split(|b| *b == b'\n').skip(1) {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            continue;
        }
        out.rows += 1;
        let fields: Vec<String> = line
            .split(|b| *b == b';')
            .map(|f| {
                encoding_rs::WINDOWS_1250
                    .decode_without_bom_handling(f)
                    .0
                    .trim()
                    .to_owned()
            })
            .collect();
        let field = |i: usize| fields.get(i).map(String::as_str).unwrap_or_default();
        let kind_text = field(0);
        let kind = if kind_text.starts_with("punktowe") {
            Some(DeviceKind::Fixed)
        } else if kind_text.starts_with("odcinkowy") {
            Some(DeviceKind::Section)
        } else if kind_text.starts_with("czerwone") && kind_text.contains("kolejowe") {
            Some(DeviceKind::LevelCrossing)
        } else if kind_text.starts_with("czerwone") {
            Some(DeviceKind::RedLight)
        } else {
            None
        };
        let at = |lat: usize, lon: usize| {
            decimal(field(lat))
                .zip(decimal(field(lon)))
                .and_then(|(a, b)| Position::new(a, b).ok())
        };
        let id = field(10);
        match (kind, at(15, 16)) {
            (Some(kind), Some(position)) if !id.is_empty() => {
                let mut d = device(id.to_owned(), kind, position);
                d.road = Some(field(6).to_owned()).filter(|r| !r.is_empty());
                if kind == DeviceKind::Section {
                    d.section_end = at(17, 18);
                    d.section_length_m = decimal(field(13)).or_else(|| decimal(field(14)));
                }
                let raw =
                    serde_json::Value::Array(fields.iter().map(|f| f.clone().into()).collect());
                out.devices.push(Listed { device: d, raw });
            }
            _ => out.skipped += 1,
        }
    }
    out
}

/// Luxembourg's list: GeoJSON points (fixed cameras) and lines (sections),
/// `ID` and `TRANCON` (the road and place) in the properties.
fn parse_luxembourg(body: &[u8]) -> Result<Parsed, IngestError> {
    let v: serde_json::Value =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "Luxembourg camera list".into(),
            source,
        })?;
    let features = v["features"].as_array().cloned().unwrap_or_default();
    let mut out = Parsed {
        rows: features.len(),
        ..Parsed::default()
    };
    let at = |c: &serde_json::Value| {
        c[1].as_f64()
            .zip(c[0].as_f64())
            .and_then(|(lat, lon)| Position::new(lat, lon).ok())
    };
    for f in features {
        let id = f["properties"]["ID"]
            .as_str()
            .map(str::to_owned)
            .or_else(|| f["properties"]["ID"].as_i64().map(|n| n.to_string()));
        let geometry = &f["geometry"];
        let (kind, start, end) = match geometry["type"].as_str() {
            Some("Point") => (DeviceKind::Fixed, at(&geometry["coordinates"]), None),
            Some("LineString") => {
                let coords = geometry["coordinates"]
                    .as_array()
                    .cloned()
                    .unwrap_or_default();
                (
                    DeviceKind::Section,
                    coords.first().and_then(at),
                    coords.last().and_then(at),
                )
            }
            _ => (DeviceKind::Fixed, None, None),
        };
        match (id, start) {
            (Some(id), Some(position)) => {
                let mut d = device(id, kind, position);
                d.road = f["properties"]["TRANCON"].as_str().map(str::to_owned);
                d.section_end = end;
                out.devices.push(Listed { device: d, raw: f });
            }
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// One page of Norway's NVDB answer: objects of type 162 with their
/// properties and a point in EPSG:4326, latitude first.
fn parse_norway(body: &[u8]) -> Result<Parsed, IngestError> {
    let v: serde_json::Value =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "Norwegian camera list".into(),
            source,
        })?;
    let objects = v["objekter"].as_array().cloned().unwrap_or_default();
    let mut out = Parsed {
        rows: objects.len(),
        ..Parsed::default()
    };
    for o in objects {
        // `POINT(lat lon)`, or `POINT Z (lat lon height)` for most objects.
        let position = o["geometri"]["wkt"]
            .as_str()
            .and_then(|w| w.strip_prefix("POINT"))
            .map(|w| w.trim_start().trim_start_matches('Z').trim_start())
            .and_then(|w| w.strip_prefix('('))
            .and_then(|w| w.strip_suffix(')'))
            .and_then(|w| {
                let mut it = w.split_whitespace();
                Some((
                    it.next()?.parse::<f64>().ok()?,
                    it.next()?.parse::<f64>().ok()?,
                ))
            })
            .and_then(|(lat, lon)| Position::new(lat, lon).ok());
        match (o["id"].as_i64(), position) {
            (Some(id), Some(position)) => {
                let mut d = device(id.to_string(), DeviceKind::Fixed, position);
                d.road = o["egenskaper"].as_array().and_then(|props| {
                    props
                        .iter()
                        .find(|p| p["navn"] == "Navn")
                        .and_then(|p| p["verdi"].as_str())
                        .map(str::to_owned)
                });
                out.devices.push(Listed { device: d, raw: o });
            }
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// The next page's address in a Norwegian answer, when the page was full.
fn next_page(body: &[u8]) -> Option<String> {
    let v: serde_json::Value = serde_json::from_slice(body).ok()?;
    let returned = v["metadata"]["returnert"].as_u64()?;
    let size = v["metadata"]["sidestørrelse"].as_u64()?;
    (returned >= size && returned > 0)
        .then(|| v["metadata"]["neste"]["href"].as_str().map(str::to_owned))
        .flatten()
        .filter(|href| href.starts_with("https://nvdbapiles.atlas.vegvesen.no/"))
}

/// The column of `header` whose name begins with `prefix`, case and spaces
/// around it ignored: the yearly French file renamed and reordered its
/// columns from 2024 (`Date de mise-en-service`, the VMA last) to 2025
/// (`Date de mise en service`, `VMA ` before the coordinates).
fn column(header: &[String], prefix: &str) -> Option<usize> {
    header
        .iter()
        .position(|h| h.trim().to_lowercase().starts_with(prefix))
}

/// The yearly French file of data.gouv.fr: ISO-8859-1, `;`-separated, a
/// header line, then each camera's number (the map's own), its type, its
/// date of service, its limit (`VMA`) and its signed coordinates. A
/// discriminating camera's (`ETD`) VMA is the limit of heavy goods
/// vehicles, not the cars' (the map's cards of radars 12024 and 12017,
/// read on 2026-10-09: "Vitesse VL 110", "Vitesse PL 80", VMA 80): it is
/// not served as a limit.
fn parse_france_dsr(body: &[u8]) -> Result<Parsed, IngestError> {
    // ISO-8859-1 is read as windows-1252, its superset for every letter
    // the file holds.
    let text = encoding_rs::WINDOWS_1252
        .decode_without_bom_handling(body)
        .0;
    let mut lines = text.lines();
    let header: Vec<String> = lines
        .next()
        .unwrap_or_default()
        .split(';')
        .map(|h| h.trim().to_owned())
        .collect();
    let col = |prefix: &str| column(&header, prefix);
    let (Some(number), Some(kind), Some(lat), Some(lon)) =
        (col("num"), col("type"), col("latitude"), col("longitude"))
    else {
        return Err(IngestError::Implausible {
            what: "the French yearly camera file names no number, type or coordinates column"
                .into(),
        });
    };
    let vma = col("vma");
    let mut out = Parsed::default();
    for line in lines {
        if line.trim().is_empty() {
            continue;
        }
        out.rows += 1;
        let fields: Vec<&str> = line.split(';').map(str::trim).collect();
        let field = |i: usize| fields.get(i).copied().unwrap_or_default();
        let code = field(kind).to_ascii_uppercase();
        let device_kind = match code.as_str() {
            "ETF" | "ETT" | "ETD" | "ETU" => Some(DeviceKind::Fixed),
            "ETVM" => Some(DeviceKind::Section),
            "ETFR" => Some(DeviceKind::RedLight),
            "ETPN" => Some(DeviceKind::LevelCrossing),
            _ => None,
        };
        let position = decimal(field(lat))
            .zip(decimal(field(lon)))
            .and_then(|(a, b)| Position::new(a, b).ok());
        let id = field(number);
        match (device_kind, position) {
            (Some(k), Some(position)) if !id.is_empty() => {
                let mut d = device(id.to_owned(), k, position);
                if code != "ETD" {
                    d.limit_kmh = vma
                        .and_then(|i| field(i).parse::<u16>().ok())
                        .filter(|l| (5..=150).contains(l));
                }
                let raw = serde_json::Value::Object(
                    header
                        .iter()
                        .zip(&fields)
                        .map(|(h, v)| (h.clone(), (*v).into()))
                        .collect(),
                );
                out.devices.push(Listed { device: d, raw });
            }
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// Brussels' cameras: the regional ones (`speedcameras`) and the
/// municipal ones (`speedcameras_municipal`), GeoJSON points. A regional
/// camera's kind is read from the first letter of its key (`fr_key`, else
/// `radar_id`): `R` a red light, `S` speed; Bruxelles Mobilité publishes no
/// table of its `radar_type` codes, and this reading is an assumption
/// (`docs/data-sources.md`). A municipal camera, which carries no
/// attribute, is a fixed one.
fn parse_brussels(body: &[u8]) -> Result<Parsed, IngestError> {
    let v: serde_json::Value =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "Brussels camera list".into(),
            source,
        })?;
    let point = |f: &serde_json::Value| {
        let c = &f["geometry"]["coordinates"];
        c[1].as_f64()
            .zip(c[0].as_f64())
            .and_then(|(lat, lon)| Position::new(lat, lon).ok())
    };
    let mut out = Parsed::default();
    for f in v["speedcameras"]["features"]
        .as_array()
        .into_iter()
        .flatten()
    {
        out.rows += 1;
        let p = &f["properties"];
        let id = p["radar_id"]
            .as_str()
            .and_then(|r| r.split_whitespace().next())
            .map(str::to_owned);
        let key = p["fr_key"]
            .as_str()
            .filter(|k| !k.trim().is_empty())
            .or_else(|| p["radar_id"].as_str())
            .unwrap_or_default();
        let kind = if key.trim_start().starts_with(['R', 'r']) {
            DeviceKind::RedLight
        } else {
            DeviceKind::Fixed
        };
        match (id, point(f), p["active"].as_bool()) {
            (Some(id), Some(position), Some(true) | None) => {
                let mut d = device(id, kind, position);
                d.road = p["street_fr"]
                    .as_str()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_owned);
                out.devices.push(Listed {
                    device: d,
                    raw: f.clone(),
                });
            }
            _ => out.skipped += 1,
        }
    }
    for f in v["speedcameras_municipal"]["features"]
        .as_array()
        .into_iter()
        .flatten()
    {
        out.rows += 1;
        let gid = f["properties"]["gid"].as_i64();
        match (gid, point(f)) {
            (Some(gid), Some(position)) => out.devices.push(Listed {
                device: device(format!("municipal/{gid}"), DeviceKind::Fixed, position),
                raw: f.clone(),
            }),
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// The fields of a Garda zone's description, an HTML table of `<td>` name
/// and value pairs (`Zone_Num`, `Start_Lat`, `Length (KM)`...).
fn garda_fields(description: &str) -> serde_json::Map<String, serde_json::Value> {
    let cells: Vec<&str> = description
        .split("<td>")
        .skip(1)
        .filter_map(|c| c.split("</td>").next())
        .map(str::trim)
        .collect();
    let mut out = serde_json::Map::new();
    for pair in cells.windows(2) {
        let known = pair[0].starts_with("Zone_")
            || pair[0].starts_with("Start_")
            || pair[0].starts_with("End_")
            || pair[0].starts_with("Length")
            || matches!(pair[0], "Fatal" | "Serious" | "Minor" | "Total");
        if known && !out.contains_key(pair[0]) {
            out.insert(pair[0].to_owned(), pair[1].into());
        }
    }
    out
}

/// Steps of the search of the longest trail through a zone's pieces, at
/// most: the Garda's most branched zone has 19 pieces (a road through a
/// roundabout, 2026-10-09), searched in a few hundred steps.
const MAX_TRAIL_STEPS: usize = 100_000;

/// A piece of a zone's line between two of its joints.
struct Piece {
    ends: (usize, usize),
    points: Vec<Position>,
    length_m: f64,
}

/// The longest trail through `pieces` (the indices of `left`), each used
/// once, as (piece, driven forward) in order; the search stops after
/// [`MAX_TRAIL_STEPS`] with the longest found.
fn longest_trail(pieces: &[Piece], left: &[usize]) -> Vec<(usize, bool)> {
    struct Search<'a> {
        pieces: &'a [Piece],
        left: &'a [usize],
        used: Vec<bool>,
        trail: Vec<(usize, bool)>,
        best: (f64, Vec<(usize, bool)>),
        steps: usize,
    }
    fn walk(s: &mut Search<'_>, at: usize, length: f64) {
        s.steps += 1;
        if length > s.best.0 {
            s.best = (length, s.trail.clone());
        }
        if s.steps >= MAX_TRAIL_STEPS {
            return;
        }
        for &i in s.left {
            if s.used[i] {
                continue;
            }
            let (a, b) = s.pieces[i].ends;
            let next = if a == at {
                Some((b, true))
            } else if b == at {
                Some((a, false))
            } else {
                None
            };
            if let Some((to, forward)) = next {
                s.used[i] = true;
                s.trail.push((i, forward));
                walk(s, to, length + s.pieces[i].length_m);
                s.trail.pop();
                s.used[i] = false;
            }
        }
    }
    let mut s = Search {
        pieces,
        left,
        used: vec![false; pieces.len()],
        trail: Vec::new(),
        best: (0.0, Vec::new()),
        steps: 0,
    };
    let mut starts: Vec<usize> = left
        .iter()
        .flat_map(|i| [pieces[*i].ends.0, pieces[*i].ends.1])
        .collect();
    starts.sort_unstable();
    starts.dedup();
    for start in starts {
        walk(&mut s, start, 0.0);
    }
    s.best.1
}

/// The roads of a zone from its pieces: the longest trail through them
/// (pieces meet where their ends lie within a metre, each piece driven
/// once), then the longest through the pieces left, and so on. Most Garda
/// zones are one piece (1 409 of the 1 456 current ones, 2026-10-09); the
/// others draw a road through a junction or a roundabout in pieces.
fn chains(pieces: Vec<Vec<Position>>) -> Vec<Vec<Position>> {
    let mut joints: Vec<Position> = Vec::new();
    let mut joint = |p: Position| {
        joints
            .iter()
            .position(|q| q.distance_m(p) < 1.0)
            .unwrap_or_else(|| {
                joints.push(p);
                joints.len() - 1
            })
    };
    let pieces: Vec<Piece> = pieces
        .into_iter()
        .filter(|p| p.len() >= 2)
        .map(|points| {
            let ends = (joint(points[0]), joint(points[points.len() - 1]));
            let length_m = points.windows(2).map(|w| w[0].distance_m(w[1])).sum();
            Piece {
                ends,
                points,
                length_m,
            }
        })
        .collect();
    let mut left: Vec<usize> = (0..pieces.len()).collect();
    let mut out = Vec::new();
    while !left.is_empty() {
        let trail = longest_trail(&pieces, &left);
        if trail.is_empty() {
            break;
        }
        let mut line: Vec<Position> = Vec::new();
        for (i, forward) in &trail {
            let mut points = pieces[*i].points.clone();
            if !forward {
                points.reverse();
            }
            let skip = usize::from(!line.is_empty());
            line.extend(points.into_iter().skip(skip));
        }
        line.dedup_by(|a, b| a.distance_m(*b) < 0.1);
        left.retain(|i| !trail.iter().any(|(t, _)| t == i));
        out.push(line);
    }
    out
}
/// One Garda KML: a `Placemark` per zone, its number in `name` and in its
/// description's table, its road as one or more `LineString`s (longitude,
/// latitude, height). Each chain of the zone's pieces of 100 m or more
/// becomes a published zone, `file/number` (`#2`, `#3` after the longest).
fn garda_zones(kml: &str, file: &str, out: &mut Parsed) -> Result<(), IngestError> {
    let walked = crate::road_events::xml::walk(kml.as_bytes(), "Placemark", |node| {
        out.rows += 1;
        let fields = garda_fields(node.find("description").map_or("", |d| d.text.as_str()));
        let number = fields
            .get("Zone_Num")
            .or_else(|| fields.get("Zone_No"))
            .and_then(|v| v.as_str())
            .map(str::to_owned)
            .or_else(|| node.child("name").map(|n| n.text.clone()))
            .filter(|n| !n.is_empty());
        let pieces: Vec<Vec<Position>> = node
            .find_all("coordinates")
            .iter()
            .map(|c| {
                c.text
                    .split_whitespace()
                    .filter_map(|t| {
                        let mut it = t.split(',');
                        let lon = it.next()?.parse::<f64>().ok()?;
                        let lat = it.next()?.parse::<f64>().ok()?;
                        Position::new(lat, lon).ok()
                    })
                    .collect()
            })
            .collect();
        let mut kept: Vec<(Vec<Position>, f64)> = chains(pieces)
            .into_iter()
            .filter_map(|c| {
                let line = RouteLine::new(c.clone())?;
                let length = line.length_m();
                (length >= MIN_ZONE_M).then_some((c, length))
            })
            .collect();
        kept.sort_by(|a, b| b.1.total_cmp(&a.1));
        let Some(number) = number.filter(|_| !kept.is_empty()) else {
            out.skipped += 1;
            return true;
        };
        for (k, (line, length)) in kept.into_iter().enumerate() {
            let id = if k == 0 {
                format!("{file}/{number}")
            } else {
                format!("{file}/{number}#{}", k + 1)
            };
            let Some(middle) = RouteLine::new(line.clone()).map(|l| l.point_at(length / 2.0))
            else {
                continue;
            };
            let mut d = device(id, DeviceKind::MobileZone, middle);
            d.zone_line = Some(line);
            let raw = serde_json::json!({
                "file": file,
                "name": node.child("name").map(|n| n.text.clone()),
                "fields": fields.clone(),
            });
            out.devices.push(Listed { device: d, raw });
        }
        true
    });
    walked.map(|_| ()).map_err(|e| IngestError::Implausible {
        what: format!("a Garda zone file does not read: {e}"),
    })
}

/// Ireland's zones: the two KML documents the Garda publishes in KMZ
/// archives (`current_zones`, `new_zones`), kept as one JSON object of
/// their texts.
fn parse_garda(body: &[u8]) -> Result<Parsed, IngestError> {
    let v: serde_json::Value =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "Garda zones".into(),
            source,
        })?;
    let mut out = Parsed::default();
    for (key, file) in [("current_zones", "current"), ("new_zones", "new")] {
        let Some(kml) = v[key].as_str() else {
            return Err(IngestError::Implausible {
                what: format!("the Garda zones lack {key}"),
            });
        };
        garda_zones(kml, file, &mut out)?;
    }
    Ok(out)
}

/// A list's body, and the date it gives of its last update, when it gives
/// one.
type Fetched = (Vec<u8>, Option<DateTime<Utc>>);

/// A `Last-Modified` date; the Garda's lack their zone (`Mon, 12 Jan 2026
/// 03:20:04`), read as GMT as HTTP dates are.
fn http_date(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc2822(value)
        .or_else(|_| DateTime::parse_from_rfc2822(&format!("{value} GMT")))
        .ok()
        .map(|t| t.with_timezone(&Utc))
}

async fn get(http: &reqwest::Client, url: &str, norway: bool) -> Result<Fetched, IngestError> {
    let retry = RetryPolicy {
        min_delay: Duration::from_secs(10),
        max_delay: Duration::from_secs(60),
        max_retries: 2,
    };
    with_retry("camera list", retry, || async {
        let mut request = http.get(url);
        if norway {
            // NVDB asks every client to name itself.
            request = request.header("X-Client", crate::http::user_agent());
        }
        let response = request.send().await.map_err(|source| IngestError::Http {
            url: url.to_owned(),
            source,
        })?;
        let response = check_status(url, response).await?;
        let updated = response
            .headers()
            .get(reqwest::header::LAST_MODIFIED)
            .and_then(|v| v.to_str().ok())
            .and_then(http_date);
        Ok((read_capped(url, response, MAX_BYTES).await?, updated))
    })
    .await
}

/// A pause between two requests of one list.
async fn pause() {
    tokio::time::sleep(Duration::from_secs(1)).await;
}

fn json(body: &[u8], what: &str) -> Result<serde_json::Value, IngestError> {
    serde_json::from_slice(body).map_err(|source| IngestError::Json {
        what: what.to_owned(),
        source,
    })
}

/// Whether `url` is HTTPS on one of `hosts`: an address read in a source's
/// metadata reaches no other server.
fn on_hosts(url: &str, hosts: &[&str]) -> bool {
    reqwest::Url::parse(url).is_ok_and(|u| {
        u.scheme() == "https"
            && u.host_str()
                .is_some_and(|h| hosts.iter().any(|x| x.eq_ignore_ascii_case(h)))
    })
}

/// The latest CSV of the French yearly file's record: the main resources
/// in CSV, the one created last, with its address and the date of its last
/// change.
fn latest_dsr_csv(record: &serde_json::Value) -> Option<(String, Option<DateTime<Utc>>)> {
    record["resources"]
        .as_array()?
        .iter()
        .filter(|r| {
            r["format"]
                .as_str()
                .is_some_and(|f| f.eq_ignore_ascii_case("csv"))
                && r["type"].as_str() == Some("main")
        })
        .max_by_key(|r| r["created_at"].as_str().unwrap_or_default().to_owned())
        .and_then(|r| {
            let url = r["url"].as_str()?.to_owned();
            let changed = r["last_modified"]
                .as_str()
                .and_then(|t| DateTime::parse_from_rfc3339(t).ok())
                .map(|t| t.with_timezone(&Utc));
            Some((url, changed))
        })
}

/// The yearly French file: the record of its dataset, then its latest CSV.
/// data.gouv.fr's robots.txt holds `Disallow: /resources`: the download of
/// a file whose address the platform's API publishes for reuse, once a
/// week, is no crawl (`docs/data-sources.md`).
async fn fetch_france_dsr(http: &reqwest::Client) -> Result<Fetched, IngestError> {
    let (record, _) = get(http, CameraList::FranceDsr.url(), false).await?;
    let (url, changed) =
        latest_dsr_csv(&json(&record, "data.gouv.fr dataset")?).ok_or_else(|| {
            IngestError::Implausible {
                what: "the French yearly camera dataset lists no CSV".into(),
            }
        })?;
    if !on_hosts(
        &url,
        &[
            "static.data.gouv.fr",
            "object.files.data.gouv.fr",
            "www.data.gouv.fr",
        ],
    ) {
        return Err(IngestError::Implausible {
            what: "the French yearly camera file lies off data.gouv.fr".into(),
        });
    }
    pause().await;
    let (csv, _) = get(http, &url, false).await?;
    Ok((csv, changed))
}

/// Poland's snapshot named by `resources` (the dataset's resources, the
/// latest first): the first whose title names the cameras' locations, its
/// date and download address.
fn latest_canard(resources: &serde_json::Value) -> Option<(NaiveDate, String)> {
    resources["data"].as_array()?.iter().find_map(|r| {
        let a = &r["attributes"];
        a["title"]
            .as_str()?
            .starts_with("Dane dotyczące urządzeń rejestrujących w tym ich lokalizacji")
            .then_some(())?;
        let date = NaiveDate::parse_from_str(a["data_date"].as_str()?, "%Y-%m-%d").ok()?;
        Some((date, a["download_url"].as_str()?.to_owned()))
    })
}

/// Where the date of the Polish snapshot held in the cache is kept.
const CANARD_DATE_KEY: &str = "cameras/pl-canard.date";

/// Poland's latest snapshot, or `None` when the dataset's latest is older
/// than the one already read: an older snapshot replaces nothing.
async fn fetch_poland(
    http: &reqwest::Client,
    cache: &Cache,
) -> Result<Option<Fetched>, IngestError> {
    let (list, _) = get(http, CameraList::Poland.url(), false).await?;
    let (date, url) = latest_canard(&json(&list, "dane.gov.pl resources")?).ok_or_else(|| {
        IngestError::Implausible {
            what: "the Polish dataset lists no snapshot of the cameras".into(),
        }
    })?;
    if !on_hosts(&url, &["api.dane.gov.pl"]) {
        return Err(IngestError::Implausible {
            what: "the Polish snapshot lies off dane.gov.pl".into(),
        });
    }
    let held = cache.read(CANARD_DATE_KEY).await?.and_then(|c| {
        NaiveDate::parse_from_str(String::from_utf8_lossy(&c.bytes).trim(), "%Y-%m-%d").ok()
    });
    if held.is_some_and(|h| date < h) {
        tracing::warn!(%date, "the Polish dataset's latest snapshot is older than the one held");
        return Ok(None);
    }
    pause().await;
    let (csv, _) = get(http, &url, false).await?;
    cache
        .write(
            CANARD_DATE_KEY,
            date.format("%Y-%m-%d").to_string().as_bytes(),
        )
        .await?;
    Ok(Some((csv, date.and_hms_opt(0, 0, 0).map(|t| t.and_utc()))))
}

/// Brussels' municipal cameras, the second layer of its WFS.
const BRUSSELS_MUNICIPAL: &str = "https://data.mobility.brussels/geoserver/bm_security/wfs?service=wfs&version=1.1.0&request=GetFeature&typeName=bm_security:speedcameras_municipal&outputFormat=json&srsName=EPSG:4326";

async fn fetch_brussels(http: &reqwest::Client) -> Result<Fetched, IngestError> {
    let (regional, _) = get(http, CameraList::Brussels.url(), false).await?;
    pause().await;
    let (municipal, _) = get(http, BRUSSELS_MUNICIPAL, false).await?;
    let body = serde_json::json!({
        "speedcameras": json(&regional, "Brussels cameras")?,
        "speedcameras_municipal": json(&municipal, "Brussels municipal cameras")?,
    });
    let body = serde_json::to_vec(&body).map_err(|source| IngestError::Json {
        what: "Brussels cameras".into(),
        source,
    })?;
    Ok((body, None))
}

/// The Garda's new zones, the second of its KMZ archives.
const GARDA_NEW: &str = "https://www.garda.ie/en/roads-policing/safety-cameras-save-lives/mobile-safety-camera-detection/new_zones.kmz";

async fn fetch_garda(http: &reqwest::Client) -> Result<Fetched, IngestError> {
    let (current, current_date) = get(http, CameraList::IrelandGarda.url(), false).await?;
    pause().await;
    let (new, new_date) = get(http, GARDA_NEW, false).await?;
    let body = serde_json::json!({
        "current_zones": crate::kmz::kml_of(&current)?,
        "new_zones": crate::kmz::kml_of(&new)?,
    });
    let body = serde_json::to_vec(&body).map_err(|source| IngestError::Json {
        what: "Garda zones".into(),
        source,
    })?;
    Ok((body, current_date.max(new_date)))
}

async fn fetch_norway(http: &reqwest::Client) -> Result<Fetched, IngestError> {
    let mut objects = Vec::new();
    let mut url = Some(CameraList::Norway.url().to_owned());
    for page_number in 0..=MAX_PAGES {
        let Some(u) = url.take() else { break };
        if page_number == MAX_PAGES {
            // More pages than any answer had: stop rather than store a
            // part of the list as the whole of it.
            return Err(IngestError::Implausible {
                what: format!("the Norwegian camera list runs past {MAX_PAGES} pages"),
            });
        }
        let (page, _) = get(http, &u, true).await?;
        let v = json(&page, "Norwegian camera list")?;
        objects.extend(v["objekter"].as_array().cloned().unwrap_or_default());
        url = next_page(&page);
        // NVDB allows 40 calls a second; one a second is plenty.
        pause().await;
    }
    let joined =
        serde_json::to_vec(&serde_json::json!({ "objekter": objects })).map_err(|source| {
            IngestError::Json {
                what: "Norwegian camera list".into(),
                source,
            }
        })?;
    Ok((joined, None))
}

/// What a fetch of a list gave: its body, when it was read, whether from
/// the cache, and the date it gives of its last update (none from the
/// cache: the date of an earlier read stays recorded).
struct Read {
    body: Vec<u8>,
    fetched_at: DateTime<Utc>,
    cached: bool,
    list_updated_at: Option<DateTime<Utc>>,
}

/// The list's body: the cached one unless `refresh` and it is older than
/// the list's [`CameraList::period`]; else from the network, the parts of a
/// list read in several requests joined into one.
async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    list: CameraList,
    refresh: bool,
) -> Result<Read, IngestError> {
    let cached = cache.read(list.cache_key()).await?;
    let from_cache = |c: crate::cache::Cached| Read {
        body: c.bytes,
        fetched_at: c.fetched_at,
        cached: true,
        list_updated_at: None,
    };
    if let Some(c) = &cached {
        let age = Utc::now()
            .signed_duration_since(c.fetched_at)
            .to_std()
            .unwrap_or_default();
        if !refresh || age < list.period() {
            return Ok(from_cache(c.clone()));
        }
    }
    let fetched = match list {
        CameraList::France | CameraList::Luxembourg => Some(get(http, list.url(), false).await?),
        CameraList::FranceDsr => Some(fetch_france_dsr(http).await?),
        CameraList::Poland => fetch_poland(http, cache).await?,
        CameraList::Brussels => Some(fetch_brussels(http).await?),
        CameraList::Norway => Some(fetch_norway(http).await?),
        CameraList::IrelandGarda => Some(fetch_garda(http).await?),
    };
    let Some((body, list_updated_at)) = fetched else {
        // The source's latest is older than the copy held: it stays.
        return cached
            .map(from_cache)
            .ok_or_else(|| IngestError::Implausible {
                what: format!(
                    "{} offers an older list than the one read, and none is held",
                    list.name()
                ),
            });
    };
    let fetched_at = cache.write(list.cache_key(), &body).await?;
    Ok(Read {
        body,
        fetched_at,
        cached: false,
        list_updated_at,
    })
}
/// What an import of a list did.
#[derive(Debug, Clone, PartialEq)]
pub struct CameraReport {
    /// Whether the body came from the cache.
    pub cached: bool,
    /// When it was fetched.
    pub fetched_at: DateTime<Utc>,
    /// What the list held.
    pub rows: usize,
    /// Devices stored.
    pub devices: usize,
    /// Rows left out.
    pub skipped: usize,
    /// Devices near Switzerland, with an id too long, or listed twice, not
    /// stored.
    pub not_stored: usize,
    /// Devices written: new, changed, or seen again (their read date
    /// moves).
    pub written: u64,
    /// Devices the list no longer gives.
    pub retired: u64,
    /// Whether retiring was refused: the list lost more than half.
    pub retire_refused: bool,
}

/// Whether a device may be stored: an id the table takes (1 to 64
/// characters), a position on land, and nowhere within
/// [`lunaway_domain::enforcement::BORDER_MARGIN_M`] of Switzerland, whose
/// law covers a database of positions carried in a car; the simplified
/// boundaries could put a Swiss camera on the wrong side.
pub(crate) fn storable(d: &Device) -> bool {
    (1..=64).contains(&d.external_id.chars().count())
        && lunaway_domain::region::country_at(d.position).is_some()
        && !near_country(d.position, "CH")
}

/// A list left alone by the truncation guard when it holds fewer than
/// half of the devices stored, at 10 stored or more.
fn truncated(seen: usize, stored: i64) -> bool {
    let seen = i64::try_from(seen).unwrap_or(i64::MAX);
    stored >= 10 && seen.saturating_mul(2) < stored
}

/// Whether `seen` cameras differ from the `stored` ones by more than
/// `share` of them, at 10 stored or more.
fn changed_too_much(seen: usize, stored: i64, share: f64) -> bool {
    #[allow(
        clippy::cast_precision_loss,
        reason = "counts of a few thousand cameras"
    )]
    let (seen, stored_f) = (seen as f64, stored as f64);
    stored >= 10 && (seen - stored_f).abs() > share * stored_f
}

/// What storing a list did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stored {
    /// Devices stored.
    pub devices: usize,
    /// Devices left out: near Switzerland, at sea, an id too long, or
    /// listed twice.
    pub not_stored: usize,
    /// Devices written: new, changed, or seen again.
    pub written: u64,
    /// Devices the list no longer gives.
    pub retired: u64,
    /// Whether retiring was refused: the list lost more than half.
    pub retire_refused: bool,
}

/// Stores the devices of `parsed` for `list`, read at `fetched_at`, the
/// list last updated at `list_updated_at` by its own account.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails.
pub async fn store(
    pool: &PgPool,
    list: CameraList,
    parsed: &Parsed,
    fetched_at: DateTime<Utc>,
    list_updated_at: Option<DateTime<Utc>>,
) -> Result<Stored, IngestError> {
    let source = list.source();
    let country = list.country();
    // A list that names a camera twice keeps the first: one statement
    // cannot write a row twice.
    let mut ids = std::collections::HashSet::new();
    let placed: Vec<(&Listed, String)> = parsed
        .devices
        .iter()
        .filter(|l| storable(&l.device) && ids.insert(l.device.external_id.as_str()))
        .map(|l| {
            let scope = crate::osm_extract::scope_of(l.device.position, Some(country))
                .unwrap_or_else(|| country.to_owned());
            (l, scope)
        })
        .collect();
    let not_stored = parsed.devices.len() - placed.len();
    let rows: Vec<NewDevice<'_>> = placed
        .iter()
        .map(|(l, scope)| NewDevice {
            device: &l.device,
            country,
            scope,
            raw: &l.raw,
        })
        .collect();
    let stored_before = db::live_count(pool, &source).await?;
    if let Some(share) = list.max_change()
        && changed_too_much(placed.len(), stored_before, share)
    {
        return Err(IngestError::Implausible {
            what: format!(
                "{source} gives {} cameras where {stored_before} are stored, more than {:.0} % \
                 apart: nothing stored",
                placed.len(),
                share * 100.0
            ),
        });
    }
    let written = db::upsert_devices(pool, &source, &rows, fetched_at).await?;
    let seen: Vec<String> = placed
        .iter()
        .map(|(l, _)| l.device.external_id.clone())
        .collect();
    let refused = truncated(seen.len(), stored_before);
    let retired = if refused {
        tracing::warn!(
            source = %source,
            seen = seen.len(),
            stored = stored_before,
            "the list holds less than half of the stored cameras; none retired"
        );
        0
    } else {
        db::retire_missing(pool, &source, &seen, fetched_at).await?
    };
    let live = db::live_count(pool, &source).await?;
    db::record_read(pool, &source, fetched_at, live, list_updated_at).await?;
    Ok(Stored {
        devices: placed.len(),
        not_stored,
        written,
        retired,
        retire_refused: refused,
    })
}

/// Fetches `list` (from the cache unless `refresh`), reads it and stores
/// its devices.
///
/// # Errors
///
/// [`IngestError`] when the fetch, the parse or a write fails.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    list: CameraList,
    refresh: bool,
) -> Result<CameraReport, IngestError> {
    let read = fetch(http, cache, list, refresh).await?;
    let parsed = list.parse(&read.body)?;
    let s = store(pool, list, &parsed, read.fetched_at, read.list_updated_at).await?;
    tracing::info!(
        source = %list.source(),
        devices = s.devices,
        written = s.written,
        retired = s.retired,
        "cameras stored"
    );
    Ok(CameraReport {
        cached: read.cached,
        fetched_at: read.fetched_at,
        rows: parsed.rows,
        devices: s.devices,
        skipped: parsed.skipped,
        not_stored: s.not_stored,
        written: s.written,
        retired: s.retired,
        retire_refused: s.retire_refused,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_full_norwegian_page_names_the_next_on_its_host() {
        let full = r#"{"objekter":[],"metadata":{"returnert":50,"sidestørrelse":50,
            "neste":{"href":"https://nvdbapiles.atlas.vegvesen.no/vegobjekter/162?start=x"}}}"#;
        assert_eq!(
            next_page(full.as_bytes()).as_deref(),
            Some("https://nvdbapiles.atlas.vegvesen.no/vegobjekter/162?start=x")
        );
        let last = r#"{"objekter":[],"metadata":{"returnert":3,"sidestørrelse":50,
            "neste":{"href":"https://nvdbapiles.atlas.vegvesen.no/x"}}}"#;
        assert_eq!(next_page(last.as_bytes()), None);
        let elsewhere = r#"{"objekter":[],"metadata":{"returnert":50,"sidestørrelse":50,
            "neste":{"href":"https://example.org/x"}}}"#;
        assert_eq!(
            next_page(elsewhere.as_bytes()),
            None,
            "another host is never followed"
        );
        assert!(truncated(4, 10) && !truncated(5, 10) && !truncated(0, 9));
    }

    #[test]
    fn the_latest_yearly_file_and_snapshot_are_found_on_their_hosts() {
        let record: serde_json::Value =
            serde_json::from_slice(include_bytes!("../tests/fixtures/fr_dsr_dataset.json"))
                .unwrap();
        let (url, changed) = latest_dsr_csv(&record).unwrap();
        assert!(
            url.ends_with("liste-des-radars-fixes-en-france-12-2025.csv"),
            "the CSV created last, not the 2024 one nor the documentation: {url}"
        );
        assert_eq!(
            changed.unwrap().to_rfc3339(),
            "2025-12-30T13:42:47.222+00:00"
        );
        assert!(on_hosts(&url, &["static.data.gouv.fr"]));
        assert!(!on_hosts(
            "http://static.data.gouv.fr/x.csv",
            &["static.data.gouv.fr"]
        ));
        assert!(!on_hosts(
            "https://example.org/x.csv",
            &["static.data.gouv.fr"]
        ));
        let resources: serde_json::Value =
            serde_json::from_slice(include_bytes!("../tests/fixtures/pl_canard_resources.json"))
                .unwrap();
        let (date, url) = latest_canard(&resources).unwrap();
        assert_eq!(date.to_string(), "2025-12-29");
        assert!(
            url.starts_with("https://api.dane.gov.pl/resources/989898,"),
            "{url}"
        );
    }

    #[test]
    fn a_yearly_file_that_moves_by_more_than_a_tenth_is_refused() {
        assert!(!changed_too_much(3_309, 3_204, 0.1));
        assert!(changed_too_much(2_800, 3_204, 0.1));
        assert!(changed_too_much(3_600, 3_204, 0.1));
        assert!(!changed_too_much(2, 9, 0.1), "a list being filled");
    }

    #[test]
    fn a_garda_date_without_its_zone_reads_as_gmt() {
        assert_eq!(
            http_date("Mon, 12 Jan 2026 03:20:04").unwrap().to_rfc3339(),
            "2026-01-12T03:20:04+00:00"
        );
        assert!(http_date("Thu, 02 Jul 2026 17:09:40 GMT").is_some());
        assert!(http_date("yesterday").is_none());
        let fields = garda_fields(
            "<td>2346</td><td>Zone_Num</td><td>2346</td><td>Length (KM)</td><td>1.5</td>",
        );
        assert_eq!(fields["Zone_Num"], "2346");
        assert_eq!(fields["Length (KM)"], "1.5");
    }
}
