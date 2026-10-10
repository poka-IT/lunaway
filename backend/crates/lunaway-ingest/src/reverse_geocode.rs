//! The reverse geocoding of the places no source gives a street or a town
//! (`lunaway addresses`), on Lunaway's own Photon (OpenStreetMap data,
//! ODbL), reached through the backend's Caddy on the loopback like the
//! map's search (`docs/deploy.md`, "Geocoding"): never a third party.
//!
//! A run walks the places due ([`lunaway_db::place_addresses::due`]) in
//! the order of their ids, asks Photon one position at a time at a bounded
//! pace (Photon serves the map's search too), and writes each page under
//! the writers' lock once its answers are in, so no HTTP call holds the
//! lock. What is asked is kept in `place_geocodes`, so a stopped run
//! resumes where the places still lack an answer. The rules of what is
//! kept are `lunaway_domain::place_address`'s.

use std::time::{Duration, Instant};

use lunaway_db::{PgPool, conflation, place_addresses};
use lunaway_domain::{
    PlaceKind, Position,
    place_address::{self, Geocoded, ReverseFeature},
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    IngestError,
    http::{RetryPolicy, check_status, read_capped, with_retry},
};

/// Largest answer accepted: ten features come back in about 4 KB.
const ANSWER_MAX_BYTES: usize = 1024 * 1024;
/// Features asked per position: the nearest within a kilometre, of the
/// layers that carry an address.
const FEATURES: usize = 10;
/// The places read per page, written in one transaction.
const PAGE: i64 = 100;
/// Places in a row whose geocoding failed past its retries after which a
/// run stops: one place a Photon refuses is skipped, a Photon that refuses
/// them all stops the run, as a crawler stops on a source that refuses it.
const FAILURES_IN_A_ROW: u32 = 20;

/// Where and how fast to ask.
#[derive(Debug, Clone)]
pub struct ReverseConfig {
    /// Photon's base URLs (`.../photon/europe`, `.../photon/morocco`),
    /// asked in order until one answers with a feature: Morocco is a
    /// database of its own.
    pub urls: Vec<String>,
    /// Least time between two requests: the default lets 20 a second
    /// through, a few percent of one core of the geocoding server
    /// (median 10 ms, p95 16 ms per request on 2026-10-10, one at a time).
    pub pace: Duration,
    /// How long one request may take.
    pub timeout: Duration,
    /// Retries on a busy or restarting Photon.
    pub retry: RetryPolicy,
}

impl Default for ReverseConfig {
    fn default() -> Self {
        Self {
            urls: Vec::new(),
            pace: Duration::from_millis(50),
            timeout: Duration::from_secs(5),
            retry: RetryPolicy {
                min_delay: Duration::from_secs(2),
                max_delay: Duration::from_secs(30),
                max_retries: 4,
            },
        }
    }
}

/// What a run did.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RunStats {
    /// Places asked.
    pub asked: u64,
    /// Answers with a street (and a house number or not).
    pub with_street: u64,
    /// Answers with a town or a postcode.
    pub with_town: u64,
    /// Places whose address changed.
    pub written: u64,
    /// Places skipped: their geocoding failed past its retries.
    pub failed: u64,
}

#[derive(Deserialize)]
struct Collection {
    #[serde(default)]
    features: Vec<Feature>,
}

#[derive(Deserialize)]
struct Feature {
    geometry: Option<Geometry>,
    #[serde(default)]
    properties: Properties,
}

#[derive(Deserialize)]
struct Geometry {
    coordinates: (f64, f64),
}

#[derive(Deserialize, Default)]
struct Properties {
    #[serde(rename = "type")]
    kind: Option<String>,
    name: Option<String>,
    housenumber: Option<String>,
    street: Option<String>,
    postcode: Option<String>,
    city: Option<String>,
    countrycode: Option<String>,
}

