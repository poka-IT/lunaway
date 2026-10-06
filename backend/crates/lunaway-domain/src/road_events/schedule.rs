//! When an event applies: its validity, the weekly windows within it, and
//! the periods it is lifted.
//!
//! The DIR feed names periods without hours ("Uniquement de nuit": 56
//! records, "Uniquement de jour": 78, in the snapshot of 2026-10-06,
//! `plan/research/20-travaux-temps-reel.md`, part 6). Their windows are
//! chosen here, wider than night or day works usually run, and flagged as
//! assumed: outside the window such a closure warns instead of blocking,
//! and inside it blocks.

use chrono::{DateTime, Datelike, Duration, NaiveDate, NaiveDateTime, Utc, Weekday};
use serde::{Deserialize, Serialize};

/// Margin on each side of every bound, minutes: the arrival time is an
/// estimate, and a closure announced for 21:00 may start a little before.
pub const MARGIN_MIN: i64 = 15;

/// The assumed window of "night only": 19:00 to 08:00, local time. Night
/// works on the national network commonly run from 20:00 or 21:00 to 05:00
/// or 06:00 (assumption, to confirm with the DIR); the window covers them
/// with an hour to spare on each side.
pub const NIGHT: (u16, u16) = (19 * 60, 8 * 60);
/// The assumed window of "day only": 06:00 to 21:00, local time.
pub const DAY: (u16, u16) = (6 * 60, 21 * 60);
/// Every day of the week, bit 0 Monday to bit 6 Sunday.
pub const EVERY_DAY: u8 = 0b111_1111;

/// The time zone of the windows.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Zone {
    /// Europe/Paris, the local time of every French source.
    #[default]
    Paris,
    /// UTC, as DiaLog writes its recurring hours.
    Utc,
}

/// A weekly window: on the days it starts, from `start_min` to `end_min`
/// minutes after midnight, the next day when the end is not after the
/// start (a night).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Window {
    /// The days it starts on, bit 0 Monday to bit 6 Sunday.
    pub days: u8,
    /// Start, minutes after midnight.
    pub start_min: u16,
    /// End, minutes after midnight; at or before the start, the next day.
    pub end_min: u16,
}

impl Window {
    /// A window starting every day.
    #[must_use]
    pub const fn daily(start_min: u16, end_min: u16) -> Self {
        Self {
            days: EVERY_DAY,
            start_min,
            end_min,
        }
    }

    /// Whether `local` falls in the window, widened by `margin` on each
    /// side.
    fn covers(self, local: NaiveDateTime, margin: Duration) -> bool {
        let date = local.date();
        [date.pred_opt(), Some(date), date.succ_opt()]
            .into_iter()
            .flatten()
            .any(|day| self.covers_from(day, local, margin))
    }

    fn covers_from(self, day: NaiveDate, local: NaiveDateTime, margin: Duration) -> bool {
        if self.days & day_bit(day.weekday()) == 0 {
            return false;
        }
        let midnight = day.and_hms_opt(0, 0, 0).unwrap_or_default();
        let start = midnight + Duration::minutes(i64::from(self.start_min));
        let mut end = midnight + Duration::minutes(i64::from(self.end_min));
        if self.end_min <= self.start_min {
            end += Duration::days(1);
        }
        local >= start - margin && local <= end + margin
    }
}

/// The bit of a weekday in [`Window::days`].
#[must_use]
pub const fn day_bit(day: Weekday) -> u8 {
    1 << day.num_days_from_monday()
}

/// A period the event is lifted.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Period {
    /// Start.
    pub from: DateTime<Utc>,
    /// End.
    pub to: DateTime<Utc>,
}

#[allow(
    clippy::trivially_copy_pass_by_ref,
    reason = "serde's skip_serializing_if passes a reference"
)]
const fn is_false(b: &bool) -> bool {
    !*b
}

#[allow(
    clippy::trivially_copy_pass_by_ref,
    reason = "serde's skip_serializing_if passes a reference"
)]
const fn is_zero(n: &u16) -> bool {
    *n == 0
}

