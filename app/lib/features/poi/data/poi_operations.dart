import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

/// What a list row of a point needs: its kind, its name, its distance and
/// its hours, which the device reads offline for 14 days.
const _poiRowFields = '''
fragment PoiRowFields on Poi {
  id
  kind
  name
  brand
  lat
  lon
  distanceM
  alwaysOpen
  openingHoursParsed
  openingIntervals { start end }
  openingIntervalsUntil
  lpg
}
''';

/// Everything the page of a point shows.
const _poiPageFields = '''
fragment PoiPageFields on Poi {
  ...PoiRowFields
  operator
  address { street postcode city countryCode }
  phone
  website
  openingHours
  products
  payment
  fuel {
    prices { fuel priceEur updatedAt }
    shortages { fuel kind since }
    sellsLpg
    selfService24h
    highway
    fetchedAt
  }
  reportedClosed { closedOn fetchedAt }
  seasonal
  fee
  selfService
  wheelchair
  checkedOn
  lastConfirmedAt
  sources { sourceId externalId externalUrl fetchedAt }
}
''';

/// "Around this place": the three nearest points of each category, so the
/// row can prefer one open now (or one open around the clock at night) to
/// the nearest closed one.
final nearbyPoisOperation = GraphQLOperation<List<NearbyPois>>(
  name: 'NearbyPois',
  document: '''
query NearbyPois(\$placeId: UUID, \$at: LatLonInput, \$perCategory: Int) {
  nearbyPois(placeId: \$placeId, at: \$at, perCategory: \$perCategory) {
    category
    radiusM
    pois { ...PoiRowFields }
  }
}
$_poiRowFields''',
  parse: (data) => nearbyPoisFromJson(data['nearbyPois']),
);

Map<String, Object?> nearbyPoisVariables({String? placeId, LatLng? at, int perCategory = 3}) => {
  'placeId': ?placeId,
  if (at != null) 'at': {'lat': at.lat, 'lon': at.lon},
  'perCategory': perCategory,
};

/// One point, with the sources the page names (their licences and
/// attributions come with `sources`).
const poiOperation = GraphQLOperation<PoiPage?>(
  name: 'PoiPage',
  document: '''
query PoiPage(\$id: UUID!) {
  poi(id: \$id) { ...PoiPageFields }
  sources { id name licence attribution url }
}
$_poiRowFields$_poiPageFields''',
  parse: poiPageFromJson,
);

/// A point and the sources it names (their licences and attributions).
typedef PoiPage = ({Poi poi, List<Source> sources});

PoiPage? poiPageFromJson(Map<String, dynamic> data) {
  final poi = poiFromJson(data['poi']);
  if (poi == null) return null;
  final ids = {for (final s in poi.sources) s.sourceId};
  final sources = [
    for (final s in (data['sources'] as List<dynamic>? ?? const []))
      if (s is Map<String, dynamic> && ids.contains(s['id'])) sourceFromJson(s),
  ];
  return (poi: poi, sources: sources);
}

/// Names and brands of points, nearest to `near` first among equal matches.
final searchPoisOperation = GraphQLOperation<List<Poi>>(
  name: 'SearchPois',
  document: '''
query SearchPois(\$text: String!, \$near: LatLonInput, \$first: Int) {
  searchPois(text: \$text, near: \$near, first: \$first) { ...PoiRowFields }
}
$_poiRowFields''',
  parse: (data) => [for (final p in data['searchPois'] as List<dynamic>) ?poiFromJson(p)],
);

/// Where a search ranks from, as it leaves the device: [point] on a grid of
/// [searchGrid] degrees (about 5 km), enough to rank equal matches by
/// distance, never a precise position. The same point for a whole cell, so
/// a map that moves a little asks nothing new.
LatLng searchAnchor(LatLng point) {
  double snap(double v) =>
      double.parse(((v / searchGrid).roundToDouble() * searchGrid).toStringAsFixed(2));
  return LatLng(snap(point.lat), snap(point.lon));
}

const searchGrid = 0.05;

Map<String, Object?> searchPoisVariables(String text, {LatLng? near, int first = 8}) {
  final anchor = near == null ? null : searchAnchor(near);
  return {
    'text': text,
    if (anchor != null) 'near': {'lat': anchor.lat, 'lon': anchor.lon},
    'first': first,
  };
}

/// A page of the fuel points of an area: the stations with the prices of
/// the feed, and where the next page starts.
typedef FuelStationsPage = ({List<Poi> stations, String? endCursor, bool hasNextPage});

