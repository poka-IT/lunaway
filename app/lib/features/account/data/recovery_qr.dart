import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;
import 'package:lunaway/features/account/domain/recovery_code.dart';
import 'package:zxing2/qrcode.dart';

/// The QR code of a recovery card: the code itself, nothing else (no link,
/// no host), so scanning it only fills the field of the app.
List<List<bool>> recoveryQrModules(String code) {
  final matrix = Encoder.encode(code, ErrorCorrectionLevel.q).matrix!;
  return [
    for (var y = 0; y < matrix.height; y++)
      [for (var x = 0; x < matrix.width; x++) matrix.get(x, y) == 1],
  ];
}

/// The longest side a card picture is read at: a phone photo is far
/// larger than the code needs, and a smaller picture is read faster and as
/// well.
const qrReadSide = 1200;

/// The recovery code in a picture of a card (a photo of the paper card, or
/// the image the app saved), or null when no valid code is found. The
/// platform's decoder reads the picture straight at [qrReadSide] (the
/// browser's on the web, off the main thread elsewhere), so a 50 megapixel
/// photo never sits whole in memory; the code is then looked for in a
/// background isolate. Nothing leaves the device.
Future<String?> readRecoveryCard(Uint8List picture) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  final ({int width, int height, Uint8List rgba}) pixels;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(picture);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = min(1, qrReadSide / max(descriptor.width, descriptor.height));
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    // A truncated picture fails here, at the first frame: no code read.
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData();
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    if (data == null) return null;
    pixels = (width: width, height: height, rgba: data.buffer.asUint8List());
  } on Object {
    return null;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
  return await compute(readRecoveryQrPixels, pixels);
}

/// [readRecoveryCard] for a picture Dart decodes itself (the tests).
String? readRecoveryQr(Uint8List picture) {
  final decoded = img.decodeImage(picture);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  if (max(image.width, image.height) > qrReadSide) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? qrReadSide : null,
      height: image.height > image.width ? qrReadSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  final rgba = image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  return readRecoveryQrPixels((width: image.width, height: image.height, rgba: rgba));
}

/// The recovery code in RGBA pixels, or null.
String? readRecoveryQrPixels(({int width, int height, Uint8List rgba}) picture) {
  final rgba = picture.rgba;
  // zxing takes one int per pixel; only the luminance it computes matters.
  final pixels = Int32List(picture.width * picture.height);
  for (var i = 0; i < pixels.length; i++) {
    final o = i * 4;
    pixels[i] = (0xFF << 24) | (rgba[o] << 16) | (rgba[o + 1] << 8) | rgba[o + 2];
  }
  final source = RGBLuminanceSource(picture.width, picture.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final bitmap in [
    BinaryBitmap(HybridBinarizer(source)),
    BinaryBitmap(GlobalHistogramBinarizer(source)),
  ]) {
    try {
      final text = QRCodeReader().decode(bitmap, hints: hints).text;
      final code = RecoveryCode.parse(text);
      if (code != null) return code;
    } on ReaderException {
      // Not found with this binarizer: the next one may read it.
    }
  }
  return null;
}
