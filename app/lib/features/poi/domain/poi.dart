import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:meta/meta.dart';

/// The families of points of interest (`PoiCategory` in the contract;
/// `category` in the map tiles): the taxonomy every list of the app reads,
/// the map's chips and tiles, "Around this place", the guidance map's places
/// and the "On the way" sheet, one chip for each family the tiles carry
/// ([tiled]). A category's kinds are those whose [PoiKind.category] it is,
/// defined once below.
enum PoiCategory {
  groceries,
  vending,
  water,
  fuel,
  health,
  services,

  /// Somewhere to eat or drink out: restaurants, cafés, fast food.
  food,

  /// Something worth a stop: viewpoints, attractions, museums, tourist
  /// offices.
  sights,

  /// Shops: clothes, books, DIY, florists. Found by the search alone.
  shopping,

  /// Places to stay: hotels, guest houses, huts. Found by the search alone.
  lodging,

  /// Leisure: cinemas, pools, sports, parks. Found by the search alone.
  leisure;

  /// The contract's spelling (`GROCERIES`).
  String get wire => name.toUpperCase();

  /// The tiles' spelling (`groceries`).
  String get code => name;

  /// Whether the map tiles carry points of the category, and so whether a
  /// chip shows it: the eight families before the establishments
  /// (`PoiCategory::tiled` on the server).
  bool get tiled => this != shopping && this != lodging && this != leisure;

  /// Its kinds the map tiles carry, in the order of [PoiKind]: what the
  /// chips, the tiles, the guidance map and "On the way" read. A family's
  /// establishments (a bar among the food, a hairdresser among the
  /// services) are left out: the search alone finds them.
  List<PoiKind> get kinds => [
    for (final k in PoiKind.values)
      if (k.category == this && k.tiled) k,
  ];

  /// Whether the map reads the category's points only while it shows them:
  /// the default tiles leave them out, and a map showing one reads the
  /// tiles of every category (`/poi/all/tiles.json`). They would have
  /// doubled a town's tiles for a map that most of the time shows neither
  /// (`PoiCategory::on_demand` on the server).
  bool get onDemand => this == food || this == sights;

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
  touristOffice('tourist_office', PoiCategory.sights),
  recyclingCentre('recycling_centre', PoiCategory.services),
  carRepair('car_repair', PoiCategory.services),
  carWash('car_wash', PoiCategory.services),
  motorhomeShop('motorhome_shop', PoiCategory.services),
  outdoorShop('outdoor_shop', PoiCategory.services),
  restaurant('restaurant', PoiCategory.food),
  cafe('cafe', PoiCategory.food),
  fastFood('fast_food', PoiCategory.food),
  viewpoint('viewpoint', PoiCategory.sights),
  attraction('attraction', PoiCategory.sights),
  museum('museum', PoiCategory.sights),

