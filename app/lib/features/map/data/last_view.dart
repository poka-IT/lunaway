import 'dart:math' as math;

import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/coverage.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/last_position.dart';

/// Where the map was left: its centre and zoom.
typedef SavedView = ({LatLng center, double zoom});

/// The view the map was left on, so the next launch opens there rather than
/// on the whole of France. Kept on the device only, its centre rounded to a
/// tenth of a degree (about 10 km) as the last position is
/// ([DriftLastPositionStore.coarsen]): the map often rests on the user, and
/// a finer copy would say where the van spent the night.
abstract interface class LastViewStore {
  Future<SavedView?> load();

  Future<void> save(LatLng center, double zoom);
}

/// [LastViewStore] in the cache database, outside the device backups (see
/// [CacheDatabase.directory]).
final class DriftLastViewStore implements LastViewStore {
  new(this._db);

  final CacheDatabase _db;

  static const _key = 'last_view';

  /// The closest a restored view opens.
  static const maxZoom = 10.0;

  @override
  Future<SavedView?> load() async {
    final row = await (_db.select(
      _db.deviceState,
    )..where((s) => s.id.equals(_key))).getSingleOrNull();
    final parts = row?.value.split(',');
    if (parts == null || parts.length != 3) return null;
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    final zoom = double.tryParse(parts[2]);
    if (lat == null || lon == null || zoom == null) return null;
    if (lat.abs() > 90 || lon.abs() > 180 || zoom < 0 || zoom > 22) return null;
    // A centre out of the area the places cover (a web page on a phone
    // once kept its view out at sea) opens on the first view instead.
    if (!inPlaceCoverage(LatLng(lat, lon))) return null;
    // A centre known to 10 km reopens no closer than the area it stands
    // for: at street zoom it would land on streets never looked at.
    return (center: LatLng(lat, lon), zoom: math.min(zoom, maxZoom));
  }

  @override
  Future<void> save(LatLng center, double zoom) {
    final coarse = DriftLastPositionStore.coarsen(center);
    return _db
        .into(_db.deviceState)
        .insertOnConflictUpdate(
          DeviceStateCompanion.insert(
            id: _key,
            value:
                '${coarse.lat.toStringAsFixed(1)},${coarse.lon.toStringAsFixed(1)},'
                '${zoom.toStringAsFixed(1)}',
          ),
        );
  }
}
