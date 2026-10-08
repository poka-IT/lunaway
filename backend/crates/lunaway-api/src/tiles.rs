//! The map tiles of two layers, the points of interest and the places:
//! `GET /poi/tiles.json` and `GET /places/tiles.json` (TileJSON naming the
//! current tiles), `GET /poi/{version}/{z}/{x}/{y}.mvt` and
//! `GET /places/{version}/{z}/{x}/{y}.mvt` (Mapbox Vector Tiles built by
//! PostGIS, `lunaway_db::pois::tile` and `lunaway_db::place_tiles::tile`).
//!
//! Hundreds of thousands of points cannot go to every device, and the map
//! shows a few streets at a time: a tile carries only what its square
//! holds, with the few properties a map needs. The places' tiles carry
//! what the app's filters read, so the web app filters the map without a
//! request and never syncs the places. The version of a layer is in the
//! URL, so a tile of the current version is cached for good by the device
//! and any proxy; a tile asked under another version answers the current
//! data with a short cache, for a client whose TileJSON is a few minutes
//! old.
//!
//! Work is bounded: a per-client charge on the shared budget, tiles in
//! memory per layer (the oldest evicted first, `TilesConfig::cache_bytes`),
//! a few tiles built at once by both layers together, each within the
//! pool's statement timeout. The places' low zooms are built ahead when
//! their version moves (one tile at a time, only while a builder stays
//! free for the clients), because a tile of half of Europe takes the
//! database up to half a second. A tile address names a place on the map,
//! often where the user is: no log line carries one (see `loggable_path`).

