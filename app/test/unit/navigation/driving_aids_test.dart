import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/data/enforcement_api.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:lunaway/features/places/data/demo/persisted_queries.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';

import '../../helpers/navigation.dart';

/// A straight road east from Limoges, a point every 50 m over 5 km.
final List<LatLng> _road = [
  for (var i = 0; i <= 100; i++) LatLng(45.8336, 1.2611 + i * 50 / 77650),
];

/// The point [m] metres along [_road].
LatLng _at(double m) => LatLng(45.8336, 1.2611 + m / 77650);

/// A zone of [_road] from [from] to [to] metres, a point every 50 m.
EnforcementItem _zone(String id, double from, double to, {String country = 'FR'}) =>
    EnforcementItem(
      id: id,
      kind: EnforcementKind.zone,
      category: 'FIXED',
      country: country,
      line: [for (var m = from; m <= to; m += 50) _at(m)],
    );

const _rules = EnforcementRules(
  version: 1,
  countries: {
    'FR': EnforcementMode.zones,
    'ES': EnforcementMode.exact,
    'DE': EnforcementMode.offWhileDriving,
    'CH': EnforcementMode.off,
  },
);

RouteOption _route({List<SpeedLimitSpan>? limits}) => RouteOption(
  index: 0,
  distanceM: 5000,
  durationS: 300,
  hasToll: false,
  hasFerry: false,
  hasMotorway: false,
  warnings: const [],
  line: _road,
  speedLimits: limits,
);

GuidanceSnapshot _snap(double along, {double? posted}) => GuidanceSnapshot(
  status: GuidanceStatus.navigating,
  position: _at(along),
  stepIndex: 0,
  distanceToManeuverM: 100,
  distanceRemainingM: 5000 - along,
  durationRemainingS: 100,
  distanceAlongM: along,
  speedLimitKmh: posted,
);

Fix _fix(double along, DateTime at, {double kmh = 50, double accuracy = 5}) =>
    Fix(position: _at(along), accuracyM: accuracy, at: at, speedMps: kmh / 3.6);

