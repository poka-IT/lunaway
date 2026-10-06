//! OpenStreetMap through the Overpass API (ODbL 1.0).
//!
//! France is read one administrative region at a time: thirteen queries of a
//! few megabytes each, which a public Overpass instance answers without
//! special arrangement, paced by a pause between regions. Each answer is
//! cached (`data/osm/`), so a re-run reads the disk.
//!
//! # Tag mapping
//!
//! | OSM | Lunaway |
//! |---|---|
//! | `tourism=camp_site` | `campsite`, overnight `allowed` |
//! | `tourism=caravan_site` | `motorhome_area`, overnight `allowed`; `campsite` when the site says it is one (below) |
//! | `amenity=sanitary_dump_station`, alone | `service_area`; next to a site, its services go to the site |
//! | `amenity=parking` + `motorhome=designated` | `parking`, overnight `tolerated` |
//! | `amenity=parking` + `motorhome=yes`, or `caravan=yes\|designated` | `parking`, overnight `unknown` |
//! | `highway=rest_area`, `highway=services` | `rest_area`, overnight `unknown` |
//!
//! A car park or rest area tagged `motorhome=no` is left out, and so is one
//! tagged `access=no|private` unless `motorhome` or `caravan` lets them in
//! (the specific key overrides the general one). The overnight status is unknown unless a tag says it
//! ([`overnight_of`]): `motorhome:overnight` or `overnight` (`yes` allowed,
//! `no` day only), a `maxstay` shorter than a night (`2 hours`,
//! `load-unload`) day only. These win over the kind's default, so a motorhome
//! area tagged `motorhome:overnight=no` is a day stop.
//!
//! A campsite or motorhome area that is a pitch of another site is not a
//! place: `camp_site=pitch`, or a node (or a way under 30 m across) inside
//! the bounding box of a larger site with no name, a pitch number for a
//! name (`S33`, `Z109`, `12`) or the larger site's name. It is folded into that
//! site like a dump station, its tags kept in the site's raw payload
//! (`plan/research/08c-backend-fixes.md` found 185 such records making 503
//! review pairs). `tourism=camp_pitch` is never read.
//!
//! A `caravan_site` is a campsite when `caravan_site` says `campsite` or
//! `camp_site`, or when it has `stars`, takes tents (`tents=yes`), or has both
//! showers and toilets: motorhome stopovers in France do not offer showers,
//! campsites do. `caravan_site=motorhome_stopover` always stays a motorhome
//! area.
//!
//! Services: `drinking_water`/`water_point` (drinking water),
//! `sanitary_dump_station` (grey and black water: French dump stations take
//! both and the tag does not tell them apart), `power_supply` (electricity),
//! `toilets`, `shower`/`showers`, `internet_access=wlan|wifi|yes` (Wi-Fi),
//! `dog=yes|leashed|unleashed` (pets allowed). Any value but `no` counts for
//! the others.
//!
//! Other fields: `fee=no` is a price of 0; `charge` gives the price when it
//! reads `<amount> EUR|€` per night or per day; `maxheight` in metres or feet
//! and inches; `maxlength`, `maxwidth` and `maxweight` (or
//! `maxweightrating`) read as the routing reads them, implausible values
//! dropped; capacity from `capacity:motorhome`, `capacity:caravans`, then
//! (sites only, a car park's `capacity` counts cars) `capacity:pitches` and
//! `capacity`; `opening_hours`; `website`/`contact:website`/`url`;
//! `phone`/`contact:phone`/`contact:mobile`; `addr:*`; `description:fr` or
//! `description`; `stars`; `wikidata`; `wikipedia`. Every description is
//! also kept by language: `description:<lang>` under its BCP 47 tag,
//! `description` as undetermined (`und`).

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use lunaway_domain::{
    InvalidPosition, NormalizedRecord, OvernightStatus, PlaceKind, Position, Service,
    UNDETERMINED_LANGUAGE,
    conflation::normalize::fold,
    is_language_tag,
    routing::{
        RestrictionKind,
        tags::{
            self as routing_tags, PLAUSIBLE_LENGTH_M, PLAUSIBLE_VEHICLE_LENGTH_M,
            PLAUSIBLE_WEIGHT_T,
        },
    },
};
use serde::Deserialize;

use crate::{
    FetchedRecord, IngestError,
    cache::{Cache, short_hash},
    http::{RetryPolicy, check_status, read_capped, with_retry},
    web,
};

/// A French administrative region, by its ISO 3166-2 code, the key Overpass
/// finds its boundary with.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Region {
    /// ISO 3166-2 code (`FR-BRE`).
    pub code: &'static str,
    /// Name, for the logs.
    pub name: &'static str,
}

/// The thirteen regions of metropolitan France. Overseas regions are left
/// out of the MVP: the app's first maps cover the mainland and Corsica.
pub const REGIONS: &[Region] = &[
    Region {
        code: "FR-ARA",
        name: "Auvergne-Rhône-Alpes",
    },
    Region {
        code: "FR-BFC",
        name: "Bourgogne-Franche-Comté",
    },
    Region {
        code: "FR-BRE",
        name: "Bretagne",
    },
    Region {
        code: "FR-CVL",
        name: "Centre-Val de Loire",
    },
    Region {
        code: "FR-20R",
        name: "Corse",
    },
    Region {
        code: "FR-GES",
        name: "Grand Est",
    },
    Region {
        code: "FR-HDF",
        name: "Hauts-de-France",
    },
    Region {
        code: "FR-IDF",
        name: "Île-de-France",
    },
    Region {
        code: "FR-NOR",
        name: "Normandie",
    },
    Region {
        code: "FR-NAQ",
        name: "Nouvelle-Aquitaine",
    },
    Region {
        code: "FR-OCC",
        name: "Occitanie",
    },
    Region {
        code: "FR-PDL",
        name: "Pays de la Loire",
    },
    Region {
        code: "FR-PAC",
        name: "Provence-Alpes-Côte d'Azur",
    },
];

/// The region with this ISO code, case-insensitive.
#[must_use]
pub fn region(code: &str) -> Option<Region> {
    REGIONS
        .iter()
        .copied()
        .find(|r| r.code.eq_ignore_ascii_case(code))
}

