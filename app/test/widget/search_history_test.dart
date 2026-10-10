import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_tile.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/search/application/search_history_providers.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';
import 'package:lunaway/features/search/presentation/recent_searches.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

final Translations t = AppLocale.fr.buildSync();

/// A restaurant of Annecy, as `searchAll` sends it with where it lies.
final Map<String, Object?> _restaurant = poiJson(
  '00000000-0000-7000-8000-00000000e001',
  'RESTAURANT',
  name: 'La Ciboulette',
  extra: {
    'inTiles': false,
    'locality': {'town': 'Annecy', 'department': '74', 'countryCode': 'FR'},
  },
);

const _segur = AddressMatch(
  kind: AddressKind.houseNumber,
  name: '20 Avenue de Ségur',
  postcode: '75007',
  city: 'Paris',
  context: '75, Paris, Île-de-France',
  countryCode: 'FR',
  position: LatLng(48.850699, 2.308628),
  sourceId: 'ban',
  attribution: 'Base Adresse Nationale, IGN Géoplateforme',
);

Finder get _field => find.byType(TextField).first;

/// [f] in the history under the field.
Finder _inHistory(Finder f) => find.descendant(of: find.byType(RecentSearchesList), matching: f);

/// [f] in the search, its field and what shows under it.
Finder _inSearch(Finder f) => find.descendant(of: find.byType(MapSearch), matching: f);

/// Every request but the pages of the list beside the map.
List<String> _searches(FakeOnlinePlaces online) => [
  for (final r in online.requests)
    if (!r.startsWith('page:')) r,
];

/// The app online with [online], a phone by default.
Future<TestApp> _app(WidgetTester tester, FakeOnlinePlaces online, {Size size = phone}) =>
    pumpLunaway(tester, size: size, online: online);

Future<void> _focus(WidgetTester tester) async {
  await tester.tap(_field);
  await settleShort(tester);
}

Future<void> _record(TestApp app, WidgetTester tester, List<RecentSearch> entries) async {
  final store = app.container(tester).read(searchHistoryStoreProvider);
  for (final e in entries) {
    await store.record(e);
  }
  await settleShort(tester);
}

