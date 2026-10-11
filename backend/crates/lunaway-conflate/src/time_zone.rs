//! The time zone of a place, from the IANA time zone database.
//!
//! A place keeps the clock of a zone the database gives its country in
//! `data/zone.tab`, the database's own table of countries and zones: the
//! only one for most countries; for a country with several, the zone whose
//! principal location (the city the table places it at) is nearest. That
//! tells the Canary Islands, the Azores and Madeira from their mainland,
//! and picks between zones with the same clock in Germany (Busingen) and
//! Spain (Ceuta). It is an approximation where zones with different clocks
//! meet inside a country: in Russia, and in southern Ukraine, nearer
//! Simferopol than Kyiv, which reads Crimea's clock (an hour ahead in
//! winter). A country the table does not name (Kosovo, `XK`) has no zone.
//!
//! The rules of every zone come from the database jiff bundles in the
//! binary (`jiff-tzdb`), never from the host, and `zone.tab` from the same
//! release. The app embeds the same table and the same rules
//! (`app/lib/core/time/zone_data.g.dart`, written by
//! `app/tool/time_zones/generate.dart`), so a place reads one clock on the
//! server and on a device; a test holds the two to one release. Moving to
//! a new release: `cargo update -p jiff-tzdb`, then the generator on that
//! release (`docs/architecture.md`, "Time zones").

use std::fmt;
use std::sync::LazyLock;

use chrono::{
    Datelike, FixedOffset, MappedLocalTime, NaiveDate, NaiveDateTime, NaiveTime, Offset, TimeZone,
    Timelike, Utc,
};
use jiff::tz::{AmbiguousOffset, TimeZoneDatabase};
use lunaway_domain::Position;

/// The database's table of countries and zones, as IANA publishes it.
const ZONE_TAB: &str = include_str!("../data/zone.tab");

/// A row of `zone.tab`: a zone of a country and its principal location.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Centre {
    country: &'static str,
    zone: &'static str,
    lat: f64,
    lon: f64,
}

impl Centre {
    /// A distance to `p` that orders like the true one at these scales:
    /// degrees, the longitude shrunk by the cosine of the mean latitude.
    /// The app computes the same (`PlaceZone`).
    fn distance(&self, p: Position) -> f64 {
        let dlat = self.lat - p.lat();
        let dlon = (self.lon - p.lon() + 540.0).rem_euclid(360.0) - 180.0;
        let shrink = ((self.lat + p.lat()) / 2.0).to_radians().cos();
        dlat * dlat + (dlon * shrink) * (dlon * shrink)
    }
}

static CENTRES: LazyLock<Vec<Centre>> =
    LazyLock::new(|| ZONE_TAB.lines().filter_map(centre).collect());

static DATABASE: LazyLock<TimeZoneDatabase> = LazyLock::new(TimeZoneDatabase::bundled);

/// A data row of `zone.tab`: country, coordinates, zone, comments, split
/// by tabs; comment lines start with `#`.
fn centre(line: &'static str) -> Option<Centre> {
    if line.starts_with('#') {
        return None;
    }
    let mut columns = line.split('\t');
    let country = columns.next()?;
    let (lat, lon) = iso6709(columns.next()?)?;
    let zone = columns.next()?;
    Some(Centre {
        country,
        zone,
        lat,
        lon,
    })
}

/// `+DDMM-DDDMM` or `+DDMMSS-DDDMMSS`: latitude, then longitude.
fn iso6709(text: &str) -> Option<(f64, f64)> {
    let split = 1 + text.get(1..)?.find(['+', '-'])?;
    Some((angle(text.get(..split)?, 2)?, angle(text.get(split..)?, 3)?))
}

/// A signed angle of `degree_digits` digits of degrees, two of minutes and
/// two of seconds or none.
fn angle(text: &str, degree_digits: usize) -> Option<f64> {
    let sign = match text.as_bytes().first()? {
        b'+' => 1.0,
        b'-' => -1.0,
        _ => return None,
    };
    let digits = text.get(1..)?;
    if !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let (degrees, rest) = digits.split_at_checked(degree_digits)?;
    let (minutes, seconds) = rest.split_at_checked(2)?;
    if !matches!(seconds.len(), 0 | 2) {
        return None;
    }
    let degrees: f64 = degrees.parse().ok()?;
    let minutes: f64 = minutes.parse().ok()?;
    let seconds: f64 = if seconds.is_empty() {
        0.0
    } else {
        seconds.parse().ok()?
    };
    Some(sign * (degrees + (minutes + seconds / 60.0) / 60.0))
}

