//! Per-client budget, charged by query cost (a token bucket per client, in
//! memory: one API process serves the whole country, and a restart forgiving
//! everyone is harmless).
//!
//! Every request pays [`REQUEST_COST`] to start, refused or not, so a flood
//! of documents the guard rejects still drains its sender. Once a document is
//! validated, its complexity is taken too, or the request is refused with
//! the time to wait. A bucket refills continuously up to its burst. An IPv6
//! client also draws on its /48's bucket, [`SITE_FACTOR`] times larger, so
//! rotating through the /64s of one allocation buys little.

use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

use crate::client::ClientKey;

/// What starting a request costs, whatever follows: about what a small
/// query costs to parse and validate, so a client sends at most
/// `rate_per_second / REQUEST_COST` requests a second once its burst is
/// spent.
pub(crate) const REQUEST_COST: usize = 1_000;
/// How much larger the budget of an IPv6 /48 is than a client's.
pub(crate) const SITE_FACTOR: f64 = 4.0;
/// How many clients are tracked before idle ones are dropped: a full bucket
/// is the same as no bucket, so forgetting it changes nothing.
const SWEEP_AT: usize = 10_000;
/// Least time between two sweeps, so a crowd of active clients does not
/// make every call scan the whole map.
const SWEEP_EVERY: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, Copy)]
struct Bucket {
    tokens: f64,
    at: Instant,
}

#[derive(Debug)]
struct Buckets {
    map: HashMap<ClientKey, Bucket>,
    swept: Option<Instant>,
}

/// The budgets of every client.
#[derive(Debug)]
pub(crate) struct RateLimiter {
    burst: f64,
    per_second: f64,
    buckets: Mutex<Buckets>,
}

