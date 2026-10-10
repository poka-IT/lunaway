import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/place_external_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/place_external_source.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/main.dart' as app;

import '../test/fixtures/place_external.dart';

/// The place card, timed in the real app on a real engine: from the tap to
/// the card on screen, to Lunaway's photos and reviews read from the API,
/// and to the external community source's content merged in. The place and
/// Lunaway's content come from the API the build points at; the external
/// source's answer is the recorded one (`test/fixtures/place_external.dart`)
/// after [_externalLatency], until the API serves it.
///
///     fvm flutter drive --profile --driver test_driver/integration_test.dart \
///       --target integration_test/place_card_measure_test.dart -d <device> \
///       --flavor store --dart-define=LUNAWAY_API_URL=https://api.lunaway.net
///
/// It prints `MEASURE card …` lines (milliseconds), the first open then
/// the median of the next ones, and the slowest frame seen.
const _placeId = String.fromEnvironment(
  'LUNAWAY_MEASURE_PLACE_ID',
  // A campsite by the lake of Annecy, on production.
  defaultValue: '01a10f0e-2a5f-70f9-a1a0-a03fa2a3f83b',
);
const _externalLatency = Duration(
  milliseconds: int.fromEnvironment('LUNAWAY_MEASURE_EXTERNAL_MS', defaultValue: 400),
);
const _opens = 6;

final _placeOperation = GraphQLOperation<Place?>(
  name: 'MeasurePlace',
  document: '''
query MeasurePlace(\$id: UUID!) {
  place(id: \$id) { ...PlaceFields }
}
$placeFieldsFragment''',
  parse: (data) => switch (data['place']) {
    final Map<String, dynamic> p => placeFromJson(p),
    _ => null,
  },
);

/// The recorded answer, after a network's wait.
final class _Recorded implements PlaceExternalSource {
  @override
  Future<ExternalContent> fetch(String placeId, {required int first}) async {
    await Future<void>.delayed(_externalLatency);
    return externalOperation.parse(externalFixture()) ?? ExternalContent.empty;
  }

  @override
  Future<ReviewPage> moreReviews(
    String placeId, {
    required String after,
    required int first,
  }) async => ReviewPage.empty;
}

/// No sync: the measure is of the card, not of a first download running
/// beside it.
final class _NoSync extends SyncController {
  @override
  void start() {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a place card opens, then fills in', (tester) async {
    final config = AppConfig.fromEnvironment();
    final place = await GraphQLClient(
      endpoint: config.graphqlEndpoint,
      httpClient: http.Client(),
      userAgent: AppConfig.userAgent('measure'),
    ).execute(_placeOperation, {'id': _placeId});
    expect(place, isNotNull, reason: 'the place is on the API');

    await app.runLunaway(
      overrides: [
        placeProvider(_placeId).overrideWith((ref) => Stream.value(place)),
        placeExternalSourceProvider.overrideWithValue(_Recorded()),
        syncControllerProvider.overrideWith(_NoSync.new),
      ],
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));

    var worstBuild = Duration.zero;
    var worstRaster = Duration.zero;
    void timings(List<FrameTiming> frames) {
      for (final f in frames) {
        if (f.buildDuration > worstBuild) worstBuild = f.buildDuration;
        if (f.rasterDuration > worstRaster) worstRaster = f.rasterDuration;
      }
    }

    SchedulerBinding.instance.addTimingsCallback(timings);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(timings));

    final runs = <({int open, int ours, int external})>[];
    for (var run = 0; run < _opens; run++) {
      container.read(mapFlowProvider.notifier).select(null);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Keeps the providers alive while the card shows, as its widgets do.
      final ours = container.listen(placeExtrasProvider(_placeId), (_, _) {});
      final feed = container.listen(placeReviewFeedProvider(_placeId), (_, _) {});
      final clock = Stopwatch()..start();
      container.read(mapFlowProvider.notifier).select(const PlaceSelection(_placeId));
      int? open;
      int? oursAt;
      int? externalAt;
      while (clock.elapsed < const Duration(seconds: 30)) {
        await tester.pump();
        open ??= find.byType(PlaceDetailsBody).evaluate().isNotEmpty
            ? clock.elapsedMilliseconds
            : null;
        oursAt ??= container.read(placeExtrasProvider(_placeId)).hasValue
            ? clock.elapsedMilliseconds
            : null;
        externalAt ??= feed.read().reviews.any((r) => r.sourceId == extcomSourceId)
            ? clock.elapsedMilliseconds
            : null;
        if (open != null && oursAt != null && externalAt != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      ours.close();
      feed.close();
      expect(open, isNotNull, reason: 'the card opened');
      runs.add((open: open!, ours: oursAt ?? -1, external: externalAt ?? -1));
    }

    int median(Iterable<int> values) {
      final sorted = values.toList()..sort();
      return sorted[sorted.length ~/ 2];
    }

    final first = runs.first;
    final rest = runs.skip(1);
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    debugPrint(
      'MEASURE card platform=$platform mode=${kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug')} '
      'externalLatency=${_externalLatency.inMilliseconds} '
      'first: open=${first.open} ours=${first.ours} external=${first.external} '
      'then (median of ${rest.length}): open=${median(rest.map((r) => r.open))} '
      'ours=${median(rest.map((r) => r.ours))} external=${median(rest.map((r) => r.external))} '
      'worstBuild=${worstBuild.inMilliseconds} worstRaster=${worstRaster.inMilliseconds}',
    );
  });
}