use std::{
    collections::{HashMap, VecDeque},
    net::SocketAddr,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use axum::{
    body::Bytes,
    extract::{ConnectInfo, FromRequestParts, Path, Request, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use lunaway_db::{PgPool, place_tiles, pois};
use tokio::sync::Semaphore;

use crate::{
    client::ClientKey,
    config::TilesConfig,
    error::{INTERNAL, NOT_FOUND, UNAVAILABLE},
    http::{refuse, wait_response},
    rate::RateLimiter,
};

/// Lowest zoom of the points: a country fits in a few tiles of clusters.
pub const MIN_ZOOM: i32 = 6;
/// Highest zoom served by both layers; maps draw the tiles of this zoom
/// beyond it.
pub const MAX_ZOOM: i32 = 14;
/// Where the points' TileJSON is.
pub const TILE_JSON_PATH: &str = "/poi/tiles.json";
/// Where the places' TileJSON is.
pub const PLACES_TILE_JSON_PATH: &str = "/places/tiles.json";
/// The attribution of what the points' tiles carry: the points
/// (OpenStreetMap and the community, ODbL), their hours from La Poste
/// (ODbL), the LPG flag from the fuel price feed and the closures from
/// FINESS (Licence Ouverte 2.0).
pub const ATTRIBUTION: &str = "© OpenStreetMap contributors, Lunaway contributors, La Poste, \
     Ministère de l'Économie (prix des carburants), FINESS";
/// The attribution of what the places' tiles carry, every source places are
/// made of (`sources`, `docs/data-sources.md`): OpenStreetMap and the
/// community (ODbL), Atout France's classified campsites with their
/// positions from the Base Adresse Nationale and IGN's BD TOPO, the tourist
/// offices' areas from DATAtourisme (Licence Ouverte 2.0), and the external
/// community source under its written agreement, by the mention the
/// agreement words. A tile names the places of any of them, so the layer
/// credits all of them.
pub const PLACES_ATTRIBUTION: &str = "© OpenStreetMap contributors, Lunaway contributors, \
     Atout France (positions: Base Adresse Nationale, IGN BD TOPO), DATAtourisme, \
     Source communautaire externe";
/// The area both layers cover (west, south, east, north), the extent of
/// the European import (`osm_extract::EUROPE`), from the Azores and the
/// Canary Islands to Svalbard and Finland: a tile outside it is empty
/// without asking the database.
pub const BOUNDS: [f64; 4] = [-32.0, 27.0, 35.0, 81.0];
/// What building a tile costs a client, on top of the request's own cost:
/// a dense tile takes the database tens of milliseconds.
const BUILD_COST: usize = 2_000;
/// How long a tile waits for a free builder before the client is asked to
/// come back.
const BUILD_WAIT: Duration = Duration::from_secs(2);
/// Longest time a tile may take to build: below the pool's statement
/// timeout (5 s by default), so a slow tile is answered as busy, not as an
/// error.
const BUILD_TIMEOUT: Duration = Duration::from_secs(4);
/// What an entry of the cache costs beyond its bytes (key, map slot, queue
/// slot): an empty tile is not free.
const ENTRY_OVERHEAD: usize = 128;
/// How long the layer's version is trusted before it is read again.
const VERSION_TTL: Duration = Duration::from_secs(5);
/// Least time between two early reads asked by a newer version in a URL:
/// a client cannot make every request a read of the database.
const VERSION_RECHECK: Duration = Duration::from_millis(200);
/// How long the building ahead waits before it looks again for a builder
/// the clients leave free.
const WARM_BACKOFF: Duration = Duration::from_millis(50);
/// The media type of a vector tile.
const MVT: &str = "application/vnd.mapbox-vector-tile";

/// The points' tile URL template of `version`, under the API's public URL.
#[must_use]
pub fn tile_template(base: &str, version: i64) -> String {
    format!("{base}/poi/{version}/{{z}}/{{x}}/{{y}}.mvt")
}

/// The places' tile URL template of `version`, under the API's public URL.
#[must_use]
pub fn places_tile_template(base: &str, version: i64) -> String {
    format!("{base}/places/{version}/{{z}}/{{x}}/{{y}}.mvt")
}

/// The layers served as tiles. Each has its own version, cache and
/// TileJSON; they share the builders and the clients' budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Layer {
    /// The points of interest (`pois`).
    Points,
    /// The places (`places`).
    Places,
}

impl Layer {
    /// What a log line calls it.
    fn what(self) -> &'static str {
        match self {
            Self::Points => "points",
            Self::Places => "places",
        }
    }

    /// The lowest zoom served.
    fn min_zoom(self) -> i32 {
        match self {
            Self::Points => MIN_ZOOM,
            Self::Places => place_tiles::DOTS_MIN_ZOOM,
        }
    }

    async fn version(self, pool: &PgPool) -> Result<i64, lunaway_db::DbError> {
        match self {
            Self::Points => pois::layer_version(pool).await.map(|v| v.version),
            Self::Places => place_tiles::layer_version(pool).await.map(|v| v.version),
        }
    }

    async fn build(
        self,
        pool: &PgPool,
        (z, x, y): (i32, i32, i32),
        max_features: i64,
    ) -> Result<Vec<u8>, lunaway_db::DbError> {
        match self {
            Self::Points => pois::tile(pool, z, x, y, max_features).await,
            Self::Places => place_tiles::tile(pool, z, x, y, max_features).await,
        }
    }

    /// The TileJSON of `version`.
    fn tile_json(self, base: &str, version: i64) -> serde_json::Value {
        match self {
            Self::Points => serde_json::json!({
                "tilejson": "3.0.0",
                "name": "Lunaway points of interest",
                "version": format!("1.0.{version}"),
                "attribution": ATTRIBUTION,
                "scheme": "xyz",
                "tiles": [tile_template(base, version)],
                "minzoom": MIN_ZOOM,
                "maxzoom": MAX_ZOOM,
                "bounds": BOUNDS,
                "vector_layers": [
                    {
                        "id": "pois",
                        "description": "Every point, from the point zoom on",
                        "minzoom": pois::POINT_MIN_ZOOM,
                        "maxzoom": MAX_ZOOM,
                        "fields": {
                            "id": "String: the point's id, for Query.poi",
                            "category": "String: groceries, vending, water, fuel, health, services",
                            "kind": "String: the PoiKind code (bakery, vending_pizza, ...)",
                            "name": "String, absent when the source gives none",
                            "alwaysOpen": "Boolean, present and true for a point open day and night",
                            "hours": "String: <first opening, minutes since 1970>:<open>,<closed>,<open>,... in minutes; empty when closed over the whole window",
                            "hoursUntil": "Number: minutes since 1970 at which the known hours end",
                            "lpg": "Boolean, present and true for a fuel station that sells LPG",
                            "maybeClosed": "Boolean, present and true when FINESS lists the establishment as closed"
                        }
                    },
                    {
                        "id": "poi_clusters",
                        "description": "Points counted per category and grid cell, below the point zoom",
                        "minzoom": MIN_ZOOM,
                        "maxzoom": pois::POINT_MIN_ZOOM - 1,
                        "fields": {
                            "category": "String",
                            "count": "Number of points in the cell"
                        }
                    },
                    {
                        "id": "poi_vending_clusters",
                        "description": "Food vending machines counted per kind and grid cell, below the point zoom; poi_clusters counts them too",
                        "minzoom": MIN_ZOOM,
                        "maxzoom": pois::POINT_MIN_ZOOM - 1,
                        "fields": {
                            "kind": "String: vending_pizza, vending_bread, vending_farm_products, vending_eggs_milk, vending_ice",
                            "count": "Number of machines of that kind in the cell"
                        }
                    }
                ]
            }),
            Self::Places => serde_json::json!({
                "tilejson": "3.0.0",
                "name": "Lunaway places",
                "version": format!("1.0.{version}"),
                "attribution": PLACES_ATTRIBUTION,
                "scheme": "xyz",
                "tiles": [places_tile_template(base, version)],
                "minzoom": place_tiles::DOTS_MIN_ZOOM,
                "maxzoom": MAX_ZOOM,
                "bounds": BOUNDS,
                "vector_layers": [
                    {
                        "id": "places",
                        "description": "Every live place, one point each, from the pin zoom on",
                        "minzoom": place_tiles::PIN_ZOOM,
                        "maxzoom": MAX_ZOOM,
                        "fields": {
                            "id": "String: the place's id, for Query.place",
                            "kind": "String: the PlaceKind code (motorhome_area, service_area, campsite, parking, nature, rest_area, picnic_area, farm, homestay, off_road, extra_service)",
                            "night": "String: the OvernightStatus code (allowed, tolerated, day_only, forbidden, unknown)",
                            "s": "Number: the services, bit i set for the i-th Service of the domain (drinking_water 0, grey_water 1, black_water 2, waste_bin 3, toilets 4, showers 5, electricity 6, wifi 7, laundry 8, lpg 9, gas_bottles 10, vehicle_wash 11, bakery 12, swimming_pool 13, pets_allowed 14, mobile_data 15, winter_caravanning 16)",
                            "price": "Number: 0 when parking is free, 1 when it is paid; absent when unknown, which is not free",
                            "h": "Number: the maximum vehicle height in centimetres, rounded; absent when unknown",
                            "name": format!("String, from zoom {}; absent when the place has none", place_tiles::NAME_MIN_ZOOM),
                            "city": format!("String, from zoom {}: the town of the address, else of the commune; absent when neither is known", place_tiles::NAME_MIN_ZOOM)
                        }
                    },
                    {
                        "id": "place_dots",
                        "description": "Every live place as a dot, below the pin zoom: one MultiPoint per set of properties, one point per pixel of a 512 px tile holding such a place",
                        "minzoom": place_tiles::DOTS_MIN_ZOOM,
                        "maxzoom": place_tiles::PIN_ZOOM - 1,
                        "fields": {
                            "kind": "String: as in places",
                            "night": "String: as in places",
                            "s": "Number: as in places, bits 0 to 8 only (drinking_water to laundry)",
                            "price": "Number: as in places",
                            "h": "Number: as in places"
                        }
                    }
                ]
            }),
        }
    }
}

type Key = (i64, i32, i32, i32);

/// Tiles in memory, the oldest evicted first, bounded in bytes.
struct TileCache {
    map: HashMap<Key, Bytes>,
    order: VecDeque<Key>,
    bytes: usize,
    max_bytes: usize,
}

impl TileCache {
    fn get(&self, key: &Key) -> Option<Bytes> {
        self.map.get(key).cloned()
    }

    fn put(&mut self, key: Key, tile: Bytes) {
        let cost = tile.len() + ENTRY_OVERHEAD;
        if cost > self.max_bytes || self.map.contains_key(&key) {
            return;
        }
        self.bytes += cost;
        self.map.insert(key, tile);
        self.order.push_back(key);
        while self.bytes > self.max_bytes {
            let Some(old) = self.order.pop_front() else {
                break;
            };
            if let Some(t) = self.map.remove(&old) {
                self.bytes -= t.len() + ENTRY_OVERHEAD;
            }
        }
    }
}

/// What the routes of one layer share.
pub(crate) struct TileEndpoint {
    layer: Layer,
    pool: PgPool,
    config: TilesConfig,
    rate: Arc<RateLimiter>,
    cache: Mutex<TileCache>,
    /// Shared by the layers: what bounds the database work of tiles.
    builders: Arc<Semaphore>,
    version: Mutex<Option<(i64, Instant)>>,
    /// Set while the low zooms of a version are built ahead.
    warming: AtomicBool,
}

impl TileEndpoint {
    pub(crate) fn new(
        layer: Layer,
        pool: PgPool,
        config: TilesConfig,
        rate: Arc<RateLimiter>,
        builders: Arc<Semaphore>,
    ) -> Self {
        Self {
            layer,
            pool,
            cache: Mutex::new(TileCache {
                map: HashMap::new(),
                order: VecDeque::new(),
                bytes: 0,
                max_bytes: config.cache_bytes,
            }),
            builders,
            version: Mutex::new(None),
            warming: AtomicBool::new(false),
            config,
            rate,
        }
    }

    /// The version this copy holds, whatever its age.
    fn known_version(&self) -> Option<i64> {
        self.version.lock().ok().and_then(|g| g.map(|(v, _)| v))
    }

    /// The layer's version, read at most every [`VERSION_TTL`]; `None`
    /// when the database cannot say (logged).
    async fn version(self: &Arc<Self>) -> Option<i64> {
        self.version_at_least(0).await
    }

    /// The layer's version, read again before its time when a client names
    /// a newer one (its TileJSON is fresher than this copy), at most every
    /// [`VERSION_RECHECK`]. A version this copy did not know starts the
    /// building ahead of the places' low zooms.
    async fn version_at_least(self: &Arc<Self>, asked: i64) -> Option<i64> {
        if let Ok(guard) = self.version.lock()
            && let Some((v, at)) = *guard
            && at.elapsed() < VERSION_TTL
            && (v >= asked || at.elapsed() < VERSION_RECHECK)
        {
            return Some(v);
        }
        let v = match self.layer.version(&self.pool).await {
            Ok(v) => v,
            Err(error) => {
                tracing::error!(
                    %error,
                    layer = self.layer.what(),
                    "cannot read the version of a tiles layer"
                );
                return None;
            }
        };
        let before = self.known_version();
        if let Ok(mut guard) = self.version.lock() {
            *guard = Some((v, Instant::now()));
        }
        if before != Some(v) {
            self.start_warming();
        }
        Some(v)
    }

    /// Builds the places' dots tiles of the current version ahead, in the
    /// background, unless it already runs (it then moves on to the newer
    /// version by itself).
    fn start_warming(self: &Arc<Self>) {
        // With a single builder, the clients would wait behind every tile
        // built ahead: the building ahead keeps one free, so it needs two.
        if self.layer != Layer::Places || !self.config.warm || self.config.concurrency < 2 {
            return;
        }
        if self.warming.swap(true, Ordering::SeqCst) {
            return;
        }
        let me = Arc::clone(self);
        tokio::spawn(async move {
            let mut done = None;
            while let Some(v) = me.known_version()
                && done != Some(v)
            {
                me.warm(v).await;
                done = Some(v);
            }
            me.warming.store(false, Ordering::SeqCst);
            // A version read between the last check and the line above found
            // the flag still set and left: look once more.
            if me.known_version() != done {
                me.start_warming();
            }
        });
    }

    /// Builds into the cache every dots tile of `version` that holds a
    /// place, one at a time and only while another builder stays free for
    /// the clients; stops when a newer version is known.
    async fn warm(&self, version: i64) {
        let started = Instant::now();
        let tiles = match place_tiles::dots_tiles_with_places(&self.pool).await {
            Ok(t) => t,
            Err(error) => {
                tracing::warn!(%error, "places layer: cannot list the tiles to build ahead");
                return;
            }
        };
        let mut built = 0_usize;
        for (z, x, y) in tiles {
            if self.known_version() != Some(version) {
                return;
            }
            if coordinates_of(self.layer, z, x, y).is_none() || !within_bounds(z, x, y) {
                continue;
            }
            let key = (version, z, x, y);
            if self.cache.lock().ok().and_then(|c| c.get(&key)).is_some() {
                continue;
            }
            let slot = loop {
                if self.known_version() != Some(version) {
                    return;
                }
                if self.builders.available_permits() > 1
                    && let Ok(slot) = self.builders.try_acquire()
                {
                    break slot;
                }
                tokio::time::sleep(WARM_BACKOFF).await;
            };
            let tile = tokio::time::timeout(
                BUILD_TIMEOUT,
                self.layer
                    .build(&self.pool, (z, x, y), self.config.max_features),
            )
            .await;
            drop(slot);
            match tile {
                Ok(Ok(bytes)) => {
                    if let Ok(mut c) = self.cache.lock() {
                        c.put(key, Bytes::from(bytes));
                    }
                    built += 1;
                }
                Ok(Err(error)) => {
                    tracing::warn!(
                        %error,
                        z,
                        "places layer: a tile built ahead failed; the others wait for the clients"
                    );
                    return;
                }
                Err(_) => {
                    tracing::warn!(
                        z,
                        "places layer: a tile built ahead ran out of time; the others wait for the clients"
                    );
                    return;
                }
            }
        }
        tracing::info!(
            version,
            built,
            ms = started.elapsed().as_millis(),
            "places layer: low zooms built ahead"
        );
    }
}

fn internal_error() -> Response {
    refuse(
        StatusCode::INTERNAL_SERVER_ERROR,
        INTERNAL,
        "internal error",
    )
}

/// The client of a request, and its headers.
async fn client(request: Request) -> (ClientKey, HeaderMap) {
    let (mut parts, _) = request.into_parts();
    let peer = ConnectInfo::<SocketAddr>::from_request_parts(&mut parts, &())
        .await
        .ok()
        .map(|c| c.0);
    (ClientKey::from_request(peer, &parts.headers), parts.headers)
}

/// `GET /poi/tiles.json` or `GET /places/tiles.json`: what a map style
/// points at.
pub(crate) async fn tile_json(
    State(endpoint): State<Arc<TileEndpoint>>,
    request: Request,
) -> Response {
    let (key, _) = client(request).await;
    if let Err(wait) = endpoint.rate.admit(key) {
        return wait_response(
            StatusCode::TOO_MANY_REQUESTS,
            "this client's request budget is spent; wait and try again",
            wait,
        );
    }
    let Some(v) = endpoint.version().await else {
        return internal_error();
    };
    let body = endpoint.layer.tile_json(&endpoint.config.public_url, v);
    let mut response = (
        StatusCode::OK,
        [(
            header::CONTENT_TYPE,
            HeaderValue::from_static("application/json"),
        )],
        body.to_string(),
    )
        .into_response();
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=60"),
    );
    response
}

