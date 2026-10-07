import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// The icons of the basemap (one-way arrows, road shields, town dots) of a
/// theme, cut from the sprite sheets the app carries for offline maps
/// (`assets/map/offline/sprites/`). When the theme turns without loading
/// the style again, MapLibre Native keeps the other theme's images; the
/// map adds these under the same names, which replaces them.
abstract final class BasemapIcons {
  static final Map<(bool, int), Future<Map<String, Uint8List>>> _loaded = {};

  /// Every icon of the [dark] or light sheet as PNG bytes of [pixelRatio]
  /// pixels per logical pixel: MapLibre Native reads the pixels of an image
  /// the plugin adds as physical ones.
  static Future<Map<String, Uint8List>> load({
    required bool dark,
    required double pixelRatio,
    AssetBundle? bundle,
  }) {
    // The ratio in tenths: a key that compares, close enough for a sheet.
    final key = (dark, (pixelRatio * 10).round());
    return _loaded.putIfAbsent(key, () => _cut(dark: dark, pixelRatio: pixelRatio, bundle: bundle));
  }

  static Future<Map<String, Uint8List>> _cut({
    required bool dark,
    required double pixelRatio,
    AssetBundle? bundle,
  }) async {
    final assets = bundle ?? rootBundle;
    final name = dark ? 'dark' : 'light';
    final index = jsonDecode(
      await assets.loadString('assets/map/offline/sprites/$name@2x.json', cache: false),
    ) as Map<String, Object?>;
    final bytes = await assets.load('assets/map/offline/sprites/$name@2x.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final sheet = (await codec.getNextFrame()).image;
    final out = <String, Uint8List>{};
    try {
      for (final MapEntry(key: id, :value) in index.entries) {
        if (value is! Map) continue;
        final x = (value['x'] as num).toDouble();
        final y = (value['y'] as num).toDouble();
        final w = (value['width'] as num).toDouble();
        final h = (value['height'] as num).toDouble();
        final sheetRatio = (value['pixelRatio'] as num?)?.toDouble() ?? 2;
        final scale = pixelRatio / sheetRatio;
        final width = (w * scale).round().clamp(1, 1024);
        final height = (h * scale).round().clamp(1, 1024);
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImageRect(
          sheet,
          ui.Rect.fromLTWH(x, y, w, h),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final image = await recorder.endRecording().toImage(width, height);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (png != null) out[id] = png.buffer.asUint8List();
      }
    } finally {
      sheet.dispose();
    }
    return out;
  }
}