/// The features of a Photon answer, as the domain reads them.
///
/// # Errors
///
/// [`serde_json::Error`] when the answer is not a feature collection.
pub fn parse(bytes: &[u8]) -> Result<Vec<ReverseFeature>, serde_json::Error> {
    let collection: Collection = serde_json::from_slice(bytes)?;
    Ok(collection
        .features
        .into_iter()
        .map(|f| {
            let p = f.properties;
            ReverseFeature {
                kind: p.kind.unwrap_or_default(),
                position: f
                    .geometry
                    .and_then(|g| Position::new(g.coordinates.1, g.coordinates.0).ok()),
                name: p.name,
                house_number: p.housenumber,
                street: p.street,
                postcode: p.postcode,
                city: p.city,
                country_code: p.countrycode,
            }
        })
        .collect())
}

/// The URL of the reverse geocoding of `at` on the Photon at `base`. A
/// private host's asks the house and street layers too: their features
/// carry the town of a home far from any village's point, and
/// `place_address::pick` keeps no street of them.
fn reverse_url(base: &str, at: Position) -> String {
    format!(
        "{}?lat={:.6}&lon={:.6}&limit={FEATURES}&radius={}\
         &layer=house&layer=street&layer=locality&layer=district&layer=city",
        reverse_path(base),
        at.lat(),
        at.lon(),
        place_address::TOWN_RADIUS_M / 1_000.0,
    )
}

/// The reverse geocoding's address without its query: what an error and a
/// log line name, never the position asked.
fn reverse_path(base: &str) -> String {
    format!("{}/reverse", base.trim_end_matches('/'))
}

async fn ask(
    http: &reqwest::Client,
    config: &ReverseConfig,
    base: &str,
    at: Position,
) -> Result<Vec<ReverseFeature>, IngestError> {
    let url = reverse_url(base, at);
    let shown = reverse_path(base);
    let bytes = with_retry("reverse geocoding", config.retry, || async {
        let response = http
            .get(&url)
            .timeout(config.timeout)
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: shown.clone(),
                source: source.without_url(),
            })?;
        let response = check_status(&shown, response).await?;
        read_capped(&shown, response, ANSWER_MAX_BYTES).await
    })
    .await?;
    parse(&bytes).map_err(|source| IngestError::Json {
        what: "a reverse geocoding".to_owned(),
        source,
    })
}

/// The reverse geocoding of a place of `kind` at `at`: the first of the
/// configured Photons that knows a feature near it, each request
/// [`ReverseConfig::pace`] after the one before (`last_request`).
///
/// # Errors
///
/// [`IngestError`] when a Photon fails past its retries or answers what is
/// not a feature collection.
pub async fn geocode(
    http: &reqwest::Client,
    config: &ReverseConfig,
    kind: PlaceKind,
    at: Position,
    last_request: &mut Option<Instant>,
) -> Result<Geocoded, IngestError> {
    let mut last = Vec::new();
    for base in &config.urls {
        if let Some(before) = *last_request
            && let Some(wait) = config.pace.checked_sub(before.elapsed())
        {
            tokio::time::sleep(wait).await;
        }
        *last_request = Some(Instant::now());
        last = ask(http, config, base, at).await?;
        if !last.is_empty() {
            break;
        }
    }
    Ok(place_address::pick(kind, at, &last))
}

