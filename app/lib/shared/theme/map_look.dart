import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';

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

  /// The dot of a place from the tiles: its family's tone, as a pin's head.
  static String familyColor(KindFamily family) => _hex(LunaTokens.familyFill(family).toARGB32());

  /// A dot of a place from the tiles. Below zoom 7 the country's density is
  /// drawn as a glow ([glowColor]) and the dots are fine grains on it, under
  /// the basemap's names, so that the towns stay readable; from zoom 7 they
  /// grow into the dots a pointer picks, and at street zoom a dot under a pin
  /// that found no room still reads as a place.
  static const List<Object> dotRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    0.7,
    5,
    1,
    7,
    2.2,
    9,
    3.8,
    12,
    5,
  ];

  /// [dotRadius] on a phone or a tablet's app, where a finger picks: from
  /// zoom 7, where the dots are the map, a third wider, so the finger sees
  /// what it aims at (it picks a dot within 22 px of its edge,
  /// `touchMapHitShapes`); from the street up, the same dots as with a
  /// mouse. Below zoom 7 the glow tells where the places are, and the same
  /// fine grains as with a mouse: a phone shows the country in half the
  /// width of a desktop window, and the wider dots of
  /// `plan/research/66-finitions-carte.md` made one carpet there (38 % of
  /// the map at zoom 5.5 on the emulator).
  static const List<Object> touchDotRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    0.7,
    5,
    1,
    7,
    3,
    9,
    4.4,
    12,
    5,
  ];
  static const List<Object> dotStrokeWidth = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    0.3,
    8,
    0.9,
    12,
    1.4,
  ];

  /// The rim of a dot, the basemap's own tone so it detaches from the land.
  static String dotStroke({required bool dark}) =>
      _hex((dark ? Palette.minuit : Palette.creme).toARGB32());

  /// Grains half seen on the glow of the country's view, plain dots from
  /// zoom 7.
  static const List<Object> dotOpacity = [
    'interpolate',
    ['linear'],
    ['zoom'],
    4,
    0.45,
    7,
    0.95,
  ];

  /// No rim on the grains of the country's view: a rim of the basemap's
  /// tone around a dot of one pixel would grey the glow.
  static const List<Object> dotStrokeOpacity = [
    'interpolate',
    ['linear'],
    ['zoom'],
    5,
    0,
    7,
    1,
  ];

  /// The country's view, below zoom 7: where the places are, as a glow, a
  /// wide blurred disc under each dot whose faint colours add up where the
  /// places crowd, which a reader takes in at a glance where thousands of
  /// dots made one carpet. A server cluster with a count cannot follow the
  /// filters (`docs/deploy.md`, "Filters on the dots"); a glow of the dots
  /// the filter keeps does. A circle layer rather than a heatmap: the
  /// Android and iOS plugins add a heatmap without its source layer, which
  /// draws nothing from vector tiles. It fades out from zoom 6 to
  /// [glowMaxZoom] while the dots grow.
  static const double glowMaxZoom = 8;
  static const List<Object> glowRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    4,
    5,
    7,
    7,
    12,
  ];

  /// The disc's edge melts into the map.
  static const double glowBlur = 1;

  /// On Minuit a light blue, as lights seen at night; on Aube the blue of
  /// the motorhome areas.
  static String glowColor({required bool dark}) =>
      dark ? '#8cb9f5' : _hex(Palette.familyStopovers.toARGB32());

  /// Faint: a hundred discs overlap in a busy region, and a stronger tint
  /// turned the whole of France blue.
  static List<Object> glowOpacity({required bool dark}) {
    final (low, high) = dark ? (0.02, 0.03) : (0.012, 0.02);
    return [
      'interpolate',
      ['linear'],
      ['zoom'],
      3,
      low,
      6,
      high,
      glowMaxZoom,
      0,
    ];
  }

  /// The mouse over a place, on the maps that have one (the browser, the
  /// desktop): a ring of the selection's amber around the place's own
  /// point, [hoverRingGap] clear of the dot or disc it circles, and its pin
  /// grown by [hoverGrow]. The same look whatever part of the place the
  /// mouse is on (`lunawayHits.hover` in `web/lunaway_maplibre.js`).
  static const double hoverRingWidth = 2.5;
  static const double hoverRingGap = 2.5;
  static const double hoverGrow = 1.12;

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
