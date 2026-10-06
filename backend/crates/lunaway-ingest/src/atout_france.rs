//! Atout France, classified tourist accommodation (data.gouv.fr dataset
//! "Hébergements touristiques classés en France", Licence Ouverte 2.0).
//!
//! The dataset is one CSV (semicolon separated, UTF-8) of every classified
//! establishment; the adapter keeps the campsites (`TYPOLOGIE ÉTABLISSEMENT`
//! = `CAMPING`). It brings what only the classification body knows: the
//! stars and the number of pitches. It has no coordinates and no identifier,
//! so:
//!
//! - positions come from the BAN geocoder ([`crate::geocode`]); a match below
//!   [`MIN_GEOCODE_SCORE`] or only at the municipality level is dropped,
//!   because a campsite put at the town hall would merge with the wrong spot
//!   or with nothing;
//! - the external id is `<postcode>:<folded municipality>:<folded name>`
//!   (several municipalities share a postcode, and "Camping du Lac" exists in
//!   two of them), stable as long as the campsite keeps its name; a renamed
//!   campsite becomes a new record and the old one is retired.
//!
//! The CSV location is looked up through the data.gouv.fr API, so a moved
//! resource is followed. Overseas establishments are skipped, like the
//! overseas OSM regions.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use lunaway_domain::{
    NormalizedRecord, OvernightStatus, PlaceKind, Position,
    conflation::normalize::{fold, normalize_name},
};
use serde::Deserialize;

use crate::{
    FetchedRecord, IngestError,
    cache::Cache,
    geocode::{AddressQuery, Geocoded, MatchType, Toponym},
    http::{RetryPolicy, check_status, read_capped, with_retry},
    web,
};

/// The dataset on data.gouv.fr.
pub const DATASET_ID: &str = "59c36c6a88ee3826d5998a35";
/// The data.gouv.fr API.
pub const DATA_GOUV_API: &str = "https://www.data.gouv.fr/api/1";
/// Hosts the CSV may be downloaded from. The data.gouv.fr metadata names the
/// file's location; it is followed only to where Atout France or data.gouv.fr
/// publish, never to whatever host the metadata might one day say.
pub const RESOURCE_HOSTS: &[&str] = &[
    "data.classement.atout-france.fr",
    "static.data.gouv.fr",
    "object.files.data.gouv.fr",
    "www.data.gouv.fr",
];
/// Largest dataset description accepted from the data.gouv.fr API.
const METADATA_MAX_BYTES: usize = 4 * 1024 * 1024;
/// Largest CSV accepted; the file weighed 3.7 MB on 2026-10-05.
const CSV_MAX_BYTES: usize = 64 * 1024 * 1024;
/// Geocoder matches below this score are dropped. The BAN scores a correct
/// house number around 0.9, a correct street around 0.7, and a guess on a
/// similar name below 0.5.
pub const MIN_GEOCODE_SCORE: f64 = 0.5;

/// A downloaded CSV.
#[derive(Debug, Clone)]
pub struct Download {
    /// The bytes.
    pub body: Vec<u8>,
    /// When they were fetched.
    pub fetched_at: DateTime<Utc>,
    /// Whether they came from the cache.
    pub cached: bool,
}

#[derive(Debug, Deserialize)]
struct Dataset {
    resources: Vec<Resource>,
}

#[derive(Debug, Deserialize)]
struct Resource {
    url: String,
    format: Option<String>,
    last_modified: Option<String>,
}

