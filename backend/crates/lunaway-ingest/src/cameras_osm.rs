//! Speed cameras from OpenStreetMap (ODbL): the nodes
//! `highway=speed_camera`, and the relations `type=enforcement`, whose
//! members say what is controlled (`device`), from where (`from`) and to
//! where (`to`). A relation gives the kind (`enforcement=maxspeed`,
//! `average_speed`, `traffic_signals`) and the direction of travel (from
//! `from` to the device); a node alone gives what its own tags say
//! (`direction`, `maxspeed`, `speed_camera`). Read from the same country
//! extracts as the places, each keeping only its own countries.

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
};

use chrono::{DateTime, Utc};
use lunaway_db::{
    PgPool,
    enforcement::{self as db, NewDevice},
};
use lunaway_domain::{
    Position, SourceId,
    enforcement::{Device, DeviceKind, bearing_of},
    routing::corridor::heading,
};
use osmpbf::{Element as PbfElement, RelMemberType};

use crate::{
    IngestError,
    cache::Cache,
    cameras::Listed,
    http::RetryPolicy,
    osm_extract::{self, Area, ExtractSpec, Refresh, osm_degrees, pbf_err, reader},
};

type Tags = BTreeMap<String, String>;

/// A camera node: its id, latitude, longitude and tags.
type CameraNode = (i64, f64, f64, Tags);
/// An enforcement relation: its id, tags, and node members with their role.
type Enforcement = (i64, Tags, Vec<(i64, String)>);

#[derive(Default)]
struct Found {
    nodes: Vec<CameraNode>,
    relations: Vec<Enforcement>,
}

impl Found {
    fn merge(mut self, other: Self) -> Self {
        self.nodes.extend(other.nodes);
        self.relations.extend(other.relations);
        self
    }
}

fn tags<'a>(it: impl Iterator<Item = (&'a str, &'a str)>) -> Tags {
    it.map(|(k, v)| (k.to_owned(), v.to_owned())).collect()
}

/// The leading number of a `maxspeed` (`90`, `90 mph` is left out).
fn speed(tags: &Tags) -> Option<u16> {
    let v = tags.get("maxspeed")?.trim();
    (!v.contains("mph")).then(|| v.parse().ok()).flatten()
}

/// What a relation's `enforcement` controls; none for what is not a
/// camera (a toll, a check, a distance).
fn relation_kind(tags: &Tags) -> Option<DeviceKind> {
    match tags.get("enforcement").map(String::as_str) {
        Some("maxspeed") => Some(DeviceKind::Fixed),
        Some("average_speed") => Some(DeviceKind::Section),
        Some("traffic_signals") => Some(DeviceKind::RedLight),
        _ => None,
    }
}

/// What a lone node controls; none for a mobile one.
fn node_kind(tags: &Tags) -> Option<DeviceKind> {
    let said = tags
        .get("speed_camera")
        .or_else(|| tags.get("enforcement"))
        .map(String::as_str);
    match said {
        Some("mobile") => None,
        Some("traffic_signals") => Some(DeviceKind::RedLight),
        Some("average_speed") => Some(DeviceKind::Section),
        _ => Some(DeviceKind::Fixed),
    }
}

/// Reads the cameras of the extract at `path` that lie in `area`'s
/// countries. CPU-bound and blocking: run it on a blocking thread.
///
/// # Errors
///
/// [`IngestError::Pbf`] when the file is not a readable PBF.
pub fn read(path: &Path, area: Area) -> Result<Vec<Listed>, IngestError> {
    // Pass 1: the camera nodes and the enforcement relations.
    let found = reader(path)?
        .par_map_reduce(
            |element| {
                let mut f = Found::default();
                match element {
                    PbfElement::Node(n) => {
                        if n.tags().any(|(k, v)| k == "highway" && v == "speed_camera") {
                            let lat = osm_degrees(n.lat());
                            let lon = osm_degrees(n.lon());
                            f.nodes.push((n.id(), lat, lon, tags(n.tags())));
                        }
                    }
                    PbfElement::DenseNode(n) => {
                        if n.tags().any(|(k, v)| k == "highway" && v == "speed_camera") {
                            let lat = osm_degrees(n.lat());
                            let lon = osm_degrees(n.lon());
                            f.nodes.push((n.id(), lat, lon, tags(n.tags())));
                        }
                    }
                    PbfElement::Relation(r) => {
                        if r.tags().any(|(k, v)| k == "type" && v == "enforcement") {
                            let members = r
                                .members()
                                .filter(|m| m.member_type == RelMemberType::Node)
                                .map(|m| (m.member_id, m.role().unwrap_or_default().to_owned()))
                                .collect();
                            f.relations.push((r.id(), tags(r.tags()), members));
                        }
                    }
                    PbfElement::Way(_) => {}
                }
                f
            },
            Found::default,
            Found::merge,
        )
        .map_err(pbf_err(path))?;

    // Pass 2: where the relations' member nodes are.
    let mut coords: HashMap<i64, (f64, f64)> =
        found.nodes.iter().map(|n| (n.0, (n.1, n.2))).collect();
    let needed: HashSet<i64> = found
        .relations
        .iter()
        .flat_map(|r| r.2.iter().map(|m| m.0))
        .filter(|id| !coords.contains_key(id))
        .collect();
    if !needed.is_empty() {
        let more = reader(path)?
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
            .map_err(pbf_err(path))?;
        coords.extend(more);
    }
    Ok(build(&found, &coords, area))
}

