import 'package:flutter/material.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';

/// A vehicle type in profile, a few rounded shapes: enough to tell a van
/// from an over-cab motorhome at a glance, in the brand's flat style.
class VehicleSilhouette extends StatelessWidget {
  const new(this.type, {this.towing = Towing.none, this.color, this.width = 72, super.key});

  final VehicleType type;
  final Towing towing;
  final Color? color;
  final double width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, width * 0.5),
      painter: _SilhouettePainter(type, towing, color ?? Theme.of(context).colorScheme.onSurface),
    ),
  );
}

class _SilhouettePainter extends CustomPainter {
  new(this.type, this.towing, this.color);

  final VehicleType type;
  final Towing towing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 100 x 50 grid, the towed part taking the left fifth.
    final towed = towing != Towing.none;
    final scaleX = size.width / 100;
    final scaleY = size.height / 50;
    // The windows and the ring round each wheel are cut out of the body,
    // in a layer of its own, so whatever lies behind shows through them:
    // painted in the surface colour, they stood out as patches on a card
    // of another tone.
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..scale(scaleX, scaleY);
    final body = Paint()..color = color;
    final glass = Paint()..blendMode = BlendMode.clear;
    final x0 = towed ? 24.0 : 6.0;
    final w = 100 - x0 - 4;
    const groundY = 40.0;
    if (type == VehicleType.car) {
      // Phosphor's car in profile, centred where a van would stand, its
      // wheels on the same ground; what it tows hitched to its rear.
      final left = x0 + (w - _carWidth) / 2;
      _paintCar(canvas, left, groundY);
      if (towed) _paintTowed(canvas, body, glass, groundY, from: x0, to: left + 2);
      canvas.restore();
      return;
    }
    final (height, cabHeight) = switch (type) {
      VehicleType.car => (22.0, 20.0),
      VehicleType.van => (22.0, 20.0),
      VehicleType.campervan => (28.0, 22.0),
      VehicleType.lowProfile => (31.0, 21.0),
      VehicleType.overcab => (34.0, 21.0),
      VehicleType.integrated => (32.0, 32.0),
    };
    final top = groundY - height;
    final cabX = x0 + w * 0.72;
    final path = Path();
    switch (type) {
      case VehicleType.car:
        break;
      case VehicleType.van:
      case VehicleType.campervan:
        path.addRRect(
          RRect.fromLTRBAndCorners(
            x0,
            top,
            x0 + w,
            groundY,
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(10),
            bottomLeft: const Radius.circular(2),
            bottomRight: const Radius.circular(4),
          ),
        );
      case VehicleType.lowProfile:
      case VehicleType.overcab:
        // The living box, then the lower cab at the front.
        path
          ..addRRect(
            RRect.fromLTRBAndCorners(
              x0,
              top,
              cabX + (type == VehicleType.overcab ? 8 : 0),
              groundY,
              topLeft: const Radius.circular(4),
              topRight: Radius.circular(type == VehicleType.overcab ? 6 : 3),
              bottomLeft: const Radius.circular(2),
            ),
          )
          ..addRRect(
            RRect.fromLTRBAndCorners(
              cabX - 2,
              groundY - cabHeight,
              x0 + w,
              groundY,
              topRight: const Radius.circular(9),
              bottomRight: const Radius.circular(4),
            ),
          );
      case VehicleType.integrated:
        path.addRRect(
          RRect.fromLTRBAndCorners(
            x0,
            top,
            x0 + w,
            groundY,
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(14),
            bottomLeft: const Radius.circular(2),
            bottomRight: const Radius.circular(6),
          ),
        );
    }
    // The body, then the windscreen and one window cut out. Under the
    // integrated's wide front corner (radius 14) the windscreen stands a
    // unit further in, or its corner would cut through the outline.
    final inset = type == VehicleType.integrated ? 1.0 : 0.0;
    canvas
      ..drawPath(path, body)
      ..drawRRect(
        RRect.fromLTRBR(
          x0 + w - 11 - inset,
          groundY - cabHeight + 4 + inset,
          x0 + w - 3 - inset,
          groundY - cabHeight + 12 + inset,
          const Radius.circular(2),
        ),
        glass,
      )
      ..drawRRect(
        RRect.fromLTRBR(x0 + w * 0.2, top + 5, x0 + w * 0.42, top + 12, const Radius.circular(2)),
        glass,
      );
    if (towed) _paintTowed(canvas, body, glass, groundY, from: x0, to: x0 + 1);
    for (final cx in [x0 + w * 0.18, x0 + w * 0.82]) {
      _paintWheel(canvas, body, glass, Offset(cx, groundY));
    }
    canvas.restore();
  }

  /// What is towed, in the left fifth, and its bar from its front to [to],
  /// where the vehicle's rear stands ([from] is the left of the vehicle's
  /// room).
  void _paintTowed(
    Canvas canvas,
    Paint body,
    Paint glass,
    double groundY, {
    required double from,
    required double to,
  }) {
    final towTop = towing == Towing.car ? groundY - 14 : groundY - 11;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(
          2,
          towTop,
          from - 5,
          groundY,
          Radius.circular(towing == Towing.car ? 5 : 2),
        ),
        body,
      )
      // The bar runs a unit into each body, so no seam shows where they meet.
      ..drawRect(Rect.fromLTRB(from - 6, groundY - 4, to, groundY - 2.4), body);
    _paintWheel(canvas, body, glass, Offset(12, groundY));
  }

  /// A wheel, ringed with a cut so it reads apart from the body.
  void _paintWheel(Canvas canvas, Paint body, Paint glass, Offset centre) => canvas
    ..drawCircle(centre, 6.2, glass)
    ..drawCircle(centre, 4.8, body);

  /// The width the car takes on the grid: Phosphor's car in profile spans
  /// x 16 to 240 and y 80 to 208 (wheels included) of its 256 square.
  static const double _carWidth = _carHeight * 224 / 128;

  /// The car's height, wheels included: a little under a van's.
  static const double _carHeight = 28;

  void _paintCar(Canvas canvas, double left, double groundY) {
    const glyph = PhosphorFill.carProfile;
    const em = _carHeight * 256 / 128;
    // The wheels' bottom on the ground the vans' wheels reach (their
    // radius under it).
    TextPainter(
        text: TextSpan(
          text: String.fromCharCode(glyph.codePoint),
          style: TextStyle(
            fontFamily: glyph.fontFamily,
            package: glyph.fontPackage,
            fontSize: em,
            height: 1,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, Offset(left - em * 16 / 256, groundY + 6 - em * 208 / 256))
      ..dispose();
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.type != type || old.towing != towing || old.color != color;
}
