//! Which open reviews a place keeps when it is offered more than it shows.
//!
//! On Mangrove anyone signs a review with a key made a second earlier, and
//! the date a review carries is its author's: newest first, ten new keys
//! would push every real review off a place in one run. Lunaway weighs a
//! key by the history it earned here instead, which no one can backdate:
//! when a review it signed was first kept (`content_review_keys`), on any
//! place. Keys kept before rank first, oldest first. A key never kept, or
//! whose review the reports, a moderator or the operator hid, is new: a
//! place gains few reviews of new keys per run, a new key reaches few
//! places per run, and a run lets in few reviews of new keys in all, so a
//! burst of fresh keys waits in line behind the reviews already shown,
//! run after run, where the reports and the operator see it
//! (`docs/data-sources.md`, "Mangrove reviews").

use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet},
};

use chrono::{DateTime, Utc};

/// How many reviews a place keeps, and how fast new keys reach the map.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReviewCaps {
    /// Reviews a place keeps at most.
    pub per_place: usize,
    /// Reviews of new keys a place gains per run at most.
    pub new_per_place: usize,
    /// Places one new key reaches per run at most.
    pub places_per_new_key: usize,
    /// Reviews of new keys a run lets in at most, every place together.
    pub new_per_run: usize,
}

/// The caps of the weekly Mangrove run. The whole of Mangrove held 10 803
/// reviews on 2026-10-07, every subject together: fifty reviews of new
/// authors a week on Lunaway's places is above what reviewers write there,
/// and far below what a script makes; three places a week is a trip's
/// stops for a new reviewer, and the rest of them come the week after.
pub const MANGROVE_CAPS: ReviewCaps = ReviewCaps {
    per_place: 10,
    new_per_place: 2,
    places_per_new_key: 3,
    new_per_run: 50,
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
    /// `None` for a new key.
    pub key_since: Option<DateTime<Utc>>,
}

/// What [`pick_reviews`] kept.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Picked {
    /// The offers kept, by their index, in increasing order.
    pub kept: Vec<usize>,
    /// New keys with a review kept by this run, each counted once.
    pub new_keys: usize,
    /// Reviews of new keys kept by this run.
    pub new_reviews: usize,
    /// Reviews of new keys left for a later run by the caps on new keys,
    /// though their place had room.
    pub deferred: usize,
}

/// The reviews each place keeps among `offers`: one per key and place
/// (its newest), at most `caps.per_place` a place. Keys kept before come
/// first, the oldest first, then the newest of their reviews; then the
/// reviews of new keys, the newest first, within the caps on new keys.
/// How many places a new key reviews in the run gives it no rank: whoever
/// makes the keys sets it.
#[must_use]
pub fn pick_reviews<P: Ord + Copy>(offers: &[ReviewOffer<'_, P>], caps: ReviewCaps) -> Picked {
    let mut order: Vec<usize> = (0..offers.len()).collect();
    order.sort_by_key(|&i| {
        let o = &offers[i];
        (o.key_since.is_none(), o.key_since, Reverse(o.written_at), i)
    });
    let mut seen: BTreeSet<(P, &str)> = BTreeSet::new();
    let mut shown: BTreeMap<P, usize> = BTreeMap::new();
    let mut new_on_place: BTreeMap<P, usize> = BTreeMap::new();
    let mut places_of_new_key: BTreeMap<&str, usize> = BTreeMap::new();
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
            let key_places = o
                .key
                .map_or(0, |k| places_of_new_key.get(k).copied().unwrap_or_default());
            if *place_new >= caps.new_per_place
                || key_places >= caps.places_per_new_key
                || picked.new_reviews >= caps.new_per_run
            {
                picked.deferred += 1;
                continue;
            }
            *place_new += 1;
            picked.new_reviews += 1;
            if let Some(k) = o.key {
                *places_of_new_key.entry(k).or_default() += 1;
            } else {
                picked.new_keys += 1;
            }
        }
        *on_place += 1;
        picked.kept.push(i);
    }
    picked.kept.sort_unstable();
    picked.new_keys += places_of_new_key.len();
    picked
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone};

    use super::*;

    fn at(days: i64) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap() + Duration::days(days)
    }

    fn offer(place: u16, key: &str, written: i64, since: Option<i64>) -> ReviewOffer<'_, u16> {
        ReviewOffer {
            place,
            key: Some(key),
            written_at: at(written),
            key_since: since.map(at),
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
    fn two_fresh_keys_on_a_thousand_places_reach_few_of_them() {
        // Two keys review every place of the map, with a review newer than
        // any real one; one real new reviewer writes about place 7.
        let mut offers = Vec::new();
        for place in 0..1_000 {
            offers.push(offer(place, "spam-a", 500, None));
            offers.push(offer(place, "spam-b", 500, None));
        }
        offers.push(offer(7, "real", 100, None));
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        let spam = picked
            .kept
            .iter()
            .filter(|&&i| offers[i].key != Some("real"))
            .count();
        assert_eq!(
            spam,
            2 * MANGROVE_CAPS.places_per_new_key,
            "a new key reaches three places a run, however many it reviews"
        );
        assert!(
            picked.kept.iter().any(|&i| offers[i].key == Some("real")),
            "a real reviewer still gets in beside them"
        );
        assert_eq!(picked.new_keys, 3);
        assert_eq!(picked.new_reviews, 7);
    }

    #[test]
    fn a_run_lets_in_few_reviews_of_new_keys_every_place_together() {
        let caps = ReviewCaps {
            new_per_run: 4,
            ..MANGROVE_CAPS
        };
        let offers: Vec<_> = (0..20u16)
            .map(|n| offer(n, KEYS[usize::from(n)], 200 + i64::from(n), None))
            .collect();
        let picked = pick_reviews(&offers, caps);
        assert_eq!(picked.kept, [16, 17, 18, 19], "the newest, up to the cap");
        assert_eq!(picked.new_reviews, 4);
        assert_eq!(picked.deferred, 16);
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
                place: 1u16,
                key: None,
                written_at: at(n),
                key_since: None,
            })
            .collect();
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(picked.kept, [2, 3]);
        assert_eq!(picked.new_keys, 2);
    }
}
