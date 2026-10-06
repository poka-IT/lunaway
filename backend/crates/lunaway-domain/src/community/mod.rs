//! What the community contributes and the rules around it: the codes of
//! contributions, the automatic moderation of text, pseudonyms, trust
//! levels and presence checks. Pure rules; the API and the database apply
//! them.

pub mod moderation;
pub mod presence;
pub mod pseudonym;
pub mod submission;
pub mod trust;

use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};

use crate::{UnknownCode, taxonomy::coded_enum};

coded_enum! {
    /// A visitor's answer to "is it still there?".
    ConfirmationStatus {
        /// The place is as described.
        StillOk => "still_ok",
        /// The place no longer takes visitors.
        Closed => "closed",
        /// The place exists but something described changed.
        Changed => "changed",
    }
}

coded_enum! {
    /// A problem a visitor met at a place.
    IssueKind {
        /// Nights are forbidden now (a sign, a by-law, the police).
        NightBan => "night_ban",
        /// A service (water, dump station, electricity) is out of order.
        ServiceBroken => "service_broken",
        /// The place cannot be reached (barrier, works, height bar).
        NoAccess => "no_access",
        /// Something dangerous (theft, flooding, unsafe ground).
        Danger => "danger",
    }
}

coded_enum! {
    /// The vehicle a reviewer travelled in: what fits depends on it.
    VehicleKind {
        /// A small van (up to about 5.5 m).
        Van => "van",
        /// A panel-van conversion (about 6 to 6.5 m).
        Campervan => "campervan",
        /// A coachbuilt or integrated motorhome.
        Motorhome => "motorhome",
        /// A car towing a caravan.
        Caravan => "caravan",
        /// Anything else.
        Other => "other",
    }
}

coded_enum! {
    /// Where a published contribution stands.
    ReviewStatus {
        /// Visible to everyone.
        Published => "published",
        /// Held by the automatic rules until a moderator decides.
        Pending => "pending",
        /// Hidden after reports, until a moderator decides.
        Hidden => "hidden",
        /// Removed by a moderator.
        Removed => "removed",
    }
}

coded_enum! {
    /// Where a photo stands.
    PhotoStatus {
        /// Visible to everyone.
        Published => "published",
        /// Hidden after reports, until a moderator decides.
        Hidden => "hidden",
        /// Removed by a moderator.
        Removed => "removed",
    }
}

coded_enum! {
    /// What a user may report.
    ReportTarget {
        /// A review.
        Review => "review",
        /// A photo.
        Photo => "photo",
        /// A place.
        Place => "place",
    }
}

coded_enum! {
    /// Why a user reports something.
    ReportReason {
        /// Advertising or repeated content.
        Spam => "spam",
        /// Insulting, hateful or shocking.
        Offensive => "offensive",
        /// False or misleading.
        Wrong => "wrong",
        /// Shows or names a person, a licence plate, a private address.
        Privacy => "privacy",
        /// Something else, said in the note.
        Other => "other",
    }
}

coded_enum! {
    /// Whether a place can be trusted to exist as described.
    Verification {
        /// Described by an open source, or confirmed by the community.
        Verified => "verified",
        /// Added by a contributor and not yet confirmed by two others.
        ToVerify => "to_verify",
    }
}

/// Distinct reporters that hide a review or a photo until a moderator
/// decides.
pub const HIDE_AFTER_REPORTS: i64 = 3;

/// Accounts other than its author that must confirm a place the community
/// alone describes before it counts as verified.
pub const CONFIRMATIONS_TO_VERIFY: i64 = 2;

/// Shortest and longest review text, in characters.
pub const REVIEW_TEXT_CHARS: std::ops::RangeInclusive<usize> = 10..=2_000;

/// Longest note of a confirmation, an issue or a report, in characters.
pub const NOTE_MAX_CHARS: usize = 500;

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_codes_hold<T>(all: &[T])
    where
        T: Copy + fmt::Display + FromStr<Err = UnknownCode> + PartialEq + fmt::Debug + Serialize,
    {
        for v in all {
            let code = v.to_string();
            assert!(
                code.bytes().all(|b| b.is_ascii_lowercase() || b == b'_'),
                "{code} is the stored form: snake case only"
            );
            assert_eq!(code.parse::<T>().unwrap(), *v);
        }
    }

    #[test]
    fn every_community_code_round_trips() {
        assert_codes_hold(ConfirmationStatus::ALL);
        assert_codes_hold(IssueKind::ALL);
        assert_codes_hold(VehicleKind::ALL);
        assert_codes_hold(ReviewStatus::ALL);
        assert_codes_hold(PhotoStatus::ALL);
        assert_codes_hold(ReportTarget::ALL);
        assert_codes_hold(ReportReason::ALL);
        assert_codes_hold(Verification::ALL);
    }
}
