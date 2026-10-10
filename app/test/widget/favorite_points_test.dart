import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fakes.dart';
import '../helpers/poi_fakes.dart';
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

const _spot = LatLng(45.7701, 4.8402);

/// A saved address with the name and note the user gave it.
SavedPoint _chezPaul({String name = 'Chez Paul'}) => SavedPoint(
  id: savedPointIdAt(_segur.position),
  kind: SavedPointKind.address,
  name: name,
  position: _segur.position,
  note: 'Portail vert',
  address: '20 Avenue de Ségur, 75007 Paris',
);

Finder _inBar(String text) =>
    find.descendant(of: find.byType(PointActionBar), matching: find.text(text));

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settleShort(tester);
}

/// A tap on bare map at street level, then the time the map waits for a
/// second tap: the card "Ici" opens.
Future<void> _tapBare(TestApp app, WidgetTester tester) async {
  app.map.lastProps!.onEmptyTap!(_spot, 15);
  await tester.pump(const Duration(milliseconds: 300));
  await settleShort(tester);
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    group(name, () {
      testWidgets('an address of the search is saved in one gesture, under its name, '
          'and marked on the map', (tester) async {
        final online = FakeOnlinePlaces(samplePlaces)..addresses.add(_segur);
        final app = await pumpLunaway(tester, size: size, places: const [], online: online);
        await tester.enterText(find.byType(TextField).first, 'avenue');
        await settleShort(tester);
        await tester.tap(find.text('20 Avenue de Ségur'));
        await settleShort(tester);

        final save = _inBar('Enregistrer');
        expect(save, findsOneWidget, reason: 'beside the way there, as on a place');
        final screen = Offset.zero & size;
        expect(
          screen.contains(tester.getRect(save).center),
          isTrue,
          reason: 'in reach without scrolling the card',
        );
        await tester.tap(save);
        await settleShort(tester);

        final saved = app.favorites.points.single;
        expect(saved.listId, 1, reason: 'in Mes favoris');
        expect(
          (saved.point.kind, saved.point.name, saved.point.address),
          (SavedPointKind.address, '20 Avenue de Ségur', '20 Avenue de Ségur, 75007 Paris'),
        );
        expect(saved.point.position, _segur.position);
        expect(find.text('Ajouté à Mes favoris'), findsOneWidget);
        expect(_inBar('Enregistré'), findsOneWidget);
        expect(find.text('Dans vos favoris'), findsOneWidget, reason: 'the card says so');
        expect(app.map.lastProps!.savedPoints, [
          SavedMark(saved.point.id, _segur.position),
        ], reason: 'the map marks it, the default list being the one shown');
      });

      testWidgets('the favourites list a saved point by its name, and its row opens its card', (
        tester,
      ) async {
        final app = await pumpLunaway(tester, size: size);
        await app.favorites.addPointToDefault(_chezPaul());
        await _openTab(tester, 'Favoris');
        expect(find.text('Chez Paul'), findsOneWidget);
        expect(find.text('Adresse · 20 Avenue de Ségur, 75007 Paris'), findsOneWidget);
        expect(find.text('Portail vert'), findsOneWidget);
        expect(find.text('1 favori'), findsWidgets, reason: 'the list counts it');

        await tester.tap(find.text('Chez Paul'));
        await settleShort(tester);
        expect(
          app.container(tester).read(selectionProvider),
          const PointSelection(LatLng(48.850699, 2.308628)),
        );
        expect(app.map.moves.last, (center: _segur.position, zoom: 16.0));
        final details = find.byType(PointDetails);
        expect(find.descendant(of: details, matching: find.text('Chez Paul')), findsOneWidget);
        expect(
          find.descendant(of: details, matching: find.text('20 Avenue de Ségur, 75007 Paris')),
          findsOneWidget,
        );
        expect(find.descendant(of: details, matching: find.text('Portail vert')), findsOneWidget);
        expect(find.descendant(of: details, matching: find.text('Renommer')), findsOneWidget);
        expect(
          find.descendant(of: details, matching: find.text('Retirer des favoris')),
          findsOneWidget,
        );
        expect(find.text("Itinéraire jusqu'ici"), findsOneWidget);
        expect(find.text("Partir d'ici"), findsOneWidget);
        expect(_inBar('Copier'), findsOneWidget);
      });
    });
  }

  testWidgets('a bare point is saved as the point of the day, offline as well', (tester) async {
    final app = await pumpLunaway(tester, reachable: false);
    await _tapBare(app, tester);
    await tester.tap(_inBar('Enregistrer'));
    await settleShort(tester);
    final saved = app.favorites.points.single.point;
    expect(
      (saved.kind, saved.name, saved.position),
      (SavedPointKind.point, 'Point du 6 oct.', _spot),
    );
    expect(saved.id, savedPointIdAt(_spot));
    expect(find.text('Point du 6 oct.'), findsWidgets, reason: 'the card takes its name');
  });

  testWidgets('a second tap takes it out of Mes favoris, with an undo', (tester) async {
    final app = await pumpLunaway(tester);
    await _tapBare(app, tester);
    await tester.tap(_inBar('Enregistrer'));
    await settleShort(tester);
    await tester.tap(_inBar('Enregistré'));
    await settleShort(tester);
    expect(app.favorites.points, isEmpty);
    expect(find.text('Retiré de Mes favoris'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(app.favorites.points, hasLength(1));
  });

  testWidgets('a long press on Save gives the name, the note and the lists', (tester) async {
    final app = await pumpLunaway(tester);
    final trip = await app.favorites.createList('Bretagne');
    await _tapBare(app, tester);
    await tester.longPress(_inBar('Enregistrer'));
    await settleShort(tester);
    expect(find.text('Enregistrer dans une liste'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('point-name'))).controller!.text,
      'Point du 6 oct.',
      reason: 'the name proposed',
    );
    await tester.enterText(find.byKey(const Key('point-name')), 'Aire du lac');
    await tester.enterText(find.byKey(const Key('point-note')), 'Calme la nuit');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Bretagne'));
    await settleShort(tester);
    final inTrip = app.favorites.points.single;
    expect(
      (inTrip.listId, inTrip.point.name, inTrip.point.note),
      (trip, 'Aire du lac', 'Calme la nuit'),
    );
    // Then a name changed again, and the sheet closed by "Terminé".
    await tester.enterText(find.byKey(const Key('point-name')), 'Aire du lac bleu');
    await tester.tap(find.text('Terminé'));
    await settleShort(tester);
    expect(app.favorites.points.single.point.name, 'Aire du lac bleu');
  });

  testWidgets('Rename on the card names the point in every list', (tester) async {
    final app = await pumpLunaway(tester);
    final trip = await app.favorites.createList('Paris');
    await app.favorites.addPointToDefault(_chezPaul());
    await app.favorites.addPoint(trip, _chezPaul());
    app.container(tester).read(mapFlowProvider.notifier).select(PointSelection(_segur.position));
    await settleShort(tester);
    await tester.tap(find.text('Renommer'));
    await settleShort(tester);
    final field = find.byKey(const Key('point-name'));
    final selected = tester.widget<TextField>(field).controller!.selection;
    expect((selected.start, selected.end), (0, 'Chez Paul'.length), reason: 'ready to retype');
    await tester.enterText(field, 'Chez Paul et Lise');
    await tester.tap(find.text('Terminé'));
    await settleShort(tester);
    expect(app.favorites.points.map((e) => e.point.name), [
      'Chez Paul et Lise',
      'Chez Paul et Lise',
    ]);
  });

  testWidgets('Remove on the card takes it out of every list, and Undo brings it back', (
    tester,
  ) async {
    final app = await pumpLunaway(tester);
    final trip = await app.favorites.createList('Paris');
    await app.favorites.addPointToDefault(_chezPaul());
    await app.favorites.addPoint(trip, _chezPaul());
    app.container(tester).read(mapFlowProvider.notifier).select(PointSelection(_segur.position));
    await settleShort(tester);
    await tester.ensureVisible(find.text('Retirer des favoris'));
    await tester.tap(find.text('Retirer des favoris'));
    await settleShort(tester);
    expect(app.favorites.points, isEmpty);
    expect(find.text('Retiré des favoris'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing, reason: 'no question asked');
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(app.favorites.points.map((e) => e.listId).toSet(), {1, trip});
  });

  testWidgets('a shop is saved from its page and opens it again from the favourites', (
    tester,
  ) async {
    final app = await pumpLunaway(tester, size: tablet);
    final bakery = poiFromJson(bakeryJson)!.feature;
    app.map.lastProps!.onPoiTap!(bakery);
    await settleShort(tester);
    await tester.tap(_inBar('Enregistrer'));
    await settleShort(tester);
    final saved = app.favorites.points.single.point;
    expect(
      (saved.kind, saved.name, saved.poiId, saved.poiKind),
      (SavedPointKind.poi, 'Boulangerie du Lac', bakery.id, bakery.kind),
    );

    app.container(tester).read(mapFlowProvider.notifier).select(null);
    await _openTab(tester, 'Favoris');
    expect(find.text('Boulangerie du Lac'), findsOneWidget);
    await tester.tap(find.text('Boulangerie du Lac'));
    await settleShort(tester);
    final selection = app.container(tester).read(selectionProvider);
    expect(selection, isA<PoiSelection>());
    expect((selection! as PoiSelection).feature.id, bakery.id);
    expect(find.text('Dans vos favoris'), findsOneWidget);
    // As any saved point, a place to set out from.
    await tester.ensureVisible(find.text("Partir d'ici"));
    await tester.tap(find.text("Partir d'ici"));
    await settleShort(tester);
    final start = app.container(tester).read(chosenDepartureProvider);
    expect((start?.position, start?.label), (bakery.position, 'Boulangerie du Lac'));
  });

  testWidgets('a name typed in the sheet of a point in no list saves it with "Done"', (
    tester,
  ) async {
    final app = await pumpLunaway(tester);
    await _tapBare(app, tester);
    await tester.longPress(_inBar('Enregistrer'));
    await settleShort(tester);
    await tester.enterText(find.byKey(const Key('point-name')), 'Aire du lac');
    await tester.tap(find.text('Terminé'));
    await settleShort(tester);
    final saved = app.favorites.points.single;
    expect((saved.listId, saved.point.name), (1, 'Aire du lac'), reason: 'in Mes favoris');
  });

  testWidgets('the map marks the points of the list the favourites show; a tap opens one', (
    tester,
  ) async {
    final app = await pumpLunaway(tester);
    final trip = await app.favorites.createList('Bretagne');
    await app.favorites.addPointToDefault(_chezPaul());
    final phare = SavedPoint(
      id: savedPointIdAt(const LatLng(48.36, -4.77)),
      kind: SavedPointKind.point,
      name: 'Phare',
      position: const LatLng(48.36, -4.77),
    );
    await app.favorites.addPoint(trip, phare);
    await settleShort(tester);
    expect(app.map.lastProps!.savedPoints, [SavedMark(_chezPaul().id, _segur.position)]);

    await _openTab(tester, 'Favoris');
    await tester.tap(find.text('Bretagne').first);
    await settleShort(tester);
    await _openTab(tester, 'Carte');
    expect(app.container(tester).read(selectedFavoriteListProvider), trip);
    expect(app.map.lastProps!.savedPoints, [SavedMark(phare.id, phare.position)]);

    app.map.lastProps!.onSavedPointTap!(phare.id);
    await settleShort(tester);
    expect(app.container(tester).read(selectionProvider), PointSelection(phare.position));
    expect(find.text('Phare'), findsWidgets);
  });

  testWidgets('a saved point opened from the favourites is named from its first frame', (
    tester,
  ) async {
    final app = await pumpLunaway(tester);
    final point = _chezPaul();
    await app.favorites.addPointToDefault(point);
    app.container(tester).read(mapFlowProvider.notifier).select(selectionOfSaved(point));
    await tester.pump();
    final details = find.byType(PointDetails);
    expect(find.descendant(of: details, matching: find.text('Chez Paul')), findsOneWidget);
    expect(find.descendant(of: details, matching: find.text('Ici')), findsNothing);
    expect(find.descendant(of: details, matching: find.text('Renommer')), findsOneWidget);
  });

  testWidgets('in a tablet panel, Rename and Remove stay side by side on one line', (tester) async {
    final app = await pumpLunaway(tester, size: const Size(768, 1024));
    await app.favorites.addPointToDefault(_chezPaul());
    app.container(tester).read(mapFlowProvider.notifier).select(PointSelection(_segur.position));
    await settleShort(tester);
    expect(
      tester.getCenter(find.text('Retirer des favoris')).dy,
      tester.getCenter(find.text('Renommer')).dy,
    );
  });

  testWidgets("a town of the search's list is saved from its row", (tester) async {
    final app = await pumpLunaway(tester);
    await tester.enterText(find.byType(TextField).first, 'Annecy');
    await settleShort(tester);
    final row = find.widgetWithText(ListTile, 'Annecy').first;
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('Enregistrer')));
    await settleShort(tester);
    final saved = app.favorites.points.single;
    expect(saved.listId, 1, reason: 'in Mes favoris');
    expect((saved.point.kind, saved.point.name), (SavedPointKind.town, 'Annecy'));
    expect(find.text('Ajouté à Mes favoris'), findsOneWidget);
  });

  testWidgets("a long press or a right click on a town's heart opens its name and lists", (
    tester,
  ) async {
    await pumpLunaway(tester);
    await tester.enterText(find.byType(TextField).first, 'Annecy');
    await settleShort(tester);
    final heart = find.descendant(
      of: find.widgetWithText(ListTile, 'Annecy').first,
      matching: find.byTooltip('Enregistrer'),
    );
    await tester.longPress(heart);
    await settleShort(tester);
    expect(find.text('Enregistrer dans une liste'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await settleShort(tester);
    await tester.tap(heart, buttons: kSecondaryButton);
    await settleShort(tester);
    expect(find.text('Enregistrer dans une liste'), findsOneWidget);
  });

  testWidgets('deleting a list says the points saved in it go with it', (tester) async {
    final app = await pumpLunaway(tester);
    final trip = await app.favorites.createList('Bretagne');
    await app.favorites.addPoint(trip, _chezPaul());
    await _openTab(tester, 'Favoris');
    await tester.tap(find.text('Bretagne').first);
    await settleShort(tester);
    await tester.tap(find.byTooltip('Options de la liste'));
    await settleShort(tester);
    await tester.tap(find.text('Supprimer la liste'));
    await settleShort(tester);
    expect(
      find.text(
        'Supprimer « Bretagne » ? Les lieux restent sur la carte. '
        'Le point enregistré dans cette liste part avec elle.',
      ),
      findsOneWidget,
    );
  });
}
