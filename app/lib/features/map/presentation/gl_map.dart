import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

final _log = Logger('map');

/// The map on Android, iOS and the web: maplibre_gl (MapLibre Native, and
/// MapLibre GL JS in the browser). Places go through one clustered GeoJSON
/// source, never one widget per place.
class GlLunaMap extends StatefulWidget {
  const new(this.props, {super.key});

  final LunaMapProps props;

  @override
  State<GlLunaMap> createState() => _GlLunaMapState();
}

class _GlLunaMapState extends State<GlLunaMap> implements LunaMapController {
  gl.MapLibreMapController? _controller;
  bool _ready = false;
  bool _locationOn = false;

  // What the style currently holds, to send only what changed.
  List<PlaceSummary>? _sentPlaces;
  String? _sentSelected;
  LatLng? _sentPoint;

  // Updates run one after the other: a newer one never races an older one.
  Future<void> _queue = Future.value();

  // Stops the web long press listener; null on native builds.
  void Function()? _stopWebLongPress;

  LunaMapProps get _props => widget.props;

  @override
  void dispose() {
    _stopWebLongPress?.call();
    super.dispose();
  }

  Future<void> _onWebLongPress(double x, double y) async {
    final c = _controller;
    if (c == null || !mounted) return;
    final position = await c.toLatLng(math.Point(x, y));
    if (mounted) _props.onLongPress(LatLng(position.latitude, position.longitude));
  }

