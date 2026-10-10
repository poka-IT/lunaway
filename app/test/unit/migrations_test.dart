import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:sqlite3/sqlite3.dart';

/// The schema of an earlier [version] as it shipped, taken from the current
/// one minus what came after it: every table, index, virtual table and
/// trigger, with [dropColumns] taken out of their CREATE TABLE and
/// [dropTables] left out.
Future<void> _writeVersion(
  QueryExecutor current,
  File file, {
  required Map<String, List<String>> dropColumns,
  required Set<String> dropTables,
  Set<String> dropIndexes = const {},
  int version = 1,
}) async {
  final db = _Raw(current);
  final rows = await db
      .customSelect(
        'SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL '
        "AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, rowid",
      )
      .get();
  final out = sqlite3.open(file.path);
  for (final r in rows) {
    final table = r.read<String>('tbl_name');
    var sql = r.read<String>('sql');
    if (dropTables.contains(table)) continue;
    if (dropIndexes.contains(r.read<String>('name'))) continue;
    // The shadow tables of a virtual table come with it.
    if (r.read<String>('type') == 'table' && RegExp('^place_(search|bounds)_').hasMatch(table)) {
      continue;
    }
    for (final column in dropColumns[table] ?? const <String>[]) {
      sql = sql.replaceAll(RegExp(',\\s*"?$column"?\\s[^,]*?(?=,|\\s*\\)\\s*\$)'), '');
    }
    out.execute(sql);
  }
  out
    ..execute('PRAGMA user_version = $version')
    ..close();
  await db.close();
}

/// What version 4 of the cache added: the region of each place, its index,
/// and the speed camera data of the guidance.
const _regionColumns = ['region'];
const _v4Tables = {'enforcement_items'};

/// What version 5 of the cache added: the places opened online.
const _v5Tables = {'place_cache'};

/// The column version 6 of the cache added: the rating the filters compare.
const _v6Columns = ['filter_rating'];

/// The columns version 7 of the cache added: what the prices include.
const _v7Columns = ['price_services_included', 'price_parking_includes'];

/// The columns version 8 of the cache added: the seasons the filter on
/// opening compares.
const _v8Columns = ['season_1', 'season_2'];
const _v4Indexes = {'places_region'};

/// The columns version 3 of the user store added to the vehicle.
const _fuelColumns = ['fuel', 'consumption_l100', 'lpg_heating'];

/// The column version 4 of the user store added to the vehicle.
const _cruiseColumns = ['cruise_speed_kph'];

/// What version 5 of the user store added: the saved points and their part
/// of the sync's base.
const _userV5Tables = {'favorite_points'};
const _userV5BaseColumns = ['points', 'local_only_points'];

final class _Raw extends GeneratedDatabase {
  new(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 2;
}

void main() {
  late Directory dir;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('lunaway-migration');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a version 1 user database keeps its favourites and gains the outbox', () async {
    final fresh = UserDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/user.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: {
        'favorite_lists': ['server_id'],
        'vehicles': [..._fuelColumns, ..._cruiseColumns],
      },
      dropTables: {'favorite_sync_base', 'outbox', 'outbox_files', ..._userV5Tables},
    );
    final old = sqlite3.open(file.path)
      ..execute("INSERT INTO favorite_lists (name, is_default, created_at) VALUES ('Été', 0, 1)")
      ..execute(
        'INSERT INTO favorite_items (list_id, place_id, kind, lat, lon, added_at) '
        "VALUES (1, 'p1', 'PARKING', 45, 6, 1)",
      );
    expect(
      old.select('PRAGMA table_info(favorite_lists)').map((r) => r['name']),
      isNot(contains('server_id')),
    );
    old.close();

