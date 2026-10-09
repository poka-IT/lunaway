@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

import '../helpers/fonts.dart';
import '../helpers/maneuver_catalogue.dart';

/// Each maneuver pictogram at every size the app draws it (the banner, the
/// arrival card, the list of steps, the lanes, the "Then" line), on the
/// guidance banner and on the list's surface in both themes, one device
/// pixel to the logical one, as golden images are taken. One image a
/// pictogram, so a change to one of them shows on its own. The review
/// sheet at two and four device pixels: `tool/pictos/sheet_test.dart`.
void main() {
  setUpAll(loadRealFonts);

  for (final (name, maneuver) in maneuverCatalogue) {
    testWidgets(name, skip: !Platform.isMacOS, (tester) async {
      const gap = 6.0;
      final width = maneuverSizes.fold<double>(0, (w, s) => w + s + gap) + gap;
      final height = maneuverGrounds.length * (maneuverSizes.first + gap);
      tester.view
        ..physicalSize = Size(width, height)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lunaTheme(Brightness.light),
          home: Column(
            key: const Key('sheet'),
            children: [
              for (final (_, background, ink) in maneuverGrounds)
                Container(
                  color: background,
                  height: maneuverSizes.first + gap,
                  padding: const EdgeInsets.fromLTRB(gap, gap / 2, 0, gap / 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final size in maneuverSizes) ...[
                        ManeuverIcon(maneuver: maneuver, size: size, color: ink),
                        const SizedBox(width: gap),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
      await expectLater(
        find.byKey(const Key('sheet')),
        matchesGoldenFile('images/maneuvers/$name.png'),
      );
    });
  }
}
