/// The geometry of the maneuver pictograms, apart from any canvas, so a
/// test can check what the eye checks: every line meets the next, a head
/// points the way its line goes, a roundabout's exit leaves the ring at the
/// angle of the road.
///
/// Every pictogram is drawn on a square grid of [glyphGrid] units, as an
/// icon font is, with one stroke width, round caps and joins, and filled
/// triangular heads; `ManeuverIcon` scales it to its size.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:lunaway/features/navigation/domain/maneuver.dart';

/// The side of the grid, units.
const glyphGrid = 24.0;

/// The width of every line, units: an eighth of the grid, thick enough for
/// a cab at arm's length and for a 28 px pictogram.
const glyphStroke = 3.0;

/// The length and the base of an arrow's head, units.
const glyphHeadLength = 5.0;
const glyphHeadWidth = 8.0;

/// The radius of a head's corners, units: rounded like the line's caps.
const glyphHeadRound = 0.6;

/// The ink of a pictogram keeps this far inside the grid.
const glyphMargin = 1.0;

/// The height an arrow fills: the grid less a margin above and below.
const double _fill = glyphGrid - 2 * glyphMargin - 1;

/// What a part of a pictogram is: the way to take, or the roads around it.
enum GlyphTone { main, muted }

/// A piece of a line: a straight segment or an arc.
sealed class GlyphSegment {
  const new();

  Offset get start;
  Offset get end;

  /// The unit direction of travel where the segment starts and ends.
  Offset get startDirection;
  Offset get endDirection;

  /// The point at [t] of the way along, 0 to 1.
  Offset pointAt(double t);

  GlyphSegment shifted(Offset by);
}

/// A straight segment.
final class GlyphLine extends GlyphSegment {
  const new(this.start, this.end);

  @override
  final Offset start;
  @override
  final Offset end;

  Offset get _direction {
    final d = end - start;
    return d / d.distance;
  }

  @override
  Offset get startDirection => _direction;
  @override
  Offset get endDirection => _direction;
  @override
  Offset pointAt(double t) => Offset.lerp(start, end, t)!;
  @override
  GlyphLine shifted(Offset by) => GlyphLine(start + by, end + by);
}

/// An arc of a circle, angles in radians from the x axis towards the y
/// axis (clockwise on screen, where y grows downwards). A positive [sweep]
/// turns clockwise on screen.
final class GlyphArc extends GlyphSegment {
  const new(this.center, this.radius, this.startAngle, this.sweep);

  final Offset center;
  final double radius;
  final double startAngle;
  final double sweep;

  double get endAngle => startAngle + sweep;

  Offset _at(double angle) => center + Offset(math.cos(angle), math.sin(angle)) * radius;

  Offset _tangent(double angle) => sweep >= 0
      ? Offset(-math.sin(angle), math.cos(angle))
      : Offset(math.sin(angle), -math.cos(angle));

  @override
  Offset get start => _at(startAngle);
  @override
  Offset get end => _at(endAngle);
  @override
  Offset get startDirection => _tangent(startAngle);
  @override
  Offset get endDirection => _tangent(endAngle);
  @override
  Offset pointAt(double t) => _at(startAngle + sweep * t);
  @override
  GlyphArc shifted(Offset by) => GlyphArc(center + by, radius, startAngle, sweep);
}

/// One continuous line, stroked once: its segments follow each other.
final class GlyphStroke {
  const new(this.segments, {this.tone = GlyphTone.main});

  final List<GlyphSegment> segments;
  final GlyphTone tone;

  Offset get start => segments.first.start;
  Offset get end => segments.last.end;

  GlyphStroke shifted(Offset by) =>
      GlyphStroke([for (final s in segments) s.shifted(by)], tone: tone);
}

/// The head of an arrow: a triangle whose tip is [tip], pointing along the
/// unit [direction].
final class GlyphHead {
  const new({required this.tip, required this.direction, this.tone = GlyphTone.main});

  final Offset tip;
  final Offset direction;
  final GlyphTone tone;

  /// The middle of its base, where its line ends.
  Offset get base => tip - direction * glyphHeadLength;

  /// The tip, then the two corners of the base.
  List<Offset> get corners {
    final across = Offset(-direction.dy, direction.dx) * (glyphHeadWidth / 2);
    return [tip, base + across, base - across];
  }

