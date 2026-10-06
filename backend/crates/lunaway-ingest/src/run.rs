//! Whole imports: fetch, map and store a source, with the counts an
//! operator reads to tell whether it went well.

use std::time::Duration;

use lunaway_db::PgPool;
use lunaway_domain::SourceId;

use crate::{
    IngestError, atout_france,
    cache::Cache,
    geocode::{self, GeocoderConfig},
    http::RetryPolicy,
    osm::{self, OverpassConfig, Region},
    osm_extract,
    store::{StoreReport, store_complete, store_whole_source},
};

/// What the import of one OSM region did.
#[derive(Debug, Clone)]
pub struct OsmRegionReport {
    /// The region.
    pub region: Region,
    /// Whether the answer came from the cache.
    pub cached: bool,
    /// Records mapped.
    pub records: usize,
    /// Elements dropped by the mapping.
    pub skipped: usize,
    /// Dump stations folded into their site.
    pub attached_dump_stations: usize,
    /// What the store did.
    pub store: StoreReport,
}

/// Imports `regions` from Overpass, one at a time, pausing between two
/// queries that reached the network. Each region is stored as soon as it is
/// read, so a failure later keeps the regions already done.
///
/// # Errors
///
/// The first [`IngestError`]; the regions before it are stored.
pub async fn osm_regions(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &OverpassConfig,
    regions: &[Region],
    refresh: bool,
) -> Result<Vec<OsmRegionReport>, IngestError> {
    let mut out = Vec::with_capacity(regions.len());
    for (i, region) in regions.iter().enumerate() {
        let payload = osm::fetch_region(http, cache, config, *region, refresh).await?;
        let (cached, fetched_at) = (payload.cached, payload.fetched_at);
        let parsed = tokio::task::spawn_blocking(move || osm::parse(&payload.body, fetched_at))
            .await
            .map_err(IngestError::Blocking)??;
        let store =
            store_complete(pool, &SourceId::OSM, Some(region.code), &parsed.records).await?;
        tracing::info!(
            region = region.code,
            records = parsed.records.len(),
            inserted = store.upsert.inserted,
            changed = store.upsert.changed,
            retired = store.retired,
            "region stored"
        );
        out.push(OsmRegionReport {
            region: *region,
            cached,
            records: parsed.records.len(),
            skipped: parsed.skipped.len(),
            attached_dump_stations: parsed.attached_dump_stations,
            store,
        });
        if !cached && i + 1 < regions.len() {
            tokio::time::sleep(config.pace).await;
        }
    }
    Ok(out)
}

/// What the import of an OSM extract did.
#[derive(Debug, Clone)]
pub struct OsmExtractReport {
    /// Whether the extract was already downloaded.
    pub cached: bool,
    /// Records mapped.
    pub records: usize,
    /// Elements outside the imported area or without coordinates.
    pub skipped: usize,
    /// Dump stations folded into their site.
    pub attached_dump_stations: usize,
    /// What the store did.
    pub store: StoreReport,
}

/// Imports OpenStreetMap from a country extract: download (or the cached
/// file), read on a blocking thread, store as the whole OSM source.
///
/// # Errors
///
/// [`IngestError`] when the download, the read or a write fails.
pub async fn osm_extract(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    url: &str,
    refresh: bool,
) -> Result<OsmExtractReport, IngestError> {
    let extract = osm_extract::fetch(http, cache, url, RetryPolicy::PATIENT, refresh).await?;
    let path = extract.path.clone();
    let fetched_at = extract.fetched_at;
    tracing::info!(path = %path.display(), "reading the extract");
    let parsed = tokio::task::spawn_blocking(move || osm_extract::read(&path, fetched_at))
        .await
        .map_err(IngestError::Blocking)??;
    let store =
        store_whole_source(pool, &SourceId::OSM, osm_extract::SCOPE, &parsed.records).await?;
    Ok(OsmExtractReport {
        cached: extract.cached,
        records: parsed.records.len(),
        skipped: parsed.skipped.len(),
        attached_dump_stations: parsed.attached_dump_stations,
        store,
    })
}

/// What the Atout France import did.
#[derive(Debug, Clone)]
pub struct AtoutFranceReport {
    /// Whether the CSV came from the cache.
    pub cached: bool,
    /// Metropolitan campsites in the CSV.
    pub campsites: usize,
    /// Rows of other kinds of accommodation.
    pub other_kinds: usize,
    /// Overseas campsites, skipped.
    pub overseas: usize,
    /// Rows listed twice.
    pub duplicates: usize,
    /// Campsites the geocoder could not place well enough.
    pub drops: atout_france::GeocodeDrops,
    /// Records stored.
    pub records: usize,
    /// What the store did.
    pub store: StoreReport,
}

/// Where Atout France and the geocoder are.
#[derive(Debug, Clone)]
pub struct AtoutFranceConfig {
    /// The data.gouv.fr API.
    pub data_gouv_api: String,
    /// Hosts the CSV may come from.
    pub resource_hosts: Vec<String>,
    /// The geocoder.
    pub geocoder: GeocoderConfig,
    /// Retries on the data.gouv.fr calls.
    pub retry: RetryPolicy,
}

impl Default for AtoutFranceConfig {
    fn default() -> Self {
        Self {
            data_gouv_api: atout_france::DATA_GOUV_API.to_owned(),
            resource_hosts: atout_france::RESOURCE_HOSTS
                .iter()
                .map(|h| (*h).to_owned())
                .collect(),
            geocoder: GeocoderConfig {
                url: GeocoderConfig::DEFAULT_URL.to_owned(),
                chunk: 1_000,
                pace: Duration::from_secs(2),
                retry: RetryPolicy::PATIENT,
            },
            retry: RetryPolicy::PATIENT,
        }
    }
}

/// Imports the classified campsites: the CSV, its geocoding, the records.
/// `refresh` asks the sources again: the CSV is downloaded and every
/// address geocoded anew.
///
/// # Errors
///
/// [`IngestError`] when a download, the geocoding or a write fails.
pub async fn atout_france(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &AtoutFranceConfig,
    refresh: bool,
) -> Result<AtoutFranceReport, IngestError> {
    let hosts: Vec<&str> = config.resource_hosts.iter().map(String::as_str).collect();
    let csv = atout_france::fetch_csv(
        http,
        cache,
        &config.data_gouv_api,
        &hosts,
        config.retry,
        refresh,
    )
    .await?;
    let parsed = atout_france::parse_csv(&csv.body)?;
    let queries = atout_france::address_queries(&parsed.campsites);
    let geocoded = geocode::geocode(http, cache, &config.geocoder, &queries, refresh).await?;
    let (records, drops) = atout_france::to_records(&parsed.campsites, &geocoded, csv.fetched_at);
    let store = store_complete(pool, &SourceId::ATOUT_FRANCE, None, &records).await?;
    Ok(AtoutFranceReport {
        cached: csv.cached,
        campsites: parsed.campsites.len(),
        other_kinds: parsed.other_kinds,
        overseas: parsed.overseas,
        duplicates: parsed.duplicates,
        drops,
        records: records.len(),
        store,
    })
}
