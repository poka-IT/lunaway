import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// The app's local store (schema in `schema.drift`). Opened once per run; the
/// queries live in the repositories of each feature.
@DriftDatabase(include: {'schema.drift'})
final class AppDatabase extends _$AppDatabase {
  new(super.e);

  /// The on-device database. Demo data goes to its own file so it never mixes
  /// with synced places.
  factory open({required bool demo}) => AppDatabase(
    driftDatabase(
      name: demo ? 'lunaway_demo' : 'lunaway',
      // Application support, not documents: the user never browses this file.
      native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(places, places.stars);
        await m.addColumn(places, places.syncedAt);
        await m.createTable(fullSyncs);
        // Places already synced would never bring their classification: a
        // delta sync only sends what changed. Forgetting the cursors makes the
        // next sync a full one; favourites and settings stay.
        await delete(syncState).go();
      }
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
