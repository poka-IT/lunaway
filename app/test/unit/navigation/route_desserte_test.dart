import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../../helpers/navigation.dart';

/// A limit that spares local access, and the stops the server moved
/// (`plan/research/65-accroche-et-desserte.md`), as the app reads and says
/// them.
RouteWarning desserte(
  RouteWarningKind kind,
  double limit, {
  WarningSeverity severity = WarningSeverity.warning,
}) => RouteWarning(
  kind: kind,
  severity: severity,
  limit: limit,
  vehicleValue: 4.5,
  distanceFromStartM: 0,
  geometryIndex: 0,
  position: const LatLng(43.858, 5.2285),
  source: RestrictionSource.osm,
  certainty: RestrictionCertainty.known,
  place: RestrictionPlace.road,
  externalId: 'way/109270742',
  exceptDestination: true,
);

/// The van's route under the Utrillo bridge, with a street for local access
/// and its destination moved, as the API answers since 2026-10-08.
RoutePlan moved() => routeFixture(
  'utrillo_van',
  edit: (answer) {
    answer['movedStops'] = [
      {'stopIndex': 1, 'lat': 45.8452, 'lon': 1.2862, 'distanceM': 120.0},
    ];
    final route = (answer['routes'] as List<dynamic>).first as Map<String, dynamic>;
    ((route['warnings'] as List<dynamic>).first as Map<String, dynamic>)
      ..['kind'] = 'TOO_HEAVY'
      ..['limit'] = 3.5
      ..['vehicleValue'] = 4.5
      ..['place'] = 'ROAD'
      ..['certainty'] = 'KNOWN'
      ..['exceptDestination'] = true;
  },
);

