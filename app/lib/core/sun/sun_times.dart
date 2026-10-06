import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Sunrise and sunset on one calendar date at one position.
///
/// Computed by [sunTimesOn] with the NOAA solar calculator algorithm
/// (https://gml.noaa.gov/grad/solcalc/). NOAA gives it as accurate to a
/// minute between latitudes 72 south and 72 north and to ten minutes beyond,
/// for the years 1800 to 2100.
@immutable
sealed class SunTimes {
  const new();
}

/// A day on which the sun rises and sets.
///
/// Both instants are UTC. Far from the Greenwich meridian they can fall on
/// the UTC date before or after the requested one: in Sydney the sun of
/// 15 January rises at 18:59 UTC on 14 January.
final class SunriseSunset extends SunTimes {
  const new(this.sunrise, this.sunset);

  final DateTime sunrise;
  final DateTime sunset;

  @override
  bool operator ==(Object other) =>
      other is SunriseSunset && other.sunrise == sunrise && other.sunset == sunset;

  @override
  int get hashCode => Object.hash(sunrise, sunset);

  @override
  String toString() => 'SunriseSunset($sunrise, $sunset)';
}

/// The sun stays above the horizon for the whole day (midnight sun).
final class PolarDay extends SunTimes {
  const new();
}

/// The sun stays below the horizon for the whole day.
final class PolarNight extends SunTimes {
  const new();
}

/// Zenith angle of the sun's centre at sunrise and sunset, in degrees: 90
/// plus 34 arcminutes of atmospheric refraction plus the 16 arcminutes of the
/// solar disc's radius. Almanacs and the NOAA calculator use the same value.
const double _horizonZenith = 90.833;

/// Sunrise and sunset on [date] at latitude [lat] and longitude [lon], in
/// degrees with north and east positive.
///
/// Only the year, month and day of [date] count, read as the calendar date
/// at the position: the result is the day around that date's solar noon
/// there, whatever the time zone of [date].
SunTimes sunTimesOn(DateTime date, {required double lat, required double lon}) {
  final midnight = DateTime.utc(date.year, date.month, date.day);
  final julianMidnight =
      midnight.millisecondsSinceEpoch / Duration.millisecondsPerDay + _julianDayOfUnixEpoch;
  // The declination at the local solar noon decides polar day and night for
  // the whole day: it moves by 0.4 degree a day at most, so only the day of
  // the transition itself can come out on the other side.
  final noon = _sunAt(julianMidnight + 0.5 - lon / 360);
  final cosNoonHourAngle = _cosHorizonHourAngle(lat, noon.declination);
  if (cosNoonHourAngle > 1) return const PolarNight();
  if (cosNoonHourAngle < -1) return const PolarDay();
  Duration since(double minutes) =>
      Duration(microseconds: (minutes * Duration.microsecondsPerMinute).round());
  return SunriseSunset(
    midnight.add(since(_crossingMinutes(julianMidnight, lat, lon, rising: true))),
    midnight.add(since(_crossingMinutes(julianMidnight, lat, lon, rising: false))),
  );
}

/// Whether the sun is up at [instant] at latitude [lat] and longitude [lon]:
/// from sunrise included to sunset excluded, always during a polar day and
/// never during a polar night.
bool isDaylightAt(DateTime instant, {required double lat, required double lon}) {
  final utc = instant.toUtc();
  // The calendar date at the position follows the sun rather than Greenwich:
  // at 22:00 UTC it is already the next morning in New Zealand. Mean solar
  // time, lon / 15 hours ahead of UTC, names the day whose sunrise and
  // sunset surround the instant.
  final solar = utc.add(Duration(microseconds: (lon / 15 * Duration.microsecondsPerHour).round()));
  return switch (sunTimesOn(solar, lat: lat, lon: lon)) {
    SunriseSunset(:final sunrise, :final sunset) => !utc.isBefore(sunrise) && utc.isBefore(sunset),
    PolarDay() => true,
    PolarNight() => false,
  };
}

/// The device's UTC offset without summer time, in the year [now] reads.
///
/// Summer time adds to the offset, so the smaller of the offsets on 1 January
/// and 1 July is the standard one in both hemispheres.
/// [offsetAt] gives the zone's offset at a local date; it defaults to the
/// device's zone and lets a test stand in a zone with summer time.
Duration standardUtcOffset(DateTime Function() now, {Duration Function(DateTime local)? offsetAt}) {
  final zoneOffset = offsetAt ?? (DateTime local) => local.timeZoneOffset;
  final year = now().year;
  // Noon stays clear of the switches some zones make at midnight.
  final january = zoneOffset(DateTime(year, 1, 1, 12));
  final july = zoneOffset(DateTime(year, 7, 1, 12));
  return january < july ? january : july;
}

