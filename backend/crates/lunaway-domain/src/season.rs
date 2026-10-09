//! Seasons: opening hours that are dates without times (`Apr 01-Oct 31`,
//! `Jan 01-Dec 31`, `24/7`), read as the days of the year a place is open.
//!
//! A season needs no moving window of intervals: whether the place is open
//! on a day of any year follows from the dates alone, on the device as on
//! the server. It is what the "open on my dates" filter compares, and it
//! spares the change feed a new copy of every such place each day (the
//! window of `opening_intervals` moves at every local midnight).
//!
//! Days are those of a leap year, so that a date of the month has one day
//! number whatever the year: 1 is 1 January, 60 is 29 February, 366 is
//! 31 December. A day of a common year from 1 March on keeps the number of
//! its date in a leap year.

/// Most ranges a season holds once its periods crossing the new year are
/// cut there (`Dec 01-Mar 31` is two): the places' tiles carry two numbers,
/// and more is opening hours, not a season.
pub const MAX_SEASON_RANGES: usize = 2;

/// The last day of the year, 31 December of a leap year.
pub const LAST_DAY: u16 = 366;

/// Days before each month in a leap year.
const DAYS_BEFORE: [u16; 12] = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];
/// Days in each month of a leap year.
const DAYS_IN: [u16; 12] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
/// OpenStreetMap's month abbreviations.
const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// The day number of `month` (1 to 12) and `day` of the month, in a leap
/// year; `None` for a date no leap year has.
#[must_use]
pub fn day_of_year(month: u32, day: u32) -> Option<u16> {
    let m = usize::try_from(month.checked_sub(1)?).ok()?;
    let d = u16::try_from(day).ok()?;
    (1..=*DAYS_IN.get(m)?)
        .contains(&d)
        .then(|| DAYS_BEFORE[m] + d)
}

/// The days of the year a place is open: one to [`MAX_SEASON_RANGES`]
/// ranges of days, both ends included, sorted, apart from each other.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Season(Vec<(u16, u16)>);

impl Season {
    /// The whole year.
    #[must_use]
    pub fn all_year() -> Self {
        Self(vec![(1, LAST_DAY)])
    }

    /// The season of `ranges` (days, both ends included; a range whose
    /// start is after its end crosses the new year), merged; `None` when a
    /// day is out of 1 to 366 or more than [`MAX_SEASON_RANGES`] ranges
    /// remain.
    #[must_use]
    pub fn from_ranges(ranges: &[(u16, u16)]) -> Option<Self> {
        let mut cut: Vec<(u16, u16)> = Vec::with_capacity(ranges.len() + 1);
        for &(a, b) in ranges {
            if !(1..=LAST_DAY).contains(&a) || !(1..=LAST_DAY).contains(&b) {
                return None;
            }
            if a <= b {
                cut.push((a, b));
            } else {
                cut.push((a, LAST_DAY));
                cut.push((1, b));
            }
        }
        cut.sort_unstable();
        let mut merged: Vec<(u16, u16)> = Vec::with_capacity(cut.len());
        for (a, b) in cut {
            match merged.last_mut() {
                Some(last) if a <= last.1.saturating_add(1) => last.1 = last.1.max(b),
                _ => merged.push((a, b)),
            }
        }
        (!merged.is_empty() && merged.len() <= MAX_SEASON_RANGES).then_some(Self(merged))
    }

    /// Its ranges, sorted.
    #[must_use]
    pub fn ranges(&self) -> &[(u16, u16)] {
        &self.0
    }

    /// Whether it is open every day of the year.
    #[must_use]
    pub fn is_all_year(&self) -> bool {
        self.0 == [(1, LAST_DAY)]
    }

    /// Whether it is open on every day of every range of `days`.
    #[must_use]
    pub fn covers(&self, days: &[(u16, u16)]) -> bool {
        days.iter()
            .all(|&(x, y)| self.0.iter().any(|&(a, b)| a <= x && y <= b))
    }
}

/// The season `opening_hours` says, when it is dates without times: `24/7`
/// and `Mo-Su 00:00-24:00` are the whole year; otherwise a list, separated
/// by commas, of `Apr 01-Oct 31`, `Apr-Oct` or `Aug`. Anything else (days
/// of the week, times, `off`, holidays, years, comments, several rules) is
/// opening hours and gives `None`, as do more than [`MAX_SEASON_RANGES`]
/// ranges.
#[must_use]
pub fn season_of(opening_hours: &str) -> Option<Season> {
    let text = opening_hours.trim();
    if text == "24/7" || text == "Mo-Su 00:00-24:00" {
        return Some(Season::all_year());
    }
    let mut ranges = Vec::new();
    for item in text.split(',') {
        ranges.push(period(item.trim())?);
    }
    Season::from_ranges(&ranges)
}

