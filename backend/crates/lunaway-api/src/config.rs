//! Runtime configuration of the API, read from the environment.

use std::{path::PathBuf, time::Duration};

use lunaway_domain::community::trust::Thresholds;

/// What the app is told about the server's policy (`Query.config`), and how
/// the server protects itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiConfig {
    /// Oldest app version the server still serves correctly.
    pub min_app_version: String,
    /// Whether browser pages served from this machine (`localhost`,
    /// `127.0.0.1`, any port) may call the API, for web development.
    pub dev_cors: bool,
    /// Bounds on requests, clients and the database.
    pub limits: Limits,
    /// Sessions and sign-in challenges.
    pub auth: AuthConfig,
    /// What each account and each client may do per period.
    pub quotas: Quotas,
    /// The numbers behind the trust levels.
    pub trust: Thresholds,
    /// Where photos go and how they are served.
    pub media: MediaConfig,
    /// The routing engine behind `Query.route`.
    pub routing: RoutingConfig,
    /// The map tiles of the points of interest.
    pub tiles: TilesConfig,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            min_app_version: "0.1.0".to_owned(),
            dev_cors: false,
            limits: Limits::default(),
            auth: AuthConfig::default(),
            quotas: Quotas::default(),
            trust: Thresholds::default(),
            media: MediaConfig::default(),
            routing: RoutingConfig::default(),
            tiles: TilesConfig::default(),
        }
    }
}

/// The vector tiles of the points of interest (`GET /poi/...`): where the
/// API says they are, and how much work they may take.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TilesConfig {
    /// The API's public URL, without a trailing slash, which the TileJSON
    /// names in its tile URLs (`LUNAWAY_PUBLIC_URL`, default
    /// `https://api.lunaway.net`).
    pub public_url: String,
    /// Bytes of tiles kept in memory, the oldest evicted first
    /// (`LUNAWAY_POI_TILE_CACHE_MB`, 64 MiB): the same tiles of a city are
    /// asked by every device that looks at it.
    pub cache_bytes: usize,
    /// Tiles built at once by the database (`LUNAWAY_POI_TILE_CONCURRENCY`,
    /// 4): a tile of a dense city takes tens of milliseconds, a cluster
    /// tile of a whole region a few hundred.
    pub concurrency: usize,
    /// Most points in one tile (`LUNAWAY_POI_TILE_MAX_FEATURES`, 4000): the
    /// densest tile of Paris at zoom 13 held 1507 on 2026-10-06.
    pub max_features: i64,
}

impl Default for TilesConfig {
    fn default() -> Self {
        Self {
            public_url: "https://api.lunaway.net".to_owned(),
            cache_bytes: 64 * 1024 * 1024,
            concurrency: 4,
            max_features: 4_000,
        }
    }
}

impl TilesConfig {
    fn from_lookup(lookup: &impl Fn(&str) -> Option<String>) -> Self {
        let d = Self::default();
        let num = |key: &str| lookup(key).and_then(|v| v.trim().parse::<usize>().ok());
        Self {
            public_url: lookup("LUNAWAY_PUBLIC_URL")
                .map(|u| u.trim().trim_end_matches('/').to_owned())
                .filter(|u| u.starts_with("https://") || u.starts_with("http://"))
                .unwrap_or(d.public_url),
            cache_bytes: num("LUNAWAY_POI_TILE_CACHE_MB")
                .filter(|n| *n <= 4_096)
                .map_or(d.cache_bytes, |mb| mb * 1024 * 1024),
            concurrency: num("LUNAWAY_POI_TILE_CONCURRENCY")
                .filter(|n| (1..=64).contains(n))
                .unwrap_or(d.concurrency),
            max_features: num("LUNAWAY_POI_TILE_MAX_FEATURES")
                .and_then(|n| i64::try_from(n).ok())
                .filter(|n| (100..=50_000).contains(n))
                .unwrap_or(d.max_features),
        }
    }
}