/// A position that stands for a time zone when the user's own is unknown.
///
/// UTC+1 maps to the middle of France, the app's region, and UTC+0 to London.
/// Any other offset maps to latitude 45 and the longitude whose mean solar
/// time matches the offset, 15 degrees per hour. That longitude is not
/// wrapped to the range from -180 to 180, so UTC+14 gives 210 and keeps the
/// zone's calendar date; the solar formulas accept it.
({double lat, double lon}) representativePoint(Duration standardOffset) {
  if (standardOffset == const Duration(hours: 1)) return (lat: 46.6, lon: 2.5);
  if (standardOffset == Duration.zero) return (lat: 51.5, lon: -0.1);
  return (lat: 45, lon: standardOffset.inMinutes / 4);
}

/// Whether the sun is down at [instant]: at [lat] and [lon] when both are
/// known, else at the [representativePoint] of [standardOffset].
bool isNightAt(DateTime instant, {required Duration standardOffset, double? lat, double? lon}) {
  if (lat != null && lon != null) return !isDaylightAt(instant, lat: lat, lon: lon);
  final point = representativePoint(standardOffset);
  return !isDaylightAt(instant, lat: point.lat, lon: point.lon);
}

const double _julianDayOfUnixEpoch = 2440587.5;

/// Minutes from 0:00 UTC of the date to the sunrise ([rising]) or the
/// sunset around the solar noon at [lon].
double _crossingMinutes(double julianMidnight, double lat, double lon, {required bool rising}) {
  // The NOAA calculator evaluates the sun once, then again at the first
  // estimate of the crossing. Starting from solar noon and taking three
  // passes evaluates the declination at the crossing itself, which matters
  // at high latitude near the equinoxes, where it moves fastest.
  var minutes = 720 - 4 * lon;
  for (var pass = 0; pass < 3; pass++) {
    final sun = _sunAt(julianMidnight + minutes / Duration.minutesPerDay);
    final cosHourAngle = math.max<double>(
      -1,
      math.min<double>(1, _cosHorizonHourAngle(lat, sun.declination)),
    );
    final hourAngle = _deg(math.acos(cosHourAngle));
    minutes = 720 - 4 * (lon + (rising ? hourAngle : -hourAngle)) - sun.equationOfTime;
  }
  return minutes;
}

/// Cosine of the hour angle at which the sun's centre reaches the horizon
/// zenith; above 1 the sun never rises, below -1 it never sets.
double _cosHorizonHourAngle(double lat, double declination) {
  final phi = _rad(lat);
  final delta = _rad(declination);
  return math.cos(_rad(_horizonZenith)) / (math.cos(phi) * math.cos(delta)) -
      math.tan(phi) * math.tan(delta);
}

/// The sun's declination in degrees and the equation of time in minutes at
/// a Julian day, with the series of the NOAA "General Solar Position
/// Calculations" spreadsheet.
({double declination, double equationOfTime}) _sunAt(double julianDay) {
  final t = (julianDay - 2451545) / 36525;
  final meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;
  final meanAnomaly = _rad(357.52911 + t * (35999.05029 - 0.0001537 * t));
  final eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  final centre =
      math.sin(meanAnomaly) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * meanAnomaly) * (0.019993 - 0.000101 * t) +
      math.sin(3 * meanAnomaly) * 0.000289;
  final omega = _rad(125.04 - 1934.136 * t);
  final apparentLongitude = _rad(meanLongitude + centre - 0.00569 - 0.00478 * math.sin(omega));
  final meanObliquity =
      23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  final obliquity = _rad(meanObliquity + 0.00256 * math.cos(omega));
  final declination = _deg(math.asin(math.sin(obliquity) * math.sin(apparentLongitude)));
  final tanHalf = math.tan(obliquity / 2);
  final y = tanHalf * tanHalf;
  final l0 = _rad(meanLongitude);
  final e = eccentricity;
  final m = meanAnomaly;
  final equationOfTime =
      4 *
      _deg(
        y * math.sin(2 * l0) -
            2 * e * math.sin(m) +
            4 * e * y * math.sin(m) * math.cos(2 * l0) -
            0.5 * y * y * math.sin(4 * l0) -
            1.25 * e * e * math.sin(2 * m),
      );
  return (declination: declination, equationOfTime: equationOfTime);
}

double _rad(double deg) => deg * math.pi / 180;

double _deg(double rad) => rad * 180 / math.pi;
