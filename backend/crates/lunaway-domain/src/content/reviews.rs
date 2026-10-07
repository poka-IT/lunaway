//! Which open reviews a place keeps when it is offered more than it shows.
//!
//! On Mangrove anyone signs a review with a key made a second earlier, and
//! the date a review carries is its author's: newest first, ten new keys
//! would push every real review off a place in one run. Lunaway weighs a
//! review by what it saw itself, which no author sets:
//!
//! - whether the key already has a review shown on the place: such a
//!   review keeps its slot;
//! - the key's age, from when a review it signed was first kept, on any
//!   place (`content_review_keys`); a key never kept, or one of whose
//!   reviews stands hidden, is new;
//! - when Lunaway first read the review (`content_review_sightings`).
//!
//! Every review that would add a key to a place, whatever the key's age,
//! is a new pair: a place gains few per run, a key reaches few new places
//! per run, and a run lets in few in all, so neither fresh keys nor keys
//! aged on purpose fill the map faster than the reports and the operator
//! see them (`docs/data-sources.md`, "Mangrove reviews").

use std::collections::{BTreeMap, BTreeSet};

use chrono::{DateTime, Utc};

/// How many reviews a place keeps, and how fast reviews reach new places.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReviewCaps {
    /// Reviews a place keeps at most.
    pub per_place: usize,
    /// New pairs a place gains per run at most.
    pub new_per_place: usize,
    /// New places one key reaches per run at most.
    pub new_places_per_key: usize,
    /// New pairs a run lets in at most, every place together.
    pub new_per_run: usize,
    /// Of them, those only new keys may take: keys aged on purpose cannot
    /// hold the whole of each week's room and lock first-time reviewers
    /// out.
    pub new_per_run_for_new_keys: usize,
}

/// The caps of the weekly Mangrove run. The whole of Mangrove held 10 803
/// reviews on 2026-10-07, every subject together: fifty reviews a week
/// reaching new places on Lunaway's map is above what reviewers write
/// there, and far below what a script makes; three new places a week per
/// key is a trip's stops, the rest of them come the week after; twenty of
/// the fifty wait for first-time reviewers.
pub const MANGROVE_CAPS: ReviewCaps = ReviewCaps {
    per_place: 10,
    new_per_place: 2,
    new_places_per_key: 3,
    new_per_run: 50,
    new_per_run_for_new_keys: 20,
};

/// A review offered to a place, as the choice weighs it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReviewOffer<'a, P> {
    /// The place it is about.
    pub place: P,
    /// The hash of the key that signed it; `None` counts as a key of its
    /// own, new everywhere.
    pub key: Option<&'a str>,
    /// When it says it was written (the author sets it): only which of a
    /// key's reviews of one place is its latest.
    pub written_at: DateTime<Utc>,
    /// When Lunaway first kept a review signed by its key, on any place;
    /// `None` for a new key.
    pub key_since: Option<DateTime<Utc>>,
    /// The key has a review shown on this place now.
    pub shown_here: bool,
    /// When Lunaway first read this review.
    pub first_seen: DateTime<Utc>,
}

/// What [`pick_reviews`] kept.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Picked {
    /// The offers kept, by their index, in increasing order.
    pub kept: Vec<usize>,
    /// New keys with a review kept by this run, each counted once.
    pub new_keys: usize,
    /// New pairs kept by this run.
    pub new_pairs: usize,
    /// New pairs left for a later run by the caps on new pairs, though
    /// their place had room.
    pub deferred: usize,
}