/// The routing engine (Valhalla on the same host) and how hard the API may
/// use it. A route costs the engine tens to hundreds of milliseconds of a
/// thread and returns up to a few megabytes, so it has its own quota per
/// client (`Quotas::route`) and a cap on the calls in flight, whoever sends
/// them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoutingConfig {
    /// The engine's base URL (`LUNAWAY_VALHALLA_URL`, default
    /// `http://127.0.0.1:8002`). Only a loopback address is accepted: the
    /// engine is never reached over a network, and a position sent to it
    /// never leaves the host. `None` when the setting names another host:
    /// routing then answers `UNAVAILABLE`.
    pub valhalla_url: Option<String>,
    /// Longest wait for one answer of the engine
    /// (`LUNAWAY_VALHALLA_TIMEOUT_MS`, 8 s).
    pub timeout: Duration,
    /// Engine calls in flight at once, all clients together
    /// (`LUNAWAY_ROUTING_CONCURRENCY`, 4: the engine's threads).
    pub concurrency: usize,
    /// How long a route waits for a free call before `RATE_LIMITED`
    /// (`LUNAWAY_ROUTING_QUEUE_WAIT_MS`, 1 s): short, because a waiting
    /// route holds its share of the API's cost in flight.
    pub queue_wait: Duration,
}

/// The engine's address on the backend (`infra/routing/valhalla.container`).
pub const DEFAULT_VALHALLA_URL: &str = "http://127.0.0.1:8002";

impl Default for RoutingConfig {
    fn default() -> Self {
        Self {
            valhalla_url: Some(DEFAULT_VALHALLA_URL.to_owned()),
            timeout: Duration::from_secs(8),
            concurrency: 4,
            queue_wait: Duration::from_secs(1),
        }
    }
}

/// Whether `url` is plain HTTP to a loopback address, with no user, path,
/// query or fragment: the only engine the API talks to.
#[must_use]
pub fn is_loopback_url(url: &str) -> bool {
    let Ok(u) = reqwest::Url::parse(url) else {
        return false;
    };
    let loopback = u.host_str().is_some_and(|h| {
        h == "localhost"
            || h.trim_start_matches('[')
                .trim_end_matches(']')
                .parse::<std::net::IpAddr>()
                .is_ok_and(|ip| ip.is_loopback())
    });
    u.scheme() == "http"
        && loopback
        && u.username().is_empty()
        && u.password().is_none()
        && u.path() == "/"
        && u.query().is_none()
        && u.fragment().is_none()
}

impl RoutingConfig {
    fn from_lookup(lookup: &impl Fn(&str) -> Option<String>) -> Self {
        let d = Self::default();
        let millis = |key: &str, default: Duration| {
            lookup(key)
                .and_then(|v| v.trim().parse::<u64>().ok())
                .filter(|n| *n > 0)
                .map_or(default, Duration::from_millis)
        };
        let valhalla_url = match lookup("LUNAWAY_VALHALLA_URL").map(|v| v.trim().to_owned()) {
            None => d.valhalla_url,
            Some(v) if v.is_empty() => d.valhalla_url,
            Some(v) if is_loopback_url(&v) => Some(v.trim_end_matches('/').to_owned()),
            Some(_) => {
                tracing::error!(
                    "LUNAWAY_VALHALLA_URL is not a loopback http URL; routing is turned off"
                );
                None
            }
        };
        Self {
            valhalla_url,
            timeout: millis("LUNAWAY_VALHALLA_TIMEOUT_MS", d.timeout),
            concurrency: lookup("LUNAWAY_ROUTING_CONCURRENCY")
                .and_then(|v| v.trim().parse::<usize>().ok())
                .filter(|n| (1..=64).contains(n))
                .unwrap_or(d.concurrency),
            queue_wait: millis("LUNAWAY_ROUTING_QUEUE_WAIT_MS", d.queue_wait),
        }
    }
}

