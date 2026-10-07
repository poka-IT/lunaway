import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/premap_spec.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';

/// What `web/premap.js` (modelFrame) computes for a window of [size] with
/// a finger and no safe area, from the constants of [premapDefaults]: where
/// the app's map stands and the room its first fit leaves inside it. The
/// page frames France there before the app has measured anything.
({Rect map, EdgeInsets fit}) _pageModel(Size size) {
  final m = premapDefaults()['frame']! as Map<String, Object?>;
  double n(String key, [int? at]) =>
      ((at == null ? m[key] : (m[key]! as List)[at]) as num).toDouble();
  final fit = n('fit');
  var left = 0.0;
  var top = fit;
  var bottom = fit;
  if (size.width < n('mediumFrom')) {
    top += n('overlay', 0);
    bottom += n('listPeek') + n('dock');
  } else if (size.width < n('expandedFrom')) {
    left = n('railFolded', 0);
    top += n('overlay', 0);
  } else {
    left = n('railExtended', 0) + n('pane', size.width >= n('paneWideFrom') ? 1 : 0);
  }
  return (
    map: Rect.fromLTRB(left, 0, size.width, size.height),
    fit: EdgeInsets.fromLTRB(fit, top, fit, bottom),
  );
}

void main() {
  for (final size in const [Size(400, 800), Size(700, 900), Size(1100, 800), Size(1440, 900)]) {
    testWidgets('the page frames its first map where the app puts its map, at $size', (
      tester,
    ) async {
      final map = FakeMap();
      await pumpLunaway(tester, size: size, map: map);
      final model = _pageModel(size);
      expect(tester.getRect(find.byKey(const ValueKey('fake-map'))), model.map);
      expect(
        map.lastProps!.padding + const EdgeInsets.all(fitInitialMargin),
        model.fit,
        reason: "the room of the app's first fit",
      );
    });
  }
}
