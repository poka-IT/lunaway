import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

/// The routing operations the app sends, held to the schema by
/// `test/contract/navigation_contract_test.dart`.
final navigationOperations = <GraphQLOperation<Object?>>[routeOperation, routingInfoOperation];

const _warningFields = '''
fragment RouteWarningFields on RouteWarning {
  kind
  severity
  limit
  vehicleValue
  distanceFromStartM
  geometryIndex
  lat
  lon
  source
  certainty
  place
  name
  externalId
}
''';

const _graphFields = '''
fragment RoutingGraphFields on RoutingGraph {
  id
  osmDataAt
  ignFetchedAt
  ignEdition
  builtAt
}
''';

/// The route request, with the limits for the vehicle along each route when
/// [speedLimits]: an API without them refuses the field, and gets the
/// request without it.
String _routeDocument({required bool speedLimits}) =>
    '''
query Route(\$input: RouteInput!) {
  route(input: \$input) {
    status
    osrmJson
    routes {
      index
      distanceM
      durationS
      hasToll
      hasFerry
      hasMotorway
      warnings { ...RouteWarningFields }${speedLimits ? '\n      speedLimits { fromM toM kmh source }' : ''}
    }
    blockers { ...RouteWarningFields }
    recalculations
    reroute {
      vehicle { kind heightM widthM lengthM weightT axleLoadT trailer { lengthM weightT heightM widthM } }
      options { avoidTolls avoidMotorways avoidFerries avoidUnpaved }
      language
    }
    graph { ...RoutingGraphFields }
    disclaimerKey
  }
}
$_warningFields
$_graphFields''';

/// A route for the user's vehicle. One `route` per request: the API refuses
/// two.
final routeOperation = GraphQLOperation<RoutePlan>(
  name: 'Route',
  document: _routeDocument(speedLimits: true),
  older: OlderForm.selecting(_routeDocument(speedLimits: false)),
  parse: (data) => routePlanFromJson(data['route'] as Map<String, dynamic>),
);

/// The request of [routeOperation].
Map<String, Object?> routeVariables({
  required LatLng origin,
  required LatLng destination,
  required VehicleProfile vehicle,
  required AvoidOptions avoid,
  required RouteLanguage language,
  double? headingDeg,
  int alternatives = 0,
  List<LatLng> stops = const [],
}) => {
  'input': {
    'origin': {
      'lat': origin.lat,
      'lon': origin.lon,
      if (headingDeg != null) 'headingDeg': headingDeg % 360,
    },
    'destination': {'lat': destination.lat, 'lon': destination.lon},
    if (stops.isNotEmpty)
      'waypoints': [
        for (final s in stops) {'lat': s.lat, 'lon': s.lon},
      ],
    'vehicle': vehicle.toJson(),
    'options': avoid.toJson(),
    'alternatives': alternatives,
    'language': language.name.toUpperCase(),
  },
};

/// Whether routing works now and on which data.
final routingInfoOperation = GraphQLOperation<RoutingInfo>(
  name: 'Routing',
  document: '''
query Routing {
  routing {
    available
    graph { ...RoutingGraphFields }
    disclaimerKey
    coveredArea { south west north east }
    maxAlternatives
    vehicleBounds {
      heightM { min max }
      widthM { min max }
      lengthM { min max }
      weightT { min max }
    }
  }
}
$_graphFields''',
  parse: (data) => routingInfoFromJson(data['routing'] as Map<String, dynamic>),
);

/// What the app knows before asking for a route.
final class RoutingInfo {
  const new({
    required this.available,
    required this.disclaimerKey,
    required this.coveredArea,
    required this.maxAlternatives,
    required this.bounds,
    this.graph,
  });

  final bool available;
  final RoutingGraphInfo? graph;
  final String disclaimerKey;
  final GeoBounds coveredArea;
  final int maxAlternatives;
  final VehicleBounds bounds;
}

RoutingInfo routingInfoFromJson(Map<String, dynamic> json) {
  final area = json['coveredArea'] as Map<String, dynamic>;
  final b = json['vehicleBounds'] as Map<String, dynamic>;
  ({double min, double max}) range(String key) {
    final r = b[key] as Map<String, dynamic>;
    return (min: (r['min'] as num).toDouble(), max: (r['max'] as num).toDouble());
  }

  return RoutingInfo(
    available: json['available'] == true,
    graph: json['graph'] == null ? null : _graph(json['graph'] as Map<String, dynamic>),
    disclaimerKey: json['disclaimerKey'] as String,
    coveredArea: GeoBounds(
      south: (area['south'] as num).toDouble(),
      west: (area['west'] as num).toDouble(),
      north: (area['north'] as num).toDouble(),
      east: (area['east'] as num).toDouble(),
    ),
    maxAlternatives: (json['maxAlternatives'] as num).toInt(),
    bounds: VehicleBounds(
      height: range('heightM'),
      width: range('widthM'),
      length: range('lengthM'),
      weight: range('weightT'),
    ),
  );
}

