import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/domain/danger_zones.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'route_extras.g.dart';

/// The stops on the way to [target], in order, as the preview edits them.
@riverpod
class RouteStopsController extends _$RouteStopsController {
  @override
  List<RouteStop> build(RouteTarget target) => const [];

  /// The stops, [maxRouteStops] at most. An undo that comes after the
  /// preview closed (its message stays a few seconds) changes nothing.
  void set(List<RouteStop> stops) {
    if (ref.mounted) state = List.unmodifiable(stops.take(maxRouteStops));
  }
}

/// How far from the route a place still shows on its map, metres.
const placesNearRouteM = 800.0;

/// The places of the device along [line], those the user's filters keep,
/// nearest the route first: the pins of the route map, a tap from a stop.
/// Asked stretch by stretch, so a long route has its places from the start
/// to the end, not only around its middle; the first 300 km.
@riverpod
Future<List<PlaceSummary>> placesNearRoute(Ref ref, List<LatLng> line) async {
  final repository = ref.watch(placesRepositoryProvider);
  final filter = ref.watch(effectiveFilterProvider);
  final found = <String, ({PlaceSummary place, double offM})>{};
  for (final stretch in _stretches(line, metres: 15000).take(20)) {
    final box = GeoBounds.around(stretch);
    if (box == null) continue;
    // 800 m: a hundredth of a degree of latitude is 1.1 km; longitude
    // degrees shrink with the latitude.
    const padLat = placesNearRouteM / 111195;
    final padLon = padLat / math.max(0.2, math.cos(box.center.lat * math.pi / 180));
    final around = GeoBounds(
      south: box.south - padLat,
      west: box.west - padLon,
      north: box.north + padLat,
      east: box.east + padLon,
    );
    final places = await repository.watchInBounds(around, filter, center: around.center).first;
    for (final p in places) {
      final near = nearestOnLine(LatLng(p.lat, p.lon), stretch);
      if (near == null || near.offM > placesNearRouteM) continue;
      final known = found[p.id];
      if (known == null || near.offM < known.offM) found[p.id] = (place: p, offM: near.offM);
    }
  }
  final sorted = found.values.toList()..sort((a, b) => a.offM.compareTo(b.offM));
  return [for (final f in sorted.take(120)) f.place];
}

/// [line] cut into pieces of about [metres], each sharing its first point
/// with the end of the one before.
Iterable<List<LatLng>> _stretches(List<LatLng> line, {required double metres}) sync* {
  if (line.length < 2) return;
  var piece = <LatLng>[line.first];
  var length = 0.0;
  for (var i = 1; i < line.length; i++) {
    length += line[i - 1].distanceTo(line[i]);
    piece.add(line[i]);
    if (length >= metres) {
      yield piece;
      piece = [line[i]];
      length = 0;
    }
  }
  if (piece.length >= 2) yield piece;
}

/// Stations along a route; the server's search along a route replaces the
/// nearby search when it exists.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
FuelStationsSource fuelStations(Ref ref) => NearbyFuelStations(ref.watch(graphQLClientProvider));

/// What the fuel list asks for: a route, from where, which fuel.
@immutable
final class FuelQuery {
  const new({required this.line, required this.fromM, required this.fuel});

  /// The route's own list of points, compared by identity.
  final List<LatLng> line;
  final double fromM;
  final FuelType fuel;

  @override
  bool operator ==(Object other) =>
      other is FuelQuery &&
      identical(other.line, line) &&
      other.fromM == fromM &&
      other.fuel == fuel;

  @override
  int get hashCode => Object.hash(identityHashCode(line), fromM, fuel);
}

/// The stations of [query], cheapest first, the detour counted at the
/// vehicle's consumption. A failure shows at once (`noRetry`).
@Riverpod(retry: noRetry)
Future<List<FuelOffer>> fuelOffers(Ref ref, FuelQuery query) async {
  // The stored vehicle's consumption (what `vehicleFuelProvider` exposes),
  // waited for rather than taken as unknown while it loads, and watched
  // alone: another fuel or the LPG heating leaves the list alone.
  final consumption = ref.watch(vehicleProvider.selectAsync((v) => v?.consumptionL100));
  final source = ref.watch(fuelStationsProvider);
  final offers = await source.along(route: query.line, fromM: query.fromM, fuel: query.fuel);
  return rankOffers(offers, consumptionL100: await consumption ?? defaultConsumptionL100);
}

/// The stations the fuel list showed last for the route [line], drawn on
/// its map so they can be tapped there too; another route starts without.
@riverpod
class ShownFuelOffers extends _$ShownFuelOffers {
  @override
  List<FuelOffer> build(List<LatLng> line) => const [];

  void show(List<FuelOffer> offers) => state = offers;
}

/// The danger zones of a route: none until a source is chosen for the
/// countries that allow them.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
DangerZoneSource dangerZones(Ref ref) => const NoDangerZones();
