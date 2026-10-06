//! Trust levels: what an account may do, and what it needs for the next one.
//!
//! | level | reached when | unlocks |
//! |---|---|---|
//! | 0 | the account exists | synced favourites, ratings, confirmations, reports |
//! | 1 | old enough and a few confirmations, or sponsored by a level 2 | written reviews, photos |
//! | 2 | older, enough published contributions, nothing removed by moderation | new places |
//! | 3 | many active days and contributions, nominated by a level 4 | direct place edits |
//! | 4 | designated by the administration | moderation |
//!
//! The numbers are server configuration ([`Thresholds`]); the level is
//! computed again at each contribution, and never falls below the level the
//! administration granted.

use serde::{Deserialize, Serialize};

/// The highest level.
pub const MAX_LEVEL: u8 = 4;

/// The numbers behind each level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Thresholds {
    /// Account age, in days, for level 1.
    pub tl1_min_age_days: u32,
    /// Confirmations for level 1.
    pub tl1_min_confirmations: u32,
    /// Account age, in days, for level 2.
    pub tl2_min_age_days: u32,
    /// Published contributions for level 2.
    pub tl2_min_contributions: u32,
    /// Days with activity for level 3.
    pub tl3_min_active_days: u32,
    /// Published contributions for level 3.
    pub tl3_min_contributions: u32,
}

impl Default for Thresholds {
    fn default() -> Self {
        Self {
            tl1_min_age_days: 3,
            tl1_min_confirmations: 3,
            tl2_min_age_days: 14,
            tl2_min_contributions: 10,
            tl3_min_active_days: 60,
            tl3_min_contributions: 50,
        }
    }
}

/// What the rules look at.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct AccountStats {
    /// Whole days since the account was created.
    pub age_days: u32,
    /// Distinct days on which the account was used.
    pub active_days: u32,
    /// "Still there?" answers given.
    pub confirmations: u32,
    /// Published contributions: ratings and reviews, photos, confirmations,
    /// applied place submissions.
    pub contributions: u32,
    /// Reviews and photos a moderator removed.
    pub removals: u32,
    /// Whether a level-2 account sponsored this one.
    pub sponsored: bool,
    /// Whether a level-4 account nominated this one.
    pub nominated: bool,
    /// The floor the administration set.
    pub granted_level: u8,
}

/// Something an account still needs for a level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Requirement {
    /// The account must be older.
    AccountAgeDays {
        /// Its age.
        current: u32,
        /// The age needed.
        needed: u32,
    },
    /// More confirmations.
    Confirmations {
        /// Given so far.
        current: u32,
        /// Needed.
        needed: u32,
    },
    /// More published contributions.
    Contributions {
        /// Published so far.
        current: u32,
        /// Needed.
        needed: u32,
    },
    /// More days of activity.
    ActiveDays {
        /// So far.
        current: u32,
        /// Needed.
        needed: u32,
    },
    /// No contribution removed by moderation.
    NoRemoval {
        /// Removed so far.
        current: u32,
    },
    /// A level-2 account sponsors this one.
    Sponsor,
    /// A level-4 account nominates this one.
    Nomination,
    /// The administration designates this account.
    Administration,
}

/// The next level and what it needs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NextLevel {
    /// The level.
    pub level: u8,
    /// Every requirement still unmet.
    pub missing: Vec<Requirement>,
    /// A way to reach the level instead of `missing`, when there is one.
    pub instead: Option<Requirement>,
}

fn at_least(
    current: u32,
    needed: u32,
    make: impl Fn(u32, u32) -> Requirement,
) -> Option<Requirement> {
    (current < needed).then(|| make(current, needed))
}

/// What `stats` lacks for `level` (1 to 4) by the rules alone, assuming the
/// level below it is reached.
fn missing_for(level: u8, s: &AccountStats, t: &Thresholds) -> Vec<Requirement> {
    let r = match level {
        1 => vec![
            at_least(s.age_days, t.tl1_min_age_days, |current, needed| {
                Requirement::AccountAgeDays { current, needed }
            }),
            at_least(
                s.confirmations,
                t.tl1_min_confirmations,
                |current, needed| Requirement::Confirmations { current, needed },
            ),
        ],
        2 => vec![
            at_least(s.age_days, t.tl2_min_age_days, |current, needed| {
                Requirement::AccountAgeDays { current, needed }
            }),
            at_least(
                s.contributions,
                t.tl2_min_contributions,
                |current, needed| Requirement::Contributions { current, needed },
            ),
            (s.removals > 0).then_some(Requirement::NoRemoval {
                current: s.removals,
            }),
        ],
        3 => vec![
            at_least(s.active_days, t.tl3_min_active_days, |current, needed| {
                Requirement::ActiveDays { current, needed }
            }),
            at_least(
                s.contributions,
                t.tl3_min_contributions,
                |current, needed| Requirement::Contributions { current, needed },
            ),
            (!s.nominated).then_some(Requirement::Nomination),
        ],
        _ => vec![Some(Requirement::Administration)],
    };
    r.into_iter().flatten().collect()
}

/// The level the rules give `stats`, never below the granted floor.
#[must_use]
pub fn level(stats: &AccountStats, thresholds: &Thresholds) -> u8 {
    let mut earned = 0;
    for next in 1..MAX_LEVEL {
        let reached =
            missing_for(next, stats, thresholds).is_empty() || (next == 1 && stats.sponsored);
        if !reached {
            break;
        }
        earned = next;
    }
    earned.max(stats.granted_level.min(MAX_LEVEL))
}

