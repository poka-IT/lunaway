// The guidance on the desktop map (macOS, Windows): the vehicle glides from
// fix to fix and, while following, the camera rides with it; the user takes
// the map with any gesture and the app hears of it. The rules are in the
// ROUTE MOTION block below, the same in the browser's page
// (web/lunaway_maplibre.js), here because a frame by frame call from the
// app through the web view would lag.
(function () {
  'use strict';

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
      container.addEventListener('pointerdown', onPointerDown);
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

  function send(event) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('lunaway', event);
    }
  }

  var motion = null;

  // The page's map is made by window.lunaway.init: the motion with it.
  function current() {
    var m = window.lunaway && window.lunaway.map();
    if (!m) return null;
    if (!motion || motion.map !== m) {
      motion = { map: m, run: lunawayRouteMotion.create(m, send, { longPress: false }) };
    }
    return motion.run;
  }

  window.lunawayRoute = {
    vehicle: function (sourceId, lat, lon, course, jump) {
      var run = current();
      return run ? run.vehicle(sourceId, lat, lon, course, jump) : false;
    },
    clear: function (sourceId) {
      var run = current();
      if (run) run.clear();
      window.lunaway.setData(sourceId, { type: 'FeatureCollection', features: [] });
      return true;
    },
    follow: function (options) {
      var run = current();
      return run ? run.follow(options) : false;
    },
    free: function () {
      var run = current();
      return run ? run.free() : false;
    },
    overview: function () {
      var run = current();
      return run ? run.overview() : false;
    },
    guiding: function (on) {
      var run = current();
      var m = window.lunaway.map();
      if (m) {
        // The guidance's map turns and tilts under the mouse and the
        // fingers; the preview's stays north up.
        if (on) {
          m.dragRotate.enable();
          m.touchZoomRotate.enableRotation();
          m.touchPitch.enable();
        } else {
          m.dragRotate.disable();
          m.touchZoomRotate.disableRotation();
          m.touchPitch.disable();
        }
      }
      return run ? run.guiding(on) : false;
    },
    watch: function (on) {
      var run = current();
      return run ? run.watch(on) : false;
    }
  };
})();
