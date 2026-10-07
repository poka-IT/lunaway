import 'package:flutter/widgets.dart';

/// Material 3 window size classes. The layout switches on width alone, so a
/// phone held in landscape keeps the layout its width calls for.
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(BuildContext context) => ofWidth(MediaQuery.sizeOf(context).width);

  static WindowSize ofWidth(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    return expanded;
  }
}