/// One period: `Apr 01-Oct 31`, `Apr-Oct`, `Aug`.
fn period(item: &str) -> Option<(u16, u16)> {
    let (from, to) = match item.split_once('-') {
        Some((from, to)) => (from.trim(), to.trim()),
        None => (item, item),
    };
    let start = day(from, false)?;
    let end = day(to, true)?;
    Some((start, end))
}

/// `Apr 01` is that day; `Apr` alone its first day, or its last at the end
/// of a period.
fn day(text: &str, end: bool) -> Option<u16> {
    let (month, day_of_month) = match text.split_once(' ') {
        Some((m, d)) => (m, Some(d)),
        None => (text, None),
    };
    let m = MONTHS.iter().position(|name| *name == month)?;
    let month = u32::try_from(m + 1).ok()?;
    match day_of_month {
        Some(d) if d.len() == 2 && d.bytes().all(|b| b.is_ascii_digit()) => {
            day_of_year(month, d.parse().ok()?)
        }
        Some(_) => None,
        None if end => day_of_year(month, u32::from(DAYS_IN[m])),
        None => day_of_year(month, 1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn season(ranges: &[(u16, u16)]) -> Season {
        Season::from_ranges(ranges).unwrap()
    }

    #[test]
    fn days_are_those_of_a_leap_year() {
        assert_eq!(day_of_year(1, 1), Some(1));
        assert_eq!(day_of_year(2, 29), Some(60));
        assert_eq!(day_of_year(3, 1), Some(61));
        assert_eq!(day_of_year(12, 31), Some(366));
        assert_eq!(day_of_year(2, 30), None);
        assert_eq!(day_of_year(13, 1), None);
        assert_eq!(day_of_year(0, 1), None);
    }

    #[test]
    fn dates_without_times_are_a_season() {
        assert_eq!(season_of("Jan 01-Dec 31"), Some(Season::all_year()));
        assert_eq!(season_of("24/7"), Some(Season::all_year()));
        assert_eq!(season_of("Mo-Su 00:00-24:00"), Some(Season::all_year()));
        assert_eq!(season_of("Jan-Dec"), Some(Season::all_year()));
        assert_eq!(season_of("Apr 01-Oct 31"), Some(season(&[(92, 305)])));
        assert_eq!(season_of("Apr-Oct"), Some(season(&[(92, 305)])));
        assert_eq!(season_of(" Aug "), Some(season(&[(214, 244)])));
        assert_eq!(
            season_of("Dec 15-Jan 15"),
            Some(season(&[(1, 15), (350, 366)])),
            "a period crossing the new year is cut there"
        );
        assert_eq!(
            season_of("Apr 01-Jun 30,Sep 01-Oct 31"),
            Some(season(&[(92, 182), (245, 305)]))
        );
        assert_eq!(
            season_of("Apr 01-Jun 30, Jul 01-Sep 30"),
            Some(season(&[(92, 274)])),
            "periods that meet are one"
        );
    }

    #[test]
    fn opening_hours_are_no_season() {
        for hours in [
            "Mo-Fr 08:00-18:00",
            "Apr 01-Oct 31 08:00-20:00",
            "Apr-Oct Mo-Sa",
            "Apr 01-Oct 31; Nov off",
            "PH off",
            "2026 Apr 01-Oct 31",
            "Apr 1-Oct 31",
            "apr 01-oct 31",
            "Feb 30-Mar 31",
            "Jan 01-Feb 28,Apr 01-May 31,Jul 01-Aug 31",
            "Dec 01-Feb 28,Jun 01-Aug 31",
            "",
            "sunrise-sunset",
            "\"on appointment\"",
        ] {
            assert_eq!(
                season_of(hours),
                None,
                "{hours:?} is opening hours, not a season"
            );
        }
    }

    #[test]
    fn a_season_covers_a_stay_within_one_of_its_ranges() {
        let summer = season(&[(92, 305)]);
        assert!(summer.covers(&[(92, 100)]));
        assert!(summer.covers(&[(300, 305)]));
        assert!(!summer.covers(&[(300, 306)]), "the last night is closed");
        assert!(!summer.covers(&[(1, 366)]), "not open all year");
        let winter = season(&[(1, 91), (305, 366)]);
        assert!(
            winter.covers(&[(360, 366), (1, 3)]),
            "a stay across the new year"
        );
        assert!(!winter.covers(&[(80, 100)]));
        assert!(Season::all_year().covers(&[(1, 366)]));
        assert!(Season::all_year().is_all_year());
        assert!(!summer.is_all_year());
    }

    #[test]
    fn ranges_out_of_the_year_make_no_season() {
        assert_eq!(Season::from_ranges(&[(0, 10)]), None);
        assert_eq!(Season::from_ranges(&[(1, 367)]), None);
        assert_eq!(Season::from_ranges(&[]), None);
    }
}
