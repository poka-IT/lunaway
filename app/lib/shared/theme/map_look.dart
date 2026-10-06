/// How Lunaway's own layers look on the basemap: clusters, pins and the
/// selection. Both map engines read these values, so they draw one map.
abstract final class MapLook {
  /// Pins are drawn at this many pixels per logical pixel and scaled back by
  /// the layers, which keeps them sharp on any screen.
  static const double pinPixelRatio = 3;

  /// The night blue of the brand, readable on the light and the dark basemap.
  static const clusterFill = '#24427A';
  static const clusterStroke = '#FFFFFF';
  static const double clusterStrokeWidth = 3;
  static const double clusterOpacity = 0.94;
  static const clusterText = '#FFFFFF';
  static const double clusterTextSize = 14;

  /// Fonts the basemap's glyph server provides.
  static const List<String> clusterFont = ['Noto Sans Bold'];

  /// Bigger discs for bigger clusters.
  static const List<Object> clusterRadius = [
    'step',
    ['get', 'point_count'],
    17,
    25,
    21,
    150,
    26,
  ];

  /// Slightly smaller pins when zoomed out, full size from zoom 13. [scale]
  /// converts the pin images to the engine's unit: 1 where an image pixel is
  /// a logical pixel (iOS, the web), the device pixel ratio on Android, which
  /// reads image pixels as physical ones.
  static List<Object> pinSize([double scale = 1]) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    8,
    0.8 * scale / pinPixelRatio,
    13,
    scale / pinPixelRatio,
  ];

  /// Lantern amber, the accent kept for what the user picked.
  static const selection = '#F2A33A';
  static double selectedPinSize([double scale = 1]) => 1.35 * scale / pinPixelRatio;
  static const double selectionHaloRadius = 24;
  static const double selectionHaloOpacity = 0.28;
  static const double selectionStrokeWidth = 3;
}
