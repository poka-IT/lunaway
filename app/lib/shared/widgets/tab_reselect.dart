import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tab_reselect.g.dart';

/// The destination of the shell tapped while it was already the current
/// one, counted so that a second tap on the same one is news again.
// keepAlive: the shell writes it whether or not a screen listens yet.
@Riverpod(keepAlive: true)
class TabReselect extends _$TabReselect {
  @override
  ({int tab, int count}) build() => (tab: -1, count: 0);

  void reselect(int tab) => state = (tab: tab, count: state.count + 1);
}

/// Brings the lists of a destination back to their top when its tab is
/// tapped again, as every phone app does. It moves the page's primary
/// scroll controller, the one a tap on the iOS status bar moves too; the
/// vertical lists of a phone follow it by themselves. On a desktop no list
/// follows it (two side by side would share one scroll bar), and a tap
/// again only returns to the destination's first page.
class ScrollsToTopOnReselect extends ConsumerWidget {
  const new({required this.tab, required this.child, super.key});

  /// The index of the shell's destination this screen belongs to.
  final int tab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(tabReselectProvider, (_, next) {
      if (next.tab != tab) return;
      final controller = PrimaryScrollController.maybeOf(context);
      if (controller == null) return;
      final duration = Motion.of(context, Motion.emphasized);
      for (final position in controller.positions.toList()) {
        if (position.pixels <= position.minScrollExtent) continue;
        unawaited(position.animateTo(0, duration: duration, curve: Motion.standard));
      }
    });
    return child;
  }
}
