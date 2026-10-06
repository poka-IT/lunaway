import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:lunaway/features/community/data/photo_prepare.dart';

PhotoPreparer platformPhotoPreparer() => const IsolatePhotoPreparer();

/// Decodes, turns, resizes and re-encodes in a background isolate, so the
/// screen keeps moving while a large photo is prepared. A format Dart does
/// not decode (HEIC, which the system pickers of Android and iOS already
/// convert) goes through the engine's decoder first.
final class IsolatePhotoPreparer implements PhotoPreparer {
  const new();

  @override
  Future<PreparedPhoto> prepare(Uint8List original) async {
    final prepared = await compute(prepareJpeg, original);
    if (prepared != null) return prepared;
    final pixels = await _engineDecode(original);
    return await compute(encodePixels, pixels);
  }

  /// The picture through the platform's codecs, at most [PhotoPreparer.maxSide].
  static Future<({int width, int height, Uint8List rgba})> _engineDecode(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = min(1, PhotoPreparer.maxSide / max(descriptor.width, descriptor.height));
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      // A truncated file fails here, at the first frame.
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      if (data == null) throw const UnreadablePhotoException('no pixels');
      return (width: width, height: height, rgba: data.buffer.asUint8List());
    } on UnreadablePhotoException {
      rethrow;
    } on Object catch (e) {
      throw UnreadablePhotoException('$e');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// Above this many pixels a picture goes through the engine's decoder,
/// which shrinks it while decoding: decoded whole by Dart it would take
/// four bytes a pixel (a 100 megapixel file, 400 MB). A modest phone camera
/// stays under it.
const int maxDartPixels = 24 * 1000 * 1000;

/// The JPEG to send, or null when Dart cannot decode [original] or should
/// not (larger than [maxDartPixels], read from its header alone).
@visibleForTesting
PreparedPhoto? prepareJpeg(Uint8List original) {
  final info = img.findDecoderForData(original)?.startDecode(original);
  if (info == null || info.width * info.height > maxDartPixels) return null;
  // The first frame only: an animated picture would otherwise be decoded
  // frame after frame at its full size.
  final decoded = img.decodeImage(original, frame: 0);
  if (decoded == null) return null;
  return _finish(img.bakeOrientation(decoded));
}

@visibleForTesting
PreparedPhoto encodePixels(({int width, int height, Uint8List rgba}) pixels) => _finish(
  img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ),
);

PreparedPhoto _finish(img.Image image) {
  var out = image;
  if (max(out.width, out.height) > PhotoPreparer.maxSide) {
    out = img.copyResize(
      out,
      width: out.width >= out.height ? PhotoPreparer.maxSide : null,
      height: out.height > out.width ? PhotoPreparer.maxSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  if (out.hasAlpha) {
    // A transparent picture lands on white, as the server would flatten it.
    final flat = img.Image(width: out.width, height: out.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    out = img.compositeImage(flat, out);
  }
  // Nothing of the original file travels: no position, no date, no model.
  out
    ..exif = img.ExifData()
    ..iccProfile = null;
  final jpeg = img.encodeJpg(out, quality: PhotoPreparer.quality, chroma: img.JpegChroma.yuv420);
  return PreparedPhoto(jpeg: jpeg, width: out.width, height: out.height);
}
