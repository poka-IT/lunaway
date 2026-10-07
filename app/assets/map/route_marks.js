// The marks of the route map on the desktop (macOS, Windows): what the
// pointer is over, told to the app for its tooltip, the hand over a mark,
// and the lit ring of the marks a row of the list stands for. The same
// rules as GlRouteMap in lib/features/navigation/presentation/
// gl_route_map.dart, here because the pointer moves too often for a call
// through the web view at each move.
(function () {
  'use strict';

  var hits = [];
  var hovered = null;
  var listening = false;

  function map() { return window.lunaway.map(); }

  function send(event) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('lunaway', event);
    }
  }

  // The topmost mark or group under the point. The hit layers are wider
  // than the badges: the box only covers the point itself.
  function topAt(point) {
    var m = map();
    var layers = hits.filter(function (id) { return m.getLayer(id); });
    if (layers.length === 0) return null;
    var box = [[point.x - 2, point.y - 2], [point.x + 2, point.y + 2]];
    var found = m.queryRenderedFeatures(box, { layers: layers });
    return found.length > 0 ? found[0] : null;
  }

  function keyOf(f) {
    if (!f) return null;
    var p = f.properties || {};
    if (p.mark !== undefined) return p.mark;
    if (p.cluster_id !== undefined) return 'group:' + f.source + ':' + p.cluster_id;
    return null;
  }

  function leave() {
    if (hovered === null) return;
    hovered = null;
    map().getCanvas().style.cursor = '';
    send({ type: 'hover' });
  }

  function onMove(e) {
    var f = topAt(e.point);
    var key = keyOf(f);
    if (key === null) { leave(); return; }
    map().getCanvas().style.cursor = 'pointer';
    if (key === hovered) return;
    hovered = key;
    var p = f.properties || {};
    var event = { type: 'hover', x: e.point.x, y: e.point.y };
    if (p.mark !== undefined) event.mark = p.mark; else event.group = p;
    send(event);
  }

  window.lunawayMarks = {
    // Watches the pointer over the hit layers, the topmost first.
    listen: function (hitLayers) {
      hits = hitLayers;
      if (listening) return;
      listening = true;
      var m = map();
      m.on('mousemove', onMove);
      m.on('mouseout', leave);
      // A callout pinned to a mark is out of place once the map moves.
      m.on('movestart', function () { send({ type: 'movestart' }); });
    },
    // Each state: { source, id, lit }.
    light: function (states) {
      var m = map();
      if (!m) return;
      states.forEach(function (s) {
        if (m.getSource(s.source)) m.setFeatureState({ source: s.source, id: s.id }, { lit: s.lit });
      });
    },
    // New marks: the old states named other features.
    clear: function (sources) {
      var m = map();
      if (!m) return;
      sources.forEach(function (s) { if (m.getSource(s)) m.removeFeatureState({ source: s }); });
    },
    // Close enough that no mark stays in a group, never further out.
    fly: function (lat, lon, zoom, duration) {
      var m = map();
      if (!m) return;
      m.easeTo({ center: [lon, lat], zoom: Math.max(m.getZoom(), zoom), duration: duration });
    }
  };
})();
