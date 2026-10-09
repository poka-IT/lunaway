import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/pin_painter.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// What each layer of the map draws, for the pointer ([nearestHit]): taken
/// from the same values that draw it (the pins' geometry, the radii and
/// sizes of [MapLook] and [PoiMapStyle]), so a change of look moves the
/// targets with it. The browser's and the desktop's map, the pages' copy.
final Map<String, HitShape> mapHitShapes = _mapShapes(_dot);

/// Whether a map draws the places' dots for a finger
/// ([MapLook.touchDotRadius]): the apps of a phone or a tablet. The browser
/// keeps the mouse's dots, whatever points at it: its pages share them.
bool fingerDots({required bool web, required TargetPlatform platform}) =>
    !web && (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

/// The shapes a tap picks from, those of the dots drawn ([fingerDots]).
Map<String, HitShape> placeHitShapes({required bool fingerDots}) =>
    fingerDots ? touchMapHitShapes : mapHitShapes;

/// [mapHitShapes] on the apps of a phone or a tablet, whose places' dots
/// are drawn larger for a finger ([MapLook.touchDotRadius]): the tolerance
/// is measured from the dot drawn there.
final Map<String, HitShape> touchMapHitShapes = _mapShapes(_touchDot);

Map<String, HitShape> _mapShapes(StopsHit dot) {
  const selected = PinGeometry(selected: true);
  // The marker of a long-pressed point (`pointMarkerSize`): a drop of
  // radius 14 whose head stands 17 px under the image's top.
  const marker = HitShape(radius: FixedHit(14), lift: FixedHit(44 - 17), priority: 0, marker: true);
  return {
    // A selection stands over the pin it was chosen from, drawn by another
    // layer: its tip, where the place's dot is (one of the tiles), is part
    // of it, so the pointer there finds the selection and not the pin
    // under it. A tap there opens what is already open. The selection
    // keeps its own look under the mouse: only the ring is added.
    MapStyle.selectionPinLayer: HitShape(
      radius: FixedHit(selected.outer),
      lift: FixedHit(selected.tipDrop),
      anchor: dot,
      priority: 0,
    ),
    '${MapStyle.selectionPinLayer}/point': marker,
    PoiMapStyle.selectionLayerId: _poiPin(
      const PoiPinGeometry(selected: true),
      priority: 0,
      selection: true,
      dot: dot,
    ),
    // The device's places: no dot under their pins.
    MapStyle.placesLayer: _pin(const PinGeometry(selected: false), dotUnder: false, dot: dot),
    PlaceTiles.pinsLayer: _pin(const PinGeometry(selected: false), dotUnder: true, dot: dot),
    MapStyle.clustersLayer: HitShape(
      radius: StopsHit('point_count', [
        for (final (x, r) in _stops(MapLook.clusterRadius)) (x, r + MapLook.clusterStrokeWidth),
      ]),
      priority: 2,
    ),
    PlaceTiles.pinDotsLayer: HitShape(radius: dot, priority: 3),
    PlaceTiles.dotsLayer: HitShape(radius: dot, priority: 3),
    PoiMapStyle.pinsLayerId: _poiPin(const PoiPinGeometry(), priority: 4, dot: dot),
    PoiMapStyle.morePinsLayerId: _poiPin(const PoiPinGeometry(), priority: 4, dot: dot),
    PoiMapStyle.quietLayerId: _poiPin(const PoiPinGeometry(quiet: true), priority: 5, dot: dot),
    PoiMapStyle.moreQuietLayerId: _poiPin(const PoiPinGeometry(quiet: true), priority: 5, dot: dot),
    PoiMapStyle.dotsLayerId: _poiDot,
    PoiMapStyle.vendingDotsLayerId: _poiDot,
  };
}

/// A place's dot with its rim, by the zoom: the dot of the low zooms, the
/// dot under each pin of the tiles, and the hover's ring under every pin.
final StopsHit _dot = StopsHit(
  'zoom',
  _sum(_stops(MapLook.dotRadius), _stops(MapLook.dotStrokeWidth)),
);

/// [_dot] as a finger's map draws it.
final StopsHit _touchDot = StopsHit(
  'zoom',
  _sum(_stops(MapLook.touchDotRadius), _stops(MapLook.dotStrokeWidth)),
);

/// The pins of the guidance map's places and points, smaller than the main
/// map's ([RoutePlaceLayers]), under the route's marks for a tap that
/// could pick either. No dot is drawn under them.
final Map<String, HitShape> routePlaceHitShapes = {
  // A rich mark is over the pins: its head, at the size it is drawn.
  RichLayers.marks: RichLayers.hit,
  RoutePlaceLayers.placePins: _pin(
    const PinGeometry(selected: false),
    dotUnder: false,
    scale: RoutePlaceLayers.placeScale,
    priority: 4,
  ),
  RoutePlaceLayers.poiPins: _poiPin(
    const PoiPinGeometry(),
    priority: 5,
    scale: RoutePlaceLayers.poiScale,
  ),
};

/// A place's pin, at the size [MapLook.pinSize] draws it by the zoom, times
/// [scale]. With [dotUnder] (the tiles' pins), the dot drawn under its tip
/// from the same feature is part of it ([HitShape.anchor]); without, the
/// hover's ring takes that dot's size ([HitShape.ring]) and the target
/// stays the head.
HitShape _pin(
  PinGeometry g, {
  required bool dotUnder,
  double scale = 1,
  int priority = 1,
  StopsHit? dot,
}) {
  final size = _stops(MapLook.pinSize(scale));
  final under = dot ?? _dot;
  return HitShape(
    radius: StopsHit('zoom', [for (final (z, s) in size) (z, g.outer * s)]),
    lift: StopsHit('zoom', [for (final (z, s) in size) (z, g.tipDrop * s)]),
    anchor: dotUnder ? under : null,
    ring: dotUnder ? null : under,
    icon: StopsHit('zoom', size),
    priority: priority,
  );
}

/// A point's pin: a rounded square on a short tail, anchored at the bottom
/// of its image, which leaves [PoiPinGeometry.margin] under the tip. No dot
/// is drawn there: the hover's ring takes a place's dot size, so it is the
/// same under every pin. A [selection] stands over the point's own pin and
/// takes in its tip, as a place's does.
HitShape _poiPin(
  PoiPinGeometry g, {
  required int priority,
  bool selection = false,
  double scale = 1,
  StopsHit? dot,
}) {
  final half = (g.side / 2 + g.rim) * scale;
  final under = dot ?? _dot;
  return HitShape(
    radius: FixedHit(half),
    lift: FixedHit((g.margin + g.tail) * scale + half),
    anchor: selection ? under : null,
    ring: selection ? null : under,
    icon: selection ? null : FixedHit(scale),
    priority: priority,
  );
}

/// A category's gathering dot, centred on its point, sized by its count.
final HitShape _poiDot = HitShape(
  radius: StopsHit('count', [
    for (final (n, s) in _stops(PoiMapStyle.dotSize(1))) (n, poiDotSize.width / 2 * s),
  ]),
  priority: 6,
);

/// The (input, output) pairs of a style `interpolate` expression.
List<(double, double)> _stops(List<Object> expression) {
  final pairs = expression.sublist(3);
  return [
    for (var i = 0; i + 1 < pairs.length; i += 2)
      ((pairs[i] as num).toDouble(), (pairs[i + 1] as num).toDouble()),
  ];
}

/// Two piecewise linear functions added: exact at every stop of either.
List<(double, double)> _sum(List<(double, double)> a, List<(double, double)> b) {
  final xs = {for (final (x, _) in a) x, for (final (x, _) in b) x}.toList()..sort();
  return [for (final x in xs) (x, interpolateStops(a, x) + interpolateStops(b, x))];
}

/// The layers a pin draws, which a query asks apart from the rest: Android
/// and iOS answer features without their layer, and a place of the tiles
/// comes as the same feature from its pin and from the dot under it.
const List<String> pinHitLayers = [
  MapStyle.selectionPinLayer,
  PoiMapStyle.selectionLayerId,
  MapStyle.placesLayer,
  PlaceTiles.pinsLayer,
  PoiMapStyle.pinsLayerId,
  // The same pins, of the kinds the default tiles keep apart: an engine
  // that answers a feature without its layer reads it as [pinsLayerId],
  // whose shape it shares.
  PoiMapStyle.morePinsLayerId,
];

/// Every other layer a pointer picks from.
const List<String> otherHitLayers = [
  MapStyle.clustersLayer,
  PlaceTiles.pinDotsLayer,
  PlaceTiles.dotsLayer,
  PoiMapStyle.quietLayerId,
  // Read as [PoiMapStyle.quietLayerId] by an engine that answers a feature
  // without its layer: the same shape.
  PoiMapStyle.moreQuietLayerId,
  PoiMapStyle.dotsLayerId,
  PoiMapStyle.vendingDotsLayerId,
];

/// The layer a feature an engine answered came from, from the query that
/// found it ([pin] for [pinHitLayers]) and its properties.
String hitLayerOf(Map<Object?, Object?> properties, {required bool pin}) {
  final kind = properties['kind'];
  final icon = properties['icon'];
  final selected = icon is String && icon.endsWith('-selected');
  final tilePlace = kind is String && isTilePlaceKind(kind);
  if (pin) {
    if (kind == 'point') return MapStyle.selectionPinLayer;
    if (kind == 'place') return selected ? MapStyle.selectionPinLayer : MapStyle.placesLayer;
    if (tilePlace) return PlaceTiles.pinsLayer;
    return selected ? PoiMapStyle.selectionLayerId : PoiMapStyle.pinsLayerId;
  }
  if (properties.containsKey('point_count')) return MapStyle.clustersLayer;
  if (tilePlace) {
    return properties[PlaceTiles.id] == null ? PlaceTiles.dotsLayer : PlaceTiles.pinDotsLayer;
  }
  if (properties.containsKey('count') && !properties.containsKey('id')) {
    return PoiMapStyle.dotsLayerId;
  }
  return PoiMapStyle.quietLayerId;
}

/// What the map pages read (`web/lunaway_maplibre.js`, `web/premap.js`,
/// `assets/map/lunaway_map.js`): the tolerances, the shapes of every layer
/// a pointer picks from, the route map's too, and the look of the hover:
/// its ring around the point under the mouse, how much a pin grows, and the
/// theme's timing for both.
Map<String, Object?> hitShapesJson() => {
  'tolerance': {for (final k in PointerKind.values) k.name: hitTolerance(k)},
  'ring': {
    'color': '#${(LunaTokens.selection.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    'width': MapLook.hoverRingWidth,
    'gap': MapLook.hoverRingGap,
    'grow': MapLook.hoverGrow,
    'ms': Motion.short.inMilliseconds,
    'enter': _bezier(Motion.enter),
    'exit': _bezier(Motion.exit),
  },
  'shapes': {
    for (final e in {...mapHitShapes, ...routeHitShapes, ...routePlaceHitShapes}.entries)
      e.key: e.value.toJson(),
  },
};

/// A cubic curve as CSS writes it (`cubic-bezier`). The theme's curves are
/// all cubic; another kind would have no CSS twin, and fails the pages'
/// test rather than ease otherwise on the map.
List<double> _bezier(Curve curve) => switch (curve) {
  Cubic(:final a, :final b, :final c, :final d) => [a, b, c, d],
  _ => throw StateError('$curve has no cubic-bezier form'),
};
