import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/filters_sheet.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/poi_fakes.dart';
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

/// The editor's own list: the last scrollable of the screen may be one of
/// its text fields, depending on how far its lazy list has built.
Finder get editorList =>
    find.descendant(of: find.byType(VehicleEditor), matching: find.byType(Scrollable)).first;

/// The chip of "my vehicle fits" in the map's row, by its label.
Finder vehicleChip(String label) =>
    find.descendant(of: find.byType(QuickFilters), matching: find.widgetWithText(MapChip, label));

bool chipOn(WidgetTester tester, String label) =>
    tester.widget<MapChip>(vehicleChip(label)).selected;

void main() {
  group('filters', () {
    testWidgets('the sheet counts the places before applying, and applying remembers', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      expect(find.text('Afficher 5 lieux'), findsOneWidget);
      final list = find
          .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
          .first;
      // The family card, by its hint: below the night, the section named
      // "Services" and the vehicle, it is built once scrolled to.
      final services = find.text('Eau et vidange, pas de nuit sur place');
      await tester.scrollUntilVisible(services, 200, scrollable: list);
      await tester.pump();
      await tester.tap(services);
      await settleShort(tester);
      expect(find.text('Afficher 1 lieu'), findsOneWidget);
      final allowed = find.descendant(
        of: find.byType(FiltersPanel),
        matching: find.text('Nuit autorisée'),
      );
      // The night comes first in the sheet: back to the top of the list. A
      // drag back stops with the chip half under the header, out of reach.
      tester.state<ScrollableState>(list).position.jumpTo(0);
      await tester.pump();
      await tester.tap(allowed);
      await settleShort(tester);
      expect(find.text('Aucun lieu ne correspond'), findsOneWidget);
      await tester.tap(find.text('Tout effacer'));
      await settleShort(tester);
      expect(find.text('Afficher 5 lieux'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Campings et accueils'), 200, scrollable: list);
      await settleShort(tester);
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

    testWidgets('a hint says what each section keeps, before and after a choice', (tester) async {
      await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final list = find
          .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
          .first;
      expect(find.text('Aucun choix : tous les lieux'), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(FiltersPanel), matching: find.text('Nuit autorisée')),
      );
      await settleShort(tester);
      expect(find.text('Aucun choix : tous les lieux'), findsNothing);
      expect(find.text('Seulement les lieux de ces statuts'), findsOneWidget);
      final hint = find.text('Aucun choix : tous les types');
      await tester.scrollUntilVisible(hint, 200, scrollable: list);
      await tester.pump();
      expect(hint, findsOneWidget);
      final family = find.text('Campings et accueils');
      await tester.ensureVisible(family);
      await tester.pump();
      await tester.tap(family);
      await settleShort(tester);
      // The title may sit just above the view once the cards are in it.
      expect(find.text('Aucun choix : tous les types', skipOffstage: false), findsNothing);
      expect(find.text('Seulement ces types', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a minimum rating keeps the places rated as high, and is remembered', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final list = find
          .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
          .first;
      Future<void> choose(String chip) async {
        await tester.ensureVisible(find.text(chip));
        await tester.pump();
        await tester.tap(find.text(chip));
        await settleShort(tester);
      }

      await tester.scrollUntilVisible(find.text('4,5 et plus'), 200, scrollable: list);
      await tester.pump();
      await choose('4 et plus');
      // The lake at 4.3 and the campsite at exactly 4; the car park's 2.9
      // and the places nobody rated are left out.
      expect(find.text('Afficher 2 lieux'), findsOneWidget);
      await choose('4,5 et plus');
      expect(find.text('Aucun lieu ne correspond'), findsOneWidget, reason: 'one step at a time');
      await choose('4,5 et plus');
      expect(find.text('Afficher 5 lieux'), findsOneWidget, reason: 'a second tap clears it');
      await choose('3 et plus');
      await tester.tap(find.text('Afficher 2 lieux'));
      await settleShort(tester);
      expect(app.settings.value.filter, const PlaceFilter(minRating: 3));
      expect(find.text('2 lieux ici'), findsOneWidget);
    });

    testWidgets('each chip answers a finger over 48 dp, drawn as before, 8 apart', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      Rect drawn(String label) => tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
      );
      const labels = [
        'Nuit autorisée',
        'Nuit tolérée',
        'De jour seulement',
        'Nuit interdite',
        'Eau',
        'Toilettes',
      ];
      for (final label in labels) {
        final node = tester.getSemantics(find.text(label));
        expect(node.rect.height, greaterThanOrEqualTo(48), reason: label);
        expect(node.rect.width, greaterThanOrEqualTo(48), reason: label);
        expect(drawn(label).height, lessThan(48), reason: '$label keeps its look');
      }
      // The first chip of the second row of the night's statuses.
      final first = drawn('Nuit autorisée');
      final below = [
        'Nuit tolérée',
        'De jour seulement',
        'Nuit interdite',
      ].firstWhere((label) => drawn(label).top > first.bottom);
      expect(
        drawn(below).top - first.bottom,
        closeTo(8, 0.5),
        reason: 'rows as far apart as before',
      );
      // A touch in the gap above a chip of the second row is that chip's.
      bool selected(String label) =>
          tester.getSemantics(find.text(label)).flagsCollection.isSelected == Tristate.isTrue;
      final second = drawn(below);
      expect(selected(below), isFalse);
      await tester.tapAt(Offset(second.center.dx, second.top - 3));
      await tester.pump();
      expect(selected(below), isTrue, reason: '$below, touched 3 dp above its drawing');
      expect(selected('Nuit autorisée'), isFalse, reason: 'the chip above keeps to its own box');
      semantics.dispose();
    });

    testWidgets('the opening keeps the places open all year or on the dates of a stay', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final list = find
          .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
          .first;
      Future<void> tapChip(String chip) async {
        await tester.ensureVisible(find.text(chip));
        await tester.pump();
        await tester.tap(find.text(chip));
        await settleShort(tester);
      }

      final hint = find.text("Les lieux dont l'ouverture n'est pas connue restent affichés.");
      await tester.scrollUntilVisible(hint, 200, scrollable: list);
      await tester.pump();
      expect(hint, findsOneWidget);
      await tapChip("Toute l'année");
      // The campsite opens from April to October; the service area all year,
      // the others have no known season.
      expect(find.text('Afficher 4 lieux'), findsOneWidget);
      await tapChip("Toute l'année");
      expect(find.text('Afficher 5 lieux'), findsOneWidget, reason: 'a second tap clears it');

      // Arrival 30 October, departure 2 November: the night of 1 November
      // finds the campsite closed. Typed rather than tapped on the calendar,
      // whose days repeat from month to month.
      await tapChip('À mes dates');
      expect(find.text('Dates du séjour'), findsOneWidget);
      final material = MaterialLocalizations.of(tester.element(find.text('Dates du séjour')));
      await tester.tap(find.byTooltip(material.inputDateModeButtonLabel));
      await settleShort(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Arrivée'), '30/10/2026');
      await tester.enterText(find.widgetWithText(TextField, 'Départ'), '02/11/2026');
      await tester.tap(find.text(material.okButtonLabel));
      await settleShort(tester);
      expect(find.text('Du 30 oct. au 2 nov.'), findsOneWidget, reason: 'the chip says the dates');
      expect(find.text('À mes dates'), findsNothing);
      expect(find.text('Afficher 4 lieux'), findsOneWidget);
      // A tap on the dates opens the calendar on them, to change them;
      // cancelled, they stay.
      await tapChip('Du 30 oct. au 2 nov.');
      expect(find.text('Dates du séjour'), findsOneWidget);
      await tester.tap(find.byTooltip(material.inputDateModeButtonLabel));
      await settleShort(tester);
      String? field(String label) =>
          tester.widget<TextField>(find.widgetWithText(TextField, label)).controller?.text;
      expect(field('Arrivée'), '30/10/2026', reason: 'the calendar opens on the dates chosen');
      expect(field('Départ'), '02/11/2026');
      await tester.tap(find.text(material.cancelButtonLabel));
      await settleShort(tester);
      expect(find.text('Du 30 oct. au 2 nov.'), findsOneWidget);
      expect(find.text('Afficher 4 lieux'), findsOneWidget);
      await tester.tap(find.byTooltip('Effacer les dates'));
      await settleShort(tester);
      expect(
        find.text('À mes dates'),
        findsOneWidget,
        reason: 'the button beside the dates clears them',
      );
      expect(find.text('Afficher 5 lieux'), findsOneWidget);

      await tapChip("Toute l'année");
      await tester.tap(find.text('Afficher 4 lieux'));
      await settleShort(tester);
      expect(app.settings.value.filter, const PlaceFilter(opening: AllYearOpening()));
      expect(find.text('4 lieux ici'), findsOneWidget);
    });

    for (final (name, size, boxed) in const [
      ('a desktop', Size(1280, 800), true),
      ('a tablet', Size(720, 1000), true),
      ('a phone', Size(390, 844), false),
      ('a phone on its side', Size(844, 390), false),
    ]) {
      testWidgets('on $name the calendar of the stay ${boxed ? 'is a box' : 'takes the screen'}', (
        tester,
      ) async {
        await pumpLunaway(tester, size: size);
        await tester.tap(find.text('Filtres'));
        await settleShort(tester);
        final dates = find.text('À mes dates');
        await tester.scrollUntilVisible(
          dates,
          200,
          scrollable: find
              .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
              .first,
        );
        await tester.pump();
        await tester.tap(dates);
        await settleShort(tester);
        expect(find.text('Dates du séjour'), findsOneWidget);
        final dialog = tester.getRect(
          find
              .descendant(of: find.byType(DateRangePickerDialog), matching: find.byType(Material))
              .first,
        );
        if (boxed) {
          expect(dialog.width, lessThanOrEqualTo(480));
          expect(dialog.height, lessThanOrEqualTo(680));
          expect(dialog.height, lessThan(size.height - 40), reason: 'room above and below');
          expect(dialog.center.dx, closeTo(size.width / 2, 1));
          expect(dialog.center.dy, closeTo(size.height / 2, 1));
        } else {
          expect(
            (dialog.top, dialog.bottom),
            (0, size.height),
            reason: 'the whole height, as Material draws it on a phone',
          );
          if (size.width < 560) expect(dialog, Offset.zero & size, reason: 'the whole screen');
        }
      });
    }

    testWidgets('a stay already begun opens the calendar from today to its departure', (
      tester,
    ) async {
      // Arrived on 1 October, the filters reopened on the 6th: the
      // calendar starts at today and cannot hold the 1st.
      await pumpLunaway(
        tester,
        settings: AppSettings(
          filter: PlaceFilter(opening: StayOpening(DateTime(2026, 10), DateTime(2026, 10, 10))),
        ),
      );
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final chip = find.text('Du 1er au 10 oct.');
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find
            .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
            .first,
      );
      await tester.pump();
      await tester.tap(chip);
      await settleShort(tester);
      final material = MaterialLocalizations.of(tester.element(find.text('Dates du séjour')));
      await tester.tap(find.byTooltip(material.inputDateModeButtonLabel));
      await settleShort(tester);
      String? field(String label) =>
          tester.widget<TextField>(find.widgetWithText(TextField, label)).controller?.text;
      expect(field('Arrivée'), '06/10/2026', reason: 'the stay goes on from today');
      expect(field('Départ'), '10/10/2026', reason: 'its departure is kept');
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
    testWidgets('"my vehicle fits" asks the height alone, then hides the lower barriers', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await tester.ensureVisible(find.text('Mon véhicule passe'));
      await tester.tap(find.text('Mon véhicule passe'));
      await settleShort(tester);
      // Two fields, not the whole editor.
      expect(find.text('Hauteur de votre véhicule'), findsOneWidget);
      expect(find.byType(VehicleEditor), findsNothing);
      await tester.enterText(find.widgetWithText(TextFormField, 'Hauteur'), '2,40');
      await tester.enterText(find.widgetWithText(TextFormField, 'Poids total autorisé'), '3,5');
      await tester.tap(find.text('Filtrer avec cette hauteur'));
      await settleShort(tester);
      final vehicle = app.container(tester).read(vehicleProvider).value;
      expect(vehicle?.heightM, 2.4);
      expect(vehicle?.weightT, 3.5);
      expect(vehicle?.widthM, isNull, reason: 'nothing the user did not give is invented');
      expect(vehicle?.lengthM, isNull);
      expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      // The day car park under a 2.10 m barrier is gone; unknown heights stay.
      expect(find.text('4 lieux ici'), findsOneWidget);
      expect(app.map.lastProps!.places.map((p) => p.id), isNot(contains(dayParking.id)));
      expect(find.text('Passe à 2,40 m'), findsOneWidget);
    });

    testWidgets('the quick entry wants a height in range before it filters', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.ensureVisible(find.text('Mon véhicule passe'));
      await tester.tap(find.text('Mon véhicule passe'));
      await settleShort(tester);
      await tester.tap(find.text('Filtrer avec cette hauteur'));
      await settleShort(tester);
      expect(find.text('Indiquez la hauteur, par exemple 2,90'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Hauteur'), '29');
      await tester.tap(find.text('Filtrer avec cette hauteur'));
      await settleShort(tester);
      expect(find.textContaining('Entre'), findsOneWidget);
      expect(app.container(tester).read(vehicleProvider).value, isNull);
      expect(app.settings.value.filter.fitsMyVehicle, isFalse);
    });

    testWidgets('a vehicle already described keeps its sizes when its height is given', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await app
          .container(tester)
          .read(vehicleRepositoryProvider)
          .save(const Vehicle(type: VehicleType.overcab, widthM: 2.3, lengthM: 7, weightT: 3.5));
      await settleShort(tester);
      await tester.ensureVisible(find.text('Mon véhicule passe'));
      await tester.tap(find.text('Mon véhicule passe'));
      await settleShort(tester);
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, 'Poids total autorisé'))
            .controller!
            .text,
        '3,5',
        reason: 'the weight known is shown',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Hauteur'), '3.10');
      await tester.tap(find.text('Filtrer avec cette hauteur'));
      await settleShort(tester);
      final vehicle = app.container(tester).read(vehicleProvider).value!;
      expect(vehicle.type, VehicleType.overcab);
      expect(vehicle.heightM, 3.1);
      expect(vehicle.widthM, 2.3);
      expect(vehicle.lengthM, 7);
    });

    testWidgets(
      'without a height the filters sheet asks for it in place, and turns the filter on',
      (tester) async {
        final app = await pumpLunaway(tester);
        await tester.tap(find.text('Filtres'));
        await settleShort(tester);
        final list = find
            .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
            .first;
        final height = find.descendant(
          of: find.byType(FiltersPanel),
          matching: find.widgetWithText(TextFormField, 'Hauteur'),
        );
        await tester.scrollUntilVisible(height, 200, scrollable: list);
        await tester.pump();
        expect(find.byType(SwitchListTile), findsNothing, reason: 'no switch that cannot work');
        await tester.enterText(height, '2,40');
        // The field's caret scrolls the list to itself first.
        await settleShort(tester);
        final apply = find.text('Filtrer avec cette hauteur');
        await tester.ensureVisible(apply);
        await settleShort(tester);
        await tester.tap(apply);
        await settleShort(tester);
        expect(app.container(tester).read(vehicleProvider).value?.heightM, 2.4);
        await tester.scrollUntilVisible(find.byType(SwitchListTile), -200, scrollable: list);
        await tester.pump();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
          reason: 'the height given, the filter is on in the draft',
        );
        await tester.tap(find.text('Afficher 4 lieux'));
        await settleShort(tester);
        expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      },
    );

    testWidgets('describing the vehicle in the profile turns "my vehicle fits" on', (tester) async {
      final app = await pumpLunaway(tester);
      expect(app.settings.value.filter.fitsMyVehicle, isFalse);
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Décrire mon véhicule'));
      await tester.tap(find.text('Décrire mon véhicule'));
      await settleShort(tester);
      // The editor offers a campervan's typical size, 2.65 m high.
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      await openTab(tester, 'Carte');
      expect(chipOn(tester, 'Passe à 2,65 m'), isTrue);
    });

    testWidgets('the vehicle forgotten, the filter goes off with it', (tester) async {
      final app = await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Décrire mon véhicule'));
      await tester.tap(find.text('Décrire mon véhicule'));
      await settleShort(tester);
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      await showInProfile(tester, find.text('Fourgon aménagé'));
      await tester.tap(find.text('Fourgon aménagé'));
      await settleShort(tester);
      await tester.tap(find.text('Effacer'));
      await settleShort(tester);
      expect(app.container(tester).read(vehicleProvider).value, isNull);
      expect(
        app.settings.value.filter.fitsMyVehicle,
        isFalse,
        reason: 'no chip on, nor a count of filters, that filters nothing',
      );
    });

    testWidgets('the vehicle forgotten from the filters, their button keeps the filter off', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        settings: const AppSettings(
          filter: PlaceFilter(fitsMyVehicle: true),
          vehicleFilterDefaulted: true,
        ),
      );
      await app
          .container(tester)
          .read(vehicleRepositoryProvider)
          .save(Vehicle.typical(VehicleType.integrated));
      await settleShort(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final list = find
          .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
          .first;
      final edit = find.descendant(of: find.byType(FiltersPanel), matching: find.text('Modifier'));
      await tester.scrollUntilVisible(edit, 200, scrollable: list);
      await tester.pump();
      await tester.tap(edit);
      await settleShort(tester);
      await tester.tap(find.text('Effacer'));
      await settleShort(tester);
      await tester.tap(find.textContaining('Afficher'));
      await settleShort(tester);
      expect(app.container(tester).read(vehicleProvider).value, isNull);
      expect(app.settings.value.filter.fitsMyVehicle, isFalse);
    });

    testWidgets('turned off, the filter stays off until the vehicle is described again', (
      tester,
    ) async {
      final app = await pumpLunaway(
        tester,
        settings: const AppSettings(
          filter: PlaceFilter(fitsMyVehicle: true),
          vehicleFilterDefaulted: true,
        ),
      );
      final vehicles = app.container(tester).read(vehicleRepositoryProvider);
      await vehicles.save(Vehicle.typical(VehicleType.integrated));
      await settleShort(tester);
      await tester.tap(vehicleChip('Passe à 2,95 m'));
      await settleShort(tester);
      expect(chipOn(tester, 'Passe à 2,95 m'), isFalse);
      // The vehicle stored again without being described, as the fuel kept
      // from a route's sheet stores it: the user's choice holds.
      await vehicles.save(
        Vehicle.typical(VehicleType.integrated).copyWith(fuel: () => FuelType.diesel),
      );
      await settleShort(tester);
      expect(app.settings.value.filter.fitsMyVehicle, isFalse);

      // Described again from the filters: on, in the settings and in the
      // switch the panel's button applies.
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      final list = find
          .descendant(of: find.byType(FiltersPanel), matching: find.byType(Scrollable))
          .first;
      final edit = find.descendant(of: find.byType(FiltersPanel), matching: find.text('Modifier'));
      await tester.scrollUntilVisible(edit, 200, scrollable: list);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
      await tester.tap(edit);
      await settleShort(tester);
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
      await tester.tap(find.textContaining('Afficher'));
      await settleShort(tester);
      expect(app.settings.value.filter.fitsMyVehicle, isTrue);
      expect(chipOn(tester, 'Passe à 2,95 m'), isTrue);
    });

    testWidgets('the filter survives a restart: on once for a vehicle described before, then '
        "the user's choice", (tester) async {
      final store = UserDatabase(memoryDatabase());
      // A user of an earlier version: a vehicle, and no setting about it.
      await DriftVehicleRepository(store).save(Vehicle.typical(VehicleType.integrated));
      Future<void> launch() async {
        await tester.pumpWidget(const SizedBox());
        await pumpLunaway(tester, userDatabase: store, storedSettings: true);
      }

      await launch();
      expect(chipOn(tester, 'Passe à 2,95 m'), isTrue, reason: 'on for the vehicle described');
      await tester.tap(vehicleChip('Passe à 2,95 m'));
      await settleShort(tester);
      expect(chipOn(tester, 'Passe à 2,95 m'), isFalse);

      await launch();
      expect(chipOn(tester, 'Passe à 2,95 m'), isFalse, reason: "the user's off, kept");

      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Intégral'));
      await tester.tap(find.text('Intégral'));
      await settleShort(tester);
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      await openTab(tester, 'Carte');
      expect(chipOn(tester, 'Passe à 2,95 m'), isTrue, reason: 'on again with the vehicle');

      await launch();
      expect(chipOn(tester, 'Passe à 2,95 m'), isTrue, reason: 'kept on');
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
        scrollable: editorList,
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
      final scroll = editorList;
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

    testWidgets('its cruising speed is picked from a list, kept, and can go back to none', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      await showInProfile(tester, find.text('Décrire mon véhicule'));
      await tester.tap(find.text('Décrire mon véhicule'));
      await settleShort(tester);
      final control = find.byType(DropdownButtonFormField<int?>);
      await tester.scrollUntilVisible(control, 200, scrollable: editorList);
      expect(
        find.descendant(of: control, matching: find.text('Pas de limite')),
        findsOneWidget,
        reason: 'the usual speeds by default',
      );
      await tester.tap(control);
      await settleShort(tester);
      await tester.tap(find.text('95 km/h').last);
      await settleShort(tester);
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      Vehicle? stored() => app.container(tester).read(vehicleProvider).value;
      expect(stored()?.cruiseSpeedKph, 95);

      // The vehicle's card in the profile opens it again.
      await showInProfile(tester, find.text('Fourgon aménagé'));
      await tester.tap(find.text('Fourgon aménagé'));
      await settleShort(tester);
      await tester.scrollUntilVisible(control, 200, scrollable: editorList);
      expect(find.descendant(of: control, matching: find.text('95 km/h')), findsOneWidget);
      await tester.tap(control);
      await settleShort(tester);
      await tester.tap(find.text('Pas de limite').last);
      await settleShort(tester);
      await tester.tap(find.text('Enregistrer').last);
      await settleShort(tester);
      expect(stored()?.cruiseSpeedKph, isNull);
      expect(stored(), isNotNull, reason: 'the vehicle stays, without a speed');
    });

    testWidgets('the profile shows the vehicle described, its type and size', (tester) async {
      final app = await pumpLunaway(tester);
      await app
          .container(tester)
          .read(vehicleRepositoryProvider)
          .save(Vehicle.typical(VehicleType.van));
      await openTab(tester, 'Profil');
      expect(find.text('Van'), findsOneWidget);
      // Each figure tied to its letter and its unit: no "L 6,00" at the end
      // of a line and "m" on the next.
      expect(find.textContaining('H\u00a02,00\u00a0m · '), findsOneWidget);
    });
  });

  group('favourites', () {
    testWidgets('empty, the screen says how to save a place', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Favoris');
      expect(find.text("Rien d'enregistré ici pour l'instant"), findsOneWidget);
      expect(find.textContaining('Enregistrez un lieu, une adresse ou un point'), findsOneWidget);
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
      // The cards are as wide as their names: the second may lie past the
      // edge of the screen, its start in sight.
      await tester.tapAt(tester.getTopLeft(find.text('Bretagne 2027').first) + const Offset(8, 8));
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

    testWidgets('a saved place without a name is titled by its street, as everywhere else', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      const unnamed = PlaceSummary(
        id: 'test-unnamed-car-park',
        kind: PlaceKind.parking,
        lat: 44.48,
        lon: 4.69,
        overnight: OvernightStatus.unknown,
        city: 'Viviers',
        street: '4 Rue de la Gare',
      );
      await app.favorites.addToDefault(unnamed);
      await openTab(tester, 'Favoris');
      expect(find.text('Parking · Rue de la Gare'), findsOneWidget);
      expect(find.text('Parking · Viviers'), findsNothing);
    });

    testWidgets('a place saved before the app kept streets gets its own on opening the lists', (
      tester,
    ) async {
      final unnamed = Place(
        id: 'test-unnamed-car-park',
        kind: PlaceKind.parking,
        lat: 44.48,
        lon: 4.69,
        overnight: OvernightStatus.unknown,
        address: const Address(street: '4 Rue de la Gare', city: 'Viviers'),
        updatedAt: DateTime.utc(2026, 10),
      );
      final app = await pumpLunaway(
        tester,
        places: [unnamed, ...samplePlaces],
        storedFavorites: true,
      );
      // Saved by a version that kept the town only.
      await app
          .container(tester)
          .read(favoritesRepositoryProvider)
          .addToDefault(
            PlaceSummary(
              id: unnamed.id,
              kind: unnamed.kind,
              lat: unnamed.lat,
              lon: unnamed.lon,
              overnight: unnamed.overnight,
              city: 'Viviers',
            ),
          );
      await openTab(tester, 'Favoris');
      await settleShort(tester);
      expect(find.text('Parking · Rue de la Gare'), findsOneWidget);
      expect(find.text('Parking · Viviers'), findsNothing);
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
      expect(find.text('1 favori'), findsOneWidget);
      expect(find.text('Aire du Lac Bleu (démo)'), findsOneWidget);
    });
  });

  group('profile', () {
    /// Scrolls the profile to the language picker, clear of the bottom bar.
    Future<void> showLanguages(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Nederlands'),
        200,
        scrollable: find
            .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
            .first,
      );
      await tester.drag(find.byType(ProfileScreen), const Offset(0, -200));
      await settleShort(tester);
    }

    testWidgets('switching the language translates the app and is remembered', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      await showLanguages(tester);
      await tester.tap(find.text('English'));
      await settleShort(tester);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      // A text of the profile beside the picker, built wherever the list stands.
      expect(find.text('Translate reviews automatically'), findsOneWidget);
      expect(app.settings.value.localeCode, 'en');
      await tester.tap(find.text('Français'));
      await settleShort(tester);
      expect(find.text('Carte'), findsOneWidget);
    });

    testWidgets('the picker offers the six languages, each under its own name', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      await showLanguages(tester);
      final names = {
        'Deutsch': ('de', 'Karte'),
        'Español': ('es', 'Mapa'),
        'Italiano': ('it', 'Mappa'),
        'Nederlands': ('nl', 'Kaart'),
      };
      for (final MapEntry(key: name, value: (code, map)) in names.entries) {
        await tester.tap(find.text(name));
        await settleShort(tester);
        expect(app.settings.value.localeCode, code);
        expect(LocaleSettings.currentLocale.languageCode, code);
        expect(find.text(map), findsOneWidget, reason: 'the map tab in $name');
        // The names stay the same whatever the language of the screens.
        for (final other in names.keys) {
          expect(find.text(other), findsOneWidget, reason: '$other read in $name');
        }
      }
    });

    testWidgets('the language follows the device until the user picks one', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      await showLanguages(tester);
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(find.text("Comme l'appareil")), isSemantics(isChecked: true));
      expect(tester.getSemantics(find.text('Deutsch')), isSemantics(isChecked: false));
      // A screen reader says each name in its own language.
      expect(
        tester
            .getSemantics(find.text('Deutsch'))
            .attributedLabel
            .attributes
            .whereType<LocaleStringAttribute>()
            .map((a) => a.locale),
        contains(const Locale('de')),
      );
      await tester.tap(find.text('Deutsch'));
      await settleShort(tester);
      expect(tester.getSemantics(find.text('Deutsch')), isSemantics(isChecked: true));
      await tester.tap(find.text(AppLocale.de.buildSync().profile.languageSystem));
      await settleShort(tester);
      expect(app.settings.value.localeCode, isNull, reason: 'the device decides again');
      semantics.dispose();
    });

    testWidgets('the appearance switches to dark and is remembered', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      // Built first: the guidance's settings above it fill more than a
      // screen, and the list builds lazily.
      await showInProfile(tester, find.text('Sombre'));
      // In the middle of the screen: clear of the dock.
      await Scrollable.ensureVisible(tester.element(find.text('Sombre')), alignment: 0.5);
      await settleShort(tester);
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
      for (final label in ['Site web', 'Politique de confidentialité', 'Code source']) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find
              .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
              .first,
        );
        await tester.pump();
        await tester.tap(find.text(label));
        await settleShort(tester);
      }
      expect(app.external.opened.map((u) => u.toString()), [
        'https://lunaway.net/',
        'https://lunaway.net/privacy',
        'https://github.com/poka-IT/lunaway',
      ]);
    });

    testWidgets('the site and the privacy policy open in the language of the app', (tester) async {
      final app = await pumpLunaway(tester, size: tallPhone, locale: AppLocale.de);
      await openTab(tester, 'Profil');
      for (final label in ['Website', 'Datenschutzerklärung']) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find
              .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
              .first,
        );
        await tester.pump();
        await tester.tap(find.text(label));
        await settleShort(tester);
      }
      expect(app.external.opened.map((u) => u.toString()), [
        'https://lunaway.net/de/',
        'https://lunaway.net/de/privacy',
      ]);
    });

    testWidgets('the about section says once, in one line, what the routes rest on', (
      tester,
    ) async {
      await pumpLunaway(tester, size: tallPhone);
      await openTab(tester, 'Profil');
      const line =
          'Itinéraires calculés sur des données ouvertes parfois incomplètes : la signalisation '
          'et le code de la route priment.';
      await tester.scrollUntilVisible(
        find.text(line),
        200,
        scrollable: find
            .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text(line), findsOneWidget);
      // A line of the profile's page itself.
      expect(
        find.descendant(of: find.byType(ProfileScreen), matching: find.text(line)),
        findsOneWidget,
      );
    });

    testWidgets('the attributions credit OpenStreetMap and the basemap', (tester) async {
      await pumpLunaway(tester, size: const Size(1280, 3200), locale: AppLocale.en);
      await openTab(tester, 'Profile');
      expect(find.text('Places and map data © OpenStreetMap contributors.'), findsOneWidget);
      expect(find.textContaining('styles derived from Protomaps'), findsOneWidget);
      expect(find.textContaining('OpenFreeMap'), findsNothing);
    });

    testWidgets('the credits name every source the app shows, with its licence', (tester) async {
      await pumpLunaway(tester, size: const Size(1280, 4800), locale: AppLocale.en);
      await openTab(tester, 'Profile');
      for (final source in [
        'DATAtourisme, under the Licence Ouverte 2.0',
        'Wikimedia Commons, each under its own licence',
        'Panoramax: the OpenStreetMap France instance under CC BY-SA 4.0',
        'Wikipedia articles, under CC BY-SA 4.0',
        'Mangrove Reviews, under CC BY 4.0',
        "Lunaway's travellers, under CC BY 4.0",
        'credited as "Lunaway contributors"',
        'OPUS-MT models of the University of Helsinki, under CC BY 4.0',
        'DIR and Bison Futé, DiaLog traffic orders (DGITM)',
        'Ville de Paris, Rennes Métropole',
        'NDW, Nationaal Dataportaal Wegverkeer',
        'DGT, Dirección General de Tráfico (CC BY)',
        'Speed cameras and danger zones: in France, the Sécurité routière map',
        'Délégation à la sécurité routière (data.gouv.fr), under the Licence Ouverte 2.0',
        'Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort',
        'An Garda Síochána, Irish Public Sector Information, CC BY',
        'Height, width, length and weight limits of the roads',
        'the Base Adresse Nationale, through',
        'OpenStreetMap, through Photon',
      ]) {
        expect(find.textContaining(source), findsOneWidget, reason: source);
      }
      expect(find.textContaining('Outlines of the offline maps'), findsOneWidget);
    });

    testWidgets('a list of speed cameras the credits do not name yet is cited in its own words', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: const Size(1280, 4800), locale: AppLocale.en);
      Map<String, Object?> list(String id, String attribution) => {
        'id': id,
        'name': id,
        'attribution': attribution,
        'fetchedAt': '2026-10-09T05:00:00Z',
        'listUpdatedAt': null,
      };
      await EnforcementStore(app.cache).apply(
        enforcementPageFromJson({
          'cursor': 'c1',
          'full': true,
          'rules': {'version': 2, 'countries': <Object>[]},
          'upserts': <Object>[],
          'removals': <Object>[],
          'sources': [
            list('securite-routiere', 'Sécurité routière, radars.securite-routiere.gouv.fr'),
            list('se-trafikverket', 'Trafikverket, CC0'),
          ],
          'pollIntervalSeconds': 21600,
          'hasMore': false,
        }),
        {'SE'},
        DateTime.utc(2026, 10, 9),
      );
      await openTab(tester, 'Profile');
      expect(find.text('Speed cameras and danger zones: Trafikverket, CC0'), findsOneWidget);
      expect(
        find.textContaining('radars.securite-routiere.gouv.fr'),
        findsNothing,
        reason: 'a list the sentence names is not cited twice',
      );
    });

    testWidgets("the voice of the guidance is the device's, not a phone's on a computer", (
      tester,
    ) async {
      await pumpLunaway(tester, size: const Size(1280, 4800));
      await openTab(tester, 'Profil');
      expect(
        find.text("Les instructions et les alertes, avec la voix de l'appareil."),
        findsOneWidget,
      );
      expect(find.textContaining('voix du téléphone'), findsNothing);
    });

    testWidgets('where the app makes no offline maps (the web), their credits are not listed', (
      tester,
    ) async {
      await pumpLunaway(
        tester,
        size: const Size(1280, 4800),
        locale: AppLocale.en,
        packFiles: MemoryPackFiles(supported: false),
      );
      await openTab(tester, 'Profile');
      expect(find.textContaining('Basemap served by Lunaway'), findsOneWidget);
      expect(find.textContaining('Outlines of the offline maps'), findsNothing);
      expect(find.textContaining('Offline map labels'), findsNothing);
    });

    for (final (locale, tab, label) in [
      (AppLocale.fr, 'Profil', 'Source communautaire externe'),
      (AppLocale.en, 'Profile', 'External community source'),
    ]) {
      testWidgets('the attributions credit the external community source by its agreed wording '
          '(${locale.languageCode})', (tester) async {
        final app = await pumpLunaway(tester, size: const Size(1280, 3200), locale: locale);
        await openTab(tester, tab);
        expect(find.text(label), findsOneWidget);
        // No link: an address would name the partner.
        await tester.tap(find.text(label));
        await settleShort(tester);
        expect(app.external.opened, isEmpty);
      });
    }
  });
}
