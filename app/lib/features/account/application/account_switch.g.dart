// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_switch.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(accountSwitch)
final accountSwitchProvider = AccountSwitchProvider._();

final class AccountSwitchProvider
    extends $FunctionalProvider<AccountSwitch, AccountSwitch, AccountSwitch>
    with $Provider<AccountSwitch> {
  AccountSwitchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountSwitchProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountSwitchHash();

  @$internal
  @override
  $ProviderElement<AccountSwitch> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AccountSwitch create(Ref ref) {
    return accountSwitch(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccountSwitch value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccountSwitch>(value),
    );
  }
}

String _$accountSwitchHash() => r'75ded9c6035e90a7cf76bc33e362471e5ce8960c';
