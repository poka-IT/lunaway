import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lunaway/features/account/data/recovery_qr.dart';
import 'package:lunaway/features/account/domain/recovery_code.dart';

void main() {
  qrTests();
  // The example of the backend's report, made by the server's own code.
  const shown = '2W3Y-9GFA-J1DR-1DGC-WVE0-7C88-CF1';

  test('a code the production server made reads as valid', () {
    // From createRecoveryCode on the deployed API (its account is deleted).
    expect(
      RecoveryCode.parse('221Q-7V2M-EK9T-S000-AJQE-T4S5-A6R'),
      '221Q-7V2M-EK9T-S000-AJQE-T4S5-A6R',
    );
  });

  test('a code reads back however it is typed', () {
    expect(RecoveryCode.parse(shown), shown);
    expect(RecoveryCode.parse(shown.toLowerCase().replaceAll('-', ' ')), shown);
    expect(RecoveryCode.parse(shown.replaceAll('-', '')), shown);
    expect(RecoveryCode.parse('  $shown  '), shown);
  });

  test('look-alike letters read as the digits they stand for', () {
    expect(RecoveryCode.parse(shown.replaceAll('0', 'O')), shown);
    expect(RecoveryCode.parse(shown.replaceAll('1', 'l')), shown);
    expect(RecoveryCode.parse(shown.replaceAll('1', 'I')), shown);
  });

  test('one mistyped symbol is always caught before it reaches the server', () {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final chars = shown.split('');
    for (var i = 0; i < chars.length; i++) {
      if (chars[i] == '-') continue;
      for (final replacement in alphabet.split('')) {
        if (replacement == chars[i]) continue;
        final typo = [...chars]..[i] = replacement;
        expect(RecoveryCode.parse(typo.join()), isNull, reason: typo.join());
      }
    }
  });

  test('wrong lengths and stray characters are refused', () {
    expect(RecoveryCode.parse(shown.substring(0, shown.length - 1)), isNull);
    expect(RecoveryCode.parse('${shown}0'), isNull);
    expect(RecoveryCode.parse(shown.replaceFirst('-', 'U')), isNull);
    expect(RecoveryCode.parse(''), isNull);
    expect(RecoveryCode.parse('0' * 500), isNull);
    expect(RecoveryCode.symbolsOf('ab-c?'), isNull);
  });

  test('groups of four for the card', () {
    expect(RecoveryCode.groups(shown), ['2W3Y', '9GFA', 'J1DR', '1DGC', 'WVE0', '7C88', 'CF1']);
    expect(RecoveryCode.group('2W3Y9GFAJ1'), '2W3Y-9GFA-J1');
  });
}

/// A card's QR code drawn as an image would hold it: dark modules on white,
/// with the quiet zone around.
Uint8List _qrPicture(String code, {int module = 8}) {
  final modules = recoveryQrModules(code);
  final size = (modules.length + 8) * module;
  final image = img.Image(width: size, height: size)..clear(img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < modules.length; y++) {
    for (var x = 0; x < modules[y].length; x++) {
      if (!modules[y][x]) continue;
      img.fillRect(
        image,
        x1: (x + 4) * module,
        y1: (y + 4) * module,
        x2: (x + 5) * module - 1,
        y2: (y + 5) * module - 1,
        color: img.ColorRgb8(0x0B, 0x1E, 0x3F),
      );
    }
  }
  return img.encodePng(image);
}

void qrTests() {
  test('the card QR code holds the code alone, and reads back from a picture of it', () {
    const code = '2W3Y-9GFA-J1DR-1DGC-WVE0-7C88-CF1';
    expect(readRecoveryQr(_qrPicture(code)), code);
  });

  test('a picture with no card QR code reads as nothing', () {
    final blank = img.encodePng(
      img.Image(width: 300, height: 300)..clear(img.ColorRgb8(255, 255, 255)),
    );
    expect(readRecoveryQr(blank), isNull);
  });
}
