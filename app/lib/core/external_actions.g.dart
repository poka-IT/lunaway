// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'external_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(externalActions)
final externalActionsProvider = ExternalActionsProvider._();

final class ExternalActionsProvider
    extends
        $FunctionalProvider<ExternalActions, ExternalActions, ExternalActions>
    with $Provider<ExternalActions> {
  ExternalActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'externalActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$externalActionsHash();

  @$internal
  @override
  $ProviderElement<ExternalActions> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ExternalActions create(Ref ref) {
    return externalActions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExternalActions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExternalActions>(value),
    );
  }
}

String _$externalActionsHash() => r'9f9829aebce70d30849da45ec29f7d46276fa920';
