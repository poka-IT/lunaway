import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/widgets/touch_target.dart';

void main() {
  Future<int Function()> pumpTarget(WidgetTester tester, {required Size child, Size? gap}) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: TouchTarget(
            key: const ValueKey('target'),
            minSize: const Size(48, 48),
            gap: gap ?? Size.zero,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: SizedBox.fromSize(key: const ValueKey('drawn'), size: child),
            ),
          ),
        ),
      ),
    );
    return () => taps;
  }

  testWidgets('a control drawn smaller than a finger answers over 48 by 48, centred', (
    tester,
  ) async {
    final taps = await pumpTarget(tester, child: const Size(30, 30));
    final box = tester.getRect(find.byKey(const ValueKey('target')));
    final drawn = tester.getRect(find.byKey(const ValueKey('drawn')));
    expect(box.size, const Size(48, 48));
    expect(drawn.center, box.center);
    await tester.tapAt(box.topLeft + const Offset(1, 1));
    expect(taps(), 1, reason: "a touch in the corner of the box is the control's");
    await tester.tapAt(box.bottomRight + const Offset(2, 2));
    expect(taps(), 1, reason: 'outside the box, nothing');
  });

  testWidgets('the gap is kept around a larger control, inside its box', (tester) async {
    final taps = await pumpTarget(tester, child: const Size(120, 44), gap: const Size(0, 8));
    final box = tester.getRect(find.byKey(const ValueKey('target')));
    final drawn = tester.getRect(find.byKey(const ValueKey('drawn')));
    expect(box.size, const Size(120, 52));
    expect(drawn.top - box.top, 4);
    await tester.tapAt(Offset(drawn.center.dx, box.top + 1));
    expect(taps(), 1);
  });
}
