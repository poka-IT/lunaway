import 'package:drift/drift.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// A list of saved places and points. The default list has no stored name:
/// it shows in the app language. [count] counts both.
@immutable
final class FavoriteList {
  const new({required this.id, required this.name, required this.isDefault, required this.count});

  final int id;
  final String? name;
  final bool isDefault;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is FavoriteList &&
      other.id == id &&
      other.name == name &&
      other.isDefault == isDefault &&
      other.count == count;

  @override
  int get hashCode => Object.hash(id, name, isDefault, count);
}

/// Something a list holds: a place of the data, or a point saved outside
/// them.
@immutable
sealed class Favorite {
  const new();

  int get listId;

  /// The place's id or the point's: one entry per id and list.
  String get key;
  LatLng get position;
  DateTime get addedAt;
}

/// A saved place, with the snapshot taken when it was saved.
final class FavoriteEntry extends Favorite {
  const new({
    required this.listId,
    required this.placeId,
    required this.kind,
    required this.position,
    required this.addedAt,
    this.name,
    this.overnight = OvernightStatus.unknown,
    this.city,
    this.street,
  });

  @override
  final int listId;
  final String placeId;
  final String? name;
  final PlaceKind kind;
  final OvernightStatus overnight;
  final String? city;

  /// The street of its address, which titles a place without a name; null
  /// for a favourite saved before the app kept it, until the copy of the
  /// place on the device gives it (`FavoritesRepository.fillStreets`).
  final String? street;
  @override
  final LatLng position;
  @override
  final DateTime addedAt;

  @override
  String get key => placeId;

  /// The place as the rows and the lists' sheet show it.
  PlaceSummary get summary => PlaceSummary(
    id: placeId,
    name: name,
    city: city,
    street: street,
    kind: kind,
    lat: position.lat,
    lon: position.lon,
    overnight: overnight,
  );

  @override
  bool operator ==(Object other) =>
      other is FavoriteEntry &&
      other.listId == listId &&
      other.placeId == placeId &&
      other.name == name &&
      other.kind == kind &&
      other.overnight == overnight &&
      other.city == city &&
      other.street == street &&
      other.position == position &&
      other.addedAt == addedAt;

  @override
  int get hashCode =>
      Object.hash(listId, placeId, name, kind, overnight, city, street, position, addedAt);
}

/// A saved point in one list.
final class FavoritePointEntry extends Favorite {
  const new({required this.listId, required this.point, required this.addedAt});

  @override
  final int listId;
  final SavedPoint point;
  @override
  final DateTime addedAt;

  @override
  String get key => point.id;

  @override
  LatLng get position => point.position;

  @override
  bool operator ==(Object other) =>
      other is FavoritePointEntry &&
      other.listId == listId &&
      other.point == point &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(listId, point, addedAt);
}

abstract interface class FavoritesRepository {
  /// Every list, the default one first; the default list exists from the
  /// first read on.
  Stream<List<FavoriteList>> watchLists();

  /// The places of a list, newest first.
  Stream<List<FavoriteEntry>> watchEntries(int listId);

  /// The places and the saved points of a list, newest first.
  Stream<List<Favorite>> watchFavorites(int listId);

  /// The saved points of a list, newest first.
  Stream<List<FavoritePointEntry>> watchPoints(int listId);

  /// The ids of the lists holding [id], a place's or a saved point's.
  Stream<Set<int>> watchListsOf(String id);

  /// The point saved as [id], as the lists hold it (the same in each); null
  /// when no list holds it.
  Stream<SavedPoint?> watchPoint(String id);

  /// The id of the default list, created on first use.
  Future<int> defaultListId();

  /// Saves [place] in the default list.
  Future<void> addToDefault(PlaceSummary place);

  Future<void> add(int listId, PlaceSummary place);

  /// Removes [placeId] from [listId] and returns what was removed, for an
  /// undo; null when it was not there.
  Future<FavoriteEntry?> remove(int listId, String placeId);

  Future<int> createList(String name);

  Future<void> renameList(int listId, String name);

  /// The default list cannot be deleted.
  Future<void> deleteList(int listId);

  /// Puts back an entry removed by mistake (the undo of the snackbar).
  Future<void> restore(FavoriteEntry entry);

  /// Saves [point] in [listId], or gives the copy already there the
  /// content of [point].
  Future<void> addPoint(int listId, SavedPoint point);

