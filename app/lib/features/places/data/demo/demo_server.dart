import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/demo/persisted_queries.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

/// Checks a GraphQL document and returns its errors; the contract tests pass
/// a validator built on `schema/lunaway.graphql`.
typedef DocumentValidator = List<String> Function(String document);

/// An in-process stand-in for the API at [apiBase], answering the app's
/// GraphQL operations from [places] and the image proxy's photos with
/// drawn landscapes. The demo mode runs the real client, parser, sync and
/// image pipeline over it, so what the demo shows is what the API path does.
/// With [validate], a document the real server would refuse fails here too.
http.Client demoApiClient(
  List<Place> places, {
  required Uri apiBase,
  Duration latency = const Duration(milliseconds: 150),
  DocumentValidator? validate,
}) {
  final byId = {for (final p in places) p.id: p};
  final persisted = PersistedQueryStore();
  http.Response answer(Map<String, Object?> json) => http.Response(
    jsonEncode(json),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  return MockClient((request) async {
    await Future<void>.delayed(latency);
    final path = request.url.path;
    if (request.method == 'GET' && path.startsWith('${apiBase.path}/media/')) {
      return await _photo(path.substring('${apiBase.path}/media/'.length));
    }
    // The photo proxy of the external community source, which the demo
    // does not have: answered as when the server's daily budget is spent.
    if (request.method == 'GET' && path.startsWith('${apiBase.path}/external-photos/')) {
      return http.Response('', 503, headers: {'retry-after': '3600'});
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final String? document;
    try {
      document = persisted.documentOf(body);
    } on FormatException {
      return answer(PersistedQueryStore.mismatch);
    }
    if (document == null) return answer(PersistedQueryStore.notFound);
    final errors = validate?.call(document) ?? const [];
    if (errors.isNotEmpty) {
      return http.Response(
        jsonEncode({
          'errors': [
            for (final e in errors) {'message': e},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final variables = (body['variables'] as Map<String, dynamic>?) ?? const {};
    final data = switch (body['operationName']) {
      'Changes' => _changes(places, variables),
      // One region, France, with no pack: the demo syncs from its feed.
      'Regions' => {
        'regions': [
          {'code': 'FR', 'country': 'FR', 'name': 'France', 'nameFr': 'France', 'pack': null},
        ],
      },
      'RegionChanges' => {
        'changes': {
          ..._changes(places, variables)['changes']! as Map<String, Object?>,
          'left': <String>[],
        },
      },
      'PlaceExtras' || 'PlaceReviews' => _extras(byId[variables['id']], variables, apiBase),
      // The demo invents nothing for the external community source: its
      // label must only ever stand on what that source said.
      final String op when op.startsWith('PlaceExternal') => _external(
        byId[variables['id']],
        reviewsOnly: op == 'PlaceExternalReviews',
      ),
      'PlaceDigests' => _digests(places, byId, variables),
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

Map<String, Object?> _extras(Place? place, Map<String, dynamic> variables, Uri apiBase) {
  if (place == null) return {'place': null};
  final extras = demoExtras(place, apiBase: apiBase);
  final first = (variables['first'] as int?) ?? 20;
  final start = int.tryParse((variables['after'] as String?) ?? '') ?? 0;
  final end = (start + first).clamp(0, extras.reviews.length);
  return {
    'place': {
      'id': place.id,
      'myReview': null,
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

Map<String, Object?> _external(Place? place, {required bool reviewsOnly}) => {
  'place': place == null
      ? null
      : {
          'id': place.id,
          if (!reviewsOnly) ...{
            'externalPhotos': <Object>[],
            'externalRatings': <Object>[],
            'externalDescriptions': <Object>[],
          },
          'externalReviews': {
            'nodes': <Object>[],
            'endCursor': null,
            'hasNextPage': false,
            'totalCount': 0,
          },
        },
};

/// The digests of the places asked, by id or by area: the demo's own
/// ratings and descriptions, nothing under the external source's label.
Map<String, Object?> _digests(
  List<Place> places,
  Map<String, Place> byId,
  Map<String, dynamic> variables,
) {
  final ids = variables['ids'];
  final box = variables['bbox'];
  final language = (variables['language'] as String?) ?? 'en';
  final chosen = <Place>[
    if (ids is List<dynamic>)
      for (final id in ids) ?byId[id]
    else if (box is Map<String, dynamic>)
      for (final p in places)
        if (p.lat >= (box['south'] as num) &&
            p.lat <= (box['north'] as num) &&
            p.lon >= (box['west'] as num) &&
            p.lon <= (box['east'] as num))
          p,
  ];
  return {
    'placeDigests': [
      for (final p in chosen)
        {
          'placeId': p.id,
          'ratings': ratingsToJson(p.ratings),
          'excerpt': switch (descriptionFor(p.descriptions, language)) {
            final d? => {
              'lang': d.text.lang,
              'text': d.text.text.length > 140 ? '${d.text.text.substring(0, 139)}…' : d.text.text,
              'sourceId': d.text.sourceId,
            },
            null => null,
          },
          'addedAt': p.updatedAt.toUtc().toIso8601String(),
        },
    ],
  };
}

/// `demo-<n>/<thumb|large>`: an invented landscape, drawn on demand. No
/// picture ships with the app, so a release build carries none.
Future<http.Response> _photo(String path) async {
  final match = RegExp(r'^demo-(\d+)/(thumb|large)$').firstMatch(path);
  if (match == null) return http.Response('', 404);
  final scene = int.parse(match[1]!) % _scenes.length;
  final large = match[2] == 'large';
  final size = large ? const ui.Size(1200, 900) : const ui.Size(480, 360);
  final recorder = ui.PictureRecorder();
  _paintScene(ui.Canvas(recorder), size, _scenes[scene]);
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return http.Response.bytes(
    png!.buffer.asUint8List(),
    200,
    headers: {'content-type': 'image/png'},
  );
}

typedef _Scene = ({int skyTop, int skyBottom, int far, int near, bool night});

const List<_Scene> _scenes = [
  (skyTop: 0xFF9CC9E8, skyBottom: 0xFFF5D9A8, far: 0xFF6E9A72, near: 0xFF3F6B4F, night: false),
  (skyTop: 0xFFF2A65A, skyBottom: 0xFFF7D08A, far: 0xFF7A6A8F, near: 0xFF4B3F63, night: false),
  (skyTop: 0xFF061F43, skyBottom: 0xFF15576D, far: 0xFF409FA7, near: 0xFF15576D, night: true),
  (skyTop: 0xFFA8D5E2, skyBottom: 0xFFE8F1F2, far: 0xFF6C9A8B, near: 0xFF2F5D50, night: false),
  (skyTop: 0xFFC9E4CA, skyBottom: 0xFF87BBA2, far: 0xFF55828B, near: 0xFF364958, night: false),
  (skyTop: 0xFF0B2A52, skyBottom: 0xFF2C5F8A, far: 0xFF2E6E7A, near: 0xFF123A4E, night: true),
];

void _paintScene(ui.Canvas canvas, ui.Size size, _Scene s) {
  final w = size.width;
  final h = size.height;
  canvas
    ..drawRect(
      Offset.zero & size,
      ui.Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [
          ui.Color(s.skyTop),
          ui.Color(s.skyBottom),
        ]),
    )
    ..drawCircle(
      Offset(w * 0.72, h * 0.28),
      h * 0.09,
      ui.Paint()..color = ui.Color(s.night ? 0xFFFDF1DB : 0xFFFFF3C4),
    );
  ui.Path hills(double base, double amplitude, double phase) {
    final path = ui.Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += w / 48) {
      path.lineTo(x, h * base - math.sin(x / w * math.pi * 2 + phase) * h * amplitude);
    }
    return path
      ..lineTo(w, h)
      ..close();
  }

  canvas
    ..drawPath(hills(0.62, 0.06, 0.4), ui.Paint()..color = ui.Color(s.far))
    ..drawPath(hills(0.78, 0.05, 2.1), ui.Paint()..color = ui.Color(s.near));
}
