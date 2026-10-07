import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/premap_spec.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

/// What `web/premap.js` (modelFrame) computes for a window of [size], from
/// the constants of [premapDefaults]: where the app's map stands and the
/// room its first fit leaves inside it. The page frames France there
/// before the app has measured anything. [mouse] for a desktop system,
/// [safe] the window's safe areas.
({Rect map, EdgeInsets fit}) _pageModel(
  Size size, {
  bool mouse = false,
  EdgeInsets safe = EdgeInsets.zero,
}) {
  final m = premapDefaults()['frame']! as Map<String, Object?>;
  double n(String key, [int? at]) =>
      ((at == null ? m[key] : (m[key]! as List)[at]) as num).toDouble();
  final dense = mouse && size.width >= n('mediumFrom') ? 1 : 0;
  final fit = n('fit');
  var left = 0.0;
  var top = fit;
  var bottom = fit;
  if (size.width < n('mediumFrom')) {
    top += safe.top + n('overlay', 0);
    bottom += n('listPeek') + n('dock') + safe.bottom;
  } else if (size.width < n('expandedFrom')) {
    left = n('railFolded', dense) + safe.left;
    top += safe.top + n('overlay', dense);
  } else {
    left =
        n('railExtended', dense) + safe.left + n('pane', size.width >= n('paneWideFrom') ? 1 : 0);
  }
  return (
    map: Rect.fromLTRB(left, 0, size.width, size.height),
    fit: EdgeInsets.fromLTRB(fit, top, fit, bottom),
  );
}

Future<void> _expectFrame(
  WidgetTester tester,
  Size size, {
  bool mouse = false,
  EdgeInsets safe = EdgeInsets.zero,
}) async {
  final map = FakeMap();
  await pumpLunaway(
    tester,
    size: size,
    map: map,
    viewPadding: safe == EdgeInsets.zero
        ? null
        : FakeViewPadding(left: safe.left, top: safe.top, right: safe.right, bottom: safe.bottom),
  );
  final model = _pageModel(size, mouse: mouse, safe: safe);
  expect(tester.getRect(find.byKey(const ValueKey('fake-map'))), model.map);
  expect(
    map.lastProps!.padding + const EdgeInsets.all(fitInitialMargin),
    model.fit,
    reason: "the room of the app's first fit",
  );
}

void main() {
  for (final size in const [Size(400, 800), Size(700, 900), Size(1100, 800), Size(1440, 900)]) {
    testWidgets('the page frames its first map where the app puts its map, at $size', (
      tester,
    ) async {
      await _expectFrame(tester, size);
    });
  }

  for (final size in const [Size(700, 900), Size(1440, 900)]) {
    testWidgets('with a mouse, the denser rail and search, at $size', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _expectFrame(tester, size, mouse: true);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets("a phone's notch and home bar move the room of the fit", (tester) async {
    await _expectFrame(
      tester,
      const Size(400, 800),
      safe: const EdgeInsets.only(top: 30, bottom: 20),
    );
  });

  testWidgets('a tablet on its side grows the rail by its cut-out', (tester) async {
    await _expectFrame(
      tester,
      const Size(700, 900),
      safe: const EdgeInsets.only(left: 24, top: 20),
    );
  });
}