  GlyphHead shifted(Offset by) => GlyphHead(tip: tip + by, direction: direction, tone: tone);
}

/// A filled shape: closed outlines, holes cut where they overlap (even-odd).
final class GlyphShape {
  const new(this.outlines, {this.tone = GlyphTone.main});

  /// Each outline's segments follow each other and come back to the start.
  final List<List<GlyphSegment>> outlines;
  final GlyphTone tone;

  GlyphShape shifted(Offset by) => GlyphShape([
    for (final o in outlines) [for (final s in o) s.shifted(by)],
  ], tone: tone);
}

/// A number written in the pictogram (a roundabout's exit), centred on
/// [center], [size] units high.
final class GlyphLabel {
  const new(this.text, this.center, this.size);

  final String text;
  final Offset center;
  final double size;

  GlyphLabel shifted(Offset by) => GlyphLabel(text, center + by, size);
}

/// A whole pictogram on the grid.
final class ManeuverGlyph {
  const new({
    this.strokes = const [],
    this.heads = const [],
    this.shapes = const [],
    this.label,
    this.snapX,
    this.snapY,
  });

  final List<GlyphStroke> strokes;
  final List<GlyphHead> heads;
  final List<GlyphShape> shapes;
  final GlyphLabel? label;

  /// The middle of a vertical line, and of a horizontal one, if the
  /// pictogram has one: the painter puts their edges on the pixel grid.
  final double? snapX;
  final double? snapY;

  ManeuverGlyph shifted(Offset by) => ManeuverGlyph(
    strokes: [for (final s in strokes) s.shifted(by)],
    heads: [for (final h in heads) h.shifted(by)],
    shapes: [for (final s in shapes) s.shifted(by)],
    label: label?.shifted(by),
    snapX: snapX == null ? null : snapX! + by.dx,
    snapY: snapY == null ? null : snapY! + by.dy,
  );

  /// The box the ink covers: lines with their width, heads, shapes. A
  /// label is left out, it sits where the pictogram leaves room.
  Rect get bounds {
    var box = Rect.zero;
    var first = true;
    void add(Rect r) {
      box = first ? r : box.expandToInclude(r);
      first = false;
    }

    for (final stroke in strokes) {
      for (final segment in stroke.segments) {
        for (final p in _samples(segment)) {
          add(Rect.fromCircle(center: p, radius: glyphStroke / 2));
        }
      }
    }
    for (final head in heads) {
      for (final c in head.corners) {
        add(Rect.fromCircle(center: c, radius: 0));
      }
    }
    for (final shape in shapes) {
      for (final outline in shape.outlines) {
        for (final segment in outline) {
          for (final p in _samples(segment)) {
            add(Rect.fromCircle(center: p, radius: 0));
          }
        }
      }
    }
    return box;
  }
}

Iterable<Offset> _samples(GlyphSegment s) => switch (s) {
  GlyphLine() => [s.start, s.end],
  GlyphArc() => [for (var i = 0; i <= 48; i++) s.pointAt(i / 48)],
};

/// The turn a modifier names, degrees from straight on, right positive. A
/// U-turn goes round to the side of the oncoming traffic: left where
/// traffic keeps right, right where it keeps left.
double turnDegrees(String? modifier, {bool leftHandTraffic = false}) => switch (modifier) {
  'uturn' => leftHandTraffic ? 180 : -180,
  'sharp left' => -135,
  'left' => -90,
  'slight left' => -45,
  'slight right' => 45,
  'right' => 90,
  'sharp right' => 135,
  _ => 0,
};

