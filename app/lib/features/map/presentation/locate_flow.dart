import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/location/browser_location.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Shows the device position on the map, asking for it the considerate way:
/// an explanation before the system prompt the first time, the way to the
/// settings after a refusal for good, a word when location is off on the
/// device, and a distinct message when no position comes in time.
Future<void> locateUser(BuildContext context, WidgetRef ref) async {
  final browser = ref.read(browserLocationProvider);
  if (browser != null) return await _locateInBrowser(context, ref, browser);
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!await ensureLocationAccess(context, ref) || !context.mounted) return;
  final controller = ref.read(mapControllerProvider);
  final position = await controller?.locateUser();
  if (!context.mounted) return;
  if (position == null) {
    showMessage(messenger, t.location.noFix);
    return;
  }
  ref.read(userLocationProvider.notifier).update(position);
  await controller?.moveTo(position, zoom: 12);
}

/// The web: the browser asks the user itself, and some browsers show that
/// prompt only during a click, so the request leaves before anything is
/// awaited. A refusal says where the browser keeps the setting; the site
/// cannot open it.
Future<void> _locateInBrowser(BuildContext context, WidgetRef ref, BrowserLocation browser) async {
  final request = browser.locate();
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final fix = await request;
  if (!context.mounted) return;
  switch (fix) {
    case BrowserPosition(:final position, :final accuracy):
      ref.read(userLocationProvider.notifier).update(position);
      final controller = ref.read(mapControllerProvider);
      await controller?.showPosition(position, accuracy: accuracy);
      await controller?.moveTo(position, zoom: 12);
    case BrowserDenied():
      await _explain(
        context,
        title: t.location.browserDeniedTitle,
        body: t.location.browserDenied,
        action: t.common.ok,
      );
    case BrowserNoFix():
      showMessage(messenger, t.location.browserNoFix);
  }
}

/// Whether the app may read the position, asking for it the considerate
/// way (see [locateUser]); the route planner asks the same way.
Future<bool> ensureLocationAccess(BuildContext context, WidgetRef ref) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final permissions = ref.read(locationPermissionsProvider);
  var access = await permissions.status();
  if (!context.mounted) return false;
  switch (access) {
    case LocationAccess.granted:
      return true;
    case LocationAccess.unsupported:
      showMessage(messenger, t.location.unsupported);
      return false;
    case LocationAccess.serviceOff:
      await _explain(
        context,
        title: t.location.serviceOffTitle,
        body: t.location.serviceOff,
        action: t.common.ok,
      );
      return false;
    case LocationAccess.deniedForever:
      if (await _explain(
        context,
        title: t.location.deniedTitle,
        body: t.location.denied,
        action: t.location.openSettings,
        dismiss: t.location.notNow,
      )) {
        await permissions.openSettings();
      }
      return false;
    case LocationAccess.notGranted:
      final allow = await _explain(
        context,
        title: t.location.rationaleTitle,
        body: t.location.rationale,
        action: t.location.allow,
        dismiss: t.location.notNow,
      );
      if (!allow) return false;
      access = await permissions.request();
      if (!context.mounted) return false;
      if (access == LocationAccess.deniedForever) {
        if (await _explain(
          context,
          title: t.location.deniedTitle,
          body: t.location.denied,
          action: t.location.openSettings,
          dismiss: t.location.notNow,
        )) {
          await permissions.openSettings();
        }
        return false;
      }
      if (access != LocationAccess.granted) {
        showMessage(messenger, t.location.notAllowed);
        return false;
      }
      return true;
  }
}

/// An explanation sheet; true when the user took its action.
Future<bool> _explain(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  String? dismiss,
}) async {
  final taken = await showModalBottomSheet<bool>(
    context: context,
    // Above the dock and the panels: the shell holds the branches.
    useRootNavigator: true,
    useSafeArea: true,
    // As tall as the text needs, and scrolling past that: at a large text
    // size the explanation and its buttons never get cut.
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(AppIcons.locate, size: 36, color: theme.colorScheme.secondary),
              const SizedBox(height: Space.m),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Space.s),
              Text(body, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Space.xl),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
              if (dismiss != null) ...[
                const SizedBox(height: Space.s),
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(dismiss)),
              ],
            ],
          ),
        ),
      );
    },
  );
  return taken ?? false;
}
