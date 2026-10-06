import 'package:lunaway/shared/theme/palette.dart';

/// How Lunaway's own layers look on the basemap: clusters, pins and the
/// selection. Both map engines read these values, so they draw one map.
abstract final class MapLook {
  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Clusters: a navy disc with a cream count by day, the reverse at night,
  /// so they read as part of the brand and never as a place.
  static String clusterFill({required bool dark}) =>
      _hex((dark ? Palette.creme : Palette.minuit).toARGB32());
  static String clusterText({required bool dark}) =>
      _hex((dark ? Palette.minuit : Palette.creme).toARGB32());
  static String clusterStroke({required bool dark}) =>
      _hex((dark ? Palette.minuit : Palette.creme).toARGB32());
  static const double clusterStrokeWidth = 2.5;
  static const double clusterOpacity = 0.94;

  /// A cluster's size says how many places it holds: 5 and 500 never look
  /// alike. The largest stays under half the clustering radius, so two
  /// neighbours on the country view keep a gap of basemap between them.
  static const List<Object> clusterRadius = [
    'interpolate',
    ['linear'],
    ['get', 'point_count'],
    2,
    12,
    10,
    14,
    50,
    16,
    200,
    19,
    1000,
    22,
  ];
  static const List<Object> clusterTextSize = [
    'interpolate',
    ['linear'],
    ['get', 'point_count'],
    2,
    12,
    200,
    13.5,
    1000,
    15,
  ];

  /// The count of a cluster in the reader's language: up to 999 as it is,
  /// then thousands with one decimal and the locale's separator ("1,1 k" in
  /// French, "1.1k" in English) and whole thousands from 9,950. MapLibre's
  /// own abbreviation (`point_count_abbreviated`) writes "1.1k" in every
  /// language. Plain style-spec arithmetic, so both engines (MapLibre
  /// Native, GL JS) read it the same, with no locale support needed from
  /// them.
  static List<Object> clusterLabel(String language) {
    final french = language == 'fr';
    final separator = french ? ',' : '.';
    final unit = french ? ' k' : 'k';
    const count = ['get', 'point_count'];
    const hundreds = [
      'round',
      ['/', count, 100],
    ];
    const tenths = [
      '-',
      hundreds,
      [
        '*',
        [
          'floor',
          ['/', hundreds, 10],
        ],
        10,
      ],
    ];
    return [
      'case',
      ['<', count, 1000],
      ['concat', count],
      // Whole thousands: from 9,950, or when the tenths round to zero.
      [
        'any',
        ['>=', count, 9950],
        ['==', tenths, 0],
      ],
      [
        'concat',
        [
          'round',
          ['/', count, 1000],
        ],
        unit,
      ],
      [
        'concat',
        [
          'floor',
          ['/', hundreds, 10],
        ],
        separator,
        tenths,
        unit,
      ],
    ];
  }

  /// The font stack of the counts, which must exist on the basemap's glyph
  /// server: the Protomaps fonts stop at Medium.
  static const clusterFont = ['Noto Sans Medium'];

  /// Slightly smaller pins when zoomed out, full size from zoom 12. [scale]
  /// converts the pin images to the engine's unit: 1 / ratio where an image
  /// pixel is a logical pixel (the web), device pixel ratio / ratio on
  /// Android and iOS, which read image pixels as physical ones.
  static List<Object> pinSize(double scale) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    6,
    0.72 * scale,
    12,
    scale,
  ];
}
