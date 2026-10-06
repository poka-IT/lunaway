//! Reading a Geofabrik-style PBF extract. `osmpbf` only reads, so the test
//! writes a small extract itself, in the PBF wire format (OSM PBF spec,
//! `fileformat.proto` and `osmformat.proto`): one header blob, then one data
//! blob holding a group of nodes, a group of ways and a group of relations.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use chrono::{TimeZone, Utc};
use lunaway_domain::{OvernightStatus, PlaceKind, Service};
use lunaway_ingest::{
    cache::Cache,
    http::{self, RetryPolicy},
    osm::Skip,
    osm_extract::{self, Refresh},
};

/// Where the France extract is kept in the cache.
const KEY: &str = "osm-extract/france-latest.osm.pbf";

/// The area of a run of the France extract alone.
fn france() -> osm_extract::Area<'static> {
    static COVERAGE: std::sync::LazyLock<osm_extract::Coverage> = std::sync::LazyLock::new(|| {
        osm_extract::Coverage::of(&[osm_extract::extract("france").unwrap()])
    });
    osm_extract::Area::of(&osm_extract::extract("france").unwrap(), &COVERAGE)
}

fn varint(out: &mut Vec<u8>, mut v: u64) {
    while v >= 0x80 {
        out.push(u8::try_from(v & 0x7f).unwrap() | 0x80);
        v >>= 7;
    }
    out.push(u8::try_from(v).unwrap());
}

fn zigzag(n: i64) -> u64 {
    u64::from_ne_bytes(((n << 1) ^ (n >> 63)).to_ne_bytes())
}

fn key(out: &mut Vec<u8>, field: u64, wire: u64) {
    varint(out, (field << 3) | wire);
}

fn bytes_field(out: &mut Vec<u8>, field: u64, bytes: &[u8]) {
    key(out, field, 2);
    varint(out, bytes.len() as u64);
    out.extend_from_slice(bytes);
}

fn varint_field(out: &mut Vec<u8>, field: u64, v: u64) {
    key(out, field, 0);
    varint(out, v);
}

fn packed(out: &mut Vec<u8>, field: u64, values: impl IntoIterator<Item = u64>) {
    let mut body = Vec::new();
    for v in values {
        varint(&mut body, v);
    }
    bytes_field(out, field, &body);
}

/// Strings of a block, index 0 being the empty string as the format wants.
struct Strings(Vec<String>);

impl Strings {
    fn id(&mut self, s: &str) -> u64 {
        if let Some(i) = self.0.iter().position(|x| x == s) {
            return i as u64;
        }
        self.0.push(s.to_owned());
        (self.0.len() - 1) as u64
    }
}

fn tags(out: &mut Vec<u8>, strings: &mut Strings, tags: &[(&str, &str)]) {
    let keys: Vec<u64> = tags.iter().map(|(k, _)| strings.id(k)).collect();
    let vals: Vec<u64> = tags.iter().map(|(_, v)| strings.id(v)).collect();
    packed(out, 2, keys);
    packed(out, 3, vals);
}

/// Degrees to the format's units at the default granularity of 100 nanodegrees.
fn units(deg: f64) -> u64 {
    let n = (deg * 1e7).round() as i64;
    zigzag(n)
}

fn node(strings: &mut Strings, id: i64, lat: f64, lon: f64, t: &[(&str, &str)]) -> Vec<u8> {
    let mut m = Vec::new();
    varint_field(&mut m, 1, zigzag(id));
    tags(&mut m, strings, t);
    varint_field(&mut m, 8, units(lat));
    varint_field(&mut m, 9, units(lon));
    m
}

fn deltas(ids: &[i64]) -> Vec<u64> {
    let mut last = 0;
    ids.iter()
        .map(|id| {
            let d = id - last;
            last = *id;
            zigzag(d)
        })
        .collect()
}

