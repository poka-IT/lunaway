//! Establishments from Overture Maps Places (`docs/data-sources.md`,
//! "Establishments from Overture Maps Places"): the shops, services and
//! venues OpenStreetMap lacks, read at a high confidence and written as
//! points of interest outside the map tiles (`in_tiles` false), under the
//! source `overture`.
//!
//! A run finds the release in Overture's STAC catalogue (the `latest` one
//! unless told), the GeoParquet files whose box reaches the countries it
//! covers (Europe of the extracts and Morocco, about 4.7 GB), downloads
//! each once into the cache (resumed, never again for the same release),
//! and reads them a row group at a time ([`parquet`]). A place is kept
//! when ([`select`]):
//!
//! - it lies in a country of the run;
//! - Overture is sure it exists ([`MIN_CONFIDENCE`]) and does not say it
//!   closed;
//! - a dataset whose categories Lunaway measured against OpenStreetMap
//!   says it ([`DATASETS`]), and every dataset that says it is under a
//!   licence the places database can take ([`LICENCES`]);
//! - its taxonomy maps to a kind ([`categories`]);
//! - it has a name and a street address: a place with a town alone stands
//!   at the town's centre, or for a business with no shop;
//! - its name does not say it comes to the customer ([`comes_to_you`]).
//!
//! A kept place that a live point of OpenStreetMap already has (a close
//! name within 150 m, or the same family within 50 m, [`TWIN_RULE`]) is
//! not written, and is retired if an earlier run wrote it. What the
//! release no longer holds is retired too, country by country, once every
//! file is read. A run that stops (a crash, the memory cap) starts again
//! after the last file it stored.

pub mod categories;
pub mod parquet;

use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
    time::Duration,
};

use chrono::{DateTime, Utc};
use lunaway_db::{
    PgPool,
    pois::{Candidate, TwinRule},
    records::UpsertStats,
};
use lunaway_domain::{
    Position, SourceId,
    poi::{PoiKind, PoiRecord},
    record::Address,
};
use serde::{Deserialize, Serialize};

use self::parquet::Place;
use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    osm_extract::{self, Coverage, Refresh},
    poi_osm::FetchedPoi,
    store::{self, Retirement},
};

/// Overture's STAC catalogue: the releases, their files and their boxes.
pub const STAC_URL: &str = "https://stac.overturemaps.org";

/// The hosts Overture serves its files from: its S3 bucket over HTTPS, and
/// its Azure mirror (`assets.aws`, `assets.azure` of each STAC item).
pub const ASSET_HOSTS: &[&str] = &[
    "overturemaps-us-west-2.s3.us-west-2.amazonaws.com",
    "overturemapswestus2.blob.core.windows.net",
];

/// The confidence a place must reach. Measured on the eleven town centres
/// of `docs/data-sources.md`: of Meta's places at 0.99 and above,
/// OpenStreetMap had 62 % under a close name, and agreed on the family of
/// 91 % of them; from 0.95 to 0.99, 41 % and 85 %; from 0.90 to 0.95,
/// 26 % and 83 %. Below 0.95 a place is less often one a mapper saw.
pub const MIN_CONFIDENCE: f64 = 0.95;

/// The datasets whose word makes a place: Meta, AllThePlaces (the brands'
/// own store lists), PinMeTo and DAC (the brands' listings). Left out:
/// BrightQuery (company registers: a registered office, filed under a
/// trade it does not sell to the public; 158,891 of its 405,463 places of
/// Germany at 0.9 and above sit at exactly 0.95), Microsoft (76 %
/// agreement with OpenStreetMap's family), and the datasets not measured
/// yet (Krick, RenderSEO). Foursquare's are left out by their licence
/// ([`LICENCES`]).
pub const DATASETS: &[&str] = &["meta", "AllThePlaces", "PinMeTo", "DAC"];

/// The licences a dataset may carry for a place to be read, as Overture
/// writes them (SPDX): CDLA Permissive 2.0 asks only that its text go with
/// the data, CC0 nothing. Foursquare's Apache 2.0 asks for its full
/// NOTICE with every copy, and none of its places reached 0.9 in France or
/// Germany.
pub const LICENCES: &[&str] = &["CDLA-Permissive-2.0", "CC0-1.0"];

/// When a point of OpenStreetMap is the same business as a place: a name
/// of trigram similarity 0.4 or more within 150 m, or the same family
/// within 50 m. Measured on 273,379 places of France (`docs/data-sources.md`).
pub const TWIN_RULE: TwinRule = TwinRule {
    name_radius_m: 150.0,
    min_similarity: 0.4,
    family_radius_m: 50.0,
};

/// The countries and areas a run covers by default: those of the European
/// extracts ([`osm_extract::EUROPE`]) and Morocco, where many motorhomes
/// spend the winter (the basemap and the geocoder cover it).
#[must_use]
pub fn default_coverage() -> BTreeSet<String> {
    osm_extract::EUROPE
        .iter()
        .filter_map(|name| osm_extract::extract(name))
        .flat_map(|spec| spec.covers.iter().map(|c| (*c).to_owned()))
        .chain(std::iter::once("MA".to_owned()))
        .collect()
}

