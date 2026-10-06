import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// One day of a price as Lunaway saw it: its lowest and highest.
@immutable
final class FuelPriceDay {
  const new({required this.day, required this.lowEur, required this.highEur});

  /// The day, in France's time.
  final DateTime day;
  final double lowEur;
  final double highEur;
}

/// A span of days of a price: the lowest and highest, how many days were
/// seen, and the change from the first day's low to the last day's.
@immutable
final class FuelPriceSpan {
  const new({required this.lowEur, required this.highEur, required this.daysKnown, this.changeEur});

  final double lowEur;
  final double highEur;
  final int daysKnown;

  /// Null with fewer than two days known.
  final double? changeEur;
}

/// The price of one fuel at a station over the last days (`priceTrend`):
/// the days seen only, never a day the feed did not give.
@immutable
final class FuelTrend {
  const new({required this.fuel, required this.days, this.last7, this.last30});

  final String fuel;

  /// Oldest first, 30 at most.
  final List<FuelPriceDay> days;
  final FuelPriceSpan? last7;
  final FuelPriceSpan? last30;
}

FuelPriceSpan? _span(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final low = (json['lowEur'] as num?)?.toDouble();
  final high = (json['highEur'] as num?)?.toDouble();
  final days = (json['daysKnown'] as num?)?.toInt();
  if (low == null || high == null || days == null) return null;
  return FuelPriceSpan(
    lowEur: low,
    highEur: high,
    daysKnown: days,
    changeEur: (json['changeEur'] as num?)?.toDouble(),
  );
}

/// The trend of [json]; null when the server saw no price.
FuelTrend? fuelTrendFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final days = <FuelPriceDay>[];
  for (final d in json['days'] as List<dynamic>? ?? const []) {
    if (d is! Map<String, dynamic>) continue;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch('${d['day']}');
    final low = (d['lowEur'] as num?)?.toDouble();
    final high = (d['highEur'] as num?)?.toDouble();
    if (m == null || low == null || high == null) continue;
    days.add(
      FuelPriceDay(
        day: DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
        lowEur: low,
        highEur: high,
      ),
    );
  }
  return FuelTrend(
    fuel: '${json['fuel']}',
    days: days,
    last7: _span(json['last7Days']),
    last30: _span(json['last30Days']),
  );
}

const _trendFields = '''
fragment FuelTrendFields on FuelPriceTrend {
  fuel
  days { day lowEur highEur }
  last7Days { lowEur highEur daysKnown changeEur }
  last30Days { lowEur highEur daysKnown changeEur }
}
''';

/// The price of one fuel at a station over the last 30 days. Read online
/// when the station's sheet opens, never kept: prices move every quarter
/// of an hour.
final fuelTrendOperation = GraphQLOperation<FuelTrend?>(
  name: 'FuelTrend',
  document: '''
query FuelTrend(\$id: UUID!, \$fuel: FuelKind!) {
  poi(id: \$id) {
    id
    fuel { priceTrend(fuel: \$fuel) { ...FuelTrendFields } }
  }
}
$_trendFields''',
  parse: (data) {
    final poi = data['poi'];
    if (poi is! Map<String, dynamic>) return null;
    final fuel = poi['fuel'];
    return fuel is Map<String, dynamic> ? fuelTrendFromJson(fuel['priceTrend']) : null;
  },
);

/// The stations within a radius of a point that sell a fuel, those out of
/// it last, then the cheapest, then the nearest (`fuelNearby`).
final fuelNearbyOperation = GraphQLOperation<List<Map<String, dynamic>>>(
  name: 'FuelNearby',
  document: r'''
query FuelNearby($at: LatLonInput!, $fuel: FuelKind!, $radiusKm: Float!, $limit: Int!) {
  fuelNearby(at: $at, fuel: $fuel, radiusKm: $radiusKm, limit: $limit) {
    stationId
    poiId
    name
    brand
    lat
    lon
    fuel
    priceEur
    priceUpdatedAt
    shortage { kind since }
    selfService24h
    highway
    fetchedAt
  }
}
''',
  parse: (data) => [
    for (final s in data['fuelNearby'] as List<dynamic>? ?? const [])
      if (s is Map<String, dynamic>) s,
  ],
);

/// A station of `fuelNearby` as the list of the cheapest shows a station of
/// the map: its price of [fuel], its distance from [from] (measured on the
/// device, from the user's own position), the shortage the feed gives.
/// Null for a station without its position or its price, or one that
/// stopped selling the fuel.
FuelOffer? nearbyOffer(Map<String, dynamic> s, {required String fuel, required LatLng from}) {
  final lat = (s['lat'] as num?)?.toDouble();
  final lon = (s['lon'] as num?)?.toDouble();
  final price = (s['priceEur'] as num?)?.toDouble();
  final updated = DateTime.tryParse('${s['priceUpdatedAt']}');
  final fetched = DateTime.tryParse('${s['fetchedAt']}');
  if (lat == null || lon == null || price == null || updated == null || fetched == null) {
    return null;
  }
  final out = s['shortage'];
  final shortage = out is Map<String, dynamic>
      ? FuelShortage(
          fuel: fuel,
          definitive: out['kind'] == 'DEFINITIVE',
          since: DateTime.tryParse('${out['since']}'),
        )
      : null;
  if (shortage?.definitive ?? false) return null;
  final priced = FuelPrice(fuel: fuel, priceEur: price, updatedAt: updated);
  final station = Poi(
    id: s['poiId'] as String? ?? 'fuel-station:${s['stationId']}',
    kind: PoiKind.fuelStation,
    lat: lat,
    lon: lon,
    name: s['name'] as String?,
    brand: s['brand'] as String?,
    fuel: FuelInfo(
      prices: [priced],
      shortages: [?shortage],
      sellsLpg: fuel == 'LPG',
      selfService24h: s['selfService24h'] == true,
      highway: s['highway'] == true,
      fetchedAt: fetched,
    ),
  );
  return FuelOffer(
    station: station,
    price: priced,
    distanceM: station.position.distanceTo(from),
    shortage: shortage,
  );
}

/// The fuel operations of this file, for the contract test.
final fuelFeedOperations = <GraphQLOperation<Object?>>[fuelTrendOperation, fuelNearbyOperation];
