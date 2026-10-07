import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

extension NavigationAppLabels on NavigationApp {
  String label(Translations t) => switch (this) {
    NavigationApp.googleMaps => t.directions.googleMaps,
    NavigationApp.waze => t.directions.waze,
    NavigationApp.osmAnd => t.directions.osmAnd,
    NavigationApp.organicMaps => t.directions.organicMaps,
    NavigationApp.magicEarth => t.directions.magicEarth,
    NavigationApp.appleMaps => t.directions.appleMaps,
    NavigationApp.openStreetMap => t.directions.openStreetMap,
  };

  IconData get icon => switch (this) {
    NavigationApp.googleMaps => AppIcons.googleMaps,
    NavigationApp.waze => AppIcons.waze,
    NavigationApp.osmAnd => AppIcons.osmand,
    NavigationApp.organicMaps => AppIcons.organicMaps,
    NavigationApp.magicEarth => AppIcons.magicEarth,
    NavigationApp.appleMaps => AppIcons.appleMaps,
    NavigationApp.openStreetMap => AppIcons.osmWeb,
  };
}

/// The apps of [offered] that can open a route here, in their order.
Future<List<NavigationApp>> availableNavigationApps(
  ExternalActions actions,
  List<NavigationApp> offered,
) async {
  final checks = await Future.wait(offered.map(actions.canNavigateWith));
  return [
    for (final (i, app) in offered.indexed)
      if (checks[i]) app,
  ];
}

/// "Itinéraire": Lunaway's own route preview, computed for the vehicle,
/// then the guidance from it. The navigation apps are a secondary way out
/// ([openInOtherApp]), never what this button does.
void openDirections(BuildContext context, LatLng to, {String? label, String? placeId}) =>
    openRoutePreview(context, RouteTarget(destination: to, label: label, placeId: placeId));

/// "Ouvrir dans...": the route to [to] handed to a navigation app, which
/// knows nothing of the vehicle's size. The app the user remembered opens
/// at once; otherwise, or when [choose] (a long press, the setting in the
/// profile), a short chooser lists those installed.
Future<void> openInOtherApp(
  BuildContext context,
  WidgetRef ref,
  LatLng to, {
  String? label,
  bool choose = false,
}) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final actions = ref.read(externalActionsProvider);
  final settings = ref.read(settingsProvider.notifier);
  final remembered = NavigationApp.fromId(ref.read(settingsProvider).navigationApp);
  final platform = Theme.of(context).platform;
  NavigationApp? app;
  if (!choose && remembered != null && await actions.canNavigateWith(remembered)) {
    app = remembered;
  } else {
    final available = await availableNavigationApps(
      actions,
      NavigationApp.offeredOn(platform, web: kIsWeb),
    );
    if (!context.mounted) return;
    final picked = await showNavigationAppChooser(context, available, selected: remembered);
    if (picked == null || !context.mounted) return;
    if (picked.remember) await settings.setNavigationApp(picked.app.id);
    if (!context.mounted) return;
    app = picked.app;
  }
  final opened = await actions.navigate(
    app,
    to,
    from: ref.read(userLocationProvider),
    label: label,
  );
  if (!opened) showMessage(messenger, t.place.openFailed);
}

/// The user's pick in the chooser.
typedef NavigationPick = ({NavigationApp app, bool remember});

/// The chooser of the navigation apps, with the option to remember the
/// choice (on by default: most users always drive with the same app).
/// Null when dismissed.
Future<NavigationPick?> showNavigationAppChooser(
  BuildContext context,
  List<NavigationApp> apps, {
  NavigationApp? selected,
}) => showSheet<NavigationPick>(
  context,
  // Above the dock and the panels: the shell holds the branches.
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => _Chooser(apps: apps, selected: selected),
);

class _Chooser extends StatefulWidget {
  const new({required this.apps, this.selected});

  final List<NavigationApp> apps;
  final NavigationApp? selected;

  @override
  State<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends State<_Chooser> {
  var _remember = true;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.xs),
              child: Text(t.directions.title, style: theme.textTheme.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.m),
              child: Text(
                t.directions.hint,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (widget.apps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.m),
                child: Text(t.directions.none, style: theme.textTheme.bodyLarge),
              ),
            for (final app in widget.apps)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: Icon(app.icon),
                ),
                title: Text(app.label(t)),
                trailing: app == widget.selected
                    ? Icon(AppIcons.check, color: scheme.onSurface)
                    : null,
                onTap: () => Navigator.of(context).pop((app: app, remember: _remember)),
              ),
            const SizedBox(height: Space.s),
            SwitchListTile(
              value: _remember,
              onChanged: (v) => setState(() => _remember = v),
              title: Text(t.directions.remember),
              subtitle: Text(t.directions.rememberHint),
            ),
            const SizedBox(height: Space.s),
          ],
        ),
      ),
    );
  }
}