/// Which copy of the files a run downloads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Mirror {
    /// Overture's S3 bucket, over HTTPS (`assets.aws`).
    #[default]
    Aws,
    /// Overture's Azure mirror (`assets.azure`).
    Azure,
}

impl Mirror {
    fn asset(self) -> &'static str {
        match self {
            Self::Aws => "aws",
            Self::Azure => "azure",
        }
    }
}

/// How a run reads Overture.
#[derive(Debug, Clone)]
pub struct OvertureConfig {
    /// The STAC catalogue ([`STAC_URL`]).
    pub stac: String,
    /// The release to read; the catalogue's `latest` when `None`.
    pub release: Option<String>,
    /// Which copy of the files to download.
    pub mirror: Mirror,
    /// The hosts a file may come from ([`ASSET_HOSTS`]).
    pub asset_hosts: Vec<String>,
    /// The areas the run covers, by their codes ([`default_coverage`]).
    pub coverage: BTreeSet<String>,
    /// [`MIN_CONFIDENCE`].
    pub min_confidence: f64,
    /// [`TWIN_RULE`].
    pub twins: TwinRule,
    /// Retries of a request or a download.
    pub retry: RetryPolicy,
    /// Wait between two requests to the catalogue.
    pub pace: Duration,
}

impl Default for OvertureConfig {
    fn default() -> Self {
        Self {
            stac: STAC_URL.to_owned(),
            release: None,
            mirror: Mirror::Aws,
            asset_hosts: ASSET_HOSTS.iter().map(|h| (*h).to_owned()).collect(),
            coverage: default_coverage(),
            min_confidence: MIN_CONFIDENCE,
            twins: TWIN_RULE,
            retry: RetryPolicy::PATIENT,
            pace: Duration::from_secs(1),
        }
    }
}

/// Why a place is not written.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Skip {
    /// No identifier: nothing to update it by later.
    Id,
    /// No usable position.
    Position,
    /// In no area of the run.
    Outside,
    /// Below the confidence of the run.
    Confidence,
    /// Overture says it closed, for a while or for good.
    Closed,
    /// A dataset under a licence the database does not take.
    Licence,
    /// No dataset of [`DATASETS`] says it.
    Dataset,
    /// Its taxonomy maps to no kind.
    Category,
    /// No name.
    Name,
    /// No street address.
    Street,
    /// Its name says it comes to the customer.
    ComesToYou,
}

impl Skip {
    /// A word for the report.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Id => "id",
            Self::Position => "position",
            Self::Outside => "outside",
            Self::Confidence => "confidence",
            Self::Closed => "closed",
            Self::Licence => "licence",
            Self::Dataset => "dataset",
            Self::Category => "category",
            Self::Name => "name",
            Self::Street => "street",
            Self::ComesToYou => "comes to you",
        }
    }
}

/// The phrases of a name that say the business comes to the customer, in
/// the languages of the coverage, folded. Measured on France: 56 of the
/// 501,797 places at 0.9 and above named so, home help and care services,
/// mobile opticians, mechanics and hairdressers.
const COMES_TO_YOU: &[&str] = &[
    "a dom",
    "a domicile",
    "a domicilio",
    "aan huis",
    "ao domicilio",
    "at home",
    "domicile",
    "domicilio",
    "itinerant",
    "itinerante",
    "mobile coiffure",
    "mobiler friseur",
    "zu hause",
];

/// Whether a name says the business comes to the customer (`Coiffure à
/// domicile`, `Mobiler Friseur`): its address is then a home, or an
/// office no customer visits.
#[must_use]
pub fn comes_to_you(name: &str) -> bool {
    let words = format!(" {} ", lunaway_domain::conflation::normalize::fold(name));
    COMES_TO_YOU
        .iter()
        .any(|phrase| words.contains(&format!(" {phrase} ")))
}

/// What a run keeps of a place, as its raw payload: the columns read, as
/// compact JSON.
fn raw_payload(p: &Place) -> Result<Box<serde_json::value::RawValue>, IngestError> {
    let sources: Vec<serde_json::Value> = p
        .sources
        .iter()
        .map(|s| {
            serde_json::json!({
                "dataset": s.dataset,
                "license": s.license,
                "record_id": s.record_id,
                "update_time": s.update_time,
            })
        })
        .collect();
    let value = serde_json::json!({
        "id": p.id,
        "version": p.version,
        "lon": p.lon,
        "lat": p.lat,
        "confidence": p.confidence,
        "names": {"primary": p.name},
        "brand": {"names": {"primary": p.brand}, "wikidata": p.brand_wikidata},
        "basic_category": p.basic_category,
        "taxonomy": {"primary": p.category, "hierarchy": p.hierarchy},
        "operating_status": p.operating_status,
        "phones": p.phones,
        "websites": p.websites,
        "addresses": p.address.as_ref().map(|a| vec![serde_json::json!({
            "freeform": a.freeform,
            "locality": a.locality,
            "postcode": a.postcode,
            "region": a.region,
            "country": a.country,
        })]),
        "sources": sources,
    });
    serde_json::value::to_raw_value(&value).map_err(|source| IngestError::Json {
        what: format!("the payload of overture place {}", p.id),
        source,
    })
}

