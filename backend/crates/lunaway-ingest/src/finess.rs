//! FINESS, the national register of health and social establishments
//! (data.gouv.fr dataset "FINESS - Structures", the new-generation flow
//! published by the Agence du numérique en santé, Licence Ouverte 2.0),
//! joined to the pharmacies of the POI layer by their FINESS number (OSM
//! `ref:FR:FINESS`, on 92 % of the French pharmacies in OSM,
//! `plan/research/05-poi-sources.md` A.1).
//!
//! What it brings is a closure: FINESS keeps closed establishments, with
//! their state and closure date, so a pharmacy OSM still shows but FINESS
//! lists as inactive is flagged on the map.
//!
//! The file is one JSON document (about 50 MB gzip-compressed, 750 MB
//! decompressed, for the snapshot of September 2026) whose `pmej` array
//! holds the legal entities, each with its geographic establishments
//! (`ege`). It is read as a stream, one legal entity at a time, never whole
//! in memory, and only the establishments whose number a live point
//! carries are kept. The fields read, from the official schema
//! (`flux/out/data.gouv/structure/schema/schema-structures-v1.json` of
//! github.com/ansforge/finess, read 2026-10-06):
//!
//! - `ege[].informationsGeneralesEGE.numFinessEge`: "Numéro FINESS
//!   alphanumérique sur 9 caractères";
//! - `ege[].etatObjet`: "État administratif de l'objet", coded in
//!   TRE-R386 (`A` "Actif", `I` "Inactif", smt.esante.gouv.fr, read
//!   2026-10-06);
//! - `ege[].informationsGeneralesEGE.dateFermeture`, `nomEgeLong`,
//!   `nomEgeCourt`, and `ege[].categorieentiteGeographiqueExercice`
//!   (TRE-R397, `620` "Pharmacie d'Officine").
//!
//! The monthly snapshot (`finess-structures-mensuel-AAAAMM.json.gz`) is
//! read rather than the daily file: a closure is worth a month's delay, and
//! the snapshot keeps its name, so the cache serves it until the next one.

use std::{
    collections::{BTreeSet, HashSet},
    fmt,
    io::Read,
};

use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::{
    PgPool,
    pois::{NewJoin, join_keys},
};
use lunaway_domain::{
    SourceId,
    poi::{FinessEstablishment, FinessTile},
};
use serde::{
    Deserialize, Deserializer,
    de::{DeserializeSeed, IgnoredAny, MapAccess, SeqAccess, Visitor},
};

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    store::{JoinStoreReport, store_joins},
    web::check_host,
};

/// The dataset's description in the data.gouv.fr API.
pub const DATASET_API: &str = "https://www.data.gouv.fr/api/1/datasets/finess-structures-1/";

/// Hosts the dataset's description may come from.
pub const API_HOSTS: &[&str] = &["www.data.gouv.fr"];

/// Hosts the file may be downloaded from: where data.gouv.fr stores its
/// resources; any other location in the metadata is refused.
pub const RESOURCE_HOSTS: &[&str] = &["static.data.gouv.fr", "object.files.data.gouv.fr"];

/// The name every monthly snapshot starts with.
pub const MONTHLY_PREFIX: &str = "finess-structures-mensuel-";

/// Largest description accepted.
const METADATA_MAX_BYTES: usize = 4 * 1024 * 1024;

/// Largest file accepted: the snapshot weighed 50.4 MB on 2026-10-01.
const FILE_MAX_BYTES: usize = 512 * 1024 * 1024;

/// Where and how to read FINESS.
#[derive(Debug, Clone)]
pub struct FinessConfig {
    /// The dataset in the data.gouv.fr API ([`DATASET_API`]).
    pub api: String,
    /// Hosts the description may come from ([`API_HOSTS`]).
    pub api_hosts: Vec<String>,
    /// Hosts the file may come from ([`RESOURCE_HOSTS`]).
    pub resource_hosts: Vec<String>,
    /// Retries on load shedding.
    pub retry: RetryPolicy,
}

impl Default for FinessConfig {
    fn default() -> Self {
        Self {
            api: DATASET_API.to_owned(),
            api_hosts: API_HOSTS.iter().map(|h| (*h).to_owned()).collect(),
            resource_hosts: RESOURCE_HOSTS.iter().map(|h| (*h).to_owned()).collect(),
            retry: RetryPolicy::PATIENT,
        }
    }
}

#[derive(Debug, Deserialize)]
struct Dataset {
    resources: Vec<Resource>,
}

#[derive(Debug, Deserialize)]
struct Resource {
    title: String,
    url: String,
}

