import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// ThumbHash (Evan Wallace's algorithm, the one the API's media pipeline
/// writes): a photo's colours and shapes in about 25 bytes, drawn while the
/// photo loads so its frame never shows an empty box.
abstract final class ThumbHash {
  /// The width over the height the hash was made from, approximately.
  static double aspectRatio(Uint8List hash) {
    if (hash.length < 5) return 1;
    final header = hash[3];
    final hasAlpha = hash[2] & 0x80 != 0;
    final landscape = hash[4] & 0x80 != 0;
    final lx = landscape ? (hasAlpha ? 5 : 7) : header & 7;
    final ly = landscape ? header & 7 : (hasAlpha ? 5 : 7);
    return ly == 0 ? 1 : lx / ly;
  }

  /// The hash as a small image, at most 32 pixels a side.
  static ({int width, int height, Uint8List rgba}) decode(Uint8List hash) {
    final header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
    final header16 = hash[3] | (hash[4] << 8);
    final lDc = (header24 & 63) / 63;
    final pDc = ((header24 >> 6) & 63) / 31.5 - 1;
    final qDc = ((header24 >> 12) & 63) / 31.5 - 1;
    final lScale = ((header24 >> 18) & 31) / 31;
    final hasAlpha = (header24 >> 23) != 0;
    final pScale = ((header16 >> 3) & 63) / 63;
    final qScale = ((header16 >> 9) & 63) / 63;
    final landscape = (header16 >> 15) != 0;
    final lx = math.max(3, landscape ? (hasAlpha ? 5 : 7) : header16 & 7);
    final ly = math.max(3, landscape ? header16 & 7 : (hasAlpha ? 5 : 7));
    final aDc = hasAlpha ? (hash[5] & 15) / 15 : 1.0;
    final aScale = hasAlpha ? (hash[5] >> 4) / 15 : 0.0;

    final acStart = hasAlpha ? 6 : 5;
    var acIndex = 0;
    List<double> channel(int nx, int ny, double scale) {
      final ac = <double>[];
      for (var cy = 0; cy < ny; cy++) {
        for (var cx = cy == 0 ? 1 : 0; cx * ny < nx * (ny - cy); cx++) {
          final i = acStart + (acIndex >> 1);
          final nibble = i < hash.length
              ? (hash[i] >> ((acIndex & 1) << 2)) & 15
              : 7;
          ac.add((nibble / 7.5 - 1) * scale);
          acIndex++;
        }
      }
      return ac;
    }

    // Saturation boosted 1.25 times, as the reference does, to make up for
    // the quantisation.
    final lAc = channel(lx, ly, lScale);
    final pAc = channel(3, 3, pScale * 1.25);
    final qAc = channel(3, 3, qScale * 1.25);
    final aAc = hasAlpha ? channel(5, 5, aScale) : const <double>[];

    final ratio = aspectRatio(hash);
    final w = (ratio > 1 ? 32 : 32 * ratio).round().clamp(1, 32);
    final h = (ratio > 1 ? 32 / ratio : 32).round().clamp(1, 32);
    final rgba = Uint8List(w * h * 4);
    final fx = List<double>.filled(7, 0);
    final fy = List<double>.filled(7, 0);
    int byte(double v) => (255 * v.clamp(0, 1)).toInt();
    for (var y = 0, i = 0; y < h; y++) {
      for (var x = 0; x < w; x++, i += 4) {
        var l = lDc;
        var p = pDc;
        var q = qDc;
        var a = aDc;
        for (var cx = 0, n = math.max(lx, hasAlpha ? 5 : 3); cx < n; cx++) {
          fx[cx] = math.cos(math.pi / w * (x + 0.5) * cx);
        }
        for (var cy = 0, n = math.max(ly, hasAlpha ? 5 : 3); cy < n; cy++) {
          fy[cy] = math.cos(math.pi / h * (y + 0.5) * cy);
        }
        for (var cy = 0, j = 0; cy < ly; cy++) {
          final fy2 = fy[cy] * 2;
          for (var cx = cy == 0 ? 1 : 0; cx * ly < lx * (ly - cy); cx++, j++) {
            l += lAc[j] * fx[cx] * fy2;
          }
        }
        for (var cy = 0, j = 0; cy < 3; cy++) {
          final fy2 = fy[cy] * 2;
          for (var cx = cy == 0 ? 1 : 0; cx < 3 - cy; cx++, j++) {
            final f = fx[cx] * fy2;
            p += pAc[j] * f;
            q += qAc[j] * f;
          }
        }
        if (hasAlpha) {
          for (var cy = 0, j = 0; cy < 5; cy++) {
            final fy2 = fy[cy] * 2;
            for (var cx = cy == 0 ? 1 : 0; cx < 5 - cy; cx++, j++) {
              a += aAc[j] * fx[cx] * fy2;
            }
          }
        }
        final b = l - 2 / 3 * p;
        final r = (3 * l - b + q) / 2;
        final g = r - q;
        rgba[i] = byte(r);
        rgba[i + 1] = byte(g);
        rgba[i + 2] = byte(b);
        rgba[i + 3] = byte(a);
      }
    }
    return (width: w, height: h, rgba: rgba);
  }

