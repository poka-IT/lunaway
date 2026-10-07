import 'package:lunaway/core/web/tile_errors_stub.dart'
    if (dart.library.js_interop) 'package:lunaway/core/web/tile_errors_web.dart'
    as impl;

/// The tiles of the places that MapLibre GL JS failed to load in this page
/// (`web/lunaway_maplibre.js` counts them). Elsewhere none are counted.
abstract final class PlaceTileErrors {
  /// How many failed since the page loaded.
  static int count() => impl.placeTileErrors();
}
