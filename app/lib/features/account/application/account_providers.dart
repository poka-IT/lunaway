import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
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
  const new({this.lost = false});

  /// The account went without the user asking on this device.
  final bool lost;
}

final class SignedIn extends AccountState {
  const new({
    required this.account,
    this.recoveryCardAt,
    this.muted = const [],
    this.justCreated = false,
  });

  final Account account;

  /// When a recovery card was made or used on this device.
  final DateTime? recoveryCardAt;

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
      if (state is AccountLoading) state = const NoAccount();
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
        state = current is SignedIn && current.account.id == account.id
            ? current.copyWith(account: account, justCreated: current.justCreated || created)
            : SignedIn(account: account, justCreated: created);
        if (created) {
          // What the reader saw belongs to no account: the next reads come
          // with the new one's session (its own review, its mutes).
          unawaited(ref.read(placeExtrasRepositoryProvider).forgetAll());
        }
      case AccountGone(:final lost):
        state = NoAccount(lost: lost);
        unawaited(ref.read(placeExtrasRepositoryProvider).forgetAll());
    }
  }

  /// Reads the account again (its level, its mutes); quiet when offline.
  Future<void> refresh() async {
    try {
      final read = await ref.read(accountServiceProvider).refresh();
      if (!ref.mounted) return;
      final current = state;
      state = current is SignedIn
          ? current.copyWith(account: read.account, muted: read.muted)
          : SignedIn(account: read.account, muted: read.muted);
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
    if (ref.mounted) {
      state = SignedIn(account: account, recoveryCardAt: ref.read(clockProvider)());
      unawaited(refresh());
    }
    return account;
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
