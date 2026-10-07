import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/web/premap_stub.dart'
    if (dart.library.js_interop) 'package:lunaway/core/web/premap_web.dart'
    as impl;

/// The web page's first map (`web/premap.js`), drawn while the app starts.
/// Elsewhere there is none, and these do nothing.
abstract final class Premap {
  /// The camera the first map shows now (the user may have moved it), null
  /// once it has gone or where there is none.
  static ({LatLng center, double zoom})? camera() => impl.premapCamera();

  /// The app's map shows the same view: the first map fades out.
  static void handOver() => impl.premapHandOver();

  /// Keeps [json] (premapState) for the first map of the next visit.
  static void remember(String json) => impl.premapRemember(json);
}