/// The coordinates of a tile path, if they name a tile `layer` serves,
/// written in digits only: Caddy's access log masks `/<z>/<x>/<y>.mvt` in
/// digits, so a spelling it would not mask (`+2075`) is not served.
fn coordinates(layer: Layer, z: &str, x: &str, y_mvt: &str) -> Option<(i32, i32, i32)> {
    let y = y_mvt.strip_suffix(".mvt")?;
    coordinates_of(layer, digits(z)?, digits(x)?, digits(y)?)
}

/// `s` as a number, if it is written in ASCII digits only.
fn digits<T: std::str::FromStr>(s: &str) -> Option<T> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

/// `z/x/y`, if it is a tile `layer` serves.
fn coordinates_of(layer: Layer, z: i32, x: i32, y: i32) -> Option<(i32, i32, i32)> {
    let side = 1_i32.checked_shl(u32::try_from(z).ok()?)?;
    ((layer.min_zoom()..=MAX_ZOOM).contains(&z) && (0..side).contains(&x) && (0..side).contains(&y))
        .then_some((z, x, y))
}

/// Whether the tile `z/x/y` meets the area the layers cover ([`BOUNDS`]).
fn within_bounds(z: i32, x: i32, y: i32) -> bool {
    let n = f64::from(1_i32 << z.clamp(0, 30));
    let lon = |x: i32| f64::from(x) / n * 360.0 - 180.0;
    let lat = |y: i32| {
        (std::f64::consts::PI * (1.0 - 2.0 * f64::from(y) / n))
            .sinh()
            .atan()
            .to_degrees()
    };
    let (west, east, north, south) = (lon(x), lon(x + 1), lat(y), lat(y + 1));
    let [b_west, b_south, b_east, b_north] = BOUNDS;
    east >= b_west && west <= b_east && north >= b_south && south <= b_north
}

