import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../fixtures/place_open_content.dart';
import '../helpers/fake_api.dart';
import '../helpers/fakes.dart';
import '../helpers/fonts.dart';
import '../helpers/pump.dart';
import 'place_external_test.dart' show inDetails, openExtcom, reviewCard, scrollTo, swipePhotos;

FakeExternalSource openSources() =>
    FakeExternalSource(content: externalOperation.parse(openContentFixture())!);

/// Picks a reason in the open report sheet and sends it; the community's
/// follow-up sync waits three seconds.
Future<void> sendReport(WidgetTester tester) async {
  final t = AppLocale.fr.buildSync();
  await tester.tap(find.text(t.reportReason(ReportReason.offensive)));
  await tester.pump();
  await tester.tap(find.text(t.common.send));
  await settleShort(tester, const Duration(seconds: 4));
}

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
    final app = await openExtcom(tester, external: openSources());
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
    expect(find.text('Signaler cette photo'), findsOneWidget);
    await tester.tap(find.text('Voir à la source'));
    await settleShort(tester);
    expect(app.external.opened, [
      Uri.parse('https://commons.wikimedia.org/wiki/File:Plage_invent%C3%A9e.jpg'),
    ]);
    semantics.dispose();
  });

  testWidgets('a photo of an open source is reported as an external photo', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = FakeApi();
    await openExtcom(tester, external: openSources(), api: api, signedIn: true);
    await swipePhotos(tester);
    await settleShort(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('Aux alentours')));
    await settleShort(tester);
    final viewer = find.byType(PhotoViewer);
    await tester.tap(find.descendant(of: viewer, matching: find.byTooltip("Plus d'actions")));
    await settleShort(tester);
    await tester.tap(find.text('Signaler cette photo'));
    await settleShort(tester);
    await sendReport(tester);
    expect(api.last('ReportContent'), {
      'target': 'EXTERNAL_PHOTO',
      'id': '0d4f6a1b-4444-4a2b-8c3d-000000000004',
      'reason': 'OFFENSIVE',
    });
    semantics.dispose();
  });

  testWidgets("a tourist office's text shows with its office, date and link", (tester) async {
    final app = await openExtcom(tester, external: openSources());
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
    await tester.tap(inDetails(find.text('Lire la suite')));
    await settleShort(tester);
    expect(app.external.opened, [Uri.parse('https://data.datatourisme.fr/23/invented')]);
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
    final api = FakeApi();
    final app = await openExtcom(tester, external: openSources(), api: api, signedIn: true);
    final card = reviewCard('Avis ouvert inventé, au calme.');
    await scrollTo(tester, card);
    expect(find.descendant(of: card, matching: find.text('Mangrove Reviews')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('CC BY 4.0')), findsOneWidget);
    final more = find.descendant(of: card, matching: find.byTooltip("Plus d'actions"));
    await tester.tap(more);
    await settleShort(tester);
    await tester.tap(find.text('Voir à la source'));
    await settleShort(tester);
    expect(app.external.opened, [Uri.parse('https://mangrove.reviews/list?signature=abc')]);
    await tester.tap(more);
    await settleShort(tester);
    await tester.tap(find.text('Signaler cet avis'));
    await settleShort(tester);
    await sendReport(tester);
    expect(api.last('ReportContent'), {
      'target': 'EXTERNAL_REVIEW',
      'id': '7a000000-0000-4000-8000-000000000009',
      'reason': 'OFFENSIVE',
    });
  });

  testWidgets('in English the kinds read "Street view" and "Surroundings"', (tester) async {
    final semantics = tester.ensureSemantics();
    await openExtcom(tester, external: openSources(), locale: AppLocale.en);
    await swipePhotos(tester);
    await settleShort(tester);
    expect(find.bySemanticsLabel(RegExp('Panoramax · Street view')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Wikimedia Commons · Surroundings')), findsOneWidget);
    semantics.dispose();
  });
}