/// The level after the current one and what it still needs; `None` at the
/// top.
#[must_use]
pub fn next_level(stats: &AccountStats, thresholds: &Thresholds) -> Option<NextLevel> {
    let current = level(stats, thresholds);
    let next = current.checked_add(1).filter(|l| *l <= MAX_LEVEL)?;
    Some(NextLevel {
        level: next,
        missing: missing_for(next, stats, thresholds),
        instead: (next == 1).then_some(Requirement::Sponsor),
    })
}

/// What an account does, and the level it takes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// Favourite lists, ratings, confirmations, issue and content reports,
    /// mutes.
    Basic,
    /// A review with text.
    Review,
    /// A photo.
    Photo,
    /// A point of interest (a vending machine) added on the map.
    AddPoi,
    /// Sponsoring a new account.
    Sponsor,
    /// A new place.
    AddPlace,
    /// A place edit applied without review (below, it is a proposal).
    EditPlaceDirectly,
    /// Nominating a level-3 account.
    Nominate,
}

impl Action {
    /// The lowest level allowed to do it.
    #[must_use]
    pub const fn required_level(self) -> u8 {
        match self {
            Self::Basic => 0,
            Self::Review | Self::Photo | Self::AddPoi => 1,
            Self::Sponsor | Self::AddPlace => 2,
            Self::EditPlaceDirectly => 3,
            Self::Nominate => 4,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: Thresholds = Thresholds {
        tl1_min_age_days: 3,
        tl1_min_confirmations: 3,
        tl2_min_age_days: 14,
        tl2_min_contributions: 10,
        tl3_min_active_days: 60,
        tl3_min_contributions: 50,
    };

    #[test]
    fn a_new_account_is_level_zero_and_is_told_what_level_one_needs() {
        let s = AccountStats::default();
        assert_eq!(level(&s, &T), 0);
        let next = next_level(&s, &T).unwrap();
        assert_eq!(next.level, 1);
        assert_eq!(
            next.missing,
            [
                Requirement::AccountAgeDays {
                    current: 0,
                    needed: 3
                },
                Requirement::Confirmations {
                    current: 0,
                    needed: 3
                }
            ]
        );
        assert_eq!(next.instead, Some(Requirement::Sponsor));
    }

    #[test]
    fn age_and_confirmations_or_a_sponsor_give_level_one() {
        let s = AccountStats {
            age_days: 3,
            confirmations: 3,
            ..AccountStats::default()
        };
        assert_eq!(level(&s, &T), 1);
        let young = AccountStats {
            age_days: 1,
            confirmations: 9,
            ..AccountStats::default()
        };
        assert_eq!(level(&young, &T), 0, "confirmations alone are not enough");
        let sponsored = AccountStats {
            sponsored: true,
            ..AccountStats::default()
        };
        assert_eq!(level(&sponsored, &T), 1);
    }

    #[test]
    fn a_removal_by_moderation_holds_level_two_back() {
        let s = AccountStats {
            age_days: 20,
            confirmations: 5,
            contributions: 12,
            ..AccountStats::default()
        };
        assert_eq!(level(&s, &T), 2);
        let removed = AccountStats { removals: 1, ..s };
        assert_eq!(level(&removed, &T), 1);
        assert_eq!(
            next_level(&removed, &T).unwrap().missing,
            [Requirement::NoRemoval { current: 1 }]
        );
    }

    #[test]
    fn level_three_needs_a_nomination_and_four_the_administration() {
        let s = AccountStats {
            age_days: 100,
            active_days: 70,
            confirmations: 20,
            contributions: 80,
            ..AccountStats::default()
        };
        assert_eq!(level(&s, &T), 2, "the numbers alone stop at level 2");
        assert_eq!(
            next_level(&s, &T).unwrap().missing,
            [Requirement::Nomination]
        );
        let nominated = AccountStats {
            nominated: true,
            ..s
        };
        assert_eq!(level(&nominated, &T), 3);
        assert_eq!(
            next_level(&nominated, &T).unwrap().missing,
            [Requirement::Administration]
        );
        let moderator = AccountStats {
            granted_level: 4,
            ..AccountStats::default()
        };
        assert_eq!(level(&moderator, &T), 4);
        assert_eq!(next_level(&moderator, &T), None);
    }

    #[test]
    fn a_granted_level_is_a_floor_not_a_ceiling() {
        let demo = AccountStats {
            granted_level: 2,
            ..AccountStats::default()
        };
        assert_eq!(
            level(&demo, &T),
            2,
            "the store reviewers' account starts at level 2"
        );
        assert_eq!(
            level(
                &AccountStats {
                    granted_level: 9,
                    ..demo
                },
                &T
            ),
            MAX_LEVEL
        );
    }

    #[test]
    fn actions_need_the_levels_of_the_contract() {
        assert_eq!(Action::Basic.required_level(), 0);
        assert_eq!(Action::Review.required_level(), 1);
        assert_eq!(Action::Photo.required_level(), 1);
        assert_eq!(Action::AddPlace.required_level(), 2);
        assert_eq!(Action::EditPlaceDirectly.required_level(), 3);
        assert_eq!(Action::Nominate.required_level(), 4);
    }
}
