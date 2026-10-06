import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/data/account_operations.dart';
import 'package:lunaway/features/community/data/community_operations.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/demo/demo_server.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

import 'graphql_validator.dart';

/// Every operation the app sends must be valid against the schema the
/// server exports (`schema/lunaway.graphql`): when either side changes, this
/// test names the field that drifted. The demo server, which stands in for
/// the API in the demo build and in tests, is held to the same schema: it
/// refuses a document the server would refuse, and its answers carry what
/// the schema promises.
void main() {
  final schema = File('../schema/lunaway.graphql').readAsStringSync();
  final validator = SchemaValidator(schema);

  test('the app sends at least the sync operation', () {
    expect(allOperations.map((o) => o.name), contains('Changes'));
  });

  for (final op in [
    ...allOperations,
    ...accountOperations,
    ...communityOperations,
    ...GraphQLFavoritesRemote.operations,
  ]) {
    test('${op.name} is valid against schema/lunaway.graphql', () {
      expect(validator.validate(op.document), isEmpty);
    });
  }

  group('the demo server answers as the schema says', () {
    final apiBase = Uri.parse('https://api.example.org');
    final exchanges =
        <
          ({
            String query,
            Map<String, Object?> variables,
            Map<String, dynamic> body,
          })
        >[];
    final client = GraphQLClient(
      endpoint: Uri.parse('$apiBase/graphql'),
      httpClient: _Recording(
        demoApiClient(
          demoPlaces(),
          apiBase: apiBase,
          latency: Duration.zero,
          validate: validator.validate,
        ),
        exchanges,
      ),
      userAgent: 'Lunaway/test (+https://lunaway.net)',
    );
    setUp(exchanges.clear);

    void conforms() {
      expect(exchanges, isNotEmpty);
      for (final e in exchanges) {
        expect(
          validator.checkVariables(e.query, e.variables),
          isEmpty,
          reason: 'variables',
        );
        expect(e.body['errors'], isNull);
        expect(
          validator.checkResponse(
            e.query,
            e.body['data'] as Map<String, dynamic>,
          ),
          isEmpty,
          reason: 'response',
        );
      }
    }

    test('a sync page', () async {
      final page = await client.execute(
        changesOperation,
        changesVariables(bbox: GeoBounds.metropolitanFrance, first: 200),
      );
      expect(page.places, hasLength(200));
      conforms();
    });

    test('the photos and reviews of a place, then the next reviews', () async {
      // A place the demo gives a community rating has photos and reviews.
      final place = demoPlaces().firstWhere(
        (p) => p.ratings.any(
          (r) => r.sourceId == communitySourceId && r.count > 25,
        ),
      );
      final extras = await client.execute(extrasOperation, {
        'id': place.id,
        'first': 20,
      });
      expect(extras!.photos, isNotEmpty);
      expect(extras.reviews.nodes, hasLength(20));
      expect(
        extras.reviews.nodes.map((r) => r.authorVehicle),
        everyElement(isNotNull),
      );
      final next = await client.execute(reviewsOperation, {
        'id': place.id,
        'first': 20,
        'after': extras.reviews.endCursor,
      });
      expect(next.nodes, isNotEmpty);
      conforms();
    });

    test('refuses a document the server would refuse', () async {
      final broken = GraphQLOperation<Object?>(
        name: 'Changes',
        document: changesOperation.document.replaceFirst('cursor', 'colour'),
        parse: (data) => data,
      );
      await expectLater(
        client.execute(
          broken,
          changesVariables(bbox: GeoBounds.metropolitanFrance),
        ),
        throwsA(isA<GraphQLResponseException>()),
      );
    });
  });

  group('the validator itself', () {
    final v = SchemaValidator('''
      schema { query: Root }
      type Root { thing(id: ID!, n: Int = 3): Thing things(first: Int): [Thing!]! version: String! }
      type Thing { id: ID! name: String child: Thing }
    ''');

    test('accepts a valid operation', () {
      expect(
        v.validate(
          r'query Q($id: ID!) { version thing(id: $id) { id name child { id } } }',
        ),
        isEmpty,
      );
    });

    test('names an unknown field', () {
      expect(v.validate('query Q { version colour }'), [
        'Q: Root has no field "colour"',
      ]);
    });

    test('names a missing required argument and an unknown one', () {
      expect(v.validate('query Q { thing(nope: 1) { id } }'), [
        'Q.thing: no argument "nope"',
        'Q.thing: required argument "id" is missing',
      ]);
    });

    test('refuses a nullable variable for a required argument', () {
      expect(v.validate(r'query Q($id: ID) { thing(id: $id) { id } }'), [
        r'Q.thing: $id is ID, argument "id" wants ID!',
      ]);
    });

    test(
      'refuses a missing selection, a selection on a leaf, an unused variable',
      () {
        expect(v.validate(r'query Q($n: Int) { things version { x } }'), [
          'Q.things: Thing needs a selection',
          'Q.version: String is a leaf and takes no selection',
          r'Q: variable $n is declared but never used',
        ]);
      },
    );

    test('checks the values of variables', () {
      expect(
        v.checkVariables(
          r'query Q($id: ID!, $n: Int) { thing(id: $id, n: $n) { id } }',
          {'n': 'three'},
        ),
        [r'$id: null for ID!', r'$n: three is not a Int'],
      );
    });

    test('checks a response against the selection', () {
      const q = 'query Q { version things { id name child { id } } }';
      expect(
        v.checkResponse(q, {
          'version': '1',
          'things': [
            {'id': 'a', 'name': null, 'child': null},
          ],
        }),
        isEmpty,
      );
      expect(
        v.checkResponse(q, {
          'things': [
            {
              'id': null,
              'name': 3,
              'child': {'id': 'b'},
            },
          ],
        }),
        [
          'Q.version: missing',
          'Q.things[0].id: null for ID!',
          'Q.things[0].name: 3 is not a String',
        ],
      );
    });

    test('checks fragments against their type', () {
      expect(
        v.validate(
          'query Q { things { ...F } } fragment F on Thing { id size }',
        ),
        ['Q.things{F}: Thing has no field "size"'],
      );
    });
  });
}

/// Passes requests to [_inner] and keeps each GraphQL request with its
/// answer, for the checks above.
final class _Recording extends http.BaseClient {
  new(this._inner, this._log);

  final http.Client _inner;
  final List<
    ({String query, Map<String, Object?> variables, Map<String, dynamic> body})
  >
  _log;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sent = request is http.Request ? request.body : '';
    final response = await http.Response.fromStream(await _inner.send(request));
    if (sent.isNotEmpty) {
      final body = jsonDecode(sent) as Map<String, dynamic>;
      _log.add((
        query: body['query'] as String,
        variables: (body['variables'] as Map<String, dynamic>?) ?? const {},
        body: jsonDecode(response.body) as Map<String, dynamic>,
      ));
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
