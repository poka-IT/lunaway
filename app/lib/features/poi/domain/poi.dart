import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:meta/meta.dart';

/// The six families of points of interest, one map chip each, in display
/// order (`PoiCategory` in the contract; `category` in the map tiles).
enum PoiCategory {
  groceries,
  vending,
  water,
  fuel,
  health,
  services;

  /// The contract's spelling (`GROCERIES`).
  String get wire => name.toUpperCase();

  /// The tiles' spelling (`groceries`).
  String get code => name;

  static PoiCategory? fromCode(Object? code) {
    if (code is! String) return null;
    final lower = code.toLowerCase();
    return values.firstWhereOrNull((c) => c.name == lower);
  }
}

/// What a point of interest is (`PoiKind`). [code] is the tiles' spelling,
/// the contract's is the same in capitals.
enum PoiKind {
  supermarket('supermarket', PoiCategory.groceries),
  convenience('convenience', PoiCategory.groceries),
  bakery('bakery', PoiCategory.groceries),
  butcher('butcher', PoiCategory.groceries),
  greengrocer('greengrocer', PoiCategory.groceries),
  farmShop('farm_shop', PoiCategory.groceries),
  marketplace('marketplace', PoiCategory.groceries),
  vendingPizza('vending_pizza', PoiCategory.vending),
  vendingBread('vending_bread', PoiCategory.vending),
  vendingFarmProducts('vending_farm_products', PoiCategory.vending),
  vendingEggsMilk('vending_eggs_milk', PoiCategory.vending),
  vendingIce('vending_ice', PoiCategory.vending),
  vendingOther('vending_other', PoiCategory.vending),
  drinkingWater('drinking_water', PoiCategory.water),
  waterPoint('water_point', PoiCategory.water),
  dumpStation('dump_station', PoiCategory.water),
  toilets('toilets', PoiCategory.water),
  shower('shower', PoiCategory.water),
  fuelStation('fuel_station', PoiCategory.fuel),
  evCharging('ev_charging', PoiCategory.fuel),
  gasBottles('gas_bottles', PoiCategory.fuel),
  pharmacy('pharmacy', PoiCategory.health),
  doctor('doctor', PoiCategory.health),
  hospital('hospital', PoiCategory.health),
  veterinary('veterinary', PoiCategory.health),
  laundry('laundry', PoiCategory.services),
  atm('atm', PoiCategory.services),
  postOffice('post_office', PoiCategory.services),
  touristOffice('tourist_office', PoiCategory.services),
  recyclingCentre('recycling_centre', PoiCategory.services),
  carRepair('car_repair', PoiCategory.services),
  carWash('car_wash', PoiCategory.services),
  motorhomeShop('motorhome_shop', PoiCategory.services);

  new(this.code, this.category);

  final String code;
  final PoiCategory category;

  String get wire => code.toUpperCase();

  static PoiKind? fromCode(Object? code) {
    if (code is! String) return null;
    final lower = code.toLowerCase();
    return values.firstWhereOrNull((k) => k.code == lower);
  }

  /// The machines a traveller adds in two gestures: the three the add sheet
  /// offers.
  static const List<PoiKind> addable = [
    vendingPizza,
    vendingBread,
    vendingOther,
  ];

  /// What the vending chip lets one show alone, in the order of its menu,
  /// pizza first. The tiles count these per kind below the zoom of the
  /// points (`poi_vending_clusters`); [vendingOther] is not among them.
  static const List<PoiKind> vendingChoices = [
    vendingPizza,
    vendingBread,
    vendingFarmProducts,
    vendingEggsMilk,
    vendingIce,
  ];
}

/// Whether a point is open at a moment, read from what is known of its
/// hours.
enum PoiOpenness { open, closed, unknown }

/// A point's hours: around the clock, or intervals valid until a date.
@immutable
final class PoiHours {
  const new({this.alwaysOpen = false, this.intervals, this.validUntil});

  /// Nothing known.
  static const unknown = PoiHours();

  final bool alwaysOpen;
  final List<OpeningInterval>? intervals;
  final DateTime? validUntil;

  /// The state at [now]; null when nothing can be said (no hours, a window
  /// that has run out). Around the clock reads as open through the window.
  OpeningState? stateAt(DateTime now) {
    if (alwaysOpen) return const OpenThroughWindow();
    return openingStateAt(intervals, now, validUntil: validUntil);
  }

  PoiOpenness opennessAt(DateTime now) => switch (stateAt(now)) {
    OpenUntil() || OpenThroughWindow() => PoiOpenness.open,
    ClosedUntil() || ClosedThroughWindow() => PoiOpenness.closed,
    null => PoiOpenness.unknown,
  };
}

