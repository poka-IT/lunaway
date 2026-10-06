import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'user_database.g.dart';

/// What the user made on this device (schema in `user_schema.drift`):
/// settings, favourites, the vehicle. A file of its own so the device
/// backups carry it and nothing else.
@DriftDatabase(include: {'user_schema.drift'})
final class UserDatabase extends _$UserDatabase {
  new(super.e);

  /// The on-device file; its name is the one the Android backup rules keep
  /// (`android/app/src/main/res/xml/`).
  factory open({required bool demo}) => UserDatabase(
    driftDatabase(
      name: demo ? 'lunaway_user_demo' : 'lunaway_user',
      native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );

  // Version 1 is the first shipped schema: earlier ones never left a
  // developer's device, so they get no migration. Version 2 adds the
  // account's favourites sync and the outbox of contributions, version 3
  // the vehicle's fuel.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(favoriteLists, favoriteLists.serverId);
        await m.createTable(favoriteSyncBase);
        await m.createTable(outbox);
        await m.createIndex(outboxOrder);
        await m.createTable(outboxFiles);
      }
      if (from < 3) {
        for (final column in [vehicles.fuel, vehicles.consumptionL100, vehicles.lpgHeating]) {
          await m.addColumn(vehicles, column);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