/// `GET /poi/{version}/{z}/{x}/{y}.mvt` or
/// `GET /places/{version}/{z}/{x}/{y}.mvt`.
pub(crate) async fn tile(
    State(endpoint): State<Arc<TileEndpoint>>,
    Path((version, z, x, y_mvt)): Path<(String, String, String, String)>,
    request: Request,
) -> Response {
    let (key, headers) = client(request).await;
    if let Err(wait) = endpoint.rate.admit(key) {
        return wait_response(
            StatusCode::TOO_MANY_REQUESTS,
            "this client's request budget is spent; wait and try again",
            wait,
        );
    }
    let layer = endpoint.layer;
    let Some((z, x, y)) = coordinates(layer, &z, &x, &y_mvt) else {
        return refuse(StatusCode::NOT_FOUND, NOT_FOUND, "no such tile");
    };
    let Some(asked) = digits::<i64>(&version) else {
        return refuse(StatusCode::NOT_FOUND, NOT_FOUND, "no such tile");
    };
    let Some(current) = endpoint.version_at_least(asked).await else {
        return internal_error();
    };
    let etag = format!("\"{current}-{z}-{x}-{y}\"");
    let cache_control = if asked == current {
        "public, max-age=31536000, immutable"
    } else if asked > current {
        // A version this copy does not know yet (read again at most every
        // VERSION_RECHECK): today's tile, kept by nobody, since the newer
        // version may lack a place this one still shows (a takedown).
        "no-store"
    } else {
        // An older (or a made-up) version gets the current data, briefly
        // cached: the client's TileJSON is about to name the new version.
        "public, max-age=300"
    };
    if headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.split(',').any(|t| t.trim() == etag))
    {
        return with_headers(StatusCode::NOT_MODIFIED, Bytes::new(), &etag, cache_control);
    }
    if !within_bounds(z, x, y) {
        // Nothing of the layer is there: no database work, no cache entry.
        return with_headers(StatusCode::NO_CONTENT, Bytes::new(), &etag, cache_control);
    }
    let cache_key = (current, z, x, y);
    let cached = endpoint.cache.lock().ok().and_then(|c| c.get(&cache_key));
    let tile = match cached {
        Some(t) => t,
        None => {
            if let Err(wait) = endpoint.rate.charge(key, BUILD_COST) {
                return wait_response(
                    StatusCode::TOO_MANY_REQUESTS,
                    "this client's request budget is spent; wait and try again",
                    wait,
                );
            }
            let Ok(Ok(_slot)) = tokio::time::timeout(BUILD_WAIT, endpoint.builders.acquire()).await
            else {
                return wait_response(
                    StatusCode::SERVICE_UNAVAILABLE,
                    "the server is busy; try again in a moment",
                    Duration::from_secs(1),
                );
            };
            // Another request may have built it while this one waited.
            let again = endpoint.cache.lock().ok().and_then(|c| c.get(&cache_key));
            match again {
                Some(t) => t,
                None => {
                    let built = tokio::time::timeout(
                        BUILD_TIMEOUT,
                        layer.build(&endpoint.pool, (z, x, y), endpoint.config.max_features),
                    )
                    .await;
                    let bytes = match built {
                        Ok(Ok(b)) => Bytes::from(b),
                        Ok(Err(error)) if is_cancelled(&error) => {
                            // The database's statement timeout stopped it.
                            tracing::warn!(
                                z,
                                layer = layer.what(),
                                "a tile ran out of time in the database"
                            );
                            return refuse(
                                StatusCode::SERVICE_UNAVAILABLE,
                                UNAVAILABLE,
                                "the tile took too long; try again later",
                            );
                        }
                        Ok(Err(error)) => {
                            tracing::error!(%error, z, layer = layer.what(), "a tile failed");
                            return internal_error();
                        }
                        Err(_) => {
                            tracing::warn!(z, layer = layer.what(), "a tile ran out of time");
                            return refuse(
                                StatusCode::SERVICE_UNAVAILABLE,
                                UNAVAILABLE,
                                "the tile took too long; try again later",
                            );
                        }
                    };
                    if let Ok(mut c) = endpoint.cache.lock() {
                        c.put(cache_key, bytes.clone());
                    }
                    bytes
                }
            }
        }
    };
    let status = if tile.is_empty() {
        StatusCode::NO_CONTENT
    } else {
        StatusCode::OK
    };
    with_headers(status, tile, &etag, cache_control)
}

