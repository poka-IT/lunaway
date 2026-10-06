//! Evaluating OSM `opening_hours` into UTC intervals.
//!
//! The device cannot evaluate the syntax (no Dart evaluator exists), so the
//! server ships two weeks of open intervals with each place and refreshes
//! them daily.
//!
//! The window runs from local midnight of the place's own today for
//! [`OPENING_WINDOW_DAYS`] days, in the time zone of where it is:
//! [`timezone_at`] maps a country to its zone, and the Canary Islands, the
//! Azores and Madeira to theirs; a country it does not know yields no
//! intervals rather than intervals in the wrong zone. The window moves at
//! the next local midnight (`refresh_at`), so a place in Lisbon and one in
//! Helsinki each start their day at their own midnight. Public holidays
//! (`PH`) follow the national calendar of the country, embedded in the
//! `opening-hours` crate (Nager.Date data); regional holidays are not
//! applied, so in Alsace-Moselle Good Friday and 26 December count as
//! ordinary days, and so do the holidays of a German Land or a Spanish
//! community. Sun events (`sunrise`, `sunset`) are computed at the place's
//! position. Only `open` periods become intervals: `unknown` ones ("on
//! appointment", a comment without a time) are not claimed as open.
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

/// The zone of a country, for the countries the data covers and their
/// neighbours. A country with islands in another zone (Spain, Portugal)
/// maps to its mainland zone here; [`timezone_at`] tells the islands apart.
#[must_use]
pub fn timezone_of(country_code: &str) -> Option<Tz> {
    Some(match country_code.to_ascii_uppercase().as_str() {
        "FR" | "MC" => Tz::Europe__Paris,
        "BE" => Tz::Europe__Brussels,
        "LU" => Tz::Europe__Luxembourg,
        "CH" => Tz::Europe__Zurich,
        "LI" => Tz::Europe__Vaduz,
        "DE" => Tz::Europe__Berlin,
        "AT" => Tz::Europe__Vienna,
        "IT" => Tz::Europe__Rome,
        "SM" => Tz::Europe__San_Marino,
        "VA" => Tz::Europe__Vatican,
        "AD" => Tz::Europe__Andorra,
        "ES" => Tz::Europe__Madrid,
        "GI" => Tz::Europe__Gibraltar,
        "PT" => Tz::Europe__Lisbon,
        "NL" => Tz::Europe__Amsterdam,
        "GB" => Tz::Europe__London,
        "IE" => Tz::Europe__Dublin,
        "DK" => Tz::Europe__Copenhagen,
        "NO" => Tz::Europe__Oslo,
        "SJ" => Tz::Arctic__Longyearbyen,
        "SE" => Tz::Europe__Stockholm,
        "FI" => Tz::Europe__Helsinki,
        "AX" => Tz::Europe__Mariehamn,
        "HR" => Tz::Europe__Zagreb,
        "SI" => Tz::Europe__Ljubljana,
        "GR" => Tz::Europe__Athens,
        "PL" => Tz::Europe__Warsaw,
        "CZ" => Tz::Europe__Prague,
        "SK" => Tz::Europe__Bratislava,
        "HU" => Tz::Europe__Budapest,
        _ => return None,
    })
}

/// The zone of a place: its country's, or its island's where the island
/// keeps another time (the Canary Islands, the Azores, Madeira).
#[must_use]
pub fn timezone_at(country_code: &str, position: Position) -> Option<Tz> {
    let country = country_code.to_ascii_uppercase();
    if matches!(country.as_str(), "ES" | "PT") {
        let areas = lunaway_domain::region::areas_at(position);
        if areas.contains(&"IC") {
            return Some(Tz::Atlantic__Canary);
        }
        if areas.contains(&"PT-20") {
            return Some(Tz::Atlantic__Azores);
        }
        if areas.contains(&"PT-30") {
            return Some(Tz::Atlantic__Madeira);
        }
    }
    timezone_of(&country)
}

/// The local date at `now` in the zone of a place, the first day of its
/// window; the UTC date when its zone is unknown.
#[must_use]
pub fn local_today(
    country_code: Option<&str>,
    position: Position,
    now: DateTime<Utc>,
) -> NaiveDate {
    country_code
        .and_then(|cc| timezone_at(cc, position))
        .map_or_else(
            || now.date_naive(),
            |tz| now.with_timezone(&tz).date_naive(),
        )
}

/// When a window starting on `start` must move: the next local midnight,
/// in the zone of the place (UTC midnight when it is unknown).
#[must_use]
pub fn refresh_at(
    country_code: Option<&str>,
    position: Position,
    start: NaiveDate,
) -> DateTime<Utc> {
    let next = start.succ_opt().unwrap_or(start);
    country_code
        .and_then(|cc| timezone_at(cc, position))
        .and_then(|tz| local_midnight(tz, next))
        .map_or_else(
            || Utc.from_utc_datetime(&NaiveDateTime::from(next)),
            |m| m.with_timezone(&Utc),
        )
}

