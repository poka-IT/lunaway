import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

/// The fuel stations around a point, with their prices and whether they
/// are open now (`nearbyPois`).
final fuelNearOperation = GraphQLOperation<List<Map<String, dynamic>>>(
  name: 'FuelNear',
  document: r'''
query FuelNear($at: LatLonInput!, $radiusM: Float!) {
  nearbyPois(at: $at, categories: [FUEL], kinds: [FUEL_STATION], perCategory: 10, radiusM: $radiusM) {
    pois {
      id
      name
      brand
      lat
      lon
      openNow { state }
      fuel {
        prices { fuel priceEur updatedAt }
        shortages { fuel kind }
      }
    }
  }
}
''',
  parse: (data) => [
    for (final group in data['nearbyPois'] as List? ?? const [])
      if (group is Map<String, dynamic>)
        for (final poi in group['pois'] as List? ?? const [])
          if (poi is Map<String, dynamic>) poi,
  ],
);

/// [FuelStationsSource] until the server searches along a route: the
/// stations around a few points of the route ahead, their detour reckoned
/// from their distance to it (there and back, a third longer by road, at
/// 50 km/h). Marked as estimated. The server gives the 10 nearest stations
/// of each point (`perCategory` at most): in a town, a cheaper one a little
/// further can be left out.
final class NearbyFuelStations implements FuelStationsSource {
  new(this._client);

  final GraphQLClient _client;

  /// Points asked along the route, this far apart, so many: the 40 km
  /// ahead.
  static const _spacingM = 8000.0;
  static const _samples = 5;

  /// The points leave the device rounded to the hundredth of a degree: about
  /// a kilometre, 790 m off at most (on the equator; 720 m in the south of
  /// Spain). The stations within 5 km of the true point are still within
  /// this radius of the rounded one.
  static const _radiusM = 5800.0;
  static const _roadFactor = 1.3;
  static const double _detourSpeedMps = 50 / 3.6;

  @override
  Future<List<FuelOffer>> along({
    required List<LatLng> route,
    required double fromM,
    required FuelType fuel,
    double maxDetourM = defaultMaxDetourM,
    double consumptionL100 = defaultConsumptionL100,
    Map<String, Object?>? vehicle,
  }) async {
    final points = [for (var i = 0; i < _samples; i++) ?_pointAt(route, fromM + i * _spacingM)];
    final answers = await Future.wait([
      for (final p in points)
        _client.execute(fuelNearOperation, {
          'at': {'lat': _rounded(p.lat), 'lon': _rounded(p.lon)},
          'radiusM': _radiusM,
        }),
    ]);
    final seen = <String>{};
    final offers = <FuelOffer>[];
    for (final poi in answers.expand((a) => a)) {
      final id = '${poi['id']}';
      if (!seen.add(id)) continue;
      final offer = _offer(poi, route: route, fromM: fromM, fuel: fuel);
      if (offer != null && offer.detourM <= maxDetourM) offers.add(offer);
    }
    return offers;
  }

  static FuelOffer? _offer(
    Map<String, dynamic> poi, {
    required List<LatLng> route,
    required double fromM,
    required FuelType fuel,
  }) {
    final info = poi['fuel'];
    if (info is! Map<String, dynamic>) return null;
    final out = [
      for (final s in info['shortages'] as List? ?? const [])
        if (s is Map<String, dynamic> && s['fuel'] == fuel.wire) s,
    ];
    if (out.isNotEmpty) return null;
    final price = [
      for (final p in info['prices'] as List? ?? const [])
        if (p is Map<String, dynamic> && p['fuel'] == fuel.wire) p,
    ].firstOrNull;
    final updated = DateTime.tryParse('${price?['updatedAt']}');
    final euros = (price?['priceEur'] as num?)?.toDouble();
    if (euros == null || updated == null) return null;
    final position = LatLng((poi['lat'] as num).toDouble(), (poi['lon'] as num).toDouble());
    final near = nearestOnLine(position, route);
    if (near == null || near.alongM < fromM - 200) return null;
    final detourM = 2 * near.offM * _roadFactor;
    final open = switch ((poi['openNow'] as Map<String, dynamic>?)?['state']) {
      'OPEN' => StationOpen.open,
      'CLOSED' => StationOpen.closed,
      _ => StationOpen.unknown,
    };
    return FuelOffer(
      id: '${poi['id']}',
      poiId: '${poi['id']}',
      name: poi['name'] as String?,
      brand: poi['brand'] as String?,
      position: position,
      priceEur: euros,
      priceUpdatedAt: updated,
      detourM: detourM,
      detourS: detourM / _detourSpeedMps,
      alongM: near.alongM,
      fuel: fuel,
      open: open,
      detourEstimated: true,
    );
  }

  static double _rounded(double degrees) => (degrees * 100).round() / 100;

  /// The point [metres] along [line], null past its end.
  static LatLng? _pointAt(List<LatLng> line, double metres) {
    var along = 0.0;
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1];
      final b = line[i];
      final d = a.distanceTo(b);
      if (along + d >= metres) {
        final t = d == 0 ? 0.0 : math.max(0, metres - along) / d;
        return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      }
      along += d;
    }
    return null;
  }
}
