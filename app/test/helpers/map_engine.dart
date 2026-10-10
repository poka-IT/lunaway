import 'dart:convert';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// The layers of [style], a style document, bottom to top.
List<Map<String, Object?>> styleLayers(String style) => [
  for (final l in (jsonDecode(style) as Map<String, Object?>)['layers']! as List)
    l as Map<String, Object?>,
];

/// MapLibre's channel on a phone, with a style of its own: each layer the
/// map adds goes where the engine puts it (under `belowLayerId`, else on
/// top), so a test reads the order the map draws, the basemap's layers
/// included. Every other call answers nothing.
final class LayerStackEngine extends gl.MapLibreMethodChannel {
  new(String style) : layers = [for (final l in styleLayers(style)) l['id']! as String];

  /// Bottom to top.
  final List<String> layers;

  /// How many layers the map added so far.
  int added = 0;

  bool _created = false;

  /// Takes the place of the platform's engine for the test, until its end.
  void install(WidgetTester tester) {
    const channel = MethodChannel('plugins.flutter.io/maplibre_gl_0');
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, _answer);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final previous = gl.MapLibrePlatform.createInstance;
    gl.MapLibrePlatform.createInstance = () => this;
    addTearDown(() => gl.MapLibrePlatform.createInstance = previous);
  }

  /// The view is made once, as a platform view is, whatever the rebuilds.
  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    gl.OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    if (!_created) {
      _created = true;
      onPlatformViewCreated(0);
    }
    return const SizedBox.expand();
  }

  Future<Object?> _answer(MethodCall call) async {
    final args = call.arguments is Map
        ? call.arguments as Map<Object?, Object?>
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'symbolLayer#add' || 'lineLayer#add' || 'circleLayer#add' || 'fillLayer#add':
        final id = args['layerId']! as String;
        final below = args['belowLayerId'] as String?;
        if (layers.contains(id)) throw PlatformException(code: 'layerExists', message: id);
        added++;
        if (below == null) {
          layers.add(id);
        } else {
          final at = layers.indexOf(below);
          if (at < 0) throw PlatformException(code: 'noLayer', message: below);
          layers.insert(at, id);
        }
      case 'style#removeLayer':
        layers.remove(args['layerId']);
    }
    return null;
  }

  /// The style loaded, then the map's setup until [done]: its images are
  /// drawn on real time, its calls to the engine on the test's clock.
  Future<void> loadStyle(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    onMapStyleLoadedPlatform(null);
    await until(tester, done);
  }
}

/// Waits until [done] on both clocks, a few seconds at most.
Future<void> until(WidgetTester tester, bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!done() && DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Assets that all hold one byte: the pins' images, where what they hold
/// does not matter.
final class BlankAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(1);
}

/// What [drawn] (bottom to top) breaks of [expected]: an id missing, or
/// one drawn over the next.
List<String> outOfOrder(List<String> drawn, List<String> expected) => [
  for (final id in expected)
    if (!drawn.contains(id)) '$id missing',
  for (var i = 1; i < expected.length; i++)
    if (drawn.contains(expected[i - 1]) &&
        drawn.contains(expected[i]) &&
        drawn.indexOf(expected[i - 1]) > drawn.indexOf(expected[i]))
      '${expected[i - 1]} over ${expected[i]}',
];
