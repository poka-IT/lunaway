// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(secretStore)
final secretStoreProvider = SecretStoreProvider._();

final class SecretStoreProvider
    extends $FunctionalProvider<SecretStore, SecretStore, SecretStore>
    with $Provider<SecretStore> {
  SecretStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secretStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secretStoreHash();

  @$internal
  @override
  $ProviderElement<SecretStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SecretStore create(Ref ref) {
    return secretStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SecretStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SecretStore>(value),
    );
  }
}

String _$secretStoreHash() => r'c7f682ecf4d083d7d0e657b9395ba61bcffe0916';

@ProviderFor(deviceKeys)
final deviceKeysProvider = DeviceKeysProvider._();

final class DeviceKeysProvider
    extends $FunctionalProvider<DeviceKeys, DeviceKeys, DeviceKeys>
    with $Provider<DeviceKeys> {
  DeviceKeysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceKeysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceKeysHash();

  @$internal
  @override
  $ProviderElement<DeviceKeys> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeviceKeys create(Ref ref) {
    return deviceKeys(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceKeys value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceKeys>(value),
    );
  }
}

String _$deviceKeysHash() => r'8a0b97f520f44fbf84183b7c7ea002d7d2a5fc9c';

@ProviderFor(accountService)
final accountServiceProvider = AccountServiceProvider._();

final class AccountServiceProvider
    extends $FunctionalProvider<AccountService, AccountService, AccountService>
    with $Provider<AccountService> {
  AccountServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountServiceHash();

  @$internal
  @override
  $ProviderElement<AccountService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AccountService create(Ref ref) {
    return accountService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccountService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccountService>(value),
    );
  }
}

String _$accountServiceHash() => r'0080d6f3a18ac3d4212d08979e56ac13a252e2d8';

/// The account of this device and what can be done with it. The account
/// changes underneath when a contribution makes it, when a session is
/// renewed, or when it goes: the service says so, and this state follows.
// keepAlive: the account shapes the profile, the place sheet and the
// outbox for the whole run.

@ProviderFor(AccountController)
final accountControllerProvider = AccountControllerProvider._();

/// The account of this device and what can be done with it. The account
/// changes underneath when a contribution makes it, when a session is
/// renewed, or when it goes: the service says so, and this state follows.
// keepAlive: the account shapes the profile, the place sheet and the
// outbox for the whole run.
final class AccountControllerProvider
    extends $NotifierProvider<AccountController, AccountState> {
  /// The account of this device and what can be done with it. The account
  /// changes underneath when a contribution makes it, when a session is
  /// renewed, or when it goes: the service says so, and this state follows.
  // keepAlive: the account shapes the profile, the place sheet and the
  // outbox for the whole run.
  AccountControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountControllerHash();

  @$internal
  @override
  AccountController create() => AccountController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccountState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccountState>(value),
    );
  }
}

String _$accountControllerHash() => r'3cc1cf7af9564c9536468965c00781db2d287192';

/// The account of this device and what can be done with it. The account
/// changes underneath when a contribution makes it, when a session is
/// renewed, or when it goes: the service says so, and this state follows.
// keepAlive: the account shapes the profile, the place sheet and the
// outbox for the whole run.

abstract class _$AccountController extends $Notifier<AccountState> {
  AccountState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AccountState, AccountState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AccountState, AccountState>,
              AccountState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The level of the device's account; 0 without one (the level a new
/// account starts at).

@ProviderFor(trustLevel)
final trustLevelProvider = TrustLevelProvider._();

/// The level of the device's account; 0 without one (the level a new
/// account starts at).

final class TrustLevelProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// The level of the device's account; 0 without one (the level a new
  /// account starts at).
  TrustLevelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trustLevelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trustLevelHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return trustLevel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$trustLevelHash() => r'afaaf032082b256ea4af2ae6e70cd225a082bb72';

/// The devices of the account, read online.

@ProviderFor(accountDevices)
final accountDevicesProvider = AccountDevicesProvider._();

/// The devices of the account, read online.

final class AccountDevicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Device>>,
          List<Device>,
          FutureOr<List<Device>>
        >
    with $FutureModifier<List<Device>>, $FutureProvider<List<Device>> {
  /// The devices of the account, read online.
  AccountDevicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'accountDevicesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountDevicesHash();

  @$internal
  @override
  $FutureProviderElement<List<Device>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Device>> create(Ref ref) {
    return accountDevices(ref);
  }
}

String _$accountDevicesHash() => r'0bdd03c3583509c6980bfb4e3e794351363d5edb';