/// A website Lunaway may link to: HTTP or HTTPS only.
fn website(url: &str) -> Option<String> {
    let lower = url.to_ascii_lowercase();
    (lower.starts_with("https://") || lower.starts_with("http://")).then(|| url.to_owned())
}

/// The point a place becomes, or why it does not, by the rules of the
/// module; `coverage` holds the areas of the run.
///
/// # Errors
///
/// [`Skip`] says why the place is left out.
pub fn select(
    p: &Place,
    coverage: &BTreeSet<String>,
    min_confidence: f64,
) -> Result<(PoiRecord, String), Skip> {
    if p.id.is_empty() {
        return Err(Skip::Id);
    }
    let position = match (p.lat, p.lon) {
        (Some(lat), Some(lon)) => Position::new(lat, lon).map_err(|_| Skip::Position)?,
        _ => return Err(Skip::Position),
    };
    let country = lunaway_domain::region::country_at(position);
    let scope = osm_extract::scope_of(position, country).ok_or(Skip::Outside)?;
    if !coverage.contains(&scope) {
        return Err(Skip::Outside);
    }
    if p.confidence.is_none_or(|c| c < min_confidence) {
        return Err(Skip::Confidence);
    }
    if p.operating_status.as_deref().is_some_and(|s| s != "open") {
        return Err(Skip::Closed);
    }
    let datasets = || {
        p.sources
            .iter()
            .filter(|s| s.dataset.as_deref() != Some("Overture"))
    };
    if datasets().any(|s| s.license.as_deref().is_none_or(|l| !LICENCES.contains(&l))) {
        return Err(Skip::Licence);
    }
    if !datasets().any(|s| s.dataset.as_deref().is_some_and(|d| DATASETS.contains(&d))) {
        return Err(Skip::Dataset);
    }
    let kind = if p.hierarchy.is_empty() {
        categories::kind_of(p.category.as_slice())
    } else {
        categories::kind_of(&p.hierarchy)
    }
    .ok_or(Skip::Category)?;
    let name = p.name.clone().ok_or(Skip::Name)?;
    let street = p
        .address
        .as_ref()
        .and_then(|a| a.freeform.clone())
        .ok_or(Skip::Street)?;
    if comes_to_you(&name) {
        return Err(Skip::ComesToYou);
    }
    let mut record = PoiRecord::new(kind, position);
    record.name = Some(name);
    record.brand = p.brand.clone();
    record.phone = p.phones.first().cloned();
    record.website = p.websites.iter().find_map(|w| website(w));
    record.address = Address {
        street: Some(street),
        postcode: p.address.as_ref().and_then(|a| a.postcode.clone()),
        city: p.address.as_ref().and_then(|a| a.locality.clone()),
        // The country the position lies in, as for OpenStreetMap: the one
        // a source writes may be its own office's.
        country_code: country.map(str::to_owned),
        city_code: None,
    };
    Ok((record, scope))
}

/// One file of a release.
#[derive(Debug, Clone, PartialEq)]
pub struct ReleaseFile {
    /// Its name in the release (`part-00007-...zstd.parquet`).
    pub name: String,
    /// Where to download it.
    pub url: String,
    /// Its size, as the catalogue gives it.
    pub size: Option<u64>,
    /// The box of its places, `[south, west, north, east]`.
    pub bbox: [f64; 4],
}

#[derive(Debug, Deserialize)]
struct Catalog {
    latest: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Collection {
    #[serde(default)]
    links: Vec<Link>,
}

#[derive(Debug, Deserialize)]
struct Link {
    rel: String,
    href: String,
}

#[derive(Debug, Deserialize)]
struct Item {
    /// `[west, south, east, north]`.
    bbox: Vec<f64>,
    #[serde(default)]
    assets: BTreeMap<String, Asset>,
}

#[derive(Debug, Deserialize)]
struct Asset {
    href: String,
    #[serde(rename = "file:size")]
    size: Option<u64>,
}

/// Most bytes a catalogue answer may have: the root catalogue weighs 14
/// KB, an item 3 KB.
const STAC_MAX_BYTES: usize = 4 * 1024 * 1024;

/// Whether a release name is one Overture writes (`2026-09-23.1`): it
/// becomes a directory of the cache and a part of URLs.
#[must_use]
pub fn valid_release(release: &str) -> bool {
    let (date, n) = release.split_once('.').unwrap_or((release, ""));
    let digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    let parts: Vec<&str> = date.split('-').collect();
    parts.len() == 3 && parts.iter().all(|p| digits(p)) && (n.is_empty() || digits(n))
}

/// Whether a file name is one a release holds: letters, digits, dots,
/// dashes and underscores, ending in `.parquet`. It becomes a file of the
/// cache.
fn valid_file_name(name: &str) -> bool {
    !name.starts_with('.')
        && name.ends_with(".parquet")
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-' | b'_'))
}

async fn get_json<T: serde::de::DeserializeOwned>(
    http: &reqwest::Client,
    url: &str,
    retry: RetryPolicy,
) -> Result<T, IngestError> {
    let bytes = with_retry("overture catalogue", retry, || async {
        let response = http
            .get(url)
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: url.to_owned(),
                source,
            })?;
        let response = check_status(url, response).await?;
        read_capped(url, response, STAC_MAX_BYTES).await
    })
    .await?;
    serde_json::from_slice(&bytes).map_err(|source| IngestError::Json {
        what: url.to_owned(),
        source,
    })
}

