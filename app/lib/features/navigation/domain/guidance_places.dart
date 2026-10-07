import 'package:collection/collection.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// What a driver looks for on the guidance map, one tap each: where to
/// spend the night, fuel, water and a dump station.
enum GuidancePlaceGroup {
  /// The places where a night is allowed or tolerated.
  nights,

  /// The points of the fuel category: stations, gas bottles, chargers.
  fuel,

  /// Drinking water, water points and dump stations, and the places that
  /// offer one of them (a service area, a motorhome area with a borne).
  water;

  static GuidancePlaceGroup? fromName(Object? name) =>
      values.firstWhereOrNull((g) => g.name == name);
}

/// The places and points the guidance map shows, kept between guidances:
/// none, those of the map's own filters (the default), or the groups
/// chosen.
@immutable
final class GuidancePlaces {
  const new({this.shown = true, this.groups = const {}});

  /// Unknown values (an older or a newer app) read as the default.
  factory fromJson(Object? json) {
    if (json is! Map) return const GuidancePlaces();
    final groups = json['groups'];
    return GuidancePlaces(
      shown: json['shown'] != false,
      groups: {
        if (groups is List)
          for (final g in groups) ?GuidancePlaceGroup.fromName(g),
      },
    );
  }

  final bool shown;

  /// Empty: the places and points the main map shows, with its filters.
  final Set<GuidancePlaceGroup> groups;

  bool get mapFilters => groups.isEmpty;

  /// [group] added, or taken out when it was in; none left is the map's
  /// own filters.
  GuidancePlaces toggle(GuidancePlaceGroup group) => GuidancePlaces(
    shown: shown,
    groups: groups.contains(group) ? ({...groups}..remove(group)) : {...groups, group},
  );

  Map<String, Object?> toJson() => {
    'shown': shown,
    'groups': [
      for (final g in GuidancePlaceGroup.values)
        if (groups.contains(g)) g.name,
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is GuidancePlaces &&
      other.shown == shown &&
      const SetEquality<GuidancePlaceGroup>().equals(other.groups, groups);

  @override
  int get hashCode => Object.hash(shown, Object.hashAllUnordered(groups));
}

/// The point kinds of the water group.
const List<PoiKind> waterPoiKinds = [
  PoiKind.drinkingWater,
  PoiKind.waterPoint,
  PoiKind.dumpStation,
];

/// The MapLibre filter of the places' tiles on the guidance map; null when
/// no place shows. [mapFilter] is the main map's, resolved: its vehicle
/// height still applies to the groups, a barrier is no less low there.
List<Object>? guidancePlaceFilter(GuidancePlaces choice, PlaceFilter mapFilter) {
  if (!choice.shown) return null;
  if (choice.mapFilters) return placeTileFilter(mapFilter);
  final groups = <Object>[
    if (choice.groups.contains(GuidancePlaceGroup.nights))
      [
        'match',
        ['get', PlaceTiles.night],
        [for (final o in nightPossible) tileNightCode(o)],
        true,
        false,
      ],
    if (choice.groups.contains(GuidancePlaceGroup.water))
      [
        'any',
        [
          'match',
          ['get', PlaceTiles.kind],
          [for (final k in KindFamily.services.kinds) tileKindCode(k)],
          true,
          false,
        ],
        for (final s in {...Amenity.water.services, ...Amenity.dumpStation.services})
          placeTileHasService(s),
      ],
  ];
  if (groups.isEmpty) return null;
  final height = mapFilter.vehicleHeightM;
  final any = groups.length == 1 ? groups.single : ['any', ...groups];
  if (height == null) return any as List<Object>;
  return ['all', any, placeTileFitsHeight(height)];
}

/// Whether the guidance map shows [place] when it draws the places the
/// device holds (offline): the same rule as [guidancePlaceFilter].
bool guidanceKeepsPlace(GuidancePlaces choice, PlaceFilter mapFilter, PlaceSummary place) {
  if (!choice.shown) return false;
  if (choice.mapFilters) return mapFilter.matches(place);
  final night = choice.groups.contains(GuidancePlaceGroup.nights) && place.overnight.nightOk;
  final water =
      choice.groups.contains(GuidancePlaceGroup.water) &&
      (place.kind.family == KindFamily.services ||
          Amenity.water.offeredBy(place.services) ||
          Amenity.dumpStation.offeredBy(place.services));
  return night || water;
}

/// The MapLibre filter of the points' tiles on the guidance map; null when
/// no point shows. With the map's own filters, the points of the chip the
/// main map has on, none without one: every point of a street would crowd
/// the driver's view.
List<Object>? guidancePoiFilter(
  GuidancePlaces choice, {
  required PoiCategory? category,
  PoiKind? vending,
}) {
  if (!choice.shown) return null;
  if (choice.mapFilters) {
    if (category == null) return null;
    if (category == PoiCategory.vending && vending != null) {
      return [
        '==',
        ['get', 'kind'],
        vending.code,
      ];
    }
    return [
      '==',
      ['get', 'category'],
      category.code,
    ];
  }
  final groups = <Object>[
    if (choice.groups.contains(GuidancePlaceGroup.fuel))
      [
        '==',
        ['get', 'category'],
        PoiCategory.fuel.code,
      ],
    if (choice.groups.contains(GuidancePlaceGroup.water))
      [
        'match',
        ['get', 'kind'],
        [for (final k in waterPoiKinds) k.code],
        true,
        false,
      ],
  ];
  if (groups.isEmpty) return null;
  return groups.length == 1 ? groups.single as List<Object> : ['any', ...groups];
}
