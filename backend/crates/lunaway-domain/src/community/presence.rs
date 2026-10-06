//! Presence checks: a position sent with a confirmation becomes a verdict.
//! The position itself is never kept; only whether the visitor was there.

use std::{fmt, str::FromStr};

use serde::{Deserialize, Serialize};

use crate::{Position, UnknownCode, taxonomy::coded_enum};

/// How close to the place a visitor must be, in metres.
pub const PRESENCE_RADIUS_M: f64 = 300.0;

coded_enum! {
    /// What the server concluded from the position sent with a confirmation.
    Presence {
        /// The device was within [`PRESENCE_RADIUS_M`] of the place, with an
        /// accuracy no worse than that radius.
        Present => "present",
        /// No position, or one too far or too vague.
        Unverified => "unverified",
    }
}

/// The verdict for a visitor at `reported` (with the device's horizontal
/// accuracy in metres, when it gives one) about the place at `place`.
///
/// The distance is not reduced by the accuracy: a vague fix 500 m away
/// could be anywhere, so it proves nothing.
#[must_use]
pub fn verdict(place: Position, reported: Option<Position>, accuracy_m: Option<f64>) -> Presence {
    let Some(at) = reported else {
        return Presence::Unverified;
    };
    let precise_enough =
        accuracy_m.is_none_or(|a| a.is_finite() && (0.0..=PRESENCE_RADIUS_M).contains(&a));
    if precise_enough && place.distance_m(at) <= PRESENCE_RADIUS_M {
        Presence::Present
    } else {
        Presence::Unverified
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    #[test]
    fn only_a_precise_fix_near_the_place_counts() {
        let place = p(45.0, 6.0);
        // 0.002 degrees of latitude is about 222 m.
        assert_eq!(
            verdict(place, Some(p(45.002, 6.0)), Some(20.0)),
            Presence::Present
        );
        assert_eq!(
            verdict(place, Some(p(45.002, 6.0)), None),
            Presence::Present
        );
        assert_eq!(
            verdict(place, Some(p(45.004, 6.0)), Some(5.0)),
            Presence::Unverified,
            "445 m away is not at the place"
        );
        assert_eq!(
            verdict(place, Some(p(45.0, 6.0)), Some(2_000.0)),
            Presence::Unverified,
            "a fix vaguer than the radius proves nothing"
        );
        assert_eq!(
            verdict(place, Some(p(45.0, 6.0)), Some(f64::NAN)),
            Presence::Unverified
        );
        assert_eq!(verdict(place, None, None), Presence::Unverified);
    }
}
