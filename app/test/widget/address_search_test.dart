import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
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
        isA<PointSelection>(),
        reason: 'the address stays marked',
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

  testWidgets('nothing found among the places says so at once, the addresses on their way', (
    tester,
  ) async {
    final online = _online()..holdSearches = Completer<void>();
    await pumpLunaway(tester, online: online);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await settleShort(tester);
    expect(find.text('Aucun lieu ni aucune commune ne correspond à « zzz ».'), findsOneWidget);
    expect(find.text('Recherche des adresses'), findsOneWidget);
    online.holdSearches!.complete();
    await settleShort(tester);
    expect(find.text('Recherche des adresses'), findsNothing);
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

  test('a town the list shows is not an address again, unless its postcode differs', () {
    const towns = [
      Municipality(name: 'Annecy', postcode: '74000', center: LatLng(45.9, 6.1), placeCount: 3),
    ];
    const other = AddressMatch(
      kind: AddressKind.town,
      name: 'Annecy',
      postcode: '99999',
      position: LatLng(0, 0),
      sourceId: 'ban',
      attribution: '',
    );
    expect(withoutShownTowns(const [_annecyTown, _munich, other], towns), [_munich, other]);
  });
}
