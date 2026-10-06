import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
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

/// The account's lists, in memory, as the server keeps them.
final class _Account implements FavoritesRemote {
  final held = <String, ({String name, Set<String> places})>{};

  /// Places the server knows; any other is refused.
  final known = <String>{for (var i = 0; i < 20; i++) 'p$i'};
  var _next = 0;
  int calls = 0;

  @override
  Future<List<RemoteList>> lists() async => [
    for (final e in held.entries)
      RemoteList(id: e.key, name: e.value.name, placeIds: {...e.value.places}),
  ];

  @override
  Future<List<RemoteList>> import(List<({String name, List<String> placeIds})> imported) async {
    calls++;
    for (final l in imported) {
      final existing = held.entries.where((e) => e.value.name == l.name).firstOrNull;
      final id = existing?.key ?? 'L${_next++}';
      held[id] = (
        name: l.name,
        places: {...?existing?.value.places, ...l.placeIds.where(known.contains)},
      );
    }
    return await lists();
  }

  @override
  Future<bool> add(String listId, String placeId) async {
    calls++;
    if (!known.contains(placeId)) return false;
    held[listId]!.places.add(placeId);
    return true;
  }

  @override
  Future<void> remove(String listId, String placeId) async {
    calls++;
    held[listId]!.places.remove(placeId);
  }

  @override
  Future<void> rename(String listId, String name) async {
    calls++;
    held[listId] = (name: name, places: held[listId]!.places);
  }

  @override
  Future<void> delete(String listId) async {
    calls++;
    held.remove(listId);
  }

  @override
  Future<PlaceSummary?> place(String id) async => known.contains(id) ? _place(id) : null;

  String idOf(String name) => held.entries.firstWhere((e) => e.value.name == name).key;
}

