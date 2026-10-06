/// The wall clock of a place, from its country: opening hours read "closes
/// at 19:00" in the place's time, whatever the device's zone (a traveller
/// from Portugal planning a night in France reads French hours).
///
/// The app covers Europe, where every country follows one of three standard
/// offsets and, but for Iceland, the European Union's summer time: from the
/// last Sunday of March at 01:00 UTC to the last Sunday of October at 01:00
/// UTC. A table of a few countries replaces a time zone database of several
/// hundred kilobytes.
library;

/// A European time zone: its standard offset, and whether it keeps summer
/// time.
final class PlaceZone {
  const new(this.standardOffset, {this.summerTime = true});

  /// Central European Time, the zone of metropolitan France.
  static const central = PlaceZone(Duration(hours: 1));
  static const western = PlaceZone(Duration.zero);
  static const eastern = PlaceZone(Duration(hours: 2));
  static const iceland = PlaceZone(Duration.zero, summerTime: false);

  final Duration standardOffset;
  final bool summerTime;

  /// The zone of a country by its ISO 3166-1 alpha-2 code; France's when the
  /// code is missing or not European.
  static PlaceZone ofCountry(String? countryCode) => switch (countryCode?.toUpperCase()) {
    'PT' || 'GB' || 'IE' || 'FO' => western,
    'IS' => iceland,
    'FI' || 'EE' || 'LV' || 'LT' || 'RO' || 'BG' || 'GR' || 'CY' || 'UA' || 'MD' => eastern,
    _ => central,
  };

  /// The offset from UTC at [instant].
  Duration offsetAt(DateTime instant) {
    if (!summerTime) return standardOffset;
    final utc = instant.toUtc();
    final start = _lastSundayAtOneUtc(utc.year, 3);
    final end = _lastSundayAtOneUtc(utc.year, 10);
    final summer = !utc.isBefore(start) && utc.isBefore(end);
    return summer ? standardOffset + const Duration(hours: 1) : standardOffset;
  }

  /// The wall clock time of the place at [instant], as a UTC [DateTime]
  /// whose fields read like the place's clock: format it, never convert it.
  DateTime wallClock(DateTime instant) => instant.toUtc().add(offsetAt(instant));

  static DateTime _lastSundayAtOneUtc(int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0);
    final back = lastDay.weekday % 7;
    return DateTime.utc(year, month, lastDay.day - back, 1);
  }
}
