import 'package:collection/collection.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// How the guidance map draws the places it shows.
enum GuidanceLook {
  /// The few places that matter most as their photo, an illustrated mark
  /// for one without; the others as small pins.
  photos,

  /// The few places that matter most as an illustrated mark with a short
  /// label; the others as small pins.
  pictograms,

  /// Small pins only, as the main map draws them, smaller.
  dots;

  static GuidanceLook? fromName(Object? name) => values.firstWhereOrNull((l) => l.name == name);

  /// Whether some places stand out as rich marks.
  bool get rich => this != dots;
}

/// What the guidance map shows of the places and the points of interest:
/// categories, each one "show these", the map showing every place or point
/// one of them keeps. The categories are the main map's own (the filters'
/// overnight statuses, families and amenities, the chips' kinds of points
/// and vending machines, the minimum rating): one definition in the domain,
/// read by both. Unlike the main map's filter, whose criteria narrow the
/// list, these add up: "nights" and "water" show both kinds of place. The
/// minimum rating alone narrows, the places only (the points carry none).
@immutable
final class GuidanceSelection {
  const new({
    this.overnight = const {},
    this.families = const {},
    this.amenities = const {},
    this.points = const {},
    this.vending = const {},
    this.minRating,
  });

  /// Unknown values (an older or a newer app) are dropped.
  factory fromJson(Object? json) {
    if (json is! Map) return const GuidanceSelection();
    Set<T> read<T extends Object>(String key, T? Function(Object?) parse) => {
      if (json[key] case final List<Object?> list)
        for (final v in list) ?parse(v),
    };
    final rating = json['minRating'];
    return GuidanceSelection(
      overnight: read(
        'overnight',
        (v) => OvernightStatus.values.firstWhereOrNull((o) => o.name == v),
      ),
      families: read('families', (v) => KindFamily.values.firstWhereOrNull((f) => f.name == v)),
      amenities: read('amenities', (v) => Amenity.values.firstWhereOrNull((a) => a.name == v)),
      points: read('points', (v) => pointCategories.firstWhereOrNull((c) => c.name == v)),
      vending: read('vending', (v) => PoiKind.vendingChoices.firstWhereOrNull((k) => k.code == v)),
      minRating: rating is num && minRatingSteps.contains(rating.toDouble())
          ? rating.toDouble()
          : null,
    );
  }

  /// The places whose night is one of these.
  final Set<OvernightStatus> overnight;

  /// The places of these families.
  final Set<KindFamily> families;

  /// The places offering one of these.
  final Set<Amenity> amenities;

  /// The points of these categories ([pointCategories]: every category but
  /// the vending machines, chosen by what they sell in [vending]).
  final Set<PoiCategory> points;

  /// The vending machines selling these ([PoiKind.vendingChoices]).
  final Set<PoiKind> vending;

  /// The places rated at least this ([minRatingSteps]); null for any.
  final double? minRating;

  /// The categories of points the selection offers apart from vending.
  static const List<PoiCategory> pointCategories = [
    PoiCategory.fuel,
    PoiCategory.water,
    PoiCategory.groceries,
    PoiCategory.health,
    PoiCategory.services,
  ];

  bool get placesShown => overnight.isNotEmpty || families.isNotEmpty || amenities.isNotEmpty;
  bool get pointsShown => points.isNotEmpty || vending.isNotEmpty;
  bool get isEmpty => !placesShown && !pointsShown;

  /// Whether [place] is one of the selection's, before the vehicle's
  /// height ([guidanceKeepsPlace] adds it).
  bool keeps(PlaceSummary place) {
    final chosen =
        overnight.contains(place.overnight) ||
        families.contains(place.kind.family) ||
        amenities.any((a) => a.offeredBy(place.services));
    if (!chosen) return false;
    final rating = minRating;
    return rating == null || meetsMinRating(place.ratingForFilters, rating);
  }

  static Set<T> _toggled<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  GuidanceSelection toggleOvernight(OvernightStatus o) =>
      copyWith(overnight: _toggled(overnight, o));
  GuidanceSelection toggleFamily(KindFamily f) => copyWith(families: _toggled(families, f));
  GuidanceSelection toggleAmenity(Amenity a) => copyWith(amenities: _toggled(amenities, a));
  GuidanceSelection togglePoints(PoiCategory c) => copyWith(points: _toggled(points, c));
  GuidanceSelection toggleVending(PoiKind k) => copyWith(vending: _toggled(vending, k));

  /// [step] chosen, or taken off when it was the one.
  GuidanceSelection toggleMinRating(double step) =>
      copyWith(minRating: () => minRating == step ? null : step);

