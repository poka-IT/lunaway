//! OpenStreetMap from a Geofabrik extract (ODbL 1.0, © OpenStreetMap
//! contributors), the import path for a whole country.
//!
//! Overpass serves region queries well when an instance has free slots, but
//! every public instance can shed load for hours, and a country-wide import
//! is what extracts exist for: one download of a file Geofabrik rebuilds
//! daily, read locally, with no load on a shared server. The elements are
//! the ones the Overpass query selects and go through the same mapping
//! ([`crate::osm`]), so both paths produce identical records.
//!
//! The file is read in three parallel passes: tagged nodes, ways and
//! relations; the ways that outline a selected relation; the coordinates of
//! every node those ways reference. A way or relation becomes the centre of
//! its bounding box, as with Overpass's `out bb`.

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::{Path, PathBuf},
    time::Duration,
};

use chrono::{DateTime, Utc};
use osmpbf::{Element as PbfElement, ElementReader, RelMemberType};
use tokio::io::AsyncWriteExt;

use crate::{
    IngestError,
    cache::Cache,
    http::{RetryPolicy, check_status, with_retry},
    osm::{self, Bounds, Element, Parsed, Skip},
};

/// Geofabrik's daily extract of France (mainland and Corsica).
pub const FRANCE_EXTRACT_URL: &str = "https://download.geofabrik.de/europe/france-latest.osm.pbf";

/// The scope of the records an extract import writes: one scope for the
/// whole country, so a run retires what the extract no longer holds.
pub const SCOPE: &str = "FR";

/// Metropolitan France and Corsica with a margin: elements outside are not
/// imported, whatever the extract holds.
const AREA: (f64, f64, f64, f64) = (41.0, -5.8, 51.6, 10.0);

const CACHE_KEY: &str = "osm-extract/france-latest.osm.pbf";

/// A downloaded extract.
#[derive(Debug, Clone)]
pub struct Extract {
    /// Where it is on disk.
    pub path: PathBuf,
    /// When it was downloaded.
    pub fetched_at: DateTime<Utc>,
    /// Whether it was already in the cache.
    pub cached: bool,
}

/// How long a download may go without receiving a byte before it counts as
/// stalled and is resumed.
const STALL: Duration = Duration::from_secs(60);
/// Upper bound of one download attempt; a 5 GB file at a slow 2 MB/s takes
/// under an hour.
const ATTEMPT: Duration = Duration::from_secs(4 * 3600);
/// Largest extract accepted: France weighs 5.9 GB; a server announcing or
/// sending more is not filling the disk.
const MAX_BYTES: u64 = 16 * 1024 * 1024 * 1024;

/// What a partial download was taken from, kept next to it: the URL asked,
/// the URL that answered (a `-latest` URL redirects to a dated file), and the
/// answer's validator (`ETag`, or `Last-Modified` without one). A resume
/// sends the validator in `If-Range`, so a server whose file changed in the
/// meantime sends the new file whole instead of splicing its end onto the
/// old one's start.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Pin {
    asked: String,
    answered: String,
    validator: String,
}

impl Pin {
    fn parse(text: &str) -> Option<Self> {
        let mut lines = text.lines();
        let pin = Self {
            asked: lines.next()?.to_owned(),
            answered: lines.next()?.trim().to_owned(),
            validator: lines.next()?.trim().to_owned(),
        };
        (!pin.validator.is_empty()).then_some(pin)
    }

    fn render(&self) -> String {
        format!("{}\n{}\n{}\n", self.asked, self.answered, self.validator)
    }
}

/// The validator a resume can send in `If-Range`: a strong `ETag` (a weak
/// one may not be used there), else `Last-Modified`.
fn validator(headers: &reqwest::header::HeaderMap) -> Option<String> {
    let value = |name| {
        headers
            .get(name)
            .and_then(|v| v.to_str().ok())
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(str::to_owned)
    };
    value(reqwest::header::ETAG)
        .filter(|e| !e.starts_with("W/"))
        .or_else(|| value(reqwest::header::LAST_MODIFIED))
}

