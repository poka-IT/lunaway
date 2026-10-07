import 'package:flutter/animation.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/pin_painter.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// What each layer of the map draws, for the pointer ([nearestHit]): taken
/// from the same values that draw it (the pins' geometry, the radii and
/// sizes of [MapLook] and [PoiMapStyle]), so a change of look moves the
/// targets with it.
final Map<String, HitShape> mapHitShapes = () {
  final pin = _pin(const PinGeometry(selected: false));
  const selected = PinGeometry(selected: true);
  // The marker of a long-pressed point (`pointMarkerSize`): a drop of
  // radius 14 whose head stands 17 px under the image's top.
  const marker = HitShape(radius: FixedHit(14), lift: FixedHit(44 - 17), priority: 0, inert: true);
  final poiPin = _poiPin(const PoiPinGeometry(), priority: 4);
  return {
    MapStyle.selectionPinLayer: HitShape(
      radius: FixedHit(selected.outer),
      lift: FixedHit(selected.tipDrop),
      anchor: _dot,
      icon: const FixedHit(1),
      priority: 0,
    ),
    '${MapStyle.selectionPinLayer}/point': marker,
    PoiMapStyle.selectionLayerId: _poiPin(const PoiPinGeometry(selected: true), priority: 0),
    MapStyle.placesLayer: pin,
    PlaceTiles.pinsLayer: pin,
    MapStyle.clustersLayer: HitShape(
      radius: StopsHit('point_count', [
        for (final (x, r) in _stops(MapLook.clusterRadius)) (x, r + MapLook.clusterStrokeWidth),
      ]),
      priority: 2,
    ),
    PlaceTiles.pinDotsLayer: HitShape(radius: _dot, priority: 3),
    PlaceTiles.dotsLayer: HitShape(radius: _dot, priority: 3),
    PoiMapStyle.pinsLayerId: poiPin,
    PoiMapStyle.quietLayerId: _poiPin(const PoiPinGeometry(quiet: true), priority: 5),
    PoiMapStyle.dotsLayerId: _poiDot,
    PoiMapStyle.vendingDotsLayerId: _poiDot,
  };
}();

/// A place's dot with its rim, by the zoom: the dot of the low zooms, the
/// dot under each pin, and the place's own point a pin stands on.
final StopsHit _dot = StopsHit(
  'zoom',
  _sum(_stops(MapLook.dotRadius), _stops(MapLook.dotStrokeWidth)),
);

/// A place's pin, at the size [MapLook.pinSize] draws it by the zoom, with
/// the dot under its tip ([HitShape.anchor]).
HitShape _pin(PinGeometry g) {
  final size = _stops(MapLook.pinSize(1));
  return HitShape(
    radius: StopsHit('zoom', [for (final (z, s) in size) (z, g.outer * s)]),
    lift: StopsHit('zoom', [for (final (z, s) in size) (z, g.tipDrop * s)]),
    anchor: _dot,
    icon: StopsHit('zoom', size),
    priority: 1,
  );
}

/// A point's pin: a rounded square on a short tail, anchored at the bottom
/// of its image, which leaves [PoiPinGeometry.margin] under the tip. No dot
/// is drawn there; its point takes a place's, so the hover's ring is the
/// same size under every pin.
HitShape _poiPin(PoiPinGeometry g, {required int priority}) {
  final half = g.side / 2 + g.rim;
  return HitShape(
    radius: FixedHit(half),
    lift: FixedHit(g.margin + g.tail + half),
    anchor: _dot,
    icon: const FixedHit(1),
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
];

/// Every other layer a pointer picks from.
const List<String> otherHitLayers = [
  MapStyle.clustersLayer,
  PlaceTiles.pinDotsLayer,
  PlaceTiles.dotsLayer,
  PoiMapStyle.quietLayerId,
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
    for (final e in {...mapHitShapes, ...routeHitShapes}.entries) e.key: e.value.toJson(),
  },
};

/// A cubic curve as CSS writes it (`cubic-bezier`); the theme's curves are
/// all cubic.
List<double> _bezier(Curve curve) => switch (curve) {
  Cubic(:final a, :final b, :final c, :final d) => [a, b, c, d],
  _ => const [0, 0, 1, 1],
};
