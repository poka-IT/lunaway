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
    var HITS = /* BEGIN HIT SHAPES */ {"tolerance":{"touch":22.0,"mouse":14.0},"ring":{"color":"#f2a541","width":2.5,"gap":2.5,"grow":1.12,"ms":160,"enter":[0.215,0.61,0.355,1.0],"exit":[0.55,0.055,0.675,0.19]},"shapes":{"lw-selection-pin":{"r":18.85,"y":26.9555,"p":0,"a":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]}},"lw-selection-pin/point":{"r":14.0,"y":27.0,"p":0,"marker":true},"lw-poi-selection":{"r":15.4,"y":27.9,"p":0,"a":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]}},"lw-places":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":1,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":{"by":"zoom","stops":[[6.0,0.72],[12.0,1.0]]}},"lw-place-pins":{"r":{"by":"zoom","stops":[[6.0,10.44],[12.0,14.5]]},"y":{"by":"zoom","stops":[[6.0,14.9292],[12.0,20.735]]},"p":1,"a":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":{"by":"zoom","stops":[[6.0,0.72],[12.0,1.0]]}},"lw-clusters":{"r":{"by":"point_count","stops":[[2.0,14.5],[10.0,16.5],[50.0,18.5],[200.0,21.5],[1000.0,24.5]]},"y":0.0,"p":2},"lw-place-pin-dots":{"r":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":3},"lw-place-dots":{"r":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"y":0.0,"p":3},"lw-poi-pins":{"r":11.3,"y":17.8,"p":4,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-pins-more":{"r":11.3,"y":17.8,"p":4,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-quiet":{"r":8.9,"y":13.9,"p":5,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-quiet-more":{"r":8.9,"y":13.9,"p":5,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":1.0},"lw-poi-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":6},"lw-poi-vending-dots":{"r":{"by":"count","stops":[[1.0,6.6],[10.0,8.8],[60.0,11.0]]},"y":0.0,"p":6},"lw-route-anchors-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":1,"state":"mark"},"lw-route-marks-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":2,"state":"mark"},"lw-route-minor-badges":{"r":{"by":"size","stops":[[0.72,11.16],[1.0,15.5]]},"y":0.0,"p":3,"state":"mark"},"lw-route-alternatives-line":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-alternatives-casing":{"r":0.0,"y":0.0,"p":9,"line":true},"lw-route-rich-marks":{"r":{"prop":"hr","plus":0.0,"fallback":0.0},"y":{"prop":"lift","plus":0.0,"fallback":0.0},"p":3},"lw-route-place-pins":{"r":{"by":"zoom","stops":[[6.0,7.5168],[12.0,10.44]]},"y":{"by":"zoom","stops":[[6.0,10.749023999999999],[12.0,14.9292]]},"p":4,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":{"by":"zoom","stops":[[6.0,0.5184],[12.0,0.72]]}},"lw-route-poi-pins":{"r":8.814,"y":13.884,"p":5,"ring":{"by":"zoom","stops":[[3.0,1.0],[5.0,1.54],[7.0,2.9800000000000004],[8.0,3.9000000000000004],[9.0,4.824999999999999],[12.0,6.4]]},"icon":0.78}}} /* END HIT SHAPES */;
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

  // Once the map rests at the zoom of the pins: every place of the tiles,
  // whatever the filter, for the list beside the map, the count of the
  // filters' sheet and the points of interest that leave them room (the
  // same reading as GlPlaceTiles.probe in the app, which keeps those inside
  // the bounds sent and applies the filter). Of two copies of a place, the
  // one that carries its name and town stays: a tile below the zoom of the
  // names may still be held by the engine.
  function probePlaces() {
    var tiles = spec && spec.placeTiles;
    // The guidance's map lists no places: it only opens them.
    if (!tiles || tiles.probe === false || !map.getSource(tiles.source)) return;
    var c = map.getCenter();
    var zoom = map.getZoom();
    var view = map.getBounds();
    // The view too: a resize keeps the camera and changes what is in view.
    var key = [c.lat, c.lng, zoom, view.toArray().join(',')].join(',');
    if (key === placesProbed) return;
    placesProbed = key;
    var named = function (p) { return (p.name ? 1 : 0) + (p.city ? 1 : 0); };
    var seen = {};
    var features = [];
    if (zoom >= tiles.pinZoom) {
      map.querySourceFeatures(tiles.source, { sourceLayer: tiles.sourceLayer })
        .forEach(function (f) {
          var id = f.properties && f.properties.id;
          if (id === undefined) return;
          var copy = { geometry: { coordinates: f.geometry.coordinates }, properties: f.properties };
          if (seen[id] === undefined) {
            seen[id] = features.length;
            features.push(copy);
          } else if (named(f.properties) > named(features[seen[id]].properties)) {
            features[seen[id]] = copy;
          }
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
    // Each layer of points of the tiles (`pois`, `pois_more`), together.
    var found = drawn
      ? spec.pois.sourceLayers.reduce(function (all, layer) {
          return all.concat(map.querySourceFeatures(spec.pois.source, {
            sourceLayer: layer,
            filter: poiUpdate.probe.filter
          }));
        }, [])
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
  // zooms in, the marker of a bare point brings its card back.
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
    if (hit.marker) {
      send({ type: 'marker' });
      return;
    }
    var p = hit.properties;
    var at = hit.coordinates || [e.lngLat.lng, e.lngLat.lat];
    var duration = reducedMotion ? 0 : 600;
    // A mark of the route map: the app says what it stands for
    // (assets/map/route_marks.js), where it was clicked.
    if (p.mark !== undefined) {
      send({ type: 'mark', id: p.mark, x: e.point.x, y: e.point.y });
      return;
    }
    // A rich mark of a place of the tiles opens it as its pin does.
    if (spec.richLayer && hit.layer === spec.richLayer) {
      send({ type: 'place', id: p.id, properties: p, coordinates: at });
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
        bearing: options.bearing || 0,
        pitch: options.pitch || 0,
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
