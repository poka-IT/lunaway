import 'package:collection/collection.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
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

/// What the guidance map shows of a category of "On the way"
/// ([OnTheWayCategory], one definition for both): the places and points its
/// search takes. Fuel's own search ranks stations by price; on the map it is
/// its stations.
extension GuidanceCategory on OnTheWayCategory {
  /// The places it shows; null for none.
  OnTheWayPlaces? get mapPlaces => search()?.places;

  /// The points it shows.
  List<PoiKind> get mapPoiKinds =>
      this == OnTheWayCategory.fuel ? const [PoiKind.fuelStation] : search()!.poiKinds;
}

/// What the guidance map shows of the places and the points of interest:
/// every place or none, the categories of "On the way" ([GuidanceCategory]),
/// and a minimum rating. They add up: "Sleep" and "Water and waste" show
/// both kinds of place. The minimum rating alone narrows, the places only
/// (the points carry none); without a category of places, it keeps every
/// place rated at least that.
@immutable
final class GuidanceSelection {
  const new({this.everyPlace = false, this.categories = const {}, this.minRating});

  /// Unknown values (an older or a newer app) are dropped.
  factory fromJson(Object? json) {
    if (json is! Map) return const GuidanceSelection();
    final rating = json['minRating'];
    return GuidanceSelection(
      everyPlace: json['everyPlace'] == true,
      categories: {
        if (json['categories'] case final List<Object?> list)
          for (final v in list) ?OnTheWayCategory.values.firstWhereOrNull((c) => c.name == v),
      },
      minRating: rating is num && minRatingSteps.contains(rating.toDouble())
          ? rating.toDouble()
          : null,
    );
  }

  /// Every place, of every kind.
  final bool everyPlace;
  final Set<OnTheWayCategory> categories;

  /// The places rated at least this ([minRatingSteps]); null for any.
  final double? minRating;

  /// Whether some places are chosen by kind; without, a minimum rating
  /// alone keeps every place rated at least that.
  bool get _placesChosen => everyPlace || categories.any((c) => c.mapPlaces != null);

  bool get placesShown => _placesChosen || minRating != null;
  bool get pointsShown => categories.any((c) => c.mapPoiKinds.isNotEmpty);
  bool get isEmpty => !placesShown && !pointsShown;

  /// The points of interest shown, in the order of [PoiKind].
  List<PoiKind> get poiKinds {
    final kinds = {for (final c in categories) ...c.mapPoiKinds};
    return [
      for (final k in PoiKind.values)
        if (kinds.contains(k)) k,
    ];
  }

  /// Whether [place] is one of the selection's, before the vehicle's
  /// height ([guidanceKeepsPlace] adds it).
  bool keeps(PlaceSummary place) {
    if (!placesShown) return false;
    final chosen =
        !_placesChosen || everyPlace || categories.any((c) => c.mapPlaces?.takes(place) ?? false);
    final rating = minRating;
    return chosen && (rating == null || meetsMinRating(place.ratingForFilters, rating));
  }

  GuidanceSelection toggleEveryPlace() => copyWith(everyPlace: !everyPlace);

  GuidanceSelection toggleCategory(OnTheWayCategory c) => copyWith(
    categories: categories.contains(c) ? ({...categories}..remove(c)) : {...categories, c},
  );

  /// [step] chosen, or taken off when it was the one.
  GuidanceSelection toggleMinRating(double step) =>
      copyWith(minRating: () => minRating == step ? null : step);

  GuidanceSelection copyWith({
    bool? everyPlace,
    Set<OnTheWayCategory>? categories,
    double? Function()? minRating,
  }) => GuidanceSelection(
    everyPlace: everyPlace ?? this.everyPlace,
    categories: categories ?? this.categories,
    minRating: minRating == null ? this.minRating : minRating(),
  );

  /// In the order of the categories, so two equal selections write the
  /// same text.
  Map<String, Object?> toJson() => {
    'everyPlace': everyPlace,
    'categories': [
      for (final c in OnTheWayCategory.values)
        if (categories.contains(c)) c.name,
    ],
    'minRating': ?minRating,
  };

  static const _categoriesEq = SetEquality<OnTheWayCategory>();

  @override
  bool operator ==(Object other) =>
      other is GuidanceSelection &&
      other.everyPlace == everyPlace &&
      _categoriesEq.equals(other.categories, categories) &&
      other.minRating == minRating;

  @override
  int get hashCode => Object.hash(everyPlace, Object.hashAllUnordered(categories), minRating);
}

/// The places' rule of a category, on the device and on the tiles.
extension on OnTheWayPlaces {
  /// Whether [place] is one these take: every part given holds, as the
  /// server's search reads them.
  bool takes(PlaceSummary place) =>
      (overnight?.contains(place.overnight) ?? true) &&
      (kinds?.contains(place.kind) ?? true) &&
      (anyService.isEmpty || anyService.any(place.services.contains));

  /// The same rule on the places' tiles.
  List<Object> get tileFilter {
    final all = <Object>[
      if (overnight case final night?)
        [
          'match',
          ['get', PlaceTiles.night],
          [
            for (final o in OvernightStatus.values)
              if (night.contains(o)) tileNightCode(o),
          ],
          true,
          false,
        ],
      if (kinds case final kinds?)
        [
          'match',
          ['get', PlaceTiles.kind],
          [
            for (final k in PlaceKind.values)
              if (kinds.contains(k)) tileKindCode(k),
          ],
          true,
          false,
        ],
      if (anyService.isNotEmpty)
        [
          'any',
          for (final s in Service.values)
            if (anyService.contains(s)) placeTileHasService(s),
        ],
    ];
    return switch (all.length) {
      0 => const ['has', PlaceTiles.kind],
      1 => all.single as List<Object>,
      _ => ['all', ...all],
    };
  }
}

