// The guidance on the desktop map (macOS, Windows): the vehicle glides from
// fix to fix and, while following, the camera rides with it, tilted and
// turned to the course. The same rule as VehicleMotion and followZoom in
// lib/features/navigation/presentation/vehicle_motion.dart, here because a
// frame by frame call from the app through the web view would lag.
(function () {
  'use strict';

  var MAX_GLIDE = 1500;
  // A fix this far from the drawn vehicle is a jump (a new route from
  // elsewhere), not a move to glide through, metres.
  var JUMP_M = 500;
  var TILT = 55;
  var source = null;
  var from = null;
  var to = null;
  var start = 0;
  var length = 0;
  var lastTarget = null;
  var follow = null;
  var zoom = null;
  var bearing = 0;
  var lastFrame = 0;
  var frame = null;

  function map() { return window.lunaway.map(); }

  function delta(a, b) {
    var d = (((b - a) % 360) + 360) % 360;
    return d > 180 ? d - 360 : d;
  }

  function at(now) {
    if (!from || !to) return null;
    var t = length <= 0 ? 1 : Math.min(1, Math.max(0, (now - start) / length));
    var course = from.course === null || to.course === null
      ? (to.course !== null ? to.course : from.course)
      : (((from.course + delta(from.course, to.course) * t) % 360) + 360) % 360;
    return {
      lat: from.lat + (to.lat - from.lat) * t,
      lon: from.lon + (to.lon - from.lon) * t,
      course: course,
      moving: t < 1
    };
  }

  function step(now) {
    frame = null;
    var m = map();
    var shown = at(now);
    if (!m || !shown) return;
    var dt = lastFrame ? now - lastFrame : 0;
    lastFrame = now;
    var src = m.getSource(source);
    if (src) {
      src.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          properties: { course: shown.course === null ? 0 : shown.course },
          geometry: { type: 'Point', coordinates: [shown.lon, shown.lat] }
        }]
      });
    }
    var settled = !shown.moving;
    if (follow) {
      zoom = zoom === null ? follow.zoom : zoom + (follow.zoom - zoom) * Math.min(1, dt / 2000);
      if (Math.abs(follow.zoom - zoom) > 0.01) settled = false;
      if (shown.course !== null) bearing = shown.course;
      m.jumpTo({ center: [shown.lon, shown.lat], zoom: zoom, bearing: bearing, pitch: TILT });
    }
    if (!settled) frame = requestAnimationFrame(step);
  }

  function metres(a, b) {
    var r = Math.PI / 180;
    var x = (b.lon - a.lon) * r * Math.cos(((a.lat + b.lat) / 2) * r);
    var y = (b.lat - a.lat) * r;
    return Math.sqrt(x * x + y * y) * 6371008.8;
  }

  function kick() {
    if (frame === null) frame = requestAnimationFrame(step);
  }

  window.lunawayRoute = {
    // A new fix; jump: drawn there at once (the first fix, a new route from
    // elsewhere, reduced motion).
    vehicle: function (sourceId, lat, lon, course, jump) {
      source = sourceId;
      var now = performance.now();
      var shown = at(now);
      var target = { lat: lat, lon: lon, course: course === undefined ? null : course };
      // The same fix again changes nothing: restarting would cut the glide.
      if (!jump && to && to.lat === lat && to.lon === lon &&
          (target.course === null || target.course === to.course)) {
        return true;
      }
      var gap = lastTarget === null ? 1000 : now - lastTarget;
      lastTarget = now;
      if (!shown || jump || metres(shown, target) > JUMP_M) {
        from = target;
        to = target;
        length = 0;
      } else {
        from = { lat: shown.lat, lon: shown.lon, course: shown.course };
        if (target.course === null) target.course = shown.course;
        to = target;
        length = Math.min(gap, MAX_GLIDE);
      }
      start = now;
      kick();
      return true;
    },
    // Following ({zoom, padding}) or not (null): the overview, the preview.
    follow: function (options) {
      var m = map();
      if (!m) return false;
      if (!options) {
        if (follow) m.jumpTo({ padding: { top: 0, bottom: 0, left: 0, right: 0 }, pitch: 0, bearing: 0 });
        follow = null;
        zoom = null;
        return true;
      }
      if (!follow || JSON.stringify(follow.padding) !== JSON.stringify(options.padding)) {
        m.setPadding(options.padding);
      }
      follow = options;
      kick();
      return true;
    }
  };
})();