/// The pictogram of [maneuver].
ManeuverGlyph maneuverGlyph(Maneuver maneuver) {
  final modifier = maneuver.modifier;
  final leftHand = maneuver.leftHandTraffic;
  final angle = turnDegrees(modifier, leftHandTraffic: leftHand);
  if (maneuver.ferry) return ferryGlyph();
  if (maneuver.isRoundabout) {
    // A `roundabout turn` (a small roundabout taken as a turn, in OSRM's
    // words) has the turn itself as its modifier, where Valhalla's
    // roundabouts have the turn into the ring.
    final fromTurn = maneuver.type == 'roundabout turn'
        ? (leftHand ? 180 + angle : 180 - angle)
        : null;
    return roundaboutGlyph(
      exitDegrees: maneuver.exitDegrees?.toDouble() ?? fromTurn,
      leftHandTraffic: leftHand,
      exitNumber: maneuver.exitNumber,
    );
  }
  // The side a fork, a ramp or a merge goes to when the modifier does not
  // say: the side traffic keeps to, where those roads leave.
  final side = angle == 0 ? (leftHand ? -1.0 : 1.0) : angle.sign;
  return switch (maneuver.type) {
    'arrive' => arriveGlyph(angle.sign),
    'depart' => arrowGlyph(angle, origin: true),
    'fork' => forkGlyph(angle == 0 ? 0 : side, otherSide: angle == 0 ? side : -side),
    'off ramp' => rampGlyph(side, angle.abs() > 60 ? 90 : 45),
    'end of road' => endOfRoadGlyph(side),
    // A merge into the road on the other side: from the right where
    // traffic keeps right, onto the motorway's lane on the left.
    'merge' => mergeGlyph(angle == 0 ? -side : side),
    _ => arrowGlyph(angle),
  };
}

/// How sharp the bend of a turn is: the radius of its curve, the straight
/// line after it, units.
({double radius, double arm}) _bendOf(double angle) => switch (angle.abs()) {
  0 => (radius: 0, arm: 0),
  <= 60 => (radius: 6, arm: 2.5),
  <= 100 => (radius: 4, arm: 2.5),
  < 179 => (radius: 3.5, arm: 2.5),
  _ => (radius: 4, arm: 2),
};

/// The line of an arrow that leaves [base] going up, runs [stem] units,
/// bends by [angle] degrees (right positive) on a curve of [radius], then
/// runs [arm] units straight; and where and which way it ends.
({List<GlyphSegment> segments, Offset end, Offset direction}) _bend(
  Offset base,
  double stem,
  double angle, {
  required double radius,
  required double arm,
}) {
  final knee = base - Offset(0, stem);
  final segments = <GlyphSegment>[if (stem > 0) GlyphLine(base, knee)];
  var end = knee;
  var direction = const Offset(0, -1);
  if (angle != 0) {
    final turn = angle * math.pi / 180;
    final arc = angle > 0
        ? GlyphArc(knee + Offset(radius, 0), radius, math.pi, turn)
        : GlyphArc(knee - Offset(radius, 0), radius, 0, turn);
    segments.add(arc);
    end = arc.end;
    direction = arc.endDirection;
  }
  if (arm > 0) {
    final tail = end + direction * arm;
    segments.add(GlyphLine(end, tail));
    end = tail;
  }
  return (segments: segments, end: end, direction: direction);
}

/// [build] with the stretch that makes the pictogram [_fill] units high
/// (at least [least]), centred on the grid.
ManeuverGlyph _fit(ManeuverGlyph Function(double stretch) build, {double least = 2}) {
  var low = least;
  var high = glyphGrid;
  if (build(low).bounds.height < _fill) {
    for (var i = 0; i < 40; i++) {
      final mid = (low + high) / 2;
      if (build(mid).bounds.height > _fill) {
        high = mid;
      } else {
        low = mid;
      }
    }
  }
  final glyph = build(low);
  return glyph.shifted(const Offset(glyphGrid / 2, glyphGrid / 2) - glyph.bounds.center);
}

/// An arrow up from the bottom that bends by [angle] degrees (0 straight
/// on, ±180 a U-turn), with a dot where it starts when it is the
/// [origin] of the trip.
ManeuverGlyph arrowGlyph(double angle, {bool origin = false}) {
  final bend = _bendOf(angle);
  return _fit((stem) {
    final line = _bend(Offset.zero, stem, angle, radius: bend.radius, arm: bend.arm);
    return ManeuverGlyph(
      strokes: [
        GlyphStroke(line.segments.isEmpty ? [GlyphLine(Offset.zero, line.end)] : line.segments),
      ],
      heads: [
        GlyphHead(tip: line.end + line.direction * glyphHeadLength, direction: line.direction),
      ],
      shapes: [if (origin) _disc(Offset.zero, glyphStroke)],
      snapX: 0,
      snapY: angle.abs() == 90 ? line.end.dy : null,
    );
  }, least: origin ? 6 : 2);
}

