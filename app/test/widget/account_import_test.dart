import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/account/presentation/account_import.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

final Translations t = AppLocale.fr.buildSync();

const _current = 'Martre du Vercors';
const _imported = 'Hérisson du Morvan';

/// The profile's "use another account": the card of another account opens
/// it beside the device's, and one sheet then asks what becomes of the two.
void main() {
  Future<(TestApp, GoRouter)> openImport(
    WidgetTester tester,
    FakeApi api, {
    Size size = phone,
    DateTime? recoveryCardAt,
    _Refusing? storage,
  }) async {
    final app = await pumpLunaway(
      tester,
      api: api,
      signedIn: true,
      size: size,
      storedFavorites: true,
      recoveryCardAt: recoveryCardAt,
      secretStore: storage == null ? null : (memory) => storage..inner = memory,
    );
    // A place the device saved under its account.
    await app.container(tester).read(favoritesRepositoryProvider).addToDefault(lakeArea.summary);
    final router = app.container(tester).read(routerProvider)..go(AppRoutes.useAnotherAccount);
    await settleShort(tester);
    return (app, router);
  }

  Future<void> openOther(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), FakeApi.otherRecoveryCode);
    await tester.pump();
    await tester.ensureVisible(find.text(t.accountImport.submit));
    await tester.tap(find.text(t.accountImport.submit));
    await settleShort(tester, const Duration(seconds: 2));
  }

  String? signedIn(TestApp app, WidgetTester tester) =>
      switch (app.container(tester).read(accountControllerProvider)) {
        SignedIn(:final account) => account.pseudonym,
        _ => null,
      };

  Future<List<FavoriteItemRow>> saved(TestApp app) => app.user.select(app.user.favoriteItems).get();

  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    final inSheet = find.descendant(of: find.byType(ImportChoice), matching: finder);
    await tester.ensureVisible(inSheet);
    await tester.pump();
    await tester.tap(inSheet);
    await settleShort(tester, const Duration(seconds: 2));
  }

  testWidgets('the profile offers to use another account', (tester) async {
    final app = await pumpLunaway(tester, api: FakeApi(), signedIn: true);
    app.container(tester).read(routerProvider).go(AppRoutes.profile);
    await settleShort(tester);
    final entry = find.text(t.account.useAnother);
    await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await settleShort(tester);
    expect(find.text(t.accountImport.intro(current: _current)), findsOneWidget);
    expect(
      find.text(t.recover.revoke),
      findsNothing,
      reason: 'the other account keeps its devices: the import is not a recovery',
    );
  });

  for (final (name, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    testWidgets('on a $name the sheet names both accounts, and merging keeps the imported one', (
      tester,
    ) async {
      final api = FakeApi();
      final (app, _) = await openImport(tester, api, size: size);
      await openOther(tester);
      expect(find.text(t.accountImport.choiceTitle), findsOneWidget);
      expect(
        find.text(t.accountImport.choiceBody(current: _current, imported: _imported)),
        findsOneWidget,
      );
      expect(
        find.text(t.accountImport.mergePublic(imported: _imported)),
        findsOneWidget,
        reason: 'the public contributions changing name is said in the sheet',
      );
      expect(find.text(t.accountImport.mergeDeletes(current: _current)), findsOneWidget);

      await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
      expect(api.merged, isTrue);
      expect(find.byType(ImportChoice), findsNothing);
      expect(find.text(t.accountImport.merged(name: _imported)), findsOneWidget);
      expect(signedIn(app, tester), _imported);
      expect((await saved(app)).map((r) => r.placeId), [
        lakeArea.id,
      ], reason: 'the device keeps its favourites: they join the imported account');
      await settleShort(tester, const Duration(seconds: 2));
      expect(
        api.calls.any(
          (c) =>
              c.operation == 'ImportFavorites' &&
              (c.token ?? '').startsWith('other-') &&
              jsonEncode(c.variables).contains(lakeArea.id),
        ),
        isTrue,
        reason: "the first sync of the imported account carries the device's lists to it",
      );
    });
  }

  testWidgets('replacing without merging says what is lost, then clears the account left', (
    tester,
  ) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.replace));
    expect(
      find.text(t.accountImport.replaceTitle(current: _current, imported: _imported)),
      findsOneWidget,
    );
    expect(
      find.text(t.accountImport.replaceNoCard(current: _current)),
      findsOneWidget,
      reason: 'no card known: the account left would be erased, and the sheet says it',
    );
    expect(find.text(t.accountImport.card(current: _current)), findsOneWidget);

    await tapInSheet(tester, find.text(t.accountImport.replaceConfirm));
    expect(api.merged, isFalse);
    expect(api.forgotten, ['current'], reason: 'the account left lists this device no more');
    expect(find.text(t.accountImport.replaced(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
    expect(await saved(app), isEmpty, reason: "the account left's favourites leave the device");
  });

  testWidgets('with a card made, the replacement says that card brings the account back', (
    tester,
  ) async {
    final api = FakeApi();
    await openImport(tester, api, recoveryCardAt: testNow.subtract(const Duration(days: 30)));
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.replace));
    expect(find.text(t.accountImport.replaceKeeps(current: _current)), findsOneWidget);
    expect(find.text(t.accountImport.replaceNoCard(current: _current)), findsNothing);
    // Back to the choice: nothing done.
    await tapInSheet(tester, find.text(t.accountImport.back));
    expect(find.text(t.accountImport.merge(imported: _imported)), findsOneWidget);
    expect(api.forgotten, isEmpty);
  });

  testWidgets('with a home on both sides, the sheet says the imported one stays', (tester) async {
    final api = FakeApi()..otherHasHome = true;
    final (app, _) = await openImport(tester, api);
    final homes = app.container(tester).read(homeRepositoryProvider);
    await homes.set(
      SavedPoint(
        id: 'home',
        kind: SavedPointKind.address,
        name: 'Hôtel de ville',
        position: const LatLng(45.8992, 6.1294),
      ),
    );
    await openOther(tester);
    expect(find.text(t.accountImport.mergeHomeKept(imported: _imported)), findsOneWidget);

    // Replacing instead: the device's home leaves with the account left,
    // and the imported account's comes with its first sync.
    await tapInSheet(tester, find.text(t.accountImport.replace));
    await tapInSheet(tester, find.text(t.accountImport.replaceConfirm));
    await settleShort(tester, const Duration(seconds: 2));
    expect((await homes.read())?.name, 'Capitainerie');
  });

  testWidgets('without a home on the device, the sheet does not speak of one', (tester) async {
    final api = FakeApi()..otherHasHome = true;
    await openImport(tester, api);
    await openOther(tester);
    expect(find.text(t.accountImport.mergeHomeKept(imported: _imported)), findsNothing);
  });

  testWidgets('giving up leaves the device as it was', (tester) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.common.cancel));
    expect(api.merged, isFalse);
    expect(api.forgotten, ['other'], reason: 'the new key leaves the imported account');
    expect(find.text(t.accountImport.cancelled(name: _current)), findsOneWidget);
    expect(signedIn(app, tester), _current);
    expect((await saved(app)).map((r) => r.placeId), [lakeArea.id]);
  });

  testWidgets('a replacement the server did not hear stays in the sheet, the device unchanged', (
    tester,
  ) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.replace));
    api.offline = true;
    await tapInSheet(tester, find.text(t.accountImport.replaceConfirm));
    expect(find.byType(ImportChoice), findsOneWidget, reason: 'the sheet stays');
    expect(find.text(t.accountImport.replaceFailed), findsOneWidget);
    expect(signedIn(app, tester), _current);
    expect(api.forgotten, isEmpty);
    expect((await saved(app)).map((r) => r.placeId), [lakeArea.id]);

    api.offline = false;
    await tapInSheet(tester, find.text(t.accountImport.replaceConfirm));
    expect(find.text(t.accountImport.replaced(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
  });

  testWidgets('the card of the account left is made on the way, and the choice comes back', (
    tester,
  ) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.replace));
    await tapInSheet(tester, find.text(t.accountImport.card(current: _current)));
    expect(find.byType(ImportChoice), findsNothing);
    await tester.ensureVisible(find.text(t.recovery.make));
    await tester.tap(find.text(t.recovery.make));
    await settleShort(tester, const Duration(seconds: 2));
    await tester.ensureVisible(find.text(t.recovery.done));
    await tester.tap(find.text(t.recovery.done));
    await settleShort(tester);
    await tester.tap(find.text(t.recovery.done).last);
    await settleShort(tester, const Duration(seconds: 2));

    expect(
      find.text(t.accountImport.replaceTitle(current: _current, imported: _imported)),
      findsOneWidget,
      reason: 'the sheet opens again at the replacement',
    );
    expect(
      find.text(t.accountImport.replaceKeeps(current: _current)),
      findsOneWidget,
      reason: 'the card just made brings the account left back',
    );
    expect(signedIn(app, tester), _current);
    expect(api.forgotten, isEmpty);
  });

  testWidgets('offline before the merge leaves, nothing is uncertain and giving up is direct', (
    tester,
  ) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    api.offline = true;
    await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
    expect(find.text(t.accountImport.failed), findsOneWidget);
    expect(api.operations, isNot(contains('MergeAccount')));
    expect(
      find.text(t.accountImport.merge(imported: _imported)),
      findsOneWidget,
      reason: 'no merge left the device: nothing to settle, the button merges',
    );
    await tapInSheet(tester, find.text(t.common.cancel));
    expect(find.text(t.accountImport.cancelled(name: _current)), findsOneWidget);
    expect(signedIn(app, tester), _current);
  });

  testWidgets('after a cut merge, giving up offline waits for the server and says why', (
    tester,
  ) async {
    final api = FakeApi()..loseMergeAnswer = true;
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
    api.offline = true;
    await tapInSheet(tester, find.text(t.common.cancel));
    expect(find.byType(ImportChoice), findsOneWidget, reason: 'the merge may have been made');
    expect(find.text(t.accountImport.unsettled), findsOneWidget);
    expect(signedIn(app, tester), _current);
    expect(api.forgotten, isEmpty, reason: 'the imported account keeps the key it may now need');

    api.offline = false;
    await tapInSheet(tester, find.text(t.common.cancel));
    expect(find.text(t.accountImport.merged(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
  });

  testWidgets('replacing after a cut merge finishes the merge the server made', (tester) async {
    final api = FakeApi()..loseMergeAnswer = true;
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
    await tapInSheet(tester, find.text(t.accountImport.replace));
    final card = find.ancestor(
      of: find.text(t.accountImport.card(current: _current)),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(
      tester.widget<OutlinedButton>(card).onPressed,
      isNull,
      reason: 'no card of an account that may be gone',
    );
    await tapInSheet(tester, find.text(t.accountImport.replaceConfirm));
    expect(find.text(t.accountImport.merged(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
    expect(api.forgotten, isEmpty, reason: 'nothing was detached: the merge had been made');
    expect((await saved(app)).map((r) => r.placeId), [lakeArea.id]);
  });

  testWidgets('a merge cut by the network loses nothing, and "Réessayer" finishes it', (
    tester,
  ) async {
    final api = FakeApi()..loseMergeAnswer = true;
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
    expect(find.byType(ImportChoice), findsOneWidget, reason: 'the sheet stays');
    expect(find.text(t.accountImport.failed), findsOneWidget);
    expect(signedIn(app, tester), _current, reason: 'the device has not switched');
    expect((await saved(app)).map((r) => r.placeId), [lakeArea.id]);

    await tapInSheet(tester, find.text(t.common.retry));
    expect(find.text(t.accountImport.merged(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
    expect((await saved(app)).map((r) => r.placeId), [lakeArea.id]);
  });

  testWidgets('given up after a cut merge, the merge the server made is finished', (tester) async {
    final api = FakeApi()..loseMergeAnswer = true;
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
    expect(find.text(t.accountImport.failed), findsOneWidget);

    await tapInSheet(tester, find.text(t.common.cancel));
    expect(
      find.text(t.accountImport.merged(name: _imported)),
      findsOneWidget,
      reason: 'the account the device held is gone: the device keeps the one it went into',
    );
    expect(signedIn(app, tester), _imported);
    expect(api.forgotten, isEmpty);
  });

  testWidgets('the dock does not end the choice while the merge is under way', (tester) async {
    final api = FakeApi()
      ..held = {'MergeAccount'}
      ..hold = Completer<void>();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    final merge = find.descendant(
      of: find.byType(ImportChoice),
      matching: find.text(t.accountImport.merge(imported: _imported)),
    );
    await tester.ensureVisible(merge);
    await tester.tap(merge);
    await tester.pump(const Duration(milliseconds: 300));
    // The profile's destination, tapped again: the sheet covers it.
    await tester.tap(find.text(t.nav.profile).last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ImportChoice), findsOneWidget);
    api.hold!.complete();
    await settleShort(tester, const Duration(seconds: 2));
    expect(signedIn(app, tester), _imported);
    expect(api.forgotten, isEmpty, reason: 'no cancel ran beside the merge');
  });

  testWidgets('no sync of the favourites starts while the device changes accounts', (tester) async {
    final api = FakeApi();
    final app = await pumpLunaway(tester, api: api, signedIn: true, storedFavorites: true);
    await settleShort(tester, const Duration(seconds: 2));
    final favorites = app.container(tester).read(favoritesSyncControllerProvider.notifier);
    int reads() => api.operations.where((o) => o == 'MyFavoriteLists').length;
    final before = reads();
    api
      ..held = {'MyFavoriteLists'}
      ..hold = Completer<void>();
    // A sync under way, and one more asked meanwhile, which would start as
    // the first ends.
    unawaited(favorites.syncNow());
    unawaited(favorites.syncNow());
    await tester.pump();
    final switching = Completer<void>();
    var inside = false;
    final held = favorites.holding(() async {
      inside = true;
      await switching.future;
    });
    api.hold!.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(inside, isTrue, reason: 'the switch runs once the sync under way has ended');
    expect(reads(), before + 1, reason: 'the sync asked meanwhile waits for the switch to end');

    switching.complete();
    await held;
    await settleShort(tester, const Duration(seconds: 2));
    expect(reads(), before + 2, reason: 'the switch done, the favourites sync again');
  });

  testWidgets('the system back gives up as "Annuler" does', (tester) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await openOther(tester);
    await tester.binding.handlePopRoute();
    await settleShort(tester, const Duration(seconds: 2));
    expect(find.text(t.accountImport.cancelled(name: _current)), findsOneWidget);
    expect(api.forgotten, ['other']);
    expect(signedIn(app, tester), _current);
  });

  testWidgets('a merge the device could not keep loses nothing, and "Réessayer" ends it', (
    tester,
  ) async {
    final api = FakeApi();
    final storage = _Refusing();
    final (app, _) = await openImport(tester, api, storage: storage);
    final container = app.container(tester);
    final account = (container.read(accountControllerProvider) as SignedIn).account;
    final store = container.read(outboxStoreProvider);
    final waiting = await store.add(
      ContributionKind.confirm,
      placeId: campsite.id,
      payload: {'placeId': campsite.id, 'status': 'STILL_OK'},
      accountId: account.id,
    );
    await openOther(tester);
    storage.refused.add('session');
    await tapInSheet(tester, find.text(t.accountImport.merge(imported: _imported)));
    expect(find.text(t.accountImport.deviceFailed), findsOneWidget);
    await settleShort(tester, const Duration(seconds: 2));
    expect(
      (await store.byId(waiting!.id))?.state,
      isNot(OutboxState.failed),
      reason: 'moved to the account kept, it waits for the device to hold it',
    );

    storage.refused.clear();
    await tapInSheet(tester, find.text(t.common.retry));
    expect(find.text(t.accountImport.merged(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
    await settleShort(tester, const Duration(seconds: 2));
    expect(await store.byId(waiting.id), isNull, reason: 'sent under the account kept');
  });

  testWidgets('a replacement cut after the account was left offers only to end it', (tester) async {
    final api = FakeApi();
    final storage = _Refusing();
    final (app, _) = await openImport(tester, api, storage: storage);
    await openOther(tester);
    await tapInSheet(tester, find.text(t.accountImport.replace));
    storage.refused.add('device_key');
    await tapInSheet(tester, find.text(t.accountImport.replaceConfirm));
    expect(find.text(t.accountImport.replaceUnfinished(current: _current)), findsOneWidget);
    expect(find.text(t.accountImport.card(current: _current)), findsNothing);
    expect(find.text(t.accountImport.back), findsNothing);
    await tester.binding.handlePopRoute();
    await settleShort(tester);
    expect(find.byType(ImportChoice), findsOneWidget, reason: 'the back does not give it up');

    storage.refused.clear();
    await tapInSheet(tester, find.text(t.common.retry));
    expect(find.text(t.accountImport.replaced(name: _imported)), findsOneWidget);
    expect(signedIn(app, tester), _imported);
    expect(api.forgotten, ['current'], reason: 'the account was left once');
  });

  testWidgets('no pass of the outbox starts while the device changes accounts', (tester) async {
    final api = FakeApi();
    final app = await pumpLunaway(tester, api: api, signedIn: true);
    await settleShort(tester, const Duration(seconds: 2));
    final container = app.container(tester);
    final runner = container.read(outboxRunnerProvider.notifier);
    final store = container.read(outboxStoreProvider);
    final id = (container.read(accountControllerProvider) as SignedIn).account.id;
    int confirms() => api.operations.where((o) => o == 'Confirm').length;
    Future<void> confirm(String placeId) => store.add(
      ContributionKind.confirm,
      placeId: placeId,
      payload: {'placeId': placeId, 'status': 'STILL_OK'},
      accountId: id,
    );
    api.hold = Completer<void>();
    await confirm(lakeArea.id);
    unawaited(runner.kick());
    await tester.pump();
    final switching = Completer<void>();
    var inside = false;
    final held = runner.holding(() async {
      inside = true;
      await switching.future;
    });
    await tester.pump(const Duration(seconds: 1));
    expect(inside, isFalse, reason: 'the switch waits for the pass under way');
    api.hold!.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(inside, isTrue, reason: 'the switch runs once the pass under way has ended');
    expect(confirms(), 1);

    await confirm(campsite.id);
    unawaited(runner.kick());
    await tester.pump(const Duration(seconds: 1));
    expect(confirms(), 1, reason: 'what is queued meanwhile waits for the switch to end');

    switching.complete();
    await held;
    await settleShort(tester, const Duration(seconds: 2));
    expect(confirms(), 2, reason: 'the switch done, the outbox sends what waits');
  });

  /// The device held an account merged from elsewhere into the account
  /// [intoId], with a contribution waiting, and has just signed out of the
  /// one it then made: the account of the recovery card comes next.
  Future<(TestApp, PendingContribution)> mergedAway(
    WidgetTester tester,
    FakeApi api, {
    required String Function(Account account) intoId,
  }) async {
    final app = await pumpLunaway(tester, api: api, signedIn: true);
    await settleShort(tester, const Duration(seconds: 2));
    final container = app.container(tester);
    final account = (container.read(accountControllerProvider) as SignedIn).account;
    await container.read(accountControllerProvider.notifier).signOut();
    await settleShort(tester);
    const gone = '01990000-0000-7000-8000-0000000000aa';
    final entry = await container
        .read(outboxStoreProvider)
        .add(
          ContributionKind.confirm,
          placeId: lakeArea.id,
          payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
          accountId: gone,
        );
    await app.secrets.write(
      'merged_from',
      jsonEncode({'from': gone, 'into': account.pseudonym, 'intoId': intoId(account)}),
    );
    await container
        .read(accountControllerProvider.notifier)
        .recover(FakeApi.recoveryCode, revokeOthers: false);
    await settleShort(tester, const Duration(seconds: 2));
    return (app, entry!);
  }

  testWidgets('what waited for the account the device went into leaves once it comes', (
    tester,
  ) async {
    final api = FakeApi();
    final (app, entry) = await mergedAway(tester, api, intoId: (a) => a.id);
    final store = app.container(tester).read(outboxStoreProvider);
    expect(await store.byId(entry.id), isNull, reason: 'sent under the account it went into');
    expect(api.operations, contains('Confirm'));
  });

  testWidgets('a namesake of the account the device went into takes nothing of it', (tester) async {
    final api = FakeApi();
    final (app, entry) = await mergedAway(
      tester,
      api,
      intoId: (_) => '01990000-0000-7000-8000-0000000000bb',
    );
    final store = app.container(tester).read(outboxStoreProvider);
    final left = await store.byId(entry.id);
    expect(left?.state, OutboxState.failed, reason: 'another account came: it never leaves');
    expect(left?.errorCode, OutboxError.otherAccount);
    expect(api.operations, isNot(contains('Confirm')));
  });

  testWidgets("the card of the device's own account is said on the field", (tester) async {
    final api = FakeApi();
    final (app, _) = await openImport(tester, api);
    await tester.enterText(find.byType(TextField), FakeApi.recoveryCode);
    await tester.pump();
    await tester.ensureVisible(find.text(t.accountImport.submit));
    await tester.tap(find.text(t.accountImport.submit));
    await settleShort(tester, const Duration(seconds: 2));
    expect(find.text(t.accountImport.same(current: _current)), findsOneWidget);
    expect(find.byType(ImportChoice), findsNothing);
    expect(signedIn(app, tester), _current);
    expect(api.forgotten, hasLength(1), reason: 'the new key of the same account goes at once');
  });

  testWidgets('a device of an account merged elsewhere says where it went', (tester) async {
    final api = FakeApi();
    final app = await pumpLunaway(tester, api: api, signedIn: true);
    api.mergeElsewhere(_imported, id: FakeApi.otherId);
    // Its next read of the account, as a sync would.
    await app.container(tester).read(accountControllerProvider.notifier).refresh();
    await settleShort(tester, const Duration(seconds: 2));
    expect(find.text(t.account.merged(name: _imported)), findsOneWidget);
    app.container(tester).read(routerProvider).go(AppRoutes.profile);
    await settleShort(tester);
    expect(find.text(t.account.mergedTitle(name: _imported)), findsOneWidget);
    expect(find.text(t.account.mergedOpen(name: _imported)), findsOneWidget);
    final state = app.container(tester).read(accountControllerProvider);
    expect(state, isA<NoAccount>().having((s) => s.mergedInto, 'mergedInto', _imported));
  });
}

/// The device's protected storage over the test's memory one, refusing to
/// write the slots in [refused] (a keychain locked, IndexedDB refused).
final class _Refusing implements SecretStore {
  MemorySecretStore inner = MemorySecretStore();
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
