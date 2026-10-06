import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

/// An in-process stand-in for the API, answering the app's GraphQL
/// operations from [places]. The demo mode runs the real client, parser and
/// sync over it, so what the demo shows is what the API path does.
http.Client demoApiClient(
  List<Place> places, {
  Duration latency = const Duration(milliseconds: 150),
}) {
  final byId = {for (final p in places) p.id: p};
  return MockClient((request) async {
    await Future<void>.delayed(latency);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final variables = (body['variables'] as Map<String, dynamic>?) ?? const {};
    final data = switch (body['operationName']) {
      'Changes' => _changes(places, variables),
      'PlaceExtras' || 'PlaceReviews' => _extras(byId[variables['id']], variables),
      final other => throw StateError('the demo API does not serve $other'),
    };
    return http.Response(
      jsonEncode({'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

Map<String, Object?> _changes(List<Place> places, Map<String, dynamic> variables) {
  final first = (variables['first'] as int?) ?? 1000;
  final start = int.tryParse((variables['since'] as String?) ?? '') ?? 0;
  final end = (start + first).clamp(0, places.length);
  return {
    'changes': {
      'places': [
        for (final p in places.sublist(start.clamp(0, places.length), end)) placeToJson(p),
      ],
      'deleted': <String>[],
      'cursor': '$end',
      'hasMore': end < places.length,
    },
  };
}

Map<String, Object?> _extras(Place? place, Map<String, dynamic> variables) {
  if (place == null) return {'place': null};
  final extras = demoExtras(place);
  final first = (variables['first'] as int?) ?? 20;
  final start = int.tryParse((variables['after'] as String?) ?? '') ?? 0;
  final end = (start + first).clamp(0, extras.reviews.length);
  return {
    'place': {
      'id': place.id,
      'photos': photosToJson(extras.photos),
      'reviews': reviewPageToJson(
        ReviewPage(
          nodes: extras.reviews.sublist(start.clamp(0, extras.reviews.length), end),
          endCursor: '$end',
          hasNextPage: end < extras.reviews.length,
          totalCount: extras.reviews.length,
        ),
      ),
    },
  };
}
