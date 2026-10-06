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
import 'package:lunaway/features/map/presentation/pin_images.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;
import 'package:permission_handler/permission_handler.dart';

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

  static Future<Map<String, Uint8List>>? _images;

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
    if (old.props.styleUrl != _props.styleUrl) {
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

  /// MapLibre Android reads an image pixel as a physical pixel; elsewhere
  /// as a logical one.
  double get _imageScale => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? MediaQuery.devicePixelRatioOf(context)
      : 1;

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || !mounted) return;
    if (kIsWeb) _stopWebLongPress ??= listenWebMapLongPress(_onWebLongPress);
    try {
      final images = await (_images ??= renderPinImages());
      for (final e in images.entries) {
        await c.addImage(e.key, e.value);
      }
      const empty = {'type': 'FeatureCollection', 'features': <Object>[]};
      await c.addSource(
        MapStyle.placesSource,
        const gl.GeojsonSourceProperties(
          data: empty,
          cluster: true,
          clusterRadius: MapStyle.clusterRadius,
          clusterMaxZoom: MapStyle.clusterMaxZoom,
        ),
      );
      await c.addSource(MapStyle.selectionSource, const gl.GeojsonSourceProperties(data: empty));
      await c.addCircleLayer(
        MapStyle.placesSource,
        MapStyle.clustersLayer,
        const gl.CircleLayerProperties(
          circleColor: MapLook.clusterFill,
          circleRadius: MapLook.clusterRadius,
          circleStrokeWidth: MapLook.clusterStrokeWidth,
          circleStrokeColor: MapLook.clusterStroke,
          circleOpacity: MapLook.clusterOpacity,
        ),
        filter: MapStyle.clusterFilter,
      );
      await c.addSymbolLayer(
        MapStyle.placesSource,
        MapStyle.clusterCountLayer,
        const gl.SymbolLayerProperties(
          textField: ['get', 'point_count_abbreviated'],
          textFont: MapLook.clusterFont,
          textSize: MapLook.clusterTextSize,
          textColor: MapLook.clusterText,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        filter: MapStyle.clusterFilter,
      );
      await c.addSymbolLayer(
        MapStyle.placesSource,
        MapStyle.placesLayer,
        gl.SymbolLayerProperties(
          iconImage: const ['get', 'icon'],
          iconSize: MapLook.pinSize(_imageScale),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          symbolSortKey: ['get', 'rank'],
        ),
        filter: MapStyle.pointFilter,
      );
      await c.addCircleLayer(
        MapStyle.selectionSource,
        MapStyle.selectionHaloLayer,
        const gl.CircleLayerProperties(
          circleRadius: MapLook.selectionHaloRadius,
          circleColor: MapLook.selection,
          circleOpacity: MapLook.selectionHaloOpacity,
          circleStrokeColor: MapLook.selection,
          circleStrokeWidth: MapLook.selectionStrokeWidth,
        ),
      );
      await c.addSymbolLayer(
        MapStyle.selectionSource,
        MapStyle.selectionPinLayer,
        gl.SymbolLayerProperties(
          iconImage: const ['get', 'icon'],
          iconSize: MapLook.selectedPinSize(_imageScale),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
      _ready = true;
      _scheduleSync();
      // The first camera rests without a move: report it, so the list beside
      // the map follows from the start.
      await _onCameraIdle();
    } on Object catch (e, st) {
      _log.warning('could not set up the map style', e, st);
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
    if (features.isEmpty) return;
    final feature = features.first as Map<Object?, Object?>;
    final properties = (feature['properties'] as Map<Object?, Object?>?) ?? const {};
    if (properties.containsKey('point_count')) {
      final clusterId = (properties['cluster_id']! as num).toInt();
      final zoom = await c.getClusterExpansionZoom(MapStyle.placesSource, clusterId);
      final coordinates =
          (feature['geometry']! as Map<Object?, Object?>)['coordinates']! as List<Object?>;
      await moveTo(
        LatLng((coordinates[1]! as num).toDouble(), (coordinates[0]! as num).toDouble()),
        zoom: zoom + 0.3,
      );
    } else if (properties['id'] case final String id) {
      _props.onPlaceTap(id);
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
      duration: Motion.camera,
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // MapLibre Android shows the position but does not ask for the
      // permission; MapLibre iOS asks by itself.
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return null;
    }
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
    if (kIsWeb) placeWebMapControls(top: props.padding.top);
    return gl.MapLibreMap(
      styleString: props.styleUrl,
      initialCameraPosition: gl.CameraPosition(
        target: gl.LatLng(props.initialCenter.lat, props.initialCenter.lon),
        zoom: props.initialZoom,
      ),
      trackCameraPosition: true,
      myLocationEnabled: _locationOn,
      compassViewPosition: gl.CompassViewPosition.topRight,
      compassViewMargins: math.Point(12, props.padding.top + 8),
      attributionButtonPosition: gl.AttributionButtonPosition.topRight,
      attributionButtonMargins: math.Point(12, props.padding.top + 60),
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
