import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/tile_json_source.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// The points of interest on maplibre_gl (Android, iOS, the web): the
/// vector tiles of the API through one source, the category's gathering
/// dots below zoom 13, its pins above, every point quietly at street zoom
/// when no chip is on, and the open point on top. The map widget calls it
/// at each style load, each change of [PoiLayerView] and each rest.
final class GlPoiLayers {
  PoiLayerView? _sent;
  Object? _probed;
  String? _installedUrl;

  /// The TileJSON the source reads, once installed: the tiles of every
  /// category while a chip shows one read on demand, the default ones
  /// otherwise. A change installs the source again ([installBelowPlaces]).
  String? get installedUrl => _installedUrl;

  /// The camera and the category of the last report of the points in view:
  /// the map settles again after each change of a layer, which must not
  /// report the same view again.
  void forget() {
    _sent = null;
    _probed = null;
  }

  /// Adds the source and the layers of [view] to a freshly loaded style;
  /// [below] is the basemap's first label layer, under which the quiet
  /// points and the category's gathering dots go so street and place names
  /// keep their room. On a style whose places are already there, [below]
  /// and [pinsBelow] are the places' own layers ([poiReinstallAnchors]),
  /// so the night spots keep the map.
  Future<void> installBelowPlaces(
    gl.MapLibreMapController c,
    PoiLayerView view, {
    required double pinScale,
    required bool Function() current,
    required bool dark,
    String? below,
    String? pinsBelow,
  }) async {
    forget();
    _installedUrl = null;
    for (final layer in [
      PoiMapStyle.morePinsLayerId,
      PoiMapStyle.pinsLayerId,
      PoiMapStyle.fuelLayerId,
      PoiMapStyle.moreQuietLayerId,
      PoiMapStyle.quietLayerId,
      PoiMapStyle.vendingDotsLayerId,
      PoiMapStyle.dotsLayerId,
    ]) {
      await _quietly(() => c.removeLayer(layer));
    }
    await _quietly(() => c.removeSource(PoiMapStyle.source));
    await _quietly(() => c.removeSource(PoiMapStyle.fuelSource));
    if (!current()) return;
    await c.addSource(PoiMapStyle.source, tileJsonSource(view.tileJsonUrl));
    _installedUrl = view.tileJsonUrl;
    if (!current()) return;
    await c.addSymbolLayer(
      PoiMapStyle.source,
      PoiMapStyle.dotsLayerId,
      _dots(view, pinScale),
      sourceLayer: PoiMapStyle.clustersLayer,
      maxzoom: PoiMapStyle.pointsMinZoom,
      filter: PoiMapStyle.dotsFilter(view),
      // Under the basemap's names, where the places' glow and dots go too,
      // after them: the night spots keep the map.
      belowLayerId: below ?? pinsBelow,
      enableInteraction: false,
    );
    if (!current()) return;
    await c.addSymbolLayer(
      PoiMapStyle.source,
      PoiMapStyle.vendingDotsLayerId,
      _vendingDots(pinScale),
      sourceLayer: PoiMapStyle.vendingClustersLayer,
      maxzoom: PoiMapStyle.pointsMinZoom,
      filter: PoiMapStyle.vendingDotsFilter(view),
      belowLayerId: below ?? pinsBelow,
      enableInteraction: false,
    );
    if (!current()) return;
    for (final (id, layer) in [
      (PoiMapStyle.quietLayerId, PoiMapStyle.pointsLayer),
      (PoiMapStyle.moreQuietLayerId, PoiMapStyle.morePointsLayer),
    ]) {
      if (!current()) return;
      await c.addSymbolLayer(
        PoiMapStyle.source,
        id,
        _quiet(view, pinScale),
        sourceLayer: layer,
        minzoom: PoiMapStyle.quietMinZoom,
        filter: PoiMapStyle.quietFilter(view),
        belowLayerId: below ?? pinsBelow,
        enableInteraction: false,
      );
    }
    if (!current()) return;
    // The prices sit under the pins: a pin keeps its room, its price shows
    // where there is some left.
    await c.addSource(
      PoiMapStyle.fuelSource,
      gl.GeojsonSourceProperties(data: PoiMapStyle.fuelCollection(view.fuelLabels)),
    );
    if (!current()) return;
    await c.addSymbolLayer(
      PoiMapStyle.fuelSource,
      PoiMapStyle.fuelLayerId,
      _fuel(dark: dark),
      minzoom: PoiMapStyle.pointsMinZoom,
      belowLayerId: pinsBelow,
      enableInteraction: false,
    );
    if (!current()) return;
    await c.addSymbolLayer(
      PoiMapStyle.source,
      PoiMapStyle.pinsLayerId,
      _pins(view, pinScale),
      sourceLayer: PoiMapStyle.pointsLayer,
      minzoom: PoiMapStyle.pointsMinZoom,
      filter: PoiMapStyle.pinsFilter(view),
      belowLayerId: pinsBelow,
      enableInteraction: false,
    );
    if (!current()) return;
    await c.addSymbolLayer(
      PoiMapStyle.source,
      PoiMapStyle.morePinsLayerId,
      _pins(view, pinScale),
      sourceLayer: PoiMapStyle.morePointsLayer,
      minzoom: PoiMapStyle.pointsMinZoom,
      filter: PoiMapStyle.pinsFilter(view),
      belowLayerId: pinsBelow,
      enableInteraction: false,
    );
  }

