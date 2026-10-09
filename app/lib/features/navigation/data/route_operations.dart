import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/road_events_api.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

/// The routing operations the app sends, held to the schema by
/// `test/contract/navigation_contract_test.dart`.
final navigationOperations = <GraphQLOperation<Object?>>[routeOperation, routingInfoOperation];

/// The fields of a restriction; whether it spares local access when
/// [desserte], which an API before 2026-10-08 does not know.
String _warningFields({required bool desserte}) =>
    '''
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
  externalId${desserte ? '\n  exceptDestination' : ''}
}
''';

// The road events a route meets or goes around, with what the screens show
// of them: the road, the source's words, where and how recent.
const _roadEventFields = '''
fragment RouteRoadEventFields on RoadEvent {
  id
  class
  source
  roadNumber
  roadName
  validFrom
  validTo
  match
  mayBlock
  position { lat lon }
  headingDeg
  limits { maxHeightM maxWidthM }
  sourceUpdatedAt
  firstSeenAt
}
fragment RoadEventWarningFields on RoadEventWarning {
  event { ...RouteRoadEventFields }
  severity
  reason
  distanceFromStartM
  lengthM
  lat
  lon
  dataReadAt
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

const _ferryFields = '''
fragment FerryCrossingFields on FerryCrossing {
  name
  ports
  fromLat
  fromLon
  toLat
  toLon
  fromCountry
  toCountry
  distanceFromStartM
  distanceM
  durationS
}
''';

/// The route request, with the limits for the vehicle along each route when
/// [speedLimits], why there is no route and the ferry crossings when
/// [reasons], the cruising speed the times assume when [cruise], and the
/// stops the server moved and the limits that spare local access when
/// [desserte]: an API without them refuses the fields, and gets the request
/// without them.
String _routeDocument({
  required bool speedLimits,
  required bool reasons,
  bool cruise = false,
  bool desserte = false,
}) =>
    '''