/// The hours a map tile carries (`hours`, `hoursUntil`, `alwaysOpen`), read
/// back into intervals. The form is the server's `encode_hours`: the first
/// opening in minutes since 1970, a colon, then the minutes of each span,
/// open and closed in turn, ending with an open one; an empty text is
/// closed over the whole window. Its reference reader is
/// `lunaway_domain::poi::decode_hours`; a text it would refuse reads here as
/// unknown hours.
PoiHours tileHours({Object? hours, Object? until, Object? alwaysOpen}) {
  if (alwaysOpen == true) return const PoiHours(alwaysOpen: true);
  if (hours is! String || until is! num) return PoiHours.unknown;
  final validUntil = _minute(until.toInt());
  if (validUntil == null) return PoiHours.unknown;
  final intervals = decodeTileHours(hours);
  if (intervals == null) return PoiHours.unknown;
  return PoiHours(intervals: intervals, validUntil: validUntil);
}

/// The intervals of a tile's `hours` text; null for a text the server would
/// not have written.
List<OpeningInterval>? decodeTileHours(String text) {
  if (text.isEmpty) return const [];
  final colon = text.indexOf(':');
  if (colon <= 0) return null;
  final first = int.tryParse(text.substring(0, colon));
  if (first == null) return null;
  var at = _minute(first);
  if (at == null) return null;
  final out = <OpeningInterval>[];
  var open = true;
  for (final part in text.substring(colon + 1).split(',')) {
    final minutes = int.tryParse(part);
    if (minutes == null || minutes < 0) return null;
    final next = at!.add(Duration(minutes: minutes));
    if (open) out.add(OpeningInterval(at, next));
    at = next;
    open = !open;
  }
  // The text ends with an open span; a trailing gap is not one the server
  // wrote.
  return open ? null : out;
}

DateTime? _minute(int minutes) {
  // Years 1970 to about 2970: anything else is not a time the server wrote.
  if (minutes < 0 || minutes > 525600000) return null;
  return DateTime.fromMillisecondsSinceEpoch(minutes * 60000, isUtc: true);
}

/// Night, when what is open around the clock comes first (a pizza machine,
/// a card pump, a cash machine): from 21:00 to 06:00 on the place's clock.
bool isNight(DateTime now, {PlaceZone zone = PlaceZone.central}) {
  final hour = zone.wallClock(now).hour;
  return hour >= 21 || hour < 6;
}

/// A point of interest as a map tile shows it: enough to draw it, to say
/// whether it is open and to open its page.
@immutable
final class PoiFeature {
  const new({
    required this.id,
    required this.kind,
    required this.position,
    this.name,
    this.hours = PoiHours.unknown,
    this.lpg = false,
    this.maybeClosed = false,
  });

  /// The feature of the `pois` layer of a tile, from its properties and its
  /// `[lon, lat]`; null when it lacks what the app needs.
  static PoiFeature? fromTile(
    Map<Object?, Object?>? properties,
    List<Object?>? coordinates,
  ) {
    if (properties == null || coordinates == null || coordinates.length < 2)
      return null;
    final id = properties['id'];
    final kind = PoiKind.fromCode(properties['kind']);
    final lon = coordinates[0];
    final lat = coordinates[1];
    if (id is! String || kind == null || lon is! num || lat is! num)
      return null;
    final name = properties['name'];
    return PoiFeature(
      id: id,
      kind: kind,
      position: LatLng(lat.toDouble(), lon.toDouble()),
      name: name is String && name.isNotEmpty ? name : null,
      hours: tileHours(
        hours: properties['hours'],
        until: properties['hoursUntil'],
        alwaysOpen: properties['alwaysOpen'],
      ),
      lpg: properties['lpg'] == true,
      maybeClosed: properties['maybeClosed'] == true,
    );
  }

  final String id;
  final PoiKind kind;
  final LatLng position;
  final String? name;
  final PoiHours hours;
  final bool lpg;
  final bool maybeClosed;

  PoiCategory get category => kind.category;

  @override
  bool operator ==(Object other) => other is PoiFeature && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What the map's point layer must know beyond the tiles, for one minute
/// and one view: the points closed now (drawn faded), those open now (the
/// only ones "Open now" keeps), and those it hides because a place of the
/// map stands on them.
@immutable
final class PoiLayerState {
  const new({
    this.closed = const {},
    this.open = const {},
    this.hidden = const {},
  });

  static const empty = PoiLayerState();

  final Set<String> closed;
  final Set<String> open;
  final Set<String> hidden;

  static const _sets = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is PoiLayerState &&
      _sets.equals(other.closed, closed) &&
      _sets.equals(other.open, open) &&
      _sets.equals(other.hidden, hidden);

