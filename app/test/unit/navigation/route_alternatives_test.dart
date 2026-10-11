import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';

import '../../helpers/navigation.dart';

/// The best route sent alone and its alternatives after it
/// (`routeAlternatives`), as the app reads and joins them.
void main() {
  Map<String, dynamic> osrmOf(RoutePlan plan) => jsonDecode(plan.osrmJson!) as Map<String, dynamic>;

  /// The recorded Utrillo answer with only its best route, and its token.
  RoutePlan bestAlone() => routeFixture(
    'utrillo_motorhome',
    edit: (a) {
      final osrm = jsonDecode(a['osrmJson'] as String) as Map<String, dynamic>;
      a['osrmJson'] = jsonEncode({
        ...osrm,
        'routes': (osrm['routes'] as List<dynamic>).sublist(0, 1),
      });
      a['routes'] = (a['routes'] as List<dynamic>).sublist(0, 1);
      a['alternativesToken'] = 'token-1';
    },
  );

  /// Its alternative, numbered 0 in an answer of its own.
  LaterRoutes alternative() {
    final full = routeFixture('utrillo_motorhome');
    final osrm = osrmOf(full);
    final summary = jsonDecode(
      jsonEncode((routeAnswer('utrillo_motorhome')['routes'] as List<dynamic>)[1]),
    );
    return laterRoutesFromJson({
      'status': 'OK',
      'osrmJson': jsonEncode({...osrm, 'routes': (osrm['routes'] as List<dynamic>).sublist(1)}),
      'routes': [
        {...summary as Map<String, dynamic>, 'index': 0},
      ],
    });
  }

  test('the token of a best route sent alone is read with it', () {
    final plan = bestAlone();
    expect(plan.alternativesToken, 'token-1');
    expect(plan.routes, hasLength(1));
    expect(routeFixture('utrillo_motorhome').alternativesToken, isNull);
  });

  test('the alternatives follow the routes there, each read in its own answer', () {
    final plan = bestAlone();
    final later = alternative();
    final joined = plan.withAlternatives(later);
    expect(joined.routes.map((r) => r.index), [0, 1]);
    expect(joined.routes[1].distanceM, later.routes.single.distanceM);
    expect(joined.alternativesToken, isNull, reason: 'a token serves once');
    expect(joined.osrmOf(0), (json: plan.osrmJson!, index: 0));
    expect(joined.osrmOf(1), (
      json: later.osrmJson!,
      index: 0,
    ), reason: 'the guidance engine reads the alternative where it came');
    expect(joined.cameLater(joined.routes[0]), isFalse);
    expect(joined.cameLater(joined.routes[1]), isTrue);
    expect(
      routeFixture('utrillo_motorhome').cameLater(routeFixture('utrillo_motorhome').routes[1]),
      isFalse,
      reason: 'every route of one answer came at once',
    );
  });

  test('alternatives that did not come change nothing', () {
    final plan = bestAlone();
    expect(identical(plan.withAlternatives(LaterRoutes.none), plan), isTrue);
    expect(
      laterRoutesFromJson({'status': 'SOMETHING_NEW', 'osrmJson': null, 'routes': <Object>[]})
          .status,
      LaterStatus.none,
      reason: 'a status of a newer server leaves the best route alone',
    );
  });

  test('a token is asked once: a preview opened again gets the same alternatives', () async {
    final inner = FakeRouteService(const [])..later['token-1'] = alternative();
    final service = CachingRouteService(inner);
    final first = await service.alternatives('token-1');
    final again = await service.alternatives('token-1');
    expect(identical(first, again), isTrue);
    expect(inner.laterAsked, ['token-1'], reason: 'the server serves a token once');
  });
}
