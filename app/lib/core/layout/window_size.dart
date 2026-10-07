import 'package:flutter/widgets.dart';

/// Material 3 window size classes. The layout switches on width alone, so a
/// phone held in landscape keeps the layout its width calls for.
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(BuildContext context) => ofWidth(MediaQuery.sizeOf(context).width);

  /// The narrowest window of the medium class, and of the expanded one.
  static const double mediumFrom = 600;
  static const double expandedFrom = 840;

  static WindowSize ofWidth(double width) {
    if (width < mediumFrom) return compact;
    if (width < expandedFrom) return medium;
    return expanded;
  }
}
