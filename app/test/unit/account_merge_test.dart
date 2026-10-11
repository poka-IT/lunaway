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

    final again = await accounts.merge(imported, currentId: oldId);
    expect(again.account.id, FakeApi.otherId);
    expect((await service.restore())!.account.id, FakeApi.otherId);
  });

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
