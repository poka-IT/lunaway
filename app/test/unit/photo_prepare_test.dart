import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/data/photo_prepare_io.dart';

/// A camera JPEG of 3000 x 2000 stored pixels, held sideways (EXIF
/// orientation 6: turn a quarter clockwise to view), with a position, a
/// date and a camera model in its metadata. Its stored top-left quarter is
/// red, the rest blue.
Uint8List cameraJpeg() {
  final image = img.Image(width: 3000, height: 2000)
    ..clear(img.ColorRgb8(0, 0, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 1499,
    y2: 999,
    color: img.ColorRgb8(255, 0, 0),
  );
  image.exif.imageIfd
    ..orientation = 6
    ..['Model'] = img.IfdValueAscii('Pixel 9 Pro')
    ..['DateTime'] = img.IfdValueAscii('2026:10:06 07:42:00');
  image.exif.gpsIfd
    ..['GPSLatitudeRef'] = img.IfdValueAscii('N')
    ..['GPSLatitude'] = img.IfdValueRational(4554, 100);
  return img.encodeJpg(image, quality: 90);
}

void main() {
  final original = cameraJpeg();

  test('the sample carries what a camera writes', () {
    // The decoder applies the orientation it reads (a sideways file
    // decodes upright), so the tag is in the file.
    final read = img.decodeJpg(original)!;
    expect((read.width, read.height), (2000, 3000));
    expect(read.exif.gpsIfd.isEmpty, isFalse);
    final text = latin1.decode(original, allowInvalid: true);
    expect(text, contains('Exif'));
    expect(text, contains('Pixel 9 Pro'));
  });

  test('a photo is turned the right way up and brought to 2560 pixels on its long side', () {
    final prepared = prepareJpeg(original)!;
    // Viewed upright the picture is 2000 x 3000; scaled to a 2560 long side.
    expect(prepared.height, PhotoPreparer.maxSide);
    expect(prepared.width, closeTo(1707, 1));
    final out = img.decodeJpg(prepared.jpeg)!;
    expect((out.width, out.height), (prepared.width, prepared.height));
    // The stored top-left quarter is now at the top right.
    final topRight = out.getPixel(out.width - 10, 10);
    final topLeft = out.getPixel(10, 10);
    expect(topRight.r, greaterThan(200));
    expect(topRight.b, lessThan(60));
    expect(topLeft.b, greaterThan(200));
  });

  test('nothing of the original metadata leaves the device', () {
    final prepared = prepareJpeg(original)!;
    final out = img.decodeJpg(prepared.jpeg)!;
    expect(out.exif.isEmpty, isTrue);
    expect(out.exif.gpsIfd.isEmpty, isTrue);
    final text = latin1.decode(prepared.jpeg, allowInvalid: true);
    expect(text, isNot(contains('Pixel 9 Pro')));
    expect(text, isNot(contains('2026:10:06')));
    expect(text, isNot(contains('Exif')));
  });

  test(
    'a small picture keeps its size, and a transparent one lands on white',
    () {
      final png = img.encodePng(
        img.Image(width: 400, height: 300, numChannels: 4)
          ..clear(img.ColorRgba8(0, 0, 0, 0)),
      );
      final prepared = prepareJpeg(png)!;
      expect((prepared.width, prepared.height), (400, 300));
      final pixel = img.decodeJpg(prepared.jpeg)!.getPixel(200, 150);
      expect(pixel.r, greaterThan(240));
    },
  );

  test(
    'a picture too large for Dart is left to the engine, read from its header',
    () {
      // 9000 x 5000 is over the limit; a PNG of one colour stays small.
      final huge = img.encodePng(img.Image(width: 9000, height: 5000));
      expect(9000 * 5000, greaterThan(maxDartPixels));
      expect(prepareJpeg(huge), isNull);
    },
  );

  test('bytes that are no picture are refused', () {
    expect(
      prepareJpeg(Uint8List.fromList(utf8.encode('not an image'))),
      isNull,
    );
  });
}
