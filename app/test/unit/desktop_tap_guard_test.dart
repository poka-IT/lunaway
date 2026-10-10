import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The desktop page's judgement of a press (`lunawayTapGuard` in
/// `assets/map/lunaway_map.js`), the rule of `MapTapGuard` for the maps of
/// macOS and Windows, whose pointers the app's hit test may not see.
final _block = RegExp(r'  // BEGIN TAP GUARD\n[\s\S]*?  // END TAP GUARD\n');

/// Runs the block under node with a stand-in for MapLibre's map: its
/// `moveend`, whether it moves, and a container whose capture listeners a
/// press goes through.
const _script = r'''
const block = require('fs').readFileSync(0, 'utf8');
const guards = new Function(block + '\nreturn lunawayTapGuard;')();
let now = 10000;
let moving = false;
const handlers = {};
const listeners = {};
const map = {
  on(name, f) { (handlers[name] = handlers[name] || []).push(f); },
  isMoving() { return moving; },
  getContainer() {
    return {
      addEventListener(type, f, capture) {
        if (!capture) throw new Error('the press is judged before MapLibre stops the camera');
        (listeners[type] = listeners[type] || []).push(f);
      },
    };
  },
};
const guard = guards.create(map, () => 500, () => now);
const press = (type) => (listeners[type || 'mousedown'] || []).forEach((f) => f({}));
const rest = () => (handlers.moveend || []).forEach((f) => f({}));
const out = {};

press();
out.first = guard.meant();

// A fling: the camera still glides when the finger comes down.
moving = true;
press('touchstart');
out.stopsFling = guard.meant();
moving = false;
rest();

now += 300;
press();
out.soonAfterRest = guard.meant();

now += 300;
press();
out.afterQuiet = guard.meant();

// A flight the app asked for: its rest counts too.
rest();
now += 100;
press();
out.afterFlight = guard.meant();

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
  test(
    "the desktop page tells a meant tap from the press that stops a fling or follows the camera's "
    'rest by less than 500 ms',
    () async {
      final page = File('assets/map/lunaway_map.js').readAsStringSync();
      final block = _block.firstMatch(page)?.group(0);
      expect(block, isNotNull, reason: 'the block between its markers');
      final process = await Process.start('node', ['-e', _script]);
      process.stdin.write(block);
      await process.stdin.close();
      final output = await process.stdout.transform(utf8.decoder).join();
      final errors = await process.stderr.transform(utf8.decoder).join();
      expect(await process.exitCode, 0, reason: errors);
      expect(jsonDecode(output), {
        'first': true,
        'stopsFling': false,
        'soonAfterRest': false,
        'afterQuiet': true,
        'afterFlight': false,
      });
    },
    skip: _hasNode() ? false : 'needs node on the PATH (the CI has it)',
  );
}
