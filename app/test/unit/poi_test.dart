import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/map/presentation/web_view_map.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_operations.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/gl_poi_layers.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/sprites.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

import '../helpers/poi_fakes.dart';
import '../helpers/samples.dart';

/// A minute since 1970, as the tiles write them.
int _minute(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;

/// A map engine that keeps what the points' layers asked of it and answers
/// each layer of points of the tiles with [features].
final class _Engine implements gl.MapLibreMapController {
  final sources = <String>[];
  final layers = <({String id, String? sourceLayer, String? below, Object? filter})>[];
  final queried = <String?>[];
  Map<String, List<Object?>> features = const {};

  @override
  Future<void> addSource(String sourceId, gl.SourceProperties properties) async {
    if (properties is gl.VectorSourceProperties) sources.add(properties.url ?? '');
  }

  @override
  Future<void> addSymbolLayer(
    String sourceId,
    String layerId,
    gl.SymbolLayerProperties properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    bool enableInteraction = true,
  }) async {
    layers.add((id: layerId, sourceLayer: sourceLayer, below: belowLayerId, filter: filter));
  }

  @override
  Future<List<Object?>> querySourceFeatures(
    String sourceId,
    String? sourceLayerId,
    List<Object>? filter,
  ) async {
    queried.add(sourceLayerId);
    return features[sourceLayerId] ?? const [];
  }

  @override
  Object? noSuchMethod(Invocation invocation) => Future<void>.value();
}

Map<String, Object?> _tileFeature(String id, String kind) => {
  'geometry': {
    'coordinates': [6.13, 45.9],
  },
  'properties': {'id': id, 'kind': kind},
};

