//! Evaluating OSM `opening_hours` into UTC intervals.
//!
//! The device cannot evaluate the syntax (no Dart evaluator exists), so the
//! server ships two weeks of open intervals with each place and refreshes
//! them daily.
//!
//! The window runs from local midnight of `today` for
//! [`OPENING_WINDOW_DAYS`] days, in the timezone of the place's country:
//! [`timezone_of`] maps a country code to its zone; a country it does not
//! know yields no intervals rather than intervals in the wrong zone. Public
//! holidays (`PH`) follow the national calendar embedded in the
//! `opening-hours` crate (Nager.Date data); regional holidays are not
//! applied, so in Alsace-Moselle Good Friday and 26 December count as
//! ordinary days. Sun events (`sunrise`, `sunset`) are computed at the
//! place's position. Only `open` periods become intervals: `unknown` ones
//! ("on appointment", a comment without a time) are not claimed as open.
//!
//! Two bounds keep a hostile or broken value cheap: an expression longer
//! than OSM allows ([`MAX_EXPRESSION_CHARS`]) is not evaluated, and at most
//! [`MAX_INTERVALS`] intervals are kept, the window then ending where the
//! first one left out begins (`until`).

use chrono::{DateTime, NaiveDate, NaiveDateTime, TimeZone, Utc};
use chrono_tz::Tz;
use lunaway_db::conflation::OpeningEval;
use lunaway_domain::{OPENING_WINDOW_DAYS, OpeningInterval, Position};
use opening_hours::{
    Context, OpeningHours, RuleKind,
    localization::{Coordinates, Country, TzLocation},
};

/// Longest expression evaluated, in characters: OpenStreetMap caps a tag
/// value at 255.
pub const MAX_EXPRESSION_CHARS: usize = 255;

/// Most intervals kept for one place. Two weeks of a place open twice a day
/// is 28; a value that opens and closes every few minutes would otherwise
/// cost thousands of rows in every sync page.
pub const MAX_INTERVALS: usize = 256;

/// The zone of a country, for the countries the data covers so far and
/// their neighbours, each a single-zone country in Europe. Metropolitan
/// France is `Europe/Paris`; its overseas departments share the code `FR`
/// in addresses but are not imported, so the mapping holds for the data.
#[must_use]
pub fn timezone_of(country_code: &str) -> Option<Tz> {
    Some(match country_code.to_ascii_uppercase().as_str() {
        "FR" | "MC" => Tz::Europe__Paris,
        "BE" => Tz::Europe__Brussels,
        "LU" => Tz::Europe__Luxembourg,
        "CH" => Tz::Europe__Zurich,
        "DE" => Tz::Europe__Berlin,
        "IT" => Tz::Europe__Rome,
        "AD" => Tz::Europe__Andorra,
        "NL" => Tz::Europe__Amsterdam,
        "GB" => Tz::Europe__London,
        _ => return None,
    })
}

/// Today in metropolitan France, the day a run's opening window starts on.
/// Every place of the MVP is there; a run covering other zones will anchor
/// each place on its own date.
#[must_use]
pub fn today_in_france() -> NaiveDate {
    Utc::now().with_timezone(&Tz::Europe__Paris).date_naive()
}

fn local_midnight(tz: Tz, day: NaiveDate) -> Option<chrono::DateTime<Tz>> {
    tz.from_local_datetime(&NaiveDateTime::from(day)).earliest()
}

/// Evaluates `opening_hours` for the window starting on `today`.
#[must_use]
pub fn evaluate(
    opening_hours: Option<&str>,
    country_code: Option<&str>,
    position: Position,
    today: NaiveDate,
) -> OpeningEval {
    let Some(raw) = opening_hours.map(str::trim).filter(|s| !s.is_empty()) else {
        return OpeningEval {
            parsed: false,
            intervals: None,
            until: None,
            window_start: None,
        };
    };
    let not_evaluated = OpeningEval {
        parsed: false,
        intervals: None,
        until: None,
        window_start: Some(today),
    };
    if raw.chars().count() > MAX_EXPRESSION_CHARS {
        return not_evaluated;
    }
    let parsed: Result<OpeningHours, _> = raw.parse();
    let Ok(oh) = parsed else {
        return not_evaluated;
    };
    let window = country_code
        .and_then(|cc| Some((timezone_of(cc)?, cc)))
        .and_then(|(tz, cc)| intervals(&oh, tz, cc, position, today));
    let (intervals, until) = window.map_or((None, None), |(i, u)| (Some(i), Some(u)));
    OpeningEval {
        parsed: true,
        intervals,
        until,
        window_start: Some(today),
    }
}

