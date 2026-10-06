import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settleShort(tester);
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
      // The family tile, before the services section of the same name.
      await tester.tap(find.text('Services').first);
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
      // The button on the map counts the active filters.
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);
    });

    testWidgets('the vehicle height slider hides lower barriers', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      await tester.scrollUntilVisible(
        find.byType(Slider),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Toutes hauteurs'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(5); // the sixth stop: 2.30 m
      await settleShort(tester);
      expect(find.text('2,30 m'), findsWidgets);
      expect(find.text('Afficher 4 lieux'), findsOneWidget);
      await tester.tap(find.text('Afficher 4 lieux'));
      await settleShort(tester);
      expect(app.settings.value.filter.vehicleHeightM, 2.3);
    });

    testWidgets('on a wide screen the filters open in a dialog', (tester) async {
      await pumpLunaway(tester, size: desktop);
      await tester.tap(find.text('Filtres'));
      await settleShort(tester);
      expect(find.byType(Dialog), findsOneWidget);
    });
  });

  group('favourites', () {
    testWidgets('empty, the screen says how to save a place', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Favoris');
      expect(find.text('Les lieux que vous enregistrez apparaîtront ici.'), findsOneWidget);
    });

    testWidgets('a saved place shows, opens on the map, and can be removed then put back', (
      tester,
    ) async {
      final app = await pumpLunaway(tester);
      await app.favorites.addToDefault(campsite.summary);
      await openTab(tester, 'Favoris');
      expect(find.text('Camping des Peupliers (démo)'), findsOneWidget);
      await tester.drag(find.text('Camping des Peupliers (démo)'), const Offset(-500, 0));
      await settleShort(tester);
      expect(app.favorites.entries, isEmpty);
      await tester.tap(find.text('Annuler'));
      await settleShort(tester);
      expect(app.favorites.entries.single.placeId, campsite.id);
      await tester.tap(find.text('Camping des Peupliers (démo)'));
      await settleShort(tester);
      expect(app.container(tester).read(selectionProvider), PlaceSelection(campsite.id));
      expect(app.map.moves.last.center, campsite.position);
      expect(find.text('Mes favoris'), findsNothing, reason: 'back on the map');
      expect(find.text('Nuit autorisée'), findsWidgets, reason: 'with the place open in its sheet');
    });

    testWidgets('a new list can be created and becomes the shown one', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Favoris');
      await tester.ensureVisible(find.text('Nouvelle liste'));
      await tester.tap(find.text('Nouvelle liste'));
      await settleShort(tester);
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Bretagne 2027',
      );
      await tester.tap(find.text('Enregistrer'));
      await settleShort(tester);
      expect(find.text('Bretagne 2027 · 0'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Bretagne 2027 · 0')).selected,
        isTrue,
      );
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
      final app = await pumpLunaway(tester);
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

    testWidgets('the offline data panel tells the count, the size and the age', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      expect(find.text('5 lieux sur cet appareil'), findsOneWidget);
      expect(find.text('Espace utilisé : 3,3 Mo'), findsOneWidget);
      expect(find.text("Dernière mise à jour aujourd'hui"), findsOneWidget);
    });

    testWidgets('update now runs a sync and reports it', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      await tester.scrollUntilVisible(
        find.text('Mettre à jour'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Mettre à jour'));
      await settleShort(tester);
      expect(find.text('Les lieux sont à jour.'), findsOneWidget);
    });

    testWidgets('the about card links the website, the privacy policy and the source code', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: const Size(400, 2600));
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

    testWidgets('the attributions credit OpenStreetMap under the ODbL', (tester) async {
      await pumpLunaway(tester, size: desktop, locale: AppLocale.en);
      await openTab(tester, 'Profile');
      expect(
        find.textContaining('© OpenStreetMap contributors, under the Open Database License'),
        findsOneWidget,
      );
    });

    testWidgets('the language follows the device until the user picks one', (tester) async {
      await pumpLunaway(tester);
      await openTab(tester, 'Profil');
      final buttons = tester.widget<SegmentedButton<AppLocale?>>(
        find.byType(SegmentedButton<AppLocale?>),
      );
      expect(buttons.selected, {null});
    });
  });
}