query Route(\$input: RouteInput!) {
  route(input: \$input) {
    status
    osrmJson${reasons ? _reasonsSelection : ''}${desserte ? '\n    movedStops { stopIndex lat lon distanceM }' : ''}
    routes {
      index
      distanceM
      durationS
      hasToll
      hasFerry
      hasMotorway
      warnings { ...RouteWarningFields }
      roadEvents { ...RoadEventWarningFields }${speedLimits ? '\n      speedLimits { fromM toM kmh source }' : ''}${reasons ? '\n      notices { kind ferry { ...FerryCrossingFields } }' : ''}
    }
    blockers { ...RouteWarningFields }
    roadEventBlockers { ...RoadEventWarningFields }
    avoidedRoadEvents { ...RouteRoadEventFields }
    roadEventSources { id name attribution lastReadAt dataAt staleAfterSeconds fresh }
    recalculations
    reroute {
      vehicle { kind heightM widthM lengthM weightT axleLoadT trailer { lengthM weightT heightM widthM }${cruise ? ' cruiseSpeedKph' : ''} }
      options { avoidTolls avoidMotorways avoidFerries avoidUnpaved }
      language${cruise ? '\n      topSpeedKph' : ''}
    }
    graph { ...RoutingGraphFields }
  }
}
${_warningFields(desserte: desserte)}
$_roadEventFields
$_graphFields${reasons ? _ferryFields : ''}''';

const _reasonsSelection = '''

    noRouteReasons {
      kind
      stopIndex
      limits { kind limit vehicleValue restriction { ...RouteWarningFields } }
    }''';

/// A route for the user's vehicle. One `route` per request: the API refuses
/// two.
final routeOperation = GraphQLOperation<RoutePlan>(
  name: 'Route',
  document: _routeDocument(speedLimits: true, reasons: true, cruise: true, desserte: true),
  // The API before the moved stops and the limits that spare local access
  // (2026-10-08): it moves no stop, so the vehicle's own position needs no
  // flag. Then the one before the cruising speed (2026-10-07), the one
  // before the reasons and the crossings, the one before the speed limits.
  // None of these knows the cruising speed: the route is timed without it,
  // and the preview then tells no speed.
  older: OlderForm(
    document: _routeDocument(speedLimits: true, reasons: true, cruise: true),
    variables: withoutVehiclePosition,
    withoutFields: true,
    older: _withoutCruise(
      _routeDocument(speedLimits: true, reasons: true),
      older: _withoutCruise(
        _routeDocument(speedLimits: true, reasons: false),
        older: _withoutCruise(_routeDocument(speedLimits: false, reasons: false)),
      ),
    ),
  ),
  parse: (data) => routePlanFromJson(data['route'] as Map<String, dynamic>),
);

/// [document] for an API before the cruising speed: its request leaves the
/// vehicle's `cruiseSpeedKph` out, which that API would refuse, and the
/// origin's `vehiclePosition`, which came later.
OlderForm _withoutCruise(String document, {OlderForm? older}) => OlderForm(
  document: document,
  variables: (v) => withoutCruiseSpeed(withoutVehiclePosition(v)),
  withoutFields: true,
  older: older,
);

/// [variables] of a route request without the origin's `vehiclePosition`,
/// which an API before 2026-10-08 refuses.
Map<String, Object?> withoutVehiclePosition(Map<String, Object?> variables) {
  final input = variables['input'];
  if (input is! Map<String, Object?>) return variables;
  final origin = input['origin'];
  if (origin is! Map<String, Object?>) return variables;
  return {
    ...variables,
    'input': {
      ...input,
      'origin': {
        for (final MapEntry(:key, :value) in origin.entries)
          if (key != 'vehiclePosition') key: value,
      },
    },
  };
}

/// [variables] of a route or fuel request without the vehicle's cruising
/// speed.
Map<String, Object?> withoutCruiseSpeed(Map<String, Object?> variables) {
  final input = variables['input'];
  if (input is! Map<String, Object?>) return variables;
  final vehicle = input['vehicle'];
  if (vehicle is! Map<String, Object?>) return variables;
  return {
    ...variables,
    'input': {
      ...input,
      'vehicle': {
        for (final MapEntry(:key, :value) in vehicle.entries)
          if (key != 'cruiseSpeedKph') key: value,
      },
    },
  };
}

/// The request of [routeOperation].
Map<String, Object?> routeVariables({
  required LatLng origin,
  required LatLng destination,
  required VehicleProfile vehicle,
  required AvoidOptions avoid,
  required RouteLanguage language,
  double? headingDeg,
  bool fromVehicle = false,
  int alternatives = 0,
  List<LatLng> stops = const [],
}) => {
  'input': {
    'origin': {
      'lat': origin.lat,
      'lon': origin.lon,
      if (headingDeg != null) 'headingDeg': headingDeg % 360,
      // The vehicle's own position during guidance: the server never moves
      // it, course or not. Said either way: an origin that says nothing
      // counts as the vehicle's, which the preview's need not be.
      'vehiclePosition': fromVehicle,
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

/// The routing information; with the countries and the longest trip when
/// [countries], which an API before 2026-10-07 does not know.
String _routingDocument({required bool countries}) =>
    '''
