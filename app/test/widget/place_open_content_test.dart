import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../fixtures/place_open_content.dart';
import '../helpers/fakes.dart';
import '../helpers/fonts.dart';
import '../helpers/pump.dart';
import 'place_external_test.dart'
    show extcomArea, inDetails, openExtcom, reviewCard, scrollTo, swipePhotos;

FakeExternalSource openSources() =>
    FakeExternalSource(content: externalOperation.parse(openContentFixture())!);

void main() {
  setUpAll(loadRealFonts);

  test('reads the kind, licence and page of each item of the open sources', () {
    final content = externalOperation.parse(openContentFixture())!;
    final [street, nearby] = content.photos;
    expect(street.kind, PhotoKind.streetView);
    expect(street.terms?.publisher, 'Panoramax OpenStreetMap France');
    expect(nearby.kind, PhotoKind.surroundings);
    expect(nearby.terms?.pageUrl, startsWith('https://commons.wikimedia.org/'));
    final review = content.reviews.nodes.single;
    expect(review.terms?.licence, 'CC BY 4.0');
    final text = content.descriptions.single;
    expect(text.terms.updatedOn, DateTime(2026, 8, 4));
    expect(text.shortened, isTrue, reason: 'Lunaway cut it: the card links to the whole text');
  });

  testWidgets('a street view and a photo of the surroundings say what they show', (tester) async {
    final semantics = tester.ensureSemantics();
    await openExtcom(tester, external: openSources());
    await swipePhotos(tester);
    await settleShort(tester);
    expect(
      find.bySemanticsLabel(RegExp('Panoramax · Vue de la rue · PanierAvide')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Wikimedia Commons · Aux alentours · Pierre')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel(RegExp('Aux alentours')));
    await settleShort(tester);
    final viewer = find.byType(PhotoViewer);
    expect(
      find.descendant(of: viewer, matching: find.textContaining('CC BY-SA 4.0')),
      findsOneWidget,
      reason: 'the licence shows with the photo',
    );
    await tester.tap(find.descendant(of: viewer, matching: find.byTooltip("Plus d'actions")));
    await settleShort(tester);
    expect(find.text('Voir à la source'), findsOneWidget);
    expect(find.text('Signaler cette photo'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets("a tourist office's text shows with its office, date and link", (tester) async {
    await openExtcom(tester, external: openSources());
    final text = find.text('Aire de services inventée au bord du lac…');
    await scrollTo(tester, text);
    expect(inDetails(text), findsOneWidget);
    expect(inDetails(find.text('DATAtourisme')), findsOneWidget);
    expect(
      inDetails(
        find.text('Licence Ouverte 2.0 · Office de tourisme inventé · mis à jour le 4 août 2026'),
      ),
      findsOneWidget,
      reason: 'the Licence Ouverte asks for the producer and the date of the last update',
    );
    expect(inDetails(find.text('Lire la suite')), findsOneWidget);
    expect(
      inDetails(find.text('Aire calme sous les pins.')),
      findsOneWidget,
      reason: "the place's own description stays first",
    );
    expect(inDetails(find.text("D'après d'autres sources")), findsOneWidget);
  });

  testWidgets('an open review shows its licence and leads to its page and to a report', (
    tester,
  ) async {
    await openExtcom(tester, external: openSources());
    final card = reviewCard('Avis ouvert inventé, au calme.');
    await scrollTo(tester, card);
    expect(find.descendant(of: card, matching: find.text('Mangrove Reviews')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('CC BY 4.0')), findsOneWidget);
    await tester.tap(find.descendant(of: card, matching: find.byTooltip("Plus d'actions")));
    await settleShort(tester);
    expect(find.text('Voir à la source'), findsOneWidget);
    await tester.tap(find.text('Signaler cet avis'));
    await settleShort(tester);
    expect(find.text('Signaler cet avis'), findsWidgets, reason: 'the report sheet opens');
  });

  testWidgets('in English the kinds read "Street view" and "Surroundings"', (tester) async {
    final semantics = tester.ensureSemantics();
    await openExtcom(tester, external: openSources(), locale: AppLocale.en);
    await swipePhotos(tester);
    await settleShort(tester);
    expect(find.bySemanticsLabel(RegExp('Panoramax · Street view')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Wikimedia Commons · Surroundings')), findsOneWidget);
    expect(extcomArea.id, 'test-extcom');
    semantics.dispose();
  });
}
