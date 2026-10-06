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
  // developer's device, so they get no migration.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
