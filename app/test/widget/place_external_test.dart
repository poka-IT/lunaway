import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';
import 'package:lunaway/shared/images/retrying_image.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

import '../fixtures/place_external.dart';
import '../helpers/fake_api.dart';
import '../helpers/fakes.dart';
import '../helpers/fonts.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import 'place_open_content_test.dart' show sendReport;

/// A place the external community source describes along with
/// OpenStreetMap, with Lunaway's own rating.
final extcomArea = Place(
  id: 'test-extcom',
  name: 'Aire des Pins (démo)',
  kind: PlaceKind.motorhomeArea,
  lat: 44.66,
  lon: -1.17,
  overnight: OvernightStatus.allowed,
  address: const Address(city: 'Arcachon', countryCode: 'FR'),
  updatedAt: DateTime.utc(2026, 10),
  sources: [
    PlaceSource(source: osm, externalId: 'node/9', fetchedAt: DateTime.utc(2026, 10, 3)),
    PlaceSource(
      // The API's name of the source; the app shows its own wording.
      source: const Source(
        id: 'extcom',
        name: 'Source communautaire externe',
        // The reference of the agreement, as the API served it until
        // 2026-10-08: never shown.
        licence: 'EXTCOM-2026-10-07',
        attribution: "Données d'une communauté partenaire, sous accord écrit.",
        url: 'https://lunaway.net',
      ),
      externalId: 'e-1',
      externalUrl: 'https://partner.example/spot/1',
      fetchedAt: DateTime.utc(2026, 10, 6),
    ),
  ],
  descriptions: const [
    LocalizedText(lang: 'fr', text: 'Aire calme sous les pins.', sourceId: 'extcom'),
  ],
  ratings: const [SourceRating(sourceId: 'community-cc-by', average: 4.3, count: 128)],
);

/// The recorded answer, and an older page behind its cursor.
FakeExternalSource recorded() => FakeExternalSource(
  content: externalOperation.parse(externalFixture())!,
  more: {
    'Mw': ReviewPage(
      nodes: [
        Review(
          id: '7a000000-0000-4000-8000-000000000004',
          sourceId: extcomSourceId,
          text: 'Avis externe plus ancien.',
          authorName: 'Marmotte',
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      ],
      hasNextPage: false,
      totalCount: 1734,
    ),
  },
);

Future<TestApp> openExtcom(
  WidgetTester tester, {
  FakeExternalSource? external,
  Size size = const Size(1280, 2400),
  AppLocale locale = AppLocale.fr,
  FakeApi? api,
  bool signedIn = false,
}) async {
  final app = await pumpLunaway(
    tester,
    size: size,
    locale: locale,
    api: api,
    signedIn: signedIn,
    external: external ?? recorded(),
    places: [extcomArea, ...samplePlaces],
  );
  app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(extcomArea.id));
  await settleShort(tester);
  return app;
}

Finder inDetails(Finder finder) =>
    find.descendant(of: find.byType(PlaceDetailsBody), matching: finder);

Future<void> scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 300, scrollable: inDetails(find.byType(Scrollable)).first);

/// Brings the photo strip into view and swipes it to its last photos,
/// which it builds as they scroll in.
Future<void> swipePhotos(WidgetTester tester) async {
  final strip = find.byType(PlacePhotos);
  await scrollTo(tester, strip);
  // On a phone the sheet opens part way, the strip below the screen's
  // edge: pulling the card up brings it in.
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var i = 0; i < 8 && tester.getCenter(strip).dy > screen.height - 80; i++) {
    await tester.drag(inDetails(find.text('Aire des Pins (démo)')), const Offset(0, -100));
    await settleShort(tester);
  }
  await tester.drag(strip, const Offset(-500, 0));
}

/// The card of the review that says [text].
Finder reviewCard(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(ReviewCard));

