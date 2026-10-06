import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/features/map/domain/map_page_policy.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/shared/theme/motion.dart';

final _log = Logger('route_map');

/// The route preview on macOS and Windows: the desktop map page
/// (`assets/map/map.html` and its MapLibre GL JS) given the route layers
/// instead of the places. Guidance does not run on the desktop, so the
/// camera only frames the route.
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
        'pixelRatio': 1,
        'images': <String, String>{},
        'spec': _spec(dark: _props.dark),
        'reducedMotion': Motion.reduced(context),
      },
    });
  }

  /// The route layers in the GL JS style syntax. Nothing is tappable: the
  /// cards beside the map pick the route.
  static Map<String, Object?> _spec({required bool dark}) => {
    'clusterSource': RouteLayers.routeSource,
    'selectionLayer': RouteLayers.marks,
    'tappable': const <String>[],
    'sources': [
      {'id': RouteLayers.alternativesSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.marksSource, 'options': <String, Object?>{}},
      {'id': RouteLayers.routeSource, 'options': <String, Object?>{}},
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
      {
        'id': RouteLayers.marks,
        'type': 'circle',
        'source': RouteLayers.marksSource,
        'paint': {
          'circle-color': ['get', 'fill'],
          'circle-radius': ['get', 'radius'],
          'circle-stroke-color': RouteLook.markStroke,
          'circle-stroke-width': RouteLook.markStrokeWidth,
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
        _sentCamera = null;
        if (_style != null && _props.style != _style) {
          _setStyle();
        } else {
          _schedule();
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
    final camera = p.camera;
    if (camera != _sentCamera && camera is FitCamera) {
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

  @override
  Widget build(BuildContext context) => _view.build(context);
}
