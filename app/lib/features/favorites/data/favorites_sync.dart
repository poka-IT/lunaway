import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

final _log = Logger('favorites-sync');

/// A favourite list as the account holds it.
@immutable
final class RemoteList {
  const new({required this.id, required this.name, required this.placeIds, this.points});

  final String id;
  final String name;
  final Set<String> placeIds;

  /// Its saved points by id; null when the API predates them: the device's
  /// points then stay on the device until an API that knows them answers.
  final Map<String, SavedPoint>? points;
}

/// A list sent to the account at once: its name, its places, its points.
typedef ImportedList = ({String name, List<String> placeIds, List<SavedPoint> points});

/// The account's favourites on the server.
abstract interface class FavoritesRemote {
  Future<List<RemoteList>> lists();

  /// Merges each list into the account's list of the same name (made when
  /// missing) and returns every list. Unknown places are skipped; a point
  /// the account already holds in that list keeps the account's copy.
  Future<List<RemoteList>> import(List<ImportedList> lists);

  /// Saves the place in the list and returns the id the account keeps it
  /// under: [placeId], or the id of the place that absorbed it since (the
  /// server saves the live place). Null when the server does not know the
  /// place.
  Future<String?> add(String listId, String placeId);

  Future<void> remove(String listId, String placeId);

  /// Saves [point] in the list, or gives the account's copy its content.
  /// False when the server refuses it (its content, or the account holds
  /// as many points as it may).
  Future<bool> addPoint(String listId, SavedPoint point);

  Future<void> removePoint(String listId, String pointId);

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
/// - a place or a point added on one side and not removed on the other is
///   kept; removed on either side since the last sync, it goes;
/// - a point renamed (or its note changed) here since the last sync keeps
///   this side's name and note, else it takes the account's;
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

  /// What the server takes in one import: lists, places and points, and
  /// the bytes of the variables, kept well under its 64 KB body with the
  /// document around them.
  static const importLists = 100;
  static const importPlaces = 1000;
  static const importPoints = 500;
  static const int importBytes = 48 * 1024;

  /// The account the lists' links belong to, kept with them: a database
  /// restored from a backup, or a device that changed accounts, must not
  /// read another account's links as its own (it would delete the lists it
  /// does not find there).
  static const _boundSetting = 'favorites_account';

  /// Forgets every link to an account (signed out, deleted, another
  /// account): the lists stay on the device, unsynced.
  Future<void> unlink() => db.transaction(() async {
    await db.update(db.favoriteLists).write(const FavoriteListsCompanion(serverId: Value(null)));
    await db.delete(db.favoriteSyncBase).go();
    await (db.delete(db.settings)..where((r) => r.id.equals(_boundSetting))).go();
  });

  /// Syncs the lists with the account [accountId].
  Future<void> sync({required String accountId}) async {
    final bound = await (db.select(
      db.settings,
    )..where((r) => r.id.equals(_boundSetting))).getSingleOrNull();
    final linked = await (db.select(db.favoriteLists)..where((l) => l.serverId.isNotNull())).get();
    if (bound?.value != accountId && (bound != null || linked.isNotEmpty)) await unlink();
    await db
        .into(db.settings)
        .insertOnConflictUpdate(SettingsCompanion.insert(id: _boundSetting, value: accountId));
    await _sync();
  }

