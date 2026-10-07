import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/presentation/map_gesture_watch.dart';

void main() {
  late int gestures;
  late List<bool> touches;

  Future<void> pumpWatch(WidgetTester tester) async {
    gestures = 0;
    touches = [];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MapGestureWatch(
          onGesture: () => gestures++,
          onTouch: touches.add,
          // A plain box stands for the platform view: it takes every
          // pointer, as the map does.
          child: const ColoredBox(color: Color(0xFFEEEEEE), child: SizedBox.expand()),
        ),
      ),
    );
  }

  testWidgets('a tap that stays put is no gesture: it opens what is under it', (tester) async {
    await pumpWatch(tester);
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(seconds: 1));
    expect(gestures, 0);
    expect(touches, [true, false]);
  });

  testWidgets('a finger that slides past the slop moves the map, told once', (tester) async {
    await pumpWatch(tester);
    final drag = await tester.startGesture(const Offset(200, 300));
    await drag.moveBy(const Offset(10, 0));
    expect(gestures, 0, reason: 'within the slop');
    await drag.moveBy(const Offset(30, 0));
    await drag.moveBy(const Offset(30, 0));
    expect(gestures, 1);
    await drag.up();
    expect(touches, [true, false]);
  });

  testWidgets('a second finger is a pinch, a turn or a tilt', (tester) async {
    await pumpWatch(tester);
    final a = await tester.startGesture(const Offset(150, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(250, 300), pointer: 2);
    expect(gestures, 1);
    await b.up();
    expect(touches, [true], reason: 'one finger still down');
    await a.up();
    expect(touches, [true, false]);
  });

  testWidgets('a quick second tap zooms; a slow one is another tap', (tester) async {
    await pumpWatch(tester);
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(const Offset(205, 302));
    expect(gestures, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(200, 300));
    expect(gestures, 1);
  });

  testWidgets('the mouse wheel zooms the map', (tester) async {
    await pumpWatch(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(200, 300)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
    expect(gestures, 2);
    expect(touches, isEmpty, reason: 'a wheel presses nothing');
  });

  testWidgets('a mouse drag moves the map after a few pixels', (tester) async {
    await pumpWatch(tester);
    final drag = await tester.startGesture(const Offset(200, 300), kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(6, 0));
    expect(gestures, 1);
    await drag.up();
  });
}
