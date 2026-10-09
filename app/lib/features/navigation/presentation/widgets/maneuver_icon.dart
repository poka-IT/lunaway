import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_glyph.dart';

/// The share of the pictogram's colour its muted parts keep (the ring of a
/// roundabout, the branch of a fork not taken, a lane the route does not
/// use): 3.3:1 to 3.4:1 against the guidance banner's navy in both themes,
/// against 13:1 for the way to take.
const maneuverMutedAlpha = 0.4;

/// Below this size the exit's number in a roundabout would be smaller
/// than the smallest text of the app, logical pixels: the pictogram goes
/// without it.
const _labelFrom = 40.0;

/// The pictogram of a maneuver, drawn from its geometry
/// ([maneuverGlyph]): a turn, a fork, a ramp, a roundabout with its exit
/// at the road's angle, a ferry, the arrival. One stroke width for every
/// line at every size, its edges on the pixel grid.
class ManeuverIcon extends StatelessWidget {
  const new({required this.maneuver, this.size = 64, this.color, this.mutedColor, super.key});

  final Maneuver maneuver;
  final double size;

  /// The way to take; the theme's `onSurface` when null.
  final Color? color;

  /// The roads around it; [color] at [maneuverMutedAlpha] when null.
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final main = color ?? Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: ManeuverPainter(
          glyph: glyphOf(maneuver),
          color: main,
          mutedColor: mutedColor ?? main.withValues(alpha: main.a * maneuverMutedAlpha),
          devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          labelStyle: size >= _labelFrom ? Theme.of(context).textTheme.labelLarge : null,
        ),
      ),
    );
  }
}

/// The pictograms already worked out: the banner rebuilds every second
/// with the same few maneuvers.
final _glyphs = <Maneuver, ManeuverGlyph>{};

/// [maneuverGlyph], kept.
ManeuverGlyph glyphOf(Maneuver maneuver) {
  if (_glyphs.length > 256) _glyphs.clear();
  return _glyphs.putIfAbsent(maneuver, () => maneuverGlyph(maneuver));
}

/// Paints a [ManeuverGlyph] scaled to its box: muted parts first, then the
/// way to take over them, each group composed as one layer, so where two
/// lines of a group overlap no darker seam shows. The stroke is a whole
/// number of device pixels and the pictogram moves by less than one so its
/// vertical (and horizontal) line falls on the pixel grid.
class ManeuverPainter extends CustomPainter {
  const new({
    required this.glyph,
    required this.color,
    required this.mutedColor,
    this.devicePixelRatio = 1,
    this.labelStyle,
  });

  final ManeuverGlyph glyph;
  final Color color;
  final Color mutedColor;
  final double devicePixelRatio;

