import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/main.dart' as app;

/// The theme turned on a phone, timed: from the change of setting to the
/// map in its new colours ("theme turned in place", or "style set up" when
/// the style loads whole, gl_map.dart), and the frames the app builds
/// meanwhile. Screenshots of each theme come back with the report.
///
///     fvm flutter drive --profile --driver=test_driver/integration_test.dart \
///       --target=integration_test/theme_switch_measure_test.dart -d <device> --flavor store
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the theme turns without the map loading again', (tester) async {
    final done = <String>[];
    final logs = Logger.root.onRecord.listen((r) {
      if (r.loggerName != 'map') return;
      if (r.message.startsWith('theme turned') || r.message.startsWith('style set up')) {
        done.add(r.message);
      }
    });
    await app.main();
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final clock = Stopwatch()..start();
    while (container.read(viewportProvider) == null && clock.elapsed.inSeconds < 60) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The tiles of the view arrive.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 6)));
    await tester.pump();
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    final results = <String, Object?>{};
    for (final theme in [ThemePreference.dark, ThemePreference.light, ThemePreference.dark]) {
      done.clear();
      final frames = <FrameTiming>[];
      void collect(List<FrameTiming> timings) => frames.addAll(timings);
      SchedulerBinding.instance.addTimingsCallback(collect);
      final switchClock = Stopwatch()..start();
      await container.read(settingsProvider.notifier).setTheme(theme);
      int? turnedMs;
      while (turnedMs == null && switchClock.elapsed.inSeconds < 20) {
        await tester.pump(const Duration(milliseconds: 16));
        if (done.isNotEmpty) turnedMs = switchClock.elapsedMilliseconds;
      }
      // Its colours settle (the app's own theme turns over a second).
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pump();
      SchedulerBinding.instance.removeTimingsCallback(collect);
      final worst = frames.isEmpty
          ? 0
          : frames.map((f) => f.totalSpan.inMicroseconds).reduce((a, b) => a > b ? a : b) / 1000;
      results['${theme.name}-${results.length}'] = {
        'turnedMs': turnedMs,
        'how': done.isEmpty ? null : done.first,
        'frames': frames.length,
        'worstFrameMs': worst,
        'framesOver16ms': frames.where((f) => f.totalSpan.inMilliseconds > 16).length,
      };
      await binding.takeScreenshot('theme-${theme.name}-${results.length}');
    }
    await logs.cancel();
    binding.reportData = {'theme': results};
    stdout.writeln('MEASURE $results');
  });
}
