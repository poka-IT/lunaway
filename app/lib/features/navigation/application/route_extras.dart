import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/fuel_along_route.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
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
Future<List<PlaceSummary>> placesNearRoute(Ref ref, List<LatLng> line) =>
    _placesNear(ref, line, ref.watch(effectiveFilterProvider));

/// The places along [line] the guidance may show, offline: those of the
/// guidance's own choice (`GuidancePlaces`) the vehicle's height lets
/// through, whatever the main map's filters, as online it picks among the
/// tiles'; narrowed by the map's filters first, a choice of every place
/// would show online what it hides offline. Chosen before the nearest are
/// kept, so the cap leaves out none of the choice for places it hides.
@riverpod
Future<List<PlaceSummary>> guidancePlacesNearRoute(Ref ref, List<LatLng> line) {
  final selection =
      ref.watch(routeSettingsControllerProvider.select((s) => s.value?.guidancePlaces.selection)) ??
      GuidancePlaces.defaultSelection;
  return _placesNear(
    ref,
    line,
    PlaceFilter(vehicleHeightM: ref.watch(effectiveFilterProvider).vehicleHeightM),
    keep: selection.keeps,
  );
}

Future<List<PlaceSummary>> _placesNear(
  Ref ref,
  List<LatLng> line,
  PlaceFilter filter, {
  bool Function(PlaceSummary place)? keep,
}) async {
  final repository = ref.watch(placesRepositoryProvider);
  final online = ref.watch(placesFromTilesProvider) ? ref.watch(onlinePlacesProvider) : null;
  // The device's places when it holds some, the API's otherwise (the web).
  final ask = online != null && await repository.watchCount().first == 0;
  final boxes = [
    for (final stretch in _stretches(line, metres: 15000).take(20))
      if (GeoBounds.around(stretch) case final box?) (stretch: stretch, around: _padded(box)),
  ];
  final found = <String, ({PlaceSummary place, double offM})>{};
  // A few stretches at a time: the API answers each in a few tens of
  // milliseconds, and a burst of twenty would spend the client's budget.
  for (var i = 0; i < boxes.length; i += 4) {
    final batch = boxes.skip(i).take(4).toList();
    final pages = await Future.wait([
      for (final b in batch)
        if (ask)
          online
              .inBounds(b.around, filter, near: b.around.center, first: 100)
              .then((page) => page.places)
        else
          repository.watchInBounds(b.around, filter, center: b.around.center).first,
    ]);
    for (final (j, places) in pages.indexed) {
      _keepNearest(found, [
        for (final p in places)
          if (keep == null || keep(p)) p,
      ], batch[j].stretch);
    }
  }
  final sorted = found.values.toList()..sort((a, b) => a.offM.compareTo(b.offM));
  return [for (final f in sorted.take(120)) f.place];
}

/// [box] grown by [placesNearRouteM] on every side.
GeoBounds _padded(GeoBounds box) {
  // 800 m: a hundredth of a degree of latitude is 1.1 km; longitude
  // degrees shrink with the latitude.
  const padLat = placesNearRouteM / 111195;
  final padLon = padLat / math.max(0.2, math.cos(box.center.lat * math.pi / 180));
  return GeoBounds(
    south: box.south - padLat,
    west: box.west - padLon,
    north: box.north + padLat,
    east: box.east + padLon,
  );
}

/// Records each of [places] within [placesNearRouteM] of [stretch], with
/// its distance from the route, keeping the nearest stretch's.
void _keepNearest(
  Map<String, ({PlaceSummary place, double offM})> found,
  List<PlaceSummary> places,
  List<LatLng> stretch,
) {
  for (final p in places) {
    final near = nearestOnLine(LatLng(p.lat, p.lon), stretch);
    if (near == null || near.offM > placesNearRouteM) continue;
    final known = found[p.id];
    if (known == null || near.offM < known.offM) found[p.id] = (place: p, offM: near.offM);
  }
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

/// Stations along a route: the server's search along it, the nearby
/// search around points of it against an API without that search. Through
/// the routing client, which does not wait out a rate limit: the list
/// says at once that the server asks to wait.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
FuelStationsSource fuelStations(Ref ref) {
  final client = ref.watch(routingClientProvider);
  return ServerFuelStations(client, fallback: NearbyFuelStations(client));
}

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
  // The router's profile of the vehicle: the server measures the detours
  // on the roads it may take.
  final profile = ref.watch(vehicleProvider.selectAsync((v) => checkVehicle(v).profile));
  final source = ref.watch(fuelStationsProvider);
  final litres = await consumption ?? defaultConsumptionL100;
  final offers = await source.along(
    route: query.line,
    fromM: query.fromM,
    fuel: query.fuel,
    consumptionL100: litres,
    vehicle: (await profile)?.toJson(),
  );
  return rankOffers(offers, consumptionL100: litres);
}

/// The stations the fuel list showed last for the route [line], drawn on
/// its map so they can be tapped there too; another route starts without.
@riverpod
class ShownFuelOffers extends _$ShownFuelOffers {
  @override
  List<FuelOffer> build(List<LatLng> line) => const [];

  void show(List<FuelOffer> offers) => state = offers;
}
