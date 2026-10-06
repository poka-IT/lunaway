import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The angle of a maneuver, degrees from straight ahead (left negative),
/// from the OSRM modifier.
double maneuverAngle(String? modifier) => switch (modifier) {
  'uturn' => -180,
  'sharp left' => -135,
  'left' => -90,
  'slight left' => -40,
  'slight right' => 40,
  'right' => 90,
  'sharp right' => 135,
  _ => 0,
};

/// The arrow of a maneuver, drawn rather than taken from an icon font: a
/// turn, a fork, a U-turn, a roundabout exit or the arrival read at a
/// glance, thick enough for a cab at arm's length.
class ManeuverIcon extends StatelessWidget {
  const new({
    required this.type,
    required this.modifier,
    this.roundaboutExitDegrees,
    this.size = 64,
    this.color,
    this.ghostColor,
    super.key,
  });

  /// The OSRM maneuver type (`turn`, `roundabout`, `arrive`...).
  final String? type;
  final String? modifier;
  final int? roundaboutExitDegrees;
  final double size;
  final Color? color;

  /// The roads not taken (the rest of a roundabout).
  final Color? ghostColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurface;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _ManeuverPainter(
          type: type,
          modifier: modifier,
          exitDegrees: roundaboutExitDegrees,
          color: c,
          ghost: ghostColor ?? c.withValues(alpha: 0.32),
        ),
      ),
    );
  }
}

class _ManeuverPainter extends CustomPainter {
  new({
    required this.type,
    required this.modifier,
    required this.exitDegrees,
    required this.color,
    required this.ghost,
  });

  final String? type;
  final String? modifier;
  final int? exitDegrees;
  final Color color;
  final Color ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.13;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    Offset p(double x, double y) => Offset(x * s, y * s);

    switch (type) {
      case 'arrive':
        // A flag on its pole: the end of the trip.
        canvas.drawLine(p(0.32, 0.9), p(0.32, 0.12), line);
        final flag = Path()
          ..moveTo(0.36 * s, 0.14 * s)
          ..lineTo(0.8 * s, 0.28 * s)
          ..lineTo(0.36 * s, 0.46 * s)
          ..close();
        canvas.drawPath(flag, fill);
        return;
      case 'roundabout' || 'rotary' || 'roundabout turn' || 'exit roundabout' || 'exit rotary':
        _roundabout(canvas, s, line, fill);
        return;
      case 'fork':
        // The branch not taken, faint, then the one taken.
        final other = -maneuverAngle(modifier).sign * 35;
        _arrow(canvas, s, other == 0 ? -35 : other, line..color = ghost, null);
        _arrow(
          canvas,
          s,
          maneuverAngle(modifier) == 0 ? 35 : maneuverAngle(modifier),
          line..color = color,
          fill,
        );
        return;
    }
    _arrow(canvas, s, maneuverAngle(modifier), line, fill);
  }

  /// A stem up from the bottom, then a bend of [angle] degrees and the head.
  void _arrow(Canvas canvas, double s, double angle, Paint line, Paint? head) {
    final rad = angle * math.pi / 180;
    if (angle.abs() >= 179) {
      // U-turn: up, round, down.
      final left = angle < 0;
      final x0 = left ? 0.66 : 0.34;
      final x1 = left ? 0.3 : 0.7;
      final path = Path()
        ..moveTo(x0 * s, 0.9 * s)
        ..lineTo(x0 * s, 0.4 * s)
        ..arcToPoint(Offset(x1 * s, 0.4 * s), radius: Radius.circular(0.18 * s), clockwise: !left)
        ..lineTo(x1 * s, 0.6 * s);
      canvas.drawPath(path, line);
      if (head != null) _head(canvas, Offset(x1 * s, 0.74 * s), math.pi, s, head);
      return;
    }
    // A sharp turn bends back down: its stem moves aside to leave room for
    // the arm, which leaves the stem's top over a rounded hook.
    final sharp = angle.abs() > 100;
    final stemX = sharp ? (angle < 0 ? 0.66 : 0.34) : 0.5;
    final base = Offset(stemX * s, 0.92 * s);
    final knee = Offset(stemX * s, angle == 0 ? 0.3 * s : (sharp ? 0.42 * s : 0.52 * s));
    final reach = (sharp ? 0.38 : 0.3) * s;
    final end = angle == 0
        ? Offset(0.5 * s, 0.24 * s)
        : knee + Offset(math.sin(rad) * reach, -math.cos(rad) * reach);
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..lineTo(knee.dx, knee.dy);
    if (angle != 0) {
      final control = sharp
          ? knee + Offset(math.sin(rad).sign * 0.1 * s, -0.22 * s)
          : knee + Offset(0, -0.12 * s);
      path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    } else {
      path.lineTo(end.dx, end.dy);
    }
    canvas.drawPath(path, line);
    if (head != null) {
      final tip = end + Offset(math.sin(rad) * 0.1 * s, -math.cos(rad) * 0.1 * s);
      _head(canvas, tip, rad, s, head);
    }
  }

  /// A triangle pointing along [direction] radians from up, its tip at
  /// [tip].
  void _head(Canvas canvas, Offset tip, double direction, double s, Paint paint) {
    final w = 0.17 * s;
    final l = 0.2 * s;
    final back = tip - Offset(math.sin(direction) * l, -math.cos(direction) * l);
    final side = Offset(math.cos(direction) * w, math.sin(direction) * w);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + side.dx, back.dy + side.dy)
        ..lineTo(back.dx - side.dx, back.dy - side.dy)
        ..close(),
      paint,
    );
  }

  /// The ring, the entry from below, and the exit leaving at its angle:
  /// degrees counter-clockwise from the entry, as the banner gives them
  /// (180 is straight through; right-hand traffic, so 90 is a right turn).
  void _roundabout(Canvas canvas, double s, Paint line, Paint head) {
    final center = Offset(0.5 * s, 0.5 * s);
    final r = 0.19 * s;
    canvas
      ..drawCircle(
        center,
        r,
        Paint()
          ..color = ghost
          ..style = PaintingStyle.stroke
          ..strokeWidth = line.strokeWidth * 0.7,
      )
      ..drawLine(Offset(0.5 * s, 0.95 * s), center + Offset(0, r), line);
    final degrees = exitDegrees?.toDouble() ?? (180 - maneuverAngle(modifier)).clamp(10, 350);
    final phi = degrees * math.pi / 180;
    // On screen, y grows downwards: angle 0 is the bottom of the ring, 90
    // its right side, 180 its top.
    final dir = Offset(math.sin(phi), math.cos(phi));
    final at = center + dir * r;
    final out = center + dir * (r * 1.95);
    canvas.drawLine(at, out, line);
    final heading = math.atan2(dir.dx, -dir.dy);
    _head(canvas, out + dir * (0.1 * s), heading, s, head);
  }

  @override
  bool shouldRepaint(_ManeuverPainter old) =>
      old.type != type ||
      old.modifier != modifier ||
      old.exitDegrees != exitDegrees ||
      old.color != color ||
      old.ghost != ghost;
}
