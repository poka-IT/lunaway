//! Runtime configuration of the API, read from the environment.

use std::time::Duration;

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
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            min_app_version: "0.1.0".to_owned(),
            dev_cors: false,
            limits: Limits::default(),
        }
    }
}

/// The bounds of the public, anonymous API. The defaults let the app run
/// unhindered (a full sync of France is 16 `changes` pages in a row, the map
/// sends a viewport query per pan, the search a query per keystroke after a
/// debounce) and stop one client from taking the server.
///
/// Costs are the query complexity of `schema.rs`: a full sync page is about
/// 55 000, a viewport of 500 places about 29 000, a search about 6 000, and
/// every request pays 1 000 to start. The shape limits (depth, complexity,
/// page sizes) are part of the schema and live there.
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
    /// syncs of France back to back, with room for the map.
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
            max_cost_in_flight: 300_000,
            request_timeout: Duration::from_secs(20),
            db_queries_per_request: 2,
            db_pool_size: 16,
            db_acquire_timeout: Duration::from_secs(5),
            db_statement_timeout: Duration::from_secs(5),
            rate_burst: 2_000_000,
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
        Self {
            min_app_version,
            dev_cors: lookup("LUNAWAY_DEV_CORS").is_some_and(|v| v.trim() == "1"),
            limits: Limits::from_lookup(&lookup),
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
        // 16 pages of about 55 000 each, plus their start, measured on the
        // database of 2026-10-06 (15 606 places).
        let l = Limits::default();
        assert!(l.rate_burst >= 16 * 56_000 * 2, "two full syncs in a row");
        assert!(
            l.rate_per_second >= 30_000,
            "a 500-place viewport every second"
        );
    }

    #[test]
    fn a_burst_below_the_costliest_request_is_raised() {
        let l = with(&[("LUNAWAY_RATE_BURST", "1000")]).limits;
        assert_eq!(l.rate_burst, MIN_RATE_BURST);
    }
}
