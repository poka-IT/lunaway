import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';

/// The navigation apps the directions offer, with the link that starts a
/// route (not just a pin) to a point in each. Built by the app from a
/// position, never from data: these links bypass the web-only rule of
/// `ExternalActions.openUrl` because nothing in them comes from outside.
///
/// The in-app navigation, planned for a later iteration, will be one more
/// target beside these, offered first.
enum NavigationApp {
  googleMaps('google_maps'),
  waze('waze'),
  osmAnd('osmand'),
  organicMaps('organic_maps'),
  magicEarth('magic_earth'),
  appleMaps('apple_maps'),

  /// The browser's OpenStreetMap routing, where no app can be told apart
  /// (the web app, Windows).
  openStreetMap('openstreetmap');

  new(this.id);

  /// Stored when the user remembers a choice.
  final String id;

  static NavigationApp? fromId(String? id) => values.where((a) => a.id == id).firstOrNull;

  /// The apps worth offering on [platform]; [web] for the web app.
  static List<NavigationApp> offeredOn(TargetPlatform platform, {required bool web}) {
    if (web) return const [googleMaps, waze, openStreetMap];
    return switch (platform) {
      TargetPlatform.android => const [googleMaps, waze, osmAnd, organicMaps, magicEarth],
      TargetPlatform.iOS => const [appleMaps, googleMaps, waze, osmAnd, organicMaps, magicEarth],
      TargetPlatform.macOS => const [appleMaps, googleMaps, openStreetMap],
      _ => const [googleMaps, openStreetMap],
    };
  }

  /// The link that tells whether the app is installed, by its own scheme;
  /// null when a web link reaches it anyway (it opens the app when
  /// installed, the site otherwise).
  Uri? installCheck({required TargetPlatform platform, required bool web}) {
    if (web) return null;
    final mobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return switch (this) {
      googleMaps when platform == TargetPlatform.android => Uri.parse('google.navigation:q=0,0'),
      googleMaps when mobile => Uri.parse('comgooglemaps://'),
      waze when mobile => Uri.parse('waze://'),
      osmAnd when platform == TargetPlatform.android => Uri.parse('osmand.api://navigate'),
      osmAnd when mobile => Uri.parse('osmand.navigation:'),
      organicMaps when mobile => Uri.parse('om://'),
      magicEarth when mobile => Uri.parse('magicearth://'),
      _ => null,
    };
  }

  /// The link that starts a car route to [to], from [from] when an app
  /// needs a start (Organic Maps). Sources: the apps' own documentation
  /// (Google Maps intents and URLs, Waze deep links, the OsmAnd API, the
  /// Organic Maps API, Apple's unified map URLs); Magic Earth publishes none,
  /// its scheme is the one its app answers.
  Uri routeTo(
    LatLng to, {
    required TargetPlatform platform,
    required bool web,
    LatLng? from,
    String? label,
  }) {
    String f(double v) => v.toStringAsFixed(6);
    final lat = f(to.lat);
    final lon = f(to.lon);
    final android = !web && platform == TargetPlatform.android;
    final ios = !web && platform == TargetPlatform.iOS;
    return switch (this) {
      // Turn by turn at once on Android; the app's scheme on iOS; the
      // universal Maps URL, asking for navigation, elsewhere.
      googleMaps when android => Uri.parse('google.navigation:q=$lat,$lon&mode=d'),
      googleMaps when ios => Uri.parse('comgooglemaps://?daddr=$lat,$lon&directionsmode=driving'),
      googleMaps => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '$lat,$lon',
        'travelmode': 'driving',
        'dir_action': 'navigate',
      }),
      // Waze documents its universal link only; it opens the app when
      // installed.
      waze => Uri.https('waze.com', '/ul', {'ll': '$lat,$lon', 'navigate': 'yes'}),
      osmAnd when android => Uri.parse(
        'osmand.api://navigate?dest_lat=$lat&dest_lon=$lon&profile=car&force=true',
      ),
      osmAnd => Uri.parse('osmand.navigation:q=$lat,$lon'),
      organicMaps when from != null => Uri(
        scheme: 'om',
        host: 'route',
        queryParameters: {
          'sll': '${f(from.lat)},${f(from.lon)}',
          'saddr': '',
          'dll': '$lat,$lon',
          'daddr': label ?? '$lat,$lon',
          'type': 'vehicle',
        },
      ),
      // Without a start Organic Maps refuses a route: it shows the point,
      // and the route is one tap away there.
      organicMaps => Uri(
        scheme: 'om',
        host: 'map',
        queryParameters: {'v': '1', 'll': '$lat,$lon', 'n': label ?? '$lat,$lon'},
      ),
      magicEarth => Uri.parse('magicearth://?drive_to&lat=$lat&lon=$lon'),
      appleMaps => Uri.https('maps.apple.com', '/directions', {
        'destination': '$lat,$lon',
        'mode': 'driving',
      }),
      openStreetMap => Uri.https('www.openstreetmap.org', '/directions', {
        'engine': 'fossgis_osrm_car',
        'route': ';$lat,$lon',
      }),
    };
  }
}