/// The selectors of everything the MVP reads from OSM, inside the set `.r`.
const SELECTORS: &str = r#"  nwr["tourism"="caravan_site"](area.r);
  nwr["tourism"="camp_site"](area.r);
  nwr["amenity"="sanitary_dump_station"](area.r);
  nwr["amenity"="parking"]["motorhome"~"^(yes|designated)$"](area.r);
  nwr["amenity"="parking"]["caravan"~"^(yes|designated)$"](area.r);
  nwr["highway"~"^(rest_area|services)$"](area.r);"#;

/// The Overpass QL query for one region. `out tags bb` returns the
/// coordinates of nodes and the bounding box of ways and relations, from
/// which the adapter takes the centre and the size.
#[must_use]
pub fn region_query(region: Region) -> String {
    format!(
        "[out:json][timeout:900][maxsize:1073741824];\n\
         area[\"ISO3166-2\"=\"{}\"][\"admin_level\"=\"4\"][\"boundary\"=\"administrative\"]->.r;\n\
         (\n{SELECTORS}\n);\nout tags bb qt;\n",
        region.code
    )
}

/// Largest Overpass answer accepted. A region answers a few megabytes; the
/// whole of France with tags and bounds stays under 100 MB.
const ANSWER_MAX_BYTES: usize = 256 * 1024 * 1024;

/// Where and how to ask Overpass.
#[derive(Debug, Clone)]
pub struct OverpassConfig {
    /// Interpreter endpoints, tried in turn: each retry goes to the next
    /// one, so an overloaded instance does not stall the import while
    /// another one has free slots. Every one must keep an area index (the
    /// region queries select by boundary).
    pub urls: Vec<String>,
    /// Pause after a query that reached the network, so one run never holds
    /// more than one slot of a public instance.
    pub pace: std::time::Duration,
    /// Retries on load shedding.
    pub retry: RetryPolicy,
}

impl OverpassConfig {
    /// The main public instance, whose usage policy is quoted in
    /// `docs/data-sources.md`. Another instance is used only when the
    /// operator names it (`--overpass-url`), after reading its terms.
    pub const DEFAULT_URLS: &'static [&'static str] = &["https://overpass-api.de/api/interpreter"];
}

/// An Overpass answer, read from the network or the cache.
#[derive(Debug, Clone)]
pub struct RegionPayload {
    /// The JSON as received.
    pub body: Vec<u8>,
    /// When it was fetched.
    pub fetched_at: DateTime<Utc>,
    /// Whether it came from the cache.
    pub cached: bool,
}

/// The answer for `region`: from the cache unless `refresh`, otherwise from
/// Overpass (stored in the cache once it parsed as a complete answer).
///
/// # Errors
///
/// [`IngestError`] when Overpass keeps failing, answers with an error, or the
/// cache cannot be read or written.
pub async fn fetch_region(
    http: &reqwest::Client,
    cache: &Cache,
    config: &OverpassConfig,
    region: Region,
    refresh: bool,
) -> Result<RegionPayload, IngestError> {
    let query = region_query(region);
    let key = format!("osm/{}-{}.json", region.code, short_hash(query.as_bytes()));
    if !refresh && let Some(c) = cache.read(&key).await? {
        tracing::info!(
            region = region.code,
            key,
            "overpass answer read from the cache"
        );
        return Ok(RegionPayload {
            body: c.bytes,
            fetched_at: c.fetched_at,
            cached: true,
        });
    }
    if config.urls.is_empty() {
        return Err(IngestError::NoEndpoint);
    }
    let attempt = std::sync::atomic::AtomicUsize::new(0);
    let body = with_retry("overpass", config.retry, || async {
        let n = attempt.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let url = &config.urls[n % config.urls.len()];
        tracing::info!(region = region.code, %url, attempt = n + 1, "querying overpass");
        let response = http
            .post(url)
            .form(&[("data", query.as_str())])
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: url.clone(),
                source,
            })?;
        let response = check_status(url, response).await?;
        let body = read_capped(url, response, ANSWER_MAX_BYTES).await?;
        // A complete answer is the only one worth caching: a timeout remark
        // means elements are missing, and retiring the records of the
        // missing elements would delete real places. Parsing up to 256 MB
        // of JSON is CPU work, kept off the async thread.
        tokio::task::spawn_blocking(move || parse_response(&body).map(|_| body))
            .await
            .map_err(IngestError::Blocking)?
    })
    .await?;
    let fetched_at = cache.write(&key, &body).await?;
    Ok(RegionPayload {
        body,
        fetched_at,
        cached: false,
    })
}

/// The bounding box of a way or relation, as Overpass writes it.
#[derive(Debug, Clone, Copy, PartialEq, Deserialize, serde::Serialize)]
pub(crate) struct Bounds {
    pub(crate) minlat: f64,
    pub(crate) minlon: f64,
    pub(crate) maxlat: f64,
    pub(crate) maxlon: f64,
}

/// An OSM element as the mapping reads it, whatever the transport.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct Element {
    #[serde(rename = "type")]
    pub(crate) kind: String,
    pub(crate) id: i64,
    pub(crate) lat: Option<f64>,
    pub(crate) lon: Option<f64>,
    pub(crate) bounds: Option<Bounds>,
    #[serde(default)]
    pub(crate) tags: BTreeMap<String, String>,
}

/// The elements of an Overpass answer, each typed and with its raw JSON.
/// The JSON tree is read once and its elements moved out of it, so a large
/// answer is held twice at most (bytes and tree), not four times.
pub(crate) fn parse_response(
    body: &[u8],
) -> Result<Vec<(Element, serde_json::Value)>, IngestError> {
    let json_err = |source| IngestError::Json {
        what: "overpass answer".into(),
        source,
    };
    let mut values: serde_json::Value = serde_json::from_slice(body).map_err(json_err)?;
    if let Some(remark) = values.get("remark").and_then(serde_json::Value::as_str)
        && remark.contains("error")
    {
        return Err(IngestError::OverpassIncomplete {
            remark: remark.to_owned(),
        });
    }
    let serde_json::Value::Array(raw) = values
        .get_mut("elements")
        .map(serde_json::Value::take)
        .unwrap_or_default()
    else {
        return Err(json_err(serde::de::Error::custom(
            "`elements` is not an array",
        )));
    };
    raw.into_iter()
        .map(|v| Ok((Element::deserialize(&v).map_err(json_err)?, v)))
        .collect()
}