/// Sessions and sign-in challenges.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AuthConfig {
    /// How long a session lives without use; each use pushes it back
    /// (`LUNAWAY_SESSION_DAYS`, 60).
    pub session_ttl: Duration,
    /// How long a sign-in challenge may be answered (five minutes).
    pub challenge_ttl: Duration,
    /// Answered challenges remembered at once (until they expire), all
    /// clients together: past it, sign-ins wait for old ones to expire
    /// (`LUNAWAY_MAX_CHALLENGES`). Handing a challenge out stores nothing.
    pub max_challenges: usize,
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            session_ttl: Duration::from_secs(60 * 86_400),
            challenge_ttl: Duration::from_secs(300),
            max_challenges: 1_000_000,
        }
    }
}

/// A number of uses per period: a bucket of `count` that refills over
/// `period`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Quota {
    /// Uses allowed at once.
    pub count: u32,
    /// Time to regain them all.
    pub period: Duration,
}

impl Quota {
    const fn per(count: u32, seconds: u64) -> Self {
        Self {
            count,
            period: Duration::from_secs(seconds),
        }
    }
}

const MINUTE: u64 = 60;
const HOUR: u64 = 3_600;
const DAY: u64 = 86_400;

/// What a client (an address) or an account may do per period, on top of
/// the cost budget. The state stays in memory, keyed by account id or by
/// the client key; no address is stored. Each is read from
/// `LUNAWAY_QUOTA_<NAME>` as `<count>/<seconds>`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Quotas {
    /// Sign-in challenges per client (`CHALLENGE`).
    pub challenge: Quota,
    /// Sign-ins per client (`SIGN_IN`): 10 a minute.
    pub sign_in: Quota,
    /// Accounts created per client (`ACCOUNT_CREATION`): 5 an hour.
    pub account_creation: Quota,
    /// Recovery code attempts per client (`RECOVERY`): 5 an hour.
    pub recovery: Quota,
    /// Ratings per account (`RATING`).
    pub rating: Quota,
    /// Written reviews per account (`REVIEW`): 20 a day.
    pub review: Quota,
    /// Photos per account (`PHOTO`): 30 a day.
    pub photo: Quota,
    /// Content and issue reports per account (`REPORT`): 50 a day.
    pub report: Quota,
    /// Confirmations per account (`CONFIRMATION`).
    pub confirmation: Quota,
    /// New places and edits per account (`SUBMISSION`).
    pub submission: Quota,
    /// Changes to favourite lists per account (`LIST`).
    pub list: Quota,
    /// Other account changes (profile, recovery code, mutes, devices) per
    /// account (`ACCOUNT`).
    pub account: Quota,
    /// Accounts a level-2 account sponsors, or a level-4 account nominates
    /// (`ENDORSEMENT`): each sponsorship makes a level-1 account at once.
    pub endorsement: Quota,
    /// Routes per client (`ROUTE`): 30 every ten minutes, recalculations
    /// included. A driver off course is recalculated at most every 10 s
    /// (`plan/research/07-navigation.md`, C.3), so the burst covers five
    /// minutes lost in a town.
    pub route: Quota,
    /// Searches of fuel along a route per client (`FUEL_ROUTE`): 30 every
    /// ten minutes, as routes. Each measures up to 20 detours with the
    /// routing engine, in one or a few matrix calls.
    pub fuel_route: Quota,
    /// Road events reported or said over, per account
    /// (`LUNAWAY_QUOTA_ROAD_REPORT`, 30 a day): a driver meets a few a
    /// day, and a burst of reports is what a vandal does.
    pub road_report: Quota,
    /// Road events reported or said over, per client
    /// (`LUNAWAY_QUOTA_ROAD_REPORT_CLIENT`, 100 a day): accounts are cheap
    /// to create, so one network must not report for a crowd. A campsite
    /// or a mobile operator puts several drivers behind one address, hence
    /// more than one account's quota.
    pub road_report_client: Quota,
}

