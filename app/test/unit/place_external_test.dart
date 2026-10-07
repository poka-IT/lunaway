import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/place_external_source.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';

import '../fixtures/place_external.dart';

Review _review(String id, DateTime at, {String source = communityCcBySourceId}) =>
    Review(id: id, sourceId: source, createdAt: at, text: id);

ReviewPage _page(List<Review> nodes, {bool more = false}) =>
    ReviewPage(nodes: nodes, hasNextPage: more, totalCount: nodes.length, endCursor: 'c');

void main() {
  group('the recorded answer', () {
    test('reads photos with their author, the rating apart and reviews with their date', () {
      final content = externalOperation.parse(externalFixture())!;
      expect(content.photos.map((p) => p.authorName), ['Loutre des Landes', null]);
      expect(content.photos.first.createdAt, DateTime.utc(2026, 8, 14, 9, 30));
      expect(content.photos.every((p) => p.sourceId == extcomSourceId), isTrue);
      expect(
        content.ratings.single,
        const SourceRating(sourceId: 'extcom', average: 3.8, count: 1734),
      );
      final reviews = content.reviews;
      expect(reviews.nodes.map((r) => r.createdAt.day), [12, 7, 1]);
      expect(reviews.nodes.first.authorVehicle, ReviewVehicle.motorhome);
      expect(reviews.nodes.last.rating, isNull);
      expect(reviews.hasNextPage, isTrue);
      expect(reviews.endCursor, 'Mw');
      expect(reviews.totalCount, 1734);
    });
  });

  group('reviews from two lists', () {
    test('interleave newest first and hold back what an unread page could precede', () {
      final merged = mergeReviews(
        _page([
          _review('a', DateTime.utc(2026, 9, 9)),
          _review('b', DateTime.utc(2026, 9, 8)),
        ], more: true),
        _page([
          _review('x', DateTime.utc(2026, 9, 12), source: extcomSourceId),
          _review('y', DateTime.utc(2026, 9, 7), source: extcomSourceId),
        ], more: true),
      );
      // Lunaway's next page may hold a review of 7 September or later, so
      // y waits for it.
      expect(merged.reviews.map((r) => r.id), ['x', 'a', 'b']);
      expect(merged.next, ReviewOrigin.lunaway);
    });

    test('the list whose last read review is newer is the one to read on', () {
      final merged = mergeReviews(
        _page([_review('a', DateTime.utc(2026, 9))], more: true),
        _page([_review('x', DateTime.utc(2026, 9, 10), source: extcomSourceId)], more: true),
      );
      expect(merged.reviews.map((r) => r.id), ['x']);
      expect(merged.next, ReviewOrigin.external);
    });

    test('once both lists are read whole, everything shows and nothing is left', () {
      final at = DateTime.utc(2026, 9, 5);
      final merged = mergeReviews(
        _page([_review('a', at), _review('b', DateTime.utc(2026, 8))]),
        _page([_review('x', at, source: extcomSourceId)]),
      );
      expect(merged.reviews.map((r) => r.id), ['a', 'x', 'b'], reason: 'Lunaway first at a tie');
      expect(merged.next, isNull);
    });

    test('a page that announces more but brought nothing holds everything back', () {
      final merged = mergeReviews(
        _page([_review('a', DateTime.utc(2026, 9))]),
        _page(const [], more: true),
      );
      expect(merged.reviews, isEmpty);
      expect(merged.next, ReviewOrigin.external);
    });
  });

  group('the source', () {
    GraphQLClient client(String body) => GraphQLClient(
      endpoint: Uri.parse('https://api.lunaway.net/graphql'),
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      userAgent: 'Lunaway/test (+https://lunaway.net)',
    );

    test('an API that does not serve it yet gives a place nothing from it', () async {
      // Production's answer of 2026-10-07, before the source was deployed.
      final source = GraphQLPlaceExternalSource(
        client(
          r'{"data":null,"errors":[{"message":"Unknown field \"externalRatings\" on type '
          r'\"Place\". Did you mean \"externalLinks\"?","extensions":{"code":"INVALID_INPUT"}}]}',
        ),
      );
      expect(await source.fetch('p', first: 20), ExternalContent.empty);
    });

    test('any other refusal reaches the screen', () async {
      final source = GraphQLPlaceExternalSource(
        client('{"data":null,"errors":[{"message":"boom","extensions":{"code":"INTERNAL"}}]}'),
      );
      await expectLater(source.fetch('p', first: 20), throwsA(isA<GraphQLResponseException>()));
    });

    test('reads the recorded answer', () async {
      final source = GraphQLPlaceExternalSource(client(jsonEncode({'data': externalFixture()})));
      final content = await source.fetch('p', first: 20);
      expect(content.reviews.nodes, hasLength(3));
      expect(content.photos, hasLength(2));
    });
  });

  group('photos through the proxy', () {
    const config = AppConfig(apiBaseUrl: 'https://api.lunaway.net', demo: false, basemapUrl: '');
    const proxied =
        'https://api.lunaway.net/external-photos/0d4f6a1b-2222-4a2b-8c3d-000000000002/thumb';
    late List<Uri> asked;
    late DateTime now;

    ImageFetcher fetcher(http.StreamedResponse Function(Uri url) answer) => ImageFetcher(
      client: MockClient.streaming((r, _) async {
        asked.add(r.url);
        return answer(r.url);
      }),
      config: config,
      userAgent: 'Lunaway/9.9 (+https://lunaway.net)',
      sleep: (_) async {},
      clock: () => now,
    );

    http.StreamedResponse status(int code, [Map<String, String> headers = const {}]) =>
        http.StreamedResponse(const Stream.empty(), code, headers: headers);

    setUp(() {
      asked = [];
      now = DateTime.utc(2026, 10, 7, 12);
    });

    test('takes only the proxy of a photo id, thumb or large, on the API', () {
      final f = fetcher((_) => status(500));
      expect(f.accepts(proxied), isTrue);
      expect(f.accepts(proxied.replaceFirst('/thumb', '/large')), isTrue);
      for (final url in [
        'https://api.lunaway.net/external-photos/not-an-id/thumb',
        proxied.replaceFirst('/thumb', '/original'),
        '$proxied?size=9000',
        proxied.replaceFirst('api.lunaway.net', 'evil.example'),
        proxied.replaceFirst('https:', 'http:'),
      ]) {
        expect(f.accepts(url), isFalse, reason: url);
      }
    });

    test("follows the proxy's redirect to the API's own copy, and nowhere else", () async {
      final f = fetcher(
        (url) => url.path.startsWith('/media/')
            ? http.StreamedResponse(Stream.value([1, 2]), 200)
            : status(302, {'location': '/media/ab/cd.jpg'}),
      );
      expect(await f.fetch(proxied), [1, 2]);
      expect(asked.map((u) => u.toString()), [proxied, 'https://api.lunaway.net/media/ab/cd.jpg']);

      asked.clear();
      final away = fetcher((_) => status(302, {'location': 'https://evil.example/x.jpg'}));
      await expectLater(away.fetch(proxied), throwsA(isA<ImageFetchException>()));
      expect(asked, hasLength(1), reason: 'the redirect is not followed');
    });

    test('a photo not fetched yet is not asked again before its Retry-After', () async {
      var answers = [
        status(503, {'retry-after': '3600'}),
      ];
      final f = fetcher((_) => answers.removeAt(0));
      await expectLater(
        f.fetch(proxied),
        throwsA(
          isA<PhotoNotYetException>().having((e) => e.retryAfter, 'wait', const Duration(hours: 1)),
        ),
      );
      now = now.add(const Duration(minutes: 59));
      await expectLater(f.fetch(proxied), throwsA(isA<PhotoNotYetException>()));
      expect(asked, hasLength(1), reason: 'no request inside the wait');

      now = now.add(const Duration(minutes: 2));
      answers = [
        http.StreamedResponse(Stream.value([9]), 200),
      ];
      expect(await f.fetch(proxied), [9]);
      expect(asked, hasLength(2));
    });

    test('a failed download (502) and a spent budget (429) are waits, not errors', () {
      expect(ImageFetcher.unavailableDelay(502, {'retry-after': '7200'}), const Duration(hours: 2));
      expect(ImageFetcher.unavailableDelay(429, const {}), const Duration(minutes: 1));
      expect(ImageFetcher.unavailableDelay(404, {'retry-after': '3'}), isNull);
    });
  });
}
