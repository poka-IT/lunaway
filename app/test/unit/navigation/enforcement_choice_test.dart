import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/places/data/demo/persisted_queries.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';

/// The rules as an API that knows the choice sends them: France in zones,
/// its positions for a user who asks for them.
const _rules = EnforcementRules(
  version: 2,
  countries: {
    'FR': EnforcementMode.zones,
    'ES': EnforcementMode.exact,
    'CH': EnforcementMode.off,
    'IT': EnforcementMode.zones,
  },
  optIn: {'FR': EnforcementMode.exact},
);

void main() {
  final t0 = DateTime.utc(2026, 10, 9, 9);

  group("the rules once the user's choices apply", () {
    test('France chosen: its cameras as points; unchosen, zones; elsewhere nothing moves', () {
      final chosen = _rules.withChoices({'FR'});
      expect(chosen.modeOf('FR'), EnforcementMode.exact);
      expect(chosen.modeOf('IT'), EnforcementMode.zones, reason: 'no choice offered there');
      expect(_rules.modeOf('FR'), EnforcementMode.zones, reason: 'the table itself is untouched');
      expect(identical(_rules.withChoices(const {}), _rules), isTrue);
      expect(identical(_rules.withChoices({'IT', 'CH'}), _rules), isTrue, reason: 'no choice');
      expect(_rules.withChoices({'fr'}).modeOf('FR'), EnforcementMode.exact, reason: 'any case');
    });

    test('a choice only turns zones into points: a country turned off stays off', () {
      const off = EnforcementRules(
        version: 3,
        countries: {'FR': EnforcementMode.off, 'ES': EnforcementMode.exact},
      );
      expect(off.withChoices({'FR'}).modeOf('FR'), EnforcementMode.off);
      const strange = EnforcementRules(
        version: 3,
        countries: {'FR': EnforcementMode.zones},
        optIn: {'FR': EnforcementMode.offWhileDriving},
      );
      expect(strange.withChoices({'FR'}).modeOf('FR'), EnforcementMode.zones);
    });

    test('an API that does not say which choice exists: France exact stands for it', () {
      const older = EnforcementRules(version: 1, countries: {'FR': EnforcementMode.zones});
      expect(older.optIn, isNull);
      expect(older.withChoices({'FR'}).modeOf('FR'), EnforcementMode.exact);
      expect(
        EnforcementRules.none.withChoices({'FR'}).modeOf('FR'),
        EnforcementMode.off,
        reason: 'a country the table does not name stays off',
      );
      const saysNone = EnforcementRules(
        version: 3,
        countries: {'FR': EnforcementMode.zones},
        optIn: {},
      );
      expect(
        saysNone.withChoices({'FR'}).modeOf('FR'),
        EnforcementMode.zones,
        reason: 'a table that offers no choice in France is obeyed',
      );
    });

    test('the choice read from the API, kept on the device as it came', () {
      final withField = rulesFromJson({
        'version': 2,
        'reviewedOn': '2026-10-09',
        'countries': [
          {'country': 'FR', 'mode': 'ZONES', 'optInMode': 'EXACT'},
          {'country': 'ES', 'mode': 'EXACT', 'optInMode': null},
        ],
      });
      expect(withField.optIn, {'FR': EnforcementMode.exact});
      expect(rulesFromJson(rulesToJson(withField)).optIn, {'FR': EnforcementMode.exact});
      final without = rulesFromJson({
        'version': 1,
        'countries': [
          {'country': 'FR', 'mode': 'ZONES'},
        ],
      });
      expect(without.optIn, isNull);
      expect(rulesFromJson(rulesToJson(without)).optIn, isNull, reason: 'still the fallback');
    });

    test('the choice is a setting of its own, off by default, kept across runs', () {
      expect(const DrivingAidsSettings().exactIn, isEmpty);
      final chosen = const DrivingAidsSettings().copyWith(exactIn: {'FR'});
      expect(DrivingAidsSettings.decode(chosen.encode()), chosen);
      expect(DrivingAidsSettings.decode('{"exactIn": "FR"}').exactIn, isEmpty);
      expect(DrivingAidsSettings.decode('{"exactIn": ["fr", 3, "FRA"]}').exactIn, {'FR'});
      expect(DrivingAidsSettings.decode('{"showSpeedLimit": false}').showSpeedLimit, isFalse);
    });
  });

  group('the delta and the choice', () {
    late CacheDatabase db;
    setUp(() => db = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Map<String, Object?> camera(String id, String country, {double lat = 45.8}) => {
      'id': id,
      'kind': 'CAMERA',
      'category': 'FIXED',
      'country': country,
      'line': null,
      'lat': lat,
      'lon': 1.3,
      'bearingDeg': null,
      'limitKmh': 90,
      'sourceIds': ['securite-routiere'],
    };

    Map<String, Object?> zone(String id, String country) => {
      ...camera(id, country),
      'kind': 'ZONE',
      'lat': null,
      'lon': null,
      'limitKmh': null,
      'line': encodePolyline([for (var i = 0; i < 10; i++) LatLng(45.8, 1.3 + i * 0.0006)]),
    };

    Map<String, Object?> page(
      String cursor,
      List<Map<String, Object?>> upserts, {
      bool full = true,
      bool optInField = true,
    }) => {
      'enforcement': {
        'cursor': cursor,
        'full': full,
        'rules': {
          'version': 2,
          'reviewedOn': '2026-10-09',
          'countries': [
            {'country': 'FR', 'mode': 'ZONES', if (optInField) 'optInMode': 'EXACT'},
            {'country': 'ES', 'mode': 'EXACT', if (optInField) 'optInMode': null},
          ],
        },
        'upserts': upserts,
        'removals': <String>[],
        'sources': [
          {
            'id': 'securite-routiere',
            'name': 'Sécurité routière',
            'attribution': 'Sécurité routière, radars.securite-routiere.gouv.fr',
            'fetchedAt': '2026-10-09T05:00:00Z',
            'listUpdatedAt': null,
          },
        ],
        'pollIntervalSeconds': 21600,
        'hasMore': false,
      },
    };

    /// An API answering [answers] in turn, the requests it got in [asked]
    /// (their documents and variables).
    GraphQLClient serving(List<Object> answers, List<Map<String, dynamic>> asked) {
      final store = PersistedQueryStore();
      return GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          final document = store.documentOf(body);
          if (document == null) return http.Response(jsonEncode(PersistedQueryStore.notFound), 200);
          asked.add({'document': document, ...body['variables'] as Map<String, dynamic>});
          final answer = answers.removeAt(0);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(answer is Map && answer.containsKey('errors') ? answer : {'data': answer}),
            ),
            200,
          );
        }),
        userAgent: 'test',
        persistedQueries: true,
      );
    }

    test('France is named only for a trip through France, always as a variable', () async {
      final asked = <Map<String, dynamic>>[];
      final sync = EnforcementSync(
        client: serving([
          page('e1', [camera('es', 'ES')]),
          page('f1', [camera('fr', 'FR')]),
        ], asked),
        store: EnforcementStore(db),
        chosen: () async => {'FR'},
      );
      await sync.refresh({'ES'}, t0);
      expect(asked.single.containsKey('exactIn'), isFalse, reason: 'a trip in Spain says nothing');
      await sync.refresh({'FR', 'ES'}, t0.add(const Duration(minutes: 1)));
      expect(asked.last['exactIn'], ['FR']);
      for (final a in asked) {
        expect(a['document'], isNot(contains('"FR"')), reason: 'never written in the document');
      }
    });

    test('the choice changed, the cursor starts over from the whole set', () async {
      final asked = <Map<String, dynamic>>[];
      var chosen = <String>{};
      final sync = EnforcementSync(
        client: serving([
          page('z1', [zone('fz', 'FR')]),
          page('p1', [camera('fc', 'FR')]),
          page('z2', [zone('fz', 'FR')]),
        ], asked),
        store: EnforcementStore(db),
        chosen: () async => chosen,
      );
      final zones = await sync.refresh({'FR'}, t0);
      expect(zones.items.map((i) => i.id), ['fz']);
      chosen = {'FR'};
      // Within the server's rhythm: the change alone makes it due.
      final points = await sync.refresh({'FR'}, t0.add(const Duration(minutes: 5)));
      expect(asked[1]['since'], isNull, reason: 'the cursor was asked without the choice');
      expect(asked[1]['exactIn'], ['FR']);
      expect(points.items.map((i) => i.id), ['fc'], reason: 'the zones replaced by the points');
      chosen = {};
      await sync.refresh({'FR'}, t0.add(const Duration(minutes: 10)));
      expect(asked[2]['since'], isNull);
      expect(asked[2].containsKey('exactIn'), isFalse);
    });

    test("France's points are kept only with the choice", () async {
      final sync = EnforcementSync(
        client: serving([
          page('c1', [camera('fc', 'FR'), camera('ec', 'ES'), zone('fz', 'FR')]),
        ], []),
        store: EnforcementStore(db),
      );
      await sync.refresh({'FR', 'ES'}, t0);
      expect(
        (await EnforcementStore(db).items({'FR', 'ES'})).map((i) => i.id),
        unorderedEquals(['ec', 'fz']),
        reason: 'a French camera sent without the choice never reaches the device',
      );
    });

    test('the choice withdrawn: the positions of France go from the device at once, from every '
        'trip, offline too', () async {
      var chosen = {'FR'};
      final sync = EnforcementSync(
        client: serving([
          page('c1', [camera('fc', 'FR'), camera('fc2', 'FR', lat: 48.8), camera('ec', 'ES')]),
        ], []),
        store: EnforcementStore(db),
        chosen: () async => chosen,
      );
      final held = await sync.refresh({'FR', 'ES'}, t0);
      expect(held.items.map((i) => i.id), unorderedEquals(['fc', 'fc2', 'ec']));
      chosen = {};
      // No network from here on: the purge needs none.
      await sync.purge();
      final left = await EnforcementStore(db).items({'FR', 'ES'});
      expect(left.map((i) => i.id), ['ec'], reason: "Spain's own rule shows points");
    });

    test('positions the purge missed are never handed out once the choice is withdrawn', () async {
      var chosen = {'FR'};
      final sync = EnforcementSync(
        client: serving([
          page('c1', [camera('fc', 'FR'), zone('fz', 'FR')]),
        ], []),
        store: EnforcementStore(db),
        chosen: () async => chosen,
      );
      await sync.refresh({'FR'}, t0);
      chosen = {};
      // Offline: the poll that would replace them fails.
      final data = await EnforcementSync(
        client: GraphQLClient(
          endpoint: Uri.parse('https://api.example.org/graphql'),
          httpClient: MockClient((_) async => throw http.ClientException('offline')),
          userAgent: 'test',
        ),
        store: EnforcementStore(db),
        chosen: () async => chosen,
      ).refresh({'FR'}, t0.add(const Duration(hours: 7)));
      expect(data.items.map((i) => i.id), ['fz']);
    });

    test('settings that cannot be read: the default of every country, never a failure', () async {
      final asked = <Map<String, dynamic>>[];
      final sync = EnforcementSync(
        client: serving([
          page('c1', [camera('fc', 'FR'), zone('fz', 'FR')]),
        ], asked),
        store: EnforcementStore(db),
        chosen: () async => throw StateError('no settings'),
      );
      final data = await sync.refresh({'FR'}, t0);
      expect(asked.single.containsKey('exactIn'), isFalse);
      expect(data.items.map((i) => i.id), ['fz']);
      await sync.purge();
    });

    test(
      'an API older than the choice: the older form, the zones of France, nothing lost',
      () async {
        final asked = <Map<String, dynamic>>[];
        final sync = EnforcementSync(
          client: serving([
            {
              'data': null,
              'errors': [
                {
                  'message': 'Unknown argument "exactIn" on field "Query.enforcement".',
                  'extensions': {'code': 'INVALID_INPUT'},
                },
                {
                  'message': 'Unknown field "optInMode" on type "EnforcementCountryRule".',
                  'extensions': {'code': 'INVALID_INPUT'},
                },
              ],
            },
            page('c1', [zone('fz', 'FR')], optInField: false),
          ], asked),
          store: EnforcementStore(db),
          chosen: () async => {'FR'},
        );
        final data = await sync.refresh({'FR'}, t0);
        expect(asked.last['document'], isNot(contains('exactIn')));
        expect(asked.last['document'], isNot(contains('optInMode')));
        expect(data.items.map((i) => i.id), ['fz']);
        expect(data.rules!.optIn, isNull, reason: 'the fallback table then stands');
      },
    );
  });
}
