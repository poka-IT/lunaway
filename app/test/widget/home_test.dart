import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/home_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/home_views.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/features/navigation/presentation/widgets/departure_sheet.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/search/application/search_history_providers.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';
import 'package:lunaway/features/search/presentation/recent_searches.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

final Translations t = AppLocale.fr.buildSync();

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

const _lilasAt = LatLng(45.9, 6.12);

/// The home of the tests: an address of Annecy.
SavedPoint _lilas() => asHome(
  SavedPoint(
    id: '',
    kind: SavedPointKind.address,
    name: '1 rue des Lilas',
    position: _lilasAt,
    address: '1 rue des Lilas, 74000 Annecy',
  ),
);

/// The app with the navigation's fakes, so the route home can open, and
/// the home's watch kept alive whatever the screen shows.
Future<TestApp> _app(
  WidgetTester tester, {
  Size size = phone,
  FakeOnlinePlaces? online,
  LatLng? here,
}) async {
  final app = await pumpLunaway(
    tester,
    size: size,
    online: online,
    overrides: navigationOverrides(
      routes: FakeRouteService([routeFixture('utrillo_motorhome')]),
      feed: here == null ? null : FakeLocationFeed(position: here),
    ),
  );
  final home = app.container(tester).listen(userHomeProvider, (_, _) {});
  addTearDown(home.close);
  return app;
}

Future<void> _setHome(TestApp app, WidgetTester tester) async {
  await app.container(tester).read(homeRepositoryProvider).set(_lilas());
  await settleShort(tester);
}

/// The home as the screens read it ([userHomeProvider]), once the
/// database's writes and its watch have run.
Future<SavedPoint?> _stored(TestApp app, WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return app.container(tester).read(userHomeProvider).value;
}

/// The passing message shown (6 s with an action) has left the foot of
/// the screen, which it covered.
Future<void> _messageGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 7));
  await settleShort(tester);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settleShort(tester);
}

Finder _inCard(Finder f) => find.descendant(of: find.byType(HomeCard), matching: f);

/// A home the device's storage refuses to read while [broken], and finds
/// none of after.
final class _FailingHome implements HomeRepository {
  bool broken = true;

  @override
  Stream<SavedPoint?> watch() =>
      broken ? Stream.error(StateError('storage refused')) : Stream.value(null);

  @override
  Future<SavedPoint?> read() async => throw StateError('storage refused');

  @override
  Future<void> set(SavedPoint point) async => throw StateError('storage refused');

  @override
  Future<void> clear() async => throw StateError('storage refused');