  @override
  void didUpdateWidget(GlLunaMap old) {
    super.didUpdateWidget(old);
    if (old.props.style != _props.style) {
      // The new style drops every source and layer; they come back on load.
      _ready = false;
      _sentPlaces = null;
      _sentSelected = null;
      _sentPoint = null;
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    _queue = _queue.then((_) => _sync()).catchError((Object e, StackTrace st) {
      _log.warning('map update failed', e, st);
    });
  }

  /// The pin images of the screen's density, and the factor that brings
  /// them to the engine's unit: MapLibre Android reads an image pixel as a
  /// physical pixel, the others as a logical one.
  int get _ratio => PinSprites.ratioFor(MediaQuery.devicePixelRatioOf(context));

  double get _pinScale {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return (android ? MediaQuery.devicePixelRatioOf(context) : 1) / _ratio;
  }

  gl.SymbolLayerProperties _selectionLayer(double size) => gl.SymbolLayerProperties(
    iconImage: const ['get', 'icon'],
    iconSize: size,
    iconAnchor: 'bottom',
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );

  /// Counts style loads: a theme or language switch loads a new style while
  /// the setup of the previous one may still be adding its layers.
  int _styleLoads = 0;

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || !mounted) return;
    if (kIsWeb) _stopWebLongPress ??= listenWebMapLongPress(_onWebLongPress);
    final load = ++_styleLoads;
    _ready = false;
    // A newer style load takes over: this one stops at its next step.
    bool current() => mounted && load == _styleLoads;
    final dark = _props.dark;
    try {
      final images = await PinSprites.load(_ratio);
      for (final e in images.entries) {
        if (!current()) return;
        await c.addImage(e.key, e.value);
      }
      // The one call an older setup had in flight may already have added a
      // layer or a source to this style: each is removed before it is added.
      Future<void> fresh(Future<void> Function() add, {String? layer, String? source}) async {
        if (!current()) return;
        if (layer != null) await _quietly(() => c.removeLayer(layer));
        if (source != null) await _quietly(() => c.removeSource(source));
        if (!current()) return;
        await add();
      }

      const empty = {'type': 'FeatureCollection', 'features': <Object>[]};
      for (final layer in [
        MapStyle.selectionPinLayer,
        MapStyle.placesLayer,
        MapStyle.clusterCountLayer,
        MapStyle.clustersLayer,
      ]) {
        await fresh(() async {}, layer: layer);
      }
      await fresh(
        () => c.addSource(
          MapStyle.placesSource,
          const gl.GeojsonSourceProperties(
            data: empty,
            cluster: true,
            clusterRadius: MapStyle.clusterRadius,
            clusterMaxZoom: MapStyle.clusterMaxZoom,
          ),
        ),
        source: MapStyle.placesSource,
      );
      await fresh(
        () => c.addSource(MapStyle.selectionSource, const gl.GeojsonSourceProperties(data: empty)),
        source: MapStyle.selectionSource,
      );
      await fresh(
        () => c.addCircleLayer(
          MapStyle.placesSource,
          MapStyle.clustersLayer,
          gl.CircleLayerProperties(
            circleColor: MapLook.clusterFill(dark: dark),
            circleRadius: MapLook.clusterRadius,
            circleStrokeWidth: MapLook.clusterStrokeWidth,
            circleStrokeColor: MapLook.clusterStroke(dark: dark),
            circleOpacity: MapLook.clusterOpacity,
          ),
          filter: MapStyle.clusterFilter,
        ),
        layer: MapStyle.clustersLayer,
      );
      await fresh(
        () => c.addSymbolLayer(
          MapStyle.placesSource,
          MapStyle.clusterCountLayer,
          gl.SymbolLayerProperties(
            textField: const ['get', 'point_count_abbreviated'],
            textFont: MapLook.clusterFont,
            textSize: MapLook.clusterTextSize,
            textColor: MapLook.clusterText(dark: dark),
            textAllowOverlap: true,
            textIgnorePlacement: true,
          ),
          filter: MapStyle.clusterFilter,
        ),
        layer: MapStyle.clusterCountLayer,
      );
      await fresh(
        () => c.addSymbolLayer(
          MapStyle.placesSource,
          MapStyle.placesLayer,
          gl.SymbolLayerProperties(
            iconImage: const ['get', 'icon'],
            iconSize: MapLook.pinSize(_pinScale),
            iconAnchor: 'bottom',
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
            symbolSortKey: const ['get', 'rank'],
          ),
          filter: MapStyle.pointFilter,
        ),
        layer: MapStyle.placesLayer,
      );
      await fresh(
        () => c.addSymbolLayer(
          MapStyle.selectionSource,
          MapStyle.selectionPinLayer,
          _selectionLayer(_pinScale),
        ),
        layer: MapStyle.selectionPinLayer,
      );
      if (!current()) return;
      _ready = true;
      _sentPlaces = null;
      _sentSelected = null;
      _sentPoint = null;
      _scheduleSync();
      // The first camera rests without a move: report it, so the list beside
      // the map follows from the start.
      await _onCameraIdle();
    } on Object catch (e, st) {
      _log.warning('could not set up the map style', e, st);
    }
  }

  /// A removal that may find nothing to remove.
  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // Nothing of that id on this style: the add that follows is all.
    }
  }

  Future<void> _sync() async {
    final c = _controller;
    if (c == null || !_ready) return;
    final props = _props;
    if (!identical(props.places, _sentPlaces)) {
      _sentPlaces = props.places;
      await c.setGeoJsonSource(
        MapStyle.placesSource,
        await placesFeatureCollectionInBackground(props.places),
      );
    }
    if (props.selectedId != _sentSelected || props.markedPoint != _sentPoint) {
      _sentSelected = props.selectedId;
      _sentPoint = props.markedPoint;
      final selected = props.places.where((p) => p.id == props.selectedId).firstOrNull;
      await c.setGeoJsonSource(
        MapStyle.selectionSource,
        pointFeatureCollection(selected, point: props.markedPoint),
      );
      if (selected != null || props.markedPoint != null) await _popSelection(c);
    }
  }

  /// The selected pin grows into place with a spring's give, so the eye
  /// finds it.
  Future<void> _popSelection(gl.MapLibreMapController c) async {
    if (!mounted || Motion.reduced(context)) return;
    final full = _pinScale;
    const steps = [0.55, 0.8, 1.02, 1.08, 1.03, 1.0];
    for (final s in steps) {
      if (!mounted) return;
      await c.setLayerProperties(MapStyle.selectionPinLayer, _selectionLayer(full * s));
      await Future<void>.delayed(const Duration(milliseconds: 34));
    }
  }

  Future<void> _onTap(math.Point<double> point) async {
    final c = _controller;
    if (c == null || !_ready) return;
    // A finger is wider than a pin: look in a square around the tap.
    const slop = 14.0;
    final features = await c.queryRenderedFeaturesInRect(
      Rect.fromCenter(center: Offset(point.x, point.y), width: slop * 2, height: slop * 2),
      MapStyle.tappableLayers,
      null,
    );
    if (features.isEmpty) {
      _props.onEmptyTap?.call();
      return;
    }
    final feature = features.first as Map<Object?, Object?>;
    final geometry = feature['geometry'] as Map<Object?, Object?>?;
    final tap = mapTapFor(
      feature['properties'] as Map<Object?, Object?>?,
      geometry?['coordinates'] as List<Object?>?,
    );
    switch (tap) {
      case TapCluster(:final clusterId, :final at):
        final zoom = await c.getClusterExpansionZoom(MapStyle.placesSource, clusterId);
        await moveTo(at, zoom: zoom + 0.3);
      case TapPlace(:final id):
        _props.onPlaceTap(id);
      case TapNothing():
        break;
    }
  }

  Future<void> _onCameraIdle() async {
    final c = _controller;
    if (c == null) return;
    final region = await c.getVisibleRegion();
    final camera = c.cameraPosition;
    if (camera == null || !mounted) return;
    _props.onViewportChanged(
      MapViewport(
        bounds: GeoBounds(
          south: region.southwest.latitude,
          west: region.southwest.longitude,
          north: region.northeast.latitude,
          east: region.northeast.longitude,
        ),
        center: LatLng(camera.target.latitude, camera.target.longitude),
        zoom: camera.zoom,
      ),
    );
  }

  // LunaMapController

  @override
  Future<void> moveTo(LatLng center, {double? zoom}) async {
    // A move often follows a selection that opens a sheet: wait for the frame
    // that lays the sheet out, so the padding below is the new one.
    await WidgetsBinding.instance.endOfFrame;
    final c = _controller;
    if (c == null || !mounted) return;
    final z = zoom ?? c.cameraPosition?.zoom ?? 12;
    final target = centerForPadding(center, z, _props.padding);
    await c.animateCamera(
      gl.CameraUpdate.newLatLngZoom(gl.LatLng(target.lat, target.lon), z),
      duration: Motion.of(context, Motion.camera),
    );
  }

  @override
  Future<void> zoomBy(double delta) async {
    final c = _controller;
    if (c == null) return;
    await c.animateCamera(
      gl.CameraUpdate.zoomBy(delta),
      duration: Motion.of(context, Motion.medium),
    );
  }

  @override
  Future<void> fitBounds(GeoBounds bounds) async {
    final c = _controller;
    if (c == null) return;
    final p = _props.padding;
    await c.animateCamera(
      gl.CameraUpdate.newLatLngBounds(
        gl.LatLngBounds(
          southwest: gl.LatLng(bounds.south, bounds.west),
          northeast: gl.LatLng(bounds.north, bounds.east),
        ),
        left: p.left + 40,
        top: p.top + 40,
        right: p.right + 40,
        bottom: p.bottom + 40,
      ),
    );
  }

  @override
  Future<LatLng?> locateUser() async {
    final c = _controller;
    if (c == null) return null;
    if (!_locationOn && mounted) setState(() => _locationOn = true);
    try {
      final position = await c.requestMyLocationLatLng().timeout(const Duration(seconds: 12));
      return position == null ? null : LatLng(position.latitude, position.longitude);
    } on Object catch (e) {
      _log.info('no position: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = _props;
    if (kIsWeb) {
      placeWebMapControls(top: props.padding.top);
    }
    final inset = props.attributionInset;
    return gl.MapLibreMap(
      styleString: props.style,
      initialCameraPosition: gl.CameraPosition(
        target: gl.LatLng(props.initialCenter.lat, props.initialCenter.lon),
        zoom: props.initialZoom,
      ),
      trackCameraPosition: true,
      // No annotations: the places are layers of their own. The plugin's
      // annotation manager would add unused layers on every style load, and
      // races a style switch (the theme turning at sunset).
      annotationOrder: const [],
      myLocationEnabled: _locationOn,
      // North stays up: rotating a map by accident confuses more than it
      // helps when looking for a place to sleep.
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      attributionButtonPosition: gl.AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: math.Point(inset.left + 8, inset.bottom + 8),
      logoViewPosition: gl.LogoViewPosition.bottomLeft,
      logoViewMargins: math.Point(inset.left + 44, inset.bottom + 8),
      onMapCreated: (c) {
        _controller = c;
        props.onMapReady(this);
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: (point, _) => _onTap(point),
      // On the web the plugin reports a double click here, which also zooms:
      // the web long press comes from listenWebMapLongPress instead.
      onMapLongClick: kIsWeb
          ? null
          : (_, position) => _props.onLongPress(LatLng(position.latitude, position.longitude)),
      onCameraIdle: _onCameraIdle,
    );
  }
}
