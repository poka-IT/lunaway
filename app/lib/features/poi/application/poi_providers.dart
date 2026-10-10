import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'poi_providers.g.dart';

/// The points of interest read online, with the copies kept for offline.
// keepAlive: a repository over the app-wide database and client.
@Riverpod(keepAlive: true)
PoiRepository poiRepository(Ref ref) => PoiRepository(
  db: ref.watch(cacheDatabaseProvider),
  // With the account's session when the device has one, for the reviews.
  source: GraphQLPoiSource(
    ref.watch(graphQLClientProvider),
    headers: () => ref.read(accountServiceProvider).readHeaders(),
  ),
  clock: ref.read(clockProvider),
);

/// The TileJSON of the points layer, on the API's host: the map reads the
/// tiles it names, of the layer's current version. The default tiles
/// (`/poi/tiles.json`) leave out the categories read on demand; a map that
/// shows one of them reads the tiles of every category
/// (`/poi/all/tiles.json`, [all]), so that most of the time the device
/// loads no restaurant ([PoiCategory.onDemand]).
@riverpod
String poiTileJsonUrl(Ref ref, {bool all = false}) {
  final base = ref.watch(appConfigProvider).apiBase;
  return base
      .replace(path: '${base.path}${all ? '/poi/all/tiles.json' : '/poi/tiles.json'}')
      .toString();
}

/// What the map shows of the points: one category at a time (none by
/// default: then every point shows quietly at street zoom), and whether
/// only the open ones.
@immutable
final class PoiLayerChoice {
  const new({this.category, this.vending, this.openNowOnly = false});

  final PoiCategory? category;

  /// With the vending machines on, the one kind shown alone (one of
  /// [PoiKind.vendingChoices]); null shows them all.
  final PoiKind? vending;
  final bool openNowOnly;

  @override
  bool operator ==(Object other) =>
      other is PoiLayerChoice &&
      other.category == category &&
      other.vending == vending &&
      other.openNowOnly == openNowOnly;

  @override
  int get hashCode => Object.hash(category, vending, openNowOnly);
}

// keepAlive: the chip stays on while the user visits another tab.
@Riverpod(keepAlive: true)
class PoiLayer extends _$PoiLayer {
  @override
  PoiLayerChoice build() => const PoiLayerChoice();

  /// Turns [category] on, or off when it already is: one chip at a time.
  void toggle(PoiCategory category) => state = state.category == category
      ? const PoiLayerChoice()
      : PoiLayerChoice(category: category, openNowOnly: state.openNowOnly);

  /// Turns the vending machines on, only those of [kind] when given.
  void showVending(PoiKind? kind) {
    assert(kind == null || PoiKind.vendingChoices.contains(kind), 'not a vending choice: $kind');
    state = PoiLayerChoice(
      category: PoiCategory.vending,
      vending: kind,
      openNowOnly: state.openNowOnly,
    );
  }

  void setOpenNowOnly({required bool on}) =>
      state = PoiLayerChoice(category: state.category, vending: state.vending, openNowOnly: on);

  void clear() => state = const PoiLayerChoice();
}

/// The points of the tiles under the map's view, as the map reported them
/// once it settled: what their hours and their neighbours decide.
// keepAlive: the map reports them; the layer state reads them at each tick.
@Riverpod(keepAlive: true)
class PoisInView extends _$PoisInView {
  @override
  List<PoiFeature> build() => const [];

  void report(List<PoiFeature> features) {
    if (!listEquals(features, state)) state = features;
  }
}

/// Which points of the view are open, closed, or left to a place of the
/// map; read again every minute.
@riverpod
PoiLayerState poiLayerState(Ref ref) {
  final features = ref.watch(poisInViewProvider);
  if (features.isEmpty) return PoiLayerState.empty;
  final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
  // The places the map draws in view: those of the tiles' report the
  // filter keeps (the report holds them all), or those the device holds
  // when the map draws them.
  final List<PlaceSummary> drawn;
  if (ref.watch(placesFromTilesProvider)) {
    final filter = ref.watch(effectiveFilterProvider);
    drawn = ref.watch(placesInViewProvider).places.where(filter.matches).toList();
  } else {
    drawn = ref.watch(mapPlacesProvider).value ?? const <PlaceSummary>[];
  }
  final places = [for (final p in drawn) p.position];
  return computePoiLayerState(features, now, places: places);
}

/// Whether it is night now, when what is open around the clock comes first.
@riverpod
bool poiNight(Ref ref) =>
    isNight(ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)());

/// "Around this place": the copy kept on the device first, then the API's.
/// A failure shows at once (no automatic retry): offline without a copy,
/// the section says so and offers to try again.
@Riverpod(retry: noRetry)
Stream<Read<List<NearbyPois>>> placeSurroundings(Ref ref, String placeId) =>
    ref.watch(poiRepositoryProvider).watchNearby(placeId);

/// The page of a point; null inside when it is gone or hidden. A failure
/// shows at once, as for [placeSurroundings].
@Riverpod(retry: noRetry)
Stream<Read<PoiPage?>> poiPage(Ref ref, String poiId) =>
    ref.watch(poiRepositoryProvider).watchPage(poiId);

/// The reviews of a point, read online when its page opens. A failure
/// shows at once, with a way to try again.
@Riverpod(retry: noRetry)
Future<PoiReviews?> pointReviews(Ref ref, String poiId) =>
    ref.watch(poiRepositoryProvider).reviews(poiId);