/// What the history keeps, read outside the test's clock: a query that
/// watches the database emits through a timer of its own.
Future<List<RecentSearch>> _kept(TestApp app, WidgetTester tester) async => (await tester.runAsync(
  () => app.container(tester).read(searchHistoryStoreProvider).watch().first,
))!;

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('the history of the search', () {
    for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
      testWidgets('on a $name, the empty field focused shows the recent searches, newest first', (
        tester,
      ) async {
        final online = FakeOnlinePlaces(samplePlaces);
        final app = await _app(tester, online, size: size);
        await _focus(tester);
        expect(find.text(t.search.recent), findsNothing, reason: 'nothing to show yet');
        await _record(app, tester, [
          RecentPlace(lakeArea.summary),
          const RecentText('pizzeria annecy'),
        ]);
        expect(find.text(t.search.recent), findsOneWidget);
        expect(find.text(t.search.clearHistory), findsOneWidget);
        final text = tester.getTopLeft(_inHistory(find.text('pizzeria annecy'))).dy;
        final place = tester.getTopLeft(_inHistory(find.text(lakeArea.name!))).dy;
        expect(text, lessThan(place), reason: 'the most recent first');
        expect(
          _inHistory(find.text('${t.kind(lakeArea.kind)} · Annecy\u00a0(74)')),
          findsOneWidget,
          reason: 'what and where, as under its result',
        );
        expect(_searches(online), isEmpty, reason: 'the history asks the server nothing');
      });
    }

    testWidgets('a place of the history opens again by its id, without a search', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      await _record(app, tester, [RecentPlace(lakeArea.summary)]);
      await _focus(tester);
      await tester.tap(_inHistory(find.text(lakeArea.name!)));
      await settleShort(tester);
      expect(app.container(tester).read(selectionProvider), PlaceSelection(lakeArea.id));
      expect(
        _searches(online).where((r) => r.startsWith('searchAll') || r.startsWith('search:')),
        isEmpty,
        reason: 'reopened, not searched again',
      );
      expect(find.text(t.search.recent), findsNothing, reason: 'the history closed');
    });

    testWidgets('a point of the history opens again by its id, its town in its header', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await pumpLunaway(
        tester,
        online: online,
        pois: FakePoiSource(pois: [_restaurant]),
      );
      await _record(app, tester, [RecentPoi.of(poiFromJson(_restaurant)!)]);
      await _focus(tester);
      expect(_inHistory(find.text('Restaurant · Annecy\u00a0(74)')), findsOneWidget);
      await tester.tap(_inHistory(find.text('La Ciboulette')));
      await settleShort(tester);
      final open = app.container(tester).read(selectionProvider);
      expect(open, isA<PoiSelection>());
      expect((open! as PoiSelection).feature.id, _restaurant['id']);
      expect(_searches(online), isEmpty, reason: 'reopened by its id, no search');
    });

    testWidgets('a place gone from the map leaves the history with a message', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      // Opened once, then merged or taken down: neither the device nor the
      // server holds it any more.
      const gone = PlaceSummary(
        id: 'test-gone',
        name: 'Aire disparue',
        kind: PlaceKind.motorhomeArea,
        lat: 45.9,
        lon: 6.1,
        overnight: OvernightStatus.allowed,
      );
      await _record(app, tester, [const RecentPlace(gone)]);
      await _focus(tester);
      await tester.tap(_inHistory(find.text(gone.name!)));
      await settleShort(tester);
      expect(app.container(tester).read(selectionProvider), isNull, reason: 'nothing opens');
      expect(find.text(t.search.recentGone(name: gone.name!)), findsOneWidget);
      expect(await _kept(app, tester), isEmpty, reason: 'the entry left');
      expect(online.requests, contains('place:test-gone'), reason: 'read by its id');
    });

    testWidgets('the cross takes one entry out, the button the whole history', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online, size: desktop);
      await _record(app, tester, [
        RecentPlace(lakeArea.summary),
        const RecentText('pizzeria annecy'),
        const RecentAddress(_segur),
      ]);
      await _focus(tester);
      await tester.tap(find.byTooltip(t.search.removeRecent(name: 'pizzeria annecy')));
      await settleShort(tester);
      expect(_inHistory(find.text('pizzeria annecy')), findsNothing);
      expect(_inHistory(find.text(lakeArea.name!)), findsOneWidget, reason: 'the others stay');
      expect(_inHistory(find.text('Adresse · Paris\u00a07e')), findsOneWidget);
      await tester.tap(find.text(t.search.clearHistory));
      await settleShort(tester);
      expect(_inHistory(find.text(lakeArea.name!)), findsNothing);
      expect(find.text(t.search.recent), findsNothing);
      expect(find.text(t.search.historyCleared), findsOneWidget);
      expect(await _kept(app, tester), isEmpty);
    });

    testWidgets('each cross is a target of 48 named for a screen reader', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online, size: desktop);
      await _record(app, tester, [const RecentText('aire de services')]);
      await _focus(tester);
      final cross = find.byTooltip(t.search.removeRecent(name: 'aire de services'));
      expect(cross, findsOneWidget);
      final box = tester.getSize(cross);
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      // The keyboard reaches it from the field, the history open all along.
      final button = find.ancestor(of: cross, matching: find.byType(IconButton));
      bool onCross() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<IconButton>() ==
          tester.widget(button);
      for (var i = 0; i < 6 && !onCross(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(find.text(t.search.recent), findsOneWidget, reason: 'the history stays');
      }
      expect(onCross(), isTrue, reason: 'Tab reaches the cross');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleShort(tester);
      expect(
        _inHistory(find.text('aire de services')),
        findsNothing,
        reason: 'the cross works from the keys',
      );
    });

    testWidgets('opening a result keeps it, and the same result again is one entry', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      for (var i = 0; i < 2; i++) {
        await tester.enterText(_field, 'Lac Bleu');
        await settleShort(tester);
        // The result's row, not the entry of the history above it.
        await tester.tap(
          find.descendant(
            of: _inSearch(find.byType(PlaceTile)),
            matching: find.text(lakeArea.name!),
          ),
        );
        await settleShort(tester);
        // Its card closed, the map bare again for the next search.
        app.container(tester).read(mapFlowProvider.notifier).select(null);
        await settleShort(tester);
      }
      final kept = await _kept(app, tester);
      expect(kept.map((e) => e.key), ['place:${lakeArea.id}'], reason: 'one entry, not two');
    });

    testWidgets('a text validated without opening anything is kept, and searched again', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      await tester.enterText(_field, 'Tilleuls');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleShort(tester);
      await tester.tap(find.byTooltip(t.map.clearSearch));
      await settleShort(tester);
      final kept = await _kept(app, tester);
      expect(kept.map((e) => e.title), ['Tilleuls']);
      online.requests.clear();
      await _focus(tester);
      await tester.tap(_inHistory(find.text('Tilleuls')));
      await settleShort(tester);
      expect(app.container(tester).read(searchQueryProvider), 'Tilleuls');
      expect(_searches(online), ['searchAll:Tilleuls'], reason: 'the text is searched again');
      expect(_inSearch(find.text(dayParking.name!)), findsOneWidget);
    });

    testWidgets('a text followed by the result it found keeps the result only', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      await tester.enterText(_field, 'Lac Bleu');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleShort(tester);
      await tester.tap(_inSearch(find.text(lakeArea.name!)));
      await settleShort(tester);
      final kept = await _kept(app, tester);
      expect(kept.map((e) => e.key), ['place:${lakeArea.id}']);
    });

    testWidgets('typing, the entries the text matches head the results under a clock', (
      tester,
    ) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      await _record(app, tester, [RecentPlace(campsite.summary), const RecentAddress(_segur)]);
      await tester.enterText(_field, 'segur');
      await settleShort(tester);
      expect(_inSearch(find.byIcon(AppIcons.recent)), findsOneWidget, reason: 'under a clock');
      expect(_inSearch(find.text('20 Avenue de Ségur')), findsOneWidget);
      expect(
        _inSearch(find.text(campsite.name!)),
        findsNothing,
        reason: 'an entry the text does not name',
      );
      expect(find.text(t.search.recent), findsNothing, reason: 'the results, not the history');
    });

    testWidgets('the system back closes the history before anything else', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces);
      final app = await _app(tester, online);
      await _record(app, tester, [const RecentText('pizzeria annecy')]);
      await _focus(tester);
      expect(find.text(t.search.recent), findsOneWidget);
      expect(app.container(tester).read(mapFlowProvider.notifier).back(), isTrue);
      await settleShort(tester);
      expect(find.text(t.search.recent), findsNothing);
      expect(app.container(tester).read(searchHistoryOpenProvider), isFalse);
    });
  });

  group('the town on each row of the search', () {
    testWidgets('an establishment says where it lies, and so does its page', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces)..pois.add(_restaurant);
      await pumpLunaway(
        tester,
        online: online,
        pois: FakePoiSource(pois: [_restaurant]),
      );
      await tester.enterText(_field, 'Ciboulette');
      await settleShort(tester);
      expect(_inSearch(find.textContaining('Restaurant · Annecy\u00a0(74)')), findsOneWidget);
      await tester.tap(_inSearch(find.text('La Ciboulette')));
      await settleShort(tester);
      expect(
        find.textContaining('Annecy\u00a0(74)'),
        findsWidgets,
        reason: 'the header of its page',
      );
    });

    testWidgets('a place, an address and a town each say where they lie', (tester) async {
      final online = FakeOnlinePlaces(samplePlaces)..addresses.add(_segur);
      await _app(tester, online, size: desktop);
      await tester.enterText(_field, 'Lyon');
      await settleShort(tester);
      expect(
        _inSearch(find.textContaining('Lyon\u00a01er')),
        findsWidgets,
        reason: 'an arrondissement of Lyon',
      );
      await tester.enterText(_field, 'Ségur');
      await settleShort(tester);
      expect(_inSearch(find.textContaining('Adresse · Paris\u00a07e')), findsOneWidget);
      await tester.enterText(_field, 'Annecy');
      await settleShort(tester);
      expect(_inSearch(find.textContaining('Commune · Haute-Savoie')), findsOneWidget);
    });
  });
}
