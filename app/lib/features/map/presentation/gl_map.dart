import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/domain/style_diff.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/presentation/gl_poi_layers.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/basemap_icons.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

final _log = Logger('map');

/// The map on Android, iOS and the web: maplibre_gl (MapLibre Native, and
/// MapLibre GL JS in the browser). Online the places come from the API's
/// vector tiles ([GlPlaceTiles]); offline from one clustered GeoJSON source
/// of the places the device holds. Never one widget per place.
class GlLunaMap extends StatefulWidget {
  const new(this.props, {super.key});

  final LunaMapProps props;

  @override
  State<GlLunaMap> createState() => _GlLunaMapState();
}

class _GlLunaMapState extends State<GlLunaMap> implements LunaMapController {
  gl.MapLibreMapController? _controller;
  bool _ready = false;

  /// The style the map widget is given: the one loaded whole. A change of
  /// theme on Android and iOS keeps it and turns the colours in place
  /// ([StyleDiff]); the browser does the same inside MapLibre GL JS
  /// (`web/lunaway_maplibre.js`), so the web passes every style on.
  late String _style = widget.props.style;

  /// The style the map shows: [_style], or the one a change in place
  /// turned it into.
  late String _shown = widget.props.style;

  /// The first view still has to be fitted to the region. Decided when the
  /// map is made, not read from the props at style load: the map can
  /// report its first camera (which ends `fitInitial`) before a slow first
  /// setup reaches the fit. In the tours on the emulator and the iOS
  /// simulator, whose setup a theme and language change slows, France
  /// stayed at the default camera.
  late bool _fitPending = widget.props.fitInitial;

  bool _locationOn = false;

  // What the style currently holds, to send only what changed.
  List<PlaceSummary>? _sentPlaces;
  Object? _sentSelected;
  LatLng? _sentPoint;
  bool? _sentDark;

  // Updates run one after the other: a newer one never races an older one.
  Future<void> _queue = Future.value();

  // The points of interest: their source, layers and selection.
  final _poi = GlPoiLayers();