/// Why an element was not turned into a record.
#[derive(Debug, Clone, Copy, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum Skip {
    /// Its tags describe nothing the MVP reads.
    #[error("not a kind the MVP reads")]
    OutOfScope,
    /// Neither coordinates nor a bounding box.
    #[error("no coordinates")]
    NoCoordinates,
    /// Coordinates outside the WGS 84 range.
    #[error("invalid coordinates")]
    InvalidCoordinates(#[from] InvalidPosition),
    /// Outside the area the import covers (an extract's overseas parts).
    #[error("outside the imported area")]
    OutsideArea,
}

/// What a parse produced.
#[derive(Debug, Default)]
pub struct Parsed {
    /// One record per element kept.
    pub records: Vec<FetchedRecord>,
    /// Elements dropped, with the reason.
    pub skipped: Vec<(String, Skip)>,
    /// Dump stations folded into the site they stand in.
    pub attached_dump_stations: usize,
    /// Pitches folded into the site they belong to.
    pub folded_pitches: usize,
}

struct Mapped {
    id: String,
    record: NormalizedRecord,
    /// The site's footprint, to find the dump stations inside it.
    bounds: Option<Bounds>,
    raw: serde_json::Value,
}

/// Maps an Overpass answer onto normalised records.
///
/// # Errors
///
/// [`IngestError`] when the body is not an Overpass JSON answer or reports a
/// runtime error.
pub fn parse(body: &[u8], fetched_at: DateTime<Utc>) -> Result<Parsed, IngestError> {
    Ok(build(parse_response(body)?, fetched_at))
}

/// Maps elements (with their raw JSON) onto records, folding each dump
/// station into the site it stands in.
pub(crate) fn build(
    elements: impl IntoIterator<Item = (Element, serde_json::Value)>,
    fetched_at: DateTime<Utc>,
) -> Parsed {
    let mut out = Parsed::default();
    let mut sites: Vec<Mapped> = Vec::new();
    let mut stations: Vec<Mapped> = Vec::new();
    for (element, raw) in elements {
        let id = format!("{}/{}", element.kind, element.id);
        match map_element(&element) {
            Ok((record, bounds)) => {
                let m = Mapped {
                    id,
                    record,
                    bounds,
                    raw,
                };
                if m.record.kind == PlaceKind::ServiceArea {
                    stations.push(m);
                } else {
                    sites.push(m);
                }
            }
            Err(reason) => out.skipped.push((id, reason)),
        }
    }

    let (mut sites, folded) = fold_pitches(sites);
    out.folded_pitches = folded;

    for station in stations {
        match host_site(&sites, &station) {
            Some(i) => {
                let host = &mut sites[i];
                host.record
                    .services
                    .extend(station.record.services.iter().copied());
                attach_raw(&mut host.raw, station.raw);
                out.attached_dump_stations += 1;
            }
            None => sites.push(station),
        }
    }

    out.records = sites
        .into_iter()
        .map(|m| FetchedRecord {
            external_url: Some(format!("https://www.openstreetmap.org/{}", m.id)),
            external_id: m.id,
            record: m.record,
            raw: m.raw,
            fetched_at,
        })
        .collect();
    out
}

/// Largest half-diagonal, in metres, of a way that may be a pitch: a
/// pitch is a few metres across, a small site some tens.
const PITCH_MAX_M: f64 = 15.0;

/// Whether a name reads as a pitch number: up to three letters, an
/// optional space or hyphen, one to four digits, an optional letter
/// (`S33`, `Z109`, `A-12`, `12b`).
fn is_pitch_code(name: &str) -> bool {
    let n = name.trim();
    let letters = n.chars().take_while(char::is_ascii_alphabetic).count();
    if letters > 3 {
        return false;
    }
    let rest = n[letters..].trim_start_matches([' ', '-']);
    let digits = rest.chars().take_while(char::is_ascii_digit).count();
    let tail = &rest[digits..];
    (1..=4).contains(&digits)
        && (tail.is_empty() || (tail.len() == 1 && tail.chars().all(|c| c.is_ascii_alphabetic())))
}

/// Whether `m` looks like a pitch of a site named `host_name`: no name, a
/// pitch number, or the site's own name.
fn pitch_like(m: &Mapped, host_name: Option<&str>) -> bool {
    match m.record.name.as_deref() {
        None => true,
        Some(name) => is_pitch_code(name) || host_name.is_some_and(|h| fold(h) == fold(name)),
    }
}

/// The larger site whose footprint holds the small site `i`, if `i` reads as
/// one of its pitches.
fn pitch_host(sites: &[Mapped], i: usize) -> Option<usize> {
    let pitch = &sites[i];
    let small = pitch.bounds.is_none() || pitch.record.accuracy_m <= PITCH_MAX_M;
    let site_kind = |k: PlaceKind| matches!(k, PlaceKind::Campsite | PlaceKind::MotorhomeArea);
    if !small || !site_kind(pitch.record.kind) {
        return None;
    }
    let p = pitch.record.position;
    sites
        .iter()
        .enumerate()
        .filter(|(j, s)| {
            *j != i
                && site_kind(s.record.kind)
                && s.record.accuracy_m > pitch.record.accuracy_m.max(PITCH_MAX_M)
                && s.bounds.is_some_and(|b| within_bounds(b, p, 0.0))
                && pitch_like(pitch, s.record.name.as_deref())
        })
        // The smallest footprint that holds it: a pitch of a site inside a
        // larger holiday park belongs to the site.
        .min_by(|(_, a), (_, b)| {
            a.record
                .accuracy_m
                .total_cmp(&b.record.accuracy_m)
                .then(a.id.cmp(&b.id))
        })
        .map(|(j, _)| j)
}