/// The first byte of a `206` answer, from `Content-Range: bytes a-b/n`.
fn range_start(headers: &reqwest::header::HeaderMap) -> Option<u64> {
    headers
        .get(reqwest::header::CONTENT_RANGE)?
        .to_str()
        .ok()?
        .strip_prefix("bytes ")?
        .split('-')
        .next()?
        .parse()
        .ok()
}

/// The extract at `url`: the cached copy unless `refresh`, otherwise a
/// download streamed to disk (the France file weighs about 5 GB). An
/// interrupted or stalled download resumes where it stopped, with an HTTP
/// range request on the file that answered, conditional on its validator
/// ([`Pin`]), so a resume never splices two days of data: Geofabrik
/// redirects `-latest` to a dated file, OpenStreetMap France serves the
/// changing file itself under one URL.
///
/// # Errors
///
/// [`IngestError`] when the download keeps failing or the file cannot be
/// written.
pub async fn fetch(
    http: &reqwest::Client,
    cache: &Cache,
    url: &str,
    retry: RetryPolicy,
    refresh: bool,
) -> Result<Extract, IngestError> {
    let path = cache.root().join(CACHE_KEY);
    if !refresh && let Some(fetched_at) = modified(&path).await? {
        tracing::info!(path = %path.display(), "extract read from the cache");
        return Ok(Extract {
            path,
            fetched_at,
            cached: true,
        });
    }
    let partial = path.with_extension("partial");
    let source_file = path.with_extension("partial.source");
    let io = |source| IngestError::Cache {
        path: partial.clone(),
        source,
    };
    if let Some(dir) = path.parent() {
        tokio::fs::create_dir_all(dir).await.map_err(io)?;
    }
    tracing::info!(%url, "downloading the extract");
    with_retry("osm extract", retry, || async {
        // Resume only a download of the same file, asked for with the same
        // URL and carrying a validator.
        let pin = tokio::fs::read_to_string(&source_file)
            .await
            .ok()
            .as_deref()
            .and_then(Pin::parse)
            .filter(|p| p.asked == url);
        let have = match (&pin, modified(&partial).await?) {
            (Some(_), Some(_)) => tokio::fs::metadata(&partial).await.map_err(io)?.len(),
            _ => 0,
        };
        let pin = pin.filter(|_| have > 0);
        let target = pin
            .as_ref()
            .map_or_else(|| url.to_owned(), |p| p.answered.clone());
        let mut request = http.get(&target).timeout(ATTEMPT);
        if let Some(p) = &pin {
            request = request
                .header(reqwest::header::RANGE, format!("bytes={have}-"))
                .header(reqwest::header::IF_RANGE, p.validator.as_str());
        }
        let response = request.send().await.map_err(|source| IngestError::Http {
            url: target.clone(),
            source,
        })?;
        if response.status() == reqwest::StatusCode::RANGE_NOT_SATISFIABLE {
            // The partial file already holds every byte (the process stopped
            // between the last write and the rename), or more: start over
            // rather than ask for the same range forever.
            let _ = tokio::fs::remove_file(&source_file).await;
            return Err(IngestError::Incomplete {
                what: "osm extract (range not satisfiable)".into(),
                expected: 0,
                got: usize::try_from(have).unwrap_or(usize::MAX),
            });
        }
        let mut response = check_status(&target, response).await?;
        let resumed = response.status() == reqwest::StatusCode::PARTIAL_CONTENT
            && range_start(response.headers()) == Some(have);
        if response.status() == reqwest::StatusCode::PARTIAL_CONTENT && !resumed {
            // Another range than the one asked for: forget the partial file,
            // the next attempt downloads it whole.
            let _ = tokio::fs::remove_file(&source_file).await;
            return Err(IngestError::Incomplete {
                what: "osm extract (range start)".into(),
                expected: usize::try_from(have).unwrap_or(usize::MAX),
                got: range_start(response.headers())
                    .and_then(|n| usize::try_from(n).ok())
                    .unwrap_or(0),
            });
        }
        // The announced size, read before the body: afterwards reqwest
        // reports what is left to read.
        let expected = response
            .content_length()
            .map(|n| if resumed { n + have } else { n });
        if expected.is_some_and(|n| n > MAX_BYTES) {
            return Err(IngestError::TooLarge {
                url: target.clone(),
                limit: usize::try_from(MAX_BYTES).unwrap_or(usize::MAX),
            });
        }
        // The file first, then its pin: a pin naming the new answer beside
        // the bytes of an older one would splice them on the next resume.
        let mut file = if resumed {
            tracing::info!(from = have, "resuming the extract download");
            tokio::fs::OpenOptions::new()
                .append(true)
                .open(&partial)
                .await
                .map_err(io)?
        } else {
            tokio::fs::File::create(&partial).await.map_err(io)?
        };
        // Without a validator a later resume could not tell a changed file
        // from the same one: no pin, so an interruption starts over.
        match validator(response.headers()) {
            Some(validator) => tokio::fs::write(
                &source_file,
                Pin {
                    asked: url.to_owned(),
                    answered: response.url().to_string(),
                    validator,
                }
                .render(),
            )
            .await
            .map_err(io)?,
            None => {
                let _ = tokio::fs::remove_file(&source_file).await;
            }
        }
        let mut written: u64 = if resumed { have } else { 0 };
        loop {
            let next = tokio::time::timeout(STALL, response.chunk())
                .await
                .map_err(|source| IngestError::Stalled {
                    url: target.clone(),
                    source,
                })?;
            let Some(chunk) = next.map_err(|source| IngestError::Http {
                url: target.clone(),
                source,
            })?
            else {
                break;
            };
            written += chunk.len() as u64;
            if written > MAX_BYTES {
                return Err(IngestError::TooLarge {
                    url: target.clone(),
                    limit: usize::try_from(MAX_BYTES).unwrap_or(usize::MAX),
                });
            }
            file.write_all(&chunk).await.map_err(io)?;
        }
        file.flush().await.map_err(io)?;
        if let Some(expected) = expected
            && expected != written
        {
            return Err(IngestError::Incomplete {
                what: "osm extract (bytes)".into(),
                expected: usize::try_from(expected).unwrap_or(usize::MAX),
                got: usize::try_from(written).unwrap_or(usize::MAX),
            });
        }
        Ok(())
    })
    .await?;
    tokio::fs::rename(&partial, &path).await.map_err(io)?;
    // The pin only matters while a partial file exists.
    let _ = tokio::fs::remove_file(&source_file).await;
    let fetched_at = modified(&path).await?.unwrap_or_else(Utc::now);
    Ok(Extract {
        path,
        fetched_at,
        cached: false,
    })
}

