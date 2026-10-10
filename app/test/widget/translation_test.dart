import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/translation/application/translation_providers.dart';
import 'package:lunaway/features/translation/domain/translation.dart';
import 'package:lunaway/features/translation/presentation/translatable_text.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

import '../helpers/fakes.dart';
import '../helpers/poi_fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';
import '../helpers/translation_fakes.dart';
import 'filters_favorites_profile_test.dart' show openTab, showInProfile, tallPhone;
import 'place_external_test.dart' show extcomArea, recorded, reviewCard;

const _german = 'Sehr schöner Platz am See, sauber und ruhig.';
const _item = TranslatableItem.externalReview('7a000000-0000-4000-8000-000000000009');
final String _translated = FakeTranslationSource.translationOf(_item, 'fr');

/// [TranslatableText] alone, in French, over [source], online unless
/// [reachable] says otherwise, in a window [width] wide at [textScale].
Future<void> pumpText(
  WidgetTester tester,
  FakeTranslationSource source, {
  String? lang = 'de',
  String text = _german,
  bool autoTranslate = false,
  bool? reachable = true,
  double width = 400,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationSourceProvider.overrideWithValue(source),
        basemapReachabilityProvider.overrideWith(() => FixedReachability(reachable: reachable)),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          theme: lunaTheme(Brightness.light),
          home: Scaffold(
            // In a scrolling list, as a card's text is.
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TranslatableText(
                item: _item,
                text: text,
                lang: lang,
                autoTranslate: autoTranslate,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

TextButton button(WidgetTester tester, String label) => tester.widget<TextButton>(
  find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
);

/// The providers of the text pumped by [pumpText].
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TranslatableText)));

const _lunawayReview = '7b000000-0000-4000-8000-0000000000de';

/// A review of Lunaway's community, in German.
final _germanReview = Review(
  id: _lunawayReview,
  sourceId: communityCcBySourceId,
  rating: 4,
  text: _german,
  lang: 'de',
  authorName: 'Loutre du Doubs',
  createdAt: DateTime.utc(2026, 9),
);

Finder _detailsScrollable() =>
    find.descendant(of: find.byType(PlaceDetailsBody), matching: find.byType(Scrollable)).first;

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('a text in another language', () {
    testWidgets('in the reader language, nothing is offered', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, lang: 'fr', text: 'Très bel endroit au calme.');
      expect(find.text('Très bel endroit au calme.'), findsOneWidget);
      expect(find.text('Traduire'), findsNothing);
    });

    testWidgets('a touch translates it, marked as automatic with its language', (tester) async {
      final source = FakeTranslationSource()..gate = Completer<void>();
      await pumpText(tester, source);
      expect(find.text(_german), findsOneWidget);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      expect(find.text('Traduction en cours'), findsOneWidget);
      expect(find.text(_german), findsOneWidget, reason: 'the original stays while it waits');
      source.gate!.complete();
      await tester.pump();
      expect(find.text(_translated), findsOneWidget);
      expect(find.text(_german), findsNothing);
      expect(find.text("Traduit automatiquement de l'allemand"), findsOneWidget);
      expect(source.asked.single, (_item, 'fr'));
    });

    testWidgets('the original is one touch away, and the translation one more, asked once', (
      tester,
    ) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      await tester.tap(find.text("Voir l'original"));
      await tester.pump();
      expect(find.text(_german), findsOneWidget);
      expect(find.text("Traduit automatiquement de l'allemand"), findsNothing);
      await tester.tap(find.text('Voir la traduction'));
      await tester.pump();
      expect(find.text(_translated), findsOneWidget);
      expect(source.asked, hasLength(1));
    });

    testWidgets('a busy server says so, and a retry translates', (tester) async {
      final source = FakeTranslationSource(failure: TranslationFailure.busy);
      await pumpText(tester, source);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      expect(
        find.text('Le service de traduction est occupé. Réessayez plus tard.'),
        findsOneWidget,
      );
      expect(find.text(_german), findsOneWidget);
      source.failure = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      expect(find.text(_translated), findsOneWidget);
      expect(source.asked, hasLength(2));
    });

    testWidgets('a language without a model says so and offers nothing more', (tester) async {
      final source = FakeTranslationSource(failure: TranslationFailure.unsupported);
      await pumpText(tester, source);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      expect(find.text('Pas de traduction disponible pour cette langue.'), findsOneWidget);
      expect(find.text('Traduire'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('a text given back as it came is said untranslatable, never translated', (
      tester,
    ) async {
      // A review in Finnish taken for German on 2026-10-10,
      // and what the German model gave back of it: one verb of fifteen
      // words changed.
      const finnish =
          'Hyvä hiljainen paikka yöpymiseen. Alueella ajosuunta on niin hölmö että '
          'vesihuoltopisteelle vaikea kääntää yli 6m autolla.';
      final source = FakeTranslationSource()..givesBack = finnish.replaceFirst('kääntää', 'kääntä');
      await pumpText(tester, source, text: finnish, autoTranslate: true);
      await tester.pump();
      expect(find.text('Pas de traduction disponible pour cette langue.'), findsOneWidget);
      expect(find.textContaining('Traduit automatiquement'), findsNothing);
      expect(find.text(finnish), findsOneWidget, reason: 'the original stays, untouched');
    });

    testWidgets('offline, the button stays disabled and says why', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, reachable: false);
      expect(button(tester, 'Traduire').onPressed, isNull);
      expect(find.text('La traduction a besoin du réseau.'), findsOneWidget);
      await tester.tap(find.text('Traduire'), warnIfMissed: false);
      await tester.pump();
      expect(source.asked, isEmpty);
    });

    testWidgets('a screen reader hears what the touch changed', (tester) async {
      final semantics = tester.ensureSemantics();
      final source = FakeTranslationSource()..gate = Completer<void>();
      await pumpText(tester, source);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      expect(
        tester.getSemantics(find.text('Traduction en cours')),
        matchesSemantics(isLiveRegion: true, label: 'Traduction en cours'),
      );
      source.gate!.complete();
      await tester.pump();
      expect(
        tester.getSemantics(find.text("Traduit automatiquement de l'allemand")),
        matchesSemantics(isLiveRegion: true, label: "Traduit automatiquement de l'allemand"),
        reason: 'the button touched is gone, and the result is said as it appears',
      );
      semantics.dispose();
    });

    testWidgets("the original is read out in its own language, the translation in the app's", (
      tester,
    ) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source);
      final original = tester.widget<Text>(find.text(_german));
      expect((original.textSpan! as TextSpan).locale, const Locale('de'));
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      final translation = tester.widget<Text>(find.text(_translated));
      expect((translation.textSpan! as TextSpan).locale, const Locale('fr'));
    });

    testWidgets('the wait fits a narrow card at a large text size', (tester) async {
      final source = FakeTranslationSource()..gate = Completer<void>();
      await pumpText(tester, source, width: 200, textScale: 2);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      expect(find.text('Traduction en cours'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the words wrap, nothing overflows');
      final paragraph = tester.renderObject<RenderParagraph>(find.text('Traduction en cours'));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(paragraph.getMinIntrinsicHeight(paragraph.size.width)),
        reason: 'the wrapped lines get their height, none is cut',
      );
      source.gate!.complete();
      await tester.pump();
    });

    testWidgets('offline after a failure, the retry is disabled and says why', (tester) async {
      final source = FakeTranslationSource(failure: TranslationFailure.busy);
      await pumpText(tester, source);
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      containerOf(tester).read(basemapReachabilityProvider.notifier).assume(reachable: false);
      await tester.pump();
      expect(button(tester, 'Réessayer').onPressed, isNull);
      expect(find.text('La traduction a besoin du réseau.'), findsOneWidget);
    });

    testWidgets('a text the server finds in the reader language shows as it is', (tester) async {
      final source = FakeTranslationSource(sameLanguage: true);
      await pumpText(tester, source, lang: 'und');
      await tester.tap(find.text('Traduire'));
      await tester.pump();
      expect(find.text(_german), findsOneWidget);
      expect(find.text('Traduire'), findsNothing);
      expect(find.textContaining('Traduit automatiquement'), findsNothing);
    });
  });

  group('with the setting on', () {
    testWidgets('a review is translated without a touch', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, autoTranslate: true);
      await tester.pump();
      expect(find.text(_translated), findsOneWidget);
      expect(find.text("Voir l'original"), findsOneWidget);
      expect(source.asked, hasLength(1));
    });

    testWidgets('a review translated without a touch is not announced', (tester) async {
      final semantics = tester.ensureSemantics();
      final source = FakeTranslationSource();
      await pumpText(tester, source, autoTranslate: true);
      await tester.pump();
      expect(
        tester.getSemantics(find.text("Traduit automatiquement de l'allemand")),
        isSemantics(isLiveRegion: false, label: "Traduit automatiquement de l'allemand"),
        reason: 'every review coming into view would otherwise speak up',
      );
      semantics.dispose();
    });

    testWidgets('offline, nothing is asked', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, autoTranslate: true, reachable: false);
      await tester.pump();
      expect(source.asked, isEmpty);
      expect(find.text(_german), findsOneWidget);
    });

    testWidgets('a failed attempt leaves the plain button, not an error', (tester) async {
      final source = FakeTranslationSource(failure: TranslationFailure.unavailable);
      await pumpText(tester, source, autoTranslate: true);
      await tester.pump();
      expect(source.asked, hasLength(1));
      expect(find.text("La traduction n'est pas disponible pour l'instant."), findsNothing);
      expect(find.text('Traduire'), findsOneWidget);
      await tester.pump();
      expect(source.asked, hasLength(1), reason: 'asked once, not in a loop');
    });

    testWidgets('a new app language is translated into again', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, autoTranslate: true);
      await tester.pump();
      expect(source.asked, [(_item, 'fr')]);
      await LocaleSettings.setLocale(AppLocale.en);
      await tester.pump();
      await tester.pump();
      expect(source.asked, [(_item, 'fr'), (_item, 'en')]);
      expect(find.text(FakeTranslationSource.translationOf(_item, 'en')), findsOneWidget);
    });
  });

  group('on the card of a place', () {
    testWidgets("only the external review in English offers a translation, by the review's id", (
      tester,
    ) async {
      final source = FakeTranslationSource(sourceLang: 'en');
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        external: recorded(),
        // No review of Lunaway's own: the source's three show at once,
        // none waiting behind a next page of Lunaway's.
        extras: FakeExtrasSource(),
        places: [extcomArea, ...samplePlaces],
        overrides: [translationSourceProvider.overrideWithValue(source)],
      );
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(extcomArea.id));
      await settleShort(tester);
      final english = reviewCard('Invented external review number 3.');
      await tester.scrollUntilVisible(
        english,
        300,
        scrollable: find
            .descendant(of: find.byType(PlaceDetailsBody), matching: find.byType(Scrollable))
            .first,
      );
      expect(
        find.descendant(
          of: reviewCard('Avis externe inventé numéro 1.'),
          matching: find.text('Traduire'),
        ),
        findsNothing,
        reason: 'a French review for a French reader',
      );
      await tester.tap(find.descendant(of: english, matching: find.text('Traduire')));
      await settleShort(tester);
      const item = TranslatableItem.externalReview('7a000000-0000-4000-8000-000000000003');
      expect(source.asked.single, (item, 'fr'));
      expect(find.text(FakeTranslationSource.translationOf(item, 'fr')), findsOneWidget);
      expect(find.text("Traduit automatiquement de l'anglais"), findsOneWidget);
      expect(find.byType(ReviewCard), findsWidgets);
    });

    testWidgets('a description in another language says it once, translated or not', (
      tester,
    ) async {
      final source = FakeTranslationSource(sourceLang: 'en');
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        overrides: [translationSourceProvider.overrideWithValue(source)],
      );
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      final details = find.byType(PlaceDetailsBody);
      // Written in German and English: the chip of the text shown names its
      // language, and no line says it again.
      final english = find.descendant(of: details, matching: find.text('EN'));
      expect(english, findsOneWidget);
      expect(find.text("Texte d'origine en anglais"), findsNothing);
      await tester.tap(find.descendant(of: details, matching: find.text('Traduire')));
      await settleShort(tester);
      final item = TranslatableItem.description(
        placeId: lakeArea.id,
        sourceId: 'community',
        lang: 'en',
      );
      expect(source.asked.single, (item, 'fr'));
      expect(find.text(FakeTranslationSource.translationOf(item, 'fr')), findsOneWidget);
      expect(find.text("Traduit automatiquement de l'anglais"), findsOneWidget);
      expect(
        find.text("Texte d'origine en anglais"),
        findsNothing,
        reason: 'the translation line already says it',
      );
      await tester.tap(find.text("Voir l'original"));
      await settleShort(tester);
      expect(find.text('Invented area by the lake.'), findsOneWidget);
      expect(english, findsOneWidget, reason: 'its chip says it');
      expect(find.text("Texte d'origine en anglais"), findsNothing);
    });

    testWidgets("a Lunaway review is named by its own id, apart from the other sources'", (
      tester,
    ) async {
      final source = FakeTranslationSource();
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        external: FakeExternalSource(),
        extras: FakeExtrasSource(reviews: [_germanReview]),
        places: [extcomArea, ...samplePlaces],
        overrides: [translationSourceProvider.overrideWithValue(source)],
      );
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(extcomArea.id));
      await settleShort(tester);
      final card = reviewCard(_german);
      await tester.scrollUntilVisible(card, 300, scrollable: _detailsScrollable());
      await tester.tap(find.descendant(of: card, matching: find.text('Traduire')));
      await settleShort(tester);
      const item = TranslatableItem.review(_lunawayReview);
      expect(source.asked.single, (item, 'fr'));
      expect(find.text(FakeTranslationSource.translationOf(item, 'fr')), findsOneWidget);
    });

    testWidgets('a description of an open source is named by the place, its source and language', (
      tester,
    ) async {
      final source = FakeTranslationSource();
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        external: FakeExternalSource(
          content: const ExternalContent(
            photos: [],
            ratings: [],
            reviews: ReviewPage.empty,
            descriptions: [
              ExternalDescription(
                text: LocalizedText(
                  lang: 'de',
                  text: 'Ein ruhiger Platz unter Kiefern, nahe dem Strand.',
                  sourceId: 'wikipedia',
                ),
                terms: ItemTerms(
                  licence: 'CC BY-SA 4.0',
                  licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
                  pageUrl: 'https://de.wikipedia.org/wiki/Arcachon',
                ),
              ),
            ],
          ),
        ),
        extras: FakeExtrasSource(),
        places: [extcomArea, ...samplePlaces],
        overrides: [translationSourceProvider.overrideWithValue(source)],
      );
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(extcomArea.id));
      await settleShort(tester);
      final details = find.byType(PlaceDetailsBody);
      final origin = find.descendant(
        of: details,
        matching: find.text("Texte d'origine en allemand"),
      );
      await tester.scrollUntilVisible(origin, 300, scrollable: _detailsScrollable());
      expect(origin, findsOneWidget);
      await tester.tap(find.descendant(of: details, matching: find.text('Traduire')));
      await settleShort(tester);
      final item = TranslatableItem.externalDescription(
        placeId: extcomArea.id,
        sourceId: 'wikipedia',
        lang: 'de',
      );
      expect(source.asked.single, (item, 'fr'));
      expect(find.text(FakeTranslationSource.translationOf(item, 'fr')), findsOneWidget);
      expect(find.text("Traduit automatiquement de l'allemand"), findsOneWidget);
      expect(origin, findsNothing, reason: 'the translation line already says it');
    });

    testWidgets('with the setting on, a review in another language comes translated', (
      tester,
    ) async {
      final source = FakeTranslationSource();
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        settings: const AppSettings(autoTranslateReviews: true),
        external: FakeExternalSource(),
        extras: FakeExtrasSource(reviews: [_germanReview]),
        places: [extcomArea, ...samplePlaces],
        overrides: [translationSourceProvider.overrideWithValue(source)],
      );
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(extcomArea.id));
      await settleShort(tester);
      const item = TranslatableItem.review(_lunawayReview);
      final translated = find.text(FakeTranslationSource.translationOf(item, 'fr'));
      await tester.scrollUntilVisible(translated, 300, scrollable: _detailsScrollable());
      expect(translated, findsOneWidget, reason: 'translated without a touch');
      expect(source.asked.single, (item, 'fr'));
    });
  });

  testWidgets('the profile turns the automatic translation of reviews on, and keeps it', (
    tester,
  ) async {
    final app = await pumpLunaway(tester, size: tallPhone);
    await openTab(tester, 'Profil');
    final toggle = find.text('Traduire automatiquement les avis');
    await showInProfile(tester, toggle);
    expect(app.settings.value.autoTranslateReviews, isFalse, reason: 'off until chosen');
    await tester.tap(toggle);
    await settleShort(tester);
    expect(app.settings.value.autoTranslateReviews, isTrue);
  });
}
