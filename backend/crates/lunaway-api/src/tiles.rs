//! The map tiles of the points of interest: `GET /poi/tiles.json` (a
//! TileJSON naming the current tiles) and
//! `GET /poi/{version}/{z}/{x}/{y}.mvt` (Mapbox Vector Tiles built by
//! PostGIS, `lunaway_db::pois::tile`).
//!
//! Hundreds of thousands of points cannot go to every device, and the map
//! shows a few streets at a time: a tile carries only what its square
//! holds, with the few properties a map needs (id, category, kind, name,
//! hours in a compact form). The version of the layer is in the URL, so a
//! tile of the current version is cached for good by the device and any
//! proxy; a tile asked under another version answers the current data with
//! a short cache, for a client whose TileJSON is a few minutes old.
//!
//! Work is bounded: a per-client charge on the shared budget, tiles in
//! memory (the oldest evicted first, `TilesConfig::cache_bytes`), a few tiles
//! built at once, each within the pool's statement timeout. A tile address
//! names a place on the map, often where the user is: no log line carries
//! one (see `loggable_path` in `lib.rs`).

use std::{
    collections::{HashMap, VecDeque},
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use axum::{
    body::Bytes,
    extract::{ConnectInfo, FromRequestParts, Path, Request, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use lunaway_db::{PgPool, pois};
use tokio::sync::Semaphore;

use crate::{
    client::ClientKey,
    config::TilesConfig,
    error::{INTERNAL, NOT_FOUND, UNAVAILABLE},
    http::{refuse, wait_response},
    rate::RateLimiter,
};

/// Lowest zoom served: France fits in a few tiles of clusters.
pub const MIN_ZOOM: i32 = 6;
/// Highest zoom served; maps draw the tiles of this zoom beyond it.
pub const MAX_ZOOM: i32 = 14;
/// Where the TileJSON is.
pub const TILE_JSON_PATH: &str = "/poi/tiles.json";
/// The attribution of what the tiles carry: the points (OpenStreetMap and
/// the community, ODbL), their hours from La Poste (ODbL), the LPG flag
/// from the fuel price feed and the closures from FINESS (Licence Ouverte
/// 2.0).
pub const ATTRIBUTION: &str = "© OpenStreetMap contributors, Lunaway contributors, La Poste, \
     Ministère de l'Économie (prix des carburants), FINESS";
/// The area the layer covers (west, south, east, north), the extent of the
/// imports: a tile outside it is empty without asking the database.
pub const BOUNDS: [f64; 4] = [-5.8, 41.0, 10.0, 51.6];
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
/// The media type of a vector tile.
const MVT: &str = "application/vnd.mapbox-vector-tile";

/// The tile URL template of `version`, under the API's public URL.
#[must_use]
pub fn tile_template(base: &str, version: i64) -> String {
    format!("{base}/poi/{version}/{{z}}/{{x}}/{{y}}.mvt")
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

/// What the tile routes share.
pub(crate) struct TileEndpoint {
    pool: PgPool,
    config: TilesConfig,
    rate: Arc<RateLimiter>,
    cache: Mutex<TileCache>,
    builders: Semaphore,
    version: Mutex<Option<(pois::LayerVersion, Instant)>>,
}

impl TileEndpoint {
    pub(crate) fn new(pool: PgPool, config: TilesConfig, rate: Arc<RateLimiter>) -> Self {
        Self {
            pool,
            cache: Mutex::new(TileCache {
                map: HashMap::new(),
                order: VecDeque::new(),
                bytes: 0,
                max_bytes: config.cache_bytes,
            }),
            builders: Semaphore::new(config.concurrency),
            version: Mutex::new(None),
            config,
            rate,
        }
    }

    /// The layer's version, read at most every [`VERSION_TTL`]; `None`
    /// when the database cannot say (logged).
    async fn version(&self) -> Option<pois::LayerVersion> {
        self.version_at_least(0).await
    }

    /// The layer's version, read again before its time when a client names
    /// a newer one (its TileJSON is fresher than this copy), at most every
    /// [`VERSION_RECHECK`].
    async fn version_at_least(&self, asked: i64) -> Option<pois::LayerVersion> {
        if let Ok(guard) = self.version.lock()
            && let Some((v, at)) = *guard
            && at.elapsed() < VERSION_TTL
            && (v.version >= asked || at.elapsed() < VERSION_RECHECK)
        {
            return Some(v);
        }
        let v = match pois::layer_version(&self.pool).await {
            Ok(v) => v,
            Err(error) => {
                tracing::error!(%error, "cannot read the version of the points layer");
                return None;
            }
        };
        if let Ok(mut guard) = self.version.lock() {
            *guard = Some((v, Instant::now()));
        }
        Some(v)
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

/// `GET /poi/tiles.json`: what a map style points at.
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
    let base = &endpoint.config.public_url;
    let body = serde_json::json!({
        "tilejson": "3.0.0",
        "name": "Lunaway points of interest",
        "version": format!("1.0.{}", v.version),
        "attribution": ATTRIBUTION,
        "scheme": "xyz",
        "tiles": [tile_template(base, v.version)],
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
            }
        ]
    });
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

/// The coordinates of a tile path, if they name a tile this layer serves.
fn coordinates(z: &str, x: &str, y_mvt: &str) -> Option<(i32, i32, i32)> {
    let z: i32 = z.parse().ok()?;
    let x: i32 = x.parse().ok()?;
    let y: i32 = y_mvt.strip_suffix(".mvt")?.parse().ok()?;
    let side = 1_i32.checked_shl(u32::try_from(z).ok()?)?;
    ((MIN_ZOOM..=MAX_ZOOM).contains(&z) && (0..side).contains(&x) && (0..side).contains(&y))
        .then_some((z, x, y))
}

/// Whether the tile `z/x/y` meets the area the layer covers ([`BOUNDS`]).
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

/// `GET /poi/{version}/{z}/{x}/{y}.mvt`.
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
    let Some((z, x, y)) = coordinates(&z, &x, &y_mvt) else {
        return refuse(StatusCode::NOT_FOUND, NOT_FOUND, "no such tile");
    };
    let Ok(asked) = version.parse::<i64>() else {
        return refuse(StatusCode::NOT_FOUND, NOT_FOUND, "no such tile");
    };
    let Some(current) = endpoint.version_at_least(asked).await.map(|v| v.version) else {
        return internal_error();
    };
    let etag = format!("\"{current}-{z}-{x}-{y}\"");
    let cache_control = if asked == current {
        "public, max-age=31536000, immutable"
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
                        pois::tile(&endpoint.pool, z, x, y, endpoint.config.max_features),
                    )
                    .await;
                    let bytes = match built {
                        Ok(Ok(b)) => Bytes::from(b),
                        Ok(Err(error)) if is_cancelled(&error) => {
                            // The database's statement timeout stopped it.
                            tracing::warn!(z, "a points tile ran out of time in the database");
                            return refuse(
                                StatusCode::SERVICE_UNAVAILABLE,
                                UNAVAILABLE,
                                "the tile took too long; try again later",
                            );
                        }
                        Ok(Err(error)) => {
                            tracing::error!(%error, z, "a points tile failed");
                            return internal_error();
                        }
                        Err(_) => {
                            tracing::warn!(z, "a points tile ran out of time");
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
/// name a place on the map, so they are replaced (the zoom stays, as in
/// Caddy's access log).
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
        (Some(""), Some("poi"), Some(version), Some(z), Some(_)) if version != "tiles.json" => {
            std::borrow::Cow::Owned(format!("/poi/{version}/{z}/x/y.mvt"))
        }
        _ => std::borrow::Cow::Borrowed(path),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiles_far_from_france_are_known_empty() {
        let (x, y) = (4149, 2815);
        assert!(within_bounds(13, x, y), "Paris");
        assert!(within_bounds(6, 32, 22), "the tile of France at zoom 6");
        assert!(!within_bounds(14, 1, 1), "the Arctic Ocean");
        assert!(!within_bounds(13, 0, 4095), "the Pacific");
    }

    #[test]
    fn only_tiles_of_the_layer_are_served() {
        assert_eq!(
            coordinates("13", "4149", "2815.mvt"),
            Some((13, 4149, 2815))
        );
        assert_eq!(
            coordinates("5", "15", "11.mvt"),
            None,
            "below the lowest zoom"
        );
        assert_eq!(
            coordinates("15", "1", "1.mvt"),
            None,
            "beyond the highest zoom"
        );
        assert_eq!(coordinates("6", "64", "1.mvt"), None, "x past the side");
        assert_eq!(coordinates("6", "-1", "1.mvt"), None);
        assert_eq!(coordinates("6", "1", "1.pbf"), None);
        assert_eq!(coordinates("99999999999", "1", "1.mvt"), None);
    }

    #[test]
    fn a_tile_path_never_reaches_a_log_with_its_place() {
        assert_eq!(
            loggable_path("/poi/12/13/4149/2815.mvt"),
            "/poi/12/13/x/y.mvt"
        );
        assert_eq!(loggable_path("/poi/tiles.json"), "/poi/tiles.json");
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
