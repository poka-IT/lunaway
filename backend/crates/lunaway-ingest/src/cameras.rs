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
    enforcement::{Device, DeviceKind, ZONE_STEP_M, near_country},
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
    /// Rows left out: no position, a mobile route, a kind not known; for a
    /// published zone, each of its roads longer than any zone, else the
    /// zone itself when it keeps no road.
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
    // the file holds; a byte order mark (a file saved as UTF-8) switches to
    // UTF-8 and is dropped, so it never hides the first column.
    let text = encoding_rs::WINDOWS_1252.decode(body).0;
    let mut reader = csv::ReaderBuilder::new()
        .delimiter(b';')
        .flexible(true)
        .trim(csv::Trim::All)
        .from_reader(text.as_bytes());
    let header: Vec<String> = reader
        .headers()
        .map_err(|source| IngestError::Csv {
            what: "French yearly camera file".into(),
            source,
        })?
        .iter()
        .map(str::to_owned)
        .collect();
    let col = |prefix: &str| {
        column(&header, prefix).ok_or_else(|| IngestError::MissingColumn {
            what: "French yearly camera file".into(),
            column: prefix.to_owned(),
        })
    };
    let (number, kind, lat, lon) = (
        col("num")?,
        col("type")?,
        col("latitude")?,
        col("longitude")?,
    );
    let vma = col("vma").ok();
    let mut out = Parsed::default();
    for record in reader.records() {
        let record = record.map_err(|source| IngestError::Csv {
            what: "French yearly camera file".into(),
            source,
        })?;
        if record.iter().all(str::is_empty) {
            continue;
        }
        out.rows += 1;
        let field = |i: usize| record.get(i).unwrap_or_default();
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
        let id = camera_number(field(number));
        match (device_kind, position) {
            (Some(k), Some(position)) if !id.is_empty() => {
                let mut d = device(id, k, position);
                if code != "ETD" {
                    d.limit_kmh = vma
                        .and_then(|i| field(i).parse::<u16>().ok())
                        .filter(|l| (5..=150).contains(l));
                }
                let raw = serde_json::Value::Object(
                    header
                        .iter()
                        .zip(record.iter())
                        .map(|(h, v)| (h.clone(), v.into()))
                        .collect(),
                );
                out.devices.push(Listed { device: d, raw });
            }
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// A camera's number as the map writes it: the file of 2024 pads numbers
/// with zeros (`00101`), the map and the file of 2025 do not (`101`).
fn camera_number(text: &str) -> String {
    let t = text.trim();
    if !t.is_empty() && t.bytes().all(|b| b.is_ascii_digit()) {
        let trimmed = t.trim_start_matches('0');
        if trimmed.is_empty() { "0" } else { trimmed }.to_owned()
    } else {
        t.to_owned()
    }
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

/// Steps of the search of the longest trails through a zone's pieces, at
/// most, for the whole zone: the Garda's most branched zone has 19 pieces
/// (a road through a roundabout, 2026-10-09), searched in a few hundred
/// steps.
const MAX_TRAIL_STEPS: usize = 100_000;
/// Most pieces of one zone: a zone of more is left out, which keeps the
/// search, its depth and the joining of the pieces' ends small whatever a
/// file holds.
const MAX_ZONE_PIECES: usize = 64;
/// Longest road of a published zone, metres: the Garda's longest was 26.9
/// km (2026-10-09); a longer line is no zone (a coordinate's sign lost
/// draws hundreds of kilometres) and is left out.
const MAX_ZONE_M: f64 = 60_000.0;

/// A piece of a zone's line between two of its joints.
struct Piece {
    ends: (usize, usize),
    points: Vec<Position>,
    length_m: f64,
}

/// The longest trail through `pieces` (the indices of `left`), each used
/// once, as (piece, driven forward) in order; the search stops once
/// `steps` reaches [`MAX_TRAIL_STEPS`], with the longest found.
fn longest_trail(pieces: &[Piece], left: &[usize], steps: &mut usize) -> Vec<(usize, bool)> {
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
        steps: *steps,
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
    *steps = s.steps;
    s.best.1
}

/// The roads of a zone from its pieces: the longest trail through them
/// (pieces meet where their ends lie within a metre, each piece driven
/// once), then the longest through the pieces left, and so on; with the
/// number of pieces left on no road once the search's budget is spent.
/// Most Garda zones are one piece (1 409 of the 1 456 current ones,
/// 2026-10-09); the others draw a road through a junction or a roundabout
/// in pieces.
fn chains(pieces: Vec<Vec<Position>>) -> (Vec<Vec<Position>>, usize) {
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
    let mut steps = 0;
    while !left.is_empty() {
        let trail = longest_trail(&pieces, &left, &mut steps);
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
    // Once the search's budget is spent, the pieces left are on no road.
    (out, left.len())
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
        let zone = number.as_deref().unwrap_or("?");
        if pieces.len() > MAX_ZONE_PIECES {
            tracing::warn!(
                file,
                zone,
                pieces = pieces.len(),
                "a Garda zone of too many pieces left out"
            );
            out.skipped += 1;
            return true;
        }
        let (roads, unplaced) = chains(pieces);
        if unplaced > 0 {
            tracing::warn!(
                file,
                zone,
                pieces = unplaced,
                "pieces of a Garda zone past the search's budget left out"
            );
        }
        let mut kept: Vec<(RouteLine, f64)> = Vec::new();
        let mut too_long = 0;
        for road in roads {
            let Some(points) = densified(&road) else {
                tracing::warn!(
                    file,
                    zone,
                    "a road of a Garda zone longer than any left out"
                );
                too_long += 1;
                continue;
            };
            if let Some(line) = RouteLine::new(points) {
                let length = line.length_m();
                if length >= MIN_ZONE_M {
                    kept.push((line, length));
                }
            }
        }
        kept.sort_by(|a, b| b.1.total_cmp(&a.1));
        // Each road too long counts once, the zone that keeps none too only
        // when no road of it was counted.
        out.skipped += too_long;
        let Some(number) = number.filter(|_| !kept.is_empty()) else {
            if too_long == 0 {
                out.skipped += 1;
            }
            return true;
        };
        for (k, (line, length)) in kept.into_iter().enumerate() {
            let id = if k == 0 {
                format!("{file}/{number}")
            } else {
                format!("{file}/{number}#{}", k + 1)
            };
            let mut d = device(id, DeviceKind::MobileZone, line.point_at(length / 2.0));
            d.zone_line = Some(line.points().to_vec());
            let raw = serde_json::json!({
                "file": file,
                "name": node.child("name").map(|n| n.text.clone()),
                "fields": fields.clone(),
            });
            out.devices.push(Listed { device: d, raw });
        }
        true
    });
    walked.map(|_| ()).map_err(|e| IngestError::RoadEvents {
        what: "Garda zones".into(),
        source: e.into(),
    })
}

/// `line` with a point every [`ZONE_STEP_M`] or less along it: the border
/// checks read every fourth point of a zone, built 50 m apart, and a
/// published line's own vertices may lie kilometres apart. `None` for a
/// line longer than [`MAX_ZONE_M`], which no zone is: it is left out
/// rather than drawn with points without end.
fn densified(line: &[Position]) -> Option<Vec<Position>> {
    let length: f64 = line.windows(2).map(|w| w[0].distance_m(w[1])).sum();
    if length > MAX_ZONE_M {
        return None;
    }
    let mut out: Vec<Position> = Vec::with_capacity(line.len());
    for w in line.windows(2) {
        let (a, b) = (w[0], w[1]);
        out.push(a);
        let d = a.distance_m(b);
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "at most MAX_ZONE_M / ZONE_STEP_M steps, the line being bounded above"
        )]
        let n = (d / ZONE_STEP_M).ceil() as usize;
        for i in 1..n {
            #[allow(clippy::cast_precision_loss, reason = "a step count")]
            let t = i as f64 / n as f64;
            if let Ok(p) = Position::new(
                a.lat() + (b.lat() - a.lat()) * t,
                a.lon() + (b.lon() - a.lon()) * t,
            ) {
                out.push(p);
            }
        }
    }
    out.extend(line.last());
    Some(out)
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

/// That `url` is HTTPS on one of `hosts`: an address read in a source's
/// metadata reaches no other server.
fn on_hosts(url: &str, hosts: &[&str]) -> Result<(), IngestError> {
    let ok = reqwest::Url::parse(url).is_ok_and(|u| {
        u.scheme() == "https"
            && u.host_str()
                .is_some_and(|h| hosts.iter().any(|x| x.eq_ignore_ascii_case(h)))
    });
    if ok {
        Ok(())
    } else {
        Err(IngestError::UntrustedUrl {
            url: url.to_owned(),
            reason: "not HTTPS on the source's own hosts",
        })
    }
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
            IngestError::NoResource {
                dataset: "data.gouv.fr 6712583387af110196942793".into(),
            }
        })?;
    on_hosts(
        &url,
        &[
            "static.data.gouv.fr",
            "object.files.data.gouv.fr",
            "www.data.gouv.fr",
        ],
    )?;
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
        IngestError::NoResource {
            dataset: "dane.gov.pl 4364".into(),
        }
    })?;
    on_hosts(&url, &["api.dane.gov.pl"])?;
    let held = cache.read(CANARD_DATE_KEY).await?.and_then(|c| {
        NaiveDate::parse_from_str(String::from_utf8_lossy(&c.bytes).trim(), "%Y-%m-%d").ok()
    });
    if !replaces(held, date) {
        tracing::warn!(%date, "the Polish dataset's latest snapshot is older than the one held");
        return Ok(None);
    }
    pause().await;
    let (csv, _) = get(http, &url, false).await?;
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

