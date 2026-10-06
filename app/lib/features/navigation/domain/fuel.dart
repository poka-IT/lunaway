import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:meta/meta.dart';

/// Litres per 100 km of a motorhome of 3.5 t on the road: what a detour to
/// a cheaper station is weighed with until the vehicle's own figure is
/// given (in the vehicle's editor).
const defaultConsumptionL100 = 11.0;

/// Whether a station is open now, as its opening hours read (`openNow` of
/// the API).
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
    required this.fuel,
    this.name,
    this.brand,
    this.open = StationOpen.unknown,
    this.detourEstimated = false,
    this.poiId,
    this.stationId,
  });

  /// The station's identity among the offers: its point of interest, else
  /// its id in the price feed.
  final String id;

  /// The point of interest that describes it (`Query.poi`), when there is
  /// one: its sheet opens from a stop made of it.
  final String? poiId;

  /// Its id in the price feed, when the offer comes from the server's
  /// search along the route.
  final String? stationId;

  /// The fuel the price is for.
  final FuelType fuel;
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
/// A detour of 2 km at 1.75 EUR/L and 11 L/100 km costs
/// 1.75 * (1 + 0.22 / 50), 1.758 EUR/L.
double effectivePrice(FuelOffer offer, {required double consumptionL100}) {
  final burnt = offer.detourM / 1000 * consumptionL100 / 100;
  return offer.priceEur * (1 + burnt / refillLitres);
}

/// [offers] cheapest first, the detour counted, the stations closed now
/// after the others; at an equal price, the nearest detour first.
List<FuelOffer> rankOffers(List<FuelOffer> offers, {required double consumptionL100}) =>
    [...offers]..sort((a, b) {
      final closed = (a.open == StationOpen.closed ? 1 : 0).compareTo(
        b.open == StationOpen.closed ? 1 : 0,
      );
      if (closed != 0) return closed;
      final byPrice = effectivePrice(
        a,
        consumptionL100: consumptionL100,
      ).compareTo(effectivePrice(b, consumptionL100: consumptionL100));
      return byPrice != 0 ? byPrice : a.detourM.compareTo(b.detourM);
    });

/// Stations along a route: the server's search along it, or stations
/// around points of it from an API without that search.
abstract interface class FuelStationsSource {
  /// Stations selling [fuel] within [maxDetourM] of the detour, along
  /// [route] from [fromM] metres on; the detour priced at
  /// [consumptionL100], measured on the roads [vehicle] (the router's
  /// profile, as JSON) may take.
  Future<List<FuelOffer>> along({
    required List<LatLng> route,
    required double fromM,
    required FuelType fuel,
    double maxDetourM = defaultMaxDetourM,
    double consumptionL100 = defaultConsumptionL100,
    Map<String, Object?>? vehicle,
  });
}

/// The detour a station may cost at most, there and back.
const defaultMaxDetourM = 6000.0;
