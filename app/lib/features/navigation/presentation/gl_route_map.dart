import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

final _log = Logger('route_map');

/// The route map on Android, iOS and the web (maplibre_gl): the routes, the
/// restrictions and the vehicle as layers of their own over the basemap.
///
/// While guiding, the vehicle glides between fixes ([VehicleMotion]) and the
/// camera rides with it, frame by frame: tilted, turned to the course, the
/// vehicle in the lower part of the free map so the road ahead shows.
class GlRouteMap extends StatefulWidget {
  const new(this.props, {super.key});

  final RouteMapProps props;

  @override
  State<GlRouteMap> createState() => _GlRouteMapState();
}

class _GlRouteMapState extends State<GlRouteMap> with SingleTickerProviderStateMixin {
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

  // The drawn vehicle and the camera that rides with it.
  final _motion = VehicleMotion();
  final _clock = Stopwatch()..start();
  late final Ticker _ticker = createTicker((_) => _frame());
  bool _frameBusy = false;
  Duration _lastFrame = Duration.zero;
  double? _shownZoom;
  double _shownBearing = 0;
  EdgeInsets? _sentInsets;
  Size _size = Size.zero;

  /// Where the camera was when following began, and when: the first moments
  /// ease from that view into the driver's, instead of a cut.
  gl.CameraPosition? _entryFrom;
  Duration _entryStart = Duration.zero;

  /// The insets following asks for; during the entry they grow from none
  /// with the rest of the camera, so the view does not drop at once.
  EdgeInsets _followTarget = EdgeInsets.zero;
  static const _entry = Duration(milliseconds: 900);

  /// Native maps take each frame over a platform channel: 30 a second keeps
  /// the glide smooth without queueing calls. The browser's map is called
  /// directly and takes every frame.
  static const Duration _frameGap = kIsWeb ? Duration.zero : Duration(milliseconds: 33);

  /// A fix this far from the drawn vehicle is a jump (a new route from
  /// elsewhere), not a move to glide through.
  static const _jumpM = 500.0;

