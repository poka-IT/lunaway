//! Batch geocoding with the Base Adresse Nationale (Licence Ouverte 2.0).
//!
//! The CSV endpoint takes a file of addresses and returns it with the
//! coordinates, a score and the precision of each match. The service moved
//! from `api-adresse.data.gouv.fr` to the IGN Géoplateforme
//! (`data.geopf.fr/geocodage`), with the same API; the old host answers with
//! `Deprecation` and `Sunset` headers, so the new one is the default.
//!
//! Every request and its answer are cached by content, so geocoding the same
//! addresses again reads the disk, unless the caller asks to refresh.

use std::time::Duration;

use reqwest::multipart::{Form, Part};
use serde::Deserialize;

use crate::{
    IngestError,
    cache::{Cache, short_hash},
    http::{RetryPolicy, check_status, read_capped, with_retry},
};

/// Largest answer accepted for one chunk: a thousand rows come back in
/// about 330 KB.
const ANSWER_MAX_BYTES: usize = 16 * 1024 * 1024;

/// Where and how to geocode.
#[derive(Debug, Clone)]
pub struct GeocoderConfig {
    /// Base URL; `/search/csv/` is appended.
    pub url: String,
    /// Rows per request.
    pub chunk: usize,
    /// Pause between two requests that reached the network: the endpoint
    /// announces a limit of one CSV request per second.
    pub pace: Duration,
    /// Retries on load shedding.
    pub retry: RetryPolicy,
}

impl GeocoderConfig {
    /// The Géoplateforme geocoder.
    pub const DEFAULT_URL: &'static str = "https://data.geopf.fr/geocodage";
}

/// One address to geocode.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AddressQuery {
    /// The caller's key, returned with the result.
    pub key: String,
    /// Street, house number, place name.
    pub address: String,
    /// Postcode, used as a filter.
    pub postcode: String,
    /// Municipality name.
    pub city: String,
}

/// How precise a match is, from the BAN's `result_type`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchType {
    /// A house number.
    HouseNumber,
    /// The middle of a street.
    Street,
    /// A named place (lieu-dit).
    Locality,
    /// The municipality as a whole.
    Municipality,
}

impl MatchType {
    fn parse(s: &str) -> Option<Self> {
        match s {
            "housenumber" => Some(Self::HouseNumber),
            "street" => Some(Self::Street),
            "locality" => Some(Self::Locality),
            "municipality" => Some(Self::Municipality),
            _ => None,
        }
    }

    /// How far the spot may be from the point, in metres. A street's point
    /// is its middle and a French rural street is often a kilometre long; a
    /// municipality's point is its town hall, too far from a campsite to be
    /// used at all (`None`).
    #[must_use]
    pub const fn accuracy_m(self) -> Option<f64> {
        match self {
            Self::HouseNumber => Some(30.0),
            Self::Street => Some(250.0),
            Self::Locality => Some(300.0),
            Self::Municipality => None,
        }
    }
}

/// The geocoder's answer for one address.
#[derive(Debug, Clone, PartialEq)]
pub struct Geocoded {
    /// The caller's key.
    pub key: String,
    /// Latitude and longitude, when found.
    pub lat_lon: Option<(f64, f64)>,
    /// Confidence, 0 to 1.
    pub score: Option<f64>,
    /// Precision of the match.
    pub match_type: Option<MatchType>,
    /// The address as the BAN knows it.
    pub label: Option<String>,
    /// INSEE code of the municipality.
    pub city_code: Option<String>,
    /// `ok`, `not-found`, `skipped` or `error`.
    pub status: String,
}

#[derive(Debug, Deserialize)]
struct Row {
    key: String,
    latitude: Option<String>,
    longitude: Option<String>,
    result_score: Option<String>,
    result_type: Option<String>,
    result_label: Option<String>,
    result_citycode: Option<String>,
    result_status: Option<String>,
}

fn non_empty(s: Option<String>) -> Option<String> {
    s.map(|v| v.trim().to_owned()).filter(|v| !v.is_empty())
}

/// Reads the CSV the endpoint returns.
///
/// # Errors
///
/// [`IngestError::Csv`] when the answer is not the expected CSV.
pub fn parse_answer(body: &[u8]) -> Result<Vec<Geocoded>, IngestError> {
    let mut reader = csv::ReaderBuilder::new().from_reader(body);
    let mut out = Vec::new();
    for row in reader.deserialize::<Row>() {
        let row = row.map_err(|source| IngestError::Csv {
            what: "geocoder answer".into(),
            source,
        })?;
        let num = |s: Option<String>| non_empty(s).and_then(|v| v.parse::<f64>().ok());
        let lat = num(row.latitude);
        let lon = num(row.longitude);
        out.push(Geocoded {
            key: row.key,
            lat_lon: lat.zip(lon),
            score: num(row.result_score),
            match_type: non_empty(row.result_type)
                .as_deref()
                .and_then(MatchType::parse),
            label: non_empty(row.result_label),
            city_code: non_empty(row.result_citycode),
            status: non_empty(row.result_status).unwrap_or_else(|| "error".into()),
        });
    }
    Ok(out)
}

