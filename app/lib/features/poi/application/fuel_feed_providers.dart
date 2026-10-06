import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/fuel_feed.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fuel_feed_providers.g.dart';

/// How far around the point the list of the cheapest looks when it asks
/// the server, kilometres.
const nearbyFuelRadiusKm = 20.0;

/// The point the server's search near a point is asked about: the user's
/// position, else the centre of the view, rounded to a twentieth of a
/// degree (about 5 km) before it leaves the device, as the search of shops
/// does. Watched alone, so the view moving within the same square asks
/// nothing again.
@riverpod
LatLng? nearbyFuelPoint(Ref ref) {
  final from = ref.watch(userLocationProvider) ?? ref.watch(viewportProvider)?.center;
  if (from == null) return null;
  double round(double v) => (v * 20).roundToDouble() / 20;
  return LatLng(round(from.lat), round(from.lon));
}

/// The cheapest stations of the chosen fuel around the user, from the
/// server (`fuelNearby`): what the list shows where the stations of the
/// view cannot all be read (far out, or a dense town). Null against an API
/// without that search. The distances are measured on the device, from
/// the user's own position when known.
@Riverpod(retry: noRetry)
Future<List<FuelOffer>?> nearbyFuel(Ref ref) async {
  final fuel = ref.watch(chosenFuelProvider).wire;
  final at = ref.watch(nearbyFuelPointProvider);
  final user = ref.watch(userLocationProvider);
  if (at == null) return const [];
  final List<Map<String, dynamic>> stations;
  try {
    stations = await ref.read(graphQLClientProvider).execute(fuelNearbyOperation, {
      'at': {'lat': at.lat, 'lon': at.lon},
      'fuel': fuel,
      'radiusKm': nearbyFuelRadiusKm,
      'limit': 30,
    });
  } on GraphQLResponseException catch (e) {
    if (e.errors.any((error) => error.unknownField)) return null;
    rethrow;
  }
  final from = user ?? at;
  final offers = [for (final s in stations) ?nearbyOffer(s, fuel: fuel, from: from)];
  return offers..sort((a, b) {
    final out = (a.shortage != null ? 1 : 0).compareTo(b.shortage != null ? 1 : 0);
    if (out != 0) return out;
    final byPrice = a.price.priceEur.compareTo(b.price.priceEur);
    return byPrice != 0 ? byPrice : a.distanceM.compareTo(b.distanceM);
  });
}

/// The price of [fuel] at the station [poiId] over the last 30 days, read
/// when its sheet opens; null when the server saw none. A failure shows at
/// once, beside the prices that did load.
@Riverpod(retry: noRetry)
Future<FuelTrend?> fuelTrend(Ref ref, String poiId, String fuel) =>
    ref.watch(graphQLClientProvider).execute(fuelTrendOperation, {'id': poiId, 'fuel': fuel});