    final upgraded = UserDatabase(NativeDatabase(file));
    final list = await upgraded.select(upgraded.favoriteLists).getSingle();
    expect(list.name, 'Été');
    expect(list.serverId, isNull);
    expect(await upgraded.select(upgraded.favoriteItems).get(), hasLength(1));
    await upgraded
        .into(upgraded.outbox)
        .insert(OutboxCompanion.insert(id: 'e1', kind: 'rate', payload: '{}', createdAt: 1));
    expect(await upgraded.select(upgraded.outbox).get(), hasLength(1));
    await upgraded.close();
  });

  test('a version 1 cache keeps its places and resyncs them for the new columns', () async {
    final fresh = CacheDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/cache.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: {
        'places': [
          'verification',
          'review_count',
          'photo_count',
          'cover_photos_json',
          'issues_json',
          ..._regionColumns,
          ..._v6Columns,
          ..._v7Columns,
          ..._v8Columns,
        ],
      },
      dropTables: const {'poi_cache', ..._v4Tables, ..._v5Tables},
      dropIndexes: _v4Indexes,
    );
    sqlite3.open(file.path)
      ..execute(
        'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at) '
        "VALUES ('p1', 'PARKING', 0, 45, 6, 'ALLOWED', 1)",
      )
      ..execute(
        'INSERT INTO region_syncs (region, cursor, generation, full_sync, running, completed_at) '
        "VALUES ('fr-metro', 'c42', 3, 0, 0, 1700000000000)",
      )
      ..close();

    final upgraded = CacheDatabase(NativeDatabase(file));
    final repo = DriftPlacesRepository(upgraded);
    final place = await repo.watchPlace('p1').first;
    expect(place, isNotNull, reason: 'the places stay until the next sync sweeps');
    expect(place!.coverPhotos, isEmpty);
    final state = await repo.stateOf(SyncRegion.metropolitanFrance.id);
    expect(state.running, isTrue, reason: 'a sync starts at the next launch');
    expect(state.fullSync, isTrue);
    expect(state.cursor, isNull, reason: 'from scratch, to fill the new columns');
    expect(state.generation, 5, reason: 'versions 2 and 6 each start a sync from scratch');
    expect(state.completedAt, isNotNull, reason: 'the date of the last sync stays for the screens');
    await upgraded.close();
  });

  test('a version 2 cache keeps its places and gains the points read around them', () async {
    final fresh = CacheDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/cache2.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {
        'places': [..._regionColumns, ..._v6Columns, ..._v7Columns, ..._v8Columns],
      },
      dropTables: const {'poi_cache', ..._v4Tables, ..._v5Tables},
      dropIndexes: _v4Indexes,
      version: 2,
    );
    sqlite3.open(file.path)
      ..execute(
        'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at) '
        "VALUES ('p1', 'PARKING', 0, 45, 6, 'ALLOWED', 1)",
      )
      ..execute(
        'INSERT INTO region_syncs (region, cursor, generation, full_sync, running, completed_at) '
        "VALUES ('fr-metro', 'c42', 3, 0, 0, 1700000000000)",
      )
      ..close();

    final upgraded = CacheDatabase(NativeDatabase(file));
    final repo = DriftPlacesRepository(upgraded);
    expect(await repo.watchPlace('p1').first, isNotNull);
    final state = await repo.stateOf(SyncRegion.metropolitanFrance.id);
    expect(
      state.cursor,
      isNull,
      reason: 'versions 3 to 5 keep the cursor; version 6 syncs again for the rating',
    );
    await upgraded
        .into(upgraded.poiCache)
        .insert(PoiCacheCompanion.insert(cacheKey: 'nearby:p1', json: '[]', fetchedAt: 1));
    expect(await upgraded.select(upgraded.poiCache).get(), hasLength(1));
    await upgraded.close();
  });

  test('a version 3 cache keeps the places synced by box until its regions have synced', () async {
    final fresh = CacheDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/cache3.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {
        'places': [..._regionColumns, ..._v6Columns, ..._v7Columns, ..._v8Columns],
      },
      dropTables: const {..._v4Tables, ..._v5Tables},
      dropIndexes: _v4Indexes,
      version: 3,
    );
    sqlite3.open(file.path)
      ..execute(
        'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at) '
        "VALUES ('p1', 'PARKING', 0, 45, 6, 'ALLOWED', 1)",
      )
      ..execute(
        'INSERT INTO region_syncs (region, cursor, generation, full_sync, running, completed_at) '
        "VALUES ('fr-metro', 'c42', 3, 0, 0, 1700000000000)",
      )
      ..close();

    final upgraded = CacheDatabase(NativeDatabase(file));
    final repo = DriftPlacesRepository(upgraded);
    expect(await repo.watchPlace('p1').first, isNotNull, reason: 'the map keeps its places');
    final row = await upgraded.select(upgraded.places).getSingle();
    expect(row.region, isNull, reason: 'a place of the sync by box has no region yet');
    final state = await repo.stateOf(SyncRegion.metropolitanFrance.id);
    expect(state.completedAt, isNotNull, reason: 'its date stands until the regions have synced');
    await upgraded
        .into(upgraded.enforcementItems)
        .insert(
          EnforcementItemsCompanion.insert(
            id: 'z1',
            kind: 'ZONE',
            category: 'FIXED',
            country: 'FR',
          ),
        );
    expect(await upgraded.select(upgraded.enforcementItems).get(), hasLength(1));
    await upgraded.close();
  });

  test('a version 4 cache keeps its places and gains the places opened online', () async {
    final fresh = CacheDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/cache4.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {
        'places': [..._v6Columns, ..._v7Columns, ..._v8Columns],
      },
      dropTables: _v5Tables,
      version: 4,
    );
    sqlite3.open(file.path)
      ..execute(
        'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at, region) '
        "VALUES ('p1', 'PARKING', 0, 45, 6, 'ALLOWED', 1, 'FR-ARA')",
      )
      ..close();

    final upgraded = CacheDatabase(NativeDatabase(file));
    expect(await DriftPlacesRepository(upgraded).watchPlace('p1').first, isNotNull);
    await upgraded
        .into(upgraded.placeCache)
        .insert(PlaceCacheCompanion.insert(placeId: 'p2', json: '{}', fetchedAt: 1));
    expect(await upgraded.select(upgraded.placeCache).get(), hasLength(1));
    await upgraded.close();
  });

  test(
    'a version 5 cache keeps its places and syncs again for the rating of the filters',
    () async {
      final fresh = CacheDatabase(NativeDatabase.memory());
      await fresh.customSelect('SELECT 1').get();
      final file = File('${dir.path}/cache5.sqlite');
      await _writeVersion(
        fresh.executor,
        file,
        dropColumns: const {
          'places': [..._v6Columns, ..._v7Columns, ..._v8Columns],
        },
        dropTables: const {},
        version: 5,
      );
      sqlite3.open(file.path)
        ..execute(
          'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at, region) '
          "VALUES ('p1', 'PARKING', 0, 45, 6, 'ALLOWED', 1, 'FR-ARA')",
        )
        ..execute(
          'INSERT INTO region_syncs (region, cursor, generation, full_sync, running, completed_at) '
          "VALUES ('FR-ARA', 'c42', 3, 0, 0, 1700000000000)",
        )
        ..close();

      final upgraded = CacheDatabase(NativeDatabase(file));
      final repo = DriftPlacesRepository(upgraded);
      final place = await repo.watchPlace('p1').first;
      expect(place, isNotNull);
      expect(place!.ratingForFilters, isNull, reason: 'unknown until the region syncs again');
      final state = await repo.stateOf('FR-ARA');
      expect(
        state.cursor,
        isNull,
        reason: 'from scratch: a place rated long ago does not come again in the feed',
      );
      expect(state.fullSync, isTrue);
      expect(state.running, isTrue, reason: 'the sync starts at the next launch');
      expect(
        state.completedAt,
        isNotNull,
        reason: 'the date of the last sync stays for the screens',
      );
      expect(
        await repo.countMatching(const PlaceFilter(minRating: 3)),
        0,
        reason: 'the filter reads the new column',
      );
      await upgraded.close();
    },
  );

  test('a version 6 cache keeps its places and syncs again for what the prices include', () async {
    final fresh = CacheDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/cache6.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {
        'places': [..._v7Columns, ..._v8Columns],
      },
      dropTables: const {},
      version: 6,
    );
    sqlite3.open(file.path)
      ..execute(
        'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at, region, '
        'price_parking, price_services) '
        "VALUES ('p1', 'CAMPSITE', 1, 45, 6, 'ALLOWED', 1, 'FR-ARA', 60, 0)",
      )
      ..execute(
        'INSERT INTO region_syncs (region, cursor, generation, full_sync, running, completed_at) '
        "VALUES ('FR-ARA', 'c42', 3, 0, 0, 1700000000000)",
      )
      ..close();

    final upgraded = CacheDatabase(NativeDatabase(file));
    final repo = DriftPlacesRepository(upgraded);
    final place = await repo.watchPlace('p1').first;
    expect(place, isNotNull, reason: 'the places stay until the next sync sweeps');
    expect(place!.priceServicesIncluded, isFalse, reason: 'unknown until the region syncs');
    expect(place.priceParkingIncludes, isEmpty);
    expect(place.servicesIncluded, isTrue, reason: 'free services at a paid night read at once');
    expect(place.openingSeason, isNull, reason: 'no season known until the region syncs');
    expect(
      await repo.countMatching(const PlaceFilter(opening: AllYearOpening())),
      1,
      reason: 'the filter on opening reads the new columns and keeps a place of unknown season',
    );
    final state = await repo.stateOf('FR-ARA');
    expect(state.cursor, isNull, reason: 'a place priced long ago does not come again in the feed');
    expect(state.fullSync, isTrue);
    expect(state.running, isTrue, reason: 'the sync starts at the next launch');
    expect(state.generation, 4, reason: 'one sync from scratch');
    expect(state.completedAt, isNotNull, reason: 'the date of the last sync stays for the screens');
    await upgraded.close();
  });

  test('a version 7 cache keeps its places and syncs again for the seasons', () async {
    final fresh = CacheDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/cache7.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {'places': _v8Columns},
      dropTables: const {},
      version: 7,
    );
    sqlite3.open(file.path)
      ..execute(
        'INSERT INTO places (id, kind, family, lat, lon, overnight, updated_at, region, '
        'price_parking, price_services_included) '
        "VALUES ('p1', 'CAMPSITE', 1, 45, 6, 'ALLOWED', 1, 'FR-ARA', 60, 1)",
      )
      ..execute(
        'INSERT INTO region_syncs (region, cursor, generation, full_sync, running, completed_at) '
        "VALUES ('FR-ARA', 'c42', 3, 0, 0, 1700000000000)",
      )
      ..close();

    final upgraded = CacheDatabase(NativeDatabase(file));
    final repo = DriftPlacesRepository(upgraded);
    final place = await repo.watchPlace('p1').first;
    expect(place, isNotNull, reason: 'the places stay until the next sync sweeps');
    expect(place!.priceServicesIncluded, isTrue, reason: 'what version 7 knew stays');
    expect(place.openingSeason, isNull, reason: 'no season known until the region syncs');
    expect(
      await repo.countMatching(const PlaceFilter(opening: AllYearOpening())),
      1,
      reason: 'the filter on opening reads the new columns and keeps a place of unknown season',
    );
    final state = await repo.stateOf('FR-ARA');
    expect(state.cursor, isNull, reason: 'a place given a season before does not come again');
    expect(state.fullSync, isTrue);
    expect(state.running, isTrue, reason: 'the sync starts at the next launch');
    expect(state.generation, 4, reason: 'one sync from scratch');
    expect(state.completedAt, isNotNull, reason: 'the date of the last sync stays for the screens');
    await upgraded.close();
  });

  test('a version 2 user database keeps its vehicle and gains its fuel, unsaid', () async {
    final fresh = UserDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/user2.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {
        'vehicles': [..._fuelColumns, ..._cruiseColumns],
        'favorite_sync_base': _userV5BaseColumns,
      },
      dropTables: _userV5Tables,
      version: 2,
    );
    final old = sqlite3.open(file.path)
      ..execute(
        'INSERT INTO vehicles (id, type, towing, height_m, updated_at) '
        "VALUES (1, 'overcab', 'none', 3.1, 1)",
      );
    expect(
      old.select('PRAGMA table_info(vehicles)').map((r) => r['name']),
      isNot(contains('fuel')),
    );
    old.close();

    final upgraded = UserDatabase(NativeDatabase(file));
    final repo = DriftVehicleRepository(upgraded, clock: () => DateTime.utc(2026, 10, 6));
    final vehicle = await repo.watch().first;
    expect(vehicle?.type, VehicleType.overcab);
    expect(vehicle?.heightM, 3.1);
    expect(vehicle?.fuel, isNull);
    expect(vehicle?.lpgHeating, isFalse);
    await repo.save(vehicle!.copyWith(fuel: () => FuelType.lpg, lpgHeating: true));
    final saved = await repo.watch().first;
    expect(saved?.fuel, FuelType.lpg);
    expect(saved?.lpgHeating, isTrue);
    await upgraded.close();
  });

  test('a version 3 user database keeps its vehicle and gains its cruising speed, unset', () async {
    final fresh = UserDatabase(NativeDatabase.memory());
    await fresh.customSelect('SELECT 1').get();
    final file = File('${dir.path}/user3.sqlite');
    await _writeVersion(
      fresh.executor,
      file,
      dropColumns: const {'vehicles': _cruiseColumns, 'favorite_sync_base': _userV5BaseColumns},
      dropTables: _userV5Tables,
      version: 3,
    );
    final old = sqlite3.open(file.path)
      ..execute(
        'INSERT INTO vehicles (id, type, towing, height_m, updated_at, fuel) '
        "VALUES (1, 'overcab', 'none', 3.1, 1, 'DIESEL')",
      );
    expect(
      old.select('PRAGMA table_info(vehicles)').map((r) => r['name']),
      isNot(contains('cruise_speed_kph')),
    );
    old.close();

    final upgraded = UserDatabase(NativeDatabase(file));
    final repo = DriftVehicleRepository(upgraded, clock: () => DateTime.utc(2026, 10, 7));
    final vehicle = await repo.watch().first;
    expect(vehicle?.fuel, FuelType.diesel);
    expect(vehicle?.cruiseSpeedKph, isNull, reason: 'the usual speeds until set');
    await repo.save(vehicle!.copyWith(cruiseSpeedKph: () => 95));
    expect((await repo.watch().first)?.cruiseSpeedKph, 95);
    await repo.save(vehicle.copyWith(cruiseSpeedKph: () => null));
    expect((await repo.watch().first)?.cruiseSpeedKph, isNull, reason: '"no limit" is kept too');
    await upgraded.close();
  });

  test(
    'a version 4 user database keeps its synced favourites and gains the saved points',
    () async {
      final fresh = UserDatabase(NativeDatabase.memory());
      await fresh.customSelect('SELECT 1').get();
      final file = File('${dir.path}/user4.sqlite');
      await _writeVersion(
        fresh.executor,
        file,
        dropColumns: const {'favorite_sync_base': _userV5BaseColumns},
        dropTables: _userV5Tables,
        version: 4,
      );
      final old = sqlite3.open(file.path)
        ..execute(
          'INSERT INTO favorite_lists (name, is_default, created_at, server_id) '
          "VALUES (NULL, 1, 1, 'L1')",
        )
        ..execute(
          'INSERT INTO favorite_items (list_id, place_id, kind, lat, lon, added_at) '
          "VALUES (1, 'p1', 'PARKING', 45, 6, 1)",
        )
        ..execute(
          'INSERT INTO favorite_sync_base (server_id, name, place_ids) '
          "VALUES ('L1', 'Mes favoris', '[\"p1\"]')",
        );
      expect(old.select("SELECT name FROM sqlite_master WHERE name = 'favorite_points'"), isEmpty);
      old.close();

      final upgraded = UserDatabase(NativeDatabase(file));
      final base = await upgraded.select(upgraded.favoriteSyncBase).getSingle();
      expect((base.placeIds, base.points, base.localOnlyPoints), ('["p1"]', '{}', '[]'));
      final repo = DriftFavoritesRepository(upgraded, clock: () => DateTime.utc(2026, 10, 10));
      final list = await repo.defaultListId();
      await repo.addPoint(
        list,
        SavedPoint(
          id: savedPointIdAt(const LatLng(45, 6)),
          kind: SavedPointKind.point,
          name: 'Point du 10 oct.',
          position: const LatLng(45, 6),
        ),
      );
      expect((await repo.watchLists().first).single.count, 2);
      await upgraded.close();
    },
  );
}