/// The fuel stations of an area with the prices of the feed: the labels of
/// the map and the cheapest stations around, while the fuel chip is on.
/// The category also holds charging points and gas bottles, which come
/// without prices and are left out here.
final fuelStationsOperation = GraphQLOperation<FuelStationsPage>(
  name: 'FuelStations',
  document: '''
query FuelStations(\$bbox: BBoxInput!, \$first: Int, \$after: String) {
  pois(bbox: \$bbox, categories: [FUEL], first: \$first, after: \$after) {
    nodes {
      ...PoiRowFields
      fuel {
        prices { fuel priceEur updatedAt }
        shortages { fuel kind since }
        sellsLpg
        selfService24h
        highway
        fetchedAt
      }
    }
    endCursor
    hasNextPage
  }
}
$_poiRowFields''',
  parse: (data) {
    final pois = data['pois'] as Map<String, dynamic>;
    return (
      stations: [
        for (final p in pois['nodes'] as List<dynamic>)
          if (poiFromJson(p) case final poi? when poi.fuel != null) poi,
      ],
      endCursor: pois['endCursor'] as String?,
      hasNextPage: pois['hasNextPage'] == true,
    );
  },
);

Map<String, Object?> fuelStationsVariables(GeoBounds box, {String? after, int first = 1000}) => {
  'bbox': {'south': box.south, 'west': box.west, 'north': box.north, 'east': box.east},
  'first': first,
  'after': ?after,
};

/// Every operation of the points of interest that reads, for the contract
/// test (the two that write are in `communityOperations`).
final poiOperations = <GraphQLOperation<Object?>>[
  nearbyPoisOperation,
  poiOperation,
  searchPoisOperation,
  fuelStationsOperation,
];

List<NearbyPois> nearbyPoisFromJson(Object? json) => [
  if (json is List<dynamic>)
    for (final n in json)
      if (n is Map<String, dynamic>)
        if (PoiCategory.fromCode(n['category']) case final category?)
          NearbyPois(
            category: category,
            radiusM: (n['radiusM'] as num?)?.toDouble() ?? 0,
            pois: [for (final p in (n['pois'] as List<dynamic>? ?? const [])) ?poiFromJson(p)],
          ),
];

Poi? poiFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final id = json['id'];
  final kind = PoiKind.fromCode(json['kind']);
  final lat = json['lat'];
  final lon = json['lon'];
  if (id is! String || kind == null || lat is! num || lon is! num) return null;
  final address = json['address'];
  final reported = json['reportedClosed'];
  return Poi(
    id: id,
    kind: kind,
    lat: lat.toDouble(),
    lon: lon.toDouble(),
    name: _text(json['name']),
    brand: _text(json['brand']),
    operator: _text(json['operator']),
    distanceM: (json['distanceM'] as num?)?.toDouble(),
    address: address is Map<String, dynamic> ? addressFromJson(address) : null,
    phone: _text(json['phone']),
    website: _text(json['website']),
    openingHours: _text(json['openingHours']),
    openingHoursParsed: json['openingHoursParsed'] == true,
    hours: PoiHours(
      alwaysOpen: json['alwaysOpen'] == true,
      intervals: openingIntervalsFromJson(json['openingIntervals']),
      validUntil: _date(json['openingIntervalsUntil']),
    ),
    products: _strings(json['products']),
    payment: _strings(json['payment']),
    lpg: json['lpg'] as bool?,
    fuel: _fuel(json['fuel']),
    reportedClosed: reported is Map<String, dynamic>
        ? _date(reported['closedOn']) ?? _date(reported['fetchedAt'])
        : null,
    seasonal: json['seasonal'] as bool?,
    fee: json['fee'] as bool?,
    selfService: json['selfService'] as bool?,
    wheelchair: _text(json['wheelchair']),
    checkedOn: _date(json['checkedOn']),
    lastConfirmedAt: _date(json['lastConfirmedAt']),
    sources: [
      if (json['sources'] case final List<dynamic> list)
        for (final s in list)
          if (s is Map<String, dynamic>)
            if ((s['sourceId'], s['externalId'], _date(s['fetchedAt'])) case (
              final String sourceId,
              final String externalId,
              final DateTime fetchedAt,
            ))
              PoiSourceRef(
                sourceId: sourceId,
                externalId: externalId,
                externalUrl: _text(s['externalUrl']),
                fetchedAt: fetchedAt,
              ),
    ],
  );
}

FuelInfo? _fuel(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final fetched = _date(json['fetchedAt']);
  if (fetched == null) return null;
  return FuelInfo(
    prices: [
      if (json['prices'] case final List<dynamic> list)
        for (final p in list)
          if (p is Map<String, dynamic>)
            if ((p['fuel'], p['priceEur'], _date(p['updatedAt'])) case (
              final String fuel,
              final num price,
              final DateTime updated,
            ))
              FuelPrice(fuel: fuel, priceEur: price.toDouble(), updatedAt: updated),
    ],
    shortages: [
      if (json['shortages'] case final List<dynamic> list)
        for (final s in list)
          if (s is Map<String, dynamic>)
            if (s['fuel'] case final String fuel)
              FuelShortage(
                fuel: fuel,
                definitive: s['kind'] == 'DEFINITIVE',
                since: _date(s['since']),
              ),
    ],
    sellsLpg: json['sellsLpg'] == true,
    selfService24h: json['selfService24h'] == true,
    highway: json['highway'] == true,
    fetchedAt: fetched,
  );
}

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

List<String> _strings(Object? value) => [
  if (value is List<dynamic>)
    for (final v in value)
      if (v is String && v.isNotEmpty) v,
];

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toUtc() : null;
