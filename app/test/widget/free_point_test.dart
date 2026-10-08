import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/widgets/floating.dart';

import '../helpers/fake_api.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// A tap on bare map at street level opens "Here"; further out, nothing.
void main() {
  const spot = LatLng(45.7701, 4.8402);

  /// A tap on the map where there is no pin, at [zoom], then the time the
  /// map waits for a second tap.
  Future<void> tapBare(TestApp app, WidgetTester tester, double zoom, {LatLng at = spot}) async {
    app.map.lastProps!.onEmptyTap!(at, zoom);
    await tester.pump(const Duration(milliseconds: 300));
    await settleShort(tester);
  }

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    group(name, () {
      testWidgets('at street level a tap on bare map marks the point and opens "Here"', (
        tester,
      ) async {
        final app = await pumpLunaway(tester, size: size);
        await tapBare(app, tester, 14);
        expect(find.text('Ici'), findsOneWidget);
        expect(find.text('Point sur la carte'), findsOneWidget);
        expect(find.text("Itinéraire jusqu'ici"), findsOneWidget);
        expect(find.text('Créer un lieu ici'), findsOneWidget);
        expect(find.text('Copier les coordonnées'), findsOneWidget);
        expect(app.map.lastProps!.markedPoint, spot);
      });

      testWidgets('further out a tap on bare map opens nothing', (tester) async {
        final app = await pumpLunaway(tester, size: size);
        await tapBare(app, tester, 13.9);
        expect(find.text('Ici'), findsNothing);
        expect(app.container(tester).read(selectionProvider), isNull);
        expect(app.map.lastProps!.markedPoint, isNull);
      });

      testWidgets('the map has no "+" button: a place starts from the map itself', (tester) async {
        await pumpLunaway(tester, size: size);
        expect(find.byTooltip('Ajouter un lieu'), findsNothing);
      });
    });
  }

  // The desktop page and the browsers report both clicks of a double click:
  // the app waits before acting.
  final clicks = TargetPlatformVariant.only(TargetPlatform.macOS);

  group('the double tap', () {
    testWidgets('a double click zooms and opens nothing', variant: clicks, (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      final seen = <MapSelection?>[];
      app.container(tester).listen(selectionProvider, (_, next) => seen.add(next));
      app.map.lastProps!.onEmptyTap!(spot, 15);
      await tester.pump(const Duration(milliseconds: 120));
      app.map.lastProps!.onEmptyTap!(spot, 15);
      await tester.pump(const Duration(milliseconds: 300));
      await settleShort(tester);
      expect(find.text('Ici'), findsNothing);
      expect(seen, isEmpty, reason: 'not even a card opened and closed again');
    });

    testWidgets('a single click waits for the window before opening', variant: clicks, (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: desktop);
      app.map.lastProps!.onEmptyTap!(spot, 15);
      await tester.pump(const Duration(milliseconds: 200));
      expect(app.container(tester).read(selectionProvider), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(app.container(tester).read(selectionProvider), isA<PointSelection>());
    });

    testWidgets('a pin clicked just after drops the bare click', variant: clicks, (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      app.map.lastProps!.onEmptyTap!(spot, 15);
      await tester.pump(const Duration(milliseconds: 50));
      app.map.lastProps!.onPlaceTap(lakeArea.id);
      await tester.pump(const Duration(milliseconds: 300));
      await settleShort(tester);
      expect(
        app.container(tester).read(selectionProvider),
        isA<PlaceSelection>().having((s) => s.id, 'id', lakeArea.id),
      );
    });

    testWidgets('on a phone the engine has waited already: the card opens at once', (tester) async {
      final app = await pumpLunaway(tester);
      app.map.lastProps!.onEmptyTap!(spot, 15);
      await tester.pump();
      expect(app.container(tester).read(selectionProvider), isA<PointSelection>());
    });
  });

  group('closing the point', () {
    testWidgets('a tap elsewhere removes the temporary pin, and opens nothing else', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tapBare(app, tester, 15);
      expect(app.map.lastProps!.markedPoint, spot);
      await tapBare(app, tester, 15, at: const LatLng(45.771, 4.841));
      expect(app.map.lastProps!.markedPoint, isNull);
      expect(find.text('Ici'), findsNothing);
    });

    testWidgets('Escape removes it', (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      await tapBare(app, tester, 15);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      expect(app.map.lastProps!.markedPoint, isNull);
    });

    testWidgets('a long press opens the same card at any zoom', (tester) async {
      final app = await pumpLunaway(tester);
      expect(app.map.viewport.zoom, lessThan(14));
      await tester.longPress(find.byKey(const ValueKey('fake-map')));
      await settleShort(tester);
      expect(find.text('Ici'), findsOneWidget);
      expect(find.text('Créer un lieu ici'), findsOneWidget);
    });
  });

  group('a place without a pointer', () {
    const label = 'Ajouter un lieu au centre de la carte';
    const centre = LatLng(45.91, 6.12);
    void restOn(TestApp app) => app.map.viewport = const MapViewport(
      bounds: GeoBounds(south: 45.9, west: 6.1, north: 45.92, east: 6.14),
      center: centre,
      zoom: 15,
    );

    /// Tabs through the screen until the keyboard reaches the control
    /// that holds [text].
    Future<void> tabTo(WidgetTester tester, String text) async {
      final node = Focus.of(tester.element(find.text(text)));
      for (var i = 0; i < 40 && FocusManager.instance.primaryFocus != node; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(FocusManager.instance.primaryFocus, node, reason: 'the keyboard reaches it');
    }

    testWidgets('the keyboard tabs to "add a place at the centre", shown only then, and it opens '
        'the placement on the middle of the map', (tester) async {
      final app = await pumpLunaway(tester, size: desktop, api: FakeApi(level: 2), signedIn: true);
      restOn(app);
      final button = find.ancestor(of: find.text(label), matching: find.byType(TextButton));
      expect(button, findsOneWidget);
      expect(find.ancestor(of: button, matching: find.byType(FloatingSurface)), findsNothing);
      // Hidden, it takes no click: the map under it does.
      expect(
        tester
            .hitTestOnBinding(tester.getCenter(button))
            .path
            .any((e) => e.target == tester.renderObject(button)),
        isFalse,
      );
      await tabTo(tester, label);
      await tester.pump();
      expect(find.ancestor(of: button, matching: find.byType(FloatingSurface)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleShort(tester);
      expect(find.text(t.placement.title), findsOneWidget);
      expect(app.map.lastProps!.initialCenter, centre, reason: 'no panel over this map');
    });

    testWidgets('a screen reader finds it, and on a phone it starts from the middle left free', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpLunaway(tester, api: FakeApi(level: 2), signedIn: true);
      restOn(app);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel(label));
      await settleShort(tester);
      expect(find.text(t.placement.title), findsOneWidget);
      // The list's sheet covers the bottom of the phone's map: the middle
      // of what shows stands north of the camera's.
      expect(app.map.lastProps!.initialCenter.lat, greaterThan(centre.lat));
      semantics.dispose();
    });
  });

  group('the marker of the point', () {
    testWidgets('on a phone, a tap on it brings the lowered card back up', (tester) async {
      final app = await pumpLunaway(tester);
      await tapBare(app, tester, 15);
      final title = find.text('Point sur la carte');
      final open = tester.getTopLeft(title).dy;
      await tester.drag(title, const Offset(0, 250));
      await settleShort(tester);
      expect(tester.getTopLeft(title).dy, greaterThan(open + 100), reason: 'the card lowered');
      app.map.lastProps!.onMarkerTap!();
      await settleShort(tester);
      expect(tester.getTopLeft(title).dy, moreOrLessEquals(open, epsilon: 1));
      expect(app.map.lastProps!.markedPoint, spot, reason: 'the point stays marked');
      expect(find.text('Créer un lieu ici'), findsOneWidget);
    });

    testWidgets('on a desktop, a tap on it keeps the card open and opens nothing else', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: desktop);
      await tapBare(app, tester, 15);
      app.map.lastProps!.onMarkerTap!();
      await settleShort(tester);
      expect(find.text('Ici'), findsOneWidget);
      expect(app.container(tester).read(selectionProvider), isA<PointSelection>());
    });
  });

  group('the hint', () {
    MapViewport street(double zoom) => MapViewport(
      bounds: const GeoBounds(south: 45.76, west: 4.83, north: 45.78, east: 4.85),
      center: spot,
      zoom: zoom,
    );

    testWidgets('the first time the map reaches the street, one line says what a tap does', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      app.map.lastProps!.onViewportChanged(street(12));
      await settleShort(tester);
      expect(find.text('Touchez la carte pour y aller ou y ajouter un lieu'), findsNothing);
      app.map.lastProps!.onViewportChanged(street(14));
      await tester.pump();
      expect(find.text('Touchez la carte pour y aller ou y ajouter un lieu'), findsOneWidget);
      expect(app.container(tester).read(settingsProvider).mapTapHintShown, isTrue);
      expect((await app.settings.load()).mapTapHintShown, isTrue, reason: 'kept for next time');
    });

    testWidgets('once shown, it never comes back', (tester) async {
      final app = await pumpLunaway(tester, settings: const AppSettings(mapTapHintShown: true));
      app.map.lastProps!.onViewportChanged(street(15));
      await tester.pump();
      expect(find.text('Touchez la carte pour y aller ou y ajouter un lieu'), findsNothing);
    });

    testWidgets('in English too', (tester) async {
      final app = await pumpLunaway(tester, locale: AppLocale.en);
      app.map.lastProps!.onViewportChanged(street(14));
      await tester.pump();
      expect(find.text('Tap the map to go there or add a place'), findsOneWidget);
    });
  });

  testWidgets('in English the card says "Here" and its actions', (tester) async {
    final app = await pumpLunaway(tester, locale: AppLocale.en, size: tablet);
    await tapBare(app, tester, 16);
    expect(find.text('Here'), findsOneWidget);
    expect(find.text('Directions here'), findsOneWidget);
    expect(find.text('Create a place here'), findsOneWidget);
    expect(find.text('Copy coordinates'), findsOneWidget);
  });

  group('a free point as a destination', () {
    testWidgets('"Directions here" previews the route to the point, and creates nothing', (
      tester,
    ) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final api = FakeApi(level: 2);
      final app = await pumpLunaway(
        tester,
        api: api,
        signedIn: true,
        overrides: navigationOverrides(routes: routes),
      );
      await tapBare(app, tester, 15);
      await tester.tap(find.text("Itinéraire jusqu'ici"));
      await settleShort(tester);
      expect(routes.requests.single.destination, spot);
      expect(find.text('Point sur la carte'), findsOneWidget);
      expect(find.text('45.770100, 4.840200'), findsOneWidget);
      expect(api.calls.where((c) => c.operation == 'AddPlace'), isEmpty, reason: 'no place made');
    });

    testWidgets('the preview writes the point in the format the user copies coordinates in', (
      tester,
    ) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        settings: const AppSettings(copyFormat: CoordinateFormat.dms),
        overrides: navigationOverrides(routes: routes),
      );
      await tapBare(app, tester, 15);
      await tester.tap(find.text("Itinéraire jusqu'ici"));
      await settleShort(tester);
      expect(find.text(CoordinateFormat.dms.format(spot)), findsOneWidget);
      expect(find.text('45.770100, 4.840200'), findsNothing);
      // A stop without a name is written the same way.
      const stop = LatLng(45.84, 1.27);
      SchematicRouteMap.last!.onEmptyTap!(stop, 15);
      await tester.pump(const Duration(milliseconds: 300));
      await settleShort(tester);
      await tester.tap(find.textContaining('Ajouter comme étape'));
      await settleShort(tester);
      expect(find.text(CoordinateFormat.dms.format(stop)), findsOneWidget);
    });

    testWidgets('degrees, minutes, seconds take two digits of seconds, copied and on the preview', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(
        tester,
        settings: const AppSettings(copyFormat: CoordinateFormat.dms),
        overrides: navigationOverrides(routes: routes),
      );
      const point = LatLng(45.7623, 4.8338);
      const written = '45°45\'44.3"N 4°50\'01.7"E';
      await tapBare(app, tester, 15, at: point);
      await tester.tap(find.text('Copier les coordonnées'));
      await settleShort(tester);
      expect(copied, [written]);
      await tester.tap(find.text("Itinéraire jusqu'ici"));
      await settleShort(tester);
      expect(find.text(written), findsOneWidget);
    });

    testWidgets('the preview routes to the point exact, whatever its link rounds', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(tester, overrides: navigationOverrides(routes: routes));
      // More decimals than any link holds.
      const exact = LatLng(45.77010049, 4.84020051);
      await tapBare(app, tester, 15, at: exact);
      await tester.tap(find.text("Itinéraire jusqu'ici"));
      await settleShort(tester);
      final preview = tester.widget<RoutePreviewScreen>(find.byType(RoutePreviewScreen));
      expect(preview.target?.destination, exact);
      expect(routes.requests.single.destination, exact);
    });

    testWidgets('on the preview, a tap at street level offers the point as a stop', (tester) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final app = await pumpLunaway(tester, overrides: navigationOverrides(routes: routes));
      await tapBare(app, tester, 15);
      await tester.tap(find.text("Itinéraire jusqu'ici"));
      await settleShort(tester);
      const stop = LatLng(45.84, 1.27);
      SchematicRouteMap.last!.onEmptyTap!(stop, 12);
      await tester.pump(const Duration(milliseconds: 300));
      await settleShort(tester);
      expect(find.text('Y aller directement'), findsNothing, reason: 'too far out for a point');
      SchematicRouteMap.last!.onEmptyTap!(stop, 15);
      await tester.pump(const Duration(milliseconds: 300));
      await settleShort(tester);
      expect(find.text('Point sur la carte'), findsWidgets);
      expect(find.text('Y aller directement'), findsOneWidget);
      expect(find.textContaining('Ajouter comme étape'), findsOneWidget);
    });
  });
}
