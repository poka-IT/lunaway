import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

final _log = Logger('route_map');

/// The route map on Android, iOS and the web (maplibre_gl): the routes, the
/// restrictions and the vehicle as layers of their own over the basemap.
class GlRouteMap extends StatefulWidget {
  const new(this.props, {super.key});

  final RouteMapProps props;

  @override
  State<GlRouteMap> createState() => _GlRouteMapState();
}

class _GlRouteMapState extends State<GlRouteMap> {
  gl.MapLibreMapController? _controller;
  bool _ready = false;
  int _styleLoads = 0;

  // One update runs at a time and sends the latest state: at a fix a
  // second, a queue of every intermediate state would drift behind.
  bool _syncing = false;
  bool _dirty = false;

  // What the style holds, to send only what changed.
  List<RouteMapLine>? _sentLines;
  List<RouteMapMark>? _sentMarks;
  VehiclePuck? _sentVehicle;
  RouteCamera? _sentCamera;

  RouteMapProps get _props => widget.props;

  /// The arrow is drawn at the screen's density. MapLibre on Android and
  /// iOS reads an image pixel as a physical one (maplibre_gl 0.27.1 makes
  /// the iOS image at the screen's scale), the web as a CSS pixel.
  double get _arrowScale => kIsWeb ? 1 / MediaQuery.devicePixelRatioOf(context) : 1;

  @override
  void didUpdateWidget(GlRouteMap old) {
    super.didUpdateWidget(old);
    if (old.props.style != _props.style) {
      _ready = false;
      _sentLines = null;
      _sentMarks = null;
      _sentVehicle = null;
    }
    _schedule();
  }

