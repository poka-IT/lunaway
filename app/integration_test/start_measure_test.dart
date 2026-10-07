import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/main.dart' as app;
import 'package:path_provider/path_provider.dart';

/// A launch on a phone, timed, then a window for pans: from the start of the
/// app to its first frame and to the first places the map draws ("places
/// drawn", gl_map.dart), then the frames the app itself produces while the
/// map is moved from outside (`adb shell input swipe`, see the report
/// `43-perf-carte.md`). The map's own frames are counted by the system
/// (`dumpsys SurfaceFlinger --latency`), not here.
///
///     fvm flutter drive --profile --driver=test_driver/integration_test.dart \
///       --target=integration_test/start_measure_test.dart -d <device> --flavor store
///
/// `--dart-define=LUNAWAY_MEASURE_EMPTY=true` starts from an empty device
/// (no place, no setting), as a first launch. The numbers come back in
/// `build/integration_response_data.json` and on one line, `MEASURE …`.
const _empty = bool.fromEnvironment('LUNAWAY_MEASURE_EMPTY');

/// How long the app waits, map at rest, while the host pans it.
const _panWindow = Duration(
  seconds: int.fromEnvironment('LUNAWAY_MEASURE_PAN_S', defaultValue: 25),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_empty) return;
    final cache = await CacheDatabase.directory();
    final support = await getApplicationSupportDirectory();
    for (final (dir, name) in [(cache, 'lunaway'), (support, 'lunaway_user')]) {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('${dir.path}/$name.sqlite$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
  });

  testWidgets('launch to the places drawn, then frames while the map is panned', (tester) async {
    final clock = Stopwatch()..start();
    int? drawn;
    final logs = Logger.root.onRecord.listen((r) {
      if (r.loggerName == 'map' && r.message == 'places drawn') drawn ??= clock.elapsedMilliseconds;
    });
    await app.main();
    await tester.pump();
    final firstFrame = clock.elapsedMilliseconds;
    while (drawn == null && clock.elapsed < const Duration(seconds: 90)) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The window for the host's pans: every frame the app builds meanwhile.
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> timings) => frames.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(collect);
    stdout.writeln('MEASURE pan-window-open');
    await tester.runAsync(() => Future<void>.delayed(_panWindow));
    await tester.pump();
    SchedulerBinding.instance.removeTimingsCallback(collect);
    await logs.cancel();

    final build = [for (final f in frames) f.buildDuration.inMicroseconds / 1000]..sort();
    final raster = [for (final f in frames) f.rasterDuration.inMicroseconds / 1000]..sort();
    double at(List<double> sorted, double q) =>
        sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * q).round()];
    final result = {
      'empty': _empty,
      'firstFrameMs': firstFrame,
      'placesDrawnMs': drawn,
      'panFrames': frames.length,
      'buildP50Ms': at(build, 0.5),
      'buildP90Ms': at(build, 0.9),
      'buildMaxMs': build.isEmpty ? 0 : build.last,
      'rasterP50Ms': at(raster, 0.5),
      'rasterP90Ms': at(raster, 0.9),
      'rasterMaxMs': raster.isEmpty ? 0 : raster.last,
      'framesOver16ms': [
        for (final f in frames)
          if (f.totalSpan > const Duration(milliseconds: 16)) 1,
      ].length,
    };
    binding.reportData = {'start': result};
    stdout.writeln('MEASURE $result');
    expect(drawn, isNotNull, reason: 'the map drew no place within 90 s');
  });
}
