import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// What a [NightScene] tells, in the brand's landscape: a moon over teal
/// hills and a road, as in the mark.
enum SceneMood {
  /// Nothing here yet: the quiet landscape, a road leading on.
  empty,

  /// No connection: a cloud drifts over the moon.
  offline,

  /// Something failed: the road stops at a small barrier.
  error,

  /// Nothing saved yet: a van rests by the road.
  saved,
}

/// A small night landscape for the empty, offline and error states. Drawn
/// as vector paths in the theme's colours, so it follows light and dark and
/// stays sharp at any size.
class NightScene extends StatelessWidget {
  const new({this.mood = SceneMood.empty, this.width = 168, super.key});

  final SceneMood mood;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = LunaTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 0.62,
        child: CustomPaint(
          painter: _ScenePainter(
            mood: mood,
            sky: tokens.illustrationSky,
            moon: tokens.illustrationMoon,
            far: tokens.illustrationFarHills,
            near: tokens.illustrationNearHills,
            road: tokens.illustrationRoad,
            accent: scheme.onSurfaceVariant,
            alert: scheme.error,
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  new({
    required this.mood,
    required this.sky,
    required this.moon,
    required this.far,
    required this.near,
    required this.road,
    required this.accent,
    required this.alert,
  });

  final SceneMood mood;
  final Color sky;
  final Color moon;
  final Color far;
  final Color near;
  final Color road;
  final Color accent;
  final Color alert;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final frame = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h * 0.22));
    canvas
      ..save()
      ..clipRRect(frame)
      ..drawRRect(frame, Paint()..color = sky);

    // Stars: a four-point star and two dots, as in the mark.
    final star = Paint()..color = moon.withValues(alpha: 0.8);
    _star(canvas, Offset(w * 0.6, h * 0.2), h * 0.05, star);
    canvas
      ..drawCircle(Offset(w * 0.74, h * 0.34), h * 0.014, star)
      ..drawCircle(Offset(w * 0.86, h * 0.16), h * 0.012, star);

    // The crescent.
    final moonCenter = Offset(w * 0.27, h * 0.3);
    final r = h * 0.15;
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moonCenter, radius: r)),
      Path()..addOval(
        Rect.fromCircle(center: moonCenter + Offset(r * 0.55, -r * 0.35), radius: r * 0.82),
      ),
    );
    canvas.drawPath(crescent, Paint()..color = moon);

    if (mood == SceneMood.offline) {
      final cloud = Paint()..color = accent.withValues(alpha: 0.55);
      final c = moonCenter + Offset(r * 0.7, r * 0.55);
      canvas
        ..drawCircle(c, r * 0.48, cloud)
        ..drawCircle(c + Offset(r * 0.55, r * 0.12), r * 0.38, cloud)
        ..drawCircle(c + Offset(-r * 0.55, r * 0.18), r * 0.32, cloud)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c.dx - r * 0.85, c.dy + r * 0.05, r * 1.8, r * 0.45),
            Radius.circular(r * 0.22),
          ),
          cloud,
        );
    }

    canvas
      ..drawPath(_hill(w, h, base: 0.62, amplitude: 0.07, phase: 0.6), Paint()..color = far)
      ..drawPath(_hill(w, h, base: 0.76, amplitude: 0.06, phase: 2.4), Paint()..color = near);

    // The road, winding from the hills down to the foreground.
    final roadPath = Path()
      ..moveTo(w * 0.56, h * 0.7)
      ..cubicTo(w * 0.62, h * 0.78, w * 0.44, h * 0.84, w * 0.5, h * 1.02)
      ..lineTo(w * 0.66, h * 1.02)
      ..cubicTo(w * 0.58, h * 0.86, w * 0.7, h * 0.78, w * 0.585, h * 0.7)
      ..close();
    canvas.drawPath(roadPath, Paint()..color = road);

    switch (mood) {
      case SceneMood.error:
        final bar = Paint()
          ..color = alert
          ..strokeWidth = h * 0.03
          ..strokeCap = StrokeCap.round;
        final y = h * 0.86;
        canvas
          ..drawLine(Offset(w * 0.47, y), Offset(w * 0.69, y), bar)
          ..drawLine(
            Offset(w * 0.49, y),
            Offset(w * 0.49, y + h * 0.08),
            bar..strokeWidth = h * 0.02,
          )
          ..drawLine(Offset(w * 0.67, y), Offset(w * 0.67, y + h * 0.08), bar);
      case SceneMood.saved:
        _van(canvas, Offset(w * 0.74, h * 0.83), h * 0.12, Paint()..color = moon);
      case SceneMood.empty || SceneMood.offline:
        break;
    }
    canvas.restore();
  }

  static Path _hill(
    double w,
    double h, {
    required double base,
    required double amplitude,
    required double phase,
  }) {
    final path = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w + 1; x += w / 40) {
      path.lineTo(x, h * base - math.sin(x / w * math.pi * 1.6 + phase) * h * amplitude);
    }
    return path
      ..lineTo(w, h)
      ..close();
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// A van in profile, a few rounded shapes.
  static void _van(Canvas canvas, Offset at, double size, Paint paint) {
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(at.dx - size, at.dy - size * 0.75, size * 2, size * 0.75),
      topLeft: Radius.circular(size * 0.25),
      topRight: Radius.circular(size * 0.45),
      bottomLeft: Radius.circular(size * 0.1),
      bottomRight: Radius.circular(size * 0.1),
    );
    canvas
      ..drawRRect(body, paint)
      ..drawCircle(Offset(at.dx - size * 0.55, at.dy), size * 0.2, paint)
      ..drawCircle(Offset(at.dx + size * 0.55, at.dy), size * 0.2, paint);
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.mood != mood ||
      old.sky != sky ||
      old.moon != moon ||
      old.far != far ||
      old.near != near ||
      old.road != road ||
      old.accent != accent ||
      old.alert != alert;
}
