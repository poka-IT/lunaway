import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_glyph.dart';

import '../../helpers/maneuver_catalogue.dart';

/// Close enough on a 24 unit grid: a thousandth of a pixel at 76 px.
const _eps = 1e-6;

void _near(Offset actual, Offset expected, String why) =>
    expect((actual - expected).distance, lessThan(_eps), reason: '$why: $actual, not $expected');

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Distance from [p] to the segment [a]-[b].
double _toSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final t = (_dot(p - a, ab) / _dot(ab, ab)).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Where the exit of [glyph] goes: the direction of its head.
Offset _exitOf(ManeuverGlyph glyph) => glyph.heads.single.direction;

/// The screen direction of a road [degrees] round a ring from the entry
/// at its bottom, in the direction of traffic: anticlockwise as seen from
/// above where traffic keeps right.
Offset _expectedExit(double degrees, {bool leftHand = false}) {
  final a = degrees * math.pi / 180;
  return Offset(leftHand ? -math.sin(a) : math.sin(a), math.cos(a));
}

void main() {
  final everyGlyph = [
    for (final (name, m) in maneuverCatalogue) (name, maneuverGlyph(m)),
    for (var d = 0; d < 360; d += 15)
      for (final left in [false, true])
        (
          'roundabout $d${left ? ' left-hand' : ''}',
          maneuverGlyph(Maneuver(type: 'roundabout', exitDegrees: d, leftHandTraffic: left)),
        ),
  ];

  group('every pictogram', () {
    test('runs each line on from one segment to the next, with no gap', () {
      for (final (name, glyph) in everyGlyph) {
        for (final stroke in glyph.strokes) {
          for (var i = 1; i < stroke.segments.length; i++) {
            _near(stroke.segments[i].start, stroke.segments[i - 1].end, '$name, segment $i');
          }
        }
      }
    });

    test('bends without a kink, but where a road meets a roundabout square', () {
      for (final (name, glyph) in everyGlyph) {
        for (final stroke in glyph.strokes) {
          for (var i = 1; i < stroke.segments.length; i++) {
            final before = stroke.segments[i - 1].endDirection;
            final after = stroke.segments[i].startDirection;
            final square = name.startsWith('roundabout') && stroke.tone == GlyphTone.main;
            expect(
              _dot(before, after),
              square ? closeTo(0, _eps) : closeTo(1, _eps),
              reason: '$name, between segments ${i - 1} and $i',
            );
          }
        }
      }
    });

    test('ends its way in a head that sits on the line and points the way it goes', () {
      for (final (name, glyph) in everyGlyph) {
        final ways = glyph.strokes.where((s) => s.tone == GlyphTone.main).toList();
        for (final head in glyph.heads) {
          final line = ways.firstWhere(
            (s) => (s.end - head.base).distance < _eps,
            orElse: () => fail('$name: no line ends at the head ${head.base}'),
          );
          _near(head.direction, line.segments.last.endDirection, '$name, head direction');
          // The line's round end hides inside the head: the head is wider
          // than the line half a stroke past its base.
          const halfWidthThere = glyphHeadWidth / 2 * (1 - glyphStroke / 2 / glyphHeadLength);
          expect(halfWidthThere, greaterThan(glyphStroke / 2), reason: name);
        }
      }
    });

    test('keeps its ink inside the grid, a margin from the edge', () {
      for (final (name, glyph) in everyGlyph) {
        final box = glyph.bounds;
        expect(box.left, greaterThanOrEqualTo(glyphMargin - _eps), reason: '$name $box');
        expect(box.top, greaterThanOrEqualTo(glyphMargin - _eps), reason: '$name $box');
        expect(box.right, lessThanOrEqualTo(glyphGrid - glyphMargin + _eps), reason: '$name $box');
        expect(box.bottom, lessThanOrEqualTo(glyphGrid - glyphMargin + _eps), reason: '$name $box');
      }
    });

    test('is centred across the grid, roundabouts on their entry', () {
      for (final (name, glyph) in everyGlyph) {
        if (name.startsWith('roundabout')) {
          expect(glyph.snapX, glyphGrid / 2, reason: name);
          continue;
        }
        expect(glyph.bounds.center.dx, closeTo(glyphGrid / 2, 1e-3), reason: name);
      }
    });
  });

  group('turns', () {
    test('bend by the angle the modifier names, the head along it', () {
      const turns = {
        'straight': 0.0,
        'slight right': 45.0,
        'right': 90.0,
        'sharp right': 135.0,
        'slight left': -45.0,
        'left': -90.0,
        'sharp left': -135.0,
      };
      for (final MapEntry(key: modifier, value: degrees) in turns.entries) {
        final glyph = maneuverGlyph(Maneuver(type: 'turn', modifier: modifier));
        final a = degrees * math.pi / 180;
        _near(glyph.heads.single.direction, Offset(math.sin(a), -math.cos(a)), modifier);
        // The line starts straight up from the bottom.
        _near(glyph.strokes.single.segments.first.startDirection, const Offset(0, -1), modifier);
      }
    });

    test('a U-turn goes round to the left where traffic keeps right, to the right where it '
        'keeps left', () {
      for (final (left, side) in [(false, -1.0), (true, 1.0)]) {
        final glyph = maneuverGlyph(
          Maneuver(type: 'continue', modifier: 'uturn', leftHandTraffic: left),
        );
        final stroke = glyph.strokes.single;
        _near(glyph.heads.single.direction, const Offset(0, 1), 'U-turn comes back down');
        expect((stroke.end.dx - stroke.start.dx).sign, side);
      }
    });

    test('the line a pictogram lines up on the pixel grid is one of its own', () {
      for (final (name, glyph) in everyGlyph) {
        final lines = [
          for (final s in glyph.strokes)
            for (final segment in s.segments)
              if (segment is GlyphLine) segment,
        ];
        final x = glyph.snapX;
        if (x != null) {
          expect(
            lines.any((l) => (l.start.dx - x).abs() < _eps && (l.end.dx - x).abs() < _eps),
            isTrue,
            reason: '$name: no vertical line at $x',
          );
        }
        final y = glyph.snapY;
        if (y != null) {
          expect(
            lines.any((l) => (l.start.dy - y).abs() < _eps && (l.end.dy - y).abs() < _eps),
            isTrue,
            reason: '$name: no horizontal line at $y',
          );
        }
      }
    });
  });

  group('roundabouts', () {
    ManeuverGlyph roundabout(double degrees, {bool leftHand = false, int? exit}) => maneuverGlyph(
      Maneuver(
        type: 'roundabout',
        exitDegrees: degrees.round(),
        exitNumber: exit,
        leftHandTraffic: leftHand,
      ),
    );

    test('the entry comes straight up the middle and meets the ring square to it', () {
      final way = roundabout(212).strokes.last.segments;
      final entry = way[0] as GlyphLine;
      final ring = way[1] as GlyphArc;
      expect(entry.start.dx, glyphGrid / 2);
      expect(entry.end.dx, glyphGrid / 2);
      _near(entry.end, ring.start, 'the entry ends on the ring');
      expect((entry.end - ring.center).distance, closeTo(roundaboutRadius, _eps));
      expect(_dot(entry.endDirection, ring.startDirection), closeTo(0, _eps));
    });

    test('each exit of a four-way and a five-way roundabout leaves at its angle, square to '
        'the ring', () {
      for (final arms in [4, 5]) {
        for (var rank = 1; rank < arms; rank++) {
          final degrees = 360 / arms * rank;
          for (final left in [false, true]) {
            final glyph = roundabout(degrees, leftHand: left, exit: rank);
            final way = glyph.strokes.last.segments;
            final ring = way[1] as GlyphArc;
            final exit = way[2] as GlyphLine;
            final expected = _expectedExit(degrees, leftHand: left);
            _near(_exitOf(glyph), expected, 'exit $rank of $arms${left ? ', left-hand' : ''}');
            // The arm is radial: it starts on the ring and points away from
            // its centre.
            _near((exit.start - ring.center) / roundaboutRadius, expected, 'radial arm');
            expect(ring.sweep.abs(), closeTo(degrees * math.pi / 180, _eps));
            expect(
              ring.sweep.sign,
              left ? 1 : -1,
              reason: 'anticlockwise where traffic keeps right',
            );
            expect(glyph.label?.text, '$rank');
          }
        }
      }
    });

    test('the ring is whole: the way round it bright, the rest muted, overlapping a little', () {
      for (final degrees in [62.0, 90.0, 180.0, 212.0, 298.0]) {
        final glyph = roundabout(degrees);
        final bright = glyph.strokes.last.segments[1] as GlyphArc;
        final muted = glyph.strokes.first.segments.single as GlyphArc;
        expect(glyph.strokes.first.tone, GlyphTone.muted);
        expect(bright.sweep.abs() + muted.sweep.abs(), greaterThan(2 * math.pi));
        expect(muted.center, bright.center);
        expect(muted.radius, bright.radius);
      }
    });

    test('an exit close to the entry is drawn far enough round for its head to clear the '
        'entry', () {
      for (final degrees in [10.0, 30.0, 45.0, 350.0, 326.0]) {
        final glyph = roundabout(degrees);
        final drawn = degrees < 180 ? roundaboutClosestExit : 360 - roundaboutClosestExit;
        _near(_exitOf(glyph), _expectedExit(drawn), '$degrees drawn at $drawn');
        final entry = glyph.strokes.last.segments.first as GlyphLine;
        for (final corner in glyph.heads.single.corners) {
          expect(
            _toSegment(corner, entry.start, entry.end),
            greaterThan(glyphStroke / 2 + 0.5),
            reason: 'the head of $degrees keeps off the entry road',
          );
        }
      }
    });

    test('the exits of the Brive to Ussel route leave at the angle of the roads', () {
      // The recorded answer, parsed as the app parses it: each roundabout
      // step knows how far round its exit is; the pictogram's exit leaves
      // in the heading of the road out, relative to the road in.
      final json = jsonDecode(
        File('test/fixtures/navigation/route_brive_ussel_en.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final osrm = ((json['data'] as Map)['route'] as Map)['osrmJson'] as String;
      final routes = (jsonDecode(osrm) as Map<String, dynamic>)['routes'] as List;
      final legs = (routes.first as Map<String, dynamic>)['legs'] as List;
      final raw = [
        for (final s in (legs.single as Map<String, dynamic>)['steps'] as List)
          (s as Map<String, dynamic>)['maneuver'] as Map<String, dynamic>,
      ];
      final steps = readOsrmShapes(osrm).first.steps;
      var seen = 0;
      for (var i = 0; i < steps.length; i++) {
        if (steps[i].maneuverType != 'roundabout') continue;
        seen++;
        final headingIn = (raw[i]['bearing_before'] as num).toDouble();
        final headingOut = (raw[i + 1]['bearing_after'] as num).toDouble();
        final turn = ((headingOut - headingIn + 540) % 360) - 180;
        final glyph = maneuverGlyph(steps[i].maneuver);
        final degrees = 180 - turn;
        if (degrees < roundaboutClosestExit || degrees > 360 - roundaboutClosestExit) continue;
        // On screen, up is the heading in: the road out turns by [turn].
        final a = turn * math.pi / 180;
        _near(_exitOf(glyph), Offset(math.sin(a), -math.cos(a)), 'step $i, turn $turn');
        expect(glyph.label?.text, '${steps[i].exit}');
      }
      expect(seen, 10);
    });

    test('the number of the exit stands on the side the exit leaves free', () {
      for (final degrees in [90.0, 180.0, 212.0, 270.0, 298.0]) {
        for (final left in [false, true]) {
          final glyph = roundabout(degrees, leftHand: left, exit: 2);
          final label = glyph.label!;
          final head = glyph.heads.single;
          final box = Rect.fromCenter(center: label.center, width: label.size, height: label.size);
          for (final corner in [head.tip, ...head.corners]) {
            expect(box.contains(corner), isFalse, reason: '$degrees${left ? ' left-hand' : ''}');
          }
          final entry = glyph.strokes.last.segments.first as GlyphLine;
          expect(
            _toSegment(label.center, entry.start, entry.end),
            greaterThan(label.size / 2 + glyphStroke / 2),
          );
        }
      }
    });
  });

  group('exit degrees', () {
    test('follow the router: 180 straight across, a quarter turn right 90 where traffic '
        'keeps right', () {
      expect(roundaboutExitDegrees(headingIn: 11, headingOut: 339, leftHandTraffic: false), 212);
      expect(roundaboutExitDegrees(headingIn: 0, headingOut: 0, leftHandTraffic: false), 180);
      expect(roundaboutExitDegrees(headingIn: 0, headingOut: 90, leftHandTraffic: false), 90);
      expect(roundaboutExitDegrees(headingIn: 0, headingOut: 270, leftHandTraffic: false), 270);
      // Clockwise where traffic keeps left: the first exit is to the left.
      expect(roundaboutExitDegrees(headingIn: 0, headingOut: 270, leftHandTraffic: true), 90);
    });
  });
}