/// When a list is downloaded rather than read from its cached copy.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refresh {
    /// Only when no copy is held.
    Never,
    /// When the copy held is as old as the list's [`CameraList::period`]:
    /// the daily run.
    WhenDue,
    /// Every time: an operator who knows a list changed.
    Always,
}

/// Whether a list is downloaded: when no copy is held, or as `refresh`
/// says of the copy held since `cached_at`, the list's period being
/// `period`.
fn due(
    cached_at: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
    period: Duration,
    refresh: Refresh,
) -> bool {
    cached_at.is_none_or(|at| match refresh {
        Refresh::Never => false,
        Refresh::WhenDue => now.signed_duration_since(at).to_std().unwrap_or_default() >= period,
        Refresh::Always => true,
    })
}

/// Whether a snapshot dated `latest` replaces the one held, dated `held`:
/// an older one replaces nothing.
fn replaces(held: Option<NaiveDate>, latest: NaiveDate) -> bool {
    held.is_none_or(|h| latest >= h)
}

/// The list's body: the cached one unless the list is [`due`]; else from
/// the network, the parts of a list read in several requests joined into
/// one. A body read from the network is cached by [`import`] only once it
/// is stored, so a body that does not read is never kept for a period.
async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    list: CameraList,
    refresh: Refresh,
) -> Result<Read, IngestError> {
    let cached = cache.read(list.cache_key()).await?;
    let from_cache = |c: crate::cache::Cached| Read {
        body: c.bytes,
        fetched_at: c.fetched_at,
        cached: true,
        list_updated_at: None,
    };
    let cached_at = cached.as_ref().map(|c| c.fetched_at);
    if !due(cached_at, Utc::now(), list.period(), refresh)
        && let Some(c) = cached
    {
        return Ok(from_cache(c));
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
    Ok(Read {
        body,
        fetched_at: Utc::now(),
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

/// How the cameras a list gives differ from those stored.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Change {
    /// Ids the list gives that are not stored.
    added: usize,
    /// Ids stored that the list no longer gives.
    gone: usize,
    /// Ids stored.
    held: usize,
}

/// How the cameras `seen` differ from the `stored` ones.
fn change(
    seen: &std::collections::HashSet<&str>,
    stored: &std::collections::HashSet<String>,
) -> Change {
    Change {
        added: seen.iter().filter(|id| !stored.contains(**id)).count(),
        gone: stored
            .iter()
            .filter(|id| !seen.contains(id.as_str()))
            .count(),
        held: stored.len(),
    }
}

impl Change {
    /// Whether the ids added and gone together pass `share` of those
    /// stored, at 10 stored or more: a file whose numbers all changed while
    /// their count did not passes it as well.
    fn exceeds(self, share: f64) -> bool {
        #[allow(
            clippy::cast_precision_loss,
            reason = "counts of a few thousand cameras"
        )]
        let (churn, held) = ((self.added + self.gone) as f64, self.held as f64);
        self.held >= 10 && churn > share * held
    }
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
/// list last updated at `list_updated_at` by its own account; a list that
/// changes more than its [`CameraList::max_change`] stores nothing.
///
/// # Errors
///
/// [`IngestError::Db`] when a statement fails;
/// [`IngestError::Implausible`] when the list changes too much.
pub async fn store(
    pool: &PgPool,
    list: CameraList,
    parsed: &Parsed,
    fetched_at: DateTime<Utc>,
    list_updated_at: Option<DateTime<Utc>>,
) -> Result<Stored, IngestError> {
    store_guarded(
        pool,
        list,
        parsed,
        fetched_at,
        list_updated_at,
        ChangeGuard::Hold,
    )
    .await
}

/// Whether the guard on a list's change ([`CameraList::max_change`]) holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChangeGuard {
    /// A list that changes too much stores nothing.
    Hold,
    /// Lifted by an operator who knows why a yearly file moved by more than
    /// a tenth (a new shape read and checked, a wave of new cameras): the
    /// list is stored, and the change logged.
    Lift,
}

/// [`store`], its guard on the list's change as `guard` says.
///
/// # Errors
///
/// As [`store`].
pub async fn store_guarded(
    pool: &PgPool,
    list: CameraList,
    parsed: &Parsed,
    fetched_at: DateTime<Utc>,
    list_updated_at: Option<DateTime<Utc>>,
    guard: ChangeGuard,
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
    if let Some(share) = list.max_change() {
        let stored = db::live_ids(pool, &source).await?;
        let seen: std::collections::HashSet<&str> = placed
            .iter()
            .map(|(l, _)| l.device.external_id.as_str())
            .collect();
        let c = change(&seen, &stored);
        if c.exceeds(share) {
            if guard == ChangeGuard::Hold {
                return Err(IngestError::Implausible {
                    what: format!(
                        "{source} adds {} and removes {} of its {} stored cameras, more than \
                         {:.0} %: nothing stored",
                        c.added,
                        c.gone,
                        c.held,
                        share * 100.0
                    ),
                });
            }
            tracing::warn!(
                source = %source,
                added = c.added,
                gone = c.gone,
                stored = c.held,
                "the guard on the list's change lifted: stored"
            );
        }
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
    refresh: Refresh,
    guard: ChangeGuard,
) -> Result<CameraReport, IngestError> {
    let read = fetch(http, cache, list, refresh).await?;
    let parsed = list.parse(&read.body)?;
    let s = store_guarded(
        pool,
        list,
        &parsed,
        read.fetched_at,
        read.list_updated_at,
        guard,
    )
    .await?;
    if !read.cached {
        // The cameras are stored: a copy that cannot be kept is the next
        // read's matter, not this one's.
        let kept = cache.write(list.cache_key(), &read.body).await;
        let dated = match (list, read.list_updated_at) {
            (CameraList::Poland, Some(date)) => cache
                .write(
                    CANARD_DATE_KEY,
                    date.format("%Y-%m-%d").to_string().as_bytes(),
                )
                .await
                .map(|_| ()),
            _ => Ok(()),
        };
        if let Err(e) = kept.map(|_| ()).and(dated) {
            tracing::warn!(source = %list.source(), error = %e, "a list stored but not cached");
        }
    }
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
        assert!(on_hosts(&url, &["static.data.gouv.fr"]).is_ok());
        assert!(on_hosts("http://static.data.gouv.fr/x.csv", &["static.data.gouv.fr"]).is_err());
        assert!(on_hosts("https://example.org/x.csv", &["static.data.gouv.fr"]).is_err());
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
        fn set(v: &[String]) -> std::collections::HashSet<&str> {
            v.iter().map(String::as_str).collect()
        }
        let stored: std::collections::HashSet<String> = (0..100).map(|i| i.to_string()).collect();
        let ids = |r: std::ops::Range<i32>| -> Vec<String> { r.map(|i| i.to_string()).collect() };
        let year = ids(5..103);
        let c = change(&set(&year), &stored);
        assert_eq!((c.added, c.gone, c.held), (3, 5, 100));
        assert!(!c.exceeds(0.1), "5 gone and 3 added: 8 %");
        let renumbered = ids(1_000..1_100);
        assert!(
            change(&set(&renumbered), &stored).exceeds(0.1),
            "the same count, every number changed"
        );
        assert!(change(&set(&ids(0..80)), &stored).exceeds(0.1));
        let few: std::collections::HashSet<String> = (0..9).map(|i| i.to_string()).collect();
        assert!(
            !change(&set(&ids(50..52)), &few).exceeds(0.1),
            "a list being filled"
        );
    }

    #[test]
    fn a_list_is_downloaded_at_its_pace_and_an_older_snapshot_replaces_nothing() {
        let now = Utc::now();
        let week = WEEKLY;
        let days = |d: i64| Some(now - chrono::Duration::days(d));
        assert!(
            due(None, now, week, Refresh::Never),
            "nothing held: downloaded"
        );
        assert!(
            !due(days(1), now, week, Refresh::WhenDue),
            "a day old: the copy held"
        );
        assert!(
            due(days(8), now, week, Refresh::WhenDue),
            "a week old: downloaded"
        );
        assert!(
            !due(days(8), now, week, Refresh::Never),
            "without --refresh: the copy held"
        );
        assert!(!due(days(0), now, DAILY, Refresh::WhenDue));
        assert!(due(days(0), now, week, Refresh::Always), "--force");
        let date = |d: &str| NaiveDate::parse_from_str(d, "%Y-%m-%d").unwrap();
        assert!(replaces(None, date("2025-12-29")));
        assert!(replaces(Some(date("2025-06-30")), date("2025-12-29")));
        assert!(replaces(Some(date("2025-12-29")), date("2025-12-29")));
        assert!(!replaces(Some(date("2025-12-29")), date("2025-06-30")));
    }

    #[test]
    fn a_published_line_gets_a_point_every_50_m_and_a_line_of_no_zone_is_left_out() {
        let p = |lat: f64, lon: f64| Position::new(lat, lon).unwrap();
        let line = [p(53.0, -6.0), p(53.01, -6.0), p(53.01, -5.99)];
        let dense = densified(&line).unwrap();
        assert_eq!(
            (dense[0], dense[dense.len() - 1]),
            (line[0], line[2]),
            "both ends kept"
        );
        assert!(
            dense
                .windows(2)
                .all(|w| w[0].distance_m(w[1]) <= ZONE_STEP_M + 0.5),
            "no gap over 50 m"
        );
        assert!(
            densified(&[p(53.3, -6.4), p(53.3, 6.4)]).is_none(),
            "a sign lost: 850 km, no zone"
        );
    }

    #[test]
    fn a_zone_of_too_many_pieces_is_left_out() {
        let piece = |i: usize| {
            #[allow(clippy::cast_precision_loss, reason = "a few test pieces")]
            let lat = 53.0 + i as f64 * 0.01;
            format!(
                "<LineString><coordinates>-6.0,{lat},0 -6.0,{},0</coordinates></LineString>",
                lat + 0.005
            )
        };
        let zone = |n: usize| {
            format!(
                "<kml><Placemark><name>7</name><MultiGeometry>{}</MultiGeometry></Placemark></kml>",
                (0..n).map(piece).collect::<String>()
            )
        };
        let mut ok = Parsed::default();
        garda_zones(&zone(MAX_ZONE_PIECES), "current", &mut ok).unwrap();
        assert_eq!(
            ok.devices.len(),
            MAX_ZONE_PIECES,
            "one road per piece, none joined"
        );
        let mut refused = Parsed::default();
        garda_zones(&zone(MAX_ZONE_PIECES + 1), "current", &mut refused).unwrap();
        assert_eq!((refused.devices.len(), refused.skipped), (0, 1));
        // One road of the zone runs 850 km (a sign lost): it goes, counted,
        // and the other road stays.
        let mixed = "<kml><Placemark><name>8</name><MultiGeometry>\
            <LineString><coordinates>-6.0,53.0,0 -6.0,53.005,0</coordinates></LineString>\
            <LineString><coordinates>-6.4,53.3,0 6.4,53.3,0</coordinates></LineString>\
            </MultiGeometry></Placemark></kml>";
        let mut partly = Parsed::default();
        garda_zones(mixed, "current", &mut partly).unwrap();
        assert_eq!((partly.devices.len(), partly.skipped), (1, 1));
        let too_long = "<kml><Placemark><name>9</name><MultiGeometry>\
            <LineString><coordinates>-6.4,53.3,0 6.4,53.3,0</coordinates></LineString>\
            </MultiGeometry></Placemark></kml>";
        let mut none = Parsed::default();
        garda_zones(too_long, "current", &mut none).unwrap();
        assert_eq!(
            (none.devices.len(), none.skipped),
            (0, 1),
            "its one road counted, the zone not again"
        );
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
