import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_page_policy.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_mark_layers.dart';
import 'package:lunaway/features/navigation/presentation/route_place_layers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:lunaway/shared/theme/motion.dart';

final _log = Logger('route_map');

/// The route map on macOS and Windows: the desktop map page
/// (`assets/map/map.html` and its MapLibre GL JS) given the route layers
/// instead of the places. While guiding, `assets/map/route_motion.js`
/// glides the vehicle between fixes and rides the camera with it, as
/// the maplibre_gl route map does on the other platforms, and stops
/// following at the user's first gesture.
///
/// As for the main map, the web view holds the app's bridge, so it holds
/// nothing but the map page.
class WebViewRouteMap extends ConsumerStatefulWidget {
  const new(this.props, {super.key});

  final RouteMapProps props;

  @override
  ConsumerState<WebViewRouteMap> createState() => _WebViewRouteMapState();
}

class _WebViewRouteMapState extends ConsumerState<WebViewRouteMap> {
  PlatformInAppWebViewController? _web;
  Uri? _mapPage;
  bool _ready = false;
  String? _style;
  Future<void> _queue = Future.value();
  List<RouteMapLine>? _sentLines;

  /// The zones sent, with the lines they were cut from.
  (List<RouteMapLine>, List<RouteSpan>)? _sentZones;
  List<RouteMapMark>? _sentMarks;

  /// The marks lit, by index, as the page has them.
  Set<int> _sentLit = const {};
  int? _sentFocus;
  RouteCamera? _sentCamera;
  VehiclePuck? _sentVehicle;
  EdgeInsets? _sentFollowPadding;
  RouteMapPlaces? _sentPlaces;
  bool? _sentGuiding;
  bool? _sentWatching;
  Size _size = Size.zero;

  /// The places of the last spec given to the page.
  RouteMapPlaces? _specPlaces;

  /// A gesture of the user stopped following in the page; the camera stays
  /// where the user puts it until following starts again from another view.
  bool _heldByUser = false;

  /// The rich marks, and when their passes run.
  late final RichMarkDriver _rich = RichMarkDriver(_PageRichEngine(this), onReady: _requestRich);
  late final RichPasses _richPasses = RichPasses(_richPass);

  /// The route marks the rich marks hide, as the page's filter has them.
  List<String>? _richHidden;

  RouteMapProps get _props => widget.props;

