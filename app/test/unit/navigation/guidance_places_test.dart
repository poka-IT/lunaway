import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

import '../../helpers/style_expressions.dart';

/// A place, and the properties its tile gives it.
({PlaceSummary place, Map<String, Object> tile}) _sample(Random r) {
  final kind = PlaceKind.values[r.nextInt(PlaceKind.values.length)];
  final night = OvernightStatus.values[r.nextInt(OvernightStatus.values.length)];
  final services = {
    for (final s in Service.values)
      if (r.nextInt(5) == 0) s,
  };
  return (
    place: PlaceSummary(id: 'p', kind: kind, lat: 45, lon: 6, overnight: night, services: services),
    tile: {
      'id': 'p',
      'kind': tileKindCode(kind),
      'night': tileNightCode(night),
      's': Service.maskOf(services),
    },
  );
}

Map<String, Object> _poi(PoiKind kind) => {
  'id': 'x',
  'kind': kind.code,
  'category': kind.category.code,
};

void main() {
  group('the choice', () {
    test("shows the map's own filters by default", () {
      const choice = GuidancePlaces();
      expect(choice.shown, isTrue);
      expect(choice.mapFilters, isTrue);
    });

    test('is kept with the route settings, and an unknown group is dropped', () {
      const settings = NavigationSettings(
        guidancePlaces: GuidancePlaces(groups: {GuidancePlaceGroup.fuel, GuidancePlaceGroup.water}),
      );
      expect(NavigationSettings.decode(settings.encode()), settings);
      expect(
        GuidancePlaces.fromJson(const {
          'shown': false,
          'groups': ['nights', 'a_later_group'],
        }),
        const GuidancePlaces(shown: false, groups: {GuidancePlaceGroup.nights}),
      );
      expect(GuidancePlaces.fromJson('nonsense'), const GuidancePlaces());
    });

    test("a group taken out last goes back to the map's filters", () {
      final fuel = const GuidancePlaces().toggle(GuidancePlaceGroup.fuel);
      expect(fuel.groups, {GuidancePlaceGroup.fuel});
      expect(fuel.toggle(GuidancePlaceGroup.fuel).mapFilters, isTrue);
    });
  });

  group('the places drawn', () {
    test('none when the user hid them', () {
      expect(guidancePlaceFilter(const GuidancePlaces(shown: false), PlaceFilter.none), isNull);
    });

    test("with the map's filters, the main map's own filter", () {
      const filter = PlaceFilter(families: {KindFamily.campsites}, freeOnly: true);
      expect(guidancePlaceFilter(const GuidancePlaces(), filter), placeTileFilter(filter));
    });

    test('fuel alone draws no place, only its points', () {
      const fuel = GuidancePlaces(groups: {GuidancePlaceGroup.fuel});
      expect(guidancePlaceFilter(fuel, PlaceFilter.none), isNull);
      expect(guidancePoiFilter(fuel, category: null), isNotNull);
    });

    test('each group keeps on the tiles what it keeps on the device', () {
      final r = Random(7);
      for (final groups in [
        {GuidancePlaceGroup.nights},
        {GuidancePlaceGroup.water},
        {GuidancePlaceGroup.nights, GuidancePlaceGroup.water},
        {GuidancePlaceGroup.nights, GuidancePlaceGroup.fuel},
      ]) {
        final choice = GuidancePlaces(groups: groups);
        final filter = guidancePlaceFilter(choice, PlaceFilter.none)!;
        for (var i = 0; i < 300; i++) {
          final s = _sample(r);
          expect(
            styleFilterKeeps(filter, s.tile),
            guidanceKeepsPlace(choice, PlaceFilter.none, s.place),
            reason: '$groups, ${s.tile}',
          );
        }
      }
    });

    test('a night is one allowed or tolerated, water a service point or a borne', () {
      final nights = guidancePlaceFilter(
        const GuidancePlaces(groups: {GuidancePlaceGroup.nights}),
        PlaceFilter.none,
      )!;
      expect(styleFilterKeeps(nights, {'kind': 'parking', 'night': 'tolerated'}), isTrue);
      expect(styleFilterKeeps(nights, {'kind': 'parking', 'night': 'day_only'}), isFalse);
      final water = guidancePlaceFilter(
        const GuidancePlaces(groups: {GuidancePlaceGroup.water}),
        PlaceFilter.none,
      )!;
      expect(styleFilterKeeps(water, {'kind': 'service_area', 'night': 'unknown'}), isTrue);
      expect(
        styleFilterKeeps(water, {
          'kind': 'motorhome_area',
          'night': 'allowed',
          's': Service.maskOf({Service.greyWater}),
        }),
        isTrue,
      );
      expect(styleFilterKeeps(water, {'kind': 'campsite', 'night': 'allowed', 's': 0}), isFalse);
    });

    test("the vehicle's height still keeps out a low barrier in a group", () {
      final filter = guidancePlaceFilter(
        const GuidancePlaces(groups: {GuidancePlaceGroup.nights}),
        const PlaceFilter(vehicleHeightM: 3.2),
      )!;
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'h': 210}), isFalse);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'h': 350}), isTrue);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed'}), isTrue);
    });
  });

  group('the points drawn', () {
    test("with the map's filters, those of the chip on, none without a chip", () {
      const mine = GuidancePlaces();
      expect(guidancePoiFilter(mine, category: null), isNull);
      final water = guidancePoiFilter(mine, category: PoiCategory.water)!;
      expect(styleFilterKeeps(water, _poi(PoiKind.toilets)), isTrue);
      expect(styleFilterKeeps(water, _poi(PoiKind.bakery)), isFalse);
      final pizza = guidancePoiFilter(
        mine,
        category: PoiCategory.vending,
        vending: PoiKind.vendingPizza,
      )!;
      expect(styleFilterKeeps(pizza, _poi(PoiKind.vendingPizza)), isTrue);
      expect(styleFilterKeeps(pizza, _poi(PoiKind.vendingBread)), isFalse);
    });

    test('fuel keeps the stations, gas and chargers; water the water and dump points', () {
      final fuel = guidancePoiFilter(
        const GuidancePlaces(groups: {GuidancePlaceGroup.fuel}),
        category: null,
      )!;
      for (final kind in PoiKind.values) {
        expect(
          styleFilterKeeps(fuel, _poi(kind)),
          kind.category == PoiCategory.fuel,
          reason: kind.code,
        );
      }
      final water = guidancePoiFilter(
        const GuidancePlaces(groups: {GuidancePlaceGroup.water}),
        category: PoiCategory.groceries,
      )!;
      for (final kind in PoiKind.values) {
        expect(
          styleFilterKeeps(water, _poi(kind)),
          waterPoiKinds.contains(kind),
          reason: kind.code,
        );
      }
    });

    test('nights alone draws no point, and hidden draws none', () {
      expect(
        guidancePoiFilter(
          const GuidancePlaces(groups: {GuidancePlaceGroup.nights}),
          category: PoiCategory.fuel,
        ),
        isNull,
      );
      expect(
        guidancePoiFilter(const GuidancePlaces(shown: false), category: PoiCategory.fuel),
        isNull,
      );
    });
  });
}