impl Default for Quotas {
    fn default() -> Self {
        Self {
            challenge: Quota::per(30, MINUTE),
            sign_in: Quota::per(10, MINUTE),
            account_creation: Quota::per(5, HOUR),
            recovery: Quota::per(5, HOUR),
            rating: Quota::per(200, DAY),
            review: Quota::per(20, DAY),
            photo: Quota::per(30, DAY),
            report: Quota::per(50, DAY),
            confirmation: Quota::per(200, DAY),
            submission: Quota::per(30, DAY),
            list: Quota::per(2_000, DAY),
            account: Quota::per(100, DAY),
            endorsement: Quota::per(5, DAY),
            route: Quota::per(30, 10 * MINUTE),
            fuel_route: Quota::per(30, 10 * MINUTE),
            road_report: Quota::per(30, DAY),
            road_report_client: Quota::per(100, DAY),
        }
    }
}

impl Quotas {
    fn from_lookup(lookup: &impl Fn(&str) -> Option<String>) -> Self {
        let d = Self::default();
        let read = |name: &str, default: Quota| {
            lookup(&format!("LUNAWAY_QUOTA_{name}"))
                .and_then(|v| {
                    let (count, seconds) = v.trim().split_once('/')?;
                    let count = count.trim().parse::<u32>().ok().filter(|n| *n > 0)?;
                    let seconds = seconds.trim().parse::<u64>().ok().filter(|n| *n > 0)?;
                    Some(Quota::per(count, seconds))
                })
                .unwrap_or(default)
        };
        Self {
            challenge: read("CHALLENGE", d.challenge),
            sign_in: read("SIGN_IN", d.sign_in),
            account_creation: read("ACCOUNT_CREATION", d.account_creation),
            recovery: read("RECOVERY", d.recovery),
            rating: read("RATING", d.rating),
            review: read("REVIEW", d.review),
            photo: read("PHOTO", d.photo),
            report: read("REPORT", d.report),
            confirmation: read("CONFIRMATION", d.confirmation),
            submission: read("SUBMISSION", d.submission),
            list: read("LIST", d.list),
            account: read("ACCOUNT", d.account),
            endorsement: read("ENDORSEMENT", d.endorsement),
            route: read("ROUTE", d.route),
            fuel_route: read("FUEL_ROUTE", d.fuel_route),
            road_report: read("ROAD_REPORT", d.road_report),
            road_report_client: read("ROAD_REPORT_CLIENT", d.road_report_client),
        }
    }
}

/// Where photos are stored and from where they are served.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaConfig {
    /// Root of the content-addressed files (`LUNAWAY_MEDIA_DIR`; default
    /// the repository's `data/media`; production `/srv/data/media`, which
    /// Caddy serves under `/media/`).
    pub dir: PathBuf,
    /// Public URL of that root, ending with `/`
    /// (`LUNAWAY_MEDIA_BASE_URL`, default `https://api.lunaway.net/media/`).
    pub base_url: String,
    /// Photos processed at once: decoding holds up to a few hundred
    /// megabytes (`LUNAWAY_MEDIA_WORKERS`, 2).
    pub workers: usize,
    /// Largest upload body, bytes (`LUNAWAY_MAX_UPLOAD_BYTES`, 10 MiB);
    /// Caddy allows the same on `/upload` only.
    pub max_upload_bytes: usize,
}

impl Default for MediaConfig {
    fn default() -> Self {
        Self {
            dir: PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../data/media")),
            base_url: "https://api.lunaway.net/media/".to_owned(),
            workers: 2,
            max_upload_bytes: 10 * 1024 * 1024,
        }
    }
}

