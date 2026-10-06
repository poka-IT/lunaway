import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

final _log = Logger('favorites-sync');

/// A favourite list as the account holds it.
@immutable
final class RemoteList {
  const new({required this.id, required this.name, required this.placeIds});

  final String id;
  final String name;
  final Set<String> placeIds;
}

/// The account's favourites on the server.
abstract interface class FavoritesRemote {
  Future<List<RemoteList>> lists();

  /// Merges each list into the account's list of the same name (made when
  /// missing) and returns every list. Unknown places are skipped.
  Future<List<RemoteList>> import(
    List<({String name, List<String> placeIds})> lists,
  );

  /// False when the server does not know the place.
  Future<bool> add(String listId, String placeId);

  Future<void> remove(String listId, String placeId);

  Future<void> rename(String listId, String name);

  /// Deleting a list already gone is done.
  Future<void> delete(String listId);

  /// What a place saved on another device is, for its row here; null when
  /// the server no longer has it.
  Future<PlaceSummary?> place(String id);
}

/// What the device knows of a place, for the row of a favourite pulled
/// from the account: the synced places first.
typedef PlaceLookup = Future<PlaceSummary?> Function(String id);

/// Keeps the device's favourite lists and the account's in step, offline
/// first: the device's lists are what the screens show and change; a sync
/// merges both sides against the state the last sync left
/// (`favorite_sync_base`), so a change on either side, made while the other
/// was offline, survives:
///
/// - a place added on one side and not removed on the other is kept;
///   removed on either side since the last sync, it goes;
/// - a list renamed here wins over the account's name only if it was
///   renamed here since the last sync;
/// - a list deleted on one side goes, unless the other side changed it
///   since, in which case it comes back with those changes;
/// - the first sync of an account imports the device's lists into it,
///   merging lists of the same name.
final class FavoritesSync {
  new({
    required this.db,
    required this.remote,
    required this.lookup,
    required this.defaultName,
    this.clock = DateTime.now,
  });

  final UserDatabase db;
  final FavoritesRemote remote;
  final PlaceLookup lookup;

  /// The name the default list takes on the account (it has none on the
  /// device, where it follows the app's language).
  final String Function() defaultName;
  final DateTime Function() clock;

  /// The default list's names on an account: either language's.
  static const defaultNames = {'Mes favoris', 'My favourites'};

  /// The longest list name the server takes.
  static const maxName = 60;

  /// The account the lists' links belong to, kept with them: a database
  /// restored from a backup, or a device that changed accounts, must not
  /// read another account's links as its own (it would delete the lists it
  /// does not find there).
  static const _boundSetting = 'favorites_account';

  /// Forgets every link to an account (signed out, deleted, another
  /// account): the lists stay on the device, unsynced.
  Future<void> unlink() => db.transaction(() async {
    await db
        .update(db.favoriteLists)
        .write(const FavoriteListsCompanion(serverId: Value(null)));
    await db.delete(db.favoriteSyncBase).go();
    await (db.delete(
      db.settings,
    )..where((r) => r.id.equals(_boundSetting))).go();
  });

