//! Per-account and per-client quotas on actions (sign-ins, reviews, photos,
//! reports...), on top of the cost budget of `rate.rs`. A token bucket per
//! action and subject, in memory: no address is ever stored, and a restart
//! forgiving everyone is harmless. As in `rate.rs`, an IPv6 client also
//! draws on its /48's bucket, [`crate::rate::SITE_FACTOR`] times larger, so
//! rotating /64s inside one allocation does not multiply a quota.

use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

use uuid::Uuid;

use crate::{client::ClientKey, config::Quota};

/// What is counted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum Action {
    /// A sign-in challenge.
    Challenge,
    /// A sign-in.
    SignIn,
    /// An account created by a sign-in.
    AccountCreation,
    /// A recovery code tried.
    Recovery,
    /// A rating.
    Rating,
    /// A written review.
    Review,
    /// A photo.
    Photo,
    /// A content or issue report.
    Report,
    /// A confirmation.
    Confirmation,
    /// A new place or an edit.
    Submission,
    /// A change to favourite lists.
    List,
    /// Another change to the account.
    Account,
    /// A sponsorship or a nomination.
    Endorsement,
    /// A route computed.
    Route,
    /// Fuel stations ranked along a route, their detours measured by the
    /// routing engine.
    FuelRoute,
    /// Places and points of interest ranked along a route, their detours
    /// measured by the routing engine.
    AlongRoute,
    /// A road event reported, or said over.
    RoadReport,
    /// A road event reported, or said over, counted per client.
    RoadReportClient,
    /// A search that asks the geocoders.
    Geocode,
    /// A photo of the external community source downloaded for a client.
    ExternalPhoto,
    /// A read of the digests of a list's rows (`placeDigests`).
    PlaceDigests,
    /// A text the translation server translated for a client.
    Translate,
}

/// Who is counted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum Subject {
    /// A client address (an IPv4 address or an IPv6 /64).
    Client(ClientKey),
    /// An account.
    Account(Uuid),
}

#[derive(Debug, Clone, Copy)]
struct Bucket {
    tokens: f64,
    at: Instant,
}

/// Buckets tracked before full ones are dropped.
const SWEEP_AT: usize = 50_000;
/// Least time between two sweeps.
const SWEEP_EVERY: Duration = Duration::from_secs(10);

#[derive(Debug, Default)]
struct State {
    buckets: HashMap<(Action, Subject), Bucket>,
    swept: Option<Instant>,
}

/// Every quota's buckets.
#[derive(Debug)]
pub(crate) struct QuotaLimiter {
    quotas: crate::config::Quotas,
    state: Mutex<State>,
}

impl QuotaLimiter {
    pub(crate) fn new(quotas: crate::config::Quotas) -> Self {
        Self {
            quotas,
            state: Mutex::new(State::default()),
        }
    }

    fn quota(&self, action: Action) -> Quota {
        let q = &self.quotas;
        match action {
            Action::Challenge => q.challenge,
            Action::SignIn => q.sign_in,
            Action::AccountCreation => q.account_creation,
            Action::Recovery => q.recovery,
            Action::Rating => q.rating,
            Action::Review => q.review,
            Action::Photo => q.photo,
            Action::Report => q.report,
            Action::Confirmation => q.confirmation,
            Action::Submission => q.submission,
            Action::List => q.list,
            Action::Account => q.account,
            Action::Endorsement => q.endorsement,
            Action::Route => q.route,
            Action::FuelRoute => q.fuel_route,
            Action::AlongRoute => q.along_route,
            Action::RoadReport => q.road_report,
            Action::RoadReportClient => q.road_report_client,
            Action::Geocode => q.geocode,
            Action::ExternalPhoto => q.external_photo,
            Action::PlaceDigests => q.place_digests,
            Action::Translate => q.translate,
        }
    }

    /// Takes one use of `action` for `subject`, or says how long until one
    /// is free.
    ///
    /// # Errors
    ///
    /// The wait, when the quota is spent; nothing is taken.
    pub(crate) fn take(&self, action: Action, subject: Subject) -> Result<(), Duration> {
        self.take_at(action, subject, Instant::now())
    }

    /// Takes `n` uses of `action` for `subject` at once, for a request that
    /// counts as several (a read of an area), or says how long until all `n`
    /// are free. A bucket smaller than `n` serves the request once full and
    /// goes below empty: the next request waits for all `n`, so a request
    /// of several uses never costs less per use than single ones.
    ///
    /// # Errors
    ///
    /// The wait, when the quota lacks one of the `n`; nothing is taken.
    pub(crate) fn take_n(&self, action: Action, subject: Subject, n: u32) -> Result<(), Duration> {
        self.take_n_at(action, subject, n, Instant::now())
    }

