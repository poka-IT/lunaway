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
    municipalities,
    osm::{self, OverpassConfig, Region},
    store::{StoreReport, store_complete},
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
    /// Pitches folded into their site.
    pub folded_pitches: usize,
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
            folded_pitches: parsed.folded_pitches,
            store,
        });
        if !cached && i + 1 < regions.len() {
            tokio::time::sleep(config.pace).await;
        }
    }
    Ok(out)
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
    /// Campsites the first geocoding pass could not place well enough.
    pub drops: atout_france::GeocodeDrops,
    /// What the second pass placed of them.
    pub second_pass: SecondPassReport,
    /// Records stored.
    pub records: usize,
    /// What the store did.
    pub store: StoreReport,
}

/// What the second geocoding pass placed, of the campsites the first one
/// dropped.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SecondPassReport {
    /// Placed by their address without a locality marker or road number.
    pub by_address: usize,
    /// Placed by a campsite toponym of the same name (IGN BD TOPO).
    pub by_toponym: usize,
    /// Placed at their municipality, flagged approximate.
    pub by_municipality: usize,
    /// Still without a position: not stored.
    pub still_dropped: usize,
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
    let (mut records, drops) =
        atout_france::to_records(&parsed.campsites, &geocoded, csv.fetched_at);
    let placed: std::collections::BTreeSet<&str> =
        records.iter().map(|r| r.external_id.as_str()).collect();
    let dropped: Vec<&atout_france::Campsite> = parsed
        .campsites
        .iter()
        .filter(|c| !placed.contains(c.external_id.as_str()))
        .collect();
    let (more, second_pass) = atout_france_second_pass(
        http,
        cache,
        config,
        &dropped,
        &geocoded,
        csv.fetched_at,
        refresh,
    )
    .await?;
    records.extend(more);
    let store = store_complete(pool, &SourceId::ATOUT_FRANCE, None, &records).await?;
    Ok(AtoutFranceReport {
        cached: csv.cached,
        campsites: parsed.campsites.len(),
        other_kinds: parsed.other_kinds,
        overseas: parsed.overseas,
        duplicates: parsed.duplicates,
        drops,
        second_pass,
        records: records.len(),
        store,
    })
}

/// Pause between two searches of the Géoplateforme's points of interest:
/// one a second, the pace its CSV endpoint announces, far below the fair
/// use its terms set.
const TOPONYM_PACE: Duration = Duration::from_secs(1);

