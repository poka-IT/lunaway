import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/map/presentation/pin_images.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/shared/theme/map_look.dart';

final _log = Logger('map');

/// The map on macOS and Windows, where maplibre_gl has no implementation:
/// MapLibre GL JS shipped in the app's assets, in a web view, driven through
/// a small bridge (`assets/map/lunaway_map.js`). It draws the same layers as
/// the native map, from the same [MapStyle].
class WebViewLunaMap extends StatefulWidget {
  const new(this.props, {super.key});

  final LunaMapProps props;

  @override
  State<WebViewLunaMap> createState() => _WebViewLunaMapState();
}

class _WebViewLunaMapState extends State<WebViewLunaMap> implements LunaMapController {
  PlatformInAppWebViewController? _web;
  late final PlatformInAppWebViewWidget _view = PlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams(
      initialFile: 'assets/map/map.html',
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        disableContextMenu: true,
        allowFileAccessFromFileURLs: true,
      ),
      onWebViewCreated: (controller) {
        final web = controller as PlatformInAppWebViewController;
        _web = web;
        web.addJavaScriptHandler(handlerName: 'lunaway', callback: _onEvent);
      },
      onLoadStop: (_, url) {
        _log.fine('map page loaded: $url');
        unawaited(_init());
      },
      onReceivedError: (_, request, error) =>
          _log.warning('map page error: ${error.description} (${request.url})'),
      onConsoleMessage: (_, message) => _log.info('map js: ${message.message}'),
    ),
  );

  bool _ready = false;
  String? _style;
  double _zoom = 0;
  List<PlaceSummary>? _sentPlaces;
  String? _sentSelected;
  LatLng? _sentPoint;
  Future<void> _queue = Future.value();

  LunaMapProps get _props => widget.props;

  Future<Object?> _call(String body, [Map<String, Object?> arguments = const {}]) async {
    final web = _web;
    if (web == null) return null;
    final result = await web.callAsyncJavaScript(functionBody: body, arguments: arguments);
    if (result?.error != null) _log.warning('map js error: ${result!.error}');
    return result?.value;
  }

  Future<void> _init() async {
    final images = await renderPinImages();
    _style = _props.styleUrl;
    await _call('return window.lunaway.init(options);', {
      'options': {
        'style': _props.styleUrl,
        'lat': _props.initialCenter.lat,
        'lon': _props.initialCenter.lon,
        'zoom': _props.initialZoom,
        'images': {for (final e in images.entries) e.key: base64Encode(e.value)},
        'spec': _spec,
      },
    });
  }

  /// The sources and layers of [MapStyle], in the GL JS style syntax.
  static final Map<String, Object?> _spec = {
    'clusterSource': MapStyle.placesSource,
    'tappable': MapStyle.tappableLayers,
    'sources': [
      {
        'id': MapStyle.placesSource,
        'options': {
          'cluster': true,
          'clusterRadius': MapStyle.clusterRadius,
          'clusterMaxZoom': MapStyle.clusterMaxZoom,
        },
      },
      {'id': MapStyle.selectionSource, 'options': <String, Object?>{}},
    ],
    'layers': [
      {
        'id': MapStyle.clustersLayer,
        'type': 'circle',
        'source': MapStyle.placesSource,
        'filter': MapStyle.clusterFilter,
        'paint': {
          'circle-color': MapLook.clusterFill,
          'circle-radius': MapLook.clusterRadius,
          'circle-stroke-width': MapLook.clusterStrokeWidth,
          'circle-stroke-color': MapLook.clusterStroke,
          'circle-opacity': MapLook.clusterOpacity,
        },
      },
      {
        'id': MapStyle.clusterCountLayer,
        'type': 'symbol',
        'source': MapStyle.placesSource,
        'filter': MapStyle.clusterFilter,
        'layout': {
          'text-field': ['get', 'point_count_abbreviated'],
          'text-font': MapLook.clusterFont,
          'text-size': MapLook.clusterTextSize,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': MapLook.clusterText},
      },
      {
        'id': MapStyle.placesLayer,
        'type': 'symbol',
        'source': MapStyle.placesSource,
        'filter': MapStyle.pointFilter,
        'layout': {
          'icon-image': ['get', 'icon'],
          'icon-size': MapLook.pinSize(),
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          'symbol-sort-key': ['get', 'rank'],
        },
      },
      {
        'id': MapStyle.selectionHaloLayer,
        'type': 'circle',
        'source': MapStyle.selectionSource,
        'paint': {
          'circle-radius': MapLook.selectionHaloRadius,
          'circle-color': MapLook.selection,
          'circle-opacity': MapLook.selectionHaloOpacity,
          'circle-stroke-color': MapLook.selection,
          'circle-stroke-width': MapLook.selectionStrokeWidth,
        },
      },
      {
        'id': MapStyle.selectionPinLayer,
        'type': 'symbol',
        'source': MapStyle.selectionSource,
        'layout': {
          'icon-image': ['get', 'icon'],
          'icon-size': MapLook.selectedPinSize(),
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
    ],
  };

  void _onEvent(List<dynamic> arguments) {
    if (arguments.isEmpty || arguments.first is! Map) return;
    final event = Map<String, Object?>.from(arguments.first as Map);
    switch (event['type']) {
      case 'ready':
        final first = !_ready;
        _ready = true;
        _sentPlaces = null;
        _sentSelected = null;
        _sentPoint = null;
        _scheduleSync();
        if (first) _props.onMapReady(this);
      case 'idle':
        _zoom = (event['zoom']! as num).toDouble();
        _props.onViewportChanged(
          MapViewport(
            bounds: GeoBounds(
              south: (event['south']! as num).toDouble(),
              west: (event['west']! as num).toDouble(),
              north: (event['north']! as num).toDouble(),
              east: (event['east']! as num).toDouble(),
            ),
            center: LatLng((event['lat']! as num).toDouble(), (event['lon']! as num).toDouble()),
            zoom: _zoom,
          ),
        );
      case 'place':
        _props.onPlaceTap('${event['id']}');
      case 'longpress':
        _props.onLongPress(
          LatLng((event['lat']! as num).toDouble(), (event['lon']! as num).toDouble()),
        );
    }
  }

  @override
  void didUpdateWidget(WebViewLunaMap old) {
    super.didUpdateWidget(old);
    if (_ready && _style != null && _props.styleUrl != _style) {
      _style = _props.styleUrl;
      unawaited(_call('return window.lunaway.setStyle(url);', {'url': _props.styleUrl}));
      return;
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    _queue = _queue.then((_) => _sync()).catchError((Object e, StackTrace st) {
      _log.warning('map update failed', e, st);
    });
  }

  Future<void> _sync() async {
    if (!_ready) return;
    final props = _props;
    // The data goes as call arguments, which the web view serialises safely;
    // text interpolated into a script would break on quotes and accents.
    if (!identical(props.places, _sentPlaces)) {
      _sentPlaces = props.places;
      final json = await placesGeoJsonInBackground(props.places);
      await _call('return window.lunaway.setData(id, JSON.parse(data));', {
        'id': MapStyle.placesSource,
        'data': json,
      });
    }
    if (props.selectedId != _sentSelected || props.markedPoint != _sentPoint) {
      _sentSelected = props.selectedId;
      _sentPoint = props.markedPoint;
      final selected = props.places.where((p) => p.id == props.selectedId).firstOrNull;
      await _call('return window.lunaway.setData(id, data);', {
        'id': MapStyle.selectionSource,
        'data': pointFeatureCollection(selected, point: props.markedPoint),
      });
    }
  }

  @override
  Future<void> moveTo(LatLng center, {double? zoom}) async {
    // Wait for the frame that lays out a sheet the selection just opened.
    await WidgetsBinding.instance.endOfFrame;
    final z = zoom ?? _zoom;
    final target = centerForPadding(center, z, _props.padding);
    await _call('return window.lunaway.moveTo(lat, lon, zoom);', {
      'lat': target.lat,
      'lon': target.lon,
      'zoom': z,
    });
  }

  @override
  Future<void> fitBounds(GeoBounds bounds) async {
    final p = _props.padding;
    await _call('return window.lunaway.fitBounds(s, w, n, e, padding);', {
      's': bounds.south,
      'w': bounds.west,
      'n': bounds.north,
      'e': bounds.east,
      'padding': {
        'top': p.top + 40,
        'bottom': p.bottom + 40,
        'left': p.left + 40,
        'right': p.right + 40,
      },
    });
  }

  @override
  Future<LatLng?> locateUser() async {
    try {
      final geo = GeolocatorPlatform.instance;
      var permission = await geo.checkPermission();
      if (permission == LocationPermission.denied) permission = await geo.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await geo.getCurrentPosition().timeout(const Duration(seconds: 15));
      return LatLng(position.latitude, position.longitude);
    } on Object catch (e) {
      _log.info('no position: $e');
      return null;
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
