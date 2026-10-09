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
  // A third unrated, the others from 1 to 5 in tenths; a third with a
  // height limit.
  final rating = r.nextInt(3) == 0 ? null : (10 + r.nextInt(41)) / 10;
  final height = r.nextInt(3) == 0 ? (180 + r.nextInt(250)) / 100 : null;
  return (
    place: PlaceSummary(
      id: 'p',
      kind: kind,
      lat: 45,
      lon: 6,
      overnight: night,
      services: services,
      ratingForFilters: rating,
      maxHeightM: height,
    ),
    tile: {
      'id': 'p',
      'kind': tileKindCode(kind),
      'night': tileNightCode(night),
      's': Service.maskOf(services),
      if (rating != null) 'r': ratingTenths(rating),
      if (height != null) 'h': heightCentimetres(height),
    },
  );
}

Map<String, Object> _poi(PoiKind kind) => {
  'id': 'x',
  'kind': kind.code,
  'category': kind.category.code,
};

GuidancePlaces _of(GuidanceSelection s) => GuidancePlaces(selection: s);

void main() {
  group('the choice', () {
    test('starts with the places for the night, drawn with their photos', () {
      const choice = GuidancePlaces();
      expect(choice.preset, GuidancePreset.sleep);
      expect(choice.look, GuidanceLook.photos);
      expect(choice.shown, isTrue);
    });

    test('is kept with the route settings, and an unknown value is dropped', () {
      final settings = NavigationSettings(
        guidancePlaces: GuidancePlaces(
          selection: GuidancePreset.fill.selection.toggleMinRating(4),
          look: GuidanceLook.pictograms,
        ),
      );
      expect(NavigationSettings.decode(settings.encode()), settings);
      expect(
        GuidancePlaces.fromJson(const {
          'selection': {
            'families': ['campsites', 'a_later_family'],
            'vending': ['vending_pizza', 'vending_soup'],
            'minRating': 3.7,
          },
          'look': 'holograms',
        }),
        const GuidancePlaces(
          selection: GuidanceSelection(
            families: {KindFamily.campsites},
            vending: {PoiKind.vendingPizza},
          ),
        ),
      );
      expect(GuidancePlaces.fromJson('nonsense'), const GuidancePlaces());
    });

    test("an older app's choice becomes the selection its groups made", () {
      expect(
        GuidancePlaces.fromJson(const {'shown': false, 'groups': <Object>[]}).preset,
        GuidancePreset.none,
      );
      expect(
        GuidancePlaces.fromJson(const {
          'shown': true,
          'groups': ['nights', 'fuel'],
        }).selection,
        const GuidanceSelection(overnight: nightPossible, points: {PoiCategory.fuel}),
      );
      expect(
        GuidancePlaces.fromJson(const {
          'groups': ['fuel', 'water'],
        }).preset,
        GuidancePreset.fill,
        reason: 'fuel and water were the fill-up',
      );
      expect(
        GuidancePlaces.fromJson(const {'shown': true, 'groups': <Object>[]}),
        const GuidancePlaces(),
        reason: "the map's own filters, no longer followed, give the default",
      );
    });

    test("a preset is what the selection is; a category more makes it the user's own", () {
      final fill = _of(GuidancePreset.fill.selection);
      expect(fill.preset, GuidancePreset.fill);
      final more = fill.selection.togglePoints(PoiCategory.health);
      expect(_of(more).preset, isNull);
      expect(_of(more.togglePoints(PoiCategory.health)).preset, GuidancePreset.fill);
      expect(_of(GuidancePreset.none.selection).shown, isFalse);
    });
  });

  group('the places drawn', () {
    test('none for a selection of points only, and none for nothing', () {
      expect(
        guidancePlaceFilter(_of(GuidancePreset.groceries.selection), PlaceFilter.none),
        isNull,
      );
      expect(guidancePlaceFilter(_of(GuidancePreset.none.selection), PlaceFilter.none), isNull);
    });

    test('each selection keeps on the tiles what it keeps on the device', () {
      final r = Random(7);
      final selections = [
        GuidancePreset.sleep.selection,
        GuidancePreset.fill.selection,
        GuidancePreset.all.selection,
        const GuidanceSelection(
          families: {KindFamily.nature},
          overnight: {OvernightStatus.dayOnly},
        ),
        const GuidanceSelection(amenities: {Amenity.showers, Amenity.electricity}, minRating: 4),
        GuidancePreset.sleep.selection.toggleMinRating(3),
      ];
      for (final selection in selections) {
        for (final height in [null, 3.2]) {
          final mapFilter = PlaceFilter(vehicleHeightM: height);
          final filter = guidancePlaceFilter(_of(selection), mapFilter)!;
          for (var i = 0; i < 300; i++) {
            final s = _sample(r);
            expect(
              styleFilterKeeps(filter, s.tile),
              guidanceKeepsPlace(_of(selection), mapFilter, s.place),
              reason: '${selection.toJson()}, height $height, ${s.tile}',
            );
          }
        }
      }
    });

    test('categories add up: nights and services show both kinds of place', () {
      final filter = guidancePlaceFilter(
        _of(const GuidanceSelection(overnight: nightPossible, families: {KindFamily.services})),
        PlaceFilter.none,
      )!;
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'tolerated'}), isTrue);
      expect(styleFilterKeeps(filter, {'kind': 'service_area', 'night': 'forbidden'}), isTrue);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'day_only'}), isFalse);
    });

    test('the minimum rating narrows, and leaves out a place nobody rated', () {
      final filter = guidancePlaceFilter(
        _of(GuidancePreset.sleep.selection.toggleMinRating(4)),
        PlaceFilter.none,
      )!;
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'r': 42}), isTrue);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'r': 38}), isFalse);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed'}), isFalse);
    });

    test("the vehicle's height still keeps out a low barrier", () {
      final filter = guidancePlaceFilter(
        const GuidancePlaces(),
        const PlaceFilter(vehicleHeightM: 3.2),
      )!;
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'h': 210}), isFalse);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed', 'h': 350}), isTrue);
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'allowed'}), isTrue);
    });
  });

  group('the points drawn', () {
    test('the places for the night draw no point', () {
      expect(guidancePoiFilter(const GuidancePlaces()), isNull);
    });

    test('the fill-up keeps fuel, gas and chargers, water and dump points', () {
      final filter = guidancePoiFilter(_of(GuidancePreset.fill.selection))!;
      for (final kind in PoiKind.values) {
        expect(
          styleFilterKeeps(filter, _poi(kind)),
          kind.category == PoiCategory.fuel || kind.category == PoiCategory.water,
          reason: kind.code,
        );
      }
    });

    test('groceries keep the shops and every vending machine; one kind keeps its own', () {
      final groceries = guidancePoiFilter(_of(GuidancePreset.groceries.selection))!;
      for (final kind in PoiKind.values) {
        expect(
          styleFilterKeeps(groceries, _poi(kind)),
          kind.category == PoiCategory.groceries || kind.category == PoiCategory.vending,
          reason: kind.code,
        );
      }
      final pizza = guidancePoiFilter(
        _of(const GuidanceSelection(vending: {PoiKind.vendingPizza})),
      )!;
      expect(styleFilterKeeps(pizza, _poi(PoiKind.vendingPizza)), isTrue);
      expect(styleFilterKeeps(pizza, _poi(PoiKind.vendingBread)), isFalse);
      expect(styleFilterKeeps(pizza, _poi(PoiKind.vendingOther)), isFalse);
    });

    test('all keeps every point', () {
      final filter = guidancePoiFilter(_of(GuidancePreset.all.selection))!;
      for (final kind in PoiKind.values) {
        expect(styleFilterKeeps(filter, _poi(kind)), isTrue, reason: kind.code);
      }
    });
  });
}
