import 'dart:async';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// The engine's channel, which records what the map asks of the platform
/// view instead of making one.
final class _Recorder extends gl.MapLibreMethodChannel {
  Map<String, dynamic>? params;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    gl.OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    params = creationParams;
    // The channel the map closes when it goes, answered by the test.
    unawaited(initPlatform(0));
    return const SizedBox.expand();
  }
}

void main() {
  testWidgets(
    "the engine's blue info button is out of the map on Android and iOS",
    variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}),
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/maplibre_gl_0');
      final messenger = tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final recorder = _Recorder();
      final previous = gl.MapLibrePlatform.createInstance;
      gl.MapLibrePlatform.createInstance = () => recorder;
      addTearDown(() => gl.MapLibrePlatform.createInstance = previous);
      await tester.pumpWidget(
        MaterialApp(
          home: GlLunaMap(
            LunaMapProps(
              style: '{"version":8,"sources":{},"layers":[]}',
              dark: false,
              initialCenter: const LatLng(46.6, 2.5),
              initialZoom: 5,
              places: const [],
              selectedPlace: null,
              onPlaceTap: (_, {hint}) {},
              onLongPress: (_) {},
              onViewportChanged: (_) {},
              onMapReady: (_) {},
              attributionInset: const EdgeInsets.only(left: 8, bottom: 170),
            ),
          ),
        ),
      );
      final options = recorder.params!['options'] as Map<String, dynamic>;
      final margins = (options['attributionButtonMargins'] as List).cast<num>();
      // Beyond the map's bottom left corner, whatever the sheet's inset:
      // the app's own credit (MapCredit) stands alone in that corner.
      expect(margins[0], lessThan(-100));
      expect(margins[1], lessThan(-100));
    },
  );
}
