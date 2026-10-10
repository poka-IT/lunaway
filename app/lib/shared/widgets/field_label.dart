import 'package:flutter/widgets.dart';

/// The label of a text field, for `InputDecoration.label`: a label longer
/// than the field (a German or Dutch one at a large text size) gets a
/// little smaller rather than end in "...", which said nothing of the
/// field. A label stays on one line: it floats above the field once filled.
class FieldLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, maxLines: 1),
  );
}