fn way(strings: &mut Strings, id: i64, refs: &[i64], t: &[(&str, &str)]) -> Vec<u8> {
    let mut m = Vec::new();
    varint_field(&mut m, 1, u64::try_from(id).unwrap());
    tags(&mut m, strings, t);
    packed(&mut m, 8, deltas(refs));
    m
}

fn relation(strings: &mut Strings, id: i64, outer_ways: &[i64], t: &[(&str, &str)]) -> Vec<u8> {
    let mut m = Vec::new();
    varint_field(&mut m, 1, u64::try_from(id).unwrap());
    tags(&mut m, strings, t);
    let role = strings.id("outer");
    packed(&mut m, 8, outer_ways.iter().map(|_| role));
    packed(&mut m, 9, deltas(outer_ways));
    packed(&mut m, 10, outer_ways.iter().map(|_| 1)); // WAY
    m
}

fn blob(kind: &str, payload: &[u8]) -> Vec<u8> {
    let mut b = Vec::new();
    bytes_field(&mut b, 1, payload); // raw
    varint_field(&mut b, 2, payload.len() as u64); // raw_size
    let mut header = Vec::new();
    bytes_field(&mut header, 1, kind.as_bytes());
    varint_field(&mut header, 3, b.len() as u64);
    let mut out = u32::try_from(header.len()).unwrap().to_be_bytes().to_vec();
    out.extend(header);
    out.extend(b);
    out
}

/// A small extract around Angers, plus a campsite in La Réunion.
fn extract() -> Vec<u8> {
    let mut s = Strings(vec![String::new()]);
    let square = |lat: f64, lon: f64, first: i64| {
        [
            (0.001, 0.001),
            (0.001, -0.001),
            (-0.001, -0.001),
            (-0.001, 0.001),
        ]
        .iter()
        .enumerate()
        .map(|(i, (dlat, dlon))| (first + i as i64, lat + dlat, lon + dlon))
        .collect::<Vec<_>>()
    };
    let mut nodes = vec![
        node(
            &mut s,
            1,
            47.40,
            -0.60,
            &[("tourism", "camp_site"), ("name", "Camping A")],
        ),
        node(&mut s, 2, 47.41, -0.61, &[("amenity", "bench")]),
        node(
            &mut s,
            3,
            47.5005,
            -0.5005,
            &[("amenity", "sanitary_dump_station")],
        ),
        node(
            &mut s,
            4,
            47.70,
            -0.30,
            &[
                ("amenity", "parking"),
                ("motorhome", "designated"),
                ("name", "Parking D"),
            ],
        ),
        node(
            &mut s,
            5,
            -21.1,
            55.5,
            &[("tourism", "camp_site"), ("name", "Camping Réunion")],
        ),
        node(&mut s, 6, 47.42, -0.62, &[("amenity", "parking")]),
    ];
    for (id, lat, lon) in square(47.50, -0.50, 10)
        .into_iter()
        .chain(square(47.60, -0.40, 20))
    {
        nodes.push(node(&mut s, id, lat, lon, &[]));
    }
    let ways = [
        way(
            &mut s,
            100,
            &[10, 11, 12, 13, 10],
            &[("tourism", "caravan_site"), ("name", "Aire B")],
        ),
        way(&mut s, 200, &[20, 21, 22, 23, 20], &[]),
    ];
    let relations = [relation(
        &mut s,
        300,
        &[200],
        &[
            ("type", "multipolygon"),
            ("tourism", "camp_site"),
            ("name", "Camping C"),
        ],
    )];

    let group = |field: u64, items: &[Vec<u8>]| {
        let mut g = Vec::new();
        for item in items {
            bytes_field(&mut g, field, item);
        }
        g
    };
    let groups = [group(1, &nodes), group(3, &ways), group(4, &relations)];
    let mut table = Vec::new();
    for string in &s.0 {
        bytes_field(&mut table, 1, string.as_bytes());
    }
    let mut block = Vec::new();
    bytes_field(&mut block, 1, &table);
    for g in &groups {
        bytes_field(&mut block, 2, g);
    }

    let mut header_block = Vec::new();
    bytes_field(&mut header_block, 4, b"OsmSchema-V0.6");
    let mut file = blob("OSMHeader", &header_block);
    file.extend(blob("OSMData", &block));
    file
}

