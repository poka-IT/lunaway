import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

part 'cache_database.g.dart';

/// The place cache (schema in `cache_schema.drift`): everything the device
/// downloaded and can download again. Opened once per run; the queries live
/// in the repositories of each feature.
@DriftDatabase(include: {'cache_schema.drift'})
final class CacheDatabase extends _$CacheDatabase {
  new(super.e);

  /// The on-device file. Demo data goes to its own file so it never mixes
  /// with synced places. The name is the one the Android backup rules
  /// leave out (`android/app/src/main/res/xml/`).
  factory open({required bool demo}) => CacheDatabase(
    driftDatabase(
      name: demo ? 'lunaway_demo' : 'lunaway',
      native: const DriftNativeOptions(databaseDirectory: directory),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );

  /// Where the file lives, out of the device backups. On iOS and macOS the
  /// caches directory, which iCloud, the computer backups and Time Machine
  /// skip (the system may empty it when space runs out: the next sync
  /// downloads the places again). Elsewhere application support, the user
  /// never browsing it; Android's backup rules leave the file out by name.
  static Future<Directory> directory() => keptInCaches(defaultTargetPlatform)
      ? getApplicationCacheDirectory()
      : getApplicationSupportDirectory();

  /// Whether [platform] keeps the cache in its caches directory.
  @visibleForTesting
  static bool keptInCaches(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  // Version 1 is the first shipped schema: earlier ones never left a
  // developer's device, so they get no migration. Version 2 keeps what the
  // community says of each place, version 3 the points of interest read
  // around them.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        for (final column in [
          places.verification,
          places.reviewCount,
          places.photoCount,
          places.coverPhotosJson,
          places.issuesJson,
        ]) {
          await m.addColumn(places, column);
        }
        // The places on the device lack the new columns: a full sync of
        // each region starts at the next launch, the places staying on the
        // map until it sweeps, and the date of the last sync kept for the
        // screens.
        await customStatement(
          'UPDATE region_syncs SET cursor = NULL, running = 1, full_sync = 1, '
          'generation = generation + 1',
        );
      }
      if (from < 3) await m.createTable(poiCache);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Bytes used by the database file, for the offline data panel.
  Future<int> sizeInBytes() async {
    final row = await customSelect(
      'SELECT page_count * page_size AS size FROM pragma_page_count(), pragma_page_size()',
    ).getSingle();
    return row.read<int>('size');
  }
}