impl MediaConfig {
    fn from_lookup(lookup: &impl Fn(&str) -> Option<String>) -> Self {
        let d = Self::default();
        let text = |key: &str| {
            lookup(key)
                .map(|v| v.trim().to_owned())
                .filter(|v| !v.is_empty())
        };
        let base_url = text("LUNAWAY_MEDIA_BASE_URL")
            .filter(|u| u.starts_with("https://") || u.starts_with("http://"))
            .map_or(d.base_url, |u| {
                if u.ends_with('/') { u } else { format!("{u}/") }
            });
        Self {
            dir: text("LUNAWAY_MEDIA_DIR").map_or(d.dir, PathBuf::from),
            base_url,
            workers: text("LUNAWAY_MEDIA_WORKERS")
                .and_then(|v| v.parse::<usize>().ok())
                .filter(|n| (1..=16).contains(n))
                .unwrap_or(d.workers),
            max_upload_bytes: text("LUNAWAY_MAX_UPLOAD_BYTES")
                .and_then(|v| v.parse::<usize>().ok())
                .filter(|n| *n > 0)
                .unwrap_or(d.max_upload_bytes),
        }
    }

    /// The public URL of a file stored at `relative`.
    #[must_use]
    pub fn url(&self, relative: &str) -> String {
        format!("{}{relative}", self.base_url)
    }
}

fn thresholds_from_lookup(lookup: &impl Fn(&str) -> Option<String>) -> Thresholds {
    let d = Thresholds::default();
    let num = |key: &str, default: u32| {
        lookup(key)
            .and_then(|v| v.trim().parse::<u32>().ok())
            .unwrap_or(default)
    };
    Thresholds {
        tl1_min_age_days: num("LUNAWAY_TL1_MIN_AGE_DAYS", d.tl1_min_age_days),
        tl1_min_confirmations: num("LUNAWAY_TL1_MIN_CONFIRMATIONS", d.tl1_min_confirmations),
        tl2_min_age_days: num("LUNAWAY_TL2_MIN_AGE_DAYS", d.tl2_min_age_days),
        tl2_min_contributions: num("LUNAWAY_TL2_MIN_CONTRIBUTIONS", d.tl2_min_contributions),
        tl3_min_active_days: num("LUNAWAY_TL3_MIN_ACTIVE_DAYS", d.tl3_min_active_days),
        tl3_min_contributions: num("LUNAWAY_TL3_MIN_CONTRIBUTIONS", d.tl3_min_contributions),
    }
}