  void _schedule() {
    _dirty = true;
    if (_syncing) return;
    _syncing = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_dirty && mounted) {
        _dirty = false;
        await _sync();
      }
    } on Object catch (e, st) {
      _log.warning('route map update failed', e, st);
    } finally {
      _syncing = false;
    }
  }

  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // Nothing of that id on this style.
    }
  }

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || !mounted) return;
    final load = ++_styleLoads;
    bool current() => mounted && load == _styleLoads;
    _ready = false;
    final dark = _props.dark;
    const empty = {'type': 'FeatureCollection', 'features': <Object>[]};
    try {
      final arrow = await _vehicleArrow(MediaQuery.devicePixelRatioOf(context));
      if (!current()) return;
      await c.addImage(RouteLayers.vehicleImage, arrow);
      for (final id in [
        RouteLayers.vehicle,
        RouteLayers.marks,
        RouteLayers.route,
        RouteLayers.routeCasing,
        RouteLayers.alternatives,
        RouteLayers.alternativesCasing,
      ]) {
        await _quietly(() => c.removeLayer(id));
      }
      for (final id in [
        RouteLayers.alternativesSource,
        RouteLayers.routeSource,
        RouteLayers.marksSource,
        RouteLayers.vehicleSource,
      ]) {
        if (!current()) return;
        await _quietly(() => c.removeSource(id));
        await c.addSource(id, const gl.GeojsonSourceProperties(data: empty));
      }
      if (!current()) return;
      const round = gl.LineLayerProperties(lineJoin: 'round', lineCap: 'round');
      await c.addLineLayer(
        RouteLayers.alternativesSource,
        RouteLayers.alternativesCasing,
        round.copyWith(
          gl.LineLayerProperties(
            lineColor: RouteLook.alternativeCasing(dark: dark),
            lineWidth: RouteLook.alternativeWidth + 3,
          ),
        ),
      );
      await c.addLineLayer(
        RouteLayers.alternativesSource,
        RouteLayers.alternatives,
        round.copyWith(
          gl.LineLayerProperties(
            lineColor: RouteLook.alternative(dark: dark),
            lineWidth: RouteLook.alternativeWidth,
          ),
        ),
      );
      await c.addLineLayer(
        RouteLayers.routeSource,
        RouteLayers.routeCasing,
        round.copyWith(
          gl.LineLayerProperties(
            lineColor: RouteLook.casing(dark: dark),
            lineWidth: RouteLook.casingWidth,
          ),
        ),
      );
      await c.addLineLayer(
        RouteLayers.routeSource,
        RouteLayers.route,
        round.copyWith(
          gl.LineLayerProperties(
            lineColor: RouteLook.line(dark: dark),
            lineWidth: RouteLook.lineWidth,
          ),
        ),
      );
      await c.addCircleLayer(
        RouteLayers.marksSource,
        RouteLayers.marks,
        gl.CircleLayerProperties(
          circleColor: const ['get', 'fill'],
          circleRadius: const ['get', 'radius'],
          circleStrokeColor: RouteLook.markStroke,
          circleStrokeWidth: RouteLook.markStrokeWidth,
        ),
      );
      await c.addSymbolLayer(
        RouteLayers.vehicleSource,
        RouteLayers.vehicle,
        gl.SymbolLayerProperties(
          iconImage: RouteLayers.vehicleImage,
          iconSize: _arrowScale,
          iconRotate: const ['get', 'course'],
          iconRotationAlignment: 'map',
          iconPitchAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
      if (!current()) return;
      _ready = true;
      _sentLines = null;
      _sentMarks = null;
      _sentVehicle = null;
      _sentCamera = null;
      _schedule();
    } on Object catch (e, st) {
      _log.warning('could not set up the route layers', e, st);
    }
  }

  Future<void> _sync() async {
    final c = _controller;
    if (c == null || !_ready || !mounted) return;
    final p = _props;
    if (!listEquals(p.lines, _sentLines)) {
      _sentLines = p.lines;
      await c.setGeoJsonSource(
        RouteLayers.alternativesSource,
        routeLinesCollection(p.lines, selected: false),
      );
      await c.setGeoJsonSource(
        RouteLayers.routeSource,
        routeLinesCollection(p.lines, selected: true),
      );
    }
    if (!listEquals(p.marks, _sentMarks)) {
      _sentMarks = p.marks;
      await c.setGeoJsonSource(RouteLayers.marksSource, routeMarksCollection(p.marks));
    }
    if (!identical(p.vehicle, _sentVehicle)) {
      _sentVehicle = p.vehicle;
      await c.setGeoJsonSource(RouteLayers.vehicleSource, vehicleCollection(p.vehicle));
    }
    if (p.camera != _sentCamera) {
      final previous = _sentCamera;
      _sentCamera = p.camera;
      await _moveCamera(c, p.camera, follow: previous is FollowCamera);
    }
  }

  Future<void> _moveCamera(
    gl.MapLibreMapController c,
    RouteCamera camera, {
    required bool follow,
  }) async {
    if (!mounted) return;
    final pad = _props.padding;
    switch (camera) {
      case FitCamera(:final bounds):
        await c.animateCamera(
          gl.CameraUpdate.newLatLngBounds(
            gl.LatLngBounds(
              southwest: gl.LatLng(bounds.south, bounds.west),
              northeast: gl.LatLng(bounds.north, bounds.east),
            ),
            left: pad.left + 48,
            top: pad.top + 48,
            right: pad.right + 48,
            bottom: pad.bottom + 48,
          ),
          duration: Motion.of(context, Motion.camera),
        );
      case FollowCamera(:final position, :final course, :final zoom):
        final update = gl.CameraUpdate.newCameraPosition(
          gl.CameraPosition(
            target: gl.LatLng(position.lat, position.lon),
            zoom: zoom,
            bearing: course ?? c.cameraPosition?.bearing ?? 0,
            tilt: 45,
          ),
        );
        // A fix a second: the camera glides from one to the next instead of
        // jumping, which reads calmer at the wheel. Not awaited: the next
        // fix's glide takes over from this one.
        unawaited(
          c.animateCamera(
            update,
            duration: Motion.reduced(context)
                ? Duration.zero
                : follow
                ? const Duration(milliseconds: 950)
                : Motion.camera,
          ),
        );
    }
  }

  Future<void> _onTap(math.Point<double> point) async {
    final c = _controller;
    final onLineTap = _props.onLineTap;
    if (c == null || !_ready || onLineTap == null) return;
    const slop = 16.0;
    final features = await c.queryRenderedFeaturesInRect(
      Rect.fromCenter(center: Offset(point.x, point.y), width: slop * 2, height: slop * 2),
      const [RouteLayers.alternatives, RouteLayers.alternativesCasing],
      null,
    );
    if (features.isEmpty) return;
    final properties = (features.first as Map<Object?, Object?>)['properties'];
    final index = properties is Map<Object?, Object?> ? properties['index'] : null;
    if (index is num) onLineTap(index.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final p = _props;
    final camera = p.camera;
    final start = switch (camera) {
      FitCamera(:final bounds) => bounds.center,
      FollowCamera(:final position) => position,
    };
    return gl.MapLibreMap(
      styleString: p.style,
      initialCameraPosition: gl.CameraPosition(
        target: gl.LatLng(start.lat, start.lon),
        zoom: camera is FollowCamera ? camera.zoom : 12,
      ),
      trackCameraPosition: true,
      annotationOrder: const [],
      compassEnabled: false,
      // The guidance turns the map with the road; the preview keeps north up.
      rotateGesturesEnabled: camera is FollowCamera,
      tiltGesturesEnabled: false,
      attributionButtonPosition: gl.AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: math.Point(p.padding.left + 8, p.padding.bottom + 8),
      logoViewPosition: gl.LogoViewPosition.bottomLeft,
      logoViewMargins: math.Point(p.padding.left + 44, p.padding.bottom + 8),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: kIsWeb && p.onLineTap == null ? null : (point, _) => _onTap(point),
    );
  }
}

/// The vehicle's arrow, drawn once per screen density: a lantern-amber
/// chevron with a navy rim, pointing north (the layer turns it).
Future<Uint8List> _vehicleArrow(double ratio) async {
  final size = 30 * ratio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final path = Path()
    ..moveTo(size / 2, size * 0.08)
    ..lineTo(size * 0.86, size * 0.88)
    ..lineTo(size / 2, size * 0.68)
    ..lineTo(size * 0.14, size * 0.88)
    ..close();
  canvas
    ..drawPath(
      path,
      Paint()
        ..color = Palette.minuit
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * ratio
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(path, Paint()..color = Palette.lanterne);
  final image = await recorder.endRecording().toImage(size.ceil(), size.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
