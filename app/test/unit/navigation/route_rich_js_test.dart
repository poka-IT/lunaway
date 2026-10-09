import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs `assets/map/route_rich.js`, the desktop page's side of the rich
/// marks, under node with a stand-in for MapLibre's map and the page's
/// images; returns what the page answered and did.
const _script = '''
const source = require('fs').readFileSync(0, 'utf8');
const calls = [];
const images = { 'lw-rich-0': 'old' };
const map = {
  getLayer(id) { return id === 'probe' ? {} : undefined; },
  queryRenderedFeatures(options) {
    calls.push(['query', options.layers]);
    return [{ properties: { id: 'a', kind: 'parking' }, geometry: { coordinates: [4.5, 45.2] } }];
  },
  project(p) { return { x: (p[0] - 4) * 1000, y: (46 - p[1]) * 1000 }; },
  getCenter() { return { lng: 4.2, lat: 45.5 }; },
  getZoom() { return 15.5; },
  getPitch() { return 55; },
  hasImage(id) { return id in images; },
  removeImage(id) { calls.push(['remove', id]); delete images[id]; },
  addImage(id, img, options) { calls.push(['add', id, options.pixelRatio]); images[id] = img.src; },
};
globalThis.window = { lunaway: { map: () => map } };
globalThis.Image = class {
  set src(v) { this._src = v; setTimeout(() => (v.includes('broken') ? this.onerror() : this.onload())); }
  get src() { return this._src; }
};
new Function(source)();
const rich = window.lunawayRich;
(async () => {
  const out = {
    places: rich.places('probe'),
    none: rich.places('gone'),
    view: rich.view([[4.1, 45.9], [4.3, 45.7]]),
    put: await rich.image('lw-rich-0', 'AAAA', 2.625),
    broken: await rich.image('lw-rich-1', 'broken', 2),
  };
  out.calls = calls;
  out.slot = images['lw-rich-0'];
  process.stdout.write(JSON.stringify(out));
})();
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

  setUpAll(() async {
    if (!node) return;
    final process = await Process.start('node', ['-e', _script]);
    process.stdin.write(File('assets/map/route_rich.js').readAsStringSync());
    await process.stdin.close();
    final output = await process.stdout.transform(utf8.decoder).join();
    final errors = await process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode, 0, reason: errors);
    seen = jsonDecode(output) as Map<String, Object?>;
  });

  final skip = node ? false : 'needs node on the PATH (the CI has it)';

  test('the places of the probe in view, with their properties and point', () {
    expect(seen['places'], [
      {
        'p': {'id': 'a', 'kind': 'parking'},
        'c': [4.5, 45.2],
      },
    ]);
    expect(seen['none'], isEmpty, reason: 'a style without the probe answers nothing');
  }, skip: skip);

  test('points placed on the screen, with the zoom, the tilt and the centre', () {
    final view = seen['view']! as Map<String, Object?>;
    expect(view['zoom'], 15.5);
    expect(view['pitch'], 55);
    final points = view['points']! as List<Object?>;
    expect((points.first! as List<Object?>).map((v) => (v! as num).round()), [100, 100]);
    expect((view['centre']! as List<Object?>).map((v) => (v! as num).round()), [200, 500]);
  }, skip: skip);

  test('a slot filled again replaces its image, at the screen density', () {
    expect(seen['put'], isTrue);
    expect(
      seen['calls'],
      containsAllInOrder([
        ['remove', 'lw-rich-0'],
        ['add', 'lw-rich-0', 2.625],
      ]),
    );
    expect(seen['slot'], 'data:image/png;base64,AAAA');
    expect(seen['broken'], isFalse, reason: 'an image that does not decode adds nothing');
  }, skip: skip);
}