/// The URL of a file a catalogue item gives, parsed as the client parses
/// it before a request, and its file name: on a host of `hosts`, with no
/// user information, under the name of a Parquet file; `None` otherwise.
/// Reading the host off the text would let `https://evil.example\@host/`
/// through, which the client sends to `evil.example`. The client speaks
/// HTTPS only ([`crate::http::client`]).
fn asset_url(href: &str, hosts: &[String]) -> Option<(String, String)> {
    let url = reqwest::Url::parse(href).ok()?;
    if !matches!(url.scheme(), "https" | "http")
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return None;
    }
    let host = url.host_str()?;
    if !hosts.iter().any(|h| h == host) {
        return None;
    }
    let name = url.path_segments()?.next_back()?.to_owned();
    valid_file_name(&name).then(|| (url.to_string(), name))
}

/// The release the run reads, and the files of its places whose box
/// reaches the areas of the run.
///
/// # Errors
///
/// [`IngestError`] when the catalogue does not answer, names no release, or
/// gives a file on a host or under a name the run does not accept.
pub async fn release_files(
    http: &reqwest::Client,
    config: &OvertureConfig,
) -> Result<(String, Vec<ReleaseFile>), IngestError> {
    let stac = config.stac.trim_end_matches('/');
    let release = match &config.release {
        Some(r) => r.clone(),
        None => {
            let catalog: Catalog =
                get_json(http, &format!("{stac}/catalog.json"), config.retry).await?;
            catalog.latest.ok_or_else(|| IngestError::Implausible {
                what: "the Overture catalogue names no latest release".into(),
            })?
        }
    };
    if !valid_release(&release) {
        return Err(IngestError::Implausible {
            what: format!("{release:?} is not a release name"),
        });
    }
    let base = format!("{stac}/{release}/places/place/");
    let collection: Collection =
        get_json(http, &format!("{base}collection.json"), config.retry).await?;
    let mut files = Vec::new();
    for link in collection.links.iter().filter(|l| l.rel == "item") {
        // An item of the place collection, on the catalogue's own host.
        if !link.href.starts_with(&base) || !link.href.ends_with(".json") {
            return Err(IngestError::UntrustedUrl {
                url: link.href.clone(),
                reason: "an item outside the release's place collection",
            });
        }
        tokio::time::sleep(config.pace).await;
        let item: Item = get_json(http, &link.href, config.retry).await?;
        let [west, south, east, north] = item.bbox[..] else {
            return Err(IngestError::Implausible {
                what: format!("{} has no box", link.href),
            });
        };
        let bbox = [south, west, north, east];
        if !parquet::box_reaches(bbox, &config.coverage) {
            continue;
        }
        let asset =
            item.assets
                .get(config.mirror.asset())
                .ok_or_else(|| IngestError::Implausible {
                    what: format!("{} has no {} asset", link.href, config.mirror.asset()),
                })?;
        let (url, name) = asset_url(&asset.href, &config.asset_hosts).ok_or_else(|| {
            IngestError::UntrustedUrl {
                url: asset.href.clone(),
                reason: "not a Parquet file on a host Overture publishes its files on",
            }
        })?;
        files.push(ReleaseFile {
            name,
            url,
            size: asset.size,
            bbox,
        });
    }
    Ok((release, files))
}

/// A file of the release on disk.
#[derive(Debug, Clone)]
pub struct LocalFile {
    /// Its name in the release.
    pub name: String,
    /// Where it is.
    pub path: PathBuf,
    /// When it was downloaded.
    pub fetched_at: DateTime<Utc>,
    /// Whether it was already in the cache.
    pub cached: bool,
}

/// The cache key of a file of `release`.
fn file_key(release: &str, name: &str) -> String {
    format!("overture/{release}/{name}")
}

/// Downloads `file` of `release` into the cache, unless it is there: a
/// release never changes, so a file is downloaded once. A download cut
/// half way resumes.
///
/// # Errors
///
/// [`IngestError`] when the download fails or the file is not the size the
/// catalogue gives (it is removed, and downloaded again next time).
pub async fn fetch_file(
    http: &reqwest::Client,
    cache: &Cache,
    release: &str,
    file: &ReleaseFile,
    retry: RetryPolicy,
) -> Result<LocalFile, IngestError> {
    let got = osm_extract::fetch(
        http,
        cache,
        &file.url,
        &file_key(release, &file.name),
        retry,
        Refresh::Never,
    )
    .await?;
    let size = tokio::fs::metadata(&got.path)
        .await
        .map_err(|source| IngestError::Cache {
            path: got.path.clone(),
            source,
        })?
        .len();
    if let Some(expected) = file.size
        && expected != size
    {
        let _ = tokio::fs::remove_file(&got.path).await;
        return Err(IngestError::Incomplete {
            what: format!("overture file {} (bytes)", file.name),
            expected: usize::try_from(expected).unwrap_or(usize::MAX),
            got: usize::try_from(size).unwrap_or(usize::MAX),
        });
    }
    Ok(LocalFile {
        name: file.name.clone(),
        path: got.path,
        fetched_at: got.fetched_at,
        cached: got.cached,
    })
}

