import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/shared/theme/palette.dart';

/// The engine's feature id of the mark at [index] of a map's marks. Ids
/// start far above those MapLibre gives its groups, which share the
/// source: a lit mark never lights a group.
int routeMarkFeatureId(int index) => _featureBase + index;

/// The index among a map's marks of the feature [id]; null for a group.
int? routeMarkIndex(Object? id) {
  final n = id is num ? id.toInt() : int.tryParse('$id');
  return n == null || n < _featureBase ? null : n - _featureBase;
}

const _featureBase = 1000000000;

/// The source of [mark]: the ends and stops never grouped, the minor marks
/// apart from the others.
String routeMarkSource(RouteMapMark mark) => mark.kind.anchor
    ? RouteLayers.anchorsSource
    : mark.minor
    ? RouteLayers.minorSource
    : RouteLayers.marksSource;

/// The marks as the GeoJSON sources of [RouteLayers.markSources].
Map<String, Map<String, Object?>> routeMarkSources(List<RouteMapMark> marks) {
  final features = {for (final s in RouteLayers.markSources) s: <Object?>[]};
  for (final (i, m) in marks.indexed) {
    features[routeMarkSource(m)]!.add({
      'type': 'Feature',
      'id': routeMarkFeatureId(i),
      'properties': {
        'mark': m.id,
        'kind': m.kind.name,
        'badge': m.badge.id,
        'rank': m.kind.tone.rank,
        'size': m.minor ? RouteMarkStyle.minorSize : 1,
        'ink': RouteLook.hex(m.badge.ink),
        'label': ?m.label,
        'side': ?m.side,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [m.position.lon, m.position.lat],
      },
    });
  }
  return {
    for (final e in features.entries) e.key: {'type': 'FeatureCollection', 'features': e.value},
  };
}

/// The look of the marks, as MapLibre style expressions both engines share.
abstract final class RouteMarkStyle {
  /// A minor mark beside a major one.
  static const double minorSize = routeMinorScale;

  /// Minor marks show from this zoom: a town's streets, where a place near
  /// the route is worth seeing.
  static const minorMinZoom = 10.0;

  /// Marks closer than this, in pixels, gather into one badge with their
  /// count; above [clusterMaxZoom] they never do.
  static const clusterRadius = 26.0;
  static const clusterMaxZoom = 13.0;

  /// The zoom a row's marks are shown at. Groups are made at whole zooms up
  /// to [clusterMaxZoom] and drawn until the next one: at 13.5 a mark could
  /// still hide in its group (seen on Android).
  static const double focusZoom = clusterMaxZoom + 1.5;
  static const font = ['Noto Sans Medium'];

  /// The badges keep their place on the map: a town's name that a badge
  /// or a group covers is left out, rather than written through it (seen
  /// on Android, a group over Châteauneuf-du-Rhône). They are drawn
  /// whatever lies under them.
  static const ignorePlacement = false;

  static const List<Object> _group = ['has', 'point_count'];
  static const List<Object> notGroup = ['!', _group];

  /// The badge of a mark, or that of a group in the tone of its most
  /// pressing mark ([RouteBadge.cluster]).
  static const List<Object> iconImage = [
    'case',
    _group,
    [
      'concat',
      'lw-rb-cluster-',
      [
        'to-string',
        ['get', 'top'],
      ],
    ],
    ['get', 'badge'],
  ];

  /// [scale] brings an image pixel to the engine's unit.
  static List<Object> iconSize(double scale) => [
    '*',
    scale,
    [
      'case',
      _group,
      1,
      ['get', 'size'],
    ],
  ];

  /// A group's count, a stop's number, a limit's figure.
  static const List<Object> textField = [
    'case',
    _group,
    ['get', 'point_count_abbreviated'],
    [
      'coalesce',
      ['get', 'label'],
      '',
    ],
  ];
  static final List<Object> textColor = [
    'case',
    _group,
    RouteLook.hex(Palette.creme),
    [
      'coalesce',
      ['get', 'ink'],
      RouteLook.hex(Palette.minuit),
    ],
  ];
  static const List<Object> textSize = [
    'case',
    _group,
    12,
    [
      '*',
      11,
      ['get', 'size'],
    ],
  ];

  /// A higher rank draws above: a closure over a place.
  static const List<Object> sortKey = [
    'coalesce',
    ['get', 'rank'],
    ['get', 'top'],
    0,
  ];

