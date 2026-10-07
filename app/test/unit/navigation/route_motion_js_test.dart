import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The pages that carry the guidance's motion: the browser's and the
/// desktop's.
const _pages = ['web/lunaway_maplibre.js', 'assets/map/route_motion.js'];

final _block = RegExp(r'  // BEGIN ROUTE MOTION\n[\s\S]*?  // END ROUTE MOTION\n');

/// Runs the block under node with a stand-in for MapLibre's map, the clock
/// and the frames in the test's hands; each scenario returns what it saw.
const _script = r'''
const block = require('fs').readFileSync(0, 'utf8');
const listeners = {};
globalThis.window = {
  addEventListener(name, f) { (listeners[name] = listeners[name] || []).push(f); },
  removeEventListener() {},
};
const motion = new Function(block + '\nreturn lunawayRouteMotion;')();

function fakeMap() {
  const on = {};
  const box = {};
  const map = {
    jumps: [],
    camera: { lat: 45, lon: 1, zoom: 12, bearing: 0, pitch: 0, padding: { top: 0, bottom: 0, left: 0, right: 0 } },
    moving: false,
    data: null,
    on(name, f) { (on[name] = on[name] || []).push(f); },
    fire(name, e) { (on[name] || []).forEach((f) => f(e || {})); },
    getSource() { return { setData(d) { map.data = d; } }; },
    jumpTo(c, own) {
      map.jumps.push({ c, own });
      if (c.center) { map.camera.lon = c.center[0]; map.camera.lat = c.center[1]; }
      for (const k of ['zoom', 'bearing', 'pitch', 'padding']) if (c[k] !== undefined) map.camera[k] = c[k];
    },
    getCenter() { return { lat: map.camera.lat, lng: map.camera.lon }; },
    getZoom() { return map.camera.zoom; },
    getBearing() { return map.camera.bearing; },
    getPitch() { return map.camera.pitch; },
    getPadding() { return map.camera.padding; },
    isMoving() { return map.moving; },
    project(p) { return { x: (p[0] - 1) * 1000 + 200, y: (45 - p[1]) * 1000 + 500 }; },
    unproject(p) { return { lng: 1, lat: 45 }; },
    getCanvas() { return { clientWidth: 400, clientHeight: 800 }; },
    getCanvasContainer() {
      return {
        addEventListener(name, f) { box[name] = f; },
        getBoundingClientRect() { return { left: 0, top: 0 }; },
      };
    },
    press(id, type) { box.pointerdown({ pointerId: id, pointerType: type || 'touch', clientX: 10, clientY: 10 }); },
    lift(id) { (listeners.pointerup || []).forEach((f) => f({ pointerId: id })); },
  };
  return map;
}

function rig(options) {
  const map = fakeMap();
  const events = [];
  let t = 0;
  let pending = null;
  const run = motion.create(map, (e) => events.push(e), {
    now: () => t,
    frame: (f) => { pending = f; return 1; },
    cancel: () => { pending = null; },
    longPress: options && options.longPress,
  });
  const frames = (n, step) => {
    for (let i = 0; i < n; i++) {
      t += step || 16;
      const f = pending;
      pending = null;
      if (f) f(t);
    }
  };
  return { map, run, events, frames, clock: () => t };
}

const out = {};

// Following: the camera rides with the vehicle, tilted and turned to the
// course, its own moves flagged.
{
  const r = rig();
  r.run.guiding(true);
  r.run.vehicle('v', 45, 1, 90, true);
  r.run.follow({ zoom: 17, padding: { top: 400 }, ease: 0 });
  r.frames(3);
  const last = r.map.jumps[r.map.jumps.length - 1];
  out.follows = { pitch: last.c.pitch, bearing: last.c.bearing, zoom: last.c.zoom, own: last.own.lunawayMotion === true, padding: last.c.padding.top };
}

// The way in eases from the view the map had.
{
  const r = rig();
  r.run.vehicle('v', 45, 1, 90, true);
  r.run.follow({ zoom: 17, padding: {}, ease: 450 });
  r.frames(1, 100);
  const early = r.map.jumps[r.map.jumps.length - 1].c;
  r.frames(10, 100);
  const late = r.map.jumps[r.map.jumps.length - 1].c;
  out.entry = { earlyZoom: early.zoom, earlyPitch: early.pitch, lateZoom: late.zoom, latePitch: late.pitch };
}

// A user's gesture stops following at once and is told once; the app's own
// moves are no gesture.
{
  const r = rig();
  r.run.guiding(true);
  r.run.vehicle('v', 45, 1, 90, true);
  r.run.follow({ zoom: 17, padding: {}, ease: 0 });
  r.frames(2);
  r.map.fire('movestart', { lunawayMotion: true });
  r.map.fire('movestart', {});
  const before = r.events.filter((e) => e.type === 'gesture').length;
  r.map.press(1);
  r.map.fire('movestart', { originalEvent: {} });
  r.map.fire('dragstart', { originalEvent: {} });
  const jumps = r.map.jumps.length;
  r.run.vehicle('v', 45.001, 1, 90, false);
  r.frames(5);
  out.gesture = {
    before,
    gestures: r.events.filter((e) => e.type === 'gesture').length,
    jumpsAfter: r.map.jumps.length - jumps,
    following: r.run.following(),
    touch: r.events.filter((e) => e.type === 'touch').map((e) => e.down),
  };
  // The camera rests while the finger is still down: nothing yet; then the
  // finger lifts.
  r.map.fire('moveend', {});
  const restsHeld = r.events.filter((e) => e.type === 'rest').length;
  r.map.lift(1);
  const rest = r.events.filter((e) => e.type === 'rest');
  out.rest = { held: restsHeld, count: rest.length, last: rest[rest.length - 1] };
  // A second rest without a new gesture says nothing.
  r.map.fire('moveend', {});
  out.rest.again = r.events.filter((e) => e.type === 'rest').length;
}

// A finger down holds the camera (MapLibre drops a gesture it has begun when
// the camera moves under it); a tap that lifts lets it follow on.
{
  const r = rig();
  r.run.guiding(true);
  r.run.vehicle('v', 45, 1, 90, true);
  r.run.follow({ zoom: 17, padding: {}, ease: 0 });
  r.frames(2);
  r.map.press(1);
  const held = r.map.jumps.length;
  r.run.vehicle('v', 45.0005, 1, 90, false);
  r.frames(5);
  const whileHeld = r.map.jumps.length - held;
  r.map.lift(1);
  r.frames(3);
  out.pressed = { whileHeld, after: r.map.jumps.length - held - whileHeld, following: r.run.following(), gestures: r.events.filter((e) => e.type === 'gesture').length };
}

// The preview's map is not guiding: no gesture, no press told.
{
  const r = rig();
  r.map.press(1);
  r.map.fire('movestart', { originalEvent: {} });
  r.map.lift(1);
  r.map.fire('moveend', {});
  out.preview = r.events.length;
}

// Back into following from where the user left it, then the whole route:
// flat, north up, no insets.
{
  const r = rig();
  r.run.guiding(true);
  r.run.vehicle('v', 45, 1, 90, true);
  r.run.follow({ zoom: 17, padding: { top: 300 }, ease: 0 });
  r.frames(2);
  r.map.fire('movestart', { originalEvent: {} });
  r.run.free();
  r.run.follow({ zoom: 17, padding: { top: 300 }, ease: 450 });
  r.frames(40);
  out.refollow = { following: r.run.following(), pitch: r.map.camera.pitch };
  r.run.overview();
  const flat = r.map.jumps[r.map.jumps.length - 1].c;
  out.overview = { pitch: flat.pitch, bearing: flat.bearing, top: flat.padding.top, following: r.run.following() };
}

// A finger held still is a long press, on the browser's map only.
{
  const r = rig({ longPress: true });
  r.map.press(1);
  setTimeout(() => {
    out.longPress = r.events.filter((e) => e.type === 'longpress').length;
    const s = rig();
    s.map.press(2);
    setTimeout(() => {
      out.noLongPress = s.events.filter((e) => e.type === 'longpress').length;
      process.stdout.write(JSON.stringify(out));
    }, 700);
  }, 700);
}
''';

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test('the browser and the desktop run the same block', () {
    final blocks = [
      for (final page in _pages) _block.firstMatch(File(page).readAsStringSync())?.group(0),
    ];
    expect(blocks.first, isNotNull, reason: '${_pages.first} lost its ROUTE MOTION markers');
    expect(blocks.last, blocks.first, reason: '${_pages.last} differs from ${_pages.first}');
  });

  group('the page', () {
    late Map<String, Object?> seen;
    final node = _hasNode();

    setUpAll(() async {
      if (!node) return;
      final block = _block.firstMatch(File(_pages.first).readAsStringSync())!.group(0)!;
      final process = await Process.start('node', ['-e', _script]);
      process.stdin.write(block);
      await process.stdin.close();
      final output = await process.stdout.transform(utf8.decoder).join();
      final errors = await process.stderr.transform(utf8.decoder).join();
      expect(await process.exitCode, 0, reason: errors);
      seen = jsonDecode(output) as Map<String, Object?>;
    });

    final skip = node ? false : 'needs node on the PATH (the CI has it)';

    test('follows the vehicle tilted and turned to its course, its own moves flagged', () {
      expect(seen['follows'], {
        'pitch': 55,
        'bearing': 90,
        'zoom': 17,
        'own': true,
        'padding': 400,
      });
    }, skip: skip);

    test('eases into following from the view the map had', () {
      final entry = seen['entry']! as Map<String, Object?>;
      expect(entry['earlyZoom']! as num, inExclusiveRange(12, 17));
      expect(entry['earlyPitch']! as num, inExclusiveRange(0, 55));
      expect(entry['lateZoom'], 17);
      expect(entry['latePitch'], 55);
    }, skip: skip);

    test("stops following at the user's first gesture, told once, never for its own moves", () {
      expect(seen['gesture'], {
        'before': 0,
        'gestures': 1,
        'jumpsAfter': 0,
        'following': false,
        'touch': [true],
      });
    }, skip: skip);

    test('tells where the vehicle is once the camera rests and the finger lifts', () {
      final rest = seen['rest']! as Map<String, Object?>;
      expect(rest['held'], 0, reason: 'nothing while the finger is down');
      expect(rest['count'], 1);
      expect(rest['again'], 1, reason: 'one rest per gesture');
      final last = rest['last']! as Map<String, Object?>;
      expect(last['x'], closeTo(200, 1e-6));
      expect(last['y'], closeTo(499, 1e-6));
      expect(last['width'], 400);
      expect(last['pitch'], 55);
    }, skip: skip);

    test('a finger down holds the camera; a tap that lifts is no gesture', () {
      final pressed = seen['pressed']! as Map<String, Object?>;
      expect(pressed['whileHeld'], 0);
      expect(pressed['after']! as num, greaterThan(0), reason: 'the camera catches up');
      expect(pressed['following'], isTrue);
      expect(pressed['gestures'], 0);
    }, skip: skip);

    test("the preview's map tells nothing of gestures", () {
      expect(seen['preview'], 0);
    }, skip: skip);

    test('follows again from where the user left it; the whole route is flat', () {
      expect(seen['refollow'], {'following': true, 'pitch': 55});
      expect(seen['overview'], {'pitch': 0, 'bearing': 0, 'top': 0, 'following': false});
    }, skip: skip);

    test("a finger held still is a long press on the browser's map", () {
      expect(seen['longPress'], 1);
      expect(seen['noLongPress'], 0);
    }, skip: skip);
  });
}