void main() {
  group('the hours of a tile', () {
    test('read back as the server wrote them: first opening, then open and closed spans', () {
      final start = DateTime.utc(2026, 10, 6, 5);
      final intervals = decodeTileHours('${_minute(start)}:600,840,600')!;
      expect(intervals, [
        OpeningInterval(start, start.add(const Duration(minutes: 600))),
        OpeningInterval(
          start.add(const Duration(minutes: 1440)),
          start.add(const Duration(minutes: 2040)),
        ),
      ]);
    });

    test('an empty text is closed over the whole window; a malformed one reads as unknown', () {
      expect(decodeTileHours(''), isEmpty);
      // Ending on a closed span, a negative span, no colon: not the
      // server's form (`lunaway_domain::poi::decode_hours` refuses them too).
      expect(decodeTileHours('29854380:600,840'), isNull);
      expect(decodeTileHours('29854380:600,-1,600'), isNull);
      expect(decodeTileHours('600,840'), isNull);
      expect(tileHours(hours: '29854380:600,840', until: 29874120), PoiHours.unknown);
    });

    test('say open, closed, or unknown once the window has run out', () {
      final start = DateTime.utc(2026, 10, 6, 5);
      final hours = tileHours(
        hours: '${_minute(start)}:600',
        until: _minute(DateTime.utc(2026, 10, 7)),
      );
      expect(hours.opennessAt(DateTime.utc(2026, 10, 6, 8)), PoiOpenness.open);
      expect(hours.opennessAt(DateTime.utc(2026, 10, 6, 16)), PoiOpenness.closed);
      expect(hours.opennessAt(DateTime.utc(2026, 10, 8)), PoiOpenness.unknown);
      expect(tileHours(alwaysOpen: true).opennessAt(DateTime.utc(2026, 10, 8)), PoiOpenness.open);
      expect(tileHours().opennessAt(DateTime.utc(2026, 10, 6)), PoiOpenness.unknown);
    });
  });

  test(
    'a tile feature as maplibre answers it becomes a point, or nothing when it lacks its id',
    () {
      // A point of the production tile z13 of Annecy, 2026-10-06.
      final feature = PoiFeature.fromTile(
        {
          'hoursUntil': 29874120,
          'kind': 'supermarket',
          'hours': '29854470:660,780,660',
          'name': 'Lidl',
          'category': 'groceries',
          'id': '01a110ea-c3cb-70cc-a8cd-c590d0276928',
        },
        [6.1147606, 45.8887088],
      )!;
      expect(feature.kind, PoiKind.supermarket);
      expect(feature.category, PoiCategory.groceries);
      expect(feature.name, 'Lidl');
      expect(feature.position, const LatLng(45.8887088, 6.1147606));
      expect(feature.hours.intervals, hasLength(2));
      expect(PoiFeature.fromTile({'kind': 'bakery'}, [6, 45]), isNull);
      expect(PoiFeature.fromTile({'id': 'x', 'kind': 'castle'}, [6, 45]), isNull);
    },
  );

  group('the layer state', () {
    final now = DateTime.utc(2026, 10, 6, 8, 30);
    final open = PoiFeature(
      id: 'open',
      kind: PoiKind.bakery,
      position: const LatLng(45.9, 6.13),
      hours: tileHours(hours: '${_minute(DateTime.utc(2026, 10, 6, 5))}:600', until: 29900000),
    );
    final closed = PoiFeature(
      id: 'closed',
      kind: PoiKind.pharmacy,
      position: const LatLng(45.9, 6.14),
      hours: tileHours(hours: '${_minute(DateTime.utc(2026, 10, 6, 14))}:300', until: 29900000),
    );
    const unknown = PoiFeature(id: 'unknown', kind: PoiKind.atm, position: LatLng(45.9, 6.15));
    // About 22 m and about 80 m east of the place at (45.9, 6.16).
    const onSpot = PoiFeature(
      id: 'dump-here',
      kind: PoiKind.dumpStation,
      position: LatLng(45.9, 6.16028),
    );
    const nearby = PoiFeature(
      id: 'dump-near',
      kind: PoiKind.dumpStation,
      position: LatLng(45.9, 6.16103),
    );

    test('sorts the points open now from those closed, and leaves the unknown out of both', () {
      final state = computePoiLayerState([open, closed, unknown], now, places: const []);
      expect(state.open, {'open'});
      expect(state.closed, {'closed'});
      expect(state.hidden, isEmpty);
    });

    test('hides a dump station a place of the map stands on, not one 80 m away', () {
      final state = computePoiLayerState([onSpot, nearby], now, places: const [LatLng(45.9, 6.16)]);
      expect(state.hidden, {'dump-here'});
    });
  });

  test('a list reads open first, then unknown, then closed, by distance; at night 24/7 first', () {
    Poi poi(String id, double d, PoiHours hours) =>
        Poi(id: id, kind: PoiKind.atm, lat: 45, lon: 6, distanceM: d, hours: hours);
    final now = DateTime.utc(2026, 10, 6, 20, 30);
    final hours = PoiHours(
      intervals: [OpeningInterval(DateTime.utc(2026, 10, 6, 19), DateTime.utc(2026, 10, 6, 22))],
      validUntil: DateTime.utc(2026, 10, 19),
    );
    final shut = PoiHours(
      intervals: [OpeningInterval(DateTime.utc(2026, 10, 7, 7), DateTime.utc(2026, 10, 7, 17))],
      validUntil: DateTime.utc(2026, 10, 19),
    );
    final list = [
      poi('far-open', 900, hours),
      poi('near-closed', 100, shut),
      poi('unknown', 300, PoiHours.unknown),
      poi('always', 1500, const PoiHours(alwaysOpen: true)),
      poi('near-open', 200, hours),
    ];
    expect(sortForReading(list, now).map((p) => p.id), [
      'near-open',
      'far-open',
      'always',
      'unknown',
      'near-closed',
    ]);
    expect(sortForReading(list, now, night: true).first.id, 'always');
  });

  test('night runs from 21:00 to 06:00 on the place clock (summer time in October)', () {
    expect(isNight(DateTime.utc(2026, 10, 6, 18, 59)), isFalse, reason: '20:59 in Paris');
    expect(isNight(DateTime.utc(2026, 10, 6, 19)), isTrue, reason: '21:00 in Paris');
    expect(isNight(DateTime.utc(2026, 10, 6, 3, 59)), isTrue, reason: '05:59 in Paris');
    expect(isNight(DateTime.utc(2026, 10, 6, 4)), isFalse, reason: '06:00 in Paris');
    expect(
      isNight(DateTime.utc(2026, 10, 6, 19), zone: PlaceZone.western),
      isFalse,
      reason: '20:00 in Lisbon',
    );
  });

  group('the taxonomy', () {
    test('every kind is listed by its one category; the restaurants and sights are on demand', () {
      for (final k in PoiKind.values) {
        expect(
          [
            for (final c in PoiCategory.values)
              if (c.kinds.contains(k)) c,
          ],
          [k.category],
          reason: '$k in one list only, the one the chips and "On the way" read',
        );
      }
      expect(PoiCategory.food.kinds, [PoiKind.restaurant, PoiKind.cafe, PoiKind.fastFood]);
      expect(
        PoiCategory.sights.kinds,
        containsAll([PoiKind.viewpoint, PoiKind.attraction, PoiKind.museum, PoiKind.touristOffice]),
        reason: 'the tourist offices tell of what there is to see',
      );
      expect(PoiCategory.services.kinds, contains(PoiKind.outdoorShop));
      expect(
        {
          for (final c in PoiCategory.values)
            if (c.onDemand) c,
        },
        {PoiCategory.food, PoiCategory.sights},
        reason: 'what the default tiles leave out (PoiCategory::on_demand on the server)',
      );
    });

    test('the map reads the tiles of every category only for the categories read on demand', () {
      final container = ProviderContainer.test();
      expect(container.read(poiTileJsonUrlProvider()), endsWith('/poi/tiles.json'));
      expect(container.read(poiTileJsonUrlProvider(all: true)), endsWith('/poi/all/tiles.json'));
    });
  });

  group('the map layers', () {
    const view = PoiLayerView(
      tileJsonUrl: 'https://api.lunaway.net/poi/tiles.json',
      category: PoiCategory.water,
      openNowOnly: true,
      state: PoiLayerState(open: {'b', 'a'}, closed: {'c'}, hidden: {'h'}),
    );

    test(
      'the pins keep the chosen category, drop the hidden, and only the open with "Open now"',
      () {
        expect(PoiMapStyle.pinsFilter(view), [
          'all',
          [
            '==',
            ['get', 'category'],
            'water',
          ],
          [
            '!',
            [
              'in',
              ['get', 'id'],
              [
                'literal',
                ['h'],
              ],
            ],
          ],
          [
            'any',
            [
              '==',
              ['get', 'alwaysOpen'],
              true,
            ],
            [
              'in',
              ['get', 'id'],
              [
                'literal',
                ['a', 'b'],
              ],
            ],
          ],
        ]);
        const all = PoiLayerView(tileJsonUrl: 'x', category: PoiCategory.water);
        expect(PoiMapStyle.pinsFilter(all), hasLength(3), reason: 'no clause for the open ones');
      },
    );

    test(
      'the quiet filter is an expression: MapLibre refuses a bare boolean as a legacy filter',
      () {
        final quiet = PoiMapStyle.quietFilter(const PoiLayerView(tileJsonUrl: 'x'));
        expect(quiet[1], ['boolean', true]);
        expect(PoiMapStyle.quietFilter(view)[1], ['boolean', false]);
      },
    );

    test(
      'a closed point fades; open around the clock goes first at night, with the open by day',
      () {
        expect(PoiMapStyle.opacity(view)[1], [
          'in',
          ['get', 'id'],
          [
            'literal',
            ['c'],
          ],
        ]);
        final night = PoiLayerView(tileJsonUrl: 'x', night: true, state: view.state);
        expect(PoiMapStyle.sortKey(night).sublist(0, 3), [
          'case',
          [
            '==',
            ['get', 'alwaysOpen'],
            true,
          ],
          0,
        ]);
        // By day, open around the clock ranks with the open ones: the map
        // reports none of them back.
        expect(PoiMapStyle.sortKey(view).sublist(0, 5), [
          'case',
          [
            '==',
            ['get', 'alwaysOpen'],
            true,
          ],
          1,
          PoiMapStyle.sortKey(view)[3],
          1,
        ]);
      },
    );

    test('one kind of vending machine alone: its pins, its own dots, nothing of the others', () {
      const pizza = PoiLayerView(
        tileJsonUrl: 'x',
        category: PoiCategory.vending,
        vending: PoiKind.vendingPizza,
      );
      final byKind = [
        '==',
        ['get', 'kind'],
        'vending_pizza',
      ];
      expect(PoiMapStyle.pinsFilter(pizza)[1], byKind);
      expect(PoiMapStyle.probeFilter(pizza)[1], byKind);
      expect(PoiMapStyle.vendingDotsFilter(pizza), byKind);
      expect(PoiMapStyle.dotsFilter(pizza), [
        '==',
        ['get', 'category'],
        '',
      ], reason: 'the category dots count every machine, the pizza dots replace them');

      const every = PoiLayerView(tileJsonUrl: 'x', category: PoiCategory.vending);
      expect(PoiMapStyle.dotsFilter(every)[2], 'vending');
      expect(PoiMapStyle.vendingDotsFilter(every)[2], '', reason: 'no kind dot then');
      expect(PoiMapStyle.pinsFilter(every)[1], [
        '==',
        ['get', 'category'],
        'vending',
      ]);
      // A kind left over from the vending chip never narrows another one.
      const water = PoiLayerView(
        tileJsonUrl: 'x',
        category: PoiCategory.water,
        vending: PoiKind.vendingPizza,
      );
      expect(PoiMapStyle.pinsFilter(water)[1], [
        '==',
        ['get', 'category'],
        'water',
      ]);
      expect(PoiMapStyle.vendingDotsFilter(water)[2], '');

      final images = PoiMapStyle.vendingDotImage;
      expect(images.sublist(2, 4), ['vending_pizza', 'poi-dot-vending_pizza']);
      expect(PoiMapStyle.tappable, contains(PoiMapStyle.vendingDotsLayerId));
      expect(
        poiTapFor({'kind': 'vending_pizza', 'count': 3}, [6.1, 45.9]),
        isA<TapPoiDot>(),
        reason: 'a pizza dot zooms in, as a category dot does',
      );
    });

    test('the vending kind holds with "Open now" and goes with the chip', () {
      final container = ProviderContainer.test();
      final layer = container.read(poiLayerProvider.notifier)
        ..showVending(PoiKind.vendingPizza)
        ..setOpenNowOnly(on: true);
      expect(
        container.read(poiLayerProvider),
        const PoiLayerChoice(
          category: PoiCategory.vending,
          vending: PoiKind.vendingPizza,
          openNowOnly: true,
        ),
      );
      layer.toggle(PoiCategory.vending);
      expect(container.read(poiLayerProvider).category, isNull);
      layer
        ..showVending(PoiKind.vendingBread)
        ..toggle(PoiCategory.water);
      expect(container.read(poiLayerProvider).vending, isNull, reason: 'another chip, no kind');
      layer.showVending(null);
      expect(container.read(poiLayerProvider).vending, isNull, reason: 'every machine');
    });

    test('every kind has its image, drawn for every pixel ratio the app ships', () {
      final match = PoiMapStyle.iconImage();
      expect(match.length, 2 + PoiKind.values.length * 2 + 1);
      for (final ratio in PinSprites.ratios) {
        for (final id in PoiMapStyle.allImageIds()) {
          expect(File('assets/map/pins/${ratio}x/$id.png').existsSync(), isTrue, reason: id);
        }
      }
    });

    test('the kinds the default tiles keep apart are drawn and read like the others', () async {
      final engine = _Engine()
        ..features = {
          'pois': [_tileFeature('a', 'bakery')],
          'pois_more': [_tileFeature('b', 'outdoor_shop')],
        };
      const view = PoiLayerView(
        tileJsonUrl: 'https://api.lunaway.net/poi/tiles.json',
        category: PoiCategory.services,
      );
      final layers = GlPoiLayers();
      await layers.installBelowPlaces(
        engine,
        view,
        pinScale: 1,
        current: () => true,
        dark: false,
        below: 'labels',
        pinsBelow: 'place-pin-dots',
      );
      expect(engine.sources, [view.tileJsonUrl]);
      expect(layers.installedUrl, view.tileJsonUrl);
      final pins = engine.layers.where((l) => l.sourceLayer == 'pois' && l.id.contains('pins'));
      final more = engine.layers.where((l) => l.sourceLayer == 'pois_more');
      expect(more.single.id, PoiMapStyle.morePinsLayerId);
      expect(more.single.filter, pins.single.filter, reason: 'the same chip keeps both');
      expect(
        [pins.single.below, more.single.below],
        ['place-pin-dots', 'place-pin-dots'],
        reason: 'put back under the places, as the style first drew them',
      );
      final seen = await layers.probe(engine, view, zoom: 15, camera: 1);
      expect(engine.queried, ['pois', 'pois_more']);
      expect(seen!.map((f) => f.kind), [PoiKind.bakery, PoiKind.outdoorShop]);
    });

    test("the desktop's page draws and reads both layers of points with the chip's filter", () {
      const view = PoiLayerView(
        tileJsonUrl: 'https://api/poi/all/tiles.json',
        category: PoiCategory.food,
      );
      final spec = webViewMapSpec(dark: false, language: 'fr', pois: view);
      final pins = {
        for (final l in (spec['layers']! as List).cast<Map<String, Object?>>())
          if (l['source'] == PoiMapStyle.source && l['minzoom'] == PoiMapStyle.pointsMinZoom)
            l['source-layer']: l['filter'],
      };
      expect(pins.keys, ['pois', 'pois_more']);
      expect(pins['pois'], PoiMapStyle.pinsFilter(view));
      expect(pins['pois_more'], PoiMapStyle.pinsFilter(view), reason: 'the same chip keeps both');
      expect((spec['pois']! as Map<String, Object?>)['sourceLayers'], ['pois', 'pois_more']);
      final sources = (spec['sources']! as List).cast<Map<String, Object?>>();
      expect(
        sources.firstWhere((s) => s['id'] == PoiMapStyle.source)['url'],
        view.tileJsonUrl,
        reason: 'the page reads the tiles the chip asked for',
      );
    });

    test('a tap names a point, or zooms where a category gathers', () {
      final tap = poiTapFor({'id': 'p1', 'kind': 'bakery', 'category': 'groceries'}, [6.1, 45.9]);
      expect(tap, isA<TapPoi>().having((t) => t.feature.id, 'id', 'p1'));
      final dot = poiTapFor({'category': 'water', 'count': 12}, [6.1, 45.9]);
      expect(dot, isA<TapPoiDot>().having((d) => d.lat, 'lat', 45.9));
      expect(poiTapFor({'kind': 'place', 'id': 'x'}, [6, 45]), isNull);
    });

    test('the quiet points go under the first label layer of the basemap', () {
      expect(
        PoiMapStyle.firstLabelLayer(
          '{"layers":[{"id":"water","type":"fill"},{"id":"roads_label","type":"symbol"}]}',
        ),
        'roads_label',
      );
      expect(PoiMapStyle.firstLabelLayer('https://tiles.lunaway.net/style.json'), isNull);
    });
  });

  test('a search sends where to rank from on a 0.05 degree grid, never a precise point', () {
    final v = searchPoisVariables('lidl', near: const LatLng(45.91234, 6.13456));
    expect(v['near'], {'lat': 45.9, 'lon': 6.15});
    expect(searchPoisVariables('lidl')['near'], isNull);
  });

  group('the API answers', () {
    test('a station reads its prices with LPG first, its shortages and the feed time', () {
      final poi = poiFromJson(stationJson)!;
      expect(poi.fuel!.sortedPrices.map((p) => p.fuel), ['LPG', 'DIESEL', 'E10']);
      expect(poi.fuel!.shortageOf('E85')!.definitive, isFalse);
      expect(poi.fuel!.fetchedAt, DateTime.utc(2026, 10, 6, 8, 20));
      expect(poi.sources.map((s) => s.sourceId), ['osm', 'prix-carburants']);
      expect(poi.address!.city, 'Annecy');
    });

    test('around a place keeps the categories it knows and drops another', () {
      final groups = nearbyPoisFromJson([
        {
          'category': 'WATER',
          'radiusM': 5000,
          'pois': [dumpJson],
        },
        {'category': 'MOON_BASES', 'radiusM': 5000, 'pois': <Object>[]},
        {
          'category': 'FOOD',
          'radiusM': 5000,
          'pois': [poiJson('r', 'RESTAURANT', name: 'Le Garde Manger')],
        },
      ]);
      expect(groups.map((g) => g.category), [PoiCategory.water, PoiCategory.food]);
      expect(groups.first.pois.single.kind, PoiKind.dumpStation);
      expect(groups.last.pois.single.kind, PoiKind.restaurant);
    });

    test('a wash says the vehicles it takes; nothing said is unknown, not no', () {
      final wash = poiFromJson(
        poiJson('w', 'CAR_WASH', extra: {'hgv': true, 'motorhome': null, 'maxHeightM': 4}),
      )!;
      expect(wash.hgv, isTrue);
      expect(wash.motorhome, isNull);
      expect(wash.maxHeightM, 4.0);
      final garage = poiFromJson(poiJson('g', 'MOTORHOME_SHOP', extra: {'motorhome': false}))!;
      expect(garage.motorhome, isFalse);
    });
  });

  group('the copies of the points read', () {
    late CacheDatabase db;
    late FakePoiSource source;
    var now = testNow;
    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      source = FakePoiSource();
      now = testNow;
    });
    tearDown(() => db.close());

    PoiRepository repo({int keep = 400}) =>
        PoiRepository(db: db, source: source, clock: () => now, keep: keep);

    test('a place read once says what is around it offline, saying when it was read', () async {
      final first = await repo().watchNearby('test-lake').toList();
      expect(first.single.offline, isFalse);
      now = testNow.add(const Duration(days: 2));
      source.online = false;
      final again = await repo().watchNearby('test-lake').toList();
      expect(again.map((r) => r.offline), [false, true]);
      expect(again.last.fetchedAt, testNow);
      expect(again.last.value.expand((g) => g.pois).map((p) => p.id), contains(bakeryJson['id']));
    });

    test('offline without a copy, the failure reaches the screen', () async {
      source.online = false;
      expect(repo().watchNearby('test-lake').toList(), throwsA(anything));
    });

    test('a fresh copy is not read again; the oldest copies go first', () async {
      final r = repo(keep: 2);
      await r.watchNearby('a').toList();
      await r.watchNearby('a').toList();
      expect(source.nearbyReads, 1);
      now = now.add(const Duration(minutes: 1));
      await r.watchNearby('b').toList();
      now = now.add(const Duration(minutes: 1));
      await r.watchNearby('c').toList();
      final keys = (await db.select(db.poiCache).get()).map((row) => row.cacheKey);
      expect(keys, unorderedEquals(['nearby:b', 'nearby:c']));
    });
  });
}