  /// The hash of an image of at most 100 by 100 pixels: the demo and the
  /// tests make theirs this way.
  static Uint8List encode(int w, int h, Uint8List rgba) {
    if (w > 100 || h > 100)
      throw ArgumentError('${w}x$h does not fit in 100x100');
    var avgR = 0.0;
    var avgG = 0.0;
    var avgB = 0.0;
    var avgA = 0.0;
    for (var i = 0, j = 0; i < w * h; i++, j += 4) {
      final alpha = rgba[j + 3] / 255;
      avgR += alpha / 255 * rgba[j];
      avgG += alpha / 255 * rgba[j + 1];
      avgB += alpha / 255 * rgba[j + 2];
      avgA += alpha;
    }
    if (avgA > 0) {
      avgR /= avgA;
      avgG /= avgA;
      avgB /= avgA;
    }
    final hasAlpha = avgA < w * h;
    final lLimit = hasAlpha ? 5 : 7;
    final lx = math.max(1, (lLimit * w / math.max(w, h)).round());
    final ly = math.max(1, (lLimit * h / math.max(w, h)).round());
    final l = List<double>.filled(w * h, 0);
    final p = List<double>.filled(w * h, 0);
    final q = List<double>.filled(w * h, 0);
    final a = List<double>.filled(w * h, 0);
    for (var i = 0, j = 0; i < w * h; i++, j += 4) {
      final alpha = rgba[j + 3] / 255;
      final r = avgR * (1 - alpha) + alpha / 255 * rgba[j];
      final g = avgG * (1 - alpha) + alpha / 255 * rgba[j + 1];
      final b = avgB * (1 - alpha) + alpha / 255 * rgba[j + 2];
      l[i] = (r + g + b) / 3;
      p[i] = (r + g) / 2 - b;
      q[i] = r - g;
      a[i] = alpha;
    }
    (double, List<double>, double) channel(
      List<double> values,
      int nx,
      int ny,
    ) {
      var dc = 0.0;
      final ac = <double>[];
      var scale = 0.0;
      final fx = List<double>.filled(w, 0);
      for (var cy = 0; cy < ny; cy++) {
        for (var cx = 0; cx * ny < nx * (ny - cy); cx++) {
          var f = 0.0;
          for (var x = 0; x < w; x++) {
            fx[x] = math.cos(math.pi / w * cx * (x + 0.5));
          }
          for (var y = 0; y < h; y++) {
            final fy = math.cos(math.pi / h * cy * (y + 0.5));
            for (var x = 0; x < w; x++) {
              f += values[x + y * w] * fx[x] * fy;
            }
          }
          f /= w * h;
          if (cx > 0 || cy > 0) {
            ac.add(f);
            scale = math.max(scale, f.abs());
          } else {
            dc = f;
          }
        }
      }
      if (scale > 0) {
        for (var i = 0; i < ac.length; i++) {
          ac[i] = 0.5 + 0.5 / scale * ac[i];
        }
      }
      return (dc, ac, scale);
    }

    final (lDc, lAc, lScale) = channel(l, math.max(3, lx), math.max(3, ly));
    final (pDc, pAc, pScale) = channel(p, 3, 3);
    final (qDc, qAc, qScale) = channel(q, 3, 3);
    final alphaChannel = hasAlpha ? channel(a, 5, 5) : null;
    final landscape = w > h;
    final header24 =
        (63 * lDc).round() |
        ((31.5 + 31.5 * pDc).round() << 6) |
        ((31.5 + 31.5 * qDc).round() << 12) |
        ((31 * lScale).round() << 18) |
        ((hasAlpha ? 1 : 0) << 23);
    final header16 =
        (landscape ? ly : lx) |
        ((63 * pScale).round() << 3) |
        ((63 * qScale).round() << 9) |
        ((landscape ? 1 : 0) << 15);
    final hash = <int>[
      header24 & 255,
      (header24 >> 8) & 255,
      header24 >> 16,
      header16 & 255,
      header16 >> 8,
    ];
    final acStart = hasAlpha ? 6 : 5;
    var acIndex = 0;
    if (alphaChannel != null) {
      hash.add(
        (15 * alphaChannel.$1).round() | ((15 * alphaChannel.$3).round() << 4),
      );
    }
    for (final ac in [lAc, pAc, qAc, ?alphaChannel?.$2]) {
      for (final f in ac) {
        final i = acStart + (acIndex >> 1);
        while (hash.length <= i) {
          hash.add(0);
        }
        hash[i] |= (15 * f).round() << ((acIndex & 1) << 2);
        acIndex++;
      }
    }
    return Uint8List.fromList(hash);
  }

  /// The bytes of a base64 hash as the API writes it; null when malformed.
  static Uint8List? fromBase64(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final bytes = base64.decode(base64.normalize(text));
      return bytes.length < 5 ? null : bytes;
    } on FormatException {
      return null;
    }
  }
}

/// A ThumbHash drawn as an image: the placeholder of a photo.
@immutable
final class ThumbHashImage extends ImageProvider<ThumbHashImage> {
  const new(this.hash);

  /// The hash, base64, as the API sends it.
  final String hash;

  @override
  Future<ThumbHashImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ThumbHashImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final bytes = ThumbHash.fromBase64(hash);
    if (bytes == null) throw ArgumentError('not a thumbhash: $hash');
    final image = ThumbHash.decode(bytes);
    final buffer = await ui.ImmutableBuffer.fromUint8List(image.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    descriptor.dispose();
    buffer.dispose();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is ThumbHashImage && other.hash == hash;

  @override
  int get hashCode => hash.hashCode;
}
