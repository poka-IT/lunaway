import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/navigation/data/place_thumbs.dart';
import 'package:lunaway/features/navigation/domain/guidance_marks.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/map/pin_painter.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/theme/typography.dart';

final _log = Logger('rich_marks');

/// The ring of a rich mark: the night's tone, as the moon badge of the
/// map's pins draws it (navy for a night allowed or tolerated, cream for a
/// day only or nobody knows, coral for forbidden), so the one colour a
/// driver reads first says whether the place takes a night.
Color richRing(OvernightStatus night) => pinNightTone(night).disc;

/// What a rich mark shows inside its head.
@immutable
sealed class RichFace {
  const new();
}

/// The place's photo, cut round.
final class PhotoFace extends RichFace {
  const new(this.image);

  final ui.Image image;
}

/// The kind's pictogram on its family's colour, and a short label.
final class IllustratedFace extends RichFace {
  const new({this.label, this.star = false});

  /// The label's words; null for none.
  final String? label;

  /// A star before the words: they are a rating.
  final bool star;
}

/// The label's text style: Atkinson Hyperlegible, bold, the body face drawn
/// for low-vision readers, 13 px whatever the mark's size: its capitals are
/// 9 px tall, 1.5 mm on a phone, 8 minutes of arc at 65 cm.
const TextStyle richLabelStyle = TextStyle(
  fontFamily: LunaType.body,
  fontSize: 13,
  height: 1,
  fontWeight: FontWeight.w700,
  color: Palette.creme,
);

const double _labelPad = 6;
const double _starGap = 2;

/// The label's laid out width, logical pixels, its padding and the star
/// included.
double richLabelWidth(String text, {bool star = false}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: richLabelStyle),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width + 2 * _labelPad + (star ? _starSize + _starGap : 0);
  painter.dispose();
  return width.ceilToDouble();
}

double get _starSize => richLabelStyle.fontSize! * 0.95;

/// Around the mark in its image: the rim, the shadow, the badge's
/// overflow.
const double _margin = 3;

/// The size of the image of a rich mark, logical pixels; the tip stands at
/// its bottom centre, which the map anchors at the place.
Size richMarkCanvas(RichGeometry g) {
  final half = g.capsule ? g.width / 2 : g.radius + g.badge * 0.5;
  return Size(
    (2 * (half + _margin)).ceilToDouble(),
    (g.radius + g.tipDrop + _margin).ceilToDouble(),
  );
}

/// The cream rim around every mark: it stands out of both basemaps.
const double _rim = 1.6;
const double _ringWidth = 3;

/// Paints a rich mark of [g] on [canvas] at the canvas's logical scale, the
/// tip at the bottom centre of [richMarkCanvas]: a photo in the logo's
/// drop, ringed with the night's tone ([richRing]), the kind's badge at its
/// lower right; or the illustrated capsule, the kind's pictogram on its
/// family's colour in a ringed disc and the label after it.
void paintRichMark(
  Canvas canvas, {
  required RichGeometry g,
  required RichFace face,
  required PlaceKind kind,
  required OvernightStatus night,
}) {
  final size = richMarkCanvas(g);
  final tip = Offset(size.width / 2, size.height - 1.5);
  final c = g.head(tip);
  final shadow = Paint()
    ..color = const Color(0x5C061F43)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  switch (face) {
    case PhotoFace(:final image):
      final drop = teardrop(c, g.radius, tip);
      canvas
        ..drawPath(drop.shift(const Offset(0, 1.2)), shadow)
        ..drawPath(drop, Paint()..color = LunaTokens.pinRim)
        ..drawPath(
          teardrop(c, g.radius - _rim, tip - const Offset(0, _rim * 1.6)),
          Paint()..color = richRing(night),
        );
      final disc = Rect.fromCircle(center: c, radius: g.radius - _rim - _ringWidth);
      // The photo's middle square covers the disc.
      final side = math.min(image.width, image.height).toDouble();
      final src = Rect.fromCenter(
        center: Offset(image.width / 2, image.height / 2),
        width: side,
        height: side,
      );
      canvas
        ..save()
        ..clipPath(Path()..addOval(disc))
        ..drawImageRect(image, src, disc, Paint()..filterQuality = FilterQuality.medium)
        ..restore();
      _paintBadge(canvas, g, c, kind);
    case IllustratedFace(:final label, :final star):
      final r = g.radius;
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: g.width, height: g.height),
        Radius.circular(r),
      );
      // A short tail under the middle, down to the place.
      final tail = Path()
        ..moveTo(c.dx - 6, c.dy + r - 1)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(c.dx + 6, c.dy + r - 1)
        ..close();
      final outline = Path()
        ..addRRect(body)
        ..addPath(tail, Offset.zero);
      canvas
        ..drawPath(outline.shift(const Offset(0, 1.2)), shadow)
        ..drawRRect(body.inflate(_rim), Paint()..color = LunaTokens.pinRim)
        ..drawPath(
          tail.shift(const Offset(0, 0.4)),
          Paint()
            ..color = LunaTokens.pinRim
            ..style = PaintingStyle.stroke
            ..strokeWidth = _rim * 2
            ..strokeJoin = StrokeJoin.round,
        )
        ..drawRRect(body, Paint()..color = Palette.minuit)
        ..drawPath(tail, Paint()..color = Palette.minuit);
      // The pictogram's disc at the left end, ringed with the night's tone.
      final disc = Offset(c.dx - g.width / 2 + r, c.dy);
      canvas
        ..drawCircle(disc, r - 1, Paint()..color = richRing(night))
        ..drawCircle(disc, r - 1 - _ringWidth, Paint()..color = LunaTokens.familyFill(kind.family));
      _paintGlyph(
        canvas,
        AppIcons.kind(kind),
        disc,
        (r - 1 - _ringWidth) * 1.25,
        LunaTokens.pinGlyph,
      );
      if (label != null) _paintLabel(canvas, Offset(disc.dx + r, c.dy), label, star: star);
  }
}

