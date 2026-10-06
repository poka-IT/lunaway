import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

/// The stations along a route, searched by the server (`fuelAlongRoute`):
/// the detours of the best of them measured by the routing engine.
final fuelAlongRouteOperation = GraphQLOperation<List<Map<String, dynamic>>>(
  name: 'FuelAlongRoute',
  document: r'''
query FuelAlongRoute($input: FuelAlongRouteInput!) {
  fuelAlongRoute(input: $input) {
    stations {
      stationId
      poiId
      name
      brand
      lat
      lon
      fuel
      priceEur
      priceUpdatedAt
      shortage { kind }
      openNow { state }
      alongKm
      detour { km minutes measured }
      effectivePriceEur
    }
  }
}
''',
  parse: (data) => [
    for (final s in (data['fuelAlongRoute'] as Map<String, dynamic>)['stations'] as List)
      if (s is Map<String, dynamic>) s,
  ],
);

/// [FuelStationsSource] through the server's search along the route
/// (`fuelAlongRoute`), and through [fallback] against an API without it.
///
/// The line sent is the route ahead as the server drew it, from its first
/// point past the vehicle: no position of the device goes with it. A line
/// over the server's limit is simplified first (5 m, as its contract
/// suggests).
final class ServerFuelStations implements FuelStationsSource {
  new(this._client, {required this.fallback});

  final GraphQLClient _client;
  final FuelStationsSource fallback;

  /// The longest polyline the server takes, characters.
  static const maxPolyline = 48000;

  /// Stations asked for: the server's ceiling.
  static const _limit = 20;

  /// The server answered that it does not know the search.
  bool _unknown = false;

  @override
  Future<List<FuelOffer>> along({
    required List<LatLng> route,
    required double fromM,
    required FuelType fuel,
    double maxDetourM = defaultMaxDetourM,
    double consumptionL100 = defaultConsumptionL100,
    Map<String, Object?>? vehicle,
  }) async {
    if (_unknown) {
      return await fallback.along(route: route, fromM: fromM, fuel: fuel, maxDetourM: maxDetourM);
    }
    final (:line, :startM) = ahead(route, fromM);
    if (line.length < 2) return const [];
    var polyline = encodePolyline(line);
    for (final tolerance in [5.0, 25.0]) {
      if (polyline.length <= maxPolyline) break;
      polyline = encodePolyline(simplifyLine(line, toleranceM: tolerance));
    }
    final List<Map<String, dynamic>> stations;
    try {
      stations = await _client.execute(fuelAlongRouteOperation, {
        'input': {
          'polyline': polyline,
          'fuel': fuel.wire,
          'maxDetourKm': (maxDetourM / 1000).clamp(0.5, 30),
          'litresPer100Km': consumptionL100.clamp(2, 50),
          'fillLitres': refillLitres,
          'limit': _limit,
          'vehicle': ?vehicle,
        },
      });
    } on GraphQLResponseException catch (e) {
      if (!e.errors.any((error) => error.unknownField)) rethrow;
      _unknown = true;
      return await fallback.along(route: route, fromM: fromM, fuel: fuel, maxDetourM: maxDetourM);
    }
    return [for (final s in stations) ?_offer(s, startM: startM, fuel: fuel)];
  }

  /// The route from its first point past [fromM], and where that point
  /// lies along the route.
  static ({List<LatLng> line, double startM}) ahead(List<LatLng> route, double fromM) {
    var along = 0.0;
    for (var i = 0; i < route.length; i++) {
      if (i > 0) along += route[i - 1].distanceTo(route[i]);
      if (along >= fromM) return (line: route.sublist(i), startM: along);
    }
    return (line: const <LatLng>[], startM: along);
  }

  static FuelOffer? _offer(
    Map<String, dynamic> s, {
    required double startM,
    required FuelType fuel,
  }) {
    // A station out of the fuel is no offer to drive to.
    if (s['shortage'] != null) return null;
    final updated = DateTime.tryParse('${s['priceUpdatedAt']}');
    final price = (s['priceEur'] as num?)?.toDouble();
    final lat = (s['lat'] as num?)?.toDouble();
    final lon = (s['lon'] as num?)?.toDouble();
    if (updated == null || price == null || lat == null || lon == null) return null;
    final detour = s['detour'] as Map<String, dynamic>?;
    final km = (detour?['km'] as num?)?.toDouble() ?? 0;
    final minutes = (detour?['minutes'] as num?)?.toDouble() ?? 0;
    final poi = s['poiId'] as String?;
    final station = '${s['stationId']}';
    return FuelOffer(
      id: poi ?? 'fuel-station:$station',
      poiId: poi,
      stationId: station,
      name: s['name'] as String?,
      brand: s['brand'] as String?,
      position: LatLng(lat, lon),
      priceEur: price,
      priceUpdatedAt: updated,
      detourM: km * 1000,
      detourS: minutes * 60,
      alongM: startM + ((s['alongKm'] as num?)?.toDouble() ?? 0) * 1000,
      fuel: fuel,
      open: switch ((s['openNow'] as Map<String, dynamic>?)?['state']) {
        'OPEN' => StationOpen.open,
        'CLOSED' => StationOpen.closed,
        _ => StationOpen.unknown,
      },
      detourEstimated: detour?['measured'] != true,
    );
  }
}