  /// The arrow is drawn at the screen's density. MapLibre on Android and
  /// iOS reads an image pixel as a physical one (maplibre_gl 0.27.1 makes
  /// the iOS image at the screen's scale), the web as a CSS pixel.
  double get _arrowScale => kIsWeb ? 1 / MediaQuery.devicePixelRatioOf(context) : 1;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

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
      final arrow = await vehicleArrowPng(MediaQuery.devicePixelRatioOf(context));
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
      _sentInsets = null;
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
    if (p.vehicle != _sentVehicle) {
      _sentVehicle = p.vehicle;
      final v = p.vehicle;
      if (v == null) {
        await c.setGeoJsonSource(RouteLayers.vehicleSource, vehicleCollection(null));
      } else if (mounted) {
        final shown = _motion.target;
        _motion.retarget(
          v.position,
          v.course,
          _clock.elapsed,
          jump: Motion.reduced(context) || (shown != null && shown.distanceTo(v.position) > _jumpM),
        );
        _startTicker();
      }
    }
    final camera = p.camera;
    if (camera is FollowCamera) {
      if (_sentCamera is! FollowCamera && mounted) {
        _entryFrom = Motion.reduced(context) ? null : c.cameraPosition;
        _entryStart = _clock.elapsed;
      }
      _sentCamera = camera;
      await _followInsets(c);
      _startTicker();
    } else if (camera != _sentCamera) {
      final wasFollowing = _sentCamera is FollowCamera;
      _sentCamera = camera;
      if (wasFollowing) {
        _sentInsets = EdgeInsets.zero;
        await c.updateContentInsets(EdgeInsets.zero);
        // The overview reads north up and flat, as the preview does: the
        // bounds below keep whatever tilt and bearing the map had.
        if (c.cameraPosition case final at?) {
          await c.moveCamera(
            gl.CameraUpdate.newCameraPosition(gl.CameraPosition(target: at.target, zoom: at.zoom)),
          );
        }
      }
      _shownZoom = null;
      await _moveCamera(c, camera);
    }
  }

  /// Starts the frames, the first one measured from now: after a pause
  /// (parked, a tunnel) the zoom must not catch up in one step.
  void _startTicker() {
    if (_ticker.isActive) return;
    _lastFrame = Duration.zero;
    _ticker.start();
  }

  /// While following, the camera's centre sits low in the free part of the
  /// map (under the banner, above the bar): the vehicle near the bottom,
  /// the road ahead above it.
  Future<void> _followInsets(gl.MapLibreMapController c) async {
    final pad = _props.padding;
    final free = math.max(0, _size.height - pad.top - pad.bottom);
    final insets = EdgeInsets.fromLTRB(pad.left, pad.top + free * 0.45, pad.right, pad.bottom);
    _followTarget = insets;
    // During the entry the frames move the insets along with the camera.
    if (insets == _sentInsets || _entryFrom != null) return;
    _sentInsets = insets;
    await c.updateContentInsets(insets);
  }

  /// One frame of the glide: the vehicle where [VehicleMotion] draws it,
  /// and the camera on it while following. A frame waits for the previous
  /// one's calls, so a slow map drops frames instead of queueing them.
  void _frame() {
    final c = _controller;
    final now = _clock.elapsed;
    if (c == null || !_ready || !mounted) {
      // No style yet (or a failed one): frames resume with the next sync.
      _ticker.stop();
      return;
    }
    if (_frameBusy || now - _lastFrame < _frameGap) return;
    final (position, course) = _motion.at(now);
    if (position == null) return;
    final dt = _lastFrame == Duration.zero ? Duration.zero : now - _lastFrame;
    _lastFrame = now;
    final camera = _props.camera;
    var settled = !_motion.movingAt(now);
    final calls = <Future<Object?>>[
      c.setGeoJsonSource(
        RouteLayers.vehicleSource,
        vehicleCollection(VehiclePuck(position: position, course: course)),
      ),
    ];
    if (camera is FollowCamera) {
      final wanted = camera.zoom;
      final shownZoom = _shownZoom;
      var zoom = shownZoom == null ? wanted : easeZoom(shownZoom, wanted, dt);
      _shownZoom = zoom;
      if ((wanted - zoom).abs() > 0.01) settled = false;
      if (course != null) _shownBearing = course;
      var target = position;
      var bearing = _shownBearing;
      var tilt = followTiltDeg;
      // Into following: from the view the user had to the driver's.
      if (_entryFrom case final from?) {
        final t = (now - _entryStart).inMicroseconds / _entry.inMicroseconds;
        if (t >= 1) {
          _entryFrom = null;
          _sentInsets = _followTarget;
          calls.add(c.updateContentInsets(_followTarget));
        } else {
          settled = false;
          final k = Motion.standard.transform(t.clamp(0, 1).toDouble());
          final a = from.target;
          target = LatLng(
            a.latitude + (position.lat - a.latitude) * k,
            a.longitude + (position.lon - a.longitude) * k,
          );
          zoom = from.zoom + (zoom - from.zoom) * k;
          bearing = (from.bearing + angleDelta(from.bearing, bearing) * k) % 360;
          tilt = from.tilt + (followTiltDeg - from.tilt) * k;
          calls.add(c.updateContentInsets(EdgeInsets.lerp(EdgeInsets.zero, _followTarget, k)!));
        }
      }
      calls.add(
        c.moveCamera(
          gl.CameraUpdate.newCameraPosition(
            gl.CameraPosition(
              target: gl.LatLng(target.lat, target.lon),
              zoom: zoom,
              bearing: bearing,
              tilt: tilt,
            ),
          ),
        ),
      );
    }
    _frameBusy = true;
    unawaited(
      Future.wait(calls)
          .then<void>((_) {})
          .catchError((Object e, StackTrace st) => _log.warning('route map frame failed', e, st))
          .whenComplete(() => _frameBusy = false),
    );
    if (settled) _ticker.stop();
  }

  Future<void> _moveCamera(gl.MapLibreMapController c, RouteCamera camera) async {
    if (!mounted || camera is! FitCamera) return;
    final pad = _props.padding;
    final bounds = camera.bounds;
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
  }

  /// A mark first (a place, a station, a stop), then another route.
  Future<void> _onTap(math.Point<double> point, gl.LatLng at) async {
    final c = _controller;
    if (c == null || !_ready || !mounted) return;
    // The tap's point is in the engine's units, physical pixels on Android.
    final scale = mapQueryScale(
      web: kIsWeb,
      platform: defaultTargetPlatform,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    Rect box(double slop) => Rect.fromCenter(
      center: Offset(point.x, point.y),
      width: slop * 2 * scale,
      height: slop * 2 * scale,
    );
    final onMarkTap = _props.onMarkTap;
    if (onMarkTap != null) {
      final marks = await featuresAroundTap(
        (slop) => c.queryRenderedFeaturesInRect(box(slop), const [RouteLayers.marks], null),
      );
      for (final f in marks) {
        final properties = (f as Map<Object?, Object?>)['properties'];
        final id = properties is Map<Object?, Object?> ? properties['id'] : null;
        if (id is String) {
          onMarkTap(id);
          return;
        }
      }
    }
    final onLineTap = _props.onLineTap;
    if (onLineTap != null) {
      final features = await featuresAroundTap(
        (slop) => c.queryRenderedFeaturesInRect(box(slop), const [
          RouteLayers.alternatives,
          RouteLayers.alternativesCasing,
        ], null),
      );
      if (features.isNotEmpty) {
        final properties = (features.first as Map<Object?, Object?>)['properties'];
        final index = properties is Map<Object?, Object?> ? properties['index'] : null;
        if (index is num) onLineTap(index.toInt());
        return;
      }
    }
    final onEmptyTap = _props.onEmptyTap;
    if (onEmptyTap == null || !mounted) return;
    final zoom = (await c.queryCameraPosition())?.zoom;
    if (zoom == null || !mounted) return;
    onEmptyTap(LatLng(at.latitude, at.longitude), zoom);
  }

  @override
  Widget build(BuildContext context) {
    final p = _props;
    final camera = p.camera;
    final start = switch (camera) {
      FitCamera(:final bounds) => bounds.center,
      FollowCamera(:final position) => position,
    };
    final following = camera is FollowCamera;
    final map = gl.MapLibreMap(
      styleString: p.style,
      initialCameraPosition: gl.CameraPosition(
        target: gl.LatLng(start.lat, start.lon),
        zoom: following ? camera.zoom : 12,
        tilt: following ? followTiltDeg : 0,
      ),
      trackCameraPosition: true,
      annotationOrder: const [],
      compassEnabled: false,
      // While following, the camera rides with the vehicle and a drag
      // would be undone at the next frame: the overview frees the map.
      // The preview keeps north up.
      rotateGesturesEnabled: false,
      scrollGesturesEnabled: !following,
      zoomGesturesEnabled: !following,
      tiltGesturesEnabled: false,
      attributionButtonPosition: gl.AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: math.Point(p.padding.left + 8, p.padding.bottom + 8),
      logoViewPosition: gl.LogoViewPosition.bottomLeft,
      logoViewMargins: math.Point(p.padding.left + 44, p.padding.bottom + 8),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: kIsWeb && p.onLineTap == null && p.onMarkTap == null && p.onEmptyTap == null
          ? null
          : _onTap,
      onMapLongClick: p.onLongPress == null
          ? null
          : (_, at) => p.onLongPress!(LatLng(at.latitude, at.longitude)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (size != _size) {
          _size = size;
          // The follow camera's insets follow the map's height.
          if (following) WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
        }
        return map;
      },
    );
  }
}
