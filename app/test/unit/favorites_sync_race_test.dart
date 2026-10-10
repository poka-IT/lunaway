import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

PlaceSummary _place(String id) => PlaceSummary(
  id: id,
  name: 'Lieu $id',
  kind: PlaceKind.parking,
  lat: 45,
  lon: 6,
  overnight: OvernightStatus.allowed,
);

/// The account's lists behind a slow network: each call waits a random
/// while, so the device's changes land in the middle of a sync.
final class _SlowAccount implements FavoritesRemote {
  new(this.random);

  final Random random;
  final held = <String, ({String name, Set<String> places})>{};
  final log = <String>[];
  var _next = 0;

  Future<void> _wait() async {
    for (var i = random.nextInt(6); i > 0; i--) {
      await Future<void>.delayed(Duration(microseconds: random.nextInt(300)));
    }
  }

  List<RemoteList> _snapshot() => [
    for (final e in held.entries)
      RemoteList(id: e.key, name: e.value.name, placeIds: {...e.value.places}, points: const {}),
  ];

  @override
  Future<List<RemoteList>> lists() async {
    await _wait();
    return _snapshot();
  }

  @override
  Future<List<RemoteList>> import(List<ImportedList> imported) async {
    await _wait();
    for (final l in imported) {
      final existing = held.entries.where((e) => e.value.name == l.name).firstOrNull;
      final id = existing?.key ?? 'L${_next++}';
      held[id] = (name: l.name, places: {...?existing?.value.places, ...l.placeIds});
    }
    log.add('import ${[for (final l in imported) l.name]}');
    await _wait();
    return _snapshot();
  }

  @override
  Future<String?> add(String listId, String placeId) async {
    await _wait();
    held[listId]!.places.add(placeId);
    log.add('add $listId $placeId');
    await _wait();
    return placeId;
  }

  @override
  Future<void> remove(String listId, String placeId) async {
    await _wait();
    held[listId]!.places.remove(placeId);
    log.add('remove $listId $placeId');
    await _wait();
  }

  @override
  Future<bool> addPoint(String listId, SavedPoint point) async => true;

  @override
  Future<void> removePoint(String listId, String pointId) async {}

  @override
  Future<void> rename(String listId, String name) async {
    await _wait();
    held[listId] = (name: name, places: held[listId]!.places);
  }

  @override
  Future<void> delete(String listId) async {
    await _wait();
    held.remove(listId);
    log.add('delete $listId');
  }

  @override
  Future<PlaceSummary?> place(String id) async => _place(id);
}

/// The sequence of the second UX audit (94, M8): a place saved in Mes
/// favoris, a new account, then a new list holding the place too, with the
/// syncs of the account running at random moments of it. Mes favoris keeps
/// the place, on the device and on the account, whatever the order.
void main() {
  for (var seed = 0; seed < 20; seed++) {
    test(
      'a new list made while a sync runs leaves the place in Mes favoris (seed $seed)',
      () async {
        final random = Random(seed);
        final db = UserDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = DriftFavoritesRepository(db, clock: () => DateTime.utc(2026, 10, 6));
        final account = _SlowAccount(random);
        final sync = FavoritesSync(
          db: db,
          remote: account,
          lookup: (id) async => _place(id),
          defaultName: () => 'Mes favoris',
        );
        Future<void> pause() async {
          for (var i = random.nextInt(8); i > 0; i--) {
            await Future<void>.delayed(Duration(microseconds: random.nextInt(400)));
          }
        }

        final savedFirst = random.nextBool();
        if (savedFirst) await repo.addToDefault(_place('p1'));
        final first = sync.sync(accountId: 'a');
        await pause();
        if (!savedFirst) await repo.addToDefault(_place('p1'));
        await pause();
        final second = first.then((_) => sync.sync(accountId: 'a'));
        await pause();
        final trip = await repo.createList('Test audit 9');
        await pause();
        await repo.add(trip, _place('p1'));
        await second;
        await sync.sync(accountId: 'a');
        await sync.sync(accountId: 'a');
        final defaultId = await repo.defaultListId();
        expect(
          [for (final e in await repo.watchEntries(defaultId).first) e.placeId],
          ['p1'],
          reason: 'saved first: $savedFirst; ${account.log}',
        );
        expect(account.held.values.firstWhere((l) => l.name == 'Mes favoris').places, {'p1'});
      },
    );
  }
}
