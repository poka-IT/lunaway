import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// MapLibre GL JS on the web ignores the plugin's control margins, so its
/// top right controls (compass, attribution) would sit under the floating
/// search bar. A style rule moves that corner below the overlays instead; it
/// is rewritten when the overlays change height.
void placeWebMapControls({required double top}) {
  // Scoped under the map class to outrank maplibre-gl.css, which the plugin
  // links after this rule is added.
  final css = '.maplibregl-map .maplibregl-ctrl-top-right{top:${top.round()}px}';
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
