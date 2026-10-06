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
  var data = {};
  var longPressTimer = null;
  var suppressClick = false;

  function send(event) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('lunaway', event);
    }
  }

  function emptyCollection() {
    return { type: 'FeatureCollection', features: [] };
  }

  function loadImage(id, base64) {
    return new Promise(function (resolve) {
      var img = new Image();
      img.onload = function () {
        if (!map.hasImage(id)) map.addImage(id, img);
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

  function onClick(e) {
    if (suppressClick) { suppressClick = false; return; }
    var slop = 14;
    var box = [[e.point.x - slop, e.point.y - slop], [e.point.x + slop, e.point.y + slop]];
    var layers = spec.tappable.filter(function (id) { return map.getLayer(id); });
    var features = map.queryRenderedFeatures(box, { layers: layers });
    if (features.length === 0) return;
    var f = features[0];
    var p = f.properties || {};
    if (p.point_count !== undefined) {
      map.getSource(spec.clusterSource).getClusterExpansionZoom(p.cluster_id).then(function (zoom) {
        map.easeTo({ center: f.geometry.coordinates, zoom: zoom + 0.3, duration: 600 });
      });
    } else if (p.id !== undefined) {
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

  window.lunaway = {
    init: function (options) {
      spec = options.spec;
      images = options.images;
      map = new maplibregl.Map({
        container: 'map',
        style: options.style,
        center: [options.lon, options.lat],
        zoom: options.zoom,
        attributionControl: false,
        dragRotate: false,
        pitchWithRotate: false
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
      // Bottom left, clear of the position button at the bottom right.
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
    setStyle: function (url) {
      map.setStyle(url);
      return true;
    },
    setData: function (sourceId, collection) {
      data[sourceId] = collection;
      var source = map && map.getSource(sourceId);
      if (source) source.setData(collection);
      return true;
    },
    moveTo: function (lat, lon, zoom) {
      map.easeTo({ center: [lon, lat], zoom: zoom, duration: 700 });
      return true;
    },
    fitBounds: function (south, west, north, east, padding) {
      map.fitBounds([[west, south], [east, north]], { padding: padding, duration: 700 });
      return true;
    },
    viewport: function () { return viewport(); }
  };
})();
