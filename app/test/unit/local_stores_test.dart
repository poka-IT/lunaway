import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

import '../helpers/fakes.dart';
import '../helpers/samples.dart';

void main() {
  late CacheDatabase db;
  late UserDatabase user;
  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    user = UserDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await user.close();
  });

  test(
    'the cache is at version 7 (what the prices include), the user store at 4 (cruising speed)',
    () {
      expect(db.schemaVersion, 7);
      expect(user.schemaVersion, 4);
    },
  );

  group('settings', () {
    test('a new user starts with no filter, the automatic theme and the device language', () async {
      final settings = await SettingsRepository(user).load();
      expect(settings.filter, PlaceFilter.none, reason: 'service points show from the start');
      expect(settings.theme, ThemePreference.auto);
      expect(settings.localeCode, isNull);
      expect(settings.navigationApp, isNull);
      expect(settings.listSort, ListSort.distance, reason: 'nearest first until chosen');
    });

    test('the language, the theme, the navigation app, the order of the list and every filter '
        'survive a restart', () async {
      const filter = PlaceFilter(
        families: {KindFamily.campsites, KindFamily.nature},
        overnight: {OvernightStatus.allowed},
        amenities: {Amenity.dumpStation, Amenity.showers},
        fitsMyVehicle: true,
        freeOnly: true,
        minRating: 4.5,
      );
      await SettingsRepository(user).save(
        const AppSettings(
          localeCode: 'fr',
          filter: filter,
          theme: ThemePreference.dark,
          navigationApp: 'waze',
          railCollapsed: true,
          copyFormat: CoordinateFormat.dms,
          listSort: ListSort.newest,
        ),
      );
      final loaded = await SettingsRepository(user).load();
      expect(loaded.localeCode, 'fr');
      expect(loaded.filter, filter);
      expect(loaded.theme, ThemePreference.dark);
      expect(loaded.navigationApp, 'waze');
      expect(loaded.railCollapsed, isTrue);
      expect(loaded.copyFormat, CoordinateFormat.dms);
      expect(loaded.listSort, ListSort.newest);
    });

    test('going back to the device language and forgetting the app clears them', () async {
      await SettingsRepository(user)
          .save(const AppSettings(localeCode: 'en', navigationApp: 'waze'));
      await SettingsRepository(user).save(const AppSettings());
      final loaded = await SettingsRepository(user).load();
      expect(loaded.localeCode, isNull);
      expect(loaded.navigationApp, isNull);
    });

    test('a filter no longer offered (LPG) is dropped from a stored value', () {
      expect(
        SettingsRepository.decodeFilter('{"amenities": ["lpg", "water"]}'),
        const PlaceFilter(amenities: {Amenity.water}),
      );
    });

    test('a stored minimum rating the filters no longer offer is dropped', () {
      expect(
        SettingsRepository.decodeFilter('{"freeOnly": true, "minRating": 4.75}'),
        const PlaceFilter(freeOnly: true),
      );
      expect(SettingsRepository.decodeFilter('{"minRating": 4}'), const PlaceFilter(minRating: 4));
      expect(
        SettingsRepository.decodeFilter('{"freeOnly": true}'),
        const PlaceFilter(freeOnly: true),
        reason: 'a value stored before the rating has none',
      );
    });

    test('a corrupt or older filter value falls back without blocking the start', () {
      expect(SettingsRepository.decodeFilter('{not json'), PlaceFilter.none);
      expect(
        SettingsRepository.decodeFilter('{"overnight": ["allowed", "someday"], "families": ["x"]}'),
        const PlaceFilter(overnight: {OvernightStatus.allowed}),
      );
    });
  });

  group('favourites', () {
    test('the default list exists from the first read and holds what is saved', () async {
      final repo = DriftFavoritesRepository(user, clock: () => testNow);
      final lists = await repo.watchLists().first;
      expect(lists.single.isDefault, isTrue);
      expect(await repo.defaultListId(), lists.single.id);
      await repo.addToDefault(lakeArea.summary);
      final entries = await repo.watchEntries(lists.single.id).first;
      final entry = entries.single;
      expect(entry.placeId, lakeArea.id);
      // A snapshot keeps the place readable offline: name, kind, night, town.
      expect(
        (entry.name, entry.overnight, entry.city),
        (lakeArea.name, OvernightStatus.allowed, 'Annecy'),
      );
      expect(await repo.watchListsOf(lakeArea.id).first, {lists.single.id});
    });

    test('lists can be created, renamed and deleted, the default one stays', () async {
      final repo = DriftFavoritesRepository(user, clock: () => testNow);
      final defaultId = (await repo.watchLists().first).single.id;
      final trip = await repo.createList('  Été 2027 ');
      await repo.add(trip, campsite.summary);
      await repo.renameList(trip, 'Bretagne');
      var lists = await repo.watchLists().first;
      expect(lists.map((l) => (l.name, l.count)), [(null, 0), ('Bretagne', 1)]);
      await repo.deleteList(defaultId);
      await repo.deleteList(trip);
      lists = await repo.watchLists().first;
      expect(lists.single.isDefault, isTrue);
      expect(
        await repo.watchListsOf(campsite.id).first,
        isEmpty,
        reason: 'its entries went with the list',
      );
    });

    test('a removal from one list leaves the others, and gives back what to restore', () async {
      final repo = DriftFavoritesRepository(user, clock: () => testNow);
      final defaultId = await repo.defaultListId();
      final trip = await repo.createList('Trip');
      await repo.addToDefault(dayParking.summary);
      await repo.add(trip, dayParking.summary);
      final removed = await repo.remove(defaultId, dayParking.id);
      expect(removed?.listId, defaultId);
      expect(await repo.watchListsOf(dayParking.id).first, {trip});
      await repo.restore(removed!);
      expect(await repo.watchListsOf(dayParking.id).first, {defaultId, trip});
      expect(await repo.remove(defaultId, 'nowhere'), isNull);
    });
  });

  group('vehicle', () {
    test('none at first, then the saved one, with every dimension', () async {
      final repo = DriftVehicleRepository(user, clock: () => testNow);
      expect(await repo.watch().first, isNull);
      final van = Vehicle.typical(VehicleType.overcab)
          .copyWith(towing: Towing.car, weightT: () => null);
      await repo.save(van);
      expect(await repo.watch().first, van);
      await repo.save(van.copyWith(heightM: () => 3.3));
      expect((await repo.watch().first)!.heightM, 3.3, reason: 'one vehicle, updated in place');
      await repo.clear();
      expect(await repo.watch().first, isNull);
    });
  });

  group('last position', () {
    test('is kept coarse, about ten kilometres, out of the user store', () async {
      final store = DriftLastPositionStore(db);
      expect(await store.load(), isNull);
      await store.save(const LatLng(45.899236, 6.129387));
      expect(await store.load(), const LatLng(45.9, 6.1));
    });
  });

  group('photos and reviews', () {
    test('are fetched once, then served from the cache while fresh', () async {
      final source = FakeExtrasSource(photos: samplePhotos, reviews: sampleReviews);
      var now = testNow;
      final repo = PlaceExtrasRepository(db: db, source: source, clock: () => now, pageSize: 2);
      final first = await repo.watch(lakeArea.id).last;
      expect(first!.photos, samplePhotos);
      expect(first.reviews.nodes, hasLength(2));
      expect(source.fetches, 1);
      now = testNow.add(const Duration(hours: 1));
      expect(
        await repo.watch(lakeArea.id).toList(),
        hasLength(1),
        reason: 'fresh cache, no new request',
      );
      expect(source.fetches, 1);
    });

    test('offline, a stale cache still shows; without a cache the error surfaces', () async {
      final source = FakeExtrasSource(photos: samplePhotos, reviews: sampleReviews);
      var now = testNow;
      final repo = PlaceExtrasRepository(db: db, source: source, clock: () => now);
      await repo.watch(lakeArea.id).last;
      source.online = false;
      now = testNow.add(const Duration(days: 3));
      expect((await repo.watch(lakeArea.id).toList()).single!.photos, samplePhotos);
      await expectLater(repo.watch(campsite.id).toList(), throwsStateError);
    });

    test('the next pages of reviews append to the first', () async {
      final source = FakeExtrasSource(reviews: sampleReviews);
      final repo = PlaceExtrasRepository(db: db, source: source, clock: () => testNow, pageSize: 2);
      final first = (await repo.watch(lakeArea.id).last)!.reviews;
      final second = await repo.more(lakeArea.id, first);
      final third = await repo.more(lakeArea.id, second);
      expect(third.nodes.map((r) => r.id), sampleReviews.map((r) => r.id));
      expect(third.hasNextPage, isFalse);
      expect(await repo.more(lakeArea.id, third), same(third), reason: 'nothing left to load');
    });
  });

  test('the combined rating weighs each source by its review count', () {
    final rating = combinedRating(const [
      SourceRating(sourceId: 'a', average: 4, count: 30),
      SourceRating(sourceId: 'b', average: 2, count: 10),
      SourceRating(sourceId: 'c', average: 5, count: 0),
    ]);
    expect(rating!.count, 40);
    expect(rating.average, 3.5);
    expect(combinedRating(const []), isNull);
  });

  test('the description follows the user language, then English, then the first', () {
    const texts = [
      LocalizedText(lang: 'de', text: 'Deutsch', sourceId: 's'),
      LocalizedText(lang: 'en', text: 'English', sourceId: 's'),
    ];
    expect(descriptionFor(texts, 'de')!.inUserLanguage, isTrue);
    final fr = descriptionFor(texts, 'fr')!;
    expect((fr.text.text, fr.inUserLanguage), ('English', false));
    expect(descriptionFor(texts.take(1).toList(), 'fr')!.text.text, 'Deutsch');
    expect(descriptionFor(const [], 'fr'), isNull);
  });
}
