import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/account/application/account_switch.dart';
import 'package:lunaway/features/account/data/account_operations.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/p256.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The import of another account beside the device's, and what each choice
/// does: the merge signed by both keys, the replacement, giving up, and
/// the other devices of a merged account. Against the fake API, which
/// checks both signatures as the server does.
void main() {
  late FakeApi api;
  late MemorySecretStore secrets;
  late SoftwareDeviceKeys keys;
  late AccountService service;
  late UserDatabase db;
  late OutboxStore outbox;
  late AccountSwitch accounts;
  var homeForgotten = false;

  setUp(() async {
    api = FakeApi();
    secrets = MemorySecretStore();
    keys = SoftwareDeviceKeys(secrets);
    final client = GraphQLClient(
      endpoint: Uri.parse('$testApiBase/graphql'),
      httpClient: api.client(MockClient((_) async => http.Response('', 404))),
      userAgent: 'Lunaway/test (+https://lunaway.net)',
    );
    service = AccountService(
      client: client,
      keys: keys,
      secrets: secrets,
      locale: () => 'fr',
      clock: () => testNow,
    );
    db = UserDatabase(NativeDatabase.memory());
    outbox = OutboxStore(db, files: MemoryPendingFiles(), clock: () => testNow);
    homeForgotten = false;
    accounts = AccountSwitch(
      service: service,
      outbox: outbox,
      favorites: FavoritesSync(
        db: db,
        remote: GraphQLFavoritesRemote(service),
        lookup: (_) async => null,
        defaultName: () => 'Mes favoris',
      ),
      deviceHasHome: () async => true,
      forgetHome: () async => homeForgotten = true,
    );
    await seedAccount(secrets, api);
  });
  tearDown(() async {
    expect(api.violations, isEmpty);
    await db.close();
  });

  Future<String> currentId() async => (await service.restore())!.account.id;

  /// The device's service and switch over [store], beside the ones of
  /// [setUp]: the same storage underneath, with its failures.
  (AccountService, AccountSwitch) over(SecretStore store) {
    final device = AccountService(
      client: GraphQLClient(
        endpoint: Uri.parse('$testApiBase/graphql'),
        httpClient: api.client(MockClient((_) async => http.Response('', 404))),
        userAgent: 'Lunaway/test (+https://lunaway.net)',
      ),
      keys: SoftwareDeviceKeys(store),
      secrets: store,
      locale: () => 'fr',
      clock: () => testNow,
    );
    return (
      device,
      AccountSwitch(
        service: device,
        outbox: outbox,
        favorites: accounts.favorites,
        deviceHasHome: () async => false,
        forgetHome: () async {},
      ),
    );
  }

  test(
    'a merge the server made and the device could not keep is finished here, not asked again',
    () async {
      final store = _Breakable(secrets)..refused.add('device_key');
      final (device, switcher) = over(store);
      final oldId = await currentId();
      final imported = await switcher.import(FakeApi.otherRecoveryCode);
      await expectLater(
        switcher.merge(imported, currentId: oldId),
        throwsA(isA<MergeUnsettledException>()),
        reason: 'made on the server, unfinished here: the sheet keeps it uncertain',
      );
      expect(api.merged, isTrue);
      store.refused.clear();
      final merges = api.operations.where((o) => o == 'MergeAccount').length;
      expect(await switcher.settle(imported, currentId: oldId), isTrue);
      expect(
        api.operations.where((o) => o == 'MergeAccount').length,
        merges,
        reason: 'the keys may be half switched: the device ends what the server did',
      );
      expect((await device.restore())!.account.id, FakeApi.otherId);
      expect((await keys.load())!.publicJwk, imported.key.publicJwk);
    },
  );

  test('a replacement that failed after leaving ends when tried again, leaving once', () async {
    final store = _Breakable(secrets)..refused.add('device_key');
    final (device, switcher) = over(store);
    final imported = await switcher.import(FakeApi.otherRecoveryCode);
    await expectLater(switcher.replace(imported), throwsA(anything));
    expect(api.forgotten, ['current']);
    expect(switcher.left, isTrue, reason: 'only the replacement can end now');
    store.refused.clear();
    await switcher.replace(imported);
    expect(api.forgotten, ['current'], reason: 'the account was left once');
    expect(switcher.left, isFalse);
    expect((await device.restore())!.account.id, FakeApi.otherId);
  });

  test('once the device left its account for another, no sign-in says it was lost', () async {
    await accounts.import(FakeApi.otherRecoveryCode);
    await service.leaveForReplace();
    final events = <AccountEvent>[];
    final sub = service.events.listen(events.add);
    addTearDown(sub.cancel);
    await expectLater(service.run(myAccountOperation), throwsA(isA<AccountChangedException>()));
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty, reason: 'the switch under way is no account lost');
    expect(await keys.load(), isNotNull, reason: 'the key goes with the switch, not before it');
  });

  test('the text both keys sign is the one the server checks', () {
    const absorbed = PublicJwk(x: 'ax', y: 'ay');
    const into = PublicJwk(x: 'bx', y: 'by');
    expect(
      AccountService.mergeMessage('n', absorbed, into),
      'lunaway-merge:v1:n:${absorbed.thumbprint}:${into.thumbprint}',
      reason: 'the API builds lunaway-merge:v1:<nonce>:<absorbed>:<into> (merge_message)',
    );
  });

  test("an imported account waits beside the device's until the user chooses", () async {
    final before = (await keys.load())!.publicJwk;
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    expect(imported.account.pseudonym, 'Hérisson du Morvan');
    expect((await keys.load())!.publicJwk, before, reason: 'the device keeps its own key');
    expect((await service.restore())!.account.pseudonym, 'Martre du Vercors');
  });

  test(
    'a merge signs with both keys, moves what waits, then the device keeps the import',
    () async {
      final oldId = await currentId();
      final waiting = await outbox.add(
        ContributionKind.confirm,
        placeId: lakeArea.id,
        payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
        accountId: oldId,
      );
      final imported = await accounts.import(FakeApi.otherRecoveryCode);
      final result = await accounts.merge(imported, currentId: oldId);

      expect(api.merged, isTrue, reason: 'the fake checked both signatures');
      expect(result.home, MergedHome.moved);
      expect((await service.restore())!.account.id, FakeApi.otherId);
      expect((await keys.load())!.publicJwk, imported.key.publicJwk);
      expect(
        (await outbox.byId(waiting!.id))!.accountId,
        FakeApi.otherId,
        reason: 'a contribution waiting under the merged account leaves under the one kept',
      );
    },
  );

  test('a merge whose answer was lost changes nothing here, and asked again it is made', () async {
    final oldId = await currentId();
    final before = (await keys.load())!.publicJwk;
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    api.loseMergeAnswer = true;
    await expectLater(accounts.merge(imported, currentId: oldId), throwsA(anything));
    expect(api.merged, isTrue, reason: 'the server made it');
    expect((await keys.load())!.publicJwk, before, reason: 'the device has not switched');
    expect((await service.restore())!.account.id, oldId);

    // Meanwhile a request of the device's account (a sync) neither forgets
    // its key nor says the account is lost: it waits, as offline.
    await expectLater(service.run(myAccountOperation), throwsA(isA<AccountMergingException>()));
    expect((await keys.load())!.publicJwk, before, reason: 'the key that proves the merge stays');

    final again = await accounts.merge(imported, currentId: oldId);
    expect(again.account.id, FakeApi.otherId);
    expect((await service.restore())!.account.id, FakeApi.otherId);
  });

  test('given up after a lost answer, the merge the server made is finished', () async {
    final oldId = await currentId();
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    api.loseMergeAnswer = true;
    await expectLater(accounts.merge(imported, currentId: oldId), throwsA(anything));
    expect(await accounts.settle(imported, currentId: oldId), isTrue);
    expect((await service.restore())!.account.id, FakeApi.otherId);
    await accounts.cancel(imported);
    expect(api.forgotten, isEmpty, reason: 'the key adopted is not detached by a late cancel');
  });

  test(
    'a request refused once the device took another account is not sent again under it',
    () async {
      final imported = await accounts.import(FakeApi.otherRecoveryCode);
      api
        ..held = {'MyAccount'}
        ..hold = Completer<void>();
      // A read of the account under way, with the session of the account the
      // device holds, while the device merges it into the import.
      final read = service.run(myAccountOperation);
      await accounts.merge(imported, currentId: await currentId());
      api.hold!.complete();
      await expectLater(read, throwsA(isA<AccountChangedException>()));
      expect(
        api.calls.where((c) => c.operation == 'MyAccount').map((c) => c.token),
        everyElement(isNot(startsWith('other-'))),
        reason: 'a request of the account left never goes with the session of the account taken',
      );
    },
  );

  test('the account a merged one went into is known by its id, never by its name', () async {
    final oldId = await currentId();
    final waiting = await outbox.add(
      ContributionKind.confirm,
      placeId: lakeArea.id,
      payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
      accountId: oldId,
    );
    api.mergeElsewhere('Hérisson du Morvan', id: FakeApi.otherId);
    await expectLater(service.run(myAccountOperation), throwsA(isA<AccountLostException>()));
    // Another account of the same name comes to the device.
    final namesake = Account.fromJson({
      ...api.otherAccount(),
      'id': '01990000-0000-7000-8000-000000000042',
    })!;
    expect(await accounts.claimMerged(namesake), isFalse);
    expect(
      (await outbox.byId(waiting!.id))!.accountId,
      oldId,
      reason: 'what waited for the account merged does not leave under a namesake',
    );
    expect(await service.mergedFrom(), isNull, reason: 'another account came: it waits no more');
  });

  test('a merge never made leaves the device to its choice', () async {
    final oldId = await currentId();
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    expect(await accounts.settle(imported, currentId: oldId), isFalse);
    expect((await service.restore())!.account.id, oldId);
  });

  test(
    'stopped during a merge, the device keeps what waits for the account it went into',
    () async {
      final oldId = await currentId();
      final waiting = await outbox.add(
        ContributionKind.confirm,
        placeId: lakeArea.id,
        payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
        accountId: oldId,
      );
      final imported = await accounts.import(FakeApi.otherRecoveryCode);
      api.loseMergeAnswer = true;
      await expectLater(accounts.merge(imported, currentId: oldId), throwsA(anything));
      // The app ends: what it held in memory goes, its storage stays.
      final restarted = AccountService(
        client: GraphQLClient(
          endpoint: Uri.parse('$testApiBase/graphql'),
          httpClient: api.client(MockClient((_) async => http.Response('', 404))),
          userAgent: 'Lunaway/test (+https://lunaway.net)',
        ),
        keys: keys,
        secrets: secrets,
        locale: () => 'fr',
        clock: () => testNow,
      );
      await expectLater(
        restarted.run(myAccountOperation),
        throwsA(
          isA<AccountLostException>().having((e) => e.mergedInto, 'into', 'Hérisson du Morvan'),
        ),
      );
      expect(await restarted.mergedFrom(), (
        from: oldId,
        into: 'Hérisson du Morvan',
        intoId: FakeApi.otherId,
      ));
      // The user opens the account it went into with its card.
      final again = AccountSwitch(
        service: restarted,
        outbox: outbox,
        favorites: accounts.favorites,
        deviceHasHome: () async => false,
        forgetHome: () async {},
      );
      final account = await restarted.recover(FakeApi.otherRecoveryCode, revokeOthers: false);
      await again.claimMerged(account);
      expect(
        (await outbox.byId(waiting!.id))!.accountId,
        FakeApi.otherId,
        reason: 'what waited under the merged account leaves under the one it went into',
      );
      expect(await restarted.mergedFrom(), isNull);
    },
  );

  test('replacing clears what the device held of the account left and detaches its key', () async {
    final list = await db
        .into(db.favoriteLists)
        .insert(FavoriteListsCompanion.insert(createdAt: testNow.millisecondsSinceEpoch));
    await db
        .into(db.favoriteItems)
        .insert(
          FavoriteItemsCompanion.insert(
            listId: list,
            placeId: lakeArea.id,
            kind: 'MOTORHOME_AREA',
            lat: 45,
            lon: 6,
            addedAt: 0,
          ),
        );
    await outbox.add(
      ContributionKind.confirm,
      placeId: lakeArea.id,
      payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
      accountId: await currentId(),
    );
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    await accounts.replace(imported);

    expect(api.forgotten, ['current'], reason: 'the account left lists this device no more');
    expect(api.merged, isFalse);
    expect(await db.select(db.favoriteItems).get(), isEmpty);
    expect(await outbox.all(), isEmpty);
    expect(homeForgotten, isTrue);
    expect((await service.restore())!.account.id, FakeApi.otherId);
  });

  test('a replacement the server did not hear changes nothing on the device', () async {
    final oldId = await currentId();
    final before = (await keys.load())!.publicJwk;
    await outbox.add(
      ContributionKind.confirm,
      placeId: lakeArea.id,
      payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
      accountId: oldId,
    );
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    api.offline = true;
    await expectLater(accounts.replace(imported), throwsA(anything));
    expect(
      (await keys.load())!.publicJwk,
      before,
      reason: 'the key of an account the server still keeps is never forgotten unheard',
    );
    expect((await service.restore())!.account.id, oldId);
    expect(await outbox.all(), hasLength(1), reason: 'what waits stays');
    expect(homeForgotten, isFalse);
  });

  test('giving up detaches the new key from the imported account', () async {
    final oldId = await currentId();
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    await accounts.cancel(imported);
    expect(api.forgotten, ['other']);
    expect((await service.restore())!.account.id, oldId);
  });

  test('another device of a merged account hears where it went', () async {
    final imported = await accounts.import(FakeApi.otherRecoveryCode);
    await accounts.merge(imported, currentId: await currentId());
    // A second device of the merged account: the seeded key again, its
    // session gone with the account.
    final other = MemorySecretStore();
    await seedAccount(other, FakeApi());
    final device = AccountService(
      client: GraphQLClient(
        endpoint: Uri.parse('$testApiBase/graphql'),
        httpClient: api.client(MockClient((_) async => http.Response('', 404))),
        userAgent: 'Lunaway/test (+https://lunaway.net)',
      ),
      keys: SoftwareDeviceKeys(other),
      secrets: other,
      locale: () => 'fr',
      clock: () => testNow,
    );
    final gone = expectLater(
      device.events,
      emits(isA<AccountGone>().having((g) => g.mergedInto, 'mergedInto', 'Hérisson du Morvan')),
    );
    await expectLater(
      device.run(myAccountOperation),
      throwsA(
        isA<AccountLostException>().having((e) => e.mergedInto, 'mergedInto', 'Hérisson du Morvan'),
      ),
    );
    await gone;
    expect(await device.restore(), isNull, reason: 'the device forgot the merged account');
  });
}

/// The device's protected storage, refusing to write the slots in
/// [refused] (a keychain locked, IndexedDB refused).
final class _Breakable implements SecretStore {
  new(this.inner);

  final MemorySecretStore inner;
  final refused = <String>{};

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (refused.contains(key)) throw StateError('storage refused');
    await inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => inner.delete(key);
}
