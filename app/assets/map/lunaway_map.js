// The desktop map (macOS, Windows): MapLibre GL JS in a web view, driven by
// the app through window.lunaway and reporting back through the web view's
// "lunaway" handler. The app sends the layer specification, the pin images
// and the data; this file only wires them into MapLibre and turns gestures
// into events. Everything ships with the app, so the map code needs no CDN.
(function () {
  'use strict';

  var map = null;
  var spec = null;
  var images = {};
  var pixelRatio = 1;
  var reducedMotion = false;
  var data = {};
  var longPressTimer = null;
  var suppressClick = false;
  var popFrame = null;

  function send(event) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('lunaway', event);
    }
  }

  // A link in the page (the basemap attribution) never loads in the web
  // view, which holds the app's bridge: the app opens it in the browser.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    e.preventDefault();
    send({ type: 'link', url: a.href });
  }, true);

  function emptyCollection() {
    return { type: 'FeatureCollection', features: [] };
  }

  function loadImage(id, base64) {
    return new Promise(function (resolve) {
      var img = new Image();
      img.onload = function () {
        if (!map.hasImage(id)) map.addImage(id, img, { pixelRatio: pixelRatio });
        resolve();
      };
      img.onerror = function () { resolve(); };
      img.src = 'data:image/png;base64,' + base64;
    });
  }

  // Sources, layers and images are lost on every style change: this puts
  // them back, with the last data the app sent.
  function installLayers() {
    var ids = Object.keys(images);
    return Promise.all(ids.map(function (id) { return loadImage(id, images[id]); })).then(function () {
      spec.sources.forEach(function (source) {
        if (map.getSource(source.id)) return;
        var options = Object.assign({ type: 'geojson', data: data[source.id] || emptyCollection() }, source.options);
        map.addSource(source.id, options);
      });
      spec.layers.forEach(function (layer) {
        if (!map.getLayer(layer.id)) map.addLayer(layer);
      });
    });
  }

  function viewport() {
    var b = map.getBounds();
    var c = map.getCenter();
    return {
      type: 'idle',
      south: b.getSouth(), west: b.getWest(), north: b.getNorth(), east: b.getEast(),
      lat: c.lat, lon: c.lng, zoom: map.getZoom()
    };
  }

  // The same rule as mapTapFor in lib/features/map/domain/map_geojson.dart:
  // a cluster zooms in, a place opens, the long-press marker does nothing.
  function onClick(e) {
    if (suppressClick) { suppressClick = false; return; }
    var slop = 14;
    var box = [[e.point.x - slop, e.point.y - slop], [e.point.x + slop, e.point.y + slop]];
    var layers = spec.tappable.filter(function (id) { return map.getLayer(id); });
    var features = map.queryRenderedFeatures(box, { layers: layers });
    if (features.length === 0) { send({ type: 'empty' }); return; }
    // A mark that does nothing (a route's start, a warning) can lie over a
    // place: the first feature that acts wins.
    var f = features.find(function (x) {
      var q = x.properties || {};
      return q.point_count !== undefined || (q.kind === 'place' && q.id !== undefined);
    });
    if (!f) return;
    var p = f.properties || {};
    if (p.point_count !== undefined) {
      map.getSource(spec.clusterSource).getClusterExpansionZoom(p.cluster_id).then(function (zoom) {
        map.easeTo({ center: f.geometry.coordinates, zoom: zoom + 0.3, duration: reducedMotion ? 0 : 600 });
      });
    } else if (p.kind === 'place' && p.id !== undefined) {
      send({ type: 'place', id: p.id });
    }
  }

  // A held press (or a right click) gives the coordinates of the point, as a
  // long press does on a phone.
  function startLongPress(e) {
    clearTimeout(longPressTimer);
    var at = e.lngLat;
    longPressTimer = setTimeout(function () {
      suppressClick = true;
      send({ type: 'longpress', lat: at.lat, lon: at.lng });
    }, 650);
  }

  function cancelLongPress() { clearTimeout(longPressTimer); }

  // The selected pin grows into place with a spring's give.
  function popSelection() {
    if (reducedMotion || !map.getLayer(spec.selectionLayer)) return;
    var steps = [0.55, 0.8, 1.02, 1.08, 1.03, 1.0];
    var i = 0;
    cancelAnimationFrame(popFrame);
    function step() {
      if (!map.getLayer(spec.selectionLayer)) return;
      map.setLayoutProperty(spec.selectionLayer, 'icon-size', steps[i]);
      i += 1;
      if (i < steps.length) popFrame = requestAnimationFrame(function () { setTimeout(step, 20); });
    }
    step();
  }

  var position = null;

  window.lunaway = {
    init: function (options) {
      spec = options.spec;
      images = options.images;
      pixelRatio = options.pixelRatio || 1;
      reducedMotion = !!options.reducedMotion;
      map = new maplibregl.Map({
        container: 'map',
        style: options.style,
        center: [options.lon, options.lat],
        zoom: options.zoom,
        attributionControl: false,
        dragRotate: false,
        pitchWithRotate: false,
        touchPitch: false
      });
      // Bottom left, clear of the app's own buttons at the bottom right.
      map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-left');
      map.on('style.load', function () {
        installLayers().then(function () {
          send({ type: 'ready' });
          // The first camera rests without a move: report it, so the list
          // beside the map follows from the start.
          send(viewport());
        });
      });
      map.on('moveend', function () { send(viewport()); });
      map.on('click', onClick);
      map.on('contextmenu', function (e) { send({ type: 'longpress', lat: e.lngLat.lat, lon: e.lngLat.lng }); });
      map.on('mousedown', startLongPress);
      map.on('touchstart', startLongPress);
      ['mouseup', 'mousemove', 'dragstart', 'touchend', 'touchmove', 'zoomstart'].forEach(function (name) {
        map.on(name, cancelLongPress);
      });
      return true;
    },
    setStyle: function (style, newSpec) {
      spec = newSpec;
      map.setStyle(style);
      return true;
    },
    setData: function (sourceId, collection) {
      data[sourceId] = collection;
      var source = map && map.getSource(sourceId);
      if (source) source.setData(collection);
      return true;
    },
    setSelection: function (collection) {
      window.lunaway.setData(spec.sources[1].id, collection);
      if (collection.features.length > 0) popSelection();
      return true;
    },
    moveTo: function (lat, lon, zoom, duration) {
      map.easeTo({ center: [lon, lat], zoom: zoom, duration: duration });
      return true;
    },
    zoomBy: function (delta) {
      map.easeTo({ zoom: map.getZoom() + delta, duration: reducedMotion ? 0 : 260 });
      return true;
    },
    fitBounds: function (south, west, north, east, padding) {
      map.fitBounds([[west, south], [east, north]], { padding: padding, duration: reducedMotion ? 0 : 700 });
      return true;
    },
    showPosition: function (lat, lon) {
      if (!position) {
        var dot = document.createElement('div');
        dot.className = 'lunaway-position';
        position = new maplibregl.Marker({ element: dot }).setLngLat([lon, lat]).addTo(map);
      } else {
        position.setLngLat([lon, lat]);
      }
      return true;
    },
    viewport: function () { return viewport(); }
  };
})();
