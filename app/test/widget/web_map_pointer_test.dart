import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/presentation/web_map_pointer.dart';

/// A map with a button over its top left corner and a modal sheet that can
/// open over it, as the route preview has.
class _MapUnderButton extends StatelessWidget {
  const new({required this.onChanged, this.onPress});

  final void Function({required bool on}) onChanged;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: WebMapPointer(
              onChanged: onChanged,
              onPress: onPress ?? () {},
              // The map's HTML element: nothing the app draws.
              child: const ColoredBox(key: Key('map'), color: Color(0xFF88AACC)),
            ),
          ),
          Positioned(
            left: 20,
            top: 20,
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => SizedBox(
                    height: 200,
                    child: Center(
                      child: FilledButton(onPressed: () {}, child: const Text('Accept')),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() => WebMapPointer.enabled = true);
  // A desktop window: the mouse is the point.
  Future<void> desktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  tearDown(() => WebMapPointer.enabled = kIsWeb);

  testWidgets(
    'the page lets the map draw its cursor only where the app sees the map under the mouse',
    (tester) async {
      await desktop(tester);
      final calls = <bool>[];
      await tester.pumpWidget(_MapUnderButton(onChanged: ({required on}) => calls.add(on)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('map'))));
      await tester.pump();
      expect(calls, [true], reason: 'over the bare map: the map draws its cursor');

      await mouse.moveTo(tester.getCenter(find.text('Open')));
      await tester.pump();
      expect(calls, [true, false], reason: 'over a button above the map: the app draws it');

      await mouse.moveTo(tester.getCenter(find.byKey(const Key('map'))));
      await tester.pump();
      expect(calls.last, isTrue);

      // A modal sheet over the map: its barrier and its buttons belong to
      // the app, wherever the map lies under them.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.text('Accept')));
      await tester.pump();
      expect(calls.last, isFalse);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(calls.last, isFalse, reason: "the sheet's barrier covers the map");
    },
  );

  testWidgets(
    'a press the app gives to the map claims its gesture; one on a button or a sheet over it does not',
    (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        _MapUnderButton(onChanged: ({required on}) {}, onPress: () => pressed.add('map')),
      );
      // A finger, as on a phone: no hover, only presses.
      await tester.tapAt(tester.getCenter(find.byKey(const Key('map'))));
      expect(pressed, ['map']);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(pressed, ['map'], reason: "the button over the map is the app's");
      await tester.tap(find.text('Accept'));
      await tester.tapAt(const Offset(5, 5));
      expect(pressed, ['map'], reason: "the sheet and its barrier are the app's");
    },
  );

  testWidgets('a map that goes away under the mouse tells the page', (tester) async {
    await desktop(tester);
    final calls = <bool>[];
    await tester.pumpWidget(_MapUnderButton(onChanged: ({required on}) => calls.add(on)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('map'))));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    expect(calls, [true, false]);
  });
}
