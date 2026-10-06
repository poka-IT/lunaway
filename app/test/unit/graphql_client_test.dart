import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  late List<http.Request> sent;
  late List<Duration> waits;
  GraphQLClient client(http.Response Function(http.Request) answer) {
    sent = [];
    waits = [];
    return GraphQLClient(
      endpoint: Uri.parse('http://127.0.0.1:8484/graphql'),
      httpClient: MockClient((r) async {
        sent.add(r);
        return answer(r);
      }),
      userAgent: AppConfig.userAgent('1.2.3'),
      sleep: (d) async => waits.add(d),
    );
  }

  http.Response json(String body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

  test('posts the operation with its name, variables and an honest User-Agent', () async {
    final c = client((_) => json(fixture('changes_page.json')));
    await GraphQLChangesSource(c)
        .changes(bbox: GeoBounds.metropolitanFrance, since: 'c1', first: 1000);
    final request = sent.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'http://127.0.0.1:8484/graphql');
    expect(request.headers['user-agent'], 'Lunaway/1.2.3 (+https://lunaway.net)');
    expect(request.headers['content-type'], startsWith('application/json'));
    // One operation per request: the API refuses batches (a JSON array).
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body.keys, unorderedEquals(['operationName', 'query', 'variables']));
    expect(body['operationName'], 'Changes');
    expect(body['query'], contains(r'changes(bbox: $bbox, since: $since, first: $first)'));
    expect(body['variables'], {
      'bbox': {'south': 41.2, 'west': -5.5, 'north': 51.3, 'east': 9.9},
      'since': 'c1',
      'first': 1000,
    });
  });

  test('reads a page of changes, tolerating values a newer server may add', () async {
    final page = await GraphQLChangesSource(client((_) => json(fixture('changes_page.json'))))
        .changes(bbox: GeoBounds.metropolitanFrance, first: 1000);
    expect(page.cursor, 'opaque-cursor-2');
    expect(page.hasMore, isTrue);
    expect(page.deleted, ['0192f5a0-0000-7000-8000-000000000009']);
    final first = page.places.first;
    expect(first.kind, PlaceKind.motorhomeArea);
    expect(first.services, {
      Service.drinkingWater,
      Service.greyWater,
    }, reason: 'an unknown service is skipped');
    expect(first.website, isNull, reason: 'an empty string is no website');
    expect(first.address!.city, 'Grenoble');
    expect(first.openingIntervals, [
      OpeningInterval(DateTime.utc(2026, 10, 6, 6), DateTime.utc(2026, 10, 6, 18)),
    ]);
    expect(first.openingValidUntil, DateTime.utc(2026, 10, 19, 22));
    expect(first.stars, 4);
    expect(first.descriptions.map((d) => d.lang), ['fr', 'de'], reason: 'a blank text is dropped');
    expect(first.ratings.single.count, 37);
    expect(first.provenance.single.alternatives.single.value, 'Aire Essais');
    final second = page.places.last;
    expect(second.name, isNull);
    expect(
      second.kind,
      PlaceKind.extraService,
      reason: 'an unknown kind still shows, under a neutral kind',
    );
    expect(second.overnight, OvernightStatus.unknown);
    expect(second.stars, isNull, reason: 'a classification outside 1 to 5 means nothing');
  });

  test('GraphQL errors become a response exception', () async {
    final c = client((_) => json('{"errors":[{"message":"bbox too large"}],"data":null}'));
    await expectLater(
      GraphQLChangesSource(c).changes(bbox: GeoBounds.metropolitanFrance, first: 10),
      throwsA(
        isA<GraphQLResponseException>().having((e) => e.messages, 'messages', ['bbox too large']),
      ),
    );
  });

  test('an error code is kept for the caller to act on', () async {
    final c = client(
      (_) =>
          json('{"data":null,"errors":[{"message":"sync again","extensions":{"code":"RESYNC"}}]}'),
    );
    await expectLater(
      c.execute(changesOperation),
      throwsA(
        isA<GraphQLResponseException>().having(
          (e) => e.hasCode(GraphQLError.resync),
          'RESYNC',
          isTrue,
        ),
      ),
    );
  });

  group('rate limiting', () {
    const limited =
        '{"data":null,"errors":[{"message":"slow down","extensions":{"code":"RATE_LIMITED","retryAfterSeconds":7}}]}';

    test('waits what the server asks, then sends again', () async {
      var calls = 0;
      final c = client(
        (_) => calls++ == 0
            ? http.Response(limited, 429, headers: {'retry-after': '7'})
            : json(fixture('changes_page.json')),
      );
      final page = await GraphQLChangesSource(c)
          .changes(bbox: GeoBounds.metropolitanFrance, first: 10);
      expect(page.cursor, 'opaque-cursor-2');
      expect(waits, [const Duration(seconds: 7)]);
      expect(sent, hasLength(2));
    });

    test('reads the Retry-After header of a proxy that answers without JSON', () async {
      var calls = 0;
      final c = client(
        (_) => calls++ == 0
            ? http.Response('Too Many Requests', 429, headers: {'retry-after': '3'})
            : json(fixture('changes_page.json')),
      );
      await GraphQLChangesSource(c).changes(bbox: GeoBounds.metropolitanFrance, first: 10);
      expect(waits, [const Duration(seconds: 3)]);
    });

    test('gives up for now after a few refusals, as when offline', () async {
      final c = client((_) => http.Response(limited, 429));
      await expectLater(
        c.execute(changesOperation),
        throwsA(
          isA<GraphQLRateLimitedException>().having(
            (e) => e,
            'is a network failure',
            isA<GraphQLNetworkException>(),
          ),
        ),
      );
      expect(sent, hasLength(4), reason: 'the first try and three more');
      expect(waits, hasLength(3));
    });

    test('a wait longer than a minute is not spent on a spinner', () async {
      final c = client(
        (_) => json(
          '{"data":null,"errors":[{"message":"later","extensions":{"code":"RATE_LIMITED","retryAfterSeconds":600}}]}',
        ),
      );
      await expectLater(c.execute(changesOperation), throwsA(isA<GraphQLRateLimitedException>()));
      expect(waits, isEmpty);
    });
  });

  test('a server that is down or not GraphQL is a network exception', () async {
    final c = client((_) => http.Response('<html>502</html>', 502));
    await expectLater(
      GraphQLChangesSource(c).changes(bbox: GeoBounds.metropolitanFrance, first: 10),
      throwsA(isA<GraphQLNetworkException>()),
    );
  });

  test('a dropped connection is a network exception', () async {
    final c = GraphQLClient(
      endpoint: Uri.parse('http://127.0.0.1:1/graphql'),
      httpClient: MockClient((_) async => throw http.ClientException('connection refused')),
      userAgent: 'x',
    );
    await expectLater(c.execute(changesOperation), throwsA(isA<GraphQLNetworkException>()));
  });

  test('the release build points at the public API, debug builds at the local one', () {
    expect(AppConfig.publicApi, 'https://api.lunaway.net');
    expect(AppConfig.localApi, 'http://127.0.0.1:8484');
    final config = AppConfig.fromEnvironment();
    // Tests run in debug mode without LUNAWAY_API.
    expect(config.apiBaseUrl, AppConfig.localApi);
    expect(config.graphqlEndpoint.toString(), 'http://127.0.0.1:8484/graphql');
  });
}
