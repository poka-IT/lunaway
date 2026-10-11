import 'package:flutter/services.dart';
import 'package:lunaway/shared/theme/typography.dart';

/// Loads the app's typefaces under the families the theme names (Figtree and
/// the Phosphor icons), so golden images show the real text and icons rather
/// than test boxes. Figtree is one variable file for every weight.
Future<void> loadRealFonts() async {
  const families = {
    LunaType.family: ['figtree-lunaway/FigtreeLunaway-Variable.ttf'],
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
