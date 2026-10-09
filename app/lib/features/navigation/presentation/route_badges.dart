import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// How a badge is drawn.
enum BadgeShape {
  /// A coloured disc under a cream rim, a glyph in it.
  disc,

  /// A road sign: white, a coral ring, the glyph or the figure in navy.
  sign,

  /// The start: a small teal dot in a cream ring.
  start,
}

/// One image of the route marks: a round badge that says what the mark is
/// by its glyph and its colour. The same painter draws it into the map's
/// sprite and into the legend, so both always look alike.
@immutable
final class RouteBadge {
  const new(
    this.id, {
    required this.shape,
    required this.fill,
    this.glyph,
    this.ink = Palette.creme,
    this.ring = Palette.creme,
    this.ringWidth = 2.5,
    this.diameter = 26,
  });

  /// The sign of a limit, its glyph saying what it limits; the figure is
  /// written beside it.
  factory sign(SignGlyph glyph, {bool blocking = false}) => RouteBadge(
    'lw-rb-sign-${glyph.name}${blocking ? '-x' : ''}',
    shape: BadgeShape.sign,
    fill: Palette.white,
    glyph: glyph.icon,
    ink: Palette.minuit,
    ring: blocking ? Palette.corail700 : Palette.corail,
    ringWidth: blocking ? 5 : 3.5,
    diameter: 24,
  );

  factory place(PlaceKind kind) => RouteBadge(
    'lw-rb-place-${kind.name}',
    shape: BadgeShape.disc,
    fill: LunaTokens.familyFill(kind.family),
    glyph: AppIcons.kind(kind),
  );

  /// Where marks gather at a low zoom; its count is the map's text. The
  /// tone is that of the most pressing mark inside ([MarkTone]).
  factory cluster(MarkTone tone) => RouteBadge(
    'lw-rb-cluster-${tone.rank}',
    shape: BadgeShape.disc,
    fill: switch (tone) {
      MarkTone.alert => Palette.corail700,
      MarkTone.caution => Palette.lanterne700,
      MarkTone.info => Palette.minuit600,
    },
    diameter: 28,
  );

  /// The image id in the map style.
  final String id;
  final BadgeShape shape;
  final Color fill;
  final IconData? glyph;

  /// The glyph's colour, and the colour of a text the map writes on it.
  final Color ink;
  final Color ring;
  final double ringWidth;

  /// The disc, rim excluded, in logical pixels.
  final double diameter;

  /// The whole image: disc, rim and a hairline that keeps it apart from a
  /// cream basemap.
  double get extent => diameter + 2 * ringWidth + 2;

  static const _prefix = 'lw-rb-';

  static const origin = RouteBadge(
    '${_prefix}origin',
    shape: BadgeShape.start,
    fill: Palette.sarcelle,
    ringWidth: 3.5,
    diameter: 12,
  );
  static const destination = RouteBadge(
    '${_prefix}destination',
    shape: BadgeShape.disc,
    fill: Palette.minuit,
    glyph: PhosphorFill.flagCheckered,
    diameter: 28,
  );

  /// Its number is the map's text, drawn over it.
  static const stop = RouteBadge(
    '${_prefix}stop',
    shape: BadgeShape.disc,
    fill: Palette.sarcelleProfonde,
  );
  static const closure = RouteBadge(
    '${_prefix}closure',
    shape: BadgeShape.disc,
    fill: Palette.corail,
    glyph: PhosphorFill.barricade,
    ink: Palette.white,
  );

  /// A closure that stops every route: darker, a heavier rim.
  static const closureBlocking = RouteBadge(
    '${_prefix}closure-x',
    shape: BadgeShape.disc,
    fill: Palette.corail700,
    glyph: PhosphorFill.barricade,
    ink: Palette.white,
    ring: Palette.corail900,
    ringWidth: 3,
  );
  static const works = RouteBadge(
    '${_prefix}works',
    shape: BadgeShape.disc,
    fill: Palette.lanterne,
    glyph: PhosphorFill.wrench,
    ink: Palette.minuit,
  );
  static const lanes = RouteBadge(
    '${_prefix}lanes',
    shape: BadgeShape.disc,
    fill: Palette.lanterne200,
    glyph: PhosphorFill.arrowsMerge,
    ink: Palette.lanterne900,
  );
  static const fuel = RouteBadge(
    '${_prefix}fuel',
    shape: BadgeShape.disc,
    fill: Palette.lanterne700,
    glyph: PhosphorFill.gasPump,
  );

  /// A speed camera: a camera on its mast, cream on the night navy, in a
  /// lantern rim that sets it apart from the destination's flag. Its
  /// limit is written beside it. Never drawn for a danger zone.
  static const camera = RouteBadge(
    '${_prefix}camera',
    shape: BadgeShape.disc,
    fill: Palette.minuit,
    glyph: PhosphorFill.securityCamera,
    ring: Palette.lanterne,
    ringWidth: 3,
  );

  /// Every badge, drawn once per screen density.
  static final List<RouteBadge> all = [
    origin,
    destination,
    stop,
    closure,
    closureBlocking,
    works,
    lanes,
    fuel,
    camera,
    for (final g in SignGlyph.values) ...[RouteBadge.sign(g), RouteBadge.sign(g, blocking: true)],
    for (final k in PlaceKind.values) RouteBadge.place(k),
    for (final t in MarkTone.values) RouteBadge.cluster(t),
  ];