  /// Adds the open point's layer, above the places.
  Future<void> installSelection(
    gl.MapLibreMapController c, {
    required double pinScale,
    required bool Function() current,
  }) async {
    await _quietly(() => c.removeLayer(PoiMapStyle.selectionLayerId));
    await _quietly(() => c.removeSource(PoiMapStyle.selectionSource));
    if (!current()) return;
    await c.addSource(
      PoiMapStyle.selectionSource,
      const gl.GeojsonSourceProperties(data: {'type': 'FeatureCollection', 'features': <Object>[]}),
    );
    if (!current()) return;
    await c.addSymbolLayer(
      PoiMapStyle.selectionSource,
      PoiMapStyle.selectionLayerId,
      gl.SymbolLayerProperties(
        iconImage: const ['get', 'icon'],
        iconSize: pinScale,
        iconAnchor: 'bottom',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
  }

  /// Sends what changed in [view] since the last call.
  Future<void> sync(
    gl.MapLibreMapController c,
    PoiLayerView view, {
    required double pinScale,
  }) async {
    final sent = _sent;
    if (sent == view && sent?.selected?.kind == view.selected?.kind) return;
    _sent = view;
    if (sent == null ||
        sent.category != view.category ||
        sent.vending != view.vending ||
        sent.openNowOnly != view.openNowOnly ||
        sent.state != view.state ||
        sent.night != view.night) {
      await c.setFilter(PoiMapStyle.dotsLayerId, PoiMapStyle.dotsFilter(view));
      await c.setFilter(PoiMapStyle.vendingDotsLayerId, PoiMapStyle.vendingDotsFilter(view));
      for (final quiet in [PoiMapStyle.quietLayerId, PoiMapStyle.moreQuietLayerId]) {
        await c.setFilter(quiet, PoiMapStyle.quietFilter(view));
        await c.setLayerProperties(quiet, _quiet(view, pinScale));
      }
      for (final pins in [PoiMapStyle.pinsLayerId, PoiMapStyle.morePinsLayerId]) {
        await c.setFilter(pins, PoiMapStyle.pinsFilter(view));
        await c.setLayerProperties(pins, _pins(view, pinScale));
      }
      await c.setLayerProperties(PoiMapStyle.dotsLayerId, _dots(view, pinScale));
    }
    if (!listEquals(sent?.fuelLabels, view.fuelLabels)) {
      await c.setGeoJsonSource(PoiMapStyle.fuelSource, PoiMapStyle.fuelCollection(view.fuelLabels));
    }
    if (sent?.selected != view.selected || sent?.selected?.kind != view.selected?.kind) {
      await c.setGeoJsonSource(
        PoiMapStyle.selectionSource,
        PoiMapStyle.selectionCollection(view.selected),
      );
    }
  }

  /// The points under the view once the map rests, or null when nothing
  /// changed since the last report (the same camera, the same chip). Below
  /// the zoom of the points, or below street zoom with no chip on, nothing
  /// is drawn and the list is empty.
  Future<List<PoiFeature>?> probe(
    gl.MapLibreMapController c,
    PoiLayerView view, {
    required double zoom,
    required Object camera,
  }) async {
    final key = (camera, view.category, view.vending);
    if (key == _probed) return null;
    _probed = key;
    final drawn = view.category != null
        ? zoom >= PoiMapStyle.pointsMinZoom
        : zoom >= PoiMapStyle.quietMinZoom;
    if (!drawn) return const [];
    final raw = [
      for (final layer in PoiMapStyle.pointLayers)
        ...await c.querySourceFeatures(PoiMapStyle.source, layer, PoiMapStyle.probeFilter(view)),
    ];
    return decodeProbe(raw);
  }

  static gl.SymbolLayerProperties _pins(PoiLayerView view, double scale) =>
      gl.SymbolLayerProperties(
        iconImage: PoiMapStyle.iconImage(),
        iconSize: scale,
        iconAnchor: 'bottom',
        iconOpacity: PoiMapStyle.opacity(view),
        symbolSortKey: PoiMapStyle.sortKey(view),
        iconPadding: 1,
      );

  static gl.SymbolLayerProperties _quiet(PoiLayerView view, double scale) =>
      gl.SymbolLayerProperties(
        iconImage: PoiMapStyle.iconImage(quiet: true),
        iconSize: scale,
        iconAnchor: 'bottom',
        iconOpacity: PoiMapStyle.opacity(view),
        symbolSortKey: PoiMapStyle.sortKey(view),
        iconPadding: 1,
      );

  static gl.SymbolLayerProperties _fuel({required bool dark}) => gl.SymbolLayerProperties(
    textField: const ['get', 'label'],
    textFont: PoiMapStyle.fuelFont,
    textSize: PoiMapStyle.fuelTextSize,
    textColor: PoiMapStyle.fuelTextColor(dark: dark),
    textHaloColor: PoiMapStyle.fuelHalo(dark: dark),
    textHaloWidth: 2,
    textAnchor: 'top',
    textOffset: const [0, 0.25],
    textPadding: 1,
  );

  static gl.SymbolLayerProperties _dots(PoiLayerView view, double scale) =>
      gl.SymbolLayerProperties(
        iconImage: PoiMapStyle.dotImage,
        iconSize: PoiMapStyle.dotSize(scale),
        symbolSortKey: PoiMapStyle.dotSortKey,
        iconPadding: 2,
      );

  static gl.SymbolLayerProperties _vendingDots(double scale) => gl.SymbolLayerProperties(
    iconImage: PoiMapStyle.vendingDotImage,
    iconSize: PoiMapStyle.dotSize(scale),
    symbolSortKey: PoiMapStyle.dotSortKey,
    iconPadding: 2,
  );

  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // Nothing of that id on this style: the add that follows is all.
    }
  }
}

