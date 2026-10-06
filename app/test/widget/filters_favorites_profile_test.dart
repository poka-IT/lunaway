import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/filters_sheet.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// A phone tall enough to show the whole profile above the dock.
const tallPhone = Size(400, 3200);

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settleShort(tester);
}

/// Scrolls the profile until [finder] is built and clear of the dock.
Future<void> showInProfile(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  group('filters', () {
    testWidgets('the sheet counts the places before applying, and applying remembers', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      expect(find.text('Afficher 5 lieux'), findsOneWidget);
      // The family card, before the services section of the same name (the
      // map's "Services" chip of the shops and services stays behind).
      await tester.tap(
        find.descendant(of: find.byType(FiltersPanel), matching: find.text('Services')).first,
      );
      await settleShort(tester);
      expect(find.text('Afficher 1 lieu'), findsOneWidget);
      await tester.tap(find.text('Nuit autorisée').last);
      await settleShort(tester);
      expect(find.text('Aucun lieu ne correspond'), findsOneWidget);
      await tester.tap(find.text('Tout effacer'));
      await settleShort(tester);
      expect(find.text('Afficher 5 lieux'), findsOneWidget);
      await tester.tap(find.text('Campings et accueils'));
      await settleShort(tester);
      await tester.tap(find.text('Afficher 1 lieu'));
      await settleShort(tester);
      expect(app.settings.value.filter, const PlaceFilter(families: {KindFamily.campsites}));
      expect(find.text('1 lieu ici'), findsOneWidget);
      // The chip on the map counts the active filters.
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Filtres, 1 filtre actif'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the sticky button never covers the last filters', (tester) async {
      await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      await tester.scrollUntilVisible(
        find.text('Mon véhicule passe').last,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await settleShort(tester);
      final button = tester.getRect(find.text('Afficher 5 lieux'));
      final last = tester.getRect(find.text('Mon véhicule passe').last);
      expect(last.bottom, lessThan(button.top), reason: 'the list ends above the button');
    });

    testWidgets('on a wide screen the filters open in a dialog', (tester) async {
      await pumpLunaway(tester, size: desktop);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      expect(find.byType(Dialog), findsOneWidget);
    });
  });

  group('my vehicle', () {
    testWidgets('"my vehicle fits" asks the height once, then hides the lower barriers', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.ensureVisible(find.text('Mon véhicule passe'));
      await tester.tap(find.text('Mon véhicule passe'));
      await settleShort(tester);
      // The editor explains why it asks, with the typical van filled in.
      expect(find.textContaining('indiquez au moins sa hauteur'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Hauteur'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Hauteur'), '2,40');
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      final vehicle = app.container(tester).read(vehicleProvider).value;
      expect(vehicle?.heightM, 2.4);
      expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      // The day car park under a 2.10 m barrier is gone; unknown heights stay.
      expect(find.text('4 lieux ici'), findsOneWidget);
      expect(app.map.lastProps!.places.map((p) => p.id), isNot(contains(dayParking.id)));
      expect(find.text('Passe à 2,40 m'), findsOneWidget);
    });

    testWidgets('a height out of range is refused with the range', (tester) async {
      final app = await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Décrire mon véhicule'));
      await tester.tap(find.text('Décrire mon véhicule'));
      await settleShort(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Hauteur'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Hauteur'), '29');
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      expect(find.textContaining('Entre'), findsOneWidget);
      expect(app.container(tester).read(vehicleProvider).value, isNull);
    });

    testWidgets('its fuel, consumption and LPG heating are kept with it for the prices', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Décrire mon véhicule'));
      await tester.tap(find.text('Décrire mon véhicule'));
      await settleShort(tester);
      final scroll = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Gazole'),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Gazole'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Consommation'),
        200,
        scrollable: scroll,
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Consommation'), '11,5');
      await tester.scrollUntilVisible(find.text('Chauffage au GPL'), 200, scrollable: scroll);
      await tester.tap(find.text('Chauffage au GPL'));
      await tester.pump();
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      expect(
        app.container(tester).read(vehicleFuelProvider),
        const VehicleFuel(fuel: FuelType.diesel, consumptionL100: 11.5, lpgHeating: true),
      );
    });

    testWidgets('the profile shows the vehicle described, its type and size', (tester) async {
      final app = await pumpLunaway(tester);
      await app
          .container(tester)
          .read(vehicleRepositoryProvider)
          .save(Vehicle.typical(VehicleType.van));
      await openTab(tester, 'Profil');
      expect(find.text('Van'), findsOneWidget);
      expect(find.textContaining('H 2,00 m'), findsOneWidget);
    });
  });

  group('favourites', () {
    testWidgets('empty, the screen says how to save a place', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Favoris');
      expect(find.text("Rien d'enregistré ici pour l'instant"), findsOneWidget);
      expect(find.textContaining('Touchez Enregistrer sur un lieu'), findsOneWidget);
    });

    testWidgets('a swiped place leaves at once and comes back with undo', (tester) async {
      final app = await pumpLunaway(tester);
      await app.favorites.addToDefault(campsite.summary);
      await openTab(tester, 'Favoris');
      expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
      await tester.drag(find.text('Camping des Peupliers (démo)'), const Offset(-500, 0));
      await settleShort(tester);
      expect(find.text('Camping des Peupliers (démo)'), findsNothing);
      expect(app.favorites.entries, isEmpty);
      expect(find.text('Retiré de la liste'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(app.favorites.entries.single.placeId, campsite.id);
      expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
    });

    testWidgets('a place swiped out of one list still shows in the others', (tester) async {
      final app = await pumpLunaway(tester);
      final trip = await app.favorites.createList('Bretagne 2027');
      await app.favorites.add(trip, campsite.summary);
      await app.favorites.addToDefault(campsite.summary);
      await openTab(tester, 'Favoris');
      await tester.drag(find.text('Camping des Peupliers (démo)'), const Offset(-500, 0));
      await settleShort(tester);
      expect(find.text('Camping des Peupliers (démo)'), findsNothing);
      await tester.tap(find.text('Bretagne 2027').first);
      await settleShort(tester);
      expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
    });

    testWidgets('a place swiped out and saved again from the map shows again', (tester) async {
      final app = await pumpLunaway(tester);
      await app.favorites.addToDefault(campsite.summary);
      await openTab(tester, 'Favoris');
      await tester.drag(find.text('Camping des Peupliers (démo)'), const Offset(-500, 0));
      await settleShort(tester);
      expect(find.text('Camping des Peupliers (démo)'), findsNothing);
      await app.favorites.addToDefault(campsite.summary);
      await settleShort(tester);
      expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
    });

    testWidgets('a removal that fails puts the row back and says so', (tester) async {
      final app = await pumpLunaway(tester);
      await app.favorites.addToDefault(campsite.summary);
      await openTab(tester, 'Favoris');
      app.favorites.failWrites = true;
      await tester.drag(find.text('Camping des Peupliers (démo)'), const Offset(-500, 0));
      await settleShort(tester);
      expect(find.text("La modification n'a pas pu être enregistrée."), findsOneWidget);
      expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
    });

    testWidgets('a saved place opens on the map from its row', (tester) async {
      final app = await pumpLunaway(tester);
      await app.favorites.addToDefault(campsite.summary);
      await openTab(tester, 'Favoris');
      await tester.tap(find.text('Camping des Peupliers (démo)'));
      await settleShort(tester);
      expect(app.container(tester).read(selectionProvider), PlaceSelection(campsite.id));
      expect(app.map.moves.last.center, campsite.position);
      expect(find.text('Nuit autorisée'), findsWidgets, reason: 'with the place open in its sheet');
    });

    testWidgets('the row menu removes a place without a swipe', (tester) async {
      final app = await pumpLunaway(tester);
      await app.favorites.addToDefault(lakeArea.summary);
      await openTab(tester, 'Favoris');
      await tester.tap(find.byTooltip('Options du lieu'));
      await settleShort(tester);
      await tester.tap(find.text('Retirer de la liste'));
      await settleShort(tester);
      expect(app.favorites.entries, isEmpty);
    });

    testWidgets('a new list can be created and becomes the shown one', (tester) async {
      final app = await pumpLunaway(tester);
      await openTab(tester, 'Favoris');
      await tester.tap(find.text('Nouvelle liste'));
      await settleShort(tester);
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Bretagne 2027',
      );
      await tester.tap(find.text('Enregistrer'));
      await settleShort(tester);
      final semantics = tester.ensureSemantics();
      // The card of the new list: its name and its count, selected.
      final card = find.bySemanticsLabel(RegExp(r'^Bretagne 2027\s+Vide$'));
      expect(card, findsOneWidget);
      expect(tester.getSemantics(card), isSemantics(isSelected: true));
      semantics.dispose();
      expect(app.favorites.entries, isEmpty);
    });

    testWidgets('"New list" stays whole at a large text size', (tester) async {
      await pumpLunaway(tester, textScale: 2);
      await openTab(tester, 'Favoris');
      final label = tester.renderObject<RenderParagraph>(find.text('Nouvelle liste'));
      expect(label.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a desktop the lists sit beside the places', (tester) async {
      final app = await pumpLunaway(tester, size: desktop);
      await app.favorites.addToDefault(lakeArea.summary);
      await openTab(tester, 'Favoris');
      expect(find.text('Mes favoris'), findsWidgets);
      expect(find.text('1 lieu'), findsOneWidget);
      expect(find.text('Aire du Lac Bleu (démo)'), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('switching the language translates the app and is remembered', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      await tester.tap(find.text('English'));
      await settleShort(tester);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Offline data'), findsOneWidget);
      expect(app.settings.value.localeCode, 'en');
      await tester.tap(find.text('Français'));
      await settleShort(tester);
      expect(find.text('Carte'), findsOneWidget);
    });

    testWidgets('the language follows the device until the user picks one', (tester) async {
      await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(find.text('Appareil')), isSemantics(isSelected: true));
      semantics.dispose();
    });

    testWidgets('the appearance switches to dark and is remembered', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      await tester.tap(find.text('Sombre'));
      await settleShort(tester);
      expect(app.settings.value.theme, ThemePreference.dark);
      expect(Theme.of(tester.element(find.text('Sombre'))).brightness, Brightness.dark);
      expect(find.text('Toujours sombre, doux pour les yeux la nuit.'), findsOneWidget);
    });

    testWidgets('the offline data panel tells the count, the size and the age', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('5 lieux sur cet appareil'));
      expect(find.text('5 lieux sur cet appareil'), findsOneWidget);
      expect(find.text('Espace utilisé : 3,3 Mo'), findsOneWidget);
      expect(find.text("Dernière mise à jour aujourd'hui"), findsOneWidget);
    });

    testWidgets('an interrupted first download says the data is incomplete, with a way on', (
      tester,
    ) async {
      await pumpLunaway(
        tester,
        sync: const SyncState(cursor: '600', fullSync: true, running: true),
      );
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Téléchargement incomplet'));
      expect(find.text('Téléchargement incomplet'), findsOneWidget);
      expect(find.text('Reprendre'), findsOneWidget);
    });

    testWidgets('update now asks the server for the changes', (tester) async {
      final source = FakeChangesSource(const []);
      await pumpLunaway(
        tester,
        syncService: SyncService(source: source, store: MemorySyncStore()),
      );
      await openTab(tester, 'Profil');
      expect(source.requests, 0, reason: 'a sync an hour old is fresh enough at start');
      await tester.scrollUntilVisible(
        find.text('Mettre à jour'),
        200,
        scrollable: find
            .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
            .first,
      );
      // The last jump of the scroll lays out on the next frame.
      await tester.pump();
      await tester.tap(find.text('Mettre à jour'));
      await settleShort(tester);
      expect(source.requests, 1);
    });

    testWidgets('the about section links the website, the privacy policy and the source code', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      for (final label in ['Site web', 'Confidentialité', 'Code source']) {
        await tester.tap(find.text(label));
        await settleShort(tester);
      }
      expect(app.external.opened.map((u) => u.toString()), [
        'https://lunaway.net',
        'https://lunaway.net/privacy',
        'https://github.com/poka-IT/lunaway',
      ]);
    });

    testWidgets('the attributions credit OpenStreetMap and the basemap', (tester) async {
      await pumpLunaway(tester, size: const Size(1280, 3200), locale: AppLocale.en);
      await openTab(tester, 'Profile');
      expect(find.text('Places and map data © OpenStreetMap contributors.'), findsOneWidget);
      expect(find.textContaining('styles derived from Protomaps'), findsOneWidget);
      expect(find.textContaining('OpenFreeMap'), findsNothing);
    });
  });
}
