import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Semantics] of the guidance whose label holds [label]: what a screen
/// reader hears where the screen writes less (the bar's distance and
/// arrival time, the road under the vehicle).
Finder guidanceSaid(Pattern label) =>
    find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.contains(label) ?? false));

/// The handle of the guidance's bar, which opens and closes its options.
final Finder guidanceOptionsHandle = find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.label == 'Options du guidage' || w.properties.label == 'Guidance options'),
);

/// Opens the guidance's options under the bar, and lets them grow.
Future<void> openGuidanceOptions(WidgetTester tester) async {
  await tester.tap(guidanceOptionsHandle);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
