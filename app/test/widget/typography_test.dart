import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/theme/app_theme.dart';

import '../helpers/fonts.dart';

/// The width [text] takes in [style], laid out with the app's real font.
double _width(TextStyle? style, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  final text = lunaTheme(Brightness.light).textTheme;

  testWidgets("the guidance's distance keeps its width as its figures change", (tester) async {
    await loadRealFonts();
    // displaySmall sets the distance of the next maneuver in the guidance.
    final live = text.displaySmall;
    expect(_width(live, '110 m'), _width(live, '800 m'));
    expect(_width(live, '11:11'), _width(live, '20:48'));
  });

  testWidgets('text read at length keeps proportional figures: the "1"s of "11 lits" stay narrow', (
    tester,
  ) async {
    await loadRealFonts();
    final body = text.bodyMedium;
    expect(_width(body, '11 lits'), lessThan(_width(body, '00 lits')));
  });
}