/// The newest monthly snapshot among `titles`: `finess-structures-mensuel-`
/// then the year and month, gzip-compressed JSON.
fn newest_monthly<'a>(
    resources: impl IntoIterator<Item = (&'a str, &'a str)>,
) -> Option<(&'a str, &'a str)> {
    resources
        .into_iter()
        .filter(|(title, _)| {
            title
                .strip_prefix(MONTHLY_PREFIX)
                .and_then(|rest| rest.strip_suffix(".json.gz"))
                .is_some_and(|month| month.len() == 6 && month.bytes().all(|b| b.is_ascii_digit()))
        })
        .max_by_key(|(title, _)| *title)
}

/// The snapshot on disk, and when it was fetched.
#[derive(Debug, Clone)]
pub struct Snapshot {
    /// Its file in the cache.
    pub path: std::path::PathBuf,
    /// Its name (`finess-structures-mensuel-202609.json.gz`).
    pub name: String,
    /// When it was fetched.
    pub fetched_at: DateTime<Utc>,
    /// Whether it was already in the cache.
    pub cached: bool,
}

/// The newest monthly snapshot: the cached one unless `refresh`; otherwise
/// the one the dataset's description names, downloaded unless the cache
/// already has it.
///
/// # Errors
///
/// [`IngestError`] when the description or the download fails, names no
/// snapshot, or points to a host the dataset does not publish from.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    config: &FinessConfig,
    refresh: bool,
) -> Result<Snapshot, IngestError> {
    let snapshot = |key: String, name: String, fetched_at, cached| Snapshot {
        path: cache.root().join(key),
        name,
        fetched_at,
        cached,
    };
    if !refresh
        && let Some(key) = cache.latest("finess", MONTHLY_PREFIX).await?
        && let Some(c) = cache.read(&key).await?
    {
        let name = key.trim_start_matches("finess/").to_owned();
        tracing::info!(key, "finess snapshot read from the cache");
        return Ok(snapshot(key, name, c.fetched_at, true));
    }
    let api_hosts: Vec<&str> = config.api_hosts.iter().map(String::as_str).collect();
    let resource_hosts: Vec<&str> = config.resource_hosts.iter().map(String::as_str).collect();
    check_host(&config.api, &api_hosts)?;
    let api = config.api.as_str();
    let dataset: Dataset = with_retry("data.gouv.fr", config.retry, || async {
        let response = http
            .get(api)
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: api.to_owned(),
                source,
            })?;
        let response = check_status(api, response).await?;
        let bytes = read_capped(api, response, METADATA_MAX_BYTES).await?;
        serde_json::from_slice(&bytes).map_err(|source| IngestError::Json {
            what: "finess dataset".into(),
            source,
        })
    })
    .await?;
    let (name, url) = newest_monthly(
        dataset
            .resources
            .iter()
            .map(|r| (r.title.as_str(), r.url.as_str())),
    )
    .ok_or_else(|| IngestError::NoResource {
        dataset: "finess-structures-1".into(),
    })?;
    let (name, url) = (name.to_owned(), url.to_owned());
    let key = format!("finess/{name}");
    if !refresh && let Some(c) = cache.read(&key).await? {
        return Ok(snapshot(key, name, c.fetched_at, true));
    }
    check_host(&url, &resource_hosts)?;
    tracing::info!(%url, "downloading the finess snapshot");
    let body = with_retry("finess snapshot", config.retry, || async {
        let response = http
            .get(url.as_str())
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: url.clone(),
                source,
            })?;
        let response = check_status(&url, response).await?;
        // A redirect may not leave the allowed hosts either.
        check_host(response.url().as_str(), &resource_hosts)?;
        read_capped(&url, response, FILE_MAX_BYTES).await
    })
    .await?;
    let fetched_at = cache.write(&key, &body).await?;
    Ok(snapshot(key, name, fetched_at, false))
}

#[derive(Debug, Deserialize)]
struct Pmej {
    #[serde(default)]
    ege: Vec<Ege>,
}

#[derive(Debug, Deserialize)]
struct Ege {
    #[serde(rename = "informationsGeneralesEGE")]
    info: Option<EgeInfo>,
    #[serde(rename = "categorieentiteGeographiqueExercice")]
    category: Option<String>,
    #[serde(rename = "etatObjet")]
    state: Option<String>,
    #[serde(rename = "dateDerniereMaj")]
    updated: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EgeInfo {
    #[serde(rename = "numFinessEge")]
    number: Option<String>,
    #[serde(rename = "dateFermeture")]
    closed_on: Option<String>,
    #[serde(rename = "nomEgeLong")]
    long_name: Option<String>,
    #[serde(rename = "nomEgeCourt")]
    short_name: Option<String>,
}

/// One establishment kept.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedEstablishment {
    /// Its FINESS number, upper-cased.
    pub key: String,
    /// What FINESS says of it.
    pub establishment: FinessEstablishment,
    /// The fields read, as FINESS wrote them.
    pub raw: serde_json::Value,
}