  /// Saves [point] in the default list.
  Future<void> addPointToDefault(SavedPoint point);

  /// Removes the point [id] from [listId] and returns what was removed, for
  /// an undo; null when it was not there.
  Future<FavoritePointEntry?> removePoint(int listId, String id);

  /// Removes the point [id] from every list and returns what was removed,
  /// for an undo.
  Future<List<FavoritePointEntry>> removePointEverywhere(String id);

  /// Gives every list's copy of [point] its name and note.
  Future<void> updatePoint(SavedPoint point);

  /// Puts back points removed by mistake (the undo of the snackbar); a
  /// list deleted meanwhile stays deleted.
  Future<void> restorePoints(List<FavoritePointEntry> entries);

  /// Gives the saved places without a name and without a street (saved
  /// before the app kept it) the street [lookup] finds for them, so they
  /// are titled by it; returns how many places got one. A place [lookup]
  /// fails on keeps its town until a later call, the others get their
  /// street, then the first failure is thrown.
  Future<int> fillStreets(Future<PlaceSummary?> Function(String placeId) lookup);
}

final class DriftFavoritesRepository implements FavoritesRepository {
  new(this._db, {this.clock = DateTime.now});

  final UserDatabase _db;
  final DateTime Function() clock;

  @override
  Future<int> defaultListId() => _db.transaction(() async {
    final existing = await (_db.select(
      _db.favoriteLists,
    )..where((l) => l.isDefault.equals(true))).getSingleOrNull();
    if (existing != null) return existing.id;
    return await _db
        .into(_db.favoriteLists)
        .insert(
          FavoriteListsCompanion.insert(
            isDefault: const Value(true),
            createdAt: clock().millisecondsSinceEpoch,
          ),
        );
  });

