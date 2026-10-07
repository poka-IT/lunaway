// The desktop map (macOS, Windows): MapLibre GL JS in a web view, driven by
// the app through window.lunaway and reporting back through the web view's
// "lunaway" handler. The app sends the layer specification, the pin images
// and the data; this file only wires them into MapLibre and turns gestures
// into events. Everything ships with the app, so the map code needs no CDN.
(function () {
  'use strict';

  // BEGIN MAP HITS
  // How a pointer picks a feature of a map, the rule of nearestHit in
  // lib/features/map/domain/map_hits.dart: the feature whose drawn shape
  // lies nearest the pointer, within a tolerance that does not depend on
  // how small it is drawn. The shapes come from hitShapesJson in
  // lib/features/map/presentation/map_hit_shapes.dart. This block is the
  // same in web/lunaway_maplibre.js and assets/map/lunaway_map.js, and its
  // shapes the app's (test/unit/map_hits_test.dart, UPDATE_MAP_HITS=1
  // rewrites them).
  var lunawayHits = (function () {
    var HITS = /* BEGIN HIT SHAPES */ {"tolerance":{"touch":22.0,"mouse":14.0},"ring":{"color":"#f2a541","width":2.5,"gap":2.5},"shapes":{"lw-selection-pin":{"r":18.85,"y":26.9555,"p":0},"lw-selection-pin/point":{"r":14.0,"y":27.0,"p":0,"inert":true},"lw-poi-selection":{"r":15.4,"y":27.9,"p":0},"lw-places":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":1},"lw-place-pins":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":1},"lw-clusters":{"r":{"by":"point_count","stops":[[2.0,14.5],[10.0,16.5],[50.0,18.5],[200.0,21.5],[1000.0,24.5]]},"y":0.0,"p":2},"lw-place-pin-dots":{"r":{"by":"zoom","stops":[[3.0,1.9000000000000001],[6.0,3.2600000000000002],[8.0,4.3],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":3},"lw-place-dots":{"r":{"by":"zoom","stops":[[3.0,1.9000000000000001],[6.0,3.2600000000000002],[8.0,4.3],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":3},"lw-poi-pins":{"r":11.3,"y":17.8,"p":4},"lw-poi-quiet":{"r":8.9,"y":13.9,"p":5},"lw-poi-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":6},"lw-poi-vending-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":6},"lw-route-anchors-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":1},"lw-route-marks-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":2},"lw-route-minor-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":3},"lw-route-alternatives-line":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-alternatives-casing":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-place-pins":{"r":{"by":"zoom","stops":[[6.0,7.5168],[12.0,10.44]]},"y":{"by":"zoom","stops":[[6.0,10.749023999999999],[12.0,14.9292]]},"p":4},"lw-route-poi-pins":{"r":8.814,"y":13.884,"p":5}}} /* END HIT SHAPES */;
    var EPSILON = 1e-6;

    // What last pressed on the page: a finger asks for a wider target.
    var lastPointer = 'mouse';
    if (typeof document !== 'undefined') {
      document.addEventListener('pointerdown', function (e) {
        lastPointer = e.pointerType === 'touch' ? 'touch' : 'mouse';
      }, true);
    }

    function value(v, zoom, props) {
      if (typeof v === 'number') return v;
      if (v.prop !== undefined) {
        var p = props[v.prop];
        return (typeof p === 'number' ? p : v.fallback) + v.plus;
      }
      var s = v.stops;
      var x = v.by === 'zoom' ? zoom : props[v.by];
      if (typeof x !== 'number') x = s[0][0];
      if (x <= s[0][0]) return s[0][1];
      for (var i = 1; i < s.length; i++) {
        if (x <= s[i][0]) return s[i - 1][1] + (s[i][1] - s[i - 1][1]) * (x - s[i - 1][0]) / (s[i][0] - s[i - 1][0]);
      }
      return s[s.length - 1][1];
    }

    // A layer may draw two kinds of features, told apart by their kind.
    function shapeOf(layer, props) {
      var kind = props.kind;
      if (typeof kind === 'string' && HITS.shapes[layer + '/' + kind]) return HITS.shapes[layer + '/' + kind];
      return HITS.shapes[layer];
    }

    // Candidates topmost first: {layer, properties, points: [[x, y], ...]}.
    // A tie goes to the lower priority, then to the one drawn on top.
    // `signs`: a shape that needs a property (a route mark's id) is picked
    // without it too, to tell a tap on a sign of the route from bare map.
    function nearest(at, candidates, zoom, tolerance, signs) {
      var best = null;
      var bestPriority = 0;
      for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        var props = c.properties || {};
        var shape = shapeOf(c.layer, props);
        if (!shape) continue;
        if (!signs && shape.needs && (props[shape.needs] === undefined || props[shape.needs] === null)) continue;
        var distance = tolerance;
        var point = 0;
        if (!shape.line) {
          if (!c.points.length) continue;
          var r = value(shape.r, zoom, props);
          var lift = value(shape.y, zoom, props);
          distance = Infinity;
          for (var j = 0; j < c.points.length; j++) {
            var dx = at[0] - c.points[j][0];
            var dy = at[1] - (c.points[j][1] - lift);
            var d = Math.max(0, Math.sqrt(dx * dx + dy * dy) - r);
            if (d < distance) {
              distance = d;
              point = j;
            }
          }
        }
        if (distance > tolerance) continue;
        if (!best || distance < best.distance - EPSILON ||
            (distance <= best.distance + EPSILON && shape.p < bestPriority)) {
          best = { index: i, pointIndex: point, distance: distance, inert: !!shape.inert };
          bestPriority = shape.p;
        }
      }
      return best;
    }

    // The layers of `map` a pointer picks from: `only`, or every layer
    // with a shape, those the style holds (GL JS answers nothing at all
    // to a query that names a missing layer).
    function layersOf(map, only) {
      var ids = only || Object.keys(HITS.shapes).map(function (k) { return k.split('/')[0]; });
      var seen = {};
      return ids.filter(function (id) {
        if (seen[id] || !HITS.shapes[id] || !map.getLayer(id)) return false;
        seen[id] = true;
        return true;
      });
    }

    // What a click at `point` (screen pixels) on `map` picks: the feature,
    // its layer, the point of it picked (one of a MultiPoint) in degrees
    // and on screen, and its shape; null for none. `options.wider`: the
    // tolerance times this (the reach before a tap counts as bare map,
    // FreeTap in lib/features/map/domain/map_taps.dart); `options.signs`:
    // see nearest.
    function pick(map, point, options) {
      options = options || {};
      var tolerance = (HITS.tolerance[options.pointer || lastPointer] || HITS.tolerance.mouse) *
        (options.wider || 1);
      var layers = layersOf(map, options.layers);
      if (!layers.length) return null;
      var box = [[point.x - tolerance, point.y - tolerance], [point.x + tolerance, point.y + tolerance]];
      var features = map.queryRenderedFeatures(box, { layers: layers });
      if (!features.length) return null;
      // A dot of the low zooms is one feature of up to thousands of points:
      // only those near the box are projected (a pin's tip may stand some
      // way below its head).
      var reach = tolerance + 64;
      var sw = map.unproject([point.x - reach, point.y + reach]);
      var ne = map.unproject([point.x + reach, point.y - reach]);
      var candidates = features.map(function (f) {
        var g = f.geometry || {};
        var coords = g.type === 'Point' ? [g.coordinates] : (g.type === 'MultiPoint' ? g.coordinates : []);
        var points = [];
        var kept = [];
        for (var k = 0; k < coords.length; k++) {
          var c = coords[k];
          if (coords.length > 1 && (c[1] < sw.lat || c[1] > ne.lat || c[0] < sw.lng || c[0] > ne.lng)) continue;
          var s = map.project(c);
          points.push([s.x, s.y]);
          kept.push(c);
        }
        return { layer: f.layer.id, properties: f.properties || {}, points: points, coordinates: kept, feature: f };
      });
      var zoom = map.getZoom();
      var hit = nearest([point.x, point.y], candidates, zoom, tolerance, !!options.signs);
      if (!hit) return null;
      var chosen = candidates[hit.index];
      return {
        feature: chosen.feature,
        layer: chosen.layer,
        properties: chosen.properties,
        coordinates: chosen.coordinates[hit.pointIndex] || null,
        point: chosen.points[hit.pointIndex] || null,
        shape: shapeOf(chosen.layer, chosen.properties),
        zoom: zoom,
        inert: hit.inert
      };
    }

    var EMPTY = { type: 'FeatureCollection', features: [] };

    // The pointing finger over what a click would pick, the closed hand
    // while the map is dragged, and a ring around the shape under the
    // mouse. One query per animation frame at most, and only while the
    // mouse moves. `options.gate`: whether the map is the one under the
    // mouse (the app's maps, under the app's own surfaces); `options.layers`
    // a function giving the layers to pick from.
    function hover(map, options) {
      options = options || {};
      var container = map.getCanvasContainer();
      var last = null;
      var frame = 0;
      var moving = false;
      var shownKey = null;

      function ring(hit) {
        var source = map.getSource('lw-hover');
        if (!source) {
          if (!hit) return;
          try {
            map.addSource('lw-hover', { type: 'geojson', data: EMPTY });
            map.addLayer({
              id: 'lw-hover',
              type: 'circle',
              source: 'lw-hover',
              paint: {
                'circle-radius': ['get', 'r'],
                'circle-color': 'rgba(0,0,0,0)',
                'circle-stroke-width': HITS.ring.width,
                'circle-stroke-color': HITS.ring.color
              }
            });
          } catch (e) {
            // The style is loading: the next move draws it.
            return;
          }
          source = map.getSource('lw-hover');
        }
        if (!hit || !hit.point || hit.shape.line) {
          source.setData(EMPTY);
          return;
        }
        // Each new ring repaints the map, which then reports itself idle
        // again: the readers of an idle map skip a camera they already read.
        var props = hit.properties;
        var lift = value(hit.shape.y, hit.zoom, props);
        var centre = map.unproject([hit.point[0], hit.point[1] - lift]);
        source.setData({
          type: 'FeatureCollection',
          features: [{
            type: 'Feature',
            properties: { r: value(hit.shape.r, hit.zoom, props) + HITS.ring.gap },
            geometry: { type: 'Point', coordinates: [centre.lng, centre.lat] }
          }]
        });
      }

      function show(hit) {
        var key = hit ? hit.layer + '|' + (hit.properties.id || hit.properties.cluster_id || '') + '|' +
          (hit.coordinates ? hit.coordinates.join(',') : '') : null;
        if (key === shownKey) return;
        shownKey = key;
        container.classList.toggle('lw-hit', !!hit);
        ring(hit);
        // What the mouse is over, for whoever listens on the page (the
        // route map's tooltip: listenWebMapHover in
        // lib/features/map/presentation/web_map_controls_web.dart).
        container.dispatchEvent(new CustomEvent('lunawayhover', {
          bubbles: true,
          detail: hit && hit.point ? {
            layer: hit.layer,
            properties: hit.properties,
            x: hit.point[0],
            y: hit.point[1]
          } : null
        }));
      }

      function update() {
        frame = 0;
        if (!last || moving || lastPointer === 'touch' || (options.gate && !options.gate())) {
          show(null);
          return;
        }
        var hit = null;
        try {
          hit = pick(map, last, { pointer: 'mouse', layers: options.layers ? options.layers() : undefined });
        } catch (e) {
          hit = null;
        }
        show(hit && !hit.inert ? hit : null);
      }

      function later() {
        if (!frame) frame = requestAnimationFrame(update);
      }

      // A frame still due when the map goes would touch a removed map.
      map.on('remove', function () {
        if (frame) cancelAnimationFrame(frame);
        frame = 0;
        last = null;
      });

      map.on('mousemove', function (e) {
        last = e.point;
        later();
      });
      map.on('mouseout', function () {
        last = null;
        later();
      });
      map.on('movestart', function () {
        moving = true;
        show(null);
      });
      map.on('moveend', function () {
        moving = false;
        if (last) later();
      });
      map.on('dragstart', function () { container.classList.add('lw-dragging'); });
      map.on('dragend', function () { container.classList.remove('lw-dragging'); });
      // A new style may drop the ring's layer (loaded whole, or diffed
      // without it on the desktop page): it comes back at the next hover.
      map.on('styledata', function () {
        if (!map.getLayer('lw-hover')) shownKey = null;
      });
    }

    return {
      nearest: nearest,
      pick: pick,
      hover: hover,
      pointerType: function () { return lastPointer; }
    };
  })();
  // END MAP HITS

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
  var placesProbed = null;

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
        // The places and the points of interest are vector tiles named by a
        // TileJSON; the rest is GeoJSON the app sends.
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
      placesProbed = null;
      applyPois();
    });
  }

  // The app's own sources and layers in the GL JS form, from the current
  // spec, the GeoJSON with the last data the app sent.
  function ownSources() {
    var out = {};
    spec.sources.forEach(function (source) {
      out[source.id] = source.vector
        ? { type: 'vector', url: source.url }
        : Object.assign({ type: 'geojson', data: data[source.id] || emptyCollection() }, source.options);
    });
    return out;
  }

  // A new style given with the app's layers kept: each of them goes before
  // the basemap layer it names (`before`), the others on top in the spec's
  // order. MapLibre then turns the loaded style into it in place when only
  // paint properties and the sprite differ (a theme), keeping the tiles and
  // the images; otherwise it loads it whole and style.load sets it up.
  function withOwnLayers(previous, next) {
    var before = {};
    var top = [];
    spec.layers.forEach(function (layer) {
      var copy = Object.assign({}, layer);
      var anchor = copy.before;
      delete copy.before;
      if (anchor) {
        (before[anchor] = before[anchor] || []).push(copy);
      } else {
        top.push(copy);
      }
    });
    var layers = [];
    next.layers.forEach(function (layer) {
      (before[layer.id] || []).forEach(function (own) { layers.push(own); });
      layers.push(layer);
    });
    top.forEach(function (own) { layers.push(own); });
    return Object.assign({}, next, {
      sources: Object.assign({}, next.sources, ownSources()),
      layers: layers
    });
  }

  // Once the map rests at the zoom of the pins: the places of the tiles,
  // for the list beside the map and the points of interest that leave them
  // room (the same reading as GlPlaceTiles.probe in the app, which keeps
  // those inside the bounds sent).
  function probePlaces() {
    var tiles = spec && spec.placeTiles;
    // The guidance's map lists no places: it only opens them.
    if (!tiles || tiles.probe === false || !map.getSource(tiles.source)) return;
    var c = map.getCenter();
    var zoom = map.getZoom();
    var view = map.getBounds();
    // The view too: a resize keeps the camera and changes what is in view.
    var key = [c.lat, c.lng, zoom, view.toArray().join(','), JSON.stringify(tiles.filter)].join(',');
    if (key === placesProbed) return;
    placesProbed = key;
    var seen = {};
    var features = [];
    if (zoom >= tiles.pinZoom) {
      map.querySourceFeatures(tiles.source, { sourceLayer: tiles.sourceLayer, filter: tiles.filter })
        .forEach(function (f) {
          var id = f.properties && f.properties.id;
          if (id === undefined || seen[id]) return;
          seen[id] = true;
          features.push({ geometry: { coordinates: f.geometry.coordinates }, properties: f.properties });
        });
    }
    send({ type: 'places', features: features, bounds: [view.getWest(), view.getSouth(), view.getEast(), view.getNorth()] });
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

  // The nearest feature within reach decides (lunawayHits.pick), then the
  // same rule as mapTapFor in lib/features/map/domain/map_geojson.dart and
  // placeTileTapFor in gl_place_tiles.dart: a cluster zooms in, a place
  // opens (a pin or a dot that carries its id), a dot of the low zooms
  // zooms in, the long-press marker does nothing.
  function onClick(e) {
    if (suppressClick) { suppressClick = false; return; }
    // From the street, a click that just missed a pin opens it rather than
    // the card of a bare point (hitAroundTap in map_taps.dart); a sign of
    // the route that opens nothing still is no bare map.
    var free = spec.hit || { wider: 1.5, freePointMinZoom: 14 };
    var street = map.getZoom() >= free.freePointMinZoom;
    var hit = lunawayHits.pick(map, e.point, { layers: spec.tappable });
    if (!hit && street) hit = lunawayHits.pick(map, e.point, { layers: spec.tappable, wider: free.wider });
    if (!hit) {
      var sign = lunawayHits.pick(map, e.point, { layers: spec.tappable, wider: street ? free.wider : 1, signs: true });
      if (!sign) send({ type: 'empty', lat: e.lngLat.lat, lon: e.lngLat.lng, zoom: map.getZoom() });
      return;
    }
    if (hit.inert) return;
    var p = hit.properties;
    var at = hit.coordinates || [e.lngLat.lng, e.lngLat.lat];
    var duration = reducedMotion ? 0 : 600;
    // A mark of the route map: the app says what it stands for
    // (assets/map/route_marks.js), where it was clicked.
    if (p.mark !== undefined) {
      send({ type: 'mark', id: p.mark, x: e.point.x, y: e.point.y });
      return;
    }
    if (p.point_count !== undefined) {
      // The source the group is in: the route map groups two of them.
      var source = (hit.feature && hit.feature.source) || spec.clusterSource;
      map.getSource(source).getClusterExpansionZoom(p.cluster_id).then(function (zoom) {
        map.easeTo({ center: at, zoom: zoom + 0.3, duration: duration });
      });
      return;
    }
    if (p.kind === 'place' && p.id !== undefined) {
      send({ type: 'place', id: p.id });
      return;
    }
    var tiles = spec.placeTiles;
    if (tiles && tiles.layers.indexOf(hit.layer) >= 0) {
      if (p.id !== undefined) {
        send({ type: 'place', id: p.id, properties: p, coordinates: at });
      } else {
        // A dot of the low zooms: closer around the dot picked.
        var closer = Math.max(map.getZoom() + 3, tiles.pinZoom + 0.5);
        map.easeTo({ center: at, zoom: closer, duration: duration });
      }
      return;
    }
    // A point of interest, or where a category's points gather (the
    // same rule as poiTapFor in lib/features/poi/presentation).
    if (p.count !== undefined && p.id === undefined && spec.pois) {
      var next = Math.min(map.getZoom() + 2, spec.pois.pointsMinZoom + 0.5);
      map.easeTo({ center: at, zoom: next, duration: duration });
      return;
    }
    if (p.id !== undefined && p.kind !== undefined) {
      send({ type: 'poi', properties: p, coordinates: at });
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
        // Turned and tilted only on the guidance's map, which enables both
        // (route_motion.js); the mouse tilts with the turn then.
        dragRotate: false,
        pitchWithRotate: true,
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
      map.on('idle', probePlaces);
      map.on('click', onClick);
      // The spec changes with the style: read at each hover.
      lunawayHits.hover(map, { layers: function () { return spec.tappable; } });
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
      poiProbed = null;
      placesProbed = null;
      map.setStyle(style, { diff: true, transformStyle: withOwnLayers });
      return true;
    },
    setPlaceTiles: function (filter) {
      var tiles = spec && spec.placeTiles;
      if (!tiles || !map) return true;
      tiles.filter = filter;
      tiles.layers.forEach(function (id) {
        if (map.getLayer(id)) map.setFilter(id, filter);
      });
      spec.layers.forEach(function (layer) {
        if (tiles.layers.indexOf(layer.id) >= 0) layer.filter = filter;
      });
      placesProbed = null;
      return true;
    },
    // One of the app's layers filtered and shown or hidden, kept for the
    // next style change.
    setLayer: function (id, filter, visible) {
      spec.layers.forEach(function (layer) {
        if (layer.id !== id) return;
        layer.filter = filter;
        layer.layout = Object.assign({}, layer.layout, { visibility: visible ? 'visible' : 'none' });
      });
      if (map && map.getLayer(id)) {
        map.setFilter(id, filter);
        map.setLayoutProperty(id, 'visibility', visible ? 'visible' : 'none');
      }
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
