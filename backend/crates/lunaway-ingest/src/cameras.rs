//! Speed cameras from the open official lists (`docs/data-sources.md`,
//! "Speed cameras"): France's (Sécurité routière, reused under the CRPA with
//! its source and date), Poland's (GITD CANARD, CC0), Luxembourg's (Ponts et
//! Chaussées, CC0), Catalonia's (Servei Català de Trànsit, Generalitat
//! licence) and Norway's (NVDB, NLOD). Each list is fetched whole, cached,
//! and stores its devices with their source; a device the list no longer
//! gives is retired, unless the list lost more than half of them (a
//! truncated answer). Each list's cameras take the list's country; none
//! within a kilometre of Switzerland is stored.

use std::time::Duration;

use chrono::{DateTime, Utc};
use lunaway_db::{
    PgPool,
    enforcement::{self as db, NewDevice},
};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, DeviceKind, from_utm_north, near_country},
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

/// An official list of cameras.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CameraList {
    /// France, Sécurité routière.
    France,
    /// Poland, GITD CANARD.
    Poland,
    /// Luxembourg, Ponts et Chaussées.
    Luxembourg,
    /// Catalonia, Servei Català de Trànsit.
    Catalonia,
    /// Norway, NVDB (fixed cameras, type 162).
    Norway,
}

impl CameraList {
    /// Every list.
    pub const ALL: [Self; 5] = [
        Self::France,
        Self::Poland,
        Self::Luxembourg,
        Self::Catalonia,
        Self::Norway,
    ];

    /// The list a command line names: `france`, `poland`, `luxembourg`,
    /// `catalonia`, `norway`.
    #[must_use]
    pub fn named(name: &str) -> Option<Self> {
        match name.trim().to_ascii_lowercase().as_str() {
            "france" => Some(Self::France),
            "poland" => Some(Self::Poland),
            "luxembourg" => Some(Self::Luxembourg),
            "catalonia" => Some(Self::Catalonia),
            "norway" => Some(Self::Norway),
            _ => None,
        }
    }

    /// Its source in the database.
    #[must_use]
    pub const fn source(self) -> SourceId {
        match self {
            Self::France => SourceId::SECURITE_ROUTIERE,
            Self::Poland => SourceId::PL_CANARD,
            Self::Luxembourg => SourceId::LU_PCH_RADARS,
            Self::Catalonia => SourceId::CAT_SCT_RADARS,
            Self::Norway => SourceId::NO_NVDB_ATK,
        }
    }

