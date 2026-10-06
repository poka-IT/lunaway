/// The Lunaway taxonomy, mirrored from the GraphQL enums of
/// `schema/lunaway.graphql`. Each value keeps its wire name so parsing and
/// the contract test read the same spelling the server sends.
library;

/// What a place is.
enum PlaceKind {
  motorhomeArea('MOTORHOME_AREA', KindFamily.stopovers),
  serviceArea('SERVICE_AREA', KindFamily.services),
  campsite('CAMPSITE', KindFamily.campsites),
  parking('PARKING', KindFamily.stopovers),
  nature('NATURE', KindFamily.nature),
  restArea('REST_AREA', KindFamily.stopovers),
  picnicArea('PICNIC_AREA', KindFamily.stopovers),
  farm('FARM', KindFamily.campsites),
  homestay('HOMESTAY', KindFamily.campsites),
  offRoad('OFF_ROAD', KindFamily.nature),
  extraService('EXTRA_SERVICE', KindFamily.services);

  new(this.wire, this.family);

  final String wire;
  final KindFamily family;

  static final Map<String, PlaceKind> _byWire = {for (final k in values) k.wire: k};

  /// Unknown values (a newer server) fall back to [extraService] rather than
  /// dropping the place: it still shows, under the most neutral family.
  static PlaceKind fromWire(String wire) => _byWire[wire] ?? extraService;
}

/// The four groups the filters and the pin colours use. Fewer choices than
/// kinds, so a user in a cab decides at a glance.
enum KindFamily {
  /// Motorhome areas and car parks: where most nights are spent.
  stopovers,

  /// Campsites, farms and private hosts.
  campsites,

  /// Spots in nature, 4x4 tracks.
  nature,

  /// Service points: water, dump station, without a night.
  services;

  Set<PlaceKind> get kinds => {
    for (final k in PlaceKind.values)
      if (k.family == this) k,
  };
}

/// A facility of a place. [bit] packs a set of services into one integer
/// column so the local filter is a single bitwise test in SQL.
enum Service {
  drinkingWater('DRINKING_WATER'),
  greyWater('GREY_WATER'),
  blackWater('BLACK_WATER'),
  wasteBin('WASTE_BIN'),
  toilets('TOILETS'),
  showers('SHOWERS'),
  electricity('ELECTRICITY'),
  wifi('WIFI'),
  laundry('LAUNDRY'),
  lpg('LPG'),
  gasBottles('GAS_BOTTLES'),
  vehicleWash('VEHICLE_WASH'),
  bakery('BAKERY'),
  swimmingPool('SWIMMING_POOL'),
  petsAllowed('PETS_ALLOWED'),
  mobileData('MOBILE_DATA'),
  winterCaravanning('WINTER_CARAVANNING');

  new(this.wire);

  final String wire;

  int get bit => 1 << index;

  static final Map<String, Service> _byWire = {for (final s in values) s.wire: s};

  static Service? fromWire(String wire) => _byWire[wire];

  static int maskOf(Iterable<Service> services) =>
      services.fold(0, (mask, service) => mask | service.bit);

  static Set<Service> fromMask(int mask) => {
    for (final s in values)
      if (mask & s.bit != 0) s,
  };
}

/// Something to do around a place.
enum Activity {
  monuments('MONUMENTS'),
  windsurfKitesurf('WINDSURF_KITESURF'),
  mountainBiking('MOUNTAIN_BIKING'),
  hiking('HIKING'),
  climbing('CLIMBING'),
  canoeKayak('CANOE_KAYAK'),
  fishing('FISHING'),
  shoreFishing('SHORE_FISHING'),
  swimming('SWIMMING'),
  motorcycling('MOTORCYCLING'),
  viewpoint('VIEWPOINT'),
  playground('PLAYGROUND');

  new(this.wire);

  final String wire;

  int get bit => 1 << index;

  static final Map<String, Activity> _byWire = {for (final a in values) a.wire: a};

  static Activity? fromWire(String wire) => _byWire[wire];

  static int maskOf(Iterable<Activity> activities) =>
      activities.fold(0, (mask, activity) => mask | activity.bit);

  static Set<Activity> fromMask(int mask) => {
    for (final a in values)
      if (mask & a.bit != 0) a,
  };
}

/// Whether a night may be spent there. The first thing a traveller looks for.
enum OvernightStatus {
  allowed('ALLOWED'),
  tolerated('TOLERATED'),
  dayOnly('DAY_ONLY'),
  forbidden('FORBIDDEN'),
  unknown('UNKNOWN');

  new(this.wire);

  final String wire;

  /// What the "night allowed" filter keeps: a tolerated night is still a night.
  bool get nightOk => this == allowed || this == tolerated;

  static final Map<String, OvernightStatus> _byWire = {for (final o in values) o.wire: o};

  static OvernightStatus fromWire(String wire) => _byWire[wire] ?? unknown;
}
