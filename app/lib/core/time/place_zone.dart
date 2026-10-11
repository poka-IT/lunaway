/// The wall clock of a place, from its country and its position: opening
/// hours read "closes at 19:00" in the place's time, whatever the device's
/// zone (a traveller from Portugal planning a night in France reads French
/// hours).
///
/// The zone comes from the IANA time zone database, embedded in the app
/// (`zone_data.g.dart`, from `tool/time_zones/generate.dart`) and read by
/// the timezone package: a zone the database gives the country in its
/// table of countries and zones (zone.tab), the only one for most
/// countries, and for a country with several the one whose principal
/// location is nearest (the Canary Islands, the Azores and Madeira keep
/// their own clock). The server picks the zone the same way from the same
/// release (`lunaway_conflate::time_zone`): the opening intervals it
/// computes and the times written here agree.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/time/zone_data.g.dart';
import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

/// The zone of a place.
@immutable
final class PlaceZone {
  const new _(this._location);

  /// The zone of a place in [countryCode] (ISO 3166-1 alpha-2, any case)
  /// at [position]; France's when the code is missing or the database does
  /// not name the country (Kosovo).
  factory of(String? countryCode, LatLng position) {
    final centres = _byCountry[countryCode?.toUpperCase()];
    if (centres == null) return paris;
    var best = centres.first;
    var bestDistance = double.infinity;
    for (final centre in centres) {
      final d = _distance(centre.$3, centre.$4, position);
      if (d < bestDistance) {
        best = centre;
        bestDistance = d;
      }
    }
    return PlaceZone.named(best.$2);
  }

  /// The zone named [name] (`Europe/Paris`); France's for a name the
  /// database embedded here does not hold.
  factory named(String name) => switch (_zones[name]) {
    final location? => PlaceZone._(location),
    null => paris,
  };

  /// Metropolitan France, the zone of the French sources and the app's
  /// fallback (UTC if the embedded database lacked it, which a test rules
  /// out).
  static final PlaceZone paris = PlaceZone._(_zones['Europe/Paris'] ?? tz.UTC);

  final tz.Location _location;

  /// Its name in the database (`Africa/Casablanca`).
  String get name => _location.name;

  /// The offset from UTC at [instant].
  Duration offsetAt(DateTime instant) => _location.timeZone(instant.millisecondsSinceEpoch).offset;

  /// The wall clock time of the place at [instant], as a UTC [DateTime]
  /// whose fields read like the place's clock: format it, never convert it.
  DateTime wallClock(DateTime instant) => instant.toUtc().add(offsetAt(instant));

  /// The instant at which the place's clock reads the fields of [wall] (a
  /// [wallClock] value): the inverse of [wallClock] outside the hour the
  /// clocks change.
  DateTime instantOf(DateTime wall) {
    final fields = DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute);
    return DateTime.fromMillisecondsSinceEpoch(
      _location.translateToUtc(fields.millisecondsSinceEpoch),
      isUtc: true,
    );
  }

  @override
  bool operator ==(Object other) => other is PlaceZone && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PlaceZone($name)';

  /// The rows of zone.tab by country.
  static final Map<String, List<(String, String, double, double)>> _byCountry = () {
    final out = <String, List<(String, String, double, double)>>{};
    for (final centre in zoneCentres) {
      (out[centre.$1] ??= []).add(centre);
    }
    return out;
  }();

  /// The zones of the embedded database by name, read once on first use.
  /// A copy: the package keeps its database in a global another reader
  /// could fill again.
  static final Map<String, tz.Location> _zones = () {
    tz.initializeDatabase(base64.decode(zoneRules));
    return Map<String, tz.Location>.unmodifiable(tz.timeZoneDatabase.locations);
  }();

  /// A distance to [p] that orders like the true one at these scales:
  /// degrees, the longitude shrunk by the cosine of the mean latitude. The
  /// server computes the same.
  static double _distance(double lat, double lon, LatLng p) {
    final dlat = lat - p.lat;
    final dlon = (lon - p.lon + 540) % 360 - 180;
    final shrink = math.cos((lat + p.lat) / 2 * math.pi / 180);
    return dlat * dlat + (dlon * shrink) * (dlon * shrink);
  }
}
