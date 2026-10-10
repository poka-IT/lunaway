import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The page's gate of the maps' gestures (`lunawayGestures`).
final _block = RegExp(r'  // BEGIN GESTURES\n[\s\S]*?  // END GESTURES\n');

/// Runs the block under node with a window and a document that dispatch an
/// event through their capture listeners, as a browser does before the
/// event reaches its target, and tells what reached the map.
const _script = r'''
const block = require('fs').readFileSync(0, 'utf8');
const gestures = new Function(block + '\nreturn lunawayGestures;')();

function target(name, inAppMap) {
  return {
    name,
    closest(selector) {
      return selector === 'flt-platform-view .maplibregl-map' && inAppMap ? {} : null;
    },
  };
}
const MAP = target('canvas of the map', true);
const LIST = target('list over the map', false);
const PREMAP = target("the page's first map", false);

function eventTarget() {
  const listeners = {};
  return {
    listeners,
    addEventListener(type, f, capture) {
      if (!capture) throw new Error('the gate listens before anything else');
      (listeners[type] = listeners[type] || []).push(f);
    },
  };
}
const win = eventTarget();
const doc = eventTarget();
gestures.install(win, doc);

// An event through the capture listeners: whether it went on to its target,
// and whether its default was kept.
function fire(type, on, extra) {
  const e = Object.assign({ type, target: on, stopped: false, prevented: false,
    stopPropagation() { this.stopped = true; },
    preventDefault() { this.prevented = true; } }, extra || {});
  for (const f of win.listeners[type] || []) f(e);
  for (const f of doc.listeners[type] || []) { if (!e.stopped) f(e); }
  return { reached: !e.stopped, prevented: e.prevented };
}
const reached = (types, on) => types.filter((t) => fire(t, on).reached);
const TAP = ['touchstart', 'touchend', 'mousedown', 'mouseup', 'click'];
const out = {};

// A search result tapped: the app takes the press (no claim), the list
// goes, and the browser's late mouse events land on the map uncovered.
fire('pointerdown', LIST, { isPrimary: true });
out.listTouch = reached(['touchstart', 'touchend'], LIST);
out.lateClick = reached(['mousedown', 'mouseup', 'click'], MAP);
out.lateFocus = fire('mousedown', MAP).prevented;

// A tap on the map itself: the app's hit test claims it.
fire('pointerdown', MAP, { isPrimary: true });
gestures.claim();
out.mapTap = reached(TAP, MAP);

// A button the app draws over the map, with nothing between it and the
// map's element: the touch lands on the map's element all the same.
fire('pointerdown', MAP, { isPrimary: true });
out.overlayTap = reached(TAP, MAP);

// A pinch begun on the map: the second finger joins its gesture, even on
// something drawn over the map.
fire('pointerdown', MAP, { isPrimary: true });
gestures.claim();
fire('pointerdown', LIST, { isPrimary: false });
out.pinch = reached(['touchmove', 'touchend'], MAP);
out.owns = gestures.owns();

// The page's first map, before the app runs, keeps its gestures.
fire('pointerdown', PREMAP, { isPrimary: true });
out.premap = reached(TAP, PREMAP);

// What is not a gesture passes: no listener for it.
out.untouched = ['wheel', 'mousemove', 'pointermove', 'pointerdown'].filter((t) => (doc.listeners[t] || []).length > 0);
process.stdout.write(JSON.stringify(out));
''';

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  late Map<String, Object?> seen;
  final node = _hasNode();
  final skip = node ? false : 'needs node on the PATH (the CI has it)';

  setUpAll(() async {
    if (!node) return;
    final block = _block.firstMatch(File('web/lunaway_maplibre.js').readAsStringSync())?.group(0);
    expect(block, isNotNull, reason: 'web/lunaway_maplibre.js lost its GESTURES markers');
    final process = await Process.start('node', ['-e', _script]);
    process.stdin.write(block);
    await process.stdin.close();
    final output = await process.stdout.transform(utf8.decoder).join();
    final errors = await process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0, reason: errors);
    seen = jsonDecode(output) as Map<String, Object?>;
  });

  test("a tap the app took never reaches the map, nor do its browser's late clicks", () {
    expect(seen['listTouch'], ['touchstart', 'touchend'], reason: 'off the map: untouched');
    expect(seen['lateClick'], isEmpty, reason: 'the click that once cut the flight to a result');
    expect(seen['lateFocus'], isTrue, reason: "nor does the map's canvas take the focus");
  }, skip: skip);

  test('a tap the app gives to the map reaches it whole', () {
    expect(seen['mapTap'], ['touchstart', 'touchend', 'mousedown', 'mouseup', 'click']);
  }, skip: skip);

  test("a press on something drawn over the map, on the map's element, does not reach it", () {
    expect(seen['overlayTap'], isEmpty);
  }, skip: skip);

  test('a second finger joins the gesture the map was given', () {
    expect(seen['pinch'], ['touchmove', 'touchend']);
    expect(seen['owns'], isTrue);
  }, skip: skip);

  test("the page's first map keeps its gestures, and what is no gesture passes", () {
    expect(seen['premap'], ['touchstart', 'touchend', 'mousedown', 'mouseup', 'click']);
    expect(seen['untouched'], isEmpty);
  }, skip: skip);
}
