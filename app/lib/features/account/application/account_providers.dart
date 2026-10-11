import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_switch.dart';
import 'package:lunaway/features/account/data/account_operations.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/device_keys_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/account/data/device_keys_web.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_providers.g.dart';

final _log = Logger('account');

// keepAlive: the system's protected storage, one handle for the run.
@Riverpod(keepAlive: true)
SecretStore secretStore(Ref ref) => const PlatformSecretStore();

// keepAlive: the device key's store, one for the run.
@Riverpod(keepAlive: true)
DeviceKeys deviceKeys(Ref ref) => platformDeviceKeys(ref.watch(secretStoreProvider));

// keepAlive: holds the session and serialises the sign-ins of the run.
@Riverpod(keepAlive: true)
AccountService accountService(Ref ref) {
  final service = AccountService(
    client: ref.watch(graphQLClientProvider),
    keys: ref.watch(deviceKeysProvider),
    secrets: ref.watch(secretStoreProvider),
    locale: () => LocaleSettings.currentLocale.languageCode,
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Where the account of this device stands.
@immutable
sealed class AccountState {
  const new();
}

/// Read from the protected storage at start.
final class AccountLoading extends AccountState {
  const new();
}

/// No account on this device: browsing needs none, the first contribution
/// makes one.
final class NoAccount extends AccountState {
  const new({this.lost = false, this.mergedInto});

  /// The account went without the user asking on this device.
  final bool lost;

  /// The pseudonym of the account it went into, merged from another
  /// device: that account's recovery card brings it here.
  final String? mergedInto;
}

final class SignedIn extends AccountState {
  const new({
    required this.account,
    this.recoveryCardAt,
    this.recoveryCardChecked = false,
    this.muted = const [],
    this.justCreated = false,
  });

  final Account account;

  /// When the account's recovery card was made: the server's date once
  /// read, else the one this device kept (a card made or used here),
  /// offline or with an API older than that date.
  final DateTime? recoveryCardAt;

  /// The server said, this run, whether the account has a recovery card:
  /// without a date, then, the account has none on any device.
  final bool recoveryCardChecked;

  /// The authors the account mutes, as last read.
  final List<Author> muted;

  /// This run made the account (its first contribution): the profile
  /// welcomes it and suggests the recovery card.
  final bool justCreated;

  SignedIn copyWith({
    Account? account,
    DateTime? recoveryCardAt,
    List<Author>? muted,
    bool? justCreated,
  }) => SignedIn(
    account: account ?? this.account,
    recoveryCardAt: recoveryCardAt ?? this.recoveryCardAt,
    recoveryCardChecked: recoveryCardChecked,
    muted: muted ?? this.muted,
    justCreated: justCreated ?? this.justCreated,
  );
}

/// The account of this device and what can be done with it. The account
/// changes underneath when a contribution makes it, when a session is
/// renewed, or when it goes: the service says so, and this state follows.
// keepAlive: the account shapes the profile, the place sheet and the
// outbox for the whole run.
@Riverpod(keepAlive: true)
class AccountController extends _$AccountController {
  @override
  AccountState build() {
    final service = ref.watch(accountServiceProvider);
    final events = service.events.listen(_onEvent);
    ref.onDispose(events.cancel);
    unawaited(_restore(service));
    return const AccountLoading();
  }

  Future<void> _restore(AccountService service) async {
    final StoredAccount? stored;
    try {
      stored = await service.restore();
    } on Object catch (e) {
      // The device's storage failed (IndexedDB refused on the web): the
      // profile shows no account rather than a loading state for ever.
      _log.warning('account not read: $e');
      if (ref.mounted && state is AccountLoading) state = const NoAccount();
      return;
    }
    if (!ref.mounted) return;
    if (stored == null) {
      // An account merged into another, since: the profile keeps saying
      // where it went until that account comes here.
      final merged = await service.mergedFrom();
      if (ref.mounted && state is AccountLoading) state = NoAccount(mergedInto: merged?.into);
      return;
    }
    state = SignedIn(account: stored.account, recoveryCardAt: stored.recoveryCardAt);
    // The level and the mutes may have moved since the last run; offline,
    // the stored account stays.
    unawaited(refresh());
  }

  void _onEvent(AccountEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case AccountSignedIn(:final account, :final created):
        final current = state;
        final same = current is SignedIn && current.account.id == account.id;
        state = same
            ? current.copyWith(account: account, justCreated: current.justCreated || created)
            : SignedIn(account: account, justCreated: created);
        if (created || (current is SignedIn && !same)) {
          // What the reader saw belongs to no account, or to the one the
          // device left: the next reads come with the new one's session
          // (its own review, its mutes).
          unawaited(ref.read(placeExtrasRepositoryProvider).forgetAll());
        }
      case AccountGone(:final lost, :final mergedInto):
        state = NoAccount(lost: lost, mergedInto: mergedInto);
        unawaited(ref.read(placeExtrasRepositoryProvider).forgetAll());
    }
  }

  /// Reads the account again (its level, its mutes); quiet when offline.
  Future<void> refresh() async {
    try {
      final read = await ref.read(accountServiceProvider).refresh();
      if (!ref.mounted) return;
      final current = state;
      final card = read.recoveryCode;
      state = current is SignedIn
          ? SignedIn(
              account: read.account,
              muted: read.muted,
              recoveryCardAt: card == null ? current.recoveryCardAt : card.createdAt,
              recoveryCardChecked: card != null || current.recoveryCardChecked,
              justCreated: current.justCreated,
            )
          : SignedIn(
              account: read.account,
              muted: read.muted,
              recoveryCardAt: card?.createdAt,
              recoveryCardChecked: card != null,
            );
    } on NoAccountException {
      if (ref.mounted) state = const NoAccount();
    } on Object catch (e) {
      _log.info('account not refreshed: $e');
    }
  }

  /// The welcome after the first contribution has been seen.
  void welcomed() {
    final current = state;
    if (current is SignedIn && current.justCreated) state = current.copyWith(justCreated: false);
  }

  /// Makes the account now (the user asked to sync their favourites).
  Future<Account> create() => ref.read(accountServiceProvider).ensureAccount();

  Future<void> rename(String pseudonym) async {
    await ref.read(accountServiceProvider).rename(pseudonym);
  }

  /// A new recovery code, to show once. The earlier card stops working;
  /// the profile shows the new card's date from now on.
  Future<String> createRecoveryCode() async {
    final (code, at) = await ref.read(accountServiceProvider).createRecoveryCode();
    final current = state;
    if (ref.mounted && current is SignedIn) state = current.copyWith(recoveryCardAt: at);
    return code;
  }

  Future<Account> recover(String code, {required bool revokeOthers}) async {
    final account = await ref
        .read(accountServiceProvider)
        .recover(code, revokeOthers: revokeOthers);
    // The account the device's went into, from elsewhere: what waited for
    // it leaves under it.
    await ref.read(accountSwitchProvider).claimMerged(account);
    if (ref.mounted) {
      state = SignedIn(account: account, recoveryCardAt: ref.read(clockProvider)());
      unawaited(refresh());
    }
    return account;
  }

  /// Opens the account of [code] beside the device's own, for the user to
  /// choose what becomes of the two ([merge], [replace], [cancelImport]).
  Future<ImportedAccount> importAccount(String code) =>
      ref.read(accountSwitchProvider).import(code);

  /// Merges the device's account into [imported], which the device keeps.
  /// The caller holds the favourites' sync meanwhile
  /// (`FavoritesSyncController.holding`): none runs under the account
  /// merged.
  Future<MergeResult> merge(ImportedAccount imported) async {
    final current = state;
    if (current is! SignedIn) throw const NoAccountException();
    final result = await ref
        .read(accountSwitchProvider)
        .merge(imported, currentId: current.account.id);
    _imported(result.account);
    return result;
  }

  /// After a merge whose answer did not come: finishes it when the server
  /// made it (true), else leaves everything as it was (false). Throws while
  /// the server does not answer.
  Future<bool> settleImport(ImportedAccount imported) async {
    final current = state;
    if (current is! SignedIn) return false;
    final landed = await ref
        .read(accountSwitchProvider)
        .settle(imported, currentId: current.account.id);
    if (landed) _imported(imported.account);
    return landed;
  }

  /// Takes [imported] in place of the device's account, without merging.
  /// The caller holds the favourites' sync meanwhile: none runs under the
  /// account left while its lists leave the device.
  Future<void> replace(ImportedAccount imported) async {
    await ref.read(accountSwitchProvider).replace(imported);
    _imported(imported.account);
  }

  /// Gives [imported] up; the device keeps its account.
  Future<void> cancelImport(ImportedAccount imported) =>
      ref.read(accountSwitchProvider).cancel(imported);

  /// The device now holds [account], whose card was just used here.
  void _imported(Account account) {
    if (!ref.mounted) return;
    state = SignedIn(account: account, recoveryCardAt: ref.read(clockProvider)());
    unawaited(refresh());
  }

  Future<void> signOut() => ref.read(accountServiceProvider).signOut();

  /// Deletes the account on the server. Its ratings without text, photos
  /// and reports leave the places they were on: a sync brings the new
  /// summaries.
  Future<void> delete() async {
    await ref.read(accountServiceProvider).deleteAccount();
    if (ref.mounted) ref.read(syncControllerProvider.notifier).syncAfterContribution();
  }

  /// Changes the mutes shown at once, before the server confirms them.
  void showMuted(List<Author> muted) {
    final current = state;
    if (current is SignedIn) state = current.copyWith(muted: muted);
  }
}

/// The level of the device's account; 0 without one (the level a new
/// account starts at).
@riverpod
int trustLevel(Ref ref) => switch (ref.watch(accountControllerProvider)) {
  SignedIn(:final account) => account.trustLevel,
  _ => 0,
};

/// The devices of the account, read online.
@Riverpod(retry: noRetry)
Future<List<Device>> accountDevices(Ref ref) => ref.watch(accountServiceProvider).devices();