/// The bounds of the public, anonymous API. The defaults let the app run
/// unhindered (a full sync of France is 16 `changes` pages in a row, the map
/// sends a viewport query per pan, the search a query per keystroke after a
/// debounce) and stop one client from taking the server.
///
/// Costs are the query complexity of `schema.rs`: the app's sync page is
/// 67 000 (with descriptions, ratings and links; measured by
/// `tests/budget.rs`), a viewport of 500 places about 29 000, a search
/// about 6 000, a place's photos and first reviews about 15 000, and every
/// request pays 1 000 to start. The shape limits (depth, complexity, page
/// sizes) are part of the schema and live there.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// Largest request body, bytes (`LUNAWAY_MAX_BODY_BYTES`).
    pub max_body_bytes: usize,
    /// Largest response before compression, bytes
    /// (`LUNAWAY_MAX_RESPONSE_BYTES`): a full sync page is 2.3 MB.
    pub max_response_bytes: usize,
    /// Requests served at once; more wait for a slot
    /// (`LUNAWAY_MAX_CONCURRENT_REQUESTS`).
    pub max_concurrent_requests: usize,
    /// How long a request waits for a slot before a `503`
    /// (`LUNAWAY_QUEUE_WAIT_MS`).
    pub queue_wait: Duration,
    /// Total cost of the requests running at once, whoever sends them
    /// (`LUNAWAY_MAX_COST_IN_FLIGHT`): the memory a request holds grows with
    /// its cost, about 20 MB for a full sync page, so this bounds the API's
    /// memory under a crowd of clients each within its budget.
    pub max_cost_in_flight: usize,
    /// Longest a request may run (`LUNAWAY_REQUEST_TIMEOUT_MS`).
    pub request_timeout: Duration,
    /// Database queries one request runs at once
    /// (`LUNAWAY_DB_QUERIES_PER_REQUEST`): aliases of one field do not
    /// take the whole pool.
    pub db_queries_per_request: usize,
    /// Connections of the database pool (`LUNAWAY_DB_POOL_SIZE`).
    pub db_pool_size: u32,
    /// How long a query waits for a pooled connection
    /// (`LUNAWAY_DB_ACQUIRE_TIMEOUT_MS`).
    pub db_acquire_timeout: Duration,
    /// Server-side limit of one statement (`LUNAWAY_DB_STATEMENT_TIMEOUT_MS`).
    pub db_statement_timeout: Duration,
    /// Cost a client may spend at once (`LUNAWAY_RATE_BURST`): two full
    /// syncs of France back to back (16 pages of 68 000 each), with room
    /// for the app to select the other feed fields and for the map.
    pub rate_burst: u64,
    /// Cost a client regains per second (`LUNAWAY_RATE_PER_SECOND`): a
    /// viewport query per second with search beside it.
    pub rate_per_second: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_body_bytes: 64 * 1024,
            max_response_bytes: 8 * 1024 * 1024,
            max_concurrent_requests: 64,
            queue_wait: Duration::from_secs(2),
            max_cost_in_flight: 400_000,
            request_timeout: Duration::from_secs(20),
            db_queries_per_request: 2,
            db_pool_size: 16,
            db_acquire_timeout: Duration::from_secs(5),
            db_statement_timeout: Duration::from_secs(5),
            rate_burst: 3_000_000,
            rate_per_second: 40_000,
        }
    }
}

/// Least burst read from the environment: the costliest request allowed.
const MIN_RATE_BURST: u64 = (crate::schema::MAX_COMPLEXITY + crate::rate::REQUEST_COST) as u64;

impl Limits {
    /// Reads every `LUNAWAY_*` limit through `lookup`; a missing, empty or
    /// unreadable value (or zero) keeps the default, so a typo cannot turn
    /// a bound off.
    #[must_use]
    pub fn from_lookup(lookup: &impl Fn(&str) -> Option<String>) -> Self {
        let d = Self::default();
        let num = |key: &str| -> Option<u64> {
            lookup(key)
                .and_then(|v| v.trim().parse::<u64>().ok())
                .filter(|n| *n > 0)
        };
        let size = |key: &str, default: usize| {
            num(key)
                .and_then(|n| usize::try_from(n).ok())
                .unwrap_or(default)
        };
        let millis = |key: &str, default: Duration| num(key).map_or(default, Duration::from_millis);
        Self {
            max_body_bytes: size("LUNAWAY_MAX_BODY_BYTES", d.max_body_bytes),
            max_response_bytes: size("LUNAWAY_MAX_RESPONSE_BYTES", d.max_response_bytes),
            max_concurrent_requests: size(
                "LUNAWAY_MAX_CONCURRENT_REQUESTS",
                d.max_concurrent_requests,
            ),
            queue_wait: millis("LUNAWAY_QUEUE_WAIT_MS", d.queue_wait),
            max_cost_in_flight: size("LUNAWAY_MAX_COST_IN_FLIGHT", d.max_cost_in_flight)
                .max(crate::schema::MAX_COMPLEXITY),
            request_timeout: millis("LUNAWAY_REQUEST_TIMEOUT_MS", d.request_timeout),
            db_queries_per_request: size(
                "LUNAWAY_DB_QUERIES_PER_REQUEST",
                d.db_queries_per_request,
            ),
            db_pool_size: num("LUNAWAY_DB_POOL_SIZE")
                .and_then(|n| u32::try_from(n).ok())
                .unwrap_or(d.db_pool_size),
            db_acquire_timeout: millis("LUNAWAY_DB_ACQUIRE_TIMEOUT_MS", d.db_acquire_timeout),
            db_statement_timeout: millis("LUNAWAY_DB_STATEMENT_TIMEOUT_MS", d.db_statement_timeout),
            // Below one request of the largest cost plus its start, that
            // request would be refused forever with a finite Retry-After.
            rate_burst: num("LUNAWAY_RATE_BURST")
                .unwrap_or(d.rate_burst)
                .max(MIN_RATE_BURST),
            rate_per_second: num("LUNAWAY_RATE_PER_SECOND").unwrap_or(d.rate_per_second),
        }
    }
}

