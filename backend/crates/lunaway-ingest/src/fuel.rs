//! Fuel prices, the live feed of the French ministry of the economy
//! (data.gouv.fr dataset "Prix des carburants en France - Flux instantané -
//! v2", Licence Ouverte 2.0), joined to the fuel stations of the POI layer
//! by the station's id in the feed (OSM `ref:FR:prix-carburants`).
//!
//! The feed is refreshed every 10 minutes at the source; the export of
//! data.economie.gouv.fr harvests it every 15 minutes (dataset page on
//! data.gouv.fr, note of 22/05/2026), so a poll every 15 minutes sees every
//! change. One poll is one request: the whole export, restricted with
//! `select=` to the fields read (about 11.5 MB of JSON for 9 846 stations
//! on 2026-10-06). The latest answer is cached under a single key, so a
//! poller never fills the disk.
//!
//! Per station: the price and update time of each fuel sold, the fuels it
//! is out of (temporarily or for good, with the start the feed gives), the
//! services it lists (gas bottles, laundry, showers, cash machine), whether
//! a card machine sells fuel day and night, and whether it is on a
//! motorway. The tiles show whether it sells LPG
//! ([`FuelStation::sells_lpg`]).

use std::{collections::BTreeSet, time::Duration};

use chrono::{DateTime, Utc};
use lunaway_db::{PgPool, pois::NewJoin};
use lunaway_domain::{
    Position, SourceId,
    poi::{FuelKind, FuelPrice, FuelShortage, FuelStation, FuelTile, ShortageKind},
};

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    store::{JoinStoreReport, store_joins},
};

/// The export endpoint of the dataset on data.economie.gouv.fr.
pub const EXPORT_URL: &str = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/exports/json";

/// The fields read, sent as `select=`: the export otherwise carries the
/// opening hours, regions and labels the layer does not use.
pub const SELECT: &str = "id,latitude,longitude,cp,ville,adresse,pop,\
gazole_prix,gazole_maj,gazole_rupture_debut,gazole_rupture_type,\
sp95_prix,sp95_maj,sp95_rupture_debut,sp95_rupture_type,\
e10_prix,e10_maj,e10_rupture_debut,e10_rupture_type,\
sp98_prix,sp98_maj,sp98_rupture_debut,sp98_rupture_type,\
e85_prix,e85_maj,e85_rupture_debut,e85_rupture_type,\
gplc_prix,gplc_maj,gplc_rupture_debut,gplc_rupture_type,\
carburants_rupture_temporaire,carburants_rupture_definitive,\
horaires_automate_24_24,services_service";

/// Where the latest answer is kept, overwritten by every poll.
const CACHE_KEY: &str = "fuel/prix-carburants-latest.json";

/// Largest answer accepted. The export weighed 11.5 MB on 2026-10-06; the
/// client takes no compressed transfer, so this leaves room for the feed to
/// grow fourfold.
const ANSWER_MAX_BYTES: usize = 48 * 1024 * 1024;

/// Prices outside this range, in euros per litre, are typos and dropped.
const PLAUSIBLE_PRICE_EUR: std::ops::RangeInclusive<f64> = 0.1..=10.0;

/// Most services kept for one station: the feed lists about twenty kinds.
const MAX_SERVICES: usize = 40;

/// The fuels of the feed: the domain's kind, the prefix of its columns,
/// and its name in the shortage lists.
struct FuelColumns {
    kind: FuelKind,
    price: &'static str,
    updated: &'static str,
    since: &'static str,
    shortage: &'static str,
    label: &'static str,
}

const FUELS: [FuelColumns; 6] = [
    FuelColumns {
        kind: FuelKind::Diesel,
        price: "gazole_prix",
        updated: "gazole_maj",
        since: "gazole_rupture_debut",
        shortage: "gazole_rupture_type",
        label: "Gazole",
    },
    FuelColumns {
        kind: FuelKind::Sp95,
        price: "sp95_prix",
        updated: "sp95_maj",
        since: "sp95_rupture_debut",
        shortage: "sp95_rupture_type",
        label: "SP95",
    },
    FuelColumns {
        kind: FuelKind::E10,
        price: "e10_prix",
        updated: "e10_maj",
        since: "e10_rupture_debut",
        shortage: "e10_rupture_type",
        label: "E10",
    },
    FuelColumns {
        kind: FuelKind::Sp98,
        price: "sp98_prix",
        updated: "sp98_maj",
        since: "sp98_rupture_debut",
        shortage: "sp98_rupture_type",
        label: "SP98",
    },
    FuelColumns {
        kind: FuelKind::E85,
        price: "e85_prix",
        updated: "e85_maj",
        since: "e85_rupture_debut",
        shortage: "e85_rupture_type",
        label: "E85",
    },
    FuelColumns {
        kind: FuelKind::Lpg,
        price: "gplc_prix",
        updated: "gplc_maj",
        since: "gplc_rupture_debut",
        shortage: "gplc_rupture_type",
        label: "GPLc",
    },
];