  Future<void> _sync() async {
    final remoteLists = {for (final r in await remote.lists()) r.id: r};
    final base = {for (final b in await db.select(db.favoriteSyncBase).get()) b.serverId: b};
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
            .where((r) => !taken.contains(r.id) && _sameName(r.name, name, list.isDefault))
            .firstOrNull;
        if (match != null) {
          taken.add(match.id);
          await _bind(list.id, match.id);
        } else {
          toImport.add((
            list: list,
            name: _unique(name, remoteLists.values, toImport.map((t) => t.name)),
          ));
        }
      }
      if (toImport.isNotEmpty) {
        final imported = await _importAll([
          for (final t in toImport)
            (
              name: t.name,
              placeIds: (await _itemIds(t.list.id)).toList(),
              points: (await _points(t.list.id)).values.toList(),
            ),
        ]);
        for (final t in toImport) {
          final r = imported.where((r) => r.name == t.name).firstOrNull;
          if (r == null) continue;
          remoteLists[r.id] = r;
          await _bind(t.list.id, r.id);
          // The import already holds this side's places and points: the
          // base is the list as imported, so nothing is pushed twice.
          await _writeBase(r.id, r.name, r.placeIds, const {}, points: _fingerprints(r.points));
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
      final localPoints = await _points(list.id);
      final baseIds = b == null ? <String>{} : _ids(b.placeIds);
      final localOnly = b == null ? <String>{} : _ids(b.localOnly);
      final basePoints = b == null ? <String, String>{} : _fingerprintsOf(b.points);
      final localOnlyPoints = b == null ? <String, String>{} : _fingerprintsOf(b.localOnlyPoints);
      if (r == null) {
        // Gone from the account: deleted on another device, unless this
        // device changed it since.
        final unchanged =
            b != null &&
            const SetEquality<String>().equals(localIds, baseIds) &&
            const MapEquality<String, String>().equals(
              _fingerprints(localPoints, without: localOnlyPoints.keys.toSet()),
              basePoints,
            ) &&
            (list.isDefault || list.name == b.name);
        if (unchanged && !list.isDefault) {
          await (db.delete(db.favoriteLists)..where((l) => l.id.equals(list.id))).go();
          await _dropBase(serverId);
          continue;
        }
        final name = _unique(_serverName(list), remoteLists.values, const []);
        final again = (await _importAll([
          (
            name: name,
            placeIds: localIds.difference(localOnly).toList(),
            points: [
              for (final p in localPoints.values)
                if (localOnlyPoints[p.id] != p.fingerprint) p,
            ],
          ),
        ])).where((x) => x.name == name).firstOrNull;
        await _dropBase(serverId);
        if (again == null) continue;
        remoteLists[again.id] = again;
        await _bind(list.id, again.id);
        await _writeBase(
          again.id,
          again.name,
          again.placeIds,
          localOnly,
          points: _fingerprints(again.points),
          localOnlyPoints: localOnlyPoints,
        );
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
      final absorbing = <String>{};
      for (final p in addedHere.difference(r.placeIds)) {
        final kept = await remote.add(serverId, p);
        if (kept == null) {
          refused.add(p);
        } else if (kept != p) {
          _takeAbsorbing(merged, p, kept);
          absorbing.add(kept);
        }
      }
      // A place this device held under the id of a place merged into it
      // (an import saves the live place) is no removal: it stays.
      for (final p in removedHere.intersection(r.placeIds).difference(absorbing)) {
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
          await (db.update(
            db.favoriteLists,
          )..where((l) => l.id.equals(list.id))).write(FavoriteListsCompanion(name: Value(r.name)));
        }
      }
      await _applyItems(list.id, localIds, merged);
      // The points, when the API knows them; else they wait, unsent.
      final remotePoints = r.points;
      final points = remotePoints == null
          ? null
          : await _mergePoints(
              list.id,
              serverId,
              local: localPoints,
              remote: remotePoints,
              base: basePoints,
              localOnly: localOnlyPoints,
            );
      await _writeBase(
        serverId,
        name,
        merged.difference(localOnly).difference(refused),
        {...localOnly.intersection(merged), ...refused},
        points: points?.base,
        localOnlyPoints: points?.localOnly,
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
            const SetEquality<String>().equals(r.placeIds, _ids(b.placeIds)) &&
            (r.points == null ||
                const MapEquality<String, String>().equals(
                  _fingerprints(r.points),
                  _fingerprintsOf(b.points),
                ));
        if (unchanged) {
          await remote.delete(r.id);
          await _dropBase(r.id);
          continue;
        }
      }
      final isDefault =
          defaultNames.contains(r.name) &&
          !(await db.select(db.favoriteLists).get()).any((l) => l.isDefault && l.serverId != null);
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
        final kept = await remote.add(r.id, p);
        if (kept != null && kept != p) _takeAbsorbing(merged, p, kept);
      }
      await _applyItems(listId, localIds, merged);
      final remotePoints = r.points;
      final points = remotePoints == null
          ? null
          : await _mergePoints(
              listId,
              r.id,
              local: await _points(listId),
              remote: remotePoints,
              base: const {},
              localOnly: const {},
            );
      await _writeBase(
        r.id,
        r.name,
        merged,
        const {},
        points: points?.base,
        localOnlyPoints: points?.localOnly,
      );
    }