  @override
  bool operator ==(Object other) => other is RouteBadge && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What a limit's sign shows: what it limits.
enum SignGlyph {
  height(PhosphorRegular.arrowsVertical),
  weight(PhosphorRegular.scales),
  width(PhosphorRegular.arrowsHorizontal),
  length(PhosphorRegular.ruler),
  motorhome(PhosphorRegular.van),
  trailer(PhosphorRegular.truckTrailer);

  new(this.icon);

  final IconData icon;
}

/// How pressing a mark is, for the colour of a group that holds it.
enum MarkTone {
  info(1),
  caution(2),
  alert(3);

  new(this.rank);

  final int rank;
}

/// Paints [badge] centred on [center], [scale] times its size; [text] (a
/// stop's number, a limit's figure, a count) over it in the badge's ink.
void paintRouteBadge(
  Canvas canvas,
  RouteBadge badge,
  Offset center, {
  double scale = 1,
  String? text,
  String? fontFamily,
}) {
  final r = badge.diameter / 2 * scale;
  final ring = badge.ringWidth * scale;
  final outer = r + ring;
  // The hairline keeps a cream rim visible on the cream basemap.
  canvas.drawCircle(
    center,
    outer + 0.75 * scale,
    Paint()..color = Palette.minuit.withValues(alpha: 0.45),
  );
  switch (badge.shape) {
    case BadgeShape.disc || BadgeShape.start:
      canvas
        ..drawCircle(center, outer, Paint()..color = badge.ring)
        ..drawCircle(center, r, Paint()..color = badge.fill);
    case BadgeShape.sign:
      canvas
        ..drawCircle(center, outer, Paint()..color = badge.ring)
        ..drawCircle(center, outer - ring, Paint()..color = badge.fill);
  }
  final glyph = badge.glyph;
  if (glyph != null) {
    final size = (badge.shape == BadgeShape.sign ? r * 1.25 : r * 1.2);
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          fontSize: size,
          height: 1,
          color: badge.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }
  if (text != null && text.isNotEmpty) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: (text.length > 2 ? 9.5 : 12) * scale,
          fontWeight: FontWeight.w700,
          height: 1,
          color: badge.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, figuresCentred(painter, center));
    painter.dispose();
  }
}

/// The height of figures and capitals over the font's size: Atkinson's
/// digits run 680 units of 1000 up from the baseline.
const double _figureHeight = 0.68;

/// Where to paint the one line of [painter] so its figures (a limit, a
/// count, a rating) stand centred on [center]. Centred on its line box,
/// the figures sat high: the box holds the descenders below the baseline
/// and room above the capitals, a pixel off at 12 px.
Offset figuresCentred(TextPainter painter, Offset center) {
  final lines = painter.computeLineMetrics();
  if (lines.isEmpty) return center - Offset(painter.width / 2, painter.height / 2);
  final line = lines.first;
  final size = painter.text?.style?.fontSize ?? line.ascent;
  return Offset(
    center.dx - painter.width / 2,
    center.dy - (line.baseline - size * _figureHeight / 2),
  );
}

/// The badge as a PNG at [ratio] physical pixels per logical one.
Future<Uint8List> routeBadgePng(RouteBadge badge, double ratio) async {
  final side = (badge.extent * ratio).ceil();
  final recorder = ui.PictureRecorder();
  paintRouteBadge(Canvas(recorder), badge, Offset(side / 2, side / 2), scale: ratio);
  final image = await recorder.endRecording().toImage(side, side);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

final Map<double, Future<Map<String, Uint8List>>> _drawn = {};

/// Every badge as a PNG at [ratio], drawn once per density and run: a new
/// style or a second map reuses them.
Future<Map<String, Uint8List>> routeBadgePngs(double ratio) => _drawn[ratio] ??= () async {
  try {
    final out = <String, Uint8List>{};
    for (final b in RouteBadge.all) {
      out[b.id] = await routeBadgePng(b, ratio);
    }
    return out;
  } on Object {
    // A drawing that failed is tried again by the next map.
    _drawn.remove(ratio)?.ignore();
    rethrow;
  }
}();

/// A badge as a widget: the legend and the tooltips draw the mark as the map
/// does.
class RouteBadgeView extends StatelessWidget {
  const new(this.badge, {this.text, this.scale = 1, super.key});

  final RouteBadge badge;
  final String? text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final side = badge.extent * scale;
    return CustomPaint(
      size: Size.square(side),
      painter: _BadgePainter(badge, text, scale, DefaultTextStyle.of(context).style.fontFamily),
    );
  }
}

class _BadgePainter extends CustomPainter {
  new(this.badge, this.text, this.scale, this.fontFamily);

  final RouteBadge badge;
  final String? text;
  final double scale;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) => paintRouteBadge(
    canvas,
    badge,
    size.center(Offset.zero),
    scale: scale,
    text: text,
    fontFamily: fontFamily,
  );

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.badge != badge || old.text != text || old.scale != scale;
}