/// The kind's badge of a photo: its family's colour and pictogram, small,
/// at the head's lower right.
void _paintBadge(Canvas canvas, RichGeometry g, Offset c, PlaceKind kind) {
  final r = g.badge / 2;
  final at = c + Offset(g.radius * 0.72, g.radius * 0.62);
  canvas
    ..drawCircle(at, r + 1.5, Paint()..color = LunaTokens.pinRim)
    ..drawCircle(at, r, Paint()..color = LunaTokens.familyFill(kind.family));
  _paintGlyph(canvas, AppIcons.kind(kind), at, r * 1.3, LunaTokens.pinGlyph);
}

/// The label's words, cream on the capsule's navy, from [start]; a rating
/// has its star first, in the amber of the stars.
void _paintLabel(Canvas canvas, Offset start, String label, {required bool star}) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: richLabelStyle),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  var left = start.dx + _labelPad;
  if (star) {
    _paintGlyph(
      canvas,
      AppIcons.star,
      Offset(left + _starSize / 2, start.dy),
      _starSize,
      Palette.lanterne,
    );
    left += _starSize + _starGap;
  }
  painter
    ..paint(canvas, Offset(left, start.dy - painter.height / 2))
    ..dispose();
}

void _paintGlyph(Canvas canvas, IconData icon, Offset centre, double size, Color color) {
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
  painter
    ..paint(canvas, centre - Offset(painter.width / 2, painter.height / 2))
    ..dispose();
}

/// A rich mark as a PNG at [ratio] physical pixels per logical one.
Future<Uint8List> richMarkPng({
  required RichGeometry g,
  required RichFace face,
  required PlaceKind kind,
  required OvernightStatus night,
  required double ratio,
}) async {
  final size = richMarkCanvas(g);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  paintRichMark(canvas, g: g, face: face, kind: kind, night: night);
  final image = await recorder.endRecording().toImage(
    (size.width * ratio).ceil(),
    (size.height * ratio).ceil(),
  );
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// The rich marks' art: the API says a place's photo and price
/// ([PlaceThumbs]), [load] brings the photo through the app's image proxy
/// and its cache, the painter draws. A photo that does not come in
/// [photoWait] leaves the illustrated mark; offline, every mark is one.
final class PlaceRichArt implements RichArt {
  new({
    required this.thumbs,
    required this.load,
    this.thumbWait = const Duration(seconds: 3),
    this.photoWait = const Duration(seconds: 6),
  });

  final PlaceThumbs thumbs;
  final Future<Uint8List> Function(String url) load;
  final Duration thumbWait;
  final Duration photoWait;

  /// The photos that failed to come: those places stay illustrated.
  final _noPhoto = <String>{};

  @override
  ({bool capsule, double labelWidth}) plan(
    PlaceSummary place,
    GuidanceLook look,
    RichWords words, {
    required bool online,
  }) {
    final known = thumbs.known(place.id);
    final photos = look == GuidanceLook.photos && !_noPhoto.contains(place.id);
    // A photo known, or, online, one not asked about yet, which may well
    // come.
    if (photos && (known?.url != null || (online && known == null))) {
      return (capsule: false, labelWidth: 0);
    }
    final label = RichLabel.of(place, priceEur: known?.priceEur);
    return (
      capsule: true,
      labelWidth: label == null ? 0 : richLabelWidth(words.text(label), star: label is RatingLabel),
    );
  }

  @override
  Future<RichArtwork?> draw(
    PlaceSummary place, {
    required GuidanceLook look,
    required double size,
    required double ratio,
    required RichWords words,
    required bool online,
  }) async {
    final thumb = online
        ? await thumbs.of(place.id).timeout(thumbWait, onTimeout: () => null)
        : thumbs.known(place.id);
    final url = thumb?.url;
    if (look == GuidanceLook.photos && url != null && !_noPhoto.contains(place.id)) {
      final photo = await _photo(url, size, ratio);
      if (photo != null) {
        try {
          final g = RichGeometry(size);
          return RichArtwork(
            png: await richMarkPng(
              g: g,
              face: PhotoFace(photo),
              kind: place.kind,
              night: place.overnight,
              ratio: ratio,
            ),
            geometry: g,
            photo: true,
          );
        } finally {
          photo.dispose();
        }
      }
      _noPhoto.add(place.id);
    }
    final label = RichLabel.of(place, priceEur: thumb?.priceEur);
    final text = label == null ? null : words.text(label);
    final star = label is RatingLabel;
    final g = RichGeometry(
      size,
      labelWidth: text == null ? 0 : richLabelWidth(text, star: star),
      capsule: true,
    );
    return RichArtwork(
      png: await richMarkPng(
        g: g,
        face: IllustratedFace(label: text, star: star),
        kind: place.kind,
        night: place.overnight,
        ratio: ratio,
      ),
      geometry: g,
      photo: false,
    );
  }

  /// The photo decoded at the size the mark draws it (its shorter side the
  /// disc's), or null.
  Future<ui.Image?> _photo(String url, double size, double ratio) async {
    try {
      final bytes = await load(url).timeout(photoWait);
      final target = (size * ratio).ceil();
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (width, height) {
          final shorter = math.min(width, height);
          if (shorter <= target) return ui.TargetImageSize(width: width, height: height);
          final k = target / shorter;
          return ui.TargetImageSize(width: (width * k).ceil(), height: (height * k).ceil());
        },
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Object catch (e) {
      _log.fine('no photo for a mark: $e');
      return null;
    }
  }
}
