import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/perf/timeline_mark.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart' show hiddenAttributionMargins;
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart' show RawLayerProperties;
import 'package:lunaway/features/map/presentation/map_hit_shapes.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';
import 'package:lunaway/features/map/presentation/web_map_pointer.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/route_progress.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/map_gesture_watch.dart';
import 'package:lunaway/features/navigation/presentation/page_route_motion.dart'
    if (dart.library.js_interop) 'package:lunaway/features/navigation/presentation/page_route_motion_web.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_layer_order.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_mark_layers.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:lunaway/shared/map/tile_json_source.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

final _log = Logger('route_map');

/// The route map on Android, iOS and the web (maplibre_gl): the routes, the
/// restrictions, the places and the vehicle as layers of their own over the
/// basemap.
///
/// While guiding, the vehicle glides between fixes ([VehicleMotion]) and the
/// camera rides with it: tilted, turned to the course, the vehicle in the
/// lower part of the free map so the road ahead shows. In the browser the
/// page draws those frames ([PageRouteMotion]), so the app does nothing at
/// each one; on a phone the app sends them, 30 a second. The user may move
/// the map at any time: following stops at the first gesture, before the
/// screen answers with a [FreeCamera].
class GlRouteMap extends StatefulWidget {
  const new(this.props, {super.key});

  final RouteMapProps props;

  @override
  State<GlRouteMap> createState() => _GlRouteMapState();
}

class _GlRouteMapState extends State<GlRouteMap> {
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

  /// The zones sent, with the lines they were cut from.
  (List<RouteMapLine>, List<RouteSpan>)? _sentZones;
  List<RouteMapMark>? _sentMarks;
  VehiclePuck? _sentVehicle;
  RouteCamera? _sentCamera;
  RouteMapPlaces? _sentPlaces;
  bool _placeLayers = false;

  /// The grey behind the vehicle, as drawn.
  final _traveled = TraveledLine();
  bool _gradientSent = false;

  /// The maneuver's arrow sent, once the style holds its sources.
  ManeuverArrow? _sentArrow;
  bool _arrowSent = false;

  RouteMapProps get _props => widget.props;

  /// The page's own source that names this map to its motion
  /// (`lunawayRouteMotion.bind` in web/lunaway_maplibre.js).
  late final String _tag = 'lw-route-tag-${identityHashCode(this)}';

  /// The browser's page draws the guidance's frames; null on a phone.
  PageRouteMotion? _page;

  // The drawn vehicle and the camera that rides with it, on a phone.
  final _motion = VehicleMotion();
  final _clock = Stopwatch()..start();

  /// The frames of the glide on a phone. A timer rather than a ticker: a
  /// ticker asks Flutter for a frame at every vsync (60, up to 120 a second
  /// on some phones) while the map takes one call every [_frameGap], and
  /// the map's own frames reach the screen without one of Flutter's
  /// (measured on the emulator: 57.5 Flutter frames a second while
  /// driving, `plan/research/117-voix-energie-android.md`). The next frame
  /// is set once the last one's calls are answered, [_frameGap] after it
  /// began, or at once when they took longer.
  Timer? _nextFrame;
  bool _framing = false;
  bool _frameBusy = false;
  Duration _lastFrame = Duration.zero;

  /// What the last frame sent: a frame that would send the same is not
  /// sent, and the map draws nothing.
  _SentFrame? _sentFrame;
  double? _shownZoom;
  double? _shownTilt;
  double _shownBearing = 0;

  /// The course the camera has turned to, easing toward the vehicle's
  /// ([easeCourse]); null until following draws a frame.
  double? _shownCourse;
  EdgeInsets? _sentInsets;
  Size _size = Size.zero;

  /// Where the camera was when following began, and when: the first moments
  /// ease from that view into the driver's, instead of a cut.
  gl.CameraPosition? _entryFrom;
  Duration _entryStart = Duration.zero;
  Duration _entryLength = FreeMap.recenterEase;

  /// The insets when following began; they move to following's with the
  /// rest of the camera, so the view does not drop at once.
  EdgeInsets _entryInsets = EdgeInsets.zero;

  /// The insets following asks for.
  EdgeInsets _followTarget = EdgeInsets.zero;

  /// A gesture of the user stopped following; the camera stays where the
  /// user puts it until following starts again from another view.
  bool _heldByUser = false;

  /// On a phone: a gesture since the camera last rested, a finger down, the
  /// camera moving.
  bool _gestured = false;
  bool _pressed = false;
  bool _cameraMoving = false;

  /// Native maps take each frame over a platform channel: 30 a second keeps
  /// the glide smooth without queueing calls.
  static const Duration _frameGap = Duration(milliseconds: 33);

  /// A fix this far from the drawn vehicle is a jump (a new route from
  /// elsewhere), not a move to glide through.
  static const _jumpM = 500.0;

  /// The arrow and the badges are drawn at the screen's density. MapLibre
  /// on Android and iOS reads an image pixel as a physical one (maplibre_gl
  /// 0.27.1 makes the iOS image at the screen's scale), the web as a CSS
  /// pixel.
  double get _imageScale => kIsWeb ? 1 / MediaQuery.devicePixelRatioOf(context) : 1;

  /// The pins of the places, as the main map sizes them: in the browser the
  /// page adds each at its density (web/lunaway_maplibre.js), on a phone
  /// the app adds the shipped set nearest the screen's.
  double get _pinScale =>
      kIsWeb ? 1 : MediaQuery.devicePixelRatioOf(context) / PinSprites.ratioFor(_ratio);

  double get _ratio => MediaQuery.devicePixelRatioOf(context);

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

  /// The rich marks, and when their passes run.
  late final _richEngine = _GlRichEngine(this);
  late final RichMarkDriver _rich = RichMarkDriver(_richEngine, onReady: _requestRich);
  late final RichPasses _richPasses = RichPasses(_richPass);

