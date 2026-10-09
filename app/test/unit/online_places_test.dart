import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/online_places.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

void main() {
  test('a filter reads as the API reads it, with the same meaning', () {
    expect(placeFilterInput(PlaceFilter.none), isNull, reason: 'no filter, no argument');
    final input = placeFilterInput(
      const PlaceFilter(
        families: {KindFamily.campsites},
        overnight: {OvernightStatus.allowed, OvernightStatus.tolerated},
        amenities: {Amenity.dumpStation, Amenity.water},
        freeOnly: true,
        vehicleHeightM: 3.2,
        minRating: 4.5,
      ),
    )!;
    expect(input['kinds'], ['CAMPSITE', 'FARM', 'HOMESTAY']);
    expect(input['overnight'], ['ALLOWED', 'TOLERATED']);
    expect(input['serviceGroups'], [
      ['DRINKING_WATER'],
      ['GREY_WATER', 'BLACK_WATER'],
    ], reason: 'a dump station is grey or black water, each group needs one of its services');
    expect(input['freeOnly'], isTrue);
    expect(input['vehicleHeightM'], 3.2);
    expect(input['minRating'], 4.5, reason: 'the list keeps what the tiles keep');
    expect(placeFilterInput(const PlaceFilter(minRating: 3)), {'minRating': 3.0});
  });

  test('the opening filter sends the days it asks, one range or two', () {
    expect(placeFilterInput(const PlaceFilter(opening: AllYearOpening())), {
      'openDays': [
        {'from': 1, 'to': 366},
      ],
    });
    expect(
      placeFilterInput(
        PlaceFilter(opening: StayOpening(DateTime(2026, 12, 28), DateTime(2027, 1, 3))),
      ),
      {
        'openDays': [
          {'from': 1, 'to': 2},
          {'from': 363, 'to': 366},
        ],
      },
      reason: 'the nights of 28 December to 2 January',
    );
  });

  test('the list sends the view and its centre on a grid of 0.05 degree', () async {
    Map<String, dynamic>? sent;
    final client = GraphQLClient(
      endpoint: Uri.parse('https://api.example.org/graphql'),
      httpClient: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {
              'places': {
                'nodes': <Object>[],
                'endCursor': null,
                'hasNextPage': false,
                'totalCount': 0,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      userAgent: 'test',
    );
    await GraphQLOnlinePlaces(client).inBounds(
      const GeoBounds(south: 45, west: 6, north: 46, east: 7),
      PlaceFilter.none,
      near: const LatLng(45.86789, 6.12345),
    );
    final variables = sent!['variables'] as Map<String, dynamic>;
    expect(variables['near'], {'lat': 45.85, 'lon': 6.1}, reason: 'a point of the 0.05 grid');
    expect(variables['filter'], isNull);

    await GraphQLOnlinePlaces(client).inBounds(
      const GeoBounds(south: 45.8612, west: 6.1034, north: 45.9123, east: 6.1789),
      PlaceFilter.none,
      near: const LatLng(45.8868, 6.1411),
    );
    expect((sent!['variables'] as Map<String, dynamic>)['bbox'], {
      'south': 45.85,
      'west': 6.1,
      'north': 45.95,
      'east': 6.2,
    }, reason: 'the view widened to the grid: its centre is not the user');
  });
}
