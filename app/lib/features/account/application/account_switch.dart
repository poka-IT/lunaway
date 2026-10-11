import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/data/account_operations.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/domain/account.dart';
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

  /// The merge under way, which a choice made meanwhile waits for.
  Future<MergeResult>? _merging;

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
    final running = _merge(imported, currentId);
    _merging = running;
    try {
      return await running;
    } finally {
      if (identical(_merging, running)) _merging = null;
    }
  }

  Future<MergeResult> _merge(ImportedAccount imported, String currentId) async {
    if (!identical(_landed?.imported, imported)) {
      final (target, result) = await service.mergeOnServer(imported);
      _landed = _Landed(imported: imported, target: target, result: result);
    }
    return await _finish(currentId);
  }

  /// A merge the server made that the device has not finished.
  _Landed? _landed;

  /// Finishes on the device the merge the server made ([_landed]): what
  /// waits moves to the account kept, which the device then holds. Its
  /// failure (the device's storage refused) leaves the merge to finish at
  /// the next try, from here: never by asking the server again with keys
  /// the device may have half switched.
  Future<MergeResult> _finish(String currentId) async {
    final landed = _landed!;
    try {
      await outbox.reassign(from: currentId, to: landed.result.account.id);
      await service.adopt(landed.target, landed.result.account);
    } on Object catch (e) {
      throw MergeUnsettledException(e, onDevice: true);
    }
    _landed = null;
    return landed.result;
  }

  /// After a merge whose answer did not come: when the server made it, the
  /// device finishes it as [merge] would and returns true; when it did
  /// not, returns false and nothing changed. Throws while the server does
  /// not answer.
  Future<bool> settle(ImportedAccount imported, {required String currentId}) async {
    await _waitForMerge();
    if (!identical(_landed?.imported, imported)) {
      if (!await service.mergeLanded(imported)) return false;
      _landed = _Landed(
        imported: imported,
        target: imported,
        // What became of the home is not known here, and nothing reads it.
        result: (account: imported.account, home: MergedHome.none),
      );
    }
    await _finish(currentId);
    return true;
  }

  /// The device's key left its account for [replace], which did not end:
  /// only the replacement can finish what it began.
  bool get left => service.left;

  /// Takes [imported] in place of the device's account, without merging:
  /// the device leaves the account first (its key detached on the server,
  /// which throws, nothing changed, when the server does not answer); then
  /// the device's lists, home and waiting contributions go (they are the
  /// account left's, which keeps on the server what it synced), and the
  /// device switches.
  Future<void> replace(ImportedAccount imported) async {
    final running = _replace(imported);
    _replacing = running;
    try {
      await running;
    } finally {
      if (identical(_replacing, running)) _replacing = null;
    }
  }

  Future<void> _replace(ImportedAccount imported) async {
    await service.leaveForReplace();
    await favorites.clearLocal();
    await forgetHome();
    await outbox.clear();
    await service.adopt(imported, imported.account);
  }

  /// Gives [imported] up; the device keeps its account. A merge under way
  /// ends first: given up after it landed, the import is the device's and
  /// stays.
  Future<void> cancel(ImportedAccount imported) async {
    await quiet();
    if (identical(_landed?.imported, imported)) _landed = null;
    await service.cancelImport(imported);
  }

  /// Once no merge nor replacement is under way.
  Future<void> quiet() async {
    await _waitForMerge();
    await _waitForReplace();
  }

  Future<void> _waitForMerge() async {
    try {
      await _merging;
    } on Object {
      // Its failure is the sheet's to show.
    }
  }

  /// The replacement under way, which giving up waits for.
  Future<void>? _replacing;

  Future<void> _waitForReplace() async {
    try {
      await _replacing;
    } on Object {
      // Its failure is the sheet's to show.
    }
  }

  /// The id of the account whose contributions wait for a merge to end on
  /// the device: moved to it, while the device still holds the account
  /// merged. Null otherwise.
  String? get landing => _landed?.result.account.id;

  /// [account] came to this device: when it is the account the device's
  /// went into from elsewhere, the contributions that waited for it leave
  /// under it; when it is another, made or opened here instead, they never
  /// leave, as any other account's (the outbox fails them). Whether
  /// contributions were handed over.
  Future<bool> claimMerged(Account account) async {
    final merged = await service.mergedFrom();
    if (merged == null) return false;
    final claimed = merged.intoId == account.id;
    if (claimed) await outbox.reassign(from: merged.from, to: account.id);
    await service.forgetMergedFrom();
    return claimed;
  }
}

/// A merge the server made that the device has not finished.
final class _Landed {
  const new({required this.imported, required this.target, required this.result});

  final ImportedAccount imported;

  /// The imported account with the session the merge was made under.
  final ImportedAccount target;
  final MergeResult result;
}

// keepAlive: one switch for the run, over the services that outlive it.
@Riverpod(keepAlive: true)
AccountSwitch accountSwitch(Ref ref) => AccountSwitch(
  service: ref.watch(accountServiceProvider),
  outbox: ref.watch(outboxStoreProvider),
  favorites: ref.watch(favoritesSyncProvider),
  deviceHasHome: () async => await ref.read(homeRepositoryProvider).read() != null,
  forgetHome: () => ref.read(homeRepositoryProvider).clearLocal(),
);
