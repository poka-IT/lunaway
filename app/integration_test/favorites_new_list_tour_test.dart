import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;

/// The steps of the second UX audit (94, M8) on the real app and the real
/// API: "Save" on a place, a new account (its welcome, its recovery card),
/// a long press, a new list, "Done"; then what the device and the account
/// hold, printed as `FAVORITES` lines, and Mes favoris still holding the
/// place. The account is deleted at the end, whatever happens. Run on a
/// device of one's own:
///
///     fvm flutter test integration_test/favorites_new_list_tour_test.dart \
///       -d <device> --flavor store --no-uninstall \
///       --dart-define=LUNAWAY_API_URL=https://api.lunaway.net
const _viviers = '01a10f0e-2a62-7763-9c8a-0d9fbedb1e49';

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a new list keeps the place in Mes favoris', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 2));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final t = AppLocale.fr.buildSync();
    final repo = container.read(favoritesRepositoryProvider);
    final remote = GraphQLFavoritesRemote(container.read(accountServiceProvider));
    final db = container.read(userDatabaseProvider);

    Future<void> dump(String when) async {
      final lists = await repo.watchLists().first;
      final local = {
        for (final l in lists)
          '${l.name ?? 'default'}#${l.id}': [
            for (final e in await repo.watchFavorites(l.id).first) e.key.substring(0, 8),
          ],
      };
      final bound = {
        for (final l in await db.select(db.favoriteLists).get()) l.id: l.serverId?.substring(0, 8),
      };
      final base = {
        for (final b in await db.select(db.favoriteSyncBase).get())
          b.serverId.substring(0, 8): b.placeIds,
      };
      String server;
      try {
        server = [
          for (final r in await remote.lists())
            '${r.name}#${r.id.substring(0, 8)}: ${r.placeIds.map((p) => p.substring(0, 8)).toList()}',
        ].join(' | ');
      } on Object catch (e) {
        server = 'unread: ${e.runtimeType}';
      }
      debugPrint(
        'FAVORITES $when local=$local bound=$bound base=$base server=$server '
        'sync=${container.read(favoritesSyncControllerProvider).runtimeType}',
      );
    }

    // A device without an earlier run's lists.
    for (final l in await repo.watchLists().first) {
      for (final e in await repo.watchEntries(l.id).first) {
        await repo.remove(l.id, e.placeId);
      }
      for (final e in await repo.watchPoints(l.id).first) {
        await repo.removePointEverywhere(e.point.id);
      }
      if (!l.isDefault) await repo.deleteList(l.id);
    }
    await dump('start');

    // The place saved before the account exists, as the audit's card
    // already said "Enregistré" when the account came with a rating.
    container.read(mapFlowProvider.notifier).select(const PlaceSelection(_viviers));
    await settle(tester, const Duration(seconds: 6));
    final bar = find.byType(PlaceActionBar);
    await tester.tap(
      find.descendant(of: bar, matching: find.text(t.place.save)).hitTestable().first,
    );
    await settle(tester, const Duration(seconds: 3));
    await dump('saved');

    await container.read(accountControllerProvider.notifier).create();
    try {
      await settle(tester, const Duration(seconds: 8));
      await dump('account made');
      final later = find.text(t.common.later);
      if (later.evaluate().isNotEmpty) {
        await tester.tap(later.first);
        await settle(tester, const Duration(seconds: 1));
      }
      // The audit made its recovery card next: a fresh sign-in.
      await container.read(accountControllerProvider.notifier).createRecoveryCode();
      await settle(tester, const Duration(seconds: 5));
      await dump('recovery card');

      await tester.longPress(
        find.descendant(of: bar, matching: find.text(t.place.saved)).hitTestable().first,
      );
      await settle(tester, const Duration(seconds: 1));
      await tester.tap(find.text(t.favorites.newList).last);
      await settle(tester, const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField).last, 'Test repro');
      await tester.tap(find.widgetWithText(FilledButton, t.common.save).last);
      await settle(tester, const Duration(seconds: 1));
      await dump('new list');
      await tester.tap(find.text(t.common.done).last);
      for (var i = 0; i < 4; i++) {
        await settle(tester, const Duration(seconds: 5));
        await dump('after done +${(i + 1) * 5}s');
      }
      final defaultId = await repo.defaultListId();
      expect(
        [for (final e in await repo.watchEntries(defaultId).first) e.placeId],
        [_viviers],
        reason: 'Mes favoris keeps the place after the new list',
      );
      final mine = (await remote.lists()).firstWhere((l) => l.name == t.favorites.defaultList);
      expect(mine.placeIds, {_viviers}, reason: 'and so does the account');
    } finally {
      await container.read(accountControllerProvider.notifier).delete();
      await settle(tester, const Duration(seconds: 3));
      await dump('account deleted');
      debugPrint('FAVORITES DONE');
    }
  });
}