  @override
  Future<void> clearLocal() async => throw StateError('storage refused');
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    testWidgets('on a $name, the home heads the favourites and its route starts in one tap', (
      tester,
    ) async {
      final app = await _app(tester, size: size);
      await _setHome(app, tester);
      await _openTab(tester, 'Favoris');
      expect(_inCard(find.text('Domicile')), findsOneWidget);
      expect(
        _inCard(find.text('1 rue des Lilas, 74000 Annecy')),
        findsOneWidget,
        reason: 'its address, said once',
      );
      final card = tester.getRect(find.byType(HomeCard));
      final lists = tester.getRect(find.text('Mes favoris').first);
      expect(card.top, lessThan(lists.top), reason: 'above the lists');

      await tester.tap(_inCard(find.text('Itinéraire')));
      await settleShort(tester);
      expect(find.byType(RoutePreviewScreen), findsOneWidget);
      expect(find.text('Vers Domicile'), findsOneWidget);
    });
  }

  testWidgets("the route home's link, opened again, routes to the home kept here", (tester) async {
    final app = await _app(tester);
    await _setHome(app, tester);
    // As a reload or a link typed: nothing beside the link but the device.
    unawaited(app.container(tester).read(routerProvider).push('/route?to=home'));
    await settleShort(tester);
    expect(find.byType(RoutePreviewScreen), findsOneWidget);
    expect(find.text('Vers Domicile'), findsOneWidget);
  });

  testWidgets('a home the device cannot read says so above the lists, with a retry', (
    tester,
  ) async {
    final failing = _FailingHome();
    await pumpLunaway(tester, overrides: [homeRepositoryProvider.overrideWithValue(failing)]);
    await _openTab(tester, 'Favoris');
    expect(_inCard(find.text(t.home.error)), findsOneWidget);
    expect(find.text('Mes favoris'), findsWidgets, reason: 'the lists show all the same');
    failing.broken = false;
    await tester.tap(_inCard(find.text(t.common.retry)));
    await settleShort(tester);
    expect(
      _inCard(find.text(t.home.setTitle)),
      findsOneWidget,
      reason: 'read again, the device has no home: the way to set one',
    );
  });

  testWidgets('choosing the home on the map ends with the card of the point closed', (
    tester,
  ) async {
    final app = await _app(tester);
    final container = app.container(tester);
    container.read(homePickingProvider.notifier).start();
    container.read(mapFlowProvider.notifier).select(const PointSelection(LatLng(45.77, 4.84)));
    await settleShort(tester);
    expect(find.text(t.home.here), findsOneWidget);
    container.read(mapFlowProvider.notifier).select(null);
    await settleShort(tester);
    expect(
      container.read(homePickingProvider),
      isFalse,
      reason: 'a point held days later is not offered as the home',
    );
  });

  testWidgets('at twice the text size, a phone shows the home and the lists without overflow', (
    tester,
  ) async {
    final app = await pumpLunaway(tester, textScale: 2);
    await app.container(tester).read(homeRepositoryProvider).set(_lilas());
    await settleShort(tester);
    await _openTab(tester, 'Favoris');
    expect(_inCard(find.text('Domicile')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the card holds to one line of address');
  });

  testWidgets('without a home, "Définir mon domicile" takes an address the search finds', (
    tester,
  ) async {
    final online = FakeOnlinePlaces(samplePlaces)..addresses.add(_segur);
    final app = await _app(tester, online: online);
    await _openTab(tester, 'Favoris');
    await tester.tap(find.text(t.home.setTitle));
    await settleShort(tester);
    final sheet = find.byType(HomeSearch);
    expect(find.text(t.home.sheetTitle), findsOneWidget);
    expect(find.text(t.home.privacy), findsOneWidget, reason: 'where it is kept, before it is');
    await tester.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), 'avenue');
    await tester.pump(const Duration(milliseconds: 600));
    await settleShort(tester);
    await tester.tap(find.descendant(of: sheet, matching: find.text('20 Avenue de Ségur')));
    await settleShort(tester);
    final home = await _stored(app, tester);
    expect(
      (home?.kind, home?.name, home?.address, home?.position),
      (
        SavedPointKind.address,
        '20 Avenue de Ségur',
        '20 Avenue de Ségur, 75007 Paris',
        _segur.position,
      ),
    );
    expect(find.byType(HomeSearch), findsNothing, reason: 'the sheet closes');
    expect(find.text(t.home.saved), findsOneWidget);
    expect(_inCard(find.text('20 Avenue de Ségur, 75007 Paris')), findsOneWidget);
  });

  testWidgets('"Ma position actuelle" makes the position the home, as a point of the day', (
    tester,
  ) async {
    const here = LatLng(45.84719, 1.28476);
    final app = await _app(tester, here: here);
    await _openTab(tester, 'Favoris');
    await tester.tap(find.text(t.home.setTitle));
    await settleShort(tester);
    await tester.tap(find.text(t.home.myPosition));
    await settleShort(tester);
    final home = await _stored(app, tester);
    expect(
      (home?.kind, home?.position, home?.name),
      (SavedPointKind.point, here, 'Point du 6 oct.'),
    );
  });

  testWidgets("a point's menu makes it the home; Undo takes it back; then it offers to remove", (
    tester,
  ) async {
    final app = await _app(tester);
    const spot = LatLng(45.7701, 4.8402);
    app.container(tester).read(mapFlowProvider.notifier).select(const PointSelection(spot));
    await settleShort(tester);
    Future<void> openMenu() async {
      await tester.tap(
        find.descendant(of: find.byType(PointDetails), matching: find.byTooltip("Plus d'actions")),
      );
      await settleShort(tester);
    }

    await openMenu();
    await tester.tap(find.text(t.home.setHere));
    await settleShort(tester);
    expect((await _stored(app, tester))?.position, spot);
    expect(find.text(t.home.saved), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(await _stored(app, tester), isNull, reason: 'undone');

    await openMenu();
    await tester.tap(find.text(t.home.setHere));
    await settleShort(tester);
    // The message of the change, at the foot, gone from over the menu.
    await _messageGone(tester);
    await openMenu();
    expect(find.text(t.home.removeHere), findsOneWidget, reason: 'it is the home already');
    await tester.tap(find.text(t.home.removeHere));
    await settleShort(tester);
    expect(await _stored(app, tester), isNull);
    expect(find.text(t.home.removed), findsOneWidget);
  });

  testWidgets("a place's menu makes the place the home, and another one changes it", (
    tester,
  ) async {
    final app = await _app(tester);
    await _setHome(app, tester);
    app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
    await settleShort(tester);
    await tester.tap(
      find.descendant(of: find.byType(PlaceDetails), matching: find.byTooltip("Plus d'actions")),
    );
    await settleShort(tester);
    await tester.tap(find.text(t.home.setHere));
    await settleShort(tester);
    final home = await _stored(app, tester);
    expect((home?.name, home?.position), (lakeArea.name, lakeArea.position));
    expect(find.text(t.home.changed), findsOneWidget, reason: 'nothing asked, the change said');
  });

  testWidgets('the empty search lists the home before the history; a tap routes home', (
    tester,
  ) async {
    final app = await _app(tester, online: FakeOnlinePlaces(samplePlaces));
    await app.container(tester).read(searchHistoryStoreProvider).record(const RecentText('lac'));
    await _setHome(app, tester);
    await tester.tap(find.byType(TextField).first);
    await settleShort(tester);
    final list = find.byType(RecentSearchesList);
    final home = find.descendant(of: list, matching: find.byType(HomeSearchTile));
    expect(home, findsOneWidget);
    expect(
      tester.getRect(home).top,
      lessThan(tester.getRect(find.descendant(of: list, matching: find.text('lac'))).top),
      reason: 'the home first',
    );
    expect(
      tester.getSemantics(home).label,
      t.home.directionsHome,
      reason: 'a screen reader hears what the tap does',
    );
    await tester.tap(home);
    await settleShort(tester);
    expect(find.byType(RoutePreviewScreen), findsOneWidget);
    expect(find.text('Vers Domicile'), findsOneWidget);
  });

  testWidgets('with no history, the empty search still lists the home', (tester) async {
    final app = await _app(tester, online: FakeOnlinePlaces(samplePlaces));
    await _setHome(app, tester);
    await tester.tap(find.byType(TextField).first);
    await settleShort(tester);
    expect(find.byType(HomeSearchTile), findsOneWidget);
    expect(find.text(t.search.recent), findsNothing, reason: 'no history to title');
    expect(find.text(t.search.clearHistory), findsNothing);
  });

  testWidgets('the preview offers the home as the start, and as the destination instead', (
    tester,
  ) async {
    final app = await _app(tester, size: const Size(400, 2400));
    await _setHome(app, tester);
    const target = RouteTarget(
      destination: LatLng(45.84510, 1.28637),
      label: 'Aire de la rue Utrillo',
    );
    unawaited(app.container(tester).read(routerProvider).push(NavigationRoutes.previewOf(target)));
    await settleShort(tester);
    expect(find.text('Vers Aire de la rue Utrillo'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Changer'));
    await settleShort(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(DepartureSearch),
        matching: find.widgetWithText(ListTile, 'Domicile'),
      ),
    );
    await settleShort(tester);
    final start = app.container(tester).read(chosenDepartureProvider);
    expect((start?.position, start?.label), (_lilasAt, 'Domicile'));
    expect(find.text('Départ : Domicile'), findsOneWidget);
    expect(
      find.text(t.home.goHome),
      findsNothing,
      reason: 'a route from home is offered no way home',
    );

    app.container(tester).read(chosenDepartureProvider.notifier).clear();
    await settleShort(tester);
    await tester.tap(find.text(t.home.goHome));
    await settleShort(tester);
    expect(find.text('Vers Domicile'), findsOneWidget, reason: 'the route home in its place');
    expect(find.text(t.home.goHome), findsNothing, reason: 'it goes home already');
  });

  testWidgets('placed on the map: the sheet leads there, and the point held is the home', (
    tester,
  ) async {
    final app = await _app(tester);
    await _openTab(tester, 'Favoris');
    await tester.tap(find.text(t.home.setTitle));
    await settleShort(tester);
    await tester.tap(find.text(t.home.onMap));
    await settleShort(tester);
    expect(find.text(t.home.onMapNotice), findsOneWidget, reason: 'what to do next is said');
    expect(app.container(tester).read(homePickingProvider), isTrue);

    const spot = LatLng(45.7701, 4.8402);
    app.map.lastProps!.onLongPress(spot);
    await _messageGone(tester);
    await settleShort(tester);
    await tester.tap(find.text(t.home.here));
    await settleShort(tester);
    expect((await _stored(app, tester))?.position, spot);
    expect(app.container(tester).read(homePickingProvider), isFalse, reason: 'placed once');
    expect(find.text(t.home.here), findsNothing);
  });
}
