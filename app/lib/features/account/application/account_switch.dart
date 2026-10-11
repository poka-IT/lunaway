import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/data/account_operations.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/outbox.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_switch.g.dart';

/// What the device does with an account it opened beside its own (the
/// profile's "use another account"): merge its own into it, take it in
/// place of its own, or give it up. Each choice moves or clears what the
/// device holds of the account it leaves before the device switches, so the
/// first sync of the new account finds the right lists, home and waiting
/// contributions.
final class AccountSwitch {
  new({
    required this.service,
    required this.outbox,
    required this.favorites,
    required this.deviceHasHome,
    required this.forgetHome,
  });

  final AccountService service;
  final OutboxStore outbox;
  final FavoritesSync favorites;

  /// Whether the device keeps a home of its own.
  final Future<bool> Function() deviceHasHome;

  /// Forgets the home kept on the device and what its sync knew of it.
  final Future<void> Function() forgetHome;

  /// Opens the account of [code] beside the device's.
  Future<ImportedAccount> import(String code) => service.importAccount(code);

  /// Whether a merge into [imported] keeps its home in place of the
  /// device's: both have one. A failure to read the imported account's
  /// counts as no home: the merge keeps its home all the same, the choice
  /// only says it less precisely.
  Future<bool> importedHomeWins(ImportedAccount imported) async {
    if (!await deviceHasHome()) return false;
    try {
      return await service.importedHasHome(imported);
    } on Object {
      return false;
    }
  }

  /// Merges the device's account (its id [currentId]) into [imported] on
  /// the server, then keeps [imported]: the contributions waiting on the
  /// device leave under it, and the device's lists and home join it at its
  /// first sync, where the imported account's home wins. Throws, the device
  /// unchanged, when the merge did not answer: asked again, the server
  /// answers the same whether it merged or not.
  Future<MergeResult> merge(ImportedAccount imported, {required String currentId}) async {
    final (target, result) = await service.mergeOnServer(imported);
    await outbox.reassign(from: currentId, to: result.account.id);
    await service.adopt(target, result.account);
    return result;
  }

  /// Takes [imported] in place of the device's account, without merging:
  /// the device's lists, home and waiting contributions go first (they are
  /// the account left's, which keeps on the server what it synced), then
  /// the device switches.
  Future<void> replace(ImportedAccount imported) async {
    await favorites.clearLocal();
    await forgetHome();
    await outbox.clear();
    await service.replaceWith(imported);
  }

  /// Gives [imported] up; the device keeps its account.
  Future<void> cancel(ImportedAccount imported) => service.cancelImport(imported);
}

// keepAlive: one switch for the run, over the services that outlive it.
@Riverpod(keepAlive: true)
AccountSwitch accountSwitch(Ref ref) => AccountSwitch(
  service: ref.watch(accountServiceProvider),
  outbox: ref.watch(outboxStoreProvider),
  favorites: ref.watch(favoritesSyncProvider),
  deviceHasHome: () async => false,
  forgetHome: () async {},
);
