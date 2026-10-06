import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

/// The road events delta, with the selection the backend measured for a
/// phone in guidance (`plan/research/21-backend-travaux.md`, part 5): the
/// events that may block, without any position of the phone.
final roadEventsOperation = GraphQLOperation<RoadEventsDelta>(
  name: 'RoadEvents',
  document: r'''
query RoadEvents($since: String) {
  roadEvents(since: $since) {
    cursor
    full
    hasMore
    asOf
    pollIntervalSeconds
    removals
    upserts {
      id
      class
      roadNumber
      limits { maxHeightM maxWidthM maxLengthM maxWeightT appliesTo }
      validFrom
      validTo
      schedule {
        windows { days startMinute endMinute }
        exceptions { from to }
        timeZone
        marginMinutes
        widenMinutes
        assumed
        unplanned
      }
      lines
      position { lat lon }
      match
      mayBlock
      sourceUpdatedAt
      firstSeenAt
      source
    }
    sources { id lastReadAt staleAfterSeconds fresh }
  }
}
''',
  parse: (data) => roadEventsDeltaFromJson(data['roadEvents'] as Map<String, dynamic>),
);

/// [RoadEventsSource] over the API's `roadEvents` query.
final class GraphQLRoadEventsSource implements RoadEventsSource {
  new(this._client);

  final GraphQLClient _client;

  @override
  Future<RoadEventsDelta> delta({String? cursor}) async {
    try {
      return await _client.execute(roadEventsOperation, {'since': cursor});
    } on GraphQLRateLimitedException catch (e) {
      throw RoadEventsUnavailable('rate limited', retryAfter: e.wait);
    } on GraphQLNetworkException catch (e) {
      throw RoadEventsUnavailable(e.message);
    } on GraphQLResponseException catch (e) {
      // A cursor the server no longer knows comes back refused: the next
      // poll starts from the whole set. A server without the query (before
      // its deployment) refuses the document the same way, harmlessly.
      throw RoadEventsUnavailable(
        e.messages.join('; '),
        cursorRefused: cursor != null && e.hasCode(GraphQLError.invalidInput),
      );
    }
  }
}

RoadEventsDelta roadEventsDeltaFromJson(Map<String, dynamic> json) {
  final interval = (json['pollIntervalSeconds'] as num?)?.toInt();
  return RoadEventsDelta(
    cursor: json['cursor'] as String,
    full: json['full'] == true,
    hasMore: json['hasMore'] == true,
    asOf: DateTime.parse(json['asOf'] as String),
    pollInterval: interval == null || interval <= 0 ? null : Duration(seconds: interval),
    removals: [for (final r in json['removals'] as List? ?? const []) '$r'],
    upserts: [
      for (final e in json['upserts'] as List? ?? const [])
        if (e is Map<String, dynamic>) ?_event(e),
    ],
    sources: [
      for (final s in json['sources'] as List? ?? const [])
        if (s is Map<String, dynamic>)
          RoadEventSourceStatus(
            id: s['id'] as String,
            fresh: s['fresh'] == true,
            lastReadAt: _date(s['lastReadAt']),
            staleAfter: (s['staleAfterSeconds'] as num?) == null
                ? null
                : Duration(seconds: (s['staleAfterSeconds'] as num).toInt()),
          ),
    ],
  );
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// An event this app cannot read (a class or a placement of a newer server)
/// is left out: the server's own route check still knows it.
RoadEvent? _event(Map<String, dynamic> e) {
  final eventClass = switch (e['class']) {
    'CLOSURE' => RoadEventClass.closure,
    'VEHICLE_LIMIT' => RoadEventClass.vehicleLimit,
    'LANE_RESTRICTION' => RoadEventClass.laneRestriction,
    'DETOUR' => RoadEventClass.detour,
    'WORKS' => RoadEventClass.works,
    _ => null,
  };
  if (eventClass == null) return null;
  final limits = e['limits'] is Map<String, dynamic>
      ? e['limits'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final position = e['position'] is Map<String, dynamic>
      ? e['position'] as Map<String, dynamic>
      : null;
  final schedule = e['schedule'] is Map<String, dynamic>
      ? e['schedule'] as Map<String, dynamic>
      : null;
  return RoadEvent(
    id: '${e['id']}',
    eventClass: eventClass,
    placement: switch (e['match']) {
      'MATCHED' => RoadEventPlacement.matched,
      'RAMP' => RoadEventPlacement.ramp,
      'POINT' => RoadEventPlacement.point,
      _ => RoadEventPlacement.other,
    },
    source: '${e['source']}',
    mayBlock: e['mayBlock'] == true,
    lines: [
      for (final l in e['lines'] as List? ?? const [])
        if (l is String) decodePolyline(l),
    ],
    position: position == null
        ? null
        : LatLng((position['lat'] as num).toDouble(), (position['lon'] as num).toDouble()),
    maxHeightM: (limits['maxHeightM'] as num?)?.toDouble(),
    maxWidthM: (limits['maxWidthM'] as num?)?.toDouble(),
    maxLengthM: (limits['maxLengthM'] as num?)?.toDouble(),
    maxWeightT: (limits['maxWeightT'] as num?)?.toDouble(),
    validFrom: _date(e['validFrom']),
    validTo: _date(e['validTo']),
    roadNumber: e['roadNumber'] as String?,
    updatedAt: _date(e['sourceUpdatedAt']) ?? _date(e['firstSeenAt']),
    schedule: schedule == null
        ? const RoadEventSchedule()
        : RoadEventSchedule(
            windows: [
              for (final w in schedule['windows'] as List? ?? const [])
                if (w is Map<String, dynamic>)
                  (
                    days: {for (final d in w['days'] as List? ?? const []) (d as num).toInt()},
                    startMinute: (w['startMinute'] as num).toInt(),
                    endMinute: (w['endMinute'] as num).toInt(),
                  ),
            ],
            exceptions: [
              for (final x in schedule['exceptions'] as List? ?? const [])
                if (x is Map<String, dynamic> && _date(x['from']) != null && _date(x['to']) != null)
                  (from: _date(x['from'])!, to: _date(x['to'])!),
            ],
            utc: schedule['timeZone'] == 'UTC',
            marginMinutes: (schedule['marginMinutes'] as num?)?.toInt() ?? 15,
            widenMinutes: (schedule['widenMinutes'] as num?)?.toInt() ?? 0,
            assumed: schedule['assumed'] == true,
            unplanned: schedule['unplanned'] == true,
          ),
  );
}