async fn modified(path: &Path) -> Result<Option<DateTime<Utc>>, IngestError> {
    match tokio::fs::metadata(path).await {
        Ok(m) => Ok(Some(DateTime::<Utc>::from(m.modified().map_err(
            |source| IngestError::Cache {
                path: path.to_owned(),
                source,
            },
        )?))),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(source) => Err(IngestError::Cache {
            path: path.to_owned(),
            source,
        }),
    }
}

/// A coordinate at OSM's precision (1e-7 degree). The PBF decoder computes
/// `1e-9 * granularity * units`, which leaves a tail in the last bits; the
/// division below returns the number nearest to the seven-decimal value
/// Overpass prints, so both import paths store the same coordinates and
/// switching between them changes no record.
fn osm_degrees(decoded: f64) -> f64 {
    (decoded * 1e7).round() / 1e7
}

/// What a read of the extract keeps: a cheap test on the raw tags, run on
/// every element of the file, then the full test on the collected tags.
pub(crate) trait Selector: Sync {
    /// Whether the tags may describe something kept; a false answer skips
    /// the element without allocating.
    fn candidate<'a>(&self, tags: impl Iterator<Item = (&'a str, &'a str)>) -> bool;
    /// Whether the collected tags describe something kept.
    fn keep(&self, tags: &BTreeMap<String, String>) -> bool;
}

