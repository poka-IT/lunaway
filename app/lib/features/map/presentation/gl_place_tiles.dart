import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/shared/map/tile_json_source.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// Layer properties as a style document writes them, sent as they are. The
/// plugin's typed classes send every property they know, the unset ones as
/// null, which resets them: a change of one paint property, or of a
/// basemap layer's colours, must leave the others alone.
final class RawLayerProperties implements gl.LayerProperties {
  const new(this.properties);

  final Map<String, Object?> properties;

  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) => {
    for (final MapEntry(:key, :value) in properties.entries)
      if (value != null || !skipNulls) key: value,
  };
}

/// The places from the API's vector tiles on maplibre_gl (Android, iOS, the
/// web): one source, the dots of the low zooms, a dot under each place
/// from the zoom of the pins, the pins. A change of filter is a filter on
/// those layers, drawn at the next frame without a request.
final class GlPlaceTiles {
  PlaceTilesView? _sent;
  bool? _sentDark;
  Object? _probed;

  /// The layers are gone with their style.
  void forget() {
    _sent = null;
    _sentDark = null;
    _probed = null;
  }

  bool get installed => _sent != null;

  /// Adds the source and the layers of [view]: the glow and the low zooms'
  /// dots under [labels] when given (the basemap's first layer of names, so
  /// the towns stay readable over the country's view), the rest below
  /// [below] when given (the selected pin goes above them).
  Future<void> install(
    gl.MapLibreMapController c,
    PlaceTilesView view, {
    required double pinScale,
    required bool dark,
    required bool Function() current,
    bool touch = false,
    String? below,
    String? labels,
  }) async {
    // A newer style load or install may own the layers by now: this one
    // leaves them alone.
    if (!current()) return;
    await remove(c);
    if (!current()) return;
    await c.addSource(PlaceTiles.source, tileJsonSource(view.tileJsonUrl));
    final filter = placeTileFilter(view.filter);
    if (!current()) return;
    await c.addCircleLayer(
      PlaceTiles.source,
      PlaceTiles.glowLayer,
      glow(dark: dark),
      sourceLayer: PlaceTiles.dotsSourceLayer,
      maxzoom: MapLook.glowMaxZoom,
      filter: filter,
      belowLayerId: labels ?? below,
      enableInteraction: false,
    );
    if (!current()) return;
    await c.addCircleLayer(
      PlaceTiles.source,
      PlaceTiles.dotsLayer,
      dots(dark: dark, touch: touch),
      sourceLayer: PlaceTiles.dotsSourceLayer,
      maxzoom: PlaceTiles.pinZoom,
      filter: filter,
      belowLayerId: labels ?? below,
      enableInteraction: false,
    );
    if (!current()) return;
    await c.addCircleLayer(
      PlaceTiles.source,
      PlaceTiles.pinDotsLayer,
      dots(dark: dark, touch: touch),
      sourceLayer: PlaceTiles.pinsSourceLayer,
      minzoom: PlaceTiles.pinZoom,
      filter: filter,
      belowLayerId: below,
      enableInteraction: false,
    );
    if (!current()) return;
    await c.addSymbolLayer(
      PlaceTiles.source,
      PlaceTiles.pinsLayer,
      _pins(pinScale),
      sourceLayer: PlaceTiles.pinsSourceLayer,
      minzoom: PlaceTiles.pinZoom,
      filter: filter,
      belowLayerId: below,
      enableInteraction: false,
    );
    _sent = view;
    _sentDark = dark;
    _probed = null;
  }

  /// Takes the source and its layers away (the map turned to the places the
  /// device holds).
  Future<void> remove(gl.MapLibreMapController c) async {
    for (final layer in [
      PlaceTiles.pinsLayer,
      PlaceTiles.pinDotsLayer,
      PlaceTiles.dotsLayer,
      PlaceTiles.glowLayer,
    ]) {
      await _quietly(() => c.removeLayer(layer));
    }
    await _quietly(() => c.removeSource(PlaceTiles.source));
    _sent = null;
    _sentDark = null;
  }

  /// Sends what changed in [view] since the last call: a filter is four
  /// filters, the theme the dots' rims and the glow's colour. A new
  /// TileJSON (another API) needs [install] again.
  Future<void> sync(gl.MapLibreMapController c, PlaceTilesView view, {required bool dark}) async {
    final sent = _sent;
    if (sent == null) return;
    if (sent.filter != view.filter) {
      final filter = placeTileFilter(view.filter);
      for (final layer in [
        PlaceTiles.glowLayer,
        PlaceTiles.dotsLayer,
        PlaceTiles.pinDotsLayer,
        PlaceTiles.pinsLayer,
      ]) {
        await c.setFilter(layer, filter);
      }
    }
    if (_sentDark != dark) {
      final stroke = RawLayerProperties({'circle-stroke-color': MapLook.dotStroke(dark: dark)});
      await c.setLayerProperties(PlaceTiles.dotsLayer, stroke);
      await c.setLayerProperties(PlaceTiles.pinDotsLayer, stroke);
      await c.setLayerProperties(
        PlaceTiles.glowLayer,
        RawLayerProperties({
          'circle-color': MapLook.glowColor(dark: dark),
          'circle-opacity': MapLook.glowOpacity(dark: dark),
        }),
      );
      _sentDark = dark;
    }
    _sent = view;
  }