/// A fork: the branch taken bends towards [side] (0 straight on), the
/// other one, muted, towards [otherSide].
ManeuverGlyph forkGlyph(double side, {required double otherSide}) => _fit((stem) {
  const angle = 40.0;
  const radius = 7.0;
  // Straight on, the way taken runs on past the split as far as the
  // branch does, so the branch does not grow out of the head.
  final taken = _bend(Offset.zero, stem, side * angle, radius: radius, arm: side == 0 ? 6.5 : 2);
  final other = _bend(Offset(0, -stem), 0, otherSide * angle, radius: radius, arm: 4.5);
  return ManeuverGlyph(
    strokes: [
      GlyphStroke(other.segments, tone: GlyphTone.muted),
      GlyphStroke(taken.segments),
    ],
    heads: [
      GlyphHead(tip: taken.end + taken.direction * glyphHeadLength, direction: taken.direction),
    ],
    snapX: 0,
  );
});

/// An exit from a motorway: the road going on, muted, and the ramp that
/// leaves it towards [side] by [angle] degrees.
ManeuverGlyph rampGlyph(double side, double angle) {
  final bend = _bendOf(angle);
  return _fit((stem) {
    final ramp = _bend(Offset.zero, stem, side * angle, radius: bend.radius, arm: bend.arm);
    final tip = ramp.end + ramp.direction * glyphHeadLength;
    final knee = Offset(0, -stem);
    return ManeuverGlyph(
      strokes: [
        GlyphStroke([GlyphLine(knee, Offset(0, tip.dy + glyphStroke / 2))], tone: GlyphTone.muted),
        GlyphStroke(ramp.segments),
      ],
      heads: [GlyphHead(tip: tip, direction: ramp.direction)],
      snapX: 0,
    );
  });
}

/// The end of a road at a T: the turn towards [side], and the other way,
/// muted.
ManeuverGlyph endOfRoadGlyph(double side) => _fit((stem) {
  final taken = _bend(Offset.zero, stem, side * 90, radius: 4, arm: 2.5);
  final other = _bend(Offset(0, -stem), 0, -side * 90, radius: 4, arm: 4);
  return ManeuverGlyph(
    strokes: [
      GlyphStroke(other.segments, tone: GlyphTone.muted),
      GlyphStroke(taken.segments),
    ],
    heads: [
      GlyphHead(tip: taken.end + taken.direction * glyphHeadLength, direction: taken.direction),
    ],
    snapX: 0,
    snapY: taken.end.dy,
  );
});

/// A merge: the road joined runs up the middle, muted below the point
/// where the way taken, coming from the other side, moves over towards
/// [side] and joins it.
ManeuverGlyph mergeGlyph(double side) => _fit((stretch) {
  const radius = 4.0;
  const turn = 45.0 * math.pi / 180;
  const across = 2.5;
  final shift = 2 * radius * (1 - math.cos(turn)) + across * math.sin(turn);
  final first = _bend(
    Offset(-side * shift, 0),
    2,
    side * turn * 180 / math.pi,
    radius: radius,
    arm: across,
  );
  // The second curve turns back to straight up: its centre lies square to
  // the line, on the side it turns to.
  final towards = Offset(-first.direction.dy, first.direction.dx) * side;
  final centre = first.end - towards * radius;
  final from = math.atan2(first.end.dy - centre.dy, first.end.dx - centre.dx);
  final curve = GlyphArc(centre, radius, from, -side * turn);
  final joined = curve.end;
  final top = joined - Offset(0, stretch);
  final segments = [...first.segments, curve, GlyphLine(joined, top)];
  return ManeuverGlyph(
    strokes: [
      GlyphStroke([GlyphLine(Offset(joined.dx, 0), joined)], tone: GlyphTone.muted),
      GlyphStroke(segments),
    ],
    heads: [GlyphHead(tip: top - const Offset(0, glyphHeadLength), direction: const Offset(0, -1))],
    snapX: joined.dx,
  );
});

