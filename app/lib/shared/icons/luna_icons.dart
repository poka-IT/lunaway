import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:path_parsing/path_parsing.dart';

/// A vector glyph on a 24 x 24 grid, in SVG path syntax: a filled part, an
/// optional part cut out of it, and an optional stroked part. Drawn by code,
/// so the same glyph serves the widgets and the map pins at any density.
@immutable
final class LunaIconData {
  const new({this.fill, this.cutout, this.stroke, this.strokeWidth = 1.9});

  final String? fill;
  final String? cutout;
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
      final cut = cutout;
      if (cut != null) path = Path.combine(ui.PathOperation.difference, path, _parse(cut));
      canvas.drawPath(path, Paint()..color = color);
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

/// The Lunaway glyphs: kind families and overnight statuses (filled, they are
/// read at pin size), and services (outlined, they are read in a list).
abstract final class LunaIcons {
  static const van = LunaIconData(
    fill:
        'M3 15.6V8.5C3 7.4 3.9 6.5 5 6.5h9.9c.6 0 1.2.3 1.6.8l2.3 3h1.2c1.1 0 2 .9 2 2v3.3 '
        'c0 .5-.4.9-.9.9H3.9c-.5 0-.9-.4-.9-.9z '
        'M9.3 17.4a2.2 2.2 0 1 1-4.4 0 2.2 2.2 0 0 1 4.4 0z '
        'M19.1 17.4a2.2 2.2 0 1 1-4.4 0 2.2 2.2 0 0 1 4.4 0z',
    cutout: 'M5.4 8.7h4.3v2.5H5.4z M11.6 8.7h3.3l1.9 2.5h-5.2z',
  );

  static const tent = LunaIconData(
    fill: 'M12 3.2 2.3 20.3h19.4L12 3.2z',
    cutout: 'M12 12.2 8.8 20.3h6.4L12 12.2z',
  );

  static const tree = LunaIconData(
    fill: 'M12 2.4 6 10.3h3.1L4.8 16.2h5.7v5.4h3v-5.4h5.7l-4.3-5.9H18L12 2.4z',
  );

  static const tap = LunaIconData(
    fill:
        'M4.5 8.6h6.2V7H8.8V4.8h6.4V7h-1.9v1.6h2.9a3.6 3.6 0 0 1 3.6 3.6v2.4h-3.5v-2.2 '
        'a.6.6 0 0 0-.6-.6H4.5z '
        'M17.9 21.2a2.1 2.1 0 0 1-2.1-2.1c0-1.3 2.1-3.8 2.1-3.8s2.1 2.5 2.1 3.8a2.1 2.1 0 0 1-2.1 2.1z',
  );

  static const moonStar = LunaIconData(
    fill:
        'M14.6 3.4a8.6 8.6 0 1 0 6 13.4A7.1 7.1 0 0 1 14.6 3.4z '
        'M19 2.8l.65 1.55 1.55.65-1.55.65L19 7.2l-.65-1.55-1.55-.65 1.55-.65z',
  );

  static const moon = LunaIconData(fill: 'M14.6 3.4a8.6 8.6 0 1 0 6 13.4A7.1 7.1 0 0 1 14.6 3.4z');

  static const sun = LunaIconData(
    fill: 'M16.2 12a4.2 4.2 0 1 1-8.4 0 4.2 4.2 0 0 1 8.4 0z',
    stroke:
        'M12 2.6v2 M12 19.4v2 M2.6 12h2 M19.4 12h2 M5.4 5.4l1.4 1.4 M17.2 17.2l1.4 1.4 '
        'M5.4 18.6l1.4-1.4 M17.2 6.8l1.4-1.4',
    strokeWidth: 2,
  );

  static const moonBarred = LunaIconData(
    fill: 'M14.6 3.4a8.6 8.6 0 1 0 6 13.4A7.1 7.1 0 0 1 14.6 3.4z',
    cutout: 'M2.6 4.6 4.6 2.6 21.4 19.4 19.4 21.4z',
    stroke: 'M3.8 3.8l16.4 16.4',
    strokeWidth: 1.8,
  );

  static const question = LunaIconData(
    stroke: 'M8.9 9.1a3.1 3.1 0 1 1 4.6 2.7c-1 .55-1.6 1.3-1.6 2.4v.6 M11.95 18.3h.01',
    strokeWidth: 2.4,
  );

  // Services, outlined.

  static const water = LunaIconData(
    stroke:
        'M12 3.2C9 7 6.2 10.4 6.2 14a5.8 5.8 0 0 0 11.6 0c0-3.6-2.8-7-5.8-10.8z '
        'M9.3 14.4a2.8 2.8 0 0 0 2.3 2.7',
  );

  static const greyWater = LunaIconData(
    stroke: 'M12 3v8 M8.6 7.8 12 11.2l3.4-3.4 M4 14.5h16v5H4z M8 14.5v5 M12 14.5v5 M16 14.5v5',
  );

  static const blackWater = LunaIconData(
    stroke: 'M6.5 3.5h11v7.5h-11z M10 7.2h4 M12 11v4.4 M9.6 13.4 12 15.8l2.4-2.4 M4.5 20h15',
  );

  static const bin = LunaIconData(
    stroke: 'M4.5 6.5h15 M9.5 6.5v-2h5v2 M6.5 6.5l1 14h9l1-14 M10 10.5v6.5 M14 10.5v6.5',
  );

  static const toilet = LunaIconData(
    stroke: 'M7 3.5h5v6.5H7z M5 10h14c0 3.6-2.6 6.4-6 6.9l.8 3.6H8.4l.9-3.8C6.9 15.8 5 13.2 5 10z',
  );