/// The ready-made selections the sheet offers first, one tap each, made of
/// the categories of "On the way".
enum GuidancePreset {
  /// The places where a night is allowed or tolerated.
  sleep(GuidanceSelection(categories: {OnTheWayCategory.sleep})),

  /// Fuel, water and the waste points.
  fill(GuidanceSelection(categories: {OnTheWayCategory.fuel, OnTheWayCategory.water})),

  /// Food: the shops, the bakeries, the vending machines, the restaurants
  /// and the cafés. The restaurants make the map read the tiles of every
  /// category ([guidanceReadsEveryCategory]), heavier in a town, for a
  /// preset that says it is for eating.
  groceries(
    GuidanceSelection(
      categories: {
        OnTheWayCategory.groceries,
        OnTheWayCategory.bakeries,
        OnTheWayCategory.food,
        OnTheWayCategory.vending,
      },
    ),
  ),

  /// Every place. The points stay with the presets that ask for them: a
  /// town centre's view ahead (300 m by 600 m) holds 8 to 27 points for 0
  /// to 3 places (Viviers, Montélimar, Annecy, Vannes, 2026-10-09), and
  /// every point would make the shops the map.
  all(GuidancePlaces.defaultSelection),

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
      // A selection of none of these keys is an earlier form, never
      // released: the default rather than nothing at all.
      final known = selection.keys.any(const {'everyPlace', 'categories', 'minRating'}.contains);
      final read = known ? GuidanceSelection.fromJson(selection) : defaultSelection;
      // "Pour manger" chosen before it took the restaurants is that preset
      // still; the same three categories written since are the user's own.
      final former = json['form'] != _formWithFood && read == _formerGroceries;
      return GuidancePlaces(
        selection: former ? GuidancePreset.groceries.selection : read,
        look: look,
      );
    }
    if (json['shown'] == false) {
      return GuidancePlaces(selection: GuidancePreset.none.selection, look: look);
    }
    final categories = <OnTheWayCategory>{
      if (json['groups'] case final List<Object?> groups)
        for (final group in groups)
          ?switch (group) {
            'nights' => OnTheWayCategory.sleep,
            'fuel' => OnTheWayCategory.fuel,
            'water' => OnTheWayCategory.water,
            _ => null,
          },
    };
    // No group was the map's own filters, which the guidance no longer
    // follows: the default takes their place.
    return GuidancePlaces(
      selection: categories.isEmpty ? defaultSelection : GuidanceSelection(categories: categories),
      look: look,
    );
  }

  /// The stored form from the day "Pour manger" took the restaurants: a
  /// choice written without it is read as an earlier app wrote it.
  static const int _formWithFood = 2;

  /// The preset "Pour manger" before the restaurants and the cafés.
  static const _formerGroceries = GuidanceSelection(
    categories: {OnTheWayCategory.groceries, OnTheWayCategory.bakeries, OnTheWayCategory.vending},
  );

  /// What a new user starts with: every place, as the guidance showed them
  /// before its presets. The places for the night alone would leave out
  /// most of them: 2 to 24 % of the places allow or tolerate a night
  /// (Lyon 4 of 252, Viviers 21 of 167, Provence 140 of 1 227, south
  /// Brittany 227 of 935, 2026-10-09).
  static const GuidanceSelection defaultSelection = GuidanceSelection(everyPlace: true);

  final GuidanceSelection selection;
  final GuidanceLook look;

  /// The preset the selection is, null for one the user made.
  GuidancePreset? get preset =>
      GuidancePreset.values.firstWhereOrNull((p) => p.selection == selection);

  /// Whether the map shows any place or point.
  bool get shown => !selection.isEmpty;

  GuidancePlaces copyWith({GuidanceSelection? selection, GuidanceLook? look}) =>
      GuidancePlaces(selection: selection ?? this.selection, look: look ?? this.look);

  Map<String, Object?> toJson() => {
    'form': _formWithFood,
    'selection': selection.toJson(),
    'look': look.name,
  };

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
    if (!s.everyPlace)
      for (final c in OnTheWayCategory.values)
        if (s.categories.contains(c))
          if (c.mapPlaces case final places?) places.tileFilter,
  ];
  final conditions = <Object>[
    if (any.length == 1) any.single else if (any.length > 1) ['any', ...any],
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
  return switch (conditions.length) {
    // Every place: every pin carries its kind (the main map's own form).
    0 => const ['has', PlaceTiles.kind],
    1 => conditions.single as List<Object>,
    _ => ['all', ...conditions],
  };
}

/// Whether the guidance map shows [place]: the rule of
/// [guidancePlaceFilter] on what the device knows of it. Offline, the
/// places drawn come from a query of the device with the vehicle's height
/// alone (`guidancePlacesNearRoute`); the selection keeps its own among
/// them.
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
  final kinds = choice.selection.poiKinds;
  if (kinds.isEmpty) return null;
  return [
    'match',
    ['get', 'kind'],
    [for (final k in kinds) k.code],
    true,
    false,
  ];
}

/// Whether the guidance map reads the tiles of every category: only when
/// it shows points of a category read on demand ([PoiCategory.onDemand]:
/// "Restaurants et cafés", "À voir"), which the default tiles leave out. A
/// kind the default tiles keep apart (the outdoor shops of "Garages et
/// équipement") comes in their layer `pois_more`, which the guidance map
/// draws beside `pois` (`RoutePlaceLayers.poiMorePins`).
bool guidanceReadsEveryCategory(GuidancePlaces choice) =>
    choice.selection.poiKinds.any((k) => k.category.onDemand);
