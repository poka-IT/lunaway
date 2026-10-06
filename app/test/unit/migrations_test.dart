import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/places/data/drift_places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:sqlite3/sqlite3.dart';

/// The schema of version 1 as it shipped, taken from version 2 minus what
/// version 2 added: every table, index, virtual table and trigger, with
/// [dropColumns] taken out of their CREATE TABLE and [dropTables] left out.
Future<void> _writeVersion1(
  QueryExecutor current,
  File file, {
  required Map<String, List<String>> dropColumns,
  required Set<String> dropTables,
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
    ..execute('PRAGMA user_version = 1')
    ..close();
  await db.close();
}

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
    await _writeVersion1(
      fresh.executor,
      file,
      dropColumns: {
        'favorite_lists': ['server_id'],
      },
      dropTables: {'favorite_sync_base', 'outbox', 'outbox_files'},
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
    await _writeVersion1(
      fresh.executor,
      file,
      dropColumns: {
        'places': [
          'verification',
          'review_count',
          'photo_count',
          'cover_photos_json',
          'issues_json',
        ],
      },
      dropTables: const {},
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
    expect(state.generation, 4);
    expect(state.completedAt, isNotNull, reason: 'the date of the last sync stays for the screens');
    await upgraded.close();
  });
}