    /// Capacity and refill rate (per second) of `subject`'s bucket for
    /// `action`.
    fn size(&self, action: Action, subject: Subject) -> (f64, f64) {
        let quota = self.quota(action);
        let factor = match subject {
            Subject::Client(key) if key.is_site() => crate::rate::SITE_FACTOR,
            _ => 1.0,
        };
        let capacity = f64::from(quota.count.max(1)) * factor;
        (capacity, capacity / quota.period.as_secs_f64().max(0.001))
    }

    pub(crate) fn take_at(
        &self,
        action: Action,
        subject: Subject,
        now: Instant,
    ) -> Result<(), Duration> {
        self.take_n_at(action, subject, 1, now)
    }

    /// [`Self::take_n`] at `now`.
    pub(crate) fn take_n_at(
        &self,
        action: Action,
        subject: Subject,
        n: u32,
        now: Instant,
    ) -> Result<(), Duration> {
        let site = match subject {
            Subject::Client(key) => key.site().map(Subject::Client),
            Subject::Account(_) => None,
        };
        let subjects = [Some(subject), site];
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.sweep(&mut state, now);
        let mut wait: Option<Duration> = None;
        for s in subjects.into_iter().flatten() {
            let (capacity, rate) = self.size(action, s);
            let b = state.buckets.entry((action, s)).or_insert(Bucket {
                tokens: capacity,
                at: now,
            });
            b.tokens =
                (b.tokens + now.saturating_duration_since(b.at).as_secs_f64() * rate).min(capacity);
            b.at = now;
            let needed = f64::from(n).min(capacity);
            if b.tokens < needed {
                let w = Duration::from_secs_f64(((needed - b.tokens) / rate).max(0.001));
                wait = Some(wait.map_or(w, |x| x.max(w)));
            }
        }
        if let Some(w) = wait {
            return Err(w);
        }
        for s in subjects.into_iter().flatten() {
            if let Some(b) = state.buckets.get_mut(&(action, s)) {
                b.tokens -= f64::from(n);
            }
        }
        Ok(())
    }

    /// Gives back a use taken for an attempt that turned out not to count
    /// (an account that was found, so none was created).
    pub(crate) fn give_back(&self, action: Action, subject: Subject) {
        let site = match subject {
            Subject::Client(key) => key.site().map(Subject::Client),
            Subject::Account(_) => None,
        };
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for s in [Some(subject), site].into_iter().flatten() {
            let (capacity, _) = self.size(action, s);
            if let Some(b) = state.buckets.get_mut(&(action, s)) {
                b.tokens = (b.tokens + 1.0).min(capacity);
            }
        }
    }

