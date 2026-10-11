import 'package:drift/drift.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';

/// The user's home on the device: one point at most, an address, a town, a
/// bare point of the map or a shop, as a saved point is, without a note.
/// It lives here first and goes with the account's favourites
/// (`HomeSync`), as private as they are.
abstract interface class HomeRepository {
  /// The home, and every change of it; null while there is none.
  Stream<SavedPoint?> watch();

  /// The home as it is now.
  Future<SavedPoint?> read();

  /// Makes [point] the home, in place of any other; its note is not kept.
  Future<void> set(SavedPoint point);

  /// Removes the home. The sync carries the removal to the account.
  Future<void> clear();

  /// Forgets the home and what the last sync agreed on, as if this device
  /// had never had one: another account replaced the one it belonged to,
  /// and the account brought in gives its own at the next sync.
  Future<void> clearLocal();
}

/// [point] as a home: its note left out, its id the one the point takes in
/// a list, so the card of a point or a shop knows it is the home.
SavedPoint asHome(SavedPoint point) => SavedPoint(
  id: point.poiId == null ? savedPointIdAt(point.position) : savedPoiPointId(point.poiId!),
  kind: point.kind,
  name: point.name,
  position: point.position,
  address: point.address,
  poiId: point.poiId,
  poiKindCode: point.poiKindCode,
);

final class DriftHomeRepository implements HomeRepository {
  new(this._db, {this.clock = DateTime.now});

  final UserDatabase _db;
  final DateTime Function() clock;

  /// The `settings` row holding the home as the last sync left it.
  static const baseSetting = 'home_sync_base';

  /// The `settings` row holding the home the server refused, as it was.
  static const refusedSetting = 'home_refused';

  @override
  Stream<SavedPoint?> watch() =>
      _db.select(_db.favoriteHome).watchSingleOrNull().map((r) => r == null ? null : homeOf(r));

  @override
  Future<SavedPoint?> read() async {
    final row = await _db.select(_db.favoriteHome).getSingleOrNull();
    return row == null ? null : homeOf(row);
  }

  @override
  Future<void> set(SavedPoint point) => _db
      .into(_db.favoriteHome)
      .insertOnConflictUpdate(homeRow(asHome(point), clock().millisecondsSinceEpoch));

  @override
  Future<void> clear() => _db.delete(_db.favoriteHome).go();

  @override
  Future<void> clearLocal() => _db.transaction(() async {
    await _db.delete(_db.favoriteHome).go();
    await (_db.delete(
      _db.settings,
    )..where((r) => r.id.isIn(const [baseSetting, refusedSetting]))).go();
  });
}

/// The home a row of `favorite_home` holds.
SavedPoint homeOf(FavoriteHomeRow r) => asHome(
  SavedPoint(
    id: '',
    kind: SavedPointKind.fromWire(r.kind),
    name: r.name,
    position: LatLng(r.lat, r.lon),
    address: r.address,
    poiId: r.poiId,
    poiKindCode: r.poiKind,
  ),
);

/// The row of [point] as the home, changed at [updatedAt] (milliseconds).
FavoriteHomeCompanion homeRow(SavedPoint point, int updatedAt) => FavoriteHomeCompanion.insert(
  id: const Value(1),
  kind: point.kind.wire,
  name: point.name,
  address: Value(point.address),
  lat: point.position.lat,
  lon: point.position.lon,
  poiId: Value(point.poiId),
  poiKind: Value(point.poiKindCode),
  updatedAt: updatedAt,
);
