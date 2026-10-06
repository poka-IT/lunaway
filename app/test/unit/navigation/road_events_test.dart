import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/road_events_api.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';

import '../../helpers/navigation.dart';

/// A delta as the API's `roadEvents` query writes it
/// (`plan/research/21-backend-travaux.md`, part 5).
Map<String, dynamic> deltaJson() => {
  'cursor': 'r-1042',
  'full': true,
  'hasMore': false,
  'asOf': '2026-10-06T13:02:00Z',
  'pollIntervalSeconds': 180,
  'removals': ['old-1'],
  'upserts': [
    {
      'id': 'e-closure',
      'class': 'CLOSURE',
      'roadNumber': 'N141',
      'limits': null,
      'validFrom': '2026-10-01T00:00:00Z',
      'validTo': '2026-11-06T16:30:00Z',
      'schedule': {
        'windows': [
          {
            'days': [1, 2, 3, 4, 5],
            'startMinute': 19 * 60,
            'endMinute': 8 * 60,
          },
        ],
        'exceptions': <Object>[],
        'timeZone': 'Europe/Paris',
        'marginMinutes': 15,
        'widenMinutes': 0,
        'assumed': true,
        'unplanned': false,
      },
      'lines': ['yhhmvAshlmAD_@^wB'],
      'position': null,
      'match': 'MATCHED',
      'mayBlock': true,
      'sourceUpdatedAt': '2026-10-05T08:00:00Z',
      'firstSeenAt': '2026-10-01T08:00:00Z',
      'source': 'dir',
    },
    {
      'id': 'e-height',
      'class': 'VEHICLE_LIMIT',
      'roadNumber': null,
      'limits': {
        'maxHeightM': 3.0,
        'maxWidthM': null,
        'maxLengthM': null,
        'maxWeightT': null,
        'appliesTo': 'ALL',
      },
      'validFrom': null,
      'validTo': null,
      'schedule': null,
      'lines': <Object>[],
      'position': {'lat': 45.84, 'lon': 1.28},
      'match': 'POINT',
      'direction': 'NORTH',
      'mayBlock': true,
      'sourceUpdatedAt': null,
      'firstSeenAt': '2026-10-06T07:00:00Z',
      'source': 'dialog',
    },
    {'id': 'e-future', 'class': 'FLOOD', 'match': 'MATCHED', 'source': 'dir'},
  ],
  'sources': [
    {
      'id': 'dir',
      'lastReadAt': '2026-10-06T13:00:00Z',
      'dataAt': '2026-10-06T11:00:00Z',
      'staleAfterSeconds': 7800,
      'fresh': true,
    },
  ],
};

RoadEvent event({
  RoadEventClass eventClass = RoadEventClass.closure,
  bool mayBlock = true,
  double? maxHeightM,
  double? maxLengthM,
  DateTime? validFrom,
  DateTime? validTo,
  DateTime? updatedAt,
  RoadEventSchedule schedule = const RoadEventSchedule(),
}) => RoadEvent(
  id: 'e',
  eventClass: eventClass,
  placement: RoadEventPlacement.point,
  source: 'dir',
  mayBlock: mayBlock,
  position: const LatLng(45, 1),
  maxHeightM: maxHeightM,
  maxLengthM: maxLengthM,
  validFrom: validFrom,
  validTo: validTo,
  updatedAt: updatedAt,
  schedule: schedule,
);

const van = VehicleProfile(
  type: RouterVehicleType.panelVan,
  heightM: 2.6,
  widthM: 2.05,
  lengthM: 6,
  weightT: 3.5,
);
final VehicleProfile tall = checkVehicle(motorhome).profile!;
final now = DateTime.utc(2026, 10, 6, 13, 10);