fn position(coords: &HashMap<i64, (f64, f64)>, id: i64) -> Option<Position> {
    coords
        .get(&id)
        .and_then(|(lat, lon)| Position::new(*lat, *lon).ok())
}

fn build(found: &Found, coords: &HashMap<i64, (f64, f64)>, area: Area) -> Vec<Listed> {
    let mut out = Vec::new();
    let mut devices_of_relations: HashSet<i64> = HashSet::new();
    for (id, rel_tags, members) in &found.relations {
        let Some(kind) = relation_kind(rel_tags) else {
            continue;
        };
        let member = |role: &str| {
            members
                .iter()
                .filter(|(_, r)| r == role)
                .find_map(|(m, _)| position(coords, *m))
        };
        let device_node = members.iter().find(|(_, r)| r == "device").map(|m| m.0);
        let (from, to) = (member("from"), member("to"));
        let Some(at) = member("device").or(from) else {
            continue;
        };
        if let Some(n) = device_node {
            devices_of_relations.insert(n);
        }
        let toward = if kind == DeviceKind::Section {
            to
        } else {
            Some(at)
        };
        let bearing = from
            .zip(toward)
            .filter(|(a, b)| a.distance_m(*b) > 5.0)
            .map(|(a, b)| heading(a, b).rem_euclid(360.0));
        let device = Device {
            external_id: format!("relation/{id}"),
            kind,
            position: at,
            bearing_deg: bearing,
            limit_kmh: speed(rel_tags),
            road: rel_tags.get("ref").cloned(),
            section_end: (kind == DeviceKind::Section).then_some(to).flatten(),
            section_length_m: None,
        };
        let raw = serde_json::json!({"type": "relation", "id": id, "tags": rel_tags,
            "members": members.iter().map(|(m, r)| serde_json::json!({"ref": m, "role": r}))
                .collect::<Vec<_>>()});
        out.push(Listed { device, raw });
    }
    for (id, lat, lon, node_tags) in &found.nodes {
        if devices_of_relations.contains(id) {
            continue;
        }
        let (Some(kind), Ok(at)) = (node_kind(node_tags), Position::new(*lat, *lon)) else {
            continue;
        };
        let device = Device {
            external_id: format!("node/{id}"),
            kind,
            position: at,
            bearing_deg: node_tags.get("direction").and_then(|d| bearing_of(d)),
            limit_kmh: speed(node_tags),
            road: node_tags.get("ref").cloned(),
            section_end: None,
            section_length_m: None,
        };
        let raw = serde_json::json!({"type": "node", "id": id, "lat": lat, "lon": lon,
            "tags": node_tags});
        out.push(Listed { device, raw });
    }
    out.retain(|l| {
        area.country(l.device.position.lat(), l.device.position.lon())
            .is_ok()
    });
    out.sort_by(|a, b| a.device.external_id.cmp(&b.device.external_id));
    out
}