/// When, within its validity, an event applies.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Schedule {
    /// Weekly windows; none means all the time.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub windows: Vec<Window>,
    /// Periods it is lifted.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub exceptions: Vec<Period>,
    /// The windows' time zone.
    #[serde(default)]
    pub zone: Zone,
    /// The period as the source names it ("Uniquement de nuit").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    /// Whether the windows were chosen here for a label without hours.
    #[serde(default, skip_serializing_if = "is_false")]
    pub assumed: bool,
    /// An incident (accident, obstacle, broken-down vehicle) rather than
    /// planned works: one without an end ages faster.
    #[serde(default, skip_serializing_if = "is_false")]
    pub unplanned: bool,
    /// Minutes added on each side of every window, beyond [`MARGIN_MIN`]:
    /// DiaLog writes its daily hours in UTC from a local time converted on
    /// one date, an hour off for half of the year.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub widen_min: u16,
}

/// Whether an event applies at a given time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum Activity {
    /// It applies.
    Active,
    /// Within its validity, outside its weekly windows.
    OutsideWindow,
    /// Not yet started, over, or lifted.
    Inactive,
}

impl Schedule {
    /// The schedule of a period the source names: the assumed night or day
    /// window when the label names one of them only ("Uniquement de nuit"),
    /// the label alone otherwise ("jour et nuit", "tous les jours", "jours
    /// fériés": all the time within the validity).
    #[must_use]
    pub fn from_label(label: &str) -> Self {
        let lower = label.to_lowercase();
        let words: Vec<&str> = lower.split(|c: char| !c.is_alphanumeric()).collect();
        let night = words
            .iter()
            .any(|w| matches!(*w, "nuit" | "nocturne" | "nocturnes"));
        let day = words
            .iter()
            .any(|w| matches!(*w, "jour" | "journée" | "diurne" | "diurnes"));
        let window = match (night, day) {
            (true, false) => Some(NIGHT),
            (false, true) => Some(DAY),
            _ => None,
        };
        Self {
            windows: window
                .map(|(s, e)| vec![Window::daily(s, e)])
                .unwrap_or_default(),
            label: Some(label.trim().to_owned()),
            assumed: window.is_some(),
            ..Self::default()
        }
    }

