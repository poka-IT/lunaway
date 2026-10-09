import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';

/// The pixels of [icon] drawn white on black at [ratio] device pixels per
/// logical pixel, its box at a whole logical offset: one byte of
/// brightness per pixel, row after row.
Future<({Uint8List grey, int width, int height})> _render(
  WidgetTester tester,
  Widget icon, {
  double ratio = 1,
}) async {
  tester.view
    ..physicalSize = Size(200 * ratio, 200 * ratio)
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: Colors.black,
            child: Padding(padding: const EdgeInsets.all(8), child: icon),
          ),
        ),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  final rgba = bytes.buffer.asUint8List();
  final grey = Uint8List(image.width * image.height);
  for (var i = 0; i < grey.length; i++) {
    grey[i] = rgba[i * 4];
  }
  final out = (grey: grey, width: image.width, height: image.height);
  image.dispose();
  return out;
}

/// How many separate patches of bright pixels there are.
int _patches(({Uint8List grey, int width, int height}) image) {
  final seen = Uint8List(image.grey.length);
  var patches = 0;
  for (var start = 0; start < image.grey.length; start++) {
    if (seen[start] == 1 || image.grey[start] < 128) continue;
    patches++;
    final queue = [start];
    seen[start] = 1;
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      final x = i % image.width;
      final y = i ~/ image.width;
      for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= image.width || ny >= image.height) continue;
        final j = ny * image.width + nx;
        if (seen[j] == 1 || image.grey[j] < 128) continue;
        seen[j] = 1;
        queue.add(j);
      }
    }
  }
  return patches;
}

void main() {
  const white = Colors.white;
  const none = Color(0x00000000);

  group('the way a pictogram shows is one unbroken line', () {
    for (final (name, maneuver) in [
      (
        'a roundabout, second exit a little left',
        const Maneuver(type: 'roundabout', exitDegrees: 212),
      ),
      ('a roundabout, first exit right', const Maneuver(type: 'roundabout', exitDegrees: 90)),
      ('a roundabout, third exit left', const Maneuver(type: 'roundabout', exitDegrees: 270)),
      (
        'a roundabout where traffic keeps left',
        const Maneuver(type: 'roundabout', exitDegrees: 90, leftHandTraffic: true),
      ),
      ('a sharp left', const Maneuver(type: 'turn', modifier: 'sharp left')),
      ('a U-turn', const Maneuver(type: 'turn', modifier: 'uturn')),
    ]) {
      testWidgets(name, (tester) async {
        // Only the way taken is drawn: the muted parts are transparent, so
        // the line must hold together by itself from the entry to the head.
        final image = await _render(
          tester,
          ManeuverIcon(maneuver: maneuver, size: 76, color: white, mutedColor: none),
        );
        expect(_patches(image), 1);
      });
    }
  });

  testWidgets('a vertical line has whole pixels on both edges, at the sizes the app draws', (
    tester,
  ) async {
    for (final (size, ratio) in [(28.0, 1.0), (32.0, 1.0), (76.0, 1.0), (76.0, 2.0), (28.0, 3.0)]) {
      final image = await _render(
        tester,
        ManeuverIcon(
          maneuver: const Maneuver(type: 'turn', modifier: 'straight'),
          size: size,
          color: white,
        ),
        ratio: ratio,
      );
      // A row across the middle of the stem: every pixel lit or dark, none
      // half covered, which would blur the edge.
      final y = ((8 + size * 0.75) * ratio).round();
      final row = image.grey.sublist(y * image.width, (y + 1) * image.width);
      final blurred = row.where((v) => v > 12 && v < 243).length;
      expect(blurred, 0, reason: '$size px at $ratio: ${row.where((v) => v > 0).toList()}');
      expect(row.where((v) => v >= 243), isNotEmpty);
    }
  });

  testWidgets('a roundabout shows its exit number from the banner size, not on the small "then" '
      'line', (tester) async {
    const maneuver = Maneuver(type: 'roundabout', exitDegrees: 180, exitNumber: 2);
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            ManeuverIcon(maneuver: maneuver, size: 76),
            ManeuverIcon(maneuver: maneuver, size: 28),
          ],
        ),
      ),
    );
    final painters = [
      for (final p in tester.widgetList<CustomPaint>(
        find.descendant(of: find.byType(ManeuverIcon), matching: find.byType(CustomPaint)),
      ))
        p.painter! as ManeuverPainter,
    ];
    expect(painters.first.glyph.label?.text, '2');
    expect(painters.first.labelStyle, isNotNull);
    expect(painters.last.labelStyle, isNull);
  });
}