  late final PlatformInAppWebViewWidget _view = PlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams(
      initialFile: 'assets/map/map.html',
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        disableContextMenu: true,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (controller) {
        final web = controller as PlatformInAppWebViewController;
        _web = web;
        web.addJavaScriptHandler(handlerName: 'lunaway', callback: _onEvent);
      },
      shouldOverrideUrlLoading: (_, action) => _decide(action.request.url),
      onCreateWindow: (_, action) async {
        await _decide(action.request.url);
        return false;
      },
      onLoadStop: (_, url) {
        final loaded = url == null ? null : Uri.tryParse(url.toString());
        if (_mapPage == null && decideMapNavigation(loaded, mapPage: null) == .allow) {
          _mapPage = loaded;
        }
        if (_onMapPage(loaded)) unawaited(_init());
      },
      onConsoleMessage: (_, message) => _log.info('route map js: ${message.message}'),
    ),
  );

  bool _onMapPage(Uri? url) {
    final page = _mapPage;
    return page != null && isMapPage(url, mapPage: page);
  }

  Future<NavigationActionPolicy> _decide(WebUri? url) async {
    final target = url == null ? null : Uri.tryParse(url.toString());
    switch (decideMapNavigation(target, mapPage: _mapPage)) {
      case MapPageNavigation.allow:
        return NavigationActionPolicy.ALLOW;
      case MapPageNavigation.openExternally:
        await ref.read(externalActionsProvider).openUrl(target!);
        return NavigationActionPolicy.CANCEL;
      case MapPageNavigation.block:
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<Object?> _call(String body, [Map<String, Object?> arguments = const {}]) async {
    final web = _web;
    if (web == null) return null;
    final current = await web.getUrl();
    if (!_onMapPage(current == null ? null : Uri.tryParse(current.toString()))) return null;
    final result = await web.callAsyncJavaScript(functionBody: body, arguments: arguments);
    if (result?.error != null) _log.warning('route map js error: ${result!.error}');
    return result?.value;
  }

  static Object _styleArgument(String style) =>
      style.trimLeft().startsWith('{') ? jsonDecode(style) as Object : style;

  Future<void> _init() async {
    _style = _props.style;
    _specPlaces = _props.places;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final reduced = Motion.reduced(context);
    final arrow = base64Encode(await vehicleArrowPng(ratio));
    final badges = await routeBadgePngs(ratio);
    final pins = _props.places == null
        ? const <String, Uint8List>{}
        : await PinSprites.load(PinSprites.ratioFor(ratio));
    if (!mounted) return;
    final start = initialCamera(_props);
    await _call('return window.lunaway.init(options);', {
      'options': {
        'style': _styleArgument(_props.style),
        'lat': start.target.lat,
        'lon': start.target.lon,
        'zoom': start.zoom,
        'bearing': start.bearing,
        'pitch': start.tilt,
        // The vehicle's arrow and the badges of the marks, drawn at the
        // screen's density.
        'pixelRatio': ratio,
        'images': {
          RouteLayers.vehicleImage: arrow,
          for (final MapEntry(:key, :value) in badges.entries) key: base64Encode(value),
          for (final id in RoutePlaceLayers.imageIds())
            if (pins[id] case final bytes?) id: base64Encode(bytes),
        },
        'spec': _spec(dark: _props.dark, places: _props.places, ratio: ratio),
        'reducedMotion': reduced,
      },
    });
    await _call('return window.lunawayMarks.listen(layers);', {
      // A rich mark standing for a route mark tells its tooltip as the
      // mark's badge does.
      'layers': [...RouteLayers.badges, RichLayers.marks],
    });
  }

  /// The route layers in the GL JS style syntax. Every badge is a target
  /// (lunawayHits.pick, by routeHitShapes): a mark reports itself, a group
  /// zooms in; the cards beside the map pick the route. The places and the
  /// points of [places] lie under the route and open their card.
  static Map<String, Object?> _spec({
    required bool dark,
    required RouteMapPlaces? places,
    required double ratio,
  }) => {
    'hit': {'wider': FreeTap.wider, 'freePointMinZoom': FreeTap.freePointMinZoom},
    'tappable': [
      ...RouteLayers.badges,
      RichLayers.marks,
      if (places != null) ...RoutePlaceLayers.tappable,
    ],
    // A rich mark of a place of the tiles opens that place.
    'richLayer': RichLayers.marks,
    if (places != null)
      // A pin of the places reports itself (onClick in lunaway_map.js); the
      // guidance lists none.
      'placeTiles': {
        'source': RoutePlaceLayers.placeSource,
        'sourceLayer': PlaceTiles.pinsSourceLayer,
        'layers': [RoutePlaceLayers.placePins],
        'pinZoom': PlaceTiles.pinZoom,
        'filter': places.placeFilter ?? RoutePlaceLayers.none,
        'probe': false,
      },
    'sources': [
      if (places != null) ...RoutePlaceLayers.jsonSources(places),
      {'id': RouteLayers.alternativesSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.zonesSource, 'options': <String, Object?>{}},
      for (final s in RouteLayers.markSources)
        {'id': s, 'options': RouteMarkStyle.sourceOptions(s)},
      {'id': RichLayers.source, 'options': <String, Object?>{}},
      {'id': RouteLayers.routeSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.vehicleSource, 'options': <String, Object?>{}},
    ],
    'layers': [
      // The pins are shipped at their own density and added at the
      // screen's (pixelRatio): sized back as the main map draws them.
      if (places != null) ..._placeLayers(places, ratio / PinSprites.ratioFor(ratio)),
      _line(
        RouteLayers.alternativesCasing,
        RouteLayers.alternativesSource,
        RouteLook.alternativeCasing(dark: dark),
        RouteLook.alternativeWidth + 3,
      ),
      _line(
        RouteLayers.alternatives,
        RouteLayers.alternativesSource,
        RouteLook.alternative(dark: dark),
        RouteLook.alternativeWidth,
      ),
      // Under the chosen route, the band of its danger zones.
      {
        ..._line(RouteLayers.zones, RouteLayers.zonesSource, RouteLook.zone, RouteLook.zoneWidth),
        'paint': {
          'line-color': RouteLook.zone,
          'line-width': RouteLook.zoneWidth,
          'line-opacity': RouteLook.zoneOpacity,
        },
      },
      _line(
        RouteLayers.routeCasing,
        RouteLayers.routeSource,
        RouteLook.casing(dark: dark),
        RouteLook.casingWidth,
      ),
      _line(
        RouteLayers.route,
        RouteLayers.routeSource,
        RouteLook.line(dark: dark),
        RouteLook.lineWidth,
      ),
      // The rich marks over the minor marks (one is the place's own small
      // badge, hidden while its rich mark shows), under those about the
      // road, as on the other engines.
      for (final layer in RouteMarkStyle.jsonLayers())
        if (layer['source'] == RouteLayers.minorSource) layer,
      {
        'id': RichLayers.marks,
        'type': 'symbol',
        'source': RichLayers.source,
        'layout': RichLayers.layout(1),
      },
      for (final layer in RouteMarkStyle.jsonLayers())
        if (layer['source'] != RouteLayers.minorSource) layer,
      {
        'id': RouteLayers.vehicle,
        'type': 'symbol',
        'source': RouteLayers.vehicleSource,
        'layout': {
          'icon-image': RouteLayers.vehicleImage,
          'icon-rotate': ['get', 'course'],
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          'icon-allow-overlap': true,
          // The arrow keeps the pins of the places off itself, as on the
          // other engines.
          'icon-ignore-placement': false,
          'icon-padding': RoutePlaceLayers.vehicleClearance,
        },
      },
    ],
  };

  /// The places' and the points' layers, their images drawn at [scale].
  static List<Map<String, Object?>> _placeLayers(RouteMapPlaces places, double scale) => [
    for (final layer in RoutePlaceLayers.jsonLayers(places))
      {
        ...layer,
        'layout': {
          ...layer['layout']! as Map<String, Object?>,
          'icon-size': layer['id'] == RoutePlaceLayers.placePins
              ? RoutePlaceLayers.placeSize(scale)
              : RoutePlaceLayers.poiSize(scale),
        },
      },
    // Every place the filter keeps in view, even one whose pin found no
    // room: what the rich marks choose among.
    {
      'id': RichLayers.probe,
      'type': 'circle',
      'source': RoutePlaceLayers.placeSource,
      'source-layer': PlaceTiles.pinsSourceLayer,
      'minzoom': RoutePlaceLayers.placeMinZoom,
      'filter': places.placeFilter ?? RoutePlaceLayers.none,
      'layout': {'visibility': places.placeFilter == null ? 'none' : 'visible'},
      'paint': RichLayers.probePaint,
    },
  ];

  static Map<String, Object?> _line(String id, String source, String color, double width) => {
    'id': id,
    'type': 'line',
    'source': source,
    'layout': {'line-join': 'round', 'line-cap': 'round'},
    'paint': {'line-color': color, 'line-width': width},
  };

  void _onEvent(List<dynamic> arguments) {
    if (arguments.isEmpty || arguments.first is! Map) return;
    final event = Map<String, Object?>.from(arguments.first as Map);
    switch (event['type']) {
      case 'ready':
        _ready = true;
        _sentLines = null;
        _sentZones = null;
        _sentMarks = null;
        _sentLit = const {};
        _sentFocus = _props.focus?.serial;
        _sentCamera = null;
        _sentVehicle = null;
        _sentFollowPadding = null;
        _sentGuiding = null;
        _sentWatching = null;
        // A new page follows nothing yet: no gesture holds it.
        _heldByUser = false;
        // A new style holds none of the rich marks' images.
        _rich.reset();
        _richHidden = null;
        // The spec the page holds carries the places as they were sent.
        _sentPlaces = _specPlaces;
        if (_style != null && _props.style != _style) {
          _setStyle();
        } else {
          _schedule();
        }
      case 'mark':
        if (event['id'] case final String id) {
          _props.onMarkTap?.call(id, at: _pointOf(event));
        }
      case 'movestart':
        _props.onCameraMove?.call();
      // The camera came to rest: other places may stand out.
      case 'idle':
        _requestRich();
      case 'gesture':
        _heldByUser = true;
        _props.onGesture?.call();
      case 'touch':
        _props.onTouch?.call(event['down'] == true);
      case 'rest':
        _props.onRest?.call(freeViewOfPage(event, size: _size));
      case 'place':
        final place = placeFromTile(
          event['properties'] as Map<Object?, Object?>?,
          event['coordinates'] as List<Object?>?,
        );
        if (place != null) _props.onPlaceTap?.call(place);
      case 'poi':
        final poi = PoiFeature.fromTile(
          event['properties'] as Map<Object?, Object?>?,
          event['coordinates'] as List<Object?>?,
        );
        if (poi != null) _props.onPoiTap?.call(poi);
      case 'hover':
        _props.onMarkHover?.call(switch ((_pointOf(event), event['mark'], event['group'])) {
          (final at?, final String id, _) => RouteMapHover(at: at, mark: id),
          (final at?, _, final Map<Object?, Object?> group) => RouteMapHover(
            at: at,
            group: RouteMarkStyle.groupCounts(group),
          ),
          _ => null,
        });
      case 'longpress':
        // GL JS gives longitudes past 180 on the world's repeated copies.
        if ((event['lat'], event['lon']) case (final num lat, final num lon)
            when lat.abs() <= 90 && lon.isFinite) {
          final wrapped = (lon + 180) % 360 - 180;
          _props.onLongPress?.call(LatLng(lat.toDouble(), wrapped.toDouble()));
        }
      case 'empty':
        if ((event['lat'], event['lon'], event['zoom'])
            case (final num lat, final num lon, final num zoom)
            when lat.abs() <= 90 && lon.isFinite) {
          final wrapped = (lon + 180) % 360 - 180;
          _props.onEmptyTap?.call(LatLng(lat.toDouble(), wrapped.toDouble()), zoom.toDouble());
        }
      case 'link':
        if (Uri.tryParse('${event['url']}') case final url?) {
          unawaited(ref.read(externalActionsProvider).openUrl(url));
        }
    }
  }

  /// The point of a page event, in CSS pixels, which are the app's logical
  /// ones.
  static Offset? _pointOf(Map<String, Object?> event) => switch ((event['x'], event['y'])) {
    (final num x, final num y) => Offset(x.toDouble(), y.toDouble()),
    _ => null,
  };

  void _setStyle() {
    _style = _props.style;
    _specPlaces = _props.places;
    unawaited(
      _call('return window.lunaway.setStyle(style, spec);', {
        'style': _styleArgument(_props.style),
        'spec': _spec(
          dark: _props.dark,
          places: _props.places,
          ratio: MediaQuery.devicePixelRatioOf(context),
        ),
      }),
    );
  }

  @override
  void didUpdateWidget(WebViewRouteMap old) {
    super.didUpdateWidget(old);
    // The places came: their sources go into the spec. Gone, their layers
    // are hidden (_sync), the sources kept for their return.
    final placesCame = _props.places != null && _specPlaces == null;
    // The points of a category read on demand come in other tiles: the
    // page's source changes with them.
    final poiTilesMoved =
        _props.places != null &&
        _specPlaces != null &&
        _props.places!.poiTileJsonUrl != _specPlaces!.poiTileJsonUrl;
    if (_ready &&
        (_props.style != _style || _props.dark != old.props.dark || placesCame || poiTilesMoved)) {
      _setStyle();
      return;
    }
    _heldByUser = heldAfter(held: _heldByUser, before: old.props.camera, after: _props.camera);
    _schedule();
  }

  void _schedule() {
    _queue = _queue
        .then((_) => _sync())
        .catchError((Object e, StackTrace st) {
          _log.warning('route map update failed', e, st);
        })
        .whenComplete(_requestRich);
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
        ratio: MediaQuery.devicePixelRatioOf(context),
        line: _props.lines.firstWhereOrNull((l) => l.selected)?.points ?? const [],
        vehicle: _props.vehicle?.position,
        marks: [
          for (final m in _props.marks)
            if (m.kind != RouteMarkKind.place) m.position,
        ],
      ),
    );
  }

  Future<void> _sync() async {
    if (!_ready) return;
    final p = _props;
    if (p.guiding != _sentGuiding) {
      _sentGuiding = p.guiding;
      await _call('return window.lunawayRoute.guiding(on);', {'on': p.guiding});
    }
    // The preview's map tells the user's gestures when its screen listens.
    final watching = p.onGesture != null;
    if (watching != _sentWatching) {
      _sentWatching = watching;
      await _call('return window.lunawayRoute.watch(on);', {'on': watching});
    }
    final places = p.places;
    if (places != _sentPlaces && _specPlaces != null) {
      _sentPlaces = places;
      for (final (id, filter) in [
        (RoutePlaceLayers.placePins, places?.placeFilter),
        (RichLayers.probe, places?.placeFilter),
        (RoutePlaceLayers.poiPins, places?.poiFilter),
      ]) {
        await _call('return window.lunaway.setLayer(id, filter, visible);', {
          'id': id,
          'filter': filter ?? RoutePlaceLayers.none,
          'visible': filter != null,
        });
      }
    }
    if (!identical(p.lines, _sentLines)) {
      _sentLines = p.lines;
      await _call('return window.lunaway.setData(id, data);', {
        'id': RouteLayers.alternativesSource,
        'data': routeLinesCollection(p.lines, selected: false),
      });
      await _call('return window.lunaway.setData(id, data);', {
        'id': RouteLayers.routeSource,
        'data': routeLinesCollection(p.lines, selected: true),
      });
    }
    if (_sentZones case (final lines, final zones)
        when listEquals(lines, p.lines) && listEquals(zones, p.zones)) {
      // Sent already.
    } else {
      _sentZones = (p.lines, p.zones);
      await _call('return window.lunaway.setData(id, data);', {
        'id': RouteLayers.zonesSource,
        'data': routeZonesCollection(p.lines, p.zones),
      });
    }
    if (!listEquals(p.marks, _sentMarks)) {
      _sentMarks = p.marks;
      for (final MapEntry(:key, :value) in routeMarkSources(p.marks).entries) {
        await _call('return window.lunaway.setData(id, data);', {'id': key, 'data': value});
      }
      // The states name features by their index in the old marks.
      await _call('return window.lunawayMarks.clear(sources);', {
        'sources': RouteLayers.markSources,
      });
      _sentLit = const {};
    }
    await _light(p.highlighted);
    if (p.focus case final focus? when focus.serial != _sentFocus) {
      _sentFocus = focus.serial;
      unawaited(_fly(focus));
    }
    final vehicle = p.vehicle;
    if (vehicle != _sentVehicle) {
      final before = _sentVehicle;
      _sentVehicle = vehicle;
      if (vehicle == null) {
        await _call('return window.lunawayRoute.clear(id);', {'id': RouteLayers.vehicleSource});
      } else {
        await _call('return window.lunawayRoute.vehicle(id, lat, lon, course, jump);', {
          'id': RouteLayers.vehicleSource,
          'lat': vehicle.position.lat,
          'lon': vehicle.position.lon,
          'course': vehicle.course,
          'jump': before == null || _reduced,
        });
      }
    }
    final camera = p.camera;
    // A gesture that stopped following in the page keeps the user's view
    // until the screen asks again to follow (cameraStep, heldAfter).
    final step = cameraStep(sent: _sentCamera, next: camera, heldByUser: _heldByUser);
    if (step == CameraStep.none) return;
    _sentCamera = camera;
    if (camera is FollowCamera) {
      final padding = followInsets(_size, p.padding);
      _sentFollowPadding = padding;
      await _call('return window.lunawayRoute.follow(options);', {
        'options': {
          'zoom': camera.zoom,
          'padding': {
            'top': padding.top,
            'bottom': padding.bottom,
            'left': padding.left,
            'right': padding.right,
          },
          'ease': _reduced ? 0 : camera.ease.inMilliseconds,
          'enter': step == CameraStep.enterFollow,
        },
      });
      return;
    }
    if (step == CameraStep.free) {
      _sentFollowPadding = null;
      await _call('return window.lunawayRoute.free();');
      return;
    }
    if (camera is FitCamera) {
      // Whether the page follows is its own state: a resize clears
      // _sentCamera while it still does.
      if (step == CameraStep.overview || _sentFollowPadding != null) {
        _sentFollowPadding = null;
        await _call('return window.lunawayRoute.overview();');
      }
      final pad = p.padding + camera.room;
      await _call('return window.lunaway.fitBounds(s, w, n, e, padding);', {
        's': camera.bounds.south,
        'w': camera.bounds.west,
        'n': camera.bounds.north,
        'e': camera.bounds.east,
        'padding': {
          'top': pad.top + 48,
          'bottom': pad.bottom + 48,
          'left': pad.left + 48,
          'right': pad.right + 48,
        },
      });
    }
  }

  /// Lights the marks of [highlighted] and puts out the others, sending
  /// only what changed.
  Future<void> _light(Set<String> highlighted) async {
    final marks = _props.marks;
    final lit = {
      for (final (i, m) in marks.indexed)
        if (highlighted.contains(m.id)) i,
    };
    if (setEquals(lit, _sentLit)) return;
    final changed = lit.union(_sentLit).difference(lit.intersection(_sentLit));
    _sentLit = lit;
    await _call('return window.lunawayMarks.light(states);', {
      'states': [
        for (final i in changed)
          if (i < marks.length)
            {
              'source': routeMarkSource(marks[i]),
              'id': routeMarkFeatureId(i),
              'lit': lit.contains(i),
            },
      ],
    });
  }

  /// Brings the marks of [focus] into view, then three beats of their ring,
  /// as the maplibre_gl route map does.
  Future<void> _fly(RouteMapFocus focus) async {
    final duration = Motion.of(context, Motion.camera);
    await _call('return window.lunawayMarks.fly(lat, lon, zoom, duration);', {
      'lat': focus.position.lat,
      'lon': focus.position.lon,
      'zoom': RouteMarkStyle.focusZoom,
      'duration': duration.inMilliseconds,
    });
    if (_reduced) return;
    await Future<void>.delayed(duration);
    final keep = _props.highlighted;
    for (var beat = 0; beat < 3; beat++) {
      if (!mounted) return;
      await _light({...keep, ...focus.marks});
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      await _light(keep.difference(focus.marks.toSet()));
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    if (mounted) await _light(_props.highlighted);
  }

  @override
  void dispose() {
    _richPasses.dispose();
    _view.dispose();
    super.dispose();
  }

  bool get _reduced => mounted && Motion.reduced(context);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.biggest != _size) {
        _size = box.biggest;
        // The follow camera's padding follows the map's height.
        if (_sentFollowPadding != null) {
          _sentCamera = null;
          WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
        }
      }
      return _view.build(context);
    },
  );
}