  @override
  Stream<List<FavoriteList>> watchLists() async* {
    await defaultListId();
    yield* _db
        .customSelect(
          'SELECT l.id, l.name, l.is_default, '
          '(SELECT COUNT(*) FROM favorite_items i WHERE i.list_id = l.id) + '
          '(SELECT COUNT(*) FROM favorite_points p WHERE p.list_id = l.id) AS n '
          'FROM favorite_lists l ORDER BY l.is_default DESC, l.created_at, l.id',
          readsFrom: {_db.favoriteLists, _db.favoriteItems, _db.favoritePoints},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              FavoriteList(
                id: r.read<int>('id'),
                name: r.readNullable<String>('name'),
                isDefault: r.read<bool>('is_default'),
                count: r.read<int>('n'),
              ),
          ],
        );
  }

  @override
  Stream<List<FavoriteEntry>> watchEntries(int listId) =>
      (_db.select(_db.favoriteItems)
            ..where((i) => i.listId.equals(listId))
            ..orderBy([(i) => OrderingTerm.desc(i.addedAt)]))
          .watch()
          .map((rows) => rows.map(_entry).toList());

  @override
  Stream<List<Favorite>> watchFavorites(int listId) => _db
      .customSelect(
        // One query over both tables, so a change to either gives one new
        // list, never a list with half of it.
        "SELECT 'place' AS t, place_id AS id, name, kind, overnight, city, NULL AS note, "
        'NULL AS address, lat, lon, NULL AS poi_id, NULL AS poi_kind, added_at, street '
        'FROM favorite_items WHERE list_id = ?1 '
        "UNION ALL SELECT 'point', id, name, kind, NULL, NULL, note, address, lat, lon, "
        'poi_id, poi_kind, added_at, NULL FROM favorite_points WHERE list_id = ?1 '
        'ORDER BY added_at DESC, id',
        variables: [Variable.withInt(listId)],
        readsFrom: {_db.favoriteItems, _db.favoritePoints},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            if (r.read<String>('t') == 'place')
              FavoriteEntry(
                listId: listId,
                placeId: r.read<String>('id'),
                name: r.readNullable<String>('name'),
                kind: PlaceKind.fromWire(r.read<String>('kind')),
                overnight: OvernightStatus.fromWire(r.read<String>('overnight')),
                city: r.readNullable<String>('city'),
                street: r.readNullable<String>('street'),
                position: LatLng(r.read<double>('lat'), r.read<double>('lon')),
                addedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('added_at'), isUtc: true),
              )
            else
              FavoritePointEntry(
                listId: listId,
                point: SavedPoint(
                  id: r.read<String>('id'),
                  kind: SavedPointKind.fromWire(r.read<String>('kind')),
                  name: r.read<String>('name'),
                  position: LatLng(r.read<double>('lat'), r.read<double>('lon')),
                  note: r.readNullable<String>('note'),
                  address: r.readNullable<String>('address'),
                  poiId: r.readNullable<String>('poi_id'),
                  poiKindCode: r.readNullable<String>('poi_kind'),
                ),
                addedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('added_at'), isUtc: true),
              ),
        ],
      );

  @override
  Stream<List<FavoritePointEntry>> watchPoints(int listId) =>
      (_db.select(_db.favoritePoints)
            ..where((p) => p.listId.equals(listId))
            ..orderBy([(p) => OrderingTerm.desc(p.addedAt)]))
          .watch()
          .map((rows) => rows.map(_pointEntry).toList());

  @override
  Stream<Set<int>> watchListsOf(String id) => _db
      .customSelect(
        'SELECT list_id FROM favorite_items WHERE place_id = ?1 '
        'UNION SELECT list_id FROM favorite_points WHERE id = ?1',
        variables: [Variable.withString(id)],
        readsFrom: {_db.favoriteItems, _db.favoritePoints},
      )
      .watch()
      .map((rows) => {for (final r in rows) r.read<int>('list_id')});

  @override
  Stream<SavedPoint?> watchPoint(String id) =>
      (_db.select(_db.favoritePoints)
            ..where((p) => p.id.equals(id))
            ..orderBy([(p) => OrderingTerm.desc(p.addedAt), (p) => OrderingTerm.asc(p.listId)])
            ..limit(1))
          .watchSingleOrNull()
          .map((r) => r == null ? null : savedPointOf(r));

  @override
  Future<void> addToDefault(PlaceSummary place) async => await add(await defaultListId(), place);

  @override
  Future<void> add(int listId, PlaceSummary place) => _db
      .into(_db.favoriteItems)
      .insert(
        FavoriteItemsCompanion.insert(
          listId: listId,
          placeId: place.id,
          name: Value(place.name),
          kind: place.kind.wire,
          overnight: Value(place.overnight.wire),
          city: Value(place.city),
          street: Value(place.street),
          lat: place.lat,
          lon: place.lon,
          addedAt: clock().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );

  @override
  Future<FavoriteEntry?> remove(int listId, String placeId) => _db.transaction(() async {
    final query = _db.select(_db.favoriteItems)
      ..where((i) => i.listId.equals(listId) & i.placeId.equals(placeId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    await (_db.delete(
      _db.favoriteItems,
    )..where((i) => i.listId.equals(listId) & i.placeId.equals(placeId))).go();
    return _entry(row);
  });

  @override
  Future<int> createList(String name) => _db
      .into(_db.favoriteLists)
      .insert(
        FavoriteListsCompanion.insert(
          name: Value(name.trim()),
          createdAt: clock().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> renameList(int listId, String name) => (_db.update(
    _db.favoriteLists,
  )..where((l) => l.id.equals(listId))).write(FavoriteListsCompanion(name: Value(name.trim())));

  @override
  Future<void> deleteList(int listId) => (_db.delete(
    _db.favoriteLists,
  )..where((l) => l.id.equals(listId) & l.isDefault.equals(false))).go();

  @override
  Future<void> restore(FavoriteEntry entry) => _db
      .into(_db.favoriteItems)
      .insert(
        FavoriteItemsCompanion.insert(
          listId: entry.listId,
          placeId: entry.placeId,
          name: Value(entry.name),
          kind: entry.kind.wire,
          overnight: Value(entry.overnight.wire),
          city: Value(entry.city),
          street: Value(entry.street),
          lat: entry.position.lat,
          lon: entry.position.lon,
          addedAt: entry.addedAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );

  @override
  Future<void> addPoint(int listId, SavedPoint point) => _db.transaction(() async {
    // A point saved again keeps its place in the list.
    final existing = await (_db.select(
      _db.favoritePoints,
    )..where((p) => p.listId.equals(listId) & p.id.equals(point.id))).getSingleOrNull();
    await _db
        .into(_db.favoritePoints)
        .insertOnConflictUpdate(
          pointRow(listId, point, existing?.addedAt ?? clock().millisecondsSinceEpoch),
        );
  });

  @override
  Future<void> addPointToDefault(SavedPoint point) async =>
      await addPoint(await defaultListId(), point);

  @override
  Future<FavoritePointEntry?> removePoint(int listId, String id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.favoritePoints,
    )..where((p) => p.listId.equals(listId) & p.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (_db.delete(
      _db.favoritePoints,
    )..where((p) => p.listId.equals(listId) & p.id.equals(id))).go();
    return _pointEntry(row);
  });

  @override
  Future<List<FavoritePointEntry>> removePointEverywhere(String id) => _db.transaction(() async {
    final rows = await (_db.select(_db.favoritePoints)..where((p) => p.id.equals(id))).get();
    await (_db.delete(_db.favoritePoints)..where((p) => p.id.equals(id))).go();
    return rows.map(_pointEntry).toList();
  });

  @override
  Future<void> updatePoint(SavedPoint point) =>
      (_db.update(_db.favoritePoints)..where((p) => p.id.equals(point.id))).write(
        FavoritePointsCompanion(name: Value(point.name), note: Value(point.note)),
      );

  @override
  Future<void> restorePoints(List<FavoritePointEntry> entries) => _db.transaction(() async {
    for (final e in entries) {
      final list = await (_db.select(
        _db.favoriteLists,
      )..where((l) => l.id.equals(e.listId))).getSingleOrNull();
      if (list == null) continue;
      await _db
          .into(_db.favoritePoints)
          .insertOnConflictUpdate(pointRow(e.listId, e.point, e.addedAt.millisecondsSinceEpoch));
    }
  });

  @override
  Future<int> fillStreets(Future<PlaceSummary?> Function(String placeId) lookup) async {
    final ids = await _db
        .customSelect(
          'SELECT DISTINCT place_id FROM favorite_items WHERE name IS NULL AND street IS NULL',
          readsFrom: {_db.favoriteItems},
        )
        .map((r) => r.read<String>('place_id'))
        .get();
    final streets = <String, String>{};
    (Object, StackTrace)? failed;
    for (final id in ids) {
      try {
        final street = (await lookup(id))?.street;
        if (street != null && street.isNotEmpty) streets[id] = street;
      } on Object catch (e, st) {
        failed ??= (e, st);
      }
    }
    await _db.transaction(() async {
      for (final MapEntry(key: id, value: street) in streets.entries) {
        await (_db.update(_db.favoriteItems)
              ..where((i) => i.placeId.equals(id) & i.name.isNull() & i.street.isNull()))
            .write(FavoriteItemsCompanion(street: Value(street)));
      }
    });
    if (failed case (final e, final st)) Error.throwWithStackTrace(e, st);
    return streets.length;
  }

  FavoriteEntry _entry(FavoriteItemRow r) => FavoriteEntry(
    listId: r.listId,
    placeId: r.placeId,
    name: r.name,
    kind: PlaceKind.fromWire(r.kind),
    overnight: OvernightStatus.fromWire(r.overnight),
    city: r.city,
    street: r.street,
    position: LatLng(r.lat, r.lon),
    addedAt: DateTime.fromMillisecondsSinceEpoch(r.addedAt, isUtc: true),
  );

  FavoritePointEntry _pointEntry(FavoritePointRow r) => FavoritePointEntry(
    listId: r.listId,
    point: savedPointOf(r),
    addedAt: DateTime.fromMillisecondsSinceEpoch(r.addedAt, isUtc: true),
  );
}

/// The point a row of `favorite_points` holds.
SavedPoint savedPointOf(FavoritePointRow r) => SavedPoint(
  id: r.id,
  kind: SavedPointKind.fromWire(r.kind),
  name: r.name,
  position: LatLng(r.lat, r.lon),
  note: r.note,
  address: r.address,
  poiId: r.poiId,
  poiKindCode: r.poiKind,
);

/// The row of [point] in [listId], added at [addedAt] (milliseconds).
FavoritePointsCompanion pointRow(int listId, SavedPoint point, int addedAt) =>
    FavoritePointsCompanion.insert(
      listId: listId,
      id: point.id,
      kind: point.kind.wire,
      name: point.name,
      note: Value(point.note),
      address: Value(point.address),
      lat: point.position.lat,
      lon: point.position.lon,
      poiId: Value(point.poiId),
      poiKind: Value(point.poiKindCode),
      addedAt: addedAt,
    );