/// Where and how to poll the feed.
#[derive(Debug, Clone)]
pub struct FuelConfig {
    /// The export endpoint ([`EXPORT_URL`]); `select=` is added to it.
    pub url: String,
    /// Retries on a transient failure. Few and short: a poll that fails
    /// waits for the next one rather than piling up behind it.
    pub retry: RetryPolicy,
}

impl FuelConfig {
    /// Two retries, 10 s then up to a minute apart.
    pub const POLL_RETRY: RetryPolicy = RetryPolicy {
        min_delay: Duration::from_secs(10),
        max_delay: Duration::from_secs(60),
        max_retries: 2,
    };
}

impl Default for FuelConfig {
    fn default() -> Self {
        Self {
            url: EXPORT_URL.to_owned(),
            retry: Self::POLL_RETRY,
        }
    }
}

/// One station as the adapter read it.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedStation {
    /// Its id in the feed, as a decimal number without leading zeros: the
    /// key OSM `ref:FR:prix-carburants` points to.
    pub key: String,
    /// What the feed says of it.
    pub station: FuelStation,
    /// The row as the feed sent it.
    pub raw: serde_json::Value,
}

/// What a parse produced.
#[derive(Debug, Default)]
pub struct ParsedFuel {
    /// Rows in the answer.
    pub rows: usize,
    /// One per station kept.
    pub stations: Vec<ParsedStation>,
    /// Rows without a usable id, or listed twice.
    pub skipped: usize,
}

fn text<'a>(row: &'a serde_json::Value, key: &str) -> Option<&'a str> {
    row.get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

fn instant(row: &serde_json::Value, key: &str) -> Option<DateTime<Utc>> {
    text(row, key).and_then(|s| {
        DateTime::parse_from_rfc3339(s)
            .ok()
            .map(|d| d.with_timezone(&Utc))
    })
}

/// A coordinate of the feed: a string of hundred-thousandths of a degree
/// (`"4365100"` is 43.651).
fn degrees(row: &serde_json::Value, key: &str) -> Option<f64> {
    let raw = row.get(key)?;
    let n = match raw {
        serde_json::Value::String(s) => s.trim().parse::<f64>().ok()?,
        serde_json::Value::Number(n) => n.as_f64()?,
        _ => return None,
    };
    Some(n / 100_000.0)
}

/// The fuels a `;` list names (`"SP95;GPLc"`).
fn listed(row: &serde_json::Value, key: &str) -> Vec<&'static str> {
    let Some(list) = text(row, key) else {
        return Vec::new();
    };
    FUELS
        .iter()
        .map(|f| f.label)
        .filter(|label| {
            list.split(';')
                .any(|item| item.trim().eq_ignore_ascii_case(label))
        })
        .collect()
}

/// Reads one row of the export; `None` when it has no usable id.
#[must_use]
pub fn station_of(row: &serde_json::Value) -> Option<(String, FuelStation)> {
    let id = row
        .get("id")
        .and_then(serde_json::Value::as_i64)
        .filter(|id| *id > 0)?;
    let temporary = listed(row, "carburants_rupture_temporaire");
    let definitive = listed(row, "carburants_rupture_definitive");
    let mut prices = Vec::new();
    let mut shortages = Vec::new();
    for f in &FUELS {
        let price = row
            .get(f.price)
            .and_then(serde_json::Value::as_f64)
            .filter(|p| p.is_finite() && PLAUSIBLE_PRICE_EUR.contains(p));
        if let (Some(price_eur), Some(updated_at)) = (price, instant(row, f.updated)) {
            prices.push(FuelPrice {
                fuel: f.kind,
                price_eur,
                updated_at,
            });
        }
        // The per-fuel column first; the lists name the fuels out of stock
        // when it is empty.
        let kind = match text(row, f.shortage) {
            Some("temporaire") => Some(ShortageKind::Temporary),
            Some("definitive") => Some(ShortageKind::Definitive),
            _ if temporary.contains(&f.label) => Some(ShortageKind::Temporary),
            _ if definitive.contains(&f.label) => Some(ShortageKind::Definitive),
            _ => None,
        };
        if let Some(kind) = kind {
            shortages.push(FuelShortage {
                fuel: f.kind,
                kind,
                since: instant(row, f.since),
            });
        }
    }
    let services: Vec<String> = row
        .get("services_service")
        .and_then(serde_json::Value::as_array)
        .map(|list| {
            list.iter()
                .filter_map(serde_json::Value::as_str)
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
                .collect::<BTreeSet<_>>()
                .into_iter()
                .take(MAX_SERVICES)
                .collect()
        })
        .unwrap_or_default();
    let position = degrees(row, "latitude")
        .zip(degrees(row, "longitude"))
        .and_then(|(lat, lon)| Position::new(lat, lon).ok())
        // A station at 0,0 is a station without coordinates.
        .filter(|p| p.lat() != 0.0 || p.lon() != 0.0);
    let mut station = FuelStation {
        prices,
        shortages,
        services,
        automate_24_24: text(row, "horaires_automate_24_24") == Some("Oui"),
        highway: text(row, "pop") == Some("A"),
        position,
        tile: FuelTile::default(),
    };
    station.tile = FuelTile {
        lpg: station.sells_lpg(),
    };
    Some((id.to_string(), station))
}

