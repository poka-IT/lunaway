import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/presentation/web_map_pointer.dart';

/// A map with a button over its top left corner and a modal sheet that can
/// open over it, as the route preview has.
class _MapUnderButton extends StatelessWidget {
  const new({required this.onChanged});

  final void Function({required bool on}) onChanged;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: WebMapPointer(
              onChanged: onChanged,
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
  tearDown(() => WebMapPointer.enabled = kIsWeb);

  testWidgets(
    'the page lets the map draw its cursor only where the app sees the map under the mouse',
    (tester) async {
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

  testWidgets('a map that goes away under the mouse tells the page', (tester) async {
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