impl ApiConfig {
    /// Reads `LUNAWAY_MIN_APP_VERSION`, `LUNAWAY_DEV_CORS` (`1` opens the API
    /// to local pages) and the limits through `lookup`, which is
    /// `std::env::var(..).ok()` in the server and a map in tests.
    #[must_use]
    pub fn from_lookup(lookup: impl Fn(&str) -> Option<String>) -> Self {
        let default = Self::default();
        let min_app_version = lookup("LUNAWAY_MIN_APP_VERSION")
            .map(|v| v.trim().to_owned())
            .filter(|v| !v.is_empty())
            .unwrap_or(default.min_app_version);
        let auth_default = AuthConfig::default();
        let auth = AuthConfig {
            session_ttl: lookup("LUNAWAY_SESSION_DAYS")
                .and_then(|v| v.trim().parse::<u64>().ok())
                .filter(|d| (1..=365).contains(d))
                .map_or(auth_default.session_ttl, |d| {
                    Duration::from_secs(d * 86_400)
                }),
            max_challenges: lookup("LUNAWAY_MAX_CHALLENGES")
                .and_then(|v| v.trim().parse::<usize>().ok())
                .filter(|n| *n > 0)
                .unwrap_or(auth_default.max_challenges),
            ..auth_default
        };
        Self {
            min_app_version,
            dev_cors: lookup("LUNAWAY_DEV_CORS").is_some_and(|v| v.trim() == "1"),
            limits: Limits::from_lookup(&lookup),
            auth,
            quotas: Quotas::from_lookup(&lookup),
            trust: thresholds_from_lookup(&lookup),
            media: MediaConfig::from_lookup(&lookup),
            routing: RoutingConfig::from_lookup(&lookup),
            tiles: TilesConfig::from_lookup(&lookup),
        }
    }