/// The CSV of the dataset: the newest cached copy unless `refresh`;
/// otherwise the resource the data.gouv.fr API points to, if it is on one
/// of `resource_hosts` ([`RESOURCE_HOSTS`] in production), cached under its
/// last modification date.
///
/// # Errors
///
/// [`IngestError`] when the API or the download fails, the dataset has no
/// CSV resource, or the resource is on another host.
pub async fn fetch_csv(
    http: &reqwest::Client,
    cache: &Cache,
    api: &str,
    resource_hosts: &[&str],
    retry: RetryPolicy,
    refresh: bool,
) -> Result<Download, IngestError> {
    if !refresh
        && let Some(key) = cache
            .latest("atout-france", "hebergements_classes-")
            .await?
        && let Some(c) = cache.read(&key).await?
    {
        tracing::info!(key, "atout france csv read from the cache");
        return Ok(Download {
            body: c.bytes,
            fetched_at: c.fetched_at,
            cached: true,
        });
    }
    let meta_url = format!("{}/datasets/{DATASET_ID}/", api.trim_end_matches('/'));
    let dataset: Dataset = with_retry("data.gouv.fr", retry, || async {
        let response = http
            .get(&meta_url)
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: meta_url.clone(),
                source,
            })?;
        let response = check_status(&meta_url, response).await?;
        let bytes = read_capped(&meta_url, response, METADATA_MAX_BYTES).await?;
        serde_json::from_slice(&bytes).map_err(|source| IngestError::Json {
            what: "data.gouv.fr dataset".into(),
            source,
        })
    })
    .await?;
    let resource = dataset
        .resources
        .into_iter()
        .find(|r| {
            r.format
                .as_deref()
                .is_some_and(|f| f.eq_ignore_ascii_case("csv"))
        })
        .ok_or_else(|| IngestError::NoResource {
            dataset: DATASET_ID.into(),
        })?;
    let stamp: String = resource
        .last_modified
        .as_deref()
        .unwrap_or("undated")
        .chars()
        .take(10)
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
        .collect();
    let key = format!("atout-france/hebergements_classes-{stamp}.csv");
    if !refresh && let Some(c) = cache.read(&key).await? {
        return Ok(Download {
            body: c.bytes,
            fetched_at: c.fetched_at,
            cached: true,
        });
    }
    web::check_host(&resource.url, resource_hosts)?;
    tracing::info!(url = %resource.url, "downloading the atout france csv");
    let body = with_retry("atout france csv", retry, || async {
        let response =
            http.get(&resource.url)
                .send()
                .await
                .map_err(|source| IngestError::Http {
                    url: resource.url.clone(),
                    source,
                })?;
        let response = check_status(&resource.url, response).await?;
        // A redirect may not leave the allowed hosts either.
        web::check_host(response.url().as_str(), resource_hosts)?;
        read_capped(&resource.url, response, CSV_MAX_BYTES).await
    })
    .await?;
    let fetched_at = cache.write(&key, &body).await?;
    Ok(Download {
        body,
        fetched_at,
        cached: false,
    })
}

/// A classified campsite as the CSV lists it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Campsite {
    /// `<postcode>:<folded municipality>:<folded name>`.
    pub external_id: String,
    /// Commercial name, upper case as published.
    pub name: String,
    /// Street address.
    pub address: String,
    /// Postcode.
    pub postcode: String,
    /// Municipality, upper case as published.
    pub city: String,
    /// `1 étoile` to `5 étoiles`, or `Aire naturelle`.
    pub classification: String,
    /// Number of pitches.
    pub pitches: Option<u32>,
    /// Website as published.
    pub website: Option<String>,
    /// Date of the classification decision, `DD/MM/YYYY`.
    pub classified_on: String,
    /// The row, header to value, kept as the raw payload.
    pub row: BTreeMap<String, String>,
}

/// What the CSV parse kept and dropped.
#[derive(Debug, Default)]
pub struct ParsedCsv {
    /// The campsites, one per external id.
    pub campsites: Vec<Campsite>,
    /// Rows of other kinds of accommodation.
    pub other_kinds: usize,
    /// Overseas campsites.
    pub overseas: usize,
    /// Rows listed twice under one external id (the newest is kept).
    pub duplicates: usize,
}