  GuidanceSelection copyWith({
    Set<OvernightStatus>? overnight,
    Set<KindFamily>? families,
    Set<Amenity>? amenities,
    Set<PoiCategory>? points,
    Set<PoiKind>? vending,
    double? Function()? minRating,
  }) => GuidanceSelection(
    overnight: overnight ?? this.overnight,
    families: families ?? this.families,
    amenities: amenities ?? this.amenities,
    points: points ?? this.points,
    vending: vending ?? this.vending,
    minRating: minRating == null ? this.minRating : minRating(),
  );

  /// In the order of the enums, so two equal selections write the same
  /// text.
  Map<String, Object?> toJson() => {
    'overnight': [
      for (final o in OvernightStatus.values)
        if (overnight.contains(o)) o.name,
    ],
    'families': [
      for (final f in KindFamily.values)
        if (families.contains(f)) f.name,
    ],
    'amenities': [
      for (final a in Amenity.values)
        if (amenities.contains(a)) a.name,
    ],
    'points': [
      for (final c in pointCategories)
        if (points.contains(c)) c.name,
    ],
    'vending': [
      for (final k in PoiKind.vendingChoices)
        if (vending.contains(k)) k.code,
    ],
    'minRating': ?minRating,
  };

  static const _overnightEq = SetEquality<OvernightStatus>();
  static const _familiesEq = SetEquality<KindFamily>();
  static const _amenitiesEq = SetEquality<Amenity>();
  static const _pointsEq = SetEquality<PoiCategory>();
  static const _vendingEq = SetEquality<PoiKind>();

  @override
  bool operator ==(Object other) =>
      other is GuidanceSelection &&
      _overnightEq.equals(other.overnight, overnight) &&
      _familiesEq.equals(other.families, families) &&
      _amenitiesEq.equals(other.amenities, amenities) &&
      _pointsEq.equals(other.points, points) &&
      _vendingEq.equals(other.vending, vending) &&
      other.minRating == minRating;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(overnight),
    Object.hashAllUnordered(families),
    Object.hashAllUnordered(amenities),
    Object.hashAllUnordered(points),
    Object.hashAllUnordered(vending),
    minRating,
  );
}

/// The ready-made selections the sheet offers first, one tap each.
enum GuidancePreset {
  /// The places where a night is allowed or tolerated.
  sleep(GuidanceSelection(overnight: nightPossible)),

  /// Fuel and the motorhome's other fill-ups: stations, gas and chargers,
  /// water and dump points, service areas and the places with a borne.
  fill(
    GuidanceSelection(
      families: {KindFamily.services},
      amenities: {Amenity.water, Amenity.dumpStation},
      points: {PoiCategory.fuel, PoiCategory.water},
    ),
  ),

  /// Food: the shops and the vending machines.
  groceries(
    GuidanceSelection(
      points: {PoiCategory.groceries},
      vending: {
        PoiKind.vendingPizza,
        PoiKind.vendingBread,
        PoiKind.vendingFarmProducts,
        PoiKind.vendingEggsMilk,
        PoiKind.vendingIce,
      },
    ),
  ),

  /// Every place and every point.
  all(
    GuidanceSelection(
      families: {
        KindFamily.stopovers,
        KindFamily.campsites,
        KindFamily.nature,
        KindFamily.services,
      },
      points: {
        PoiCategory.fuel,
        PoiCategory.water,
        PoiCategory.groceries,
        PoiCategory.health,
        PoiCategory.services,
      },
      vending: {
        PoiKind.vendingPizza,
        PoiKind.vendingBread,
        PoiKind.vendingFarmProducts,
        PoiKind.vendingEggsMilk,
        PoiKind.vendingIce,
      },
    ),
  ),

  /// Nothing: the map shows the road alone.
  none(GuidanceSelection());

  new(this.selection);

  final GuidanceSelection selection;
}

/// The places and points the guidance map shows, and how, kept between
/// guidances.
@immutable
final class GuidancePlaces {
  const new({this.selection = defaultSelection, this.look = GuidanceLook.photos});

  /// Reads the stored choice; an older app's (a switch and a few groups over
  /// the map's own filters) becomes the selection those groups made, and
  /// unknown values read as the default.
  factory fromJson(Object? json) {
    if (json is! Map) return const GuidancePlaces();
    final look = GuidanceLook.fromName(json['look']) ?? GuidanceLook.photos;
    if (json['selection'] case final Map<Object?, Object?> selection) {
      return GuidancePlaces(selection: GuidanceSelection.fromJson(selection), look: look);
    }
    if (json['shown'] == false) {
      return GuidancePlaces(selection: GuidancePreset.none.selection, look: look);
    }
    var selection = const GuidanceSelection();
    if (json['groups'] case final List<Object?> groups) {
      for (final group in groups) {
        selection = switch (group) {
          'nights' => selection.copyWith(overnight: {...selection.overnight, ...nightPossible}),
          'fuel' => selection.copyWith(points: {...selection.points, PoiCategory.fuel}),
          'water' => selection.copyWith(
            families: {...selection.families, KindFamily.services},
            amenities: {...selection.amenities, Amenity.water, Amenity.dumpStation},
            points: {...selection.points, PoiCategory.water},
          ),
          _ => selection,
        };
      }
    }
    // No group was the map's own filters, which the guidance no longer
    // follows: the default takes their place.
    return GuidancePlaces(selection: selection.isEmpty ? defaultSelection : selection, look: look);
  }

