import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/places/presentation/place_extras_view.dart';
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
/// [reachable] says otherwise.
Future<void> pumpText(
  WidgetTester tester,
  FakeTranslationSource source, {
  String? lang = 'de',
  String text = _german,
  bool autoTranslate = false,
  bool? reachable = true,
}) async {
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
            body: Padding(
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
        find.text('Le service de traduction est occupé. Réessayez dans un instant.'),
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

    testWidgets('offline, the button stays disabled and says why', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, reachable: false);
      expect(button(tester, 'Traduire').onPressed, isNull);
      expect(find.text('La traduction a besoin du réseau.'), findsOneWidget);
      await tester.tap(find.text('Traduire'), warnIfMissed: false);
      await tester.pump();
      expect(source.asked, isEmpty);
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

    testWidgets('offline, nothing is asked', (tester) async {
      final source = FakeTranslationSource();
      await pumpText(tester, source, autoTranslate: true, reachable: false);
      await tester.pump();
      expect(source.asked, isEmpty);
      expect(find.text(_german), findsOneWidget);
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
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(extcomArea.id));
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
      app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      final details = find.byType(PlaceDetailsBody);
      expect(
        find.descendant(of: details, matching: find.text("Texte d'origine en anglais")),
        findsOneWidget,
      );
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
      expect(find.text("Texte d'origine en anglais"), findsOneWidget);
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
