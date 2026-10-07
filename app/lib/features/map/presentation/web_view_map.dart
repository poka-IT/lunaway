import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/map/domain/map_page_policy.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/gl_place_tiles.dart';
import 'package:lunaway/features/map/presentation/map_style.dart';
import 'package:lunaway/features/map/presentation/place_tile_layers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/gl_poi_layers.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:lunaway/shared/theme/map_look.dart';
import 'package:lunaway/shared/theme/motion.dart';

final _log = Logger('map');

/// The map on macOS and Windows, where maplibre_gl has no implementation:
/// MapLibre GL JS shipped in the app's assets, in a web view, driven through
/// a small bridge (`assets/map/lunaway_map.js`). It draws the same layers as
/// the native map, from the same [MapStyle] and the same pin images.
///
/// The web view holds the app's bridge, so it holds nothing but the map
/// page: every other navigation is refused, and web links (the basemap's
/// attribution) open in the browser.
class WebViewLunaMap extends ConsumerStatefulWidget {
  const new(this.props, {super.key});

  final LunaMapProps props;

  @override
  ConsumerState<WebViewLunaMap> createState() => _WebViewLunaMapState();
}

class _WebViewLunaMapState extends ConsumerState<WebViewLunaMap> implements LunaMapController {
  PlatformInAppWebViewController? _web;
  Uri? _mapPage;
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
        // A link opening a new window never gets one in the app.
        await _decide(action.request.url);
        return false;
      },
      onLoadStop: (_, url) {
        final loaded = url == null ? null : Uri.tryParse(url.toString());
        if (_mapPage == null && decideMapNavigation(loaded, mapPage: null) == .allow) {
          _mapPage = loaded;
        }
        if (_onMapPage(loaded)) {
          unawaited(_init());
        } else {
          _log.warning('the map view loaded something else: $url');
        }
      },
      onReceivedError: (_, request, error) =>
          _log.warning('map page error: ${error.description} (${request.url})'),
      onConsoleMessage: (_, message) => _log.info('map js: ${message.message}'),
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
        _log.info('map view: blocked a navigation to $url');
        return NavigationActionPolicy.CANCEL;
    }
  }

  bool _ready = false;
  String? _style;
  double _zoom = 0;
  List<PlaceSummary>? _sentPlaces;
  PoiLayerView? _sentPois;
  PlaceTilesView? _sentTiles;
  Object? _sentSelected;
  LatLng? _sentPoint;
  Future<void> _queue = Future.value();

  LunaMapProps get _props => widget.props;

  Future<Object?> _call(String body, [Map<String, Object?> arguments = const {}]) async {
    final web = _web;
    if (web == null) return null;
    // The bridge only ever talks to the map page.
    final current = await web.getUrl();
    if (!_onMapPage(current == null ? null : Uri.tryParse(current.toString()))) return null;
    final result = await web.callAsyncJavaScript(functionBody: body, arguments: arguments);
    if (result?.error != null) _log.warning('map js error: ${result!.error}');
    return result?.value;
  }

  Future<void> _init() async {
    final ratio = PinSprites.ratioFor(MediaQuery.devicePixelRatioOf(context));
    final reducedMotion = Motion.reduced(context);
    final images = await PinSprites.load(ratio);
    _style = _props.style;
    await _call('return window.lunaway.init(options);', {
      'options': {
        'style': _styleArgument(_props.style),
        'lat': _props.initialCenter.lat,
        'lon': _props.initialCenter.lon,
        'zoom': _props.initialZoom,
        'pixelRatio': ratio,
        'images': {for (final e in images.entries) e.key: base64Encode(e.value)},
        'spec': _spec(
          dark: _props.dark,
          language: _props.language,
          pois: _props.pois,
          tiles: _props.placeTiles,
          style: _props.style,
        ),
        'reducedMotion': reducedMotion,
      },
    });
  }

  static bool _isStyleJson(String style) => style.trimLeft().startsWith('{');

  /// A style URL as is, a style document as an object.
  static Object _styleArgument(String style) =>
      _isStyleJson(style) ? jsonDecode(style) as Object : style;

  /// The sources and layers of [MapStyle], in the GL JS style syntax, and
  /// those of the points of interest when [pois] is given.
  static Map<String, Object?> _spec({
    required bool dark,
    required String language,
    PoiLayerView? pois,
    PlaceTilesView? tiles,
    String? style,
  }) => {
    'clusterSource': MapStyle.placesSource,
    'placeSelectionSource': MapStyle.selectionSource,
    'selectionLayer': MapStyle.selectionPinLayer,
    'hit': {
      'select': MapHit.select,
      'freePoint': MapHit.freePoint,
      'freePointMinZoom': MapHit.freePointMinZoom,
    },
    'tappable': [
      ...MapStyle.tappableLayers,
      if (tiles != null) ...PlaceTiles.tappable,
      if (pois != null) ...PoiMapStyle.tappable,
    ],
    if (tiles != null)
      'placeTiles': {
        'source': PlaceTiles.source,
        'sourceLayer': PlaceTiles.pinsSourceLayer,
        'layers': const [PlaceTiles.dotsLayer, PlaceTiles.pinDotsLayer, PlaceTiles.pinsLayer],
        'dotsLayer': PlaceTiles.dotsLayer,
        'pinZoom': PlaceTiles.pinZoom,
        'filter': placeTileFilter(tiles.filter),
      },
    if (pois != null)
      'pois': {
        'source': PoiMapStyle.source,
        'sourceLayer': PoiMapStyle.pointsLayer,
        'selectionSource': PoiMapStyle.selectionSource,
        'pointsMinZoom': PoiMapStyle.pointsMinZoom,
        'quietMinZoom': PoiMapStyle.quietMinZoom,
      },
    'sources': [
      if (tiles != null) {'id': PlaceTiles.source, 'vector': true, 'url': tiles.tileJsonUrl},
      if (pois != null) ...[
        {'id': PoiMapStyle.source, 'vector': true, 'url': pois.tileJsonUrl},
        {'id': PoiMapStyle.selectionSource, 'options': <String, Object?>{}},
        {'id': PoiMapStyle.fuelSource, 'options': <String, Object?>{}},
      ],
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
      // The points of interest under the places, the quiet ones under the
      // basemap's labels.
      if (pois != null) ..._poiLayers(pois, style, dark: dark),
      if (tiles != null) ...placeTileStyleLayers(tiles, dark: dark),
      {
        'id': MapStyle.clustersLayer,
        'type': 'circle',
        'source': MapStyle.placesSource,
        'filter': MapStyle.clusterFilter,
        'paint': {
          'circle-color': MapLook.clusterFill(dark: dark),
          'circle-radius': MapLook.clusterRadius,
          'circle-stroke-width': MapLook.clusterStrokeWidth,
          'circle-stroke-color': MapLook.clusterStroke(dark: dark),
          'circle-opacity': MapLook.clusterOpacity,
        },
      },
      {
        'id': MapStyle.clusterCountLayer,
        'type': 'symbol',
        'source': MapStyle.placesSource,
        'filter': MapStyle.clusterFilter,
        'layout': {
          'text-field': MapLook.clusterLabel(language),
          'text-font': MapLook.clusterFont,
          'text-size': MapLook.clusterTextSize,
          'text-allow-overlap': true,
          'text-ignore-placement': true,
        },
        'paint': {'text-color': MapLook.clusterText(dark: dark)},
      },
      {
        'id': MapStyle.placesLayer,
        'type': 'symbol',
        'source': MapStyle.placesSource,
        'filter': MapStyle.pointFilter,
        'layout': {
          'icon-image': ['get', 'icon'],
          'icon-size': MapLook.pinSize(1),
          'icon-anchor': 'bottom',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          'symbol-sort-key': ['get', 'rank'],
        },
      },
      {
        'id': MapStyle.selectionPinLayer,
        'type': 'symbol',
        'source': MapStyle.selectionSource,
        'layout': {
          'icon-image': ['get', 'icon'],
          'icon-size': 1,
          'icon-anchor': 'bottom',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
      if (pois != null)
        {
          'id': PoiMapStyle.selectionLayerId,
          'type': 'symbol',
          'source': PoiMapStyle.selectionSource,
          'layout': {
            'icon-image': ['get', 'icon'],
            'icon-size': 1,
            'icon-anchor': 'bottom',
            'icon-allow-overlap': true,
            'icon-ignore-placement': true,
          },
        },
    ],
  };

  /// The points' layers as [PoiMapStyle] draws them on maplibre_gl, in the
  /// GL JS syntax.
  static List<Map<String, Object?>> _poiLayers(
    PoiLayerView view,
    String? style, {
    required bool dark,
  }) => [
    {
      'id': PoiMapStyle.dotsLayerId,
      'type': 'symbol',
      'source': PoiMapStyle.source,
      'source-layer': PoiMapStyle.clustersLayer,
      'maxzoom': PoiMapStyle.pointsMinZoom,
      'filter': PoiMapStyle.dotsFilter(view),
      'layout': _poiDotsLayout,
    },
    {
      'id': PoiMapStyle.vendingDotsLayerId,
      'type': 'symbol',
      'source': PoiMapStyle.source,
      'source-layer': PoiMapStyle.vendingClustersLayer,
      'maxzoom': PoiMapStyle.pointsMinZoom,
      'filter': PoiMapStyle.vendingDotsFilter(view),
      'layout': {..._poiDotsLayout, 'icon-image': PoiMapStyle.vendingDotImage},
    },
    {
      'id': PoiMapStyle.quietLayerId,
      'type': 'symbol',
      'source': PoiMapStyle.source,
      'source-layer': PoiMapStyle.pointsLayer,
      'minzoom': PoiMapStyle.quietMinZoom,
      'filter': PoiMapStyle.quietFilter(view),
      'layout': _poiPinsLayout(view, quiet: true),
      'paint': {'icon-opacity': PoiMapStyle.opacity(view)},
      'before': style == null ? null : PoiMapStyle.firstLabelLayer(style),
    },
    {
      'id': PoiMapStyle.fuelLayerId,
      'type': 'symbol',
      'source': PoiMapStyle.fuelSource,
      'minzoom': PoiMapStyle.pointsMinZoom,
      'layout': {
        'text-field': ['get', 'label'],
        'text-font': PoiMapStyle.fuelFont,
        'text-size': PoiMapStyle.fuelTextSize,
        'text-anchor': 'top',
        'text-offset': [0, 0.25],
        'text-padding': 1,
      },
      'paint': {
        'text-color': PoiMapStyle.fuelTextColor(dark: dark),
        'text-halo-color': PoiMapStyle.fuelHalo(dark: dark),
        'text-halo-width': 2,
      },
    },
    {
      'id': PoiMapStyle.pinsLayerId,
      'type': 'symbol',
      'source': PoiMapStyle.source,
      'source-layer': PoiMapStyle.pointsLayer,
      'minzoom': PoiMapStyle.pointsMinZoom,
      'filter': PoiMapStyle.pinsFilter(view),
      'layout': _poiPinsLayout(view),
      'paint': {'icon-opacity': PoiMapStyle.opacity(view)},
    },
  ];

  static Map<String, Object?> _poiPinsLayout(PoiLayerView view, {bool quiet = false}) => {
    'icon-image': PoiMapStyle.iconImage(quiet: quiet),
    'icon-anchor': 'bottom',
    'icon-padding': 1,
    'symbol-sort-key': PoiMapStyle.sortKey(view),
  };

  static final Map<String, Object?> _poiDotsLayout = {
    'icon-image': PoiMapStyle.dotImage,
    'icon-size': PoiMapStyle.dotSize(1),
    'icon-padding': 2,
    'symbol-sort-key': PoiMapStyle.dotSortKey,
  };

  /// What changes on the points' layers with [view]: their filters, the
  /// keys and fading that follow the hours, and the open point.
  static Map<String, Object?> _poiUpdate(PoiLayerView view) => {
    'filters': {
      PoiMapStyle.dotsLayerId: PoiMapStyle.dotsFilter(view),
      PoiMapStyle.vendingDotsLayerId: PoiMapStyle.vendingDotsFilter(view),
      PoiMapStyle.quietLayerId: PoiMapStyle.quietFilter(view),
      PoiMapStyle.pinsLayerId: PoiMapStyle.pinsFilter(view),
    },
    'layout': {
      PoiMapStyle.quietLayerId: {'symbol-sort-key': PoiMapStyle.sortKey(view)},
      PoiMapStyle.pinsLayerId: {'symbol-sort-key': PoiMapStyle.sortKey(view)},
    },
    'paint': {
      PoiMapStyle.quietLayerId: {'icon-opacity': PoiMapStyle.opacity(view)},
      PoiMapStyle.pinsLayerId: {'icon-opacity': PoiMapStyle.opacity(view)},
    },
    'selection': PoiMapStyle.selectionCollection(view.selected),
    'data': {PoiMapStyle.fuelSource: PoiMapStyle.fuelCollection(view.fuelLabels)},
    // The page reads the points again when this key changes at the same
    // camera: a kind of vending machine chosen changes what is drawn.
    'probe': {
      'category': view.category == PoiCategory.vending
          ? view.vending?.code ?? view.category!.code
          : view.category?.code,
      'filter': PoiMapStyle.probeFilter(view),
    },
  };

  void _onEvent(List<dynamic> arguments) {
    if (arguments.isEmpty || arguments.first is! Map) return;
    final event = Map<String, Object?>.from(arguments.first as Map);
    switch (event['type']) {
      case 'ready':
        final first = !_ready;
        _ready = true;
        _sentPlaces = null;
        _sentPois = null;
        _sentTiles = _props.placeTiles;
        _sentSelected = null;
        _sentPoint = null;
        // The theme or the language changed while the page was loading.
        if (_style != null && _props.style != _style) {
          _setStyle();
        } else {
          _scheduleSync();
        }
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
        final hint = placeFromTile(
          event['properties'] as Map<Object?, Object?>?,
          event['coordinates'] as List<Object?>?,
        );
        _props.onPlaceTap(
          '${event['id']}',
          hint: hint ?? _props.places.where((p) => p.id == '${event['id']}').firstOrNull,
        );
      case 'places':
        final features = event['features'];
        final bounds = event['bounds'];
        if (features is List<Object?> && bounds is List && bounds.length == 4) {
          final b = [for (final v in bounds) (v as num).toDouble()];
          final view = GeoBounds(south: b[1], west: b[0], north: b[3], east: b[2]);
          _props.onPlacesInView?.call(placesOfFeatures(features, view), view);
        }
      case 'poi':
        final feature = PoiFeature.fromTile(
          event['properties'] as Map<Object?, Object?>?,
          event['coordinates'] as List<Object?>?,
        );
        if (feature != null) _props.onPoiTap?.call(feature);
      case 'pois':
        final features = event['features'];
        if (features is List<Object?>) _props.onPoisInView?.call(decodeProbe(features));
      case 'empty':
        if ((event['lat'], event['lon'], event['zoom'])
            case (final num lat, final num lon, final num zoom)
            when lat.abs() <= 90 && lon.isFinite) {
          // GL JS gives longitudes past 180 on the world's repeated copies.
          final wrapped = (lon + 180) % 360 - 180;
          _props.onEmptyTap?.call(LatLng(lat.toDouble(), wrapped.toDouble()), zoom.toDouble());
        }
      case 'longpress':
        _props.onLongPress(
          LatLng((event['lat']! as num).toDouble(), (event['lon']! as num).toDouble()),
        );
      case 'link':
        // A link clicked in the page (the attribution): the browser opens
        // web links; openUrl refuses any other scheme.
        if (Uri.tryParse('${event['url']}') case final url?) {
          unawaited(ref.read(externalActionsProvider).openUrl(url));
        }
    }
  }

  @override
  void didUpdateWidget(WebViewLunaMap old) {
    super.didUpdateWidget(old);
    if (_ready &&
        _style != null &&
        (_props.style != _style ||
            _props.dark != old.props.dark ||
            _props.language != old.props.language ||
            (_props.placeTiles == null) != (old.props.placeTiles == null))) {
      _setStyle();
      return;
    }
    _scheduleSync();
  }

  /// Gives the page the current style and layers. It turns the loaded
  /// style into the new one in place when it can (a theme: colours and the
  /// sprite), keeping the data; when it loads the style whole it answers
  /// with `ready` once the places are back on it.
  void _setStyle() {
    _style = _props.style;
    _sentTiles = _props.placeTiles;
    unawaited(
      _call('return window.lunaway.setStyle(style, spec);', {
        'style': _styleArgument(_props.style),
        'spec': _spec(
          dark: _props.dark,
          language: _props.language,
          pois: _props.pois,
          tiles: _props.placeTiles,
          style: _props.style,
        ),
      }),
    );
  }

  void _scheduleSync() {
    _queue = _queue.then((_) => _sync()).catchError((Object e, StackTrace st) {
      _log.warning('map update failed', e, st);
    });
  }

  Future<void> _sync() async {
    if (!_ready) return;
    final props = _props;
    if (props.placeTiles case final tiles? when tiles.filter != _sentTiles?.filter) {
      _sentTiles = tiles;
      await _call('return window.lunaway.setPlaceTiles(filter);', {
        'filter': placeTileFilter(tiles.filter),
      });
    }
    if (props.pois case final pois? when pois != _sentPois) {
      _sentPois = pois;
      await _call('return window.lunaway.setPois(update);', {'update': _poiUpdate(pois)});
    }
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
    final selected = props.selectedPlace;
    final selectedKey = selected == null
        ? null
        : (selected.id, selected.lat, selected.lon, selected.kind, selected.overnight);
    if (selectedKey != _sentSelected || props.markedPoint != _sentPoint) {
      _sentSelected = selectedKey;
      _sentPoint = props.markedPoint;
      await _call('return window.lunaway.setSelection(data);', {
        'data': pointFeatureCollection(selected, point: props.markedPoint),
      });
    }
  }

  @override
  Future<LatLng?> center() async {
    final v = await _call('return window.lunaway.viewport();');
    if (v is! Map) return null;
    final (lat, lon) = (v['lat'], v['lon']);
    if (lat is! num || lon is! num) return null;
    return LatLng(lat.toDouble(), (lon + 180) % 360 - 180);
  }

  @override
  Future<void> moveTo(LatLng center, {double? zoom}) async {
    // Wait for the frame that lays out a sheet the selection just opened.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final z = zoom ?? _zoom;
    final target = centerForPadding(center, z, _props.padding);
    await _call('return window.lunaway.moveTo(lat, lon, zoom, duration);', {
      'lat': target.lat,
      'lon': target.lon,
      'zoom': z,
      'duration': Motion.of(context, Motion.camera).inMilliseconds,
    });
  }

  @override
  Future<void> zoomBy(double delta) =>
      _call('return window.lunaway.zoomBy(delta);', {'delta': delta});

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
      final position = await GeolocatorPlatform.instance.getCurrentPosition().timeout(
        const Duration(seconds: 15),
      );
      final at = LatLng(position.latitude, position.longitude);
      await _call('return window.lunaway.showPosition(lat, lon);', {'lat': at.lat, 'lon': at.lon});
      return at;
    } on Object catch (e) {
      _log.info('no position: $e');
      return null;
    }
  }

  @override
  Future<void> showPosition(LatLng position, {double? accuracy}) async {
    await _call('return window.lunaway.showPosition(lat, lon);', {
      'lat': position.lat,
      'lon': position.lon,
    });
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _view.build(context);
}
