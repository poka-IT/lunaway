import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/favorites/data/home_repository.dart';
import 'package:lunaway/features/favorites/data/home_sync.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';

import '../helpers/fake_api.dart';
import '../helpers/samples.dart';

SavedPoint _home(double lat, {String name = 'Maison'}) => SavedPoint(
  id: savedPointIdAt(LatLng(lat, 6)),
  kind: SavedPointKind.address,
  name: name,
  position: LatLng(lat, 6),
  address: '1 rue des Lilas, 74000 Annecy',
);

/// The account's home, in memory, as the server keeps it.
final class _Account implements HomeRemote {
  SavedPoint? held;

  /// An API before the home.
  bool knowsHome = true;

  /// The server refuses the content of a home.
  bool refuses = false;
  int sets = 0;
  int clears = 0;

  @override
  Future<SavedPoint?> home() async {
    if (!knowsHome) throw const HomeUnsupported();
    return held;
  }

  @override
  Future<SavedPoint?> set(SavedPoint point) async {
    sets++;
    if (refuses) return null;
    return held = asHome(point);
  }

  @override
  Future<void> clear() async {
    clears++;
    held = null;
  }
}

void main() {
  late UserDatabase db;
  late DriftHomeRepository repo;
  late _Account account;
  late HomeSync sync;

  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    repo = DriftHomeRepository(db, clock: () => DateTime.utc(2026, 10, 11));
    account = _Account();
    sync = HomeSync(db: db, home: repo, remote: account);
  });
  tearDown(() => db.close());

  test('a home set on the device goes to an account without one at its first sync', () async {
    await repo.set(_home(45.9));
    await sync.sync();
    expect(account.held, asHome(_home(45.9)));
    // Nothing changed since: nothing is sent again.
    await sync.sync();
    expect(account.sets, 1);
  });

  test("at an account's first sync on the device, the account's home replaces this one", () async {
    await repo.set(_home(45.9, name: 'Ici'));
    account.held = asHome(_home(44, name: 'Chez nous'));
    await sync.sync();
    expect((await repo.read())?.name, 'Chez nous', reason: "the account's home wins");
    expect(account.sets, 0, reason: "the device's never overwrote it");
  });

  test('a home changed here goes to the account; one changed there comes here', () async {
    await repo.set(_home(45.9));
    await sync.sync();
    await repo.set(_home(46.1, name: 'Nouvelle maison'));
    await sync.sync();
    expect(account.held?.name, 'Nouvelle maison');

    // Another device changed it.
    account.held = asHome(_home(43, name: 'Chalet'));
    await sync.sync();
    expect((await repo.read())?.name, 'Chalet');
    expect(account.sets, 2, reason: 'what came from the account is not sent back');
  });

  test('a home removed here goes from the account; removed there, it goes here', () async {
    await repo.set(_home(45.9));
    await sync.sync();
    await repo.clear();
    await sync.sync();
    expect(account.held, isNull);
    expect(account.clears, 1);

    await repo.set(_home(45));
    await sync.sync();
    account.held = null;
    await sync.sync();
    expect(await repo.read(), isNull, reason: 'removed on another device');
  });

  test('an API without the home leaves the one here unsent, and the sync goes on', () async {
    account.knowsHome = false;
    await repo.set(_home(45.9));
    await sync.sync();
    expect(await repo.read(), isNotNull);
    expect(account.sets, 0);
    // The API learns the home: this one is the first it gets.
    account.knowsHome = true;
    await sync.sync();
    expect(account.held?.name, 'Maison');
  });

  test('a home the server refuses stays here, unsent, until it changes here', () async {
    account.refuses = true;
    await repo.set(_home(45.9));
    await sync.sync();
    await sync.sync();
    expect(account.sets, 1, reason: 'refused once, not sent again as it is');
    expect(await repo.read(), isNotNull, reason: 'kept on the device');
    account.refuses = false;
    await repo.set(_home(45.95, name: 'Maison corrigée'));
    await sync.sync();
    expect(account.held?.name, 'Maison corrigée');
  });

  test("another account on the device: its home wins over the last one's", () async {
    final lists = FavoritesSync(
      db: db,
      remote: _NoLists(),
      lookup: (_) async => null,
      defaultName: () => 'Mes favoris',
      home: sync,
    );
    await repo.set(_home(45.9, name: 'Maison de A'));
    await lists.sync(accountId: 'A');
    expect(account.held?.name, 'Maison de A');

    // B, imported in place of A, has a home of its own.
    account.held = asHome(_home(44, name: 'Maison de B'));
    await lists.sync(accountId: 'B');
    expect((await repo.read())?.name, 'Maison de B', reason: 'the base of A was forgotten');
  });

  test('clearLocal forgets the home and what the last sync agreed on', () async {
    await repo.set(_home(45.9));
    await sync.sync();
    await repo.clearLocal();
    expect(await repo.read(), isNull);
    // The account's home comes back as at a first sync, never removed
    // from the account by this device.
    await sync.sync();
    expect(account.clears, 0);
    expect((await repo.read())?.name, 'Maison');
  });

  test('the home through the API: set, read, cleared, and an older API said as such', () async {
    final api = FakeApi();
    final client = GraphQLClient(
      endpoint: Uri.parse('$testApiBase/graphql'),
      httpClient: api.client(MockClient((_) async => http.Response('', 404))),
      userAgent: 'test',
    );
    final service = AccountService(
      client: client,
      keys: SoftwareDeviceKeys(MemorySecretStore()),
      secrets: MemorySecretStore(),
      locale: () => 'fr',
    );
    await service.ensureAccount();
    final remote = GraphQLHomeRemote(service);
    expect(await remote.home(), isNull);
    final stored = await remote.set(
      SavedPoint(
        id: savedPoiPointId('11111111-1111-7111-8111-111111111111'),
        kind: SavedPointKind.poi,
        name: 'Boulangerie',
        position: const LatLng(45.9, 6.1),
        poiId: '11111111-1111-7111-8111-111111111111',
        poiKindCode: 'bakery',
      ),
    );
    expect((stored?.kind, stored?.poiKindCode), (SavedPointKind.poi, 'bakery'));
    expect(api.last('SetHome')?['home'], {
      'kind': 'POI',
      'name': 'Boulangerie',
      'lat': 45.9,
      'lon': 6.1,
      'poiId': '11111111-1111-7111-8111-111111111111',
      'poiKind': 'BAKERY',
    });
    expect((await remote.home())?.name, 'Boulangerie');
    await remote.clear();
    expect(await remote.home(), isNull);
    expect(api.violations, isEmpty);

    api.older = true;
    await expectLater(remote.home(), throwsA(isA<HomeUnsupported>()));
  });
}

/// An account without lists, for the home's part of the sync.
final class _NoLists implements FavoritesRemote {
  @override
  Future<List<RemoteList>> lists() async => const [];

  @override
  Future<List<RemoteList>> import(List<ImportedList> lists) async => const [];

  @override
  Future<String?> add(String listId, String placeId) async => null;

  @override
  Future<void> remove(String listId, String placeId) async {}

  @override
  Future<bool> addPoint(String listId, SavedPoint point) async => true;

  @override
  Future<void> removePoint(String listId, String pointId) async {}

  @override
  Future<void> rename(String listId, String name) async {}

  @override
  Future<void> delete(String listId) async {}

  @override
  Future<PlaceSummary?> place(String id) async => null;
}