impl RateLimiter {
    /// Clients may spend `burst` at once and regain `per_second` each
    /// second.
    #[must_use]
    pub(crate) fn new(burst: u64, per_second: u64) -> Self {
        #[allow(
            clippy::cast_precision_loss,
            reason = "budgets are far below 2^52, where f64 stops being exact"
        )]
        let (burst, per_second) = (burst as f64, per_second.max(1) as f64);
        Self {
            burst,
            per_second,
            buckets: Mutex::new(Buckets {
                map: HashMap::new(),
                swept: None,
            }),
        }
    }

    /// Burst and refill rate of `key`'s bucket.
    fn size(&self, key: ClientKey) -> (f64, f64) {
        if key.is_site() {
            (self.burst * SITE_FACTOR, self.per_second * SITE_FACTOR)
        } else {
            (self.burst, self.per_second)
        }
    }

    /// Takes `cost` from `key`'s budget, and from its /48's, or says how
    /// long until it fits in both.
    ///
    /// # Errors
    ///
    /// The wait, when a budget holds less than `cost`; nothing is taken.
    pub(crate) fn charge(&self, key: ClientKey, cost: usize) -> Result<(), Duration> {
        self.charge_at(key, cost, Instant::now())
    }

    /// Takes [`REQUEST_COST`] for a request about to start.
    ///
    /// # Errors
    ///
    /// The wait, when the budget is spent.
    pub(crate) fn admit(&self, key: ClientKey) -> Result<(), Duration> {
        self.charge_at(key, REQUEST_COST, Instant::now())
    }

    pub(crate) fn charge_at(
        &self,
        key: ClientKey,
        cost: usize,
        now: Instant,
    ) -> Result<(), Duration> {
        #[allow(
            clippy::cast_precision_loss,
            reason = "a cost is bounded by the schema's complexity limit"
        )]
        let cost = cost as f64;
        // A poisoned lock only means a panic elsewhere; the buckets stay
        // usable numbers.
        let mut buckets = self
            .buckets
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.sweep(&mut buckets, now);
        let keys = [Some(key), key.site()];
        let mut wait: Option<Duration> = None;
        for k in keys.into_iter().flatten() {
            let (burst, rate) = self.size(k);
            let b = buckets.map.entry(k).or_insert(Bucket {
                tokens: burst,
                at: now,
            });
            b.tokens =
                (b.tokens + now.saturating_duration_since(b.at).as_secs_f64() * rate).min(burst);
            b.at = now;
            if b.tokens < cost {
                let w = Duration::from_secs_f64(((cost - b.tokens) / rate).max(0.001));
                wait = Some(wait.map_or(w, |x| x.max(w)));
            }
        }
        if let Some(w) = wait {
            return Err(w);
        }
        for k in keys.into_iter().flatten() {
            if let Some(b) = buckets.map.get_mut(&k) {
                b.tokens -= cost;
            }
        }
        Ok(())
    }

    /// Drops the buckets that have refilled, at most every [`SWEEP_EVERY`]
    /// and only once many clients are tracked.
    fn sweep(&self, buckets: &mut Buckets, now: Instant) {
        if buckets.map.len() < SWEEP_AT
            || buckets
                .swept
                .is_some_and(|t| now.saturating_duration_since(t) < SWEEP_EVERY)
        {
            return;
        }
        buckets.swept = Some(now);
        buckets.map.retain(|k, b| {
            let (burst, rate) = self.size(*k);
            b.tokens + now.saturating_duration_since(b.at).as_secs_f64() * rate < burst
        });
    }

    /// Clients tracked, for the tests of the sweep.
    #[cfg(test)]
    fn tracked(&self) -> usize {
        self.buckets
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .map
            .len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: ClientKey = ClientKey::V4(1);
    const B: ClientKey = ClientKey::V4(2);

    #[test]
    fn a_full_sync_passes_and_a_flood_waits() {
        // The defaults: two full syncs of France in the burst.
        let r = RateLimiter::new(2_000_000, 40_000);
        let t = Instant::now();
        for page in 0..16 {
            assert!(
                r.charge_at(A, REQUEST_COST + 55_000, t).is_ok(),
                "page {page} of a full sync must pass"
            );
        }
        let mut refused = None;
        for _ in 0..1_000 {
            if let Err(wait) = r.charge_at(A, 60_000, t) {
                refused = Some(wait);
                break;
            }
        }
        let wait = refused.expect("a flood is refused once the burst is spent");
        assert!(wait <= Duration::from_secs(2), "{wait:?}");
        assert!(
            r.charge_at(B, 60_000, t).is_ok(),
            "another client is not affected"
        );
        assert!(
            r.charge_at(A, 60_000, t + Duration::from_secs(2)).is_ok(),
            "the budget refills over time"
        );
    }

    #[test]
    fn starting_a_request_costs_even_when_it_is_refused_later() {
        let r = RateLimiter::new(5_000, 1_000);
        let t = Instant::now();
        let mut admitted = 0;
        while r.charge_at(A, REQUEST_COST, t).is_ok() {
            admitted += 1;
        }
        assert_eq!(
            admitted, 5,
            "documents refused by the guard still drain their sender"
        );
        assert!(
            r.charge_at(A, REQUEST_COST, t + Duration::from_secs(1))
                .is_ok()
        );
    }

    #[test]
    fn rotating_ipv6_64s_inside_one_48_draws_on_a_shared_budget() {
        let r = RateLimiter::new(10_000, 1);
        let t = Instant::now();
        let in_site = |i: u64| ClientKey::V6((0x2001_0db8_0001_u64 << 16) | i);
        // Four /64s empty the /48's budget (four times a client's)...
        for i in 0..4 {
            assert!(r.charge_at(in_site(i), 10_000, t).is_ok(), "/64 number {i}");
        }
        // ...so a fresh /64 of the same /48 is refused, another /48 is not.
        assert!(r.charge_at(in_site(4), 10_000, t).is_err());
        let elsewhere = ClientKey::V6(0x2001_0db8_0002_u64 << 16);
        assert!(r.charge_at(elsewhere, 10_000, t).is_ok());
    }

    #[test]
    fn idle_clients_are_forgotten_at_most_every_few_seconds() {
        let r = RateLimiter::new(1_000, 100);
        let t = Instant::now();
        for i in 0..u32::try_from(SWEEP_AT).unwrap() {
            r.charge_at(ClientKey::V4(i), 10, t).unwrap();
        }
        assert_eq!(r.tracked(), SWEEP_AT);
        let later = t + Duration::from_secs(60);
        r.charge_at(B, 10, later).unwrap();
        assert!(
            r.tracked() < 10,
            "refilled buckets are dropped: {}",
            r.tracked()
        );
        for i in 0..u32::try_from(SWEEP_AT).unwrap() {
            r.charge_at(ClientKey::V4(i), 10, later).unwrap();
        }
        r.charge_at(B, 10, later + Duration::from_secs(5)).unwrap();
        assert!(
            r.tracked() > SWEEP_AT / 2,
            "within {SWEEP_EVERY:?} of a sweep, no new scan of the map"
        );
    }
}
