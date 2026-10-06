import 'dart:async';

import 'package:flutter/widgets.dart';

/// Whether the app is in front. Android starts the location service of
/// guidance only from an app in front: started from behind, it throws after
/// the position updates have begun, and those then run on unseen.
abstract interface class AppForeground {
  /// Completes when the app is in front: at once when it already is.
  Future<void> resumed();
}

/// [AppForeground] from the app's lifecycle.
final class LifecycleAppForeground implements AppForeground {
  const new();

  @override
  Future<void> resumed() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    final back = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!back.isCompleted) back.complete();
      },
    );
    try {
      await back.future;
    } finally {
      listener.dispose();
    }
  }
}
