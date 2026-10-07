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
  // The last state of the points of interest the app sent (filters, fading,
  // the open point), put back after each style change.
  var poiUpdate = null;
  var poiProbed = null;

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
        // The points of interest are vector tiles named by a TileJSON; the
        // rest is GeoJSON the app sends.
        var options = source.vector
          ? { type: 'vector', url: source.url }
          : Object.assign({ type: 'geojson', data: data[source.id] || emptyCollection() }, source.options);
        map.addSource(source.id, options);
      });
      spec.layers.forEach(function (layer) {
        if (map.getLayer(layer.id)) return;
        var copy = Object.assign({}, layer);
        var before = copy.before;
        delete copy.before;
        map.addLayer(copy, before && map.getLayer(before) ? before : undefined);
      });
      poiProbed = null;
      applyPois();
    });
  }

  function applyPois() {
    if (!poiUpdate || !map) return;
    Object.keys(poiUpdate.filters || {}).forEach(function (id) {
      if (map.getLayer(id)) map.setFilter(id, poiUpdate.filters[id]);
    });
    Object.keys(poiUpdate.layout || {}).forEach(function (id) {
      if (!map.getLayer(id)) return;
      Object.keys(poiUpdate.layout[id]).forEach(function (key) {
        map.setLayoutProperty(id, key, poiUpdate.layout[id][key]);
      });
    });
    Object.keys(poiUpdate.paint || {}).forEach(function (id) {
      if (!map.getLayer(id)) return;
      Object.keys(poiUpdate.paint[id]).forEach(function (key) {
        map.setPaintProperty(id, key, poiUpdate.paint[id][key]);
      });
    });
    if (spec.pois) {
      var selection = map.getSource(spec.pois.selectionSource);
      if (selection) selection.setData(poiUpdate.selection || emptyCollection());
    }
    // The prices of the fuel stations, kept for the next style change too.
    Object.keys(poiUpdate.data || {}).forEach(function (id) {
      data[id] = poiUpdate.data[id];
      var source = map.getSource(id);
      if (source) source.setData(poiUpdate.data[id]);
    });
  }

  // Once the map rests: the points under the view whose hours or
  // neighbours decide how they are drawn, the same reading as
  // GlPoiLayers.probe in the app.
  function probePois() {
    if (!spec || !spec.pois || !poiUpdate || !map.getSource(spec.pois.source)) return;
    var c = map.getCenter();
    var zoom = map.getZoom();
    var category = poiUpdate.probe.category;
    var key = [c.lat, c.lng, zoom, category].join(',');
    if (key === poiProbed) return;
    poiProbed = key;
    var drawn = category ? zoom >= spec.pois.pointsMinZoom : zoom >= spec.pois.quietMinZoom;
    var found = drawn
      ? map.querySourceFeatures(spec.pois.source, {
          sourceLayer: spec.pois.sourceLayer,
          filter: poiUpdate.probe.filter
        })
      : [];
    send({
      type: 'pois',
      features: found.map(function (f) {
        return { geometry: { coordinates: f.geometry.coordinates }, properties: f.properties };
      })
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
    // Topmost first: the first feature that means something decides.
    for (var i = 0; i < features.length; i++) {
      var f = features[i];
      var p = f.properties || {};
      if (p.point_count !== undefined) {
        map.getSource(spec.clusterSource).getClusterExpansionZoom(p.cluster_id).then(function (zoom) {
          map.easeTo({ center: f.geometry.coordinates, zoom: zoom + 0.3, duration: reducedMotion ? 0 : 600 });
        });
        return;
      }
      if (p.kind === 'place' && p.id !== undefined) {
        send({ type: 'place', id: p.id });
        return;
      }
      if (p.kind === 'point') return;
      // A point of interest, or where a category's points gather (the
      // same rule as poiTapFor in lib/features/poi/presentation).
      if (p.count !== undefined && p.id === undefined && spec.pois) {
        var next = Math.min(map.getZoom() + 2, spec.pois.pointsMinZoom + 0.5);
        map.easeTo({ center: f.geometry.coordinates, zoom: next, duration: reducedMotion ? 0 : 600 });
        return;
      }
      if (p.id !== undefined && p.kind !== undefined) {
        send({ type: 'poi', properties: p, coordinates: f.geometry.coordinates });
        return;
      }
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
      map.on('idle', probePois);
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
    setPois: function (update) {
      poiUpdate = update;
      poiProbed = null;
      applyPois();
      if (map && map.loaded()) probePois();
      return true;
    },
    setSelection: function (collection) {
      window.lunaway.setData(spec.placeSelectionSource, collection);
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
    viewport: function () { return viewport(); },
    // The map itself, for the guidance's motion (route_motion.js).
    map: function () { return map; }
  };
})();