query Routing {
  routing {
    available
    graph { ...RoutingGraphFields }
    coveredArea { south west north east }${countries ? '\n    coveredCountries\n    roadEventReportCountries\n    maxTripKm' : ''}
    maxAlternatives
    vehicleBounds {
      heightM { min max }
      widthM { min max }
      lengthM { min max }
      weightT { min max }
    }
  }
}
$_graphFields''';

/// Whether routing works now and on which data.
final routingInfoOperation = GraphQLOperation<RoutingInfo>(
  name: 'Routing',
  document: _routingDocument(countries: true),
  older: OlderForm.selecting(_routingDocument(countries: false)),
  parse: (data) => routingInfoFromJson(data['routing'] as Map<String, dynamic>),
);

/// What the app knows before asking for a route.
final class RoutingInfo {
  const new({
    required this.available,
    required this.coveredArea,
    required this.maxAlternatives,
    required this.bounds,
    this.graph,
    this.coveredCountries = const [],
    this.roadEventReportCountries = const [],
    this.maxTripKm,
  });

  final bool available;
  final RoutingGraphInfo? graph;
  final GeoBounds coveredArea;
  final int maxAlternatives;
  final VehicleBounds bounds;

  /// The countries routes are computed in (ISO 3166-1 alpha-2); empty from
  /// an API that does not tell them, which then decides alone.
  final List<String> coveredCountries;

  /// The countries where a road event may be reported; empty when unknown.
  final List<String> roadEventReportCountries;

  /// The longest trip accepted, kilometres in a straight line from stop to
  /// stop; null when unknown.
  final double? maxTripKm;
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
    coveredArea: GeoBounds(
      south: (area['south'] as num).toDouble(),
      west: (area['west'] as num).toDouble(),
      north: (area['north'] as num).toDouble(),
      east: (area['east'] as num).toDouble(),
    ),
    maxAlternatives: (json['maxAlternatives'] as num).toInt(),
    coveredCountries: _codes(json['coveredCountries']),
    roadEventReportCountries: _codes(json['roadEventReportCountries']),
    maxTripKm: (json['maxTripKm'] as num?)?.toDouble(),
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
            roadEvents: _roadEvents(r['roadEvents']),
            ferries: _ferries(r['notices']),
          ),
    ],
    noRouteReasons: [
      if (json['noRouteReasons'] case final List<dynamic> list)
        for (final n in list)
          if (n is Map<String, dynamic>) ?_noRouteReason(n),
    ],
    blockers: _warnings(json['blockers']),
    movedStops: [
      if (json['movedStops'] case final List<dynamic> list)
        for (final m in list)
          if (m is Map<String, dynamic>) ?_movedStop(m),
    ],
    roadEventBlockers: _roadEvents(json['roadEventBlockers']),
    avoidedRoadEvents: [
      if (json['avoidedRoadEvents'] case final List<dynamic> list)
        for (final e in list)
          if (e is Map<String, dynamic>) ?roadEventFromJson(e),
    ],
    roadEventSources: [
      if (json['roadEventSources'] case final List<dynamic> list)
        for (final s in list)
          if (s is Map<String, dynamic> && s['id'] is String) roadEventSourceFromJson(s),
    ],
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
        cruiseSpeedKph: (vehicle['cruiseSpeedKph'] as num?)?.toInt(),
      ),
      avoid: AvoidOptions.fromJson(options),
      language: RouteLanguage.fromWire(reroute['language']),
      topSpeedKph: (reroute['topSpeedKph'] as num?)?.toInt(),
    ),
    graph: _graph(json['graph'] as Map<String, dynamic>),
  );
}

List<String> _codes(Object? list) => [
  if (list is List)
    for (final c in list)
      if (c is String) c,
];

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
    exceptDestination: w['exceptDestination'] == true,
  );
}

MovedStop? _movedStop(Map<String, dynamic> m) {
  if ((m['stopIndex'], m['lat'], m['lon'], m['distanceM']) case (
    final num index,
    final num lat,
    final num lon,
    final num distance,
  )) {
    return MovedStop(
      stopIndex: index.toInt(),
      position: LatLng(lat.toDouble(), lon.toDouble()),
      distanceM: distance.toDouble(),
    );
  }
  return null;
}

/// Road events of a reason or weight this app does not know (a newer
/// server) are dropped, as warnings are.
List<RouteRoadEvent> _roadEvents(Object? list) => [
  if (list is List)
    for (final w in list)
      if (w is Map<String, dynamic>) ?_roadEvent(w),
];

RouteRoadEvent? _roadEvent(Map<String, dynamic> w) {
  final weight = _enum(RoadEventWeight.values, w['severity']);
  final reason = _enum(RoadEventReason.values, w['reason']);
  final event = w['event'] is Map<String, dynamic>
      ? roadEventFromJson(w['event'] as Map<String, dynamic>)
      : null;
  final from = w['distanceFromStartM'];
  final lat = w['lat'];
  final lon = w['lon'];
  // One event the app cannot place is left out; the route still stands.
  if (weight == null || reason == null || event == null) return null;
  if (from is! num || lat is! num || lon is! num) return null;
  final dataAt = w['dataReadAt'];
  return RouteRoadEvent(
    event: event,
    weight: weight,
    reason: reason,
    distanceFromStartM: from.toDouble(),
    lengthM: (w['lengthM'] as num?)?.toDouble() ?? 0,
    position: LatLng(lat.toDouble(), lon.toDouble()),
    dataAt: dataAt is String ? DateTime.tryParse(dataAt) : null,
  );
}

/// A reason of a kind this app does not know (a newer server) is left
/// out; the screen then says what it says without reasons. A trip too long
/// is the app's own reason, with figures the server does not send: from
/// the server it would read as one without them.
NoRouteReason? _noRouteReason(Map<String, dynamic> n) {
  final kind = _enum(NoRouteReasonKind.values, n['kind']);
  if (kind == null || kind == NoRouteReasonKind.tripTooLong) return null;
  return NoRouteReason(
    kind: kind,
    stopIndex: (n['stopIndex'] as num?)?.toInt(),
    limits: [
      if (n['limits'] case final List<dynamic> list)
        for (final l in list)
          if (l is Map<String, dynamic>)
            if (_enum(VehicleLimitKind.values, l['kind']) case final limitKind?)
              BlockingLimit(
                kind: limitKind,
                limit: (l['limit'] as num?)?.toDouble(),
                vehicleValue: (l['vehicleValue'] as num?)?.toDouble(),
                restriction: l['restriction'] is Map<String, dynamic>
                    ? _warning(l['restriction'] as Map<String, dynamic>)
                    : null,
              ),
    ],
  );
}

/// The crossings among a route's notices; a notice of a kind this app
/// does not know is left out.
List<FerryCrossing> _ferries(Object? notices) => [
  if (notices is List)
    for (final n in notices)
      if (n is Map<String, dynamic> && n['kind'] == 'ROUTE_USES_FERRY')
        if (n['ferry'] case final Map<String, dynamic> f) _ferry(f),
];

FerryCrossing _ferry(Map<String, dynamic> f) {
  LatLng? at(Object? lat, Object? lon) =>
      lat is num && lon is num ? LatLng(lat.toDouble(), lon.toDouble()) : null;
  return FerryCrossing(
    name: f['name'] as String?,
    ports: [
      if (f['ports'] case final List<dynamic> ports)
        for (final p in ports)
          if (p is String) p,
    ],
    from: at(f['fromLat'], f['fromLon']),
    to: at(f['toLat'], f['toLon']),
    fromCountry: f['fromCountry'] as String?,
    toCountry: f['toCountry'] as String?,
    distanceFromStartM: (f['distanceFromStartM'] as num?)?.toDouble() ?? 0,
    distanceM: (f['distanceM'] as num?)?.toDouble() ?? 0,
    durationS: (f['durationS'] as num?)?.toDouble() ?? 0,
  );
}

/// The value of [values] whose name is the GraphQL [wire] value
/// (`LOW_CLEARANCE` for `lowClearance`).
T? _enum<T extends Enum>(List<T> values, Object? wire) {
  final key = '$wire'.toLowerCase().replaceAll('_', '');
  return values.where((v) => v.name.toLowerCase() == key).firstOrNull;
}
