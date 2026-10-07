import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';
import 'package:lunaway/features/map/presentation/web_map_pointer.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_mark_layers.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/palette.dart';
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

  /// Counts the taps and presses: a bare tap that waits (a finger in the
  /// browser) gives way to any that came after it.
  int _taps = 0;
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

  /// The arrow and the badges are drawn at the screen's density. MapLibre
  /// on Android and iOS reads an image pixel as a physical one (maplibre_gl
  /// 0.27.1 makes the iOS image at the screen's scale), the web as a CSS
  /// pixel.
  double get _imageScale => kIsWeb ? 1 / MediaQuery.devicePixelRatioOf(context) : 1;

  /// The marks lit, by index, as the engine has them; null when unknown
  /// (new data, a new style).
  Set<int>? _sentLit;
  int? _sentFocus;

  /// The plugin has no feature state on iOS: there the halo's filter names
  /// the lit marks.
  static bool get _litByFilter => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// What the browser's hover last reported over this map: a mark's id or
  /// a group's.
  String? _hovered;
  void Function()? _stopHover;

  /// A camera move was reported and has not come to rest.
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    // Only a browser has a pointer that hovers; the page picks what it is
    // over by the same rule as a click.
    _stopHover = listenWebMapHover(_onWebHover);
  }

  @override
  void dispose() {
    _stopHover?.call();
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
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final arrow = await vehicleArrowPng(ratio);
      final badges = await routeBadgePngs(ratio);
      if (!current()) return;
      await c.addImage(RouteLayers.vehicleImage, arrow);
      for (final MapEntry(:key, :value) in badges.entries) {
        await c.addImage(key, value);
      }
      for (final id in [
        RouteLayers.vehicle,
        ...RouteLayers.markLayers.reversed,
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
        ...RouteLayers.markSources,
        RouteLayers.vehicleSource,
      ]) {
        if (!current()) return;
        await _quietly(() => c.removeSource(id));
        final options = RouteMarkStyle.sourceOptions(id);
        await c.addSource(
          id,
          gl.GeojsonSourceProperties(
            data: empty,
            cluster: options['cluster'] as bool?,
            clusterRadius: options['clusterRadius'] as double?,
            clusterMaxZoom: options['clusterMaxZoom'] as double?,
            clusterProperties: options['clusterProperties'],
          ),
        );
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
        enableInteraction: false,
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
        enableInteraction: false,
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
        // The chosen route answers no click: no pointer over it.
        enableInteraction: false,
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
        enableInteraction: false,
      );
      for (final source in RouteLayers.markSources) {
        if (!current()) return;
        await _addMarkLayers(c, source);
      }
      await c.addSymbolLayer(
        RouteLayers.vehicleSource,
        RouteLayers.vehicle,
        gl.SymbolLayerProperties(
          iconImage: RouteLayers.vehicleImage,
          iconSize: _imageScale,
          iconRotate: const ['get', 'course'],
          iconRotationAlignment: 'map',
          iconPitchAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: false,
      );
      if (!current()) return;
      _ready = true;
      _sentLines = null;
      _sentMarks = null;
      _sentLit = null;
      _sentFocus = _props.focus?.serial;
      _sentVehicle = null;
      _sentCamera = null;
      _sentInsets = null;
      _schedule();
    } on Object catch (e, st) {
      _log.warning('could not set up the route layers', e, st);
    }
  }

  /// The layers of one source of marks, bottom to top: the lit ring, the
  /// badges with their text, and the text beside them. None is watched by
  /// the plugin: a tap and the pointer pick by [routeHitShapes].
  Future<void> _addMarkLayers(gl.MapLibreMapController c, String source) async {
    final minzoom = source == RouteLayers.minorSource ? RouteMarkStyle.minorMinZoom : null;
    await c.addCircleLayer(
      source,
      RouteLayers.haloOf(source),
      gl.CircleLayerProperties(
        circleRadius: RouteMarkStyle.haloRadius,
        circleColor: RouteLook.halo,
        circleStrokeColor: RouteLook.haloRim,
        circleStrokeWidth: 2,
        circleOpacity: _litByFilter ? 1 : RouteMarkStyle.haloOpacity,
        circleStrokeOpacity: _litByFilter ? 1 : RouteMarkStyle.haloOpacity,
      ),
      minzoom: minzoom,
      filter: _litByFilter ? _litFilter(const []) : RouteMarkStyle.notGroup,
      enableInteraction: false,
    );
    await c.addSymbolLayer(
      source,
      RouteLayers.badgesOf(source),
      gl.SymbolLayerProperties(
        iconImage: RouteMarkStyle.iconImage,
        iconSize: RouteMarkStyle.iconSize(_imageScale),
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: RouteMarkStyle.sortKey,
        textField: RouteMarkStyle.textField,
        textFont: RouteMarkStyle.font,
        textSize: RouteMarkStyle.textSize,
        textColor: RouteMarkStyle.textColor,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      minzoom: minzoom,
      enableInteraction: false,
    );
    await c.addSymbolLayer(
      source,
      RouteLayers.sideOf(source),
      gl.SymbolLayerProperties(
        textField: const ['get', 'side'],
        textFont: RouteMarkStyle.font,
        textSize: 11,
        textAnchor: 'left',
        textOffset: RouteMarkStyle.sideOffset,
        textOptional: true,
        textColor: RouteLook.hex(Palette.minuit),
        textHaloColor: RouteLook.hex(Palette.creme),
        textHaloWidth: 1.5,
      ),
      minzoom: minzoom,
      filter: RouteMarkStyle.sideFilter,
      enableInteraction: false,
    );
  }

  /// The halo's filter where marks are lit through it: those of [ids].
  static List<Object> _litFilter(List<int> ids) => [
    'all',
    RouteMarkStyle.notGroup,
    [
      'in',
      ['id'],
      ['literal', ids],
    ],
  ];

  /// Lights the marks of [highlighted] and puts out the others, sending
  /// only what changed.
  Future<void> _light(gl.MapLibreMapController c, Set<String> highlighted) async {
    final marks = _props.marks;
    final lit = {
      for (final (i, m) in marks.indexed)
        if (highlighted.contains(m.id)) i,
    };
    final sent = _sentLit;
    if (sent != null && setEquals(lit, sent)) return;
    final before = sent ?? const <int>{};
    _sentLit = lit;
    if (_litByFilter) {
      final bySource = <String, List<int>>{};
      for (final i in lit) {
        (bySource[routeMarkSource(marks[i])] ??= []).add(routeMarkFeatureId(i));
      }
      for (final s in RouteLayers.markSources) {
        await c.setFilter(RouteLayers.haloOf(s), _litFilter(bySource[s] ?? const []));
      }
      return;
    }
    for (final i in before.union(lit)) {
      if (i >= marks.length || lit.contains(i) == before.contains(i)) continue;
      await c.setFeatureState(routeMarkSource(marks[i]), '${routeMarkFeatureId(i)}', {
        'lit': lit.contains(i),
      });
    }
  }

  /// Brings the marks of [focus] into view, close enough that none is in a
  /// group, then pulses them: three beats of their ring, a handful of calls
  /// rather than a frame by frame animation.
  Future<void> _fly(gl.MapLibreMapController c, RouteMapFocus focus) async {
    final zoom = math.max(c.cameraPosition?.zoom ?? 0, RouteMarkStyle.clusterMaxZoom + 0.5);
    await c.animateCamera(
      gl.CameraUpdate.newLatLngZoom(gl.LatLng(focus.position.lat, focus.position.lon), zoom),
      duration: mounted ? Motion.of(context, Motion.camera) : Duration.zero,
    );
    if (!mounted || Motion.reduced(context)) return;
    final keep = _props.highlighted;
    for (var beat = 0; beat < 3; beat++) {
      if (!mounted || !_ready) return;
      await _light(c, {...keep, ...focus.marks});
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted || !_ready) return;
      await _light(c, keep.difference(focus.marks.toSet()));
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    if (mounted && _ready) await _light(c, _props.highlighted);
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
      for (final MapEntry(:key, :value) in routeMarkSources(p.marks).entries) {
        await c.setGeoJsonSource(key, value);
      }
      // The states and the halo's filter name features by their index in
      // the old marks: all put out, then lit again.
      if (!_litByFilter) {
        for (final s in RouteLayers.markSources) {
          await _quietly(() => c.removeFeatureState(s));
        }
      }
      _sentLit = null;
    }
    await _light(c, p.highlighted);
    if (p.focus case final focus? when focus.serial != _sentFocus) {
      _sentFocus = focus.serial;
      unawaited(_fly(c, focus));
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

  /// The engine's screen units per logical pixel, for its feature queries
  /// and the points of its taps: Android counts physical pixels.
  double get _queryScale => mapQueryScale(
    web: kIsWeb,
    platform: defaultTargetPlatform,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  /// The nearest badge or other route within reach of a tap ([nearestHit],
  /// [routeHitShapes]), and at street level one the tap just missed
  /// ([hitAroundTap]): a group zooms in until it opens, a mark reports
  /// itself, another route is chosen. Nothing in reach is a tap on bare map
  /// at [at]. Every mark is a target: none is a sign that opens nothing.
  Future<void> _onTap(math.Point<double> point, gl.LatLng at) async {
    final seq = ++_taps;
    final c = _controller;
    if (c == null || !_ready || !mounted) return;
    final scale = _queryScale;
    final tolerance = hitTolerance(webMapPointerKind());
    // Wide enough for the reach of a free point (FreeTap); the selection's
    // own tolerance is applied below.
    final reach = tolerance * FreeTap.wider;
    final box = Rect.fromCenter(
      center: Offset(point.x, point.y),
      width: reach * 2 * scale,
      height: reach * 2 * scale,
    );
    final layers = [
      ...RouteLayers.badges,
      if (_props.onLineTap != null) ...[RouteLayers.alternatives, RouteLayers.alternativesCasing],
    ];
    // One query per layer: the engines do not all say which layer a
    // feature was drawn by.
    final (answers, camera) = await (
      Future.wait([
        for (final layer in layers) c.queryRenderedFeaturesInRect(box, [layer], null),
      ]),
      c.queryCameraPosition(),
    ).wait;
    if (!mounted) return;
    final zoom = camera?.zoom;
    final features = [
      for (final (i, found) in answers.indexed)
        for (final f in found)
          if (f is Map) (layers[i], f),
    ];
    final positions = [
      for (final (_, f) in features) pointsOfGeometry(f['geometry'] as Map<Object?, Object?>?),
    ];
    // Projected by the engine: while guiding, the map turns and tilts.
    final flat = [for (final p in positions) ...p];
    final projected = flat.isEmpty
        ? const <math.Point<num>>[]
        : await c.toScreenLocationBatch([for (final p in flat) gl.LatLng(p.lat, p.lon)]);
    if (!mounted) return;
    var next = 0;
    final candidates = [
      for (var i = 0; i < features.length; i++)
        HitCandidate(
          layer: features[i].$1,
          properties: (features[i].$2['properties'] as Map<Object?, Object?>?) ?? const {},
          points: [
            for (final _ in positions[i])
              if (projected[next++] case final s) Offset(s.x.toDouble(), s.y.toDouble()) / scale,
          ],
        ),
    ];
    final tapped = Offset(point.x, point.y) / scale;
    final hit = hitAroundTap(
      (t) => nearestHit(tapped, candidates, shapes: routeHitShapes, zoom: 0, tolerance: t),
      tolerance: tolerance,
      zoom: zoom,
    );
    if (hit == null) {
      final onEmptyTap = _props.onEmptyTap;
      if (onEmptyTap == null) return;
      // On a touch screen GL JS keeps the second tap of a double tap for its
      // zoom: the first one is dropped once the camera zooms.
      if (kIsWeb && webMapPointerKind() == PointerKind.touch && camera != null && zoom != null) {
        final stands = await touchTapStands(
          camera: () async {
            final now = await c.queryCameraPosition();
            if (now == null) return null;
            return (center: LatLng(now.target.latitude, now.target.longitude), zoom: now.zoom);
          },
          center: LatLng(camera.target.latitude, camera.target.longitude),
          zoom: zoom,
          superseded: () => _taps != seq,
        );
        if (!stands) return;
      }
      // Without a zoom no point opens (bareTapAt), but a callout still
      // closes.
      if (mounted) onEmptyTap(LatLng(at.latitude, at.longitude), zoom ?? 0);
      return;
    }
    final chosen = candidates[hit.index];
    final p = chosen.properties;
    if (p['cluster_id'] case final num cluster) {
      final source = RouteLayers.markSources.firstWhere(
        (s) => RouteLayers.badgesOf(s) == chosen.layer,
        orElse: () => RouteLayers.marksSource,
      );
      final where = positions[hit.index];
      try {
        final open = await c.getClusterExpansionZoom(source, cluster.toInt());
        if (where.isNotEmpty && mounted) {
          final centre = where[hit.pointIndex];
          await c.animateCamera(
            gl.CameraUpdate.newLatLngZoom(gl.LatLng(centre.lat, centre.lon), open + 0.3),
            duration: Motion.of(context, Motion.camera),
          );
        }
      } on Object catch (e, st) {
        // The group went with new data between the tap and the answer.
        _log.fine('could not open a group of marks', e, st);
      }
      return;
    }
    if (p['mark'] case final String id) {
      final screen = chosen.points.isEmpty ? tapped : chosen.points[hit.pointIndex];
      _props.onMarkTap?.call(id, at: screen);
      return;
    }
    if (p['index'] case final num index) _props.onLineTap?.call(index.toInt());
  }

  /// The browser's hover picked another target ([listenWebMapHover]): a
  /// badge of this map is told to the screen, anything else is nothing.
  void _onWebHover(WebMapHover? hover) {
    final p = hover == null || !RouteLayers.badges.contains(hover.layer) ? null : hover.properties;
    final next = switch (p) {
      null => null,
      {'mark': final String id} => RouteMapHover(at: hover!.at, mark: id),
      {'cluster_id': _} => RouteMapHover(at: hover!.at, group: RouteMarkStyle.groupCounts(p)),
      _ => null,
    };
    final key = next?.mark ?? (next == null ? null : 'group:${p?['cluster_id']}');
    if (key == _hovered || !mounted) return;
    _hovered = key;
    _props.onMarkHover?.call(next);
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
      // Told once a move starts, not at each of its frames.
      onCameraMove: p.onCameraMove == null
          ? null
          : (_) {
              if (_moving) return;
              _moving = true;
              _props.onCameraMove?.call();
            },
      onCameraIdle: () => _moving = false,
      onMapLongClick: p.onLongPress == null
          ? null
          : (_, at) {
              _taps++;
              p.onLongPress!(LatLng(at.latitude, at.longitude));
            },
    );
    return WebMapPointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          if (size != _size) {
            _size = size;
            // The follow camera's insets follow the map's height.
            if (following) WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
          }
          return map;
        },
      ),
    );
  }
}
