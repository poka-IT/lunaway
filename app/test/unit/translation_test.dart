import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/features/places/data/demo/demo_server.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/translation/application/translation_providers.dart';
import 'package:lunaway/features/translation/data/translation_source.dart';
import 'package:lunaway/features/translation/domain/translation.dart';

import '../helpers/translation_fakes.dart';

const _review = TranslatableItem.externalReview('7a000000-0000-4000-8000-000000000003');
const _description = TranslatableItem.description(placeId: 'p1', sourceId: 'osm', lang: 'und');

void main() {
  group('which texts offer a translation', () {
    test('a text in another language than the app', () {
      expect(offersTranslation(lang: 'de', text: 'Sehr schön', appLanguage: 'fr'), isTrue);
      expect(
        offersTranslation(lang: 'fr-CA', text: 'Très beau', appLanguage: 'fr'),
        isFalse,
        reason: 'a regional French is French',
      );
    });

    test('a text of unknown language only when long enough to have one', () {
      expect(
        offersTranslation(lang: 'und', text: 'Ruhiger Platz am See, sauber', appLanguage: 'fr'),
        isTrue,
      );
      expect(offersTranslation(lang: null, text: 'Top !', appLanguage: 'fr'), isFalse);
    });
  });

  group('the request names the item, never the text', () {
    late List<Map<String, dynamic>> sent;
    late String answer;
    late int status;

    GraphQLTranslationSource source() => GraphQLTranslationSource(
      GraphQLClient(
        endpoint: Uri.parse('https://api.lunaway.net/graphql'),
        httpClient: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response.bytes(
            utf8.encode(answer),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
        userAgent: 'Lunaway/test (+https://lunaway.net)',
        sleep: (_) async {},
      ),
    );

    String error(String code, {String? reason, int? retryAfter}) => jsonEncode({
      'data': null,
      'errors': [
        {
          'message': 'refused',
          'extensions': {'code': code, 'reason': ?reason, 'retryAfterSeconds': ?retryAfter},
        },
      ],
    });

    setUp(() {
      sent = [];
      status = 200;
      answer = jsonEncode({
        'data': {
          'translate': {
            'text': 'Very nice place.',
            'sourceLang': 'de',
            'targetLang': 'en',
            'engine': 'opus-mt',
            'model': 'de-en opus+bt-2021-04-30',
          },
        },
      });
    });

    test('a review by its id alone, and the translation read back', () async {
      final t = await source().translate(_review, 'en');
      expect(t.text, 'Very nice place.');
      expect(t.sourceLang, 'de');
      expect(t.needed, isTrue);
      final variables = sent.single['variables'] as Map<String, dynamic>;
      expect(variables, {'kind': 'EXTERNAL_REVIEW', 'id': _review.id, 'targetLang': 'en'});
      expect(jsonEncode(sent.single), isNot(contains('Sehr')), reason: 'no text leaves the app');
    });

    test('a description by its place, source and language', () async {
      await source().translate(_description, 'fr');
      expect(sent.single['variables'], {
        'kind': 'DESCRIPTION',
        'id': 'p1',
        'sourceId': 'osm',
        'lang': 'und',
        'targetLang': 'fr',
      });
    });

    Future<TranslationFailure> failure() async {
      try {
        await source().translate(_review, 'fr');
      } on TranslationException catch (e) {
        return e.failure;
      }
      fail('the translation should have failed');
    }

    test('each refusal of the server says why', () async {
      answer = error('INVALID_INPUT', reason: 'UNSUPPORTED_LANGUAGE');
      expect(await failure(), TranslationFailure.unsupported);
      answer = error('NOT_FOUND');
      expect(await failure(), TranslationFailure.gone);
      answer = error('UNAVAILABLE');
      expect(await failure(), TranslationFailure.unavailable);
      answer = error('RATE_LIMITED', retryAfter: 600);
      expect(
        await failure(),
        TranslationFailure.busy,
        reason: 'a quota spent for ten minutes is no spinner to keep up',
      );
    });

    test('no answer at all is offline', () async {
      final offline = GraphQLTranslationSource(
        GraphQLClient(
          endpoint: Uri.parse('https://api.lunaway.net/graphql'),
          httpClient: MockClient((_) async => throw http.ClientException('no route')),
          userAgent: 'Lunaway/test (+https://lunaway.net)',
        ),
      );
      await expectLater(
        offline.translate(_review, 'fr'),
        throwsA(
          isA<TranslationException>().having(
            (e) => e.failure,
            'failure',
            TranslationFailure.offline,
          ),
        ),
      );
    });
  });

  group('the translation of one text', () {
    late FakeTranslationSource source;
    late ProviderContainer container;
    final provider = itemTranslationProvider(_review, 'fr');

    setUp(() {
      source = FakeTranslationSource();
      container = ProviderContainer.test(
        overrides: [translationSourceProvider.overrideWithValue(source)],
      );
    });

    test('starts on the original and asks nothing', () {
      container.listen(provider, (_, _) {});
      expect(container.read(provider), const NotTranslated());
      expect(source.asked, isEmpty);
    });

    test('waits, then shows the translation', () async {
      container.listen(provider, (_, _) {});
      source.gate = Completer<void>();
      final asking = container.read(provider.notifier).translate();
      expect(container.read(provider), const Translating());
      source.gate!.complete();
      await asking;
      final state = container.read(provider);
      expect(state, isA<Translated>());
      expect(
        (state as Translated).translation.text,
        FakeTranslationSource.translationOf(_review, 'fr'),
      );
      expect(state.showingOriginal, isFalse);
    });

    test('goes back to the original and to the translation without a new request', () async {
      container.listen(provider, (_, _) {});
      await container.read(provider.notifier).translate();
      container.read(provider.notifier).showOriginal();
      expect((container.read(provider) as Translated).showingOriginal, isTrue);
      container.read(provider.notifier).showTranslation();
      expect((container.read(provider) as Translated).showingOriginal, isFalse);
      await container.read(provider.notifier).translate();
      expect(source.asked, hasLength(1), reason: 'the server translated it once');
    });

    test('a failure says which, and a retry asks again', () async {
      container.listen(provider, (_, _) {});
      source.failure = TranslationFailure.busy;
      await container.read(provider.notifier).translate();
      expect(container.read(provider), const TranslationFailed(TranslationFailure.busy));
      source.failure = null;
      await container.read(provider.notifier).translate();
      expect(container.read(provider), isA<Translated>());
      expect(source.asked, hasLength(2));
    });

    test('a language without a model stays unsupported', () async {
      container.listen(provider, (_, _) {});
      source.failure = TranslationFailure.unsupported;
      await container.read(provider.notifier).translate();
      expect(container.read(provider), const TranslationFailed(TranslationFailure.unsupported));
    });

    test('a translation made comes back at once when the card shows again', () async {
      final listening = container.listen(provider, (_, _) {});
      await container.read(provider.notifier).translate();
      // The card scrolls out of the list: its provider goes.
      listening.close();
      await pumpEventQueue();
      container.listen(provider, (_, _) {});
      expect(container.read(provider), isA<Translated>());
      expect(source.asked, hasLength(1));
    });
  });

  test('the demo build, without a translation server, answers as one that is down', () async {
    final demo = GraphQLTranslationSource(
      GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: demoApiClient(
          const [],
          apiBase: Uri.parse('https://api.example.org'),
          latency: Duration.zero,
        ),
        userAgent: 'Lunaway/test (+https://lunaway.net)',
      ),
    );
    await expectLater(
      demo.translate(_review, 'fr'),
      throwsA(
        isA<TranslationException>().having(
          (e) => e.failure,
          'failure',
          TranslationFailure.unavailable,
        ),
      ),
    );
  });

  test('the memory keeps the most recent translations only', () {
    final memory = TranslationMemory(capacity: 2);
    const t = Translation(text: 'x', sourceLang: 'de', targetLang: 'fr', engine: 'opus-mt');
    memory
      ..keep(const TranslatableItem.review('1'), 'fr', t)
      ..keep(const TranslatableItem.review('2'), 'fr', t)
      ..keep(const TranslatableItem.review('1'), 'fr', t)
      ..keep(const TranslatableItem.review('3'), 'fr', t);
    expect(memory.read(const TranslatableItem.review('2'), 'fr'), isNull, reason: 'the oldest');
    expect(memory.read(const TranslatableItem.review('1'), 'fr'), t);
    expect(memory.read(const TranslatableItem.review('3'), 'fr'), t);
  });
}
