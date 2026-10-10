import 'dart:convert';

import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';

/// The order of the route maps' layers, the preview's and the guidance's,
/// the same on every engine: maplibre_gl on Android, iOS and the web
/// (`gl_route_map.dart`) and the desktop page (`web_view_route_map.dart`)
/// add their layers in this order and in no other.
/// `test/widget/route_layer_order_test.dart` reads what each engine draws.
abstract final class RouteLayerOrder {
  /// The lines, bottom to top: the danger zones' band under every route, the
  /// other routes under the chosen one, each casing under its line. Over the
  /// basemap and its roads' names, under its names of towns
  /// ([townNamesOf]): a town the route crosses keeps its name.
  static const List<String> lines = [
    RouteLayers.zones,
    RouteLayers.alternativesCasing,
    RouteLayers.alternatives,
    RouteLayers.routeCasing,
    RouteLayers.route,
  ];

  /// The pins of the points and of the places, a place over a shop as on
  /// the main map, and the invisible probe the rich marks read. Over the
  /// route, which never hides one: a pin keeps its size and its tip on its
  /// place, so one whose tip lies on the line covers only the bit of line
  /// under its head.
  static const List<String> pins = [RichLayers.probe, ...RoutePlaceLayers.layers];

  /// Every layer, bottom to top: [lines], [pins], the route's marks (the
  /// minor ones, the others, the numbered stops), the places drawn large,
  /// the start and the arrival, the vehicle. The marks over the names of
  /// towns: MapLibre places the upper layers first, so a town's name is
  /// left out where a badge or the vehicle stands, rather than written
  /// across it. The places drawn large keep clear of every mark of the
  /// route under them (`RichMarkDriver`).
  static final List<String> layers = [
    ...lines,
    ...pins,
    ...RouteLayers.layersOf(RouteLayers.minorSource),
    ...RouteLayers.layersOf(RouteLayers.marksSource),
    ...RouteLayers.layersOf(RouteLayers.stopsSource),
    RichLayers.marks,
    ...RouteLayers.layersOf(RouteLayers.endsSource),
    RouteLayers.vehicle,
  ];

  /// The source layer of the basemaps' names of places (Protomaps): towns,
  /// their quarters, regions, countries. The roads' names come before.
  /// The lines go under all of them, a name over a line hiding only a
  /// short stretch of it; the main map's pins go under the towns' names
  /// only (`PlaceTiles.basemapTownNames`), a pin giving way to one.
  static const basemapPlaceNames = 'places';

  /// The basemap's first layer of names of towns in [style], a style
  /// document; null for a style without one, or given by its URL, where the
  /// lines go on top with the rest.
  static String? townNamesOf(String style) {
    if (!style.trimLeft().startsWith('{')) return null;
    try {
      final layers = (jsonDecode(style) as Map<String, Object?>)['layers'];
      if (layers is! List) return null;
      for (final l in layers) {
        if (l is Map && l['type'] == 'symbol' && l['source-layer'] == basemapPlaceNames) {
          return l['id'] as String?;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// The layer [layer] goes under when it is added: the first of [layers]
  /// above it that the map holds ([present]; the pins come once their
  /// filters are known, over a route already drawn), a line staying under
  /// the basemap's [townNames]; none when nothing is above it: the top.
  static String? below(
    String layer, {
    required bool Function(String id) present,
    String? townNames,
  }) {
    final at = layers.indexOf(layer);
    if (at < 0) throw ArgumentError.value(layer, 'layer', 'not a layer of the route maps');
    final line = lines.contains(layer);
    for (final above in layers.skip(at + 1)) {
      if (line && townNames != null && !lines.contains(above)) return townNames;
      if (present(above)) return above;
    }
    return line ? townNames : null;
  }

  /// The layers a pointer picks from, topmost first.
  static final List<String> _targets = [
    for (final id in layers.reversed)
      if (RouteLayers.badges.contains(id) ||
          id == RichLayers.marks ||
          RoutePlaceLayers.tappable.contains(id))
        id,
  ];

  /// The priority of [layer]'s targets (`HitShape.priority`): of two the
  /// pointer is on at once, the one drawn on top.
  static int hitPriority(String layer) {
    final at = _targets.indexOf(layer);
    if (at < 0) throw ArgumentError.value(layer, 'layer', 'no target of the route maps');
    return 1 + at;
  }

  /// The priority of the other routes' lines, a target under every other.
  static int get linePriority => 1 + _targets.length;
}
