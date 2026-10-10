import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// Opens [place] in the details panel of the desktop layout, where the whole
/// sheet fits without scrolling the map away.
Future<TestApp> openPlace(
  WidgetTester tester,
  Place place, {
  AppLocale locale = AppLocale.fr,
  FakeExtrasSource? extras,
  Size size = const Size(1280, 3200),
  List<Place>? places,
}) async {
  final app = await pumpLunaway(tester, size: size, locale: locale, extras: extras, places: places);
  app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(place.id));
  await settleShort(tester);
  return app;
}

/// [finder] inside the details pane, not in the list beside it.
Finder inDetails(Finder finder) =>
    find.descendant(of: find.byType(PlaceDetailsBody), matching: finder);

void main() {
  late List<String> clipboard;
  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map<Object?, Object?>)['text']! as String);
        }
        return null;
      },
    );
  });

  testWidgets('the overnight status comes first, with how fresh the information is', (
    tester,
  ) async {
    await openPlace(tester, lakeArea);
    expect(find.text('Nuit autorisée'), findsWidgets);
    expect(find.text('Vous pouvez passer la nuit ici.'), findsOneWidget);
    expect(find.text('Confirmé par un voyageur il y a 3 mois'), findsOneWidget);
  });

  testWidgets('in a tablet panel the facts keep room for their longest word', (tester) async {
    // A 10-inch tablet held upright: the medium layout's wider panel.
    final app = await pumpLunaway(tester, size: const Size(800, 1280));
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
    await settleShort(tester);
    final tile = find.ancestor(of: find.text('Emplacements'), matching: find.byType(Container));
    expect(tester.getSize(tile.first).width, greaterThanOrEqualTo(112));
  });

  testWidgets('a price the sources do not give is said quietly', (tester) async {
    await openPlace(tester, serviceArea);
    expect(find.text('Non indiqué'), findsOneWidget);
  });

  testWidgets('a place no traveller has confirmed says so, whatever its last import', (
    tester,
  ) async {
    await openPlace(tester, dayParking);
    expect(find.text('Pas encore confirmé par un voyageur'), findsOneWidget);
    expect(find.textContaining('Mis à jour'), findsNothing);
  });

  testWidgets('a place missing after a finished download is said to be gone', (tester) async {
    final app = await pumpLunaway(tester, size: const Size(1280, 2400));
    app.container(tester).read(selectionProvider.notifier).select(const PlaceSelection('missing'));
    await settleShort(tester);
    expect(find.text(AppLocale.fr.buildSync().place.gone), findsOneWidget);
  });

  testWidgets('a place missing during the first download is said to be on its way', (tester) async {
    final app = await pumpLunaway(tester, size: const Size(1280, 2400), neverSynced: true);
    app.container(tester).read(selectionProvider.notifier).select(const PlaceSelection('missing'));
    await settleShort(tester);
    final t = AppLocale.fr.buildSync();
    expect(find.text(t.place.arriving), findsOneWidget);
    expect(find.text(t.place.gone), findsNothing);
  });

  testWidgets('information unconfirmed for over a year is flagged', (tester) async {
    await openPlace(tester, campsite);
    expect(find.text("Dernière confirmation il y a plus d'un an"), findsOneWidget);
  });

  testWidgets('a day-only car park says so plainly, with its height barrier', (tester) async {
    await openPlace(tester, dayParking);
    expect(find.text('De jour seulement'), findsWidgets);
    expect(
      find.text('Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.'),
      findsOneWidget,
    );
    expect(find.text('Gratuit'), findsOneWidget);
    expect(find.text('2,10 m'), findsOneWidget);
  });

  testWidgets('facts, opening hours and labelled services', (tester) async {
    await openPlace(tester, lakeArea);
    expect(find.text('12 €'), findsOneWidget);
    expect(find.text('3 €'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Ouvert, ferme à 20:00'), findsOneWidget);
    expect(find.text('Lun.-dim. 08:00-20:00'), findsOneWidget);
    for (final label in ['Eau potable', 'Vidange eaux grises', 'Vidange cassette', 'Électricité']) {
      expect(inDetails(find.text(label)), findsOneWidget);
    }
  });

  testWidgets('once the opening window has run out, the hours say so rather than closed', (
    tester,
  ) async {
    final stale = Place(
      id: 'test-stale-hours',
      name: 'Aire des Horaires (démo)',
      kind: lakeArea.kind,
      lat: lakeArea.lat,
      lon: lakeArea.lon,
      overnight: lakeArea.overnight,
      updatedAt: lakeArea.updatedAt,
      openingHours: 'Mo-Su 08:00-20:00',
      openingHoursParsed: true,
      openingIntervals: lakeArea.openingIntervals,
      openingValidUntil: testNow.subtract(const Duration(days: 1)).toUtc(),
    );
    await openPlace(tester, stale, places: [stale]);
    expect(
      inDetails(find.text('Ouvert ou fermé ? Mettez à jour les lieux dans Profil.')),
      findsOneWidget,
    );
    expect(inDetails(find.textContaining('Fermé')), findsNothing);
    expect(inDetails(find.text('Lun.-dim. 08:00-20:00')), findsOneWidget);
  });

  testWidgets('a season says whether the place is open today, and until when', (tester) async {
    Place seasonal(String id, String hours, List<DayRange> season) => Place(
      id: id,
      name: 'Camping des Saisons (démo)',
      kind: PlaceKind.campsite,
      lat: lakeArea.lat,
      lon: lakeArea.lon,
      overnight: OvernightStatus.allowed,
      updatedAt: lakeArea.updatedAt,
      openingHours: hours,
      openingHoursParsed: true,
      openingSeason: season,
    );
    final summer = seasonal('test-summer', 'Apr 01-Oct 31', const [DayRange(92, 305)]);
    final may = seasonal('test-may', 'May 01-Sep 30', const [DayRange(122, 274)]);
    final app = await openPlace(tester, summer, places: [summer, may, serviceArea]);
    final scheme = Theme.of(tester.element(find.byType(PlaceDetailsBody))).colorScheme;
    Color? colour(String text) => tester.widget<Text>(inDetails(find.text(text))).style?.color;

    // 6 October 2026.
    expect(inDetails(find.text("Ouvert jusqu'au 31 octobre")), findsOneWidget);
    expect(colour("Ouvert jusqu'au 31 octobre"), scheme.secondary);
    expect(inDetails(find.text('1 avr.-31 oct.')), findsOneWidget, reason: 'the hours stay');

    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(may.id));
    await settleShort(tester);
    expect(inDetails(find.text('Fermé, ouvre le 1er mai')), findsOneWidget);
    expect(colour('Fermé, ouvre le 1er mai'), scheme.error);

    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(serviceArea.id));
    await settleShort(tester);
    expect(inDetails(find.text("Ouvert toute l'année")), findsOneWidget);
  });

  testWidgets('a place open all year says it once, without a note of local time', (tester) async {
    final allYear = Place(
      id: 'test-all-year',
      name: "Aire de l'Année (démo)",
      kind: PlaceKind.motorhomeArea,
      lat: lakeArea.lat,
      lon: lakeArea.lon,
      overnight: OvernightStatus.allowed,
      updatedAt: lakeArea.updatedAt,
      openingHours: 'Jan 01-Dec 31',
      openingHoursParsed: true,
      openingSeason: const [DayRange.wholeYear],
    );
    await openPlace(tester, allYear, places: [allYear]);
    expect(inDetails(find.text("Ouvert toute l'année")), findsOneWidget);
    expect(inDetails(find.textContaining("oute l'année")), findsOneWidget);
    expect(inDetails(find.text("Horaires à l'heure locale du lieu")), findsNothing);
  });

  testWidgets('hours with times of day keep the note that they are the local time', (tester) async {
    await openPlace(tester, lakeArea);
    expect(inDetails(find.text('Lun.-dim. 08:00-20:00')), findsOneWidget);
    expect(inDetails(find.text("Horaires à l'heure locale du lieu")), findsOneWidget);
  });

  Place priced(
    String id, {
    double? parking,
    double? services,
    bool included = false,
    Set<PriceInclusion> includes = const {},
  }) => Place(
    id: id,
    name: 'Aire des Prix (démo)',
    kind: PlaceKind.motorhomeArea,
    lat: lakeArea.lat,
    lon: lakeArea.lon,
    overnight: OvernightStatus.allowed,
    updatedAt: lakeArea.updatedAt,
    priceParkingEur: parking,
    priceServicesEur: services,
    priceServicesIncluded: included,
    priceParkingIncludes: includes,
  );

  testWidgets('included services and what the night includes are said under the prices', (
    tester,
  ) async {
    final area = priced(
      'test-included',
      parking: 14.5,
      included: true,
      includes: {PriceInclusion.touristTax, PriceInclusion.services},
    );
    await openPlace(tester, area, places: [area]);
    expect(inDetails(find.textContaining(RegExp(r'^14,50\s€$'))), findsOneWidget);
    expect(
      inDetails(find.text('Le prix de la nuit comprend : services, taxe de séjour')),
      findsOneWidget,
    );
    expect(inDetails(find.text('Inclus')), findsOneWidget);
    expect(inDetails(find.text('Gratuit')), findsNothing);
  });

  testWidgets('free services at a paid campsite read as included, never as free', (tester) async {
    final camp = priced('test-paid-campsite', parking: 60, services: 0);
    await openPlace(tester, camp, places: [camp]);
    expect(inDetails(find.textContaining(RegExp(r'^60\s€$'))), findsOneWidget);
    expect(inDetails(find.text('Inclus')), findsOneWidget);
    expect(inDetails(find.text('Gratuit')), findsNothing);
    expect(
      inDetails(find.textContaining('comprend')),
      findsNothing,
      reason: 'the source said nothing',
    );
  });

  testWidgets('free services at a free stop stay free', (tester) async {
    final stop = priced('test-free', parking: 0, services: 0);
    await openPlace(tester, stop, places: [stop]);
    expect(inDetails(find.text('Gratuit')), findsNWidgets(2));
    expect(inDetails(find.text('Inclus')), findsNothing);
  });

  testWidgets(
    'in English, the night says it includes the electricity, priced services their price',
    (tester) async {
      final area = priced(
        'test-electric',
        parking: 26,
        services: 4,
        includes: {PriceInclusion.electricity},
      );
      await openPlace(tester, area, places: [area], locale: AppLocale.en);
      expect(inDetails(find.text('The price of a night includes: electricity')), findsOneWidget);
      expect(inDetails(find.text('€4')), findsOneWidget);
    },
  );

  testWidgets('services priced by another source leave the list of what the night includes', (
    tester,
  ) async {
    final area = priced(
      'test-two-sources',
      parking: 14.5,
      services: 3,
      includes: {PriceInclusion.services, PriceInclusion.touristTax},
    );
    await openPlace(tester, area, places: [area]);
    expect(
      inDetails(find.text('Le prix de la nuit comprend : taxe de séjour')),
      findsOneWidget,
      reason: 'never "included" beside a price of their own',
    );
    expect(inDetails(find.textContaining(RegExp(r'^3\s€$'))), findsOneWidget);
  });

  testWidgets('a classified campsite shows its stars among the facts', (tester) async {
    await openPlace(tester, campsite);
    expect(inDetails(find.text('Classement')), findsOneWidget);
    expect(inDetails(find.text('3 étoiles')), findsOneWidget);
  });

  testWidgets('an unnamed place reads as its kind in its town', (tester) async {
    await openPlace(tester, unnamedParking);
    expect(find.text('Parking à Saint-Malo'), findsWidgets);
  });

  testWidgets('copy puts the decimal coordinates on the clipboard and says what was copied', (
    tester,
  ) async {
    await openPlace(tester, dayParking);
    await tester.tap(
      find.descendant(of: find.byType(PlaceActionBar), matching: find.text('Copier')),
    );
    await tester.pump();
    expect(clipboard, ['45.762900, 4.831697']);
    expect(find.text('Copié : 45.762900, 4.831697'), findsOneWidget);
  });

  testWidgets('where Android shows the copied text itself, the app does not say it again', (
    tester,
  ) async {
    final app = await pumpLunaway(tester, size: const Size(1280, 2400), systemShowsCopies: true);
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(dayParking.id));
    await settleShort(tester);
    await tester.tap(
      find.descendant(of: find.byType(PlaceActionBar), matching: find.text('Copier')),
    );
    await settleShort(tester);
    expect(clipboard, ['45.762900, 4.831697']);
    expect(find.textContaining('Copié'), findsNothing);
  });

  testWidgets('the formats menu copies degrees, minutes and seconds', (tester) async {
    await openPlace(tester, dayParking);
    await tester.tap(find.byTooltip('Choisir le format copié'));
    await settleShort(tester);
    await tester.tap(find.text('Degrés, minutes, secondes'));
    await settleShort(tester);
    expect(clipboard, ['45°45\'46.4"N 4°49\'54.1"E']);
  });

  testWidgets('a format picked in the menu stays the one "Copy" copies, and says so', (
    tester,
  ) async {
    final app = await openPlace(tester, dayParking);
    expect(find.textContaining('« Copier » copie'), findsNothing);
    await tester.tap(find.byTooltip('Choisir le format copié'));
    await settleShort(tester);
    await tester.tap(find.text('Degrés, minutes, secondes'));
    await settleShort(tester);
    expect(app.settings.value.copyFormat, CoordinateFormat.dms, reason: 'kept on the device');
    expect(find.text('« Copier » copie : Degrés, minutes, secondes'), findsOneWidget);

    clipboard.clear();
    await tester.tap(
      find.descendant(of: find.byType(PlaceActionBar), matching: find.text('Copier')),
    );
    await settleShort(tester);
    expect(clipboard, ['45°45\'46.4"N 4°49\'54.1"E']);

    // Picking decimal degrees again goes back to the default.
    await tester.tap(find.byTooltip('Choisir le format copié'));
    await settleShort(tester);
    await tester.tap(find.text('Degrés décimaux'));
    await settleShort(tester);
    expect(find.textContaining('« Copier » copie'), findsNothing);
  });

  testWidgets('the coordinates are copied by the action bar alone, not twice on the page', (
    tester,
  ) async {
    await openPlace(tester, dayParking);
    expect(inDetails(find.byIcon(AppIcons.copy)), findsNothing);
    expect(
      find.descendant(of: find.byType(PlaceActionBar), matching: find.text('Copier')),
      findsOneWidget,
    );
  });

  testWidgets('a long press on directions offers the installed navigation apps', (tester) async {
    final app = await openPlace(tester, dayParking);
    await tester.longPress(find.text('Itinéraire'));
    await settleShort(tester);
    expect(find.text('Ouvrir dans'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
    expect(find.text('Waze'), findsOneWidget);
    expect(find.text('OsmAnd'), findsNothing, reason: 'not installed');
    await tester.tap(find.text('Waze'));
    await settleShort(tester);
    expect(app.external.routes.single.app, NavigationApp.waze);
    expect(app.external.routes.single.to, dayParking.position);
    expect(app.settings.value.navigationApp, NavigationApp.waze.id);
  });

  testWidgets('with the switch off, the chooser forgets the app', (tester) async {
    final app = await openPlace(tester, dayParking);
    await tester.longPress(find.text('Itinéraire'));
    await settleShort(tester);
    await tester.tap(find.text('Toujours utiliser cette application'));
    await settleShort(tester);
    await tester.tap(find.text('Google Maps'));
    await settleShort(tester);
    expect(app.external.routes.single.app, NavigationApp.googleMaps);
    expect(app.settings.value.navigationApp, isNull);
  });

  testWidgets('when no app opens the route, the user is told', (tester) async {
    final app = await openPlace(tester, dayParking);
    app.external.openSucceeds = false;
    await tester.longPress(find.text('Itinéraire'));
    await settleShort(tester);
    await tester.tap(find.text('Waze'));
    await settleShort(tester);
    expect(find.text("Aucune application n'a pu ouvrir ce lien."), findsOneWidget);
  });

  testWidgets('share sends the name, the coordinates and a map link', (tester) async {
    final app = await openPlace(tester, dayParking);
    await tester.tap(find.text('Partager'));
    await settleShort(tester);
    expect(app.external.shared.single.split('\n'), [
      'Parking des Tilleuls (démo)',
      '45.762900, 4.831697',
      'https://www.openstreetmap.org/?mlat=45.762900&mlon=4.831697#map=17/45.762900/4.831697',
    ]);
  });

  testWidgets('save adds the place to the favourites, a second tap removes it', (tester) async {
    final app = await openPlace(tester, campsite);
    await tester.tap(find.text('Enregistrer'));
    await settleShort(tester);
    expect(app.favorites.entries.single.placeId, campsite.id);
    expect(find.text('Enregistré'), findsOneWidget);
    expect(find.text('Ajouté à Mes favoris'), findsOneWidget);
    await tester.tap(find.text('Enregistré'));
    await settleShort(tester);
    expect(app.favorites.entries, isEmpty);
  });

  testWidgets('saving again takes the place out of "My favourites" only, with an undo', (
    tester,
  ) async {
    final app = await openPlace(tester, campsite);
    final trip = await app.favorites.createList('Bretagne 2027');
    await app.favorites.add(trip, campsite.summary);
    await app.favorites.addToDefault(campsite.summary);
    await settleShort(tester);
    await tester.tap(find.text('Enregistré'));
    await settleShort(tester);
    expect(app.favorites.entries.map((e) => e.listId), [trip], reason: 'the trip list keeps it');
    expect(find.text('Retiré de Mes favoris'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await settleShort(tester);
    expect(app.favorites.entries.map((e) => e.listId).toSet(), {trip, 1});
  });

  testWidgets('a screen reader saves, shares and copies from the place actions', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openPlace(tester, campsite);
    tester.semantics.tap(find.semantics.byLabel('Enregistrer'));
    await settleShort(tester);
    expect(app.favorites.entries.map((e) => e.placeId), [campsite.id]);
    tester.semantics.tap(find.semantics.byLabel('Partager'));
    await settleShort(tester);
    expect(app.external.shared, hasLength(1));
    tester.semantics.tap(find.semantics.byLabel('Copier'));
    await settleShort(tester);
    expect(find.textContaining('Copié'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a screen reader reaches "add a photo" beside the photos', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPlace(tester, lakeArea);
    tester.semantics.tap(find.semantics.byLabel('Ajouter une photo'));
    await settleShort(tester);
    expect(find.text('Photos : à partir du niveau\u00a01'), findsOneWidget, reason: 'its gate');
    semantics.dispose();
  });

  testWidgets('the lists offered after a save still open once the place is closed', (tester) async {
    final app = await pumpLunaway(tester);
    final selection = app.container(tester).read(selectionProvider.notifier)
      ..select(PlaceSelection(campsite.id));
    await settleShort(tester);
    await tester.tap(find.text('Enregistrer').hitTestable());
    await settleShort(tester);
    selection.select(null);
    await settleShort(tester);
    expect(find.text('Itinéraire'), findsNothing);
    await tester.tap(find.text('Listes'));
    await settleShort(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Enregistrer dans une liste'), findsOneWidget);
  });

  testWidgets('a place opened again from the search shows from its top', (tester) async {
    final app = await pumpLunaway(tester);
    final selection = app.container(tester).read(selectionProvider.notifier)
      ..select(PlaceSelection(campsite.id));
    await settleShort(tester);
    final details = find
        .descendant(of: find.byType(PlaceDetailsBody), matching: find.byType(Scrollable))
        .first;
    // The sheet up, then the page read down to its reviews.
    for (var i = 0; i < 4; i++) {
      await tester.drag(details, const Offset(0, -400));
      await settleShort(tester);
    }
    final position = tester.state<ScrollableState>(details).position;
    expect(position.pixels, greaterThan(200));
    selection.select(PlaceSelection(campsite.id));
    await settleShort(tester);
    expect(position.pixels, 0, reason: 'not where the reader had left it');
  });

  testWidgets('the lists sheet ticks a list at once and closes on Done', (tester) async {
    final app = await openPlace(tester, campsite);
    await tester.longPress(find.text('Enregistrer'));
    await settleShort(tester);
    await tester.tap(find.text('Mes favoris'));
    await settleShort(tester);
    expect(
      tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Mes favoris')).value,
      isTrue,
      reason: 'saved at once, the sheet open for another list',
    );
    expect(await app.favorites.watchListsOf(campsite.id).first, {1});
    await tester.tap(find.text('Terminé'));
    await settleShort(tester);
    expect(find.text('Enregistrer dans une liste'), findsNothing);
  });

  testWidgets('a save that fails says so', (tester) async {
    final app = await openPlace(tester, campsite);
    app.favorites.failWrites = true;
    await tester.tap(find.text('Enregistrer'));
    await settleShort(tester);
    expect(find.text("La modification n'a pas pu être enregistrée."), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget, reason: 'still not saved');
  });

  testWidgets('a long press on save picks the lists, with no tooltip in the way', (tester) async {
    await openPlace(tester, campsite);
    await tester.longPress(find.text('Enregistrer'));
    await settleShort(tester);
    expect(find.text('Enregistrer dans une liste'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Enregistrer'), matching: find.byType(Tooltip)),
      findsNothing,
    );
  });

  testWidgets('with a mouse, a right click on save picks the lists, and the hint says so', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final semantics = tester.ensureSemantics();
      await openPlace(tester, campsite);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Enregistrer')).hint,
        'Dans Mes favoris. Clic droit pour choisir des listes.',
      );
      await tester.tap(find.text('Enregistrer'), buttons: kSecondaryButton);
      await settleShort(tester);
      expect(find.text('Enregistrer dans une liste'), findsOneWidget);
      semantics.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('with large text on a phone the actions stack and no label is cut', (tester) async {
    final app = await pumpLunaway(tester, textScale: 2);
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(campsite.id));
    await settleShort(tester);
    expect(tester.takeException(), isNull);
    final directions = tester.getRect(find.text('Itinéraire'));
    for (final label in ['Enregistrer', 'Partager', 'Copier']) {
      final text = find.text(label).hitTestable();
      expect(text, findsOneWidget, reason: label);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(
        tester.getRect(text).width,
        lessThanOrEqualTo(phone.width / 3),
        reason: '$label fits its third of the row',
      );
      expect(tester.getRect(text).top, greaterThan(directions.bottom), reason: 'on a second row');
    }
  });

  testWidgets('the rating shows with its review count', (tester) async {
    await openPlace(tester, lakeArea);
    // 4.3 over 128 reviews and 4.0 over 2, weighted.
    expect(inDetails(find.text('4,3 (130)')), findsOneWidget);
    expect(inDetails(find.text('4,3 (128)')), findsOneWidget);
  });

  testWidgets('the description falls back to another language and says which', (tester) async {
    await openPlace(tester, lakeArea);
    expect(find.text('Invented area by the lake.'), findsOneWidget);
    expect(find.text("Texte d'origine en anglais"), findsOneWidget);
  });

  testWidgets('in the description language, no note is shown', (tester) async {
    await openPlace(tester, lakeArea, locale: AppLocale.en);
    expect(find.text('Invented area by the lake.'), findsOneWidget);
    expect(find.textContaining('Original text'), findsNothing);
  });

  testWidgets('photos open full screen, one at a time', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPlace(tester, lakeArea);
    // Each photo is named with its rank and its source, badged on the image.
    final first = find.bySemanticsLabel('Photo 1 sur 3, Lunaway');
    expect(first, findsOneWidget);
    await tester.tap(first);
    await settleShort(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1500);
    await settleShort(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Fermer').last);
    await settleShort(tester);
    expect(find.text('2 / 3'), findsNothing);
    semantics.dispose();
  });

  testWidgets('reviews show their source, author and vehicle, with more on demand', (tester) async {
    await openPlace(tester, lakeArea);
    // The reviews are items of the card's list, built as they come into
    // view.
    await tester.scrollUntilVisible(
      find.text('Avis inventé numéro 1.'),
      400,
      scrollable: inDetails(find.byType(Scrollable)).first,
    );
    expect(find.text('Avis inventé numéro 1.'), findsOneWidget);
    expect(find.text('Avis inventé numéro 3.'), findsNothing);
    expect(find.textContaining('Voyageur démo 1 · Fourgon aménagé'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text("Plus d'avis"),
      200,
      scrollable: inDetails(find.byType(Scrollable)).first,
    );
    await settleShort(tester);
    await tester.tap(find.text("Plus d'avis"));
    await settleShort(tester);
    expect(find.text('Avis inventé numéro 3.', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Avis inventé numéro 5.', skipOffstage: false),
      findsNothing,
      reason: 'two per page',
    );
  });

  testWidgets('offline without a cached copy, photos and reviews say they need a connection', (
    tester,
  ) async {
    await openPlace(
      tester,
      lakeArea,
      extras: FakeExtrasSource(photos: samplePhotos)..online = false,
    );
    expect(
      find.text("Pas de connexion : les photos et les avis s'afficheront au retour du réseau."),
      findsWidgets,
    );
    expect(
      find.text('Nuit autorisée'),
      findsWidgets,
      reason: 'the rest of the place still shows offline',
    );
  });

  testWidgets('a place opened offline gets its photos and reviews once the network is back', (
    tester,
  ) async {
    const offline = "Pas de connexion : les photos et les avis s'afficheront au retour du réseau.";
    final extras = FakeExtrasSource(photos: samplePhotos)..online = false;
    final app = await pumpLunaway(
      tester,
      size: const Size(1280, 3200),
      extras: extras,
      reachable: false,
    );
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
    await settleShort(tester);
    expect(find.text(offline), findsWidgets);

    final fetches = extras.fetches;
    extras.online = true;
    app.container(tester).read(basemapReachabilityProvider.notifier).assume(reachable: true);
    await settleShort(tester);
    expect(find.text(offline), findsNothing, reason: 'read again without a tap');
    expect(extras.fetches, greaterThan(fetches));
  });

  testWidgets('the sources show their licence, attribution and a link', (tester) async {
    final app = await openPlace(tester, lakeArea);
    await tester.scrollUntilVisible(
      find.text('ODbL-1.0'),
      400,
      scrollable: inDetails(find.byType(Scrollable)).first,
    );
    expect(find.text('ODbL-1.0'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('Atout France'), findsWidgets);
    expect(find.textContaining('Correspondance'), findsNothing, reason: 'an internal score');
    await tester.ensureVisible(find.text('Voir à la source'));
    await tester.pump();
    await tester.tap(find.text('Voir à la source'));
    expect(app.external.opened.single.toString(), 'https://www.openstreetmap.org/node/1');
  });

  testWidgets('a link named as its source says the name once', (tester) async {
    final linked = Place(
      id: 'test-linked',
      name: 'Aire des Liens (démo)',
      kind: PlaceKind.motorhomeArea,
      lat: 44.48,
      lon: 4.68,
      overnight: OvernightStatus.allowed,
      updatedAt: DateTime.utc(2026, 9),
      sources: [
        PlaceSource(source: osm, externalId: 'way/303783613', fetchedAt: DateTime.utc(2026, 10, 3)),
      ],
      externalLinks: const [
        ExternalLink(
          sourceId: 'osm',
          url: 'https://www.openstreetmap.org/way/303783613',
          label: 'OpenStreetMap',
        ),
        ExternalLink(
          sourceId: 'wikidata',
          url: 'https://www.wikidata.org/wiki/Q1',
          label: 'Aire de Viviers',
        ),
      ],
    );
    await openPlace(tester, linked, places: [linked, ...samplePlaces]);
    final links = find.ancestor(of: find.text("Sur d'autres sites"), matching: find.byType(Column));
    await tester.scrollUntilVisible(
      find.text('Aire de Viviers'),
      400,
      scrollable: inDetails(find.byType(Scrollable)).first,
    );
    expect(
      find.descendant(of: links.first, matching: find.text('OpenStreetMap')),
      findsOneWidget,
      reason: 'not "OpenStreetMap / OpenStreetMap"',
    );
    expect(
      find.descendant(of: links.first, matching: find.text('Wikidata')),
      findsOneWidget,
      reason: 'a page named otherwise keeps its source under it',
    );
  });

  testWidgets('a place gone from the data says so', (tester) async {
    final app = await pumpLunaway(tester, size: desktop);
    app.container(tester).read(selectionProvider.notifier).select(const PlaceSelection('removed'));
    await settleShort(tester);
    expect(find.text("Ce lieu n'est plus sur la carte"), findsOneWidget);
  });
}
