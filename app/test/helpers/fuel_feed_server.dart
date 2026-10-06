import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/features/places/data/demo/persisted_queries.dart';

import '../contract/graphql_validator.dart';

/// The API's searches of fuel prices in memory (`fuelNearby`, and the
/// trend of a station's price): what they answer is set by the test, every
/// request is held to `schema/lunaway.graphql`, and a request names its
/// document by its hash as the app's client does. Anything else goes to
/// [fallback].
final class FuelFeedServer {
  new(this.fallback);

  final http.Client fallback;

  static final _schema = SchemaValidator(File('../schema/lunaway.graphql').readAsStringSync());
  final _persisted = PersistedQueryStore();

  /// The stations `fuelNearby` answers, as the API writes `FuelStop`.
  List<Map<String, Object?>> nearby = [];

  /// The trend each station's sheet reads, by point id; absent: none seen.
  Map<String, Map<String, Object?>> trends = {};

  /// Answers as an API without these searches (`Unknown field`).
  bool older = false;

  /// The requests received, by operation, with their variables.
  final List<(String, Map<String, dynamic>)> requests = [];

  /// What the schema found wrong in a request.
  final List<String> violations = [];

  http.Client get client => MockClient((request) async {
    if (request.method != 'POST' || !request.url.path.endsWith('/graphql')) {
      return await fallback.send(request).then(http.Response.fromStream);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final name = body['operationName'];
    if (name != 'FuelNearby' && name != 'FuelTrend') {
      return await fallback.send(request).then(http.Response.fromStream);
    }
    final document = _persisted.documentOf(body);
    if (document == null) return _json(PersistedQueryStore.notFound);
    final variables = (body['variables'] as Map<String, dynamic>?) ?? const {};
    requests.add((name as String, variables));
    violations
      ..addAll(_schema.validate(document))
      ..addAll(_schema.checkVariables(document, variables));
    if (older) {
      return _json({
        'data': null,
        'errors': [
          {
            'message': name == 'FuelNearby'
                ? 'Unknown field "fuelNearby" on type "Query".'
                : 'Unknown field "priceTrend" on type "FuelInfo".',
            'extensions': {'code': 'INVALID_INPUT'},
          },
        ],
      });
    }
    final data = name == 'FuelNearby'
        ? {'fuelNearby': nearby}
        : {
            'poi': {
              'id': variables['id'],
              'fuel': {'priceTrend': trends[variables['id']]},
            },
          };
    violations.addAll(
      _schema.checkResponse(document, jsonDecode(jsonEncode(data)) as Map<String, dynamic>),
    );
    return _json({'data': data});
  });

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// A station as `fuelNearby` answers it.
Map<String, Object?> fuelStop(
  String stationId,
  String name,
  double price, {
  required double lat,
  required double lon,
  String? poiId,
  String fuel = 'DIESEL',
  String? shortage,
}) => {
  'stationId': stationId,
  'poiId': poiId,
  'name': name,
  'brand': null,
  'lat': lat,
  'lon': lon,
  'fuel': fuel,
  'priceEur': price,
  'priceUpdatedAt': '2026-10-06T06:00:00Z',
  'shortage': shortage == null ? null : {'kind': shortage, 'since': null},
  'selfService24h': false,
  'highway': false,
  'fetchedAt': '2026-10-06T08:20:00Z',
};
