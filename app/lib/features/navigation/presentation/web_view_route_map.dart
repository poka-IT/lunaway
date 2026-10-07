import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_page_policy.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/shared/theme/motion.dart';

final _log = Logger('route_map');

/// The route map on macOS and Windows: the desktop map page
/// (`assets/map/map.html` and its MapLibre GL JS) given the route layers
/// instead of the places. While guiding, `assets/map/route_motion.js`
/// glides the vehicle between fixes and rides the camera with it, as
/// the maplibre_gl route map does on the other platforms.
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
  List<RouteMapMark>? _sentMarks;
  RouteCamera? _sentCamera;
  VehiclePuck? _sentVehicle;
  EdgeInsets? _sentFollowPadding;
  Size _size = Size.zero;

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
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final reduced = Motion.reduced(context);
    final arrow = base64Encode(await vehicleArrowPng(ratio));
    if (!mounted) return;
    final start = switch (_props.camera) {
      FitCamera(:final bounds) => bounds.center,
      FollowCamera(:final position) => position,
    };
    await _call('return window.lunaway.init(options);', {
      'options': {
        'style': _styleArgument(_props.style),
        'lat': start.lat,
        'lon': start.lon,
        'zoom': 11,
        // The route map's one image, the vehicle's arrow, drawn at the
        // screen's density.
        'pixelRatio': ratio,
        'images': {RouteLayers.vehicleImage: arrow},
        'spec': _spec(dark: _props.dark),
        'reducedMotion': reduced,
      },
    });
  }

  /// The route layers in the GL JS style syntax. The marks with an id
  /// (places, stations, stops) are tappable; the cards beside the map pick
  /// the route.
  static Map<String, Object?> _spec({required bool dark}) => {
    'clusterSource': RouteLayers.routeSource,
    'selectionLayer': RouteLayers.marks,
    'hit': {
      'select': FreeTap.select,
      'freePoint': FreeTap.freePoint,
      'freePointMinZoom': FreeTap.freePointMinZoom,
    },
    // Every mark, those without an id too: a tap on the destination or a
    // warning is no tap on bare map (the page ignores a feature without an
    // id, and sends nothing).
    'tappable': const [RouteLayers.tappableMarks, RouteLayers.marks],
    'sources': [
      {'id': RouteLayers.alternativesSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.marksSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.routeSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.vehicleSource, 'options': <String, Object?>{}},
    ],
    'layers': [
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
      // A start or a warning drawn over a place never hides it from a tap.
      _marks(RouteLayers.marks, const [
        '!',
        ['has', 'id'],
      ]),
      _marks(RouteLayers.tappableMarks, const ['has', 'id']),
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
          'icon-ignore-placement': true,
        },
      },
    ],
  };

  static Map<String, Object?> _marks(String id, List<Object> filter) => {
    'id': id,
    'type': 'circle',
    'source': RouteLayers.marksSource,
    'filter': filter,
    'paint': {
      'circle-color': ['get', 'fill'],
      'circle-radius': ['get', 'radius'],
      'circle-stroke-color': RouteLook.markStroke,
      'circle-stroke-width': RouteLook.markStrokeWidth,
    },
  };

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
        _sentMarks = null;
        _sentCamera = null;
        _sentVehicle = null;
        _sentFollowPadding = null;
        if (_style != null && _props.style != _style) {
          _setStyle();
        } else {
          _schedule();
        }
      case 'place':
        if (event['id'] case final String id) _props.onMarkTap?.call(id);
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

  void _setStyle() {
    _style = _props.style;
    unawaited(
      _call('return window.lunaway.setStyle(style, spec);', {
        'style': _styleArgument(_props.style),
        'spec': _spec(dark: _props.dark),
      }),
    );
  }

  @override
  void didUpdateWidget(WebViewRouteMap old) {
    super.didUpdateWidget(old);
    if (_ready && (_props.style != _style || _props.dark != old.props.dark)) {
      _setStyle();
      return;
    }
    _schedule();
  }

  void _schedule() {
    _queue = _queue.then((_) => _sync()).catchError((Object e, StackTrace st) {
      _log.warning('route map update failed', e, st);
    });
  }

  Future<void> _sync() async {
    if (!_ready) return;
    final p = _props;
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
    if (!identical(p.marks, _sentMarks)) {
      _sentMarks = p.marks;
      await _call('return window.lunaway.setData(id, data);', {
        'id': RouteLayers.marksSource,
        'data': routeMarksCollection(p.marks),
      });
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
    if (camera is FollowCamera && camera != _sentCamera) {
      _sentCamera = camera;
      final pad = p.padding;
      final free = math.max(0, _size.height - pad.top - pad.bottom);
      final padding = EdgeInsets.fromLTRB(pad.left, pad.top + free * 0.45, pad.right, pad.bottom);
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
        },
      });
    }
    if (camera != _sentCamera && camera is FitCamera) {
      // Whether the page follows is its own state: a resize clears
      // _sentCamera while it still does.
      if (_sentFollowPadding != null) {
        _sentFollowPadding = null;
        await _call('return window.lunawayRoute.follow(null);');
      }
      _sentCamera = camera;
      final pad = p.padding;
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

  @override
  void dispose() {
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