void main() {
  late UserDatabase db;
  late DriftFavoritesRepository repo;
  late _Account account;
  late FavoritesSync sync;

  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    repo = DriftFavoritesRepository(db, clock: () => DateTime.utc(2026, 10, 6));
    account = _Account();
    sync = FavoritesSync(
      db: db,
      remote: account,
      lookup: (id) async => _place(id),
      defaultName: () => 'Mes favoris',
      clock: () => DateTime.utc(2026, 10, 6),
    );
  });
  tearDown(() => db.close());

  Future<Map<String, Set<String>>> localLists() async {
    final out = <String, Set<String>>{};
    for (final l in await repo.watchLists().first) {
      out[l.isDefault ? 'Mes favoris' : l.name!] = {
        for (final e in await repo.watchEntries(l.id).first) e.placeId,
      };
    }
    return out;
  }

  Map<String, Set<String>> accountLists() => {
    for (final l in account.held.values) l.name: {...l.places},
  };

  test("the first sync imports the device's lists into the account", () async {
    await repo.addToDefault(_place('p1'));
    final trip = await repo.createList('Bretagne 2027');
    await repo.add(trip, _place('p2'));
    await repo.add(trip, _place('p3'));
    await sync.sync(accountId: 'acc-a');
    expect(accountLists(), {
      'Mes favoris': {'p1'},
      'Bretagne 2027': {'p2', 'p3'},
    });
    // Nothing changed: a second sync sends nothing.
    final calls = account.calls;
    await sync.sync(accountId: 'acc-a');
    expect(account.calls, calls);
    expect(await localLists(), accountLists());
  });

  test('changes made on both sides while apart are all kept', () async {
    await repo.addToDefault(_place('p1'));
    await repo.addToDefault(_place('p2'));
    await sync.sync(accountId: 'acc-a');
    // This device, offline: adds p3, removes p1.
    await repo.addToDefault(_place('p3'));
    final defaultId = await repo.defaultListId();
    await repo.remove(defaultId, 'p1');
    // Another device: adds p4, removes p2.
    final id = account.idOf('Mes favoris');
    account.held[id]!.places
      ..add('p4')
      ..remove('p2');
    await sync.sync(accountId: 'acc-a');
    expect(accountLists()['Mes favoris'], {'p3', 'p4'});
    expect((await localLists())['Mes favoris'], {'p3', 'p4'});
  });

  test("a rename made here wins; otherwise the account's name comes down", () async {
    final listId = await repo.createList('Été');
    await repo.add(listId, _place('p1'));
    await sync.sync(accountId: 'acc-a');
    await repo.renameList(listId, 'Été 2027');
    await sync.sync(accountId: 'acc-a');
    expect(accountLists().keys, contains('Été 2027'));

    final id = account.idOf('Été 2027');
    account.held[id] = (name: 'Vacances', places: account.held[id]!.places);
    await sync.sync(accountId: 'acc-a');
    expect((await localLists()).keys, contains('Vacances'));
  });

  test('a list deleted elsewhere goes here, unless it changed here since', () async {
    final a = await repo.createList('A');
    await repo.add(a, _place('p1'));
    final b = await repo.createList('B');
    await repo.add(b, _place('p2'));
    await sync.sync(accountId: 'acc-a');
    account.held.remove(account.idOf('A'));
    account.held.remove(account.idOf('B'));
    await repo.add(b, _place('p3'));
    await sync.sync(accountId: 'acc-a');
    final local = await localLists();
    expect(local.containsKey('A'), isFalse);
    expect(local['B'], {'p2', 'p3'});
    expect(accountLists()['B'], {'p2', 'p3'}, reason: 'it comes back with the change');
  });

  test('a list deleted here goes from the account, unless it changed there since', () async {
    final a = await repo.createList('A');
    await repo.add(a, _place('p1'));
    final b = await repo.createList('B');
    await repo.add(b, _place('p2'));
    await sync.sync(accountId: 'acc-a');
    await repo.deleteList(a);
    await repo.deleteList(b);
    account.held[account.idOf('B')]!.places.add('p5');
    await sync.sync(accountId: 'acc-a');
    expect(accountLists().containsKey('A'), isFalse);
    expect(accountLists()['B'], {'p2', 'p5'});
    expect((await localLists())['B'], {'p2', 'p5'});
  });

  test('a list made on another device arrives with its places', () async {
    await sync.sync(accountId: 'acc-a');
    account.held['other'] = (name: 'Alpes', places: {'p7', 'p8'});
    await sync.sync(accountId: 'acc-a');
    expect((await localLists())['Alpes'], {'p7', 'p8'});
  });

  test("the device's default list merges into the account's, in either language", () async {
    account.held['other'] = (name: 'My favourites', places: {'p9'});
    await repo.addToDefault(_place('p1'));
    await sync.sync(accountId: 'acc-a');
    expect(accountLists(), {
      'My favourites': {'p1', 'p9'},
    });
    expect((await localLists())['Mes favoris'], {'p1', 'p9'});
  });

  test('a place the server no longer knows stays on the device and is not sent again', () async {
    await repo.addToDefault(_place('gone-1'));
    await repo.addToDefault(_place('p1'));
    await sync.sync(accountId: 'acc-a');
    expect(accountLists()['Mes favoris'], {'p1'});
    final calls = account.calls;
    await sync.sync(accountId: 'acc-a');
    expect(account.calls, calls);
    expect((await localLists())['Mes favoris'], {'gone-1', 'p1'});
  });

  test('unlinking keeps the lists on the device, ready for another account', () async {
    await repo.addToDefault(_place('p1'));
    await sync.sync(accountId: 'acc-a');
    await sync.unlink();
    expect((await localLists())['Mes favoris'], {'p1'});
    final other = _Account();
    await FavoritesSync(
      db: db,
      remote: other,
      lookup: (id) async => _place(id),
      defaultName: () => 'Mes favoris',
    ).sync(accountId: 'acc-b');
    expect(other.held.values.single.places, {'p1'});
  });

  test("lists linked to one account are never read as another account's", () async {
    // A database restored from a backup, or a device that changed account
    // without signing out here: the lists keep links to account A.
    await repo.addToDefault(_place('p1'));
    final summer = await repo.createList('Été');
    await repo.add(summer, _place('p2'));
    await sync.sync(accountId: 'acc-a');
    expect(account.held, hasLength(2));

    final other = _Account();
    await FavoritesSync(
      db: db,
      remote: other,
      lookup: (id) async => _place(id),
      defaultName: () => 'Mes favoris',
    ).sync(accountId: 'acc-b');
    // Without the binding, B's empty account would read as both lists
    // deleted elsewhere, and "Été" would go from the device.
    expect(await localLists(), {
      'Mes favoris': {'p1'},
      'Été': {'p2'},
    });
    expect(
      {for (final l in other.held.values) l.name: l.places},
      {
        'Mes favoris': {'p1'},
        'Été': {'p2'},
      },
    );
  });
}