/// Bytes of an extract holding `nodes` and `ways` only.
fn file_of(s: &Strings, nodes: &[Vec<u8>], ways: &[Vec<u8>]) -> Vec<u8> {
    let group = |field: u64, items: &[Vec<u8>]| {
        let mut g = Vec::new();
        for item in items {
            bytes_field(&mut g, field, item);
        }
        g
    };
    let mut table = Vec::new();
    for string in &s.0 {
        bytes_field(&mut table, 1, string.as_bytes());
    }
    let mut block = Vec::new();
    bytes_field(&mut block, 1, &table);
    bytes_field(&mut block, 2, &group(1, nodes));
    bytes_field(&mut block, 2, &group(3, ways));
    let mut header_block = Vec::new();
    bytes_field(&mut header_block, 4, b"OsmSchema-V0.6");
    let mut file = blob("OSMHeader", &header_block);
    file.extend(blob("OSMData", &block));
    file
}

#[test]
fn the_points_of_interest_come_from_the_same_extract() {
    use lunaway_domain::poi::PoiKind;
    let mut s = Strings(vec![String::new()]);
    let mut nodes = vec![
        node(
            &mut s,
            1,
            47.47,
            -0.55,
            &[("shop", "bakery"), ("name", "Ma Petite Mie")],
        ),
        node(&mut s, 2, 47.471, -0.551, &[("amenity", "bench")]),
        node(
            &mut s,
            3,
            47.472,
            -0.552,
            &[("amenity", "vending_machine"), ("vending", "drinks")],
        ),
        node(
            &mut s,
            4,
            47.473,
            -0.553,
            &[("amenity", "vending_machine"), ("vending", "food;pizza")],
        ),
        node(
            &mut s,
            5,
            47.474,
            -0.554,
            &[("amenity", "toilets"), ("access", "private")],
        ),
        node(&mut s, 6, -21.1, 55.5, &[("amenity", "pharmacy")]),
        // A camp site is a place, not a point of interest.
        node(&mut s, 7, 47.475, -0.555, &[("tourism", "camp_site")]),
    ];
    for (id, lat, lon) in [
        (10, 47.48, -0.56),
        (11, 47.48, -0.558),
        (12, 47.482, -0.558),
        (13, 47.482, -0.56),
    ] {
        nodes.push(node(&mut s, id, lat, lon, &[]));
    }
    let ways = [way(
        &mut s,
        100,
        &[10, 11, 12, 13, 10],
        &[
            ("shop", "supermarket"),
            ("name", "Super U"),
            ("brand", "Super U"),
        ],
    )];
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("pois.osm.pbf");
    std::fs::write(&path, file_of(&s, &nodes, &ways)).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 4, 20, 0, 0).unwrap();
    let parsed = lunaway_ingest::poi_osm::read(&path, at, france()).unwrap();
    let got: Vec<(&str, PoiKind)> = parsed
        .points
        .iter()
        .map(|p| (p.external_id.as_str(), p.record.kind))
        .collect();
    assert_eq!(
        got,
        [
            ("node/1", PoiKind::Bakery),
            ("node/4", PoiKind::VendingPizza),
            ("way/100", PoiKind::Supermarket)
        ],
        "a bench, a drinks machine, private toilets and a camp site are not points of the layer"
    );
    let skipped: Vec<&str> = parsed.skipped.iter().map(|(id, _)| id.as_str()).collect();
    assert!(
        skipped.contains(&"node/5"),
        "private toilets are read and left out"
    );
    assert!(
        skipped.contains(&"node/6"),
        "the overseas pharmacy is outside the imported area"
    );
    let shop = &parsed.points[2];
    assert_eq!(shop.record.brand.as_deref(), Some("Super U"));
    assert_eq!(
        (shop.record.position.lat(), shop.record.position.lon()),
        (47.481, -0.559),
        "a way is placed at the centre of its outline"
    );
    assert_eq!(
        shop.external_url.as_deref(),
        Some("https://www.openstreetmap.org/way/100")
    );
}

