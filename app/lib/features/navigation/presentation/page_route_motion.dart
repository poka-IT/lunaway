import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:lunaway/core/geo/geo.dart';

/// The guidance's vehicle and camera run by the browser's page
/// (`lunawayRouteMotion` in `web/lunaway_maplibre.js`): the app sends one
/// call per fix and per change of view, the page draws every frame in
/// between and says when the user takes the map.
abstract interface class PageRouteMotion {
  /// A new fix of the vehicle drawn by [source]; [jump] draws it there at
  /// once.
  void vehicle(String source, LatLng position, double? course, {required bool jump});

  /// No vehicle any more: no frame draws it back.
  void clear();

  /// Behind the vehicle at [zoom], its centre inside [padding]. [enter]
  /// starts following, from the view the map has, over [ease]; without it,
  /// a map the user took stays free (the page stopped following at the
  /// gesture, before the app heard of it).
  void follow({
    required double zoom,
    required EdgeInsets padding,
    required Duration ease,
    required bool enter,
  });

  /// Where the user left it.
  void free();

  /// Flat and north up, ready for the whole route to be fitted.
  void overview();

  /// Whether the page reports gestures, presses and rests.
  void guiding({required bool on});
}

/// Off the web there is no page: the app draws the frames itself.
PageRouteMotion? bindPageRouteMotion(
  String tag,
  void Function(Map<Object?, Object?> event) onEvent,
) => null;
