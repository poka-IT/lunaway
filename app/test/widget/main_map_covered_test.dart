import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/platform/map_caches.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart';

import '../helpers/map_engine.dart';

/// The main map under a page pushed over it (the route's preview, the
/// guidance): it draws nothing and follows no position there
/// (`plan/research/117-voix-energie-android.md`), and it first lets go of
/// the tiles it keeps beyond its view (`plan/research/139-memoire-android.md`).

final String _aube = File('assets/map/styles/aube.json').readAsStringSync();

/// Whether the last options sent to the engine turn the device's position
/// on; null when none named it.
bool? _locationShown(LayerStackEngine engine) {
  for (final call in engine.calls.reversed) {
    if (call.method != 'map#update') continue;
    final options = (call.arguments as Map<Object?, Object?>)['options'];
    if (options is Map && options.containsKey('myLocationEnabled')) {
      return options['myLocationEnabled'] as bool?;
    }
  }
  return null;
}

int _count(LayerStackEngine engine, String method) =>
    engine.calls.where((c) => c.method == method).length;

/// The Android host's map channel, its calls written in [engine]'s list so
/// a test reads them in order with the engine's.
void _hostInto(WidgetTester tester, LayerStackEngine engine) {
  const channel = MethodChannel('lunaway/map');
  final messenger = tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(channel, (call) async {
      engine.calls.add(call);
      return null;
    });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// The main map on its own page, once ready.
Future<GlobalKey<NavigatorState>> _mainMap(
  WidgetTester tester,
  void Function(LunaMapController) onReady,
) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: GlLunaMap(
        LunaMapProps(
          style: _aube,
          dark: false,
          initialCenter: const LatLng(45.9, 6.13),
          initialZoom: 12,
          places: const [],
          selectedPlace: null,
          onPlaceTap: (_, {hint}) {},
          onLongPress: (_) {},
          onViewportChanged: (_) {},
          onMapReady: onReady,
        ),
      ),
    ),
  );
  await tester.pump();
  return navigator;
}

void main() {
  testWidgets('covered by a page, the main map stops drawing and following the position; '
      'back on screen, it starts again', (tester) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    LunaMapController? map;
    final navigator = await _mainMap(tester, (c) => map = c);
    expect(map, isNotNull);
    // The user showed the position on the map before asking for a route.
    await map!.showPosition(const LatLng(45.9, 6.13));
    await tester.pump();
    expect(_locationShown(engine), isTrue);
    expect(_count(engine, 'map#pause'), 0);

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    await tester.pump(mapCacheReleaseFrame);
    expect(_count(engine, 'map#pause'), 1);
    expect(_locationShown(engine), isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_count(engine, 'map#resume'), 1);
    expect(_locationShown(engine), isTrue);
  });

  testWidgets(
    'on Android, the covered map lets go of its cache and draws a frame before it pauses',
    (tester) async {
      final engine = LayerStackEngine(_aube)..install(tester);
      _hostInto(tester, engine);
      final navigator = await _mainMap(tester, (_) {});

      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      final released = engine.calls.indexWhere((c) => c.method == 'releaseCaches');
      expect(released, isNot(-1));
      // Still drawing: the engine frees the tiles on its next frame.
      expect(_count(engine, 'map#pause'), 0);

      await tester.pump(mapCacheReleaseFrame);
      final paused = engine.calls.indexWhere((c) => c.method == 'map#pause');
      expect(paused, greaterThan(released));
    },
  );

  testWidgets('a page gone before the map paused leaves it drawing', (tester) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    _hostInto(tester, engine);
    final navigator = await _mainMap(tester, (_) {});

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(mapCacheReleaseFrame);
    expect(_count(engine, 'map#pause'), 0);
  });
}
