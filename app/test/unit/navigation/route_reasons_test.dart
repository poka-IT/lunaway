import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/trip_check.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../../helpers/navigation.dart';

const _limoges = LatLng(45.8472, 1.2848);
const _sarajevo = LatLng(43.86, 18.41);
const _dakhla = LatLng(23.6848, -15.958);
const _lille = LatLng(50.6292, 3.0573);

/// Countries as the device would read them for the points of these tests.
({String? at, List<String> near}) _around(LatLng p) => switch (p) {
  _sarajevo => (at: 'BA', near: const ['BA']),
  _dakhla => (at: 'EH', near: const ['EH']),
  _limoges || _lille => (at: 'FR', near: const ['FR']),
  // Bosnia, 600 m from the Croatian border at Metković: the graph's cut of
  // Croatia runs past the border, the server may still route it.
  LatLng(lat: 43.05) => (at: 'BA', near: const ['BA', 'HR']),
  _ => (at: null, near: const <String>[]),
};

/// Why a trip has no route, as the app reads the API and as it tells
/// before asking, from answers built on the backend's recordings of
/// 2026-10-07 (`test/fixtures/navigation/route_*_no_route.json`).
void main() {
  group('the reasons of an answer without a route', () {
    test('Toulouse: the destination, kept out by an IGN section at 3.20 m', () {
      final plan = routeFixture('toulouse_no_route');
      expect(plan.status, RouteStatus.noRoute);
      final reason = plan.noRouteReasons.single;
      expect(reason.kind, NoRouteReasonKind.destinationUnreachable);
      expect(reason.stopIndex, 1);
      final limit = reason.limits.single;
      expect(limit.kind, VehicleLimitKind.height);
      expect(limit.limit, 3.2);
      expect(limit.vehicleValue, 3.3);
      expect(limit.restriction!.externalId, 'ign/TRONROUT0000000073480284');
      expect(limit.restriction!.source, RestrictionSource.ign);
      expect(limit.restriction!.name, 'Chemin de Gabardie');
    });

    test('Porquerolles and the open sea: the stop, with no limit', () {
      final island = routeFixture('porquerolles_no_route').noRouteReasons.single;
      expect(island.kind, NoRouteReasonKind.notConnected);
      expect(island.stopIndex, 1);
      expect(island.limits, isEmpty);
      final sea = routeFixture('sea_off_network');
      expect(sea.status, RouteStatus.offNetwork);
      expect(sea.noRouteReasons.single.kind, NoRouteReasonKind.noRoadNearby);
    });

    test('a reason or a limit of a kind this app does not know is left out', () {
      final plan = routeFixture(
        'toulouse_no_route',
        edit: (answer) {
          final reasons = answer['noRouteReasons'] as List<dynamic>;
          ((reasons.single as Map<String, dynamic>)['limits'] as List<dynamic>).add({
            'kind': 'AXLE_COUNT',
            'limit': 2,
            'vehicleValue': 3,
            'restriction': null,
          });
          reasons.add({'kind': 'MOON_PHASE', 'stopIndex': 1, 'limits': <Object>[]});
        },
      );
      expect(plan.noRouteReasons.single.limits.single.kind, VehicleLimitKind.height);
    });

    test('an API before the reasons gives none, and the old screen stays', () {
      expect(routeFixture('braille_tall').noRouteReasons, isEmpty);
    });
  });

  group('the ferry crossings of a route', () {
    test('Piombino to Elba with ferries avoided: one crossing, its line, ports and country', () {
      final plan = routeFixture('elba_ferry');
      expect(plan.applied.avoid.ferries, isTrue);
      final route = plan.routes.single;
      expect(route.hasFerry, isTrue);
      final ferry = route.ferries.single;
      expect(ferry.name, 'Piombino - Portoferraio');
      expect(ferry.ports, ['Piombino', 'Portoferraio']);
      expect(ferry.fromCountry, 'IT');
      expect(ferry.toCountry, 'IT');
      expect(ferry.distanceM / 1000, inInclusiveRange(20, 35));
      expect(ferry.from!.distanceTo(const LatLng(42.9256, 10.5267)), lessThan(5000));
      expect(route.steps, isNotEmpty, reason: 'the shape reads from the recorded answer');
    });

    test('a notice of a kind this app does not know is left out', () {
      final plan = routeFixture(
        'elba_ferry',
        edit: (answer) {
          final route = (answer['routes'] as List<dynamic>).single as Map<String, dynamic>;
          (route['notices'] as List<dynamic>).add({'kind': 'ROUTE_CROSSES_BORDER', 'ferry': null});
        },
      );
      expect(plan.routes.single.ferries, hasLength(1));
    });
  });

  group('the routing information', () {
    test('names the covered countries, those that take reports and the longest trip', () {
      final info = routingInfoFromJson({
        'available': true,
        'graph': null,
        'disclaimerKey': 'routing.disclaimer.v1',
        'coveredArea': {'south': 20.4, 'west': -31.6, 'north': 81.05, 'east': 35.53},
        'coveredCountries': ['AD', 'MA'],
        'roadEventReportCountries': ['ES', 'FR'],
        'maxTripKm': 4500,
        'maxAlternatives': 2,
        'vehicleBounds': {
          for (final k in ['heightM', 'widthM', 'lengthM', 'weightT']) k: {'min': 1, 'max': 4},
        },
      });
      expect(info.coveredCountries, ['AD', 'MA']);
      expect(info.roadEventReportCountries, ['ES', 'FR']);
      expect(info.maxTripKm, 4500);
    });

    test('is asked once for several previews, and a failure is not kept', () async {
      var now = DateTime.utc(2026, 10, 7, 9);
      final inner = FakeRouteService(const [])..infoFailure = Exception('offline');
      final service = CachingRouteService(inner, clock: () => now);
      await expectLater(service.info(), throwsException);
      inner.infoFailure = null;
      expect((await service.info()).maxTripKm, 4500);
      await service.info();
      expect(inner.infoCalls, 2, reason: 'the failure, then one answer kept');
      now = now.add(const Duration(hours: 7));
      await service.info();
      expect(inner.infoCalls, 3, reason: 'read again with the graph of the week');
    });

    test('two asking at once share one request', () async {
      final inner = FakeRouteService(const []);
      final service = CachingRouteService(inner);
      await Future.wait([service.info(), service.info()]);
      expect(inner.infoCalls, 1);
    });
  });

  group('the trip checked before asking', () {
    List<NoRouteReason> check(List<LatLng> stops, {RoutingInfo info = europeRouting}) => checkTrip(
      stops: stops,
      covered: info.coveredCountries,
      maxTripKm: info.maxTripKm,
      countries: _around,
    );

    test('a destination in Bosnia is outside, named as the last stop', () {
      final reason = check([_limoges, _sarajevo]).single;
      expect(reason.kind, NoRouteReasonKind.outsideCoverage);
      expect(reason.stopIndex, 1);
    });

    test('a waypoint outside is named by its index, the others pass', () {
      final reasons = check([_limoges, _sarajevo, _lille]);
      expect(reasons.map((r) => (r.kind, r.stopIndex)), [(NoRouteReasonKind.outsideCoverage, 1)]);
    });

    test('a point within a kilometre of a covered country, or at sea, goes to the server', () {
      expect(check([_limoges, const LatLng(43.05, 17.62)]), isEmpty);
      expect(check([_limoges, const LatLng(45.5, -3)]), isEmpty);
    });

    test('Lille to Dakhla is within 4 500 km; past it, the trip is too long', () {
      expect(check([_lille, _dakhla]), isEmpty, reason: '3 415 km');
      final tooLong = check([_lille, _dakhla], info: _withMax(3000)).single;
      expect(tooLong.kind, NoRouteReasonKind.tripTooLong);
      expect(tooLong.tripKm, closeTo(3415, 20));
      expect(tooLong.maxKm, 3000);
    });

    test('an API that names no country and no bound leaves everything to the server', () {
      expect(check([_limoges, _sarajevo], info: olderRouting), isEmpty);
    });
  });

  group('the words of a reason', () {
    late Translations fr;
    late Translations en;
    setUpAll(() async {
      fr = await AppLocale.fr.build();
      en = await AppLocale.en.build();
    });

    test('the stop and what keeps the vehicle out, in one sentence', () {
      final reason = routeFixture('toulouse_no_route').noRouteReasons.single;
      expect(
        fr.noRouteTitle(reason, lastStop: 1),
        'Destination inaccessible avec votre véhicule : hauteur limitée à 3,20 m',
      );
      final warsaw = routeFixture('warsaw_no_route').noRouteReasons.single;
      expect(
        en.noRouteTitle(warsaw, lastStop: 1),
        'Destination out of reach for your vehicle: weight limit 1.5 t',
      );
    });

    test('a bridge, a waypoint, an island', () {
      const bridge = NoRouteReason(
        kind: NoRouteReasonKind.waypointUnreachable,
        stopIndex: 2,
        limits: [
          BlockingLimit(
            kind: VehicleLimitKind.height,
            limit: 3.2,
            vehicleValue: 3.3,
            restriction: RouteWarning(
              kind: RouteWarningKind.lowClearance,
              severity: WarningSeverity.blocking,
              distanceFromStartM: 0,
              geometryIndex: 0,
              position: LatLng(45, 1),
              source: RestrictionSource.osm,
              certainty: RestrictionCertainty.known,
              place: RestrictionPlace.bridge,
              externalId: 'way/1',
            ),
          ),
        ],
      );
      expect(
        fr.noRouteTitle(bridge, lastStop: 3),
        'Étape 2 inaccessible avec votre véhicule : pont à 3,20 m',
      );
      expect(
        fr.noRouteTitle(
          const NoRouteReason(kind: NoRouteReasonKind.notConnected, stopIndex: 1),
          lastStop: 1,
        ),
        'Aucune route ne mène à la destination',
      );
    });

    test('the covered countries by name, in alphabetical order, without the territories', () {
      expect(
        fr.countryList(['MA', 'FR', 'AX', 'ES', 'AD', 'GI']),
        'Andorre, Espagne, France, Maroc',
      );
      expect(en.countryList(['XK', 'NL']), 'Netherlands, XK');
    });
  });
}

RoutingInfo _withMax(double km) => RoutingInfo(
  available: true,
  disclaimerKey: europeRouting.disclaimerKey,
  coveredArea: europeRouting.coveredArea,
  maxAlternatives: 2,
  bounds: europeRouting.bounds,
  coveredCountries: europeRouting.coveredCountries,
  maxTripKm: km,
);
