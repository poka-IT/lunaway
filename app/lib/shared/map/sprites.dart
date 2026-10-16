import 'package:flutter/services.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';

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

  /// Whether the image [id] goes into a native map only when a pin first
  /// shows selected with it (a place's, a point's), rather than with the
  /// others at the style's setup: one shows at a time, and the engine kept
  /// the hundred of them decoded, 11 MB at the 3x ratio
  /// (`plan/research/139-memoire-android.md`).
  static bool onDemand(String id) => id.endsWith('-selected');

  static final Map<int, Future<Map<String, Uint8List>>> _loaded = {};

  /// Every pin image at [ratio], by image id: the places' and the points of
  /// interest's.
  static Future<Map<String, Uint8List>> load(int ratio, {AssetBundle? bundle}) =>
      _loaded.putIfAbsent(ratio, () async {
        final assets = bundle ?? rootBundle;
        final ids = [...allPinImageIds(), ...PoiMapStyle.allImageIds()];
        // Read together: one after the other, two hundred reads (each a
        // request on the web) held the map's first places back.
        final bytes = await Future.wait([
          for (final id in ids) assets.load('assets/map/pins/${ratio}x/$id.png'),
        ]);
        return {for (final (i, id) in ids.indexed) id: bytes[i].buffer.asUint8List()};
      });
}
