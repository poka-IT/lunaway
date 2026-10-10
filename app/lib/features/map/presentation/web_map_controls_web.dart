import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show Offset;

import 'package:lunaway/features/map/domain/map_hits.dart';
import 'package:web/web.dart' as web;

/// MapLibre GL JS on the web ignores the plugin's control margins, so its
/// controls would sit under the floating search bar, the sheet or the dock.
/// A style rule moves the top corner below the overlays; it is rewritten
/// when the overlays change. The engine's attribution control is hidden:
/// the app draws the basemap credit itself, visible on every engine.
void placeWebMapControls({required double top}) {
  // Scoped under the map class to outrank maplibre-gl.css, which the plugin
  // links after this rule is added.
  final css = [
    '.maplibregl-map .maplibregl-ctrl-top-right{top:${top.round()}px}',
    '.maplibregl-map .maplibregl-ctrl-attrib{display:none}',
  ].join();
  final existing = web.document.getElementById(_styleId);
  if (existing != null) {
    if (existing.textContent != css) existing.textContent = css;
    return;
  }
  final style = web.document.createElement('style')
    ..id = _styleId
    ..textContent = css;
  web.document.head?.appendChild(style);
}

const _styleId = 'lunaway-map-controls';

/// A long press on the web map, at a point in map pixels: a right click with
/// a mouse, a finger held still on a touch screen. MapLibre GL JS has no
/// long press, and the plugin reports a double click as one, which also
/// zooms; the map ignores that report on the web and listens here instead.
/// Returns the function that stops listening, or null before the map exists.
void Function()? listenWebMapLongPress(void Function(double x, double y) onPress) {
  final target = web.document.querySelector('.maplibregl-canvas-container');
  if (target == null) return null;
  Timer? hold;
  var startX = 0.0;
  var startY = 0.0;

  void at(double clientX, double clientY) {
    final box = target.getBoundingClientRect();
    onPress(clientX - box.left, clientY - box.top);
  }

  final contextMenu = ((web.MouseEvent e) {
    e.preventDefault();
    at(e.clientX.toDouble(), e.clientY.toDouble());
  }).toJS;
  final touchStart = ((web.TouchEvent e) {
    hold?.cancel();
    if (e.touches.length != 1) return;
    final touch = e.touches.item(0)!;
    startX = touch.clientX;
    startY = touch.clientY;
    hold = Timer(const Duration(milliseconds: 600), () => at(startX, startY));
  }).toJS;
  final touchMove = ((web.TouchEvent e) {
    final touch = e.touches.item(0);
    // A finger that slides is panning the map, not holding a point.
    if (touch == null ||
        (touch.clientX - startX).abs() > 10 ||
        (touch.clientY - startY).abs() > 10) {
      hold?.cancel();
    }
  }).toJS;
  final touchEnd = ((web.TouchEvent _) => hold?.cancel()).toJS;

  target
    ..addEventListener('contextmenu', contextMenu)
    ..addEventListener('touchstart', touchStart)
    ..addEventListener('touchmove', touchMove)
    ..addEventListener('touchend', touchEnd)
    ..addEventListener('touchcancel', touchEnd);
  return () {
    hold?.cancel();
    target
      ..removeEventListener('contextmenu', contextMenu)
      ..removeEventListener('touchstart', touchStart)
      ..removeEventListener('touchmove', touchMove)
      ..removeEventListener('touchend', touchEnd)
      ..removeEventListener('touchcancel', touchEnd);
  };
}

/// What last pressed on a map of the page, as the page's map code records
/// it (`lunawayHits.pointerType` in web/lunaway_maplibre.js): a tap with a
/// finger asks for a wider target than a click.
PointerKind webMapPointerKind() =>
    _hits?.pointerType() == 'touch' ? PointerKind.touch : PointerKind.mouse;

@JS('lunawayHits')
external _Hits? get _hits;

extension type _Hits._(JSObject _) implements JSObject {
  external String? pointerType();
}

/// Tells the page that the gesture starting now is a map's: the app's hit
/// test gave its first press to a map (`lunawayGestures` in
/// web/lunaway_maplibre.js). Called while the app handles that press,
/// before the browser hands the map the gesture's touch and mouse events;
/// those of a gesture no map claimed never reach one.
void claimWebMapGesture() => _gestures?.claim();

@JS('lunawayGestures')
external _Gestures? get _gestures;

extension type _Gestures._(JSObject _) implements JSObject {
  external void claim();
}

/// How many of the app's maps the mouse is over, in the app's own hit test.
var _mapsUnderPointer = 0;

/// The mouse entered ([on]) or left one of the app's maps as the app sees
/// it. Over a map, the map draws its own cursor (the grab hand, the
/// pointing finger over a target); anywhere else, a dialog, a sheet or a
/// button over the map included, the cursor the app sets on the page wins.
/// The browser would otherwise show the map's cursor wherever the map's
/// element lies under the app's canvas (the rules in web/index.html).
void markPointerOnWebMap({required bool on}) {
  _mapsUnderPointer = (_mapsUnderPointer + (on ? 1 : -1)).clamp(0, 1 << 10);
  final body = web.document.body;
  if (body == null) return;
  if (_mapsUnderPointer > 0) {
    body.classList.add(_onMapClass);
  } else {
    body.classList.remove(_onMapClass);
  }
}

const _onMapClass = 'lw-on-map';

/// Listens to what the mouse is over on the page's maps, as their hover
/// picks it (`lunawayhover`, fired by lunawayHits.hover in
/// web/lunaway_maplibre.js when the target under the mouse changes): null
/// when it leaves every target. Returns the function that stops listening.
void Function()? listenWebMapHover(void Function(WebMapHover? hover) onHover) {
  final listener = ((web.CustomEvent e) {
    final detail = e.detail.dartify();
    if (detail is! Map) {
      onHover(null);
      return;
    }
    final (layer, properties, x, y) = (
      detail['layer'],
      detail['properties'],
      detail['x'],
      detail['y'],
    );
    if (layer is! String || properties is! Map || x is! num || y is! num) {
      onHover(null);
      return;
    }
    onHover(
      WebMapHover(
        layer: layer,
        properties: Map<Object?, Object?>.from(properties),
        at: Offset(x.toDouble(), y.toDouble()),
      ),
    );
  }).toJS;
  web.document.addEventListener(_hoverEvent, listener);
  return () => web.document.removeEventListener(_hoverEvent, listener);
}

const _hoverEvent = 'lunawayhover';
