import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/auto_zoom.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/shared/map/sprites.dart';

import '../helpers/map_engine.dart';

/// The guidance map's frames on a phone: what it asks of the map engine and
/// of Flutter while the vehicle drives and while it is parked
/// (`plan/research/117-voix-energie-android.md`).

final String _aube = File('assets/map/styles/aube.json').readAsStringSync();

const _ratio = 3.0;

final _line = [const LatLng(44.93, 4.89), const LatLng(44.94, 4.90), const LatLng(44.95, 4.91)];

/// Draws no mark: the passes are counted by what they ask of the map.
final class _NoArt implements RichArt {
  @override
  RichPlan? plan(PlaceSummary place, RichStyle style, {bool ask = true, VoidCallback? onReady}) =>
      null;

  @override
  Future<RichArtwork?> draw(
    PlaceSummary place,
    RichPlan plan, {
    required double size,
    required double ratio,
    required RichStyle style,
  }) async => null;
}

final _art = _NoArt();

final _words = RichWords(
  free: 'Gratuit',
  nightOk: 'Nuit OK',
  price: (e) => '$e',
  rating: (r) => '$r',
);

RouteMapProps _props(
  LatLng at,
  double speedMps, {
  double zoom = AutoZoom.parkedZoom,
  double tilt = AutoTilt.cruise,
  RouteCamera? camera,
  bool guiding = true,
}) => RouteMapProps(
  style: _aube,
  dark: false,
  lines: [RouteMapLine(index: 0, points: _line, selected: true)],
  vehicle: VehiclePuck(position: at, course: 40, speedMps: speedMps),
  // Following at once: the way in from another view is not what is
  // measured. The zoom and the tilt hold while parked (`GuidanceAim`).
  camera:
      camera ?? FollowCamera(position: at, course: 40, zoom: zoom, tilt: tilt, ease: Duration.zero),
  guiding: guiding,
  places: const RouteMapPlaces(
    placeTileJsonUrl: 'https://api.example/places/tiles.json',
    poiTileJsonUrl: 'https://api.example/poi/tiles.json',
    placeFilter: ['has', 'kind'],
    poiFilter: ['has', 'kind'],
  ),
  // The places of the tiles in view, as the guidance has them online;
  // where the vehicle is changes with each fix.
  rich: RouteMapRich(
    style: RichStyle(look: GuidanceLook.photos, words: _words),
    art: _art,
    tiles: true,
    speedMps: speedMps,
    vehicleAlongM: at.distanceTo(_line.first),
  ),
);

/// The questions the rich marks' passes ask the map: the places of the
/// tiles in view.
int _placeQueries(LayerStackEngine engine) =>
    engine.calls.where((c) => c.method == 'map#queryRenderedFeatures').length;

/// The calls that draw a frame of the glide: the camera moved, the vehicle
/// moved.
int _frameCalls(LayerStackEngine engine) => engine.calls
    .where(
      (c) =>
          c.method == 'camera#move' ||
          (c.method == 'source#setGeoJson' &&
              (c.arguments as Map<Object?, Object?>)['sourceId'] == RouteLayers.vehicleSource),
    )
    .length;

/// Lets [real] time pass for the glide's clock, the test's clock firing the
/// frames' timer meanwhile.
Future<void> _wait(WidgetTester tester, Duration real) async {
  final end = DateTime.now().add(real);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 34));
  }
}

