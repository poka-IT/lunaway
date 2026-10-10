// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'locating.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the map waits for the device's position after the user asked
/// for it (up to the map's own wait): the button shows it turning, and a
/// second tap meanwhile starts no second wait.
// keepAlive: the wait outlives the button (a layout change rebuilds it
// elsewhere), and its end must still reach the state.

@ProviderFor(Locating)
final locatingProvider = LocatingProvider._();

/// Whether the map waits for the device's position after the user asked
/// for it (up to the map's own wait): the button shows it turning, and a
/// second tap meanwhile starts no second wait.
// keepAlive: the wait outlives the button (a layout change rebuilds it
// elsewhere), and its end must still reach the state.
final class LocatingProvider extends $NotifierProvider<Locating, bool> {
  /// Whether the map waits for the device's position after the user asked
  /// for it (up to the map's own wait): the button shows it turning, and a
  /// second tap meanwhile starts no second wait.
  // keepAlive: the wait outlives the button (a layout change rebuilds it
  // elsewhere), and its end must still reach the state.
  LocatingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'locatingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$locatingHash();

  @$internal
  @override
  Locating create() => Locating();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$locatingHash() => r'049e543f9653048c83f9bc60a7eb9c2be3c3f127';

/// Whether the map waits for the device's position after the user asked
/// for it (up to the map's own wait): the button shows it turning, and a
/// second tap meanwhile starts no second wait.
// keepAlive: the wait outlives the button (a layout change rebuilds it
// elsewhere), and its end must still reach the state.

abstract class _$Locating extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