  // The establishments, found by the search alone: the map tiles never
  // carry them ([tiled]).
  bar('bar', PoiCategory.food),
  pub('pub', PoiCategory.food),
  iceCream('ice_cream', PoiCategory.food),
  deli('deli', PoiCategory.groceries),
  cheese('cheese', PoiCategory.groceries),
  seafood('seafood', PoiCategory.groceries),
  pastry('pastry', PoiCategory.groceries),
  confectionery('confectionery', PoiCategory.groceries),
  wineShop('wine_shop', PoiCategory.groceries),
  beverages('beverages', PoiCategory.groceries),
  teaCoffee('tea_coffee', PoiCategory.groceries),
  organicShop('organic_shop', PoiCategory.groceries),
  frozenFood('frozen_food', PoiCategory.groceries),
  winery('winery', PoiCategory.groceries),
  brewery('brewery', PoiCategory.groceries),
  distillery('distillery', PoiCategory.groceries),
  beekeeper('beekeeper', PoiCategory.groceries),
  dentist('dentist', PoiCategory.health),
  clinic('clinic', PoiCategory.health),
  physiotherapist('physiotherapist', PoiCategory.health),
  laboratory('laboratory', PoiCategory.health),
  nurse('nurse', PoiCategory.health),
  midwife('midwife', PoiCategory.health),
  podiatrist('podiatrist', PoiCategory.health),
  psychologist('psychologist', PoiCategory.health),
  speechTherapist('speech_therapist', PoiCategory.health),
  alternativeMedicine('alternative_medicine', PoiCategory.health),
  optician('optician', PoiCategory.health),
  hearingAids('hearing_aids', PoiCategory.health),
  medicalSupply('medical_supply', PoiCategory.health),
  hairdresser('hairdresser', PoiCategory.services),
  beauty('beauty', PoiCategory.services),
  massage('massage', PoiCategory.services),
  tattoo('tattoo', PoiCategory.services),
  bank('bank', PoiCategory.services),
  moneyExchange('money_exchange', PoiCategory.services),
  carRental('car_rental', PoiCategory.services),
  bicycleRental('bicycle_rental', PoiCategory.services),
  boatRental('boat_rental', PoiCategory.services),
  vehicleInspection('vehicle_inspection', PoiCategory.services),
  drivingSchool('driving_school', PoiCategory.services),
  dryCleaning('dry_cleaning', PoiCategory.services),
  tailor('tailor', PoiCategory.services),
  shoeRepair('shoe_repair', PoiCategory.services),
  locksmith('locksmith', PoiCategory.services),
  copyshop('copyshop', PoiCategory.services),
  photographer('photographer', PoiCategory.services),
  travelAgency('travel_agency', PoiCategory.services),
  estateAgent('estate_agent', PoiCategory.services),
  insurance('insurance', PoiCategory.services),
  funeralDirectors('funeral_directors', PoiCategory.services),
  petGrooming('pet_grooming', PoiCategory.services),
  tyres('tyres', PoiCategory.services),
  carParts('car_parts', PoiCategory.services),
  carDealer('car_dealer', PoiCategory.services),
  motorcycleShop('motorcycle_shop', PoiCategory.services),
  repairShop('repair_shop', PoiCategory.services),
  internetCafe('internet_cafe', PoiCategory.services),
  coworking('coworking', PoiCategory.services),
  townhall('townhall', PoiCategory.services),
  police('police', PoiCategory.services),
  library('library', PoiCategory.services),
  rental('rental', PoiCategory.services),
  storageRental('storage_rental', PoiCategory.services),
  animalBoarding('animal_boarding', PoiCategory.services),
  ferryTerminal('ferry_terminal', PoiCategory.services),
  clothes('clothes', PoiCategory.shopping),
  shoes('shoes', PoiCategory.shopping),
  accessories('accessories', PoiCategory.shopping),
  jewellery('jewellery', PoiCategory.shopping),
  books('books', PoiCategory.shopping),
  newsagent('newsagent', PoiCategory.shopping),
  tobacco('tobacco', PoiCategory.shopping),
  stationery('stationery', PoiCategory.shopping),
  gift('gift', PoiCategory.shopping),
  toys('toys', PoiCategory.shopping),
  sports('sports', PoiCategory.shopping),
  fishingHunting('fishing_hunting', PoiCategory.shopping),
  bicycleShop('bicycle_shop', PoiCategory.shopping),
  boatShop('boat_shop', PoiCategory.shopping),
  florist('florist', PoiCategory.shopping),
  gardenCentre('garden_centre', PoiCategory.shopping),
  hardware('hardware', PoiCategory.shopping),
  home('home', PoiCategory.shopping),
  electronics('electronics', PoiCategory.shopping),
  cosmetics('cosmetics', PoiCategory.shopping),
  departmentStore('department_store', PoiCategory.shopping),
  varietyStore('variety_store', PoiCategory.shopping),
  secondHand('second_hand', PoiCategory.shopping),
  artShop('art_shop', PoiCategory.shopping),
  musicShop('music_shop', PoiCategory.shopping),
  petShop('pet_shop', PoiCategory.shopping),
  babyGoods('baby_goods', PoiCategory.shopping),
  fabric('fabric', PoiCategory.shopping),
  craft('craft', PoiCategory.shopping),
  shop('shop', PoiCategory.shopping),
  hotel('hotel', PoiCategory.lodging),
  guestHouse('guest_house', PoiCategory.lodging),
  hostel('hostel', PoiCategory.lodging),
  holidayRental('holiday_rental', PoiCategory.lodging),
  mountainHut('mountain_hut', PoiCategory.lodging),
  cinema('cinema', PoiCategory.leisure),
  theatre('theatre', PoiCategory.leisure),
  eventsVenue('events_venue', PoiCategory.leisure),
  artsCentre('arts_centre', PoiCategory.leisure),
  nightclub('nightclub', PoiCategory.leisure),
  casino('casino', PoiCategory.leisure),
  sportsCentre('sports_centre', PoiCategory.leisure),
  fitnessCentre('fitness_centre', PoiCategory.leisure),
  swimmingPool('swimming_pool', PoiCategory.leisure),
  waterPark('water_park', PoiCategory.leisure),
  golfCourse('golf_course', PoiCategory.leisure),
  miniatureGolf('miniature_golf', PoiCategory.leisure),
  marina('marina', PoiCategory.leisure),
  horseRiding('horse_riding', PoiCategory.leisure),
  bowlingAlley('bowling_alley', PoiCategory.leisure),
  escapeGame('escape_game', PoiCategory.leisure),
  amusementArcade('amusement_arcade', PoiCategory.leisure),
  iceRink('ice_rink', PoiCategory.leisure),
  spa('spa', PoiCategory.leisure),
  dance('dance', PoiCategory.leisure),
  park('park', PoiCategory.leisure),
  natureReserve('nature_reserve', PoiCategory.leisure),
  gallery('gallery', PoiCategory.sights),
  zoo('zoo', PoiCategory.sights),
  themePark('theme_park', PoiCategory.sights);

