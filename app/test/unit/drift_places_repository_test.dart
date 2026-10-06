import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/app_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

import '../helpers/samples.dart';

void main() {
  late AppDatabase db;
  late DriftPlacesRepository repo;
  final synced = DateTime.utc(2026, 10, 6, 8);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftPlacesRepository(db);
    await repo.applyPage(
      'fr',
      ChangeSet(places: samplePlaces, deleted: const [], cursor: 'c1', hasMore: false),
      synced,
    );
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
    });

    test('intervals from a server that sends no window end hold 14 days from the sync', () async {
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
        synced,
      );
      expect(
        (await repo.watchPlace(older.id).first)!.openingValidUntil,
        synced.add(const Duration(days: 14)),
      );
    });

    test('stores the cursor with the page', () async {
      expect(await repo.cursorFor('fr'), 'c1');
      expect(await repo.watchLastSync('fr').first, synced);
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
        synced,
      );
      expect((await repo.watchPlace(dayParking.id).first)!.name, 'Parking renommé (démo)');
      expect(await repo.watchPlace(campsite.id).first, isNull);
      expect(await repo.watchCount().first, samplePlaces.length - 1);
      // The search index follows the rename and the deletion.
      expect((await repo.search('renommé')).places.map((p) => p.id), [dayParking.id]);
      expect((await repo.search('peupliers')).places, isEmpty);
    });

    test('a full sync removes the places it did not write, inside its region only', () async {
      final later = synced.add(const Duration(hours: 1));
      await repo.beginFullSync('fr', later);
      expect(await repo.cursorFor('fr'), isNull);
      expect(await repo.fullSyncStart('fr'), later);
      // The server still has the lake area and the campsite.
      await repo.applyPage(
        'fr',
        ChangeSet(places: [lakeArea, campsite], deleted: const [], cursor: 'c9', hasMore: false),
        later,
      );
      final swept = await repo.finishFullSync(
        'fr',
        const GeoBounds(south: 44, west: -2, north: 48, east: 7),
      );
      final left = {for (final p in await repo.watchAll(PlaceFilter.none).first) p.id};
      // The service area and the unnamed car park lie outside these bounds.
      expect(left, {lakeArea.id, campsite.id, unnamedParking.id, serviceArea.id});
      expect(swept, 1, reason: 'only the day car park was inside and not written');
      expect(await repo.fullSyncStart('fr'), isNull);
      expect(await repo.cursorFor('fr'), 'c9');
      // The search index follows the sweep.
      expect((await repo.search('tilleuls')).places, isEmpty);
    });

    test('a reset forgets the places and the cursor', () async {
      await repo.reset('fr');
      expect(await repo.watchCount().first, 0);
      expect(await repo.cursorFor('fr'), isNull);
    });
  });

  group('local filters', () {
    test('no filter keeps everything', () async {
      expect(await ids(PlaceFilter.none), samplePlaces.map((p) => p.id).toSet());
    });

    test('"night allowed" keeps allowed and tolerated, drops day-only places', () async {
      expect(await ids(PlaceFilter.initial), {lakeArea.id, campsite.id, unnamedParking.id});
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

    test('the count matches the filtered list', () async {
      const filter = PlaceFilter(nightOk: true, amenities: {Amenity.water});
      expect(await repo.countMatching(filter), (await ids(filter)).length);
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
          .watchInBounds(alps, PlaceFilter.initial, center: const LatLng(45.76, 4.83))
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
