import 'package:flutter/foundation.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// The places as the API's vector tiles carry them (`GET /places/tiles.json`,
/// `docs/deploy.md`, "Places layer"): a map shows a country at once without
/// the device holding a single place, and the filters are expressions the
/// map engine applies to what it already has, without a request.
///
/// Below [pinZoom] a tile holds dots (`place_dots`): every place, without
/// its id or name, two places on one pixel with the same properties drawn
/// once. From [pinZoom] it holds the places themselves (`places`), with
/// their id and name, so a tap opens one.
abstract final class PlaceTiles {
  static const source = 'lw-place-tiles';

  /// The tile layers of the source.
  static const dotsSourceLayer = 'place_dots';
  static const pinsSourceLayer = 'places';

  /// Map layers: the glow of the country's view, the dots of the low zooms,
  /// a dot under every place from [pinZoom] (a pin that has no room is not
  /// drawn, its dot still is), and the pins. The glow and the low zooms'
  /// dots lie under the basemap's names ([basemapFirstLabel]); the pins and
  /// their dots over the streets' names, under the towns' ones
  /// ([basemapTownNames]).
  static const glowLayer = 'lw-place-glow';
  static const dotsLayer = 'lw-place-dots';
  static const pinDotsLayer = 'lw-place-pin-dots';
  static const pinsLayer = 'lw-place-pins';

  /// The first zoom whose tiles carry [pinsSourceLayer]. MapLibre's zoom
  /// levels count 512 px tiles, so a map at zoom z draws the tiles of z.
  static const pinZoom = 10.0;

  /// The first zoom whose pins carry their name (`NAME_MIN_ZOOM` on the
  /// server): from it the list beside the map reads the tiles in view.
  static const nameZoom = 12.0;

  /// Below it the map shows the country: the places as a glow
  /// (`MapLook.glowColor`) and fine dots, and the button of the position
  /// says what it is for until the user is located (`LocateButton`).
  static const countryZoom = 7.0;

  /// Topmost first, for a tap. The glow is no target: a tap near a dot of
  /// the country's view comes closer around it.
  static const List<String> tappable = [pinsLayer, pinDotsLayer, dotsLayer];

  /// Every layer of the source the filters apply to: each engine sets the
  /// filter on all of them, so the glow never shows the places a filter
  /// hides.
  static const List<String> filteredLayers = [glowLayer, dotsLayer, pinDotsLayer, pinsLayer];

  /// The first layer of names of the app's basemaps (Aube and Minuit, from
  /// Protomaps): what lies under it leaves the towns' names readable. The
  /// maps that read their style ask it (`PoiMapStyle.firstLabelLayer`); the
  /// web page's first map, drawn before the app runs, takes this one, which
  /// `test/unit/place_tile_layers_test.dart` holds to both styles.
  static const basemapFirstLabel = 'address_label';

  /// The basemaps' layer of the names of towns and villages, and the layers
  /// after it (countries' names): the places' pins go under it, and so do
  /// the pins of a category chosen and those of the route maps (the PO's
  /// rule of 2026-10-10). MapLibre places the upper layers first, so a pin
  /// that would cover a town's name gives way and its dot stays, rather
  /// than the name be left out (Viviers at zoom 13, audit 94, m3). The
  /// quarters' and the regions' names, before it, stay under the pins.
  /// Held to both styles by `test/unit/place_tile_layers_test.dart`.
  static const basemapTownNames = 'places_locality';

  /// The properties of a tile feature (the contract of the API).
  static const id = 'id';
  static const kind = 'kind';
  static const night = 'night';
  static const services = 's';
  static const price = 'price';
  static const height = 'h';
  static const name = 'name';
  static const city = 'city';

  /// The rating the filters use ([PlaceSummary.ratingForFilters]) in
  /// tenths: 33 for 3.3 on a pin; on a dot, rounded down to a step of the
  /// filter (30, 40 or 45), so the dots of a pixel stay few. Absent when
  /// nobody rated the place, and on a dot below 3.
  static const rating = 'r';

  /// The first and second ranges of the place's season
  /// ([PlaceSummary.openingSeason]), each as [DayRange.code] (92305 for 1
  /// April to 31 October). Absent when the place's opening is not a
  /// season; the second absent without a second range.
  static const season1 = 'o1';
  static const season2 = 'o2';
}

/// What the map draws of the places when they come from the tiles: the
/// TileJSON and the filter. The map props carry none when the map draws
/// the places the device holds instead (offline, or a demo build).
@immutable
final class PlaceTilesView {
  const new({required this.tileJsonUrl, this.filter = PlaceFilter.none});

  /// `/places/tiles.json` on the API.
  final String tileJsonUrl;

  /// Resolved: [PlaceFilter.vehicleHeightM] set when "fits my vehicle" is
  /// on and a height is known.
  final PlaceFilter filter;

  @override
  bool operator ==(Object other) =>
      other is PlaceTilesView && other.tileJsonUrl == tileJsonUrl && other.filter == filter;

  @override
  int get hashCode => Object.hash(tileJsonUrl, filter);
}

/// The domain code a tile carries for [kind] (`motorhome_area`): the GraphQL
/// value in lower case.
String tileKindCode(PlaceKind kind) => kind.wire.toLowerCase();

/// Whether [code] is the kind of a place as the tiles write it: a point of
/// interest's kinds (`fuel_station`, `bakery`) are none of them.
bool isTilePlaceKind(String code) => _kindsByCode.containsKey(code);

/// The domain code a tile carries for [status] (`day_only`).
String tileNightCode(OvernightStatus status) => status.wire.toLowerCase();

final Map<String, PlaceKind> _kindsByCode = {for (final k in PlaceKind.values) tileKindCode(k): k};
final Map<String, OvernightStatus> _nightsByCode = {
  for (final o in OvernightStatus.values) tileNightCode(o): o,
};

/// The MapLibre filter that keeps the tile features [filter] keeps: the same
/// rule as [PlaceFilter.matches], written on the tiles' properties.
///
/// - a family keeps its kinds;
/// - an overnight set keeps its statuses;
/// - an amenity needs one of its services: a bit of the services mask, read
///   with arithmetic since the expression language has no bitwise operator;
/// - "free only" needs a known price of zero (`price` 0);
/// - a vehicle height keeps the places of unknown height and those at least
///   as high, in centimetres;
/// - a minimum rating needs a rating at least as high, in tenths: a place
///   nobody rated has none and is left out;
/// - the days of an opening filter keep the places without a season and
///   those with a range holding each range of the days
///   ([placeTileOpenOn]).
List<Object> placeTileFilter(PlaceFilter filter) {
  final conditions = <Object>[
    if (filter.families.isNotEmpty)
      [
        'match',
        ['get', PlaceTiles.kind],
        [
          for (final k in PlaceKind.values)
            if (filter.families.contains(k.family)) tileKindCode(k),
        ],
        true,
        false,
      ],
    if (filter.overnight.isNotEmpty)
      [
        'match',
        ['get', PlaceTiles.night],
        [
          for (final o in OvernightStatus.values)
            if (filter.overnight.contains(o)) tileNightCode(o),
        ],
        true,
        false,
      ],
    for (final amenity in Amenity.values)
      if (filter.amenities.contains(amenity))
        ['any', for (final s in amenity.services) placeTileHasService(s)],
    if (filter.freeOnly)
      [
        '==',
        ['get', PlaceTiles.price],
        0,
      ],
    if (filter.vehicleHeightM case final height?) placeTileFitsHeight(height),
    if (filter.minRating case final rating?)
      [
        '>=',
        [
          'coalesce',
          ['get', PlaceTiles.rating],
          0,
        ],
        ratingTenths(rating),
      ],
    for (final days in filter.openDays ?? const <DayRange>[]) placeTileOpenOn(days),
  ];
  // True for every feature (each carries its kind): the empty filter keeps
  // everything, and an `all` without arguments may read as a legacy filter.
  if (conditions.isEmpty) return const ['has', PlaceTiles.kind];
  return ['all', ...conditions];
}

/// Keeps the places a vehicle [heightM] high fits under. An unknown height
/// reads as no limit, so the place stays.
List<Object> placeTileFitsHeight(double heightM) => [
  '>=',
  [
    'coalesce',
    ['get', PlaceTiles.height],
    _noLimitCm,
  ],
  heightCentimetres(heightM),
];

/// Keeps the places open on every day of [days]: those without a season
/// (no `o1`) and those whose first or second range holds them all.
List<Object> placeTileOpenOn(DayRange days) => [
  'any',
  ['==', _seasonCode(PlaceTiles.season1), 0],
  _rangeHolds(PlaceTiles.season1, days),
  _rangeHolds(PlaceTiles.season2, days),
];

/// The code of a range of the season, 0 when the tile has none.
List<Object> _seasonCode(String property) => [
  'coalesce',
  ['get', property],
  0,
];

/// Whether the range in [property] holds [days]: its first day,
/// `floor(code / 1000)`, is not after theirs, and its last day not before
/// theirs. The last day is the remainder `code - 1000 * floor(code /
/// 1000)`: the iOS plugin cannot convert `%`. An absent range (0) has a
/// last day of 0 and holds nothing.
List<Object> _rangeHolds(String property, DayRange days) {
  final code = _seasonCode(property);
  final first = [
    'floor',
    ['/', code, 1000],
  ];
  return [
    'all',
    ['>=', days.from, first],
    [
      '>=',
      [
        '-',
        code,
        ['*', 1000, first],
      ],
      days.to,
    ],
  ];
}

/// Higher than any vehicle, for a place whose height limit is unknown.
const _noLimitCm = 100000;

/// A height in metres as the tiles carry it.
int heightCentimetres(double metres) => (metres * 100).round();

/// Whether the services mask holds [service]: `floor(s / 2^bit)` is odd,
/// written `floor(s / 2^bit) - 2 * floor(s / 2^(bit + 1)) == 1` because the
/// expression language has no bitwise operator and the iOS plugin cannot
/// convert `%` (`test/unit/cluster_label_test.dart`).
List<Object> placeTileHasService(Service service) {
  const mask = [
    'coalesce',
    ['get', PlaceTiles.services],
    0,
  ];
  List<Object> shifted(int bits) => [
    'floor',
    ['/', mask, 1 << bits],
  ];
  return [
    '==',
    [
      '-',
      shifted(service.position),
      ['*', 2, shifted(service.position + 1)],
    ],
    1,
  ];
}

/// The pin image of a tile feature, from its kind and overnight status: a
/// lookup rather than text built at draw time, which the iOS plugin cannot
/// convert. A kind or status this version does not know gets the neutral
/// pin.
List<Object> placeTilePinImage() => [
  'match',
  ['get', PlaceTiles.kind],
  for (final kind in PlaceKind.values) ...[
    tileKindCode(kind),
    [
      'match',
      ['get', PlaceTiles.night],
      for (final night in OvernightStatus.values) ...[
        tileNightCode(night),
        pinImageId(kind, night),
      ],
      pinImageId(kind, OvernightStatus.unknown),
    ],
  ],
  pinImageId(PlaceKind.extraService, OvernightStatus.unknown),
];

/// The order of a tile feature where features compete: a night allowed
/// before a night tolerated, and so on. Drawn on top for dots (a higher
/// circle sort key draws later); placed first for pins that must not
/// overlap ([placement]), which MapLibre gives to the lower sort key.
List<Object> placeTileRank({bool placement = false}) {
  int rank(OvernightStatus night) => placement ? -placeRank(night) : placeRank(night);
  return [
    'match',
    ['get', PlaceTiles.night],
    for (final night in OvernightStatus.values) ...[tileNightCode(night), rank(night)],
    rank(OvernightStatus.unknown),
  ];
}

/// The colour of a dot: its family's, as the pins' heads.
List<Object> placeTileDotColor(String Function(KindFamily family) colour) => [
  'match',
  ['get', PlaceTiles.kind],
  for (final family in KindFamily.values) ...[
    [
      for (final k in PlaceKind.values)
        if (k.family == family) tileKindCode(k),
    ],
    colour(family),
  ],
  colour(KindFamily.services),
];

/// A place as a tile describes it, enough to open its page at once (its
/// name, kind and night) and to draw its pin as selected while the rest
/// arrives. Null when the feature is not a place of the tiles (a dot has no
/// id).
PlaceSummary? placeFromTile(Map<Object?, Object?>? properties, List<Object?>? coordinates) {
  if (properties == null || coordinates == null || coordinates.length < 2) return null;
  final id = properties[PlaceTiles.id];
  final lon = coordinates[0];
  final lat = coordinates[1];
  if (id is! String || id.isEmpty || lon is! num || lat is! num) return null;
  final mask = properties[PlaceTiles.services];
  final price = properties[PlaceTiles.price];
  final name = properties[PlaceTiles.name];
  final city = properties[PlaceTiles.city];
  final height = properties[PlaceTiles.height];
  final rating = properties[PlaceTiles.rating];
  final season = seasonFromCodes(properties[PlaceTiles.season1], properties[PlaceTiles.season2]);
  return PlaceSummary(
    id: id,
    name: name is String && name.isNotEmpty ? name : null,
    city: city is String && city.isNotEmpty ? city : null,
    kind: _kindsByCode['${properties[PlaceTiles.kind]}'] ?? PlaceKind.extraService,
    overnight: _nightsByCode['${properties[PlaceTiles.night]}'] ?? OvernightStatus.unknown,
    lat: lat.toDouble(),
    lon: lon.toDouble(),
    services: mask is num ? Service.fromMask(mask.toInt()) : const {},
    // The tile says free or paid, not how much: a paid place's price waits
    // for its page.
    priceParkingEur: price == 0 ? 0 : null,
    maxHeightM: height is num ? height / 100 : null,
    ratingForFilters: rating is num && rating >= 10 && rating <= 50 ? rating / 10 : null,
    openingSeason: season,
  );
}
