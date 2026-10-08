import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/presentation/widgets/panels_beside_buttons.dart';

/// The guidance's panels and its column of buttons on a small phone held
/// upright, with the bottom bar's 100 px kept free.
void main() {
  const screen = Size(360, 640);
  const banner = ValueKey('banner');
  const notices = ValueKey('notices');
  const buttons = ValueKey('buttons');

  Future<void> pumpPanels(WidgetTester tester, String notice, {bool settle = true}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanelsBesideButtons(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
            gap: 8,
            banner: const SizedBox(key: banner, height: 100),
            // As the guidance's notices: their height follows the text, and
            // eases when it changes.
            notices: AnimatedSize(
              key: notices,
              duration: const Duration(milliseconds: 300),
              alignment: Alignment.topCenter,
              child: Text(notice),
            ),
            buttons: const SizedBox(key: buttons, width: 56, height: 400),
          ),
        ),
      ),
    );
    if (settle) await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a notice that reaches the buttons lies beside them, and the screen comes to rest', (
    tester,
  ) async {
    await pumpPanels(tester, 'Point d’arrivée déplacé de 120 m vers la rue accessible ' * 4);
    final column = tester.getRect(find.byKey(buttons));
    final notice = tester.getRect(find.byKey(notices));
    expect(column.top, 140, reason: 'above the bar');
    expect(notice.top, 108, reason: 'under the banner');
    expect(notice.right, column.left - 8, reason: 'beside the column, with the gap');
    expect(notice.overlaps(column), isFalse);
    expect(
      tester.getRect(find.byKey(banner)).right,
      352,
      reason: 'the banner ends above the column: the whole width',
    );
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'laid out once a pass, the notice does not restart its easing at every frame',
    );
  });

  testWidgets('a notice that appears while the buttons are there is never drawn under them', (
    tester,
  ) async {
    await pumpPanels(tester, '');
    await pumpPanels(
      tester,
      'Point d’arrivée déplacé de 120 m vers la rue accessible ' * 4,
      settle: false,
    );
    final column = tester.getRect(find.byKey(buttons));
    // The easing of the notice, frame by frame.
    for (var frame = 0; frame < 30; frame++) {
      expect(tester.getRect(find.byKey(notices)).overlaps(column), isFalse, reason: 'frame $frame');
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a notice that ends above the buttons keeps the whole width', (tester) async {
    await pumpPanels(tester, 'Nouvel itinéraire');
    expect(tester.getRect(find.byKey(notices)).right, 352);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
