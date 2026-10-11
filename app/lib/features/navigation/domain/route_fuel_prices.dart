import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/poi/domain/poi.dart'
    show FuelLabel, Poi, priceIsCurrent, priceRank;
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:meta/meta.dart';

/// The prices the maps of a route write by their stations: the price of the
/// fuel of the vehicle's profile, as the main map writes it ("1,789" in
/// French, "1.789" in English), coloured from the cheapest to the dearest of
/// those shown together ([FuelLabel.rank]).
@immutable
final class RoutePrices {
  const new({this.marks = const {}, this.pins = const []});

  static const none = RoutePrices();

  /// Beside the marks of the stations of the fuel list ("Sur le trajet"),
  /// by the offer's id.
  final Map<String, FuelLabel> marks;

  /// Under the pins of the points of interest: the stations read around
  /// the vehicle, those of the fuel list left out, which their mark prices.
  final List<FuelLabel> pins;

  @override
  bool operator ==(Object other) =>
      other is RoutePrices &&
      const MapEquality<String, FuelLabel>().equals(other.marks, marks) &&
      const ListEquality<FuelLabel>().equals(other.pins, pins);

  @override
  int get hashCode => Object.hash(
    const MapEquality<String, FuelLabel>().hash(marks),
    const ListEquality<FuelLabel>().hash(pins),
  );
}

/// The prices of [fuel], the vehicle's, for the stations of the fuel list
/// ([offers]) and those read around the vehicle ([stations]), written in
/// [language] at [now]. Nothing without a fuel in the profile (the logo
/// alone), for a station that gave no price of it, nor for one it gave more
/// than `maxPriceAge` ago, nor for a station out of it: no price rather than
/// a wrong one. An offer of another fuel (the list switched to another one)
/// is no price of the vehicle's. Outside France the stations have no price
/// at all, and show their logo alone.
RoutePrices routePrices({
  required FuelType? fuel,
  required DateTime now,
  required String language,
  List<FuelOffer> offers = const [],
  List<Poi> stations = const [],
}) {
  if (fuel == null) return RoutePrices.none;
  final listed = <String, ({FuelOffer offer, double price})>{
    for (final o in offers)
      if (o.fuel == fuel && priceIsCurrent(o.priceUpdatedAt, now))
        o.id: (offer: o, price: o.priceEur),
  };
  // The fuel list's stations priced beside their mark, by their point of
  // interest: their pin says nothing more. A station of the list switched
  // to another fuel keeps the vehicle's price under its pin.
  final listedPois = {for (final l in listed.values) ?l.offer.poiId};
  final around = <({Poi station, double price})>[];
  final seen = <String>{};
  for (final s in stations) {
    if (listedPois.contains(s.id) || !seen.add(s.id)) continue;
    final info = s.fuel;
    final price = info?.prices.where((p) => p.fuel == fuel.wire).firstOrNull;
    if (info == null || price == null) continue;
    if (info.shortageOf(fuel.wire) != null || !priceIsCurrent(price.updatedAt, now)) continue;
    around.add((station: s, price: price.priceEur));
  }
  final all = [for (final l in listed.values) l.price, for (final a in around) a.price];
  final format = NumberFormat('0.000', language);
  FuelLabel label(String id, double price, LatLng at) =>
      FuelLabel(id: id, position: at, text: format.format(price), rank: priceRank(price, all));
  return RoutePrices(
    marks: {
      for (final MapEntry(:key, :value) in listed.entries)
        key: label(key, value.price, value.offer.position),
    },
    pins: [for (final a in around) label(a.station.id, a.price, a.station.position)],
  );
}