/// The name of the zone of a place in `country_code` (ISO 3166-1 alpha-2,
/// any case) at `position`: see the module. `None` for a country the
/// database does not name.
#[must_use]
pub fn zone_name_at(country_code: &str, position: Position) -> Option<&'static str> {
    CENTRES
        .iter()
        .filter(|c| c.country.eq_ignore_ascii_case(country_code))
        .min_by(|a, b| a.distance(position).total_cmp(&b.distance(position)))
        .map(|c| c.zone)
}

/// The zone of a place in `country_code` at `position` ([`zone_name_at`]).
#[must_use]
pub fn place_zone(country_code: &str, position: Position) -> Option<PlaceTz> {
    zone_name_at(country_code, position).and_then(PlaceTz::named)
}

/// A zone of the database, read through chrono's [`TimeZone`]: what the
/// `opening_hours` evaluator walks a window of days in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaceTz(jiff::tz::TimeZone);

impl PlaceTz {
    /// The zone named `name` (`Europe/Paris`) in the bundled database.
    #[must_use]
    pub fn named(name: &str) -> Option<Self> {
        DATABASE.get(name).ok().map(Self)
    }

    /// Paris, the clock of the French sources (La Poste's calendar). UTC
    /// if the bundled database lacked it, which a test rules out.
    #[must_use]
    pub fn paris() -> Self {
        Self::named("Europe/Paris").unwrap_or(Self(jiff::tz::TimeZone::UTC))
    }

    /// Its name in the database (`Africa/Casablanca`).
    #[must_use]
    pub fn name(&self) -> Option<&str> {
        self.0.iana_name()
    }

    fn offset(&self, offset: jiff::tz::Offset) -> PlaceOffset {
        PlaceOffset {
            zone: self.0.clone(),
            // Every offset of the database is within a day; chrono's bound.
            fixed: FixedOffset::east_opt(offset.seconds()).unwrap_or_else(|| Utc.fix()),
        }
    }
}

/// The offset of a [`PlaceTz`] at some instant, with its zone, as chrono
/// asks of an offset.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaceOffset {
    zone: jiff::tz::TimeZone,
    fixed: FixedOffset,
}

impl Offset for PlaceOffset {
    fn fix(&self) -> FixedOffset {
        self.fixed
    }
}

impl fmt::Display for PlaceOffset {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.fixed.fmt(f)
    }
}

impl TimeZone for PlaceTz {
    type Offset = PlaceOffset;

    fn from_offset(offset: &PlaceOffset) -> Self {
        Self(offset.zone.clone())
    }

    fn offset_from_local_date(&self, local: &NaiveDate) -> MappedLocalTime<PlaceOffset> {
        self.offset_from_local_datetime(&local.and_time(NaiveTime::MIN))
    }

    fn offset_from_local_datetime(&self, local: &NaiveDateTime) -> MappedLocalTime<PlaceOffset> {
        let Some(civil) = civil(local) else {
            return MappedLocalTime::None;
        };
        match self.0.to_ambiguous_timestamp(civil).offset() {
            AmbiguousOffset::Unambiguous { offset } => MappedLocalTime::Single(self.offset(offset)),
            // A wall clock time the change skips (spring forward).
            AmbiguousOffset::Gap { .. } => MappedLocalTime::None,
            // One that happens twice (fall back): the earlier instant has
            // the offset before the change.
            AmbiguousOffset::Fold { before, after } => {
                MappedLocalTime::Ambiguous(self.offset(before), self.offset(after))
            }
        }
    }

    fn offset_from_utc_date(&self, utc: &NaiveDate) -> PlaceOffset {
        self.offset_from_utc_datetime(&utc.and_time(NaiveTime::MIN))
    }

    fn offset_from_utc_datetime(&self, utc: &NaiveDateTime) -> PlaceOffset {
        let second = utc.and_utc().timestamp();
        // Outside jiff's years (-9999 to 9999), the offset at its bound.
        let at = jiff::Timestamp::from_second(second).unwrap_or(if second < 0 {
            jiff::Timestamp::MIN
        } else {
            jiff::Timestamp::MAX
        });
        self.offset(self.0.to_offset(at))
    }
}

