import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/sun/sun_times.dart';

// Reference times come from the US Naval Observatory "Rise/Set/Transit
// Times" service (https://aa.usno.navy.mil/api/rstt/oneday, queried on
// 2026-10-06 with the coordinates below), to the minute, converted to UTC:
//
//   Paris 48.8566, 2.3522          2026-06-21  rise 03:47  set 19:58
//   Paris 48.8566, 2.3522          2026-12-21  rise 07:41  set 15:56
//   Annecy 45.8992, 6.1294         2026-03-20  rise 05:39  set 17:48
//   Sydney -33.8688, 151.2093      2026-01-15  rise 05:59  set 20:09 AEDT
//                                  (UTC+11): 2026-01-14 18:59, 2026-01-15 09:09
//   Reykjavik 64.1466, -21.9426    2026-09-23  rise 07:14  set 19:25
//   Tromso 69.6492, 18.9553        2026-06-21  "continuously above the horizon"
//   Tromso 69.6492, 18.9553        2026-12-21  "continuously below the horizon"
//   Honolulu 21.3069, -157.8583    2026-06-21  rise 05:50  set 19:16 HST (UTC-10)
//   Auckland -36.8485, 174.7633    2026-06-22  rise 07:34  set 17:12 NZST (UTC+12)
//   46.6, 2.5                      2026-12-21  rise 07:31  set 16:05
//   45, -75                        2026-12-21  rise 12:35  set 21:21
//
// NOAA's own calculator code (https://gml.noaa.gov/grad/solcalc/main.js,
// calcSunriseSet) gives the same first seven cases within a minute: Paris
// 03:46.9 / 19:57.9 and 07:41.3 / 15:56.1, Annecy 05:38.8 / 17:47.9, Sydney
// 05:59.5 / 20:09.0 local, Reykjavik 07:13.5 / 19:25.1, and no sunrise nor
// sunset in Tromso on either date.

const tolerance = Duration(minutes: 2);

Matcher near(DateTime expected) => predicate<DateTime>(
  (actual) => actual.isUtc && actual.difference(expected).abs() <= tolerance,
  'a UTC instant within $tolerance of $expected',
);

Matcher risesAndSets(DateTime sunrise, DateTime sunset) => isA<SunriseSunset>()
    .having((s) => s.sunrise, 'sunrise', near(sunrise))
    .having((s) => s.sunset, 'sunset', near(sunset));

const ({double lat, double lon}) paris = (lat: 48.8566, lon: 2.3522);
const ({double lat, double lon}) tromso = (lat: 69.6492, lon: 18.9553);

/// A zone that adds an hour from April to October, as Central European Time does.
Duration centralEurope(DateTime local) =>
    Duration(hours: local.month >= 4 && local.month <= 10 ? 2 : 1);

/// A zone that adds an hour from October to April, as Sydney does.
Duration eastAustralia(DateTime local) =>
    Duration(hours: local.month >= 4 && local.month <= 9 ? 10 : 11);

