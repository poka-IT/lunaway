// Draws every maneuver pictogram side by side, at every size the app uses
// and on every ground it stands on, for a person to review:
//
//   LUNAWAY_PICTO_SHEET_DIR=<dir> fvm flutter test tool/pictos/sheet_test.dart   # from app/
//
// One PNG per ground at two device pixels per logical pixel, named after
// it (banner-light.png...), and zoom.png: the banner size at four device
// pixels, where a seam or a crooked head shows. Outside test/, so
// `flutter test` alone never writes anything.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

import '../../test/helpers/fonts.dart';
import '../../test/helpers/maneuver_catalogue.dart';

Future<void> _shoot(WidgetTester tester, GlobalKey key, double ratio, String path) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _sheet(Color ground, Color ink, List<double> sizes, {required bool names}) => Material(
  color: ground,
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (name, maneuver) in maneuverCatalogue)
          SizedBox(
            width: sizes.fold<double>(0, (a, s) => a + s + 6) + 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final size in sizes) ...[
                      ManeuverIcon(maneuver: maneuver, size: size, color: ink),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
                if (names)
                  Text(
                    name,
                    style: TextStyle(color: ink, fontSize: 11, fontFamily: 'Atkinson'),
                  ),
              ],
            ),
          ),
      ],
    ),
  ),
);

void main() {
  final dir = Platform.environment['LUNAWAY_PICTO_SHEET_DIR'];

  testWidgets('draws the review sheets', skip: dir == null, (tester) async {
    await tester.runAsync(loadRealFonts);
    Directory(dir!).createSync(recursive: true);
    final key = GlobalKey();
    for (final (ground, background, ink) in maneuverGrounds) {
      tester.view
        ..physicalSize = const Size(1400 * 2, 1700 * 2)
        ..devicePixelRatio = 2;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lunaTheme(Brightness.light),
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 1400,
                child: _sheet(background, ink, maneuverSizes, names: true),
              ),
            ),
          ),
        ),
      );
      await _shoot(tester, key, 2, '$dir/$ground.png');
    }
    tester.view
      ..physicalSize = const Size(1400 * 4, 1100 * 4)
      ..devicePixelRatio = 4;
    final (_, background, ink) = maneuverGrounds.first;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lunaTheme(Brightness.light),
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 1400, child: _sheet(background, ink, const [76], names: true)),
          ),
        ),
      ),
    );
    await _shoot(tester, key, 4, '$dir/zoom.png');
    addTearDown(tester.view.reset);
  });
}
