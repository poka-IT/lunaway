import 'package:flutter/services.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';

/// The pin images rendered ahead of time by tool/map_sprites/, one set per
/// pixel ratio, loaded by both map engines.
abstract final class PinSprites {
  /// The ratios the app ships; a screen denser than the last uses the last,
  /// a 1x screen the 2x set scaled down (a third of the weight saved for few
  /// screens).
  static const ratios = [2, 3];

  /// The smallest shipped ratio at least as dense as [devicePixelRatio], so a
  /// pin is never upscaled.
  static int ratioFor(double devicePixelRatio) =>
      ratios.firstWhere((r) => r >= devicePixelRatio - 0.05, orElse: () => ratios.last);

  static final Map<int, Future<Map<String, Uint8List>>> _loaded = {};

  /// Every pin image at [ratio], by image id.
  static Future<Map<String, Uint8List>> load(int ratio, {AssetBundle? bundle}) =>
      _loaded.putIfAbsent(ratio, () async {
        final assets = bundle ?? rootBundle;
        return {
          for (final id in allPinImageIds())
            id: (await assets.load('assets/map/pins/${ratio}x/$id.png')).buffer.asUint8List(),
        };
      });
}
