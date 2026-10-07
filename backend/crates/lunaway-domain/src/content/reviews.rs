//! Which open reviews a place keeps when it is offered more than it shows.
//!
//! On Mangrove anyone signs a review with a key made a second earlier, and
//! a place keeps at most a few reviews: newest first, ten new keys would
//! push every real review off a place in one run. Lunaway weighs a key by
//! the history it earned here instead, which no one can backdate: when a
//! review it signed was first kept (`content_review_keys`). Keys kept
//! before rank first, oldest first; a key never kept is new, and a place
//! gains few new keys per run, and a run few new keys in all, so a burst
//! of fresh keys waits in line behind the reviews already shown, run
//! after run, where the reports and the operator see it
//! (`docs/data-sources.md`, "Mangrove reviews").

use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet},
};

use chrono::{DateTime, Utc};

/// How many reviews a place keeps, and how fast new keys reach it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReviewCaps {
    /// Reviews a place keeps at most.
    pub per_place: usize,
    /// Reviews of new keys a place gains per run at most.
    pub new_keys_per_place: usize,
    /// New keys a run lets in at most, every place together.
    pub new_keys_per_run: usize,
}

/// The caps of the weekly Mangrove run: ten reviews a place, two new keys
/// a place, fifty new keys a run. The whole of Mangrove held 10 803
/// reviews on 2026-10-07, every subject together: fifty new authors a
/// week on Lunaway's places is above what reviewers write there, and far
/// below what a script makes.
pub const MANGROVE_CAPS: ReviewCaps = ReviewCaps {
    per_place: 10,
    new_keys_per_place: 2,
    new_keys_per_run: 50,
};

/// A review offered to a place, as the choice weighs it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewOffer<'a, P> {
    /// The place it is about.
    pub place: P,
    /// The hash of the key that signed it; `None` counts as a new key of
    /// its own.
    pub key: Option<&'a str>,
    /// When it says it was written (the author sets it).
    pub written_at: DateTime<Utc>,
    /// When Lunaway first kept a review signed by its key, on any place;
    /// `None` for a key never kept: a new key.
    pub key_since: Option<DateTime<Utc>>,
    /// Other places this run offers a review by the same key to: a new key
    /// that reviewed several places ranks before one made for a single
    /// place.
    pub elsewhere: usize,
}

/// What [`pick_reviews`] kept.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Picked {
    /// The offers kept, by their index, in increasing order.
    pub kept: Vec<usize>,
    /// New keys let in by this run, each counted once.
    pub new_keys: usize,
    /// Reviews of new keys left for a later run by the new-key caps,
    /// though their place had room.
    pub deferred: usize,
}

