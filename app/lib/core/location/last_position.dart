import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';

/// The last position the device reported, kept coarse (a tenth of a degree,
/// about 10 km) and only on the device: enough for the automatic theme to
/// know when the sun sets at the next launch, too coarse to say where the
/// user sleeps.
abstract interface class LastPositionStore {
  Future<LatLng?> load();

  Future<void> save(LatLng position);
}

/// [LastPositionStore] in the cache database, outside the device backups
/// (see [CacheDatabase.directory]).
final class DriftLastPositionStore implements LastPositionStore {
  new(this._db);

  final CacheDatabase _db;

  static const _key = 'last_position';

  @override
  Future<LatLng?> load() async {
    final row = await (_db.select(
      _db.deviceState,
    )..where((s) => s.id.equals(_key))).getSingleOrNull();
    final parts = row?.value.split(',');
    if (parts == null || parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    return lat == null || lon == null ? null : LatLng(lat, lon);
  }

  @override
  Future<void> save(LatLng position) {
    final coarse = coarsen(position);
    return _db
        .into(_db.deviceState)
        .insertOnConflictUpdate(
          DeviceStateCompanion.insert(
            id: _key,
            value: '${coarse.lat.toStringAsFixed(1)},${coarse.lon.toStringAsFixed(1)}',
          ),
        );
  }

  /// [position] rounded to a tenth of a degree.
  static LatLng coarsen(LatLng position) =>
      LatLng((position.lat * 10).roundToDouble() / 10, (position.lon * 10).roundToDouble() / 10);
}
