import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/widgets/centred_clear.dart';

/// The rule of every element meant to be centred over the screen or the
/// map: centred on the whole of it, pushed aside only as far as a column of
/// buttons, a panel or a cut-out it would cover requires.
void main() {
  group('centredSpan', () {
    test('a span that fits stays centred, whatever the room around it', () {
      expect(centredSpan(centre: 180, width: 140, lo: 0, hi: 288), (left: 110.0, width: 140.0));
    });

    test('one that would cross a bound moves by the overlap, no more', () {
      // Centred it would end at 260: 20 past the column at 240.
      expect(centredSpan(centre: 180, width: 160, lo: 0, hi: 240), (left: 80.0, width: 160.0));
      expect(centredSpan(centre: 180, width: 160, lo: 120, hi: 360), (left: 120.0, width: 160.0));
    });

    test('one wider than the room fills it', () {
      expect(centredSpan(centre: 195, width: 420, lo: 16, hi: 322), (left: 16.0, width: 306.0));
    });

    test('no room: nothing wide, at the lower bound', () {
      expect(centredSpan(centre: 100, width: 50, lo: 80, hi: 60), (left: 80.0, width: 0.0));
    });
  });

  group('CentredClear', () {
    const child = ValueKey('child');

    Future<Rect> place(
      WidgetTester tester, {
      required Widget clear,
      Size screen = const Size(360, 640),
    }) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: clear));
      return tester.getRect(find.byKey(child));
    }

    testWidgets('a button that clears the column of buttons sits in the middle of the screen', (
      tester,
    ) async {
      final rect = await place(
        tester,
        clear: const CentredClear(
          obstacles: [SideRoom.right(72)],
          child: SizedBox(key: child, width: 140, height: 56),
        ),
      );
      expect(rect.center.dx, 180);
      expect(rect.center.dy, 320, reason: 'and in the middle of the height it was given');
    });

    testWidgets('one that would reach the column stops beside it', (tester) async {
      final rect = await place(
        tester,
        clear: const CentredClear(
          obstacles: [SideRoom.right(72)],
          child: SizedBox(key: child, width: 240, height: 56),
        ),
      );
      expect(rect.right, 360 - 72);
      expect(rect.width, 240);
    });

    testWidgets('one wider than the room left is narrowed to it, within the margin', (
      tester,
    ) async {
      final rect = await place(
        tester,
        clear: const CentredClear(
          margin: EdgeInsets.symmetric(horizontal: 16),
          obstacles: [SideRoom.right(72)],
          child: SizedBox(key: child, width: 420, height: 56),
        ),
      );
      expect(rect.left, 16);
      expect(rect.right, 288);
    });

    testWidgets('a cut-out on one side moves a wide card only by what it would cover', (
      tester,
    ) async {
      final rect = await place(
        tester,
        screen: const Size(844, 390),
        clear: const CentredClear(
          margin: EdgeInsets.all(12),
          obstacles: [SideRoom.left(47)],
          child: SizedBox(key: child, width: 560, height: 56),
        ),
      );
      expect(rect.center.dx, 422, reason: 'from 142 to 702: clear of the cut-out');
      final wide = await place(
        tester,
        screen: const Size(844, 390),
        clear: const CentredClear(
          margin: EdgeInsets.all(12),
          obstacles: [SideRoom.left(47)],
          child: SizedBox(key: child, width: 760, height: 56),
        ),
      );
      expect(wide.left, 47);
      expect(wide.width, 760);
    });

    testWidgets('a corner button counts only for a child that reaches down to it', (tester) async {
      // The room of a 60 px button at the bottom right of the area.
      const corner = [SideRoom.right(68, height: 60)];
      final above = await place(
        tester,
        clear: const CentredClear(
          margin: EdgeInsets.symmetric(horizontal: 16),
          obstacles: corner,
          child: SizedBox(key: child, width: 420, height: 400),
        ),
      );
      expect(above.left, 16, reason: 'from 120 to 520, above the button from 580');
      expect(above.right, 344);
      final reaching = await place(
        tester,
        clear: const CentredClear(
          margin: EdgeInsets.symmetric(horizontal: 16),
          obstacles: corner,
          child: SizedBox(key: child, width: 420, height: 560),
        ),
      );
      expect(reaching.left, 16, reason: 'from 40 to 600, down to the button');
      expect(reaching.right, 292);
    });

    testWidgets('with a height factor it is as tall as its child', (tester) async {
      await place(
        tester,
        clear: const Align(
          alignment: Alignment.bottomCenter,
          child: CentredClear(
            heightFactor: 1,
            obstacles: [SideRoom.left(40)],
            child: SizedBox(key: child, width: 280, height: 64),
          ),
        ),
      );
      final box = tester.getRect(find.byType(CentredClear));
      expect(box.height, 64);
      expect(box.width, 360);
      expect(tester.getRect(find.byKey(child)).center.dx, 180, reason: 'the cut-out ends at 40');
    });

    testWidgets('a tap beside the child goes through to what is under it', (tester) async {
      var under = 0;
      await place(
        tester,
        clear: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => under++),
            ),
            const Positioned.fill(
              child: CentredClear(child: SizedBox(key: child, width: 100, height: 56)),
            ),
          ],
        ),
      );
      await tester.tapAt(const Offset(20, 320));
      expect(under, 1);
    });
  });
}
