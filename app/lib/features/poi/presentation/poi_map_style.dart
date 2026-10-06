import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';

/// The ids, filters and looks of the points layers, the same for maplibre_gl
/// and the desktop page. The tiles (`/poi/{version}/{z}/{x}/{y}.mvt`) hold
/// two layers: `poi_clusters` (a point per category and grid cell, with
/// `count`) up to zoom 12, and `pois` (every point) from zoom 13.
abstract final class PoiMapStyle {
  static const source = 'lw-pois';
  static const pointsLayer = 'pois';
  static const clustersLayer = 'poi_clusters';

  /// Where the category's points gather, below the zoom of the points.
  static const dotsLayerId = 'lw-poi-dots';

  /// The points of the chosen category.
  static const pinsLayerId = 'lw-poi-pins';

  /// Every point, small and grey, at street zoom when no chip is on.
  static const quietLayerId = 'lw-poi-quiet';

  /// The point whose page is open.
  static const selectionSource = 'lw-poi-selection';
  static const selectionLayerId = 'lw-poi-selection';

  /// The price of the chosen fuel under each station, while the fuel chip
  /// is on.
  static const fuelSource = 'lw-fuel-prices';
  static const fuelLayerId = 'lw-fuel-prices';

  /// The zoom of the tiles' `pois` layer.
  static const pointsMinZoom = 13.0;

  /// The street zoom, from which the quiet points show.
  static const quietMinZoom = 15.0;

  /// Topmost first, for a tap.
  static const List<String> tappable = [selectionLayerId, pinsLayerId, quietLayerId, dotsLayerId];

  /// The image of a point of [kind]: its glyph on the category's tone, or
  /// grey and smaller when [quiet], or larger and ringed in amber when
  /// [selected]. The sprite generator writes them under the same ids.
  static String imageId(PoiKind kind, {bool quiet = false, bool selected = false}) =>
      'poi-${kind.code}${quiet ? '-quiet' : ''}${selected ? '-selected' : ''}';

  /// The dot of a category where its points gather.
  static String dotImageId(PoiCategory category) => 'poi-dot-${category.code}';

  /// Every image the layers use, for the sprite loader.
  static List<String> allImageIds() => [
    for (final kind in PoiKind.values) ...[
      imageId(kind),
      imageId(kind, quiet: true),
      imageId(kind, selected: true),
    ],
    for (final c in PoiCategory.values) dotImageId(c),
  ];

  /// The image of each feature by its `kind` property. A `match` rather than
  /// a `concat`: the iOS plugin crashed on text built by expressions
  /// (`gl_map.dart`, the cluster counts).
  static List<Object> iconImage({bool quiet = false}) => [
    'match',
    ['get', 'kind'],
    for (final kind in PoiKind.values) ...[kind.code, imageId(kind, quiet: quiet)],
    imageId(PoiKind.vendingOther, quiet: quiet),
  ];

  static List<Object> _inIds(Set<String> ids) => [
    'in',
    ['get', 'id'],
    ['literal', ids.toList()..sort()],
  ];

  /// The points of the chosen category, less those a place stands for, and
  /// only the open ones when asked.
  static List<Object> pinsFilter(PoiLayerView view) => [
    'all',
    [
      '==',
      ['get', 'category'],
      view.category?.code ?? '',
    ],
    ['!', _inIds(view.state.hidden)],
    if (view.openNowOnly)
      [
        'any',
        [
          '==',
          ['get', 'alwaysOpen'],
          true,
        ],
        _inIds(view.state.open),
      ],
  ];

  /// Every point but those a place stands for, when no chip is on.
  static List<Object> quietFilter(PoiLayerView view) => [
    'all',
    // An expression, not a bare boolean: MapLibre would read `["==", true,
    // true]` as a legacy filter and refuse it (seen on Android).
    ['boolean', view.category == null],
    ['!', _inIds(view.state.hidden)],
  ];

  /// The gathering dots of the chosen category.
  static List<Object> dotsFilter(PoiLayerView view) => [
    '==',
    ['get', 'category'],
    view.category?.code ?? '',
  ];

  /// A closed point is drawn faded: it stays on the map, an information when
  /// arriving in the evening.
  static List<Object> opacity(PoiLayerView view) => ['case', _inIds(view.state.closed), 0.42, 1.0];

  /// Lower keys are placed first where points collide: at night what is
  /// open around the clock, then the open ones (by day, those open around
  /// the clock among them: the map reports none of them back), then the
  /// rest.
  static List<Object> sortKey(PoiLayerView view) => [
    'case',
    [
      '==',
      ['get', 'alwaysOpen'],
      true,
    ],
    if (view.night) 0 else 1,
    _inIds(view.state.open),
    1,
    _inIds(view.state.closed),
    3,
    2,
  ];

