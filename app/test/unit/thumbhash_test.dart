import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/images/thumbhash.dart';

Uint8List _image(int w, int h, int Function(int x, int y) colour) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = colour(x, y);
      final i = (y * w + x) * 4;
      rgba
        ..[i] = (c >> 16) & 255
        ..[i + 1] = (c >> 8) & 255
        ..[i + 2] = c & 255
        ..[i + 3] = (c >> 24) & 255;
    }
  }
  return rgba;
}

void main() {
  test('a landscape photo keeps its shape and its colours in the placeholder', () {
    // A blue sky over green ground, 4:3.
    final hash = ThumbHash.encode(
      40,
      30,
      _image(40, 30, (x, y) => y < 18 ? 0xFF4A90D9 : 0xFF2E7D32),
    );
    expect(hash.length, lessThan(30));
    expect(ThumbHash.aspectRatio(hash), closeTo(4 / 3, 0.2));
    final decoded = ThumbHash.decode(hash);
    expect(decoded.width, 32);
    expect(decoded.height, closeTo(24, 2));
    int at(int x, int y, int channel) => decoded.rgba[(y * decoded.width + x) * 4 + channel];
    // The top is blue (more blue than red), the bottom green (more green).
    expect(at(16, 2, 2), greaterThan(at(16, 2, 0) + 40));
    expect(at(16, decoded.height - 2, 1), greaterThan(at(16, decoded.height - 2, 2) + 20));
    expect(at(16, 2, 3), 255, reason: 'an opaque photo stays opaque');
  });

  test('a portrait photo reads as a portrait', () {
    final hash = ThumbHash.encode(30, 60, _image(30, 60, (x, y) => 0xFFE0B080));
    expect(ThumbHash.aspectRatio(hash), lessThan(1));
    final decoded = ThumbHash.decode(hash);
    expect(decoded.height, 32);
    expect(decoded.width, lessThan(decoded.height));
  });

  test('the base64 of the API reads back, and a malformed one is refused', () {
    final hash = ThumbHash.encode(8, 8, _image(8, 8, (x, y) => 0xFF808080));
    const text = 'AAAAAA==';
    expect(ThumbHash.fromBase64(text), isNull, reason: 'too short to be a hash');
    expect(ThumbHash.fromBase64('not base64!'), isNull);
    expect(ThumbHash.fromBase64(null), isNull);
    expect(ThumbHash.fromBase64(_b64(hash)), hash);
  });
}

String _b64(Uint8List bytes) => const Base64Encoder().convert(bytes);
