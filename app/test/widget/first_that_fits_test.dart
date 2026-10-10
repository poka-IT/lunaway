import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/widgets/first_that_fits.dart';

// The test font draws every glyph a square as wide as the text is high:
// at 10, "aaaaaaaaaa" is 100 wide and "aaaaa" 50; at 30, "aa" is 60.
const _style = TextStyle(fontSize: 10);

/// Three forms of the same words, longest first, the last one taller.
List<Widget> _forms({VoidCallback? onLong, VoidCallback? onShort}) => [
  GestureDetector(
    onTap: onLong,
    child: const Text('aaaaaaaaaa', style: _style),
  ),
  GestureDetector(
    onTap: onShort,
    child: const Text('aaaaa', style: _style),
  ),
  const Text('aa', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 30)),
];

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

void main() {
  testWidgets('shows the first form that fits on one line, else the last', (tester) async {
    for (final (width, shown) in [
      (120.0, 'aaaaaaaaaa'),
      (100.0, 'aaaaaaaaaa'),
      (80.0, 'aaaaa'),
      (30.0, 'aa'),
      (10.0, 'aa'),
    ]) {
      await _pump(
        tester,
        SizedBox(
          width: width,
          child: FirstThatFits(children: _forms()),
        ),
      );
      for (final text in ['aaaaaaaaaa', 'aaaaa', 'aa']) {
        expect(find.text(text), text == shown ? findsOneWidget : findsNothing, reason: '$width');
        expect(find.text(text, skipOffstage: false), findsOneWidget, reason: 'kept, not shown');
      }
    }
  });

  testWidgets('measures as the form it would show, inside a parent that asks first', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 80,
        child: IntrinsicHeight(child: FirstThatFits(children: _forms())),
      ),
    );
    expect(tester.takeException(), isNull);
    final box = tester.renderObject<RenderBox>(find.byType(FirstThatFits));
    expect(box.size, const Size(80, 10));
    expect(box.getMaxIntrinsicHeight(120), 10);
    expect(box.getMinIntrinsicHeight(40), 30, reason: 'the last form, the taller');
    expect(box.getMaxIntrinsicWidth(double.infinity), 100, reason: 'the longest form');
    expect(box.getDryLayout(const BoxConstraints(maxWidth: 80)), const Size(50, 10));
    expect(box.getDryLayout(const BoxConstraints(maxWidth: 40)), const Size(40, 30));
  });

  testWidgets('a screen reader and a tap reach the form shown alone', (tester) async {
    final semantics = tester.ensureSemantics();
    final taps = <String>[];
    await _pump(
      tester,
      SizedBox(
        width: 80,
        child: FirstThatFits(
          children: _forms(onLong: () => taps.add('long'), onShort: () => taps.add('short')),
        ),
      ),
    );
    expect(find.bySemanticsLabel('aaaaa'), findsOneWidget);
    expect(find.bySemanticsLabel('aaaaaaaaaa', skipOffstage: false), findsNothing);
    await tester.tap(find.byType(FirstThatFits));
    expect(taps, ['short']);
    semantics.dispose();
  });
}
