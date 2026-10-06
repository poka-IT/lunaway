import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

import '../helpers/samples.dart';

void main() {
  group('formatting in the app language', () {
    final fr = AppLocale.fr.buildSync();
    final en = AppLocale.en.buildSync();

    test('distances round to tens of metres, then tenths of a kilometre', () {
      expect(fr.distance(347), '350 m');
      expect(fr.distance(994), '990 m');
      expect(fr.distance(995), '1,0 km', reason: 'never "1000 m"');
      expect(fr.distance(3240), '3,2 km');
      expect(en.distance(3240), '3.2 km');
      expect(en.distance(9960), '10 km');
      expect(en.distance(48400), '48 km');
    });

    test('counts group thousands the local way', () {
      expect(fr.number(15256), '15\u202f256');
      expect(en.number(15256), '15,256');
      expect(fr.number(420), '420');
    });

    test('file sizes keep one decimal only under ten, and switch unit at a thousand', () {
      expect(fr.fileSize(850 * 1024), '850 ko');
      expect(fr.fileSize(1020 * 1024), '1,0 Mo', reason: 'never "1020,0 ko"');
      expect(en.fileSize((3.3 * 1024 * 1024).round()), '3.3 MB');
      expect(fr.fileSize(23 * 1024 * 1024), '23 Mo');
    });

    test('vehicle weights read in tonnes with the local separator', () {
      expect(fr.tonnes(3.5), '3,5 t');
      expect(en.tonnes(3.5), '3.5 t');
    });

    test('prices drop the cents when there are none', () {
      // CLDR puts a no-break space before the euro sign in French.
      expect(fr.euros(12), '12\u00a0€');
      expect(fr.euros(22.5), '22,50\u00a0€');
      expect(en.euros(12), '€12');
    });

    test('heights keep two decimals with the local separator', () {
      expect(fr.metres(2.1), '2,10 m');
      expect(en.metres(2.1), '2.10 m');
    });

    test('an unnamed place reads as its kind in its town', () {
      expect(
        fr.placeTitle(name: null, kind: PlaceKind.parking, city: 'Saint-Malo'),
        'Parking à Saint-Malo',
      );
      expect(en.placeTitle(name: '', kind: PlaceKind.parking), 'Car park');
    });

    test('ages read naturally', () {
      final now = DateTime(2026, 10, 6);
      expect(fr.ago(now, now), "aujourd'hui");
      expect(fr.ago(DateTime(2026, 10, 5), now), 'hier');
      expect(fr.ago(DateTime(2026, 7, 6), now), 'il y a 3 mois');
      expect(en.ago(DateTime(2024, 9), now), '2 years ago');
    });

    test('the French count forms agree with the number, zero included', () {
      expect(fr.map.placesHereLabel(n: 0), 'lieu ici');
      expect(fr.map.placesHereLabel(n: 1), 'lieu ici');
      expect(fr.map.placesHereLabel(n: 12), 'lieux ici');
      expect(fr.filters.show(n: 15256, count: fr.number(15256)), 'Afficher 15\u202f256 lieux');
    });

    test('an unknown night reads calmly, never as an alarm', () {
      expect(fr.overnightShort(OvernightStatus.unknown), 'Nuit non renseignée');
      expect(en.overnightShort(OvernightStatus.unknown), 'Overnight not reported');
    });
  });

  test('the search query keeps only words, as prefixes', () {
    expect(ftsPrefixQuery('Saint-Malo'), '"saint"* "malo"*');
    expect(ftsPrefixQuery(' "lac" (bleu) '), '"lac"* "bleu"*');
    expect(ftsPrefixQuery('*-*'), isNull);
  });

  group('the map camera', () {
    test('without padding the target is the centre', () {
      const p = LatLng(45, 5);
      expect(centerForPadding(p, 12, EdgeInsets.zero), p);
    });

    test('a sheet over the bottom moves the centre south, so the target shows above it', () {
      const p = LatLng(45, 5);
      final c = centerForPadding(p, 12, const EdgeInsets.only(bottom: 400));
      expect(c.lat, lessThan(p.lat));
      expect(c.lon, closeTo(p.lon, 1e-9));
      // 200 px at zoom 12 (a 2 097 152 px world) is 0.0343 degrees of
      // longitude, so about 0.0343 x cos 45° of latitude.
      expect(p.lat - c.lat, closeTo(0.0243, 0.0005));
    });

    test('a panel on the right moves the centre east', () {
      final c = centerForPadding(const LatLng(45, 5), 10, const EdgeInsets.only(right: 380));
      expect(c.lon, greaterThan(5));
    });

    // Screen position of [p] on a map of [size] whose camera is [camera].
    Offset onScreen(LatLng p, ({LatLng center, double zoom}) camera, Size size) {
      final world = 512 * math.pow(2, camera.zoom).toDouble();
      double x(LatLng q) => (q.lon + 180) / 360 * world;
      double y(LatLng q) {
        final s = math.sin(q.lat * math.pi / 180);
        return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * world;
      }

      return Offset(
        size.width / 2 + x(p) - x(camera.center),
        size.height / 2 + y(p) - y(camera.center),
      );
    }

    test('a fit shows the bounds whole in the part the overlays leave free', () {
      const size = Size(411, 731);
      const padding = EdgeInsets.fromLTRB(16, 192, 16, 298);
      const france = GeoBounds.metropolitanFrance;
      final camera = cameraForBounds(france, size, padding);
      final nw = onScreen(LatLng(france.north, france.west), camera, size);
      final se = onScreen(LatLng(france.south, france.east), camera, size);
      expect(nw.dx, greaterThanOrEqualTo(padding.left - 0.5));
      expect(se.dx, lessThanOrEqualTo(size.width - padding.right + 0.5));
      expect(nw.dy, greaterThanOrEqualTo(padding.top - 0.5));
      expect(se.dy, lessThanOrEqualTo(size.height - padding.bottom + 0.5));
      // The tighter side touches its edges: the fit is as close as it can be.
      final filled = math.max(
        (se.dx - nw.dx) / (size.width - padding.horizontal),
        (se.dy - nw.dy) / (size.height - padding.vertical),
      );
      expect(filled, closeTo(1, 0.002));
      // Centred in the free part, not in the window.
      expect((nw.dy + se.dy) / 2, closeTo((padding.top + size.height - padding.bottom) / 2, 0.5));
    });

    test('only the untouched first camera counts as one to fit', () {
      expect(isFirstCamera(initialViewport), isTrue);
      expect(
        isFirstCamera(
          const MapViewport(
            bounds: GeoBounds.metropolitanFrance,
            center: LatLng(45.9, 6.1),
            zoom: 5,
          ),
        ),
        isFalse,
      );
      expect(
        isFirstCamera(
          const MapViewport(
            bounds: GeoBounds.metropolitanFrance,
            center: initialMapCenter,
            zoom: 6,
          ),
        ),
        isFalse,
      );
    });

    test('a fit never comes closer than its maximum zoom', () {
      const tiny = GeoBounds(south: 45, west: 6, north: 45.0001, east: 6.0001);
      final camera = cameraForBounds(tiny, const Size(400, 800), EdgeInsets.zero, maxZoom: 16);
      expect(camera.zoom, 16);
    });
  });

  test('the map source carries id, kind, pin and rank, nights allowed on top', () {
    final fc = placesFeatureCollection([lakeArea.summary, dayParking.summary]);
    final features = fc['features']! as List<Object?>;
    final lake = features.first! as Map<String, Object?>;
    expect(lake['id'], lakeArea.id);
    expect((lake['geometry']! as Map)['coordinates'], [lakeArea.lon, lakeArea.lat]);
    expect(lake['properties'], {
      'id': lakeArea.id,
      'kind': 'place',
      'icon': 'pin-motorhomeArea-allowed',
      'rank': 4,
    });
    final parking = features.last! as Map<String, Object?>;
    expect((parking['properties']! as Map)['rank'], lessThan(4));
    expect(
      jsonEncode(fc),
      isNot(contains('Lac Bleu')),
      reason: 'names stay out of the map payload',
    );
  });

  test('the selection source marks the selected place, or else a long-pressed point', () {
    List<Object?> features(Map<String, Object?> fc) => fc['features']! as List<Object?>;
    Map<Object?, Object?> props(Map<String, Object?> fc) =>
        (features(fc).single! as Map)['properties']! as Map;
    const point = LatLng(45.7629, 4.831697);
    expect(
      props(pointFeatureCollection(lakeArea.summary))['icon'],
      'pin-motorhomeArea-allowed-selected',
    );
    expect(props(pointFeatureCollection(null, point: point))['icon'], markedPointImageId);
    expect(
      props(pointFeatureCollection(lakeArea.summary, point: point))['icon'],
      'pin-motorhomeArea-allowed-selected',
      reason: 'a place selection wins',
    );
    final marked = features(pointFeatureCollection(null, point: point)).single! as Map;
    expect((marked['geometry']! as Map)['coordinates'], [point.lon, point.lat]);
    expect(features(pointFeatureCollection(null)), isEmpty);
  });

  group('a tap on the map', () {
    test('on a place opens it', () {
      final fc = placesFeatureCollection([lakeArea.summary]);
      final f = (fc['features']! as List<Object?>).single! as Map<String, Object?>;
      expect(mapTapFor(f['properties']! as Map<Object?, Object?>, null), TapPlace(lakeArea.id));
    });

    test('on the long-pressed point marker does nothing (it never reads as a place)', () {
      final fc = pointFeatureCollection(null, point: const LatLng(45, 5));
      final f = (fc['features']! as List<Object?>).single! as Map<String, Object?>;
      expect(
        mapTapFor(f['properties']! as Map<Object?, Object?>, const [5, 45]),
        const TapNothing(),
      );
    });

    test('on a cluster zooms into it, at its position', () {
      expect(
        mapTapFor({'point_count': 12, 'cluster_id': 7}, const [5.5, 45.25]),
        const TapCluster(7, LatLng(45.25, 5.5)),
      );
      expect(mapTapFor({'point_count': 12}, const [5.5, 45.25]), const TapNothing());
    });

    test('on a feature of unknown shape does nothing', () {
      expect(mapTapFor(null, null), const TapNothing());
      expect(mapTapFor({'id': 'x'}, null), const TapNothing(), reason: 'no kind: not ours');
    });
  });

  test('a filter counts and matches by its criteria', () {
    const f = PlaceFilter(
      overnight: nightPossible,
      amenities: {Amenity.water, Amenity.toilets},
      fitsMyVehicle: true,
    );
    expect(f.activeCount, 4);
    expect(f.nightOk, isTrue);
    expect(f.matches(lakeArea.summary), isFalse, reason: 'no toilets');
    expect(PlaceFilter.none.withNightOk(on: true).matches(dayParking.summary), isFalse);
    expect(PlaceFilter.none.isEmpty, isTrue);
    expect(
      PlaceFilter.none.toggleAmenity(Amenity.water).toggleAmenity(Amenity.water),
      PlaceFilter.none,
    );
  });

  test('"my vehicle fits" turns into the stored height, or into nothing without one', () {
    const f = PlaceFilter(fitsMyVehicle: true);
    expect(f.resolve(vehicleHeightM: 2.9).vehicleHeightM, 2.9);
    expect(f.resolve().vehicleHeightM, isNull);
    expect(PlaceFilter.none.resolve(vehicleHeightM: 2.9).vehicleHeightM, isNull);
    expect(f.resolve(vehicleHeightM: 2.9).matches(dayParking.summary, maxHeightM: 2.1), isFalse);
  });

  test('service and activity bits are pinned, so stored masks keep their meaning', () {
    // The bit of a value is written to the device: it must never follow
    // the declaration order. This table is the stored format.
    expect(
      {for (final s in Service.values) s.wire: s.bit},
      {
        'DRINKING_WATER': 1,
        'GREY_WATER': 2,
        'BLACK_WATER': 4,
        'WASTE_BIN': 8,
        'TOILETS': 16,
        'SHOWERS': 32,
        'ELECTRICITY': 64,
        'WIFI': 128,
        'LAUNDRY': 256,
        'LPG': 512,
        'GAS_BOTTLES': 1024,
        'VEHICLE_WASH': 2048,
        'BAKERY': 4096,
        'SWIMMING_POOL': 8192,
        'PETS_ALLOWED': 16384,
        'MOBILE_DATA': 32768,
        'WINTER_CARAVANNING': 65536,
      },
    );
    expect(Activity.values.map((a) => a.position).toSet(), hasLength(Activity.values.length));
    expect(Activity.playground.bit, 1 << 11);
    expect(Service.fromMask(Service.maskOf({Service.lpg, Service.toilets})), {
      Service.lpg,
      Service.toilets,
    });
  });
}
