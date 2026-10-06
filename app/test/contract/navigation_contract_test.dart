import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/fuel_stations_api.dart';
import 'package:lunaway/features/navigation/data/road_events_api.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';

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
      vehicle: checkVehicle(motorhome).profile!,
      avoid: const AvoidOptions(tolls: true),
      language: RouteLanguage.fr,
      headingDeg: 132,
      alternatives: 2,
    );
    expect(validator.checkVariables(routeOperation.document, vars), isEmpty);
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
  ]) {
    test('the recorded answer $name matches the selection', () {
      final body = jsonDecode(
        File('test/fixtures/navigation/route_$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        validator.checkResponse(routeOperation.document, body['data'] as Map<String, dynamic>),
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