/// The CSV sent for a chunk of addresses.
///
/// # Errors
///
/// [`IngestError::Csv`] when a value cannot be written (never, in practice:
/// the writer quotes what needs quoting).
pub fn request_csv(queries: &[AddressQuery]) -> Result<Vec<u8>, IngestError> {
    let mut w = csv::Writer::from_writer(Vec::new());
    let csv_err = |source| IngestError::Csv {
        what: "geocoder request".into(),
        source,
    };
    w.write_record(["key", "adresse", "code_postal", "commune"])
        .map_err(csv_err)?;
    for q in queries {
        w.write_record([&q.key, &q.address, &q.postcode, &q.city])
            .map_err(csv_err)?;
    }
    w.into_inner().map_err(|e| IngestError::Csv {
        what: "geocoder request".into(),
        source: e.into_error().into(),
    })
}

/// Geocodes `queries` in chunks, from the cache when the same chunk was
/// geocoded before and `refresh` is false; with `refresh` every chunk is
/// asked again and its cached answer replaced.
///
/// # Errors
///
/// [`IngestError`] when the geocoder keeps failing or answers something
/// that is not its CSV.
pub async fn geocode(
    http: &reqwest::Client,
    cache: &Cache,
    config: &GeocoderConfig,
    queries: &[AddressQuery],
    refresh: bool,
) -> Result<Vec<Geocoded>, IngestError> {
    let url = format!("{}/search/csv/", config.url.trim_end_matches('/'));
    let mut out = Vec::with_capacity(queries.len());
    let chunks: Vec<&[AddressQuery]> = queries.chunks(config.chunk.max(1)).collect();
    for (i, chunk) in chunks.iter().enumerate() {
        let body = request_csv(chunk)?;
        let key = format!("ban/{}.csv", short_hash(&body));
        if !refresh && let Some(c) = cache.read(&key).await? {
            out.extend(parse_answer(&c.bytes)?);
            continue;
        }
        tracing::info!(
            chunk = i + 1,
            of = chunks.len(),
            rows = chunk.len(),
            "geocoding"
        );
        let answer = with_retry("geocoder", config.retry, || async {
            let form = Form::new()
                .part(
                    "data",
                    Part::bytes(body.clone())
                        .file_name("lunaway.csv")
                        .mime_str("text/csv")
                        .map_err(|source| IngestError::Http {
                            url: url.clone(),
                            source,
                        })?,
                )
                .text("columns", "adresse")
                .text("columns", "commune")
                .text("postcode", "code_postal");
            let response = http
                .post(&url)
                .multipart(form)
                .send()
                .await
                .map_err(|source| IngestError::Http {
                    url: url.clone(),
                    source,
                })?;
            let response = check_status(&url, response).await?;
            let bytes = read_capped(&url, response, ANSWER_MAX_BYTES).await?;
            let parsed = parse_answer(&bytes)?;
            if parsed.len() != chunk.len() {
                return Err(IngestError::Incomplete {
                    what: "geocoder answer".into(),
                    expected: chunk.len(),
                    got: parsed.len(),
                });
            }
            Ok((bytes, parsed))
        })
        .await?;
        cache.write(&key, &answer.0).await?;
        out.extend(answer.1);
        if i + 1 < chunks.len() {
            tokio::time::sleep(config.pace).await;
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn match_types_map_to_an_uncertainty() {
        assert_eq!(
            MatchType::parse("housenumber").and_then(MatchType::accuracy_m),
            Some(30.0)
        );
        assert_eq!(
            MatchType::parse("municipality").and_then(MatchType::accuracy_m),
            None
        );
        assert_eq!(MatchType::parse("poi"), None);
    }

    #[test]
    fn the_request_quotes_what_needs_quoting() {
        let csv = request_csv(&[AddressQuery {
            key: "49170:x".into(),
            address: "chemin de la Bradière, lieu-dit la Chauvineau".into(),
            postcode: "49170".into(),
            city: "SAVENNIÈRES".into(),
        }])
        .unwrap();
        let text = String::from_utf8(csv).unwrap();
        assert_eq!(
            text,
            "key,adresse,code_postal,commune\n49170:x,\"chemin de la Bradière, lieu-dit la Chauvineau\",49170,SAVENNIÈRES\n"
        );
    }
}