void main() {
  late Translations fr;
  late Translations en;

  setUpAll(() async {
    fr = await AppLocale.fr.build();
    en = await AppLocale.en.build();
  });

  group('a limit that spares local access', () {
    test('is read from the answer, and an older answer has none', () {
      final plan = moved();
      final w = plan.routes.single.warnings.single;
      expect(w.exceptDestination, isTrue);
      expect(w.kind, RouteWarningKind.tooHeavy);
      expect(
        routeFixture('utrillo_van').routes.single.warnings.single.exceptDestination,
        isFalse,
        reason: 'an API before 2026-10-08 does not tell: a plain limit',
      );
    });

    test('says the street is for local access, with the sign figure', () {
      expect(
        fr.warningTitle(desserte(RouteWarningKind.tooHeavy, 3.5)),
        'Accès riverains (desserte) : interdit aux plus de 3,5 t sauf pour rejoindre votre '
        'destination',
      );
      expect(
        en.warningTitle(desserte(RouteWarningKind.tooHeavy, 3.5)),
        'Local access only: no vehicles over 3.5 t except to reach your destination',
      );
      expect(
        fr.warningTitle(desserte(RouteWarningKind.narrow, 2.3)),
        'Accès riverains (desserte) : interdit aux plus de 2,30 m de large sauf pour rejoindre '
        'votre destination',
      );
      expect(
        fr.warningTitle(
          desserte(RouteWarningKind.tooHeavy, 3.5, severity: WarningSeverity.blocking),
        ),
        startsWith('Accès riverains (desserte)'),
        reason: 'a blocker of NO_SAFE_ROUTE: the route would cross the zone',
      );
    });

    test('a reason without a route keeps the nuance', () {
      final limit = BlockingLimit(
        kind: VehicleLimitKind.weight,
        limit: 3.5,
        vehicleValue: 4.5,
        restriction: desserte(RouteWarningKind.tooHeavy, 3.5, severity: WarningSeverity.blocking),
      );
      expect(fr.blockingLimit(limit), 'poids limité à 3,5 t sauf desserte');
      expect(en.blockingLimit(limit), 'weight limit 3.5 t, local access only');
      expect(
        fr.blockingLimit(const BlockingLimit(kind: VehicleLimitKind.weight, limit: 3.5)),
        'poids limité à 3,5 t',
      );
    });

    test('is spoken in guidance', () {
      final w = TranslatedWording(fr, DistanceUnits.metric);
      expect(
        w.warningAhead(desserte(RouteWarningKind.tooHeavy, 3.5), 300),
        'Attention, dans 300 mètres, accès riverains : plus de 3,5 tonnes seulement pour la '
        'desserte.',
      );
      expect(
        TranslatedWording(
          en,
          DistanceUnits.metric,
        ).warningAhead(desserte(RouteWarningKind.tooHeavy, 3.5), 300),
        'Caution, in 300 metres, local access only above 3.5 tonnes.',
      );
      expect(
        w.warningAhead(desserte(RouteWarningKind.narrow, 2.3), 300),
        'Attention, dans 300 mètres, accès riverains : plus de 2 mètres 30 de large seulement '
        'pour la desserte.',
        reason: 'a width is not taken for a weight',
      );
      expect(w.warningAhead(desserte(RouteWarningKind.axleLoad, 10), 300), contains('par essieu'));
    });
  });

  group('a stop the server moved', () {
    test('is read from the answer, where the route ends', () {
      final plan = moved();
      expect(plan.movedStops.single.stopIndex, 1);
      expect(plan.movedTo(1), const LatLng(45.8452, 1.2862));
      expect(plan.movedTo(0), isNull);
      expect(routeFixture('utrillo_van').movedStops, isEmpty);
    });

    test('is told by its place in the trip and its distance', () {
      const m = MovedStop(stopIndex: 2, position: LatLng(43.3023, 5.3799), distanceM: 120);
      expect(
        fr.movedStop(m, lastStop: 2, units: DistanceUnits.metric),
        "Point d'arrivée déplacé de 120 m vers la rue accessible la plus proche",
      );
      expect(
        fr.movedStop(
          const MovedStop(stopIndex: 0, position: LatLng(43.6087, 3.8807), distanceM: 80),
          lastStop: 2,
          units: DistanceUnits.metric,
        ),
        'Point de départ déplacé de 80 m vers la rue accessible la plus proche',
      );
      expect(
        en.movedStop(
          const MovedStop(stopIndex: 1, position: LatLng(45, 1), distanceM: 141),
          lastStop: 2,
          units: DistanceUnits.metric,
        ),
        'Stop 1 moved 140 m to the nearest street your vehicle can reach',
      );
    });

    test('is said by the guidance, in each language', () {
      const end = MovedStop(stopIndex: 2, position: LatLng(43.3023, 5.3799), distanceM: 120);
      const stop = MovedStop(stopIndex: 1, position: LatLng(45, 1), distanceM: 141);
      final frWords = TranslatedWording(fr, DistanceUnits.metric);
      final enWords = TranslatedWording(en, DistanceUnits.metric);
      expect(
        frWords.moved(end, lastStop: 2),
        "Point d'arrivée déplacé de 120 mètres vers la rue accessible la plus proche.",
      );
      expect(
        frWords.moved(stop, lastStop: 2),
        'Étape 1 déplacée de 140 mètres vers la rue accessible la plus proche.',
      );
      expect(
        enWords.moved(end, lastStop: 2),
        'Destination moved 120 metres to the nearest street your vehicle can reach.',
      );
      expect(
        enWords.moved(stop, lastStop: 2),
        'Stop 1 moved 140 metres to the nearest street your vehicle can reach.',
      );
      expect(
        TranslatedWording(en, DistanceUnits.imperial).moved(end, lastStop: 2),
        'Destination moved 400 feet to the nearest street your vehicle can reach.',
      );
    });
  });

  group('the request', () {
    final vehicle = checkVehicle(motorhome).profile!;
    Map<String, Object?> origin(Map<String, Object?> vars) =>
        (vars['input']! as Map<String, Object?>)['origin']! as Map<String, Object?>;

    test('marks the vehicle own position during guidance, never a point of the map', () {
      final driving = routeVariables(
        origin: const LatLng(45.84719, 1.28476),
        destination: const LatLng(45.84510, 1.28637),
        vehicle: vehicle,
        avoid: const AvoidOptions(),
        language: RouteLanguage.fr,
        fromVehicle: true,
      );
      expect(origin(driving)['vehiclePosition'], isTrue);
      final planned = routeVariables(
        origin: const LatLng(45.84719, 1.28476),
        destination: const LatLng(45.84510, 1.28637),
        vehicle: vehicle,
        avoid: const AvoidOptions(),
        language: RouteLanguage.fr,
      );
      expect(
        origin(planned)['vehiclePosition'],
        isFalse,
        reason: 'the preview may have its start moved: an origin that says nothing would not',
      );
    });

    test('leaves the flag out for every older API', () {
      final driving = routeVariables(
        origin: const LatLng(45.84719, 1.28476),
        destination: const LatLng(45.84510, 1.28637),
        vehicle: vehicle,
        avoid: const AvoidOptions(),
        language: RouteLanguage.fr,
        headingDeg: 90,
        fromVehicle: true,
      );
      var n = 0;
      for (var form = routeOperation.older; form != null; form = form.older) {
        n++;
        final sent = origin(form.variables(driving));
        expect(sent, isNot(contains('vehiclePosition')), reason: 'form $n');
        expect(sent['headingDeg'], 90, reason: 'the course still goes');
      }
      expect(n, 4);
    });
  });
}
