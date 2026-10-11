import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart';

import '../helpers/map_engine.dart';

/// The main map under a page pushed over it (the route's preview, the
/// guidance): it draws nothing and follows no position there
/// (`plan/research/117-voix-energie-android.md`).

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

void main() {
  testWidgets('covered by a page, the main map stops drawing and following the position; '
      'back on screen, it starts again', (tester) async {
    final engine = LayerStackEngine(_aube)..install(tester);
    final navigator = GlobalKey<NavigatorState>();
    LunaMapController? map;
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
            onMapReady: (c) => map = c,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(map, isNotNull);
    // The user showed the position on the map before asking for a route.
    await map!.showPosition(const LatLng(45.9, 6.13));
    await tester.pump();
    expect(_locationShown(engine), isTrue);
    expect(_count(engine, 'map#pause'), 0);

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(_count(engine, 'map#pause'), 1);
    expect(_locationShown(engine), isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_count(engine, 'map#resume'), 1);
    expect(_locationShown(engine), isTrue);
  });
}