#[test]
fn an_extract_maps_like_an_overpass_answer() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("sample.osm.pbf");
    std::fs::write(&path, extract()).unwrap();
    let at = Utc.with_ymd_and_hms(2026, 10, 4, 20, 0, 0).unwrap();
    let parsed = osm_extract::read(&path, at, france()).unwrap();

    let ids: Vec<&str> = parsed
        .records
        .iter()
        .map(|r| r.external_id.as_str())
        .collect();
    assert_eq!(ids, ["node/1", "node/4", "relation/300", "way/100"]);
    assert_eq!(
        parsed.skipped,
        vec![("node/5".to_owned(), Skip::OutsideArea)],
        "the overseas campsite is outside the imported area"
    );
    assert_eq!(parsed.attached_dump_stations, 1);

    let get = |id: &str| parsed.records.iter().find(|r| r.external_id == id).unwrap();
    let area = &get("way/100").record;
    assert_eq!(area.kind, PlaceKind::MotorhomeArea);
    assert!(
        (area.position.lat() - 47.50).abs() < 1e-9 && (area.position.lon() + 0.50).abs() < 1e-9
    );
    assert!(
        area.accuracy_m > 100.0 && area.accuracy_m < 200.0,
        "half the outline's diagonal: {}",
        area.accuracy_m
    );
    assert!(
        area.services.contains(&Service::BlackWater),
        "the borne inside the area gives its services"
    );

    let multipolygon = &get("relation/300").record;
    assert_eq!(multipolygon.kind, PlaceKind::Campsite);
    assert!(
        (multipolygon.position.lat() - 47.60).abs() < 1e-9,
        "the outline's centre"
    );
    assert!(multipolygon.accuracy_m > 100.0);

    let parking = &get("node/4").record;
    assert_eq!(parking.kind, PlaceKind::Parking);
    assert_eq!(parking.overnight, OvernightStatus::Tolerated);
    assert_eq!(get("node/1").raw["tags"]["name"], "Camping A");
    let minlat = get("way/100").raw["bounds"]["minlat"].as_f64().unwrap();
    assert!(
        (minlat - 47.499).abs() < 1e-9,
        "the raw payload keeps the bounds: {minlat}"
    );
    assert!(parsed.records.iter().all(|r| r.fetched_at == at));
}