/// Reads the export (a JSON array of stations).
///
/// # Errors
///
/// [`IngestError::Json`] when the body is not a JSON array.
pub fn parse(body: &[u8]) -> Result<ParsedFuel, IngestError> {
    let rows: Vec<serde_json::Value> =
        serde_json::from_slice(body).map_err(|source| IngestError::Json {
            what: "fuel price export".into(),
            source,
        })?;
    let mut out = ParsedFuel {
        rows: rows.len(),
        ..ParsedFuel::default()
    };
    let mut seen = BTreeSet::new();
    for raw in rows {
        match station_of(&raw) {
            Some((key, station)) if seen.insert(key.clone()) => {
                out.stations.push(ParsedStation { key, station, raw });
            }
            _ => out.skipped += 1,
        }
    }
    Ok(out)
}

/// The export URL with the fields read.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] when `base` is not a URL.
pub fn request_url(base: &str) -> Result<String, IngestError> {
    let mut url = reqwest::Url::parse(base).map_err(|error| {
        tracing::error!(%error, url = base, "the configured URL does not parse");
        IngestError::UntrustedUrl {
            url: base.to_owned(),
            reason: "not a URL",
        }
    })?;
    url.query_pairs_mut().append_pair("select", SELECT);
    Ok(url.into())
}

/// The export, from the network unless `refresh` is false and an answer is
/// cached; the answer is cached either way.
///
/// # Errors
///
/// [`IngestError`] when the export keeps failing or the cache fails.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    config: &FuelConfig,
    refresh: bool,
) -> Result<(Vec<u8>, DateTime<Utc>, bool), IngestError> {
    if !refresh && let Some(c) = cache.read(CACHE_KEY).await? {
        tracing::info!(key = CACHE_KEY, "fuel prices read from the cache");
        return Ok((c.bytes, c.fetched_at, true));
    }
    let url = request_url(&config.url)?;
    let url = url.as_str();
    let body = with_retry("fuel prices", config.retry, || async {
        // Asked compressed: 1.9 MB instead of 11.5 MB every quarter of an
        // hour (measured 2026-10-06). The client is built without its own
        // decompression, so this request decodes what it asked for.
        let response = http
            .get(url)
            .header(reqwest::header::ACCEPT_ENCODING, "gzip")
            .send()
            .await
            .map_err(|source| IngestError::Http {
                url: url.to_owned(),
                source,
            })?;
        let response = check_status(url, response).await?;
        let gzipped = response
            .headers()
            .get(reqwest::header::CONTENT_ENCODING)
            .and_then(|v| v.to_str().ok())
            .is_some_and(|v| v.trim().eq_ignore_ascii_case("gzip"));
        let bytes = read_capped(url, response, ANSWER_MAX_BYTES).await?;
        if gzipped {
            inflate(url, &bytes)
        } else {
            Ok(bytes)
        }
    })
    .await?;
    let fetched_at = cache.write(CACHE_KEY, &body).await?;
    Ok((body, fetched_at, false))
}

/// Inflates a gzip answer, reading at most [`ANSWER_MAX_BYTES`]: a small
/// answer that inflates without end is refused, not held.
fn inflate(url: &str, gzipped: &[u8]) -> Result<Vec<u8>, IngestError> {
    use std::io::Read as _;
    let mut out = Vec::new();
    let limit = u64::try_from(ANSWER_MAX_BYTES).unwrap_or(u64::MAX);
    flate2::read::GzDecoder::new(gzipped)
        .take(limit + 1)
        .read_to_end(&mut out)
        .map_err(|source| IngestError::Inflate {
            what: url.to_owned(),
            source,
        })?;
    if out.len() > ANSWER_MAX_BYTES {
        return Err(IngestError::TooLarge {
            url: url.to_owned(),
            limit: ANSWER_MAX_BYTES,
        });
    }
    Ok(out)
}