/// What one file of a run gave.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FileReport {
    /// The file.
    pub name: String,
    /// Whether it came from the cache.
    pub cached: bool,
    /// Whether a run that stopped had already stored it.
    pub resumed: bool,
    /// Row groups of the file.
    pub groups: usize,
    /// Row groups read.
    pub groups_read: usize,
    /// Places in the row groups read.
    pub rows: u64,
    /// Places left out, by reason.
    pub skipped: BTreeMap<Skip, u64>,
    /// Places kept by the rules.
    pub candidates: u64,
    /// Kept places OpenStreetMap already has.
    pub twins: u64,
    /// The places written, by kind.
    pub kinds: BTreeMap<PoiKind, u64>,
    /// What the store did.
    pub upsert: UpsertStats,
}

/// What a run did.
#[derive(Debug, Clone, PartialEq)]
pub struct Report {
    /// The release read.
    pub release: String,
    /// Each file, in order.
    pub files: Vec<FileReport>,
    /// What was retired, and the areas left alone.
    pub retirement: Retirement,
}

/// The progress of a run, kept in the cache between its files.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
struct RunState {
    release: String,
    coverage: Vec<String>,
    files: Vec<String>,
    done: Vec<String>,
}

fn state_key(release: &str) -> String {
    format!("overture/runs/{release}.json")
}

fn seen_key(release: &str, file: &str) -> String {
    format!("overture/runs/{release}-{file}.seen")
}

/// Row groups waiting between the reading thread and the writer, each as
/// the few thousand places it kept of its 20,000 or so: the reader stays
/// at most two row groups ahead, which bounds the memory.
const CHANNEL_DEPTH: usize = 2;

/// What the writer keeps of a run: the ids written, by area.
#[derive(Default)]
struct Seen {
    by_scope: BTreeMap<String, Vec<String>>,
}

impl Seen {
    fn add(&mut self, scope: &str, id: String) {
        match self.by_scope.get_mut(scope) {
            Some(ids) => ids.push(id),
            None => {
                self.by_scope.insert(scope.to_owned(), vec![id]);
            }
        }
    }

    fn counts(&self) -> BTreeMap<String, usize> {
        self.by_scope
            .iter()
            .map(|(s, v)| (s.clone(), v.len()))
            .collect()
    }

    fn lines(&self) -> String {
        let mut out = String::new();
        for (scope, ids) in &self.by_scope {
            for id in ids {
                out.push_str(scope);
                out.push('\t');
                out.push_str(id);
                out.push('\n');
            }
        }
        out
    }
}

/// Reads one file and writes what it keeps; returns its report and the
/// ids it wrote, by area.
async fn store_file(
    pool: &PgPool,
    file: &LocalFile,
    config: &OvertureConfig,
) -> Result<(FileReport, Seen), IngestError> {
    let (tx, mut rx) =
        tokio::sync::mpsc::channel::<(Vec<FetchedPoi>, Vec<String>, BTreeMap<Skip, u64>)>(
            CHANNEL_DEPTH,
        );
    let path = file.path.clone();
    let coverage = config.coverage.clone();
    let min_confidence = config.min_confidence;
    let fetched_at = file.fetched_at;
    let reader = tokio::task::spawn_blocking(move || {
        parquet::read_places(&path, &coverage, |places| {
            let mut kept = Vec::new();
            let mut scopes = Vec::new();
            let mut skipped: BTreeMap<Skip, u64> = BTreeMap::new();
            for p in places {
                match select(&p, &coverage, min_confidence) {
                    Ok((record, scope)) => {
                        kept.push(FetchedPoi {
                            external_id: p.id.clone(),
                            external_url: None,
                            record,
                            raw: raw_payload(&p)?,
                            fetched_at,
                        });
                        scopes.push(scope);
                    }
                    Err(reason) => *skipped.entry(reason).or_default() += 1,
                }
            }
            // The writer is gone only when it failed: the reading stops,
            // and the writer's error is the one the run reports.
            if tx.blocking_send((kept, scopes, skipped)).is_err() {
                return Err(IngestError::Implausible {
                    what: "the writer of the places stopped".into(),
                });
            }
            Ok(())
        })
    });
    let mut report = FileReport {
        name: file.name.clone(),
        cached: file.cached,
        ..FileReport::default()
    };
    let mut seen = Seen::default();
    while let Some((kept, scopes, skipped)) = rx.recv().await {
        for (reason, n) in skipped {
            *report.skipped.entry(reason).or_default() += n;
        }
        report.candidates += kept.len() as u64;
        let candidates: Vec<Candidate<'_>> = kept
            .iter()
            .map(|p| Candidate {
                position: p.record.position,
                name: p.record.name.as_deref().unwrap_or_default(),
                kind: p.record.kind,
            })
            .collect();
        let twins =
            lunaway_db::pois::twins(pool, &SourceId::OSM, &candidates, config.twins).await?;
        drop(candidates);
        // A place without its answer would be neither written nor seen, and
        // retired at the end.
        if twins.len() != kept.len() {
            return Err(IngestError::Incomplete {
                what: "the lookup of OpenStreetMap's twins".into(),
                expected: kept.len(),
                got: twins.len(),
            });
        }
        let mut written = Vec::with_capacity(kept.len());
        for ((p, scope), twin) in kept.into_iter().zip(scopes).zip(twins) {
            if twin {
                report.twins += 1;
                continue;
            }
            *report.kinds.entry(p.record.kind).or_default() += 1;
            seen.add(&scope, p.external_id.clone());
            written.push(p);
        }
        let upsert =
            store::upsert_pois_by_country(pool, &SourceId::OVERTURE, &written, false).await?;
        report.upsert += upsert;
    }
    let counts = reader.await.map_err(IngestError::Blocking)??;
    report.groups = counts.groups;
    report.groups_read = counts.read;
    report.rows = counts.rows;
    Ok((report, seen))
}

