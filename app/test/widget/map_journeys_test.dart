import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fake_browser.dart';
import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'map_screen_test.dart' show systemBack;

// Every journey of the map screen, played through its controls on a phone,
// a tablet and a computer, in a browser and in the apps: a place, a town, an
// address and a shop found by the search, a point held on the map; the
// card, "Itinéraire", "C'est parti !", a back during the guidance, its end,
// the close, a second guidance. Each journey ends on the screen it should.
// The reports behind it, from a phone's browser: an address found, its route
// shown, "C'est parti !" went back to the screen before; a town found and
// touched, nothing happened. A phone's browser hands the map the late click
// of a tap on a search result once the list has gone: the map, pressed
// before the result was picked, acted on the result (the card closed, a
// point opened) instead of nothing.

final Translations t = AppLocale.fr.buildSync();

/// The prefecture of Haute-Savoie, a public address.
const _address = AddressMatch(
  kind: AddressKind.houseNumber,
  name: "30 Rue du 30e Régiment d'Infanterie",
  postcode: '74000',
  city: 'Annecy',
  context: '74, Haute-Savoie, Auvergne-Rhône-Alpes',
  countryCode: 'FR',
  position: LatLng(45.9017, 6.1263),
  sourceId: 'ban',
  attribution: 'Base Adresse Nationale, IGN Géoplateforme',
);

const _addressLabel = "30 Rue du 30e Régiment d'Infanterie, Annecy";

/// A phone, a tablet, a computer: the three layouts of the map screen.
const _layouts = [
  ('a phone', Size(400, 1000)),
  ('a tablet', Size(720, 1100)),
  ('a computer', Size(1600, 1000)),
];

/// A voice whose preparation fails: a part of the device that breaks at
/// the guidance's start.
final class _BrokenVoice implements VoiceOutput {
  @override
  Future<VoiceReadiness> prepare(RouteLanguage language) async =>
      throw StateError('no speech synthesis');

  @override
  bool get chimes => false;

  @override
  Future<bool> say(String text, {bool chime = false}) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<bool> installVoices() async => false;
}

/// The app on the map with its search online and the guidance's fakes; in
/// a browser when [web].
Future<(TestApp, FakeBrowser?)> _pump(
  WidgetTester tester,
  Size size, {
  bool web = true,
  Vehicle? vehicle = motorhome,
  VoiceOutput? voice,
}) async {
  final browser = web ? FakeBrowser(tester) : null;
  final plan = routeFixture('utrillo_motorhome');
  final online = FakeOnlinePlaces(samplePlaces)..addresses.add(_address);
  final app = await pumpLunaway(
    tester,
    size: size,
    places: const [],
    online: online,
    overrides: [
      ...navigationOverrides(
        routes: FakeRouteService([for (var i = 0; i < 8; i++) plan]),
        engine: LineEngine([plan]),
        settings: MemoryRouteSettings(),
        vehicle: vehicle,
        voice: voice,
      ),
      if (browser != null) browserProvider.overrideWithValue(browser),
    ],
  );
  return (app, browser);
}

MapSelection? _open(TestApp app, WidgetTester tester) =>
    app.container(tester).read(selectionProvider);

/// [text] typed in the map's search.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await settleShort(tester);
}

/// The result [label] of the search, touched (not the field, which may
/// hold the same words).
Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(MapSearch),
          matching: find.byWidgetPredicate((w) => w is Text && w.data == label),
        )
        .first,
  );
  await settleShort(tester);
}

/// A press on the bare map, which acts on nothing by itself: the map heard a
/// press there.
Future<void> _pressMap(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('fake-map'))));
  await settleShort(tester);
}

/// The way there from the card: "Itinéraire", or "Itinéraire jusqu'ici".
Future<void> _route(WidgetTester tester, String label) async {
  final button = find.text(label).last;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settleShort(tester);
  expect(find.byType(RoutePreviewScreen), findsOneWidget, reason: 'the route shown');
}

/// "C'est parti !": the guidance runs, its page shown.
Future<void> _start(TestApp app, WidgetTester tester) async {
  await tester.tap(find.text(t.navigation.preview.start));
  await settleShort(tester);
  expect(app.container(tester).read(guidanceControllerProvider), isNotNull);
  expect(
    find.byType(GuidanceScreen),
    findsOneWidget,
    reason: 'the guidance, not the screen before',
  );
  expect(find.byType(RoutePreviewScreen), findsNothing);
}

/// "Terminer", confirmed.
Future<void> _end(TestApp app, WidgetTester tester) async {
  await tester.tap(find.byTooltip(t.navigation.guidance.end));
  await settleShort(tester);
  await tester.tap(find.widgetWithText(FilledButton, t.navigation.guidance.end));
  await settleShort(tester);
  expect(app.container(tester).read(guidanceControllerProvider), isNull);
}