/// The reviews each place keeps among `offers`, at most `caps.per_place`
/// a place, one per key and place (its latest). First the reviews of keys
/// shown on the place already, oldest key first; then the new pairs, keys
/// kept before first (oldest first), then new keys, each group in the
/// order Lunaway first read the reviews, within the caps on new pairs.
#[must_use]
pub fn pick_reviews<P: Ord + Copy>(offers: &[ReviewOffer<'_, P>], caps: ReviewCaps) -> Picked {
    // One per key and place: its latest, as the author dates it.
    let mut latest: BTreeMap<(P, &str), usize> = BTreeMap::new();
    let mut order: Vec<usize> = Vec::new();
    for (i, o) in offers.iter().enumerate() {
        match o.key {
            Some(k) => {
                let e = latest.entry((o.place, k)).or_insert(i);
                if offers[*e].written_at < o.written_at {
                    *e = i;
                }
            }
            None => order.push(i),
        }
    }
    order.extend(latest.into_values());
    order.sort_by_key(|&i| {
        let o = &offers[i];
        (
            !o.shown_here,
            o.key_since.is_none(),
            o.key_since,
            o.first_seen,
            i,
        )
    });
    let mut shown: BTreeMap<P, usize> = BTreeMap::new();
    let mut new_on_place: BTreeMap<P, usize> = BTreeMap::new();
    let mut new_places_of_key: BTreeMap<&str, usize> = BTreeMap::new();
    let mut new_keys: BTreeSet<&str> = BTreeSet::new();
    let mut known_new_pairs = 0;
    let mut picked = Picked::default();
    for i in order {
        let o = &offers[i];
        let on_place = shown.entry(o.place).or_default();
        if *on_place >= caps.per_place {
            continue;
        }
        if !o.shown_here {
            let place_new = new_on_place.entry(o.place).or_default();
            let key_new = o
                .key
                .map_or(0, |k| new_places_of_key.get(k).copied().unwrap_or_default());
            let known_key = o.key_since.is_some();
            let room_for_known = caps
                .new_per_run
                .saturating_sub(caps.new_per_run_for_new_keys);
            if *place_new >= caps.new_per_place
                || key_new >= caps.new_places_per_key
                || picked.new_pairs >= caps.new_per_run
                || (known_key && known_new_pairs >= room_for_known)
            {
                picked.deferred += 1;
                continue;
            }
            *place_new += 1;
            picked.new_pairs += 1;
            if known_key {
                known_new_pairs += 1;
            }
            match (o.key, o.key_since) {
                (Some(k), since) => {
                    *new_places_of_key.entry(k).or_default() += 1;
                    if since.is_none() {
                        new_keys.insert(k);
                    }
                }
                (None, _) => picked.new_keys += 1,
            }
        }
        *on_place += 1;
        picked.kept.push(i);
    }
    picked.kept.sort_unstable();
    picked.new_keys += new_keys.len();
    picked
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, TimeZone};

    use super::*;

    fn at(days: i64) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap() + Duration::days(days)
    }

    /// A review of `key` on `place`, read first on day `seen`, by a key
    /// kept since day `since` (`None`: a new key).
    fn offer(place: u16, key: &str, seen: i64, since: Option<i64>) -> ReviewOffer<'_, u16> {
        ReviewOffer {
            place,
            key: Some(key),
            written_at: at(seen),
            key_since: since.map(at),
            shown_here: false,
            first_seen: at(seen),
        }
    }

    fn shown(o: ReviewOffer<'_, u16>) -> ReviewOffer<'_, u16> {
        ReviewOffer {
            shown_here: true,
            ..o
        }
    }

    const KEYS: [&str; 20] = [
        "k00", "k01", "k02", "k03", "k04", "k05", "k06", "k07", "k08", "k09", "k10", "k11", "k12",
        "k13", "k14", "k15", "k16", "k17", "k18", "k19",
    ];

    #[test]
    fn ten_fresh_keys_do_not_push_the_reviews_shown_off_a_place() {
        let mut offers: Vec<_> = (0..10)
            .map(|n| shown(offer(1, KEYS[n], 10, Some(20))))
            .collect();
        offers.extend((10..20).map(|n| offer(1, KEYS[n], 300, None)));
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(
            picked.kept,
            (0..10).collect::<Vec<_>>(),
            "the reviews shown keep the place, however new the others are"
        );
        assert_eq!(picked.new_keys, 0);
        assert_eq!(
            picked.deferred, 0,
            "a full place defers nothing: it has no room"
        );
    }

    #[test]
    fn a_place_gains_two_new_pairs_per_run_in_the_order_they_were_read() {
        let mut offers = vec![shown(offer(1, KEYS[0], 10, Some(20)))];
        offers.extend((1..8).map(|n| offer(1, KEYS[n], 300 + i64::try_from(n).unwrap(), None)));
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(
            picked.kept,
            [0, 1, 2],
            "the review shown, then the two new keys read first"
        );
        assert_eq!(picked.new_keys, 2);
        assert_eq!(picked.deferred, 5);
    }

    #[test]
    fn an_older_key_reaching_a_new_place_comes_before_a_new_key() {
        let offers = vec![
            offer(1, "new", 1, None),
            offer(1, "younger", 5, Some(3)),
            offer(1, "older", 9, Some(2)),
        ];
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(picked.kept, [1, 2], "two new pairs, the oldest keys");
        assert_eq!(picked.new_keys, 0);
    }

    #[test]
    fn two_keys_on_a_thousand_places_reach_few_of_them_run_after_run() {
        // Two keys review every place of the map; one real reviewer, read
        // later, writes about place 700.
        let mut offers = Vec::new();
        for place in 0..1_000 {
            offers.push(offer(place, "spam-a", 1, None));
            offers.push(offer(place, "spam-b", 1, None));
        }
        offers.push(offer(700, "real", 5, None));
        let first = pick_reviews(&offers, MANGROVE_CAPS);
        let spam = |p: &Picked, offers: &[ReviewOffer<'_, u16>]| {
            p.kept
                .iter()
                .filter(|&&i| offers[i].key != Some("real"))
                .count()
        };
        assert_eq!(spam(&first, &offers), 6, "three places a key in a run");
        assert!(
            first.kept.iter().any(|&i| offers[i].key == Some("real")),
            "a real reviewer still gets in beside them"
        );
        // The next week the two keys are known and shown on three places
        // each: they still reach three new places each, no more.
        let mut second = offers.clone();
        for &i in &first.kept {
            second[i].shown_here = true;
        }
        for o in &mut second {
            if o.key != Some("real") {
                o.key_since = Some(at(7));
            }
        }
        let picked = pick_reviews(&second, MANGROVE_CAPS);
        assert_eq!(
            spam(&picked, &second),
            12,
            "an aged key gains three new places a week, however many it reviews"
        );
        assert_eq!(picked.new_pairs, 6);
    }

    #[test]
    fn a_run_lets_in_few_new_pairs_every_place_together() {
        let caps = ReviewCaps {
            new_per_run: 4,
            ..MANGROVE_CAPS
        };
        // Reviews read on days 20 down to 1, the later ones dated in the
        // future: the date gives no rank.
        let offers: Vec<_> = (0..20u16)
            .map(|n| ReviewOffer {
                written_at: at(1_000),
                ..offer(n, KEYS[usize::from(n)], 20 - i64::from(n), None)
            })
            .collect();
        let picked = pick_reviews(&offers, caps);
        assert_eq!(
            picked.kept,
            [16, 17, 18, 19],
            "the first read, up to the cap"
        );
        assert_eq!(picked.new_pairs, 4);
        assert_eq!(picked.deferred, 16);
    }

    #[test]
    fn keys_aged_on_purpose_leave_room_for_first_time_reviewers() {
        // Twenty aged keys each reach three new places, read before a
        // first-time reviewer: they take thirty pairs, not fifty.
        let mut offers = Vec::new();
        for (k, key) in KEYS.iter().enumerate() {
            for p in 0..3 {
                let place = u16::try_from(k * 3 + p).unwrap();
                offers.push(offer(place, key, 1, Some(0)));
            }
        }
        offers.push(offer(900, "first-timer", 9, None));
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(
            picked.new_pairs, 31,
            "thirty pairs for keys kept before, the reserved room for the new one"
        );
        assert!(
            picked
                .kept
                .iter()
                .any(|&i| offers[i].key == Some("first-timer"))
        );
    }

    #[test]
    fn one_review_per_key_and_place_the_latest() {
        let offers = vec![
            shown(offer(1, "a", 10, Some(0))),
            shown(offer(1, "a", 20, Some(0))),
            shown(offer(2, "a", 5, Some(0))),
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
                shown_here: false,
                first_seen: at(n),
            })
            .collect();
        let picked = pick_reviews(&offers, MANGROVE_CAPS);
        assert_eq!(picked.kept, [0, 1]);
        assert_eq!(picked.new_keys, 2);
    }
}
