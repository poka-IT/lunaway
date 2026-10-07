import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';

import 'fixtures/engine_trace.dart';
import 'fixtures/engine_vectors.dart';

/// The shared vectors against the engine the app ships on this platform:
/// the library the build hook bundled on a phone or a computer, the
/// WebAssembly build in a browser. They must match the macOS build's
/// answers line for line (`test/unit/navigation/engine_vectors_test.dart`).
///
///   fvm flutter test integration_test/engine_vectors_test.dart -d macos
///   fvm flutter test integration_test/engine_vectors_test.dart -d emulator-5554 --flavor store
///   fvm flutter drive -d web-server --driver test_driver/integration_test.dart \
///     --target integration_test/engine_vectors_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test("this platform's build of the engine answers the shared vectors", () async {
    final engine = await loadFerrostarEngine();
    expect(engine, isNotNull, reason: 'the engine ships on every platform of the app');
    final trace = await engineTrace(engine!);
    final differ = [
      for (var i = 0; i < trace.length && i < engineTraceExpected.length; i++)
        if (trace[i] != engineTraceExpected[i]) '$i: ${trace[i]}\n   ${engineTraceExpected[i]}',
    ];
    expect(differ, isEmpty);
    expect(trace.length, engineTraceExpected.length);
  });
}