    /// Whether the event applies at `at`, valid from `valid_from` to
    /// `valid_to` (open when none): each bound widened by [`MARGIN_MIN`], a
    /// lifted period counted only when `at` is inside it by more than the
    /// margin.
    #[must_use]
    pub fn activity(
        &self,
        valid_from: DateTime<Utc>,
        valid_to: Option<DateTime<Utc>>,
        at: DateTime<Utc>,
    ) -> Activity {
        let margin = Duration::minutes(MARGIN_MIN);
        if at + margin < valid_from || valid_to.is_some_and(|end| at - margin > end) {
            return Activity::Inactive;
        }
        if self
            .exceptions
            .iter()
            .any(|e| at - margin >= e.from && at + margin <= e.to)
        {
            return Activity::Inactive;
        }
        if self.windows.is_empty() {
            return Activity::Active;
        }
        let local = match self.zone {
            Zone::Paris => at.with_timezone(&chrono_tz::Europe::Paris).naive_local(),
            Zone::Utc => at.naive_utc(),
        };
        let widened = margin + Duration::minutes(i64::from(self.widen_min));
        if self.windows.iter().any(|w| w.covers(local, widened)) {
            Activity::Active
        } else {
            Activity::OutsideWindow
        }
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone as _;

    use super::*;

    /// A time in Paris, 2026-10-06 (a Tuesday, summer time: UTC+2).
    fn paris(day: u32, h: u32, m: u32) -> DateTime<Utc> {
        chrono_tz::Europe::Paris
            .with_ymd_and_hms(2026, 10, day, h, m, 0)
            .single()
            .unwrap()
            .with_timezone(&Utc)
    }

    #[test]
    fn a_night_closure_applies_at_night_and_not_at_noon() {
        let s = Schedule::from_label("Uniquement de nuit");
        assert!(s.assumed, "hours chosen here are flagged");
        let (from, to) = (paris(1, 0, 0), Some(paris(30, 0, 0)));
        assert_eq!(s.activity(from, to, paris(6, 23, 0)), Activity::Active);
        assert_eq!(
            s.activity(from, to, paris(7, 3, 0)),
            Activity::Active,
            "a night window runs past midnight"
        );
        assert_eq!(
            s.activity(from, to, paris(6, 12, 0)),
            Activity::OutsideWindow
        );
        assert_eq!(
            s.activity(from, to, paris(6, 18, 50)),
            Activity::Active,
            "the margin opens the window a quarter of an hour early"
        );
    }

    #[test]
    fn a_day_closure_applies_by_day() {
        let s = Schedule::from_label("Uniquement de jour");
        let (from, to) = (paris(1, 0, 0), None);
        assert_eq!(s.activity(from, to, paris(6, 12, 0)), Activity::Active);
        assert_eq!(
            s.activity(from, to, paris(7, 2, 0)),
            Activity::OutsideWindow
        );
        for always in ["week-end et jours fériés", "jour et nuit", "tous les jours"] {
            let s = Schedule::from_label(always);
            assert!(
                s.windows.is_empty() && !s.assumed,
                "{always} names no window: all the time"
            );
        }
    }

    #[test]
    fn validity_bounds_take_the_margin() {
        let s = Schedule::default();
        let (from, to) = (paris(6, 21, 0), Some(paris(7, 6, 0)));
        assert_eq!(s.activity(from, to, paris(6, 20, 50)), Activity::Active);
        assert_eq!(s.activity(from, to, paris(6, 20, 30)), Activity::Inactive);
        assert_eq!(s.activity(from, to, paris(7, 6, 10)), Activity::Active);
        assert_eq!(s.activity(from, to, paris(7, 6, 30)), Activity::Inactive);
        assert_eq!(s.activity(from, None, paris(30, 6, 30)), Activity::Active);
    }

    #[test]
    fn a_lifted_period_lifts_only_well_inside_it() {
        let s = Schedule {
            exceptions: vec![Period {
                from: paris(9, 17, 0),
                to: paris(12, 8, 0),
            }],
            ..Schedule::default()
        };
        let from = paris(1, 0, 0);
        assert_eq!(s.activity(from, None, paris(10, 12, 0)), Activity::Inactive);
        assert_eq!(
            s.activity(from, None, paris(9, 17, 5)),
            Activity::Active,
            "at the edge of a lifted period the event still counts"
        );
    }

    #[test]
    fn days_and_utc_windows_widen_by_their_uncertainty() {
        // Weekdays 06:00 to 16:00 UTC, an hour of doubt each side.
        let s = Schedule {
            windows: vec![Window {
                days: 0b001_1111,
                start_min: 6 * 60,
                end_min: 16 * 60,
            }],
            zone: Zone::Utc,
            widen_min: 60,
            ..Schedule::default()
        };
        let from = paris(1, 0, 0);
        let utc = |d, h, m| Utc.with_ymd_and_hms(2026, 10, d, h, m, 0).unwrap();
        assert_eq!(s.activity(from, None, utc(6, 5, 0)), Activity::Active);
        assert_eq!(
            s.activity(from, None, utc(6, 4, 30)),
            Activity::OutsideWindow
        );
        assert_eq!(
            s.activity(from, None, utc(10, 12, 0)),
            Activity::OutsideWindow,
            "2026-10-10 is a Saturday"
        );
    }

    #[test]
    fn a_schedule_survives_its_json() {
        let s = Schedule::from_label("Uniquement de nuit");
        let json = serde_json::to_string(&s).unwrap();
        assert_eq!(serde_json::from_str::<Schedule>(&json).unwrap(), s);
        assert_eq!(
            serde_json::from_str::<Schedule>("{}").unwrap(),
            Schedule::default()
        );
    }
}