  /// The style of the roundabout's exit number; none drawn when null.
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / glyphGrid;
    if (unit <= 0) return;
    final ratio = devicePixelRatio;
    final strokePixels = math.max(1, (glyphStroke * unit * ratio).roundToDouble()).toDouble();
    final shift = _snap(canvas, unit, strokePixels);
    canvas
      ..save()
      ..translate(shift.dx, shift.dy)
      ..scale(unit);
    final stroke = strokePixels / ratio / unit;
    final box = Offset.zero & const Size.square(glyphGrid);
    for (final tone in GlyphTone.values) {
      final tint = tone == GlyphTone.main ? color : mutedColor;
      if (!_has(tone) || tint.a == 0) continue;
      final opaque = tint.withValues(alpha: 1);
      final layered = tint.a < 1;
      if (layered) {
        canvas.saveLayer(box.inflate(glyphGrid), Paint()..color = Color.fromRGBO(0, 0, 0, tint.a));
      }
      _paintTone(canvas, tone, opaque, stroke);
      if (layered) canvas.restore();
    }
    canvas.restore();
    final label = glyph.label;
    final style = labelStyle;
    if (label != null && style != null) {
      final text = TextPainter(
        text: TextSpan(
          text: label.text,
          style: style.copyWith(
            color: color,
            fontSize: label.size * unit,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      text.paint(canvas, shift + label.center * unit - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }
  }

  bool _has(GlyphTone tone) =>
      glyph.strokes.any((s) => s.tone == tone) ||
      glyph.heads.any((h) => h.tone == tone) ||
      glyph.shapes.any((s) => s.tone == tone);

  void _paintTone(Canvas canvas, GlyphTone tone, Color tint, double stroke) {
    final line = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = tint;
    // The corners of heads and shapes, rounded by a thin round-joined
    // stroke around an outline drawn that much inside.
    final rim = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * glyphHeadRound
      ..strokeJoin = StrokeJoin.round;
    for (final shape in glyph.shapes.where((s) => s.tone == tone)) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final outline in shape.outlines) {
        _addOutline(path, outline);
      }
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, rim..strokeWidth = glyphHeadRound);
    }
    for (final s in glyph.strokes.where((s) => s.tone == tone)) {
      canvas.drawPath(_pathOf(s.segments), line);
    }
    for (final head in glyph.heads.where((h) => h.tone == tone)) {
      final path = Path()..addPolygon(_inset(head.corners, glyphHeadRound), true);
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, rim..strokeWidth = 2 * glyphHeadRound);
    }
  }

  /// The shift, logical pixels, that puts the edges of the pictogram's
  /// vertical and horizontal lines on device pixels, given where the
  /// canvas puts its origin. A rotated or scaled canvas is left as it is.
  Offset _snap(Canvas canvas, double unit, double strokePixels) {
    final m = canvas.getTransform();
    if (m[0] != 1 || m[5] != 1 || m[1] != 0 || m[4] != 0) return Offset.zero;
    double along(double? at, double origin) {
      if (at == null) return 0;
      final device = (origin + at * unit) * devicePixelRatio;
      final wanted = strokePixels % 2 == 1
          ? (device - 0.5).roundToDouble() + 0.5
          : device.roundToDouble();
      return (wanted - device) / devicePixelRatio;
    }

    return Offset(along(glyph.snapX, m[12]), along(glyph.snapY, m[13]));
  }

  @override
  bool shouldRepaint(ManeuverPainter old) =>
      !identical(old.glyph, glyph) ||
      old.color != color ||
      old.mutedColor != mutedColor ||
      old.devicePixelRatio != devicePixelRatio ||
      old.labelStyle != labelStyle;
}

Path _pathOf(List<GlyphSegment> segments) {
  final path = Path()..moveTo(segments.first.start.dx, segments.first.start.dy);
  for (final s in segments) {
    switch (s) {
      case GlyphLine():
        path.lineTo(s.end.dx, s.end.dy);
      case GlyphArc():
        path.arcTo(
          Rect.fromCircle(center: s.center, radius: s.radius),
          s.startAngle,
          s.sweep,
          false,
        );
    }
  }
  return path;
}

void _addOutline(Path path, List<GlyphSegment> outline) {
  final only = outline.length == 1 ? outline.first : null;
  if (only is GlyphArc && only.sweep.abs() >= 2 * math.pi - 1e-9) {
    path.addOval(Rect.fromCircle(center: only.center, radius: only.radius));
    return;
  }
  path
    ..addPath(_pathOf(outline), Offset.zero)
    ..close();
}

/// The triangle [corners] moved [by] units inward on every side: the
/// triangle scaled about its incentre.
List<Offset> _inset(List<Offset> corners, double by) {
  final [a, b, c] = corners;
  final la = (b - c).distance;
  final lb = (c - a).distance;
  final lc = (a - b).distance;
  final perimeter = la + lb + lc;
  final incentre = (a * la + b * lb + c * lc) / perimeter;
  final area = ((b - a).dx * (c - a).dy - (b - a).dy * (c - a).dx).abs() / 2;
  final inradius = 2 * area / perimeter;
  final scale = (inradius - by) / inradius;
  return [for (final p in corners) incentre + (p - incentre) * scale];
}