  new(this.code, this.category);

  final String code;
  final PoiCategory category;

  String get wire => code.toUpperCase();

  /// Whether the map tiles can carry the kind: the forty kinds declared
  /// before the establishments (`PoiKind::tiled` on the server). The others
  /// come from the search alone, and the map draws one only while its page
  /// is open, with its family's pin.
  bool get tiled => index <= museum.index;

  /// A place open whenever one gets there, with no hours to know: a
  /// viewpoint, a site. "Open now" keeps it, and a list says nothing of its
  /// hours.
  bool get timeless => this == viewpoint || this == attraction;

  static PoiKind? fromCode(Object? code) {
    if (code is! String) return null;
    final lower = code.toLowerCase();
    return values.firstWhereOrNull((k) => k.code == lower);
  }

  /// The kinds the first apps did not know: the default tiles keep them
  /// apart, in their layer `pois_more` (or leave them out with their
  /// category, [PoiCategory.onDemand]); the tiles of every category hold
  /// them in `pois` (`PoiKind::tile_layer` on the server).
  static const Set<PoiKind> drawnApart = {
    outdoorShop,
    restaurant,
    cafe,
    fastFood,
    viewpoint,
    attraction,
    museum,
  };

  /// The machines a traveller adds in two gestures: the three the add sheet
  /// offers.
  static const List<PoiKind> addable = [vendingPizza, vendingBread, vendingOther];

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

/// Whether to book a table or a room (`PoiReservation`).
enum PoiReservation {
  yes,
  no,
  required,
  recommended,

  /// Only with a booking.
  only;

