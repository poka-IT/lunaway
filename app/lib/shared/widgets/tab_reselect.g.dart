// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tab_reselect.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The destination of the shell tapped while it was already the current
/// one, counted so that a second tap on the same one is news again.
// keepAlive: the shell writes it whether or not a screen listens yet.

@ProviderFor(TabReselect)
final tabReselectProvider = TabReselectProvider._();

/// The destination of the shell tapped while it was already the current
/// one, counted so that a second tap on the same one is news again.
// keepAlive: the shell writes it whether or not a screen listens yet.
final class TabReselectProvider
    extends $NotifierProvider<TabReselect, ({int count, int tab})> {
  /// The destination of the shell tapped while it was already the current
  /// one, counted so that a second tap on the same one is news again.
  // keepAlive: the shell writes it whether or not a screen listens yet.
  TabReselectProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tabReselectProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tabReselectHash();

  @$internal
  @override
  TabReselect create() => TabReselect();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({int count, int tab}) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<({int count, int tab})>(value),
    );
  }
}

String _$tabReselectHash() => r'25e9f64aae3b041f54ffb5068a4fbe3528b42359';

/// The destination of the shell tapped while it was already the current
/// one, counted so that a second tap on the same one is news again.
// keepAlive: the shell writes it whether or not a screen listens yet.

abstract class _$TabReselect extends $Notifier<({int count, int tab})> {
  ({int count, int tab}) build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<({int count, int tab}), ({int count, int tab})>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<({int count, int tab}), ({int count, int tab})>,
              ({int count, int tab}),
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
