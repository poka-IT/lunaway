import 'package:flutter/widgets.dart';
import 'package:lunaway/shared/text_measure.dart';

/// A text that never cuts a word in two: when its longest word is wider
/// than the room it has, the whole text gets just small enough for that
/// word, and still wraps between words. A German compound
/// ("Entsorgungsstation") in a narrow row at a large text size read as
/// "Entsorgungsstatio" over "n" otherwise.
///
/// It sizes itself by its width: not for a parent that asks its children's
/// intrinsic sizes ([IntrinsicHeight]).
class WholeWordsText extends StatelessWidget {
  const new(this.data, {this.style, this.maxLines, this.overflow, this.textAlign, super.key});

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final widest = widestWord([data], DefaultTextStyle.of(context).style.merge(style), scaler);
      final room = constraints.maxWidth;
      final fits = !room.isFinite || widest <= room || widest == 0;
      return Text(
        data,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        // The reader's own size, times what the longest word needs: a
        // linear scaler, as the system's is for body text.
        textScaler: fits ? null : TextScaler.linear(scaler.scale(1) * room / widest),
      );
    },
  );
}
