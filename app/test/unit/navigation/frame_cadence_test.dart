import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';
import 'package:lunaway/features/navigation/domain/frame_cadence.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';

/// The guidance map's cadence: how fast the picture moves on the screen,
/// the frames a second that show it in steps of a pixel and a half, and the
/// engine's limit of frames that follows
/// (`plan/research/124-cadence-carte-guidage.md`).

/// A phone held upright (411 x 914 logical pixels, a Pixel 6), the banner
/// over the map and the bar under it.
const _phone = Size(411, 914);
const _panels = EdgeInsets.only(top: 190, bottom: 110);
final Offset _anchor = followAnchor(_phone, _panels);

double _px({
  required double kmh,
  required double zoom,
  required double tilt,
  double turnDegPerS = 0,
  double zoomPerS = 0,
  double tiltDegPerS = 0,
}) => screenSpeed(
  size: _phone,
  covered: _panels,
  anchor: _anchor,
  latitude: 45.9,
  zoom: zoom,
  tilt: tilt,
  groundMps: kmh / 3.6,
  turnDegPerS: turnDegPerS,
  zoomPerS: zoomPerS,
  tiltDegPerS: tiltDegPerS,
);

double _fps({
  required double kmh,
  required double zoom,
  required double tilt,
  double turnDegPerS = 0,
  double zoomPerS = 0,
  double tiltDegPerS = 0,
}) => cadenceFor(
  _px(
    kmh: kmh,
    zoom: zoom,
    tilt: tilt,
    turnDegPerS: turnDegPerS,
    zoomPerS: zoomPerS,
    tiltDegPerS: tiltDegPerS,
  ),
);

