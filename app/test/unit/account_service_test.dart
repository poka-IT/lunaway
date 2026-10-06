import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/community/data/community_api.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/community/data/outbox_sender.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:lunaway/features/community/data/photo_upload.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';

import '../helpers/fake_api.dart';
import '../helpers/samples.dart';

/// The account service against the fake API, which signs nothing it cannot
/// verify and, like the server, makes an account for any key it does not
/// know.
void main() {
  late FakeApi api;
  late MemorySecretStore secrets;
  late SoftwareDeviceKeys keys;
  late AccountService service;

  setUp(() {
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
  });
  tearDown(() => expect(api.violations, isEmpty));

  test('a first contribution whose sign-in never reached the server is sent once', () async {
    // The key was kept before the first sign-in, whose request was lost:
    // no account on the device, none on the server.
    await keys.save(await keys.generate());
    final db = UserDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final outbox = OutboxStore(db, files: MemoryPendingFiles(), clock: () => testNow);
    final entry = await outbox.add(
      ContributionKind.confirm,
      placeId: lakeArea.id,
      payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
    );
    // The app ended during that attempt.
    await outbox.markSending(entry!.id);
    final sender = OutboxSender(
      outbox: outbox,
      api: GraphQLCommunityApi(
        account: service,
        uploader: PhotoUploader(
          client: MockClient((_) async => http.Response('', 404)),
          endpoint: Uri.parse('$testApiBase/upload'),
          userAgent: 'test',
        ),
      ),
      accountId: () async => (await service.restore())?.account.id,
      clock: () => testNow,
    );

    final report = await sender.sendDue();
    expect(report.sent, 1);
    expect(api.operations.where((o) => o == 'Confirm'), hasLength(1));
    expect(api.strangersDeleted, 0, reason: 'its own first account, kept');
    expect((await service.restore())?.account.id, isNotNull);
    expect(await outbox.all(), isEmpty);
  });

  test('a key the server no longer knows makes no account behind the user', () async {
    final key = await keys.generate();
    await keys.save(key);
    await service.ensureAccount();
    api.revokeAll();
    await expectLater(service.refresh(), throwsA(isA<AccountLostException>()));
    expect(api.strangersDeleted, 1);
    expect(await keys.load(), isNull);
    expect(await service.restore(), isNull);
  });

  test('an account kept here that the key does not open is replaced, never deleted', () async {
    await service.ensureAccount();
    // The device kept another account than the one its key opens (an
    // interrupted recovery): the server's answer is the right one.
    await secrets.write(
      'account',
      '{"id":"00000000-0000-7000-8000-00000000ffff",'
          '"pseudonym":"Ancien","trustLevel":0,"createdAt":"2026-09-01T08:00:00Z"}',
    );
    await secrets.delete('session');
    final fresh = AccountService(
      client: service.client,
      keys: keys,
      secrets: secrets,
      locale: () => 'fr',
      clock: () => testNow,
    );
    final read = await fresh.refresh();
    expect(read.account.pseudonym, 'Martre du Vercors');
    expect(api.operations, isNot(contains('DeleteAccount')));
    expect(api.hasAccount, isTrue);
  });

  test('a sign-in that ends after the device forgot its account keeps nothing', () async {
    final key = await keys.generate();
    await keys.save(key);
    await service.ensureAccount();
    await secrets.delete('session');
    final reading = AccountService(
      client: service.client,
      keys: keys,
      secrets: secrets,
      locale: () => 'fr',
      clock: () => testNow,
    );
    // The sign-in starts, then the account is forgotten (signed out)
    // before its answer is kept.
    final pending = reading.refresh();
    await reading.signOut();
    await expectLater(pending, throwsA(isA<NoAccountException>()));
    expect(await secrets.read('session'), isNull);
    expect(await reading.restore(), isNull);
  });
}