/// The answer of [routeOperation], without the shapes: they are read from
/// `osrmJson` apart (`readOsrmShapes`), in an isolate for long trips.
RoutePlan routePlanFromJson(Map<String, dynamic> json) {
  final reroute = json['reroute'] as Map<String, dynamic>;
  final vehicle = reroute['vehicle'] as Map<String, dynamic>;
  final trailer = vehicle['trailer'] as Map<String, dynamic>?;
  final options = reroute['options'] as Map<String, dynamic>;
  return RoutePlan(
    status: switch (json['status']) {
      'OK' => RouteStatus.ok,
      'NO_ROUTE' => RouteStatus.noRoute,
      'OFF_NETWORK' => RouteStatus.offNetwork,
      'NO_SAFE_ROUTE' => RouteStatus.noSafeRoute,
      final other => throw FormatException('unknown route status $other'),
    },
    osrmJson: json['osrmJson'] as String?,
    routes: [
      for (final r in json['routes'] as List)
        if (r is Map<String, dynamic>)
          RouteOption(
            index: (r['index'] as num).toInt(),
            distanceM: (r['distanceM'] as num).toDouble(),
            durationS: (r['durationS'] as num).toDouble(),
            hasToll: r['hasToll'] == true,
            hasFerry: r['hasFerry'] == true,
            hasMotorway: r['hasMotorway'] == true,
            warnings: _warnings(r['warnings']),
            speedLimits: _speedLimits(r['speedLimits']),
          ),
    ],
    blockers: _warnings(json['blockers']),
    recalculations: (json['recalculations'] as num?)?.toInt() ?? 0,
    applied: AppliedRequest(
      vehicle: VehicleProfile(
        type: RouterVehicleType.fromWire(vehicle['kind'] as String?),
        heightM: (vehicle['heightM'] as num).toDouble(),
        widthM: (vehicle['widthM'] as num).toDouble(),
        lengthM: (vehicle['lengthM'] as num).toDouble(),
        weightT: (vehicle['weightT'] as num).toDouble(),
        trailer: trailer == null
            ? null
            : TrailerProfile(
                lengthM: (trailer['lengthM'] as num).toDouble(),
                weightT: (trailer['weightT'] as num).toDouble(),
                heightM: (trailer['heightM'] as num?)?.toDouble(),
                widthM: (trailer['widthM'] as num?)?.toDouble(),
              ),
      ),
      avoid: AvoidOptions.fromJson(options),
      language: reroute['language'] == 'EN' ? RouteLanguage.en : RouteLanguage.fr,
    ),
    graph: _graph(json['graph'] as Map<String, dynamic>),
    disclaimerKey: json['disclaimerKey'] as String,
  );
}

RoutingGraphInfo _graph(Map<String, dynamic> g) => RoutingGraphInfo(
  id: g['id'] as String,
  osmDataAt: DateTime.parse(g['osmDataAt'] as String),
  builtAt: DateTime.parse(g['builtAt'] as String),
  ignFetchedAt: g['ignFetchedAt'] == null ? null : DateTime.parse(g['ignFetchedAt'] as String),
  ignEdition: g['ignEdition'] == null ? null : DateTime.parse(g['ignEdition'] as String),
);

/// The limits along a route, in order; null without any (an older API, an
/// engine that did not answer). A span of a source this app does not know
/// is left out: no limit shows there.
List<SpeedLimitSpan>? _speedLimits(Object? list) {
  if (list is! List) return null;
  return [
    for (final s in list)
      if (s is Map<String, dynamic>)
        if ((
              (s['fromM'] as num?)?.toDouble(),
              (s['toM'] as num?)?.toDouble(),
              (s['kmh'] as num?)?.toInt(),
              SpeedLimitSource.fromWire(s['source']),
            )
            case (final from?, final to?, final kmh?, final source?))
          SpeedLimitSpan(fromM: from, toM: to, kmh: kmh, source: source),
  ]..sort((a, b) => a.fromM.compareTo(b.fromM));
}

/// Warnings of a kind, severity, source, certainty or place this app does
/// not know (a newer server) are dropped rather than failing the route; the
/// route itself was still checked by the server.
List<RouteWarning> _warnings(Object? list) => [
  if (list is List)
    for (final w in list)
      if (w is Map<String, dynamic>) ?_warning(w),
];

RouteWarning? _warning(Map<String, dynamic> w) {
  final kind = _enum(RouteWarningKind.values, w['kind']);
  final severity = _enum(WarningSeverity.values, w['severity']);
  final source = _enum(RestrictionSource.values, w['source']);
  final certainty = _enum(RestrictionCertainty.values, w['certainty']);
  final place = _enum(RestrictionPlace.values, w['place']);
  if (kind == null || severity == null || source == null || certainty == null || place == null) {
    return null;
  }
  return RouteWarning(
    kind: kind,
    severity: severity,
    limit: (w['limit'] as num?)?.toDouble(),
    vehicleValue: (w['vehicleValue'] as num?)?.toDouble(),
    distanceFromStartM: (w['distanceFromStartM'] as num).toDouble(),
    geometryIndex: (w['geometryIndex'] as num).toInt(),
    position: LatLng((w['lat'] as num).toDouble(), (w['lon'] as num).toDouble()),
    source: source,
    certainty: certainty,
    place: place,
    name: w['name'] as String?,
    externalId: w['externalId'] as String,
  );
}

/// The value of [values] whose name is the GraphQL [wire] value
/// (`LOW_CLEARANCE` for `lowClearance`).
T? _enum<T extends Enum>(List<T> values, Object? wire) {
  final key = '$wire'.toLowerCase().replaceAll('_', '');
  return values.where((v) => v.name.toLowerCase() == key).firstOrNull;
}
