import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';

final _log = Logger('guidance_stops');

/// Runs [run], a change of the guidance's route; null when it went
/// through, else why not, in words: no network is told apart from a route
/// that could not be changed.
Future<String?> routeChangeProblem(Translations t, Future<bool> Function() run) async {
  try {
    // A change asked while a new route is on its way is refused: false,
    // and the message says the route was not changed.
    return await run() ? null : t.navigation.stops.failed;
  } on RouteFailure catch (f) {
    return f.kind == RouteFailureKind.offline
        ? t.navigation.stops.offline
        : t.navigation.stops.failed;
  } on Object catch (e, st) {
    // An answer this app cannot read: said like any other failure.
    _log.warning('a change of the stops failed', e, st);
    return t.navigation.stops.failed;
  }
}

/// Runs [action], then says it is [done] with its [undo], or why it failed.
Future<void> saidChange(
  ScaffoldMessengerState? messenger,
  Translations t, {
  required Future<bool> Function() action,
  required String done,
  required Future<bool> Function() undo,
}) async {
  final problem = await routeChangeProblem(t, action);
  if (problem != null) {
    showMessage(messenger, problem);
    return;
  }
  showMessage(
    messenger,
    done,
    action: SnackBarAction(
      label: t.common.undo,
      onPressed: () async {
        if (await routeChangeProblem(t, undo) case final problem?) showMessage(messenger, problem);
      },
    ),
  );
}

/// Takes [stop] out of the guidance's route, from its chip or its card:
/// said at once, with the way back, while the new route is asked for; a
/// failure is said in its place. Never a question first: the way back is
/// the answer to a slip. True once the stop is out.
Future<bool> removeGuidanceStop(
  ProviderContainer container,
  ScaffoldMessengerState? messenger,
  Translations t,
  RouteStop stop,
) async {
  final controller = container.read(guidanceControllerProvider.notifier);
  final before = container.read(guidanceControllerProvider)?.stops ?? const <RouteStop>[];
  final out = Completer<bool>();
  showMessage(
    messenger,
    t.navigation.stops.removed,
    action: SnackBarAction(
      label: t.common.undo,
      onPressed: () async {
        // A change asked while the stop's own is on its way would be
        // refused: the way back waits for it.
        if (!await out.future) return;
        final problem = await routeChangeProblem(t, () => controller.restoreStop(stop, before));
        if (problem != null) showMessage(messenger, problem);
      },
    ),
  );
  final problem = await routeChangeProblem(t, () => controller.removeStop(stop));
  out.complete(problem == null);
  if (problem != null) showMessage(messenger, problem);
  return problem == null;
}