  /// The route marks the rich marks hide, as the minor badges' filter has
  /// them.
  List<String>? _richHidden;

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
    _richPasses.dispose();
    _stopFrames();
    _idleLater?.cancel();
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
      _sentPlaces = null;
      _sentFrame = null;
    }
    if (old.props.guiding != _props.guiding) _page?.guiding(on: _props.guiding);
    if ((old.props.onGesture == null) != (_props.onGesture == null)) {
      _page?.watch(on: _props.onGesture != null);
    }
    _heldByUser = heldAfter(held: _heldByUser, before: old.props.camera, after: _props.camera);
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
    timelineMark('lunaway-route-map-style');
    bool current() => mounted && load == _styleLoads;
    _ready = false;
    const empty = {'type': 'FeatureCollection', 'features': <Object>[]};
    try {
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final arrow = await vehicleArrowPng(ratio);
      final head = await arrowHeadPng(ratio);
      final badges = await routeBadgePngs(ratio);
      if (!current()) return;
      await c.addImage(RouteLayers.vehicleImage, arrow);
      await c.addImage(RouteLayers.arrowHeadImage, head);
      for (final MapEntry(:key, :value) in badges.entries) {
        await c.addImage(key, value);
      }
      _drawn.clear();
      for (final id in RouteLayerOrder.layers.reversed) {
        await _quietly(() => c.removeLayer(id));
      }
      for (final id in [
        RouteLayers.alternativesSource,
        RouteLayers.zonesSource,
        RouteLayers.routeSource,
        RouteLayers.traveledSource,
        RouteLayers.arrowSource,
        RouteLayers.arrowHeadSource,
        ...RouteLayers.markSources,
        RichLayers.source,
        RouteLayers.vehicleSource,
        if (kIsWeb) _tag,
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
            // The chosen route measures its length, for the grey behind
            // the vehicle (`line-progress`).
            lineMetrics: id == RouteLayers.routeSource,
          ),
        );
      }
      if (!current()) return;
      _placeLayers = false;
      _sentPlaces = null;
      for (final id in RouteLayerOrder.layers) {
        if (!current()) return;
        // The pins come together with their sources, once the places are
        // known: now, or later over the rest (_syncPlaces).
        if (RouteLayerOrder.pins.contains(id)) {
          final places = _props.places;
          if (id == RouteLayerOrder.pins.first && places != null) {
            await _installPlaces(c, places, current: current);
          }
          continue;
        }
        await _addRouteLayer(c, id);
      }
      if (!current()) return;
      timelineMark('lunaway-route-map-layers');
      _ready = true;
      _rich.reset();
      _richEngine.forget();
      _richHidden = null;
      _sentLines = null;
      _sentZones = null;
      _traveled.forget();
      _gradientSent = false;
      _arrowSent = false;
      _sentMarks = null;
      _sentLit = null;
      _sentFocus = _props.focus?.serial;
      _sentVehicle = null;
      _sentCamera = null;
      _sentInsets = null;
      _sentFrame = null;
      if (kIsWeb) {
        _page = bindPageRouteMotion(_tag, _onPageEvent);
        _page?.guiding(on: _props.guiding);
        _page?.watch(on: _props.onGesture != null);
      }
      _schedule();
      // The pins' images last, once the route shows: the plugin decodes each
      // on Android's main thread, which is also the app's.
      if (_props.places != null) await _addPinImages(c, current);
    } on Object catch (e, st) {
      _log.warning('could not set up the route layers', e, st);
    }
  }

  /// The route's own layers the style holds, for [RouteLayerOrder.below].
  final Set<String> _drawn = {};

  /// The basemap's names the route's layers go under, read once per style:
  /// the lines under every name of places, the pins under the towns'.
  ({String? placeNames, String? townNames}) get _names {
    if (!identical(_namesOf, _props.style)) {
      _namesOf = _props.style;
      _namesIds = RouteLayerOrder.namesOf(_props.style);
    }
    return _namesIds;
  }

  String? _namesOf;
  ({String? placeNames, String? townNames}) _namesIds = (placeNames: null, townNames: null);

  /// Where [id] goes in the style, by [RouteLayerOrder].
  String? _belowOf(String id) {
    final (:placeNames, :townNames) = _names;
    return RouteLayerOrder.below(
      id,
      present: _drawn.contains,
      placeNames: placeNames,
      townNames: townNames,
    );
  }

  /// The whole look of the route's line layer [id] ([routeLinePaint]):
  /// maplibre_gl resets every property a change leaves out.
  gl.LineLayerProperties _lineLook(String id) {
    final paint = routeLinePaint(id, dark: _props.dark, traveledShare: _traveled.share);
    return gl.LineLayerProperties(
      lineJoin: 'round',
      lineCap: 'round',
      lineColor: paint['line-color'],
      lineWidth: paint['line-width'],
      lineOpacity: paint['line-opacity'],
      lineGradient: paint['line-gradient'],
    );
  }

  /// Adds the layer [id] of the route, its look by its id, in its place.
  Future<void> _addRouteLayer(gl.MapLibreMapController c, String id) async {
    final below = _belowOf(id);
    switch (id) {
      // No line answers a click: a tap picks the other routes by their shape
      // (routeHitShapes), the chosen one never.
      case _ when RouteLayers.lineLayers.contains(id):
        await c.addLineLayer(
          routeLineSource(id),
          id,
          _lineLook(id),
          belowLayerId: below,
          enableInteraction: false,
        );
      case RouteLayers.arrowHead:
        final head = routeArrowHeadLayout(_imageScale);
        await c.addSymbolLayer(
          RouteLayers.arrowHeadSource,
          id,
          gl.SymbolLayerProperties(
            iconImage: head['icon-image'],
            iconSize: head['icon-size'],
            iconRotate: head['icon-rotate'],
            iconRotationAlignment: head['icon-rotation-alignment'],
            iconPitchAlignment: head['icon-pitch-alignment'],
            iconAllowOverlap: head['icon-allow-overlap'],
            iconIgnorePlacement: head['icon-ignore-placement'],
          ),
          belowLayerId: below,
          enableInteraction: false,
        );
      case RichLayers.marks:
        await c.addSymbolLayer(
          RichLayers.source,
          id,
          richSymbolProperties(_imageScale),
          belowLayerId: below,
          enableInteraction: false,
        );
      case RouteLayers.vehicle:
        await c.addSymbolLayer(
          RouteLayers.vehicleSource,
          id,
          gl.SymbolLayerProperties(
            iconImage: RouteLayers.vehicleImage,
            iconSize: _imageScale,
            iconRotate: const ['get', 'course'],
            iconRotationAlignment: 'map',
            iconPitchAlignment: 'map',
            iconAllowOverlap: true,
            // The arrow keeps the pins of the places off itself: placed
            // first (it is the top layer), its box and this room around it
            // are taken before theirs.
            iconIgnorePlacement: false,
            iconPadding: RoutePlaceLayers.vehicleClearance,
          ),
          belowLayerId: below,
          enableInteraction: false,
        );
      default:
        final source = RouteLayers.markSources.firstWhere(
          (s) => RouteLayers.layersOf(s).contains(id),
          orElse: () => throw StateError('$id is no layer of the route map'),
        );
        await _addMarkLayer(c, source, id, below: below);
    }
    _drawn.add(id);
  }

  /// The places' and the points' sources and layers, in their place among
  /// the route's.
  Future<void> _installPlaces(
    gl.MapLibreMapController c,
    RouteMapPlaces places, {
    required bool Function() current,
  }) async {
    for (final id in RouteLayerOrder.pins.reversed) {
      await _quietly(() => c.removeLayer(id));
      _drawn.remove(id);
    }
    for (final id in [RoutePlaceLayers.poiSource, RoutePlaceLayers.placeSource]) {
      await _quietly(() => c.removeSource(id));
    }
    if (!current()) return;
    await c.addSource(RoutePlaceLayers.poiSource, tileJsonSource(places.poiTileJsonUrl));
    await c.addSource(RoutePlaceLayers.placeSource, tileJsonSource(places.placeTileJsonUrl));
    final poi = RoutePlaceLayers.poiLayout(_pinScale);
    final place = RoutePlaceLayers.placeLayout(_pinScale);
    for (final id in RouteLayerOrder.pins) {
      if (!current()) return;
      final below = _belowOf(id);
      if (id == RichLayers.probe) {
        // Every place the filter keeps in view, even one whose pin found no
        // room: what the rich marks choose among.
        await c.addCircleLayer(
          RoutePlaceLayers.placeSource,
          id,
          gl.CircleLayerProperties(
            circleRadius: RichLayers.probePaint['circle-radius'],
            circleOpacity: RichLayers.probePaint['circle-opacity'],
            circleStrokeWidth: RichLayers.probePaint['circle-stroke-width'],
            visibility: places.placeFilter == null ? 'none' : 'visible',
          ),
          sourceLayer: PlaceTiles.pinsSourceLayer,
          minzoom: RoutePlaceLayers.placeMinZoom,
          filter: places.placeFilter ?? RoutePlaceLayers.none,
          belowLayerId: below,
          enableInteraction: false,
        );
      } else if (id == RoutePlaceLayers.placePins) {
        await c.addSymbolLayer(
          RoutePlaceLayers.placeSource,
          id,
          gl.SymbolLayerProperties(
            iconImage: place['icon-image'],
            iconSize: place['icon-size'],
            iconAnchor: 'bottom',
            iconAllowOverlap: false,
            iconIgnorePlacement: false,
            iconPadding: RoutePlaceLayers.pinPadding,
            symbolSortKey: place['symbol-sort-key'],
            visibility: places.placeFilter == null ? 'none' : 'visible',
          ),
          sourceLayer: PlaceTiles.pinsSourceLayer,
          minzoom: RoutePlaceLayers.placeMinZoom,
          filter: places.placeFilter ?? RoutePlaceLayers.none,
          belowLayerId: below,
          enableInteraction: false,
        );
      } else {
        final (_, sourceLayer) = RoutePlaceLayers.poiLayers.firstWhere((l) => l.$1 == id);
        await c.addSymbolLayer(
          RoutePlaceLayers.poiSource,
          id,
          gl.SymbolLayerProperties(
            iconImage: poi['icon-image'],
            iconSize: poi['icon-size'],
            iconAnchor: 'bottom',
            iconAllowOverlap: false,
            iconIgnorePlacement: false,
            iconPadding: RoutePlaceLayers.pinPadding,
            visibility: places.poiFilter == null ? 'none' : 'visible',
          ),
          sourceLayer: sourceLayer,
          minzoom: RoutePlaceLayers.poiMinZoom,
          filter: places.poiFilter ?? RoutePlaceLayers.none,
          belowLayerId: below,
          enableInteraction: false,
        );
      }
      _drawn.add(id);
    }
    _placeLayers = true;
    _sentPlaces = places;
  }

  /// The pins of the places and the points, on a phone: those the layers
  /// draw, from the set the main map loaded already.
  Future<void> _addPinImages(gl.MapLibreMapController c, bool Function() current) async {
    if (kIsWeb) return;
    final all = await PinSprites.load(PinSprites.ratioFor(_ratio));
    if (!current()) return;
    // A few per frame: the plugin decodes each on Android's main thread,
    // and the hundred of them at once held it for a burst of frames as the
    // guidance opened.
    final ids = [
      for (final id in RoutePlaceLayers.imageIds())
        if (all.containsKey(id)) id,
    ];
    for (var i = 0; i < ids.length; i += _pinsPerFrame) {
      await Future.wait([
        for (final id in ids.skip(i).take(_pinsPerFrame)) c.addImage(id, all[id]!),
      ]);
      if (!current()) return;
      await SchedulerBinding.instance.endOfFrame;
      if (!current()) return;
    }
  }

  static const _pinsPerFrame = 8;

  /// Sends what changed of the places: a filter, a layer shown or hidden.
  Future<void> _syncPlaces(gl.MapLibreMapController c) async {
    final places = _props.places;
    final sent = _sentPlaces;
    if (places == sent) return;
    _richEngine.forget();
    if (places == null) {
      if (_placeLayers) {
        for (final id in [...RoutePlaceLayers.layers, RichLayers.probe]) {
          await _quietly(() => c.setLayerVisibility(id, false));
        }
      }
      _sentPlaces = null;
      return;
    }
    if (!_placeLayers ||
        sent == null ||
        sent.placeTileJsonUrl != places.placeTileJsonUrl ||
        sent.poiTileJsonUrl != places.poiTileJsonUrl) {
      final first = !_placeLayers;
      await _installPlaces(c, places, current: () => mounted && _ready);
      // Not awaited: the images decode on Android's main thread, and the
      // vehicle and camera of this pass must not wait for them.
      if (first && mounted) unawaited(_addPinImages(c, () => mounted && _ready));
      return;
    }
    for (final (id, filter) in [
      (RoutePlaceLayers.placePins, places.placeFilter),
      (RichLayers.probe, places.placeFilter),
      for (final (layer, _) in RoutePlaceLayers.poiLayers) (layer, places.poiFilter),
    ]) {
      if (filter != null) await c.setFilter(id, filter);
      await c.setLayerVisibility(id, filter != null);
    }
    _sentPlaces = places;
  }

  void _requestRich() {
    if (_ready && mounted) _richPasses.request();
  }

  /// One pass of the rich marks, with what the map shows now.
  Future<void> _richPass() {
    if (!_ready || !mounted) return Future.value();
    final rich = _props.rich;
    if (rich == null) return _rich.clear();
    return _rich.refresh(
      RichInput(
        rich: rich,
        size: _size,
        ratio: _ratio,
        line: _props.lines.firstWhereOrNull((l) => l.selected)?.points ?? const [],
        vehicle: _props.vehicle?.position,
        marks: routeSigns(_props.marks),
      ),
    );
  }

  /// The layer [id] of one source of marks ([RouteLayers.layersOf]): the
  /// lit ring, the badges with their text, or the text beside them. None is
  /// watched by the plugin: a tap and the pointer pick by [routeHitShapes].
  Future<void> _addMarkLayer(
    gl.MapLibreMapController c,
    String source,
    String id, {
    String? below,
  }) async {
    final minzoom = source == RouteLayers.minorSource ? RouteMarkStyle.minorMinZoom : null;
    if (id == RouteLayers.haloOf(source)) {
      await c.addCircleLayer(
        source,
        id,
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
        belowLayerId: below,
        enableInteraction: false,
      );
    } else if (id == RouteLayers.badgesOf(source)) {
      await c.addSymbolLayer(
        source,
        id,
        gl.SymbolLayerProperties(
          iconImage: RouteMarkStyle.iconImage,
          iconSize: RouteMarkStyle.iconSize(_imageScale),
          iconAllowOverlap: true,
          iconIgnorePlacement: RouteMarkStyle.ignorePlacement,
          symbolSortKey: RouteMarkStyle.sortKey,
          textField: RouteMarkStyle.textField,
          textFont: RouteMarkStyle.font,
          textSize: RouteMarkStyle.textSize,
          textColor: RouteMarkStyle.textColor,
          textAllowOverlap: true,
          textIgnorePlacement: RouteMarkStyle.ignorePlacement,
        ),
        minzoom: minzoom,
        belowLayerId: below,
        enableInteraction: false,
      );
    } else {
      await c.addSymbolLayer(
        source,
        id,
        gl.SymbolLayerProperties(
          textField: const ['get', 'side'],
          textFont: RouteMarkStyle.font,
          textSize: RouteMarkStyle.sideTextSize,
          textAnchor: 'left',
          textOffset: RouteMarkStyle.sideOffset,
          textOptional: true,
          textColor: RouteLook.hex(Palette.minuit),
          textHaloColor: RouteLook.hex(Palette.creme),
          textHaloWidth: RouteMarkStyle.sideHalo,
        ),
        minzoom: minzoom,
        filter: RouteMarkStyle.sideFilter,
        belowLayerId: below,
        enableInteraction: false,
      );
    }
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
    final shown = await c.queryCameraPosition();
    if (!mounted) return;
    final zoom = math.max(shown?.zoom ?? 0, RouteMarkStyle.focusZoom);
    _sentFrame = null;
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
    final before = (
      lines: _sentLines,
      marks: _sentMarks,
      places: _sentPlaces,
      camera: _sentCamera,
      drawn: _motion.target,
    );
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
    if (_sentZones case (final lines, final zones)
        when listEquals(lines, p.lines) && listEquals(zones, p.zones)) {
      // Sent already.
    } else {
      _sentZones = (p.lines, p.zones);
      await c.setGeoJsonSource(RouteLayers.zonesSource, routeZonesCollection(p.lines, p.zones));
    }
    // The road behind the vehicle greys, at most once a fix: the gradient
    // alone (maplibre_gl resets the properties it is not given), when its
    // share moved, and the grey up to the vehicle.
    final share = _traveled.share;
    if (_traveled.next(p.lines, p.traveledM)) {
      if (_traveled.share != share || !_gradientSent) {
        _gradientSent = true;
        for (final id in [RouteLayers.routeCasing, RouteLayers.route]) {
          await c.setLayerProperties(
            id,
            RawLayerProperties({'line-gradient': _lineLook(id).lineGradient}),
          );
        }
      }
      await c.setGeoJsonSource(RouteLayers.traveledSource, routeTraveledCollection(_traveled.tail));
    }
    if (!_arrowSent || p.arrow != _sentArrow) {
      _arrowSent = true;
      _sentArrow = p.arrow;
      await c.setGeoJsonSource(RouteLayers.arrowSource, routeArrowCollection(p.arrow));
      await c.setGeoJsonSource(RouteLayers.arrowHeadSource, routeArrowHeadCollection(p.arrow));
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
    await _syncPlaces(c);
    if (!mounted) return;
    final page = _page;
    if (p.vehicle != _sentVehicle) {
      final before = _sentVehicle;
      _sentVehicle = p.vehicle;
      final v = p.vehicle;
      if (v == null) {
        page?.clear();
        _sentFrame = null;
        await c.setGeoJsonSource(RouteLayers.vehicleSource, vehicleCollection(null));
      } else if (page != null) {
        page.vehicle(
          RouteLayers.vehicleSource,
          v.position,
          v.course,
          jump: before == null || Motion.reduced(context),
        );
      } else {
        final shown = _motion.target;
        _motion.retarget(
          v.position,
          v.course,
          _clock.elapsed,
          jump: Motion.reduced(context) || (shown != null && shown.distanceTo(v.position) > _jumpM),
          speedMps: v.speedMps,
        );
        _startFrames();
      }
    }
    if (!mounted) return;
    await _syncCamera(c, page);
    // On a phone, a fix that moved nothing on the map (a parked vehicle's,
    // [VehicleMotion.parkedWanderM]) leaves the marks as they were: no pass
    // asks the map for them again, every second.
    final still =
        page == null &&
        identical(before.lines, _sentLines) &&
        identical(before.marks, _sentMarks) &&
        identical(before.places, _sentPlaces) &&
        before.drawn == _motion.target &&
        (identical(before.camera, _sentCamera) ||
            (before.camera is FollowCamera && _sentCamera is FollowCamera)) &&
        switch ((_richAsked, p.rich)) {
          (null, null) => true,
          (final RouteMapRich a, final RouteMapRich b) => a.sameBesidesVehicle(b),
          _ => false,
        };
    _richAsked = p.rich;
    if (!still) _requestRich();
  }

  /// The rich marks the last [_sync] saw.
  RouteMapRich? _richAsked;

  /// When the map's going idle last asked for the marks again, and the
  /// pass set for the end of that while.
  final _idlePasses = Stopwatch();
  Timer? _idleLater;

  /// The map has drawn all it was loading. Parked, no fix asks for the
  /// rich marks again ([_sync]): the places of tiles that came after the
  /// last pass are read now, at most once per [tilePlacesKept], an idle
  /// within that while answered at its end. Not while the glide runs,
  /// whose frames may leave the map idle between two and would query the
  /// map at each.
  void _onMapIdle() {
    if (_framing || !_ready || !mounted || _idleLater != null) return;
    final since = _idlePasses.isRunning ? _idlePasses.elapsed : tilePlacesKept;
    if (since < tilePlacesKept) {
      _idleLater = Timer(tilePlacesKept - since, () {
        _idleLater = null;
        _onMapIdle();
      });
      return;
    }
    _idlePasses
      ..reset()
      ..start();
    _richEngine.forget();
    _requestRich();
  }

  Future<void> _syncCamera(gl.MapLibreMapController c, PageRouteMotion? page) async {
    final camera = _props.camera;
    final insets = followInsets(_size, _props.padding);
    // A gesture that stopped following keeps the user's view until the
    // screen asks again to follow (cameraStep, heldAfter).
    var step = cameraStep(sent: _sentCamera, next: camera, heldByUser: _heldByUser);
    // The same camera on a map of another size: following moves its centre.
    if (step == CameraStep.none &&
        camera is FollowCamera &&
        !_heldByUser &&
        insets != _followTarget) {
      step = CameraStep.follow;
    }
    if (step == CameraStep.none) return;
    _sentCamera = camera;
    // The camera moves elsewhere, or into following from elsewhere: the
    // next frame sends the view again, even one the last frame sent.
    if (step != CameraStep.follow) _sentFrame = null;
    switch (step) {
      case CameraStep.none:
        return;
      case CameraStep.enterFollow || CameraStep.follow:
        final follow = camera as FollowCamera;
        final entering = step == CameraStep.enterFollow;
        final ease = Motion.reduced(context) ? Duration.zero : follow.ease;
        if (page != null) {
          _followTarget = insets;
          page.follow(
            zoom: follow.zoom,
            tilt: follow.tilt,
            padding: insets,
            ease: ease,
            enter: entering,
          );
          return;
        }
        if (entering) {
          // Read at once (tracked on a phone): a frame may come before any
          // answer would.
          _entryFrom = ease == Duration.zero ? null : c.cameraPosition;
          // The entry turns the map from the user's view; the course eased
          // before the user took the map is stale.
          _shownCourse = null;
          _entryStart = _clock.elapsed;
          _entryLength = ease;
          _entryInsets = _sentInsets ?? EdgeInsets.zero;
        }
        _followTarget = insets;
        // During the entry the frames move the insets along with the camera.
        if (insets != _sentInsets && _entryFrom == null) {
          _sentInsets = insets;
          await c.updateContentInsets(insets);
        }
        _startFrames();
      case CameraStep.free:
        _entryFrom = null;
        page?.free();
      case CameraStep.overview || CameraStep.fit:
        if (step == CameraStep.overview) {
          _entryFrom = null;
          // The overview reads north up and flat, as the preview does: the
          // bounds below keep whatever tilt and bearing the map had.
          if (page != null) {
            page.overview();
          } else {
            _sentInsets = EdgeInsets.zero;
            await c.updateContentInsets(EdgeInsets.zero);
            if (await c.queryCameraPosition() case final at?) {
              await c.moveCamera(
                gl.CameraUpdate.newCameraPosition(
                  gl.CameraPosition(target: at.target, zoom: at.zoom),
                ),
              );
            }
          }
        }
        _followTarget = EdgeInsets.zero;
        _shownZoom = null;
        _shownTilt = null;
        _shownCourse = null;
        await _moveCamera(c, camera);
    }
  }

  /// Starts the frames, the first one now and measured from now: after a
  /// pause (parked, a tunnel) the zoom must not catch up in one step.
  void _startFrames() {
    if (_framing || _page != null) return;
    _framing = true;
    _lastFrame = Duration.zero;
    if (!_frameBusy) _frame();
  }

  void _stopFrames() {
    _framing = false;
    _nextFrame?.cancel();
    _nextFrame = null;
  }

  /// Sets the next frame [_frameGap] after the last one began, at once
  /// when that time is past.
  void _frameAgain() {
    if (!_framing || _nextFrame != null) return;
    final wait = _frameGap - (_clock.elapsed - _lastFrame);
    _nextFrame = Timer(wait.isNegative ? Duration.zero : wait, () {
      _nextFrame = null;
      if (_framing) _frame();
    });
  }

  /// One frame of the glide on a phone: the vehicle where [VehicleMotion]
  /// draws it, and the camera on it while following. A frame waits for the
  /// previous one's calls, so a slow map drops frames instead of queueing
  /// them; one that would send what the last one sent sends nothing, and
  /// the frames stop once the vehicle, the zoom and the way into following
  /// have come to rest.
  void _frame() {
    final c = _controller;
    final now = _clock.elapsed;
    if (c == null || !_ready || !mounted || _page != null) {
      // No style yet (or a failed one): frames resume with the next sync.
      _stopFrames();
      return;
    }
    if (_frameBusy) return;
    final (position, course) = _motion.at(now);
    if (position == null) {
      _stopFrames();
      return;
    }
    final dt = _lastFrame == Duration.zero ? Duration.zero : now - _lastFrame;
    _lastFrame = now;
    final camera = _props.camera;
    var settled = !_motion.movingAt(now);
    final sent = _sentFrame;
    final calls = <Future<Object?>>[
      if (sent == null || sent.position != position || sent.course != course)
        c.setGeoJsonSource(
          RouteLayers.vehicleSource,
          vehicleCollection(VehiclePuck(position: position, course: course)),
        ),
    ];
    var view = sent?.view;
    // The camera waits while a finger is down: MapLibre drops a gesture it
    // has begun when the camera moves under it.
    if (camera is FollowCamera && !_heldByUser && !_pressed) {
      final wanted = camera.zoom;
      final shownZoom = _shownZoom;
      var zoom = shownZoom == null ? wanted : easeZoom(shownZoom, wanted, dt);
      _shownZoom = zoom;
      if ((wanted - zoom).abs() > 0.01) settled = false;
      // The map turns a moment after the arrow: a bend sweeps rather than
      // snaps, and a course that wavers does not shake the view.
      if (course != null) {
        final shownCourse = _shownCourse;
        _shownCourse = shownCourse == null ? course : easeCourse(shownCourse, course, dt);
        if (angleDelta(_shownCourse!, course).abs() > courseSettledDeg) settled = false;
        _shownBearing = _shownCourse!;
      }
      final shownTilt = _shownTilt;
      var tilt = shownTilt == null ? camera.tilt : easeTilt(shownTilt, camera.tilt, dt);
      _shownTilt = tilt;
      if ((camera.tilt - tilt).abs() > 0.3) settled = false;
      final aimTilt = tilt;
      var target = position;
      var bearing = _shownBearing;
      // Into following: from the view the user had to the driver's.
      if (_entryFrom case final from?) {
        final t = _entryLength <= Duration.zero
            ? 1.0
            : (now - _entryStart).inMicroseconds / _entryLength.inMicroseconds;
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
          tilt = from.tilt + (aimTilt - from.tilt) * k;
          final insets = EdgeInsets.lerp(_entryInsets, _followTarget, k)!;
          // Kept: a gesture that cuts the entry leaves the map with these.
          _sentInsets = insets;
          calls.add(c.updateContentInsets(insets));
        }
      }
      final next = (target: target, zoom: zoom, bearing: bearing, tilt: tilt);
      if (next != view) {
        view = next;
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
    } else {
      // Not following: the next time it does, the camera is sent again.
      view = null;
    }
    _sentFrame = (position: position, course: course, view: view);
    if (settled) _stopFrames();
    if (calls.isEmpty) {
      _frameAgain();
      return;
    }
    _frameBusy = true;
    unawaited(
      Future.wait(calls)
          .then<void>((_) {})
          .catchError((Object e, StackTrace st) => _log.warning('route map frame failed', e, st))
          .whenComplete(() {
            _frameBusy = false;
            if (mounted) _frameAgain();
          }),
    );
  }

  Future<void> _moveCamera(gl.MapLibreMapController c, RouteCamera camera) async {
    if (!mounted || camera is! FitCamera) return;
    final pad = _props.padding + camera.room;
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

  /// A gesture of the user (a phone's pointers, or the page's report):
  /// following stops at once.
  void _onGesture() {
    _heldByUser = true;
    _entryFrom = null;
    _gestured = true;
    _props.onGesture?.call();
  }

  void _onNativeTouch(bool down) {
    _pressed = down;
    _props.onTouch?.call(down);
    if (!down && _gestured && !_cameraMoving) unawaited(_reportRest());
  }

  /// The camera the user moved rests, on a phone: where the vehicle is
  /// drawn and how the map is turned, for the magnet.
  Future<void> _reportRest() async {
    final c = _controller;
    final onRest = _props.onRest;
    if (c == null || onRest == null || !_ready) return;
    _gestured = false;
    final scale = _queryScale;
    final (position, _) = _motion.at(_clock.elapsed);
    final camera = await c.queryCameraPosition();
    final screen = position == null
        ? null
        : await c.toScreenLocation(gl.LatLng(position.lat, position.lon));
    if (!mounted || camera == null) return;
    onRest(
      FreeView(
        size: _size,
        center: LatLng(camera.target.latitude, camera.target.longitude),
        vehicle: screen == null ? null : Offset(screen.x.toDouble(), screen.y.toDouble()) / scale,
        zoom: camera.zoom,
        bearing: camera.bearing,
        tilt: camera.tilt,
      ),
    );
  }

  /// What the browser's page reports of this map
  /// (`lunawayRouteMotion` in web/lunaway_maplibre.js).
  void _onPageEvent(Map<Object?, Object?> event) {
    if (!mounted) return;
    switch (event['type']) {
      case 'gesture':
        _onGesture();
      case 'touch':
        _props.onTouch?.call(event['down'] == true);
      case 'rest':
        _props.onRest?.call(freeViewOfPage(event, size: _size));
      case 'longpress':
        if ((event['lat'], event['lon']) case (final num lat, final num lon)
            when lat.abs() <= 90 && lon.isFinite) {
          _taps++;
          // GL JS gives longitudes past 180 on the world's repeated copies.
          final wrapped = (lon + 180) % 360 - 180;
          _props.onLongPress?.call(LatLng(lat.toDouble(), wrapped.toDouble()));
        }
    }
  }

  /// The engine's screen units per logical pixel, for its feature queries
  /// and the points of its taps: Android counts physical pixels.
  double get _queryScale => mapQueryScale(
    web: kIsWeb,
    platform: defaultTargetPlatform,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  /// The shapes a tap picks among: the route's marks and lines, and the
  /// places and points when the map draws them.
  static final Map<String, HitShape> _shapes = {...routeHitShapes, ...routePlaceHitShapes};

  /// The nearest badge, place, point or other route within reach of a tap
  /// ([nearestHit]), and at street level one the tap just missed
  /// ([hitAroundTap]): a group zooms in until it opens, a mark, a place or
  /// a point reports itself, another route is chosen. Nothing in reach is
  /// a tap on bare map at [at]. Every mark is a target: none is a sign that
  /// opens nothing.
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
    final places = _props.places;
    final pois = places?.poiFilter != null && _props.onPoiTap != null;
    // Topmost first, as the map draws them.
    final layers = [
      for (final id in RouteLayerOrder.layers.reversed)
        if (switch (id) {
          RichLayers.marks => _props.rich != null,
          RoutePlaceLayers.placePins => places?.placeFilter != null && _props.onPlaceTap != null,
          RoutePlaceLayers.poiPins || RoutePlaceLayers.poiMorePins => pois,
          RouteLayers.alternatives || RouteLayers.alternativesCasing => _props.onLineTap != null,
          _ => RouteLayers.badges.contains(id),
        })
          id,
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
      (t) => nearestHit(tapped, candidates, shapes: _shapes, zoom: zoom ?? 0, tolerance: t),
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
    final where = positions[hit.index];
    final picked = where.isEmpty ? null : where[hit.pointIndex];
    // A rich mark opens what its place's pin opens; one standing for a
    // route mark (a place near the route) opens that mark, below.
    if (chosen.layer == RichLayers.marks && p[RichLayers.mark] is! String) {
      final place = placeFromTile(p, picked == null ? null : [picked.lon, picked.lat]);
      if (place != null) _props.onPlaceTap?.call(place);
      return;
    }
    if (chosen.layer == RoutePlaceLayers.placePins) {
      final place = placeFromTile(p, picked == null ? null : [picked.lon, picked.lat]);
      if (place != null) _props.onPlaceTap?.call(place);
      return;
    }
    if (RoutePlaceLayers.poiLayers.any((l) => l.$1 == chosen.layer)) {
      final poi = PoiFeature.fromTile(p, picked == null ? null : [picked.lon, picked.lat]);
      if (poi != null) _props.onPoiTap?.call(poi);
      return;
    }
    if (p['cluster_id'] case final num cluster) {
      final source = RouteLayers.markSources.firstWhere(
        (s) => RouteLayers.badgesOf(s) == chosen.layer,
        orElse: () => RouteLayers.marksSource,
      );
      try {
        final open = await c.getClusterExpansionZoom(source, cluster.toInt());
        if (picked != null && mounted) {
          await c.animateCamera(
            gl.CameraUpdate.newLatLngZoom(gl.LatLng(picked.lat, picked.lon), open + 0.3),
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
    final layer = hover?.layer;
    final p = layer == null || !(RouteLayers.badges.contains(layer) || layer == RichLayers.marks)
        ? null
        : hover!.properties;
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
    final start = initialCamera(p);
    final following = camera is FollowCamera;
    final map = gl.MapLibreMap(
      styleString: p.style,
      initialCameraPosition: gl.CameraPosition(
        target: gl.LatLng(start.target.lat, start.target.lon),
        zoom: start.zoom,
        tilt: start.tilt,
        bearing: start.bearing,
      ),
      // In the browser the camera is read when needed (queryCameraPosition):
      // tracked, it would call the app at every frame of the page's motion.
      trackCameraPosition: !kIsWeb,
      annotationOrder: const [],
      compassEnabled: false,
      // The guidance's map moves, turns and tilts under the fingers and the
      // mouse, following or not; the preview keeps north up.
      rotateGesturesEnabled: p.guiding,
      scrollGesturesEnabled: p.guiding || !following,
      zoomGesturesEnabled: p.guiding || !following,
      tiltGesturesEnabled: p.guiding,
      // Out of sight, as on the main map: the screens show the map's credit
      // themselves (MapCredit), clear of their own controls.
      attributionButtonPosition: gl.AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: hiddenAttributionMargins,
      logoViewPosition: gl.LogoViewPosition.bottomLeft,
      logoViewMargins: math.Point(p.padding.left + 44, p.padding.bottom + 8),
      onMapCreated: (c) {
        timelineMark('lunaway-route-map-created');
        _controller = c;
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick:
          kIsWeb &&
              p.onLineTap == null &&
              p.onMarkTap == null &&
              p.onEmptyTap == null &&
              p.onPlaceTap == null &&
              p.onPoiTap == null
          ? null
          : _onTap,
      // Told once a move starts, not at each of its frames.
      onCameraMove: (_) {
        _cameraMoving = true;
        if (_moving) return;
        _moving = true;
        _props.onCameraMove?.call();
      },
      onCameraIdle: () {
        timelineMark('lunaway-route-map-idle');
        _moving = false;
        _cameraMoving = false;
        _props.onCameraIdle?.call();
        if (!kIsWeb && _gestured && !_pressed) unawaited(_reportRest());
        _requestRich();
      },
      onMapIdle: kIsWeb ? null : _onMapIdle,
      // In the browser the plugin reports a double click as a long press,
      // which also zooms: the page reports right clicks and held fingers
      // instead (_onPageEvent).
      onMapLongClick: p.onLongPress == null || kIsWeb
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
          // The browser's page watches the gestures itself. The preview's
          // map is watched too, when its screen listens.
          return (p.guiding || p.onGesture != null) && !kIsWeb
              ? MapGestureWatch(onGesture: _onGesture, onTouch: _onNativeTouch, child: map)
              : map;
        },
      ),
    );
  }
}

/// The rich marks' layer on maplibre_gl, the layout the desktop page draws
/// ([RichLayers.layout]) in the plugin's terms: the two kept apart, a mark
/// one engine drops would stand on the other.
@visibleForTesting
gl.SymbolLayerProperties richSymbolProperties(double scale) {
  final rich = RichLayers.layout(scale);
  return gl.SymbolLayerProperties(
    iconImage: rich['icon-image'],
    iconSize: rich['icon-size'],
    iconAnchor: rich['icon-anchor'],
    iconAllowOverlap: rich['icon-allow-overlap'],
    iconIgnorePlacement: rich['icon-ignore-placement'],
    iconPitchAlignment: rich['icon-pitch-alignment'],
    iconRotationAlignment: rich['icon-rotation-alignment'],
    symbolSortKey: rich['symbol-sort-key'],
  );
}

/// The rich marks on maplibre_gl: the places read from the invisible
/// probe, points projected by the engine (the guidance's camera turns and
/// tilts), the marks' images in a few slots.
final class _GlRichEngine implements RichMarkEngine {
  new(this._state);

  final _GlRouteMapState _state;

  gl.MapLibreMapController? get _c => _state.mounted && _state._ready ? _state._controller : null;

  /// The places found last, the camera and the part of the map they were
  /// asked under, and how long ago ([tilePlacesStillHold]).
  List<({Map<Object?, Object?> properties, LatLng at})>? _places;
  RichCamera? _placesUnder;
  Rect? _placesIn;
  final _placesAge = Stopwatch();

  /// Forgets the places found: the layers or their filter changed.
  void forget() => _places = null;

  @override
  Future<List<({Map<Object?, Object?> properties, LatLng at})>> tilePlaces() async {
    final c = _c;
    final size = _state._size;
    if (c == null || _state._props.places?.placeFilter == null || size.isEmpty) return const [];
    // Only where a mark may stand ([richQueryRect]): a place beyond would
    // be written out by the engine, sent over and dropped.
    final open = richQueryRect(size, _state._props.rich?.clear ?? EdgeInsets.zero);
    if (open.isEmpty) return const [];
    // The camera the plugin keeps from the map's moves (a browser's map is
    // not followed, and answers in the page at no such cost).
    final camera = kIsWeb ? null : c.cameraPosition;
    final under = camera == null
        ? null
        : (
            target: LatLng(camera.target.latitude, camera.target.longitude),
            zoom: camera.zoom,
            bearing: camera.bearing,
            tilt: camera.tilt,
          );
    final kept = _places;
    final keptUnder = _placesUnder;
    if (kept != null &&
        under != null &&
        keptUnder != null &&
        _placesIn == open &&
        tilePlacesStillHold(
          then: keptUnder,
          now: under,
          age: _placesAge.elapsed,
          size: open.size,
        )) {
      return kept;
    }
    final scale = _state._queryScale;
    final found = await c.queryRenderedFeaturesInRect(
      Rect.fromLTRB(open.left * scale, open.top * scale, open.right * scale, open.bottom * scale),
      [RichLayers.probe],
      null,
    );
    final places = [
      for (final f in found)
        if (f is Map)
          if (pointsOfGeometry(f['geometry'] as Map<Object?, Object?>?) case [final at, ...])
            (properties: (f['properties'] as Map<Object?, Object?>?) ?? const {}, at: at),
    ];
    // An empty view is asked again at the next pass: at the start its tiles
    // may still be on their way.
    _places = places.isEmpty ? null : places;
    _placesUnder = under;
    _placesIn = open;
    _placesAge
      ..reset()
      ..start();
    return places;
  }

  @override
  Future<RichView?> view(List<LatLng> points) async {
    final c = _c;
    if (c == null) return null;
    final camera = await c.queryCameraPosition();
    if (camera == null || _c == null) return null;
    final scale = _state._queryScale;
    final screen = await c.toScreenLocationBatch([
      for (final p in points) gl.LatLng(p.lat, p.lon),
      camera.target,
    ]);
    if (screen.length != points.length + 1) return null;
    Offset at(math.Point<num> p) => Offset(p.x.toDouble(), p.y.toDouble()) / scale;
    return RichView(
      points: [for (final p in screen.take(points.length)) at(p)],
      zoom: camera.zoom,
      pitch: camera.tilt,
      centre: at(screen.last),
    );
  }

  @override
  Future<bool> putImage(String id, Uint8List png) async {
    final c = _c;
    if (c == null) return false;
    if (kIsWeb) dropPageImage(_state._tag, id);
    try {
      await c.addImage(id, png);
      return true;
    } on Object catch (e) {
      _log.fine('could not add the image of a rich mark', e);
      return false;
    }
  }

  @override
  Future<void> show(Map<String, Object?> collection, {required List<String> hiddenMarks}) async {
    final c = _c;
    if (c == null) return;
    await c.setGeoJsonSource(RichLayers.source, collection);
    if (listEquals(hiddenMarks, _state._richHidden)) return;
    _state._richHidden = hiddenMarks;
    // A place standing out hides its small badge; a group of marks keeps
    // its own (it has no `mark`).
    await c.setFilter(RouteLayers.badgesOf(RouteLayers.minorSource), [
      'match',
      ['get', RichLayers.mark],
      if (hiddenMarks.isEmpty) [''] else hiddenMarks,
      false,
      true,
    ]);
  }
}

/// What a frame of the glide sent: the vehicle, and the camera while it
/// followed.
typedef _SentFrame = ({
  LatLng position,
  double? course,
  ({LatLng target, double zoom, double bearing, double tilt})? view,
});
