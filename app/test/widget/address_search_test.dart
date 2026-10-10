import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/widgets/departure_sheet.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

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

const _annecyTown = AddressMatch(
  kind: AddressKind.town,
  name: 'Annecy',
  postcode: '74000',
  position: LatLng(45.9, 6.12),
  sourceId: 'ban',
  attribution: 'Base Adresse Nationale, IGN Géoplateforme',
);

const _munich = AddressMatch(
  kind: AddressKind.street,
  name: 'Annecystraße',
  city: 'München',
  countryCode: 'DE',
  position: LatLng(48.13, 11.57),
  sourceId: 'osm',
  attribution: '© OpenStreetMap contributors',
);

FakeOnlinePlaces _online() =>
    FakeOnlinePlaces(samplePlaces)..addresses.addAll([_segur, _annecyTown, _munich]);

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group("a route's start", () {
    Future<FakeRouteService> openStart(
      WidgetTester tester,
      String query, {
      bool offline = false,
    }) async {
      final routes = FakeRouteService([routeFixture('utrillo_motorhome')]);
      final online = _online();
      final app = await pumpLunaway(
        tester,
        places: const [],
        online: online,
        overrides: navigationOverrides(routes: routes),
      );
      unawaited(
        app
            .container(tester)
            .read(routerProvider)
            .push(NavigationRoutes.previewOf(const RouteTarget(destination: LatLng(45.84, 1.27)))),
      );
      await settleShort(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Changer'));
      await settleShort(tester);
      online.offline = offline;
      await tester.enterText(
        find.descendant(of: find.byType(DepartureSearch), matching: find.byType(TextField)),
        query,
      );
      await settleShort(tester);
      return routes;
    }

    testWidgets('an address is credited to its source, and starts the route', (tester) async {
      final routes = await openStart(tester, 'avenue');
      final sheet = find.byType(DepartureSearch);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Adresses : Base Adresse Nationale, IGN Géoplateforme'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.descendant(of: sheet, matching: find.text('20 Avenue de Ségur')));
      await settleShort(tester);
      expect(routes.requests.last.origin, _segur.position);
      expect(find.text('Départ : 20 Avenue de Ségur, Paris'), findsOneWidget);
    });

    testWidgets('a search that fails says so, the way back still there', (tester) async {
      await openStart(tester, 'avenue', offline: true);
      final sheet = find.byType(DepartureSearch);
      expect(
        find.descendant(of: sheet, matching: find.text("La liste n'a pas pu s'afficher.")),
        findsOneWidget,
      );
      expect(find.descendant(of: sheet, matching: find.text('Ma position')), findsOneWidget);
    });

    testWidgets('a search that finds nothing says so', (tester) async {
      await openStart(tester, 'zzqx');
      expect(
        find.descendant(
          of: find.byType(DepartureSearch),
          matching: find.text('Aucun lieu ni aucune commune ne correspond à « zzqx ».'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ma position'), findsOneWidget, reason: 'the way back stays');
    });
  });

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    testWidgets('on a $name, a house number comes under the places and opens with its source', (
      tester,
    ) async {
      final online = _online();
      final app = await pumpLunaway(tester, size: size, places: const [], online: online);
      await tester.enterText(find.byType(TextField).first, 'avenue');
      await settleShort(tester);
      expect(find.text('Adresses'), findsOneWidget);
      expect(find.text('20 Avenue de Ségur'), findsOneWidget);
      expect(
        find.textContaining('75007 Paris, 75, Paris, Île-de-France'),
        findsOneWidget,
        reason: 'the postcode, the town and the area tell it apart',
      );
      expect(find.text('Adresses : Base Adresse Nationale, IGN Géoplateforme'), findsOneWidget);
      expect(online.requests.where((r) => r.contains('avenue')), [
        'searchAll:avenue',
      ], reason: 'one request for the places and the addresses');
      expect(online.languages.last, 'fr', reason: "the places abroad in the reader's language");

      await tester.tap(find.text('20 Avenue de Ségur'));
      await settleShort(tester);
      expect(
        app.container(tester).read(selectionProvider),
        const PointSelection(LatLng(48.850699, 2.308628), address: _segur),
      );
      expect(app.map.moves.last, (center: _segur.position, zoom: 17.0));
      expect(app.map.lastProps!.markedPoint, _segur.position, reason: 'a pin marks it');
      expect(find.text('20 Avenue de Ségur'), findsWidgets, reason: 'the details name it');
      expect(find.text('Source : Base Adresse Nationale, IGN Géoplateforme'), findsOneWidget);
      expect(
        find.textContaining('Itinéraire'),
        findsWidgets,
        reason: 'the way there, as for any point',
      );

      await tester.ensureVisible(find.text('Les lieux autour'));
      await tester.tap(find.text('Les lieux autour'));
      await settleShort(tester);
      expect(app.map.moves.last, (
        center: _segur.position,
        zoom: 12.0,
      ), reason: 'the map steps back to the places around it');
      expect(
        app.container(tester).read(selectionProvider),
        isNull,
        reason: 'the card gives way to the places around it',
      );
    });
  }

  testWidgets('a device that holds its places asks the addresses alone, once typing pauses', (
    tester,
  ) async {
    final online = _online();
    await pumpLunaway(tester, online: online);
    await tester.enterText(find.byType(TextField).first, 'ann');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField).first, 'anne');
    await settleShort(tester);
    expect(find.text('Communes'), findsOneWidget, reason: 'the towns the device holds');
    expect(find.text('Annecystraße'), findsOneWidget);
    expect(
      find.text('Annecy'),
      findsOneWidget,
      reason: 'the town of the places only, not again among the addresses',
    );
    expect(online.requests.where((r) => r.startsWith('searchAll:')), isEmpty);
    expect(online.requests.where((r) => r.startsWith('addresses:')), [
      'addresses:anne',
    ], reason: 'the pause before asking spares the letters typed past');
  });

  testWidgets('a search typed past is cancelled on its way', (tester) async {
    final online = _online()..holdSearches = Completer<void>();
    await pumpLunaway(tester, online: online);
    await tester.enterText(find.byType(TextField).first, 'segur');
    await settleShort(tester);
    expect(online.requests, contains('addresses:segur'));
    await tester.enterText(find.byType(TextField).first, 'segurane');
    await settleShort(tester);
    expect(online.aborted, ['segur']);
    online.holdSearches!.complete();
    await settleShort(tester);
  });

  testWidgets('offline the places and towns the device holds answer, and no address is asked', (
    tester,
  ) async {
    // No API behind the places: the device is offline.
    await pumpLunaway(tester);
    await tester.enterText(find.byType(TextField).first, 'ann');
    await settleShort(tester);
    expect(find.text('Annecy'), findsOneWidget);
    expect(find.text('Adresses'), findsNothing);
    expect(find.text('Recherche des adresses'), findsNothing);
    expect(find.text("Les adresses n'ont pas pu être cherchées pour l'instant."), findsNothing);
  });

  testWidgets('a failed address search leaves the places and towns, and says so', (tester) async {
    final online = _online()..offline = true;
    await pumpLunaway(tester, online: online);
    await tester.enterText(find.byType(TextField).first, 'ann');
    await settleShort(tester);
    expect(find.text('Annecy'), findsOneWidget);
    expect(find.text('Annecystraße'), findsNothing);
    expect(find.text("Les adresses n'ont pas pu être cherchées pour l'instant."), findsOneWidget);
  });

  testWidgets('nothing found anywhere says so once the addresses are in, not before', (
    tester,
  ) async {
    final online = _online()..holdSearches = Completer<void>();
    await pumpLunaway(tester, online: online);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await settleShort(tester);
    expect(find.text('Recherche des adresses'), findsOneWidget);
    expect(
      find.text('Aucun lieu ni aucune commune ne correspond à « zzz ».'),
      findsNothing,
      reason: 'the addresses may still find something',
    );
    online.holdSearches!.complete();
    await settleShort(tester);
    expect(find.text('Recherche des adresses'), findsNothing);
    expect(find.text('Aucun lieu ni aucune commune ne correspond à « zzz ».'), findsOneWidget);
  });

  testWidgets('addresses found without a place or a town are not told that nothing matched', (
    tester,
  ) async {
    // "Aucun lieu ni aucune commune ne correspond" stood above the
    // address of Via del Corso in Rome.
    await pumpLunaway(tester, online: _online());
    await tester.enterText(find.byType(TextField).first, 'avenue');
    await settleShort(tester);
    expect(find.text('20 Avenue de Ségur'), findsOneWidget);
    expect(find.textContaining('ne correspond'), findsNothing);
  });

  final many = [
    for (var i = 0; i < 30; i++)
      Place(
        id: 'many-$i',
        name: 'Parking des Pins $i',
        kind: PlaceKind.parking,
        lat: 45 + i * 0.01,
        lon: 6,
        overnight: OvernightStatus.unknown,
        updatedAt: DateTime.utc(2026, 10, 2),
      ),
  ];
  Finder resultsList() =>
      find.ancestor(of: find.text('Lieux'), matching: find.byType(ListView)).first;

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    testWidgets('on a $name, a long list of results takes the room down to the foot', (
      tester,
    ) async {
      await pumpLunaway(tester, size: size, places: const [], online: FakeOnlinePlaces(many));
      await tester.enterText(find.byType(TextField).first, 'parking');
      await settleShort(tester);
      final bottom = tester.getBottomLeft(resultsList()).dy;
      expect(
        tester.getSize(resultsList()).height,
        greaterThan(size.height * 0.6),
        reason: 'the list stopped at 55 % of the window with the keyboard closed',
      );
      expect(bottom, lessThanOrEqualTo(size.height), reason: 'and never runs past the window');
      expect(tester.takeException(), isNull, reason: 'nothing overflows the pane');
    });
  }

  testWidgets("on a desktop with a system bar, the list ends above it and the pane's foot", (
    tester,
  ) async {
    await pumpLunaway(
      tester,
      size: desktop,
      viewPadding: const FakeViewPadding(bottom: 48),
      places: const [],
      online: FakeOnlinePlaces(many),
    );
    await tester.enterText(find.byType(TextField).first, 'parking');
    await settleShort(tester);
    expect(tester.getBottomLeft(resultsList()).dy, lessThanOrEqualTo(desktop.height - 48));
    expect(tester.takeException(), isNull, reason: 'the SafeArea of the pane is not overflowed');
  });

  testWidgets('clearing a long search in the pane brings the list back without overflow', (
    tester,
  ) async {
    await pumpLunaway(tester, size: desktop, places: const [], online: FakeOnlinePlaces(many));
    await tester.enterText(find.byType(TextField).first, 'parking');
    await settleShort(tester);
    await tester.tap(find.byTooltip('Effacer la recherche'));
    // Frame by frame: a collapse in steps overflowed the pane on its way.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Lieux'), findsNothing);
  });

  testWidgets('the pane hides its list under a search, out of focus, and keeps its scroll', (
    tester,
  ) async {
    await pumpLunaway(tester, size: desktop, places: many);
    await settleShort(tester);
    final scrollable = find
        .descendant(
          of: find.byType(NearbyList, skipOffstage: false),
          matching: find.byType(Scrollable),
          skipOffstage: false,
        )
        .first;
    ScrollPosition position() => tester.state<ScrollableState>(scrollable).position;
    await tester.drag(scrollable, const Offset(0, -400));
    await settleShort(tester);
    final scrolled = position().pixels;
    expect(scrolled, greaterThan(0), reason: 'the list scrolls');
    await tester.enterText(find.byType(TextField).first, 'parking');
    await settleShort(tester);
    expect(
      find.byType(NearbyList).hitTestable(),
      findsNothing,
      reason: 'the results cover the pane',
    );
    expect(
      find.ancestor(
        of: find.byType(NearbyList, skipOffstage: false),
        matching: find.byWidgetPredicate(
          (w) => w is ExcludeFocus && w.excluding,
          skipOffstage: false,
        ),
      ),
      findsOneWidget,
      reason: 'a Tab past the results never lands on a hidden place',
    );
    await tester.tap(find.byTooltip('Effacer la recherche'));
    await settleShort(tester);
    expect(find.byType(NearbyList).hitTestable(), findsOneWidget, reason: 'the list is back');
    expect(position().pixels, scrolled, reason: 'where the user had scrolled it');
  });

  testWidgets('the web lists the towns of the API with every place they hold, homonyms apart', (
    tester,
  ) async {
    Place inTown(int i, String postcode, LatLng at) => Place(
      id: 'town-$postcode-$i',
      name: 'Parking $i',
      kind: PlaceKind.parking,
      lat: at.lat + i * 0.001,
      lon: at.lon,
      overnight: OvernightStatus.unknown,
      address: Address(postcode: postcode, city: 'Viviers', countryCode: 'FR'),
      updatedAt: DateTime.utc(2026, 10, 2),
    );
    // More places in Viviers than a page of results holds.
    final online = FakeOnlinePlaces([
      for (var i = 0; i < 25; i++) inTown(i, '07220', const LatLng(44.48, 4.68)),
      for (var i = 0; i < 2; i++) inTown(i, '89700', const LatLng(47.9, 4)),
    ]);
    await pumpLunaway(tester, size: desktop, places: const [], online: online);
    await tester.enterText(find.byType(TextField).first, 'viviers');
    await settleShort(tester);
    expect(find.text('Communes'), findsOneWidget);
    expect(find.text('07220 · Ardèche · 25 lieux'), findsOneWidget);
    expect(find.text('89700 · Yonne · 2 lieux'), findsOneWidget);
  });

  testWidgets('addresses that take too long are given up', (tester) async {
    final online = _online()..holdSearches = Completer<void>();
    await pumpLunaway(tester, online: online);
    await tester.enterText(find.byType(TextField).first, 'segur');
    await settleShort(tester, addressWait + const Duration(seconds: 1));
    expect(online.aborted, ['segur']);
    expect(find.text("Les adresses n'ont pas pu être cherchées pour l'instant."), findsOneWidget);
    online.holdSearches!.complete();
    await settleShort(tester);
  });

  test('a town the list shows is not an address again, unless it lies in another department', () {
    const towns = [
      Municipality(name: 'Annecy', postcode: '74000', center: LatLng(45.9, 6.1), placeCount: 3),
    ];
    AddressMatch annecy(String postcode) => AddressMatch(
      kind: AddressKind.town,
      name: 'Annecy',
      postcode: postcode,
      position: const LatLng(0, 0),
      sourceId: 'ban',
      attribution: '',
    );
    final elsewhere = annecy('99999');
    expect(withoutShownTowns([_annecyTown, annecy('74940'), _munich, elsewhere], towns), [
      _munich,
      elsewhere,
    ], reason: 'Annecy 74940 is the Annecy listed with 74000; 99999 is another department');
  });
}
