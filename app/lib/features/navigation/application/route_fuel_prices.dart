import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'route_fuel_prices.g.dart';

/// The side of the cells the stations around the vehicle are read by,
/// degrees: about 5.5 km from south to north, 3.9 km from west to east in
/// France.
const double stationCell = 0.05;

/// How far past its cell the area read reaches, degrees: about 2 km, more
/// than the guidance's map shows ahead of the vehicle at the zoom of the
/// pins.
const double _margin = 0.02;

/// The area the stations around [at] are read for: its cell of
/// [stationCell] degrees grown by [_margin], the same while the vehicle
/// stays in the cell. A guidance asks again about every 4 to 5 km.
GeoBounds stationsAround(LatLng at) {
  final south = (at.lat / stationCell).floorToDouble() * stationCell;
  final west = (at.lon / stationCell).floorToDouble() * stationCell;
  return GeoBounds(
    south: south - _margin,
    west: west - _margin,
    north: south + stationCell + _margin,
    east: west + stationCell + _margin,
  );
}

/// The fuel stations around the vehicle during a guidance, with the prices
/// of the feed, as the main map reads them (`fuelStations`): those whose
/// price the guidance's map writes under their pins. The stations of the
/// cell left stay while those of the next one are read; none before the
/// first fix. The map has no place to say a read failed (offline, too many
/// stations in the area): it writes no price, the pins stay as they are.
@riverpod
class GuidanceStations extends _$GuidanceStations {
  @override
  List<Poi> build() {
    final box = ref.watch(
      guidanceControllerProvider.select(
        (s) => switch (s?.lastFix?.position) {
          final at? => stationsAround(at),
          null => null,
        },
      ),
    );
    if (box == null) return const [];
    return switch (ref.watch(fuelStationsProvider(box))) {
      AsyncData(:final value) => value ?? const [],
      AsyncError() => const [],
      _ => stateOrNull ?? const [],
    };
  }
}
