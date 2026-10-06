import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:meta/meta.dart';

/// Whether a station is open when the vehicle gets there.
enum StationOpen { open, closed, unknown }

/// A station along the route, its price for one fuel, and what reaching it
/// costs.
@immutable
final class FuelOffer {
  const new({
    required this.id,
    required this.position,
    required this.priceEur,
    required this.priceUpdatedAt,
    required this.detourM,
    required this.detourS,
    required this.alongM,
    this.name,
    this.brand,
    this.open = StationOpen.unknown,
    this.detourEstimated = false,
  });

  /// The point of interest of the station.
  final String id;
  final String? name;
  final String? brand;
  final LatLng position;

  /// Euros per litre.
  final double priceEur;

  /// When the station last gave this price.
  final DateTime priceUpdatedAt;

  /// Metres and seconds the stop adds to the route.
  final double detourM;
  final double detourS;

  /// Where the route passes it, metres from its start.
  final double alongM;
  final StationOpen open;

  /// The detour is reckoned from the distance to the route, not routed.
  final bool detourEstimated;

  @override
  bool operator ==(Object other) =>
      other is FuelOffer &&
      other.id == id &&
      other.priceEur == priceEur &&
      other.detourM == detourM &&
      other.open == open;

  @override
  int get hashCode => Object.hash(id, priceEur, detourM, open);
}

/// The litres a stop at a station is weighed for: about half the tank of a
/// motorhome, a usual refill.
const refillLitres = 50.0;

/// The price per litre that counts the detour: the fuel burnt going there
/// and back, at [consumptionL100], spread over a refill of [refillLitres].
/// A station 2 km off the road at 1.75 EUR/L and 11 L/100 km costs
/// 1.75 * (1 + 0.22 / 50), 1.758 EUR/L.
double effectivePrice(FuelOffer offer, {required double consumptionL100}) {
  final burnt = offer.detourM / 1000 * consumptionL100 / 100;
  return offer.priceEur * (1 + burnt / refillLitres);
}

/// [offers] cheapest first, the detour counted; at an equal price, the
/// nearest detour first.
List<FuelOffer> rankOffers(List<FuelOffer> offers, {required double consumptionL100}) =>
    [...offers]..sort((a, b) {
      final byPrice = effectivePrice(
        a,
        consumptionL100: consumptionL100,
      ).compareTo(effectivePrice(b, consumptionL100: consumptionL100));
      return byPrice != 0 ? byPrice : a.detourM.compareTo(b.detourM);
    });

/// Stations along a route. The server's search along a route is to come;
/// until then the app asks for stations around points of the route.
abstract interface class FuelStationsSource {
  /// Stations selling [fuel] within [maxDetourM] of the detour, along
  /// [route] from [fromM] metres on.
  Future<List<FuelOffer>> along({
    required List<LatLng> route,
    required double fromM,
    required VehicleFuel fuel,
    double maxDetourM = defaultMaxDetourM,
  });
}

/// The detour a station may cost at most, there and back.
const defaultMaxDetourM = 6000.0;