/// Reads `files` of `release` and writes what they keep, then retires
/// the places of the run's areas they no longer hold. Resumes after the
/// files a stopped run of the same release and areas stored.
///
/// # Errors
///
/// [`IngestError`] when a file does not read or a write fails; the files
/// stored before stay, and the next run resumes after them.
pub async fn import_files(
    pool: &PgPool,
    cache: &Cache,
    release: &str,
    files: &[LocalFile],
    config: &OvertureConfig,
) -> Result<Report, IngestError> {
    // A run that read nothing would retire every area it covers.
    if files.is_empty() {
        return Err(IngestError::Implausible {
            what: format!("no file of the release {release} reaches the run's countries"),
        });
    }
    let names: Vec<String> = files.iter().map(|f| f.name.clone()).collect();
    let coverage: Vec<String> = config.coverage.iter().cloned().collect();
    let fresh = RunState {
        release: release.to_owned(),
        coverage: coverage.clone(),
        files: names.clone(),
        done: Vec::new(),
    };
    let mut state = match cache.read(&state_key(release)).await? {
        Some(c) => match serde_json::from_slice::<RunState>(&c.bytes) {
            Ok(s) if s.files == names && s.coverage == coverage => s,
            _ => fresh,
        },
        None => fresh,
    };
    let mut ids: Vec<String> = Vec::new();
    let mut by_scope: BTreeMap<String, usize> = BTreeMap::new();
    let mut reports = Vec::with_capacity(files.len());
    let mut oldest: Option<DateTime<Utc>> = None;
    for file in files {
        oldest = Some(oldest.map_or(file.fetched_at, |o| o.min(file.fetched_at)));
        let key = seen_key(release, &file.name);
        if state.done.contains(&file.name)
            && let Some(cached) = cache.read(&key).await?
        {
            let text = String::from_utf8_lossy(&cached.bytes);
            for (scope, id) in text.lines().filter_map(|l| l.split_once('\t')) {
                *by_scope.entry(scope.to_owned()).or_default() += 1;
                ids.push(id.to_owned());
            }
            tracing::info!(file = file.name, "already stored by this run");
            reports.push(FileReport {
                name: file.name.clone(),
                cached: file.cached,
                resumed: true,
                ..FileReport::default()
            });
            continue;
        }
        tracing::info!(file = file.name, path = %file.path.display(), "reading the file");
        let (report, seen) = store_file(pool, file, config).await?;
        cache.write(&key, seen.lines().as_bytes()).await?;
        state.done.retain(|d| d != &file.name);
        state.done.push(file.name.clone());
        let bytes = serde_json::to_vec_pretty(&state).map_err(|source| IngestError::Json {
            what: "overture run state".into(),
            source,
        })?;
        cache.write(&state_key(release), &bytes).await?;
        for (scope, n) in seen.counts() {
            *by_scope.entry(scope).or_default() += n;
        }
        ids.extend(seen.by_scope.into_values().flatten());
        tracing::info!(
            file = report.name,
            rows = report.rows,
            candidates = report.candidates,
            twins = report.twins,
            inserted = report.upsert.inserted,
            changed = report.upsert.changed,
            "file stored"
        );
        reports.push(report);
    }
    let at = oldest.unwrap_or_else(Utc::now);
    let reads: BTreeMap<String, DateTime<Utc>> =
        config.coverage.iter().map(|s| (s.clone(), at)).collect();
    let retirement = store::retire_pois_in_coverage(
        pool,
        &SourceId::OVERTURE,
        &Coverage::Countries(config.coverage.clone()),
        &ids,
        &by_scope,
        &reads,
        at,
        false,
    )
    .await?;
    cache.remove(&state_key(release)).await?;
    for file in files {
        cache.remove(&seen_key(release, &file.name)).await?;
    }
    Ok(Report {
        release: release.to_owned(),
        files: reports,
        retirement,
    })
}

