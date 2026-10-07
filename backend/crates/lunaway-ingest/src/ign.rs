//! IGN BD TOPO road sections that carry a restriction (height, total weight,
//! width, length), read through the Géoplateforme's WFS (Licence Ouverte
//! 2.0, "IGN, BD TOPO"; `docs/data-sources.md`).
//!
//! Only the restricted sections are asked for (a filter on the four
//! attributes), page after page in a stable order, one request at a time
//! with a pause between two. The whole answer is cached gzip-compressed, so
//! a graph build without `--refresh` reads the disk. IGN publishes a new
//! edition every quarter; a weekly refresh costs a few dozen requests.

use std::{io::Read as _, time::Duration};

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_domain::Position;
use serde::Deserialize;

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
};

/// The Géoplateforme's WFS endpoint.
pub const WFS_URL: &str = "https://data.geopf.fr/wfs/ows";
/// The road sections of BD TOPO version 3.
pub const LAYER: &str = "BDTOPO_V3:troncon_de_route";
/// The sections with at least one of the restrictions a motorhome cares
/// about. The axle load is left out: every value of Haute-Vienne is the
/// national 13 t on classified roads, not a local limit
/// (`plan/research/07-navigation.md`, B.2).
pub const FILTER: &str = "(restriction_de_hauteur IS NOT NULL OR restriction_de_poids_total IS NOT NULL \
     OR restriction_de_largeur IS NOT NULL OR restriction_de_longueur IS NOT NULL)";
/// Features per page: the server's own cap (`CountDefault` 5000 in its
/// capabilities, and a request for 6000 returns 5000, 2026-10-06).
pub const PAGE: usize = 5_000;
/// Pause between two requests.
const PACE: Duration = Duration::from_secs(1);
/// Pages read at most: France holds about 150 000 restricted sections, 30
/// pages; more means the filter no longer filters.
const MAX_PAGES: usize = 100;
/// Largest page accepted, bytes.
const MAX_PAGE_BYTES: usize = 64 * 1024 * 1024;
const CACHE_KEY: &str = "ign-bdtopo/troncons-restreints.geojson.gz";
const EDITION_KEY: &str = "ign-bdtopo/edition.txt";
/// Largest capabilities document accepted (5.3 MB on 2026-10-06).
const MAX_CAPABILITIES_BYTES: usize = 32 * 1024 * 1024;
/// Share of sections outside France (Geofabrik's cut, as the routing graph
/// reads it) above which the answer is refused: a swapped axis order or
/// another layer.
const MAX_OUTSIDE_SHARE: f64 = 0.05;

/// One restricted road section.
#[derive(Debug, Clone, PartialEq)]
pub struct IgnSection {
    /// IGN's identifier (`cleabs`).
    pub id: String,
    /// Clearance, metres.
    pub height_m: Option<f64>,
    /// Total weight, tonnes.
    pub weight_t: Option<f64>,
    /// Width, metres.
    pub width_m: Option<f64>,
    /// Length, metres.
    pub length_m: Option<f64>,
    /// Position relative to the ground: -1 under it, 0 on it, 1 above.
    pub ground: Option<i32>,
    /// The street name.
    pub name: Option<String>,
    /// When IGN last changed the section.
    pub modified_at: Option<DateTime<Utc>>,
    /// The section's line.
    pub geometry: Vec<Position>,
}

#[derive(Deserialize)]
struct Collection {
    #[serde(default)]
    features: Vec<Feature>,
}

#[derive(Deserialize)]
struct Feature {
    #[serde(default)]
    id: Option<String>,
    geometry: Option<Geometry>,
    #[serde(default)]
    properties: serde_json::Map<String, serde_json::Value>,
}

#[derive(Deserialize)]
struct Geometry {
    #[serde(rename = "type")]
    kind: String,
    coordinates: serde_json::Value,
}