/// `local` as jiff's civil time; `None` outside its years.
fn civil(local: &NaiveDateTime) -> Option<jiff::civil::DateTime> {
    jiff::civil::DateTime::new(
        i16::try_from(local.year()).ok()?,
        i8::try_from(local.month()).ok()?,
        i8::try_from(local.day()).ok()?,
        i8::try_from(local.hour()).ok()?,
        i8::try_from(local.minute()).ok()?,
        i8::try_from(local.second()).ok()?,
        // chrono writes a leap second as a nanosecond past a billion.
        i32::try_from(local.nanosecond().min(999_999_999)).ok()?,
    )
    .ok()
}

#[cfg(test)]
mod tests {
    use chrono::DateTime;

    use super::*;

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    fn marrakech() -> Position {
        at(31.63, -8.0)
    }

    fn utc(y: i32, m: u32, d: u32, h: u32, min: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(y, m, d, h, min, 0).unwrap()
    }

    fn offset_hours(tz: &PlaceTz, instant: DateTime<Utc>) -> f64 {
        f64::from(instant.with_timezone(tz).offset().fix().local_minus_utc()) / 3600.0
    }

    #[test]
    fn every_country_takes_its_zone_from_the_database() {
        assert_eq!(zone_name_at("MA", marrakech()), Some("Africa/Casablanca"));
        assert_eq!(
            zone_name_at("EH", at(27.15, -13.2)),
            Some("Africa/El_Aaiun"),
            "Laayoune keeps Western Sahara's zone, whatever region it syncs with"
        );
        assert_eq!(zone_name_at("fr", at(48.86, 2.35)), Some("Europe/Paris"));
        assert_eq!(
            zone_name_at("TR", at(41.01, 28.97)),
            Some("Europe/Istanbul")
        );
        assert_eq!(
            zone_name_at("AX", at(60.1, 19.94)),
            Some("Europe/Mariehamn")
        );
        assert_eq!(
            zone_name_at("SJ", at(78.22, 15.65)),
            Some("Arctic/Longyearbyen")
        );
        assert_eq!(
            zone_name_at("XK", at(42.67, 21.17)),
            None,
            "no row for Kosovo"
        );
        assert_eq!(zone_name_at("ZZ", marrakech()), None);
    }

    #[test]
    fn islands_take_the_zone_of_the_nearest_principal_location() {
        assert_eq!(
            zone_name_at("ES", at(28.1, -15.43)),
            Some("Atlantic/Canary")
        );
        assert_eq!(
            zone_name_at("ES", at(28.75, -17.9)),
            Some("Atlantic/Canary"),
            "La Palma"
        );
        assert_eq!(zone_name_at("ES", at(40.42, -3.70)), Some("Europe/Madrid"));
        assert_eq!(
            zone_name_at("ES", at(39.57, 2.65)),
            Some("Europe/Madrid"),
            "Majorca"
        );
        assert_eq!(
            zone_name_at("PT", at(37.74, -25.67)),
            Some("Atlantic/Azores")
        );
        assert_eq!(
            zone_name_at("PT", at(39.45, -31.13)),
            Some("Atlantic/Azores"),
            "Flores"
        );
        assert_eq!(
            zone_name_at("PT", at(32.65, -16.91)),
            Some("Atlantic/Madeira")
        );
        assert_eq!(zone_name_at("PT", at(41.15, -8.61)), Some("Europe/Lisbon"));
        // Seville is nearer Ceuta than Madrid: a zone with Madrid's clock.
        let seville = place_zone("ES", at(37.39, -5.98)).unwrap();
        let madrid = place_zone("ES", at(40.42, -3.70)).unwrap();
        for instant in [utc(2026, 1, 15, 12, 0), utc(2026, 7, 15, 12, 0)] {
            assert_eq!(
                offset_hours(&seville, instant),
                offset_hours(&madrid, instant)
            );
        }
    }

    #[test]
    fn morocco_is_back_at_utc_since_september_2026() {
        // tzdata 2026c: Decree 2.26.530 ends +01 on 2026-09-20 at 02:00
        // local; ramadan 2026 (15 February to 22 March) was already at +00.
        let morocco = place_zone("MA", marrakech()).unwrap();
        let france = place_zone("FR", at(48.86, 2.35)).unwrap();
        let cases = [
            (
                utc(2026, 1, 15, 12, 0),
                1.0,
                1.0,
                "winter 2026, +01 like Paris",
            ),
            (utc(2026, 3, 1, 12, 0), 0.0, 1.0, "ramadan 2026"),
            (utc(2026, 7, 15, 12, 0), 1.0, 2.0, "summer 2026"),
            (utc(2026, 9, 20, 0, 59), 1.0, 2.0, "the last minute of +01"),
            (
                utc(2026, 9, 20, 1, 0),
                0.0,
                2.0,
                "02:00 local becomes 01:00",
            ),
            (
                utc(2027, 2, 20, 12, 0),
                0.0,
                1.0,
                "ramadan 2027, no change any more",
            ),
            (
                utc(2027, 7, 15, 12, 0),
                0.0,
                2.0,
                "summer 2027, two hours behind Paris",
            ),
        ];
        for (instant, rabat, paris, why) in cases {
            assert_eq!(offset_hours(&morocco, instant), rabat, "Morocco, {why}");
            assert_eq!(offset_hours(&france, instant), paris, "France, {why}");
        }
        let laayoune = place_zone("EH", at(27.15, -13.2)).unwrap();
        assert_eq!(offset_hours(&laayoune, utc(2027, 7, 15, 12, 0)), 0.0);
    }

