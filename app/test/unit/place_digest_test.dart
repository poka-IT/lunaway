import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/place_digests.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/place_digest_source.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

import '../helpers/fakes.dart';

PlaceSummary _place(String id, {double km = 0, double? rating, int count = 0}) => PlaceSummary(
  id: id,
  kind: PlaceKind.motorhomeArea,
  lat: 44.48 + km / 111,
  lon: 4.68,
  overnight: OvernightStatus.allowed,
  ratingAverage: rating,
  ratingCount: count,
);

PlaceDigest _digest(String id, {List<SourceRating> ratings = const [], DateTime? added}) =>
    PlaceDigest(placeId: id, addedAt: added ?? DateTime.utc(2026, 10, 6), ratings: ratings);

const _extcom = 'extcom';

void main() {
  group('the rating a row shows', () {
    test("Lunaway users' rating when they rated the place, never added to another", () {
      final r = rowRating(
        _place('a'),
        _digest(
          'a',
          ratings: const [
            SourceRating(sourceId: communityCcBySourceId, average: 4.5, count: 2),
            SourceRating(sourceId: _extcom, average: 3.3, count: 246),
          ],
        ),
      );
      expect(r, (average: 4.5, count: 2, sourceId: communityCcBySourceId));
    });

    test('the summary carries it while the digest has not come', () {
      expect(rowRating(_place('a', rating: 4, count: 3), null), (
        average: 4.0,
        count: 3,
        sourceId: communityCcBySourceId,
      ));
    });

    test('else the other source with the most ratings, and nothing without any', () {
      final r = rowRating(
        _place('a'),
        _digest(
          'a',
          ratings: const [
            SourceRating(sourceId: 'mangrove', average: 5, count: 1),
            SourceRating(sourceId: _extcom, average: 3.3, count: 246),
          ],
        ),
      );
      expect(r, (average: 3.3, count: 246, sourceId: _extcom));
      expect(rowRating(_place('b'), _digest('b')), isNull);
    });
  });

  group('the order of the list', () {
    // Nearest first, as the list comes.
    final near = _place('near');
    final mid = _place('mid', km: 1);
    final far = _place('far', km: 2);
    final farthest = _place('farthest', km: 3);
    final rows = [near, mid, far, farthest];

    test('by distance, as the rows come', () {
      expect(sortRows(rows, const {}, ListSort.distance), same(rows));
    });

    test('by rating: best first, more ratings before fewer, the unrated after, nearest first', () {
      final digests = {
        'mid': _digest(
          'mid',
          ratings: const [SourceRating(sourceId: _extcom, average: 3.3, count: 246)],
        ),
        'far': _digest(
          'far',
          ratings: const [SourceRating(sourceId: communityCcBySourceId, average: 4.5, count: 2)],
        ),
        'farthest': _digest(
          'farthest',
          ratings: const [SourceRating(sourceId: _extcom, average: 4.5, count: 40)],
        ),
      };
      expect(sortRows(rows, digests, ListSort.rating).map((p) => p.id), [
        'farthest',
        'far',
        'mid',
        'near',
      ]);
    });

    test('by newest: the last day first, the nearest first within a day', () {
      final digests = {
        'near': _digest('near', added: DateTime.utc(2026, 10, 5, 23)),
        'mid': _digest('mid', added: DateTime.utc(2026, 10, 7, 1)),
        'far': _digest('far', added: DateTime.utc(2026, 10, 7, 22)),
      };
      // `farthest` has no digest and an id that is no UUID v7: last.
      expect(sortRows(rows, digests, ListSort.newest).map((p) => p.id), [
        'mid',
        'far',
        'near',
        'farthest',
      ]);
    });

    test("a place without a digest is dated by its id's time", () {
      expect(
        uuidV7Time('01a10f0e-2a62-7763-9c8a-0d9fbedb1e49'),
        DateTime.utc(2026, 10, 6, 2, 32, 29, 26),
      );
      expect(uuidV7Time('6f1c2a2e-0000-4000-8000-000000000000'), isNull, reason: 'a v4');
    });
  });

  test('the area asked for a list from the tiles is refused past what the API serves', () {
    const small = GeoBounds(south: 44.4, west: 4.6, north: 44.6, east: 4.8);
    const wide = GeoBounds(south: 44, west: 4, north: 45.5, east: 5);
    expect(digestArea(small), small);
    expect(digestArea(wide), isNull);
  });

  test('a digest without a readable date is left out', () {
    final digests = placeDigestsFromJson([
      {
        'placeId': 'a',
        'addedAt': '2026-10-06T02:32:29Z',
        'ratings': [
          {'sourceId': _extcom, 'average': 3.3, 'count': 246},
        ],
        'excerpt': {'lang': 'fr', 'text': 'Cadre naturel…', 'sourceId': _extcom},
      },
      {'placeId': 'b', 'addedAt': 'soon', 'ratings': <Object>[]},
    ]);
    expect(digests, [
      PlaceDigest(
        placeId: 'a',
        addedAt: DateTime.utc(2026, 10, 6, 2, 32, 29),
        ratings: const [SourceRating(sourceId: _extcom, average: 3.3, count: 246)],
        excerpt: const LocalizedText(lang: 'fr', text: 'Cadre naturel…', sourceId: _extcom),
      ),
    ]);
  });

  group('the digests read during the run', () {
    const area = GeoBounds(south: 44.45, west: 4.65, north: 44.5, east: 4.7);
    final viviers = _digest(
      'viviers',
      ratings: const [SourceRating(sourceId: _extcom, average: 3.3, count: 246)],
    );

    ProviderContainer container(FakeDigestSource source) =>
        ProviderContainer.test(overrides: [placeDigestSourceProvider.overrideWithValue(source)]);

    test('a read completes once the API answered, and an area is not asked twice', () async {
      final source = FakeDigestSource([viviers], {'viviers': const LatLng(44.48, 4.68)});
      final c = container(source);
      final digests = c.read(placeDigestsProvider.notifier);
      // A list waits on this future: it must end with the answer, not with
      // the list's own timeout.
      await digests.loadArea(area, language: 'fr').timeout(const Duration(seconds: 2));
      expect(c.read(placeDigestsProvider), {'viviers': viviers});
      await digests.loadArea(area, language: 'fr').timeout(const Duration(seconds: 2));
      expect(source.areaRequests, hasLength(1));
    });

    test('ids already read or answered for are not asked again, and a failure is', () async {
      final source = FakeDigestSource([viviers])..offline = true;
      final c = container(source);
      final digests = c.read(placeDigestsProvider.notifier);
      await digests.loadIds(['viviers', 'gone'], language: 'fr');
      expect(c.read(placeDigestsProvider), isEmpty, reason: 'offline: nothing, no error');
      source.offline = false;
      await digests.loadIds(['viviers', 'gone'], language: 'fr');
      await digests.loadIds(['viviers', 'gone'], language: 'fr');
      expect(source.idRequests, [
        ['viviers', 'gone'],
        ['viviers', 'gone'],
      ], reason: 'asked again after the failure, then never');
      expect(c.read(placeDigestsProvider).keys, ['viviers']);
    });

    test('refused past its quota, the client asks nothing until the wait is over', () async {
      var now = DateTime.utc(2026, 10, 8, 9);
      final source = FakeDigestSource([viviers], {'viviers': const LatLng(44.48, 4.68)})
        ..refusedFor = const Duration(seconds: 60);
      final c = ProviderContainer.test(
        overrides: [
          placeDigestSourceProvider.overrideWithValue(source),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      final digests = c.read(placeDigestsProvider.notifier);
      const area = GeoBounds(south: 44.45, west: 4.65, north: 44.5, east: 4.7);
      await digests.loadArea(area, language: 'fr');
      source.refusedFor = null;
      now = now.add(const Duration(seconds: 30));
      await digests.loadIds(['viviers'], language: 'fr');
      await digests.loadArea(area, language: 'fr');
      expect(source.idRequests, isEmpty, reason: 'the address shares its quota: no more');
      expect(source.areaRequests, hasLength(1));
      now = now.add(const Duration(seconds: 31));
      await digests.loadArea(area, language: 'fr');
      expect(source.areaRequests, hasLength(2));
      expect(c.read(placeDigestsProvider).keys, ['viviers']);
    });

    test('another language drops what was read: the excerpts were in the other one', () async {
      final source = FakeDigestSource([viviers], {'viviers': const LatLng(44.48, 4.68)});
      final c = container(source);
      final digests = c.read(placeDigestsProvider.notifier);
      await digests.loadArea(area, language: 'fr');
      await digests.loadArea(area, language: 'en');
      expect(source.languages, ['fr', 'en']);
    });
  });

  group('an API before the digests', () {
    GraphQLClient client(String body) => GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient(
        (_) async => http.Response(body, 200, headers: {'content-type': 'application/json'}),
      ),
      userAgent: 'Lunaway/test (+https://lunaway.net)',
    );

    test('gives the rows nothing more, without an error', () async {
      // Production's answer of 2026-10-08, before the query was deployed.
      final source = GraphQLPlaceDigestSource(
        client(
          r'{"data":null,"errors":[{"message":"Unknown field \"placeDigests\" on type '
          r'\"Query\". Did you mean \"placeKinds\"?","extensions":{"code":"INVALID_INPUT"}}]}',
        ),
      );
      expect(await source.ofPlaces(const ['a'], language: 'fr'), isEmpty);
    });

    test('any other refusal is an error', () async {
      final source = GraphQLPlaceDigestSource(
        client('{"data":null,"errors":[{"message":"boom","extensions":{"code":"INTERNAL"}}]}'),
      );
      await expectLater(
        source.inArea(const GeoBounds(south: 44, west: 4, north: 44.1, east: 4.1), language: 'fr'),
        throwsA(isA<GraphQLResponseException>()),
      );
    });
  });
}
