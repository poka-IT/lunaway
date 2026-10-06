import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/domain/danger_zones.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'route_extras.g.dart';

/// The stops on the way to [target], in order, as the preview edits them.
@riverpod
class RouteStopsController extends _$RouteStopsController {
  @override
  List<RouteStop> build(RouteTarget target) => const [];

  /// The stops, [maxRouteStops] at most.
  void set(List<RouteStop> stops) => state = List.unmodifiable(stops.take(maxRouteStops));
}

/// How far from the route a place still shows on its map, metres.
const placesNearRouteM = 800.0;

/// The places of the device along [line], those the user's filters keep,
/// nearest the route first: the pins of the route map, a tap from a stop.
@riverpod
Stream<List<PlaceSummary>> placesNearRoute(Ref ref, List<LatLng> line) {
  final bounds = GeoBounds.around(line);
  if (bounds == null) return Stream.value(const []);
  // About 800 m around the route's box.
  const pad = 0.008;
  final around = GeoBounds(
    south: bounds.south - pad,
    west: bounds.west - pad,
    north: bounds.north + pad,
    east: bounds.east + pad,
  );
  return ref
      .watch(placesRepositoryProvider)
      .watchInBounds(around, ref.watch(effectiveFilterProvider), center: around.center, limit: 400)
      .map(
        (places) => [
          for (final p in places)
            if (nearestOnLine(LatLng(p.lat, p.lon), line) case final near?
                when near.offM <= placesNearRouteM)
              p,
        ].take(80).toList(),
      );
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
  final VehicleFuel fuel;

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
  // Both watched before the first await; the consumption only, so another
  // setting leaves the list alone.
  final consumptionFuture = ref.watch(
    routeSettingsControllerProvider.selectAsync((s) => s.consumptionL100),
  );
  final source = ref.watch(fuelStationsProvider);
  final offers = await source.along(route: query.line, fromM: query.fromM, fuel: query.fuel);
  return rankOffers(offers, consumptionL100: await consumptionFuture);
}

/// The stations the fuel list showed last, drawn on the route map so they
/// can be tapped there too.
@riverpod
class ShownFuelOffers extends _$ShownFuelOffers {
  @override
  List<FuelOffer> build() => const [];

  void show(List<FuelOffer> offers) => state = offers;
}

/// The danger zones of a route: none until a source is chosen for the
/// countries that allow them.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
DangerZoneSource dangerZones(Ref ref) => const NoDangerZones();