    #[test]
    fn local_times_map_to_instants_across_the_changes() {
        let paris = PlaceTz::paris();
        assert_eq!(
            paris.name(),
            Some("Europe/Paris"),
            "bundled, not the UTC fallback"
        );
        let spring = NaiveDate::from_ymd_opt(2026, 3, 29).unwrap();
        assert_eq!(
            paris.from_local_datetime(&spring.and_hms_opt(2, 30, 0).unwrap()),
            MappedLocalTime::None,
            "02:30 does not exist on the last Sunday of March"
        );
        let autumn = NaiveDate::from_ymd_opt(2026, 10, 25).unwrap();
        let twice = paris.from_local_datetime(&autumn.and_hms_opt(2, 30, 0).unwrap());
        let (earliest, latest) = match twice {
            MappedLocalTime::Ambiguous(a, b) => (a, b),
            other => panic!("02:30 happens twice on the last Sunday of October: {other:?}"),
        };
        assert_eq!(earliest.with_timezone(&Utc), utc(2026, 10, 25, 0, 30));
        assert_eq!(latest.with_timezone(&Utc), utc(2026, 10, 25, 1, 30));
        let noon = paris
            .from_local_datetime(&autumn.and_hms_opt(12, 0, 0).unwrap())
            .single()
            .unwrap();
        assert_eq!(noon.with_timezone(&Utc), utc(2026, 10, 25, 11, 0));
        assert_eq!(noon.to_rfc3339(), "2026-10-25T12:00:00+01:00");
    }

    #[test]
    fn every_zone_of_the_table_is_in_the_bundled_database() {
        assert!(CENTRES.len() > 400, "{} rows read", CENTRES.len());
        let missing: Vec<&str> = CENTRES
            .iter()
            .filter(|c| PlaceTz::named(c.zone).is_none())
            .map(|c| c.zone)
            .collect();
        assert!(
            missing.is_empty(),
            "zone.tab names zones the bundled database lacks, a newer release than jiff-tzdb's: {missing:?}"
        );
    }

    #[test]
    fn coordinates_read_as_iso_6709() {
        let rabat = iso6709("+3339-00735").unwrap();
        assert!((rabat.0 - 33.65).abs() < 1e-9 && (rabat.1 + 7.583_333).abs() < 1e-6);
        let london = iso6709("+513030-0000731").unwrap();
        assert!((london.0 - 51.508_333).abs() < 1e-6 && (london.1 + 0.125_277).abs() < 1e-6);
        assert_eq!(iso6709("+33-00735"), None);
        assert_eq!(iso6709("3339-00735"), None);
    }

    /// The app embeds the table and the rules of one release; this one
    /// bundles another, and a place would read two clocks.
    #[test]
    fn the_app_embeds_the_release_the_server_bundles() {
        let app = include_str!("../../../../app/lib/core/time/zone_data.g.dart");
        let release = app
            .lines()
            .find_map(|l| l.strip_prefix("const tzdataRelease = '"))
            .and_then(|l| l.strip_suffix("';"));
        assert_eq!(
            release,
            jiff_tzdb::VERSION,
            "regenerate the app's zones from the release jiff-tzdb bundles (docs/architecture.md, \"Time zones\")"
        );
        let rows: Vec<(&str, &str)> = app
            .lines()
            .filter_map(|l| l.trim().strip_prefix("('"))
            .filter_map(|l| {
                let mut fields = l.split('\'');
                let country = fields.next()?;
                let zone = fields.nth(1)?;
                Some((country, zone))
            })
            .collect();
        let server: Vec<(&str, &str)> = CENTRES.iter().map(|c| (c.country, c.zone)).collect();
        assert_eq!(rows, server, "the app's table is not this zone.tab");
    }
}