  static PoiReservation? fromWire(Object? wire) =>
      values.firstWhereOrNull((r) => r.name.toUpperCase() == wire);
}

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
  static PoiFeature? fromTile(Map<Object?, Object?>? properties, List<Object?>? coordinates) {
    if (properties == null || coordinates == null || coordinates.length < 2) return null;
    final id = properties['id'];
    final kind = PoiKind.fromCode(properties['kind']);
    final lon = coordinates[0];
    final lat = coordinates[1];
    if (id is! String || kind == null || lon is! num || lat is! num) return null;
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
  const new({this.closed = const {}, this.open = const {}, this.hidden = const {}});

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
  int get hashCode => Object.hash(_sets.hash(closed), _sets.hash(open), _sets.hash(hidden));
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
          (c) => (c.position.lat - p.lat).abs() < box && (c.position.lon - p.lon).abs() < box * 2,
        ))
          p,
    ];
    for (final c in candidates) {
      if (near.any((p) => p.distanceTo(c.position) <= duplicateRadiusM)) hidden.add(c.id);
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
  const new({required this.fuel, required this.priceEur, required this.updatedAt});

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

  FuelShortage? shortageOf(String fuel) => shortages.firstWhereOrNull((s) => s.fuel == fuel);
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
    this.motorhome,
    this.hgv,
    this.maxHeightM,
    this.wheelchair,
    this.checkedOn,
    this.lastConfirmedAt,
    this.sources = const [],
    this.takesReviews = true,
    this.cuisine = const [],
    this.diets = const [],
    this.takeaway,
    this.delivery,
    this.outdoorSeating,
    this.reservation,
    this.stars,
    this.internetAccess,
    this.vehicleServices = const [],
    this.emergency,
    this.ratings = const [],
    this.externalRatings = const [],
    this.photos = const [],
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

  /// Whether a vehicle wash or a garage takes motorhomes, as OpenStreetMap
  /// says (its tags, or a wash's name); null when it says nothing, which is
  /// not a no.
  final bool? motorhome;

  /// Whether a vehicle wash takes heavy goods vehicles, and so a
  /// motorhome's height; null when nothing says.
  final bool? hgv;

  /// The highest vehicle a wash takes, metres.
  final double? maxHeightM;
  final String? wheelchair;
  final DateTime? checkedOn;
  final DateTime? lastConfirmedAt;
  final List<PoiSourceRef> sources;

  /// Whether it takes ratings and reviews: not a care practitioner's
  /// practice, whose review would say a patient's health under a public
  /// licence (`Poi.takesReviews`).
  final bool takesReviews;

  /// What it cooks, as OpenStreetMap names it (`pizza`, `italian`).
  final List<String> cuisine;

  /// The diets it caters for (`vegetarian`, `vegan`, `gluten_free`).
  final List<String> diets;

  /// Food to take away, delivery, tables outside; null when the source says
  /// nothing, which is not a no.
  final bool? takeaway;
  final bool? delivery;
  final bool? outdoorSeating;

  /// Whether to book; null when the source says nothing.
  final PoiReservation? reservation;

  /// A hotel's stars, 1 to 5.
  final int? stars;

  /// Internet access for the customers; null when the source says nothing.
  final bool? internetAccess;

  /// What a garage works on, as OpenStreetMap names it (`tyres`, `brakes`).
  final List<String> vehicleServices;

  /// A hospital or a clinic with an emergency department.
  final bool? emergency;

  /// The ratings of Lunaway's users (`community-cc-by`), and what the other
  /// sources say of its ratings (Mangrove's average): each with its own
  /// badge, never added together.
  final List<SourceRating> ratings;
  final List<SourceRating> externalRatings;

  /// Photos of open sources (Wikimedia Commons, Panoramax) served by
  /// Lunaway, each with its author, licence and link.
  final List<Photo> photos;

  PoiCategory get category => kind.category;

  LatLng get position => LatLng(lat, lon);

  /// The point as a tile would show it, for the map's selection.
  PoiFeature get feature =>
      PoiFeature(id: id, kind: kind, position: position, name: name, hours: hours);

  @override
  bool operator ==(Object other) => other is Poi && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The nearest points of one category around a place.
@immutable
final class NearbyPois {
  const new({required this.category, required this.radiusM, required this.pois});

  final PoiCategory category;
  final double radiusM;
  final List<Poi> pois;
}

/// Orders [pois] for a list read at [now]: open first, then unknown, then
/// closed, each by distance; at night, what is open around the clock comes
/// before the rest.
List<Poi> sortForReading(Iterable<Poi> pois, DateTime now, {bool night = false}) {
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
    return (a.distanceM ?? double.infinity).compareTo(b.distanceM ?? double.infinity);
  });
}

/// A station's price of one fuel, as a list of the cheapest reads it.
@immutable
final class FuelOffer {
  const new({required this.station, required this.price, required this.distanceM, this.shortage});

  final Poi station;
  final FuelPrice price;
  final double distanceM;

  /// The station is out of this fuel for now (the feed says since when).
  final FuelShortage? shortage;
}

/// The offers of [fuel] among [stations], cheapest first, then nearest to
/// [from]; a station out of it for now comes after those that sell it, one
/// that stopped selling it is left out.
List<FuelOffer> cheapestOffers(Iterable<Poi> stations, String fuel, {required LatLng from}) {
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
    final out = (a.shortage != null ? 1 : 0).compareTo(b.shortage != null ? 1 : 0);
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
  const new({required this.id, required this.position, required this.text, required this.rank});

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