fn intervals(
    oh: &OpeningHours,
    tz: Tz,
    country_code: &str,
    position: Position,
    today: NaiveDate,
) -> Option<(Vec<OpeningInterval>, DateTime<Utc>)> {
    let start = local_midnight(tz, today)?;
    let end = local_midnight(
        tz,
        today.checked_add_days(chrono::Days::new(u64::try_from(OPENING_WINDOW_DAYS).ok()?))?,
    )?;
    let mut locale = TzLocation::new(tz);
    if let Some(coords) = Coordinates::new(position.lat(), position.lon()) {
        locale = locale.with_coords(coords);
    }
    let mut context = Context::default().with_locale(locale);
    if let Ok(country) = country_code.to_ascii_uppercase().parse::<Country>() {
        context = context.with_holidays(country.holidays());
    }
    let oh = oh.clone().with_context(context);
    let mut out: Vec<OpeningInterval> = Vec::new();
    let mut until = end.with_timezone(&Utc);
    for range in oh.iter_range(start, end) {
        if range.kind != RuleKind::Open {
            continue;
        }
        let (s, e) = (
            range.range.start.with_timezone(&Utc),
            range.range.end.with_timezone(&Utc),
        );
        if s >= e {
            continue;
        }
        // Ranges differing only by their comment come out separately; a
        // client wants one interval per continuous opening.
        let full = out.len() == MAX_INTERVALS;
        match out.last_mut() {
            Some(last) if last.end == s => last.end = e,
            _ if full => {
                // Everything before this opening is known; nothing after.
                until = s;
                break;
            }
            _ => out.push(OpeningInterval { start: s, end: e }),
        }
    }
    Some((out, until))
}

#[cfg(test)]
mod tests {
    use chrono::Timelike;

    use super::*;

    /// Paris: Monday 2 November 2026, the window runs to Monday 16 November
    /// and holds Armistice Day (Wednesday 11 November), a public holiday.
    fn monday() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 11, 2).unwrap()
    }

    fn paris() -> Position {
        Position::new(48.8566, 2.3522).unwrap()
    }

    fn eval(oh: &str) -> OpeningEval {
        evaluate(Some(oh), Some("FR"), paris(), monday())
    }

    fn utc(y: i32, m: u32, d: u32, h: u32) -> chrono::DateTime<Utc> {
        Utc.with_ymd_and_hms(y, m, d, h, 0, 0).unwrap()
    }

    #[test]
    fn always_open_is_one_interval_over_the_window() {
        let e = eval("24/7");
        assert!(e.parsed);
        assert_eq!(e.window_start, Some(monday()));
        assert_eq!(
            e.until,
            Some(utc(2026, 11, 15, 23)),
            "the window ends at local midnight fourteen days later"
        );
        let iv = e.intervals.unwrap();
        // Paris is UTC+1 in November: local midnight is 23:00 UTC the day before.
        assert_eq!(
            iv,
            vec![OpeningInterval {
                start: utc(2026, 11, 1, 23),
                end: utc(2026, 11, 15, 23)
            }]
        );
    }

    #[test]
    fn weekdays_give_one_interval_per_working_day() {
        let iv = eval("Mo-Fr 08:00-19:00").intervals.unwrap();
        assert_eq!(iv.len(), 10, "two weeks of five days");
        assert_eq!(iv[0].start, utc(2026, 11, 2, 7));
        assert_eq!(iv[0].end, utc(2026, 11, 2, 18));
        assert!(
            iv.iter().all(|i| i.start.hour() == 7 && i.end.hour() == 18),
            "local 08:00-19:00 is 07:00-18:00 UTC in winter"
        );
    }

    #[test]
    fn a_lunch_break_splits_the_day() {
        let iv = eval("Mo-Fr 08:00-12:00,14:00-18:00").intervals.unwrap();
        assert_eq!(iv.len(), 20);
        assert_eq!(
            (iv[0].end, iv[1].start),
            (utc(2026, 11, 2, 11), utc(2026, 11, 2, 13))
        );
    }

    #[test]
    fn public_holidays_follow_the_french_calendar() {
        let iv = eval("Mo-Su 09:00-18:00; PH off").intervals.unwrap();
        assert_eq!(iv.len(), 13, "fourteen days minus Armistice Day");
        assert!(
            iv.iter()
                .all(|i| i.start.date_naive() != NaiveDate::from_ymd_opt(2026, 11, 11).unwrap()),
            "closed on 11 November"
        );
    }

    #[test]
    fn closed_for_the_whole_window_is_an_empty_list() {
        let iv = eval("Jun-Aug 09:00-18:00").intervals.unwrap();
        assert!(
            iv.is_empty(),
            "a summer-only place is closed in November, which is an answer"
        );
        assert_eq!(
            eval("Jun-Aug 09:00-18:00").until,
            Some(utc(2026, 11, 15, 23)),
            "closed until the end of the window, not unknown"
        );
    }

    #[test]
    fn a_value_that_opens_every_few_minutes_is_cut_with_its_window() {
        // 20 openings a day, 280 over the window: past the cap.
        let slots: Vec<String> = (0..20)
            .map(|i| format!("{:02}:00-{:02}:30", i, i))
            .collect();
        let e = eval(&format!("Mo-Su {}", slots.join(",")));
        let iv = e.intervals.unwrap();
        assert_eq!(iv.len(), MAX_INTERVALS);
        let until = e.until.unwrap();
        assert!(
            iv.last().unwrap().end <= until && until < utc(2026, 11, 15, 23),
            "the window stops where the first interval left out starts: {until}"
        );
        assert_eq!(until.minute(), 0, "an opening time, not a closing one");
    }

    #[test]
    fn a_value_longer_than_osm_allows_is_not_evaluated() {
        let long = format!("Mo-Fr 08:00-12:00{}", "; Sa 08:00-09:00".repeat(20));
        assert!(long.chars().count() > MAX_EXPRESSION_CHARS);
        assert!(
            long.parse::<OpeningHours>().is_ok(),
            "the value itself parses"
        );
        let e = eval(&long);
        assert_eq!((e.parsed, e.intervals, e.until), (false, None, None));
    }

    #[test]
    fn an_unparseable_value_has_no_intervals() {
        let e = eval("ouvert l'été, demander à la mairie");
        assert!(!e.parsed);
        assert_eq!(e.intervals, None);
        assert_eq!(e.until, None);
    }

    #[test]
    fn no_value_or_unknown_country_has_no_intervals() {
        let none = evaluate(None, Some("FR"), paris(), monday());
        assert_eq!(
            (none.parsed, none.intervals, none.window_start),
            (false, None, None)
        );
        let unknown = evaluate(Some("24/7"), Some("ZZ"), paris(), monday());
        assert!(unknown.parsed);
        assert_eq!(
            unknown.intervals, None,
            "no interval rather than one in the wrong zone"
        );
    }

    #[test]
    fn a_daylight_saving_change_inside_the_window_is_handled() {
        // Monday 19 October 2026: clocks go back on Sunday 25 October.
        let e = evaluate(
            Some("Mo-Su 10:00-11:00"),
            Some("FR"),
            paris(),
            NaiveDate::from_ymd_opt(2026, 10, 19).unwrap(),
        );
        let iv = e.intervals.unwrap();
        assert_eq!(iv.len(), 14);
        assert_eq!(iv[0].start, utc(2026, 10, 19, 8), "summer time, UTC+2");
        assert_eq!(iv[13].start, utc(2026, 11, 1, 9), "winter time, UTC+1");
    }
}