/// Where the points' layers go when they are installed again on a style
/// that holds the places already (another set of tiles, for a chip of a
/// category read on demand): where the first install left them. With the
/// places' tiles, the dots and the quiet points under the lowest of their
/// layers (the glow), the prices and the pins under their pins' dots;
/// with the device's places, under the basemap's first label and under the
/// places' clusters.
({String? below, String? pinsBelow}) poiReinstallAnchors({
  required bool placeTilesInstalled,
  String? firstLabel,
}) => placeTilesInstalled
    ? (below: PlaceTiles.glowLayer, pinsBelow: PlaceTiles.pinDotsLayer)
    : (below: firstLabel, pinsBelow: MapStyle.clustersLayer);

/// The points of a `querySourceFeatures` answer, each once (a point on the
/// edge of two tiles comes twice).
List<PoiFeature> decodeProbe(List<Object?> raw) {
  final seen = <String>{};
  final out = <PoiFeature>[];
  for (final item in raw) {
    var feature = item;
    // The web answers maps, Android and iOS GeoJSON text or maps.
    if (feature is String) feature = jsonDecode(feature);
    if (feature is! Map) continue;
    final geometry = feature['geometry'];
    final poi = PoiFeature.fromTile(
      feature['properties'] as Map<Object?, Object?>?,
      geometry is Map ? geometry['coordinates'] as List<Object?>? : null,
    );
    if (poi != null && seen.add(poi.id)) out.add(poi);
  }
  return out;
}
