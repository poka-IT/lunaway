import 'package:drift/drift.dart';
import 'package:lunaway/core/database/app_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// A list of saved places. The default list has no stored name: it shows in
/// the app language.
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

/// A saved place, with the snapshot taken when it was saved.
@immutable
final class FavoriteEntry {
  const new({
    required this.listId,
    required this.placeId,
    required this.kind,
    required this.position,
    required this.addedAt,
    this.name,
  });

  final int listId;
  final String placeId;
  final String? name;
  final PlaceKind kind;
  final LatLng position;
  final DateTime addedAt;

  @override
  bool operator ==(Object other) =>
      other is FavoriteEntry &&
      other.listId == listId &&
      other.placeId == placeId &&
      other.name == name &&
      other.kind == kind &&
      other.position == position &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(listId, placeId, name, kind, position, addedAt);
}

abstract interface class FavoritesRepository {
  /// Every list, the default one first; the default list exists from the
  /// first read on.
  Stream<List<FavoriteList>> watchLists();

  Stream<List<FavoriteEntry>> watchEntries(int listId);

  /// The ids of the lists holding [placeId].
  Stream<Set<int>> watchListsOf(String placeId);

  /// Saves [place] in the default list.
  Future<void> addToDefault(PlaceSummary place);

  Future<void> add(int listId, PlaceSummary place);

  Future<void> remove(int listId, String placeId);

  /// Removes [placeId] from every list.
  Future<void> removeEverywhere(String placeId);

  Future<int> createList(String name);

  Future<void> renameList(int listId, String name);

  /// The default list cannot be deleted.
  Future<void> deleteList(int listId);

  /// Puts back an entry removed by mistake (the undo of the snackbar).
  Future<void> restore(FavoriteEntry entry);
}

final class DriftFavoritesRepository implements FavoritesRepository {
  new(this._db, {this.clock = DateTime.now});

  final AppDatabase _db;
  final DateTime Function() clock;

  Future<int> _defaultListId() => _db.transaction(() async {
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
    await _defaultListId();
    yield* _db
        .customSelect(
          'SELECT l.id, l.name, l.is_default, COUNT(i.place_id) AS n FROM favorite_lists l '
          'LEFT JOIN favorite_items i ON i.list_id = l.id GROUP BY l.id '
          'ORDER BY l.is_default DESC, l.created_at, l.id',
          readsFrom: {_db.favoriteLists, _db.favoriteItems},
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
  Stream<Set<int>> watchListsOf(String placeId) =>
      (_db.select(_db.favoriteItems)..where((i) => i.placeId.equals(placeId))).watch().map(
        (rows) => {for (final r in rows) r.listId},
      );

  @override
  Future<void> addToDefault(PlaceSummary place) async => await add(await _defaultListId(), place);

  @override
  Future<void> add(int listId, PlaceSummary place) => _db
      .into(_db.favoriteItems)
      .insert(
        FavoriteItemsCompanion.insert(
          listId: listId,
          placeId: place.id,
          name: Value(place.name),
          kind: place.kind.wire,
          lat: place.lat,
          lon: place.lon,
          addedAt: clock().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );

  @override
  Future<void> remove(int listId, String placeId) => (_db.delete(
    _db.favoriteItems,
  )..where((i) => i.listId.equals(listId) & i.placeId.equals(placeId))).go();

  @override
  Future<void> removeEverywhere(String placeId) =>
      (_db.delete(_db.favoriteItems)..where((i) => i.placeId.equals(placeId))).go();

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
          lat: entry.position.lat,
          lon: entry.position.lon,
          addedAt: entry.addedAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );

  FavoriteEntry _entry(FavoriteItemRow r) => FavoriteEntry(
    listId: r.listId,
    placeId: r.placeId,
    name: r.name,
    kind: PlaceKind.fromWire(r.kind),
    position: LatLng(r.lat, r.lon),
    addedAt: DateTime.fromMillisecondsSinceEpoch(r.addedAt, isUtc: true),
  );
}
