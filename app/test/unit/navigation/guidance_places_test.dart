import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/on_the_way_sheet.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../../helpers/fakes.dart';
import '../../helpers/navigation.dart';
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
    test('starts with every place, the best drawn with their photos', () {
      const choice = GuidancePlaces();
      expect(choice.preset, GuidancePreset.all);
      for (final kind in PlaceKind.values) {
        for (final night in OvernightStatus.values) {
          expect(
            choice.selection.keeps(
              PlaceSummary(id: 'p', kind: kind, lat: 45, lon: 4, overnight: night),
            ),
            isTrue,
            reason: '$kind $night',
          );
        }
      }
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
            'everyPlace': true,
            'categories': ['bakeries', 'a_later_category'],
            'minRating': 3.7,
          },
          'look': 'holograms',
        }),
        const GuidancePlaces(
          selection: GuidanceSelection(everyPlace: true, categories: {OnTheWayCategory.bakeries}),
        ),
      );
      expect(GuidancePlaces.fromJson('nonsense'), const GuidancePlaces());
      expect(
        GuidancePlaces.fromJson(const {
          'selection': {
            'families': ['campsites'],
          },
          'look': 'dots',
        }),
        const GuidancePlaces(look: GuidanceLook.dots),
        reason: 'an earlier form gives the default, not nothing',
      );
    });

    test('in every language, a preset named as a category is that category alone', () async {
      for (final locale in AppLocale.values) {
        final t = await locale.build();
        final presets = {
          GuidancePreset.sleep: t.navigation.guidance.places.sleep,
          GuidancePreset.fill: t.navigation.guidance.places.fill,
          GuidancePreset.groceries: t.navigation.guidance.places.groceries,
          GuidancePreset.all: t.navigation.guidance.places.all,
          GuidancePreset.none: t.navigation.guidance.places.none,
        };
        for (final MapEntry(key: preset, value: name) in presets.entries) {
          for (final c in OnTheWayCategory.values) {
            if (t.onTheWayCategory(c) != name) continue;
            expect(
              preset.selection,
              GuidanceSelection(categories: {c}),
              reason: '${locale.languageCode}: "$name" twice, for two choices',
            );
          }
        }
      }
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
        const GuidanceSelection(categories: {OnTheWayCategory.sleep, OnTheWayCategory.fuel}),
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
      final more = fill.selection.toggleCategory(OnTheWayCategory.health);
      expect(_of(more).preset, isNull);
      expect(_of(more.toggleCategory(OnTheWayCategory.health)).preset, GuidancePreset.fill);
      expect(_of(GuidancePreset.none.selection).shown, isFalse);
    });
  });

  test('each category shows on the map what "On the way" looks for, its stations for fuel', () {
    for (final c in OnTheWayCategory.values) {
      final search = c.search();
      expect(c.mapPlaces, search?.places, reason: c.name);
      expect(
        GuidanceSelection(categories: {c}).poiKinds.toSet(),
        c == OnTheWayCategory.fuel ? {PoiKind.fuelStation} : search!.poiKinds.toSet(),
        reason: c.name,
      );
    }
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
        const GuidanceSelection(categories: {OnTheWayCategory.sleep, OnTheWayCategory.water}),
        const GuidanceSelection(categories: {OnTheWayCategory.water}, minRating: 4),
        GuidancePreset.sleep.selection.toggleMinRating(3),
        const GuidanceSelection(minRating: 4.5),
        const GuidanceSelection(everyPlace: true, minRating: 3),
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

    test('categories add up: the night and water show both kinds of place', () {
      final filter = guidancePlaceFilter(
        _of(const GuidanceSelection(categories: {OnTheWayCategory.sleep, OnTheWayCategory.water})),
        PlaceFilter.none,
      )!;
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'tolerated', 's': 0}), isTrue);
      expect(
        styleFilterKeeps(filter, {
          'kind': 'service_area',
          'night': 'forbidden',
          's': Service.maskOf({Service.drinkingWater}),
        }),
        isTrue,
      );
      expect(styleFilterKeeps(filter, {'kind': 'parking', 'night': 'day_only', 's': 0}), isFalse);
    });

    test('a minimum rating alone keeps every place rated at least that', () {
      final choice = _of(const GuidanceSelection(minRating: 4));
      expect(choice.shown, isTrue);
      final filter = guidancePlaceFilter(choice, PlaceFilter.none)!;
      expect(styleFilterKeeps(filter, {'kind': 'nature', 'night': 'unknown', 'r': 45}), isTrue);
      expect(styleFilterKeeps(filter, {'kind': 'nature', 'night': 'unknown', 'r': 31}), isFalse);
      expect(
        guidanceKeepsPlace(
          choice,
          PlaceFilter.none,
          const PlaceSummary(
            id: 'p',
            kind: PlaceKind.farm,
            lat: 45,
            lon: 4,
            overnight: OvernightStatus.unknown,
            ratingForFilters: 4.4,
          ),
        ),
        isTrue,
      );
      expect(guidancePoiFilter(choice), isNull, reason: 'the points carry no rating');
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
    test('every place, or the places for the night, draw no point', () {
      expect(guidancePoiFilter(const GuidancePlaces()), isNull);
      expect(guidancePoiFilter(_of(GuidancePreset.sleep.selection)), isNull);
    });

    test('restaurants and sights come in the tiles of every category', () {
      final food = _of(const GuidanceSelection(categories: {OnTheWayCategory.food}));
      final filter = guidancePoiFilter(food)!;
      expect(styleFilterKeeps(filter, _poi(PoiKind.restaurant)), isTrue);
      expect(styleFilterKeeps(filter, _poi(PoiKind.bakery)), isFalse);
      expect(guidanceReadsEveryCategory(food), isTrue);
      expect(
        guidanceReadsEveryCategory(
          _of(const GuidanceSelection(categories: {OnTheWayCategory.sights})),
        ),
        isTrue,
      );
      expect(
        guidanceReadsEveryCategory(_of(GuidancePreset.fill.selection)),
        isFalse,
        reason: 'the default tiles for what they hold',
      );
      expect(guidanceReadsEveryCategory(const GuidancePlaces()), isFalse, reason: 'places alone');
      expect(
        guidanceReadsEveryCategory(
          _of(const GuidanceSelection(categories: {OnTheWayCategory.garages})),
        ),
        isTrue,
        reason: 'the outdoor shops are in the layer the guidance draws only in those tiles',
      );
    });

    test('the fill-up keeps the fuel stations, water and dump points', () {
      final filter = guidancePoiFilter(_of(GuidancePreset.fill.selection))!;
      const kept = {
        PoiKind.fuelStation,
        PoiKind.drinkingWater,
        PoiKind.waterPoint,
        PoiKind.dumpStation,
      };
      for (final kind in PoiKind.values) {
        expect(styleFilterKeeps(filter, _poi(kind)), kept.contains(kind), reason: kind.code);
      }
    });

    test('groceries keep the shops, the bakeries and every vending machine', () {
      final groceries = guidancePoiFilter(_of(GuidancePreset.groceries.selection))!;
      for (final kind in PoiKind.values) {
        expect(
          styleFilterKeeps(groceries, _poi(kind)),
          kind.category == PoiCategory.groceries || kind.category == PoiCategory.vending,
          reason: kind.code,
        );
      }
    });

    test('every category chosen keeps every point', () {
      final everything = GuidanceSelection(categories: OnTheWayCategory.values.toSet());
      final filter = guidancePoiFilter(_of(everything))!;
      for (final kind in PoiKind.values) {
        expect(styleFilterKeeps(filter, _poi(kind)), isTrue, reason: kind.code);
      }
    });
  });

  group('offline, the places the guidance chooses among', () {
    Place at(String id, PlaceKind kind, double lat, {double? maxHeightM}) => Place(
      id: id,
      kind: kind,
      lat: lat,
      lon: 1,
      overnight: OvernightStatus.unknown,
      maxHeightM: maxHeightM,
      updatedAt: DateTime.utc(2026),
    );

    final line = [for (var i = 0; i <= 20; i++) LatLng(45 + i * 0.005, 1)];

    test("are every place along the route the vehicle's height lets through", () async {
      final container = ProviderContainer.test(
        overrides: [
          placesRepositoryProvider.overrideWithValue(
            FakePlacesRepository([
              at('campsite', PlaceKind.campsite, 45.01),
              at('parking', PlaceKind.parking, 45.02),
              at('low', PlaceKind.parking, 45.03, maxHeightM: 2.1),
            ]),
          ),
          // The guidance shows every place (the default), the main map
          // the campsites, for a vehicle 3 m high.
          routeSettingsStoreProvider.overrideWithValue(MemoryRouteSettings()),
          effectiveFilterProvider.overrideWithValue(
            const PlaceFilter(families: {KindFamily.campsites}, vehicleHeightM: 3),
          ),
          placesFromTilesProvider.overrideWithValue(false),
        ],
      );
      await container.read(routeSettingsControllerProvider.future);
      final guidance = await container.read(guidancePlacesNearRouteProvider(line).future);
      expect({for (final p in guidance) p.id}, {'campsite', 'parking'});
      final preview = await container.read(placesNearRouteProvider(line).future);
      expect({for (final p in preview) p.id}, {'campsite'}, reason: "the preview's are the map's");
    });

    test('are chosen by the guidance before the nearest are kept', () async {
      final container = ProviderContainer.test(
        overrides: [
          placesRepositoryProvider.overrideWithValue(
            FakePlacesRepository([
              // 130 car parks on the road, more than the cap.
              for (var i = 0; i < 130; i++) at('parking$i', PlaceKind.parking, 45 + i * 0.0007),
              // Two places for the night, 400 m off it.
              for (var i = 0; i < 2; i++)
                Place(
                  id: 'night$i',
                  kind: PlaceKind.motorhomeArea,
                  lat: 45.02 + i * 0.01,
                  lon: 1.005,
                  overnight: OvernightStatus.allowed,
                  updatedAt: DateTime.utc(2026),
                ),
            ]),
          ),
          effectiveFilterProvider.overrideWithValue(PlaceFilter.none),
          placesFromTilesProvider.overrideWithValue(false),
          routeSettingsStoreProvider.overrideWithValue(
            MemoryRouteSettings(
              NavigationSettings(
                guidancePlaces: GuidancePlaces(selection: GuidancePreset.sleep.selection),
              ),
            ),
          ),
        ],
      );
      await container.read(routeSettingsControllerProvider.future);
      final guidance = await container.read(guidancePlacesNearRouteProvider(line).future);
      expect({for (final p in guidance) p.id}, {'night0', 'night1'});
    });
  });
}
