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
  // view. The same rules as VehicleMotion, easeZoom and easeCourse in
  // lib/features/navigation/presentation/vehicle_motion.dart, as FreeMap
  // in lib/features/navigation/domain/free_map.dart, and as the cadence of
  // lib/features/navigation/domain/frame_cadence.dart. This block is the
  // same in web/lunaway_maplibre.js and assets/map/route_motion.js
  // (test/unit/navigation/route_motion_js_test.dart).
  var lunawayRouteMotion = (function () {
    var MAX_GLIDE = 1500;
    // The cadence of GL JS's frames (FrameCadence): a pixel and a half of
    // motion a frame, ten frames a second at least. GL JS keeps drawing at
    // every frame of the screen while it places its labels, however seldom
    // the camera moves (measured: 56 frames a second for 10 moves), so the
    // page samples the glide at every frame of the screen, as before, and
    // lets GL JS draw one frame in k of them: the steps stay even. The full
    // cadence is the screen's (60 here); from it down to the lowest in a
    // second.
    var STEP_PX = 1.5;
    var MIN_FPS = 10;
    var MAX_FPS = 60;
    var RELEASE_S = 1;
    // A frame of the screen this close to the cadence's time draws: the
    // screen's frames do not fall exactly on it.
    var SLACK_MS = 4;
    // MapLibre's vertical field of view, degrees, and the far edge of a
    // tilted view taken no further than this from straight down.
    var FOV = 36.87;
    var FAR_DEG = 85;
    // The zoom and the tilt ease over this (easeZoom).
    var ZOOM_MS = 2000;
    // A fix this far from the drawn vehicle is a jump (a new route from
    // elsewhere), not a move to glide through, metres.
    var JUMP_M = 500;
    // The tilt of a follow without one (AutoTilt.cruise).
    var TILT = 52;
    // The map turns to the vehicle's course a moment after the arrow
    // (courseSettle and easeCourse in vehicle_motion.dart): a bend sweeps
    // rather than snaps.
    var COURSE_MS = 400;
    var COURSE_SETTLED = 0.3;
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

    // Metres a CSS pixel covers at a zoom and a latitude (metresPerPixel).
    function metresPerPixel(zoom, lat) {
      return 40075016.686 * Math.cos(lat * Math.PI / 180) / (512 * Math.pow(2, zoom));
    }

    // How fast the picture moves, pixels a second, where it moves fastest
    // (screenSpeed in frame_cadence.dart): a corner under the vehicle,
    // where the road slides by and a turn or a zoom moves it by its
    // distance, and a corner of the top, swept across the far ground by a
    // turn of the tilted map. m: { width, height, x, y (the vehicle), lat,
    // zoom, tilt, ground (m/s), turn (deg/s), zoomRate (levels/s),
    // tiltRate (deg/s), following }. The page does not know what covers
    // its map: the view is the whole canvas, a bound.
    function screenSpeed(m) {
      var slide = Math.abs(m.ground) / metresPerPixel(m.zoom, m.lat);
      if (!m.following) return slide;
      var rad = Math.PI / 180;
      var turn = Math.abs(m.turn) * rad;
      var scale = Math.abs(m.zoomRate) * Math.LN2;
      var pitchRate = Math.abs(m.tiltRate) * rad;
      var focal = m.height / 2 / Math.tan(FOV / 2 * rad);
      var side = Math.max(m.x, m.width - m.x);
      var above = Math.max(0, m.y);
      var below = Math.max(0, m.height - m.y);
      function tilting(dy) { return pitchRate * focal * (1 + (dy / focal) * (dy / focal)); }
      // Across and along the screen, each motion's part added up with the
      // same sign (a bound), the two then taken together.
      var under = Math.hypot(turn * below + scale * side, turn * side + scale * below + tilting(below) + slide);
      var pitch = Math.min(FAR_DEG, Math.max(0, m.tilt)) * rad;
      var up = Math.atan(above / focal);
      var far = Math.min(pitch + up, FAR_DEG * rad);
      var depthVehicle = 1 / Math.cos(pitch);
      var depthFar = Math.cos(up) / Math.cos(far);
      var sweep = focal * (Math.tan(far) - Math.tan(pitch)) / depthFar;
      var top = Math.hypot(turn * sweep + scale * side,
        turn * side + scale * above + tilting(above) + slide * depthVehicle / depthFar);
      return Math.max(under, top);
    }

    // Frames a second for a motion of px pixels a second (cadenceFor).
    function cadence(px) {
      if (isNaN(px)) return MAX_FPS;
      return Math.min(MAX_FPS, Math.max(MIN_FPS, px / STEP_PX));
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
      // While following: { zoom, tilt, padding }.
      var follow = null;
      var entry = null;
      var zoom = null;
      var pitch = null;
      // The course the camera has turned to; null until following draws.
      var bearing = null;
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
      // The cadence of GL JS's frames, when it was last set (up at once,
      // down to the lowest over RELEASE_S) and when GL JS last drew.
      var fps = MAX_FPS;
      var pacedAt = null;
      var drawnAt = null;
      // The glide's frames run: GL JS's own asks to draw wait for the
      // cadence's next frame, held here.
      var running = false;
      var held = false;
      var repaint = map.triggerRepaint.bind(map);
      // The map's own fade of its labels, given back once it no longer guides.
      var fades = map._fadeDuration;
      map.triggerRepaint = function () {
        if (!running || fps >= MAX_FPS) return repaint();
        held = true;
      };

      function release() {
        if (!held) return;
        held = false;
        repaint();
      }

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

      // A finger or the button on the map, the way into following, the
      // camera moved by the user or by an animation while it does not
      // follow: the full cadence.
      function fullCadence() {
        return pressedCount > 0 || entry !== null || (follow === null && map.isMoving());
      }

      // The cadence the picture's motion wants now, from the glide and the
      // eases of the camera toward its aim.
      function wanted(shown) {
        if (fullCadence()) return MAX_FPS;
        var canvas = map.getCanvas();
        var w = canvas.clientWidth;
        var h = canvas.clientHeight;
        if (!w || !h) return MAX_FPS;
        var gliding = shown.moving && length > 0;
        var ground = gliding ? metres(from, to) / (length / 1000) : 0;
        if (!follow) {
          return cadence(screenSpeed({ ground: ground, zoom: map.getZoom(), lat: shown.lat, following: false }));
        }
        var z = zoom === null ? follow.zoom : zoom;
        var p = pitch === null ? follow.tilt : pitch;
        var pad = follow.padding;
        var turn = 0;
        if (shown.course !== null && bearing !== null) {
          turn += Math.abs(delta(bearing, shown.course)) / (COURSE_MS / 1000);
        }
        if (gliding && from.course !== null && to.course !== null) {
          turn = Math.max(turn, Math.abs(delta(from.course, to.course)) / (length / 1000));
        }
        return cadence(screenSpeed({
          width: w,
          height: h,
          x: pad.left + Math.max(0, w - pad.left - pad.right) / 2,
          y: pad.top + Math.max(0, h - pad.top - pad.bottom) / 2,
          lat: shown.lat,
          zoom: z,
          tilt: p,
          ground: ground,
          turn: turn,
          zoomRate: Math.abs(follow.zoom - z) / (ZOOM_MS / 1000),
          tiltRate: Math.abs(follow.tilt - p) / (ZOOM_MS / 1000),
          following: true
        }));
      }

      function pace(t, want) {
        if (pacedAt === null || want >= fps) {
          fps = want;
        } else {
          fps = Math.max(want, fps - (MAX_FPS - MIN_FPS) / RELEASE_S * (t - pacedAt) / 1000);
        }
        pacedAt = t;
      }

      function step(t) {
        frame = null;
        try {
          stepAt(t);
        } catch (error) {
          // A frame that throws stops the glide: GL JS's own draws are not
          // held behind it.
          running = false;
          release();
          throw error;
        }
      }

      function stepAt(t) {
        var shown = at(t);
        if (!shown) {
          running = false;
          release();
          return;
        }
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
          pitch = pitch === null ? follow.tilt : pitch + (follow.tilt - pitch) * Math.min(1, dt / 2000);
          if (Math.abs(follow.tilt - pitch) > 0.3) settled = false;
          if (shown.course !== null) {
            bearing = bearing === null
              ? shown.course
              : (((bearing + delta(bearing, shown.course) * Math.min(1, dt / COURSE_MS)) % 360) + 360) % 360;
            if (Math.abs(delta(bearing, shown.course)) > COURSE_SETTLED) settled = false;
          }
          var camera = {
            center: [shown.lon, shown.lat],
            zoom: zoom,
            bearing: bearing === null ? map.getBearing() : bearing,
            pitch: pitch,
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
              camera.bearing = (((f.bearing + delta(f.bearing, camera.bearing) * e) % 360) + 360) % 360;
              camera.pitch = lerp(f.pitch, pitch, e);
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
        // GL JS draws this sample, or waits for a later one: what a frame
        // shows is set by the clock, so fewer frames show the same path.
        // Asked here, GL JS draws at the next frame of the screen, before
        // the next sample.
        pace(t, wanted(shown));
        if (fps >= MAX_FPS || drawnAt === null || t - drawnAt >= 1000 / fps - SLACK_MS) {
          drawnAt = t;
          release();
        }
        if (settled) {
          running = false;
          release();
        } else {
          frame = frameFn(step);
        }
      }

      function kick() {
        running = true;
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
        pitch = null;
        bearing = null;
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
          running = false;
          release();
          from = null;
          to = null;
          lastTarget = null;
          return true;
        },
        // Following: { zoom, tilt, padding, ease (ms, the way in), enter }. From
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
          follow = { zoom: next.zoom, tilt: next.tilt === undefined ? TILT : next.tilt, padding: pad };
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
        // the preview's does not. It also places its labels without fading
        // them: while labels fade, GL JS draws at every frame of the
        // screen whatever the cadence (measured: 56 frames a second for 10
        // moves of the camera). GL JS reads its fade at each placement
        // from this field, which has no setter (GL JS 6.4.1 in
        // web/maplibre-gl, 5.24.0 in assets/map; route_motion_js_test.dart
        // checks both still read it).
        guiding: function (on) {
          guiding = !!on;
          if (typeof fades === 'number') map._fadeDuration = guiding ? 0 : fades;
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
