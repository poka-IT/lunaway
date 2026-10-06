import 'package:lunaway/core/geo/geo.dart';
import 'package:meta/meta.dart';

/// A stretch of road the law lets a driving aid announce: in France, a
/// "zone de danger" of 300 m to 4 km, never the spot of a speed camera.
/// Which countries allow what is being studied; no source feeds it yet.
@immutable
final class DangerZone {
  const new({required this.id, required this.startM, required this.lengthM, this.label});

  final String id;

  /// Where it starts, metres from the start of the route.
  final double startM;
  final double lengthM;

  /// What the source says of it, when it says something.
  final String? label;
}

/// The danger zones along a route. The guidance asks it as it moves; the
/// one ahead shows in a banner beside the speed limit.
abstract interface class DangerZoneSource {
  /// The zones of [line] that start within [reachM] after [fromM], or that
  /// the vehicle is in, nearest first.
  List<DangerZone> ahead({required List<LatLng> line, required double fromM, double reachM = 2000});
}

/// No zone anywhere: the source until one is chosen, country by country.
final class NoDangerZones implements DangerZoneSource {
  const new();

  @override
  List<DangerZone> ahead({
    required List<LatLng> line,
    required double fromM,
    double reachM = 2000,
  }) => const [];
}