/// Geocodes the places due, page by page, until none is left or `budget`
/// is spent: no place is asked whose first request would leave after it,
/// and what the page under way answered is written. A place whose
/// geocoding fails past its retries is skipped (logged by its id, never its
/// position) and asked again at the next run.
///
/// # Errors
///
/// [`IngestError`] when the database fails, or after
/// [`FAILURES_IN_A_ROW`] places failed in a row: what the run wrote
/// before stays, the page under way included.
pub async fn run(
    pool: &PgPool,
    http: &reqwest::Client,
    config: &ReverseConfig,
    budget: Duration,
) -> Result<RunStats, IngestError> {
    let started = Instant::now();
    let mut stats = RunStats::default();
    let mut after = Uuid::nil();
    let mut last_request: Option<Instant> = None;
    let mut in_a_row = 0_u32;
    while started.elapsed() < budget {
        let page = place_addresses::due(pool, after, PAGE).await?;
        let Some(last) = page.last() else {
            break;
        };
        after = last.id;
        let mut answers = Vec::with_capacity(page.len());
        let mut stop = None;
        for place in &page {
            // The next request leaves after the pace's wait: none leaves
            // once the budget is spent.
            let wait =
                last_request.map_or(Duration::ZERO, |l| config.pace.saturating_sub(l.elapsed()));
            if started.elapsed() + wait >= budget {
                break;
            }
            match geocode(http, config, place.kind, place.position, &mut last_request).await {
                Ok(g) => {
                    in_a_row = 0;
                    stats.asked += 1;
                    stats.with_street += u64::from(g.street.is_some());
                    stats.with_town += u64::from(g.city.is_some() || g.postcode.is_some());
                    answers.push((place.id, g));
                }
                Err(error) => {
                    in_a_row += 1;
                    stats.failed += 1;
                    tracing::warn!(place = %place.id, %error, "addresses: a place skipped");
                    if in_a_row >= FAILURES_IN_A_ROW {
                        stop = Some(error);
                        break;
                    }
                }
            }
        }
        let mut tx = conflation::begin_writer(pool).await?;
        for (id, g) in &answers {
            stats.written += u64::from(place_addresses::apply(&mut tx, *id, g).await?);
        }
        tx.commit().await?;
        if let Some(error) = stop {
            tracing::error!(
                in_a_row,
                asked = stats.asked,
                written = stats.written,
                failed = stats.failed,
                "addresses: the geocoder refused every place in a row; the run stops"
            );
            return Err(error);
        }
        tracing::info!(
            asked = stats.asked,
            written = stats.written,
            "addresses: a page of places geocoded"
        );
    }
    Ok(stats)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_photon_answer_becomes_features_nearest_first() {
        let answer = br#"{"type":"FeatureCollection","features":[
            {"type":"Feature","properties":{"type":"house","housenumber":"22","street":"Grande Rue",
              "city":"Viviers","postcode":"07220","countrycode":"FR"},
             "geometry":{"type":"Point","coordinates":[4.6895842,44.4818006]}},
            {"type":"Feature","properties":{"type":"street","name":"Rue de la Gare","city":"Viviers"},
             "geometry":{"type":"Point","coordinates":[4.6899,44.4820]}}]}"#;
        let features = parse(answer).unwrap();
        assert_eq!(features.len(), 2);
        assert_eq!(features[0].kind, "house");
        assert_eq!(features[0].house_number.as_deref(), Some("22"));
        let at = features[0].position.unwrap();
        assert!(
            (at.lat() - 44.481_800_6).abs() < 1e-9,
            "GeoJSON is lon, lat"
        );
        let g = place_address::pick(
            PlaceKind::MotorhomeArea,
            Position::new(44.4818, 4.6896).unwrap(),
            &features,
        );
        assert_eq!(g.street_line().as_deref(), Some("22 Grande Rue"));
    }

    #[test]
    fn the_url_asks_a_kilometre_of_the_address_layers_on_the_loopback_base() {
        let url = reverse_url(
            "http://127.0.0.1:8486/photon/europe/",
            Position::new(44.481_812_3, 4.689_6).unwrap(),
        );
        assert!(
            url.starts_with(
                "http://127.0.0.1:8486/photon/europe/reverse?lat=44.481812&lon=4.689600"
            ),
            "{url}"
        );
        assert!(url.contains("&radius=1&"), "{url}");
        assert!(
            url.contains("layer=house") && url.contains("layer=city"),
            "{url}"
        );
    }
}