/// The rich marks on the desktop page (`assets/map/route_rich.js`).
final class _PageRichEngine implements RichMarkEngine {
  new(this._state);

  final _WebViewRouteMapState _state;

  @override
  Future<List<({Map<Object?, Object?> properties, LatLng at})>> tilePlaces() async {
    if (_state._props.places?.placeFilter == null) return const [];
    final found = await _state._call('return window.lunawayRich.places(layer);', {
      'layer': RichLayers.probe,
    });
    return [
      if (found is List)
        for (final f in found)
          if (f case {'p': final Map<Object?, Object?> p, 'c': [final num lon, final num lat, ...]})
            (properties: p, at: LatLng(lat.toDouble(), lon.toDouble())),
    ];
  }

  @override
  Future<RichView?> view(List<LatLng> points) async {
    final answer = await _state._call('return window.lunawayRich.view(points);', {
      'points': [
        for (final p in points) [p.lon, p.lat],
      ],
    });
    Offset? at(Object? p) => switch (p) {
      [final num x, final num y] => Offset(x.toDouble(), y.toDouble()),
      _ => null,
    };
    if (answer
        case {
          'points': final List<Object?> screen,
          'zoom': final num zoom,
          'pitch': final num pitch,
        }
        when screen.length == points.length) {
      return RichView(
        points: [for (final p in screen) at(p)],
        zoom: zoom.toDouble(),
        pitch: pitch.toDouble(),
        centre: at(answer['centre']),
      );
    }
    return null;
  }

  @override
  Future<bool> putImage(String id, Uint8List png) async {
    if (!_state.mounted) return false;
    final added = await _state._call('return window.lunawayRich.image(id, data, ratio);', {
      'id': id,
      'data': base64Encode(png),
      'ratio': MediaQuery.devicePixelRatioOf(_state.context),
    });
    return added == true;
  }

  @override
  Future<void> show(Map<String, Object?> collection, {required List<String> hiddenMarks}) async {
    await _state._call('return window.lunaway.setData(id, data);', {
      'id': RichLayers.source,
      'data': collection,
    });
    if (listEquals(hiddenMarks, _state._richHidden)) return;
    _state._richHidden = hiddenMarks;
    // A place standing out hides its small badge; a group of marks keeps
    // its own (it has no `mark`).
    await _state._call('return window.lunaway.setLayer(id, filter, visible);', {
      'id': RouteLayers.badgesOf(RouteLayers.minorSource),
      'filter': [
        'match',
        ['get', RichLayers.mark],
        if (hiddenMarks.isEmpty) [''] else hiddenMarks,
        false,
        true,
      ],
      'visible': true,
    });
  }
}