/// The places: motorhome areas, campsites, dump stations, the car parks
/// and rest areas the place mapping reads ([`osm::kind_of`]).
struct Places;

impl Selector for Places {
    fn candidate<'a>(&self, mut tags: impl Iterator<Item = (&'a str, &'a str)>) -> bool {
        tags.any(|(k, v)| match k {
            "tourism" => v == "camp_site" || v == "caravan_site",
            "amenity" => v == "sanitary_dump_station" || v == "parking",
            "highway" => v == "rest_area" || v == "services",
            _ => false,
        })
    }

    fn keep(&self, tags: &BTreeMap<String, String>) -> bool {
        osm::kind_of(tags).is_some()
    }
}

fn selected<'a, S: Selector>(
    selector: &S,
    tags: impl Iterator<Item = (&'a str, &'a str)> + Clone,
) -> Option<BTreeMap<String, String>> {
    if !selector.candidate(tags.clone()) {
        return None;
    }
    let map: BTreeMap<String, String> = tags.map(|(k, v)| (k.to_owned(), v.to_owned())).collect();
    selector.keep(&map).then_some(map)
}

#[derive(Default)]
struct Selected {
    nodes: Vec<(i64, f64, f64, BTreeMap<String, String>)>,
    ways: Vec<(i64, Vec<i64>, BTreeMap<String, String>)>,
    relations: Vec<(i64, Vec<i64>, BTreeMap<String, String>)>,
}

impl Selected {
    fn merge(mut self, other: Self) -> Self {
        self.nodes.extend(other.nodes);
        self.ways.extend(other.ways);
        self.relations.extend(other.relations);
        self
    }
}

fn reader(path: &Path) -> Result<ElementReader<std::io::BufReader<std::fs::File>>, IngestError> {
    ElementReader::from_path(path).map_err(|source| IngestError::Pbf {
        path: path.to_owned(),
        source,
    })
}

fn pbf_err(path: &Path) -> impl Fn(osmpbf::Error) -> IngestError + '_ {
    move |source| IngestError::Pbf {
        path: path.to_owned(),
        source,
    }
}

/// Reads the extract at `path` into place records. CPU-bound and blocking:
/// run it on a blocking thread.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file is not a readable PBF.
pub fn read(path: &Path, fetched_at: DateTime<Utc>) -> Result<Parsed, IngestError> {
    let (elements, outside) = read_selected(path, &Places)?;
    let mut parsed = osm::build(elements, fetched_at);
    parsed
        .skipped
        .extend(outside.into_iter().map(|id| (id, Skip::OutsideArea)));
    Ok(parsed)
}

/// What a read keeps: the elements with their raw JSON, and the ids of
/// those outside the imported area.
pub(crate) type Selection = (Vec<(Element, serde_json::Value)>, Vec<String>);

