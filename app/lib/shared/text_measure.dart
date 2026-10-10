import 'package:flutter/widgets.dart';

/// The width [text] takes on one line in [style] at the reader's text
/// size ([scaler]), rounded up to a whole pixel.
double lineWidth(String text, TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width.ceilToDouble();
}

/// The width of the widest word of [texts] in [style]: the narrowest box
/// that lays them out without cutting a word in two. A word ends at a
/// plain space; a figure tied to its unit by a no-break space ("3,20 m")
/// counts as one.
double widestWord(Iterable<String> texts, TextStyle? style, TextScaler scaler) {
  var widest = 0.0;
  for (final text in texts) {
    for (final word in text.split(RegExp(r'[ \n]+'))) {
      if (word.isEmpty) continue;
      final width = lineWidth(word, style, scaler);
      if (width > widest) widest = width;
    }
  }
  return widest;
}