  /// The dot of each gathering by its `category` property.
  static List<Object> get dotImage => [
    'match',
    ['get', 'category'],
    for (final c in PoiCategory.values) ...[c.code, dotImageId(c)],
    dotImageId(PoiCategory.services),
  ];

  /// A gathering dot grows with the number of points it stands for; [scale]
  /// brings the image to the engine's unit, as for the pins.
  static List<Object> dotSize(double scale) => [
    'interpolate',
    ['linear'],
    ['get', 'count'],
    1,
    0.6 * scale,
    10,
    0.8 * scale,
    60,
    scale,
  ];

  /// The points the map reports back once it rests: those whose hours say
  /// whether they are open, and those a place may stand for. A point open
  /// around the clock needs no report (`alwaysOpen` is in the tiles).
  static List<Object> probeFilter(PoiLayerView view) => [
    'all',
    if (view.category != null)
      [
        '==',
        ['get', 'category'],
        view.category!.code,
      ],
    [
      'any',
      ['has', 'hours'],
      [
        'in',
        ['get', 'kind'],
        [
          'literal',
          [for (final k in duplicatedKinds) k.code],
        ],
      ],
    ],
  ];

  /// Lower keys are placed first: the dots of the most points win.
  static const List<Object> dotSortKey = [
    '-',
    0,
    ['get', 'count'],
  ];

  /// The fuel labels as GeoJSON: each price at its station.
  static Map<String, Object?> fuelCollection(List<FuelLabel> labels) => {
    'type': 'FeatureCollection',
    'features': [
      for (final l in labels)
        {
          'type': 'Feature',
          'id': l.id,
          'geometry': {
            'type': 'Point',
            'coordinates': [l.position.lon, l.position.lat],
          },
          'properties': {'id': l.id, 'label': l.text, 'rank': l.rank},
        },
    ],
  };

  /// From the cheapest station in view to the dearest, on
  /// [PoiLook.priceScale].
  static List<Object> fuelTextColor({required bool dark}) {
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final (cheap, middle, dear) = PoiLook.priceScale(dark: dark);
    return [
      'interpolate',
      ['linear'],
      ['get', 'rank'],
      0,
      hex(cheap),
      0.5,
      hex(middle),
      1,
      hex(dear),
    ];
  }

  static String fuelHalo({required bool dark}) => dark ? '#06142a' : '#fffbf4';

  /// The size of the prices: read at arm's length in a cab, larger than
  /// the counts of the clusters.
  static const double fuelTextSize = 14;

  /// The font of the prices, which the glyph server (and the app's offline
  /// glyphs) has.
  static const List<String> fuelFont = ['Noto Sans Medium'];

  /// The first symbol layer of a basemap style document, under which the
  /// quiet points go; null for a style URL or a style without labels.
  static String? firstLabelLayer(String style) {
    if (!style.trimLeft().startsWith('{')) return null;
    try {
      final layers = (jsonDecode(style) as Map<String, dynamic>)['layers'] as List<dynamic>?;
      for (final l in layers ?? const []) {
        if (l is Map<String, dynamic> && l['type'] == 'symbol') return l['id'] as String?;
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// The selection's single feature.
  static Map<String, Object?> selectionCollection(PoiFeature? selected) => {
    'type': 'FeatureCollection',
    'features': [
      if (selected != null)
        {
          'type': 'Feature',
          'id': selected.id,
          'geometry': {
            'type': 'Point',
            'coordinates': [selected.position.lon, selected.position.lat],
          },
          'properties': {
            'id': selected.id,
            'kind': selected.kind.code,
            'icon': imageId(selected.kind, selected: true),
          },
        },
    ],
  };
}

/// What a tap on the points layers does.
@immutable
sealed class PoiTap {
  const new();
}

/// Opens a point's page.
final class TapPoi extends PoiTap {
  const new(this.feature);

  final PoiFeature feature;
}

/// Zooms towards where a category's points gather.
final class TapPoiDot extends PoiTap {
  const new(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// The action for a tap on a feature with [properties] at [coordinates]
/// (`[lon, lat]`), or null when it is none of the points layers'.
PoiTap? poiTapFor(Map<Object?, Object?>? properties, List<Object?>? coordinates) {
  if (properties == null) return null;
  if (properties.containsKey('count') && !properties.containsKey('id')) {
    if (coordinates == null || coordinates.length < 2) return null;
    final lon = coordinates[0];
    final lat = coordinates[1];
    if (lon is! num || lat is! num) return null;
    return TapPoiDot(lat.toDouble(), lon.toDouble());
  }
  final feature = PoiFeature.fromTile(properties, coordinates);
  return feature == null ? null : TapPoi(feature);
}
