import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

import '../helpers/samples.dart';

void main() {
  late CacheDatabase db;
  late DriftPlacesRepository repo;
  final synced = DateTime.utc(2026, 10, 6, 8);
  const france = GeoBounds(south: 41, west: -6, north: 52, east: 10);

  setUp(() async {
    db = CacheDatabase(NativeDatabase.memory());
    repo = DriftPlacesRepository(db);
    await repo.beginFullSync('fr');
    await repo.applyPage(
      'fr',
      ChangeSet(places: samplePlaces, deleted: const [], cursor: 'c1', hasMore: false),
    );
    await repo.completeRun('fr', france, synced);
  });
  tearDown(() => db.close());

  Future<Set<String>> ids(PlaceFilter filter) async => {
    for (final p in await repo.watchAll(filter).first) p.id,
  };

  group('a page of changes', () {
    test('stores every place with all its fields', () async {
      final stored = await repo.watchPlace(lakeArea.id).first;
      expect(stored!.name, lakeArea.name);
      expect(stored.services, lakeArea.services);
      expect(stored.sources, lakeArea.sources);
      expect(stored.descriptions, lakeArea.descriptions);
      expect(stored.ratings, lakeArea.ratings);
      expect(stored.openingIntervals, lakeArea.openingIntervals);
      // The intervals hold until the end of the window the server sent.
      expect(stored.openingValidUntil, lakeArea.openingValidUntil);
      expect((await repo.watchPlace(campsite.id).first)!.stars, 3);
      expect(stored.ratingForFilters, 4.3);
    });

    test('keeps what the prices include', () async {
      final priced = Place(
        id: 'priced',
        kind: PlaceKind.motorhomeArea,
        lat: 45.2,
        lon: 5.1,
        overnight: OvernightStatus.allowed,
        updatedAt: DateTime.utc(2026, 10, 8),
        priceParkingEur: 14.5,
        priceServicesIncluded: true,
        priceParkingIncludes: const {PriceInclusion.touristTax, PriceInclusion.services},
      );
      await repo.applyPage(
        'fr',
        ChangeSet(places: [priced], deleted: const [], cursor: 'c2', hasMore: false),
      );
      final stored = await repo.watchPlace('priced').first;
      expect(stored!.priceServicesIncluded, isTrue);
      expect(stored.priceParkingIncludes, {PriceInclusion.touristTax, PriceInclusion.services});
      expect(stored.servicesIncluded, isTrue);
      final plain = await repo.watchPlace(lakeArea.id).first;
      expect(plain!.priceServicesIncluded, isFalse);
      expect(plain.priceParkingIncludes, isEmpty);
    });

    test('intervals without the end of their window are not kept', () async {
      // Without its end, a time in no interval could read as closed when
      // nothing is known: better no hours than wrong ones.
      final older = Place(
        id: 'test-older',
        kind: PlaceKind.parking,
        lat: 45,
        lon: 5,
        overnight: OvernightStatus.unknown,
        updatedAt: synced,
        openingHoursParsed: true,
        openingIntervals: lakeArea.openingIntervals,
      );
      await repo.applyPage(
        'fr',
        ChangeSet(places: [older], deleted: const [], cursor: 'c2', hasMore: false),
      );
      final stored = (await repo.watchPlace(older.id).first)!;
      expect(stored.openingIntervals, isNull);
      expect(stored.openingValidUntil, isNull);
    });

    test('stores the cursor with the page, the completion only at the end', () async {
      expect((await repo.stateOf('fr')).cursor, 'c1');
      expect((await repo.watchSync('fr').first).completedAt, synced);
      await repo.beginDeltaSync('fr');
      await repo.applyPage(
        'fr',
        const ChangeSet(places: [], deleted: [], cursor: 'c2', hasMore: true),
      );
      final state = await repo.stateOf('fr');
      expect(state.cursor, 'c2');
      expect(state.running, isTrue);
      expect(state.completedAt, synced, reason: 'a page is not a completed sync');
    });

    test('updates a place in place and deletes the ones the server removed', () async {
      final renamed = Place(
        id: dayParking.id,
        name: 'Parking renommé (démo)',
        kind: dayParking.kind,
        lat: dayParking.lat,
        lon: dayParking.lon,
        overnight: OvernightStatus.tolerated,
        updatedAt: synced,
      );
      await repo.applyPage(
        'fr',
        ChangeSet(places: [renamed], deleted: [campsite.id], cursor: 'c2', hasMore: false),
      );
      expect((await repo.watchPlace(dayParking.id).first)!.name, 'Parking renommé (démo)');
      expect(await repo.watchPlace(campsite.id).first, isNull);
      expect(await repo.watchCount().first, samplePlaces.length - 1);
      // The search index follows the rename and the deletion.
      expect((await repo.search('renommé')).places.map((p) => p.id), [dayParking.id]);
      expect((await repo.search('peupliers')).places, isEmpty);
    });

    test('a full sync removes the places it did not write, inside its region only', () async {
      await repo.beginFullSync('fr');
      expect((await repo.stateOf('fr')).cursor, isNull);
      expect((await repo.stateOf('fr')).fullSync, isTrue);
      // The server still has the lake area and the campsite.
      await repo.applyPage(
        'fr',
        ChangeSet(places: [lakeArea, campsite], deleted: const [], cursor: 'c9', hasMore: false),
      );
      final swept = await repo.completeRun(
        'fr',
        const GeoBounds(south: 44, west: -2, north: 48, east: 7),
        synced.add(const Duration(hours: 1)),
      );
      final left = {for (final p in await repo.watchAll(PlaceFilter.none).first) p.id};
      // The service area and the unnamed car park lie outside these bounds.
      expect(left, {lakeArea.id, campsite.id, unnamedParking.id, serviceArea.id});
      expect(swept, 1, reason: 'only the day car park was inside and not written');
      final state = await repo.stateOf('fr');
      expect(state.fullSync, isFalse);
      expect(state.cursor, 'c9');
      // The search index follows the sweep.
      expect((await repo.search('tilleuls')).places, isEmpty);
    });

    test(
      'the sweep goes by generation, not by clock: a clock set back sweeps nothing written',
      () async {
        await repo.beginFullSync('fr');
        await repo.applyPage(
          'fr',
          ChangeSet(places: samplePlaces, deleted: const [], cursor: 'c9', hasMore: false),
        );
        // Completion recorded at a time before the first sync: irrelevant.
        final swept = await repo.completeRun(
          'fr',
          france,
          synced.subtract(const Duration(days: 30)),
        );
        expect(swept, 0);
        expect(await repo.watchCount().first, samplePlaces.length);
      },
    );

    test('a reset forgets its region only: its state and the places inside its bounds', () async {
      await repo.beginFullSync('other');
      await repo.reset('fr', const GeoBounds(south: 45, west: 4, north: 47, east: 7));
      expect((await repo.stateOf('fr')).cursor, isNull);
      expect((await repo.stateOf('other')).generation, 1, reason: 'another region keeps its state');
      final left = {for (final p in await repo.watchAll(PlaceFilter.none).first) p.id};
      expect(left, {campsite.id, unnamedParking.id, serviceArea.id});
    });
  });

  group('local filters', () {
    test('no filter keeps everything', () async {
      expect(await ids(PlaceFilter.none), samplePlaces.map((p) => p.id).toSet());
    });

    test('"night possible" keeps allowed and tolerated, drops day-only places', () async {
      expect(await ids(PlaceFilter.none.withNightOk(on: true)), {
        lakeArea.id,
        campsite.id,
        unnamedParking.id,
      });
    });

    test('a single night status keeps that status only', () async {
      expect(await ids(const PlaceFilter(overnight: {OvernightStatus.dayOnly})), {
        dayParking.id,
        serviceArea.id,
      });
    });

    test('a family keeps its kinds only', () async {
      expect(await ids(const PlaceFilter(families: {KindFamily.services})), {serviceArea.id});
      expect(await ids(const PlaceFilter(families: {KindFamily.campsites})), {campsite.id});
    });

    test('a dump station is a grey or a black water point', () async {
      expect(await ids(const PlaceFilter(amenities: {Amenity.dumpStation})), {
        lakeArea.id,
        serviceArea.id,
      });
    });

    test('every amenity asked must be there', () async {
      expect(await ids(const PlaceFilter(amenities: {Amenity.water, Amenity.electricity})), {
        lakeArea.id,
        campsite.id,
      });
    });

    test('a vehicle height hides lower barriers but keeps unknown heights', () async {
      final kept = await ids(const PlaceFilter(vehicleHeightM: 2.8));
      expect(kept.contains(dayParking.id), isFalse, reason: 'its barrier is 2.10 m');
      expect(kept.contains(lakeArea.id), isTrue, reason: 'no known barrier');
    });

    test('"free" keeps the places whose night is known to be free, not the unknown ones', () async {
      expect(await ids(const PlaceFilter(freeOnly: true)), {dayParking.id});
      expect(await repo.countMatching(const PlaceFilter(freeOnly: true)), 1);
    });

    test('a minimum rating keeps the places rated at least as high, not the unrated', () async {
      expect(await ids(const PlaceFilter(minRating: 4)), {lakeArea.id, campsite.id});
      expect(await ids(const PlaceFilter(minRating: 4.5)), isEmpty);
      expect(await ids(const PlaceFilter(minRating: 3)), {
        lakeArea.id,
        campsite.id,
      }, reason: '2.9 is under 3, and the places nobody rated are left out');
      expect(await repo.countMatching(const PlaceFilter(minRating: 4)), 2);
      final camp = (await repo.watchAll(PlaceFilter.none).first).firstWhere(
        (p) => p.id == campsite.id,
      );
      expect(camp.ratingForFilters, 4, reason: 'the list filters again on the same value');
    });

    test('the count matches the filtered list', () async {
      const filter = PlaceFilter(overnight: nightPossible, amenities: {Amenity.water});
      expect(await repo.countMatching(filter), (await ids(filter)).length);
    });

    test('the count of a view matches the list of that view', () async {
      const annecy = GeoBounds(south: 45.85, west: 6.05, north: 45.95, east: 6.25);
      for (final filter in const [
        PlaceFilter.none,
        PlaceFilter(overnight: nightPossible),
        PlaceFilter(families: {KindFamily.campsites}),
      ]) {
        final listed = await repo.watchInBounds(annecy, filter, center: annecy.center).first;
        expect(await repo.countMatching(filter, bounds: annecy), listed.length, reason: '$filter');
      }
      expect(await repo.countMatching(PlaceFilter.none, bounds: annecy), 1, reason: 'the lake');
    });

    test('the summary carries the combined rating', () async {
      final lake = (await repo.watchAll(PlaceFilter.none).first).firstWhere(
        (p) => p.id == lakeArea.id,
      );
      expect(lake.ratingCount, 130);
      expect(lake.ratingAverage, closeTo((4.3 * 128 + 4 * 2) / 130, 1e-9));
    });
  });

  group('the viewport', () {
    test('returns only the places inside the box, nearest first', () async {
      const alps = GeoBounds(south: 45, west: 4, north: 47, east: 7);
      final inside = await repo
          .watchInBounds(alps, PlaceFilter.none, center: const LatLng(45.76, 4.83))
          .first;
      expect(inside.map((p) => p.id), [dayParking.id, lakeArea.id]);
    });

    test('applies the filter in the box too', () async {
      const alps = GeoBounds(south: 45, west: 4, north: 47, east: 7);
      final inside = await repo
          .watchInBounds(
            alps,
            const PlaceFilter(overnight: nightPossible),
            center: const LatLng(45.76, 4.83),
          )
          .first;
      expect(inside.map((p) => p.id), [lakeArea.id]);
    });

    test('stops at the limit', () async {
      final inside = await repo
          .watchInBounds(
            GeoBounds.metropolitanFrance,
            PlaceFilter.none,
            center: const LatLng(46, 2),
            limit: 2,
          )
          .first;
      expect(inside, hasLength(2));
    });
  });

  group('search', () {
    test('ignores accents and case, on word starts', () async {
      expect((await repo.search('LAC bl')).places.map((p) => p.id), [lakeArea.id]);
      expect((await repo.search('sete')).municipalities.map((m) => m.name), ['Sète']);
    });

    test('finds towns with their place count and centre', () async {
      final towns = (await repo.search('annec')).municipalities;
      expect(towns, hasLength(1));
      expect(towns.single.placeCount, 1);
      expect(towns.single.center.lat, closeTo(lakeArea.lat, 1e-9));
    });

    test('one town per commune and department: homonyms apart, two spellings one', () async {
      var n = 0;
      Place at(String city, String postcode, double lat, double lon) => Place(
        id: 'town-${n++}',
        kind: PlaceKind.parking,
        lat: lat,
        lon: lon,
        overnight: OvernightStatus.unknown,
        address: Address(postcode: postcode, city: city, countryCode: 'FR'),
        updatedAt: synced,
      );
      await repo.applyPage(
        'fr',
        ChangeSet(
          places: [
            for (var i = 0; i < 3; i++) at('Viviers', '07220', 44.48, 4.68),
            at('Viviers', '89700', 47.9, 4),
            for (var i = 0; i < 4; i++) at('Chamonix-Mont-Blanc', '74400', 45.92, 6.87),
            at('Chamonix', '74400', 45.93, 6.87),
          ],
          deleted: const [],
          cursor: 'c2',
          hasMore: false,
        ),
      );
      expect(
        (await repo.search('viviers')).municipalities
            .map((m) => (m.name, m.postcode, m.department, m.placeCount)),
        [('Viviers', '07220', '07', 3), ('Viviers', '89700', '89', 1)],
        reason: 'the device grouped them by name alone, the centre between two departments',
      );
      expect((await repo.search('chamonix')).municipalities.map((m) => (m.name, m.placeCount)), [
        ('Chamonix-Mont-Blanc', 5),
      ], reason: 'the device listed "Chamonix" beside "Chamonix-Mont-Blanc"');
    });

    test('quotes and operators typed by the user cannot break the query', () async {
      expect((await repo.search('"lac" -bleu* (')).places.map((p) => p.id), contains(lakeArea.id));
      expect(await repo.search('   '), same(await repo.search('')));
    });

    test('orders matches by distance when a position is given', () async {
      final near = await repo.search('démo', near: const LatLng(47.2, -1.55));
      expect(near.places.first.id, campsite.id);
    });
  });

  test('the size of the store is reported', () async {
    expect(await repo.storageSizeBytes(), greaterThan(0));
  });
}
