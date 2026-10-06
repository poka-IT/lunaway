import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/app_database.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/fakes.dart';
import '../helpers/samples.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'a version 1 store gains the classification, keeps favourites and syncs in full again',
    () async {
      final dir = Directory.systemTemp.createTempSync('lunaway-migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/store.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      await DriftPlacesRepository(before).applyPage(
        'fr',
        ChangeSet(places: samplePlaces, deleted: const [], cursor: 'c1', hasMore: false),
        DateTime.utc(2026, 10, 6),
      );
      await DriftFavoritesRepository(before).addToDefault(lakeArea.summary);
      await before.close();
      // Back to the version 1 schema: no classification, no per-place sync
      // time, no record of a full sync.
      sqlite3.open(file.path)
        ..execute('ALTER TABLE places DROP COLUMN stars')
        ..execute('ALTER TABLE places DROP COLUMN synced_at')
        ..execute('DROP TABLE full_syncs')
        ..execute('PRAGMA user_version = 1')
        ..close();

      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      final places = DriftPlacesRepository(after);
      expect(await places.cursorFor('fr'), isNull, reason: 'the next sync is a full one');
      expect(await places.watchCount().first, samplePlaces.length);
      expect((await places.watchPlace(campsite.id).first)!.stars, isNull);
      expect(await places.fullSyncStart('fr'), isNull, reason: 'the table is there again');
      final lists = await DriftFavoritesRepository(after).watchLists().first;
      expect(lists.single.count, 1);
    },
  );

  group('settings', () {
    test('a new user starts with the "night allowed" filter and the device language', () async {
      final settings = await SettingsRepository(db).load();
      expect(settings.filter, PlaceFilter.initial);
      expect(settings.filter.nightOk, isTrue);
      expect(settings.localeCode, isNull);
    });

    test('the language and every filter survive a restart', () async {
      const filter = PlaceFilter(
        families: {KindFamily.campsites, KindFamily.nature},
        amenities: {Amenity.dumpStation},
        vehicleHeightM: 3.2,
      );
      await SettingsRepository(db).save(const AppSettings(localeCode: 'fr', filter: filter));
      final loaded = await SettingsRepository(db).load();
      expect(loaded.localeCode, 'fr');
      expect(loaded.filter, filter);
    });

    test('going back to the device language forgets the stored one', () async {
      await SettingsRepository(db).save(const AppSettings(localeCode: 'en'));
      await SettingsRepository(db).save(const AppSettings());
      expect((await SettingsRepository(db).load()).localeCode, isNull);
    });
  });

  group('favourites', () {
    test('the default list exists from the first read and holds what is saved', () async {
      final repo = DriftFavoritesRepository(db, clock: () => testNow);
      final lists = await repo.watchLists().first;
      expect(lists.single.isDefault, isTrue);
      await repo.addToDefault(lakeArea.summary);
      final entries = await repo.watchEntries(lists.single.id).first;
      expect(entries.single.placeId, lakeArea.id);
      expect(
        entries.single.name,
        lakeArea.name,
        reason: 'a snapshot keeps the place visible offline',
      );
      expect(await repo.watchListsOf(lakeArea.id).first, {lists.single.id});
    });

    test('lists can be created, renamed and deleted, the default one stays', () async {
      final repo = DriftFavoritesRepository(db, clock: () => testNow);
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

    test('a removed entry can be put back', () async {
      final repo = DriftFavoritesRepository(db, clock: () => testNow);
      await repo.addToDefault(dayParking.summary);
      final listId = (await repo.watchLists().first).single.id;
      final entry = (await repo.watchEntries(listId).first).single;
      await repo.removeEverywhere(dayParking.id);
      expect(await repo.watchEntries(listId).first, isEmpty);
      await repo.restore(entry);
      expect(await repo.watchEntries(listId).first, [entry]);
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
