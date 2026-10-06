import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file under `test/`: golden images compare with a
/// small tolerance, so a macOS release that anti-aliases a glyph edge
/// differently does not fail the CI, while a moved widget, a changed colour
/// or a missing icon still does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final local = goldenFileComparator;
  if (local is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(local.basedir.resolve('golden_test.dart'));
  }
  await testMain();
}

/// Share of pixels allowed to differ: about 1,800 pixels of a phone screen.
const _tolerance = 0.005;

final class _TolerantComparator extends LocalFileComparator {
  new(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
