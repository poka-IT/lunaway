import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';

import '../helpers/fake_browser.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'map_screen_test.dart' show recordAppExits, systemBack;

/// The report of 2026-10-08, on the web app: a route started, then ended,
/// then the place closed. The close went back in the tab's history onto the
/// guidance's entry ("Le guidage n'a pas pu démarrer sur cet appareil."),
/// or onto the preview's, which the close reopened every time.

const _error = "Le guidage n'a pas pu démarrer sur cet appareil.";

/// Wide enough for the details in a panel of their own, right of the map.
const _wide = Size(1600, 1000);

/// A phone tall enough for the place's whole sheet.
const _tallPhone = Size(400, 1600);

MapSelection? _open(TestApp app, WidgetTester tester) =>
    app.container(tester).read(selectionProvider);

/// The pages a history entry shows over the map, as go_router writes them in
/// its state: none for the map itself.
List<String> _pagesOver(Object? state) => switch (state) {
  {'imperativeMatches': final List<Object?> pages} => [
    for (final page in pages)
      if (page case {'location': final String location}) location,
  ],
  _ => const [],
};

/// Neither the preview, nor the guidance, nor its error.
void _onlyTheMap() {
  expect(find.byType(RoutePreviewScreen), findsNothing);
  expect(find.byType(GuidanceScreen), findsNothing);
  expect(find.text(_error), findsNothing);
}

void main() {
  /// The app on the map with the guidance's fakes; in a browser when
  /// [web].
  Future<(TestApp, FakeBrowser?)> pumpApp(
    WidgetTester tester, {
    Size size = _wide,
    bool web = true,
  }) async {
    final browser = web ? FakeBrowser(tester) : null;
    final plan = routeFixture('utrillo_motorhome');
    final app = await pumpLunaway(
      tester,
      size: size,
      overrides: [
        ...navigationOverrides(
          routes: FakeRouteService([for (var i = 0; i < 4; i++) plan]),
          engine: LineEngine([plan]),
          settings: MemoryRouteSettings(
            const NavigationSettings(acceptedDisclaimer: 'routing.disclaimer.v1'),
          ),
        ),
        if (browser != null) browserProvider.overrideWithValue(browser),
      ],
    );
    return (app, browser);
  }

  Future<void> tapPin(TestApp app, WidgetTester tester, String id) async {
    app.map.lastProps!.onPlaceTap(id);
    await settleShort(tester);
  }

  /// "Itinéraire" from what is open, the preview.
  Future<void> openRoute(WidgetTester tester, {String label = 'Itinéraire'}) async {
    await tester.tap(find.text(label).last);
    await settleShort(tester);
    expect(find.byType(RoutePreviewScreen), findsOneWidget);
  }

  /// "C'est parti !", then "Terminer", confirmed: back on the map.
  Future<void> guideAndEnd(TestApp app, WidgetTester tester) async {
    await tester.tap(find.text("C'est parti !"));
    await settleShort(tester);
    expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
    await tester.tap(find.byTooltip('Terminer'));
    await settleShort(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await settleShort(tester);
    expect(app.container(tester).read(guidanceControllerProvider), isNull);
    _onlyTheMap();
  }

  group('in a browser, after a guidance ended', () {
    for (final (name, size) in [('a wide desktop', _wide), ('a phone', _tallPhone)]) {
      testWidgets('on $name the close shows the bare map, and no entry behind holds the route', (
        tester,
      ) async {
        final (app, browser) = await pumpApp(tester, size: size);
        await tapPin(app, tester, lakeArea.id);
        await openRoute(tester);
        await guideAndEnd(app, tester);
        expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the place it left');
        await tester.tap(find.byTooltip('Fermer'));
        await settleShort(tester);
        _onlyTheMap();
        expect(_open(app, tester), isNull);
        expect(browser!.location, '/map');
        final behind = browser.entries.sublist(0, browser.index + 1);
        expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
      });
    }

    testWidgets('Escape closes the place onto the bare map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser!.location, '/map');
    });

    testWidgets("the browser's back closes the place onto the bare map", (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await browser!.back();
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser.leftApp, isFalse);
    });

    testWidgets('after two guidances ended, the close shows the bare map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser!.location, '/map');
    });

    testWidgets('from a point of the map, the close shows the bare map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      app
          .container(tester)
          .read(selectionProvider.notifier)
          .select(const PointSelection(LatLng(45.7629, 4.831697)));
      await settleShort(tester);
      expect(browser!.location, '/map?point');
      await openRoute(tester, label: "Itinéraire jusqu'ici");
      await guideAndEnd(app, tester);
      expect(_open(app, tester), isA<PointSelection>());
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
    });

    testWidgets("forward to the ended guidance's page shows the map, not an error", (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      await browser!.forward();
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      expect(browser.location, '/map?place=${lakeArea.id}');
    });
  });

  group('in a browser, the preview left by its own back', () {
    testWidgets('the close shows the bare map rather than the preview again', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await tester.tap(find.byTooltip('Retour'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(browser!.location, '/map');
    });
  });

  group('in a browser, a page over the map', () {
    testWidgets('a selection changed under the preview writes no address and keeps the preview', (
      tester,
    ) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      final entries = browser!.entries.length;
      // As the surroundings of a place's card over the route do.
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(campsite.id));
      await settleShort(tester);
      expect(find.byType(RoutePreviewScreen), findsOneWidget);
      expect(browser.entries, hasLength(entries));
      expect(browser.location, '/map?place=${lakeArea.id}', reason: "the map's address under it");
    });
  });

  group('the guidance page without a guidance', () {
    testWidgets('in a browser, a link to it shows the map in its place', (tester) async {
      final (app, browser) = await pumpApp(tester);
      app.container(tester).read(routerProvider).go(NavigationRoutes.guidance);
      await settleShort(tester);
      _onlyTheMap();
      expect(browser!.location, '/map');
      // Its entry went to the map: the back does not come to it again.
      await browser.back();
      await settleShort(tester);
      _onlyTheMap();
    });

    testWidgets('in the apps, it goes back to the map', (tester) async {
      final (app, _) = await pumpApp(tester, size: phone, web: false);
      unawaited(app.container(tester).read(routerProvider).push<void>(NavigationRoutes.guidance));
      await settleShort(tester);
      _onlyTheMap();
    });
  });

  group('the system back of the apps, after a guidance ended', () {
    testWidgets('closes the place, then leaves the app, never the route', (tester) async {
      final exits = recordAppExits(tester);
      final (app, _) = await pumpApp(tester, size: _tallPhone, web: false);
      await tapPin(app, tester, lakeArea.id);
      await openRoute(tester);
      await guideAndEnd(app, tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      await systemBack(tester);
      _onlyTheMap();
      expect(_open(app, tester), isNull);
      expect(exits, isEmpty);
      await systemBack(tester);
      expect(exits, hasLength(1));
    });
  });

  group('in a browser, an entry the map did not write', () {
    testWidgets('a link to the place open: the close stays on the map', (tester) async {
      final (app, browser) = await pumpApp(tester);
      await tapPin(app, tester, lakeArea.id);
      app.container(tester).read(routerProvider).go('/map?place=${lakeArea.id}');
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull, reason: 'a back would have landed on the place again');
      expect(browser!.location, '/map');
      expect(browser.moves, isEmpty);
    });
  });
}