/// The second pass over the campsites the first one dropped: the simplified
/// address, then a campsite toponym of the same name, then the
/// municipality (approximate). See [`atout_france::simplify_address`].
async fn atout_france_second_pass(
    http: &reqwest::Client,
    cache: &Cache,
    config: &AtoutFranceConfig,
    dropped: &[&atout_france::Campsite],
    first_pass: &[geocode::Geocoded],
    fetched_at: chrono::DateTime<chrono::Utc>,
    refresh: bool,
) -> Result<(Vec<crate::FetchedRecord>, SecondPassReport), IngestError> {
    let mut report = SecondPassReport::default();
    let mut records = Vec::new();
    // 1. The address without what the BAN cannot read.
    let queries: Vec<geocode::AddressQuery> = dropped
        .iter()
        .filter_map(|c| {
            atout_france::simplify_address(&c.address).map(|address| geocode::AddressQuery {
                key: c.external_id.clone(),
                address,
                postcode: c.postcode.clone(),
                city: c.city.clone(),
            })
        })
        .collect();
    let simplified = if queries.is_empty() {
        Vec::new()
    } else {
        geocode::geocode(http, cache, &config.geocoder, &queries, refresh).await?
    };
    let by_key: std::collections::BTreeMap<&str, &geocode::Geocoded> =
        simplified.iter().map(|g| (g.key.as_str(), g)).collect();
    let mut left = Vec::new();
    for c in dropped {
        match by_key
            .get(c.external_id.as_str())
            .and_then(|g| atout_france::placement_of(g, Some("simplified_address")))
        {
            Some(p) => {
                records.push(atout_france::record_of(c, p, fetched_at));
                report.by_address += 1;
            }
            None => left.push(*c),
        }
    }
    // 2. A campsite toponym of the same name.
    let mut still = Vec::new();
    for (i, c) in left.iter().enumerate() {
        let (hits, cached) =
            geocode::search_toponyms(http, cache, &config.geocoder, &c.name, &c.postcode, refresh)
                .await?;
        match atout_france::toponym_placement(c, &hits) {
            Some(p) => {
                records.push(atout_france::record_of(c, p, fetched_at));
                report.by_toponym += 1;
            }
            None => still.push(*c),
        }
        if !cached && i + 1 < left.len() {
            tokio::time::sleep(TOPONYM_PACE).await;
        }
    }
    // 3. The municipality, flagged approximate: the first pass's own answer
    // when it found the town, otherwise a search for the town alone.
    let first: std::collections::BTreeMap<&str, &geocode::Geocoded> =
        first_pass.iter().map(|g| (g.key.as_str(), g)).collect();
    let mut towns = Vec::new();
    for c in still {
        match first
            .get(c.external_id.as_str())
            .and_then(|g| atout_france::municipality_placement(g))
        {
            Some(p) => {
                records.push(atout_france::record_of(c, p, fetched_at));
                report.by_municipality += 1;
            }
            None => towns.push(c),
        }
    }
    let town_queries: Vec<geocode::AddressQuery> = towns
        .iter()
        .map(|c| geocode::AddressQuery {
            key: c.external_id.clone(),
            address: String::new(),
            postcode: c.postcode.clone(),
            city: c.city.clone(),
        })
        .collect();
    let town_answers = if town_queries.is_empty() {
        Vec::new()
    } else {
        geocode::geocode(http, cache, &config.geocoder, &town_queries, refresh).await?
    };
    let by_town: std::collections::BTreeMap<&str, &geocode::Geocoded> =
        town_answers.iter().map(|g| (g.key.as_str(), g)).collect();
    for c in towns {
        match by_town
            .get(c.external_id.as_str())
            .and_then(|g| atout_france::municipality_placement(g))
        {
            Some(p) => {
                records.push(atout_france::record_of(c, p, fetched_at));
                report.by_municipality += 1;
            }
            None => report.still_dropped += 1,
        }
    }
    tracing::info!(?report, "atout france second geocoding pass");
    Ok((records, report))
}

/// What an import of the communes did.
#[derive(Debug, Clone, Copy)]
pub struct MunicipalitiesReport {
    /// Whether the file came from the cache.
    pub cached: bool,
    /// Communes stored.
    pub municipalities: u64,
    /// Municipal districts left out.
    pub districts: usize,
    /// Features without a usable code, name or polygon.
    pub skipped: usize,
    /// Live places whose commune changed (each takes a new position in the
    /// change feed).
    pub places_changed: u64,
}

/// Imports the communes and gives every live place the one that covers it,
/// in one writer transaction.
///
/// # Errors
///
/// [`IngestError`] when the download, the file or the database fails;
/// nothing is stored then.
pub async fn municipalities(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    url: &str,
    refresh: bool,
) -> Result<MunicipalitiesReport, IngestError> {
    let download = municipalities::fetch(http, cache, url, refresh).await?;
    let (cached, fetched_at) = (download.cached, download.fetched_at);
    let parsed = tokio::task::spawn_blocking(move || municipalities::parse(&download.body))
        .await
        .map_err(IngestError::Blocking)??;
    let mut tx = lunaway_db::conflation::begin_writer(pool).await?;
    let stats =
        lunaway_db::municipalities::replace_all(&mut tx, &parsed.municipalities, fetched_at)
            .await?;
    tx.commit().await?;
    tracing::info!(
        communes = stats.municipalities,
        places_changed = stats.places_changed,
        "communes stored"
    );
    Ok(MunicipalitiesReport {
        cached,
        municipalities: stats.municipalities,
        districts: parsed.districts,
        skipped: parsed.skipped,
        places_changed: stats.places_changed,
    })
}