  /// The lit ring, on through the feature state `lit`. Under the mouse
  /// (`hover`, which the page's hover sets in the browser and on the
  /// desktop) the hover's own ring stands for it: a mark never wears two.
  static const List<Object> haloOpacity = [
    'case',
    [
      'boolean',
      ['feature-state', 'hover'],
      false,
    ],
    0,
    [
      'boolean',
      ['feature-state', 'lit'],
      false,
    ],
    1,
    0,
  ];
  static const List<Object> haloRadius = [
    '*',
    19,
    ['get', 'size'],
  ];

  /// What a group counts, for its tooltip, and its most pressing tone.
  static final Map<String, Object> clusterProperties = {
    'top': [
      'max',
      ['get', 'rank'],
    ],
    // A group's badge is drawn full size, whatever its marks: so is its
    // target (routeHitShapes reads `size`).
    'size': ['max', 1],
    for (final k in RouteMarkKind.values)
      if (!k.anchor)
        'n_${k.name}': [
          '+',
          [
            'case',
            [
              '==',
              ['get', 'kind'],
              k.name,
            ],
            1,
            0,
          ],
        ],
  };

  /// The kinds a group holds, read from its properties.
  static Map<RouteMarkKind, int> groupCounts(Map<Object?, Object?> properties) => {
    for (final k in RouteMarkKind.values)
      if (properties['n_${k.name}'] case final num n when n > 0) k: n.toInt(),
  };

  /// The marks' layers in the GL JS style syntax, bottom to top, for the
  /// desktop map page.
  static List<Map<String, Object?>> jsonLayers() => [
    for (final source in RouteLayers.markSources) ...[
      {
        'id': RouteLayers.haloOf(source),
        'type': 'circle',
        'source': source,
        'filter': notGroup,
        ..._minZoom(source),
        'paint': {
          'circle-radius': haloRadius,
          'circle-color': RouteLook.halo,
          'circle-stroke-color': RouteLook.haloRim,
          'circle-stroke-width': 2,
          'circle-opacity': haloOpacity,
          'circle-stroke-opacity': haloOpacity,
        },
      },
      {
        'id': RouteLayers.badgesOf(source),
        'type': 'symbol',
        'source': source,
        ..._minZoom(source),
        'layout': {
          'icon-image': iconImage,
          'icon-size': iconSize(1),
          'icon-allow-overlap': true,
          'icon-ignore-placement': ignorePlacement,
          'symbol-sort-key': sortKey,
          'text-field': textField,
          'text-font': font,
          'text-size': textSize,
          'text-allow-overlap': true,
          'text-ignore-placement': ignorePlacement,
        },
        'paint': {'text-color': textColor},
      },
      {
        'id': RouteLayers.sideOf(source),
        'type': 'symbol',
        'source': source,
        'filter': sideFilter,
        ..._minZoom(source),
        'layout': {
          'text-field': ['get', 'side'],
          'text-font': font,
          'text-size': 11,
          'text-anchor': 'left',
          'text-offset': sideOffset,
          'text-optional': true,
        },
        'paint': {
          'text-color': RouteLook.hex(Palette.minuit),
          'text-halo-color': RouteLook.hex(Palette.creme),
          'text-halo-width': 1.5,
        },
      },
    ],
  ];

  /// The text beside a badge: a station's price.
  static const List<Object> sideFilter = [
    'all',
    notGroup,
    ['has', 'side'],
  ];

  /// Where the text beside a badge starts, in ems of the 11 px text: past
  /// the widest badge it stands beside (a blocking sign, 17.75 px from its
  /// centre with its hairline) by the text's 1.5 px halo, so neither the
  /// halo nor the figures cover the ring.
  static const List<Object> sideOffset = [1.75, 0];

  static Map<String, Object?> _minZoom(String source) =>
      source == RouteLayers.minorSource ? {'minzoom': minorMinZoom} : const {};

  /// The options of a source of the route map: the marks and the minor
  /// marks are grouped, nothing else (a grouped line draws nothing).
  static Map<String, Object?> sourceOptions(String source) =>
      source != RouteLayers.marksSource && source != RouteLayers.minorSource
      ? const {}
      : {
          'cluster': true,
          'clusterRadius': clusterRadius,
          'clusterMaxZoom': clusterMaxZoom,
          'clusterProperties': clusterProperties,
        };
}