  /// What a new user starts with: where to spend the night, the question a
  /// motorhome driver asks the map on the way.
  static const GuidanceSelection defaultSelection = GuidanceSelection(overnight: nightPossible);

  final GuidanceSelection selection;
  final GuidanceLook look;

  /// The preset the selection is, null for one the user made.
  GuidancePreset? get preset =>
      GuidancePreset.values.firstWhereOrNull((p) => p.selection == selection);

  /// Whether the map shows any place or point.
  bool get shown => !selection.isEmpty;

  GuidancePlaces copyWith({GuidanceSelection? selection, GuidanceLook? look}) =>
      GuidancePlaces(selection: selection ?? this.selection, look: look ?? this.look);

  Map<String, Object?> toJson() => {'selection': selection.toJson(), 'look': look.name};

  @override
  bool operator ==(Object other) =>
      other is GuidancePlaces && other.selection == selection && other.look == look;

  @override
  int get hashCode => Object.hash(selection, look);
}

/// The MapLibre filter of the places' tiles on the guidance map; null when
/// the selection keeps no place. [mapFilter] is the main map's, resolved:
/// its vehicle height still applies, a barrier is no less low on the way.
List<Object>? guidancePlaceFilter(GuidancePlaces choice, PlaceFilter mapFilter) {
  final s = choice.selection;
  if (!s.placesShown) return null;
  final any = <Object>[
    if (s.overnight.isNotEmpty)
      [
        'match',
        ['get', PlaceTiles.night],
        [
          for (final o in OvernightStatus.values)
            if (s.overnight.contains(o)) tileNightCode(o),
        ],
        true,
        false,
      ],
    if (s.families.isNotEmpty)
      [
        'match',
        ['get', PlaceTiles.kind],
        [
          for (final k in PlaceKind.values)
            if (s.families.contains(k.family)) tileKindCode(k),
        ],
        true,
        false,
      ],
    for (final service in {for (final a in s.amenities) ...a.services})
      placeTileHasService(service),
  ];
  final conditions = <Object>[
    if (any.length == 1) any.single else ['any', ...any],
    if (s.minRating case final rating?)
      [
        '>=',
        [
          'coalesce',
          ['get', PlaceTiles.rating],
          0,
        ],
        ratingTenths(rating),
      ],
    if (mapFilter.vehicleHeightM case final height?) placeTileFitsHeight(height),
  ];
  return conditions.length == 1 ? conditions.single as List<Object> : ['all', ...conditions];
}

/// Whether the guidance map shows [place]: the rule of
/// [guidancePlaceFilter] on what the device knows of it. Offline, the
/// places drawn come from a query of the device with the map's filter
/// (`placesNearRoute`, the height included); the selection keeps its own
/// among them.
bool guidanceKeepsPlace(GuidancePlaces choice, PlaceFilter mapFilter, PlaceSummary place) {
  if (!choice.selection.keeps(place)) return false;
  final height = mapFilter.vehicleHeightM;
  final limit = place.maxHeightM;
  // In whole centimetres, as the tiles compare.
  return height == null || limit == null || heightCentimetres(limit) >= heightCentimetres(height);
}

/// The MapLibre filter of the points' tiles on the guidance map; null when
/// the selection keeps no point.
List<Object>? guidancePoiFilter(GuidancePlaces choice) {
  final s = choice.selection;
  if (!s.pointsShown) return null;
  final any = <Object>[
    if (s.points.isNotEmpty)
      [
        'match',
        ['get', 'category'],
        [
          for (final c in GuidanceSelection.pointCategories)
            if (s.points.contains(c)) c.code,
        ],
        true,
        false,
      ],
    // Every kind chosen is every machine, those that sell something else
    // too.
    if (s.vending.containsAll(PoiKind.vendingChoices))
      [
        '==',
        ['get', 'category'],
        PoiCategory.vending.code,
      ]
    else if (s.vending.isNotEmpty)
      [
        'match',
        ['get', 'kind'],
        [
          for (final k in PoiKind.vendingChoices)
            if (s.vending.contains(k)) k.code,
        ],
        true,
        false,
      ],
  ];
  return any.length == 1 ? any.single as List<Object> : ['any', ...any];
}