  // The places from the tiles.
  final _tiles = GlPlaceTiles();

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
    if (_props.style != _shown) _restyle(_props.style);
    _scheduleSync();
  }

  /// Brings the map to [style]: in place when only colours and the sprite
  /// differ and the map runs on MapLibre Native, whole otherwise.
  void _restyle(String style) {
    if (kIsWeb) {
      // MapLibre GL JS diffs the new style against the loaded one and keeps
      // the app's sources, layers and images (`web/lunaway_maplibre.js`);
      // when it cannot, it loads the style whole and the map sets itself up
      // again on its style event.
      setState(() => _style = _shown = style);
      return;
    }
    final diff = _ready ? StyleDiff.between(_shown, style) : null;
    if (diff == null) {
      setState(() {
        _style = _shown = style;
        // The new style drops every source and layer; they come back on load.
        _ready = false;
        _forgetSent();
      });
      return;
    }
    _shown = style;
    final dark = _props.dark;
    _queue = _queue
        .then((_) => _applyInPlace(diff, dark: dark))
        .catchError((Object e, StackTrace st) => _log.warning('the theme did not turn', e, st));
  }

  /// Sets the paint properties the new style changes, then the basemap's
  /// icons of its sprite, which MapLibre Native keeps from the loaded style.
  Future<void> _applyInPlace(StyleDiff diff, {required bool dark}) async {
    final c = _controller;
    if (c == null || !_ready) return;
    await Future.wait([
      for (final MapEntry(key: layer, value: paint) in diff.paint.entries)
        _quietly(() => c.setLayerProperties(layer, RawLayerProperties(paint))),
    ]);
    if (!diff.changesSprite || !mounted) return;
    final icons = await BasemapIcons.load(
      dark: dark,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    await Future.wait([for (final e in icons.entries) _quietly(() => c.addImage(e.key, e.value))]);
  }

  void _forgetSent() {
    _sentPlaces = null;
    _sentSelected = null;
    _sentPoint = null;
    _sentDark = null;
    _poi.forget();
    _tiles.forget();
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
    // Both native plugins read an image pixel as a physical one: Android
    // directly, iOS through the UIImage it makes at the screen's scale.
    final native =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return (native ? MediaQuery.devicePixelRatioOf(context) : 1) / _ratio;
  }

  gl.SymbolLayerProperties _selectionLayer(double size) => gl.SymbolLayerProperties(
    iconImage: const ['get', 'icon'],
    iconSize: size,
    iconAnchor: 'bottom',
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );

  /// The clusters' colours, which follow the theme.
  static Map<String, Object?> _clusterPaint({required bool dark}) => {
    'circle-color': MapLook.clusterFill(dark: dark),
    'circle-stroke-color': MapLook.clusterStroke(dark: dark),
  };

  /// Counts style loads: a theme or language switch loads a new style while
  /// the setup of the previous one may still be adding its layers.
  int _styleLoads = 0;

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || !mounted) return;
    if (kIsWeb) _stopWebLongPress ??= listenWebMapLongPress(_onWebLongPress);
    final load = ++_styleLoads;
    _ready = false;
    _forgetSent();
    // A newer style load takes over: this one stops at its next step.
    bool current() => mounted && load == _styleLoads;
    final dark = _props.dark;
    try {
      final images = await PinSprites.load(_ratio);
      // The images go in together: the engine queues each call, and one at a
      // time waits a round trip for each of the hundred pins.
      if (!current()) return;
      await Future.wait([for (final e in images.entries) c.addImage(e.key, e.value)]);
      // The one call an older setup had in flight may already have added a
      // layer or a source to this style: each is removed before it is added.
      Future<void> fresh(Future<void> Function() add, {String? layer, String? source}) async {
        if (!current()) return;
        if (layer != null) await _quietly(() => c.removeLayer(layer));
        if (source != null) await _quietly(() => c.removeSource(source));
        if (!current()) return;
        await add();
      }

      // The points of interest go under the places: the night spots keep
      // the map.
      if (_props.pois case final pois?) {
        await _poi.installBelowPlaces(
          c,
          pois,
          pinScale: _pinScale,
          current: current,
          dark: dark,
          below: PoiMapStyle.firstLabelLayer(_shown),
        );
      }
      if (_props.placeTiles case final tiles?) {
        await _tiles.install(c, tiles, pinScale: _pinScale, dark: dark, current: current);
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
            // The iOS plugin crashes on any expression that writes a number
            // as text (`to-string`, `concat`, `number-format`; measured on
            // the simulator, 2026-10-06): there the count stays a number.
            textField: defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb
                ? const ['get', 'point_count']
                : MapLook.clusterLabel(_props.language),
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
      if (_props.pois != null) {
        await _poi.installSelection(c, pinScale: _pinScale, current: current);
      }
      if (!current()) return;
      if (_fitPending) {
        final size = mounted ? context.size : null;
        if (size != null) {
          _fitPending = false;
          final camera = cameraForBounds(
            GeoBounds.metropolitanFrance,
            size,
            _props.padding + const EdgeInsets.all(16),
          );
          await c.moveCamera(
            gl.CameraUpdate.newLatLngZoom(
              gl.LatLng(camera.center.lat, camera.center.lon),
              camera.zoom,
            ),
          );
        }
      }
      if (!current()) return;
      _ready = true;
      _sentPlaces = null;
      _sentSelected = null;
      _sentPoint = null;
      _sentDark = dark;
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
    final tiles = props.placeTiles;
    if (tiles != null && !_tiles.installed) {
      // Online again: the tiles come back under the device's places.
      await _tiles.install(
        c,
        tiles,
        pinScale: _pinScale,
        dark: props.dark,
        current: () => mounted && _ready,
        below: MapStyle.clustersLayer,
      );
    } else if (tiles == null && _tiles.installed) {
      await _tiles.remove(c);
    } else if (tiles != null) {
      await _tiles.sync(c, tiles, dark: props.dark);
    }
    if (!identical(props.places, _sentPlaces)) {
      _sentPlaces = props.places;
      await c.setGeoJsonSource(
        MapStyle.placesSource,
        await placesFeatureCollectionInBackground(props.places),
      );
    }
    if (_sentDark != props.dark) {
      _sentDark = props.dark;
      await c.setLayerProperties(
        MapStyle.clustersLayer,
        RawLayerProperties(_clusterPaint(dark: props.dark)),
      );
      await c.setLayerProperties(
        MapStyle.clusterCountLayer,
        RawLayerProperties({'text-color': MapLook.clusterText(dark: props.dark)}),
      );
      if (props.pois != null) {
        await _quietly(
          () => c.setLayerProperties(
            PoiMapStyle.fuelLayerId,
            RawLayerProperties({
              'text-color': PoiMapStyle.fuelTextColor(dark: props.dark),
              'text-halo-color': PoiMapStyle.fuelHalo(dark: props.dark),
            }),
          ),
        );
      }
    }
    final selected = props.selectedPlace;
    final selectedKey = selected == null
        ? null
        : (selected.id, selected.lat, selected.lon, selected.kind, selected.overnight);
    if (selectedKey != _sentSelected || props.markedPoint != _sentPoint) {
      final sameId =
          selected != null &&
          _sentSelected is (String, double, double, Object, Object) &&
          (_sentSelected! as (String, double, double, Object, Object)).$1 == selected.id;
      _sentSelected = selectedKey;
      _sentPoint = props.markedPoint;
      await c.setGeoJsonSource(
        MapStyle.selectionSource,
        pointFeatureCollection(selected, point: props.markedPoint),
      );
      // A place read after its tap redraws its pin without a second pop.
      if ((selected != null && !sameId) || props.markedPoint != null) await _popSelection(c);
    }
    if (props.pois case final pois?) await _poi.sync(c, pois, pinScale: _pinScale);
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
      [
        ...MapStyle.tappableLayers,
        if (_tiles.installed) ...PlaceTiles.tappable,
        if (_props.pois != null) ...PoiMapStyle.tappable,
      ],
      null,
    );
    if (features.isEmpty) {
      _props.onEmptyTap?.call();
      return;
    }
    // Topmost first: the first feature that means something decides.
    for (final raw in features) {
      final feature = raw as Map<Object?, Object?>;
      final geometry = feature['geometry'] as Map<Object?, Object?>?;
      final properties = feature['properties'] as Map<Object?, Object?>?;
      final coordinates = geometry?['coordinates'] as List<Object?>?;
      switch (mapTapFor(properties, coordinates)) {
        case TapCluster(:final clusterId, :final at):
          final zoom = await c.getClusterExpansionZoom(MapStyle.placesSource, clusterId);
          await moveTo(at, zoom: zoom + 0.3);
          return;
        case TapPlace(:final id):
          _props.onPlaceTap(
            id,
            hint: _props.places.where((p) => p.id == id).firstOrNull ?? _props.selectedPlace,
          );
          return;
        case TapNothing():
          break;
      }
      switch (placeTileTapFor(properties, coordinates)) {
        case OpenTilePlace(:final place):
          _props.onPlaceTap(place.id, hint: place);
          return;
        case ZoomToTileDot(:final at):
          await moveTo(at, zoom: zoomForDot((await c.queryCameraPosition())?.zoom ?? 6));
          return;
        case null:
          break;
      }
      switch (poiTapFor(properties, coordinates)) {
        case TapPoi(:final feature):
          _props.onPoiTap?.call(feature);
          return;
        case TapPoiDot(:final lat, :final lon):
          final zoom = (await c.queryCameraPosition())?.zoom ?? 10;
          await moveTo(LatLng(lat, lon), zoom: math.min(zoom + 2, PoiMapStyle.pointsMinZoom + 0.5));
          return;
        case null:
          break;
      }
      // The marker of a long-pressed point: its details are already open.
      if (properties?['kind'] == 'point') return;
    }
  }

  /// Reports the points and the places under the view once the map rests
  /// after a move or a change of chip.
  Future<void> _onMapIdle() async {
    final c = _controller;
    if (c == null || !_ready) return;
    final camera = await c.queryCameraPosition();
    if (camera == null || !mounted) return;
    final key = (camera.target.latitude, camera.target.longitude, camera.zoom);
    final pois = _props.pois;
    final reportPois = _props.onPoisInView;
    if (pois != null && reportPois != null) {
      try {
        final found = await _poi.probe(c, pois, zoom: camera.zoom, camera: key);
        if (found != null && mounted) reportPois(found);
      } on Object catch (e) {
        _log.info('could not read the points in view: $e');
      }
    }
    final reportPlaces = _props.onPlacesInView;
    if (_tiles.installed && reportPlaces != null) {
      try {
        final found = await _tiles.probe(c, zoom: camera.zoom, camera: key);
        if (found != null && mounted) reportPlaces(found);
      } on Object catch (e) {
        _log.info('could not read the places in view: $e');
      }
    }
  }

  Future<void> _onCameraIdle() async {
    final c = _controller;
    if (c == null) return;
    final region = await c.getVisibleRegion();
    final camera = await c.queryCameraPosition();
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
    final z = zoom ?? (await c.queryCameraPosition())?.zoom ?? 12;
    if (!mounted) return;
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
    if (c == null || !mounted) return;
    final size = context.size;
    if (size == null) return;
    final camera = cameraForBounds(bounds, size, _props.padding + const EdgeInsets.all(40));
    await c.animateCamera(
      gl.CameraUpdate.newLatLngZoom(gl.LatLng(camera.center.lat, camera.center.lon), camera.zoom),
      duration: Motion.of(context, Motion.camera),
    );
  }

  @override
  Future<LatLng?> locateUser() async {
    final c = _controller;
    if (c == null) return null;
    if (!_locationOn && mounted) setState(() => _locationOn = true);
    // The native location layer starts with the rebuild that turns it on,
    // and answers nothing before: asked again until a position comes, for
    // twelve seconds at most. The first locate of a run (at launch, or the
    // first touch of the button) otherwise came back empty.
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (mounted && DateTime.now().isBefore(end)) {
      try {
        final position = await c.requestMyLocationLatLng().timeout(const Duration(seconds: 3));
        if (position != null) return LatLng(position.latitude, position.longitude);
      } on Object catch (e) {
        _log.fine('no position yet: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _log.info('no position within 12 s');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final props = _props;
    if (kIsWeb) {
      placeWebMapControls(top: props.padding.top);
    }
    final inset = props.attributionInset;
    return gl.MapLibreMap(
      styleString: _style,
      initialCameraPosition: gl.CameraPosition(
        target: gl.LatLng(props.initialCenter.lat, props.initialCenter.lon),
        zoom: props.initialZoom,
      ),
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
      // Every tap comes to onMapClick, on a layer's feature too: the plugins
      // otherwise send a tap on any layer they count as interactive (the
      // pins, the points of interest) to onFeatureTapped only, which
      // _onTap's own query replaces.
      featureTapsTriggersMapClick: true,
      // On the web the plugin reports a double click here, which also zooms:
      // the web long press comes from listenWebMapLongPress instead.
      onMapLongClick: kIsWeb
          ? null
          : (_, position) => _props.onLongPress(LatLng(position.latitude, position.longitude)),
      // The camera is read when the map rests (queryCameraPosition), never
      // tracked: tracking sends every frame of a pan across the platform
      // channel, for a position nothing reads during the move.
      onCameraIdle: _onCameraIdle,
      onMapIdle: _onMapIdle,
    );
  }
}
