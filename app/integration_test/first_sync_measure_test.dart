import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/last_position.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/main.dart' as app;
import 'package:path_provider/path_provider.dart';

/// A first launch, timed: from the start of the app to the first places of
/// the user's country on the map, and to the end of the first download.
/// France by default; Spain with `--dart-define=LUNAWAY_MEASURE_PLACE=es`,
/// as a traveller whose map last showed Madrid. The device starts empty.
///
///     fvm flutter test integration_test/first_sync_measure_test.dart -d <device> \
///       --flavor store --dart-define=LUNAWAY_API_URL=https://api.lunaway.net
///
/// It prints one line, `MEASURE place=fr first=… here=… done=… places=…`
/// (milliseconds from the start).
const _place = String.fromEnvironment('LUNAWAY_MEASURE_PLACE', defaultValue: 'fr');

const _madrid = LatLng(40.4168, -3.7038);

/// Where the first places count for each case: inland, away from borders.
const _boxes = {
  'fr': GeoBounds(south: 43.5, west: -1, north: 49.5, east: 6),
  'es': GeoBounds(south: 37, west: -7, north: 42.5, east: -1),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // An empty device: no place, no choice of regions, no setting.
    final cache = await CacheDatabase.directory();
    final support = await getApplicationSupportDirectory();
    for (final (dir, name) in [(cache, 'lunaway'), (support, 'lunaway_user')]) {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('${dir.path}/$name.sqlite$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
    if (_place == 'es') {
      final db = CacheDatabase.open(demo: false);
      await DriftLastPositionStore(db).save(_madrid);
      await db.close();
    }
  });

  testWidgets('first launch to a usable map', (tester) async {
    final clock = Stopwatch()..start();
    await app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final repository = container.read(placesRepositoryProvider);
    final box = _boxes[_place]!;
    int? first;
    int? here;
    int? done;
    container.listen(placeCountProvider, (_, _) {});
    while (clock.elapsed < const Duration(minutes: 6)) {
      await tester.pump(const Duration(milliseconds: 100));
      final count = container.read(placeCountProvider).value ?? 0;
      if (first == null && count > 0) first = clock.elapsedMilliseconds;
      if (here == null && count > 0) {
        final inside = await tester.runAsync(
          () => repository.watchInBounds(box, PlaceFilter.none, center: box.center, limit: 1).first,
        );
        if (inside?.isNotEmpty ?? false) here = clock.elapsedMilliseconds;
      }
      if (container.read(syncControllerProvider) is SyncDone) {
        done = clock.elapsedMilliseconds;
        break;
      }
    }
    final places = await tester.runAsync(() => repository.watchCount().first);
    debugPrint('MEASURE place=$_place first=$first here=$here done=$done places=$places');
    expect(done, isNotNull);
  });
}
