import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fake_browser.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'map_screen_test.dart' show recordAppExits, systemBack;

final Translations t = AppLocale.fr.buildSync();

/// A phone tall enough for a place's surroundings to show in its sheet.
const _tallPhone = Size(400, 2400);

Finder _inPlace(Finder finder) =>
    find.descendant(of: find.byType(PlaceDetailsBody), matching: finder);

Finder _inPoi(Finder finder) => find.descendant(of: find.byType(PoiDetails), matching: finder);

/// What the map shows: a place, a point of interest, or nothing.
MapSelection? _open(TestApp app, WidgetTester tester) =>
    app.container(tester).read(selectionProvider);

/// A tap on the pin of [id], as the map reports it (a sheet may cover the
/// fake map's own pin widgets).
Future<void> _tapPin(TestApp app, WidgetTester tester, String id) async {
  app.map.lastProps!.onPlaceTap(id);
  await settleShort(tester);
}

/// The shop of the lake area's surroundings, opened from its sheet.
Future<void> _openBakery(WidgetTester tester) async {
  // Into the middle of the sheet, clear of the bar of actions under it.
  final row = _inPlace(find.text('Boulangerie du Lac'));
  await Scrollable.ensureVisible(tester.element(row), alignment: 0.4);
  await settleShort(tester);
  await tester.tap(row);
  await settleShort(tester);
  expect(_inPoi(find.text('Boulangerie du Lac')), findsOneWidget);
}