void main() {
  final t0 = DateTime.utc(2026, 10, 6, 9);

  group('the rule of the country', () {
    test('a stricter rule applies at once, a looser one after 30 s', () {
      final tracker = RuleTracker();
      expect(tracker.update(EnforcementMode.exact, t0), EnforcementMode.exact);
      expect(
        tracker.update(EnforcementMode.off, t0.add(const Duration(seconds: 1))),
        EnforcementMode.off,
      );
      expect(
        tracker.update(EnforcementMode.exact, t0.add(const Duration(seconds: 2))),
        EnforcementMode.off,
        reason: 'back over the border for a moment',
      );
      expect(
        tracker.update(EnforcementMode.exact, t0.add(const Duration(seconds: 31))),
        EnforcementMode.off,
      );
      expect(
        tracker.update(EnforcementMode.exact, t0.add(const Duration(seconds: 32))),
        EnforcementMode.exact,
      );
    });

    test('near a border the strictest rule within a kilometre applies; at sea, off', () {
      expect(_rules.strictestOf(['FR', 'CH']), EnforcementMode.off);
      expect(_rules.strictestOf(['ES', 'FR']), EnforcementMode.zones);
      expect(_rules.strictestOf(['ES']), EnforcementMode.exact);
      expect(_rules.strictestOf(['MA']), EnforcementMode.off, reason: 'a country not named');
      expect(_rules.strictestOf(const []), EnforcementMode.off);
      expect(EnforcementMode.fromWire('SOMETHING_NEW'), EnforcementMode.off);
    });

    test('a camera shows only where points may be shown, by its own country too', () {
      const camera = EnforcementItem(
        id: 'c',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: LatLng(43.3, -1.8),
      );
      expect(camera.shownUnder(EnforcementMode.exact, _rules), isTrue);
      expect(camera.shownUnder(EnforcementMode.zones, _rules), isFalse);
      const french = EnforcementItem(
        id: 'f',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'FR',
        position: LatLng(43.3, -1.7),
      );
      expect(french.shownUnder(EnforcementMode.exact, _rules), isFalse, reason: 'France: zones');
      final zone = _zone('z', 0, 500);
      expect(zone.shownUnder(EnforcementMode.offWhileDriving, _rules), isFalse);
      expect(zone.shownUnder(EnforcementMode.zones, _rules), isTrue);
    });
  });

  group('the items on the route', () {
    test('a zone along the route counts in either direction, a road crossing it does not', () {
      final ahead = _zone('ahead', 1000, 1500);
      final reversed = EnforcementItem(
        id: 'reversed',
        kind: EnforcementKind.zone,
        category: 'FIXED',
        country: 'FR',
        line: _zone('x', 2000, 2600).line.reversed.toList(),
      );
      // A road crossing at 3 km, north to south.
      final crossing = EnforcementItem(
        id: 'crossing',
        kind: EnforcementKind.zone,
        category: 'FIXED',
        country: 'FR',
        line: [for (var i = -5; i <= 5; i++) LatLng(_at(3000).lat + i * 0.00045, _at(3000).lon)],
      );
      final found = itemsOnRoute(_road, [crossing, reversed, ahead]);
      expect(found.map((f) => f.item.id), ['ahead', 'reversed']);
      expect(found.first.startM, closeTo(1000, 5));
      expect(found.first.endM, closeTo(1500, 5));
      expect(found.last.startM, closeTo(2000, 5));
    });

    test('a camera counts on the route only when it controls the way the route goes', () {
      final east = EnforcementItem(
        id: 'east',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: _at(1200),
        bearingDeg: 92,
      );
      final west = EnforcementItem(
        id: 'west',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: _at(1800),
        bearingDeg: 270,
      );
      final off = EnforcementItem(
        id: 'off',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: LatLng(_at(2500).lat + 0.001, _at(2500).lon),
      );
      expect(itemsOnRoute(_road, [east, west, off]).map((f) => f.item.id), ['east']);
    });

    test('the index finds what a full pass finds, across the edge of its cells too', () {
      // A road a few metres south of the 45.84 parallel, the edge of the
      // index's cells, and a zone of the same road drawn just north of it.
      LatLng south(double m) => LatLng(45.83998, 1.2611 + m / 77650);
      final road = [for (var m = 0.0; m <= 5000; m += 50) south(m)];
      final across = EnforcementItem(
        id: 'across',
        kind: EnforcementKind.zone,
        category: 'FIXED',
        country: 'FR',
        line: [for (var m = 1000.0; m <= 1500; m += 50) LatLng(45.84012, 1.2611 + m / 77650)],
      );
      final camera = EnforcementItem(
        id: 'camera',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: south(3000),
      );
      final far = EnforcementItem(
        id: 'far',
        kind: EnforcementKind.zone,
        category: 'FIXED',
        country: 'FR',
        line: [for (var m = 0.0; m <= 500; m += 50) LatLng(46.5, 1.2611 + m / 77650)],
      );
      final items = [far, camera, across];
      final indexed = EnforcementIndex(items).onRoute(road);
      expect(indexed.map((f) => f.item.id), ['across', 'camera']);
      expect(
        indexed.map((f) => (f.item.id, f.startM, f.endM)),
        itemsOnRoute(road, items).map((f) => (f.item.id, f.startM, f.endM)),
      );
    });
  });

  group('the limit and the excess', () {
    test('the span of the route gives the limit; the sign alone only for a light vehicle', () {
      const spans = [
        SpeedLimitSpan(fromM: 0, toM: 1000, kmh: 50, source: SpeedLimitSource.posted),
        SpeedLimitSpan(fromM: 1000, toM: 3000, kmh: 80, source: SpeedLimitSource.vehicle),
        SpeedLimitSpan(fromM: 3200, toM: 5000, kmh: 80, source: SpeedLimitSource.estimated),
      ];
      final at = limitAt(spans: spans, alongM: 1500, postedKmh: 90, totalWeightT: 4.2);
      expect(at, const ShownLimit(kmh: 80, source: SpeedLimitSource.vehicle));
      expect(limitAt(spans: spans, alongM: 3100, postedKmh: 90, totalWeightT: 4.2), isNull);
      expect(
        limitAt(spans: spans, alongM: 4000, postedKmh: 90, totalWeightT: 4.2)!.estimated,
        isTrue,
      );
      expect(limitAt(spans: null, alongM: 0, postedKmh: 90, totalWeightT: 3.5)!.kmh, 90);
      expect(
        limitAt(spans: null, alongM: 0, postedKmh: 130, totalWeightT: 4.2),
        isNull,
        reason: 'a motorhome of 4.2 t may not drive at the sign of a motorway',
      );
    });

    test('over after 2 s, a word after 5 s then every 2 min, again after 30 s under', () {
      final watch = OverSpeedWatch();
      const limit = ShownLimit(kmh: 50, source: SpeedLimitSource.posted);
      ({bool over, bool sound}) at(int s, double kmh) => watch.update(
        speedKmh: kmh,
        limit: limit,
        at: t0.add(Duration(seconds: s)),
      );
      expect(at(0, 53), (over: false, sound: false), reason: 'within the tolerance');
      expect(at(1, 60), (over: false, sound: false));
      expect(at(3, 60), (over: true, sound: false));
      expect(at(6, 60), (over: true, sound: true));
      expect(at(7, 60), (over: true, sound: false));
      expect(at(126, 60), (over: true, sound: true), reason: 'two minutes on');
      expect(at(130, 45), (over: false, sound: false));
      expect(at(150, 45), (over: false, sound: false));
      expect(at(160, 45), (over: false, sound: false));
      expect(at(161, 60), (over: false, sound: false), reason: 'a new excess starts over');
      expect(at(166, 60), (over: true, sound: true));
    });

    test('an estimated limit never warns', () {
      final watch = OverSpeedWatch();
      const limit = ShownLimit(kmh: 50, source: SpeedLimitSource.estimated);
      for (var s = 0; s < 20; s++) {
        final r = watch.update(
          speedKmh: 90,
          limit: limit,
          at: t0.add(Duration(seconds: s)),
        );
        expect(r, (over: false, sound: false));
      }
    });
  });

  group('the engine', () {
    DrivingAidsEngine engine(String? Function(LatLng) country) =>
        DrivingAidsEngine(locator: FakeCountries(country, rules: _rules))
          ..setData(rules: _rules, items: [_zone('zone', 1000, 1500)]);

    test('in France the zone ahead, then inside it with what is left, then nothing', () {
      final e = engine((_) => 'FR');
      final route = _route();
      var aids = e.update(fix: _fix(500, t0), snap: _snap(500), route: route, totalWeightT: 3.5);
      expect(aids.alert, isNull, reason: 'beyond the reach at 50 km/h');
      aids = e.update(fix: _fix(850, t0), snap: _snap(850), route: route, totalWeightT: 3.5);
      expect(aids.mode, EnforcementMode.zones);
      expect(aids.alert!.aheadM, closeTo(150, 6));
      expect(aids.alert!.kind, EnforcementKind.zone);
      expect(aids.words, 1, reason: 'one word for the zone, said if the user asked');
      aids = e.update(fix: _fix(1200, t0), snap: _snap(1200), route: route, totalWeightT: 3.5);
      expect(aids.alert!.inside, isTrue);
      expect(aids.alert!.remainingM, closeTo(300, 6));
      expect(aids.words, 1, reason: 'said once');
      aids = e.update(fix: _fix(1600, t0), snap: _snap(1600), route: route, totalWeightT: 3.5);
      expect(aids.alert, isNull);
    });

    test('entering a country that is off clears the zone at once; Germany while driving too', () {
      for (final strict in ['CH', 'DE']) {
        final e = engine((p) => p.lon > _at(1100).lon ? strict : 'FR');
        final route = _route();
        expect(
          e.update(fix: _fix(1050, t0), snap: _snap(1050), route: route, totalWeightT: 3.5).alert,
          isNotNull,
        );
        final aids = e.update(
          fix: _fix(1150, t0.add(const Duration(seconds: 1))),
          snap: _snap(1150),
          route: route,
          totalWeightT: 3.5,
        );
        expect(aids.alert, isNull, reason: strict);
        expect(aids.country, strict);
      }
    });

    test('an imprecise fix decides nothing about the country', () {
      final e = engine((p) => p.lon > _at(1100).lon ? 'CH' : 'FR');
      final route = _route();
      e.update(fix: _fix(1050, t0), snap: _snap(1050), route: route, totalWeightT: 3.5);
      final aids = e.update(
        fix: _fix(1150, t0, accuracy: 250),
        snap: _snap(1150),
        route: route,
        totalWeightT: 3.5,
      );
      expect(aids.mode, EnforcementMode.zones);
    });

    test('the countries asked for are those of the route, never a position', () {
      final e = engine((p) => p.lon > _at(2500).lon ? 'ES' : 'FR');
      expect(e.countriesOf(_road), {'FR', 'ES'});
    });

    test('the map gets the zone as a stretch of the route in France; in Germany and '
        'Switzerland, nothing while driving', () {
      final route = _route();
      final france = engine((_) => 'FR');
      final aids = france.update(
        fix: _fix(500, t0),
        snap: _snap(500),
        route: route,
        totalWeightT: 3.5,
      );
      expect(aids.zones, hasLength(1));
      expect(aids.zones.single.fromM, closeTo(1000, 6));
      expect(aids.zones.single.toM, closeTo(1500, 6));
      final again = france.update(
        fix: _fix(550, t0.add(const Duration(seconds: 1))),
        snap: _snap(550),
        route: route,
        totalWeightT: 3.5,
      );
      expect(identical(again.zones, aids.zones), isTrue, reason: 'the same list, cheap to compare');
      for (final strict in ['DE', 'CH', 'MA']) {
        final e = engine((_) => strict);
        expect(
          e.update(fix: _fix(500, t0), snap: _snap(500), route: route, totalWeightT: 3.5).zones,
          isEmpty,
          reason: strict,
        );
      }
    });
  });

  group('what a map of the route draws', () {
    List<ItemOnRoute> onRoute(List<EnforcementItem> items) => itemsOnRoute(_road, items);

    test('a zone in France as its stretch, at rest and while driving', () {
      final items = onRoute([_zone('z', 1000, 1500)]);
      for (final driving in [false, true]) {
        final spans = zoneSpans(
          items,
          here: EnforcementMode.zones,
          rules: _rules,
          driving: driving,
        );
        expect(spans, hasLength(1));
        expect(spans.single.fromM, closeTo(1000, 6));
        expect(spans.single.toM, closeTo(1500, 6));
      }
    });

    test('Switzerland and Morocco: nothing, at rest too; Germany: at rest only', () {
      final items = onRoute([_zone('z', 1000, 1500)]);
      List<RouteSpan> where(List<String> near, {required bool driving}) =>
          zoneSpans(items, here: _rules.strictestOf(near), rules: _rules, driving: driving);
      expect(where(['CH'], driving: false), isEmpty);
      expect(where(['MA'], driving: false), isEmpty, reason: 'a country the table does not name');
      expect(where(['FR', 'CH'], driving: false), isEmpty, reason: 'the stricter at a border');
      expect(where(const [], driving: false), isEmpty, reason: 'no country known: off');
      expect(where(['DE'], driving: false), hasLength(1), reason: 'the preview, at rest');
      expect(where(['DE'], driving: true), isEmpty);
    });

    test('never a camera, even where points are allowed; never a zone its country forbids', () {
      const camera = EnforcementItem(
        id: 'c',
        kind: EnforcementKind.camera,
        category: 'FIXED',
        country: 'ES',
        position: LatLng(45.8336, 1.2611 + 1200 / 77650),
      );
      final items = onRoute([camera, _zone('swiss', 2000, 2500, country: 'CH')]);
      expect(items, hasLength(2));
      expect(zoneSpans(items, here: EnforcementMode.exact, rules: _rules, driving: false), isEmpty);
    });

    test('overlapping zones make one stretch, cut from the route where it starts and ends', () {
      final spans = zoneSpans(
        onRoute([_zone('a', 1000, 1500), _zone('b', 1400, 2000), _zone('c', 3000, 3500)]),
        here: EnforcementMode.zones,
        rules: _rules,
        driving: false,
      );
      expect(spans, hasLength(2));
      expect(spans.first.toM, closeTo(2000, 6));
      final cut = lineAlong(_road, const RouteSpan(1025, 1475));
      // Measured along the road from its start, as the route's metres are.
      expect(_road.first.distanceTo(cut.first), closeTo(1025, 0.5));
      expect(_road.first.distanceTo(cut.last), closeTo(1475, 0.5));
      expect(cut.length, greaterThan(2), reason: 'the route bends with its points');
      expect(lineAlong(_road, const RouteSpan(6000, 7000)), isEmpty, reason: 'past its end');
    });
  });

  group('the delta', () {
    late CacheDatabase db;
    setUp(() => db = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Map<String, Object?> page({
      required String cursor,
      bool full = false,
      List<Map<String, Object?>> upserts = const [],
      List<String> removals = const [],
      bool hasMore = false,
    }) => {
      'enforcement': {
        'cursor': cursor,
        'full': full,
        'rules': {
          'version': 1,
          'reviewedOn': '2026-10-06',
          'countries': [
            {'country': 'FR', 'mode': 'ZONES'},
            {'country': 'ES', 'mode': 'EXACT'},
            {'country': 'CH', 'mode': 'OFF'},
          ],
        },
        'upserts': upserts,
        'removals': removals,
        'sources': [
          {
            'id': 'fr-securite-routiere',
            'name': 'Sécurité routière',
            'attribution': 'Sécurité routière',
            'fetchedAt': '2026-10-06T05:00:00Z',
            'listUpdatedAt': null,
          },
        ],
        'pollIntervalSeconds': 21600,
        'hasMore': hasMore,
      },
    };

    Map<String, Object?> zoneJson(String id) => {
      'id': id,
      'kind': 'ZONE',
      'category': 'FIXED',
      'country': 'FR',
      'line': encodePolyline(_zone(id, 0, 500).line),
      'lat': null,
      'lon': null,
      'bearingDeg': null,
      'limitKmh': null,
      'sourceIds': ['fr-securite-routiere'],
    };

    test('two polls at once run one after the other: their pages never interleave', () async {
      final asked = <String>[];
      final gate = Completer<void>();
      final store = PersistedQueryStore();
      final client = GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (store.documentOf(body) == null) {
            return http.Response(jsonEncode(PersistedQueryStore.notFound), 200);
          }
          final variables = body['variables'] as Map<String, dynamic>;
          final country = (variables['countries'] as List<dynamic>).single as String;
          final since = variables['since'] as String?;
          asked.add('$country ${since ?? 'whole'}');
          // The first page is slow to come.
          if (asked.length == 1) await gate.future;
          final answer = since == null
              ? page(cursor: '${country}1', full: true, hasMore: true)
              : page(cursor: '${country}2');
          return http.Response.bytes(utf8.encode(jsonEncode({'data': answer})), 200);
        }),
        userAgent: 'test',
        persistedQueries: true,
      );
      final sync = EnforcementSync(client: client, store: EnforcementStore(db));
      // The preview and the guidance ask at the same time.
      final preview = sync.refresh({'FR'}, t0);
      final guidance = sync.refresh({'ES'}, t0);
      await pumpEventQueue();
      gate.complete();
      await Future.wait([preview, guidance]);
      expect(asked, ['FR whole', 'FR FR1', 'ES whole', 'ES ES1']);
    });

    test('pages follow one another; a later poll asks from the cursor; removals go', () async {
      final answers = [
        page(cursor: 'c1', full: true, upserts: [zoneJson('z1')], hasMore: true),
        page(cursor: 'c2', upserts: [zoneJson('z2')]),
        page(cursor: 'c3', removals: ['z1']),
      ];
      final asked = <Map<String, dynamic>>[];
      final store = PersistedQueryStore();
      final client = GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (store.documentOf(body) == null) {
            return http.Response(jsonEncode(PersistedQueryStore.notFound), 200);
          }
          asked.add(body['variables'] as Map<String, dynamic>);
          return http.Response.bytes(utf8.encode(jsonEncode({'data': answers.removeAt(0)})), 200);
        }),
        userAgent: 'test',
        persistedQueries: true,
      );
      final sync = EnforcementSync(client: client, store: EnforcementStore(db));
      var data = await sync.refresh({'FR'}, t0);
      expect(data.items.map((i) => i.id), unorderedEquals(['z1', 'z2']));
      expect(data.rules!.modeOf('CH'), EnforcementMode.off);
      expect(asked.map((a) => a['since']), [null, 'c1']);
      expect(asked.first['countries'], ['FR']);
      expect(asked.first.keys, isNot(contains('at')), reason: 'no position');

      data = await sync.refresh({'FR'}, t0.add(const Duration(hours: 1)));
      expect(asked, hasLength(2), reason: 'not due before the server says');
      data = await sync.refresh({'FR'}, t0.add(const Duration(hours: 7)));
      expect(asked.last['since'], 'c2');
      expect(data.items.map((i) => i.id), ['z2']);
    });

    GraphQLClient serving(List<Object> answers, List<Map<String, dynamic>> asked) {
      final store = PersistedQueryStore();
      return GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (store.documentOf(body) == null) {
            return http.Response(jsonEncode(PersistedQueryStore.notFound), 200);
          }
          asked.add(body['variables'] as Map<String, dynamic>);
          final answer = answers.removeAt(0);
          if (answer is Exception) throw answer;
          return http.Response.bytes(utf8.encode(jsonEncode({'data': answer})), 200);
        }),
        userAgent: 'test',
        persistedQueries: true,
      );
    }

    test('a run cut short is due again at once, not after the server rhythm', () async {
      final asked = <Map<String, dynamic>>[];
      final client = serving([
        page(cursor: 'c1', full: true, upserts: [zoneJson('z1')], hasMore: true),
        http.ClientException('connection reset'),
        page(cursor: 'c2', upserts: [zoneJson('z2')]),
      ], asked);
      final sync = EnforcementSync(client: client, store: EnforcementStore(db));
      final first = await sync.refresh({'FR'}, t0);
      expect(first.polledAt, isNull, reason: 'half the zones only');
      final second = await sync.refresh({'FR'}, t0.add(const Duration(minutes: 10)));
      expect(asked.last['since'], 'c1');
      expect(second.items.map((i) => i.id), unorderedEquals(['z1', 'z2']));
      expect(second.polledAt, isNotNull);
    });

    test('only the countries of the route are asked; the others stay on the device', () async {
      Map<String, Object?> spanish(String id) => {...zoneJson(id), 'country': 'ES'};
      final asked = <Map<String, dynamic>>[];
      final client = serving([
        page(cursor: 'e1', full: true, upserts: [spanish('e')]),
        page(cursor: 'f1', full: true, upserts: [zoneJson('f')]),
      ], asked);
      final sync = EnforcementSync(client: client, store: EnforcementStore(db));
      await sync.refresh({'ES'}, t0);
      final france = await sync.refresh({'FR'}, t0.add(const Duration(hours: 1)));
      expect(asked.map((a) => a['countries']), [
        ['ES'],
        ['FR'],
      ]);
      expect(asked.last['since'], isNull, reason: 'the cursor was the one of Spain');
      expect(france.items.map((i) => i.id), ['f']);
      expect((await EnforcementStore(db).items({'ES'})).map((i) => i.id), [
        'e',
      ], reason: 'a trip back to Spain offline still has its zones');
    });

    test('only what the rules of its country allow is written on the device', () async {
      final client = serving([
        page(
          cursor: 'c1',
          full: true,
          upserts: [
            zoneJson('fr-zone'),
            {...zoneJson('fr-camera'), 'kind': 'CAMERA', 'line': null, 'lat': 45.8, 'lon': 1.3},
            {...zoneJson('ch-zone'), 'country': 'CH'},
            {
              ...zoneJson('es-camera'),
              'kind': 'CAMERA',
              'country': 'ES',
              'line': null,
              'lat': 40.4,
              'lon': -3.7,
            },
          ],
        ),
      ], []);
      await EnforcementSync(
        client: client,
        store: EnforcementStore(db),
      ).refresh({'FR', 'CH', 'ES'}, t0);
      final kept = await EnforcementStore(db).items({'FR', 'CH', 'ES'});
      expect(kept.map((i) => i.id), unorderedEquals(['fr-zone', 'es-camera']));
    });

    test('an API without the delta keeps nothing and asks no more', () async {
      var requests = 0;
      final client = GraphQLClient(
        endpoint: Uri.parse('https://api.example.org/graphql'),
        httpClient: MockClient((r) async {
          requests++;
          return http.Response(
            jsonEncode({
              'data': null,
              'errors': [
                {
                  'message': 'Unknown field "enforcement" on type "Query".',
                  'extensions': {'code': 'INVALID_INPUT'},
                },
              ],
            }),
            200,
          );
        }),
        userAgent: 'test',
      );
      final sync = EnforcementSync(client: client, store: EnforcementStore(db));
      expect((await sync.refresh({'FR'}, t0)).items, isEmpty);
      await sync.refresh({'FR', 'ES'}, t0.add(const Duration(days: 1)));
      expect(requests, 1);
    });

    test('a zone without its road, or a kind this app does not know, is left out', () {
      expect(itemFromJson({...zoneJson('z'), 'line': null}), isNull);
      expect(itemFromJson({...zoneJson('z'), 'kind': 'MOBILE'}), isNull);
      expect(itemFromJson(zoneJson('z'))!.line, hasLength(11));
    });
  });
}