void main() {
  group('the delta of the API', () {
    test('reads classes, placements, lines, points, limits, schedules and sources', () {
      final delta = roadEventsDeltaFromJson(deltaJson());
      expect(delta.cursor, 'r-1042');
      expect(delta.full, isTrue);
      expect(delta.pollInterval, const Duration(minutes: 3));
      expect(delta.removals, ['old-1']);
      expect(delta.upserts.map((e) => e.id), ['e-closure', 'e-height'], reason: 'FLOOD is new');
      final closure = delta.upserts.first;
      expect(closure.eventClass, RoadEventClass.closure);
      expect(closure.placement, RoadEventPlacement.matched);
      expect(closure.lines.single.first.lat, closeTo(45.847197, 1e-6));
      expect(closure.schedule.windows.single.days, {1, 2, 3, 4, 5});
      expect(closure.schedule.assumed, isTrue);
      final height = delta.upserts.last;
      expect(height.placement, RoadEventPlacement.point);
      expect(height.maxHeightM, 3.0);
      expect(height.position, const LatLng(45.84, 1.28));
      expect(height.updatedAt, DateTime.parse('2026-10-06T07:00:00Z'));
      // Northbound only: a route passing it within 100 degrees of north.
      expect(height.shapes.single.headingDeg, 0);
      expect(height.shapes.single.headingToleranceDeg, 100);
      expect(closure.direction, RoadEventDirection.both);
      // Read at 13:00, but data of 11:00: stale 2 h 10 after the data.
      expect(delta.sources.single.freshAt(now), isTrue);
      expect(delta.sources.single.freshAt(now.add(const Duration(minutes: 30))), isFalse);
    });

    test('a reported course binds a point event closer than a cardinal direction', () {
      const reported = RoadEvent(
        id: 'r',
        eventClass: RoadEventClass.closure,
        placement: RoadEventPlacement.point,
        source: 'community',
        position: LatLng(45, 1),
        direction: RoadEventDirection.north,
        headingDeg: 200,
      );
      expect(reported.shapes.single.headingDeg, 200);
      expect(reported.shapes.single.headingToleranceDeg, 60);
    });
  });

  group('whether an event stops the vehicle', () {
    test('a closure stops everyone; a limit only a vehicle over it', () {
      expect(event().blocks(van, now), isTrue);
      expect(
        event(eventClass: RoadEventClass.vehicleLimit, maxHeightM: 3).blocks(tall, now),
        isTrue,
      );
      expect(
        event(eventClass: RoadEventClass.vehicleLimit, maxHeightM: 3).blocks(van, now),
        isFalse,
      );
      expect(
        event(eventClass: RoadEventClass.vehicleLimit, maxHeightM: 3.3).blocks(tall, now),
        isFalse,
        reason: 'a limit equal to the vehicle lets it pass, as on the server',
      );
      expect(event(eventClass: RoadEventClass.laneRestriction).blocks(van, now), isFalse);
    });

    test('the trailer counts in the length of the combination', () {
      final towing = checkVehicle(motorhome.copyWith(lengthM: () => 12)).profile!;
      final limited = event(eventClass: RoadEventClass.vehicleLimit, maxLengthM: 10);
      expect(limited.blocks(towing, now), isTrue);
      final withTrailer = VehicleProfile(
        type: towing.type,
        heightM: towing.heightM,
        widthM: towing.widthM,
        lengthM: 7,
        weightT: 3.5,
        trailer: assumedTrailer,
      );
      expect(limited.blocks(withTrailer, now), isTrue, reason: '7 m plus 4.78 m');
    });

    test('only what the server says may block, and only while in force', () {
      expect(event(mayBlock: false).blocks(van, now), isFalse);
      expect(event(validFrom: now.add(const Duration(hours: 2))).blocks(van, now), isFalse);
      expect(
        event(validFrom: now.add(const Duration(minutes: 10))).blocks(van, now),
        isTrue,
        reason: 'within the 15 minutes of margin',
      );
      expect(event(validTo: now.subtract(const Duration(hours: 1))).blocks(van, now), isFalse);
    });

    test('an open event not updated for a month, or an incident for half a day, has ended', () {
      expect(event(updatedAt: now.subtract(const Duration(days: 40))).blocks(van, now), isFalse);
      expect(event(updatedAt: now.subtract(const Duration(days: 3))).blocks(van, now), isTrue);
      expect(
        event(
          updatedAt: now.subtract(const Duration(hours: 13)),
          schedule: const RoadEventSchedule(unplanned: true),
        ).blocks(van, now),
        isFalse,
      );
    });

    test('a night closure in the time of Paris, through midnight', () {
      final night = event(
        schedule: const RoadEventSchedule(
          windows: [
            (days: {1, 2, 3, 4, 5}, startMinute: 20 * 60, endMinute: 7 * 60),
          ],
          marginMinutes: 0,
        ),
      );
      // Tuesday 6 October 2026: 23:00 in Paris is 21:00 UTC.
      expect(night.blocks(van, DateTime.utc(2026, 10, 6, 21)), isTrue);
      // Wednesday 05:00 in Paris, in Tuesday's window.
      expect(night.blocks(van, DateTime.utc(2026, 10, 7, 3)), isTrue);
      // Tuesday noon.
      expect(night.blocks(van, DateTime.utc(2026, 10, 6, 10)), isFalse);
      // Saturday 23:00: no window on the weekend.
      expect(night.blocks(van, DateTime.utc(2026, 10, 10, 21)), isFalse);
    });
  });

  group('the check of the route ahead', () {
    final plan = routeFixture('limoges_drive');
    final route = plan.routes.single;
    RoadEvent onRoute(String id, double atM, {RoadEventClass c = RoadEventClass.closure}) {
      final track = LineTrack(route);
      return RoadEvent(
        id: id,
        eventClass: c,
        placement: RoadEventPlacement.point,
        source: 'dir',
        mayBlock: true,
        position: track.at(atM),
      );
    }

    RoadEventsDelta delta(List<RoadEvent> events, {bool full = false}) => RoadEventsDelta(
      cursor: 'c${events.length}',
      asOf: now,
      full: full,
      upserts: events,
      sources: [RoadEventSourceStatus(id: 'dir', fresh: true, lastReadAt: now)],
    );

    test('finds a closure ahead once, and not one behind', () {
      final tracker = RoadEventsTracker()
        ..apply(delta([onRoute('ahead', 1600), onRoute('behind', 300)]));
      final track = LineTrack(route);
      final first = tracker.check(track: track, alongM: 1000, vehicle: tall, now: now);
      expect(first.blocking.map((f) => f.event.id), ['ahead']);
      expect(first.blocking.single.aheadM, closeTo(600, 15));
      tracker.markHandled(['ahead']);
      final again = tracker.check(track: track, alongM: 1100, vehicle: tall, now: now);
      expect(again.blocking, isEmpty, reason: 'acted on already');
      tracker.resetHandled();
      expect(
        tracker.check(track: track, alongM: 1100, vehicle: tall, now: now).blocking,
        hasLength(1),
        reason: 'a new route that still meets it says so again',
      );
    });

    test('a lane closed ahead is a word, not a recalculation', () {
      final tracker = RoadEventsTracker()
        ..apply(delta([onRoute('lane', 2000, c: RoadEventClass.laneRestriction)]));
      final found = tracker.check(track: LineTrack(route), alongM: 0, vehicle: tall, now: now);
      expect(found.blocking, isEmpty);
      expect(found.alerts.single.event.id, 'lane');
    });

    test('events of a source grown stale are left out', () {
      final tracker = RoadEventsTracker()
        ..apply(
          RoadEventsDelta(
            cursor: 'c',
            asOf: now,
            upserts: [onRoute('stale', 1600)],
            sources: [
              RoadEventSourceStatus(
                id: 'dir',
                fresh: true,
                lastReadAt: now.subtract(const Duration(hours: 4)),
                staleAfter: const Duration(hours: 2),
              ),
            ],
          ),
        );
      final found = tracker.check(track: LineTrack(route), alongM: 0, vehicle: tall, now: now);
      expect(found.blocking, isEmpty);
    });

    test('a full delta replaces the set; removals take events out; the cursor follows', () {
      final tracker = RoadEventsTracker()..apply(delta([onRoute('a', 1600), onRoute('b', 2000)]));
      expect(tracker.count, 2);
      tracker.apply(RoadEventsDelta(cursor: 'next', asOf: now, removals: const ['a', 'unknown']));
      expect(tracker.count, 1);
      expect(tracker.cursor, 'next');
      tracker.apply(delta([onRoute('c', 1000)], full: true));
      expect(tracker.count, 1);
      tracker.restart();
      expect(tracker.cursor, isNull);
    });
  });
}