/// The elements of the extract at `path` that `selector` keeps, inside the
/// imported area, each with its raw JSON (as Overpass would write it), and
/// the ids of those outside the area. Ways and relations are placed at the
/// centre of their bounding box. CPU-bound and blocking.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file is not a readable PBF.
pub(crate) fn read_selected<S: Selector>(
    path: &Path,
    selector: &S,
) -> Result<Selection, IngestError> {
    // Pass 1: the tagged elements.
    let found = reader(path)?
        .par_map_reduce(
            |element| {
                let mut s = Selected::default();
                match element {
                    PbfElement::Node(n) => {
                        if let Some(tags) = selected(selector, n.tags()) {
                            s.nodes.push((
                                n.id(),
                                osm_degrees(n.lat()),
                                osm_degrees(n.lon()),
                                tags,
                            ));
                        }
                    }
                    PbfElement::DenseNode(n) => {
                        if let Some(tags) = selected(selector, n.tags()) {
                            s.nodes.push((
                                n.id(),
                                osm_degrees(n.lat()),
                                osm_degrees(n.lon()),
                                tags,
                            ));
                        }
                    }
                    PbfElement::Way(w) => {
                        if let Some(tags) = selected(selector, w.tags()) {
                            s.ways.push((w.id(), w.refs().collect(), tags));
                        }
                    }
                    PbfElement::Relation(r) => {
                        if let Some(tags) = selected(selector, r.tags()) {
                            let ways = r
                                .members()
                                .filter(|m| m.member_type == RelMemberType::Way)
                                .map(|m| m.member_id)
                                .collect();
                            s.relations.push((r.id(), ways, tags));
                        }
                    }
                }
                s
            },
            Selected::default,
            Selected::merge,
        )
        .map_err(pbf_err(path))?;

    // Pass 2: the outlines of the selected relations.
    let member_ways: HashSet<i64> = found
        .relations
        .iter()
        .flat_map(|r| r.1.iter().copied())
        .collect();
    let outlines: HashMap<i64, Vec<i64>> = if member_ways.is_empty() {
        HashMap::new()
    } else {
        reader(path)?
            .par_map_reduce(
                |element| match element {
                    PbfElement::Way(w) if member_ways.contains(&w.id()) => {
                        HashMap::from([(w.id(), w.refs().collect::<Vec<_>>())])
                    }
                    _ => HashMap::new(),
                },
                HashMap::new,
                |mut a, b| {
                    a.extend(b);
                    a
                },
            )
            .map_err(pbf_err(path))?
    };

    // Pass 3: the coordinates of every node those ways reference.
    let needed: HashSet<i64> = found
        .ways
        .iter()
        .flat_map(|w| w.1.iter().copied())
        .chain(outlines.values().flatten().copied())
        .collect();
    let coords: HashMap<i64, (f64, f64)> = if needed.is_empty() {
        HashMap::new()
    } else {
        reader(path)?
            .par_map_reduce(
                |element| match element {
                    PbfElement::Node(n) if needed.contains(&n.id()) => {
                        HashMap::from([(n.id(), (osm_degrees(n.lat()), osm_degrees(n.lon())))])
                    }
                    PbfElement::DenseNode(n) if needed.contains(&n.id()) => {
                        HashMap::from([(n.id(), (osm_degrees(n.lat()), osm_degrees(n.lon())))])
                    }
                    _ => HashMap::new(),
                },
                HashMap::new,
                |mut a, b| {
                    a.extend(b);
                    a
                },
            )
            .map_err(pbf_err(path))?
    };

    let mut elements: Vec<Element> = Vec::new();
    for (id, lat, lon, tags) in found.nodes {
        elements.push(Element {
            kind: "node".into(),
            id,
            lat: Some(lat),
            lon: Some(lon),
            bounds: None,
            tags,
        });
    }
    for (id, refs, tags) in found.ways {
        elements.push(Element {
            kind: "way".into(),
            id,
            lat: None,
            lon: None,
            bounds: bounds(refs.iter(), &coords),
            tags,
        });
    }
    for (id, ways, tags) in found.relations {
        let refs = ways.iter().filter_map(|w| outlines.get(w)).flatten();
        elements.push(Element {
            kind: "relation".into(),
            id,
            lat: None,
            lon: None,
            bounds: bounds(refs, &coords),
            tags,
        });
    }
    // The order of a parallel read is not stable; the records' is.
    elements.sort_by(|a, b| a.kind.cmp(&b.kind).then(a.id.cmp(&b.id)));

    let mut outside = Vec::new();
    let kept = elements.into_iter().filter_map(|e| {
        let (lat, lon) = match (e.lat, e.lon, e.bounds) {
            (Some(lat), Some(lon), _) => (lat, lon),
            (_, _, Some(b)) => ((b.minlat + b.maxlat) / 2.0, (b.minlon + b.maxlon) / 2.0),
            _ => return Some(e),
        };
        let (s, w, n, east) = AREA;
        if (s..=n).contains(&lat) && (w..=east).contains(&lon) {
            Some(e)
        } else {
            outside.push(format!("{}/{}", e.kind, e.id));
            None
        }
    });
    let with_raw: Vec<(Element, serde_json::Value)> = kept
        .map(|e| {
            let raw = raw_json(&e);
            (e, raw)
        })
        .collect();
    Ok((with_raw, outside))
}