/// The browser's back, or the system's in the apps.
Future<void> _back(WidgetTester tester, FakeBrowser? browser) async {
  if (browser == null) {
    await systemBack(tester);
    return;
  }
  await browser.back();
  await settleShort(tester);
}

/// The pages a history entry shows over the map, as go_router writes them.
List<String> _pagesOver(Object? state) => switch (state) {
  {'imperativeMatches': final List<Object?> pages} => [
    for (final page in pages)
      if (page case {'location': final String location}) location,
  ],
  _ => const [],
};

/// The bare map: nothing open, no page over it, and in a browser the map's
/// bare address, with no entry behind that holds a page over the map.
void _bareMap(TestApp app, WidgetTester tester, FakeBrowser? browser) {
  expect(_open(app, tester), isNull);
  expect(find.byType(RoutePreviewScreen), findsNothing);
  expect(find.byType(GuidanceScreen), findsNothing);
  if (browser == null) return;
  expect(browser.location, '/map');
  expect(browser.leftApp, isFalse);
  final behind = browser.entries.sublist(0, browser.index + 1);
  expect([for (final e in behind) ..._pagesOver(e.state)], isEmpty);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip(t.common.close).first);
  await settleShort(tester);
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  for (final (layout, size) in _layouts) {
    for (final web in [true, false]) {
      final where = web ? 'in a browser' : 'in the apps';
      group('on $layout $where', () {
        testWidgets('a place found: its card, its route, the guidance, its end, the close, a '
            'second guidance', (tester) async {
          final (app, browser) = await _pump(tester, size, web: web);
          await _search(tester, 'Aire du Lac');
          await _pick(tester, lakeArea.name!);
          expect(_open(app, tester), PlaceSelection(lakeArea.id));
          expect(find.byType(PlaceDetailsBody), findsOneWidget);
          if (browser != null) expect(browser.location, '/map?place=${lakeArea.id}');
          await _route(tester, t.place.directions);
          await _start(app, tester);
          await _end(app, tester);
          expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the place it left');
          expect(find.byType(PlaceDetailsBody), findsOneWidget);
          await _route(tester, t.place.directions);
          await _start(app, tester);
          await _end(app, tester);
          await _close(tester);
          _bareMap(app, tester, browser);
        });

        testWidgets('a town found: the map goes there and nothing opens', (tester) async {
          final (app, browser) = await _pump(tester, size, web: web);
          await _search(tester, 'Annecy');
          await _pick(tester, 'Annecy');
          expect(app.map.moves.last, (center: lakeArea.position, zoom: 12.0));
          expect(find.text(t.search.towns), findsNothing, reason: 'the search closed');
          _bareMap(app, tester, browser);
        });

        testWidgets('an address found: its card, a route named after it, the guidance, a back '
            'that asks, the card again', (tester) async {
          final (app, browser) = await _pump(tester, size, web: web);
          await _search(tester, 'Régiment');
          await _pick(tester, _address.name);
          expect(
            _open(app, tester),
            const PointSelection(LatLng(45.9017, 6.1263), address: _address),
          );
          if (browser != null) expect(browser.location, '/map?point');
          await _route(tester, t.map.directionsHere);
          expect(
            find.text(t.navigation.preview.titleTo(name: _addressLabel)),
            findsOneWidget,
            reason: 'the destination keeps its name',
          );
          await _start(app, tester);
          await _back(tester, browser);
          expect(find.text(t.navigation.guidance.stopTitle), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, t.navigation.guidance.stopConfirm));
          await settleShort(tester);
          expect(app.container(tester).read(guidanceControllerProvider), isNull);
          expect(find.byType(GuidanceScreen), findsNothing);
          expect(_open(app, tester), isA<PointSelection>(), reason: 'back on the address');
          await _close(tester);
          _bareMap(app, tester, browser);
        });

        testWidgets('a shop found: its card, a route named after it, back to its card', (
          tester,
        ) async {
          final (app, browser) = await _pump(tester, size, web: web);
          await _search(tester, 'Boulangerie');
          await _pick(tester, 'Boulangerie du Lac');
          expect(_open(app, tester), isA<PoiSelection>());
          expect(find.byType(PoiDetails), findsOneWidget);
          await _route(tester, t.place.directions);
          expect(
            find.text(t.navigation.preview.titleTo(name: 'Boulangerie du Lac')),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip(t.navigation.preview.back));
          await settleShort(tester);
          expect(find.byType(RoutePreviewScreen), findsNothing);
          expect(find.byType(PoiDetails), findsOneWidget);
          if (browser != null) expect(browser.location, startsWith('/map?poi='));
          await _close(tester);
          _bareMap(app, tester, browser);
        });

        testWidgets('a start chosen at an address, a place found: its route from that start, '
            'then from my position, the guidance', (tester) async {
          final (app, browser) = await _pump(tester, size, web: web);
          await _search(tester, 'Régiment');
          await _pick(tester, _address.name);
          final start = find.text(t.map.startHere);
          // Built once the card is scrolled to it, on a phone's sheet.
          await tester.scrollUntilVisible(
            start,
            120,
            scrollable: find
                .descendant(of: find.byType(PointDetails), matching: find.byType(Scrollable))
                .first,
          );
          await Scrollable.ensureVisible(tester.element(start), alignment: 0.3);
          await settleShort(tester);
          await tester.tap(start);
          await settleShort(tester);
          await _search(tester, 'Aire du Lac');
          await _pick(tester, lakeArea.name!);
          await _route(tester, t.place.directions);
          expect(
            find.text(t.navigation.preview.departure.from(name: _addressLabel)),
            findsOneWidget,
            reason: 'the route from the start chosen',
          );
          await tester.tap(find.text(t.navigation.preview.departure.fromMyPosition));
          await settleShort(tester);
          await _start(app, tester);
          await _end(app, tester);
          expect(_open(app, tester), PlaceSelection(lakeArea.id));
          await _close(tester);
          _bareMap(app, tester, browser);
        });

        testWidgets('a point held on the map: its card, its route, back to its card', (
          tester,
        ) async {
          final (app, browser) = await _pump(tester, size, web: web);
          await tester.longPressAt(tester.getCenter(find.byKey(const ValueKey('fake-map'))));
          await settleShort(tester);
          expect(_open(app, tester), PointSelection(app.map.longPressAt));
          await _route(tester, t.map.directionsHere);
          expect(find.text(t.navigation.preview.titlePoint), findsOneWidget);
          await tester.tap(find.byTooltip(t.navigation.preview.back));
          await settleShort(tester);
          expect(find.byType(RoutePreviewScreen), findsNothing);
          expect(_open(app, tester), PointSelection(app.map.longPressAt));
          if (browser != null) expect(browser.location, '/map?point');
          await _close(tester);
          _bareMap(app, tester, browser);
        });
      });
    }
  }

  group('a report of the map that comes after the user chose', () {
    for (final (layout, size) in _layouts) {
      testWidgets('on $layout, an address found keeps its card when the map reports a press of '
          'before on bare map', (tester) async {
        final (app, browser) = await _pump(tester, size);
        await _pressMap(tester);
        await _search(tester, 'Régiment');
        await _pick(tester, _address.name);
        // The browser hands the map the click of the result's tap, late,
        // once the list has gone.
        app.map.lastProps!.onEmptyTap!(_address.position, 17);
        await settleShort(tester);
        expect(_open(app, tester), isA<PointSelection>(), reason: 'the card stays open');
        expect(browser!.location, '/map?point');
        await _route(tester, t.map.directionsHere);
        await _start(app, tester);
      });

      testWidgets('on $layout, a town found opens nothing when the map reports a press of '
          'before', (tester) async {
        final (app, _) = await _pump(tester, size);
        await _pressMap(tester);
        await _search(tester, 'Annecy');
        await _pick(tester, 'Annecy');
        // At the street's zoom, a bare tap opens a point.
        app.map.lastProps!.onEmptyTap!(lakeArea.position, 16);
        await settleShort(tester);
        expect(_open(app, tester), isNull);
        expect(app.map.moves.last, (center: lakeArea.position, zoom: 12.0));
      });

      testWidgets('on $layout, a place found stays open when the map reports a pin pressed '
          'before', (tester) async {
        final (app, _) = await _pump(tester, size);
        await _pressMap(tester);
        await _search(tester, 'Aire du Lac');
        await _pick(tester, lakeArea.name!);
        app.map.lastProps!.onPlaceTap(campsite.id);
        await settleShort(tester);
        expect(_open(app, tester), PlaceSelection(lakeArea.id));
      });
    }

    testWidgets('a press on the map after the choice still acts', (tester) async {
      final (app, _) = await _pump(tester, _layouts.first.$2);
      await _search(tester, 'Régiment');
      await _pick(tester, _address.name);
      await _pressMap(tester);
      app.map.lastProps!.onEmptyTap!(_address.position, 17);
      await settleShort(tester);
      expect(_open(app, tester), isNull, reason: 'a tap elsewhere closes the card');
    });
  });

  group('in a browser, the history written in order', () {
    for (final (layout, size) in [_layouts.first, _layouts.last]) {
      testWidgets('on $layout, a pin tapped at once after a close stays open, over the bare map', (
        tester,
      ) async {
        final (app, browser) = await _pump(tester, size);
        app.map.lastProps!.onPlaceTap(lakeArea.id);
        await settleShort(tester);
        // The close goes back one entry, which lands a moment later; the
        // pin comes before it has.
        await tester.tap(find.byTooltip(t.common.close).first);
        app.map.lastProps!.onPlaceTap(campsite.id);
        await settleShort(tester);
        expect(_open(app, tester), PlaceSelection(campsite.id));
        expect(browser!.location, '/map?place=${campsite.id}');
        await browser.back();
        await settleShort(tester);
        _bareMap(app, tester, browser);
      });
    }
  });

  group("in a phone's browser, the back over a popup closes the popup", () {
    final phone = _layouts.first.$2;

    testWidgets('the filters: the back closes them, the app stays', (tester) async {
      final (_, browser) = await _pump(tester, phone);
      await tester.tap(find.text(t.filters.title).first);
      await settleShort(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      await browser!.back();
      await settleShort(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(browser.leftApp, isFalse);
      expect(browser.location, '/map');
    });

    testWidgets('the photo viewer: the back closes it, the place stays', (tester) async {
      final (app, browser) = await _pump(tester, phone);
      app.map.lastProps!.onPlaceTap(lakeArea.id);
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
      expect(find.byType(PhotoViewer), findsOneWidget);
      await browser!.back();
      await settleShort(tester);
      expect(find.byType(PhotoViewer), findsNothing);
      expect(_open(app, tester), PlaceSelection(lakeArea.id), reason: 'the card under it');
      expect(browser.location, '/map?place=${lakeArea.id}');
    });

    testWidgets('a popup closed by its own hand takes its entry with it', (tester) async {
      final (_, browser) = await _pump(tester, phone);
      final before = browser!.index;
      await tester.tap(find.text(t.filters.title).first);
      await settleShort(tester);
      await tester.tapAt(const Offset(200, 40));
      await settleShort(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(browser.index, before, reason: 'the next back is the one it was before');
      expect(browser.location, '/map');
    });
  });

  group('the keyboard', () {
    for (final (layout, size) in _layouts) {
      testWidgets('on $layout, Escape closes a card the search opened', (tester) async {
        final (app, _) = await _pump(tester, size);
        await _search(tester, 'Aire du Lac');
        await _pick(tester, lakeArea.name!);
        expect(_open(app, tester), PlaceSelection(lakeArea.id));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleShort(tester);
        expect(_open(app, tester), isNull);
      });
    }
  });

  group('"Les lieux autour" on an address', () {
    for (final (layout, size) in _layouts) {
      testWidgets('on $layout, the card gives way to the places around it', (tester) async {
        final (app, _) = await _pump(tester, size);
        await _search(tester, 'Régiment');
        await _pick(tester, _address.name);
        final around = find.text(t.map.placesAround);
        // Into the middle of the card, clear of its bar of actions.
        await Scrollable.ensureVisible(tester.element(around), alignment: 0.3);
        await settleShort(tester);
        await tester.tap(around);
        await settleShort(tester);
        expect(_open(app, tester), isNull, reason: 'the card closed');
        expect(app.map.moves.last, (center: _address.position, zoom: 12.0));
        if (layout != 'a tablet') {
          expect(find.byType(NearbyList), findsOneWidget, reason: 'the list of the places');
        }
      });
    }
  });

  group('"C\'est parti !"', () {
    for (final (layout, size) in [_layouts.first, _layouts.last]) {
      testWidgets('on $layout, a start that fails says so; no guidance is left behind', (
        tester,
      ) async {
        final (app, _) = await _pump(tester, size, voice: _BrokenVoice());
        await _search(tester, 'Régiment');
        await _pick(tester, _address.name);
        await _route(tester, t.map.directionsHere);
        await tester.tap(find.text(t.navigation.preview.start));
        await settleShort(tester);
        expect(find.text(t.navigation.guidance.unavailable), findsOneWidget);
        expect(app.container(tester).read(guidanceControllerProvider), isNull);
        expect(find.byType(RoutePreviewScreen), findsOneWidget);
      });
    }

    testWidgets('on a small phone, the vehicle to describe is the action in sight', (tester) async {
      await _pump(tester, const Size(360, 640), vehicle: null);
      await _search(tester, 'Régiment');
      await _pick(tester, _address.name);
      await _route(tester, t.map.directionsHere);
      final describe = find.widgetWithText(FilledButton, t.navigation.states.describeVehicle);
      expect(describe, findsOneWidget);
      final rect = tester.getRect(describe);
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.top, greaterThan(640 / 2), reason: 'at the foot, under the sheet');
      await tester.tap(describe);
      await settleShort(tester);
      expect(find.text(t.vehicle.title), findsWidgets, reason: 'the vehicle editor');
    });
  });
}