/// Folds every pitch into its site: its services join the site's, its raw
/// payload goes under the site's `_attached`. Returns the sites left and
/// how many pitches were folded.
fn fold_pitches(sites: Vec<Mapped>) -> (Vec<Mapped>, usize) {
    let hosts: Vec<Option<usize>> = (0..sites.len()).map(|i| pitch_host(&sites, i)).collect();
    // A pitch's host is never itself a pitch: a host is larger than
    // `PITCH_MAX_M`, a pitch smaller.
    let mut slots: Vec<Option<Mapped>> = sites.into_iter().map(Some).collect();
    let mut folded = 0;
    for (i, host) in hosts.iter().enumerate() {
        let Some(h) = *host else { continue };
        let Some(pitch) = slots[i].take() else {
            continue;
        };
        if let Some(site) = slots[h].as_mut() {
            site.record
                .services
                .extend(pitch.record.services.iter().copied());
            attach_raw(&mut site.raw, pitch.raw);
            folded += 1;
        }
    }
    (slots.into_iter().flatten().collect(), folded)
}

fn attach_raw(host: &mut serde_json::Value, raw: serde_json::Value) {
    if let Some(obj) = host.as_object_mut() {
        let attached = obj
            .entry("_attached")
            .or_insert_with(|| serde_json::Value::Array(Vec::new()));
        if let Some(list) = attached.as_array_mut() {
            list.push(raw);
        }
    }
}

/// Metres around a site's footprint within which a dump station still
/// belongs to it: the borne often stands at the entrance, just outside the
/// mapped outline.
const ATTACH_MARGIN_M: f64 = 30.0;
/// Distance from a site mapped as a point within which a dump station
/// belongs to it.
const ATTACH_POINT_M: f64 = 50.0;

/// The site a dump station belongs to: the nearest one whose footprint (plus
/// a margin) holds it, or whose point is close enough.
fn host_site(sites: &[Mapped], station: &Mapped) -> Option<usize> {
    let p = station.record.position;
    // A site whose point is more than 0.05 degrees away (over 3.5 km) cannot
    // hold the station; the comparison is cheap, the distance is not, and a
    // whole country has tens of millions of pairs.
    let near = |s: &Mapped| {
        (s.record.position.lat() - p.lat()).abs() < 0.05
            && (s.record.position.lon() - p.lon()).abs() < 0.05
    };
    sites
        .iter()
        .enumerate()
        .filter(|(_, s)| near(s))
        .filter(|(_, s)| {
            let d = s.record.position.distance_m(p);
            match s.bounds {
                Some(b) => within_bounds(b, p, ATTACH_MARGIN_M),
                None => d <= ATTACH_POINT_M,
            }
        })
        .min_by(|(_, a), (_, b)| {
            a.record
                .position
                .distance_m(p)
                .total_cmp(&b.record.position.distance_m(p))
                .then(a.id.cmp(&b.id))
        })
        .map(|(i, _)| i)
}

fn within_bounds(b: Bounds, p: Position, margin_m: f64) -> bool {
    let dlat = margin_m / 111_195.0;
    let dlon = margin_m / (111_195.0 * p.lat().to_radians().cos().max(0.01));
    (b.minlat - dlat..=b.maxlat + dlat).contains(&p.lat())
        && (b.minlon - dlon..=b.maxlon + dlon).contains(&p.lon())
}

fn tag<'a>(tags: &'a BTreeMap<String, String>, key: &str) -> Option<&'a str> {
    tags.get(key).map(|v| v.trim()).filter(|v| !v.is_empty())
}

/// Any value but a negative one: `shower=hot`, `toilets=customers` count.
fn present(tags: &BTreeMap<String, String>, key: &str) -> bool {
    tag(tags, key).is_some_and(|v| !matches!(v, "no" | "none" | "false" | "0"))
}

fn one_of(tags: &BTreeMap<String, String>, key: &str, values: &[&str]) -> bool {
    tag(tags, key).is_some_and(|v| values.contains(&v))
}

fn first_tag<'a>(tags: &'a BTreeMap<String, String>, keys: &[&str]) -> Option<&'a str> {
    keys.iter().find_map(|k| tag(tags, k))
}

/// `description` (language undetermined) and every `description:<lang>`
/// whose suffix is a language tag (not `description:payment`).
fn descriptions_of(tags: &BTreeMap<String, String>) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    if let Some(d) = tag(tags, "description") {
        out.insert(UNDETERMINED_LANGUAGE.to_owned(), d.to_owned());
    }
    let from = (
        std::ops::Bound::Included("description:"),
        std::ops::Bound::Unbounded,
    );
    for (key, _) in tags.range::<str, _>(from) {
        let Some(lang) = key.strip_prefix("description:") else {
            break;
        };
        if is_language_tag(lang)
            && let Some(d) = tag(tags, key)
        {
            out.insert(lang.to_owned(), d.to_owned());
        }
    }
    out
}

/// Whether the tags close the spot to motorhomes or to the public.
///
/// The specific key overrides the general one, as OSM reads them:
/// `access=no` with `motorhome=designated` is a car park for motorhomes
/// only, kept.
fn closed_to_motorhomes(tags: &BTreeMap<String, String>) -> bool {
    let let_in = one_of(tags, "motorhome", &["yes", "designated"])
        || one_of(tags, "caravan", &["yes", "designated"]);
    one_of(tags, "motorhome", &["no"]) || (!let_in && one_of(tags, "access", &["no", "private"]))
}