/// What an import of the feed did.
#[derive(Debug, Clone)]
pub struct FuelReport {
    /// Whether the answer came from the cache.
    pub cached: bool,
    /// When the answer was fetched.
    pub fetched_at: DateTime<Utc>,
    /// Rows in the answer.
    pub rows: usize,
    /// Stations stored.
    pub stations: usize,
    /// Rows without a usable id, or listed twice.
    pub skipped: usize,
    /// Stations that sell LPG.
    pub lpg: usize,
    /// What the store did.
    pub store: JoinStoreReport,
}

/// Polls the feed and stores every station as a joined row of
/// `prix-carburants`; stations the feed no longer lists are retired.
///
/// # Errors
///
/// [`IngestError`] when the fetch, the parse or a write fails.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    config: &FuelConfig,
    refresh: bool,
) -> Result<FuelReport, IngestError> {
    let (body, fetched_at, cached) = fetch(http, cache, config, refresh).await?;
    // About 11 MB of JSON: off the async threads.
    let parsed = tokio::task::spawn_blocking(move || parse(&body))
        .await
        .map_err(IngestError::Blocking)??;
    let data: Vec<serde_json::Value> = parsed
        .stations
        .iter()
        .map(|s| serde_json::to_value(&s.station))
        .collect::<Result<_, _>>()
        .map_err(|source| IngestError::Json {
            what: "fuel station".into(),
            source,
        })?;
    let rows: Vec<NewJoin<'_>> = parsed
        .stations
        .iter()
        .zip(&data)
        .map(|(s, data)| NewJoin {
            key: &s.key,
            data,
            raw: &s.raw,
            fetched_at,
        })
        .collect();
    let store = store_joins(pool, &SourceId::FUEL_PRICES, &rows).await?;
    let lpg = parsed
        .stations
        .iter()
        .filter(|s| s.station.tile.lpg)
        .count();
    tracing::info!(
        stations = parsed.stations.len(),
        lpg,
        changed = store.upsert.upsert.changed,
        tile_changes = store.upsert.tile_changes,
        retired = store.retired,
        "fuel prices stored"
    );
    Ok(FuelReport {
        cached,
        fetched_at,
        rows: parsed.rows,
        stations: parsed.stations.len(),
        skipped: parsed.skipped,
        lpg,
        store,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_gzip_answer_inflates_within_its_bound() {
        use std::io::Write as _;
        let mut z = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        z.write_all(b"[{\"id\": 1}]").unwrap();
        let small = z.finish().unwrap();
        assert_eq!(inflate("u", &small).unwrap(), b"[{\"id\": 1}]");
        let mut bomb = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::best());
        bomb.write_all(&vec![b' '; ANSWER_MAX_BYTES + 1]).unwrap();
        let bomb = bomb.finish().unwrap();
        assert!(bomb.len() < 1024 * 1024, "a few kilobytes on the wire");
        assert!(matches!(
            inflate("u", &bomb),
            Err(IngestError::TooLarge { .. })
        ));
        assert!(matches!(
            inflate("u", b"not gzip"),
            Err(IngestError::Inflate { .. })
        ));
    }

    #[test]
    fn coordinates_are_hundred_thousandths_of_a_degree() {
        let row = serde_json::json!({"latitude": "4365100", "longitude": "-269000"});
        assert_eq!(degrees(&row, "latitude"), Some(43.651));
        assert_eq!(degrees(&row, "longitude"), Some(-2.69));
        assert_eq!(degrees(&row, "missing"), None);
    }

    #[test]
    fn the_lists_name_fuels_without_a_column() {
        let row = serde_json::json!({
            "id": 1,
            "carburants_rupture_temporaire": "E85; GPLc",
            "carburants_rupture_definitive": "SP95",
        });
        let (_, s) = station_of(&row).unwrap();
        let shortages: Vec<(FuelKind, ShortageKind)> =
            s.shortages.iter().map(|x| (x.fuel, x.kind)).collect();
        assert_eq!(
            shortages,
            [
                (FuelKind::Sp95, ShortageKind::Definitive),
                (FuelKind::E85, ShortageKind::Temporary),
                (FuelKind::Lpg, ShortageKind::Temporary),
            ]
        );
        assert!(s.tile.lpg, "out of LPG for now still sells it");
    }

    #[test]
    fn an_implausible_price_is_dropped() {
        let row = serde_json::json!({
            "id": 2,
            "gazole_prix": 189.9,
            "gazole_maj": "2026-10-06T08:30:00+00:00",
            "e10_prix": 1.799,
        });
        let (_, s) = station_of(&row).unwrap();
        assert!(
            s.prices.is_empty(),
            "a price in cents is a typo, a price without its date unusable"
        );
        assert!(station_of(&serde_json::json!({"id": 0})).is_none());
        assert!(station_of(&serde_json::json!({"id": "x"})).is_none());
    }
}
