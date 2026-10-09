import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/messages.dart';

/// Where the shell's messages are placed from: the stage a screen reports
/// and the buttons a message moves aside from, measured where they stand
/// now, whatever moved them.
void main() {
  const screen = Size(400, 800);
  const stage = (left: 0.0, right: 400.0);

  /// A 48 px button [bottom] above the foot of the screen at its right
  /// edge, under a clearance the test reads.
  Future<MessageClearance> pumpButton(
    WidgetTester tester,
    ValueNotifier<double> bottom, {
    ValueNotifier<bool>? active,
    ValueNotifier<bool>? onScreen,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clearance = MessageClearance();
    addTearDown(clearance.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MessageClearanceScope(
          clearance: clearance,
          child: ListenableBuilder(
            listenable: Listenable.merge([bottom, ?active, ?onScreen]),
            builder: (context, _) => TickerMode(
              enabled: onScreen?.value ?? true,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 12,
                    bottom: bottom.value,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: PushesMessagesAside(
                        active: active?.value ?? true,
                        child: const SizedBox.square(dimension: 48),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return clearance;
  }

  // A message one line tall standing 16 px above the foot of the screen.
  EdgeInsets clearOfMessage(MessageClearance clearance) =>
      clearance.clearOf(stage, top: 800 - 16 - 48, bottom: 800 - 16);

  testWidgets('a button level with a message takes its room, gap included', (tester) async {
    final clearance = await pumpButton(tester, ValueNotifier(16));
    expect(clearOfMessage(clearance), const EdgeInsets.only(right: 12 + 48 + 8));
  });

  testWidgets('a button its parent moves is measured where it stands now', (tester) async {
    // As the phone's position button rides the sheet: the same constraints,
    // another place; it is not laid out again.
    final bottom = ValueNotifier<double>(300);
    addTearDown(bottom.dispose);
    final clearance = await pumpButton(tester, bottom);
    expect(clearOfMessage(clearance), EdgeInsets.zero, reason: 'far above the message');
    bottom.value = 16;
    await tester.pump();
    await tester.pump();
    expect(clearOfMessage(clearance), const EdgeInsets.only(right: 68));
    bottom.value = 300;
    await tester.pump();
    await tester.pump();
    expect(clearOfMessage(clearance), EdgeInsets.zero, reason: 'gone up again with the sheet');
  });

  testWidgets('a button faded out, or on a tab not shown, does not count', (tester) async {
    final active = ValueNotifier(true);
    final onScreen = ValueNotifier(true);
    addTearDown(active.dispose);
    addTearDown(onScreen.dispose);
    final clearance = await pumpButton(
      tester,
      ValueNotifier(16),
      active: active,
      onScreen: onScreen,
    );
    expect(clearOfMessage(clearance), const EdgeInsets.only(right: 68));
    active.value = false;
    await tester.pump();
    expect(clearOfMessage(clearance), EdgeInsets.zero, reason: 'faded out');
    active.value = true;
    await tester.pump();
    await tester.pump();
    expect(clearOfMessage(clearance), const EdgeInsets.only(right: 68));
    onScreen.value = false;
    await tester.pump();
    expect(clearOfMessage(clearance), EdgeInsets.zero, reason: 'its tickers off');
  });

  testWidgets('the innermost stage on screen wins, and goes with its screen', (tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clearance = MessageClearance();
    addTearDown(clearance.dispose);
    final inner = ValueNotifier(true);
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MessageClearanceScope(
          clearance: clearance,
          child: Row(
            children: [
              const SizedBox(width: 100),
              Expanded(
                child: MessageStage(
                  child: ListenableBuilder(
                    listenable: inner,
                    builder: (context, _) => Stack(
                      children: [
                        if (inner.value)
                          const Positioned(
                            left: 50,
                            top: 0,
                            bottom: 0,
                            right: 0,
                            child: MessageStage(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(clearance.stage, (left: 150.0, right: 400.0));
    inner.value = false;
    await tester.pump();
    await tester.pump();
    expect(clearance.stage, (left: 100.0, right: 400.0), reason: 'the page beside the rail');
  });
}