/// The bounding box of the nodes `refs`, `None` when none has coordinates.
fn bounds<'a>(
    refs: impl Iterator<Item = &'a i64>,
    coords: &HashMap<i64, (f64, f64)>,
) -> Option<Bounds> {
    let mut b: Option<Bounds> = None;
    for (lat, lon) in refs.filter_map(|r| coords.get(r)) {
        b = Some(match b {
            None => Bounds {
                minlat: *lat,
                minlon: *lon,
                maxlat: *lat,
                maxlon: *lon,
            },
            Some(x) => Bounds {
                minlat: x.minlat.min(*lat),
                minlon: x.minlon.min(*lon),
                maxlat: x.maxlat.max(*lat),
                maxlon: x.maxlon.max(*lon),
            },
        });
    }
    b
}

/// The element as Overpass would have written it with `out tags bb`, so the
/// raw payloads of both paths read the same.
fn raw_json(e: &Element) -> serde_json::Value {
    let mut obj = serde_json::Map::new();
    obj.insert("type".into(), e.kind.clone().into());
    obj.insert("id".into(), e.id.into());
    if let (Some(lat), Some(lon)) = (e.lat, e.lon) {
        obj.insert("lat".into(), lat.into());
        obj.insert("lon".into(), lon.into());
    }
    if let Some(b) = e.bounds {
        obj.insert("bounds".into(), serde_json::to_value(b).unwrap_or_default());
    }
    obj.insert(
        "tags".into(),
        serde_json::to_value(&e.tags).unwrap_or_default(),
    );
    serde_json::Value::Object(obj)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounds_cover_the_referenced_nodes_with_coordinates() {
        let coords = HashMap::from([(1, (47.0, -1.0)), (2, (47.2, -0.8)), (3, (46.9, -0.9))]);
        let b = bounds([1, 2, 3, 99].iter(), &coords).unwrap();
        assert_eq!(
            b,
            Bounds {
                minlat: 46.9,
                minlon: -1.0,
                maxlat: 47.2,
                maxlon: -0.8
            },
            "a node missing from the extract (99) is ignored"
        );
        assert_eq!(bounds([99].iter(), &coords), None);
    }

    #[test]
    fn coordinates_read_as_overpass_prints_them() {
        // 42.8034063 as osmpbf decodes it (`1e-9 * nanodegrees`), and as the
        // JSON of Overpass reads.
        let nano: i64 = 100 * 428_034_063;
        let decoded = 1e-9 * nano as f64;
        let printed: f64 = "42.8034063".parse().unwrap();
        assert_ne!(
            decoded.to_bits(),
            printed.to_bits(),
            "the decoder leaves a tail"
        );
        assert_eq!(osm_degrees(decoded).to_bits(), printed.to_bits());
    }

    #[test]
    fn only_selected_tags_are_collected() {
        let camp = [("tourism", "camp_site"), ("name", "X")];
        assert!(selected(&Places, camp.iter().copied()).is_some());
        let bench = [("amenity", "bench")];
        assert!(selected(&Places, bench.iter().copied()).is_none());
        let car_park = [("amenity", "parking")];
        assert!(
            selected(&Places, car_park.iter().copied()).is_none(),
            "a car park without motorhome or caravan access is out of scope"
        );
        let rest = [("highway", "rest_area")];
        assert!(selected(&Places, rest.iter().copied()).is_some());
    }
}