#[cfg(test)]
mod hostile {
    use super::*;

    /// Values a contributor could write, at the length OSM allows: each is
    /// evaluated in a few milliseconds and stays under the interval cap.
    #[test]
    fn hostile_values_evaluate_quickly_and_stay_bounded() {
        let today = NaiveDate::from_ymd_opt(2026, 11, 2).unwrap();
        let paris = Position::new(48.8566, 2.3522).unwrap();
        let minutes: Vec<String> = (0..20).map(|i| format!("{i:02}:01-{i:02}:02")).collect();
        let cases = [
            format!("Mo-Su {}", minutes.join(",")),
            "week 01-53/1 Mo-Su 00:00-24:00; PH off; SH off".to_owned(),
            "sunrise-sunset; (sunrise-01:00)-(sunset+01:00); dawn-dusk".to_owned(),
            "easter -100 days-easter +100 days 00:00-24:00".to_owned(),
            "2026-2099/1 Jan-Dec Mo[1,2,3,4,5,-1] 00:00-24:00".to_owned(),
            "Jan 01-Dec 31 Mo-Su 00:00+".to_owned(),
            "Mo-Su 00:00-24:00; ".repeat(12),
        ];
        // Loads the holiday calendar once, outside the measurements.
        let _ = evaluate(Some("24/7"), Some("FR"), paris, today);
        for c in &cases {
            assert!(c.chars().count() <= MAX_EXPRESSION_CHARS, "{c}");
            let started = std::time::Instant::now();
            let e = evaluate(Some(c), Some("FR"), paris, today);
            let took = started.elapsed();
            assert!(
                took < std::time::Duration::from_millis(500),
                "{c:?} took {took:?}"
            );
            assert!(e.intervals.map_or(0, |i| i.len()) <= MAX_INTERVALS);
        }
    }
}