const COL_DATE: &str = "date de classement";
const COL_TYPE: &str = "typologie etablissement";
const COL_CLASS: &str = "classement";
const COL_NAME: &str = "nom commercial";
const COL_ADDRESS: &str = "adresse";
const COL_POSTCODE: &str = "code postal";
const COL_CITY: &str = "commune";
const COL_WEBSITE: &str = "site internet";
const COL_PITCHES: &str = "nombre d emplacements";

/// `-` is how the CSV writes an empty cell.
fn cell(v: Option<&str>) -> Option<String> {
    v.map(str::trim)
        .filter(|s| !s.is_empty() && *s != "-")
        .map(str::to_owned)
}

/// `DD/MM/YYYY` as a sortable `YYYYMMDD`.
fn sortable_date(d: &str) -> String {
    let parts: Vec<&str> = d.split('/').collect();
    match parts.as_slice() {
        [day, month, year] => format!("{year}{month}{day}"),
        _ => String::new(),
    }
}

/// Reads the CSV and keeps the metropolitan campsites.
///
/// # Errors
///
/// [`IngestError::Csv`] when the file is not a semicolon CSV, and
/// [`IngestError::MissingColumn`] when a column the adapter needs is gone.
pub fn parse_csv(body: &[u8]) -> Result<ParsedCsv, IngestError> {
    let mut reader = csv::ReaderBuilder::new()
        .delimiter(b';')
        .flexible(true)
        .from_reader(body);
    let csv_err = |source| IngestError::Csv {
        what: "atout france csv".into(),
        source,
    };
    // Columns are found by their folded header, so a change of accent or
    // case in the published file does not break the import.
    let headers: Vec<String> = reader
        .headers()
        .map_err(csv_err)?
        .iter()
        .map(str::to_owned)
        .collect();
    let folded: Vec<String> = headers.iter().map(|h| fold(h)).collect();
    for needed in [
        COL_DATE,
        COL_TYPE,
        COL_CLASS,
        COL_NAME,
        COL_ADDRESS,
        COL_POSTCODE,
        COL_CITY,
    ] {
        if !folded.iter().any(|h| h == needed) {
            return Err(IngestError::MissingColumn {
                what: "atout france csv".into(),
                column: needed.into(),
            });
        }
    }
    let mut out = ParsedCsv::default();
    let mut by_id: BTreeMap<String, Campsite> = BTreeMap::new();
    for record in reader.records() {
        let record = record.map_err(csv_err)?;
        let row: BTreeMap<String, String> = headers
            .iter()
            .zip(record.iter())
            .map(|(h, v)| (h.clone(), v.to_owned()))
            .collect();
        let get = |col: &str| {
            folded
                .iter()
                .position(|h| h == col)
                .and_then(|i| cell(record.get(i)))
        };
        if get(COL_TYPE).is_none_or(|t| fold(&t) != "camping") {
            out.other_kinds += 1;
            continue;
        }
        let (Some(name), Some(postcode)) = (get(COL_NAME), get(COL_POSTCODE)) else {
            out.other_kinds += 1;
            continue;
        };
        if postcode.starts_with("97") || postcode.starts_with("98") {
            out.overseas += 1;
            continue;
        }
        let city = get(COL_CITY).unwrap_or_default();
        let external_id = format!(
            "{postcode}:{}:{}",
            fold(&city).replace(' ', "-"),
            fold(&name).replace(' ', "-")
        );
        let campsite = Campsite {
            external_id: external_id.clone(),
            name,
            address: get(COL_ADDRESS).unwrap_or_default(),
            postcode,
            city,
            classification: get(COL_CLASS).unwrap_or_default(),
            pitches: get(COL_PITCHES).and_then(|p| p.parse().ok()),
            website: get(COL_WEBSITE),
            classified_on: get(COL_DATE).unwrap_or_default(),
            row,
        };
        match by_id.get(&external_id) {
            Some(existing)
                if sortable_date(&existing.classified_on)
                    >= sortable_date(&campsite.classified_on) =>
            {
                out.duplicates += 1;
            }
            Some(_) => {
                out.duplicates += 1;
                by_id.insert(external_id, campsite);
            }
            None => {
                by_id.insert(external_id, campsite);
            }
        }
    }
    out.campsites = by_id.into_values().collect();
    Ok(out)
}