    /// Reads the process environment.
    #[must_use]
    pub fn from_env() -> Self {
        Self::from_lookup(|k| std::env::var(k).ok())
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn with(pairs: &[(&str, &str)]) -> ApiConfig {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
        ApiConfig::from_lookup(|k| map.get(k).cloned())
    }

    #[test]
    fn local_origins_need_the_dev_switch() {
        assert!(!with(&[]).dev_cors);
        assert!(
            !with(&[("LUNAWAY_DEV_CORS", "true")]).dev_cors,
            "only 1 switches it on"
        );
        assert!(with(&[("LUNAWAY_DEV_CORS", "1")]).dev_cors);
    }

    #[test]
    fn the_minimum_version_has_a_default() {
        assert_eq!(with(&[]).min_app_version, "0.1.0");
        assert_eq!(
            with(&[("LUNAWAY_MIN_APP_VERSION", "1.2.0")]).min_app_version,
            "1.2.0"
        );
        assert_eq!(
            with(&[("LUNAWAY_MIN_APP_VERSION", " ")]).min_app_version,
            "0.1.0"
        );
    }

    #[test]
    fn limits_are_read_and_a_bad_value_keeps_the_default() {
        let l = with(&[
            ("LUNAWAY_RATE_BURST", "500000"),
            ("LUNAWAY_REQUEST_TIMEOUT_MS", "1500"),
            ("LUNAWAY_MAX_BODY_BYTES", "0"),
            ("LUNAWAY_DB_POOL_SIZE", "lots"),
        ])
        .limits;
        assert_eq!(l.rate_burst, 500_000);
        assert_eq!(l.request_timeout, Duration::from_millis(1500));
        assert_eq!(
            l.max_body_bytes,
            Limits::default().max_body_bytes,
            "zero would turn the bound off"
        );
        assert_eq!(l.db_pool_size, Limits::default().db_pool_size);
    }

    #[test]
    fn the_default_budget_covers_a_full_sync_of_france() {
        // 16 pages of 67 000 each, plus their start (France, 15 606 places
        // on 2026-10-06; the page cost is measured by tests/budget.rs).
        let l = Limits::default();
        assert!(l.rate_burst >= 16 * 68_000 * 2, "two full syncs in a row");
        assert!(
            l.rate_per_second >= 30_000,
            "a 500-place viewport every second"
        );
    }

    #[test]
    fn quotas_thresholds_and_media_are_read() {
        let c = with(&[
            ("LUNAWAY_QUOTA_REVIEW", "5/60"),
            ("LUNAWAY_QUOTA_PHOTO", "lots"),
            ("LUNAWAY_TL1_MIN_AGE_DAYS", "0"),
            ("LUNAWAY_MEDIA_BASE_URL", "http://127.0.0.1:8080/media"),
            ("LUNAWAY_SESSION_DAYS", "9999"),
        ]);
        assert_eq!(c.quotas.review, Quota::per(5, 60));
        assert_eq!(
            c.quotas.photo,
            Quotas::default().photo,
            "a bad value keeps the default"
        );
        assert_eq!(
            c.quotas.sign_in,
            Quota::per(10, 60),
            "the contract: 10 a minute"
        );
        assert_eq!(c.quotas.account_creation, Quota::per(5, 3_600));
        assert_eq!(c.trust.tl1_min_age_days, 0);
        assert_eq!(
            c.media.url("photos/a.webp"),
            "http://127.0.0.1:8080/media/photos/a.webp"
        );
        assert_eq!(c.auth.session_ttl, Duration::from_secs(60 * 86_400));
    }

    #[test]
    fn the_routing_engine_must_be_on_loopback() {
        for ok in [
            "http://127.0.0.1:8002",
            "http://127.0.0.1:8002/",
            "http://localhost:8002",
            "http://[::1]:8002",
            "http://127.0.0.1",
        ] {
            assert!(is_loopback_url(ok), "{ok}");
        }
        for bad in [
            "https://127.0.0.1:8002",
            "http://10.42.0.2:8002",
            "http://valhalla.example:8002",
            "http://127.0.0.1:8002/route",
            "http://user@127.0.0.1:8002",
            "http://127.0.0.1.example.com:8002",
            "http://127.0.0.1:80x",
        ] {
            assert!(!is_loopback_url(bad), "{bad}");
        }
        let c = with(&[("LUNAWAY_VALHALLA_URL", "http://10.42.0.3:8002")]);
        assert_eq!(
            c.routing.valhalla_url, None,
            "another host turns routing off"
        );
        let c = with(&[
            ("LUNAWAY_VALHALLA_URL", "http://127.0.0.1:9002/"),
            ("LUNAWAY_QUOTA_ROUTE", "5/60"),
        ]);
        assert_eq!(
            c.routing.valhalla_url.as_deref(),
            Some("http://127.0.0.1:9002")
        );
        assert_eq!(c.quotas.route, Quota::per(5, 60));
        assert_eq!(with(&[]).routing, RoutingConfig::default());
    }

    #[test]
    fn a_burst_below_the_costliest_request_is_raised() {
        let l = with(&[("LUNAWAY_RATE_BURST", "1000")]).limits;
        assert_eq!(l.rate_burst, MIN_RATE_BURST);
    }
}
