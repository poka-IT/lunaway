// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_history.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mapHistory)
final mapHistoryProvider = MapHistoryProvider._();

final class MapHistoryProvider
    extends $FunctionalProvider<MapHistory, MapHistory, MapHistory>
    with $Provider<MapHistory> {
  MapHistoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapHistoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapHistoryHash();

  @$internal
  @override
  $ProviderElement<MapHistory> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MapHistory create(Ref ref) {
    return mapHistory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapHistory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapHistory>(value),
    );
  }
}

String _$mapHistoryHash() => r'dd50531d4d3a8601658192f83e4d954536e00000';