#[tokio::test]
async fn the_extract_is_downloaded_once_then_read_from_the_cache() {
    use axum::{Router, routing::get};
    let calls = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let counter = calls.clone();
    let app = Router::new().route(
        "/france-latest.osm.pbf",
        get(move || {
            counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            async { extract() }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });

    let dir = tempfile::tempdir().unwrap();
    let cache = Cache::new(dir.path());
    let client = http::client_allowing_plain_http().unwrap();
    let url = format!("http://{addr}/france-latest.osm.pbf");
    let retry = RetryPolicy {
        min_delay: std::time::Duration::from_millis(5),
        max_delay: std::time::Duration::from_millis(5),
        max_retries: 1,
    };
    let first = osm_extract::fetch(&client, &cache, &url, KEY, retry, Refresh::Never)
        .await
        .unwrap();
    assert!(!first.cached);
    assert_eq!(std::fs::read(&first.path).unwrap(), extract());
    let again = osm_extract::fetch(&client, &cache, &url, KEY, retry, Refresh::Never)
        .await
        .unwrap();
    assert!(again.cached);
    assert_eq!(
        calls.load(std::sync::atomic::Ordering::SeqCst),
        1,
        "a cached extract costs no download"
    );
}

/// A server of one file under one URL, as OpenStreetMap France serves its
/// extracts: a strong `ETag`, and nginx's handling of ranges (RFC 9110,
/// 13.1.5): a range is honoured unless an `If-Range` names another file,
/// which gets the whole current file instead.
#[derive(Clone)]
struct RangeServer {
    file: std::sync::Arc<std::sync::Mutex<(String, Vec<u8>)>>,
    seen: std::sync::Arc<std::sync::Mutex<Vec<(String, String)>>>,
}

impl RangeServer {
    async fn start(etag: &str, body: Vec<u8>) -> (Self, std::net::SocketAddr) {
        use axum::{
            Router,
            extract::State,
            http::{HeaderMap, StatusCode, header},
            response::IntoResponse,
            routing::get,
        };
        let server = Self {
            file: std::sync::Arc::new(std::sync::Mutex::new((etag.to_owned(), body))),
            seen: std::sync::Arc::default(),
        };
        let app = Router::new()
            .route(
                "/extracts/france-latest.osm.pbf",
                get(|State(s): State<Self>, headers: HeaderMap| async move {
                    let get = |name| {
                        headers
                            .get(name)
                            .and_then(|v: &axum::http::HeaderValue| v.to_str().ok())
                            .unwrap_or_default()
                            .to_owned()
                    };
                    let (range, if_range) = (get(header::RANGE), get(header::IF_RANGE));
                    s.seen
                        .lock()
                        .unwrap()
                        .push((range.clone(), if_range.clone()));
                    let (etag, body) = s.file.lock().unwrap().clone();
                    let from: usize = range
                        .strip_prefix("bytes=")
                        .and_then(|r| r.strip_suffix('-'))
                        .and_then(|n| n.parse().ok())
                        .unwrap_or(0);
                    if from >= body.len() && from > 0 {
                        (
                            StatusCode::RANGE_NOT_SATISFIABLE,
                            [(header::CONTENT_RANGE, format!("bytes */{}", body.len()))],
                        )
                            .into_response()
                    } else if from > 0 && (if_range.is_empty() || if_range == etag) {
                        let total = body.len();
                        (
                            StatusCode::PARTIAL_CONTENT,
                            [
                                (header::ETAG, etag),
                                (
                                    header::CONTENT_RANGE,
                                    format!("bytes {from}-{}/{total}", total - 1),
                                ),
                            ],
                            body[from..].to_vec(),
                        )
                            .into_response()
                    } else {
                        (StatusCode::OK, [(header::ETAG, etag)], body).into_response()
                    }
                }),
            )
            .with_state(server.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        (server, addr)
    }
}

fn fast() -> RetryPolicy {
    RetryPolicy {
        min_delay: std::time::Duration::from_millis(5),
        max_delay: std::time::Duration::from_millis(5),
        max_retries: 1,
    }
}

/// What an earlier run left: half of `body`, and the pin it wrote.
fn interrupted(dir: &std::path::Path, body: &[u8], pin: &str) -> usize {
    let extract_dir = dir.join("osm-extract");
    std::fs::create_dir_all(&extract_dir).unwrap();
    let half = body.len() / 2;
    std::fs::write(extract_dir.join("france-latest.osm.partial"), &body[..half]).unwrap();
    std::fs::write(extract_dir.join("france-latest.osm.partial.source"), pin).unwrap();
    half
}

#[tokio::test]
async fn an_interrupted_download_of_the_same_file_resumes_where_it_stopped() {
    let full = extract();
    let (server, addr) = RangeServer::start("\"v1\"", full.clone()).await;
    // Asked for a -latest URL that redirected to the file that answered;
    // the resume goes to the file, not through the redirect again.
    let latest = format!("http://{addr}/extracts/latest");
    let url = format!("http://{addr}/extracts/france-latest.osm.pbf");
    let dir = tempfile::tempdir().unwrap();
    let half = interrupted(dir.path(), &full, &format!("{latest}\n{url}\n\"v1\"\n"));
    let got = osm_extract::fetch(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &latest,
        KEY,
        fast(),
        Refresh::OlderThan(std::time::Duration::ZERO),
    )
    .await
    .unwrap();
    assert_eq!(std::fs::read(&got.path).unwrap(), full);
    assert_eq!(
        *server.seen.lock().unwrap(),
        [(format!("bytes={half}-"), "\"v1\"".to_owned())],
        "only the missing half is asked for, on condition that the file is the same"
    );
    assert!(
        !dir.path()
            .join("osm-extract/france-latest.osm.partial.source")
            .exists()
    );
}

#[tokio::test]
async fn a_file_replaced_between_two_attempts_is_downloaded_whole_not_spliced() {
    // Monday's file was half downloaded; the mirror now serves Tuesday's
    // under the same URL, without a redirect.
    let monday = extract();
    let mut tuesday = extract();
    tuesday.extend_from_slice(b"tuesday");
    let (server, addr) = RangeServer::start("\"v2\"", tuesday.clone()).await;
    let url = format!("http://{addr}/extracts/france-latest.osm.pbf");
    let dir = tempfile::tempdir().unwrap();
    interrupted(dir.path(), &monday, &format!("{url}\n{url}\n\"v1\"\n"));
    let got = osm_extract::fetch(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &url,
        KEY,
        fast(),
        Refresh::OlderThan(std::time::Duration::ZERO),
    )
    .await
    .unwrap();
    assert_eq!(
        std::fs::read(&got.path).unwrap(),
        tuesday,
        "Monday's start with Tuesday's end would be a corrupt extract"
    );
    assert_eq!(server.seen.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_partial_file_without_a_validator_or_from_another_url_starts_over() {
    let full = extract();
    let (server, addr) = RangeServer::start("\"v1\"", full.clone()).await;
    let url = format!("http://{addr}/extracts/france-latest.osm.pbf");
    for pin in [
        // Written before validators were kept.
        format!("{url}\n{url}"),
        format!("http://elsewhere/x.osm.pbf\n{url}\n\"v1\"\n"),
    ] {
        let dir = tempfile::tempdir().unwrap();
        interrupted(dir.path(), &full, &pin);
        let got = osm_extract::fetch(
            &http::client_allowing_plain_http().unwrap(),
            &Cache::new(dir.path()),
            &url,
            KEY,
            fast(),
            Refresh::OlderThan(std::time::Duration::ZERO),
        )
        .await
        .unwrap();
        assert_eq!(std::fs::read(&got.path).unwrap(), full);
        assert_eq!(
            server.seen.lock().unwrap().pop(),
            Some((String::new(), String::new())),
            "no range for {pin:?}"
        );
    }
}

#[tokio::test]
async fn a_partial_file_already_complete_is_downloaded_again_not_stuck() {
    // The process stopped between the last write and the rename: the server
    // answers 416 to a range past the end, which is no transient error.
    let full = extract();
    let (server, addr) = RangeServer::start("\"v1\"", full.clone()).await;
    let url = format!("http://{addr}/extracts/france-latest.osm.pbf");
    let dir = tempfile::tempdir().unwrap();
    let extract_dir = dir.path().join("osm-extract");
    std::fs::create_dir_all(&extract_dir).unwrap();
    std::fs::write(extract_dir.join("france-latest.osm.partial"), &full).unwrap();
    std::fs::write(
        extract_dir.join("france-latest.osm.partial.source"),
        format!("{url}\n{url}\n\"v1\"\n"),
    )
    .unwrap();
    let got = osm_extract::fetch(
        &http::client_allowing_plain_http().unwrap(),
        &Cache::new(dir.path()),
        &url,
        KEY,
        fast(),
        Refresh::OlderThan(std::time::Duration::ZERO),
    )
    .await
    .unwrap();
    assert_eq!(std::fs::read(&got.path).unwrap(), full);
    let seen = server.seen.lock().unwrap().clone();
    assert_eq!(seen.len(), 2, "the 416, then the whole file: {seen:?}");
    assert_eq!(seen[1].0, "", "the second request asks for no range");
}