/// What an import of OpenStreetMap's cameras did, extract by extract.
#[derive(Debug, Clone, PartialEq)]
pub struct OsmCameraReport {
    /// Each extract: its name and the cameras it gave.
    pub extracts: Vec<(&'static str, usize)>,
    /// Devices written: new, changed, or seen again (their read date
    /// moves).
    pub written: u64,
    /// Devices retired in the countries read.
    pub retired: u64,
    /// The countries where retiring was refused (fewer than half seen).
    pub refused: Vec<String>,
}

/// Reads the cameras of every extract of `specs` from `mirror` (each
/// downloaded or read from the cache), stores them, and retires, in each
/// country the extracts cover, the cameras they no longer hold.
///
/// # Errors
///
/// [`IngestError`] when a download, a read or a write fails.
pub async fn import(
    pool: &PgPool,
    http: &reqwest::Client,
    cache: &Cache,
    specs: &[ExtractSpec],
    mirror: &str,
    refresh: Refresh,
    retry: RetryPolicy,
) -> Result<OsmCameraReport, IngestError> {
    let source = SourceId::OSM;
    let mut seen: Vec<String> = Vec::new();
    let mut by_country: BTreeMap<String, usize> = BTreeMap::new();
    let mut extracts = Vec::new();
    let mut written = 0;
    let mut latest: Option<DateTime<Utc>> = None;
    for spec in specs {
        let file = osm_extract::fetch(
            http,
            cache,
            &spec.url(mirror),
            &spec.cache_key(mirror),
            retry,
            refresh,
        )
        .await?;
        latest = latest.max(Some(file.fetched_at));
        let path = file.path.clone();
        let area = Area::of(spec);
        let listed = tokio::task::spawn_blocking(move || read(&path, area))
            .await
            .map_err(IngestError::Blocking)??;
        let placed: Vec<(&Listed, &'static str)> = listed
            .iter()
            .filter_map(|l| {
                lunaway_domain::region::country_at(l.device.position)
                    .filter(|c| *c != "CH")
                    .map(|c| (l, c))
            })
            .collect();
        let rows: Vec<NewDevice<'_>> = placed
            .iter()
            .map(|(l, c)| NewDevice {
                device: &l.device,
                country: c,
                raw: &l.raw,
            })
            .collect();
        written += db::upsert_devices(pool, &source, &rows, file.fetched_at).await?;
        for (l, c) in &placed {
            seen.push(l.device.external_id.clone());
            *by_country.entry((*c).to_owned()).or_insert(0) += 1;
        }
        extracts.push((spec.name, placed.len()));
    }
    let covered: Vec<String> = specs
        .iter()
        .flat_map(|s| s.covers.iter().map(|c| (*c).to_owned()))
        .filter(|c| c.len() == 2)
        .collect();
    let stored = db::live_counts_by_country(pool, &source).await?;
    let (passing, refused): (Vec<String>, Vec<String>) = covered.into_iter().partition(|c| {
        let stored = stored.get(c).copied().unwrap_or(0);
        let seen = i64::try_from(by_country.get(c).copied().unwrap_or(0)).unwrap_or(i64::MAX);
        stored < 10 || seen.saturating_mul(2) >= stored
    });
    for c in &refused {
        tracing::warn!(country = %c, "fewer than half of the stored cameras seen; none retired");
    }
    let retired = db::retire_missing_in(
        pool,
        &source,
        &passing,
        &seen,
        latest.unwrap_or_else(Utc::now),
    )
    .await?;
    if let Some(at) = latest {
        let live = db::live_count(pool, &source).await?;
        db::record_read(pool, &source, at, live).await?;
    }
    Ok(OsmCameraReport {
        extracts,
        written,
        retired,
        refused,
    })
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "a test states its preconditions with unwrap"
    )]
    use super::*;

    fn t(pairs: &[(&str, &str)]) -> Tags {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn a_relation_gives_its_kind_and_its_direction_and_hides_its_node() {
        // A French average speed section and a lone camera beside it, as in
        // the extract: the relation's device is the node 1.
        let found = Found {
            nodes: vec![
                (1, 45.541_488, 5.388_159, t(&[("highway", "speed_camera")])),
                (
                    2,
                    45.554_302,
                    5.359_006,
                    t(&[
                        ("highway", "speed_camera"),
                        ("direction", "290"),
                        ("maxspeed", "130"),
                    ]),
                ),
                (
                    3,
                    45.0,
                    5.0,
                    t(&[("highway", "speed_camera"), ("speed_camera", "mobile")]),
                ),
            ],
            relations: vec![(
                10,
                t(&[
                    ("type", "enforcement"),
                    ("enforcement", "average_speed"),
                    ("maxspeed", "110"),
                ]),
                vec![(1, "device".into()), (4, "from".into()), (5, "to".into())],
            )],
        };
        let coords: HashMap<i64, (f64, f64)> = HashMap::from([
            (1, (45.541_488, 5.388_159)),
            (4, (45.540, 5.392)),
            (5, (45.56, 5.34)),
        ]);
        let france = Area::of(&osm_extract::extract("france").unwrap());
        let listed = build(&found, &coords, france);
        let ids: Vec<&str> = listed
            .iter()
            .map(|l| l.device.external_id.as_str())
            .collect();
        assert_eq!(
            ids,
            ["node/2", "relation/10"],
            "the mobile camera is not a place"
        );
        let section = &listed[1].device;
        assert_eq!(section.kind, DeviceKind::Section);
        assert_eq!(section.limit_kmh, Some(110));
        assert!(section.section_end.is_some());
        let b = section.bearing_deg.unwrap();
        assert!(
            (280.0..340.0).contains(&b),
            "north-west, from `from` to `to`: {b}"
        );
        assert_eq!(listed[0].device.bearing_deg, Some(290.0));
        assert_eq!(listed[0].device.limit_kmh, Some(130));
    }
}
