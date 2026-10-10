// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection_trail.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The way back through the selections of the map.
// keepAlive: it follows the selection (itself kept) through tab switches and
// the screens over the map.

@ProviderFor(MapTrail)
final mapTrailProvider = MapTrailProvider._();

/// The way back through the selections of the map.
// keepAlive: it follows the selection (itself kept) through tab switches and
// the screens over the map.
final class MapTrailProvider extends $NotifierProvider<MapTrail, SelectionTrail> {
  /// The way back through the selections of the map.
  // keepAlive: it follows the selection (itself kept) through tab switches and
  // the screens over the map.
  MapTrailProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapTrailProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapTrailHash();

  @$internal
  @override
  MapTrail create() => MapTrail();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SelectionTrail value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SelectionTrail>(value),
    );
  }
}

String _$mapTrailHash() => r'd69ccec8b553ca99ffd440a574b12e154a01bbc0';

/// The way back through the selections of the map.
// keepAlive: it follows the selection (itself kept) through tab switches and
// the screens over the map.

abstract class _$MapTrail extends $Notifier<SelectionTrail> {
  SelectionTrail build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SelectionTrail, SelectionTrail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SelectionTrail, SelectionTrail>,
              SelectionTrail,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
