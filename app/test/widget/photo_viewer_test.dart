import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The app at [size] with the lake area's card open and its three photos in
/// the viewer, on the first one.
Future<void> _openViewer(WidgetTester tester, {Size size = desktop}) async {
  final app = await pumpLunaway(tester, size: size);
  app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
  await settleShort(tester);
  unawaited(
    showPhotoViewer(
      tester.element(find.byType(PlaceDetailsBody)),
      samplePhotos,
      0,
      fetcher: app.container(tester).read(imageFetcherProvider),
    ),
  );
  await settleShort(tester);
}

Finder _counter(String text) =>
    find.descendant(of: find.byType(PhotoViewer), matching: find.text(text));

void main() {
  testWidgets('the bar of the viewer sits at the top, not over the middle of the photo', (
    tester,
  ) async {
    await _openViewer(tester, size: phone);
    final close = tester.getRect(
      find.descendant(of: find.byType(PhotoViewer), matching: find.byTooltip('Fermer')),
    );
    expect(close.top, lessThan(phone.height / 8));
    expect(tester.getRect(_counter('1 / 3')).center.dy, closeTo(close.center.dy, 4));
  });

  testWidgets('the arrow keys turn the photos and Escape closes the viewer', (tester) async {
    await _openViewer(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settleShort(tester);
    expect(_counter('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settleShort(tester);
    expect(_counter('1 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settleShort(tester);
    expect(_counter('1 / 3'), findsOneWidget, reason: 'nothing before the first');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleShort(tester);
    expect(find.byType(PhotoViewer), findsNothing);
    expect(find.byType(PlaceDetailsBody), findsOneWidget, reason: 'the card stays open');
  });

  /// A mouse over the viewer, as it moves there before a click.
  Future<TestGesture> hoveringMouse(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(PhotoViewer)));
    await mouse.moveBy(const Offset(5, 0));
    await tester.pump();
    return mouse;
  }

  /// Past half the window: the test's events carry no time, so no fling.
  Future<void> dragLeft(WidgetTester tester, TestGesture mouse) async {
    await mouse.down(tester.getCenter(find.byType(PhotoViewer)));
    for (var i = 0; i < 16; i++) {
      await mouse.moveBy(const Offset(-50, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await mouse.up();
    await settleShort(tester);
  }

  testWidgets('a drag of the mouse turns the photo', (tester) async {
    await _openViewer(tester);
    final mouse = await hoveringMouse(tester);
    await dragLeft(tester, mouse);
    expect(_counter('2 / 3'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('the wheel zooms the photo, which a drag then moves instead of turning', (
    tester,
  ) async {
    await _openViewer(tester);
    final mouse = await hoveringMouse(tester);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(PhotoViewer)),
        scrollDelta: const Offset(0, -300),
      ),
    );
    await tester.pump();
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
        .transformationController!;
    expect(zoom.value.getMaxScaleOnAxis(), greaterThan(1.5));
    await dragLeft(tester, mouse);
    expect(_counter('1 / 3'), findsOneWidget, reason: 'the zoomed photo pans');
    await mouse.removePointer();
  });

  group('the side buttons', () {
    testWidgets('show on a computer and turn the photos, none past either end', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _openViewer(tester);
        expect(find.byTooltip('Photo précédente'), findsNothing);
        await tester.tap(find.byTooltip('Photo suivante'));
        await settleShort(tester);
        expect(_counter('2 / 3'), findsOneWidget);
        await tester.tap(find.byTooltip('Photo suivante'));
        await settleShort(tester);
        expect(_counter('3 / 3'), findsOneWidget);
        expect(find.byTooltip('Photo suivante'), findsNothing);
        await tester.tap(find.byTooltip('Photo précédente'));
        await settleShort(tester);
        expect(_counter('2 / 3'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('show on a touch screen once a mouse moves over the photo', (tester) async {
      await _openViewer(tester, size: phone);
      expect(find.byTooltip('Photo suivante'), findsNothing, reason: 'a finger swipes');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(PhotoViewer)));
      await mouse.moveBy(const Offset(10, 10));
      await tester.pump();
      expect(find.byTooltip('Photo suivante'), findsOneWidget);
      await mouse.removePointer();
    });
  });

  group('on the web', () {
    setUp(() => MapShield.enabled = true);
    tearDown(() => MapShield.enabled = kIsWeb);

    testWidgets("the viewer covers the map's element, which takes neither click nor drag", (
      tester,
    ) async {
      await _openViewer(tester);
      final shield = find.descendant(
        of: find.byType(MapShield),
        matching: find.byType(PointerInterceptor),
      );
      expect(shield, findsOneWidget);
      expect(tester.getRect(shield), tester.getRect(find.byType(MapShield)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      expect(shield, findsNothing);
    });
  });
}
