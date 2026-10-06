import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/demo/persisted_queries.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  late List<Map<String, dynamic>> bodies;

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(body is String ? body : jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// A client with persisted queries over a server that keeps documents
  /// the way the API does ([PersistedQueryStore]).
  GraphQLClient over(PersistedQueryStore store) {
    bodies = [];
    return GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        final String? document;
        try {
          document = store.documentOf(body);
        } on FormatException {
          return json(PersistedQueryStore.mismatch);
        }
        if (document == null) return json(PersistedQueryStore.notFound);
        return json(fixture('changes_page.json'));
      }),
      userAgent: 'Lunaway/test (+https://lunaway.net)',
      persistedQueries: true,
    );
  }

  Future<void> page(GraphQLClient c) =>
      GraphQLChangesSource(c).changes(bbox: GeoBounds.metropolitanFrance, since: 'c1', first: 1000);

  final hash = sha256.convert(utf8.encode(changesOperation.document)).toString();

  test('the hash goes alone; an unknown one is sent again with its document', () async {
    final store = PersistedQueryStore();
    final c = over(store);
    await page(c);
    expect(bodies, hasLength(2));
    expect(bodies.first.containsKey('query'), isFalse, reason: 'the hash alone first');
    expect(bodies.first['extensions'], {
      'persistedQuery': {'version': 1, 'sha256Hash': hash},
    });
    expect(bodies.last['query'], changesOperation.document);
    expect((bodies.last['extensions'] as Map)['persistedQuery'], {
      'version': 1,
      'sha256Hash': hash,
    }, reason: 'the server keeps the document under the hash that comes with it');

    await page(c);
    expect(bodies, hasLength(3), reason: 'a known hash runs at once');
    expect(bodies.last.containsKey('query'), isFalse);
    expect(store.hits, 1);
  });

  test('a server that forgot the document (a restart) gets it again, at any time', () async {
    final store = PersistedQueryStore();
    final c = over(store);
    await page(c);
    store.clear();
    await page(c);
    expect(bodies.map((b) => b.containsKey('query')), [false, true, false, true]);
  });

  test('an API without persisted queries gets every document whole from then on', () async {
    bodies = [];
    final c = GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        // As production answered on 2026-10-06, before persisted queries.
        if (body['query'] is! String) {
          return json({
            'data': null,
            'errors': [
              {
                'extensions': {'code': 'INVALID_INPUT'},
                'message':
                    'the body must be a JSON object with a string `query`, and optionally '
                    '`variables` and `operationName`',
              },
            ],
          }, 400);
        }
        return json(fixture('changes_page.json'));
      }),
      userAgent: 'x',
      persistedQueries: true,
    );
    await page(c);
    await page(c);
    expect(bodies.map((b) => b.containsKey('query')), [false, true, true]);
    expect(bodies.last.containsKey('extensions'), isFalse);
  });

  test('another refusal of a hash alone is not taken for an API without them', () async {
    bodies = [];
    final c = GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return json({
          'data': null,
          'errors': [
            {
              'message': 'unknown region',
              'extensions': {'code': 'INVALID_INPUT'},
            },
          ],
        });
      }),
      userAgent: 'x',
      persistedQueries: true,
    );
    await expectLater(page(c), throwsA(isA<GraphQLResponseException>()));
    expect(bodies, hasLength(1), reason: 'the request ran: sending its document changes nothing');
  });

  test('the sync request weighs a fraction of its document with the hash alone', () {
    final variables = changesVariables(bbox: GeoBounds.metropolitanFrance, since: 'c1');
    final whole = utf8.encode(
      jsonEncode({
        'operationName': 'Changes',
        'query': changesOperation.document,
        'variables': variables,
      }),
    );
    final hashed = utf8.encode(
      jsonEncode({
        'operationName': 'Changes',
        'variables': variables,
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': hash},
        },
      }),
    );
    expect(hashed.length * 3, lessThan(whole.length), reason: '${hashed.length} / ${whole.length}');
  });
}