void main() {
  group('in a browser', () {
    Future<(TestApp, FakeBrowser)> pumpWeb(WidgetTester tester, {Size size = phone}) async {
      final browser = FakeBrowser(tester);
      final app = await pumpLunaway(
        tester,
        size: size,
        overrides: [browserProvider.overrideWithValue(browser)],
      );
      return (app, browser);
    }

    for (final (name, size) in [('a phone', phone), ('a desktop', desktop)]) {
      testWidgets('on $name the back closes the open place and the app stays', (tester) async {
        final (app, browser) = await pumpWeb(tester, size: size);
        expect(browser.location, '/map');
        await _tapPin(app, tester, lakeArea.id);
        expect(_open(app, tester), PlaceSelection(lakeArea.id));
        expect(browser.location, '/map?place=${lakeArea.id}', reason: 'an address to share');
        await browser.back();
        await settleShort(tester);
        expect(browser.leftApp, isFalse);
        expect(_open(app, tester), isNull);
        expect(app.map.lastProps!.selectedId, isNull);
        expect(find.byType(PlaceDetailsBody), findsNothing);
      });
    }

    testWidgets("another pin takes the open one's entry: one back still closes", (tester) async {
      final (app, browser) = await pumpWeb(tester);
      await _tapPin(app, tester, lakeArea.id);
      await _tapPin(app, tester, campsite.id);
      expect(browser.location, '/map?place=${campsite.id}');
      expect(browser.entries.map((e) => e.location), [
        'about:blank',
        '/map',
        '/map?place=${campsite.id}',
      ]);
      await browser.back();
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.leftApp, isFalse);
    });

    testWidgets('the close button goes back to the bare map rather than add an entry', (
      tester,
    ) async {
      final (app, browser) = await pumpWeb(tester);
      await _tapPin(app, tester, lakeArea.id);
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.moves, [-1]);
      expect(browser.location, '/map');
      // The browser's forward opens it again, as any page it went back from.
      await browser.forward();
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
    });

    testWidgets('a shop opened around a place: back reopens the place, then closes it', (
      tester,
    ) async {
      final (app, browser) = await pumpWeb(tester, size: _tallPhone);
      await _tapPin(app, tester, lakeArea.id);
      await _openBakery(tester);
      expect(browser.location, startsWith('/map?poi='));
      expect(browser.location, endsWith('&from=${lakeArea.id}'));
      await browser.back();
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      expect(_inPlace(find.text(t.poi.around)), findsOneWidget);
      await browser.back();
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.leftApp, isFalse);
    });

    testWidgets("the shop's way back to its place walks back the history", (tester) async {
      final (app, browser) = await pumpWeb(tester, size: _tallPhone);
      await _tapPin(app, tester, lakeArea.id);
      await _openBakery(tester);
      await tester.tap(_inPoi(find.text(t.poi.backTo(name: lakeArea.name!))));
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      expect(browser.moves, [-1]);
      expect(browser.location, '/map?place=${lakeArea.id}');
    });

    testWidgets('a link to a place opens it; its close leads to the bare map', (tester) async {
      final (app, browser) = await pumpWeb(tester);
      app.container(tester).read(routerProvider).go('/map?place=${campsite.id}');
      await settleShort(tester, const Duration(seconds: 2));
      expect(_open(app, tester), PlaceSelection(campsite.id));
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
      expect(
        browser.moves,
        isEmpty,
        reason: 'an address the map did not open itself: the bare map takes a new entry',
      );
      expect(browser.leftApp, isFalse);
    });

    testWidgets('a page opened on a link to a place shows it; its close stays in the app', (
      tester,
    ) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/map?place=${campsite.id}';
      addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
      final (app, browser) = await pumpWeb(tester);
      await settleShort(tester, const Duration(seconds: 2));
      expect(_open(app, tester), PlaceSelection(campsite.id));
      expect(app.map.moves.last.center, campsite.position);
      expect(browser.location, '/map?place=${campsite.id}');
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
      expect(browser.leftApp, isFalse, reason: 'under the link lies the page it came from');
    });

    testWidgets('a favourite opens at its own address, and its back leaves it', (tester) async {
      final (app, browser) = await pumpWeb(tester);
      await app.favorites.addToDefault(campsite.summary);
      await tester.tap(find.text('Favoris').last);
      await settleShort(tester);
      await tester.tap(find.text(campsite.name!));
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(campsite.id));
      expect(browser.location, '/map?place=${campsite.id}');
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
      expect(browser.leftApp, isFalse);
    });

    testWidgets('a place left for another tab is still open on return, and closes in the app', (
      tester,
    ) async {
      // The rail stays beside an open place; on a phone its bar of actions
      // takes the dock's place.
      final (app, browser) = await pumpWeb(tester, size: desktop);
      await _tapPin(app, tester, lakeArea.id);
      await tester.tap(find.text('Favoris').last);
      await settleShort(tester);
      expect(browser.location, '/favorites');
      await tester.tap(find.text('Carte').last);
      await settleShort(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      expect(browser.location, '/map?place=${lakeArea.id}');
      await tester.tap(find.byTooltip('Fermer'));
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
      expect(browser.moves, isEmpty, reason: 'the entry under it is the favourites, not the map');
      await browser.back();
      await settleShort(tester);
      expect(browser.leftApp, isFalse);
      expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the entry it had');
    });

    testWidgets('a page reloaded on a point, which its address does not hold, shows the map', (
      tester,
    ) async {
      final (app, browser) = await pumpWeb(tester);
      app.container(tester).read(routerProvider).go('/map?point');
      await settleShort(tester);
      expect(_open(app, tester), isNull);
      expect(browser.location, '/map');
    });
  });

  group('the system back of the apps', () {
    testWidgets('on a shop opened around a place it reopens the place, then closes it', (
      tester,
    ) async {
      final exits = recordAppExits(tester);
      final app = await pumpLunaway(tester, size: _tallPhone);
      await _tapPin(app, tester, lakeArea.id);
      await _openBakery(tester);
      await systemBack(tester);
      expect(_open(app, tester), PlaceSelection(lakeArea.id));
      expect(_inPlace(find.text(lakeArea.name!)), findsWidgets);
      await systemBack(tester);
      expect(_open(app, tester), isNull);
      expect(exits, isEmpty);
      await systemBack(tester);
      expect(exits, hasLength(1));
    });

    testWidgets('a pin tapped over another closes in one back', (tester) async {
      final exits = recordAppExits(tester);
      final app = await pumpLunaway(tester);
      await _tapPin(app, tester, lakeArea.id);
      await _tapPin(app, tester, campsite.id);
      await systemBack(tester);
      expect(_open(app, tester), isNull);
      expect(exits, isEmpty);
    });
  });
}