pub(crate) fn kind_of(tags: &BTreeMap<String, String>) -> Option<PlaceKind> {
    if one_of(tags, "camp_site", &["pitch"]) {
        return None;
    }
    match (tag(tags, "tourism"), tag(tags, "amenity")) {
        (Some("caravan_site"), _) => {
            let says_campsite = one_of(tags, "caravan_site", &["campsite", "camp_site"]);
            let stopover = one_of(tags, "caravan_site", &["motorhome_stopover"]);
            let runs_as_campsite = tag(tags, "stars").is_some()
                || one_of(tags, "tents", &["yes"])
                || ((present(tags, "shower") || present(tags, "showers"))
                    && present(tags, "toilets"));
            Some(if !stopover && (says_campsite || runs_as_campsite) {
                PlaceKind::Campsite
            } else {
                PlaceKind::MotorhomeArea
            })
        }
        (Some("camp_site"), _) => Some(PlaceKind::Campsite),
        (_, Some("sanitary_dump_station")) => Some(PlaceKind::ServiceArea),
        (_, Some("parking"))
            if (one_of(tags, "motorhome", &["yes", "designated"])
                || one_of(tags, "caravan", &["yes", "designated"]))
                && !closed_to_motorhomes(tags) =>
        {
            Some(PlaceKind::Parking)
        }
        // After the sites: an area tagged both a motorhome area and a rest
        // area is the motorhome area.
        _ if one_of(tags, "highway", &["rest_area", "services"]) => {
            (!closed_to_motorhomes(tags)).then_some(PlaceKind::RestArea)
        }
        _ => None,
    }
}

fn services_of(tags: &BTreeMap<String, String>, kind: PlaceKind) -> Vec<Service> {
    let mut s = Vec::new();
    if present(tags, "drinking_water") || present(tags, "water_point") {
        s.push(Service::DrinkingWater);
    }
    if kind == PlaceKind::ServiceArea || present(tags, "sanitary_dump_station") {
        s.extend([Service::GreyWater, Service::BlackWater]);
    }
    if present(tags, "power_supply") {
        s.push(Service::Electricity);
    }
    if present(tags, "toilets") {
        s.push(Service::Toilets);
    }
    if present(tags, "shower") || present(tags, "showers") {
        s.push(Service::Showers);
    }
    if one_of(tags, "internet_access", &["wlan", "wifi", "yes"]) {
        s.push(Service::Wifi);
    }
    if one_of(tags, "dog", &["yes", "leashed", "unleashed"]) {
        s.push(Service::PetsAllowed);
    }
    s
}

/// A price in euros from a `charge` value: `14.30 EUR`, `12€`, `13,50 EUR /
/// night`, `EUR 10`. Only the first charge of a list counts, and only a
/// price per night or per day, never per hour; anything else is `None`,
/// because a wrong price is worse than an unknown one.
#[must_use]
pub fn parse_charge(raw: &str) -> Option<f64> {
    let first = raw.split(';').next()?.trim().to_lowercase();
    let (amount_part, period) = match first.split_once('/') {
        Some((a, p)) => (a.trim().to_owned(), Some(p.trim().to_owned())),
        None => (first.clone(), None),
    };
    if let Some(p) = period
        && !["night", "nuit", "day", "jour", "24h", "24 h"].contains(&p.as_str())
    {
        return None;
    }
    let cleaned = amount_part.replace('€', " eur ");
    let tokens: Vec<&str> = cleaned.split_whitespace().collect();
    let amount = match tokens.as_slice() {
        [n, "eur" | "euro" | "euros"] | ["eur", n] => *n,
        _ => return None,
    };
    let v: f64 = amount.replace(',', ".").parse().ok()?;
    (v.is_finite() && (0.0..1_000.0).contains(&v)).then_some(v)
}

/// A height in metres from a `maxheight` value: `2.5`, `2,5 m`, `2.50m`,
/// `8'6"`. Values outside 1 to 6 m are refused as typos.
#[must_use]
pub fn parse_maxheight(raw: &str) -> Option<f64> {
    let t = raw.trim().to_lowercase();
    let metres = if let Some((feet, rest)) = t.split_once('\'') {
        let inches = rest.trim().trim_end_matches('"').trim();
        let feet: f64 = feet.trim().parse().ok()?;
        let inches: f64 = if inches.is_empty() {
            0.0
        } else {
            inches.parse().ok()?
        };
        (feet * 12.0 + inches) * 0.0254
    } else {
        let n = t.trim_end_matches('m').trim().replace(',', ".");
        n.parse().ok()?
    };
    (metres.is_finite() && (1.0..=6.0).contains(&metres))
        .then_some((metres * 100.0).round() / 100.0)
}

fn parse_count(raw: &str) -> Option<u32> {
    raw.trim()
        .parse::<u32>()
        .ok()
        .filter(|n| (1..=10_000).contains(n))
}

/// Stars from `stars=3` or `stars=3S` (the "superior" suffix some
/// classifications add).
fn parse_stars(raw: &str) -> Option<u8> {
    let digits: String = raw
        .trim()
        .chars()
        .take_while(char::is_ascii_digit)
        .collect();
    digits.parse::<u8>().ok().filter(|d| (1..=5).contains(d))
}

/// Where an element is and how large it is: a node is a point; a way or a
/// relation is the centre of its bounding box, with half its diagonal as the
/// uncertainty.
fn locate(element: &Element) -> Result<(Position, f64, Option<Bounds>), Skip> {
    if let (Some(lat), Some(lon)) = (element.lat, element.lon) {
        return Ok((Position::new(lat, lon)?, 0.0, None));
    }
    let b = element.bounds.ok_or(Skip::NoCoordinates)?;
    let sw = Position::new(b.minlat, b.minlon)?;
    let ne = Position::new(b.maxlat, b.maxlon)?;
    let centre = Position::new((b.minlat + b.maxlat) / 2.0, (b.minlon + b.maxlon) / 2.0)?;
    let half_diagonal = (sw.distance_m(ne) / 2.0 * 10.0).round() / 10.0;
    Ok((centre, half_diagonal, Some(b)))
}

/// Whether a night may be spent at a spot of `kind`: what a tag says
/// first, then the kind's default. Conservative: a car park or a rest area
/// is unknown unless a tag says otherwise; `motorhome=designated` makes a
/// car park tolerated, the reading of the MVP kept since.
#[must_use]
pub fn overnight_of(kind: PlaceKind, tags: &BTreeMap<String, String>) -> OvernightStatus {
    // Every spot read here takes motorhomes by day: one whose night is
    // refused is a day stop, which says more than "forbidden".
    let said = |key: &str| match tag(tags, key) {
        Some("yes" | "designated") => Some(OvernightStatus::Allowed),
        Some("no") => Some(OvernightStatus::DayOnly),
        _ => None,
    };
    if let Some(o) = said("motorhome:overnight").or_else(|| said("overnight")) {
        return o;
    }
    if tag(tags, "maxstay").is_some_and(shorter_than_a_night) {
        return OvernightStatus::DayOnly;
    }
    match kind {
        PlaceKind::Campsite | PlaceKind::MotorhomeArea => OvernightStatus::Allowed,
        PlaceKind::Parking if one_of(tags, "motorhome", &["designated"]) => {
            OvernightStatus::Tolerated
        }
        _ => OvernightStatus::Unknown,
    }
}