/// Today in metropolitan France: the first day La Poste's calendar is asked
/// for (a French source).
#[must_use]
pub fn today_in_france() -> NaiveDate {
    Utc::now().with_timezone(&Tz::Europe__Paris).date_naive()
}

fn local_midnight(tz: Tz, day: NaiveDate) -> Option<chrono::DateTime<Tz>> {
    tz.from_local_datetime(&NaiveDateTime::from(day)).earliest()
}

/// Evaluates `opening_hours` for the window starting on the place's own
/// today at `now`.
#[must_use]
pub fn evaluate_at(
    opening_hours: Option<&str>,
    country_code: Option<&str>,
    position: Position,
    now: DateTime<Utc>,
) -> OpeningEval {
    evaluate(
        opening_hours,
        country_code,
        position,
        local_today(country_code, position, now),
    )
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
            refresh_at: None,
        };
    };
    let refresh = Some(refresh_at(country_code, position, today));
    let not_evaluated = OpeningEval {
        parsed: false,
        intervals: None,
        until: None,
        window_start: Some(today),
        refresh_at: refresh,
    };
    if raw.chars().count() > MAX_EXPRESSION_CHARS {
        return not_evaluated;
    }
    let parsed: Result<OpeningHours, _> = raw.parse();
    let Ok(oh) = parsed else {
        return not_evaluated;
    };
    let window = country_code
        .and_then(|cc| Some((timezone_at(cc, position)?, cc)))
        .and_then(|(tz, cc)| intervals(&oh, tz, cc, position, today));
    let (intervals, until) = window.map_or((None, None), |(i, u)| (Some(i), Some(u)));
    OpeningEval {
        parsed: true,
        intervals,
        until,
        window_start: Some(today),
        refresh_at: refresh,
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

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    #[test]
    fn each_place_starts_its_window_at_its_own_midnight() {
        // 23:30 UTC on Monday 2 November: already Tuesday in Paris and
        // Helsinki, still Monday in Lisbon.
        let now = Utc.with_ymd_and_hms(2026, 11, 2, 23, 30, 0).unwrap();
        let lisbon = evaluate_at(Some("24/7"), Some("PT"), at(38.72, -9.14), now);
        assert_eq!(
            lisbon.window_start,
            NaiveDate::from_ymd_opt(2026, 11, 2),
            "a Lisbon place keeps its Monday: its open hour before midnight is known"
        );
        assert_eq!(
            lisbon.refresh_at,
            Some(utc(2026, 11, 3, 0)),
            "and moves at Lisbon's midnight, UTC in winter"
        );
        let paris_place = evaluate_at(Some("24/7"), Some("FR"), paris(), now);
        assert_eq!(
            paris_place.window_start,
            NaiveDate::from_ymd_opt(2026, 11, 3)
        );
        assert_eq!(paris_place.refresh_at, Some(utc(2026, 11, 3, 23)));
        let helsinki = evaluate_at(Some("24/7"), Some("FI"), at(60.17, 24.94), now);
        assert_eq!(helsinki.refresh_at, Some(utc(2026, 11, 3, 22)));
        assert_eq!(
            helsinki.intervals.unwrap()[0].start,
            utc(2026, 11, 2, 22),
            "Helsinki's day began at 22:00 UTC"
        );
    }

    #[test]
    fn islands_keep_their_own_time() {
        let canary = at(28.1, -15.43);
        assert_eq!(timezone_at("ES", canary), Some(Tz::Atlantic__Canary));
        assert_eq!(
            timezone_at("ES", at(40.42, -3.70)),
            Some(Tz::Europe__Madrid)
        );
        assert_eq!(
            timezone_at("PT", at(37.74, -25.67)),
            Some(Tz::Atlantic__Azores)
        );
        assert_eq!(
            timezone_at("PT", at(32.65, -16.91)),
            Some(Tz::Atlantic__Madeira)
        );
        let e = evaluate(Some("24/7"), Some("ES"), canary, monday());
        assert_eq!(
            e.intervals.unwrap()[0].start,
            utc(2026, 11, 2, 0),
            "Canarian midnight is UTC midnight in winter, an hour after Madrid's"
        );
    }

    #[test]
    fn public_holidays_follow_each_country() {
        // Saturday 3 October 2026, German Unity Day: a holiday in Germany,
        // an ordinary Saturday in France.
        let week = NaiveDate::from_ymd_opt(2026, 9, 28).unwrap();
        let oh = "Mo-Su 09:00-18:00; PH off";
        let open_on_the_3rd = |e: OpeningEval| {
            e.intervals
                .unwrap()
                .iter()
                .any(|i| i.start.date_naive() == NaiveDate::from_ymd_opt(2026, 10, 3).unwrap())
        };
        assert!(!open_on_the_3rd(evaluate(
            Some(oh),
            Some("DE"),
            at(52.52, 13.40),
            week
        )));
        assert!(open_on_the_3rd(evaluate(
            Some(oh),
            Some("FR"),
            paris(),
            week
        )));
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