/// Whether the database cancelled the statement (its timeout).
fn is_cancelled(error: &lunaway_db::DbError) -> bool {
    match error {
        lunaway_db::DbError::Query(e) => e
            .as_database_error()
            .and_then(|d| d.code())
            .is_some_and(|c| c == "57014"),
        _ => false,
    }
}

fn with_headers(
    status: StatusCode,
    body: Bytes,
    etag: &str,
    cache_control: &'static str,
) -> Response {
    let mut response = (status, body).into_response();
    let h = response.headers_mut();
    if status == StatusCode::OK {
        h.insert(header::CONTENT_TYPE, HeaderValue::from_static(MVT));
    }
    if let Ok(v) = HeaderValue::from_str(etag) {
        h.insert(header::ETAG, v);
    }
    h.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static(cache_control),
    );
    response
}

/// The path of a request as a log line may carry it: a tile's `x` and `y`
/// name a place on the map, so they are replaced in both layers (the zoom
/// stays, as in Caddy's access log).
#[must_use]
pub fn loggable_path(path: &str) -> std::borrow::Cow<'_, str> {
    let mut parts = path.split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some(""), Some(layer @ ("poi" | "places")), Some(version), Some(z), Some(_))
            if version != "tiles.json" =>
        {
            std::borrow::Cow::Owned(format!("/{layer}/{version}/{z}/x/y.mvt"))
        }
        _ => std::borrow::Cow::Borrowed(path),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiles_far_from_europe_are_known_empty() {
        let (x, y) = (4149, 2815);
        assert!(within_bounds(13, x, y), "Paris");
        assert!(within_bounds(6, 32, 22), "the tile of France at zoom 6");
        assert!(within_bounds(6, 29, 26), "the Canary Islands at zoom 6");
        assert!(within_bounds(6, 36, 18), "Helsinki at zoom 6");
        assert!(within_bounds(2, 1, 1), "western Europe at zoom 2");
        assert!(!within_bounds(14, 1, 1), "the Arctic Ocean");
        assert!(!within_bounds(13, 0, 4095), "the Pacific");
        assert!(!within_bounds(6, 40, 24), "the Caspian Sea");
        assert!(!within_bounds(2, 3, 1), "Asia at zoom 2");
    }

    #[test]
    fn only_tiles_of_the_layer_are_served() {
        let points = Layer::Points;
        assert_eq!(
            coordinates(points, "13", "4149", "2815.mvt"),
            Some((13, 4149, 2815))
        );
        assert_eq!(
            coordinates(points, "5", "15", "11.mvt"),
            None,
            "below the lowest zoom"
        );
        assert_eq!(
            coordinates(points, "15", "1", "1.mvt"),
            None,
            "beyond the highest zoom"
        );
        assert_eq!(
            coordinates(points, "6", "64", "1.mvt"),
            None,
            "x past the side"
        );
        assert_eq!(coordinates(points, "6", "-1", "1.mvt"), None);
        assert_eq!(coordinates(points, "6", "1", "1.pbf"), None);
        assert_eq!(coordinates(points, "99999999999", "1", "1.mvt"), None);
        let places = Layer::Places;
        assert_eq!(
            coordinates(places, "2", "1", "1.mvt"),
            Some((2, 1, 1)),
            "the places' dots start lower than the points"
        );
        assert_eq!(coordinates(places, "1", "1", "1.mvt"), None);
        assert_eq!(coordinates(places, "2", "4", "1.mvt"), None);
        assert_eq!(coordinates(places, "15", "1", "1.mvt"), None);
        assert_eq!(
            coordinates(places, "12", "+2075", "1409.mvt"),
            None,
            "a sign would escape Caddy's mask of the access log"
        );
        assert_eq!(coordinates(places, "12", "2075", "+1409.mvt"), None);
        assert_eq!(coordinates(places, "12", "", "1.mvt"), None);
        assert_eq!(digits::<i64>("+7"), None);
        assert_eq!(digits::<i64>("7"), Some(7));
    }

    #[test]
    fn a_tile_path_never_reaches_a_log_with_its_place() {
        assert_eq!(
            loggable_path("/poi/12/13/4149/2815.mvt"),
            "/poi/12/13/x/y.mvt"
        );
        assert_eq!(
            loggable_path("/places/7/13/4149/2815.mvt"),
            "/places/7/13/x/y.mvt"
        );
        assert_eq!(loggable_path("/poi/tiles.json"), "/poi/tiles.json");
        assert_eq!(loggable_path("/places/tiles.json"), "/places/tiles.json");
        assert_eq!(loggable_path("/graphql"), "/graphql");
    }

    #[test]
    fn the_cache_keeps_the_newest_within_its_bound() {
        let room = 2 * (4 + ENTRY_OVERHEAD);
        let mut c = TileCache {
            map: HashMap::new(),
            order: VecDeque::new(),
            bytes: 0,
            max_bytes: room,
        };
        c.put((1, 1, 1, 1), Bytes::from_static(b"aaaa"));
        c.put((1, 1, 1, 2), Bytes::from_static(b"bbbb"));
        c.put((1, 1, 1, 3), Bytes::from_static(b"cccc"));
        assert!(c.get(&(1, 1, 1, 1)).is_none(), "the oldest went first");
        assert!(c.get(&(1, 1, 1, 2)).is_some() && c.get(&(1, 1, 1, 3)).is_some());
        assert!(c.bytes <= room);
        c.put((1, 1, 1, 4), Bytes::from(vec![0; room]));
        assert!(
            c.get(&(1, 1, 1, 4)).is_none(),
            "a tile larger than the cache is not kept"
        );
        let mut empties = TileCache {
            map: HashMap::new(),
            order: VecDeque::new(),
            bytes: 0,
            max_bytes: 10 * ENTRY_OVERHEAD,
        };
        for i in 0..1_000 {
            empties.put((1, 14, i, 0), Bytes::new());
        }
        assert!(
            empties.map.len() <= 10,
            "empty tiles count too, or they would pile up: {}",
            empties.map.len()
        );
    }
}