fn number(props: &serde_json::Map<String, serde_json::Value>, key: &str) -> Option<f64> {
    match props.get(key)? {
        serde_json::Value::Number(n) => n.as_f64(),
        serde_json::Value::String(s) => s.trim().replace(',', ".").parse().ok(),
        _ => None,
    }
    .filter(|v: &f64| v.is_finite() && *v > 0.0)
}

fn text(props: &serde_json::Map<String, serde_json::Value>, key: &str) -> Option<String> {
    props
        .get(key)?
        .as_str()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.chars().take(200).collect())
}

fn date(props: &serde_json::Map<String, serde_json::Value>, key: &str) -> Option<DateTime<Utc>> {
    let s = props.get(key)?.as_str()?;
    DateTime::parse_from_rfc3339(s)
        .map(|d| d.with_timezone(&Utc))
        .ok()
        .or_else(|| {
            NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d")
                .ok()?
                .and_hms_opt(0, 0, 0)
                .map(|d| d.and_utc())
        })
}

/// The points of a `LineString` (a `MultiLineString` of one line too),
/// ignoring a third coordinate (BD TOPO is three-dimensional).
fn line(geometry: &Geometry) -> Option<Vec<Position>> {
    let coords = match geometry.kind.as_str() {
        "LineString" => geometry.coordinates.as_array()?,
        "MultiLineString" => {
            let lines = geometry.coordinates.as_array()?;
            if lines.len() != 1 {
                return None;
            }
            lines.first()?.as_array()?
        }
        _ => return None,
    };
    let points: Option<Vec<Position>> = coords
        .iter()
        .map(|c| {
            let c = c.as_array()?;
            Position::new(c.get(1)?.as_f64()?, c.first()?.as_f64()?).ok()
        })
        .collect();
    points.filter(|p| p.len() >= 2)
}

/// The sections of a GeoJSON `FeatureCollection` in WGS 84 (longitude
/// first, as the WFS answers with `SRSNAME=EPSG:4326` and GeoJSON output).
/// A feature without an identifier, a usable line or any restriction is
/// skipped and counted.
///
/// # Errors
///
/// [`IngestError::Json`] when the payload is not a feature collection.
pub fn parse(bytes: &[u8]) -> Result<(Vec<IgnSection>, usize), IngestError> {
    let collection: Collection =
        serde_json::from_slice(bytes).map_err(|source| IngestError::Json {
            what: "BD TOPO sections".into(),
            source,
        })?;
    let mut out = Vec::with_capacity(collection.features.len());
    let mut skipped = 0;
    for f in collection.features {
        let p = &f.properties;
        let id = text(p, "cleabs").or(f.id);
        let geometry = f.geometry.as_ref().and_then(line);
        let section = match (id, geometry) {
            (Some(id), Some(geometry)) => IgnSection {
                id,
                height_m: number(p, "restriction_de_hauteur"),
                weight_t: number(p, "restriction_de_poids_total"),
                width_m: number(p, "restriction_de_largeur"),
                length_m: number(p, "restriction_de_longueur"),
                ground: p
                    .get("position_par_rapport_au_sol")
                    .and_then(|v| match v {
                        serde_json::Value::Number(n) => n.as_i64(),
                        serde_json::Value::String(s) => s.trim().parse().ok(),
                        _ => None,
                    })
                    .and_then(|v| i32::try_from(v).ok()),
                name: text(p, "nom_voie_ban_gauche").or_else(|| text(p, "nom_collaboratif_gauche")),
                modified_at: date(p, "date_modification").or_else(|| date(p, "date_creation")),
                geometry,
            },
            _ => {
                skipped += 1;
                continue;
            }
        };
        if section.height_m.is_none()
            && section.weight_t.is_none()
            && section.width_m.is_none()
            && section.length_m.is_none()
        {
            skipped += 1;
            continue;
        }
        out.push(section);
    }
    Ok((out, skipped))
}

