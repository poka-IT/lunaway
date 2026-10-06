@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';

/// Every maneuver arrow the banner and the turn list draw, side by side:
/// a turn must read at a glance, and a slight one must not look sharp.
void main() {
  const icons = <(String, String?, int?)>[
    ('depart', null, null),
    ('turn', 'straight', null),
    ('turn', 'slight left', null),
    ('turn', 'left', null),
    ('turn', 'sharp left', null),
    ('turn', 'uturn', null),
    ('turn', 'slight right', null),
    ('turn', 'right', null),
    ('turn', 'sharp right', null),
    ('fork', 'slight left', null),
    ('fork', 'slight right', null),
    ('off ramp', 'slight right', null),
    ('roundabout', null, 90),
    ('roundabout', null, 180),
    ('roundabout', null, 270),
    ('roundabout', 'left', null),
    ('arrive', null, null),
  ];

  testWidgets('the maneuver arrows', skip: !Platform.isMacOS, (tester) async {
    tester.view.physicalSize = const Size(640, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF061F43),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final (type, modifier, exit) in icons)
                SizedBox(
                  width: 64,
                  height: 64,
                  child: ManeuverIcon(
                    type: type,
                    modifier: modifier,
                    roundaboutExitDegrees: exit,
                    color: const Color(0xFFFDF1DB),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await expectLater(find.byType(Wrap), matchesGoldenFile('images/maneuver_icons.png'));
  });
}