  static const shower = LunaIconData(
    stroke:
        'M5 21V9a5 5 0 0 1 10 0 M10.5 9h9 M12 12.5v1 M15 12.5v1 M18 12.5v1 M13.5 16v1 '
        'M16.5 16v1 M15 19.5v1',
  );

  static const bolt = LunaIconData(stroke: 'M13.6 2.6 5 13.6h6.6l-1.1 7.8 8.5-11h-6.6l1.2-7.8z');

  static const wifi = LunaIconData(
    stroke: 'M2.8 9.2a13.5 13.5 0 0 1 18.4 0 M5.9 12.6a9 9 0 0 1 12.2 0 M9 16a4.6 4.6 0 0 1 6 0 M12 19.6h.01',
  );

  static const laundry = LunaIconData(
    stroke:
        'M5 3.5h14v17H5z M5 7.5h14 M8 5.5h.01 M10.5 5.5h.01 M16 14a4 4 0 1 1-8 0 4 4 0 0 1 8 0z '
        'M10 14.6c.7-.6 1.3-.6 2 0s1.3.6 2 0',
  );

  static const fuelPump = LunaIconData(
    stroke:
        'M4.5 20.5v-15a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v15 M3 20.5h12 M7 8.5h4 '
        'M13.5 11h2a1.5 1.5 0 0 1 1.5 1.5v4a1.5 1.5 0 0 0 3 0V8.5L17.5 6',
  );

  static const gasBottle = LunaIconData(
    stroke: 'M9.5 3h5v3h-5z M7 10a4 4 0 0 1 4-4h2a4 4 0 0 1 4 4v10.5H7z M7 13.5h10',
  );

  static const wash = LunaIconData(
    stroke:
        'M3.5 18.5V14l1.9-3.5h9.4l2.6 3.5h3.1v4.5z M7 21v-2.5 M17.5 21v-2.5 '
        'M8 3.2c-.9 1.1-1.4 1.9-1.4 2.6a1.4 1.4 0 0 0 2.8 0c0-.7-.5-1.5-1.4-2.6z '
        'M15 3.2c-.9 1.1-1.4 1.9-1.4 2.6a1.4 1.4 0 0 0 2.8 0c0-.7-.5-1.5-1.4-2.6z',
  );

  static const bread = LunaIconData(
    stroke:
        'M4.3 16.9 16.9 4.3a2.6 2.6 0 0 1 3.7 3.7L8 20.6a2.6 2.6 0 0 1-3.7-3.7z '
        'M8.6 12.6l2 2 M11.6 9.6l2 2 M14.6 6.6l2 2',
  );

  static const pool = LunaIconData(
    stroke:
        'M8 15.5V6a2 2 0 0 1 2-2 M15 15.5V6a2 2 0 0 1 2-2 M8 8.5h7 M8 12h7 '
        'M3 19.5c1.5 0 1.5-1 3-1s1.5 1 3 1 1.5-1 3-1 1.5 1 3 1 1.5-1 3-1 1.5 1 3 1',
  );

  static const paw = LunaIconData(
    fill:
        'M12 12.2c-2.7 0-5.2 3.3-5.2 5.5 0 1.6 1.3 2.3 2.7 2.3 1 0 1.6-.5 2.5-.5s1.5.5 2.5.5 '
        'c1.4 0 2.7-.7 2.7-2.3 0-2.2-2.5-5.5-5.2-5.5z '
        'M8.3 10.3a1.7 2.1 0 1 1-3.4 0 1.7 2.1 0 0 1 3.4 0z '
        'M11.4 6.3a1.8 2.2 0 1 1-3.6 0 1.8 2.2 0 0 1 3.6 0z '
        'M16.2 6.3a1.8 2.2 0 1 1-3.6 0 1.8 2.2 0 0 1 3.6 0z '
        'M19.1 10.3a1.7 2.1 0 1 1-3.4 0 1.7 2.1 0 0 1 3.4 0z',
  );

  static const signal = LunaIconData(
    stroke: 'M5 19.5v-3 M9.5 19.5v-6 M14 19.5v-9 M18.5 19.5v-13',
    strokeWidth: 2.4,
  );

  static const snowflake = LunaIconData(
    stroke:
        'M12 2.8v18.4 M4 7.4l16 9.2 M4 16.6l16-9.2 M9.6 4.4 12 6.2l2.4-1.8 M9.6 19.6 12 17.8l2.4 1.8 '
        'M4.6 10.4l2.8-.9-.4-2.9 M19.4 13.6l-2.8.9.4 2.9 M4.6 13.6l2.8.9-.4 2.9 M19.4 10.4l-2.8-.9.4-2.9',
    strokeWidth: 1.7,
  );

  static LunaIconData family(KindFamily family) => switch (family) {
    .stopovers => van,
    .campsites => tent,
    .nature => tree,
    .services => tap,
  };

  static LunaIconData overnight(OvernightStatus status) => switch (status) {
    .allowed => moonStar,
    .tolerated => moon,
    .dayOnly => sun,
    .forbidden => moonBarred,
    .unknown => question,
  };

  static LunaIconData service(Service service) => switch (service) {
    .drinkingWater => water,
    .greyWater => greyWater,
    .blackWater => blackWater,
    .wasteBin => bin,
    .toilets => toilet,
    .showers => shower,
    .electricity => bolt,
    .wifi => wifi,
    .laundry => laundry,
    .lpg => fuelPump,
    .gasBottles => gasBottle,
    .vehicleWash => wash,
    .bakery => bread,
    .swimmingPool => pool,
    .petsAllowed => paw,
    .mobileData => signal,
    .winterCaravanning => snowflake,
  };
}