/// The edition date the WFS states for the layer: its capabilities give
/// the abstract "Tronçons de route - BDTOPO® V3 2026-06-15" (read
/// 2026-10-06); the date is what the attribution names.
#[must_use]
pub fn edition(capabilities: &str) -> Option<NaiveDate> {
    // `<Name>BDTOPO_V3:troncon_de_route</Name>`, with or without a prefix.
    let start = capabilities.find(&format!("{LAYER}</"))?;
    let block = &capabilities[start..];
    let end = block.find("FeatureType>").unwrap_or(block.len());
    let block = &block[..end];
    let abstract_start = block.find("Abstract>")?;
    let text = &block[abstract_start..];
    let text = &text[..text.find('<').unwrap_or(text.len())];
    text.split_whitespace()
        .find_map(|word| NaiveDate::parse_from_str(word, "%Y-%m-%d").ok())
}

/// Refuses sections that mostly fall outside France.
fn check_area(sections: &[IgnSection]) -> Result<(), IngestError> {
    let outside = sections
        .iter()
        .filter(|s| {
            s.geometry
                .first()
                .is_none_or(|p| !lunaway_domain::routing::coverage::in_france(*p))
        })
        .count();
    #[allow(
        clippy::cast_precision_loss,
        reason = "counts of sections, far below 2^52"
    )]
    let share = outside as f64 / sections.len().max(1) as f64;
    if share > MAX_OUTSIDE_SHARE {
        return Err(IngestError::Implausible {
            what: format!(
                "BD TOPO: {outside} of {} sections lie outside France (axis order?)",
                sections.len()
            ),
        });
    }
    Ok(())
}

/// What a fetch returned.
#[derive(Debug, Clone)]
pub struct Fetched {
    /// The edition date the WFS states, when it states one.
    pub edition: Option<NaiveDate>,
    /// The sections.
    pub sections: Vec<IgnSection>,
    /// Features skipped by [`parse`].
    pub skipped: usize,
    /// When IGN was read.
    pub fetched_at: DateTime<Utc>,
    /// Whether it came from the cache.
    pub cached: bool,
}

fn page_url(start: usize) -> String {
    let mut url = reqwest::Url::parse(WFS_URL).unwrap_or_else(|_| unreachable!("constant URL"));
    url.query_pairs_mut()
        .append_pair("SERVICE", "WFS")
        .append_pair("VERSION", "2.0.0")
        .append_pair("REQUEST", "GetFeature")
        .append_pair("TYPENAMES", LAYER)
        .append_pair("OUTPUTFORMAT", "application/json")
        .append_pair("SRSNAME", "EPSG:4326")
        .append_pair("CQL_FILTER", FILTER)
        // The server's paging is not transaction-safe (its capabilities say
        // so): a stable order keeps the pages from overlapping.
        .append_pair("SORTBY", "cleabs ASC")
        .append_pair("COUNT", &PAGE.to_string())
        .append_pair("STARTINDEX", &start.to_string());
    url.into()
}

fn gzip(bytes: &[u8]) -> Result<Vec<u8>, IngestError> {
    use std::io::Write as _;
    let mut e = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    e.write_all(bytes)
        .and_then(|()| e.finish())
        .map_err(|source| IngestError::Inflate {
            what: "BD TOPO sections".into(),
            source,
        })
}

fn gunzip(bytes: &[u8]) -> Result<Vec<u8>, IngestError> {
    let mut out = Vec::new();
    flate2::read::GzDecoder::new(bytes)
        .read_to_end(&mut out)
        .map_err(|source| IngestError::Inflate {
            what: "BD TOPO sections".into(),
            source,
        })?;
    Ok(out)
}