  @override
  int get hashCode =>
      Object.hash(_sets.hash(closed), _sets.hash(open), _sets.hash(hidden));
}

/// A dump station the map also shows as a place (2,130 of the 2,756 of the
/// first import sat within 50 m of one): the place's pin says it, so the
/// point's is left out.
const duplicateRadiusM = 50.0;

/// The kinds a place on the map already stands for when it is that close.
const Set<PoiKind> duplicatedKinds = {PoiKind.dumpStation};

/// The layer state of [features] at [now], next to the places at
/// [places] on the map.
PoiLayerState computePoiLayerState(
  Iterable<PoiFeature> features,
  DateTime now, {
  required Iterable<LatLng> places,
}) {
  final closed = <String>{};
  final open = <String>{};
  final hidden = <String>{};
  final candidates = [
    for (final f in features)
      if (duplicatedKinds.contains(f.kind)) f,
  ];
  if (candidates.isNotEmpty) {
    // A degree of latitude is 111 km: a box of 0.001 degree holds 50 m in
    // every direction up to latitude 60 and spares the exact distance for
    // most places.
    const box = 0.001;
    final near = [
      for (final p in places)
        if (candidates.any(
          (c) =>
              (c.position.lat - p.lat).abs() < box &&
              (c.position.lon - p.lon).abs() < box * 2,
        ))
          p,
    ];
    for (final c in candidates) {
      if (near.any((p) => p.distanceTo(c.position) <= duplicateRadiusM))
        hidden.add(c.id);
    }
  }
  for (final f in features) {
    switch (f.hours.opennessAt(now)) {
      case PoiOpenness.open:
        open.add(f.id);
      case PoiOpenness.closed:
        closed.add(f.id);
      case PoiOpenness.unknown:
        break;
    }
  }
  return PoiLayerState(closed: closed, open: open, hidden: hidden);
}

/// A fuel's price at a station.
@immutable
final class FuelPrice {
  const new({
    required this.fuel,
    required this.priceEur,
    required this.updatedAt,
  });

  final String fuel;
  final double priceEur;
  final DateTime updatedAt;
}

/// A fuel a station is out of.
@immutable
final class FuelShortage {
  const new({required this.fuel, required this.definitive, this.since});

  final String fuel;
  final bool definitive;
  final DateTime? since;
}

/// The source of the fuel prices: the French government's feed, under
/// Licence Ouverte 2.0.
const fuelSourceId = 'prix-carburants';

/// What the French fuel price feed says of a station.
@immutable
final class FuelInfo {
  const new({
    required this.prices,
    required this.shortages,
    required this.sellsLpg,
    required this.fetchedAt,
    this.selfService24h = false,
    this.highway = false,
  });

  final List<FuelPrice> prices;
  final List<FuelShortage> shortages;
  final bool sellsLpg;
  final bool selfService24h;
  final bool highway;

  /// When Lunaway read the feed.
  final DateTime fetchedAt;

  /// The fuels shown first: LPG, the one a motorhome looks for, then diesel.
  static const order = ['LPG', 'DIESEL', 'E10', 'SP95', 'SP98', 'E85'];

  List<FuelPrice> get sortedPrices =>
      [...prices]..sort((a, b) => _rank(a.fuel).compareTo(_rank(b.fuel)));

  /// The prices with the fuels of [first] ahead, in that order (the
  /// vehicle's, then LPG for a living area heated on it), the others after
  /// in [order].
  List<FuelPrice> pricesFirst(List<String> first) {
    int rank(String fuel) {
      final i = first.indexOf(fuel);
      return i < 0 ? first.length + _rank(fuel) : i;
    }

    return [...prices]..sort((a, b) => rank(a.fuel).compareTo(rank(b.fuel)));
  }

  static int _rank(String fuel) {
    final i = order.indexOf(fuel);
    return i < 0 ? order.length : i;
  }

  FuelShortage? shortageOf(String fuel) =>
      shortages.firstWhereOrNull((s) => s.fuel == fuel);
}

/// One source of a point, with its identifier there.
@immutable
final class PoiSourceRef {
  const new({
    required this.sourceId,
    required this.externalId,
    required this.fetchedAt,
    this.externalUrl,
  });

  final String sourceId;
  final String externalId;
  final String? externalUrl;
  final DateTime fetchedAt;
}

/// A point of interest as the API describes it (`Poi`).
@immutable
final class Poi {
  const new({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lon,
    this.name,
    this.brand,
    this.operator,
    this.distanceM,
    this.address,
    this.phone,
    this.website,
    this.openingHours,
    this.openingHoursParsed = false,
    this.hours = PoiHours.unknown,
    this.products = const [],
    this.payment = const [],
    this.lpg,
    this.fuel,
    this.reportedClosed,
    this.seasonal,
    this.fee,
    this.selfService,
    this.wheelchair,
    this.checkedOn,
    this.lastConfirmedAt,
    this.sources = const [],
  });

