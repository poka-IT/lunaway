import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// Lets an action through while the vehicle stands still; while it moves,
/// only once the user says a passenger is at the screen. One large tap
/// either way: the driver is told to stop rather than given a form or a
/// list. [title] and [body] say what waits.
Future<bool> clearedWhileDriving(
  BuildContext context, {
  required bool moving,
  required String title,
  required String body,
}) async {
  if (!moving) return true;
  final t = context.t;
  final passenger = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          child: Text(t.roadReport.passenger),
        ),
      ],
    ),
  );
  return passenger ?? false;
}
