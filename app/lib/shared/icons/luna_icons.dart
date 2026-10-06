import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:path_parsing/path_parsing.dart';

/// A vector glyph on a 24 x 24 grid, in SVG path syntax: a filled part,
/// parts cut out of it one after the other, and an optional stroked part.
/// Drawn by code, so the same glyph serves the widgets and the map pins at
/// any density.
@immutable
final class LunaIconData {
  const new({
    this.fill,
    this.cutouts = const [],
    this.softCutouts = const [],
    this.stroke,
    this.strokeWidth = 1.9,
  });

  final String? fill;

  /// Each removed from the fill in turn, so overlapping cut-outs cannot
  /// cancel each other out the way subpaths of one path can.
  final List<String> cutouts;

  /// Cut out at a third, so what is behind shows through faintly: the
  /// craters of the full moon, texture rather than holes.
  final List<String> softCutouts;
  final String? stroke;
  final double strokeWidth;

  static final Map<String, Path> _cache = {};

  static Path _parse(String data) => _cache.putIfAbsent(data, () {
    final proxy = _PathProxy();
    writeSvgPathDataToPath(data, proxy);
    return proxy.path;
  });

  /// Paints the glyph scaled to [size] at [offset] in [color].
  void paint(Canvas canvas, Offset offset, double size, Color color) {
    final scale = size / 24;
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    final fillData = fill;
    if (fillData != null) {
      var path = _parse(fillData);
      for (final cut in cutouts) {
        path = Path.combine(ui.PathOperation.difference, path, _parse(cut));
      }
      if (softCutouts.isEmpty) {
        canvas.drawPath(path, Paint()..color = color);
      } else {
        canvas
          ..saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint())
          ..drawPath(path, Paint()..color = color);
        final soft = Paint()
          ..blendMode = BlendMode.dstOut
          ..color = const Color(0x55000000);
        for (final cut in softCutouts) {
          canvas.drawPath(_parse(cut), soft);
        }
        canvas.restore();
      }
    }
    final strokeData = stroke;
    if (strokeData != null) {
      canvas.drawPath(
        _parse(strokeData),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }
}

final class _PathProxy implements PathProxy {
  final Path path = Path();

  @override
  void close() => path.close();

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

/// Draws a [LunaIconData] with the ambient [IconTheme], like [Icon] does.
class LunaIcon extends StatelessWidget {
  const new(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final LunaIconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final paint = CustomPaint(
      size: Size.square(side),
      painter: _LunaIconPainter(icon, color ?? theme.color ?? const Color(0xFF000000)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, child: paint);
  }
}

class _LunaIconPainter extends CustomPainter {
  new(this.icon, this.color);

  final LunaIconData icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => icon.paint(canvas, Offset.zero, size.shortestSide, color);

  @override
  bool shouldRepaint(_LunaIconPainter old) => old.icon != icon || old.color != color;
}

/// The glyphs Phosphor does not have: the night statuses as moon phases.
abstract final class LunaIcons {
  // The night statuses as moon phases, one shape per status, so the status
  // reads without its colour: in the sheet, the list, the filters and the
  // map pins alike.

  /// A night is allowed: the full moon, its craters a faint texture (cut
  /// clean, they turned it into a button at badge size).
  static const fullMoon = LunaIconData(
    fill: 'M3.80 12.00a8.20 8.20 0 1 0 16.40 0a8.20 8.20 0 1 0 -16.40 0z',
    softCutouts: [
      'M7.40 10.40a2.20 2.20 0 1 0 4.40 0a2.20 2.20 0 1 0 -4.40 0z',
      'M12.60 15.20a1.70 1.70 0 1 0 3.40 0a1.70 1.70 0 1 0 -3.40 0z',
      'M13.70 8.30a1.10 1.10 0 1 0 2.20 0a1.10 1.10 0 1 0 -2.20 0z',
    ],
  );

  /// A night is tolerated: the crescent of the logo.
  static const crescent = LunaIconData(
    fill: 'M4.00 12.00a8.00 8.00 0 1 0 16.00 0a8.00 8.00 0 1 0 -16.00 0z',
    cutouts: ['M9.00 9.20a6.60 6.60 0 1 0 13.20 0a6.60 6.60 0 1 0 -13.20 0z'],
  );

  /// Parking by day only: the sun.
  static const sun = LunaIconData(
    fill: 'M8.10 12.00a3.90 3.90 0 1 0 7.80 0a3.90 3.90 0 1 0 -7.80 0z',
    stroke: 'M18.20 12.00L20.60 12.00M16.38 16.38L18.08 18.08M12.00 18.20L12.00 20.60M7.62 16.38L5.92 18.08M5.80 12.00L3.40 12.00M7.62 7.62L5.92 5.92M12.00 5.80L12.00 3.40M16.38 7.62L18.08 5.92',
    strokeWidth: 1.8,
  );

  /// A night is forbidden: the crescent, struck through.
  static const crossedMoon = LunaIconData(
    fill: 'M4.00 12.00a8.00 8.00 0 1 0 16.00 0a8.00 8.00 0 1 0 -16.00 0z',
    cutouts: [
      'M9.00 9.20a6.60 6.60 0 1 0 13.20 0a6.60 6.60 0 1 0 -13.20 0z',
      'M2.16 4.84L4.84 2.16L21.84 19.16L19.16 21.84z',
    ],
    stroke: 'M4.2 4.2L19.8 19.8',
    strokeWidth: 1.8,
  );

  /// Nobody has said yet: a dotted circle, a blank to fill rather than a
  /// warning.
  static const unknownNight = LunaIconData(
    stroke: 'M12.52 4.52A7.5 7.5 0 0 1 14.81 5.05M16.82 6.25A7.5 7.5 0 0 1 18.36 8.03M19.28 10.19A7.5 7.5 0 0 1 19.48 12.52M18.95 14.81A7.5 7.5 0 0 1 17.75 16.82M15.97 18.36A7.5 7.5 0 0 1 13.81 19.28M11.48 19.48A7.5 7.5 0 0 1 9.19 18.95M7.18 17.75A7.5 7.5 0 0 1 5.64 15.97M4.72 13.81A7.5 7.5 0 0 1 4.52 11.48M5.05 9.19A7.5 7.5 0 0 1 6.25 7.18M8.03 5.64A7.5 7.5 0 0 1 10.19 4.72',
    strokeWidth: 1.8,
  );

  static LunaIconData night(OvernightStatus status) => switch (status) {
    .allowed => fullMoon,
    .tolerated => crescent,
    .dayOnly => sun,
    .forbidden => crossedMoon,
    .unknown => unknownNight,
  };
}