/// The arrival: the road up to a pin, or on [side] of the road (-1 left,
/// 1 right) a pin beside the arrow.
ManeuverGlyph arriveGlyph(double side) {
  if (side == 0) {
    return _fit((stem) {
      const pinRadius = 5.0;
      const tipBelow = 8.0;
      final tip = Offset(0, -stem);
      // The road runs into the pin up to where the pin is wider than the
      // line and covers its round end.
      return ManeuverGlyph(
        strokes: [
          GlyphStroke([GlyphLine(Offset.zero, tip - const Offset(0, 3.5))]),
        ],
        shapes: [_pin(tip - const Offset(0, tipBelow), pinRadius, tipBelow)],
        snapX: 0,
      );
    }, least: 4);
  }
  return _fit((stem) {
    const pinRadius = 4.5;
    const tipBelow = 7.0;
    final arrow = _bend(Offset.zero, stem, 0, radius: 0, arm: 0);
    final tip = arrow.end - const Offset(0, glyphHeadLength);
    final pinCentre = Offset(side * 10, tip.dy + pinRadius);
    return ManeuverGlyph(
      strokes: [GlyphStroke(arrow.segments)],
      heads: [GlyphHead(tip: tip, direction: const Offset(0, -1))],
      shapes: [_pin(pinCentre, pinRadius, tipBelow)],
      snapX: 0,
    );
  });
}

/// A boat on the water: a ferry crossing.
ManeuverGlyph ferryGlyph() {
  const hullTop = 12.5;
  const hull = [
    GlyphLine(Offset(2.5, hullTop), Offset(21.5, hullTop)),
    GlyphLine(Offset(21.5, hullTop), Offset(18, 17)),
    GlyphLine(Offset(18, 17), Offset(6, 17)),
    GlyphLine(Offset(6, 17), Offset(2.5, hullTop)),
  ];
  // The water: one line of two waves, each crest and trough a quarter of
  // a circle running into the next.
  const radius = 3.0;
  const reach = radius * math.sqrt2 / 2;
  const left = 12 - 4 * reach;
  final waves = <GlyphSegment>[];
  var at = const Offset(left, 20.5);
  for (var i = 0; i < 4; i++) {
    final crest = i.isEven;
    final centre = at + (crest ? const Offset(reach, reach) : const Offset(reach, -reach));
    final arc = crest
        ? GlyphArc(centre, radius, math.pi * 1.25, math.pi / 2)
        : GlyphArc(centre, radius, math.pi * 0.75, -math.pi / 2);
    waves.add(arc);
    at = arc.end;
  }
  return ManeuverGlyph(
    shapes: [
      const GlyphShape([hull]),
      GlyphShape([_rectangle(const Rect.fromLTRB(7, 8, 15, hullTop + 0.5))]),
      GlyphShape([_rectangle(const Rect.fromLTRB(9.5, 4.5, 12.5, 8.5))]),
    ],
    strokes: [GlyphStroke(waves)],
  );
}

List<GlyphSegment> _rectangle(Rect r) => [
  GlyphLine(r.topLeft, r.topRight),
  GlyphLine(r.topRight, r.bottomRight),
  GlyphLine(r.bottomRight, r.bottomLeft),
  GlyphLine(r.bottomLeft, r.topLeft),
];

/// A filled disc of [radius] at [centre].
GlyphShape _disc(Offset centre, double radius) => GlyphShape([
  [GlyphArc(centre, radius, 0, 2 * math.pi)],
]);

/// A map pin: a disc of [radius] at [centre] narrowing to a point
/// [tipBelow] units under it, with a round hole.
GlyphShape _pin(Offset centre, double radius, double tipBelow) {
  final tip = centre + Offset(0, tipBelow);
  // The lines from the tip touch the circle where the radius is square to
  // them.
  final touch = math.acos(radius / tipBelow);
  final arc = GlyphArc(centre, radius, math.pi / 2 - touch, -(2 * math.pi - 2 * touch));
  return GlyphShape([
    [GlyphLine(tip, arc.start), arc, GlyphLine(arc.end, tip)],
    [GlyphArc(centre, radius * 0.4, 0, 2 * math.pi)],
  ]);
}

/// The ring of a roundabout, its centre and radius on the grid, units.
const roundaboutCentre = Offset(12, 12);
const roundaboutRadius = 3.5;