void main() {
  // The real typefaces: whether a label fits is measured as users see it.
  setUpAll(loadRealFonts);

  testWidgets('the source joins the reviews by date, each with its label', (tester) async {
    await openExtcom(tester);
    await scrollTo(tester, find.text('Avis inventé numéro 2.'));
    final newest = tester.getTopLeft(find.text('Avis externe inventé numéro 1.')).dy;
    final ours1 = tester.getTopLeft(find.text('Avis inventé numéro 1.')).dy;
    final ours2 = tester.getTopLeft(find.text('Avis inventé numéro 2.')).dy;
    expect(newest, lessThan(ours1));
    expect(ours1, lessThan(ours2));
    expect(
      find.descendant(
        of: reviewCard('Avis externe inventé numéro 1.'),
        matching: find.text('Source communautaire externe'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Loutre des Landes · Camping-car'), findsOneWidget);
    // Lunaway's next page may hold reviews of 7 September: the source's
    // review of that day waits for it.
    expect(find.text('Avis externe inventé numéro 2.', skipOffstage: false), findsNothing);
    // A partner's review is reported to Lunaway's moderators; it has no
    // author to mute and no page to open.
    await tester.tap(
      find.descendant(
        of: reviewCard('Avis externe inventé numéro 1.'),
        matching: find.byTooltip("Plus d'actions"),
      ),
    );
    await settleShort(tester);
    expect(find.text('Signaler cet avis'), findsOneWidget);
    expect(find.textContaining('Masquer'), findsNothing);
    expect(find.text('Voir à la source'), findsNothing);
  });

  testWidgets("a partner's review is reported as an external review", (tester) async {
    final api = FakeApi();
    await openExtcom(tester, api: api, signedIn: true);
    final card = reviewCard('Avis externe inventé numéro 1.');
    await scrollTo(tester, card);
    await tester.tap(find.descendant(of: card, matching: find.byTooltip("Plus d'actions")));
    await settleShort(tester);
    await tester.tap(find.text('Signaler cet avis'));
    await settleShort(tester);
    await sendReport(tester);
    expect(api.last('ReportContent'), {
      'target': 'EXTERNAL_REVIEW',
      'id': '7a000000-0000-4000-8000-000000000001',
      'reason': 'OFFENSIVE',
    });
  });

  testWidgets('more reviews reads on whichever list holds the rest back, to the end', (
    tester,
  ) async {
    final app = await openExtcom(tester);
    Future<void> more() async {
      await scrollTo(tester, find.text("Plus d'avis"));
      // Clear of the action bar at the foot of the panel.
      await tester.drag(inDetails(find.byType(Scrollable)).first, const Offset(0, -300));
      await settleShort(tester);
      await tester.tap(find.text("Plus d'avis"));
      await settleShort(tester);
    }

    // Lunaway's pages first (two reviews each), as long as theirs are the
    // newer unread ones.
    await more();
    await more();
    expect(app.externalSource.pagesAfter, isEmpty);
    // Lunaway read whole: the source's next page.
    await more();
    expect(app.externalSource.pagesAfter, ['Mw']);
    await scrollTo(tester, find.text('Avis externe plus ancien.'));
    expect(find.text('Avis externe inventé numéro 2.', skipOffstage: false), findsOneWidget);
    expect(find.text('Avis inventé numéro 5.', skipOffstage: false), findsOneWidget);
    expect(find.text("Plus d'avis", skipOffstage: false), findsNothing);
  });

  testWidgets("the source's rating stands beside Lunaway's, never added to it", (tester) async {
    await openExtcom(tester);
    await scrollTo(tester, find.text('3,8 (1734)'));
    expect(inDetails(find.text('3,8 (1734)')), findsOneWidget);
    // Lunaway's, in the head of the card and in the reviews.
    expect(inDetails(find.text('4,3 (128)', skipOffstage: false)), findsNWidgets(2));
    expect(inDetails(find.textContaining('(1862)', skipOffstage: false)), findsNothing);
    final badge = find.ancestor(of: find.text('3,8 (1734)'), matching: find.byType(Wrap)).first;
    expect(
      find.descendant(of: badge, matching: find.text('Source communautaire externe')),
      findsOneWidget,
    );
  });

  testWidgets("the source's photos follow Lunaway's, each credited", (tester) async {
    final semantics = tester.ensureSemantics();
    await openExtcom(tester);
    expect(find.bySemanticsLabel(RegExp('^Photo 1 sur 5, Lunaway')), findsOneWidget);
    // The strip builds its photos as they scroll in.
    await tester.drag(find.bySemanticsLabel(RegExp('^Photo 1 sur 5')), const Offset(-500, 0));
    await settleShort(tester);
    expect(
      find.bySemanticsLabel('Photo 4 sur 5, Source communautaire externe · Loutre des Landes'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Photo 5 sur 5, Source communautaire externe'),
      findsOneWidget,
      reason: 'a photo without an author keeps its source',
    );
    await tester.tap(find.bySemanticsLabel(RegExp('^Photo 4 sur 5')));
    await settleShort(tester);
    final viewer = find.byType(PhotoViewer);
    expect(find.descendant(of: viewer, matching: find.text('4 / 5')), findsOneWidget);
    expect(
      find.descendant(of: viewer, matching: find.text('Source communautaire externe')),
      findsOneWidget,
    );
    expect(find.descendant(of: viewer, matching: find.text('Loutre des Landes')), findsOneWidget);
    // A partner's photo is reported to Lunaway's moderators, never opened
    // at its source.
    await tester.tap(find.descendant(of: viewer, matching: find.byTooltip("Plus d'actions")));
    await settleShort(tester);
    expect(find.text('Signaler cette photo'), findsOneWidget);
    expect(find.text('Voir à la source'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the sources list it with its attribution, and its description with its label', (
    tester,
  ) async {
    await openExtcom(tester);
    expect(find.text('Aire calme sous les pins.'), findsOneWidget);
    final description = find
        .ancestor(of: find.text('Aire calme sous les pins.'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: description, matching: find.text('Source communautaire externe')),
      findsOneWidget,
    );
    await scrollTo(tester, find.text("Données d'une communauté partenaire, sous accord écrit."));
    expect(find.text('Accord écrit'), findsOneWidget, reason: 'what the licence is, in words');
    expect(find.textContaining('EXTCOM-'), findsNothing, reason: 'never the reference');
    expect(
      find.text('Voir à la source', skipOffstage: false),
      findsNothing,
      reason: 'no link out to the partner',
    );
  });

  testWidgets('in English the source reads "External community source"', (tester) async {
    await openExtcom(tester, locale: AppLocale.en);
    expect(inDetails(find.text('External community source')), findsWidgets);
    await scrollTo(tester, find.text("Données d'une communauté partenaire, sous accord écrit."));
    expect(find.text('Source communautaire externe'), findsNothing);
    expect(find.text('Written agreement'), findsOneWidget);
  });

  testWidgets('a place without Lunaway reviews says "none" only once the source said too', (
    tester,
  ) async {
    final external = recorded()..hold = Completer<void>();
    final app = await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      extras: FakeExtrasSource(photos: samplePhotos),
      external: external,
      places: [extcomArea, ...samplePlaces],
    );
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(extcomArea.id));
    await settleShort(tester);
    expect(find.text("Aucun avis pour l'instant.", skipOffstage: false), findsNothing);
    external.hold!.complete();
    await settleShort(tester);
    await scrollTo(tester, find.text('Avis externe inventé numéro 1.'));
    expect(find.text("Aucun avis pour l'instant.", skipOffstage: false), findsNothing);

    external
      ..content = ExternalContent.empty
      ..hold = null;
    app.container(tester).read(selectionProvider.notifier).clear();
    await settleShort(tester);
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(extcomArea.id));
    await settleShort(tester);
    await scrollTo(tester, find.text("Aucun avis pour l'instant."));
    expect(find.text("Aucun avis pour l'instant."), findsOneWidget);
  });

  testWidgets(
    'in the strip an external photo carries a short tag on one line, its author included, '
    'the whole name said to a screen reader',
    (tester) async {
      final semantics = tester.ensureSemantics();
      // A thumbnail is as wide on every screen: the desktop's panel shows it.
      await openExtcom(tester);
      await swipePhotos(tester);
      await settleShort(tester);
      final credit = find.descendant(
        of: find.byType(PlacePhotos),
        matching: find.text('Loutre des Landes'),
      );
      expect(credit, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(credit).didExceedMaxLines, isFalse);
      final tags = find.descendant(of: find.byType(PlacePhotos), matching: find.text('Externe'));
      expect(tags, findsNWidgets(2));
      for (final tag in tags.evaluate()) {
        expect((tag.renderObject! as RenderParagraph).didExceedMaxLines, isFalse);
      }
      // The first external photo: its tags in two corners, the middle of
      // the photo clear of both.
      final tile = tester.getRect(
        find.ancestor(of: tags.first, matching: find.byType(ClipRRect)).first,
      );
      for (final tag in [tags.first, credit]) {
        final pill = tester.getRect(
          find.ancestor(of: tag, matching: find.byType(SourceBadge)).first,
        );
        expect(pill.height, lessThan(tile.height / 4), reason: 'one line each');
        expect(pill.contains(tile.center), isFalse, reason: 'the photo shows');
      }
      expect(
        find.descendant(
          of: find.byType(PlacePhotos),
          matching: find.text('Source communautaire externe'),
        ),
        findsNothing,
        reason: 'the long name would cover half the tile',
      );
      expect(
        find.bySemanticsLabel(RegExp('Source communautaire externe · Loutre des Landes')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('a photo the proxy has not fetched yet keeps a still, empty frame', (tester) async {
    // The test API answers the proxy as when the day's budget is spent.
    // The image cache outlives a test: a load another test left hanging
    // would stand in for this one.
    imageCache
      ..clear()
      ..clearLiveImages();
    await openExtcom(tester);
    await swipePhotos(tester);
    // The image cache looks for a copy on disk, real I/O that the test's
    // clock does not move; the API's answer then comes on the test's clock.
    // Under a loaded machine the disk answers later: the frame is read once
    // the load has had its turns, a dozen at most.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    final tile = find.ancestor(
      of: find.descendant(of: find.byType(PlacePhotos), matching: find.text('Externe')),
      matching: find.byType(Stack),
    );
    expect(tile, findsWidgets);
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 200));
      if (i >= 3 &&
          find.descendant(of: tile.first, matching: find.byType(Skeleton)).evaluate().isEmpty) {
        break;
      }
    }
    expect(find.descendant(of: tile.first, matching: find.byType(Skeleton)), findsNothing);
    expect(
      find.descendant(of: tile.first, matching: find.byIcon(AppIcons.noImage)),
      findsNothing,
      reason: 'not an error either',
    );
  });

  testWidgets('on a phone at a large text size the photo viewer keeps its counter', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpLunaway(
      tester,
      textScale: 1.5,
      external: recorded(),
      places: [extcomArea, ...samplePlaces],
    );
    app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(extcomArea.id));
    await settleShort(tester);
    // Opened as the strip opens it, on the source's first photo.
    unawaited(
      showPhotoViewer(
        tester.element(find.byType(PlaceDetailsBody)),
        [...samplePhotos, ...externalOperation.parse(externalFixture())!.photos],
        3,
        fetcher: app.container(tester).read(imageFetcherProvider),
        sources: extcomArea.sources,
      ),
    );
    await settleShort(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(PhotoViewer),
        matching: find.text('Source communautaire externe'),
      ),
      findsOneWidget,
    );
    expect(find.text('4 / 5').hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the card opens at once and fills in when the source answers', (tester) async {
    final semantics = tester.ensureSemantics();
    final external = recorded()..hold = Completer<void>();
    await openExtcom(tester, external: external);
    expect(inDetails(find.text('Aire des Pins (démo)')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Photo 1 sur 3, ')), findsOneWidget);
    await scrollTo(tester, find.text('Avis inventé numéro 1.'));
    expect(find.text('Avis externe inventé numéro 1.', skipOffstage: false), findsNothing);
    external.hold!.complete();
    await settleShort(tester);
    expect(find.text('Avis externe inventé numéro 1.', skipOffstage: false), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Photo 1 sur 5, ')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets("offline, the source leaves no trace and Lunaway's copy still shows", (tester) async {
    await openExtcom(tester, external: recorded()..online = false);
    await scrollTo(tester, find.text('Avis inventé numéro 1.'));
    expect(find.text('Source communautaire externe', skipOffstage: false), findsWidgets);
    expect(find.text('Avis externe inventé numéro 1.', skipOffstage: false), findsNothing);
    expect(find.text('3,8 (1734)', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    testWidgets('on a $name the source and its reviews fit the card', (tester) async {
      await openExtcom(tester, size: size);
      await scrollTo(tester, find.text('Avis externe inventé numéro 1.'));
      final card = reviewCard('Avis externe inventé numéro 1.');
      final label = find.descendant(of: card, matching: find.text('Source communautaire externe'));
      expect(label, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  group('a photo the proxy has not fetched yet', () {
    testWidgets('keeps its placeholder and is asked again once the wait is over', (tester) async {
      final image = _NotYet(const Duration(seconds: 30));
      await tester.pumpWidget(
        MaterialApp(
          home: RetryingImage(
            image: image,
            placeholder: const Text('loading'),
            waiting: const Text('waiting'),
            error: const Text('broken'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('waiting'), findsOneWidget);
      expect(image.loads, 1);
      await tester.pump(const Duration(seconds: 29));
      expect(image.loads, 1, reason: 'never before the wait');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(image.loads, 2);
      expect(find.text('broken'), findsNothing);
    });

    testWidgets('a wait of hours is left to the next time the place opens', (tester) async {
      final image = _NotYet(const Duration(hours: 3));
      await tester.pumpWidget(
        MaterialApp(
          home: RetryingImage(
            image: image,
            placeholder: const Text('loading'),
            waiting: const Text('waiting'),
            error: const Text('broken'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(minutes: 10));
      expect(find.text('waiting'), findsOneWidget);
      expect(image.loads, 1);
    });
  });
}

/// An image the proxy keeps answering "not yet" for.
final class _NotYet extends ImageProvider<_NotYet> {
  new(this.wait);

  final Duration wait;
  int loads = 0;

  @override
  Future<_NotYet> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_NotYet key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(PhotoNotYetException('https://api.lunaway.net/x', wait)),
    );
  }
}
