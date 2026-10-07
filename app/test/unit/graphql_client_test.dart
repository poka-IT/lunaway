import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
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
    expect(first.address!.city, 'Grenoble', reason: "the source's town wins over the commune");
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
    expect(
      second.address!.city,
      'Échirolles',
      reason: 'a place mapped without an address takes the commune it lies in',
    );
  });

  test('reads a review: the vehicle by its API name, the day of the stay as a date', () {
    final page = reviewPageFromJson({
      'nodes': [
        {
          'id': '0192f5a0-0000-7000-8000-000000000101',
          'sourceId': 'community',
          'rating': 4,
          'text': 'Calme.',
          'authorName': null,
          'authorVehicle': 'CAMPERVAN',
          'visitedAt': '2026-09-20',
          'createdAt': '2026-09-21T08:00:00Z',
        },
        {
          'id': '0192f5a0-0000-7000-8000-000000000102',
          'sourceId': 'community',
          'authorVehicle': 'HOVERCRAFT',
          'createdAt': '2026-09-21T08:00:00Z',
        },
      ],
      'hasNextPage': false,
      'totalCount': 2,
    });
    final first = page.nodes.first;
    expect(first.authorVehicle, ReviewVehicle.campervan);
    expect(first.visitedAt, DateTime(2026, 9, 20), reason: 'the same calendar day in any zone');
    expect(page.nodes.last.authorVehicle, isNull, reason: 'a vehicle a newer server adds');
    final back = reviewPageToJson(page)['nodes']! as List;
    expect((back.first as Map)['visitedAt'], '2026-09-20');
    expect((back.first as Map)['authorVehicle'], 'CAMPERVAN');
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

  test('every build points at the public API unless a developer names another', () {
    // A debug build on a phone has no "local" backend to reach: the old
    // localhost default made it useless there. Tests run without
    // LUNAWAY_API_URL and without the demo.
    final config = AppConfig.fromEnvironment();
    expect(config.apiBaseUrl, AppConfig.publicApi);
    expect(config.graphqlEndpoint.toString(), 'https://api.lunaway.net/graphql');
    expect(config.demo, isFalse);
    expect(demoBuild, isFalse, reason: 'the demo is a build of its own, never the default');
  });

  test('a base URL with a path and a trailing slash still gives its GraphQL endpoint', () {
    const config = AppConfig(
      apiBaseUrl: 'https://staging.example.org/api/',
      demo: false,
      basemapUrl: '',
    );
    expect(config.graphqlEndpoint.toString(), 'https://staging.example.org/api/graphql');
    expect(config.isApiMedia(Uri.parse('https://staging.example.org/api/media/x/thumb')), isTrue);
    expect(config.isApiMedia(Uri.parse('https://staging.example.org/media/x/thumb')), isFalse);
  });

  group('an API older than an operation', () {
    const document = r'''
mutation Edit($id: UUID!, $patch: PatchInput!, $key: String) {
  edit(id: $id, patch: $patch, key: $key)
}''';
    final op = GraphQLOperation<bool>(
      name: 'Edit',
      document: document,
      parse: (data) => data['edit'] == true,
      older: OlderForm.without(document, const {
        'key',
      }, usable: (v) => !(v['patch']! as Map).containsKey('clear')),
    );
    String refusal(String message) => jsonEncode({
      'data': null,
      'errors': [
        {
          'message': message,
          'extensions': {'code': 'INVALID_INPUT'},
        },
      ],
    });
    // As async-graphql answers an argument, then an input field, it does
    // not know.
    http.Response older(http.Request r) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (body['query'].toString().contains('key')) {
        return json(refusal('Unknown argument "key" on field "edit" of type "Mutation".'));
      }
      if (((body['variables'] as Map)['patch'] as Map).containsKey('clear')) {
        return json(
          refusal('Invalid value for argument "patch", unknown field "clear" of type "PatchInput"'),
        );
      }
      return json('{"data":{"edit":true}}');
    }

    test('gets the older form when it does not know an argument', () async {
      final c = client(older);
      final done = await c.execute(op, {
        'id': 'p1',
        'patch': {'name': 'A'},
        'key': 'k-12345678',
      });
      expect(done, isTrue);
      expect(sent, hasLength(2));
      final second = jsonDecode(sent.last.body) as Map<String, dynamic>;
      expect(
        second['query'],
        'mutation Edit(\$id: UUID!, \$patch: PatchInput!) {\n  edit(id: \$id, patch: \$patch)\n}',
      );
      expect(second['variables'], {
        'id': 'p1',
        'patch': {'name': 'A'},
      });
    });

    test('a request whose meaning needs what the API lacks waits for it', () async {
      final c = client(older);
      await expectLater(
        c.execute(op, {
          'id': 'p1',
          'patch': {
            'clear': ['WEBSITE'],
          },
          'key': 'k-12345678',
        }),
        throwsA(
          isA<GraphQLResponseException>().having(
            (e) => e.errors.single.unknownInput,
            'unknown input',
            isTrue,
          ),
        ),
      );
      expect(sent, hasLength(1));
    });

    test('an unknown input field is an older API too', () {
      expect(
        const GraphQLError(
          'Invalid value for argument "patch", unknown field "clear" of type "PlaceDetailsInput"',
          code: 'INVALID_INPUT',
        ).unknownInput,
        isTrue,
      );
      expect(const GraphQLError('name: too long', code: 'INVALID_INPUT').unknownInput, isFalse);
      expect(
        const GraphQLError(
          'Unknown field "confirmPoi" on type "Mutation".',
          code: 'INVALID_INPUT',
        ).unknownInput,
        isFalse,
        reason: 'a whole operation the API lacks: no older form helps',
      );
    });

    test('another refusal of the input is the answer: nothing is sent again', () async {
      final c = client((_) => json(refusal('name: too long')));
      await expectLater(
        c.execute(op, {'id': 'p1', 'patch': <String, Object?>{}}),
        throwsA(isA<GraphQLResponseException>()),
      );
      expect(sent, hasLength(1));
    });

    test('a field the API lacks calls for the form without it, when there is one', () async {
      const withField = 'query R { route { status speedLimits } }';
      const without = 'query R { route { status } }';
      final selecting = GraphQLOperation<Object?>(
        name: 'R',
        document: withField,
        older: OlderForm.selecting(without),
        parse: (data) => data,
      );
      final c = client(
        (r) => (jsonDecode(r.body) as Map<String, dynamic>)['query'] == withField
            ? json(refusal('Unknown field "speedLimits" on type "RouteSummary".'))
            : json('{"data":{"route":{"status":"OK"}}}'),
      );
      expect(await c.execute(selecting), {
        'route': {'status': 'OK'},
      });
      expect(sent, hasLength(2));
      // An operation with an older form of arguments only is not resent
      // for a field: a whole operation the API lacks.
      final args = client((_) => json(refusal('Unknown field "confirmPoi" on type "Mutation".')));
      await expectLater(
        args.execute(op, {'id': 'p1', 'patch': <String, Object?>{}}),
        throwsA(isA<GraphQLResponseException>()),
      );
      expect(sent, hasLength(1));
    });

    test('an API older still gets the next form, one release at a time', () async {
      const newest = 'query R { route { status reasons limits } }';
      const middle = 'query R { route { status limits } }';
      const oldest = 'query R { route { status } }';
      final chained = GraphQLOperation<Object?>(
        name: 'R',
        document: newest,
        older: OlderForm.selecting(middle, older: OlderForm.selecting(oldest)),
        parse: (data) => data,
      );
      // An API that knows neither field: each refusal names one.
      final c = client(
        (r) => switch ((jsonDecode(r.body) as Map<String, dynamic>)['query']) {
          newest => json(refusal('Unknown field "reasons" on type "RouteResult".')),
          middle => json(refusal('Unknown field "limits" on type "RouteResult".')),
          _ => json('{"data":{"route":{"status":"OK"}}}'),
        },
      );
      expect(await c.execute(chained), {
        'route': {'status': 'OK'},
      });
      expect(sent, hasLength(3));
      // An API that knows the middle form stops there.
      sent.clear();
      final knowsLimits = client(
        (r) => (jsonDecode(r.body) as Map<String, dynamic>)['query'] == newest
            ? json(refusal('Unknown field "reasons" on type "RouteResult".'))
            : json('{"data":{"route":{"status":"OK","limits":1}}}'),
      );
      expect(await knowsLimits.execute(chained), {
        'route': {'status': 'OK', 'limits': 1},
      });
      expect(sent, hasLength(2));
    });
  });
}
