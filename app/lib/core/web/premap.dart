import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/web/premap_stub.dart'
    if (dart.library.js_interop) 'package:lunaway/core/web/premap_web.dart'
    as impl;

/// The web page's first map (`web/premap.js`), drawn while the app starts.
/// Elsewhere there is none, and these do nothing.
abstract final class Premap {
  /// The camera the first map shows now (the user may have moved it), null
  /// once it has gone or where there is none. With [x] and [y] (a point of
  /// the window, in logical pixels), the place the first map draws there
  /// as the centre: a map whose centre stands at that point of the window
  /// draws the same view.
  static ({LatLng center, double zoom})? camera({double? x, double? y}) =>
      impl.premapCamera(x: x, y: y);

  /// The app's map shows the same view: the first map fades out.
  static void handOver() => impl.premapHandOver();

  /// The place of the tiles the user clicked on the first map, which only
  /// the app can open: its tile properties and its `[lon, lat]`; null when
  /// none, and once taken.
  static ({Map<Object?, Object?> properties, List<Object?> coordinates})? takePlace() =>
      impl.premapTakePlace();

  /// Keeps [json] (premapState) for the first map of the next visit.
  static void remember(String json) => impl.premapRemember(json);

  /// Keeps [json] (premapFrame): where the app's map stands in the window.
  static void rememberFrame(String json) => impl.premapRememberFrame(json);
}