/// The address queries for the geocoder, keyed by external id.
#[must_use]
pub fn address_queries(campsites: &[Campsite]) -> Vec<AddressQuery> {
    campsites
        .iter()
        .map(|c| AddressQuery {
            key: c.external_id.clone(),
            address: c.address.clone(),
            postcode: c.postcode.clone(),
            city: c.city.clone(),
        })
        .collect()
}

/// Lower-case words that stay lower case inside a French name.
const SMALL_WORDS: &[&str] = &[
    "de", "des", "du", "la", "le", "les", "et", "à", "au", "aux", "en", "sur", "sous", "l", "d",
];

/// "CAMPING DE L'ÉTANG" as "Camping de l'Étang", "MÛRS-ERIGNÉ" as
/// "Mûrs-Erigné": the published names are upper case, which reads as
/// shouting on a screen.
#[must_use]
pub fn title_case(s: &str) -> String {
    let lower = s.to_lowercase();
    let mut out = String::with_capacity(lower.len());
    let mut word = String::new();
    let mut first_word = true;
    let flush = |word: &mut String, out: &mut String, first: &mut bool| {
        if word.is_empty() {
            return;
        }
        if !*first && SMALL_WORDS.contains(&word.as_str()) {
            out.push_str(word);
        } else {
            let mut chars = word.chars();
            if let Some(c) = chars.next() {
                out.extend(c.to_uppercase());
                out.push_str(chars.as_str());
            }
        }
        word.clear();
        *first = false;
    };
    for c in lower.chars() {
        if c.is_alphanumeric() {
            word.push(c);
        } else {
            flush(&mut word, &mut out, &mut first_word);
            out.push(c);
        }
    }
    flush(&mut word, &mut out, &mut first_word);
    out
}

fn stars(classification: &str) -> Option<u8> {
    let digits: String = classification
        .chars()
        .take_while(char::is_ascii_digit)
        .collect();
    digits.parse::<u8>().ok().filter(|d| (1..=5).contains(d))
}

/// Why a campsite did not become a record.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct GeocodeDrops {
    /// The geocoder found nothing.
    pub not_found: usize,
    /// Found with a score below [`MIN_GEOCODE_SCORE`].
    pub low_score: usize,
    /// Found only as a municipality.
    pub municipality_only: usize,
}

/// Where a campsite was placed, and how.
#[derive(Debug, Clone, PartialEq)]
pub struct Placement {
    /// The point.
    pub position: Position,
    /// How far the campsite may be from it, metres.
    pub accuracy_m: f64,
    /// Only the municipality's point.
    pub approximate: bool,
    /// The municipality's INSEE code, when the geocoder gave it.
    pub city_code: Option<String>,
    /// What the geocoder said, kept in the raw payload.
    pub geocoding: serde_json::Value,
}

/// The placement an address answer gives, if good enough: a score of
/// [`MIN_GEOCODE_SCORE`] at least, below the municipality level. `pass`
/// names the second pass in the raw payload; the first pass writes none,
/// as before it existed.
#[must_use]
pub fn placement_of(g: &Geocoded, pass: Option<&str>) -> Option<Placement> {
    let (Some((lat, lon)), Some(score), Some(match_type)) = (g.lat_lon, g.score, g.match_type)
    else {
        return None;
    };
    let accuracy_m = match_type.accuracy_m()?;
    if score < MIN_GEOCODE_SCORE {
        return None;
    }
    let mut geocoding = serde_json::json!({
        "score": score,
        "type": format!("{match_type:?}"),
        "label": g.label,
        "cityCode": g.city_code,
    });
    if let (Some(pass), Some(o)) = (pass, geocoding.as_object_mut()) {
        o.insert("pass".into(), pass.into());
    }
    Some(Placement {
        position: Position::new(lat, lon).ok()?,
        accuracy_m,
        approximate: false,
        city_code: g.city_code.clone(),
        geocoding,
    })
}

