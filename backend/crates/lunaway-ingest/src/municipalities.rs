//! The French communes and their outlines, so every place knows its
//! municipality and a search for a town finds what lies inside it.
//!
//! Source: "Contours administratifs" (data.gouv.fr, ODbL, built from IGN
//! Admin Express and OpenStreetMap), communes simplified to 100 m: about
//! 8 MB compressed, 35 000 communes. The municipal districts of Paris, Lyon
//! and Marseille (features naming their `commune`) are left out: a place in
//! Lyon belongs to Lyon.

use std::io::Read;

use chrono::{DateTime, Utc};
use flate2::read::GzDecoder;
use lunaway_db::municipalities::Municipality;
use serde::Deserialize;

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
};

/// The 2025 communes, 100 m simplification.
pub const COMMUNES_URL: &str =
    "https://object.data.gouv.fr/contours-administratifs/2025/geojson/communes-100m.geojson.gz";

/// Most compressed bytes read: the file is about 8 MB.
const COMPRESSED_MAX_BYTES: usize = 64 * 1024 * 1024;
/// Most bytes inflated: the file is about 40 MB once inflated.
const INFLATED_MAX_BYTES: u64 = 512 * 1024 * 1024;

/// The communes as downloaded.
#[derive(Debug, Clone)]
pub struct Download {
    /// The gzip bytes.
    pub body: Vec<u8>,
    /// When they were fetched.
    pub fetched_at: DateTime<Utc>,
    /// Whether they came from the cache.
    pub cached: bool,
}

/// Downloads the communes, or reads them from the cache unless `refresh`.
///
/// # Errors
///
/// [`IngestError`] when the download or the cache fails.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    url: &str,
    refresh: bool,
) -> Result<Download, IngestError> {
    let key = format!(
        "municipalities/{}",
        url.rsplit('/').next().unwrap_or("communes.geojson.gz")
    );
    if !refresh && let Some(c) = cache.read(&key).await? {
        return Ok(Download {
            body: c.bytes,
            fetched_at: c.fetched_at,
            cached: true,
        });
    }
    tracing::info!(%url, "downloading the communes");
    let retry = RetryPolicy {
        min_delay: std::time::Duration::from_secs(5),
        max_delay: std::time::Duration::from_secs(60),
        max_retries: 4,
    };
    let body = with_retry("communes", retry, || async {
        let response = http
            .get(url)
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: url.to_owned(),
                source,
            })?;
        let response = check_status(url, response).await?;
        read_capped(url, response, COMPRESSED_MAX_BYTES).await
    })
    .await?;
    let fetched_at = cache.write(&key, &body).await?;
    Ok(Download {
        body,
        fetched_at,
        cached: false,
    })
}

#[derive(Deserialize)]
struct Collection {
    features: Vec<Feature>,
}

#[derive(Deserialize)]
struct Feature {
    properties: Properties,
    geometry: serde_json::Value,
}

#[derive(Deserialize)]
struct Properties {
    code: String,
    nom: String,
    /// Set on a municipal district: the code of its commune.
    #[serde(default)]
    commune: Option<String>,
}

/// What reading the file gave.
#[derive(Debug, Clone, Default)]
pub struct Parsed {
    /// The communes.
    pub municipalities: Vec<Municipality>,
    /// Municipal districts left out.
    pub districts: usize,
    /// Features without a usable code, name or polygon.
    pub skipped: usize,
}

fn valid_code(code: &str) -> bool {
    let b = code.as_bytes();
    b.len() == 5
        && b[0].is_ascii_digit()
        && (b[1].is_ascii_digit() || b[1] == b'A' || b[1] == b'B')
        && b[2..].iter().all(u8::is_ascii_digit)
}

/// Reads the communes from the gzip-compressed GeoJSON.
///
/// # Errors
///
/// [`IngestError::Json`] when the file is not a GeoJSON feature collection
/// (or inflates past any real size), [`IngestError::Inflate`] when it is not
/// gzip.
pub fn parse(gz: &[u8]) -> Result<Parsed, IngestError> {
    let mut json = Vec::new();
    GzDecoder::new(gz)
        .take(INFLATED_MAX_BYTES + 1)
        .read_to_end(&mut json)
        .map_err(|source| IngestError::Inflate {
            what: "communes".into(),
            source,
        })?;
    if u64::try_from(json.len()).unwrap_or(u64::MAX) > INFLATED_MAX_BYTES {
        return Err(IngestError::TooLarge {
            url: "communes (inflated)".into(),
            limit: usize::try_from(INFLATED_MAX_BYTES).unwrap_or(usize::MAX),
        });
    }
    let collection: Collection =
        serde_json::from_slice(&json).map_err(|source| IngestError::Json {
            what: "communes".into(),
            source,
        })?;
    let mut out = Parsed::default();
    for f in collection.features {
        if f.properties.commune.is_some() {
            out.districts += 1;
            continue;
        }
        let kind = f.geometry.get("type").and_then(serde_json::Value::as_str);
        let name = f.properties.nom.trim();
        if !valid_code(&f.properties.code)
            || name.is_empty()
            || !matches!(kind, Some("Polygon" | "MultiPolygon"))
        {
            out.skipped += 1;
            continue;
        }
        out.municipalities.push(Municipality {
            code: f.properties.code,
            name: name.to_owned(),
            geometry: f.geometry,
        });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use std::io::Write;

    use flate2::{Compression, write::GzEncoder};

    use super::*;

    fn gz(json: &str) -> Vec<u8> {
        let mut e = GzEncoder::new(Vec::new(), Compression::fast());
        e.write_all(json.as_bytes()).unwrap();
        e.finish().unwrap()
    }

    #[test]
    fn communes_are_kept_and_districts_left_out() {
        let file = r#"{"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"code":"74010","nom":"Annecy"},
           "geometry":{"type":"Polygon","coordinates":[[[6.0,45.8],[6.2,45.8],[6.2,46.0],[6.0,45.8]]]}},
          {"type":"Feature","properties":{"code":"69381","nom":"Lyon 1er Arrondissement","commune":"69123"},
           "geometry":{"type":"Polygon","coordinates":[[[4.8,45.7],[4.9,45.7],[4.9,45.8],[4.8,45.7]]]}},
          {"type":"Feature","properties":{"code":"2A004","nom":"Ajaccio"},
           "geometry":{"type":"MultiPolygon","coordinates":[[[[8.6,41.9],[8.8,41.9],[8.8,42.0],[8.6,41.9]]]]}},
          {"type":"Feature","properties":{"code":"bad","nom":"Nowhere"},
           "geometry":{"type":"Polygon","coordinates":[]}},
          {"type":"Feature","properties":{"code":"01001","nom":"Point"},
           "geometry":{"type":"Point","coordinates":[5.0,46.0]}}
        ]}"#;
        let parsed = parse(&gz(file)).unwrap();
        let codes: Vec<&str> = parsed
            .municipalities
            .iter()
            .map(|m| m.code.as_str())
            .collect();
        assert_eq!(codes, ["74010", "2A004"]);
        assert_eq!(parsed.districts, 1, "a place in Lyon belongs to Lyon");
        assert_eq!(parsed.skipped, 2);
    }

    #[test]
    fn a_file_that_is_not_gzip_is_refused() {
        assert!(matches!(
            parse(b"{\"features\":[]}"),
            Err(IngestError::Inflate { .. })
        ));
    }
}