  /// Syncs the lists with the account [accountId].
  Future<void> sync({required String accountId}) async {
    final bound = await (db.select(
      db.settings,
    )..where((r) => r.id.equals(_boundSetting))).getSingleOrNull();
    final linked = await (db.select(
      db.favoriteLists,
    )..where((l) => l.serverId.isNotNull())).get();
    if (bound?.value != accountId && (bound != null || linked.isNotEmpty))
      await unlink();
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(id: _boundSetting, value: accountId),
        );
    await _sync();
  }

  Future<void> _sync() async {
    final remoteLists = {for (final r in await remote.lists()) r.id: r};
    final base = {
      for (final b in await db.select(db.favoriteSyncBase).get()) b.serverId: b,
    };
    final local = await db.select(db.favoriteLists).get();
    final bound = <String>{};

    // Lists the account has not seen: bound to a list of the same name, or
    // imported as new lists.
    final unbound = local.where((l) => l.serverId == null).toList();
    if (unbound.isNotEmpty) {
      final taken = {for (final l in local) ?l.serverId};
      final toImport = <({FavoriteListRow list, String name})>[];
      for (final list in unbound) {
        final name = _serverName(list);
        final match = remoteLists.values
            .where(
              (r) =>
                  !taken.contains(r.id) &&
                  _sameName(r.name, name, list.isDefault),
            )
            .firstOrNull;
        if (match != null) {
          taken.add(match.id);
          await _bind(list.id, match.id);
        } else {
          toImport.add((
            list: list,
            name: _unique(
              name,
              remoteLists.values,
              toImport.map((t) => t.name),
            ),
          ));
        }
      }
      if (toImport.isNotEmpty) {
        final imported = await _importAll([
          for (final t in toImport)
            (name: t.name, placeIds: (await _itemIds(t.list.id)).toList()),
        ]);
        for (final t in toImport) {
          final r = imported.where((r) => r.name == t.name).firstOrNull;
          if (r == null) continue;
          remoteLists[r.id] = r;
          await _bind(t.list.id, r.id);
          // The import already holds this side's places: the base is the
          // list as imported, so nothing is pushed twice.
          await _writeBase(r.id, r.name, r.placeIds, const {});
          base[r.id] = await (db.select(
            db.favoriteSyncBase,
          )..where((b) => b.serverId.equals(r.id))).getSingle();
        }
      }
    }

    for (final list in await db.select(db.favoriteLists).get()) {
      final serverId = list.serverId;
      if (serverId == null) continue;
      bound.add(serverId);
      final r = remoteLists[serverId];
      final b = base[serverId];
      final localIds = await _itemIds(list.id);
      final baseIds = b == null ? <String>{} : _ids(b.placeIds);
      final localOnly = b == null ? <String>{} : _ids(b.localOnly);
      if (r == null) {
        // Gone from the account: deleted on another device, unless this
        // device changed it since.
        final unchanged =
            b != null &&
            const SetEquality<String>().equals(localIds, baseIds) &&
            (list.isDefault || list.name == b.name);
        if (unchanged && !list.isDefault) {
          await (db.delete(
            db.favoriteLists,
          )..where((l) => l.id.equals(list.id))).go();
          await _dropBase(serverId);
          continue;
        }
        final name = _unique(_serverName(list), remoteLists.values, const []);
        final again = (await _importAll([
          (name: name, placeIds: localIds.difference(localOnly).toList()),
        ])).where((x) => x.name == name).firstOrNull;
        await _dropBase(serverId);
        if (again == null) continue;
        remoteLists[again.id] = again;
        await _bind(list.id, again.id);
        await _writeBase(again.id, again.name, again.placeIds, localOnly);
        bound.add(again.id);
        continue;
      }
      // Three-way merge of the places.
      final addedHere = localIds.difference(baseIds).difference(localOnly);
      final removedHere = baseIds.difference(localIds);
      final addedThere = r.placeIds.difference(baseIds);
      final removedThere = baseIds.difference(r.placeIds).difference(localOnly);
      final merged = {...baseIds, ...addedHere, ...addedThere, ...localOnly}
        ..removeAll(removedHere)
        ..removeAll(removedThere);
      final refused = <String>{};
      for (final p in addedHere.difference(r.placeIds)) {
        if (!await remote.add(serverId, p)) refused.add(p);
      }
      for (final p in removedHere.intersection(r.placeIds)) {
        await remote.remove(serverId, p);
      }
      // Names: a rename here since the last sync wins, else the account's.
      var name = r.name;
      if (!list.isDefault) {
        final renamedHere = b == null || list.name != b.name;
        final mine = _clip(list.name ?? '');
        if (renamedHere && mine.isNotEmpty && mine != r.name) {
          await remote.rename(serverId, mine);
          name = mine;
        } else if (list.name != r.name) {
          await (db.update(db.favoriteLists)
                ..where((l) => l.id.equals(list.id)))
              .write(FavoriteListsCompanion(name: Value(r.name)));
        }
      }
      await _applyItems(list.id, localIds, merged);
      await _writeBase(
        serverId,
        name,
        merged.difference(localOnly).difference(refused),
        {...localOnly.intersection(merged), ...refused},
      );
    }

    // Lists of the account this device has no list for.
    for (final r in remoteLists.values.where((r) => !bound.contains(r.id))) {
      final b = base[r.id];
      if (b != null) {
        // Deleted on this device since the last sync: deleted on the
        // account too, unless another device changed it since.
        final unchanged =
            r.name == b.name &&
            const SetEquality<String>().equals(r.placeIds, _ids(b.placeIds));
        if (unchanged) {
          await remote.delete(r.id);
          await _dropBase(r.id);
          continue;
        }
      }
      final isDefault =
          defaultNames.contains(r.name) &&
          !(await db.select(db.favoriteLists).get()).any(
            (l) => l.isDefault && l.serverId != null,
          );
      final int listId;
      if (isDefault) {
        listId = await _defaultListId();
      } else {
        listId = await db
            .into(db.favoriteLists)
            .insert(
              FavoriteListsCompanion.insert(
                name: Value(r.name),
                createdAt: clock().millisecondsSinceEpoch,
              ),
            );
      }
      await _bind(listId, r.id);
      final localIds = await _itemIds(listId);
      final merged = {...localIds, ...r.placeIds};
      for (final p in localIds.difference(r.placeIds)) {
        await remote.add(r.id, p);
      }
      await _applyItems(listId, localIds, merged);
      await _writeBase(r.id, r.name, merged, const {});
    }

    // A base nobody refers to any more.
    final keep = {
      for (final l in await db.select(db.favoriteLists).get()) ?l.serverId,
    };
    await (db.delete(
      db.favoriteSyncBase,
    )..where((b) => b.serverId.isNotIn(keep))).go();
  }

  Future<List<RemoteList>> _importAll(
    List<({String name, List<String> placeIds})> lists,
  ) async {
    // The server takes 100 lists and 1000 places a call.
    var result = <RemoteList>[];
    final batch = <({String name, List<String> placeIds})>[];
    var places = 0;
    Future<void> flush() async {
      if (batch.isEmpty) return;
      result = await remote.import(List.of(batch));
      batch.clear();
      places = 0;
    }

    for (final list in lists) {
      for (var i = 0; i < list.placeIds.length || i == 0; i += 1000) {
        final chunk = list.placeIds.skip(i).take(1000).toList();
        if (batch.length >= 100 || places + chunk.length > 1000) await flush();
        batch.add((name: list.name, placeIds: chunk));
        places += chunk.length;
        if (list.placeIds.isEmpty) break;
      }
    }
    await flush();
    return result;
  }

  Future<void> _applyItems(
    int listId,
    Set<String> before,
    Set<String> after,
  ) async {
    for (final p in before.difference(after)) {
      await (db.delete(
        db.favoriteItems,
      )..where((i) => i.listId.equals(listId) & i.placeId.equals(p))).go();
    }
    for (final p in after.difference(before)) {
      final place = await lookup(p) ?? await _remotePlace(p);
      if (place == null) continue;
      await db
          .into(db.favoriteItems)
          .insert(
            FavoriteItemsCompanion.insert(
              listId: listId,
              placeId: p,
              name: Value(place.name),
              kind: place.kind.wire,
              overnight: Value(place.overnight.wire),
              city: Value(place.city),
              lat: place.lat,
              lon: place.lon,
              addedAt: clock().millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<PlaceSummary?> _remotePlace(String id) async {
    try {
      return await remote.place(id);
    } on Object catch (e) {
      _log.info('no details for the saved place $id: $e');
      return null;
    }
  }

  Future<int> _defaultListId() async {
    final existing = await (db.select(
      db.favoriteLists,
    )..where((l) => l.isDefault.equals(true))).getSingleOrNull();
    if (existing != null) return existing.id;
    return await db
        .into(db.favoriteLists)
        .insert(
          FavoriteListsCompanion.insert(
            isDefault: const Value(true),
            createdAt: clock().millisecondsSinceEpoch,
          ),
        );
  }

  String _serverName(FavoriteListRow list) =>
      _clip(list.isDefault ? defaultName() : (list.name ?? defaultName()));

  static String _clip(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ');
    return words.length <= maxName
        ? words
        : words.substring(0, maxName).trimRight();
  }

  static bool _sameName(String remoteName, String name, bool isDefault) =>
      isDefault
      ? defaultNames.contains(remoteName) || remoteName == name
      : remoteName == name;

  /// [name], or "name (2)" and so on when the account or this batch has it.
  static String _unique(
    String name,
    Iterable<RemoteList> remote,
    Iterable<String> batch,
  ) {
    final used = {...remote.map((r) => r.name), ...batch};
    if (!used.contains(name)) return name;
    for (var n = 2; ; n++) {
      final suffix = ' ($n)';
      final candidate =
          '${name.length + suffix.length > maxName ? name.substring(0, maxName - suffix.length) : name}$suffix';
      if (!used.contains(candidate)) return candidate;
    }
  }

  Future<Set<String>> _itemIds(int listId) async => {
    for (final i in await (db.select(
      db.favoriteItems,
    )..where((i) => i.listId.equals(listId))).get())
      i.placeId,
  };

  Future<void> _bind(int listId, String serverId) =>
      (db.update(db.favoriteLists)..where((l) => l.id.equals(listId))).write(
        FavoriteListsCompanion(serverId: Value(serverId)),
      );

  Future<void> _writeBase(
    String serverId,
    String name,
    Set<String> ids,
    Set<String> localOnly,
  ) => db
      .into(db.favoriteSyncBase)
      .insertOnConflictUpdate(
        FavoriteSyncBaseCompanion.insert(
          serverId: serverId,
          name: name,
          placeIds: jsonEncode(ids.toList()..sort()),
          localOnly: Value(jsonEncode(localOnly.toList()..sort())),
        ),
      );

  Future<void> _dropBase(String serverId) => (db.delete(
    db.favoriteSyncBase,
  )..where((b) => b.serverId.equals(serverId))).go();

  static Set<String> _ids(String json) => {
    for (final id in jsonDecode(json) as List<dynamic>) id as String,
  };
}

/// The account's favourites through the API.
final class GraphQLFavoritesRemote implements FavoritesRemote {
  new(this.account);

  final AccountService account;

  static List<RemoteList> _lists(Object? json) => [
    for (final l in (json! as List<dynamic>).cast<Map<String, dynamic>>())
      RemoteList(
        id: l['id'] as String,
        name: l['name'] as String,
        placeIds: {
          for (final p
              in (l['places'] as List<dynamic>).cast<Map<String, dynamic>>())
            p['placeId'] as String,
        },
      ),
  ];

  static final listsOperation = GraphQLOperation<List<RemoteList>>(
    name: 'MyFavoriteLists',
    document: 'query MyFavoriteLists { myFavoriteLists { id name places { placeId } } }',
    parse: (data) => _lists(data['myFavoriteLists']),
  );

  static final importOperation = GraphQLOperation<List<RemoteList>>(
    name: 'ImportFavorites',
    document: r'''
mutation ImportFavorites($lists: [FavoriteListInput!]!) {
  importFavorites(lists: $lists) { id name places { placeId } }
}''',
    parse: (data) => _lists(data['importFavorites']),
  );

  static final saveOperation = GraphQLOperation<bool>(
    name: 'SaveToList',
    document: r'''
mutation SaveToList($listId: UUID!, $placeId: UUID!) {
  saveToList(listId: $listId, placeId: $placeId) { id }
}''',
    parse: (data) => true,
  );

  static final removeOperation = GraphQLOperation<bool>(
    name: 'RemoveFromList',
    document: r'''
mutation RemoveFromList($listId: UUID!, $placeId: UUID!) {
  removeFromList(listId: $listId, placeId: $placeId) { id }
}''',
    parse: (data) => true,
  );

  static final renameOperation = GraphQLOperation<bool>(
    name: 'RenameList',
    document: r'mutation RenameList($id: UUID!, $name: String!) { renameList(id: $id, name: $name) { id } }',
    parse: (data) => true,
  );

  static final deleteOperation = GraphQLOperation<bool>(
    name: 'DeleteList',
    document: r'mutation DeleteList($id: UUID!) { deleteList(id: $id) }',
    parse: (data) => data['deleteList'] == true,
  );

  static final placeOperation = GraphQLOperation<PlaceSummary?>(
    name: 'FavoritePlace',
    document: r'''
query FavoritePlace($id: UUID!) {
  place(id: $id) { id name kind lat lon overnight address { city } municipality }
}''',
    parse: (data) {
      final p = data['place'];
      if (p is! Map<String, dynamic>) return null;
      final address = p['address'];
      return PlaceSummary(
        id: p['id'] as String,
        name: p['name'] as String?,
        city:
            (address is Map<String, dynamic>
                ? address['city'] as String?
                : null) ??
            p['municipality'] as String?,
        kind: PlaceKind.fromWire(p['kind'] as String),
        lat: (p['lat'] as num).toDouble(),
        lon: (p['lon'] as num).toDouble(),
        overnight: OvernightStatus.fromWire(p['overnight'] as String),
      );
    },
  );

  static final operations = <GraphQLOperation<Object?>>[
    listsOperation,
    importOperation,
    saveOperation,
    removeOperation,
    renameOperation,
    deleteOperation,
    placeOperation,
  ];

  @override
  // Never makes the account: the favourites follow one that exists (a
  // contribution or the user's "sync" made it first).
  Future<List<RemoteList>> lists() => account.run(listsOperation);

  @override
  Future<List<RemoteList>> import(
    List<({String name, List<String> placeIds})> lists,
  ) => account.run(
    importOperation,
    variables: {
      'lists': [
        for (final l in lists) {'name': l.name, 'placeIds': l.placeIds},
      ],
    },
  );

  @override
  Future<bool> add(String listId, String placeId) async {
    try {
      await account.run(
        saveOperation,
        variables: {'listId': listId, 'placeId': placeId},
      );
      return true;
    } on GraphQLResponseException catch (e) {
      // The place is gone from the data (the list is there: it was just
      // read).
      if (e.errors.any(
        (x) => x.code == GraphQLError.notFound && x.message.contains('place'),
      )) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<void> remove(String listId, String placeId) => account.run(
    removeOperation,
    variables: {'listId': listId, 'placeId': placeId},
  );

  @override
  Future<void> rename(String listId, String name) =>
      account.run(renameOperation, variables: {'id': listId, 'name': name});

  @override
  Future<void> delete(String listId) async {
    try {
      await account.run(deleteOperation, variables: {'id': listId});
    } on GraphQLResponseException catch (e) {
      if (!e.hasCode(GraphQLError.notFound)) rethrow;
    }
  }

  @override
  Future<PlaceSummary?> place(String id) =>
      account.client.execute(placeOperation, {'id': id});
}