/// Joins the campsites with their geocoding into records.
#[must_use]
pub fn to_records(
    campsites: &[Campsite],
    geocoded: &[Geocoded],
    fetched_at: DateTime<Utc>,
) -> (Vec<FetchedRecord>, GeocodeDrops) {
    let by_key: BTreeMap<&str, &Geocoded> = geocoded.iter().map(|g| (g.key.as_str(), g)).collect();
    let mut drops = GeocodeDrops::default();
    let mut records = Vec::new();
    for c in campsites {
        let Some(g) = by_key.get(c.external_id.as_str()) else {
            drops.not_found += 1;
            continue;
        };
        if g.lat_lon.is_none() || g.score.is_none() || g.match_type.is_none() {
            drops.not_found += 1;
            continue;
        }
        if g.score.is_some_and(|s| s < MIN_GEOCODE_SCORE) {
            drops.low_score += 1;
            continue;
        }
        match placement_of(g, None) {
            Some(p) => records.push(record_of(c, p, fetched_at)),
            None if g.match_type == Some(MatchType::Municipality) => drops.municipality_only += 1,
            None => drops.not_found += 1,
        }
    }
    (records, drops)
}

/// A campsite placed at `placement`, as a record.
#[must_use]
pub fn record_of(c: &Campsite, placement: Placement, fetched_at: DateTime<Utc>) -> FetchedRecord {
    let mut r = NormalizedRecord::new(PlaceKind::Campsite, placement.position);
    r.accuracy_m = placement.accuracy_m;
    r.position_approximate = placement.approximate;
    r.name = Some(title_case(&c.name));
    r.overnight = OvernightStatus::Allowed;
    r.stars = stars(&c.classification);
    r.capacity = c.pitches.filter(|p| *p > 0);
    r.website = c.website.as_deref().and_then(web::website);
    r.address.street = Some(c.address.clone()).filter(|a| !a.is_empty());
    r.address.postcode = Some(c.postcode.clone());
    r.address.city = Some(title_case(&c.city)).filter(|a| !a.is_empty());
    r.address.country_code = Some("FR".into());
    r.address.city_code = placement.city_code;
    let mut raw = serde_json::Map::new();
    raw.insert(
        "row".into(),
        serde_json::to_value(&c.row).unwrap_or(serde_json::Value::Null),
    );
    raw.insert("geocoding".into(), placement.geocoding);
    FetchedRecord {
        external_id: c.external_id.clone(),
        external_url: None,
        record: r,
        raw: serde_json::Value::Object(raw),
        fetched_at,
    }
}

// The second pass, for the campsites the first one could not place
// (`plan/research/08-backend-mvp.md`: 514 of 5682 on 2026-10-05). Three
// tries, in order, each kept only when it passes its own bar:
//
// 1. the address without what the BAN cannot read: a "lieu-dit" or
//    "hameau" prefix, a road number, a post box, a parenthesis ("Lieu-dit
//    Keraluic" scores 0.35, "Keraluic" 0.65);
// 2. the campsite's name in the Géoplateforme's points of interest (IGN BD
//    TOPO toponyms, the same service and licence), kept when the toponym is
//    a campsite whose name agrees with the commercial name;
// 3. the municipality alone, when the geocoder recognises it with a score of
//    [`MIN_MUNICIPALITY_SCORE`] at least: the record is then flagged
//    approximate, so the app says the point is the town's, not the
//    campsite's.

