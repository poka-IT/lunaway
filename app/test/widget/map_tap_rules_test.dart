import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/shared/adaptive_shell.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:lunaway/shared/widgets/spring_sheet.dart';

import '../helpers/fake_browser.dart';
import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'map_screen_test.dart' show recordAppExits, systemBack;

/// A tap on the map as the PO set it on 2026-10-10: what the user chose
/// stays chosen, a point drops only on a tap the user meant (no fling
/// stopped, no drag just ended, no sheet moving, clear of what can be
/// tapped), and a point dropped by mistake goes as easily.
void main() {
  /// The map at the street, where a tap on bare map may drop a point.
  const street = MapViewport(
    bounds: GeoBounds(south: 45.765, west: 4.83, north: 45.775, east: 4.85),
    center: LatLng(45.77, 4.84),
    zoom: 15,
  );

  /// The app with a map that reports the taps on its surface, at the
  /// street, the camera at rest long enough for a tap to count.
  Future<TestApp> pumpStreet(WidgetTester tester, Size size, {FakeBrowser? browser}) async {
    final app = await pumpLunaway(
      tester,
      size: size,
      map: FakeMap()..reportsTaps = true,
      overrides: [if (browser != null) browserProvider.overrideWithValue(browser)],
    );
    app.map.viewport = street;
    app.map.lastProps!.onViewportChanged(street);
    await tester.pump(FreeTap.motionQuiet + const Duration(milliseconds: 100));
    return app;
  }

  /// A spot where a finger lands on the bare map: nothing the app draws
  /// over it, away from the pins the fake map lays out in its middle.
  Offset bareSpot(WidgetTester tester) {
    final surface = find.descendant(
      of: find.byKey(const ValueKey('fake-map')),
      matching: find.byType(ColoredBox),
    );
    final target = tester.renderObject(surface.first);
    final map = tester.getRect(surface.first);
    for (var y = map.top + 160; y < map.bottom - 40; y += 40) {
      for (var x = map.left + 40; x < map.right - 40; x += 40) {
        final at = Offset(x, y);
        if ((at - map.center).distance < 120) continue;
        final path = tester.hitTestOnBinding(at).path;
        if (path.isNotEmpty && path.first.target == target) return at;
      }
    }
    throw StateError('no bare map left');
  }

  MapSelection? open(TestApp app, WidgetTester tester) =>
      app.container(tester).read(selectionProvider);

  /// The lowered card keeps its close and its menu in reach, above the bar
  /// of actions and the fade over it, which in a browser takes the clicks
  /// for the bar (`OverMap`).
  void expectHeadAboveBar(WidgetTester tester) {
    final bar = tester.getRect(find.byType(ActionsBar)).top;
    for (final tip in ['Fermer', "Plus d'actions"]) {
      final button = tester.getRect(find.byTooltip(tip).first);
      expect(button.bottom, lessThanOrEqualTo(bar), reason: '"$tip" at $button, the bar at $bar');
      expect(button.center.dy, lessThanOrEqualTo(bar - BottomFade.lead), reason: 'over the fade');
    }
  }

  /// The height of the phone's sheet over the map.
  double sheetHeight(WidgetTester tester) => tester
      .getSize(find.descendant(of: find.byType(SpringSheet), matching: find.byType(OverMap)).first)
      .height;

  const address = AddressMatch(
    kind: AddressKind.houseNumber,
    name: '12 Rue de la République',
    postcode: '69002',
    city: 'Lyon',
    context: '69, Rhône, Auvergne-Rhône-Alpes',
    countryCode: 'FR',
    position: LatLng(45.7665, 4.8360),
    sourceId: 'ban',
    attribution: 'Base Adresse Nationale, IGN Géoplateforme',
  );

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    group(name, () {
      for (final (what, choose) in <(String, MapSelection)>[
        ('a place', PlaceSelection(lakeArea.id)),
        ('an address', const PointSelection(LatLng(45.7665, 4.8360), address: address)),
      ]) {
        testWidgets('with $what open, a tap on bare map keeps it and drops no point', (
          tester,
        ) async {
          final app = await pumpStreet(tester, size);
          app.container(tester).read(mapFlowProvider.notifier).select(choose);
          await settleShort(tester);
          final opened = name == 'phone' ? sheetHeight(tester) : null;
          await tester.tapAt(bareSpot(tester));
          await settleShort(tester);
          expect(open(app, tester), choose, reason: 'the choice stays');
          expect(
            app.map.lastProps!.markedPoint,
            choose is PointSelection ? choose.position : isNull,
            reason: 'no point dropped',
          );
          if (opened != null) {
            expect(sheetHeight(tester), lessThan(opened - 50), reason: 'lowered from $opened');
            expectHeadAboveBar(tester);
          }
        });
      }

      testWidgets('with nothing open, a tap at the street drops a point', (tester) async {
        final app = await pumpStreet(tester, size);
        await tester.tapAt(bareSpot(tester));
        await settleShort(tester);
        expect(open(app, tester), PointSelection(app.map.tapAt));
      });
    });
  }

  for (final (name, size, scale) in [
    ('a narrow phone', const Size(360, 740), 1.0),
    ('a phone with large text', phone, 1.3),
  ]) {
    testWidgets('on $name, the card a tap lowered keeps its head above a bar of two rows', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        size: size,
        textScale: scale,
        map: FakeMap()..reportsTaps = true,
      );
      app.map.viewport = street;
      app.map.lastProps!.onViewportChanged(street);
      await tester.pump(FreeTap.motionQuiet + const Duration(milliseconds: 100));
      app
          .container(tester)
          .read(mapFlowProvider.notifier)
          .select(PointSelection(address.position, address: address));
      await settleShort(tester);
      await tester.tapAt(bareSpot(tester));
      await settleShort(tester);
      expect(open(app, tester), isA<PointSelection>());
      expectHeadAboveBar(tester);
    });
  }

  testWidgets('the touch that stops a fling drops no point, nor one within 500 ms of the '
      "map's rest; a tap after drops one", (tester) async {
    final app = await pumpStreet(tester, phone);
    final spot = bareSpot(tester);
    await tester.flingFrom(spot, const Offset(0, 200), 2000);
    await tester.pump(const Duration(milliseconds: 200));
    // The map still glides: the finger that stops it.
    await tester.tapAt(spot);
    await settleShort(tester);
    expect(open(app, tester), isNull, reason: 'it stopped the fling');
    const moved = MapViewport(
      bounds: GeoBounds(south: 45.76, west: 4.83, north: 45.77, east: 4.85),
      center: LatLng(45.765, 4.84),
      zoom: 15,
    );
    app.map.viewport = moved;
    app.map.lastProps!.onViewportChanged(moved);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(spot);
    await tester.pump();
    expect(open(app, tester), isNull, reason: '300 ms after the rest');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(spot);
    await settleShort(tester);
    expect(open(app, tester), isA<PointSelection>(), reason: 'a tap meant');
  });

  testWidgets(
    "a double click whose first click is refused in a rest's wait zooms, and drops no "
    'point with its second',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final app = await pumpStreet(tester, desktop);
      final spot = bareSpot(tester);
      // A double click's zoom has just ended.
      const zoomed = MapViewport(
        bounds: GeoBounds(south: 45.767, west: 4.835, north: 45.773, east: 4.845),
        center: LatLng(45.77, 4.84),
        zoom: 16,
      );
      app.map.viewport = zoomed;
      app.map.lastProps!.onViewportChanged(zoomed);
      await tester.pump(const Duration(milliseconds: 420));
      await tester.tapAt(spot, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(spot, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 300));
      await settleShort(tester);
      expect(open(app, tester), isNull);
    },
  );

  testWidgets('a tap while the sheet still moves drops no point', (tester) async {
    final app = await pumpStreet(tester, phone);
    app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
    await settleShort(tester);
    await tester.tap(find.byTooltip('Fermer').first);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(bareSpot(tester));
    await settleShort(tester);
    expect(open(app, tester), isNull, reason: 'the sheet was going down');
    await tester.tapAt(bareSpot(tester));
    await settleShort(tester);
    expect(open(app, tester), isA<PointSelection>());
  });

  testWidgets('a long press drops a point at any zoom, over what is open', (tester) async {
    final app = await pumpLunaway(tester);
    expect(app.map.viewport.zoom, lessThan(FreeTap.freePointMinZoom));
    app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
    await settleShort(tester);
    await tester.longPressAt(bareSpot(tester));
    await settleShort(tester);
    expect(open(app, tester), PointSelection(app.map.longPressAt));
  });

  group('a point dropped by mistake', () {
    testWidgets('in the apps, goes at a tap on the map; the back then leaves as before', (
      tester,
    ) async {
      final exits = recordAppExits(tester);
      final app = await pumpStreet(tester, phone);
      await tester.tapAt(bareSpot(tester));
      await settleShort(tester);
      expect(open(app, tester), isA<PointSelection>());
      await tester.tapAt(bareSpot(tester));
      await settleShort(tester);
      expect(open(app, tester), isNull);
      expect(app.map.lastProps!.markedPoint, isNull);
      await systemBack(tester);
      expect(exits, hasLength(1), reason: 'no step of the point left to go back to');
    });

    testWidgets('in a browser, goes at a tap on the map or at the back, and leaves no entry '
        'behind', (tester) async {
      final browser = FakeBrowser(tester);
      final app = await pumpStreet(tester, phone, browser: browser);
      final before = browser.index;
      expect(browser.location, '/map');
      await tester.tapAt(bareSpot(tester));
      await settleShort(tester);
      expect(browser.location, '/map?point');
      await tester.tapAt(bareSpot(tester));
      await settleShort(tester);
      expect(open(app, tester), isNull);
      expect(browser.location, '/map');
      expect(browser.index, before, reason: 'the entry of the point taken back');
      await tester.pump(FreeTap.motionQuiet);
      await tester.tapAt(bareSpot(tester));
      await settleShort(tester);
      expect(browser.location, '/map?point');
      await browser.back();
      await settleShort(tester);
      expect(open(app, tester), isNull);
      expect(browser.location, '/map');
      expect(browser.index, before);
      final behind = browser.entries.sublist(0, browser.index + 1).map((e) => e.location);
      expect(behind, isNot(contains('/map?point')));
    });
  });
}
