import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The reads of a place's card, as the API answers them: a place without a
/// photo of its own, with [externalPhotos] from other sources, and nothing
/// around it.
Map<String, Object?> _answer(String op, List<Object?> externalPhotos) => switch (op) {
  'Place' => {'place': placeToJson(lakeArea)},
  'PlaceExtras' => {
    'place': {
      'id': lakeArea.id,
      'photos': <Object?>[],
      'reviews': {'nodes': <Object?>[], 'hasNextPage': false, 'totalCount': 0},
      'myReview': null,
    },
  },
  'PlaceExternal' => {
    'place': {
      'id': lakeArea.id,
      'externalPhotos': externalPhotos,
      'externalRatings': <Object?>[],
      'externalReviews': {'nodes': <Object?>[], 'hasNextPage': false, 'totalCount': 0},
      'externalDescriptions': <Object?>[],
    },
  },
  'NearbyPois' => {'nearbyPois': <Object?>[]},
  _ => throw StateError('not a read of the card: $op'),
};

const _card = {'Place', 'PlaceExtras', 'PlaceExternal', 'NearbyPois'};

/// A frame at 60 Hz.
const _frame = Duration(milliseconds: 16);

/// A photo of the external community source, as `PlaceExternal` lists it.
const _theirPhoto = <String, Object?>{
  'id': 'their-1',
  'sourceId': 'extcom',
  'kind': 'PLACE',
  'authorName': null,
  'publisher': null,
  'sourceUpdatedOn': null,
  'licence': 'EXT-2026-01',
  'licenceUrl': null,
  'pageUrl': null,
  'takenAt': null,
  'thumbUrl': '$testApiBase/media/demo-4/thumb',
  'largeUrl': '$testApiBase/media/demo-4/large',
  'width': 1200,
  'height': 900,
  'thumbhash': null,
};

/// The API behind the app's own GraphQL client: each request of the card
/// noted in the order it leaves, with the test clock's time, and held until
/// the test answers it. Any other request is answered at once with an error.
final class _HeldApi extends http.BaseClient {
  new(this.now, {this.externalPhotos = const []});

  final DateTime Function() now;
  final List<Object?> externalPhotos;
  final departures = <({String op, DateTime at})>[];
  final _gates = <String, Completer<void>>{};

  /// Lets [op]'s request through, now or once it leaves.
  void answer(String op) {
    final gate = _gates.putIfAbsent(op, Completer.new);
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // The pictures, drawn by the demo server.
    if (request.method == 'GET') return await testDemoClient.send(request);
    final body = jsonDecode(await request.finalize().bytesToString()) as Map<String, dynamic>;
    final op = body['operationName'] as String;
    if (!_card.contains(op)) {
      return _json({
        'data': null,
        'errors': [
          {'message': 'not served here'},
        ],
      });
    }
    departures.add((op: op, at: now()));
    await _gates.putIfAbsent(op, Completer.new).future;
    return _json({'data': _answer(op, externalPhotos)});
  }

  static http.StreamedResponse _json(Object body) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  testWidgets('every read of a place card leaves at the touch, side by side, none waiting for '
      'the place', (tester) async {
    final api = _HeldApi(tester.binding.clock.now);
    final app = await pumpLunaway(tester, httpClient: api, graphQLSources: true, places: const []);
    final touched = tester.binding.clock.now();
    app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
    // The frame of the touch, and the next one.
    await tester.pump(_frame);
    await tester.pump(_frame);

    expect(
      api.departures.map((d) => d.op).toSet(),
      _card,
      reason:
          'the photos and reviews, the other sources and the points around do not wait '
          "for the place's answer",
    );
    for (final d in api.departures) {
      expect(
        d.at.difference(touched),
        lessThanOrEqualTo(_frame),
        reason: '${d.op} left in the frame of the touch',
      );
    }
    expect(api.departures.length, _card.length, reason: 'each once');
    expect(find.byType(PlaceDetailsBody), findsNothing, reason: 'nothing answered yet');
    _card.forEach(api.answer);
    await settleShort(tester);
  });

  for (final (name, size) in [('medium', tablet), ('expanded', desktop)]) {
    testWidgets('the blocks of a card land one by one without moving what is already shown, '
        '$name', (tester) async {
      final api = _HeldApi(tester.binding.clock.now);
      final app = await pumpLunaway(
        tester,
        size: size,
        httpClient: api,
        graphQLSources: true,
        places: const [],
      );
      app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
      await tester.pump();
      api.answer('Place');
      await settleShort(tester);
      // The night, the photos' room, then the place's facts.
      final facts = find
          .descendant(of: find.byType(PlaceDetailsBody), matching: find.text(t.place.services))
          .first;
      expect(facts, findsOneWidget, reason: 'the place shows, its photos still on their way');
      final at = tester.getTopLeft(facts);

      // Lunaway has no photo of it, and the other sources are still to say.
      api.answer('PlaceExtras');
      await settleShort(tester);
      expect(tester.getTopLeft(facts), at, reason: 'the photos still unknown');

      // Nobody has one: the tile for the first photo takes the strip's room.
      api.answer('PlaceExternal');
      await settleShort(tester);
      expect(find.text(t.contribute.firstPhoto), findsOneWidget);
      expect(tester.getTopLeft(facts), at, reason: 'no photo, nothing under them moves');

      api.answer('NearbyPois');
      await settleShort(tester);
      expect(
        app.container(tester).read(placeSurroundingsProvider(lakeArea.id)).hasValue,
        isTrue,
        reason: 'nothing around it, read',
      );
    });
  }

  testWidgets('a place whose photos all come from other sources never offers its first photo '
      'while they are read', (tester) async {
    final api = _HeldApi(tester.binding.clock.now, externalPhotos: const [_theirPhoto]);
    final app = await pumpLunaway(
      tester,
      size: desktop,
      httpClient: api,
      graphQLSources: true,
      places: const [],
    );
    app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(lakeArea.id));
    await tester.pump();
    api
      ..answer('Place')
      ..answer('PlaceExtras');
    await settleShort(tester);
    expect(
      find.text(t.contribute.firstPhoto),
      findsNothing,
      reason: "Lunaway has none, the other sources' are still to come",
    );

    api.answer('PlaceExternal');
    await settleShort(tester);
    expect(
      find.bySemanticsLabel(RegExp('^${t.place.photoPosition(index: 1, count: 1)}')),
      findsOneWidget,
    );
    expect(find.text(t.contribute.firstPhoto), findsNothing);
    api.answer('NearbyPois');
    await settleShort(tester);
  });
}
