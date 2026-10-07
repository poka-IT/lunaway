import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform;
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

/// The camera that shows [bounds] whole in the part of a map of [size] left
/// visible by [padding], no closer than [maxZoom].
///
/// Computed here rather than with MapLibre's bounds update: on Android and
/// iOS that update leaves its padding on the camera, so every later move
/// would centre on the part of the map that was free at the time of the fit
/// (a target then lands under the search bar once a sheet has risen).
({LatLng center, double zoom}) cameraForBounds(
  GeoBounds bounds,
  Size size,
  EdgeInsets padding, {
  double maxZoom = 18,
}) {
  double mercatorY(double lat) {
    final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  final x0 = (bounds.west + 180) / 360;
  final x1 = (bounds.east + 180) / 360;
  final y0 = mercatorY(bounds.north);
  final y1 = mercatorY(bounds.south);
  // A padding larger than the map (a window being resized) leaves one
  // pixel, rather than a negative size.
  final width = math.max(size.width - padding.horizontal, 1);
  final height = math.max(size.height - padding.vertical, 1);
  final spanX = math.max(x1 - x0, 1e-9);
  final spanY = math.max(y1 - y0, 1e-9);
  final zoom = math
      .min(math.log(width / (512 * spanX)) / math.ln2, math.log(height / (512 * spanY)) / math.ln2)
      .clamp(0.0, maxZoom);
  final cy = (y0 + y1) / 2;
  final n = math.pi - 2 * math.pi * cy;
  final middle = LatLng(
    180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))),
    (x0 + x1) / 2 * 360 - 180,
  );
  return (center: centerForPadding(middle, zoom, padding), zoom: zoom);
}

/// Where [point] falls down a map of [height] pixels that shows [visible],
/// from its top; Web Mercator, as the engines draw it.
double screenYOf(LatLng point, GeoBounds visible, double height) {
  double mercatorY(double lat) {
    final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  final top = mercatorY(visible.north);
  final span = math.max(mercatorY(visible.south) - top, 1e-12);
  return (mercatorY(point.lat) - top) / span * height;
}

/// How many of the map engine's screen units make one logical pixel, for
/// the rectangles the app hands to the engine's feature queries. MapLibre
/// Android counts the physical pixels of its view (the points of its taps
/// come in them too); MapLibre iOS counts points and MapLibre GL JS CSS
/// pixels, both logical.
double mapQueryScale({
  required bool web,
  required TargetPlatform platform,
  required double devicePixelRatio,
}) => !web && platform == TargetPlatform.android ? devicePixelRatio : 1;
