// Loads MapLibre GL JS with the page, beside the Flutter engine rather than
// after it, and publishes it as the `maplibregl` global the maplibre_gl
// plugin reads (MapLibreJsSource.preloaded in lib/main.dart). A file of its
// own: the Content-Security-Policy of /app/ refuses inline scripts.
//
// Its Map differs from MapLibre's in one way. The plugin gives the map a new
// style when the theme turns (or the language changes) and asks MapLibre to
// load it whole, which drops every tile, image, source and layer of the app
// and freezes the page while they come back. Here the new style is diffed
// against the loaded one instead, with the app's own sources and layers
// carried over: a theme is a few hundred paint properties and a sprite,
// applied at the next frame. When MapLibre cannot diff, it loads the style
// whole as before and the app sets itself up again on `style.load`.
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
    var HITS = /* BEGIN HIT SHAPES */ {"tolerance":{"touch":22.0,"mouse":14.0},"ring":{"color":"#f2a541","width":2.5,"gap":2.5},"shapes":{"lw-selection-pin":{"r":18.85,"y":26.9555,"p":0},"lw-selection-pin/point":{"r":14.0,"y":27.0,"p":0,"inert":true},"lw-poi-selection":{"r":15.4,"y":27.9,"p":0},"lw-places":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":1},"lw-place-pins":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":1},"lw-clusters":{"r":{"by":"point_count","stops":[[2.0,14.5],[10.0,16.5],[50.0,18.5],[200.0,21.5],[1000.0,24.5]]},"y":0.0,"p":2},"lw-place-pin-dots":{"r":{"by":"zoom","stops":[[3.0,1.9000000000000001],[6.0,3.2600000000000002],[8.0,4.3],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":3},"lw-place-dots":{"r":{"by":"zoom","stops":[[3.0,1.9000000000000001],[6.0,3.2600000000000002],[8.0,4.3],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":3},"lw-poi-pins":{"r":11.3,"y":17.8,"p":4},"lw-poi-quiet":{"r":8.9,"y":13.9,"p":5},"lw-poi-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":6},"lw-poi-vending-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":6},"lw-route-marks":{"r":{"prop":"radius","plus":3.0,"fallback":8.0},"y":0.0,"p":1,"needs":"id"},"lw-route-marks-tappable":{"r":{"prop":"radius","plus":3.0,"fallback":8.0},"y":0.0,"p":1,"needs":"id"},"lw-route-alternatives-line":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-alternatives-casing":{"r":0.0,"y":0.0,"p":9,"line":true}}} /* END HIT SHAPES */;
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
    function nearest(at, candidates, zoom, tolerance) {
      var best = null;
      var bestPriority = 0;
      for (var i = 0; i < candidates.length; i++) {
        var c = candidates[i];
        var props = c.properties || {};
        var shape = shapeOf(c.layer, props);
        if (!shape) continue;
        if (shape.needs && (props[shape.needs] === undefined || props[shape.needs] === null)) continue;
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
    // and on screen, and its shape; null for none.
    function pick(map, point, options) {
      options = options || {};
      var tolerance = HITS.tolerance[options.pointer || lastPointer] || HITS.tolerance.mouse;
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
      var hit = nearest([point.x, point.y], candidates, zoom, tolerance);
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

  // The app's own layers keep their place relative to the basemap's: each
  // goes before the basemap layer that followed it in the loaded style.
  function keepOwn(previous, next) {
    if (!previous || !previous.layers || !next || !next.layers) return next;
    var basemap = {};
    next.layers.forEach(function (layer) { basemap[layer.id] = true; });
    var sources = Object.assign({}, next.sources);
    Object.keys(previous.sources || {}).forEach(function (id) {
      if (!(id in sources)) sources[id] = previous.sources[id];
    });
    var before = {};
    var pending = [];
    previous.layers.forEach(function (layer) {
      if (basemap[layer.id]) {
        if (pending.length) {
          before[layer.id] = (before[layer.id] || []).concat(pending);
          pending = [];
        }
      } else if (layer.source === undefined || sources[layer.source]) {
        pending.push(layer);
      }
    });
    var layers = [];
    next.layers.forEach(function (layer) {
      (before[layer.id] || []).forEach(function (own) { layers.push(own); });
      layers.push(layer);
    });
    pending.forEach(function (own) { layers.push(own); });
    return Object.assign({}, next, { sources: sources, layers: layers });
  }

  // Marks, in the page's performance timeline, the first frame that draws
  // the places of the tiles: the startup budget of docs/architecture.md is
  // measured against it ("points visible").
  function markPlacesDrawn(map) {
    var loaded = false;
    function onData(e) {
      if (e.sourceId === 'lw-place-tiles' && e.isSourceLoaded && e.tile) loaded = true;
    }
    function onRender() {
      if (!loaded) return;
      map.off('sourcedata', onData);
      map.off('render', onRender);
      if (window.performance && performance.mark) performance.mark('lunaway-places-drawn');
    }
    map.on('sourcedata', onData);
    map.on('render', onRender);
  }

  // Counts the tiles of the places that failed to load (MapLibre reports
  // neither a 404 nor an empty tile as an error). The list beside the map
  // reads the tiles in view from the zoom of the names; when one failed,
  // the app asks the API instead (PlaceTileErrors in lib/core/web/).
  function countTileErrors(map) {
    map.on('error', function (e) {
      if (e && e.sourceId === 'lw-place-tiles') {
        window.lunawayPlaceTileErrors = (window.lunawayPlaceTileErrors || 0) + 1;
      }
    });
  }

  // The app's pin images (places, points of interest) load when a layer
  // first draws one, from the app's assets, decoded by the browser off the
  // page's thread: no image is fetched or decoded before it is seen, and the
  // country view at launch draws dots, which need none. The density matches
  // PinSprites.ratioFor in lib/shared/map/sprites.dart.
  var pinRatio = (window.devicePixelRatio || 1) > 2.05 ? 3 : 2;
  var PIN_ID = /^(pin|poi)-[A-Za-z0-9_-]+$/;
  function loadMissingPins(map) {
    var asked = {};
    map.on('styleimagemissing', function (e) {
      var id = e.id;
      // The ids the app names its images by (allPinImageIds, PoiMapStyle.allImageIds):
      // the kinds of points of interest carry underscores (poi-vending_pizza).
      if (asked[id] || !PIN_ID.test(id)) return;
      asked[id] = true;
      var src = new URL('assets/assets/map/pins/' + pinRatio + 'x/' + id + '.png', document.baseURI).href;
      fetch(src)
        .then(function (r) { return r.ok ? r.blob() : Promise.reject(r.status); })
        .then(function (blob) { return createImageBitmap(blob); })
        .then(function (bitmap) {
          if (!map.hasImage(id)) map.addImage(id, bitmap, { pixelRatio: pinRatio });
        })
        .catch(function () { asked[id] = false; });
    });
  }

  // The page's first map (premap.js) loads its pins the same way, and
  // picks and hovers features by the same rule; the app reads which
  // pointer last pressed (webMapPointerKind in
  // lib/features/map/presentation/web_map_controls_web.dart).
  window.lunawayLoadMissingPins = loadMissingPins;
  window.lunawayHits = lunawayHits;

  // The app's maps show their own cursor only where the app sees them
  // under the mouse: the app marks it on the body (WebMapPointer in
  // lib/features/map/presentation/web_map_pointer.dart).
  function onAppMap() {
    return document.body.classList.contains('lw-on-map');
  }

  var url = new URL('maplibre-gl/maplibre-gl.mjs', document.baseURI).href;
  import(url).then(function (lib) {
    var Base = lib.Map;
    class LunawayMap extends Base {
      constructor(options) {
        super(options);
        markPlacesDrawn(this);
        loadMissingPins(this);
        countTileErrors(this);
        lunawayHits.hover(this, { gate: onAppMap });
      }

      setStyle(style, options) {
        // The first style, given to the constructor, loads as usual.
        if (!this.style || this.style._loaded === false) return super.setStyle(style, options);
        return super.setStyle(style, Object.assign({}, options, { diff: true, transformStyle: keepOwn }));
      }
    }
    globalThis.maplibregl = Object.assign({}, lib, { Map: LunawayMap });
  }).catch(function (error) {
    // The plugin waits for the global and reports its absence; this line
    // says why it never came.
    console.error('MapLibre GL JS did not load', error);
  });
})();
