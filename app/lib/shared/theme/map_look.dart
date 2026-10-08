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
  /// drawn as a glow ([heatColor]) and the dots are fine grains on it, under
  /// the basemap's names, so that the towns stay readable; from zoom 7 they
  /// grow into the dots a pointer picks, and at street zoom a dot under a pin
  /// that found no room still reads as a place.
  static const List<Object> dotRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    0.8,
    5,
    1.1,
    7,
    2.2,
    9,
    3.8,
    12,
    5,
  ];

  /// [dotRadius] on a phone or a tablet's app, where a finger picks: a third
  /// wider from zoom 5 to 7, so the finger sees what it aims at (it picks a
  /// dot within 22 px of its edge, `touchMapHitShapes`); from the street up,
  /// the same dots as with a mouse. Below zoom 7 the glow tells where the
  /// places are, and larger dots made a carpet that hid the towns: 38 % of
  /// the map at zoom 5.5 on the emulator (`plan/research/66-finitions-carte.md`).
  static const List<Object> touchDotRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    1,
    5,
    1.4,
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
    0.55,
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

  /// The country's view, below zoom 7: where the places are, as a glow of
  /// the dots' density, which a reader takes in at a glance where thousands
  /// of dots made one carpet. A server cluster with a count cannot follow
  /// the filters (`docs/deploy.md`, "Filters on the dots"); a glow of the
  /// dots the filter keeps does. It fades out from zoom 6 to [heatMaxZoom]
  /// while the dots grow.
  static const double heatMaxZoom = 8;
  static const List<Object> heatRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    4,
    5,
    8,
    7,
    14,
  ];

  /// Low: the country holds about two hundred thousand places, and a higher
  /// intensity lit the whole of France in one colour.
  static const List<Object> heatIntensity = [
    'interpolate',
    ['linear'],
    ['zoom'],
    3,
    0.03,
    5,
    0.05,
    7,
    0.12,
  ];
  static const List<Object> heatOpacity = [
    'interpolate',
    ['linear'],
    ['zoom'],
    6,
    1,
    heatMaxZoom,
    0,
  ];

  /// The glow's colour by density: on Minuit, a light blue up to near
  /// white, as lights seen at night (the palette's greys read as a fog, the
  /// lantern's amber as a selection); on Aube, the blue of the motorhome
  /// areas up to Minuit. Transparent where there is nothing.
  static List<Object> heatColor({required bool dark}) {
    final ramp = dark
        ? const [
            (0xFF6EA0E6, 0.0),
            (0xFF6EA0E6, 0.22),
            (0xFF8CB9F5, 0.45),
            (0xFFB9D7FF, 0.62),
            (0xFFEBF4FF, 0.78),
          ]
        : [
            (Palette.familyStopovers.toARGB32(), 0.0),
            (Palette.familyStopovers.toARGB32(), 0.14),
            (Palette.familyStopovers.toARGB32(), 0.3),
            (Palette.minuit600.toARGB32(), 0.42),
            (Palette.minuit.toARGB32(), 0.55),
          ];
    const densities = [0, 0.15, 0.4, 0.7, 1];
    return [
      'interpolate',
      ['linear'],
      ['heatmap-density'],
      for (var i = 0; i < ramp.length; i++) ...[densities[i], _rgba(ramp[i].$1, ramp[i].$2)],
    ];
  }

  static String _rgba(int argb, double alpha) =>
      'rgba(${(argb >> 16) & 0xFF},${(argb >> 8) & 0xFF},${argb & 0xFF},$alpha)';

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
