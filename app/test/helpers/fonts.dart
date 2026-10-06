import 'package:flutter/services.dart';

/// Loads the app's typefaces under the families the theme names (Atkinson,
/// Fraunces and the Phosphor icons), so golden images show the real text and
/// icons rather than test boxes. Each face carries its own weight.
Future<void> loadRealFonts() async {
  const families = {
    'Atkinson': [
      'atkinson-next-lunaway/AtkinsonNextLunaway-Regular.ttf',
      'atkinson-next-lunaway/AtkinsonNextLunaway-Medium.ttf',
      'atkinson-next-lunaway/AtkinsonNextLunaway-SemiBold.ttf',
      'atkinson-next-lunaway/AtkinsonNextLunaway-Bold.ttf',
      'atkinson-next-lunaway/AtkinsonNextLunaway-ExtraBold.ttf',
    ],
    'Fraunces': ['fraunces/Fraunces-Variable.ttf'],
    'PhosphorRegular': ['phosphor/Phosphor-Regular.ttf'],
    'PhosphorFill': ['phosphor/Phosphor-Fill.ttf'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
}