/// How far from the ring's centre an exit's head begins, units: past the
/// ring's outer edge, so a little of the exit road shows.
const roundaboutHeadFrom = 6.0;

/// The nearest an exit is drawn to the entry, degrees round the ring, on
/// either side: closer, its head would lie on the entry road. A first exit
/// sharper than this is drawn here, a way back round the ring at the other
/// end ([roundaboutDrawnExit]).
const roundaboutClosestExit = 62.0;

/// Under this many degrees round, an exit that is not the first is a way
/// back round the ring: the router measures a U-turn from the headings in
/// and out, which give a few degrees past 360 as readily as a few short of
/// it.
const _backRound = 31.0;

/// Under this many degrees round, even a first exit is the way back: no
/// road leaves that close to the entry, but the single road of a turning
/// circle comes back out of it.
const _backAlways = 15.0;

/// Where [roundaboutGlyph] draws an exit [degrees] round the ring.
double roundaboutDrawnExit(double degrees, {int? exitNumber}) {
  if (degrees < _backAlways || (degrees < _backRound && exitNumber != 1)) {
    return 360 - roundaboutClosestExit;
  }
  return degrees.clamp(roundaboutClosestExit, 360 - roundaboutClosestExit);
}

/// The muted ring runs this far under the bright part at both ends,
/// radians, so no seam shows where they meet.
const _ringOverlap = 0.12;

/// A roundabout: the entry up from the bottom, square to the ring, the
/// way round the ring to the exit [exitDegrees] round in the direction of
/// traffic, bright, the rest of the ring muted, and the exit road leaving
/// square to the ring with its head. The [exitNumber] sits beside the
/// entry, on the side the exit leaves free. Without [exitDegrees] the ring
/// stays whole and muted, the entry alone bright: no exit is drawn rather
/// than one guessed (Valhalla's modifier on a roundabout is the turn into
/// the ring, not the way out).
ManeuverGlyph roundaboutGlyph({
  required double? exitDegrees,
  required bool leftHandTraffic,
  int? exitNumber,
}) {
  const centre = roundaboutCentre;
  const radius = roundaboutRadius;
  const entryAngle = math.pi / 2;
  final entry = centre + const Offset(0, radius);
  final stem = GlyphLine(const Offset(12, glyphGrid - glyphMargin - glyphStroke / 2), entry);
  final number = exitNumber;
  GlyphLabel? labelOn(double side) => number != null && number > 0
      ? GlyphLabel('$number', Offset(centre.dx + side * 6.75, 19.75), 8)
      : null;
  // Where traffic leaves the ring last: left of the entry where it keeps
  // right.
  final lastSide = leftHandTraffic ? 1.0 : -1.0;
  if (exitDegrees == null) {
    return ManeuverGlyph(
      strokes: [
        const GlyphStroke([GlyphArc(centre, radius, 0, 2 * math.pi)], tone: GlyphTone.muted),
        GlyphStroke([stem]),
      ],
      label: labelOn(lastSide),
      snapX: centre.dx,
    );
  }
  final degrees = roundaboutDrawnExit(exitDegrees, exitNumber: exitNumber);
  // Right-hand traffic goes round anticlockwise as seen from above, which
  // on screen is a negative sweep from the bottom of the ring.
  final turn = (leftHandTraffic ? 1 : -1) * degrees * math.pi / 180;
  final round = GlyphArc(centre, radius, entryAngle, turn);
  final out = (round.end - centre) / radius;
  final headBase = centre + out * roundaboutHeadFrom;
  final rest = 2 * math.pi - turn.abs();
  final muted = GlyphArc(
    centre,
    radius,
    round.endAngle - turn.sign * _ringOverlap,
    turn.sign * (rest + 2 * _ringOverlap),
  );
  return ManeuverGlyph(
    strokes: [
      GlyphStroke([muted], tone: GlyphTone.muted),
      GlyphStroke([stem, round, GlyphLine(round.end, headBase)]),
    ],
    heads: [GlyphHead(tip: headBase + out * glyphHeadLength, direction: out)],
    // Beside the entry, on the side away from the exit; for an exit
    // straight on, on the side traffic leaves the ring last.
    label: labelOn(out.dx.abs() > 0.3 ? -out.dx.sign : lastSide),
    snapX: centre.dx,
  );
}