/// Words of an address the BAN cannot place: a locality marker, a road
/// number, a post box.
const ADDRESS_NOISE: &[&str] = &[
    "lieu-dit",
    "lieu dit",
    "lieudit",
    "l.d.",
    "ld",
    "hameau de",
    "hameau des",
    "hameau du",
    "hameau",
    "quartier",
    "au lieu-dit",
];

/// The address with what the BAN cannot read removed, or `None` when
/// nothing is left or nothing changed.
#[must_use]
pub fn simplify_address(address: &str) -> Option<String> {
    let mut a = address.to_owned();
    // A parenthesis holds a comment ("(face au lac)").
    while let (Some(open), Some(close)) = (a.find('('), a.find(')')) {
        if close < open {
            break;
        }
        a.replace_range(open..=close, " ");
    }
    // Comma-separated parts: drop the ones that are only a road number or
    // a post box ("Maison Amestoya, Route Départementale 918").
    let parts: Vec<String> = a
        .split(',')
        .map(str::trim)
        .filter(|p| !p.is_empty() && !is_road_or_box(p))
        .map(|p| {
            let folded = fold(p);
            let mut keep = p.to_owned();
            for noise in ADDRESS_NOISE {
                if folded.starts_with(&fold(noise)) {
                    // Cut the marker by its length in words.
                    let words = fold(noise).split(' ').count();
                    keep = p
                        .split(|c: char| c.is_whitespace() || c == '-')
                        .filter(|w| !w.is_empty())
                        .skip(words)
                        .collect::<Vec<_>>()
                        .join(" ");
                    break;
                }
            }
            keep
        })
        .filter(|p| !p.trim().is_empty())
        .collect();
    let out = parts.join(", ");
    (!out.is_empty() && fold(&out) != fold(address)).then_some(out)
}

/// Whether an address part is only a road number or a post box: `RD 22`,
/// `Route départementale 1075`, `CD 957`, `RN 197`, `BP 2`, `CS 30012`.
fn is_road_or_box(part: &str) -> bool {
    let folded = fold(part);
    let words: Vec<&str> = folded.split(' ').collect();
    let Some((last, head)) = words.split_last() else {
        return false;
    };
    let numbered = last.chars().next().is_some_and(|c| c.is_ascii_digit());
    let road_words = [
        "rd",
        "cd",
        "rn",
        "d",
        "n",
        "bp",
        "cs",
        "route",
        "departementale",
        "nationale",
        "chemin",
        "communal",
        "vicinal",
        "b",
        "p",
    ];
    numbered && !head.is_empty() && head.iter().all(|w| road_words.contains(w))
}

/// A municipality-level match below this score is not used even as an
/// approximate position.
pub const MIN_MUNICIPALITY_SCORE: f64 = 0.5;
/// How far, in metres, a campsite placed at its municipality may be from the
/// point: a French commune is a few kilometres across.
pub const MUNICIPALITY_ACCURACY_M: f64 = 2_000.0;

/// The approximate placement a municipality-level answer gives, if the
/// geocoder recognised the municipality well enough.
#[must_use]
pub fn municipality_placement(g: &Geocoded) -> Option<Placement> {
    let (Some((lat, lon)), Some(score)) = (g.lat_lon, g.score) else {
        return None;
    };
    if g.match_type != Some(MatchType::Municipality) || score < MIN_MUNICIPALITY_SCORE {
        return None;
    }
    Some(Placement {
        position: Position::new(lat, lon).ok()?,
        accuracy_m: MUNICIPALITY_ACCURACY_M,
        approximate: true,
        city_code: g.city_code.clone(),
        geocoding: serde_json::json!({
            "score": score,
            "type": "Municipality",
            "label": g.label,
            "cityCode": g.city_code,
            "pass": "municipality",
        }),
    })
}

/// Words of a commercial name that a toponym leaves out without being
/// another campsite: a chain, a label, the word for a holiday park.
const COMMERCIAL_WORDS: &[&str] = &[
    "residence",
    "resort",
    "village",
    "domaine",
    "parc",
    "park",
    "club",
    "flower",
    "sunelia",
    "yelloh",
    "huttopia",
    "siblu",
    "capfun",
    "tohapi",
    "campeole",
    "naturiste",
    "loisirs",
    "vacances",
    "holiday",
    "holidays",
    "spa",
];

