import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:lunaway/core/geo/geo.dart';

/// The camera centre that puts [target] in the middle of the part of the map
/// left visible by [padding] (a sheet over the bottom, a panel on the side),
/// at [zoom]. Web Mercator with 512-pixel tiles, as MapLibre uses.
LatLng centerForPadding(LatLng target, double zoom, EdgeInsets padding) {
  if (padding == EdgeInsets.zero) return target;
  final world = 512 * math.pow(2, zoom).toDouble();
  final x = (target.lon + 180) / 360 * world;
  final sinLat = math.sin(target.lat * math.pi / 180).clamp(-0.9999, 0.9999);
  final y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * world;
  final cx = x + (padding.right - padding.left) / 2;
  final cy = y + (padding.bottom - padding.top) / 2;
  final lon = cx / world * 360 - 180;
  final n = math.pi - 2 * math.pi * cy / world;
  final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  return LatLng(lat, lon);
}
