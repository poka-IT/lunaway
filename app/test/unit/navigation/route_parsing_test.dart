import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';

import '../../helpers/navigation.dart';

/// The answers of the API's `route` query as the app reads them, from
/// answers recorded on 2026-10-06 (`test/fixtures/navigation/`).
void main() {
  group('a route answer', () {
    test('Aix to Marseille at night: the events met and the closures gone around', () {
      final plan = routeFixture('aix_marseille_closures');
      final events = plan.routes.single.roadEvents;
      expect(events, hasLength(4));
      final first = events.first;
      expect(first.event.eventClass, RoadEventClass.laneRestriction);
      expect(first.event.road, 'A51');
      expect(first.reason, RoadEventReason.laneRestriction);
      expect(first.weight, RoadEventWeight.warning);
      expect(first.distanceFromStartM, closeTo(3160.5, 0.1));
      expect(first.dataAt, DateTime.parse('2026-10-06T20:38:47.033Z'));
      expect(events[1].reason, RoadEventReason.unmatched);
      expect(plan.avoidedRoadEvents.map((e) => e.road), [
        'Tunnel de la Joliette',
        'Tunnel du Vieux-Port',
      ]);
      expect(plan.sourceOf('aix-marseille-tunnels')?.attribution, contains('Aix-Marseille'));
    });

    test('Rue Maurice Utrillo at 3.30 m: the recommended route and one alternative', () {
      final plan = routeFixture('utrillo_motorhome');
      expect(plan.status, RouteStatus.ok);
      expect(plan.routes.map((r) => r.index), [0, 1]);
      expect(plan.routes.first.distanceM, closeTo(1812.279, 0.001));
      expect(plan.routes.first.durationS, closeTo(191.341, 0.001));
      expect(plan.applied.vehicle.heightM, 3.3);
      expect(plan.applied.vehicle.type, RouterVehicleType.integrated);
      expect(plan.applied.language, RouteLanguage.fr);
      expect(plan.disclaimerKey, 'routing.disclaimer.v1');
      expect(plan.graph.osmDataAt, DateTime.parse('2026-10-04T20:20:21Z'));
      expect(plan.graph.ignEdition, DateTime(2026, 6, 15));
    });

    test('the speed the times assume is told only when the driver set one', () {
      void cruise(Map<String, dynamic> answer, int? asked, int? top) {
        final reroute = answer['reroute'] as Map<String, dynamic>;
        (reroute['vehicle'] as Map<String, dynamic>)['cruiseSpeedKph'] = asked;
        reroute['topSpeedKph'] = top;
      }

      // 120 asked by a motorhome over 3.5 t: the server kept to its 110.
      final capped = routeFixture('utrillo_motorhome', edit: (a) => cruise(a, 120, 110)).applied;
      expect(capped.vehicle.cruiseSpeedKph, 120, reason: 'what a recalculation sends again');
      expect(capped.topSpeedKph, 110);
      expect(capped.cruiseShownKph, 110);
      final legalOnly = routeFixture('utrillo_motorhome', edit: (a) => cruise(a, null, 110));
      expect(legalOnly.applied.cruiseShownKph, isNull, reason: 'the law, not a choice to recall');
      expect(routeFixture('utrillo_motorhome').applied.cruiseShownKph, isNull);
    });

    test('a 2.50 m van under the 2.70 m bridge carries the warning with its place', () {
      final w = routeFixture('utrillo_van').routes.single.warnings.single;
      expect(w.kind, RouteWarningKind.lowClearance);
      expect(w.severity, WarningSeverity.warning);
      expect(w.limit, 2.7);
      expect(w.vehicleValue, 2.5);
      expect(w.place, RestrictionPlace.underpass);
      expect(w.certainty, RestrictionCertainty.disputed);
      expect(w.source, RestrictionSource.osm);
      expect(w.externalId, 'way/52984577');
      expect(w.name, 'Rue Maurice Utrillo');
      expect(w.geometryIndex, 8);
      expect(w.position, const LatLng(45.846841, 1.285024));
    });

    test('the 1.90 m height bar of Rue de la Brégère stops every route', () {
      final plan = routeFixture('bregere_bar');
      expect(plan.status, RouteStatus.noSafeRoute);
      expect(plan.osrmJson, isNull);
      expect(plan.routes, isEmpty);
      final b = plan.blockers.single;
      expect(b.severity, WarningSeverity.blocking);
      expect(b.place, RestrictionPlace.barrier);
      expect(b.limit, 1.9);
      expect(b.vehicleValue, 3.3);
    });

    test('no road to the destination', () {
      expect(routeFixture('braille_tall').status, RouteStatus.noRoute);
    });

    test('a long trip says it uses a toll motorway', () {
      final route = routeFixture('brive_ussel_en').routes.single;
      expect(route.hasToll, isTrue);
      expect(route.hasMotorway, isTrue);
      expect(route.hasFerry, isFalse);
      expect(route.steps, hasLength(33));
      expect(route.steps.first.instruction, startsWith('Drive'));
    });

    test('an unknown kind of warning from a newer server is left out, the route kept', () {
      final json = routeAnswer('utrillo_van');
      final routes = json['routes'] as List<dynamic>;
      final warning = Map<String, dynamic>.of(
        ((routes.first as Map<String, dynamic>)['warnings'] as List<dynamic>).first
            as Map<String, dynamic>,
      )..['kind'] = 'SNOW_CHAINS';
      (routes.first as Map<String, dynamic>)['warnings'] = [warning];
      final plan = routePlanFromJson(json);
      expect(plan.routes.single.warnings, isEmpty);
    });

    test(
      'a goods vehicle weight limit of a DiaLog order is kept, as the road events schema adds',
      () {
        final json = routeAnswer('utrillo_van');
        final routes = json['routes'] as List<dynamic>;
        final warning =
            Map<String, dynamic>.of(
                ((routes.first as Map<String, dynamic>)['warnings'] as List<dynamic>).first
                    as Map<String, dynamic>,
              )
              ..['kind'] = 'GOODS_VEHICLE_WEIGHT'
              ..['source'] = 'DIALOG'
              ..['limit'] = 3.5;
        (routes.first as Map<String, dynamic>)['warnings'] = [warning];
        final w = routePlanFromJson(json).routes.single.warnings.single;
        expect(w.kind, RouteWarningKind.goodsVehicleWeight);
        expect(w.source, RestrictionSource.dialog);
      },
    );
  });

  group('the shape of a route', () {
    test('the line starts at the depart maneuver and ends at the arrival', () {
      final route = routeFixture('limoges_drive').routes.single;
      expect(route.line.length, greaterThan(50));
      expect(route.line.first.distanceTo(route.steps.first.position), lessThan(1));
      expect(route.line.last.distanceTo(route.steps.last.position), lessThan(1));
      var length = 0.0;
      for (var i = 1; i < route.line.length; i++) {
        length += route.line[i - 1].distanceTo(route.line[i]);
      }
      expect(length, closeTo(route.distanceM, route.distanceM * 0.01));
    });

    test('steps keep their maneuver, their road and the lanes at the next maneuver', () {
      final steps = routeFixture('limoges_drive').routes.single.steps;
      expect(steps, hasLength(10));
      expect(steps.first.maneuverType, 'depart');
      expect(steps.last.maneuverType, 'arrive');
      expect(steps[1].modifier, 'left');
      expect(steps[1].roadName, 'Boulevard Carnot');
      // Place Jourdan ends where the route bears right, through a junction
      // whose lanes Valhalla puts 22 and 39 m before the maneuver.
      final jourdan = steps[3].lanes;
      expect(steps[3].roadName, 'Place Jourdan');
      expect([for (final l in jourdan) l.active], [false, true, true]);
      expect(jourdan.first.directions, ['left']);
      expect(jourdan[1].follows, 'straight', reason: 'the route goes on from this lane');
      // The lanes of a junction 160 m before the slight left onto Port du
      // Naveix are that junction's, not the turn's.
      expect(steps[4].roadName, 'Avenue des Bénédictins');
      expect(steps[4].lanes, isEmpty);
    });

    test('a roundabout knows its exit and how far round it lies, entering and leaving', () {
      // Limoges, Place Maison-Dieu: the second exit, 212 degrees round
      // (the router's banner), a little left of straight on.
      final steps = routeFixture('limoges_stop').routes.single.steps;
      final into = steps.firstWhere((s) => s.maneuverType == 'roundabout');
      final out = steps.firstWhere((s) => s.maneuverType == 'exit roundabout');
      expect((into.exit, into.exitDegrees, into.leftHandTraffic), (2, 212, false));
      expect((out.exit, out.exitDegrees), (2, 212), reason: 'leaving, the ring is drawn the same');
      expect(steps.first.exitDegrees, isNull);
    });

    test('without banners the exit comes from the headings around the ring', () {
      // The Elba answer has no banners: the first roundabout is entered at
      // 98 degrees and left at 101, three degrees right of straight on.
      final steps = routeFixture('elba_ferry').routes.single.steps;
      final into = steps.firstWhere((s) => s.maneuverType == 'roundabout');
      expect((into.exit, into.exitDegrees), (1, 177));
      expect(steps.where((s) => s.ferry).map((s) => s.maneuverType), ['notification']);
    });

    test('where traffic keeps left, the way round the ring is clockwise', () {
      final steps = routeFixture(
        'elba_ferry',
        edit: (answer) {
          final osrm = jsonDecode(answer['osrmJson'] as String) as Map<String, dynamic>;
          for (final r in osrm['routes'] as List) {
            for (final leg in (r as Map<String, dynamic>)['legs'] as List) {
              for (final step in (leg as Map<String, dynamic>)['steps'] as List) {
                (step as Map<String, dynamic>)['driving_side'] = 'left';
              }
            }
          }
          answer['osrmJson'] = jsonEncode(osrm);
        },
      ).routes.single.steps;
      final into = steps.firstWhere((s) => s.maneuverType == 'roundabout');
      expect((into.leftHandTraffic, into.exitDegrees), (true, 183));
    });

    test('the banner shows the next step, with the exit counted by the roundabout step', () {
      final steps = routeFixture('limoges_stop').routes.single.steps;
      final at = steps.indexWhere((s) => s.maneuverType == 'roundabout');
      // Before the ring: the engine's banner names the roundabout.
      expect(
        bannerManeuver(
          banner: const ManeuverBanner(
            primary: 'Place Maison-Dieu',
            maneuverType: 'roundabout',
            modifier: 'slight right',
            roundaboutExitDegrees: 212,
          ),
          steps: steps,
          stepIndex: at - 1,
        ),
        const Maneuver(
          type: 'roundabout',
          modifier: 'slight right',
          exitDegrees: 212,
          exitNumber: 2,
        ),
      );
      // In the ring: the banner names the way out.
      final inRing = bannerManeuver(
        banner: const ManeuverBanner(
          primary: 'Place Maison-Dieu',
          maneuverType: 'exit roundabout',
          modifier: 'slight right',
          roundaboutExitDegrees: 212,
        ),
        steps: steps,
        stepIndex: at,
      );
      expect((inRing.exitNumber, inRing.exitDegrees), (2, 212));
      // Without a banner, the next step says it all.
      expect(bannerManeuver(banner: null, steps: steps, stepIndex: at - 1), steps[at].maneuver);
    });

    test('a polyline6 decodes as Valhalla encodes it, and a cut one stops cleanly', () {
      // Two points of the Utrillo route, encoded by Valhalla.
      final points = decodePolyline('yhhmvAshlmAD_@');
      expect(points, hasLength(2));
      expect(points.first.lat, closeTo(45.847197, 1e-6));
      expect(points.first.lon, closeTo(1.284762, 1e-6));
      expect(points.last.lat, closeTo(45.847194, 1e-6), reason: 'a step south');
      expect(points.last.lon, closeTo(1.284778, 1e-6));
      expect(decodePolyline('yhhmvAshlmAD'), hasLength(1));
    });

    test('negative coordinates and steps decode, as in the format reference', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5);
      expect(
        [for (final p in points) (p.lat, p.lon)],
        [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)],
      );
    });
  });

  group('the request', () {
    test('sends the profile, the avoid options, the language and the heading', () {
      final vars = routeVariables(
        origin: const LatLng(45.8, 1.2),
        destination: const LatLng(45.9, 1.3),
        vehicle: const VehicleProfile(
          type: RouterVehicleType.overcab,
          heightM: 3.15,
          widthM: 2.3,
          lengthM: 7,
          weightT: 3.5,
          trailer: assumedTrailer,
        ),
        avoid: const AvoidOptions(tolls: true, unpaved: true),
        language: RouteLanguage.en,
        headingDeg: 370,
        alternatives: 2,
      );
      final input = vars['input']! as Map<String, Object?>;
      expect(input['origin'], {
        'lat': 45.8,
        'lon': 1.2,
        'headingDeg': 10,
        'vehiclePosition': false,
      });
      expect(input['language'], 'EN');
      expect(input['alternatives'], 2);
      expect(input['options'], {
        'avoidTolls': true,
        'avoidMotorways': false,
        'avoidFerries': false,
        'avoidUnpaved': true,
      });
      expect(input['vehicle'], {
        'kind': 'OVERCAB',
        'heightM': 3.15,
        'widthM': 2.3,
        'lengthM': 7,
        'weightT': 3.5,
        'trailer': {'lengthM': 4.78, 'weightT': 1.5, 'widthM': 2.1},
      });
    });
  });
}
