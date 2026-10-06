import 'package:flutter/foundation.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/route_operations.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';

/// A route request: from a point to a destination, for a vehicle.
@immutable
final class RouteRequest {
  const new({
    required this.origin,
    required this.destination,
    required this.vehicle,
    required this.avoid,
    required this.language,
    this.headingDeg,
    this.alternatives = 0,
  });

  final LatLng origin;
  final LatLng destination;
  final VehicleProfile vehicle;
  final AvoidOptions avoid;
  final RouteLanguage language;

  /// The vehicle's course, for a recalculation: the route leaves that way.
  final double? headingDeg;

  /// Routes wanted besides the best one (0 to 2).
  final int alternatives;
}

/// Why a route request failed, each with its own message.
enum RouteFailureKind {
  /// No network, or the server did not answer.
  offline,

  /// Too many routes asked lately; [RouteFailure.retryAfter] says when.
  rateLimited,

  /// The routing engine or its data is down.
  unavailable,

  /// The server refused the request (a point outside the covered area, a
  /// figure out of bounds).
  refused,
}

final class RouteFailure implements Exception {
  const new(this.kind, {this.retryAfter, this.message});

  final RouteFailureKind kind;
  final Duration? retryAfter;
  final String? message;

  @override
  String toString() => 'RouteFailure($kind${message == null ? '' : ': $message'})';
}

/// Routes from the Lunaway API, and nowhere else: the app never asks a
/// third party for a route.
abstract interface class RouteService {
  Future<RoutePlan> route(RouteRequest request);

  Future<RoutingInfo> info();
}

final class GraphQLRouteService implements RouteService {
  new(this._client);

  final GraphQLClient _client;

  @override
  Future<RoutePlan> route(RouteRequest r) async {
    final plan = await _guard(
      () => _client.execute(
        routeOperation,
        routeVariables(
          origin: r.origin,
          destination: r.destination,
          vehicle: r.vehicle,
          avoid: r.avoid,
          language: r.language,
          headingDeg: r.headingDeg,
          alternatives: r.alternatives,
        ),
      ),
    );
    return await withShapes(plan);
  }

  @override
  Future<RoutingInfo> info() => _guard(() => _client.execute(routingInfoOperation));

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on GraphQLRateLimitedException catch (e) {
      throw RouteFailure(RouteFailureKind.rateLimited, retryAfter: e.wait);
    } on GraphQLNetworkException catch (e) {
      throw RouteFailure(RouteFailureKind.offline, message: e.message);
    } on GraphQLResponseException catch (e) {
      final kind = e.hasCode(GraphQLError.invalidInput)
          ? RouteFailureKind.refused
          : RouteFailureKind.unavailable;
      throw RouteFailure(kind, message: e.messages.join('; '));
    }
  }
}

/// [plan] with the shape and steps of each route, read from its OSRM answer
/// away from the UI thread (a 90 km answer is 200 KB of JSON).
Future<RoutePlan> withShapes(RoutePlan plan) async {
  final json = plan.osrmJson;
  if (json == null) return plan;
  final shapes = await compute(readOsrmShapes, json);
  return plan.withRoutes([
    for (final r in plan.routes)
      if (r.index >= 0 && r.index < shapes.length)
        r.withShape(line: shapes[r.index].line, steps: shapes[r.index].steps)
      else
        r,
  ]);
}
