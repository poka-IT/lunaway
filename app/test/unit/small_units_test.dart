import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/labels.dart';

import '../helpers/samples.dart';

void main() {
  group('formatting in the app language', () {
    final fr = AppLocale.fr.buildSync();
    final en = AppLocale.en.buildSync();

    test('distances round to tens of metres, then tenths of a kilometre', () {
      expect(fr.distance(347), '350 m');
      expect(fr.distance(3240), '3,2 km');
      expect(en.distance(3240), '3.2 km');
      expect(en.distance(48400), '48 km');
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

    test('the French count forms carry the number, zero included', () {
      expect(fr.map.placesHere(n: 0), '0 lieu ici');
      expect(fr.map.placesHere(n: 1), '1 lieu ici');
      expect(fr.map.placesHere(n: 12), '12 lieux ici');
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
  });

  test('the map source carries id, pin and rank, nights allowed on top', () {
    final fc = placesFeatureCollection([lakeArea.summary, dayParking.summary]);
    final features = fc['features']! as List<Object?>;
    final lake = features.first! as Map<String, Object?>;
    expect(lake['id'], lakeArea.id);
    expect((lake['geometry']! as Map)['coordinates'], [lakeArea.lon, lakeArea.lat]);
    expect(lake['properties'], {'id': lakeArea.id, 'icon': 'pin-stopovers-allowed', 'rank': 4});
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
    Object? icon(Map<String, Object?> fc) =>
        ((features(fc).single! as Map)['properties']! as Map)['icon'];
    const point = LatLng(45.7629, 4.831697);
    expect(icon(pointFeatureCollection(lakeArea.summary)), 'pin-stopovers-allowed');
    expect(icon(pointFeatureCollection(null, point: point)), markedPointImageId);
    expect(
      icon(pointFeatureCollection(lakeArea.summary, point: point)),
      'pin-stopovers-allowed',
      reason: 'a place selection wins',
    );
    final marked = features(pointFeatureCollection(null, point: point)).single! as Map;
    expect((marked['geometry']! as Map)['coordinates'], [point.lon, point.lat]);
    expect(features(pointFeatureCollection(null)), isEmpty);
  });

  test('a filter counts and matches by its criteria', () {
    const f = PlaceFilter(
      nightOk: true,
      amenities: {Amenity.water, Amenity.toilets},
      vehicleHeightM: 3,
    );
    expect(f.activeCount, 4);
    expect(f.matches(lakeArea.summary), isFalse, reason: 'no toilets');
    expect(PlaceFilter.initial.matches(dayParking.summary), isFalse);
    expect(PlaceFilter.none.isEmpty, isTrue);
    expect(
      PlaceFilter.none.toggleAmenity(Amenity.water).toggleAmenity(Amenity.water),
      PlaceFilter.none,
    );
  });

  group('directions', () {
    const to = LatLng(45.7629, 4.831697);

    test('Android hands a geo: link to the system chooser', () {
      expect(NavigationTarget.forPlatform(TargetPlatform.android, web: false), [
        NavigationTarget.system,
      ]);
      expect(
        NavigationTarget.system.url(to, label: 'Aire du Lac').toString(),
        'geo:45.762900,4.831697?q=45.762900,4.831697(Aire%20du%20Lac)',
      );
    });

    test('iOS offers Apple Maps, Google Maps and Waze', () {
      expect(NavigationTarget.forPlatform(TargetPlatform.iOS, web: false), [
        NavigationTarget.appleMaps,
        NavigationTarget.googleMaps,
        NavigationTarget.waze,
      ]);
      expect(
        NavigationTarget.appleMaps.url(to).toString(),
        'https://maps.apple.com/?daddr=45.762900%2C4.831697&dirflg=d',
      );
    });

    test('the web offers links that open in a new tab', () {
      expect(NavigationTarget.forPlatform(TargetPlatform.android, web: true), [
        NavigationTarget.googleMaps,
        NavigationTarget.openStreetMap,
      ]);
      expect(
        NavigationTarget.openStreetMap.url(to).toString(),
        'https://www.openstreetmap.org/directions?route=%3B45.762900%2C4.831697',
      );
    });
  });

  test('a photo still being fetched by the proxy is retried once after the asked delay', () {
    http.Response r(int status, [String? retry]) =>
        http.Response('', status, headers: {'retry-after': ?retry});
    expect(CachedImage.retryDelay(r(404, '3')), const Duration(seconds: 3));
    expect(CachedImage.retryDelay(r(404, '600')), const Duration(seconds: 30), reason: 'capped');
    expect(CachedImage.retryDelay(r(404)), isNull);
    expect(CachedImage.retryDelay(r(503, '3')), isNull);
  });
}
