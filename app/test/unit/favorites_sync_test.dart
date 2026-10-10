import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// A bare point saved at [lat], with [name] and [note].
SavedPoint _saved(double lat, {String name = 'Point', String? note}) =>
    SavedPoint(
      id: savedPointIdAt(LatLng(lat, 6)),
      kind: SavedPointKind.point,
      name: name,
      position: LatLng(lat, 6),
      note: note,
    );

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

  /// The saved points of each list, by list id then point id.
  final points = <String, Map<String, SavedPoint>>{};

  /// Places the server knows; any other is refused.
  final known = <String>{for (var i = 0; i < 20; i++) 'p$i'};

  /// Points whose content the server refuses.
  final refusedPoints = <String>{};

  /// An API before the saved points: it neither sends nor takes them.
  bool knowsPoints = true;

  /// The size of each import's variables, as the app sends them.
  final importBytes = <int>[];
  var _next = 0;
  int calls = 0;

  @override
  Future<List<RemoteList>> lists() async => [
    for (final e in held.entries)
      RemoteList(
        id: e.key,
        name: e.value.name,
        placeIds: {...e.value.places},
        points: knowsPoints ? {...?points[e.key]} : null,
      ),
  ];

  @override
  Future<List<RemoteList>> import(List<ImportedList> imported) async {
    calls++;
    importBytes.add(
      utf8
          .encode(
            jsonEncode([
              for (final l in imported)
                {
                  'name': l.name,
                  'placeIds': l.placeIds,
                  'points': [
                    for (final p in l.points)
                      GraphQLFavoritesRemote.pointInput(p),
                  ],
                },
            ]),
          )
          .length,
    );
    for (final l in imported) {
      final existing = held.entries
          .where((e) => e.value.name == l.name)
          .firstOrNull;
      final id = existing?.key ?? 'L${_next++}';
      held[id] = (
        name: l.name,
        places: {
          ...?existing?.value.places,
          ...l.placeIds.where(known.contains),
        },
      );
      if (knowsPoints) {
        final kept = points.putIfAbsent(id, () => {});
        for (final p in l.points) {
          // The account's copy stays, as the server's ON CONFLICT DO NOTHING.
          if (!refusedPoints.contains(p.id)) kept.putIfAbsent(p.id, () => p);
        }
      }
    }
    return await lists();
  }

  @override
  Future<bool> addPoint(String listId, SavedPoint point) async {
    calls++;
    if (!knowsPoints) throw StateError('an API before the saved points');
    if (refusedPoints.contains(point.id)) return false;
    points.putIfAbsent(listId, () => {})[point.id] = point;
    return true;
  }

  @override
  Future<void> removePoint(String listId, String pointId) async {
    calls++;
    if (!knowsPoints) throw StateError('an API before the saved points');
    points[listId]?.remove(pointId);
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
    points.remove(listId);
  }

  @override
  Future<PlaceSummary?> place(String id) async =>
      known.contains(id) ? _place(id) : null;

  String idOf(String name) =>
      held.entries.firstWhere((e) => e.value.name == name).key;
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

  test(
    "a rename made here wins; otherwise the account's name comes down",
    () async {
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
    },
  );

  test(
    'a list deleted elsewhere goes here, unless it changed here since',
    () async {
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
      expect(accountLists()['B'], {
        'p2',
        'p3',
      }, reason: 'it comes back with the change');
    },
  );

  test(
    'a list deleted here goes from the account, unless it changed there since',
    () async {
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
    },
  );

  test('a list made on another device arrives with its places', () async {
    await sync.sync(accountId: 'acc-a');
    account.held['other'] = (name: 'Alpes', places: {'p7', 'p8'});
    await sync.sync(accountId: 'acc-a');
    expect((await localLists())['Alpes'], {'p7', 'p8'});
  });

  test(
    "the device's default list merges into the account's, in either language",
    () async {
      account.held['other'] = (name: 'My favourites', places: {'p9'});
      await repo.addToDefault(_place('p1'));
      await sync.sync(accountId: 'acc-a');
      expect(accountLists(), {
        'My favourites': {'p1', 'p9'},
      });
      expect((await localLists())['Mes favoris'], {'p1', 'p9'});
    },
  );

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

  test(
    'unlinking keeps the lists on the device, ready for another account',
    () async {
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
    },
  );

  test(
    "lists linked to one account are never read as another account's",
    () async {
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
    },
  );

  group('saved points', () {
    /// The device's points by list name, each as name and note.
    Future<Map<String, Map<String, (String, String?)>>> localPoints() async => {
      for (final l in await repo.watchLists().first)
        l.isDefault ? 'Mes favoris' : l.name!: {
          for (final e in await repo.watchPoints(l.id).first)
            e.point.id: (e.point.name, e.point.note),
        },
    };

    Map<String, Map<String, (String, String?)>> accountPoints() => {
      for (final MapEntry(:key, :value) in account.held.entries)
        value.name: {
          for (final p
              in (account.points[key] ?? const <String, SavedPoint>{}).values)
            p.id: (p.name, p.note),
        },
    };

    test('a point saved here reaches the account with its name and note, at the first sync', () async {
      await repo.addPointToDefault(
        _saved(45, name: 'Chez Paul', note: 'Portail vert'),
      );
      await repo.addToDefault(_place('p1'));
      await sync.sync(accountId: 'acc-a');
      expect(accountPoints()['Mes favoris'], {
        _saved(45).id: ('Chez Paul', 'Portail vert'),
      });
      expect(accountLists()['Mes favoris'], {
        'p1',
      }, reason: 'the places go with them');
      final calls = account.calls;
      await sync.sync(accountId: 'acc-a');
      expect(account.calls, calls, reason: 'nothing changed: nothing sent');
    });

    test('a point saved on another device arrives here, and one saved here goes there', () async {
      await repo.defaultListId();
      await sync.sync(accountId: 'acc-a');
      final id = account.idOf('Mes favoris');
      account.points[id] = {_saved(46).id: _saved(46, name: 'Lac')};
      await repo.addPointToDefault(_saved(47, name: 'Col'));
      await sync.sync(accountId: 'acc-a');
      final both = {_saved(46).id: ('Lac', null), _saved(47).id: ('Col', null)};
      expect((await localPoints())['Mes favoris'], both);
      expect(accountPoints()['Mes favoris'], both);
    });

    test('a rename made here wins; made only there, it comes down', () async {
      await repo.addPointToDefault(_saved(45, name: 'Chez Paul'));
      await repo.addPointToDefault(_saved(46, name: 'Lac'));
      await sync.sync(accountId: 'acc-a');
      final id = account.idOf('Mes favoris');
      // Here: the first renamed. There: both, the second with a note.
      await repo.updatePoint(_saved(45).renamed('Chez Paul et Lise', null));
      account.points[id]![_saved(45).id] = _saved(45, name: 'Paul');
      account.points[id]![_saved(46).id] = _saved(
        46,
        name: 'Lac bleu',
        note: 'Baignade',
      );
      await sync.sync(accountId: 'acc-a');
      final merged = {
        _saved(45).id: ('Chez Paul et Lise', null),
        _saved(46).id: ('Lac bleu', 'Baignade'),
      };
      expect((await localPoints())['Mes favoris'], merged);
      expect(accountPoints()['Mes favoris'], merged);
    });

    test('a point removed on either side goes from both', () async {
      await repo.addPointToDefault(_saved(45));
      await repo.addPointToDefault(_saved(46));
      await sync.sync(accountId: 'acc-a');
      await repo.removePoint(await repo.defaultListId(), _saved(45).id);
      account.points[account.idOf('Mes favoris')]!.remove(_saved(46).id);
      await sync.sync(accountId: 'acc-a');
      expect((await localPoints())['Mes favoris'], isEmpty);
      expect(accountPoints()['Mes favoris'], isEmpty);
    });

    test(
      'a list deleted elsewhere comes back with a point saved in it here since',
      () async {
        final trip = await repo.createList('Bretagne');
        await repo.addPoint(trip, _saved(48, name: 'Plage'));
        await sync.sync(accountId: 'acc-a');
        account.held.remove(account.idOf('Bretagne'));
        await repo.addPoint(trip, _saved(49, name: 'Phare'));
        await sync.sync(accountId: 'acc-a');
        final both = {
          _saved(48).id: ('Plage', null),
          _saved(49).id: ('Phare', null),
        };
        expect((await localPoints())['Bretagne'], both);
        expect(accountPoints()['Bretagne'], both);
      },
    );

    test('a list holding only an unchanged point, deleted elsewhere, goes here too', () async {
      final trip = await repo.createList('Bretagne');
      await repo.addPoint(trip, _saved(48, name: 'Plage'));
      await sync.sync(accountId: 'acc-a');
      final id = account.idOf('Bretagne');
      account.held.remove(id);
      account.points.remove(id);
      await sync.sync(accountId: 'acc-a');
      expect((await localPoints()).containsKey('Bretagne'), isFalse);
    });

    test(
      'a point the server refuses stays here and is not sent again',
      () async {
        await repo.addPointToDefault(_saved(45, name: 'Refusé'));
        await sync.sync(accountId: 'acc-a');
        account.refusedPoints.add(_saved(46).id);
        await repo.addPointToDefault(_saved(46, name: 'Refusé aussi'));
        await sync.sync(accountId: 'acc-a');
        expect(accountPoints()['Mes favoris']!.keys, [_saved(45).id]);
        final calls = account.calls;
        await sync.sync(accountId: 'acc-a');
        expect(
          account.calls,
          calls,
          reason: 'the refused point is not sent again',
        );
        expect((await localPoints())['Mes favoris'], hasLength(2));
      },
    );

    test('a refused point is sent again once changed here', () async {
      account.refusedPoints.add(_saved(45).id);
      await repo.addPointToDefault(_saved(45, name: 'Trop'));
      await sync.sync(accountId: 'acc-a');
      expect(accountPoints()['Mes favoris'], isEmpty);
      // The account has room again; the point, unchanged, waits.
      account.refusedPoints.clear();
      final calls = account.calls;
      await sync.sync(accountId: 'acc-a');
      expect(account.calls, calls, reason: 'refused as it is: not sent again');
      await repo.updatePoint(_saved(45).renamed('Renommé', null));
      await sync.sync(accountId: 'acc-a');
      expect(accountPoints()['Mes favoris'], {
        _saved(45).id: ('Renommé', null),
      });
    });

    test(
      'a refused point taken out and saved again later reaches the account',
      () async {
        account.refusedPoints.add(_saved(45).id);
        await repo.addPointToDefault(_saved(45, name: 'Trop'));
        await sync.sync(accountId: 'acc-a');
        await repo.removePoint(await repo.defaultListId(), _saved(45).id);
        await sync.sync(accountId: 'acc-a');
        account.refusedPoints.clear();
        await repo.addPointToDefault(_saved(45, name: 'Trop'));
        await sync.sync(accountId: 'acc-a');
        expect(accountPoints()['Mes favoris'], {_saved(45).id: ('Trop', null)});
      },
    );

    test(
      'with an API before the points they stay here, and go once it knows them',
      () async {
        account.knowsPoints = false;
        await repo.addPointToDefault(_saved(45, name: 'Chez Paul'));
        await repo.addToDefault(_place('p1'));
        await sync.sync(accountId: 'acc-a');
        expect(accountLists()['Mes favoris'], {'p1'});
        expect(accountPoints()['Mes favoris'], isEmpty);
        await sync.sync(accountId: 'acc-a');
        expect((await localPoints())['Mes favoris'], {
          _saved(45).id: ('Chez Paul', null),
        });

        account.knowsPoints = true;
        await sync.sync(accountId: 'acc-a');
        expect(accountPoints()['Mes favoris'], {
          _saved(45).id: ('Chez Paul', null),
        });
      },
    );

    test("many long points go to the account in calls under the server's body limit", () async {
      final trip = await repo.createList('Tour de France');
      final note = 'Une note assez longue pour peser. ' * 8;
      for (var i = 0; i < 300; i++) {
        await repo.addPoint(
          trip,
          _saved(40 + i / 1000, name: 'Étape $i ${'é' * 80}', note: note),
        );
      }
      await sync.sync(accountId: 'acc-a');
      expect(accountPoints()['Tour de France'], hasLength(300));
      expect(
        account.importBytes.length,
        greaterThan(1),
        reason: 'more than one call',
      );
      expect(
        account.importBytes.every((b) => b < 60 * 1024),
        isTrue,
        reason:
            'each body under 64 KB with its document: ${account.importBytes}',
      );
    });
  });
}
