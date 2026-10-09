import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fake_api.dart';
import '../helpers/fonts.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// Labels measured in the app's own typeface: the test font draws every
/// glyph as a square and would decide nothing about the real widths. Kept
/// in its own file, as the fonts stay loaded for the rest of the file.
void main() {
  setUpAll(loadRealFonts);

  for (final (locale, labels) in [
    (AppLocale.fr, ['Itinéraire', 'Enregistrer', 'Partager', 'Copier']),
    (AppLocale.en, ['Directions', 'Save', 'Share', 'Copy']),
  ]) {
    testWidgets('on a common phone every action of a place shows its label at full size, '
        'in one row (${locale.languageCode})', (tester) async {
      final app = await pumpLunaway(tester, size: const Size(412, 915), locale: locale);
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      final directionsText = find.text(labels.first).last;
      final directions = tester.getRect(directionsText);
      final button = tester.getRect(
        find.ancestor(
          of: directionsText,
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      for (final label in labels.skip(1)) {
        final text = find.text(label).last;
        final fitted = find.ancestor(of: text, matching: find.byType(FittedBox)).first;
        expect(
          tester.getSize(fitted).width,
          greaterThanOrEqualTo(tester.getSize(text).width),
          reason: '"$label" is not shrunk',
        );
        expect(tester.getRect(text).center.dy, lessThan(button.bottom), reason: 'one row');
      }
      // "Itinéraire" stays on one line.
      expect(directions.height, lessThan(30));
    });
  }

  testWidgets('on a small phone the recovery card reads its name and its date on one line each', (
    tester,
  ) async {
    await pumpLunaway(
      tester,
      size: const Size(360, 3200),
      api: FakeApi(),
      signedIn: true,
      recoveryCardAt: DateTime.utc(2026, 10, 6, 12),
    );
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    final name = find.text('Carte de secours');
    final date = find.text('Faite le 6 oct. 2026');
    expect(name, findsOneWidget);
    expect(date, findsOneWidget);
    expect(find.text('Refaire'), findsOneWidget);
    final line = tester.getSize(find.text('Refaire')).height;
    expect(tester.getSize(name).height, lessThan(line * 1.6));
    expect(tester.getSize(date).height, lessThan(line * 1.6));
    // The short button names its object for a screen reader.
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Refaire la carte de secours')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('on a phone what the night includes reads whole under the facts, '
      'which keep the size they have without it', (tester) async {
    Place area(String id, Set<PriceInclusion> includes) => Place(
      id: id,
      name: 'Aire des Prix (démo)',
      kind: PlaceKind.motorhomeArea,
      lat: lakeArea.lat,
      lon: lakeArea.lon,
      overnight: OvernightStatus.allowed,
      updatedAt: lakeArea.updatedAt,
      priceParkingEur: 14.5,
      priceServicesIncluded: true,
      priceParkingIncludes: includes,
      maxHeightM: 3.2,
      capacity: 30,
    );
    final full = area('test-inclusions', const {
      PriceInclusion.services,
      PriceInclusion.touristTax,
      PriceInclusion.electricity,
    });
    final plain = area('test-no-inclusions', const {});
    // A common phone's width; tall enough for the whole card to be built.
    final app = await pumpLunaway(tester, size: const Size(393, 1800), places: [full, plain]);
    Rect tileOf(Finder value) =>
        tester.getRect(find.ancestor(of: value, matching: find.byType(Container)).first);
    final priceValue = find.textContaining(RegExp(r'^14,50\s€$'));

    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(plain.id));
    await settleShort(tester);
    final without = tileOf(priceValue);

    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(full.id));
    await settleShort(tester);
    final note = find.text('Le prix de la nuit comprend : services, taxe de séjour, électricité');
    expect(note, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: note, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'no word of the list is cut');
    final price = tileOf(priceValue);
    expect(price.size, without.size, reason: 'the note does not stretch the price and its row');
    final noteRect = tester.getRect(note);
    expect(noteRect.top, greaterThan(tileOf(find.text('30')).bottom), reason: 'under the facts');
    expect(noteRect.left, price.left);
  });

  testWidgets('a long place name shows whole in the header of its sheet', (tester) async {
    final long = Place(
      id: 'test-long',
      name: 'Aire de stationnement camping-cars de Colmyr',
      kind: PlaceKind.motorhomeArea,
      lat: 45.8906,
      lon: 6.1388,
      overnight: OvernightStatus.allowed,
      address: const Address(city: 'Annecy', postcode: '74000'),
      updatedAt: DateTime.utc(2026, 9),
      sources: [
        PlaceSource(source: osm, externalId: 'way/9', fetchedAt: DateTime.utc(2026, 10, 3)),
      ],
    );
    final app = await pumpLunaway(
      tester,
      size: const Size(412, 915),
      places: [long, ...samplePlaces],
    );
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(long.id));
    await settleShort(tester);
    final title = find.text('Aire de stationnement camping-cars de Colmyr');
    expect(tester.renderObject<RenderParagraph>(title.first).didExceedMaxLines, isFalse);
  });
}
