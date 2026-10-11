import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/features/navigation/presentation/gl_route_map.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
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

RouteMapProps _props(LatLng at, double speedMps) => RouteMapProps(
  style: _aube,
  dark: false,
  lines: [RouteMapLine(index: 0, points: _line, selected: true)],
  vehicle: VehiclePuck(position: at, course: 40, speedMps: speedMps),
  // Following at once: the way in from another view is not what is
  // measured. The zoom and the tilt hold while parked (`GuidanceAim`).
  camera: FollowCamera(position: at, course: 40, ease: Duration.zero),
  guiding: true,
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
    await routeMapImages(_ratio);
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
}
