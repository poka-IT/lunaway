import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real typefaces (Atkinson Hyperlegible Next and the Material
/// icons) so golden images show readable text rather than test boxes.
Future<void> loadRealFonts() async {
  final atkinson = FontLoader('Atkinson');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    atkinson.addFont(rootBundle.load('assets/fonts/AtkinsonHyperlegibleNext-$weight.ttf'));
  }
  await atkinson.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
}
