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
  drinkingWater('DRINKING_WATER', 0),
  greyWater('GREY_WATER', 1),
  blackWater('BLACK_WATER', 2),
  wasteBin('WASTE_BIN', 3),
  toilets('TOILETS', 4),
  showers('SHOWERS', 5),
  electricity('ELECTRICITY', 6),
  wifi('WIFI', 7),
  laundry('LAUNDRY', 8),
  lpg('LPG', 9),
  gasBottles('GAS_BOTTLES', 10),
  vehicleWash('VEHICLE_WASH', 11),
  bakery('BAKERY', 12),
  swimmingPool('SWIMMING_POOL', 13),
  petsAllowed('PETS_ALLOWED', 14),
  mobileData('MOBILE_DATA', 15),
  winterCaravanning('WINTER_CARAVANNING', 16);

  new(this.wire, this.position);

  final String wire;

  /// The bit of the service in the stored masks. Pinned, not derived from
  /// the declaration order: masks are written to the device, and a service
  /// added in the middle of the list must not shift the meaning of stored
  /// rows.
  final int position;

  int get bit => 1 << position;

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
  monuments('MONUMENTS', 0),
  windsurfKitesurf('WINDSURF_KITESURF', 1),
  mountainBiking('MOUNTAIN_BIKING', 2),
  hiking('HIKING', 3),
  climbing('CLIMBING', 4),
  canoeKayak('CANOE_KAYAK', 5),
  fishing('FISHING', 6),
  shoreFishing('SHORE_FISHING', 7),
  swimming('SWIMMING', 8),
  motorcycling('MOTORCYCLING', 9),
  viewpoint('VIEWPOINT', 10),
  playground('PLAYGROUND', 11);

  new(this.wire, this.position);

  final String wire;

  /// The bit of the activity in the stored masks, pinned like
  /// [Service.position].
  final int position;

  int get bit => 1 << position;

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