/// What a read of the snapshot produced.
#[derive(Debug, Default)]
pub struct ParsedFiness {
    /// Establishments in the file.
    pub structures: usize,
    /// Those kept, by number.
    pub establishments: Vec<ParsedEstablishment>,
    /// Numbers listed twice (the first is kept).
    pub duplicates: usize,
}

/// FINESS's spaces padded names, collapsed.
fn clean(s: Option<&str>) -> Option<String> {
    let s = s?.split_whitespace().collect::<Vec<_>>().join(" ");
    (!s.is_empty()).then_some(s)
}

impl ParsedFiness {
    fn take(&mut self, ege: Ege, wanted: &HashSet<String>, seen: &mut BTreeSet<String>) {
        self.structures += 1;
        let Some(info) = ege.info else { return };
        let Some(key) = info
            .number
            .as_deref()
            .map(|n| n.trim().to_ascii_uppercase())
        else {
            return;
        };
        if !wanted.contains(&key) {
            return;
        }
        if !seen.insert(key.clone()) {
            self.duplicates += 1;
            return;
        }
        // Closed only when FINESS says so (`I`, inactive): a missing or
        // unknown state says nothing, and a pharmacy shown "maybe closed"
        // on no evidence would send travellers elsewhere.
        let open = ege.state.as_deref() != Some("I");
        let closed_on = info
            .closed_on
            .as_deref()
            .and_then(|d| NaiveDate::parse_from_str(d.trim(), "%Y-%m-%d").ok());
        let name = clean(info.long_name.as_deref()).or_else(|| clean(info.short_name.as_deref()));
        let raw = serde_json::json!({
            "numFinessEge": info.number,
            "etatObjet": ege.state,
            "dateFermeture": info.closed_on,
            "categorieentiteGeographiqueExercice": ege.category,
            "nomEgeLong": info.long_name,
            "nomEgeCourt": info.short_name,
            "dateDerniereMaj": ege.updated,
        });
        self.establishments.push(ParsedEstablishment {
            key,
            establishment: FinessEstablishment {
                open,
                closed_on,
                category: ege
                    .category
                    .map(|c| c.trim().to_owned())
                    .filter(|c| !c.is_empty()),
                name,
                tile: FinessTile { closed: !open },
            },
            raw,
        });
    }
}

/// The top-level object: only `pmej` is walked, element by element.
struct Document<'a> {
    wanted: &'a HashSet<String>,
    out: &'a mut ParsedFiness,
}

impl<'de> Visitor<'de> for Document<'_> {
    type Value = ();

    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("the FINESS structures document")
    }

    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        let mut seen = BTreeSet::new();
        while let Some(key) = map.next_key::<String>()? {
            if key == "pmej" {
                map.next_value_seed(LegalEntities {
                    wanted: self.wanted,
                    out: &mut *self.out,
                    seen: &mut seen,
                })?;
            } else {
                map.next_value::<IgnoredAny>()?;
            }
        }
        Ok(())
    }
}

/// The `pmej` array, one legal entity in memory at a time.
struct LegalEntities<'a> {
    wanted: &'a HashSet<String>,
    out: &'a mut ParsedFiness,
    seen: &'a mut BTreeSet<String>,
}

impl<'de> DeserializeSeed<'de> for LegalEntities<'_> {
    type Value = ();

    fn deserialize<D: Deserializer<'de>>(self, d: D) -> Result<(), D::Error> {
        d.deserialize_seq(self)
    }
}

impl<'de> Visitor<'de> for LegalEntities<'_> {
    type Value = ();

    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("an array of legal entities")
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<(), A::Error> {
        while let Some(pmej) = seq.next_element::<Pmej>()? {
            for ege in pmej.ege {
                self.out.take(ege, self.wanted, self.seen);
            }
        }
        Ok(())
    }
}

/// Reads a FINESS structures document (decompressed) from `reader`,
/// keeping the establishments whose number is in `wanted` (upper-cased).
///
/// # Errors
///
/// [`IngestError::Json`] when the document is not the FINESS JSON.
pub fn parse(reader: impl Read, wanted: &HashSet<String>) -> Result<ParsedFiness, IngestError> {
    let mut out = ParsedFiness::default();
    let mut de = serde_json::Deserializer::from_reader(std::io::BufReader::new(reader));
    de.deserialize_map(Document {
        wanted,
        out: &mut out,
    })
    .and_then(|()| de.end())
    .map_err(|source| IngestError::Json {
        what: "finess structures".into(),
        source,
    })?;
    Ok(out)
}