void main() {
  setUpAll(() async {
    await routeBadgePngs(_ratio);
    await PinSprites.load(PinSprites.ratioFor(_ratio), bundle: BlankAssets());
  });

  Future<LayerStackEngine> drawn(WidgetTester tester, LatLng at, double speedMps) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    expect(tester.view.devicePixelRatio, _ratio);
    await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(at, speedMps))));
    await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
    // The first fix drawn and the zoom settled.
    await _wait(tester, const Duration(milliseconds: 600));
    return engine;
  }

  testWidgets(
    'the guidance map places its labels without fading them; the preview keeps its fades',
    (tester) async {
      final asked = <Map<Object?, Object?>>[];
      const channel = MethodChannel('lunaway/map');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'labelFades') asked.add(call.arguments as Map<Object?, Object?>);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      const at = LatLng(44.94, 4.90);
      final engine = LayerStackEngine(_aube)..install(tester);
      await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(at, 0, guiding: false))));
      await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
      await tester.pump();
      expect(asked, isEmpty, reason: "the preview's labels fade as the style has them");
      // The source that names this map to the Android host.
      final tag = engine.calls
          .map((c) => c.arguments)
          .whereType<Map<Object?, Object?>>()
          .map((a) => a['sourceId'])
          .whereType<String>()
          .firstWhere((id) => id.startsWith('lw-route-tag-'));
      await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(at, 0))));
      await tester.pump();
      expect(asked, [
        {'source': tag, 'on': false},
      ]);
      await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(at, 0, guiding: false))));
      await tester.pump();
      expect(asked.last, {
        'source': tag,
        'on': true,
      }, reason: 'the guidance over, the fades come back');
    },
  );

  testWidgets('a parked vehicle whose fixes wander a few metres draws nothing', (tester) async {
    const parked = LatLng(44.94, 4.90);
    final engine = await drawn(tester, parked, 0);
    final before = _frameCalls(engine);
    // The receiver of a parked phone: a fix a second, metres apart, at a
    // speed under a walk.
    for (final (i, (dLat, dLon)) in [
      (0.00003, 0.0),
      (-0.00004, 0.00002),
      (0.00001, -0.00005),
      (0.00006, 0.00003),
    ].indexed) {
      final at = LatLng(parked.lat + dLat, parked.lon + dLon);
      await tester.pumpWidget(MaterialApp(home: GlRouteMap(_props(at, 0.2 + i * 0.2))));
      await _wait(tester, const Duration(milliseconds: 250));
    }
    expect(_frameCalls(engine), before, reason: 'no glide, no camera moved, nothing sent');
  });

  testWidgets('parked, the fixes ask the map for no place; the map gone idle does, once a while', (
    tester,
  ) async {
    const parked = LatLng(44.94, 4.90);
    final engine = await drawn(tester, parked, 0);
    // The pass of the start, then none while the fixes wander.
    await _wait(tester, const Duration(milliseconds: 800));
    final before = _placeQueries(engine);
    for (final dLat in [0.00003, -0.00004, 0.00002]) {
      await tester.pumpWidget(
        MaterialApp(home: GlRouteMap(_props(LatLng(parked.lat + dLat, parked.lon), 0.3))),
      );
      await _wait(tester, const Duration(milliseconds: 800));
    }
    expect(_placeQueries(engine), before, reason: 'nothing moved on the map');
    // The places' tiles came late: the map goes idle once they are drawn.
    engine.onMapIdlePlatform(null);
    await _wait(tester, const Duration(milliseconds: 800));
    expect(_placeQueries(engine), before + 1);
    // Idle again at once (the pass redrew a mark): not asked again yet.
    engine.onMapIdlePlatform(null);
    await _wait(tester, const Duration(milliseconds: 800));
    expect(_placeQueries(engine), before + 1);
  });

  testWidgets('the vehicle sets off: it glides again', (tester) async {
    const parked = LatLng(44.94, 4.90);
    final engine = await drawn(tester, parked, 0);
    final before = _frameCalls(engine);
    // 8 m on, at 8 m/s: driving off, within the wander of a parked fix.
    await tester.pumpWidget(
      MaterialApp(home: GlRouteMap(_props(const LatLng(44.94005, 4.90005), 8))),
    );
    await _wait(tester, const Duration(milliseconds: 300));
    expect(_frameCalls(engine), greaterThan(before + 2));
  });

  testWidgets('while it glides, the map gets its frames and Flutter is asked for none', (
    tester,
  ) async {
    final engine = await drawn(tester, const LatLng(44.94, 4.90), 15);
    await tester.pumpWidget(
      MaterialApp(home: GlRouteMap(_props(const LatLng(44.9402, 4.9002), 15))),
    );
    final before = _frameCalls(engine);
    var asked = 0;
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      // Time passes for the timers without a frame of Flutter's.
      await tester.binding.delayed(const Duration(milliseconds: 34));
      if (tester.binding.hasScheduledFrame) asked++;
    }
    expect(_frameCalls(engine), greaterThan(before + 5), reason: 'the glide goes on');
    expect(asked, 0, reason: "each frame of the glide is the map's alone");
  });

  group("the engine's limit of frames", () {
    // 120 km/h, a fix a second 33 m on along the course, the view of a
    // motorway straight (zoom 14.6, tilt 60): about 15 pixels a second.
    const start = LatLng(44.94, 4.90);
    LatLng ahead(int i) =>
        LatLng(start.lat + i * 33 * 0.766 / 111195, start.lon + i * 33 * 0.643 / 78700);
    RouteMapProps motorway(LatLng at) => _props(at, 33, zoom: 14.6, tilt: 60);

    /// The guidance on a phone held upright (411 x 914 logical pixels), the
    /// vehicle driven for two seconds: the limit has come down to ten.
    Future<(LayerStackEngine, _Drive)> driving(WidgetTester tester) async {
      tester.view.physicalSize = const Size(411 * _ratio, 914 * _ratio);
      addTearDown(tester.view.resetPhysicalSize);
      final engine = LayerStackEngine(_aube, touchable: true)..install(tester);
      await tester.pumpWidget(MaterialApp(home: GlRouteMap(motorway(start))));
      await engine.loadStyle(tester, () => engine.layers.contains('lw-route-vehicle'));
      var fix = 0;
      Future<void> drive(Duration time, {RouteMapProps Function(LatLng)? props}) async {
        final end = DateTime.now().add(time);
        await tester.pumpWidget(MaterialApp(home: GlRouteMap((props ?? motorway)(ahead(++fix)))));
        while (DateTime.now().isBefore(end)) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 34));
        }
      }

      // The start draws freely until the motion is known; the cadence
      // comes down within a second.
      await drive(const Duration(seconds: 1));
      await drive(const Duration(seconds: 1));
      expect(_limits(engine).last, 10);
      return (engine, drive);
    }

    testWidgets(
      'down a motorway seen wide the engine draws ten frames a second; a finger frees it',
      (tester) async {
        final (engine, drive) = await driving(tester);
        final sent = _vehicleFrames(engine);
        await drive(const Duration(milliseconds: 600));
        expect(
          _vehicleFrames(engine) - sent,
          greaterThan(10),
          reason: 'the app still sends the glide 30 times a second: each frame shows the latest',
        );
        final limited = _limits(engine).length;
        final finger = await tester.startGesture(tester.getCenter(find.byType(GlRouteMap)));
        await tester.pump();
        expect(_limits(engine).skip(limited), [1000], reason: 'free at once under a finger');
        await drive(const Duration(milliseconds: 500));
        await finger.up();
        // Lifted: back down to ten within a second, never up on the way.
        await drive(const Duration(seconds: 1));
        await drive(const Duration(seconds: 1));
        final after = _limits(engine).skip(limited).toList();
        expect(after.first, 1000);
        expect(after.last, 10);
        for (var i = 1; i < after.length; i++) {
          expect(after[i], lessThan(after[i - 1]), reason: 'down step by step: $after');
        }
      },
    );

    testWidgets('the whole route shown, its animation draws freely', (tester) async {
      final (engine, drive) = await driving(tester);
      final whole = FitCamera(GeoBounds.around(_line)!);
      await drive(
        const Duration(milliseconds: 100),
        props: (at) => _props(at, 33, zoom: 14.6, tilt: 60, camera: whole),
      );
      expect(_limits(engine).last, 1000);
    });

    testWidgets('the guidance over, the map left on the screen draws freely', (tester) async {
      final (engine, _) = await driving(tester);
      // The glide to the last fix (the second) over, the frames stopped:
      // nothing but the end of the guidance changes.
      await _wait(tester, const Duration(milliseconds: 500));
      final frames = _vehicleFrames(engine);
      await tester.pumpWidget(
        MaterialApp(home: GlRouteMap(_props(ahead(2), 33, zoom: 14.6, tilt: 60, guiding: false))),
      );
      await tester.pump();
      expect(_vehicleFrames(engine), frames, reason: 'no frame of the glide sets the limit');
      expect(_limits(engine).last, 1000);
    });

    testWidgets('parked, the engine draws freely what it draws by itself', (tester) async {
      final (engine, drive) = await driving(tester);
      await drive(
        const Duration(milliseconds: 100),
        props: (at) => _props(at, 0.3, zoom: 14.6, tilt: 60),
      );
      expect(_limits(engine).last, 1000);
    });
  });
}

/// Drives the vehicle a fix on, then lets [Duration] pass; [props] gives
/// the map's at that fix.
typedef _Drive = Future<void> Function(Duration, {RouteMapProps Function(LatLng)? props});

/// The limits of frames the map gave the engine, in order (1000: none).
List<int> _limits(LayerStackEngine engine) => [
  for (final c in engine.calls)
    if (c.method == 'map#setMaximumFps') (c.arguments as Map<Object?, Object?>)['fps']! as int,
];

/// The frames that moved the vehicle.
int _vehicleFrames(LayerStackEngine engine) => engine.calls
    .where(
      (c) =>
          c.method == 'source#setGeoJson' &&
          (c.arguments as Map<Object?, Object?>)['sourceId'] == RouteLayers.vehicleSource,
    )
    .length;
