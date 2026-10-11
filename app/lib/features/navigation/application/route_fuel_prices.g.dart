// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route_fuel_prices.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The fuel stations around the vehicle during a guidance, with the prices
/// of the feed, as the main map reads them (`fuelStations`): those whose
/// price the guidance's map writes under their pins. None before the first
/// fix, and none for an area that holds more stations than are read: a
/// part of them would rank as the cheapest without being so. Read again
/// only in the next cell: a read that failed (a tunnel, offline) leaves the
/// cell without prices, the map keeping those of the cell before.
// A failure shows nowhere but in the prices missing: no retry here.

@ProviderFor(guidanceStations)
final guidanceStationsProvider = GuidanceStationsProvider._();

/// The fuel stations around the vehicle during a guidance, with the prices
/// of the feed, as the main map reads them (`fuelStations`): those whose
/// price the guidance's map writes under their pins. None before the first
/// fix, and none for an area that holds more stations than are read: a
/// part of them would rank as the cheapest without being so. Read again
/// only in the next cell: a read that failed (a tunnel, offline) leaves the
/// cell without prices, the map keeping those of the cell before.
// A failure shows nowhere but in the prices missing: no retry here.

final class GuidanceStationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Poi>>,
          List<Poi>,
          FutureOr<List<Poi>>
        >
    with $FutureModifier<List<Poi>>, $FutureProvider<List<Poi>> {
  /// The fuel stations around the vehicle during a guidance, with the prices
  /// of the feed, as the main map reads them (`fuelStations`): those whose
  /// price the guidance's map writes under their pins. None before the first
  /// fix, and none for an area that holds more stations than are read: a
  /// part of them would rank as the cheapest without being so. Read again
  /// only in the next cell: a read that failed (a tunnel, offline) leaves the
  /// cell without prices, the map keeping those of the cell before.
  // A failure shows nowhere but in the prices missing: no retry here.
  GuidanceStationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'guidanceStationsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guidanceStationsHash();

  @$internal
  @override
  $FutureProviderElement<List<Poi>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Poi>> create(Ref ref) {
    return guidanceStations(ref);
  }
}

String _$guidanceStationsHash() => r'9e1fae79a51f70ba0b6be6adfaf90c9b13e70287';
