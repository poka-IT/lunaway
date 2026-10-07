import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/data/ferrostar_engine.dart';
import 'package:lunaway_nav/lunaway_nav.dart' show ExternalLibrary;

import '../../../integration_test/fixtures/engine_trace.dart';
import '../../../integration_test/fixtures/engine_vectors.dart';
import 'ferrostar_bridge_test.dart' show hostLibrary;

/// The shared vectors against the library built for this computer. The
/// phones and the browser run the same vectors
/// (`integration_test/engine_vectors_test.dart`), so a build of the crate
/// that guides differently anywhere is caught.
///
/// After a deliberate change of the engine, write the vectors again:
/// `UPDATE_ENGINE_VECTORS=1 fvm flutter test test/unit/navigation/engine_vectors_test.dart`.
void main() {
  final library = hostLibrary();

  test(
    'the host build answers the shared vectors line for line',
    () async {
      final engine = (await loadFerrostarEngine(library: ExternalLibrary.open(library!)))!;
      final trace = await engineTrace(engine);
      if (Platform.environment['UPDATE_ENGINE_VECTORS'] == '1') {
        File('integration_test/fixtures/engine_trace.dart').writeAsStringSync(
          '// Written by test/unit/navigation/engine_vectors_test.dart from the\n'
          '// macOS build of the guidance crate; see engine_vectors.dart.\n\n'
          '/// What every build of the engine answers along the shared vectors.\n'
          'const engineTraceExpected = <String>[\n'
          '${trace.map((l) => '  ${_literal(l)},\n').join()}'
          '];\n',
        );
      }
      expect(trace.length, greaterThan(500));
      expect(trace, engineTraceExpected);
    },
    skip: library == null
        ? 'the guidance library is not built here (cargo build --release in packages/lunaway_nav/rust)'
        : null,
  );
}

/// [line] as a Dart string literal, in the quotes the lints prefer.
String _literal(String line) {
  final escaped = line.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
  return line.contains("'") && !line.contains('"')
      ? '"$escaped"'
      : "'${escaped.replaceAll("'", r"\'")}'";
}
