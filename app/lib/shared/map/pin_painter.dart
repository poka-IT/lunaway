import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The geometry of a map pin, in logical pixels: the teardrop of the logo (a
/// circle and two arcs meeting at the tip, brand/README.md), the family
/// colour inside a cream rim, the kind's glyph, and the night status as a
/// moon badge on the shoulder. The selected pin is larger, ringed and
/// haloed in amber. The tip sits at the bottom centre of the image, where
/// the map anchors it.
final class PinGeometry {
  const new({required this.selected});

  final bool selected;

  double get scale => selected ? 1.3 : 1;

  /// Radius of the coloured head.
  double get head => 12.5 * scale;
  double get rim => selected ? 2.6 : 2;
  double get outer => head + rim;

  /// From the head's centre to the tip: the logo's proportion (the tip at
  /// 552 for a circle of radius 227 centred at 227).
  double get tipDrop => outer * 1.43;
  double get badge => 7.2 * scale;
  double get badgeRing => 1.6;
  double get halo => selected ? 7 : 0;
  double get margin => 2.5 + halo;

  /// The image size: room for the badge on the right and above, the halo,
  /// and a soft shadow.
  Size get canvas {
    final badgeReach = outer * 0.62 + badge + badgeRing;
    final half = math.max(outer, badgeReach) + margin;
    return Size((half * 2).ceilToDouble(), (half + tipDrop).ceilToDouble());
  }

  Offset get center {
    final size = canvas;
    return Offset(size.width / 2, size.height - tipDrop);
  }
}

/// Paints the pin of [kind] and [overnight] on [canvas], at the logical
/// scale of the canvas.
void paintPin(
  Canvas canvas, {
  required PlaceKind kind,
  required OvernightStatus overnight,
  required bool selected,
}) {
  final g = PinGeometry(selected: selected);
  final c = g.center;
  final tip = Offset(c.dx, c.dy + g.tipDrop);
  // The coloured head ends a little above the tip, so the rim closes the
  // point instead of thinning to nothing.
  Path drop(double radius) =>
      teardrop(c, radius, radius < g.outer ? tip - Offset(0, g.rim * 1.6) : tip);

  final shadow = Paint()
    ..color = const Color(0x52061F43)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
  if (selected) {
    canvas.drawCircle(
      c,
      g.outer + g.halo,
      Paint()
        ..color = LunaTokens.selection.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }
  canvas
    ..drawPath(drop(g.outer).shift(const Offset(0, 1)), shadow)
    ..drawPath(drop(g.outer), Paint()..color = selected ? LunaTokens.selection : LunaTokens.pinRim)
    ..drawPath(drop(g.head), Paint()..color = LunaTokens.familyFill(kind.family));

  _paintIcon(canvas, AppIcons.kind(kind), c, g.head * 1.18, LunaTokens.pinGlyph);

  // On the shoulder, up and to the right, overlapping the rim. An unknown
  // status keeps its badge too: the dotted circle, so every pin reads the
  // same way.
  final at = c + Offset(g.outer * 0.62, -g.outer * 0.62);
  final tone = pinNightTone(overnight);
  canvas
    ..drawCircle(at, g.badge + g.badgeRing, Paint()..color = LunaTokens.pinRim)
    ..drawCircle(at, g.badge, Paint()..color = tone.disc);
  final glyph = g.badge * 1.5;
  LunaIcons.night(overnight).paint(canvas, at - Offset(glyph / 2, glyph / 2), glyph, tone.glyph);
}

/// The badges on the map, the same on both basemaps: a navy night sky for
/// a night allowed or tolerated, cream for a day, coral for forbidden.
NightTone pinNightTone(OvernightStatus status) => switch (status) {
  .allowed ||
  .tolerated => const NightTone(disc: Palette.minuit, glyph: Palette.creme, label: Palette.minuit),
  .dayOnly => const NightTone(
    disc: Palette.creme,
    glyph: Palette.lanterne800,
    label: Palette.minuit,
  ),
  .forbidden => const NightTone(
    disc: Palette.corail700,
    glyph: Palette.creme,
    label: Palette.minuit,
  ),
  .unknown => const NightTone(disc: Palette.creme, glyph: Palette.minuit500, label: Palette.minuit),
};

/// The logo's pin outline: a circle of [radius] around [center] whose sides
/// run down to [tip], tangent to the circle and gently convex like the
/// logo's arcs.
Path teardrop(Offset center, double radius, Offset tip) {
  final d = (tip - center).distance;
  // The tangent points: seen from the centre, at an angle from the tip's
  // direction whose cosine is radius over distance.
  final theta = math.acos((radius / d).clamp(-1, 1));
  final right = center + Offset(radius * math.sin(theta), radius * math.cos(theta));
  final left = center + Offset(-radius * math.sin(theta), radius * math.cos(theta));
  // A control point pushed outward from the middle of each side.
  Offset bulge(Offset from) {
    final mid = Offset.lerp(from, tip, 0.5)!;
    final side = from - tip;
    final normal = Offset(side.dy, -side.dx) / side.distance;
    final outward = (mid - center).dx.sign == normal.dx.sign ? normal : -normal;
    return mid + outward * side.distance * 0.05;
  }

  final r = bulge(right);
  final l = bulge(left);
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..quadraticBezierTo(r.dx, r.dy, right.dx, right.dy)
    ..arcToPoint(left, radius: Radius.circular(radius), largeArc: true, clockwise: false)
    ..quadraticBezierTo(l.dx, l.dy, tip.dx, tip.dy)
    ..close();
}

/// The geometry of the long-press marker: an amber drop with a navy dot.
const pointMarkerSize = Size(34, 44);

/// How far down [pointMarkerSize] the marker's tip lies, the point it marks.
const double pointMarkerTip = 17 + 14 * 1.43;

void paintPointMarker(Canvas canvas) {
  const c = Offset(17, 17);
  const outer = 14.0;
  const tip = Offset(17, pointMarkerTip);
  Path drop(double r) => teardrop(c, r, r < outer ? tip - const Offset(0, 3.5) : tip);

  canvas
    ..drawPath(
      drop(outer).shift(const Offset(0, 1)),
      Paint()
        ..color = const Color(0x52061F43)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    )
    ..drawPath(drop(outer), Paint()..color = LunaTokens.pinRim)
    ..drawPath(drop(outer - 2.2), Paint()..color = LunaTokens.selection)
    ..drawCircle(c, 4.6, Paint()..color = Palette.minuit);
}

void _paintIcon(Canvas canvas, IconData icon, Offset center, double size, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        height: 1,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  painter.dispose();
}