  final String id;
  final PoiKind kind;
  final double lat;
  final double lon;
  final String? name;
  final String? brand;
  final String? operator;

  /// Straight-line distance from what was asked about (a place, a point).
  final double? distanceM;
  final Address? address;
  final String? phone;
  final String? website;

  /// The hours as the source wrote them, shown as text when they could not
  /// be read ([openingHoursParsed] false).
  final String? openingHours;
  final bool openingHoursParsed;
  final PoiHours hours;
  final List<String> products;
  final List<String> payment;
  final bool? lpg;
  final FuelInfo? fuel;

  /// When FINESS lists the establishment as closed (a pharmacy): shown as
  /// "maybe closed".
  final DateTime? reportedClosed;
  final bool? seasonal;
  final bool? fee;
  final bool? selfService;
  final String? wheelchair;
  final DateTime? checkedOn;
  final DateTime? lastConfirmedAt;
  final List<PoiSourceRef> sources;

  PoiCategory get category => kind.category;

  LatLng get position => LatLng(lat, lon);

  /// The point as a tile would show it, for the map's selection.
  PoiFeature get feature => PoiFeature(
    id: id,
    kind: kind,
    position: position,
    name: name,
    hours: hours,
  );

  @override
  bool operator ==(Object other) => other is Poi && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The nearest points of one category around a place.
@immutable
final class NearbyPois {
  const new({
    required this.category,
    required this.radiusM,
    required this.pois,
  });

  final PoiCategory category;
  final double radiusM;
  final List<Poi> pois;
}

/// Orders [pois] for a list read at [now]: open first, then unknown, then
/// closed, each by distance; at night, what is open around the clock comes
/// before the rest.
List<Poi> sortForReading(
  Iterable<Poi> pois,
  DateTime now, {
  bool night = false,
}) {
  int rank(Poi p) {
    if (night && p.hours.alwaysOpen) return 0;
    return switch (p.hours.opennessAt(now)) {
      PoiOpenness.open => 1,
      PoiOpenness.unknown => 2,
      PoiOpenness.closed => 3,
    };
  }

  return [...pois]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return (a.distanceM ?? double.infinity).compareTo(
      b.distanceM ?? double.infinity,
    );
  });
}

/// A station's price of one fuel, as a list of the cheapest reads it.
@immutable
final class FuelOffer {
  const new({
    required this.station,
    required this.price,
    required this.distanceM,
    this.shortage,
  });

  final Poi station;
  final FuelPrice price;
  final double distanceM;

  /// The station is out of this fuel for now (the feed says since when).
  final FuelShortage? shortage;
}

/// The offers of [fuel] among [stations], cheapest first, then nearest to
/// [from]; a station out of it for now comes after those that sell it, one
/// that stopped selling it is left out.
List<FuelOffer> cheapestOffers(
  Iterable<Poi> stations,
  String fuel, {
  required LatLng from,
}) {
  final offers = <FuelOffer>[];
  for (final s in stations) {
    final info = s.fuel;
    if (info == null) continue;
    final price = info.prices.where((p) => p.fuel == fuel).firstOrNull;
    if (price == null) continue;
    final shortage = info.shortageOf(fuel);
    if (shortage?.definitive ?? false) continue;
    offers.add(
      FuelOffer(
        station: s,
        price: price,
        distanceM: s.position.distanceTo(from),
        shortage: shortage,
      ),
    );
  }
  return offers..sort((a, b) {
    final out = (a.shortage != null ? 1 : 0).compareTo(
      b.shortage != null ? 1 : 0,
    );
    if (out != 0) return out;
    final byPrice = a.price.priceEur.compareTo(b.price.priceEur);
    return byPrice != 0 ? byPrice : a.distanceM.compareTo(b.distanceM);
  });
}

/// Where [price] sits between the cheapest and the dearest of [prices]:
/// 0 for the cheapest, 1 for the dearest, 0 when they are all the same.
double priceRank(double price, Iterable<double> prices) {
  if (prices.isEmpty) return 0;
  final low = prices.reduce((a, b) => a < b ? a : b);
  final high = prices.reduce((a, b) => a > b ? a : b);
  if (high - low < 0.0005) return 0;
  return ((price - low) / (high - low)).clamp(0, 1).toDouble();
}

/// A price on the map, under its station's pin.
@immutable
final class FuelLabel {
  const new({
    required this.id,
    required this.position,
    required this.text,
    required this.rank,
  });

  final String id;
  final LatLng position;
  final String text;

  /// 0 for the cheapest station in view, 1 for the dearest.
  final double rank;

  @override
  bool operator ==(Object other) =>
      other is FuelLabel &&
      other.id == id &&
      other.position == position &&
      other.text == text &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(id, position, text, rank);
}