/// The reviews each place keeps among `offers`: one per key and place
/// (its newest), at most `caps.per_place` a place. Keys kept before come
/// first, the oldest first, then the newest of their reviews; then new
/// keys, those that reviewed most other places first, then the newest,
/// at most `caps.new_keys_per_place` a place and `caps.new_keys_per_run`
/// in all.
#[must_use]
pub fn pick_reviews<P: Ord + Copy>(offers: &[ReviewOffer<'_, P>], caps: ReviewCaps) -> Picked {
    let mut order: Vec<usize> = (0..offers.len()).collect();
    order.sort_by_key(|&i| {
        let o = &offers[i];
        (
            o.key_since.is_none(),
            o.key_since,
            Reverse(o.elsewhere),
            Reverse(o.written_at),
            i,
        )
    });
    let mut seen: BTreeSet<(P, &str)> = BTreeSet::new();
    let mut shown: BTreeMap<P, usize> = BTreeMap::new();
    let mut new_on_place: BTreeMap<P, usize> = BTreeMap::new();
    let mut new_keys: BTreeSet<&str> = BTreeSet::new();
    let mut keyless_new = 0;
    let mut picked = Picked::default();
    for i in order {
        let o = &offers[i];
        if let Some(k) = o.key
            && !seen.insert((o.place, k))
        {
            continue;
        }
        let on_place = shown.entry(o.place).or_default();
        if *on_place >= caps.per_place {
            continue;
        }
        if o.key_since.is_none() {
            let place_new = new_on_place.entry(o.place).or_default();
            let known_this_run = o.key.is_some_and(|k| new_keys.contains(k));
            let run_full = new_keys.len() + keyless_new >= caps.new_keys_per_run;
            if *place_new >= caps.new_keys_per_place || (!known_this_run && run_full) {
                picked.deferred += 1;
                continue;
            }
            *place_new += 1;
            match o.key {
                Some(k) => {
                    new_keys.insert(k);
                }
                None => keyless_new += 1,
            }
        }
        *on_place += 1;
        picked.kept.push(i);
    }
    picked.kept.sort_unstable();
    picked.new_keys = new_keys.len() + keyless_new;
    picked
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone};

    use super::*;

    fn at(days: i64) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap() + Duration::days(days)
    }

    fn offer(place: u8, key: &str, written: i64, since: Option<i64>) -> ReviewOffer<'_, u8> {
        ReviewOffer {
            place,
            key: Some(key),
            written_at: at(written),
            key_since: since.map(at),
            elsewhere: 0,
        }
    }

    const KEYS: [&str; 20] = [
        "k00", "k01", "k02", "k03", "k04", "k05", "k06", "k07", "k08", "k09", "k10", "k11", "k12",
        "k13", "k14", "k15", "k16", "k17", "k18", "k19",
    ];

    #[test]
    fn ten_fresh_keys_do_not_push_the_reviews_shown_off_a_place() {
        // Ten reviews by keys kept before, written long ago, and ten newer
        // ones by keys no one has seen.
        let mut offers: Vec<_> = (0..10).map(|n| offer(1, KEYS[n], 10, Some(20))).collect();
        offers.extend((10..20).map(|n| offer(1, KEYS[n], 300, None)));
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(
            picked.kept,
            (0..10).collect::<Vec<_>>(),
            "the reviews of keys kept before keep the place, however new the others are"
        );
        assert_eq!(picked.new_keys, 0);
        assert_eq!(
            picked.deferred, 0,
            "a full place defers nothing: it has no room"
        );
    }

    #[test]
    fn a_place_gains_two_new_keys_per_run() {
        let mut offers = vec![offer(1, KEYS[0], 10, Some(20))];
        offers.extend((1..8).map(|n| offer(1, KEYS[n], 300 + i64::try_from(n).unwrap(), None)));
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(
            picked.kept,
            [0, 6, 7],
            "the known key, then the two newest reviews of new keys"
        );
        assert_eq!(picked.new_keys, 2);
        assert_eq!(picked.deferred, 5);
    }

    #[test]
    fn older_keys_come_first_when_a_place_is_full() {
        let offers: Vec<_> = (0..12)
            .map(|n| offer(1, KEYS[n], 100, Some(i64::try_from(n).unwrap())))
            .collect();
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(picked.kept, (0..10).collect::<Vec<_>>());
    }

    #[test]
    fn a_run_lets_in_few_new_keys_and_prefers_those_with_history_elsewhere() {
        let caps = ReviewCaps {
            per_place: 10,
            new_keys_per_place: 2,
            new_keys_per_run: 3,
        };
        // One key reviewed two places; three single-place keys are newer.
        let mut offers = vec![
            ReviewOffer {
                elsewhere: 1,
                ..offer(1, "wide", 50, None)
            },
            ReviewOffer {
                elsewhere: 1,
                ..offer(2, "wide", 50, None)
            },
        ];
        offers.extend((0..3u8).map(|n| offer(3 + n, KEYS[usize::from(n)], 200, None)));
        let picked = pick_reviews(&offers, caps);
        assert_eq!(
            picked.kept,
            [0, 1, 2, 3],
            "the key with history elsewhere first, counted once for the run"
        );
        assert_eq!(picked.new_keys, 3);
        assert_eq!(picked.deferred, 1, "the run's cap holds the last new key");
    }

    #[test]
    fn one_review_per_key_and_place_the_newest() {
        let offers = vec![
            offer(1, "a", 10, Some(0)),
            offer(1, "a", 20, Some(0)),
            offer(2, "a", 5, Some(0)),
        ];
        assert_eq!(pick_reviews(&offers, MANGROVE_CAPS).kept, [1, 2]);
    }

    #[test]
    fn a_review_without_a_key_counts_as_a_new_key() {
        let offers: Vec<_> = (0..4)
            .map(|n| ReviewOffer {
                place: 1u8,
                key: None,
                written_at: at(n),
                key_since: None,
                elsewhere: 0,
            })
            .collect();
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(picked.kept, [2, 3]);
        assert_eq!(picked.new_keys, 2);
    }
}