void main() {
  test('a pixel at zoom 17 covers 0.42 m at 45° of latitude, twice that a level out', () {
    expect(metresPerPixel(17, 45), closeTo(0.42, 0.005));
    expect(metresPerPixel(16, 45), closeTo(0.84, 0.01));
  });

  test('a motorway straight at 120 km/h, seen wide, draws ten frames a second', () {
    // AutoZoom.motorwayWide, tilted toward the horizon down the straight:
    // the road slides 15 pixels a second under the vehicle.
    final fps = _fps(kmh: 120, zoom: AutoZoom.motorwayWide, tilt: AutoTilt.straight);
    expect(fps, inInclusiveRange(FrameCadence.minFps, 10.5));
    expect(renderCap(fps), 10);
  });

  test('a road at 80 km/h between two villages draws ten frames a second too', () {
    final fps = _fps(kmh: 80, zoom: wideZoom(80), tilt: AutoTilt.straight);
    expect(renderCap(fps), 10);
  });

  test('a long motorway bend, half a degree a second, draws fifteen; a tighter one, freely', () {
    final gentle = _fps(kmh: 120, zoom: 14.6, tilt: 60, turnDegPerS: 0.5);
    expect(renderCap(gentle), 15);
    // A curve of 1.5 km of radius at 120 km/h: 1.3° a second.
    final bend = _fps(kmh: 120, zoom: 14.6, tilt: 60, turnDegPerS: 1.3);
    expect(bend, greaterThan(15));
    expect(renderCap(bend), isNull);
  });

  test(
    'a street seen close at 50 km/h moves twice the pixels of the motorway, and draws freely',
    () {
      final street = _px(kmh: 50, zoom: closeZoom(50), tilt: AutoTilt.cruise);
      final motorway = _px(kmh: 120, zoom: AutoZoom.motorwayWide, tilt: AutoTilt.straight);
      expect(street, greaterThan(motorway * 2));
      expect(renderCap(cadenceFor(street)), isNull);
    },
  );

  test(
    'a roundabout taken at 25 km/h, the map turning with its ring, draws at the full cadence',
    () {
      // A ring of 15 m of radius at 7 m/s turns the course 26° a second.
      final fps = _fps(kmh: 25, zoom: closeZoom(25), tilt: AutoTilt.roundabout, turnDegPerS: 26);
      expect(fps, FrameCadence.maxFps);
      expect(renderCap(fps), isNull);
    },
  );

  test('a turn sweeps the far road of a tilted map wider than its flat corners', () {
    final tilted = _px(kmh: 0, zoom: 15, tilt: 60, turnDegPerS: 10);
    final flat = _px(kmh: 0, zoom: 15, tilt: 0, turnDegPerS: 10);
    expect(tilted, greaterThan(flat * 1.5));
  });

  test('a change of zoom draws at the full cadence; the end of its ease comes back down', () {
    // Half a level to go, eased over two seconds: a quarter of a level a second.
    expect(_fps(kmh: 120, zoom: 14.6, tilt: 60, zoomPerS: 0.25), FrameCadence.maxFps);
    expect(renderCap(_fps(kmh: 120, zoom: 14.6, tilt: 60, zoomPerS: 0.002)), 10);
  });

  test('a change of tilt as a junction comes draws freely', () {
    // From 52° to 26° over the 180 m before the junction, at 30 km/h.
    final fps = _fps(kmh: 30, zoom: 16.5, tilt: 40, tiltDegPerS: 1.2);
    expect(fps, greaterThan(25));
    expect(renderCap(fps), isNull);
    expect(
      renderCap(_fps(kmh: 30, zoom: 16.5, tilt: 40)),
      10,
      reason: 'the same street, the tilt set',
    );
  });

  test('nothing moving still draws the fewest frames, never fewer', () {
    expect(_fps(kmh: 0, zoom: 17, tilt: 52), FrameCadence.minFps);
  });

  test('a free map only sees the vehicle move: a turn of its course moves no pixel of the map', () {
    double free({double turn = 0}) => screenSpeed(
      size: _phone,
      covered: EdgeInsets.zero,
      anchor: Offset.zero,
      latitude: 45.9,
      zoom: 16,
      tilt: 0,
      groundMps: 10,
      turnDegPerS: turn,
      following: false,
    );
    expect(free(turn: 30), free());
    expect(free(), closeTo(10 / metresPerPixel(16, 45.9), 1e-9));
  });

  test('the engine draws a whole number of the 30 samples a second per frame, or freely', () {
    expect(renderCap(10), 10, reason: 'three samples a frame');
    expect(renderCap(13), 15, reason: 'two samples a frame');
    expect(renderCap(15), 15);
    expect(renderCap(16), isNull, reason: 'between 15 and 30 the steps would be uneven');
    expect(renderCap(FrameCadence.maxFps), isNull);
  });

  group('the pace over time', () {
    const t0 = Duration(seconds: 10);
    const motorway = 15.0;

    test('a gesture brings the full cadence at once, then it comes down over a second', () {
      final pace = FramePace()
        ..next(Duration.zero, pxPerS: motorway)
        ..next(t0, pxPerS: motorway);
      expect(pace.fps, closeTo(10, 0.01));
      expect(pace.next(t0 + const Duration(milliseconds: 100), pxPerS: motorway, full: true), 30);
      expect(
        pace.next(t0 + const Duration(milliseconds: 600), pxPerS: motorway),
        closeTo(20, 0.01),
        reason: 'half a second after: halfway down',
      );
      expect(
        pace.next(t0 + const Duration(milliseconds: 1100), pxPerS: motorway),
        closeTo(10, 0.01),
      );
    });

    test('faster motion is taken at once, slower motion comes down step by step', () {
      final pace = FramePace()
        ..next(Duration.zero, pxPerS: 0)
        ..next(t0, pxPerS: 0);
      expect(pace.fps, FrameCadence.minFps);
      expect(pace.next(t0 + const Duration(milliseconds: 100), pxPerS: 45), 30);
      final fps = pace.next(t0 + const Duration(milliseconds: 200), pxPerS: 0);
      expect(
        fps,
        closeTo(28, 0.01),
        reason: 'a tenth of a second at 20 frames a second per second',
      );
    });

    test('the frames start at the full cadence, before the motion is known', () {
      expect(FramePace().fps, FrameCadence.maxFps);
    });
  });
}