/// Whether a `maxstay` value forbids a night: a number of minutes or of
/// hours under twelve, or `load-unload`. Days, `unlimited`, `no` and
/// anything unread leave the night unknown.
fn shorter_than_a_night(raw: &str) -> bool {
    let v = raw.trim().to_ascii_lowercase();
    if v == "load-unload" {
        return true;
    }
    let mut parts = v.split_whitespace();
    let (Some(n), Some(unit)) = (parts.next(), parts.next()) else {
        return false;
    };
    let Ok(n) = n.replace(',', ".").parse::<f64>() else {
        return false;
    };
    match unit {
        "minute" | "minutes" | "min" => n > 0.0 && n < 720.0,
        "hour" | "hours" | "h" => n > 0.0 && n < 12.0,
        _ => false,
    }
}

/// A vehicle limit as the routing reads it, kept only within `plausible`.
fn limit(
    tags: &BTreeMap<String, String>,
    kind: RestrictionKind,
    plausible: &std::ops::RangeInclusive<f64>,
) -> Option<f64> {
    routing_tags::plausible(routing_tags::read_limit(tags, kind), plausible)
        .limit()
        .map(|v| (v * 100.0).round() / 100.0)
}

fn map_element(element: &Element) -> Result<(NormalizedRecord, Option<Bounds>), Skip> {
    let tags = &element.tags;
    let kind = kind_of(tags).ok_or(Skip::OutOfScope)?;
    let (position, accuracy_m, bounds) = locate(element)?;
    let mut r = NormalizedRecord::new(kind, position);
    r.accuracy_m = accuracy_m;
    r.name = tag(tags, "name").map(str::to_owned);
    r.overnight = overnight_of(kind, tags);
    r.services = services_of(tags, kind).into_iter().collect();
    let price = if one_of(tags, "fee", &["no"]) {
        Some(0.0)
    } else {
        tag(tags, "charge").and_then(parse_charge)
    };
    if kind == PlaceKind::ServiceArea {
        r.price_services_eur = price;
    } else {
        r.price_parking_eur = price;
    }
    r.max_height_m = tag(tags, "maxheight").and_then(parse_maxheight);
    r.max_length_m = limit(
        tags,
        RestrictionKind::MaxLength,
        &PLAUSIBLE_VEHICLE_LENGTH_M,
    );
    r.max_width_m = limit(tags, RestrictionKind::MaxWidth, &PLAUSIBLE_LENGTH_M);
    r.max_weight_t = limit(tags, RestrictionKind::MaxWeight, &PLAUSIBLE_WEIGHT_T);
    let capacity_keys: &[&str] = if kind == PlaceKind::Parking {
        &["capacity:motorhome", "capacity:caravans"]
    } else {
        &[
            "capacity:motorhome",
            "capacity:caravans",
            "capacity:pitches",
            "capacity",
        ]
    };
    r.capacity = first_tag(tags, capacity_keys).and_then(parse_count);
    r.opening_hours = tag(tags, "opening_hours").map(str::to_owned);
    r.website = ["website", "contact:website", "url"]
        .iter()
        .find_map(|k| tag(tags, k).and_then(web::website));
    r.phone = first_tag(tags, &["phone", "contact:phone", "contact:mobile"]).map(str::to_owned);
    r.description = first_tag(tags, &["description:fr", "description"]).map(str::to_owned);
    r.stars = tag(tags, "stars").and_then(parse_stars);
    r.descriptions = descriptions_of(tags);
    r.wikidata = tag(tags, "wikidata").map(str::to_owned);
    r.wikipedia = tag(tags, "wikipedia").map(str::to_owned);
    r.osm_ref = Some(format!("{}/{}", element.kind, element.id));
    r.address.street = match (tag(tags, "addr:housenumber"), tag(tags, "addr:street")) {
        (Some(n), Some(s)) => Some(format!("{n} {s}")),
        (None, Some(s)) => Some(s.to_owned()),
        _ => None,
    };
    r.address.postcode = tag(tags, "addr:postcode").map(str::to_owned);
    r.address.city = tag(tags, "addr:city").map(str::to_owned);
    // Every element comes from a French region query.
    r.address.country_code = Some(tag(tags, "addr:country").unwrap_or("FR").to_uppercase());
    Ok((r, bounds))
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    #[test]
    fn descriptions_are_kept_by_language() {
        let tags: BTreeMap<String, String> = [
            ("description", "Au bord du lac"),
            ("description:en", "By the lake"),
            ("description:payment", "cash only"),
            ("description:de", " "),
            ("descriptions", "not a description key"),
            ("name", "Aire du lac"),
        ]
        .iter()
        .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
        .collect();
        let got = descriptions_of(&tags);
        assert_eq!(
            got.into_iter().collect::<Vec<_>>(),
            [
                ("en".to_owned(), "By the lake".to_owned()),
                ("und".to_owned(), "Au bord du lac".to_owned())
            ],
            "a key that is not a language, or an empty value, is no description"
        );
    }

    #[test]
    fn charges_read_only_unambiguous_prices() {
        assert_eq!(parse_charge("14.30 EUR"), Some(14.3));
        assert_eq!(parse_charge("13,50 EUR / night"), Some(13.5));
        assert_eq!(parse_charge("12€"), Some(12.0));
        assert_eq!(parse_charge("12 €/nuit"), Some(12.0));
        assert_eq!(parse_charge("EUR 10"), Some(10.0));
        assert_eq!(parse_charge("16 EUR; 2 EUR/hour"), Some(16.0));
        assert_eq!(
            parse_charge("13/50 EUR / night"),
            None,
            "a typo is not a price"
        );
        assert_eq!(
            parse_charge("2 EUR/hour"),
            None,
            "an hourly rate is not the price of a night"
        );
        assert_eq!(parse_charge("free"), None);
        assert_eq!(parse_charge("10 USD"), None);
    }

    #[test]
    fn heights_read_metres_and_feet() {
        assert_eq!(parse_maxheight("2.5"), Some(2.5));
        assert_eq!(parse_maxheight("2,5 m"), Some(2.5));
        assert_eq!(parse_maxheight("2.50m"), Some(2.5));
        assert_eq!(parse_maxheight("8'6\""), Some(2.59));
        assert_eq!(parse_maxheight("default"), None);
        assert_eq!(parse_maxheight("25"), None, "25 m is a typo for 2.5");
    }

    #[test]
    fn stars_read_the_leading_number() {
        assert_eq!(parse_stars("3"), Some(3));
        assert_eq!(parse_stars("3S"), Some(3));
        assert_eq!(parse_stars("10"), None);
        assert_eq!(parse_stars("0"), None);
    }

    fn tags(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn only_web_links_become_the_website() {
        let element = |t: &[(&str, &str)]| Element {
            kind: "node".into(),
            id: 1,
            lat: Some(47.0),
            lon: Some(-0.5),
            bounds: None,
            tags: tags(t),
        };
        let website = |t: &[(&str, &str)]| map_element(&element(t)).unwrap().0.website;
        assert_eq!(
            website(&[
                ("tourism", "camp_site"),
                ("website", "javascript:alert(document.cookie)"),
                ("contact:website", "www.camping-x.fr"),
            ])
            .as_deref(),
            Some("http://www.camping-x.fr"),
            "a hostile value is skipped for the next key"
        );
        assert_eq!(
            website(&[("tourism", "camp_site"), ("url", "data:text/html,x")]),
            None
        );
    }

    #[test]
    fn caravan_sites_that_run_as_campsites_are_campsites() {
        let k = |t: &[(&str, &str)]| kind_of(&tags(t));
        assert_eq!(
            k(&[("tourism", "caravan_site")]),
            Some(PlaceKind::MotorhomeArea)
        );
        assert_eq!(
            k(&[("tourism", "caravan_site"), ("caravan_site", "campsite")]),
            Some(PlaceKind::Campsite)
        );
        assert_eq!(
            k(&[("tourism", "caravan_site"), ("stars", "3")]),
            Some(PlaceKind::Campsite)
        );
        assert_eq!(
            k(&[
                ("tourism", "caravan_site"),
                ("shower", "hot"),
                ("toilets", "yes")
            ]),
            Some(PlaceKind::Campsite)
        );
        assert_eq!(
            k(&[
                ("tourism", "caravan_site"),
                ("caravan_site", "motorhome_stopover"),
                ("tents", "yes")
            ]),
            Some(PlaceKind::MotorhomeArea),
            "an explicit stopover stays one"
        );
        assert_eq!(
            k(&[("amenity", "parking")]),
            None,
            "a car park without motorhomes is out of scope"
        );
        assert_eq!(
            k(&[("amenity", "parking"), ("motorhome", "designated")]),
            Some(PlaceKind::Parking)
        );
    }

    #[test]
    fn overnight_is_unknown_unless_a_tag_says_it() {
        let o = |kind, t: &[(&str, &str)]| overnight_of(kind, &tags(t));
        assert_eq!(
            o(PlaceKind::RestArea, &[("highway", "rest_area")]),
            OvernightStatus::Unknown
        );
        assert_eq!(
            o(
                PlaceKind::Parking,
                &[("amenity", "parking"), ("caravan", "yes")]
            ),
            OvernightStatus::Unknown
        );
        assert_eq!(
            o(
                PlaceKind::Parking,
                &[("amenity", "parking"), ("motorhome", "designated")]
            ),
            OvernightStatus::Tolerated
        );
        assert_eq!(
            o(PlaceKind::RestArea, &[("motorhome:overnight", "yes")]),
            OvernightStatus::Allowed
        );
        assert_eq!(
            o(
                PlaceKind::Parking,
                &[("motorhome", "designated"), ("overnight", "no")]
            ),
            OvernightStatus::DayOnly,
            "an explicit tag wins over the kind's default"
        );
        assert_eq!(
            o(PlaceKind::MotorhomeArea, &[("motorhome:overnight", "no")]),
            OvernightStatus::DayOnly,
            "a spot open to motorhomes whose night is refused is a day stop"
        );
        for short in ["2 hours", "1.5 hours", "30 minutes", "load-unload"] {
            assert_eq!(
                o(PlaceKind::Parking, &[("maxstay", short)]),
                OvernightStatus::DayOnly,
                "{short}"
            );
        }
        for long in [
            "unlimited",
            "no",
            "2 days",
            "24 hours",
            "1440 minutes",
            "whatever",
        ] {
            assert_eq!(
                o(PlaceKind::Parking, &[("maxstay", long)]),
                OvernightStatus::Unknown,
                "{long}"
            );
        }
    }

    #[test]
    fn new_spots_and_their_exclusions() {
        let k = |t: &[(&str, &str)]| kind_of(&tags(t));
        assert_eq!(k(&[("highway", "rest_area")]), Some(PlaceKind::RestArea));
        assert_eq!(k(&[("highway", "services")]), Some(PlaceKind::RestArea));
        assert_eq!(k(&[("highway", "rest_area"), ("motorhome", "no")]), None);
        assert_eq!(k(&[("highway", "services"), ("access", "private")]), None);
        assert_eq!(
            k(&[("amenity", "parking"), ("caravan", "yes")]),
            Some(PlaceKind::Parking)
        );
        assert_eq!(
            k(&[
                ("amenity", "parking"),
                ("caravan", "yes"),
                ("motorhome", "no")
            ]),
            None
        );
        assert_eq!(
            k(&[
                ("amenity", "parking"),
                ("motorhome", "designated"),
                ("access", "no")
            ]),
            Some(PlaceKind::Parking),
            "the specific key wins: a car park for motorhomes only"
        );
        assert_eq!(
            k(&[("amenity", "parking"), ("access", "private")]),
            None,
            "nothing lets motorhomes in"
        );
        assert_eq!(
            k(&[("tourism", "caravan_site"), ("highway", "rest_area")]),
            Some(PlaceKind::MotorhomeArea),
            "a motorhome area that is also a rest area is the motorhome area"
        );
        assert_eq!(
            k(&[
                ("tourism", "caravan_site"),
                ("highway", "rest_area"),
                ("access", "no")
            ]),
            Some(PlaceKind::MotorhomeArea),
            "and an access tag on it does not drop it"
        );
        assert_eq!(k(&[("tourism", "camp_site"), ("camp_site", "pitch")]), None);
        assert_eq!(k(&[("tourism", "camp_pitch")]), None);
    }

    #[test]
    fn vehicle_limits_read_as_the_routing_reads_them() {
        let e = Element {
            kind: "way".into(),
            id: 7,
            lat: Some(47.0),
            lon: Some(-0.5),
            bounds: None,
            tags: tags(&[
                ("amenity", "parking"),
                ("motorhome", "designated"),
                ("maxlength", "8 m"),
                ("maxwidth", "2,55"),
                ("maxweightrating", "3.5"),
                ("maxweight", "12"),
            ]),
        };
        let r = map_element(&e).unwrap().0;
        assert_eq!(r.max_length_m, Some(8.0));
        assert_eq!(r.max_width_m, Some(2.55));
        assert_eq!(
            r.max_weight_t,
            Some(3.5),
            "the lowest of maxweight and maxweightrating"
        );
        let implausible = Element {
            tags: tags(&[
                ("amenity", "parking"),
                ("motorhome", "yes"),
                ("maxweight", "120"),
            ]),
            ..e
        };
        assert_eq!(map_element(&implausible).unwrap().0.max_weight_t, None);
    }

    #[test]
    fn pitches_inside_a_site_are_folded_into_it() {
        let node = |id: i64, lat: f64, lon: f64, t: &[(&str, &str)]| {
            let e = Element {
                kind: "node".into(),
                id,
                lat: Some(lat),
                lon: Some(lon),
                bounds: None,
                tags: tags(t),
            };
            let raw = serde_json::json!({"type": "node", "id": id});
            (e, raw)
        };
        let site = Element {
            kind: "way".into(),
            id: 1,
            lat: None,
            lon: None,
            bounds: Some(Bounds {
                minlat: 47.000,
                minlon: -0.502,
                maxlat: 47.004,
                maxlon: -0.498,
            }),
            tags: tags(&[("tourism", "camp_site"), ("name", "Camping des Pins")]),
        };
        let elements = vec![
            (site, serde_json::json!({"type": "way", "id": 1})),
            node(
                2,
                47.001,
                -0.501,
                &[
                    ("tourism", "caravan_site"),
                    ("name", "S33"),
                    ("power_supply", "yes"),
                ],
            ),
            node(3, 47.002, -0.500, &[("tourism", "camp_site")]),
            node(
                4,
                47.003,
                -0.499,
                &[("tourism", "camp_site"), ("name", "camping des pins")],
            ),
            node(
                5,
                47.002,
                -0.501,
                &[("tourism", "caravan_site"), ("name", "Aire du Moulin")],
            ),
            node(
                6,
                47.200,
                -0.500,
                &[("tourism", "caravan_site"), ("name", "Z109")],
            ),
        ];
        let parsed = build(elements, Utc::now());
        let ids: Vec<&str> = parsed
            .records
            .iter()
            .map(|r| r.external_id.as_str())
            .collect();
        assert_eq!(
            ids,
            ["way/1", "node/5", "node/6"],
            "a pitch number, no name or the site's own name inside its outline is a pitch; \
             another name, or a pitch number outside any site, stays a place"
        );
        assert_eq!(parsed.folded_pitches, 3);
        let host = &parsed.records[0];
        assert!(
            host.record.services.contains(&Service::Electricity),
            "a pitch's services are the site's"
        );
        assert_eq!(host.raw["_attached"].as_array().map(Vec::len), Some(3));
    }

    #[test]
    fn pitch_codes_are_told_from_names() {
        for code in ["S33", "Z109", "12", "A-12", "12b", "AB 7"] {
            assert!(is_pitch_code(code), "{code}");
        }
        for name in [
            "Camping du Lac",
            "Aire 2000 plus",
            "Les Pins",
            "ABCD12",
            "12345",
            "",
        ] {
            assert!(!is_pitch_code(name), "{name}");
        }
    }

    #[test]
    fn negative_values_are_no_service() {
        let t = tags(&[
            ("toilets", "no"),
            ("shower", "hot"),
            ("power_supply", "yes"),
            ("dog", "no"),
        ]);
        let s = services_of(&t, PlaceKind::MotorhomeArea);
        assert_eq!(s, vec![Service::Electricity, Service::Showers]);
    }

    #[test]
    fn every_region_query_targets_its_region() {
        assert_eq!(
            REGIONS.len(),
            13,
            "the thirteen regions of metropolitan France"
        );
        for r in REGIONS {
            let q = region_query(*r);
            assert!(q.contains(&format!("\"ISO3166-2\"=\"{}\"", r.code)));
            assert!(q.contains("out tags bb"));
        }
        assert_eq!(region("fr-bre").map(|r| r.name), Some("Bretagne"));
        assert_eq!(region("FR-XXX"), None);
    }

    #[test]
    fn an_incomplete_answer_is_an_error() {
        let body = br#"{"remark":"runtime error: Query timed out in \"query\" at line 3 after 901 seconds.","elements":[]}"#;
        assert!(matches!(
            parse(body, Utc::now()),
            Err(IngestError::OverpassIncomplete { .. })
        ));
    }

    proptest! {
        #[test]
        fn value_parsers_never_panic(s in "\\PC{0,30}") {
            let _ = parse_charge(&s);
            let _ = parse_maxheight(&s);
            let _ = parse_count(&s);
            let _ = parse_stars(&s);
        }
    }
}
