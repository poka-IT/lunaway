// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route_fuel_prices.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The fuel stations around the vehicle during a guidance, with the prices
/// of the feed, as the main map reads them (`fuelStations`): those whose
/// price the guidance's map writes under their pins. The stations of the
/// cell left stay while those of the next one are read; none before the
/// first fix. The map has no place to say a read failed (offline, too many
/// stations in the area): it writes no price, the pins stay as they are.

@ProviderFor(GuidanceStations)
final guidanceStationsProvider = GuidanceStationsProvider._();

/// The fuel stations around the vehicle during a guidance, with the prices
/// of the feed, as the main map reads them (`fuelStations`): those whose
/// price the guidance's map writes under their pins. The stations of the
/// cell left stay while those of the next one are read; none before the
/// first fix. The map has no place to say a read failed (offline, too many
/// stations in the area): it writes no price, the pins stay as they are.
final class GuidanceStationsProvider
    extends $NotifierProvider<GuidanceStations, List<Poi>> {
  /// The fuel stations around the vehicle during a guidance, with the prices
  /// of the feed, as the main map reads them (`fuelStations`): those whose
  /// price the guidance's map writes under their pins. The stations of the
  /// cell left stay while those of the next one are read; none before the
  /// first fix. The map has no place to say a read failed (offline, too many
  /// stations in the area): it writes no price, the pins stay as they are.
  GuidanceStationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guidanceStationsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceStationsHash();

  @$internal
  @override
  GuidanceStations create() => GuidanceStations();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Poi> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Poi>>(value),
    );
  }
}

String _$guidanceStationsHash() => r'73f141bf4a2938e0c8125694e22fd4b7f13e1881';

/// The fuel stations around the vehicle during a guidance, with the prices
/// of the feed, as the main map reads them (`fuelStations`): those whose
/// price the guidance's map writes under their pins. The stations of the
/// cell left stay while those of the next one are read; none before the
/// first fix. The map has no place to say a read failed (offline, too many
/// stations in the area): it writes no price, the pins stay as they are.

abstract class _$GuidanceStations extends $Notifier<List<Poi>> {
  List<Poi> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<Poi>, List<Poi>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Poi>, List<Poi>>,
              List<Poi>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
