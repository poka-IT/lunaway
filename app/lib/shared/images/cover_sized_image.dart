import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// [image] decoded no larger than what covers a box of [width] by [height]
/// device pixels, as `BoxFit.cover` paints it: the picture keeps its
/// proportions, its shorter side against the box, never enlarged. Decoded
/// whole, a photo of 2 560 pixels the user just took holds 19 MB for a
/// thumbnail of 96 by 72 points. `ResizeImage` fits a box or fixes a side;
/// covering one whose photo may stand either way needs the photo's own
/// size, which the decoder gives here.
@immutable
final class CoverSizedImage extends ImageProvider<CoverSizedKey> {
  const new(this.image, {required this.width, required this.height});

  /// What a box of [size] logical pixels takes on a screen of [pixelRatio].
  new forBox(ImageProvider image, Size size, double pixelRatio)
    : this(
        image,
        width: math.max(1, (size.width * pixelRatio).ceil()),
        height: math.max(1, (size.height * pixelRatio).ceil()),
      );

  final ImageProvider image;
  final int width;
  final int height;

  @override
  Future<CoverSizedKey> obtainKey(ImageConfiguration configuration) =>
      // A synchronous key stays synchronous: the image cache answers in the
      // same frame.
      image.obtainKey(configuration).then((key) => CoverSizedKey._(key, width, height));

  @override
  ImageStreamCompleter loadImage(CoverSizedKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> covering(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) => decode(
      buffer,
      getTargetSize: (w, h) => coverSize(w, h, width: width, height: height),
    );
    return image.loadImage(key._inner, covering);
  }

  @override
  bool operator ==(Object other) =>
      other is CoverSizedImage &&
      other.image == image &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(image, width, height);
}

/// The key of a [CoverSizedImage] in the image cache: the photo's own key
/// and the box.
@immutable
final class CoverSizedKey {
  const new _(this._inner, this._width, this._height);

  final Object _inner;
  final int _width;
  final int _height;

  @override
  bool operator ==(Object other) =>
      other is CoverSizedKey &&
      other._inner == _inner &&
      other._width == _width &&
      other._height == _height;

  @override
  int get hashCode => Object.hash(_inner, _width, _height);
}

/// The size a picture of [intrinsicWidth] by [intrinsicHeight] decodes to
/// so that it covers [width] by [height]: scaled down until one side meets
/// the box, the other overflowing it; never scaled up.
@visibleForTesting
ui.TargetImageSize coverSize(
  int intrinsicWidth,
  int intrinsicHeight, {
  required int width,
  required int height,
}) {
  final scale = math.min(1, math.max(width / intrinsicWidth, height / intrinsicHeight));
  return ui.TargetImageSize(
    width: math.max(1, (intrinsicWidth * scale).ceil()),
    height: math.max(1, (intrinsicHeight * scale).ceil()),
  );
}