/// Reads the gzip-compressed snapshot at `path`. CPU-bound and blocking.
///
/// # Errors
///
/// [`IngestError::Cache`] when the file cannot be opened, and the errors
/// of [`parse`].
pub fn read(path: &std::path::Path, wanted: &HashSet<String>) -> Result<ParsedFiness, IngestError> {
    let file = std::fs::File::open(path).map_err(|source| IngestError::Cache {
        path: path.to_owned(),
        source,
    })?;
    parse(flate2::read::GzDecoder::new(file), wanted)
}

/// What an import of FINESS did.
#[derive(Debug, Clone)]
pub struct FinessReport {
    /// The snapshot read.
    pub file: String,
    /// Whether it came from the cache.
    pub cached: bool,
    /// FINESS numbers live points carry.
    pub wanted: usize,
    /// Establishments in the file.
    pub structures: usize,
    /// Establishments stored.
    pub kept: usize,
    /// Of which FINESS lists as inactive.
    pub closed: usize,
    /// What the store did.
    pub store: JoinStoreReport,
}

/// Reads the newest snapshot and stores, as joined rows of `finess`, the
/// establishments whose number a live point carries; those no point
/// carries any more are retired.
///
/// # Errors
///
/// [`IngestError`] when the fetch, the read or a write fails.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &FinessConfig,
    refresh: bool,
) -> Result<FinessReport, IngestError> {
    let wanted: HashSet<String> = join_keys(pool, &SourceId::FINESS)
        .await?
        .into_iter()
        .map(|k| k.to_ascii_uppercase())
        .collect();
    if wanted.is_empty() {
        tracing::warn!("no live point carries a FINESS number; import the points first");
    }
    let snapshot = fetch(http, cache, config, refresh).await?;
    let path = snapshot.path.clone();
    let wanted_count = wanted.len();
    let parsed = tokio::task::spawn_blocking(move || read(&path, &wanted))
        .await
        .map_err(IngestError::Blocking)??;
    let data: Vec<serde_json::Value> = parsed
        .establishments
        .iter()
        .map(|e| serde_json::to_value(&e.establishment))
        .collect::<Result<_, _>>()
        .map_err(|source| IngestError::Json {
            what: "finess establishment".into(),
            source,
        })?;
    let rows: Vec<NewJoin<'_>> = parsed
        .establishments
        .iter()
        .zip(&data)
        .map(|(e, data)| NewJoin {
            key: &e.key,
            data,
            raw: &e.raw,
            fetched_at: snapshot.fetched_at,
        })
        .collect();
    let store = store_joins(pool, &SourceId::FINESS, &rows).await?;
    let closed = parsed
        .establishments
        .iter()
        .filter(|e| !e.establishment.open)
        .count();
    tracing::info!(
        kept = parsed.establishments.len(),
        closed,
        tile_changes = store.upsert.tile_changes,
        "finess establishments stored"
    );
    Ok(FinessReport {
        file: snapshot.name,
        cached: snapshot.cached,
        wanted: wanted_count,
        structures: parsed.structures,
        kept: parsed.establishments.len(),
        closed,
        store,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_newest_monthly_snapshot_is_chosen() {
        let resources = [
            ("finess-structures-mensuel-202608.json.gz", "a"),
            ("finess-structures-journalier-20261006.json.gz", "b"),
            ("finess-structures-mensuel-202609.json.gz", "c"),
            ("finess-structures-mensuel-2026.json.gz", "d"),
            ("finess-structures-annuel-2026.json.gz", "e"),
        ];
        assert_eq!(
            newest_monthly(resources),
            Some(("finess-structures-mensuel-202609.json.gz", "c"))
        );
        assert_eq!(newest_monthly([("readme.pdf", "x")]), None);
    }

    #[test]
    fn padded_names_are_collapsed() {
        assert_eq!(
            clean(Some("SMUR POLYCLINIQUE AMBERIEU      ")).as_deref(),
            Some("SMUR POLYCLINIQUE AMBERIEU")
        );
        assert_eq!(clean(Some("   ")), None);
    }

    #[test]
    fn a_document_of_another_shape_is_an_error() {
        let wanted = HashSet::new();
        assert!(parse(&b"[1, 2]"[..], &wanted).is_err());
        assert!(parse(&b"{\"pmej\": [{\"ege\": 3}]}"[..], &wanted).is_err());
        let empty = parse(
            &b"{\"schemaVersion\": \"v1.0.0\", \"pmej\": []}"[..],
            &wanted,
        )
        .unwrap();
        assert_eq!(empty.structures, 0);
    }
}
