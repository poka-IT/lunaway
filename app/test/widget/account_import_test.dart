import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/presentation/account_import.dart';
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
  }) async {
    final app = await pumpLunaway(
      tester,
      api: api,
      signedIn: true,
      size: size,
      storedFavorites: true,
      recoveryCardAt: recoveryCardAt,
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
  });

  testWidgets('a device of an account merged elsewhere says where it went', (tester) async {
    final api = FakeApi();
    final app = await pumpLunaway(tester, api: api, signedIn: true);
    api.mergeElsewhere(_imported);
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