/// Removes from the cache the files of every release but `keep`, and what
/// a stopped run of one left under `overture/runs/`: a run reads one
/// release, and each weighs some 4.7 GB.
///
/// # Errors
///
/// [`IngestError::Cache`] when the directory cannot be listed or a release
/// removed.
pub async fn prune_releases(cache: &Cache, keep: &str) -> Result<Vec<String>, IngestError> {
    let dir = cache.root().join("overture");
    let io = |path: PathBuf| move |source| IngestError::Cache { path, source };
    let mut entries = match tokio::fs::read_dir(&dir).await {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(source) => return Err(IngestError::Cache { path: dir, source }),
    };
    let mut removed = Vec::new();
    while let Some(entry) = entries.next_entry().await.map_err(io(dir.clone()))? {
        let name = entry.file_name().to_string_lossy().into_owned();
        // Only a release's directory, whose name the run checked.
        if name == keep || !valid_release(&name) {
            continue;
        }
        let path = entry.path();
        if entry.file_type().await.map_err(io(path.clone()))?.is_dir() {
            tokio::fs::remove_dir_all(&path).await.map_err(io(path))?;
            removed.push(name);
        }
    }
    let runs = dir.join("runs");
    let mut entries = match tokio::fs::read_dir(&runs).await {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(removed),
        Err(source) => return Err(IngestError::Cache { path: runs, source }),
    };
    while let Some(entry) = entries.next_entry().await.map_err(io(runs.clone()))? {
        let name = entry.file_name().to_string_lossy().into_owned();
        // `<release>.json` and `<release>-<file>.seen`, of another release.
        let mine = name.starts_with(&format!("{keep}.")) || name.starts_with(&format!("{keep}-"));
        let path = entry.path();
        if !mine && entry.file_type().await.map_err(io(path.clone()))?.is_file() {
            tokio::fs::remove_file(&path).await.map_err(io(path))?;
        }
    }
    Ok(removed)
}