  /// Every place of the tiles inside [bounds] once the map rests, at the
  /// zoom of the pins, whatever the filter: the list and the count of the
  /// filters' sheet apply a filter to the same report on the device
  /// ([PlaceFilter.matches], the tiles' rule), so their two numbers agree.
  /// Null when nothing changed since the last report (the same camera and
  /// view: a resize keeps the camera and changes the view).
  Future<List<PlaceSummary>?> probe(
    gl.MapLibreMapController c, {
    required double zoom,
    required Object camera,
    required GeoBounds bounds,
  }) async {
    if (_sent == null) return null;
    final key = (camera, bounds);
    if (key == _probed) return null;
    _probed = key;
    if (zoom < PlaceTiles.pinZoom) return const [];
    final raw = await c.querySourceFeatures(
      PlaceTiles.source,
      PlaceTiles.pinsSourceLayer,
      placeTileFilter(PlaceFilter.none),
    );
    return placesOfFeatures(raw, bounds);
  }

  /// The dots' paint, larger in the country's view where a finger picks
  /// ([touch], [MapLook.touchDotRadius]).
  @visibleForTesting
  static gl.CircleLayerProperties dots({required bool dark, required bool touch}) =>
      gl.CircleLayerProperties(
        circleColor: placeTileDotColor(MapLook.familyColor),
        circleRadius: touch ? MapLook.touchDotRadius : MapLook.dotRadius,
        circleStrokeWidth: MapLook.dotStrokeWidth,
        circleStrokeColor: MapLook.dotStroke(dark: dark),
        circleOpacity: MapLook.dotOpacity,
        circleStrokeOpacity: MapLook.dotStrokeOpacity,
        circleSortKey: placeTileRank(),
      );

  /// The glow of the country's view ([MapLook.glowColor]).
  @visibleForTesting
  static gl.CircleLayerProperties glow({required bool dark}) => gl.CircleLayerProperties(
    circleRadius: MapLook.glowRadius,
    circleBlur: MapLook.glowBlur,
    circleColor: MapLook.glowColor(dark: dark),
    circleOpacity: MapLook.glowOpacity(dark: dark),
  );

  static gl.SymbolLayerProperties _pins(double scale) => gl.SymbolLayerProperties(
    iconImage: placeTilePinImage(),
    iconSize: MapLook.pinSize(scale),
    iconAnchor: 'bottom',
    // A pin with no room is left out, its dot still drawn: the places of a
    // busy coast stay readable, and every one of them is there.
    iconAllowOverlap: false,
    iconIgnorePlacement: false,
    iconPadding: 0,
    symbolSortKey: placeTileRank(placement: true),
  );

  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // Nothing of that id on this style: the add that follows is all.
    }
  }
}

/// What a tap on a feature of the tiles does: open a place (a pin, or a dot
/// from the zoom of the pins, which carries its id), or come closer to a
/// dot of the low zooms, which carries none.
sealed class PlaceTileTap {
  const new();
}

final class OpenTilePlace extends PlaceTileTap {
  const new(this.place);

  final PlaceSummary place;
}

/// A dot of the low zooms: the tiles draw the dots that share their
/// properties as one feature of several points (`place_dots`, a MultiPoint),
/// so the map comes closer around the tap rather than around a point of it.
final class ZoomToTileDot extends PlaceTileTap {
  const new();
}

/// The places among the features of a `querySourceFeatures` answer of the
/// pins' layer that stand inside [bounds], each once: a place on the edge of
/// two tiles comes twice, a tile carries a margin beyond its edge, and the
/// answer holds every tile the engine keeps, not only those it draws.
/// MapLibre Native loads the tiles four zooms below the view's ahead
/// (`prefetchZoomDelta`): at street zoom on Android the places also come
/// from a tile of zoom 10, without their name and town, which only travel
/// from [PlaceTiles.nameZoom]. Of two copies the one that names the place
/// stays, whatever the order, so the list never loses its names.
List<PlaceSummary> placesOfFeatures(List<Object?> raw, GeoBounds bounds) {
  final byId = <String, PlaceSummary>{};
  for (final item in raw) {
    var feature = item;
    // The web answers maps, Android and iOS GeoJSON text or maps.
    if (feature is String) feature = jsonDecode(feature);
    if (feature is! Map) continue;
    final geometry = feature['geometry'];
    final place = placeFromTile(
      feature['properties'] as Map<Object?, Object?>?,
      geometry is Map ? geometry['coordinates'] as List<Object?>? : null,
    );
    if (place == null || !bounds.contains(place.position)) continue;
    final kept = byId[place.id];
    if (kept == null || _named(place) > _named(kept)) byId[place.id] = place;
  }
  return byId.values.toList();
}

int _named(PlaceSummary place) => (place.name == null ? 0 : 1) + (place.city == null ? 0 : 1);

/// The action for a tap on a feature with [properties] at [coordinates]
/// (`[lon, lat]`); null when it is no feature of the places' tiles: the
/// map's own GeoJSON layers mark theirs with the kinds `place` and `point`,
/// and the points of interest carry kinds of their own.
PlaceTileTap? placeTileTapFor(Map<Object?, Object?>? properties, List<Object?>? coordinates) {
  final kind = properties?[PlaceTiles.kind];
  if (kind is! String || !isTilePlaceKind(kind)) return null;
  final place = placeFromTile(properties, coordinates);
  if (place != null) return OpenTilePlace(place);
  // A dot of the low zooms: no id, the map comes closer.
  return const ZoomToTileDot();
}

/// The zoom a tap on a dot brings the map to: closer by three levels, at
/// least to the pins.
double zoomForDot(double zoom) => (zoom + 3).clamp(PlaceTiles.pinZoom + 0.5, 22).toDouble();