/// The toponym of the Géoplateforme's points of interest that is this
/// campsite: a `camping` whose name, without the generic words, holds every
/// word of the commercial name, or all of them but chain and label words
/// ("Camping & Résidence le Napoléon" is the toponym "le Napoléon"). A
/// toponym that only shares a part ("Camping du Lac" for "Camping du Lac
/// Bleu") is another campsite of the town.
#[must_use]
pub fn toponym_placement(c: &Campsite, hits: &[Toponym]) -> Option<Placement> {
    let wanted = normalize_name(&c.name);
    if wanted.is_empty() {
        return None;
    }
    let wanted_words: std::collections::BTreeSet<&str> = wanted.split(' ').collect();
    let campsites: Vec<&Toponym> = hits
        .iter()
        .filter(|h| h.categories.iter().any(|k| fold(k) == "camping"))
        .collect();
    let agrees = |h: &Toponym, exact: bool| {
        h.names.iter().any(|n| {
            let got = normalize_name(n);
            let got_words: std::collections::BTreeSet<&str> =
                got.split(' ').filter(|w| !w.is_empty()).collect();
            if got_words.is_empty() {
                return false;
            }
            if exact {
                return got_words == wanted_words;
            }
            wanted_words.is_subset(&got_words)
                || (got_words.is_subset(&wanted_words)
                    && wanted_words
                        .difference(&got_words)
                        .all(|w| COMMERCIAL_WORDS.contains(w)))
        })
    };
    // The same name first: "Camping du Lac" takes the toponym "Camping du
    // Lac" over "Camping du Lac Bleu" when the town has both.
    campsites
        .iter()
        .copied()
        .find(|h| agrees(h, true))
        .or_else(|| campsites.iter().copied().find(|h| agrees(h, false)))
        .and_then(|h| {
            Some(Placement {
                position: Position::new(h.lat, h.lon).ok()?,
                // A toponym's point is inside the campsite's ground.
                accuracy_m: 100.0,
                approximate: false,
                city_code: h.city_code.clone(),
                geocoding: serde_json::json!({
                    "score": h.score,
                    "type": "Toponym",
                    "label": h.names.first(),
                    "cityCode": h.city_code,
                    "pass": "toponym",
                }),
            })
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_title_cased_the_french_way() {
        assert_eq!(title_case("CAMPING DE L'ÉTANG"), "Camping de l'Étang");
        assert_eq!(title_case("MÛRS-ERIGNÉ"), "Mûrs-Erigné");
        assert_eq!(title_case("LA BAULE-ESCOUBLAC"), "La Baule-Escoublac");
        assert_eq!(
            title_case("AGIS - CAMPING DES VARENNES"),
            "Agis - Camping des Varennes"
        );
        assert_eq!(title_case("L'ÎLE D'YEU"), "L'Île d'Yeu");
    }

    #[test]
    fn stars_come_from_the_classification() {
        assert_eq!(stars("1 étoile"), Some(1));
        assert_eq!(stars("4 étoiles"), Some(4));
        assert_eq!(stars("Aire naturelle"), None);
    }

    #[test]
    fn addresses_lose_what_the_geocoder_cannot_read() {
        assert_eq!(
            simplify_address("Lieu-dit Keraluic").as_deref(),
            Some("Keraluic")
        );
        assert_eq!(
            simplify_address("lieu dit Le Mas De Rome").as_deref(),
            Some("Le Mas De Rome")
        );
        assert_eq!(
            simplify_address("Hameau de Lozari").as_deref(),
            Some("Lozari")
        );
        assert_eq!(
            simplify_address("Maison Amestoya, Route Départementale 918").as_deref(),
            Some("Maison Amestoya")
        );
        assert_eq!(
            simplify_address("Les Pins (face au lac)").as_deref(),
            Some("Les Pins")
        );
        assert_eq!(simplify_address("BP 2"), None, "nothing left");
        assert_eq!(
            simplify_address("Route de Pingrieux"),
            None,
            "nothing to remove"
        );
        assert_eq!(simplify_address("12 rue du Lac"), None);
    }

    fn campsite(name: &str) -> Campsite {
        Campsite {
            external_id: "05000:gap:x".into(),
            name: name.into(),
            address: String::new(),
            postcode: "05000".into(),
            city: "GAP".into(),
            classification: "3 étoiles".into(),
            pitches: None,
            website: None,
            classified_on: String::new(),
            row: BTreeMap::new(),
        }
    }

    fn toponym(name: &str, category: &str) -> Toponym {
        Toponym {
            names: vec![name.into()],
            categories: vec![category.into(), "zone d'activité ou d'intérêt".into()],
            lat: 44.58298,
            lon: 6.083915,
            score: 0.33,
            city_code: Some("05061".into()),
        }
    }

    #[test]
    fn a_toponym_places_a_campsite_only_when_it_is_that_campsite() {
        let c = campsite("CAMPING & RÉSIDENCE LE NAPOLÉON");
        let p = toponym_placement(&c, &[toponym("le Napoléon", "camping")]).unwrap();
        assert!(!p.approximate);
        assert_eq!(p.position, Position::new(44.58298, 6.083915).unwrap());
        assert!(
            toponym_placement(&c, &[toponym("le Napoléon", "hôtel")]).is_none(),
            "a hotel of the same name is not the campsite"
        );
        assert!(
            toponym_placement(&c, &[toponym("les Mélèzes", "camping")]).is_none(),
            "another campsite of the town is not this one"
        );
        assert!(
            toponym_placement(
                &campsite("CAMPING DU LAC BLEU"),
                &[toponym("Camping du Lac", "camping")]
            )
            .is_none(),
            "a toponym sharing only part of the name is another campsite"
        );
        assert!(
            toponym_placement(
                &campsite("CAMPING DU LAC"),
                &[toponym("Camping du Lac Bleu", "camping")]
            )
            .is_some(),
            "a toponym holding the whole name"
        );
        let mut exact = toponym("Camping du Lac", "camping");
        exact.lat = 44.6;
        let chosen = toponym_placement(
            &campsite("CAMPING DU LAC"),
            &[toponym("Camping du Lac Bleu", "camping"), exact],
        )
        .unwrap();
        assert_eq!(
            chosen.position.lat(),
            44.6,
            "the same name wins over a longer one, whatever the order"
        );
        assert!(
            toponym_placement(
                &campsite("CAMPING MUNICIPAL"),
                &[toponym("camping municipal", "camping")]
            )
            .is_none(),
            "a name of generic words only identifies nothing"
        );
    }

    #[test]
    fn a_municipality_gives_an_approximate_position_when_recognised() {
        let g = |score: f64, t: MatchType| Geocoded {
            key: "k".into(),
            lat_lon: Some((44.4, 4.3)),
            score: Some(score),
            match_type: Some(t),
            label: Some("Le Temple-sur-Lot".into()),
            city_code: Some("47306".into()),
            status: "ok".into(),
        };
        let p = municipality_placement(&g(0.63, MatchType::Municipality)).unwrap();
        assert!(p.approximate, "a town's point is flagged");
        assert_eq!(p.accuracy_m, MUNICIPALITY_ACCURACY_M);
        assert!(municipality_placement(&g(0.4, MatchType::Municipality)).is_none());
        assert!(municipality_placement(&g(0.9, MatchType::Street)).is_none());
    }

    #[test]
    fn dates_sort_by_year_first() {
        assert!(sortable_date("01/12/2024") < sortable_date("05/01/2025"));
    }
}