    /// The country the list is the authority of: its cameras are that
    /// country's, wherever the simplified boundaries put a camera near a
    /// border, the overseas departments of France included.
    #[must_use]
    pub const fn country(self) -> &'static str {
        match self {
            Self::France => "FR",
            Self::Poland => "PL",
            Self::Luxembourg => "LU",
            Self::Catalonia => "ES",
            Self::Norway => "NO",
        }
    }

    /// Where it is read.
    #[must_use]
    pub const fn url(self) -> &'static str {
        match self {
            Self::France => "https://radars.securite-routiere.gouv.fr/radars/all",
            // The resource of 2025-12-29, the latest of its half-yearly
            // snapshots on 2026-10-06; dane.gov.pl redirects to the file on
            // its own host.
            Self::Poland => {
                "https://api.dane.gov.pl/resources/989898,dane-dotyczace-urzadzen-rejestrujacych-w-tym-ich-lokalizacji-stan-na-29122025-r/file"
            }
            Self::Luxembourg => "https://data.geoportail.lu/radar",
            Self::Catalonia => {
                "https://transit.gencat.cat/web/.content/documents/seguretat_viaria/radars.txt"
            }
            Self::Norway => {
                "https://nvdbapiles.atlas.vegvesen.no/vegobjekter/162?inkluder=egenskaper,geometri,lokasjon&srid=4326&antall=1000"
            }
        }
    }

    /// Its key in the cache.
    #[must_use]
    pub const fn cache_key(self) -> &'static str {
        match self {
            Self::France => "cameras/securite-routiere.json",
            Self::Poland => "cameras/pl-canard.csv",
            Self::Luxembourg => "cameras/lu-pch.geojson",
            Self::Catalonia => "cameras/cat-sct.txt",
            Self::Norway => "cameras/no-nvdb-162.json",
        }
    }

    /// Reads a body of this list.
    ///
    /// # Errors
    ///
    /// [`IngestError::Json`] when a JSON list does not read.
    pub fn parse(self, body: &[u8]) -> Result<Parsed, IngestError> {
        match self {
            Self::France => parse_france(body),
            Self::Poland => Ok(parse_poland(body)),
            Self::Luxembourg => parse_luxembourg(body),
            Self::Catalonia => Ok(parse_catalonia(body)),
            Self::Norway => parse_norway(body),
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

/// Whether `p` lies in Catalonia's bounding box: 17 rows of the list of
/// 2026-09-17 carry coordinates that are not a place there (decimal commas
/// lost, `462473824 462230358`, or a northing in the easting's column), some
/// of which would still read as a point elsewhere in the world.
fn in_catalonia(p: Position) -> bool {
    (40.45..=42.95).contains(&p.lat()) && (0.1..=3.4).contains(&p.lon())
}

/// Catalonia's list: text columns `Via PK Velocitat X Y`, the coordinates
/// in UTM zone 31 (ETRS89), the kilometre point with a decimal comma. The
/// road and its kilometre point make the id.
fn parse_catalonia(body: &[u8]) -> Parsed {
    let text = String::from_utf8_lossy(body);
    let mut out = Parsed::default();
    let mut started = false;
    for line in text.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if !started {
            started = cols.first() == Some(&"Via");
            continue;
        }
        if cols.is_empty() {
            continue;
        }
        out.rows += 1;
        // `Via PK Velocitat X Y`, where a few kilometre points read as two
        // words (`nord 85`, `1,8 -3,0`): the last three columns are fixed.
        let n = cols.len();
        let position = (n >= 5)
            .then(|| decimal(cols[n - 2]).zip(decimal(cols[n - 1])))
            .flatten()
            .and_then(|(x, y)| from_utm_north(31, x, y))
            .filter(|p| in_catalonia(*p));
        match position {
            Some(position) => {
                let pk = cols[1..n - 3].join(" ");
                // A range of kilometre points (`539,2-545,1`) is an average
                // speed section, from the first to the second.
                let section = pk
                    .as_bytes()
                    .windows(3)
                    .any(|w| w[0].is_ascii_digit() && w[1] == b'-' && w[2].is_ascii_digit());
                let kind = if section {
                    DeviceKind::Section
                } else {
                    DeviceKind::Fixed
                };
                let mut d = device(format!("{}@{pk}", cols[0]), kind, position);
                d.road = Some(cols[0].to_owned());
                d.limit_kmh = cols[n - 3].parse().ok();
                let raw = serde_json::json!({
                    "via": cols[0], "pk": pk, "velocitat": cols[n - 3],
                    "x": cols[n - 2], "y": cols[n - 1]
                });
                out.devices.push(Listed { device: d, raw });
            }
            None => out.skipped += 1,
        }
    }
    out
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

/// A list's body, and the date it gives of its last update
/// (`Last-Modified`), when it gives one.
type Fetched = (Vec<u8>, Option<DateTime<Utc>>);

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
            .and_then(|v| DateTime::parse_from_rfc2822(v).ok())
            .map(|t| t.with_timezone(&Utc));
        Ok((read_capped(url, response, MAX_BYTES).await?, updated))
    })
    .await
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

/// The list's body, from the network unless `refresh` is false and one is
/// cached; Norway's pages joined into one answer.
async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    list: CameraList,
    refresh: bool,
) -> Result<Read, IngestError> {
    if !refresh && let Some(c) = cache.read(list.cache_key()).await? {
        return Ok(Read {
            body: c.bytes,
            fetched_at: c.fetched_at,
            cached: true,
            list_updated_at: None,
        });
    }
    let (body, list_updated_at) = if list == CameraList::Norway {
        let mut objects = Vec::new();
        let mut url = Some(list.url().to_owned());
        for page_number in 0..=MAX_PAGES {
            let Some(u) = url.take() else { break };
            if page_number == MAX_PAGES {
                // More pages than any answer had: stop rather than store
                // a part of the list as the whole of it.
                return Err(IngestError::Implausible {
                    what: format!("the Norwegian camera list runs past {MAX_PAGES} pages"),
                });
            }
            let (page, _) = get(http, &u, true).await?;
            let v: serde_json::Value =
                serde_json::from_slice(&page).map_err(|source| IngestError::Json {
                    what: "Norwegian camera list".into(),
                    source,
                })?;
            objects.extend(v["objekter"].as_array().cloned().unwrap_or_default());
            url = next_page(&page);
            // NVDB allows 40 calls a second; one a second is plenty.
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        let joined =
            serde_json::to_vec(&serde_json::json!({ "objekter": objects })).map_err(|source| {
                IngestError::Json {
                    what: "Norwegian camera list".into(),
                    source,
                }
            })?;
        (joined, None)
    } else {
        get(http, list.url(), false).await?
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
    // A list that names a camera twice (Catalonia's B-10 at 18,5) keeps
    // the first: one statement cannot write a row twice.
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
}