/// The restricted sections: the cache unless `refresh`, otherwise every
/// page of the WFS, then cached.
///
/// # Errors
///
/// [`IngestError`] when a page keeps failing, is not GeoJSON, or the cache
/// cannot be written; a fetch that fails writes nothing.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    refresh: bool,
) -> Result<Fetched, IngestError> {
    if !refresh && let Some(c) = cache.read(CACHE_KEY).await? {
        let bytes = gunzip(&c.bytes)?;
        let (sections, skipped) = parse(&bytes)?;
        check_area(&sections)?;
        let edition = cache.read(EDITION_KEY).await?.and_then(|e| {
            NaiveDate::parse_from_str(String::from_utf8_lossy(&e.bytes).trim(), "%Y-%m-%d").ok()
        });
        return Ok(Fetched {
            edition,
            sections,
            skipped,
            fetched_at: c.fetched_at,
            cached: true,
        });
    }
    let capabilities_url = format!("{WFS_URL}?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetCapabilities");
    let capabilities = with_retry("bd topo capabilities", RetryPolicy::PATIENT, || async {
        let response = http
            .get(&capabilities_url)
            .timeout(Duration::from_secs(300))
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: capabilities_url.clone(),
                source,
            })?;
        let response = check_status(&capabilities_url, response).await?;
        read_capped(&capabilities_url, response, MAX_CAPABILITIES_BYTES).await
    })
    .await?;
    let edition = edition(&String::from_utf8_lossy(&capabilities));
    tracing::info!(?edition, "BD TOPO edition the WFS serves");
    let mut features: Vec<serde_json::Value> = Vec::new();
    let mut matched: Option<usize> = None;
    for page in 0..MAX_PAGES {
        if page > 0 {
            tokio::time::sleep(PACE).await;
        }
        // The next page starts after what was received, whatever page size
        // the server applied.
        let url = page_url(features.len());
        let bytes = with_retry("bd topo page", RetryPolicy::PATIENT, || async {
            let response = http
                .get(&url)
                .timeout(Duration::from_secs(300))
                .send()
                .await
                .map_err(|source| IngestError::Http {
                    url: url.clone(),
                    source,
                })?;
            let response = check_status(&url, response).await?;
            read_capped(&url, response, MAX_PAGE_BYTES).await
        })
        .await?;
        let mut page_json: serde_json::Value =
            serde_json::from_slice(&bytes).map_err(|source| IngestError::Json {
                what: format!("BD TOPO page {page}"),
                source,
            })?;
        if let Some(n) = page_json
            .get("numberMatched")
            .and_then(serde_json::Value::as_u64)
            .and_then(|n| usize::try_from(n).ok())
        {
            matched = Some(n);
        }
        let got = match page_json.get_mut("features").map(serde_json::Value::take) {
            Some(serde_json::Value::Array(list)) => list,
            _ => {
                return Err(IngestError::Incomplete {
                    what: format!("BD TOPO page {page} (no features)"),
                    expected: PAGE,
                    got: 0,
                });
            }
        };
        let n = got.len();
        if n > PAGE {
            return Err(IngestError::Implausible {
                what: format!("BD TOPO page {page} holds {n} sections, more than the {PAGE} asked"),
            });
        }
        features.extend(got);
        tracing::info!(
            page,
            features = n,
            total = features.len(),
            "BD TOPO page read"
        );
        // Done when the server's count is reached, or, without one, at the
        // first short page.
        let done = matched.map_or(n < PAGE, |m| features.len() >= m || n == 0);
        if done {
            if let Some(m) = matched
                && features.len() != m
            {
                return Err(IngestError::Incomplete {
                    what: "BD TOPO sections".into(),
                    expected: m,
                    got: features.len(),
                });
            }
            let body = serde_json::to_vec(&serde_json::json!({
                "type": "FeatureCollection",
                "features": features,
            }))
            .map_err(|source| IngestError::Json {
                what: "BD TOPO sections".into(),
                source,
            })?;
            let (sections, skipped) = parse(&body)?;
            check_area(&sections)?;
            let fetched_at = cache.write(CACHE_KEY, &gzip(&body)?).await?;
            // An unknown edition is written as such: an older date must not
            // name newer data.
            let text = edition.map(|e| e.to_string()).unwrap_or_default();
            cache.write(EDITION_KEY, text.as_bytes()).await?;
            return Ok(Fetched {
                edition,
                sections,
                skipped,
                fetched_at,
                cached: false,
            });
        }
    }
    Err(IngestError::Incomplete {
        what: "BD TOPO sections (more pages than any real answer)".into(),
        expected: MAX_PAGES * PAGE,
        got: features.len(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_section_reads_with_its_restrictions_and_without_its_altitude() {
        let body = br#"{"type":"FeatureCollection","features":[
          {"type":"Feature","id":"troncon_de_route.1","geometry":{"type":"LineString",
            "coordinates":[[1.2852,45.8466,301.2],[1.2855,45.8462,300.9]]},
           "properties":{"cleabs":"TRONROUT0000000001","restriction_de_hauteur":3.1,
             "restriction_de_poids_total":null,"position_par_rapport_au_sol":"-1",
             "nom_voie_ban_gauche":"Rue Maurice Utrillo","date_modification":"2023-08-27T10:00:00Z"}},
          {"type":"Feature","geometry":{"type":"LineString","coordinates":[[1.0,45.0],[1.1,45.1]]},
           "properties":{"cleabs":"TRONROUT0000000002"}},
          {"type":"Feature","geometry":{"type":"Point","coordinates":[1.0,45.0]},
           "properties":{"cleabs":"TRONROUT0000000003","restriction_de_hauteur":3.0}}
        ]}"#;
        let (sections, skipped) = parse(body).unwrap();
        assert_eq!(skipped, 2, "no restriction, and not a line");
        let s = &sections[0];
        assert_eq!(s.id, "TRONROUT0000000001");
        assert_eq!(s.height_m, Some(3.1));
        assert_eq!(s.weight_t, None);
        assert_eq!(s.ground, Some(-1));
        assert_eq!(s.name.as_deref(), Some("Rue Maurice Utrillo"));
        assert_eq!(s.geometry.len(), 2);
        assert!(
            (s.geometry[0].lat() - 45.8466).abs() < 1e-9,
            "longitude comes first"
        );
        assert!(s.modified_at.is_some());
    }

    #[test]
    fn the_edition_is_read_from_the_layer_s_abstract() {
        // As the Géoplateforme answers (2026-10-06).
        let caps = "<FeatureType><Name>BDTOPO_V3:batiment</Name>\
            <Abstract>Bâtiments \u{2212} BDTOPO® V3 2025-12-15</Abstract></FeatureType>\
            <FeatureType xmlns:BDTOPO_V3=\"http://BDTOPO_V3\"><Name>BDTOPO_V3:troncon_de_route</Name>\
            <Title>BDTOPO : Tronçons de route</Title>\
            <Abstract>Tronçons de route \u{2212} BDTOPO® V3 2026-06-15</Abstract></FeatureType>";
        assert_eq!(edition(caps), NaiveDate::from_ymd_opt(2026, 6, 15));
        assert_eq!(edition("<wfs:Name>other</wfs:Name>"), None);
    }

    #[test]
    fn sections_outside_france_are_refused() {
        let at = |lat, lon| Position::new(lat, lon).unwrap();
        let section = |p: Position| IgnSection {
            id: "x".into(),
            height_m: Some(3.0),
            weight_t: None,
            width_m: None,
            length_m: None,
            ground: None,
            name: None,
            modified_at: None,
            geometry: vec![p, p],
        };
        assert!(check_area(&[section(at(45.8, 1.2))]).is_ok());
        // Latitude and longitude swapped.
        assert!(check_area(&[section(at(1.2, 45.8))]).is_err());
    }

    #[test]
    fn the_page_url_asks_for_restricted_sections_in_a_stable_order() {
        let url = page_url(10_000);
        for part in [
            "STARTINDEX=10000",
            "SORTBY=cleabs+ASC",
            "SRSNAME=EPSG%3A4326",
            "restriction_de_hauteur",
        ] {
            assert!(url.contains(part), "{part} in {url}");
        }
        assert!(url.starts_with("https://data.geopf.fr/"));
    }
}
