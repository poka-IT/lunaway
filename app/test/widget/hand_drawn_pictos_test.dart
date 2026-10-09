import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/presentation/rich_mark_art.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/data/fuel_feed.dart';
import 'package:lunaway/features/poi/presentation/fuel_trend.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_silhouette.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';

import '../helpers/fonts.dart';

/// The pixels of [child], laid out at its own size on a [ground] at
/// [ratio] device pixels per logical one.
Future<({ByteData rgba, int width, int height})> _shoot(
  WidgetTester tester,
  Widget child, {
  double ratio = 1,
  Color ground = const Color(0x00000000),
}) async {
  tester.view
    ..physicalSize = Size(400 * ratio, 300 * ratio)
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: lunaTheme(Brightness.light),
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(color: ground, child: child),
        ),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
  final rgba = (await tester.runAsync(image.toByteData))!;
  final out = (rgba: rgba, width: image.width, height: image.height);
  image.dispose();
  return out;
}

Color _at(({ByteData rgba, int width, int height}) image, num x, num y) {
  final i = (y.floor() * image.width + x.floor()) * 4;
  return Color.fromARGB(
    image.rgba.getUint8(i + 3),
    image.rgba.getUint8(i),
    image.rgba.getUint8(i + 1),
    image.rgba.getUint8(i + 2),
  );
}

class _Painted extends CustomPainter {
  new(this.draw);

  final void Function(Canvas, Size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_Painted old) => true;
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('the cloud of the offline scene is one even tone, its puffs overlapping', (
    tester,
  ) async {
    const width = 150.0;
    final image = await _shoot(tester, const NightScene(mood: SceneMood.offline, width: width));
    // The painter's own construction: the moon at (0.27, 0.3) of the
    // scene, the cloud's middle puff down and right of it, the right puff
    // overlapping it.
    const h = width * 0.62;
    const r = h * 0.15;
    const moon = Offset(width * 0.27, h * 0.3);
    final cloud = moon + const Offset(r * 0.7, r * 0.55);
    final inOne = _at(image, cloud.dx + r * 0.8, cloud.dy - r * 0.03);
    final inTwo = _at(image, cloud.dx + r * 0.4, cloud.dy - r * 0.05);
    expect(inTwo, inOne, reason: 'no darker patch where two puffs overlap');
  });

  testWidgets('a silhouette shows what lies behind it through its windows', (tester) async {
    const red = Color(0xFFFF0000);
    final image = await _shoot(
      tester,
      const VehicleSilhouette(VehicleType.van, color: Palette.minuit, width: 100),
      ground: red,
    );
    // The van's windscreen on its 100 by 50 grid: from 85 to 93 across,
    // 24 to 32 down.
    expect(_at(image, 89, 28), red);
    expect(_at(image, 50, 34), Palette.minuit, reason: 'the body is drawn');
  });

  testWidgets('a capsule keeps its ink inside its image, its point down to the bottom edge', (
    tester,
  ) async {
    const g = RichGeometry(44, labelWidth: 48, capsule: true);
    final size = richMarkCanvas(g);
    const ratio = 4.0;
    final image = await _shoot(
      tester,
      CustomPaint(
        size: size,
        painter: _Painted(
          (canvas, _) => paintRichMark(
            canvas,
            g: g,
            face: const IllustratedFace(label: '4.5', star: true),
            kind: PlaceKind.motorhomeArea,
            night: OvernightStatus.allowed,
          ),
        ),
      ),
      ratio: ratio,
    );
    final middle = image.width / 2;
    expect(_at(image, middle, image.height - 1).a, greaterThan(0.2), reason: 'the point is there');
    for (var x = 0; x < image.width; x++) {
      expect(_at(image, x, 0).a, lessThan(0.05), reason: 'nothing cut at the top, column $x');
    }
  });

  testWidgets('a figure on a route badge stands in its middle', (tester) async {
    final badge = RouteBadge.cluster(MarkTone.info);
    const ratio = 4.0;
    final side = badge.extent;
    final image = await _shoot(
      tester,
      CustomPaint(
        size: Size.square(side),
        painter: _Painted(
          (canvas, size) => paintRouteBadge(
            canvas,
            badge,
            size.center(Offset.zero),
            text: '12',
            fontFamily: 'Atkinson',
          ),
        ),
      ),
      ratio: ratio,
    );
    // The rows that hold the figure's light ink, inside the dark disc.
    final rows = <int>[];
    final radius = badge.diameter / 2 * ratio * 0.8;
    final centre = side * ratio / 2;
    for (var y = 0; y < image.height; y++) {
      for (var x = (centre - radius).floor(); x < centre + radius; x++) {
        if ((x - centre) * (x - centre) + (y - centre) * (y - centre) > radius * radius) continue;
        if (_at(image, x, y).computeLuminance() > 0.5) {
          rows.add(y);
          break;
        }
      }
    }
    final inkMiddle = (rows.first + rows.last + 1) / 2;
    expect(inkMiddle, closeTo(centre, ratio * 0.3), reason: 'rows ${rows.first} to ${rows.last}');
  });

  testWidgets('the price chart draws its baseline on one row of pixels, bars clear of it', (
    tester,
  ) async {
    const baseline = Color(0xFF0000FF);
    const bars = Color(0xFFFF0000);
    final days = [
      for (var i = 0; i < 30; i++)
        FuelPriceDay(
          day: DateTime(2026, 9, 10).add(Duration(days: i)),
          lowEur: i.isEven ? 1.8 : 1.82,
          highEur: 1.85,
        ),
    ];
    final image = await _shoot(
      tester,
      CustomPaint(
        size: const Size(300, 56),
        painter: FuelDaysPainter(days: days, color: bars, baseline: baseline),
      ),
      ground: const Color(0xFFFFFFFF),
    );
    for (var x = 0; x < 300; x += 7) {
      expect(_at(image, x, 55), baseline, reason: 'the last row, at $x');
      expect(_at(image, x, 54), const Color(0xFFFFFFFF), reason: 'the row above, at $x');
    }
  });
}