void main() {
  group('sunrise and sunset', () {
    test('Paris at the June solstice', () {
      expect(
        sunTimesOn(DateTime(2026, 6, 21), lat: paris.lat, lon: paris.lon),
        risesAndSets(DateTime.utc(2026, 6, 21, 3, 47), DateTime.utc(2026, 6, 21, 19, 58)),
      );
    });

    test('Paris at the December solstice', () {
      expect(
        sunTimesOn(DateTime(2026, 12, 21), lat: paris.lat, lon: paris.lon),
        risesAndSets(DateTime.utc(2026, 12, 21, 7, 41), DateTime.utc(2026, 12, 21, 15, 56)),
      );
    });

    test('Annecy at the March equinox', () {
      expect(
        sunTimesOn(DateTime(2026, 3, 20), lat: 45.8992, lon: 6.1294),
        risesAndSets(DateTime.utc(2026, 3, 20, 5, 39), DateTime.utc(2026, 3, 20, 17, 48)),
      );
    });

    test('Sydney in January rises on the UTC date before the local one', () {
      expect(
        sunTimesOn(DateTime(2026, 1, 15), lat: -33.8688, lon: 151.2093),
        risesAndSets(DateTime.utc(2026, 1, 14, 18, 59), DateTime.utc(2026, 1, 15, 9, 9)),
      );
    });

    test('Reykjavik at the September equinox', () {
      expect(
        sunTimesOn(DateTime(2026, 9, 23), lat: 64.1466, lon: -21.9426),
        risesAndSets(DateTime.utc(2026, 9, 23, 7, 14), DateTime.utc(2026, 9, 23, 19, 25)),
      );
    });

    test('Tromso has the midnight sun at the June solstice', () {
      expect(sunTimesOn(DateTime(2026, 6, 21), lat: tromso.lat, lon: tromso.lon), isA<PolarDay>());
    });

    test('Tromso has the polar night at the December solstice', () {
      expect(
        sunTimesOn(DateTime(2026, 12, 21), lat: tromso.lat, lon: tromso.lon),
        isA<PolarNight>(),
      );
    });

    test('only the calendar date of the argument counts, not its time of day', () {
      expect(
        sunTimesOn(DateTime.utc(2026, 6, 21, 23, 30), lat: paris.lat, lon: paris.lon),
        sunTimesOn(DateTime.utc(2026, 6, 21), lat: paris.lat, lon: paris.lon),
      );
    });
  });

  group('isDaylightAt', () {
    bool inParis(DateTime instant) => isDaylightAt(instant, lat: paris.lat, lon: paris.lon);

    test('dark five minutes before sunrise, light five minutes after', () {
      expect(inParis(DateTime.utc(2026, 6, 21, 3, 42)), isFalse);
      expect(inParis(DateTime.utc(2026, 6, 21, 3, 52)), isTrue);
    });

    test('light five minutes before sunset, dark five minutes after', () {
      expect(inParis(DateTime.utc(2026, 6, 21, 19, 53)), isTrue);
      expect(inParis(DateTime.utc(2026, 6, 21, 20, 3)), isFalse);
    });

    test('the midnight sun is light at midnight, the polar night dark at noon', () {
      // USNO gives Tromso's lower transit at 22:46 UTC on 21 June, and civil
      // twilight from 08:31 to 12:53 UTC on 21 December, centred on 10:42.
      expect(
        isDaylightAt(DateTime.utc(2026, 6, 21, 22, 46), lat: tromso.lat, lon: tromso.lon),
        isTrue,
      );
      expect(
        isDaylightAt(DateTime.utc(2026, 12, 21, 10, 42), lat: tromso.lat, lon: tromso.lon),
        isFalse,
      );
    });

    test('far west, an afternoon in Honolulu is daylight though the UTC date moved on', () {
      // 2026-06-22 02:00 UTC is 16:00 on 21 June in Honolulu, whose sun sets
      // at 19:16 HST, 05:16 UTC on 22 June. Reading the UTC date would pick
      // the sun of 22 June, which has not risen yet.
      expect(isDaylightAt(DateTime.utc(2026, 6, 22, 2), lat: 21.3069, lon: -157.8583), isTrue);
      expect(isDaylightAt(DateTime.utc(2026, 6, 22, 6), lat: 21.3069, lon: -157.8583), isFalse);
    });

    test('far east, a morning in Auckland is daylight though the UTC date lags behind', () {
      // 2026-06-21 22:00 UTC is 10:00 on 22 June in Auckland, whose sun rose
      // at 07:34 NZST, 19:34 UTC on 21 June. Reading the UTC date would pick
      // the sun of 21 June, which has already set.
      expect(isDaylightAt(DateTime.utc(2026, 6, 21, 22), lat: -36.8485, lon: 174.7633), isTrue);
      expect(isDaylightAt(DateTime.utc(2026, 6, 22, 6), lat: -36.8485, lon: 174.7633), isFalse);
    });
  });

  group('standardUtcOffset', () {
    test('a northern zone with summer time gives its winter offset all year', () {
      for (final clock in [DateTime(2026, 1, 15), DateTime(2026, 7, 15)]) {
        expect(standardUtcOffset(() => clock, offsetAt: centralEurope), const Duration(hours: 1));
      }
    });

    test('a southern zone with summer time gives its winter offset all year', () {
      for (final clock in [DateTime(2026, 1, 15), DateTime(2026, 7, 15)]) {
        expect(standardUtcOffset(() => clock, offsetAt: eastAustralia), const Duration(hours: 10));
      }
    });

    test('the year comes from the clock', () {
      // A zone that moved its standard time from UTC+4 to UTC+3 in 2026.
      Duration moved(DateTime local) => Duration(hours: local.year < 2026 ? 4 : 3);
      expect(standardUtcOffset(() => DateTime(2025, 7), offsetAt: moved), const Duration(hours: 4));
      expect(standardUtcOffset(() => DateTime(2026, 7), offsetAt: moved), const Duration(hours: 3));
    });

    test('the device zone gives the same offset in winter and summer, never above either', () {
      final winter = DateTime(2026, 1, 15);
      final summer = DateTime(2026, 7, 15);
      final offset = standardUtcOffset(() => summer);
      expect(standardUtcOffset(() => winter), offset);
      expect(offset <= winter.timeZoneOffset && offset <= summer.timeZoneOffset, isTrue);
    });
  });

  group('representativePoint', () {
    test('UTC+1 stands for the middle of France', () {
      expect(representativePoint(const Duration(hours: 1)), (lat: 46.6, lon: 2.5));
    });

    test('UTC+0 stands for London', () {
      expect(representativePoint(Duration.zero), (lat: 51.5, lon: -0.1));
    });

    test('any other offset gives latitude 45 and 15 degrees of longitude per hour', () {
      expect(representativePoint(const Duration(hours: -5)), (lat: 45.0, lon: -75.0));
      expect(representativePoint(const Duration(hours: 5, minutes: 30)), (lat: 45.0, lon: 82.5));
      expect(representativePoint(const Duration(hours: 9)), (lat: 45.0, lon: 135.0));
      expect(representativePoint(const Duration(hours: 14)), (lat: 45.0, lon: 210.0));
    });
  });

  group('isNightAt', () {
    // 10:00 UTC on 21 December: day in Paris and in the middle of France,
    // night at 45, -75 (UTC-5), where the sun rises at 12:35 UTC.
    final morning = DateTime.utc(2026, 12, 21, 10);

    test('a known position wins over the time zone', () {
      expect(
        isNightAt(
          morning,
          lat: paris.lat,
          lon: paris.lon,
          standardOffset: const Duration(hours: -5),
        ),
        isFalse,
      );
      expect(
        isNightAt(
          DateTime.utc(2026, 12, 21, 18),
          lat: paris.lat,
          lon: paris.lon,
          standardOffset: Duration.zero,
        ),
        isTrue,
      );
    });

    test("without a position the time zone's point decides", () {
      expect(isNightAt(morning, standardOffset: const Duration(hours: 1)), isFalse);
      expect(isNightAt(morning, standardOffset: const Duration(hours: -5)), isTrue);
    });

    test('a single coordinate is not a position', () {
      expect(isNightAt(morning, lat: paris.lat, standardOffset: const Duration(hours: -5)), isTrue);
      expect(isNightAt(morning, lon: paris.lon, standardOffset: const Duration(hours: -5)), isTrue);
    });
  });
}
