// The rich marks of the route map on the desktop (macOS, Windows): what the
// app's driver asks of the page (rich_marks.dart), as maplibre_gl answers
// it on the other platforms (gl_route_map.dart): the places drawn in view,
// points placed on the screen, the marks' images in their slots.
(function () {
  'use strict';

  function map() { return window.lunaway.map(); }

  window.lunawayRich = {
    // Every place the invisible probe layer draws in view: its properties
    // and its point.
    places: function (layer) {
      var m = map();
      if (!m || !m.getLayer(layer)) return [];
      return m.queryRenderedFeatures({ layers: [layer] }).map(function (f) {
        return { p: f.properties, c: f.geometry.coordinates };
      });
    },
    // Where each [lon, lat] is drawn, in CSS pixels (the app's logical
    // ones), and how the camera looks: its zoom, its tilt and where the
    // point it looks at is drawn.
    view: function (points) {
      var m = map();
      if (!m) return null;
      var at = function (p) { var s = m.project(p); return [s.x, s.y]; };
      var centre = m.getCenter();
      return {
        points: points.map(at),
        zoom: m.getZoom(),
        pitch: m.getPitch(),
        centre: at([centre.lng, centre.lat])
      };
    },
    // Puts a mark's image in its slot, replacing what the slot held: GL JS
    // keeps the first image added under an id. Resolves once added.
    image: function (id, base64, pixelRatio) {
      return new Promise(function (resolve) {
        var img = new Image();
        img.onload = function () {
          var m = map();
          if (m) {
            if (m.hasImage(id)) m.removeImage(id);
            m.addImage(id, img, { pixelRatio: pixelRatio });
          }
          resolve(true);
        };
        img.onerror = function () { resolve(false); };
        img.src = 'data:image/png;base64,' + base64;
      });
    }
  };
})();
