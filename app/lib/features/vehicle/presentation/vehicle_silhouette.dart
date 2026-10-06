import 'package:flutter/material.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';

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
      painter: _SilhouettePainter(
        type,
        towing,
        color ?? Theme.of(context).colorScheme.onSurface,
        Theme.of(context).colorScheme.surface,
      ),
    ),
  );
}

class _SilhouettePainter extends CustomPainter {
  new(this.type, this.towing, this.color, this.window);

  final VehicleType type;
  final Towing towing;
  final Color color;
  final Color window;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 100 x 50 grid, the towed part taking the left fifth.
    final towed = towing != Towing.none;
    final scaleX = size.width / 100;
    final scaleY = size.height / 50;
    canvas
      ..save()
      ..scale(scaleX, scaleY);
    final body = Paint()..color = color;
    final glass = Paint()..color = window;
    final x0 = towed ? 24.0 : 6.0;
    final w = 100 - x0 - 4;
    const groundY = 40.0;
    final (height, cabHeight) = switch (type) {
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
    // The body, then the windscreen and one window cut in the surface
    // colour.
    canvas
      ..drawPath(path, body)
      ..drawRRect(
        RRect.fromLTRBR(
          x0 + w - 11,
          groundY - cabHeight + 4,
          x0 + w - 3,
          groundY - cabHeight + 12,
          const Radius.circular(2),
        ),
        glass,
      )
      ..drawRRect(
        RRect.fromLTRBR(x0 + w * 0.2, top + 5, x0 + w * 0.42, top + 12, const Radius.circular(2)),
        glass,
      );
    if (towed) {
      final towTop = towing == Towing.car ? groundY - 14 : groundY - 11;
      canvas
        ..drawRRect(
          RRect.fromLTRBR(
            2,
            towTop,
            x0 - 5,
            groundY,
            Radius.circular(towing == Towing.car ? 5 : 2),
          ),
          body,
        )
        ..drawRect(Rect.fromLTWH(x0 - 6, groundY - 4, 6, 1.6), body);
    }
    // Wheels, ringed in the surface colour so they read apart from the body.
    for (final cx in [x0 + w * 0.18, x0 + w * 0.82, if (towed) 12.0]) {
      canvas
        ..drawCircle(Offset(cx, groundY), 6.2, glass)
        ..drawCircle(Offset(cx, groundY), 4.8, body);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.type != type || old.towing != towing || old.color != color || old.window != window;
}
