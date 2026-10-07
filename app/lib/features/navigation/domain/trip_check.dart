import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';

/// The countries at a point and within a kilometre of it, as the device
/// reads them (`CountryLocator.around`).
typedef CountriesAround = ({String? at, List<String> near}) Function(LatLng p);

/// What the app can tell before asking for a route: a stop outside the
/// countries routes are computed in, or a trip longer than the server
/// accepts. Empty when nothing stands in the way, or when the app cannot
/// tell: the server then decides, and says why itself.
///
/// [stops] runs from the origin to the destination. [covered] empty or
/// [maxTripKm] null (an API that does not give them) skip their check.
List<NoRouteReason> checkTrip({
  required List<LatLng> stops,
  required List<String> covered,
  required double? maxTripKm,
  required CountriesAround countries,
}) {
  if (covered.isNotEmpty) {
    final outside = [
      for (final (i, p) in stops.indexed)
        if (knownOutside(countries(p), covered))
          NoRouteReason(kind: NoRouteReasonKind.outsideCoverage, stopIndex: i),
    ];
    if (outside.isNotEmpty) return outside;
  }
  if (maxTripKm != null) {
    var metres = 0.0;
    for (var i = 1; i < stops.length; i++) {
      metres += stops[i - 1].distanceTo(stops[i]);
    }
    final km = metres / 1000;
    // The server sums the same straight lines on a slightly different
    // sphere: a trip right at the bound goes to it rather than being
    // refused here for a rounding.
    if (km > maxTripKm * 1.01) {
      return [NoRouteReason(kind: NoRouteReasonKind.tripTooLong, tripKm: km, maxKm: maxTripKm)];
    }
  }
  return const [];
}

/// Whether a point is outside [countries] for sure: the device knows its
/// country, and neither it nor a neighbour within a kilometre is listed.
/// The server's cuts run a few kilometres past the borders, and at sea (no
/// country) the server knows better: both go to it.
bool knownOutside(({String? at, List<String> near}) around, List<String> countries) {
  final at = around.at;
  if (at == null || countries.isEmpty) return false;
  return !countries.contains(at) && !around.near.any(countries.contains);
}