    // A base nobody refers to any more.
    final keep = {for (final l in await db.select(db.favoriteLists).get()) ?l.serverId};
    await (db.delete(db.favoriteSyncBase)..where((b) => b.serverId.isNotIn(keep))).go();
  }

  /// The three-way merge of a list's saved points, as for its places, and
  /// each point's content: a point changed here since the last sync goes
  /// to the account as it is here; otherwise it takes the account's copy.
  /// A point the server refused ([localOnly], by the fingerprint it was
  /// refused with) stays here unsent until it changes here: then it is sent
  /// again. Returns the base the next sync starts from.
  Future<({Map<String, String> base, Map<String, String> localOnly})> _mergePoints(
    int listId,
    String serverId, {
    required Map<String, SavedPoint> local,
    required Map<String, SavedPoint> remote,
    required Map<String, String> base,
    required Map<String, String> localOnly,
  }) async {
    final localIds = local.keys.toSet();
    final remoteIds = remote.keys.toSet();
    final baseIds = base.keys.toSet();
    // A refused point taken out here is forgotten: saved again, it is new.
    final keptOnly = localOnly.keys.toSet().intersection(localIds);
    final addedHere = localIds.difference(baseIds).difference(keptOnly);
    final removedHere = baseIds.difference(localIds);
    final addedThere = remoteIds.difference(baseIds);
    final removedThere = baseIds.difference(remoteIds).difference(keptOnly);
    final merged = {...baseIds, ...addedHere, ...addedThere, ...keptOnly}
      ..removeAll(removedHere)
      ..removeAll(removedThere);
    final result = <String, SavedPoint>{};
    final refused = <String, String>{};
    Future<void> send(SavedPoint point) async {
      if (!await this.remote.addPoint(serverId, point)) refused[point.id] = point.fingerprint;
    }

    for (final id in merged) {
      final here = local[id];
      final there = remote[id];
      if (here != null && localOnly[id] == here.fingerprint) {
        // Refused as it is: the account's own copy when it has one now,
        // else kept here, unsent.
        if (there != null) {
          result[id] = there;
        } else {
          result[id] = here;
          refused[id] = here.fingerprint;
        }
      } else if (here != null && there == null) {
        // Added here, or changed here since it was refused.
        result[id] = here;
        await send(here);
      } else if (here != null && there != null) {
        final changedHere = base[id] != here.fingerprint;
        if (here.fingerprint == there.fingerprint || !changedHere) {
          result[id] = there;
        } else {
          result[id] = here;
          await send(here);
        }
      } else if (there != null) {
        result[id] = there;
      }
    }
    for (final id in removedHere.intersection(remoteIds)) {
      await this.remote.removePoint(serverId, id);
    }
    await _applyPoints(listId, local, result);
    return (
      base: {
        for (final MapEntry(:key, :value) in result.entries)
          if (!refused.containsKey(key)) key: value.fingerprint,
      },
      localOnly: refused,
    );
  }

  Future<List<RemoteList>> _importAll(List<ImportedList> lists) async {
    // The server takes so many lists, places and points a call, in a body
    // of 64 KB at most: a long list goes in parts, which it merges by name.
    var result = <RemoteList>[];
    final batch = <ImportedList>[];
    var places = 0;
    var points = 0;
    var bytes = 0;
    Future<void> flush() async {
      if (batch.isEmpty) return;
      result = await remote.import(List.of(batch));
      batch.clear();
      places = 0;
      points = 0;
      bytes = 0;
    }

    for (final list in lists) {
      var i = 0;
      var j = 0;
      do {
        final head = utf8.encode(list.name).length + 64;
        if (batch.length >= importLists || bytes + head > importBytes) await flush();
        bytes += head;
        final placeIds = <String>[];
        final savedPoints = <SavedPoint>[];
        // A place's id is 36 characters, quoted and separated.
        while (i < list.placeIds.length && places < importPlaces && bytes + 40 <= importBytes) {
          placeIds.add(list.placeIds[i++]);
          places++;
          bytes += 40;
        }
        while (j < list.points.length && points < importPoints) {
          final size = importSize(list.points[j]);
          if (bytes + size > importBytes) break;
          savedPoints.add(list.points[j++]);
          points++;
          bytes += size;
        }
        batch.add((name: list.name, placeIds: placeIds, points: savedPoints));
        // What is left of the list goes in the next call.
        if (i < list.placeIds.length || j < list.points.length) await flush();
      } while (i < list.placeIds.length || j < list.points.length);
    }
    await flush();
    return result;
  }

  /// The bytes [point] takes in an import's body, with its separator.
  static int importSize(SavedPoint point) =>
      utf8.encode(jsonEncode(GraphQLFavoritesRemote.pointInput(point))).length + 1;

  /// The place [sent], merged into [kept] since it was saved here, gives
  /// way to it in the list: the account saved the place that absorbed it,
  /// and the device keeping the id sent would see it missing from the
  /// account at the next sync and take it out of the list.
  static void _takeAbsorbing(Set<String> merged, String sent, String kept) => merged
    ..remove(sent)
    ..add(kept);

  Future<void> _applyItems(int listId, Set<String> before, Set<String> after) async {
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

  /// Writes the points of [listId] from [before] to [after]: a point that
  /// changed keeps its place in the list.
  Future<void> _applyPoints(
    int listId,
    Map<String, SavedPoint> before,
    Map<String, SavedPoint> after,
  ) async {
    for (final id in before.keys.where((id) => !after.containsKey(id))) {
      await (db.delete(
        db.favoritePoints,
      )..where((p) => p.listId.equals(listId) & p.id.equals(id))).go();
    }
    for (final MapEntry(key: id, value: point) in after.entries) {
      final was = before[id];
      if (was != null && was.fingerprint == point.fingerprint) continue;
      final row = await (db.select(
        db.favoritePoints,
      )..where((p) => p.listId.equals(listId) & p.id.equals(id))).getSingleOrNull();
      await db
          .into(db.favoritePoints)
          .insertOnConflictUpdate(
            pointRow(listId, point, row?.addedAt ?? clock().millisecondsSinceEpoch),
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
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
    return words.length <= maxName ? words : words.substring(0, maxName).trimRight();
  }

  static bool _sameName(String remoteName, String name, bool isDefault) =>
      isDefault ? defaultNames.contains(remoteName) || remoteName == name : remoteName == name;

  /// [name], or "name (2)" and so on when the account or this batch has it.
  static String _unique(String name, Iterable<RemoteList> remote, Iterable<String> batch) {
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

  Future<Map<String, SavedPoint>> _points(int listId) async => {
    for (final r in await (db.select(
      db.favoritePoints,
    )..where((p) => p.listId.equals(listId))).get())
      r.id: savedPointOf(r),
  };

  Future<void> _bind(int listId, String serverId) => (db.update(
    db.favoriteLists,
  )..where((l) => l.id.equals(listId))).write(FavoriteListsCompanion(serverId: Value(serverId)));

  /// The base of a list after a sync; the points' columns are left as they
  /// were when [points] is null (an API that does not know them).
  Future<void> _writeBase(
    String serverId,
    String name,
    Set<String> ids,
    Set<String> localOnly, {
    Map<String, String>? points,
    Map<String, String>? localOnlyPoints,
  }) => db
      .into(db.favoriteSyncBase)
      .insertOnConflictUpdate(
        FavoriteSyncBaseCompanion.insert(
          serverId: serverId,
          name: name,
          placeIds: jsonEncode(ids.toList()..sort()),
          localOnly: Value(jsonEncode(localOnly.toList()..sort())),
          points: points == null
              ? const Value.absent()
              : Value(jsonEncode(Map.fromEntries(points.entries.sortedBy((e) => e.key)))),
          localOnlyPoints: localOnlyPoints == null
              ? const Value.absent()
              : Value(jsonEncode(Map.fromEntries(localOnlyPoints.entries.sortedBy((e) => e.key)))),
        ),
      );

  Future<void> _dropBase(String serverId) =>
      (db.delete(db.favoriteSyncBase)..where((b) => b.serverId.equals(serverId))).go();

  static Set<String> _ids(String json) => {
    for (final id in jsonDecode(json) as List<dynamic>) id as String,
  };

  static Map<String, String> _fingerprintsOf(String json) => switch (jsonDecode(json)) {
    final Map<String, dynamic> map => {
      for (final MapEntry(:key, :value) in map.entries) key: value as String,
    },
    // A base a development build wrote before the refused points kept
    // their fingerprints: none refused.
    _ => const {},
  };

  /// The fingerprints of [points] by id, but those of [without]; empty for
  /// none (an API that does not know the points).
  static Map<String, String> _fingerprints(
    Map<String, SavedPoint>? points, {
    Set<String> without = const {},
  }) => {
    for (final MapEntry(:key, :value) in (points ?? const <String, SavedPoint>{}).entries)
      if (!without.contains(key)) key: value.fingerprint,
  };
}

/// The account's favourites through the API.
final class GraphQLFavoritesRemote implements FavoritesRemote {
  new(this.account);

  final AccountService account;

  static const _pointFields = 'id kind name note address lat lon poiId poiKind';

  static List<RemoteList> _lists(Object? json) => [
    for (final l in (json! as List<dynamic>).cast<Map<String, dynamic>>())
      RemoteList(
        id: l['id'] as String,
        name: l['name'] as String,
        placeIds: {
          for (final p in (l['places'] as List<dynamic>).cast<Map<String, dynamic>>())
            p['placeId'] as String,
        },
        points: switch (l['points']) {
          final List<dynamic> points => {
            for (final p in points.cast<Map<String, dynamic>>()) p['id'] as String: _point(p),
          },
          _ => null,
        },
      ),
  ];

  static SavedPoint _point(Map<String, dynamic> p) => SavedPoint(
    id: p['id'] as String,
    kind: SavedPointKind.fromWire(p['kind']),
    name: p['name'] as String,
    position: LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
    note: p['note'] as String?,
    address: p['address'] as String?,
    poiId: p['poiId'] as String?,
    poiKindCode: (p['poiKind'] as String?)?.toLowerCase(),
  );

  /// [point] as `FavoritePointInput`.
  static Map<String, Object?> pointInput(SavedPoint point) => {
    'id': point.id,
    'kind': point.kind.wire,
    'name': point.name,
    'note': ?point.note,
    'address': ?point.address,
    'lat': point.position.lat,
    'lon': point.position.lon,
    if (point.kind == SavedPointKind.poi) ...{
      'poiId': ?point.poiId,
      'poiKind': ?point.poiKindCode?.toUpperCase(),
    },
  };

  static final listsOperation = GraphQLOperation<List<RemoteList>>(
    name: 'MyFavoriteLists',
    document:
        'query MyFavoriteLists { myFavoriteLists { id name places { placeId } '
        'points { $_pointFields } } }',
    parse: (data) => _lists(data['myFavoriteLists']),
    // An API before the saved points: the lists without them.
    older: OlderForm.selecting(
      'query MyFavoriteLists { myFavoriteLists { id name places { placeId } } }',
    ),
  );

  static final importOperation = GraphQLOperation<List<RemoteList>>(
    name: 'ImportFavorites',
    document:
        '''
mutation ImportFavorites(\$lists: [FavoriteListInput!]!) {
  importFavorites(lists: \$lists) { id name places { placeId } points { $_pointFields } }
}''',
    parse: (data) => _lists(data['importFavorites']),
    // An API before the saved points: the lists without them, which stay on
    // the device until the API takes them.
    older: OlderForm(
      document: r'''
mutation ImportFavorites($lists: [FavoriteListInput!]!) {
  importFavorites(lists: $lists) { id name places { placeId } }
}''',
      variables: (v) => {
        'lists': [
          for (final l in (v['lists']! as List<Object?>).cast<Map<String, Object?>>())
            {
              for (final MapEntry(:key, :value) in l.entries)
                if (key != 'points') key: value,
            },
        ],
      },
      withoutFields: true,
    ),
  );

  /// The places of the list once saved: the id the place is kept under.
  static final saveOperation = GraphQLOperation<Set<String>>(
    name: 'SaveToList',
    document: r'''
mutation SaveToList($listId: UUID!, $placeId: UUID!) {
  saveToList(listId: $listId, placeId: $placeId) { id places { placeId } }
}''',
    parse: (data) => {
      for (final p
          in ((data['saveToList'] as Map<String, dynamic>)['places'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
        p['placeId'] as String,
    },
  );

  static final removeOperation = GraphQLOperation<bool>(
    name: 'RemoveFromList',
    document: r'''
mutation RemoveFromList($listId: UUID!, $placeId: UUID!) {
  removeFromList(listId: $listId, placeId: $placeId) { id }
}''',
    parse: (data) => true,
  );

  static final savePointOperation = GraphQLOperation<bool>(
    name: 'SavePointToList',
    document: r'''
mutation SavePointToList($listId: UUID!, $point: FavoritePointInput!) {
  savePointToList(listId: $listId, point: $point) { id }
}''',
    parse: (data) => true,
  );

  static final removePointOperation = GraphQLOperation<bool>(
    name: 'RemovePointFromList',
    document: r'''
mutation RemovePointFromList($listId: UUID!, $pointId: UUID!) {
  removePointFromList(listId: $listId, pointId: $pointId) { id }
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
            (address is Map<String, dynamic> ? address['city'] as String? : null) ??
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
    savePointOperation,
    removePointOperation,
    renameOperation,
    deleteOperation,
    placeOperation,
  ];

  @override
  // Never makes the account: the favourites follow one that exists (a
  // contribution or the user's "sync" made it first).
  Future<List<RemoteList>> lists() => account.run(listsOperation);

  @override
  Future<List<RemoteList>> import(List<ImportedList> lists) async {
    try {
      return await _import(lists, points: true);
    } on GraphQLResponseException catch (e) {
      final refused = e.errors.any(
        (x) => x.code == GraphQLError.invalidInput && !x.unknownField && !x.unknownInput,
      );
      if (!refused || lists.every((l) => l.points.isEmpty)) rethrow;
      // A point the server refuses, or an account that holds as many
      // points as it may: the lists and their places go without them, and
      // the sync sends the points one by one, each refused on its own.
      return await _import(lists, points: false);
    }
  }

  Future<List<RemoteList>> _import(List<ImportedList> lists, {required bool points}) => account.run(
    importOperation,
    variables: {
      'lists': [
        for (final l in lists)
          {
            'name': l.name,
            'placeIds': l.placeIds,
            // Left out when empty: an API before the saved points
            // refuses the field, and the older form costs a second
            // request.
            if (points && l.points.isNotEmpty) 'points': [for (final p in l.points) pointInput(p)],
          },
      ],
    },
  );

  @override
  Future<String?> add(String listId, String placeId) async {
    final Set<String> saved;
    try {
      saved = await account.run(saveOperation, variables: {'listId': listId, 'placeId': placeId});
    } on GraphQLResponseException catch (e) {
      // The place is gone from the data (the list is there: it was just
      // read).
      if (e.errors.any((x) => x.code == GraphQLError.notFound && x.message.contains('place'))) {
        return null;
      }
      rethrow;
    }
    if (saved.contains(placeId)) return placeId;
    // Merged into another place since: the server saved the place that
    // absorbed it, which the place query names (it follows the merges).
    final live = await place(placeId);
    return live != null && saved.contains(live.id) ? live.id : null;
  }

  @override
  Future<void> remove(String listId, String placeId) =>
      account.run(removeOperation, variables: {'listId': listId, 'placeId': placeId});

  @override
  Future<bool> addPoint(String listId, SavedPoint point) async {
    try {
      await account.run(
        savePointOperation,
        variables: {'listId': listId, 'point': pointInput(point)},
      );
      return true;
    } on GraphQLResponseException catch (e) {
      // Its content, or the account's room for points: sending it again
      // would be refused again. A document the API does not know is not a
      // refusal of the point.
      if (e.errors.any((x) => x.code == GraphQLError.invalidInput && !x.unknownField)) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<void> removePoint(String listId, String pointId) =>
      account.run(removePointOperation, variables: {'listId': listId, 'pointId': pointId});

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
  Future<PlaceSummary?> place(String id) => account.client.execute(placeOperation, {'id': id});
}
