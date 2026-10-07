// The marks of the route map on the desktop (macOS, Windows): what the
// mouse is over, told to the app for its tooltip, and the lit ring of the
// marks a row of the list stands for. The page's hover (lunawayHits.hover
// in lunaway_map.js) picks the target and draws the pointing hand; this
// file only passes its pick on, as GlRouteMap does in the browser
// (lib/features/navigation/presentation/gl_route_map.dart).
(function () {
  'use strict';

  var layers = [];
  var shown = null;
  var listening = false;

  function map() { return window.lunaway.map(); }

  function send(event) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('lunaway', event);
    }
  }

  function onHover(e) {
    var hit = e.detail;
    var p = hit && layers.indexOf(hit.layer) >= 0 ? (hit.properties || {}) : null;
    var key = !p ? null : p.mark !== undefined ? p.mark :
      p.cluster_id !== undefined ? 'group:' + hit.layer + ':' + p.cluster_id : null;
    if (key === shown) return;
    shown = key;
    if (key === null) { send({ type: 'hover' }); return; }
    var event = { type: 'hover', x: hit.x, y: hit.y };
    if (p.mark !== undefined) event.mark = p.mark; else event.group = p;
    send(event);
  }

  window.lunawayMarks = {
    // Passes on what the hover picks among the badge layers.
    listen: function (badgeLayers) {
      layers = badgeLayers;
      if (listening) return;
      listening = true;
      document.addEventListener('lunawayhover', onHover);
      // A callout pinned to a mark is out of place once the map moves.
      map().on('movestart', function () { send({ type: 'movestart' }); });
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
