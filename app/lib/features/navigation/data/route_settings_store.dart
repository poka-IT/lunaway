import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';

/// Where the route settings live between runs.
abstract interface class RouteSettingsStore {
  Future<NavigationSettings> load();

  Future<void> save(NavigationSettings settings);
}

/// One row of the user database's key-value `settings` table: no schema
/// change, and the device backups carry it with the other settings.
final class DriftRouteSettingsStore implements RouteSettingsStore {
  new(this._db);

  final UserDatabase _db;

  static const _key = 'route_settings';

  @override
  Future<NavigationSettings> load() async {
    final row = await (_db.select(_db.settings)..where((s) => s.id.equals(_key))).getSingleOrNull();
    return NavigationSettings.decode(row?.value);
  }

  @override
  Future<void> save(NavigationSettings settings) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(id: _key, value: settings.encode()));
}
