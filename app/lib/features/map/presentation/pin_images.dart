import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/theme/luna_colors.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// The logical size of a pin image (the disc plus room for the badge).
const pinCanvas = 40.0;

/// The logical size of the point marker image. Its tip sits at the centre,
/// where the map anchors an icon, so the marker stands on the point.
const pointCanvas = 56.0;

/// Every pin image the map style needs, as PNG bytes keyed by image id: one
/// per family and overnight status, and the marker of a long-pressed point.
Future<Map<String, Uint8List>> renderPinImages() async {
  final images = <String, Uint8List>{markedPointImageId: await _png(pointCanvas, _point)};
  for (final family in KindFamily.values) {
    for (final overnight in OvernightStatus.values) {
      images[pinImageId(family, overnight)] = await _png(
        pinCanvas,
        (canvas) => _pin(canvas, family, overnight),
      );
    }
  }
  return images;
}

Future<Uint8List> _png(double logical, void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(MapLook.pinPixelRatio);
  draw(canvas);
  final side = (logical * MapLook.pinPixelRatio).round();
  final image = await recorder.endRecording().toImage(side, side);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// A drop-shaped marker standing on the centre of the image, amber with a
/// white ring and a white dot.
void _point(Canvas canvas) {
  const tip = Offset(pointCanvas / 2, pointCanvas / 2);
  const head = Offset(pointCanvas / 2, pointCanvas / 2 - 16);
  const radius = 10.0;
  Path drop(double grow) => Path()
    ..moveTo(tip.dx, tip.dy + grow)
    ..cubicTo(
      tip.dx - 5 - grow,
      tip.dy - 6,
      head.dx - radius - grow,
      head.dy + 6,
      head.dx - radius - grow,
      head.dy,
    )
    ..arcToPoint(Offset(head.dx + radius + grow, head.dy), radius: Radius.circular(radius + grow))
    ..cubicTo(
      head.dx + radius + grow,
      head.dy + 6,
      tip.dx + 5 + grow,
      tip.dy - 6,
      tip.dx,
      tip.dy + grow,
    )
    ..close();
  canvas
    ..drawPath(
      drop(2).shift(const Offset(0, 1.2)),
      Paint()
        ..color = LunaColors.pinShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    )
    ..drawPath(drop(2), Paint()..color = LunaColors.pinRim)
    ..drawPath(drop(0), Paint()..color = LunaColors.pinPoint)
    ..drawCircle(head, 4, Paint()..color = LunaColors.pinGlyph);
}

/// A disc in the family colour with its white glyph, ringed in white, on a
/// soft shadow; the overnight status sits as a badge at the top right.
void _pin(Canvas canvas, KindFamily family, OvernightStatus overnight) {
  const center = Offset(18, 22);
  const radius = 14.0;
  canvas
    ..drawCircle(
      center.translate(0, 1.2),
      radius + 2,
      Paint()
        ..color = LunaColors.pinShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    )
    ..drawCircle(center, radius + 2, Paint()..color = LunaColors.pinRim)
    ..drawCircle(center, radius, Paint()..color = LunaColors.pinFamily(family));
  const glyph = 17.0;
  LunaIcons.family(family)
      .paint(canvas, center - const Offset(glyph / 2, glyph / 2), glyph, LunaColors.pinGlyph);

  final badgeColor = LunaColors.pinOvernight(overnight);
  if (badgeColor == null) return;
  const badgeCenter = Offset(31, 8.5);
  const badgeRadius = 7.0;
  canvas
    ..drawCircle(badgeCenter, badgeRadius + 1.6, Paint()..color = LunaColors.pinRim)
    ..drawCircle(badgeCenter, badgeRadius, Paint()..color = badgeColor);
  const badgeGlyph = 9.5;
  LunaIcons.overnight(overnight).paint(
    canvas,
    badgeCenter - const Offset(badgeGlyph / 2, badgeGlyph / 2),
    badgeGlyph,
    LunaColors.pinGlyph,
  );
}