/// The account's own rating or review of each point as the server answered
/// it last (a rating, a review, a deletion): the point's page shows it
/// while its reviews are read again, rather than the review before.
// keepAlive: the outbox runner writes it when a contribution goes, the
// page reads it after.
@Riverpod(keepAlive: true)
class SentPoiReviews extends _$SentPoiReviews {
  @override
  Map<String, Review?> build() => const {};

  void put(String poiId, Review? review) => state = {...state, poiId: review};
}

/// The fuel the price labels and the cheapest stations show: the vehicle's
/// by default, another one when the user switches in the list.
// keepAlive: the choice holds while the user moves between tabs.
@Riverpod(keepAlive: true)
class ChosenFuel extends _$ChosenFuel {
  @override
  FuelType build() => ref.watch(vehicleFuelProvider).fuel ?? FuelType.diesel;

  void choose(FuelType fuel) => state = fuel;
}

/// The box the fuel stations of [view] are asked for: the view grown to a
/// grid of 0.05 degree, so a small move asks nothing new, and at most 1.95
/// degree a side around its centre (the API takes four square degrees at
/// most; two degrees a side, summed in floating point, may pass them).
GeoBounds fuelQueryBox(GeoBounds view) {
  const step = 0.05;
  const side = 1.95;
  double down(double v) => (v / step).floorToDouble() * step;
  double up(double v) => (v / step).ceilToDouble() * step;
  var south = down(view.south);
  var north = up(view.north);
  var west = down(view.west);
  var east = up(view.east);
  if (north - south > side) {
    south = down((north + south) / 2 - side / 2);
    north = south + side;
  }
  if (east - west > side) {
    west = down((east + west) / 2 - side / 2);
    east = west + side;
  }
  return GeoBounds(south: south, west: west, north: north, east: east);
}

/// The fuel stations of a box with their prices, read once the view rests;
/// null when the box holds too many to read them all.
@Riverpod(retry: noRetry)
Future<List<Poi>?> fuelStations(Ref ref, GeoBounds box) async {
  // A view that keeps moving asks nothing until it rests.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!ref.mounted) return const [];
  return await ref.read(poiRepositoryProvider).fuelStations(box);
}

/// The zoom from which the fuel stations of the view are read: below, the
/// view holds too many.
const fuelStationsMinZoom = 10.0;

/// The fuel stations of the view while the fuel chip is on; empty
/// otherwise, or far out; null when the view holds too many to read.
// Fails only when [fuelStations] does, which shows at once: no retry here.
@Riverpod(retry: noRetry)
Future<List<Poi>?> fuelStationsInView(Ref ref) async {
  if (ref.watch(poiLayerProvider).category != PoiCategory.fuel) return const [];
  final viewport = ref.watch(viewportProvider);
  if (viewport == null || viewport.zoom < fuelStationsMinZoom) return const [];
  return await ref.watch(fuelStationsProvider(fuelQueryBox(viewport.bounds)).future);
}

/// The cheapest offers of the chosen fuel among the stations of the view
/// (the same ones as the labels, so a colour means the same price in both),
/// then the nearest to the user, or to the centre of the view; null when
/// the view holds too many stations to read them all.
// Fails only when [fuelStations] does, which shows at once: no retry here.
@Riverpod(retry: noRetry)
Future<List<FuelOffer>?> cheapestFuel(Ref ref) async {
  final fuel = ref.watch(chosenFuelProvider);
  final viewport = ref.watch(viewportProvider);
  final from = ref.watch(userLocationProvider) ?? viewport?.center;
  final stations = await ref.watch(fuelStationsInViewProvider.future);
  if (stations == null) return null;
  if (from == null || viewport == null) return const [];
  return cheapestOffers(
    stations.where((s) => viewport.bounds.contains(s.position)),
    fuel.wire,
    from: from,
  );
}

/// The price of the chosen fuel under each station of the view, coloured
/// from the cheapest to the dearest of those in view, written in
/// [language] ("1,789" or "1.789").
@riverpod
List<FuelLabel> fuelLabels(Ref ref, String language) {
  // A view whose stations could not all be read shows no price: a part of
  // them would colour as the cheapest without being so.
  final read = ref.watch(fuelStationsInViewProvider);
  // A failed read keeps the stations of the view before: their prices
  // would show under this one.
  final stations = read.hasError ? const <Poi>[] : read.value ?? const <Poi>[];
  final view = ref.watch(viewportProvider)?.bounds;
  if (stations.isEmpty || view == null) return const [];
  final fuel = ref.watch(chosenFuelProvider).wire;
  final priced = [
    for (final s in stations)
      if (view.contains(s.position))
        if (s.fuel?.prices.where((p) => p.fuel == fuel).firstOrNull case final price?)
          // Out of it for now, its last price would mislead: the list says
          // so in words, the map shows none.
          if (s.fuel!.shortageOf(fuel) == null) (s, price.priceEur),
  ];
  final prices = [for (final (_, p) in priced) p];
  final format = NumberFormat('0.000', language);
  return [
    for (final (s, p) in priced)
      FuelLabel(id: s.id, position: s.position, text: format.format(p), rank: priceRank(p, prices)),
  ];
}