/// Imports the release of `config`: the catalogue, the files of the run's
/// areas (downloaded once), the places they keep, the retirement of what
/// they no longer hold; then removes the files of older releases from the
/// cache.
///
/// # Errors
///
/// [`IngestError`] when the catalogue, a download, a read or a write fails.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &OvertureConfig,
) -> Result<Report, IngestError> {
    let (release, files) = release_files(http, config).await?;
    tracing::info!(release, files = files.len(), "overture release");
    let mut local = Vec::with_capacity(files.len());
    for f in &files {
        local.push(fetch_file(http, cache, &release, f, config.retry).await?);
    }
    let report = import_files(pool, cache, &release, &local, config).await?;
    for old in prune_releases(cache, &release).await? {
        tracing::info!(
            release = old,
            "files of an older release removed from the cache"
        );
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn place() -> Place {
        Place {
            id: "08f1".into(),
            lon: Some(-0.0765),
            lat: Some(47.2598),
            confidence: Some(0.98),
            websites: vec!["https://salon.example".into()],
            phones: vec!["+33241000000".into()],
            brand: None,
            brand_wikidata: None,
            address: Some(parquet::PlaceAddress {
                freeform: Some("12 Rue d'Orléans".into()),
                locality: Some("Saumur".into()),
                postcode: Some("49400".into()),
                region: None,
                country: Some("FR".into()),
            }),
            name: Some("Coiff'Annie".into()),
            sources: vec![
                parquet::PlaceSource {
                    dataset: Some("meta".into()),
                    license: Some("CDLA-Permissive-2.0".into()),
                    record_id: Some("1".into()),
                    update_time: None,
                },
                parquet::PlaceSource {
                    dataset: Some("Overture".into()),
                    license: Some("CDLA-Permissive-2.0".into()),
                    record_id: None,
                    update_time: None,
                },
            ],
            operating_status: None,
            basic_category: Some("personal_or_beauty_service".into()),
            category: Some("hair_salon".into()),
            hierarchy: vec![
                "lifestyle_services".into(),
                "personal_or_beauty_service".into(),
                "hair_salon".into(),
            ],
            version: Some(3),
        }
    }

    fn france() -> BTreeSet<String> {
        ["FR".to_owned(), "MC".to_owned()].into()
    }

    #[test]
    fn a_named_salon_with_a_street_in_france_is_kept() {
        let (r, scope) = select(&place(), &france(), MIN_CONFIDENCE).unwrap();
        assert_eq!(scope, "FR");
        assert_eq!(r.kind, PoiKind::Hairdresser);
        assert_eq!(r.name.as_deref(), Some("Coiff'Annie"));
        assert_eq!(r.phone.as_deref(), Some("+33241000000"));
        assert_eq!(r.website.as_deref(), Some("https://salon.example"));
        assert_eq!(r.address.street.as_deref(), Some("12 Rue d'Orléans"));
        assert_eq!(r.address.city.as_deref(), Some("Saumur"));
        assert_eq!(r.address.country_code.as_deref(), Some("FR"));
    }

    #[test]
    fn each_rule_leaves_its_places_out() {
        let skip = |change: &dyn Fn(&mut Place)| {
            let mut p = place();
            change(&mut p);
            select(&p, &france(), MIN_CONFIDENCE).err()
        };
        assert_eq!(
            skip(&|p| p.id = String::new()),
            Some(Skip::Id),
            "two places without an id would be one row"
        );
        assert_eq!(
            skip(&|p| p.confidence = Some(0.94)),
            Some(Skip::Confidence),
            "below the measured confidence"
        );
        assert_eq!(skip(&|p| p.confidence = None), Some(Skip::Confidence));
        assert_eq!(
            skip(&|p| p.operating_status = Some("permanently_closed".into())),
            Some(Skip::Closed)
        );
        assert_eq!(
            skip(&|p| p.operating_status = Some("temporarily_closed".into())),
            Some(Skip::Closed)
        );
        assert_eq!(skip(&|p| p.operating_status = Some("open".into())), None);
        assert_eq!(
            skip(&|p| p.sources[0].license = Some("Apache-2.0".into())),
            Some(Skip::Licence),
            "Foursquare's licence asks for its NOTICE with every copy"
        );
        assert_eq!(
            skip(&|p| p.sources[0].dataset = Some("BrightQuery".into())),
            Some(Skip::Dataset),
            "a company register says where an office is, not a shop"
        );
        assert_eq!(
            skip(&|p| p.hierarchy.push("hair_stylist".into())),
            Some(Skip::Category)
        );
        assert_eq!(skip(&|p| p.name = None), Some(Skip::Name));
        assert_eq!(
            skip(&|p| p.address.as_mut().unwrap().freeform = None),
            Some(Skip::Street),
            "a town alone places it at the town's centre"
        );
        assert_eq!(
            skip(&|p| p.name = Some("Julie Coiffure à domicile".into())),
            Some(Skip::ComesToYou)
        );
        assert_eq!(
            skip(&|p| {
                p.lat = Some(31.63);
                p.lon = Some(-8.0);
            }),
            Some(Skip::Outside),
            "Marrakech, outside a run of France"
        );
        assert_eq!(skip(&|p| p.lat = None), Some(Skip::Position));
        assert_eq!(
            skip(&|p| p.websites = vec!["ftp://x".into()]),
            None,
            "a website of another scheme is dropped, not the place"
        );
    }

    #[test]
    fn a_name_that_comes_to_the_customer_reads_so_in_every_language() {
        for name in [
            "Coiffure à domicile by Alison",
            "MECA A DOMICILE",
            "Lunettes A Dom",
            "Peluquería a domicilio Carmen",
            "Mobiler Friseur Sandra",
            "Kapper aan huis",
            "Le Vest'hier itinérant",
        ] {
            assert!(comes_to_you(name), "{name}");
        }
        for name in [
            "Domino's Pizza",
            "Automobiles Dumas",
            "Point Service Mobiles",
            "Atome",
        ] {
            assert!(!comes_to_you(name), "{name}");
        }
    }

    #[test]
    fn the_default_coverage_is_the_european_import_and_morocco() {
        let c = default_coverage();
        for scope in ["FR", "MC", "ES", "IC", "DE", "NO", "SJ", "MA"] {
            assert!(c.contains(scope), "{scope}");
        }
        assert!(!c.contains("EH"), "Western Sahara is no part of it");
    }

    #[test]
    fn a_place_counts_in_the_same_area_for_its_file_and_for_itself() {
        use lunaway_domain::region::{country_at, scope_at};
        for (lat, lon) in [
            (48.85, 2.35),
            (28.1, -15.43),
            (-21.1, 55.5),
            (43.7384, 7.4246),
            (31.63, -8.0),
            (78.22, 15.65),
        ] {
            let p = Position::new(lat, lon).unwrap();
            assert_eq!(
                osm_extract::scope_of(p, country_at(p)).as_deref(),
                scope_at(p),
                "({lat}, {lon}): a file is chosen by the one, a place kept by the other"
            );
        }
    }

    #[test]
    fn the_hosts_of_overture_are_hosts_the_client_follows() {
        let stac = reqwest::Url::parse(STAC_URL).unwrap();
        for h in ASSET_HOSTS.iter().chain(&[stac.host_str().unwrap()]) {
            assert!(
                crate::http::REDIRECT_HOSTS.contains(h),
                "{h}: docs/data-sources.md lists it, and a redirect there would be refused"
            );
        }
    }

    #[test]
    fn release_and_file_names_are_checked_before_they_reach_the_disk() {
        assert!(valid_release("2026-09-23.1"));
        assert!(valid_release("2026-09-23"));
        assert!(!valid_release("../2026-09-23.1"));
        assert!(!valid_release("runs"));
        assert!(valid_file_name(
            "part-00007-61ac23fc-0af6-5d61-8c46-5776ba7e6bf0-c000.zstd.parquet"
        ));
        assert!(!valid_file_name("../x.parquet"));
        assert!(!valid_file_name("x.json"));
        let hosts: Vec<String> = ASSET_HOSTS.iter().map(|h| (*h).to_owned()).collect();
        let s3 = "https://overturemaps-us-west-2.s3.us-west-2.amazonaws.com/release/\
                  2026-09-23.1/theme=places/type=place/part-00007-x-c000.zstd.parquet";
        assert_eq!(
            asset_url(s3, &hosts).map(|(_, name)| name).as_deref(),
            Some("part-00007-x-c000.zstd.parquet")
        );
        for href in [
            "https://evil.example\\@overturemapswestus2.blob.core.windows.net/x.parquet",
            "https://user@overturemapswestus2.blob.core.windows.net/x.parquet",
            "https://overturemapswestus2.blob.core.windows.net.evil.example/x.parquet",
            "https://overturemapswestus2.blob.core.windows.net/x.json",
            "https://overturemapswestus2.blob.core.windows.net/%2e%2e",
            "ftp://overturemapswestus2.blob.core.windows.net/x.parquet",
        ] {
            assert_eq!(asset_url(href, &hosts), None, "{href}");
        }
    }
}
