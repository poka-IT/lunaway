import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/data/road_events_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';

import '../helpers/navigation.dart';
import 'graphql_validator.dart';

/// The routing operations against the schema the server exports, and the
/// answers recorded from the deployed API against the same schema: when
/// either side moves, this names what drifted.
void main() {
  final schemaText = File('../schema/lunaway.graphql').readAsStringSync();
  final validator = SchemaValidator(schemaText);

  for (final op in navigationOperations) {
    test('${op.name} is valid against schema/lunaway.graphql', () {
      expect(validator.validate(op.document), isEmpty);
    });
  }

  test('a route request sends what the schema asks for', () {
    final vars = routeVariables(
      origin: const LatLng(45.84719, 1.28476),
      destination: const LatLng(45.84510, 1.28637),
      vehicle: checkVehicle(motorhome.copyWith(cruiseSpeedKph: () => 95)).profile!,
      avoid: const AvoidOptions(tolls: true),
      language: RouteLanguage.fr,
      headingDeg: 132,
      alternatives: 2,
    );
    expect(validator.checkVariables(routeOperation.document, vars), isEmpty);
    final vehicle = (vars['input']! as Map<String, Object?>)['vehicle']! as Map<String, Object?>;
    expect(vehicle['cruiseSpeedKph'], 95, reason: 'the route is timed at the speed set');
  });

  test('a route with stops sends them as the schema asks', () {
    final vars = routeVariables(
      origin: const LatLng(45.84719, 1.28476),
      destination: const LatLng(45.84510, 1.28637),
      vehicle: checkVehicle(motorhome).profile!,
      avoid: const AvoidOptions(),
      language: RouteLanguage.fr,
      stops: const [LatLng(45.8335, 1.2610), LatLng(45.8409, 1.2705)],
    );
    expect(validator.checkVariables(routeOperation.document, vars), isEmpty);
  });

  test('the fuel stations around a point are asked as the schema allows', () {
    expect(validator.validate(fuelNearOperation.document), isEmpty);
    expect(
      validator.checkVariables(fuelNearOperation.document, {
        'at': {'lat': 45.8, 'lon': 1.26},
        'radiusM': 5000.0,
      }),
      isEmpty,
    );
  });

  for (final name in [
    'utrillo_motorhome',
    'utrillo_van',
    'bregere_bar',
    'under_bridge',
    'braille_tall',
    'limoges_drive',
    'brive_ussel_en',
    'aix_marseille_closures',
  ]) {
    // Recorded before the routes carried their speed limits: they answer
    // the oldest form of the request, without them. The Aix-Marseille answer predates the
    // events' heading, limits and dates too: those were added to it empty
    // (its first-seen date is its validity start).
    test('the recorded answer $name matches the selection', () {
      final body = jsonDecode(
        File('test/fixtures/navigation/route_$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        validator.checkResponse(
          routeOperation.older!.older!.older!.document,
          body['data'] as Map<String, dynamic>,
        ),
        isEmpty,
      );
    });
  }

  test('a route with its speed limits, recorded on 2026-10-06 (road event fields added empty, '
      'the API had none then), matches the selection', () {
    final body = jsonDecode(
      File('test/fixtures/navigation/route_a20_limits.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    // Recorded before the reasons and the crossings: the form without them.
    expect(validator.checkResponse(routeOperation.older!.older!.document, data), isEmpty);
    final route = routePlanFromJson(data['route'] as Map<String, dynamic>).routes.single;
    final limits = route.speedLimits!;
    expect(limits.first.kmh, 50);
    expect(limits.map((l) => l.source), contains(SpeedLimitSource.vehicle));
    expect(limits.map((l) => l.source), contains(SpeedLimitSource.estimated));
    expect(spanAt(limits, 10000)!.kmh, 110, reason: 'the A20 north of Limoges');
  });

  test('the route request without the speed limits is valid too, for an API without them', () {
    final older = routeOperation.older!.older!.older!;
    expect(older.withoutFields, isTrue);
    expect(validator.validate(older.document), isEmpty);
    expect(older.document, isNot(contains('speedLimits')));
    expect(routeOperation.document, contains('speedLimits'));
  });

  // The API in production before the reasons, the crossings and the
  // covered countries (schema of 26961d1): the app falls back one step to
  // it, and keeps the speed limits it knows.
  group('against the API before 2026-10-07', () {
    final before = SchemaValidator(
      File('test/fixtures/schema_before_europe.graphql').readAsStringSync(),
    );

    // The route's form for that API comes after the one for the API
    // before the cruising speed.
    for (final (op, older) in [
      (routeOperation, routeOperation.older!.older!),
      (routingInfoOperation, routingInfoOperation.older!),
    ]) {
      test('${op.name} needs its older form there, which is valid on both APIs', () {
        expect(before.validate(op.document), isNotEmpty, reason: 'else no older form is needed');
        expect(before.validate(older.document), isEmpty);
        expect(validator.validate(older.document), isEmpty);
        expect(older.withoutFields, isTrue);
      });
    }

    test('the route keeps its speed limits in the form for that API', () {
      final older = routeOperation.older!.older!.document;
      expect(older, contains('speedLimits'));
      expect(older, isNot(contains('noRouteReasons')));
      expect(older, isNot(contains('notices')));
      expect(routingInfoOperation.older!.document, isNot(contains('coveredCountries')));
    });
  });

  // The API in production before the cruising speed (schema of 72fa47c):
  // the route falls back one step, without the speed, and keeps the rest.
  group('against the API before the cruising speed', () {
    final before = SchemaValidator(
      File('test/fixtures/schema_before_cruise.graphql').readAsStringSync(),
    );
    final vars = routeVariables(
      origin: const LatLng(45.84719, 1.28476),
      destination: const LatLng(45.84510, 1.28637),
      vehicle: checkVehicle(motorhome.copyWith(cruiseSpeedKph: () => 90)).profile!,
      avoid: const AvoidOptions(),
      language: RouteLanguage.fr,
    );

    test('a route with a cruising speed needs the older form there', () {
      expect(before.validate(routeOperation.document), isNotEmpty);
      expect(before.checkVariables(routeOperation.older!.document, vars), isNotEmpty);
    });

    test('the older form leaves the speed out and keeps the reasons and the limits', () {
      final older = routeOperation.older!;
      expect(older.withoutFields, isTrue);
      expect(before.validate(older.document), isEmpty);
      expect(validator.validate(older.document), isEmpty);
      final sent = older.variables(vars);
      expect(before.checkVariables(older.document, sent), isEmpty);
      final vehicle = (sent['input']! as Map<String, Object?>)['vehicle']! as Map<String, Object?>;
      expect(vehicle, isNot(contains('cruiseSpeedKph')));
      expect(vehicle['heightM'], 3.3, reason: 'the rest of the vehicle goes');
      expect(older.document, contains('noRouteReasons'));
      expect(older.document, contains('speedLimits'));
      for (var form = older.older; form != null; form = form.older) {
        expect(form.variables(vars).toString(), isNot(contains('cruiseSpeedKph')));
      }
    });
  });

  for (final name in [
    'toulouse_no_route',
    'warsaw_no_route',
    'porquerolles_no_route',
    'sea_off_network',
    'elba_ferry',
  ]) {
    // Recorded before the cruising speed: the form without it.
    test('the answer $name, built from the backend recordings, matches the selection', () {
      final body = jsonDecode(
        File('test/fixtures/navigation/route_$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        validator.checkResponse(
          routeOperation.older!.document,
          body['data'] as Map<String, dynamic>,
        ),
        isEmpty,
      );
    });
  }

  // The road events delta lands with the backend's road events
  // (plan/research/21-backend-travaux.md); until the schema has it, the
  // document cannot be checked, and the app's source treats the server's
  // refusal as no events.
  test(
    'RoadEvents is valid against schema/lunaway.graphql',
    () => expect(validator.validate(roadEventsOperation.document), isEmpty),
    skip: schemaText.contains('roadEvents(')
        ? null
        : 'the schema has no roadEvents query yet (backend road events not merged)',
  );
}
