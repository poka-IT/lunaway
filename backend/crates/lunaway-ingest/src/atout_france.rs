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
    NormalizedRecord, OvernightStatus, PlaceKind, Position, conflation::normalize::fold,
};
use serde::Deserialize;

use crate::{
    FetchedRecord, IngestError,
    cache::Cache,
    geocode::{AddressQuery, Geocoded},
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
        let (Some((lat, lon)), Some(score), Some(match_type)) = (g.lat_lon, g.score, g.match_type)
        else {
            drops.not_found += 1;
            continue;
        };
        if score < MIN_GEOCODE_SCORE {
            drops.low_score += 1;
            continue;
        }
        let Some(accuracy_m) = match_type.accuracy_m() else {
            drops.municipality_only += 1;
            continue;
        };
        let Ok(position) = Position::new(lat, lon) else {
            drops.not_found += 1;
            continue;
        };
        let mut r = NormalizedRecord::new(PlaceKind::Campsite, position);
        r.accuracy_m = accuracy_m;
        r.name = Some(title_case(&c.name));
        r.overnight = OvernightStatus::Allowed;
        r.stars = stars(&c.classification);
        r.capacity = c.pitches.filter(|p| *p > 0);
        r.website = c.website.as_deref().and_then(web::website);
        r.address.street = Some(c.address.clone()).filter(|a| !a.is_empty());
        r.address.postcode = Some(c.postcode.clone());
        r.address.city = Some(title_case(&c.city)).filter(|a| !a.is_empty());
        r.address.country_code = Some("FR".into());
        r.address.city_code.clone_from(&g.city_code);
        let mut raw = serde_json::Map::new();
        raw.insert(
            "row".into(),
            serde_json::to_value(&c.row).unwrap_or(serde_json::Value::Null),
        );
        raw.insert(
            "geocoding".into(),
            serde_json::json!({
                "score": score,
                "type": format!("{match_type:?}"),
                "label": g.label,
                "cityCode": g.city_code,
            }),
        );
        records.push(FetchedRecord {
            external_id: c.external_id.clone(),
            external_url: None,
            record: r,
            raw: serde_json::Value::Object(raw),
            fetched_at,
        });
    }
    (records, drops)
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
    fn dates_sort_by_year_first() {
        assert!(sortable_date("01/12/2024") < sortable_date("05/01/2025"));
    }
}
