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
    var HITS = /* BEGIN HIT SHAPES */ {"tolerance":{"touch":22.0,"mouse":14.0},"ring":{"color":"#f2a541","width":2.5,"gap":2.5,"grow":1.12,"ms":160,"enter":[0.215,0.61,0.355,1.0],"exit":[0.55,0.055,0.675,0.19]},"shapes":{"lw-selection-pin":{"r":18.85,"y":26.9555,"p":0,"a":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]}},"lw-selection-pin/point":{"r":14.0,"y":27.0,"p":0,"marker":true},"lw-saved-pins":{"r":11.200000000000001,"y":21.6,"p":1,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":0.8},"lw-poi-selection":{"r":15.4,"y":27.9,"p":0,"a":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]}},"lw-places":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":2,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":{"by":"zoom","stops":[[6.0,0.72],[12.0,1.0]]}},"lw-clusters":{"r":{"by":"point_count","stops":[[2.0,14.5],[10.0,16.5],[50.0,18.5],[200.0,21.5],[1000.0,24.5]]},"y":0.0,"p":3},"lw-poi-pins":{"r":11.3,"y":17.8,"p":4,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-pins-more":{"r":11.3,"y":17.8,"p":4,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-place-pins":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":5,"a":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":{"by":"zoom","stops":[[6.0,0.72],[12.0,1.0]]}},"lw-place-pin-dots":{"r":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":6},"lw-place-dots":{"r":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":6},"lw-poi-quiet":{"r":8.9,"y":13.9,"p":7,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-quiet-more":{"r":8.9,"y":13.9,"p":7,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":8},"lw-poi-vending-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":8},"lw-route-minor-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":5,"state":"mark"},"lw-route-marks-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":4,"state":"mark"},"lw-route-stops-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":3,"state":"mark"},"lw-route-ends-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":1,"state":"mark"},"lw-route-alternatives-line":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-alternatives-casing":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-rich-marks":{"r":{"prop":"hr","plus":0.0,"fallback":0.0},"y":{"prop":"lift","plus":0.0,"fallback":0.0},"p":2},"lw-route-place-pins":{"r":{"by":"zoom","stops":[[6.0,7.5168],[12.0,10.44]]},"y":{"by":"zoom","stops":[[6.0,10.749023999999999],[12.0,14.9292]]},"p":6,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":{"by":"zoom","stops":[[6.0,0.5184],[12.0,0.72]]}},"lw-route-poi-pins":{"r":8.814,"y":13.884,"p":8,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":0.78},"lw-route-poi-pins-more":{"r":8.814,"y":13.884,"p":7,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":0.78}}} /* END HIT SHAPES */;
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

    // How far `at` lies outside the disc of radius r around (x, y); zero
    // inside.
    function outside(at, x, y, r) {
      var dx = at[0] - x;
      var dy = at[1] - y;
      return Math.max(0, Math.sqrt(dx * dx + dy * dy) - r);
    }

    // Candidates topmost first: {layer, properties, points: [[x, y], ...]}.
    // A tie goes to the lower priority, then to the one drawn on top. A
    // pin's target is its head and the dot at its tip (`a`), drawn by
    // another layer from the same feature: on the exact point, the pin and
    // its dot tie, and the pin wins.
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
          var anchor = shape.a === undefined ? -1 : value(shape.a, zoom, props);
          distance = Infinity;
          for (var j = 0; j < c.points.length; j++) {
            var p = c.points[j];
            var d = outside(at, p[0], p[1] - lift, r);
            if (anchor >= 0) d = Math.min(d, outside(at, p[0], p[1], anchor));
            if (d < distance) {
              distance = d;
              point = j;
            }
          }
        }
        if (distance > tolerance) continue;
        if (!best || distance < best.distance - EPSILON ||
            (distance <= best.distance + EPSILON && shape.p < bestPriority)) {
          best = { index: i, pointIndex: point, distance: distance, marker: !!shape.marker };
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
        marker: hit.marker
      };
    }

    // What the hover shows of the feature a pick chose: one look per
    // feature, whichever part of it the mouse is on (a pin's head, the dot
    // at its tip). `key` names the feature by its source and id, never by
    // the layer that drew the part picked. `x`, `y`: the feature's own point
    // on screen, the centre of a ring of radius `ring` clear of the dot or
    // the disc drawn there (a pin's tip, a cluster). `pin`: the image the
    // pin is drawn with and its size, which the hover grows. `state`: the
    // feature to tell, through its feature state, that the mouse is on it.
    // Null where nothing is shown (a line, the marker of a bare point).
    function look(hit) {
      if (!hit || hit.marker || !hit.point || !hit.shape || hit.shape.line) return null;
      var shape = hit.shape;
      var props = hit.properties || {};
      var f = hit.feature || {};
      var out = {
        key: [f.source, f.sourceLayer, f.id, props.id, props.cluster_id, props.mark,
          hit.coordinates ? hit.coordinates.join(',') : ''].join('|'),
        x: hit.point[0],
        y: hit.point[1],
        ring: value(shape.ring !== undefined ? shape.ring : shape.a !== undefined ? shape.a : shape.r,
          hit.zoom, props) + HITS.ring.gap,
        pin: null,
        state: null
      };
      var layer = f.layer || {};
      var image = (layer.layout || {})['icon-image'];
      var name = image && typeof image === 'object' ? image.name : image;
      var opacity = (layer.paint || {})['icon-opacity'];
      // A pin drawn faded (a point closed now) keeps its look: a copy over
      // it would add up to a darker pin.
      var faded = typeof opacity === 'number' && opacity < 1;
      if (shape.icon !== undefined && typeof name === 'string' && name && !faded) {
        out.pin = { image: name, size: value(shape.icon, hit.zoom, props) };
        out.key += '|' + name;
      }
      if (shape.state && props[shape.state] !== undefined && f.id !== undefined && f.id !== null && f.source) {
        out.state = { source: f.source, id: f.id };
      }
      return out;
    }

    // The pointing finger over what a click would pick, the closed hand
    // while the map is dragged, and the look of the feature under the
    // mouse (look). One query per animation frame at most, while the mouse
    // moves or once the map settles after a change. `options.gate`: whether
    // the map is the one under the mouse (the app's maps, under the app's
    // own surfaces); `options.layers` a function giving the layers to pick
    // from.
    function hover(map, options) {
      options = options || {};
      var container = map.getCanvasContainer();
      var last = null;
      var frame = 0;
      var moving = false;
      var shownKey = null;
      var shown = null;
      var stale = false;
      var root = null;
      var less = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;

      function still() {
        return !!(less && less.matches);
      }

      // The looks are elements over the map's canvas, as MapLibre's markers
      // are: the browser draws and eases them, and the map spends no frame
      // on a hover.
      function layer() {
        if (!root || root.parentNode !== container) {
          root = document.createElement('div');
          root.style.cssText = 'position:absolute;left:0;top:0;width:0;height:0;pointer-events:none';
          container.appendChild(root);
        }
        return root;
      }

      // The pin's image as the map holds it, drawn at the size the map draws
      // it, standing on its tip as the pin does.
      function pinCopy(pin) {
        var image = map.getImage ? map.getImage(pin.image) : null;
        var data = image && image.data;
        if (!data || !data.width || !data.height || image.sdf) return null;
        var canvas = document.createElement('canvas');
        canvas.width = data.width;
        canvas.height = data.height;
        var context = canvas.getContext('2d');
        if (!context) return null;
        context.putImageData(new ImageData(new Uint8ClampedArray(data.data), data.width, data.height), 0, 0);
        var w = data.width / (image.pixelRatio || 1) * pin.size;
        var h = data.height / (image.pixelRatio || 1) * pin.size;
        canvas.style.cssText = 'position:absolute;left:' + (-w / 2) + 'px;top:' + (-h) + 'px;width:' + w +
          'px;height:' + h + 'px;transform-origin:50% 100%;transform:scale(1)';
        return canvas;
      }

      // Eases the parts of a look in (`on`) or back out to the map's own
      // drawing: the ring fades in as it closes on the point, the pin grows
      // from the size the map draws it at, and both go back the same way.
      function ease(parts, on) {
        var g = HITS.ring;
        var timing = g.ms + 'ms cubic-bezier(' + (on ? g.enter : g.exit).join(',') + ')';
        var transition = still() ? 'none' : 'opacity ' + timing + ',transform ' + timing;
        if (parts.ring) {
          parts.ring.style.transition = transition;
          parts.ring.style.opacity = on ? '1' : '0';
          parts.ring.style.transform = on ? 'scale(1)' : 'scale(0.8)';
        }
        if (parts.pin) {
          parts.pin.style.transition = still() ? 'none' : 'transform ' + timing;
          parts.pin.style.transform = 'scale(' + (on ? g.grow : 1) + ')';
        }
      }

      function draw(l) {
        var g = HITS.ring;
        var el = document.createElement('div');
        el.style.cssText = 'position:absolute;left:0;top:0;transform:translate(' + l.x + 'px,' + l.y + 'px)';
        var ring = null;
        if (l.ring > 0) {
          // The ring's inside edge at `ring`, as a circle's stroke is drawn.
          var outer = l.ring + g.width;
          ring = document.createElement('div');
          ring.style.cssText = 'position:absolute;box-sizing:border-box;border-radius:50%;left:' + (-outer) +
            'px;top:' + (-outer) + 'px;width:' + 2 * outer + 'px;height:' + 2 * outer + 'px;border:' +
            g.width + 'px solid ' + g.color + ';opacity:0;transform:scale(0.8)';
          el.appendChild(ring);
        }
        var pin = l.pin ? pinCopy(l.pin) : null;
        if (pin) el.appendChild(pin);
        layer().appendChild(el);
        var parts = { el: el, ring: ring, pin: pin };
        // The starting look applies before the eased one.
        if (!still()) void el.offsetWidth;
        ease(parts, true);
        return parts;
      }

      // A look that goes eases out, then leaves; `now` when the map moves,
      // which the elements would not follow.
      function undraw(parts, now) {
        if (now || still()) {
          parts.el.remove();
          return;
        }
        ease(parts, false);
        setTimeout(function () { parts.el.remove(); }, HITS.ring.ms + 50);
      }

      // A route mark is told the mouse is on it: its lit ring gives way to
      // the hover's (RouteMarkStyle.haloOpacity).
      function tell(l, on) {
        if (!l || !l.state || !map.getSource(l.state.source)) return;
        try {
          map.setFeatureState(l.state, { hover: on });
        } catch (e) {
          // The source went with a style change: nothing left to tell.
        }
      }

      // The same feature after a click: its copy comes back, grown from what
      // the map draws now.
      function regrow(s, l) {
        var pin = pinCopy(l.pin);
        if (!pin) return;
        s.parts.el.appendChild(pin);
        s.parts.pin = pin;
        if (!still()) void pin.offsetWidth;
        ease({ pin: pin }, true);
      }

      function show(hit, now) {
        var l = look(hit);
        var key = l ? l.key : hit ? hit.layer + '|' + JSON.stringify(hit.properties) : null;
        if (key === shownKey) {
          if (stale && shown && l && l.pin && !shown.parts.pin) regrow(shown, l);
          stale = false;
          return;
        }
        stale = false;
        shownKey = key;
        container.classList.toggle('lw-hit', !!hit);
        if (shown) {
          tell(shown.look, false);
          undraw(shown.parts, now);
          shown = null;
        }
        if (l) {
          tell(l, true);
          shown = { look: l, parts: draw(l) };
        }
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
        show(hit);
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
        show(null, true);
        // A look still easing out stays where the map was.
        if (root) root.textContent = '';
      });
      map.on('moveend', function () {
        moving = false;
        if (last) later();
      });
      // A click may change what the map draws under the look (the pin it
      // selects, drawn anew): the copy of the old drawing goes at once,
      // the ring stays, and the next pick grows the copy again from what
      // the map then draws.
      map.on('mousedown', function () {
        if (!shown || !shown.parts.pin) return;
        shown.parts.pin.remove();
        shown.parts.pin = null;
        stale = true;
      });
      // The map settled after drawing something new (a selection, tiles, a
      // theme): one pick, for the look of what is now under the mouse. The
      // looks draw nothing on the map, so a still mouse costs nothing more.
      map.on('idle', function () {
        if (last && !moving) later();
      });
      map.on('dragstart', function () { container.classList.add('lw-dragging'); });
      map.on('dragend', function () { container.classList.remove('lw-dragging'); });
    }

    return {
      nearest: nearest,
      pick: pick,
      look: look,
      shapeOf: shapeOf,
      hover: hover,
      pointerType: function () { return lastPointer; }
    };
  })();
  // END MAP HITS

  // BEGIN GESTURES
  // The app's maps are HTML elements laid out under the app's canvas, and
  // the browser hands them the touches and clicks wherever they lie: those
  // meant for a sheet or a button the app draws over them, and the late
  // ones of a tap the app has already taken. A phone's browser sends the
  // mouse events of a tap (mousedown, mouseup, click) after its touch, up
  // to a few hundred milliseconds later, to whatever element lies under the
  // finger by then: a search result tapped closes its list, and its click
  // fell on the map that the list no longer covered, which cut the flight
  // to the result short and acted on the map (the card just opened closed,
  // a cluster opened). A gesture is a map's only when the app's own hit
  // test gave it its first press (`claim`, called by the app while it
  // handles that press: WebMapPointer in
  // lib/features/map/presentation/web_map_pointer.dart); the touch and
  // mouse events of any other gesture stop before they reach a map. The
  // wheel and a mouse that only moves are no gesture and pass.
  var lunawayGestures = (function () {
    var GATED = ['touchstart', 'touchmove', 'touchend', 'touchcancel', 'mousedown', 'mouseup',
      'click', 'dblclick', 'contextmenu'];
    var claimed = false;

    // A map of the app: one in a platform view of the Flutter view. The
    // page's first map (premap.js) lies outside it and keeps its gestures.
    function onAppMap(target) {
      return !!(target && target.closest && target.closest('flt-platform-view .maplibregl-map'));
    }

    // win, doc: the page's window and document (stand-ins in tests).
    function install(win, doc) {
      // Heard first: a gesture belongs to no map until the app says so. A
      // second finger joins the gesture of the first.
      win.addEventListener('pointerdown', function (e) {
        if (e.isPrimary) claimed = false;
      }, true);
      GATED.forEach(function (type) {
        doc.addEventListener(type, function (e) {
          if (claimed || !onAppMap(e.target)) return;
          e.stopPropagation();
          // Nor does the map's canvas take the focus from the app.
          if (type === 'mousedown') e.preventDefault();
        }, true);
      });
    }

    return {
      install: install,
      claim: function () { claimed = true; },
      owns: function () { return claimed; }
    };
  })();
  // END GESTURES

  // BEGIN ROUTE MOTION
  // The guidance's vehicle and camera, run by the page rather than by the
  // app at every frame: the app sends one call per fix and per change of
  // view. The same rules as VehicleMotion and followZoom in
  // lib/features/navigation/presentation/vehicle_motion.dart, and as FreeMap
  // in lib/features/navigation/domain/free_map.dart. This block is the same
  // in web/lunaway_maplibre.js and assets/map/route_motion.js
  // (test/unit/navigation/route_motion_js_test.dart).
  var lunawayRouteMotion = (function () {
    var MAX_GLIDE = 1500;
    // A fix this far from the drawn vehicle is a jump (a new route from
    // elsewhere), not a move to glide through, metres.
    var JUMP_M = 500;
    var TILT = 55;
    // A finger held this long without sliding is a long press (the
    // browser's map has none of its own).
    var HOLD_MS = 600;
    var HOLD_SLOP = 10;
    // The app's own camera moves carry this in their event data: the app
    // ignores them (third_party/maplibre_gl_web) and so does the gesture
    // watch below.
    var OWN = { lunawayMotion: true };

    function delta(a, b) {
      var d = (((b - a) % 360) + 360) % 360;
      return d > 180 ? d - 360 : d;
    }

    function lerp(a, b, k) { return a + (b - a) * k; }

    // Motion.standard (Curves.easeInOutCubic).
    function standard(t) {
      return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
    }

    function metres(a, b) {
      var r = Math.PI / 180;
      var x = (b.lon - a.lon) * r * Math.cos(((a.lat + b.lat) / 2) * r);
      var y = (b.lat - a.lat) * r;
      return Math.sqrt(x * x + y * y) * 6371008.8;
    }

    function padding(p) {
      p = p || {};
      return { top: p.top || 0, bottom: p.bottom || 0, left: p.left || 0, right: p.right || 0 };
    }

    // map: a MapLibre GL JS map; emit(event): tells the app. options.longPress:
    // report long presses (the browser; the desktop page has its own).
    // options.owns: whether the gesture under way is the map's, asked when
    // a press lands on it (the browser's page: the app decides by its own
    // hit test, lunawayGestures); every press is the map's without it.
    // options.now and options.frame stand in for the clock and
    // requestAnimationFrame in tests.
    function create(map, emit, options) {
      options = options || {};
      var now = options.now || function () { return performance.now(); };
      var frameFn = options.frame || function (f) { return requestAnimationFrame(f); };
      var cancelFn = options.cancel || function (id) { cancelAnimationFrame(id); };
      var source = null;
      var from = null;
      var to = null;
      var start = 0;
      var length = 0;
      var lastTarget = null;
      // While following: { zoom, padding, ease }.
      var follow = null;
      var entry = null;
      var zoom = null;
      var bearing = 0;
      var lastFrame = 0;
      var frame = null;
      var guiding = false;
      // The preview's map tells the app that the user moved it, nothing
      // more: no press, no rest.
      var watching = false;
      var pressed = {};
      var pressedCount = 0;
      // A gesture of the user since the camera last rested.
      var userMoved = false;
      var hold = null;

      function at(t) {
        if (!from || !to) return null;
        var k = length <= 0 ? 1 : Math.min(1, Math.max(0, (t - start) / length));
        var course = from.course === null || to.course === null
          ? (to.course !== null ? to.course : from.course)
          : (((from.course + delta(from.course, to.course) * k) % 360) + 360) % 360;
        return {
          lat: from.lat + (to.lat - from.lat) * k,
          lon: from.lon + (to.lon - from.lon) * k,
          course: course,
          moving: k < 1
        };
      }

      function step(t) {
        frame = null;
        var shown = at(t);
        if (!shown) return;
        var dt = lastFrame ? t - lastFrame : 0;
        lastFrame = t;
        var src = source && map.getSource(source);
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
        // A finger or the button down on the map: the camera waits, for
        // MapLibre drops a gesture it has begun when the camera is moved
        // under it. A tap lets the camera go on as it lifts; a drag is a
        // gesture (onUserMove).
        if (follow && pressedCount > 0) settled = false;
        if (follow && pressedCount === 0) {
          zoom = zoom === null ? follow.zoom : zoom + (follow.zoom - zoom) * Math.min(1, dt / 2000);
          if (Math.abs(follow.zoom - zoom) > 0.01) settled = false;
          if (shown.course !== null) bearing = shown.course;
          var camera = {
            center: [shown.lon, shown.lat],
            zoom: zoom,
            bearing: bearing,
            pitch: TILT,
            padding: follow.padding
          };
          // Into following: from the view the map had to the driver's.
          if (entry) {
            var k = entry.ms > 0 ? (t - entry.start) / entry.ms : 1;
            if (k >= 1) {
              entry = null;
            } else {
              settled = false;
              var e = standard(Math.max(0, k));
              var f = entry.from;
              var p = follow.padding;
              camera.center = [lerp(f.lon, shown.lon, e), lerp(f.lat, shown.lat, e)];
              camera.zoom = lerp(f.zoom, zoom, e);
              camera.bearing = (((f.bearing + delta(f.bearing, bearing) * e) % 360) + 360) % 360;
              camera.pitch = lerp(f.pitch, TILT, e);
              camera.padding = {
                top: lerp(f.padding.top, p.top, e),
                bottom: lerp(f.padding.bottom, p.bottom, e),
                left: lerp(f.padding.left, p.left, e),
                right: lerp(f.padding.right, p.right, e)
              };
            }
          }
          map.jumpTo(camera, OWN);
        }
        if (!settled) frame = frameFn(step);
      }

      function kick() {
        if (frame !== null) return;
        // Measured from now: after a pause the zoom must not catch up in
        // one step.
        lastFrame = 0;
        frame = frameFn(step);
      }

      function stopFollowing() {
        follow = null;
        entry = null;
        zoom = null;
      }

      // The camera the user moved has come to rest and nothing presses on
      // the map: where the vehicle is drawn, for the magnet.
      function rest() {
        if (!userMoved || pressedCount > 0 || follow) return;
        userMoved = false;
        if (!guiding) return;
        var shown = at(now());
        var point = shown ? map.project([shown.lon, shown.lat]) : null;
        var canvas = map.getCanvas();
        var center = map.getCenter();
        emit({
          type: 'rest',
          lat: center.lat,
          lon: center.lng,
          x: point ? point.x : null,
          y: point ? point.y : null,
          zoom: map.getZoom(),
          bearing: map.getBearing(),
          pitch: map.getPitch(),
          width: canvas.clientWidth,
          height: canvas.clientHeight
        });
      }

      // A camera move the user caused (it carries the browser's event):
      // following stops at once, before the app answers.
      function onUserMove(e) {
        if (!e || !e.originalEvent || e.lunawayMotion) return;
        if (!guiding && !watching) return;
        if (follow) stopFollowing();
        if (!userMoved) {
          userMoved = true;
          emit({ type: 'gesture' });
        }
      }

      function cancelHold() {
        if (hold !== null) clearTimeout(hold.timer);
        hold = null;
      }

      function onPointerDown(e) {
        if (pressed[e.pointerId]) return;
        pressed[e.pointerId] = true;
        pressedCount += 1;
        if (pressedCount === 1 && guiding) emit({ type: 'touch', down: true });
        cancelHold();
        if (options.longPress && pressedCount === 1 && e.pointerType === 'touch') {
          var box = map.getCanvasContainer().getBoundingClientRect();
          var x = e.clientX - box.left;
          var y = e.clientY - box.top;
          hold = {
            x: e.clientX,
            y: e.clientY,
            timer: setTimeout(function () {
              hold = null;
              var at = map.unproject([x, y]);
              emit({ type: 'longpress', lat: at.lat, lon: at.lng, x: x, y: y });
            }, HOLD_MS)
          };
        }
      }

      function onPointerMove(e) {
        if (hold && (Math.abs(e.clientX - hold.x) > HOLD_SLOP || Math.abs(e.clientY - hold.y) > HOLD_SLOP)) {
          cancelHold();
        }
      }

      function onPointerUp(e) {
        if (!pressed[e.pointerId]) return;
        delete pressed[e.pointerId];
        pressedCount -= 1;
        cancelHold();
        if (pressedCount > 0) return;
        if (guiding) emit({ type: 'touch', down: false });
        if (!map.isMoving()) rest();
      }

      // The page lost the pointer (another window): nothing presses any more.
      function onBlur() {
        if (pressedCount === 0) return;
        pressed = {};
        pressedCount = 0;
        cancelHold();
        if (guiding) emit({ type: 'touch', down: false });
      }

      var container = map.getCanvasContainer();
      // Heard on the window once the press has gone through the page: the
      // app has had it by then and said whether it is the map's. A press on
      // a button the app draws over the map is not a touch of the map.
      function onPagePointerDown(e) {
        if (!container.contains(e.target)) return;
        if (options.owns && !options.owns()) return;
        onPointerDown(e);
      }
      window.addEventListener('pointerdown', onPagePointerDown);
      container.addEventListener('pointermove', onPointerMove);
      // Released anywhere: a drag may end off the map.
      window.addEventListener('pointerup', onPointerUp, true);
      window.addEventListener('pointercancel', onPointerUp, true);
      window.addEventListener('blur', onBlur);
      // The wheel too: MapLibre starts a wheel's zoom from its next frame,
      // without the browser's event.
      ['wheel', 'movestart', 'dragstart', 'zoomstart', 'rotatestart', 'pitchstart'].forEach(function (name) {
        map.on(name, onUserMove);
      });
      map.on('moveend', function (e) {
        if (e && e.lunawayMotion) return;
        rest();
      });
      if (options.longPress) {
        // MapLibre holds a right click until the button comes up and drops
        // it when the drag turned the map: a turn is no long press.
        map.on('contextmenu', function (e) {
          emit({ type: 'longpress', lat: e.lngLat.lat, lon: e.lngLat.lng, x: e.point.x, y: e.point.y });
        });
      }
      map.on('remove', function () {
        if (frame !== null) cancelFn(frame);
        frame = null;
        cancelHold();
        window.removeEventListener('pointerdown', onPagePointerDown);
        window.removeEventListener('pointerup', onPointerUp, true);
        window.removeEventListener('pointercancel', onPointerUp, true);
        window.removeEventListener('blur', onBlur);
      });

      var run = {
        // A new fix; jump: drawn there at once (the first fix, a new route
        // from elsewhere, reduced motion).
        vehicle: function (sourceId, lat, lon, course, jump) {
          source = sourceId;
          var t = now();
          var shown = at(t);
          var target = { lat: lat, lon: lon, course: course === undefined ? null : course };
          // The same fix again changes nothing: restarting would cut the glide.
          if (!jump && to && to.lat === lat && to.lon === lon &&
              (target.course === null || target.course === to.course)) {
            return true;
          }
          var gap = lastTarget === null ? 1000 : t - lastTarget;
          lastTarget = t;
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
          start = t;
          kick();
          return true;
        },
        // No vehicle any more: the glide stops, so no frame draws it back.
        // The caller empties the source.
        clear: function () {
          if (frame !== null) cancelFn(frame);
          frame = null;
          from = null;
          to = null;
          lastTarget = null;
          return true;
        },
        // Following: { zoom, padding, ease (ms, the way in), enter }. From
        // another view, the camera eases from it into the driver's. Only
        // `enter` starts following: a fix that comes after a gesture
        // stopped it, before the app heard of the gesture, changes nothing.
        follow: function (next) {
          if (!next) return run.free();
          if (!follow && !next.enter) return true;
          var pad = padding(next.padding);
          if (!follow) {
            var c = map.getCenter();
            entry = {
              from: {
                lat: c.lat,
                lon: c.lng,
                zoom: map.getZoom(),
                bearing: map.getBearing(),
                pitch: map.getPitch(),
                padding: padding(map.getPadding())
              },
              start: now(),
              ms: next.ease || 0
            };
            userMoved = false;
          }
          follow = { zoom: next.zoom, padding: pad };
          kick();
          return true;
        },
        // Where the user left it: following stops, the camera stays.
        free: function () {
          stopFollowing();
          return true;
        },
        // The whole route: flat, north up, no insets; the caller then fits
        // the route.
        overview: function () {
          stopFollowing();
          map.jumpTo({ padding: { top: 0, bottom: 0, left: 0, right: 0 }, pitch: 0, bearing: 0 }, OWN);
          return true;
        },
        // The guidance's map tells the app of gestures, presses and rests;
        // the preview's does not.
        guiding: function (on) {
          guiding = !!on;
          return true;
        },
        // Whether a map that is not guiding tells the app of the user's
        // gestures, once per move: the preview frames the route clear of
        // its legend until the user takes the map.
        watch: function (on) {
          watching = !!on;
          return true;
        },
        // Whether the camera follows, for the app's tests in a browser.
        following: function () { return follow !== null; }
      };
      return run;
    }

    return { create: create };
  })();
  // END ROUTE MOTION

  // The app's maps, for the guidance's motion: a route map names itself by
  // a source of its own (gl_route_map.dart), and its motion is made once.
  var liveMaps = [];
  window.lunawayRouteMotion = {
    // The motion of the map that holds the source `tag`, reporting to
    // `emit` (the app's latest listener); null while no map holds it.
    bind: function (tag, emit) {
      for (var i = 0; i < liveMaps.length; i++) {
        var map = liveMaps[i];
        if (!map.getSource(tag)) continue;
        if (!map.lunawayMotion) {
          var sink = { emit: emit };
          map.lunawayMotion = {
            sink: sink,
            run: lunawayRouteMotion.create(map, function (event) { sink.emit(event); }, {
              longPress: true,
              owns: lunawayGestures.owns
            })
          };
        }
        map.lunawayMotion.sink.emit = emit;
        return map.lunawayMotion.run;
      }
      return null;
    },
    // Takes an image off the map that holds the source `tag`: GL JS keeps
    // the first image added under an id, and the app fills the image slots
    // of its rich marks again (rich_marks.dart).
    dropImage: function (tag, id) {
      for (var i = 0; i < liveMaps.length; i++) {
        var map = liveMaps[i];
        if (map.getSource(tag) && map.hasImage(id)) map.removeImage(id);
      }
    }
  };

  // BEGIN KEEP OWN
  // The app's own layers keep their place relative to the basemap's: each
  // goes before the basemap layer that followed it in the loaded style
  // (the route's lines under the names of towns, RouteLayerOrder in the
  // app). test/widget/route_layer_order_test.dart runs this block.
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
  // END KEEP OWN

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

  // The app claims the gestures its hit test gives to a map
  // (claimWebMapGesture in lib/features/map/presentation/web_map_controls_web.dart).
  lunawayGestures.install(window, document);
  window.lunawayGestures = lunawayGestures;

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
        var self = this;
        liveMaps.push(this);
        this.on('remove', function () {
          liveMaps = liveMaps.filter(function (m) { return m !== self; });
        });
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