    fn sweep(&self, state: &mut State, now: Instant) {
        if state.buckets.len() < SWEEP_AT
            || state
                .swept
                .is_some_and(|t| now.saturating_duration_since(t) < SWEEP_EVERY)
        {
            return;
        }
        state.swept = Some(now);
        state.buckets.retain(|(action, subject), b| {
            let (capacity, rate) = self.size(*action, *subject);
            b.tokens + now.saturating_duration_since(b.at).as_secs_f64() * rate < capacity
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{Quota, Quotas};

    #[test]
    fn the_contract_s_limits_hold_and_refill() {
        let q = QuotaLimiter::new(Quotas::default());
        let client = Subject::Client(ClientKey::V4(1));
        let t = Instant::now();
        for i in 0..10 {
            assert!(q.take_at(Action::SignIn, client, t).is_ok(), "sign-in {i}");
        }
        let wait = q.take_at(Action::SignIn, client, t).unwrap_err();
        assert!(
            wait <= Duration::from_secs(7),
            "{wait:?}: one comes back every 6 s"
        );
        assert!(
            q.take_at(Action::SignIn, Subject::Client(ClientKey::V4(2)), t)
                .is_ok(),
            "another client is not affected"
        );
        assert!(
            q.take_at(Action::SignIn, client, t + Duration::from_secs(6))
                .is_ok()
        );

        let account = Subject::Account(Uuid::now_v7());
        for _ in 0..20 {
            q.take_at(Action::Review, account, t).unwrap();
        }
        assert!(
            q.take_at(Action::Review, account, t + Duration::from_secs(60))
                .is_err(),
            "20 reviews a day"
        );
        assert!(
            q.take_at(Action::Photo, account, t).is_ok(),
            "each action has its own quota"
        );
    }

    #[test]
    fn rotating_ipv6_64s_inside_one_48_shares_a_quota() {
        let q = QuotaLimiter::new(Quotas::default());
        let t = Instant::now();
        let in_site = |i: u64| Subject::Client(ClientKey::V6((0x2001_0db8_0001_u64 << 16) | i));
        // Five accounts an hour per /64, twenty per /48.
        let mut created = 0;
        for i in 0..100 {
            if q.take_at(Action::AccountCreation, in_site(i), t).is_ok() {
                created += 1;
            }
        }
        assert_eq!(
            created, 20,
            "a /48 creates four times a client's quota, not more"
        );
        let elsewhere = Subject::Client(ClientKey::V6(0x2001_0db8_0002_u64 << 16));
        assert!(q.take_at(Action::AccountCreation, elsewhere, t).is_ok());
    }

    fn quotas_of_place_digests(count: u32) -> Quotas {
        Quotas {
            place_digests: Quota {
                count,
                period: Duration::from_secs(3_600),
            },
            ..Quotas::default()
        }
    }

    #[test]
    fn several_uses_are_taken_whole_and_the_wait_covers_them_all() {
        let q = QuotaLimiter::new(quotas_of_place_digests(7));
        let client = Subject::Client(ClientKey::V4(3));
        let t = Instant::now();
        q.take_n_at(Action::PlaceDigests, client, 5, t).unwrap();
        let wait = q.take_n_at(Action::PlaceDigests, client, 5, t).unwrap_err();
        let three = Duration::from_secs_f64(3.0 * 3_600.0 / 7.0);
        assert!(
            wait >= three - Duration::from_millis(1) && wait <= three + Duration::from_secs(1),
            "{wait:?}: two left, three to come back"
        );
        assert!(q.take_at(Action::PlaceDigests, client, t).is_ok());
        assert!(
            q.take_at(Action::PlaceDigests, client, t).is_ok(),
            "the refused request took none of the two"
        );
        assert!(q.take_at(Action::PlaceDigests, client, t).is_err());
        assert!(
            q.take_n_at(Action::PlaceDigests, client, 5, t + wait)
                .is_err(),
            "two more came back meanwhile, five are needed"
        );
        assert!(
            q.take_n_at(
                Action::PlaceDigests,
                client,
                5,
                t + Duration::from_secs(2_572)
            )
            .is_ok()
        );
    }

    #[test]
    fn several_uses_draw_on_the_48_too() {
        let q = QuotaLimiter::new(quotas_of_place_digests(7));
        let t = Instant::now();
        let in_site = |i: u64| Subject::Client(ClientKey::V6((0x2001_0db8_0003_u64 << 16) | i));
        // Each /64 holds seven, the /48 four times as many: five requests of
        // five, then the /48 has three left.
        for i in 0..5 {
            q.take_n_at(Action::PlaceDigests, in_site(i), 5, t).unwrap();
        }
        let wait = q
            .take_n_at(Action::PlaceDigests, in_site(5), 5, t)
            .unwrap_err();
        let two = Duration::from_secs_f64(2.0 * 3_600.0 / 28.0);
        assert!(
            wait >= two - Duration::from_millis(1) && wait <= two + Duration::from_secs(1),
            "{wait:?}: a fresh /64 waits for its /48"
        );
        assert!(
            q.take_n_at(Action::PlaceDigests, in_site(5), 3, t).is_ok(),
            "the refused request took nothing from the /48"
        );
    }

    #[test]
    fn a_bucket_smaller_than_the_request_serves_it_full_and_waits_for_all_of_it() {
        let q = QuotaLimiter::new(quotas_of_place_digests(3));
        let client = Subject::Client(ClientKey::V4(4));
        let t = Instant::now();
        assert!(q.take_n_at(Action::PlaceDigests, client, 5, t).is_ok());
        assert!(q.take_at(Action::PlaceDigests, client, t).is_err());
        assert!(
            q.take_n_at(
                Action::PlaceDigests,
                client,
                5,
                t + Duration::from_secs(3_600)
            )
            .is_err(),
            "three back in the hour, five were taken: one use costs as much as alone"
        );
        assert!(
            q.take_n_at(
                Action::PlaceDigests,
                client,
                5,
                t + Duration::from_secs(6_000)
            )
            .is_ok(),
            "full again, it serves the request again"
        );
    }

    #[test]
    fn a_use_given_back_is_usable_again() {
        let q = QuotaLimiter::new(Quotas::default());
        let client = Subject::Client(ClientKey::V4(9));
        let t = Instant::now();
        for _ in 0..5 {
            q.take_at(Action::AccountCreation, client, t).unwrap();
        }
        assert!(q.take_at(Action::AccountCreation, client, t).is_err());
        q.give_back(Action::AccountCreation, client);
        assert!(q.take_at(Action::AccountCreation, client, t).is_ok());
    }
}
