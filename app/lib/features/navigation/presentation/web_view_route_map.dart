import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/map_page_policy.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_mark_layers.dart';
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

  /// The marks lit, by index, as the page has them.
  Set<int> _sentLit = const {};
  int? _sentFocus;
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
    final badges = await routeBadgePngs(ratio);
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
        // The vehicle's arrow and the badges of the marks, drawn at the
        // screen's density.
        'pixelRatio': ratio,
        'images': {
          RouteLayers.vehicleImage: arrow,
          for (final MapEntry(:key, :value) in badges.entries) key: base64Encode(value),
        },
        'spec': _spec(dark: _props.dark),
        'reducedMotion': reduced,
      },
    });
    await _call('return window.lunawayMarks.listen(layers);', {'layers': RouteLayers.badges});
  }

  /// The route layers in the GL JS style syntax. Every badge is a target
  /// (lunawayHits.pick, by routeHitShapes): a mark reports itself, a group
  /// zooms in; the cards beside the map pick the route.
  static Map<String, Object?> _spec({required bool dark}) => {
    'tappable': [...RouteLayers.badges],
    'sources': [
      {'id': RouteLayers.alternativesSource, 'options': <String, Object?>{}},
      for (final s in RouteLayers.markSources)
        {'id': s, 'options': RouteMarkStyle.sourceOptions(s)},
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
      ...RouteMarkStyle.jsonLayers(),
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
        _sentLit = const {};
        _sentFocus = _props.focus?.serial;
        _sentCamera = null;
        _sentVehicle = null;
        _sentFollowPadding = null;
        if (_style != null && _props.style != _style) {
          _setStyle();
        } else {
          _schedule();
        }
      case 'mark':
        if (event['id'] case final String id) {
          _props.onMarkTap?.call(id, at: _pointOf(event));
        }
      case 'empty':
        _props.onEmptyTap?.call();
      case 'movestart':
        _props.onCameraMove?.call();
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
      'zoom': RouteMarkStyle.clusterMaxZoom + 0.5,
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
