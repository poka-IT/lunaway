import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/route_entry.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

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

/// Takes the user to [to]: Lunaway's own guidance, computed for the
/// vehicle, or a navigation app. The choice the user remembered applies at
/// once; otherwise a short chooser offers Lunaway first, then the apps
/// installed, and to remember the choice. [choose] shows the chooser
/// whatever was remembered (a long press on the button, or the setting in
/// the profile).
Future<void> openDirections(
  BuildContext context,
  WidgetRef ref,
  LatLng to, {
  String? label,
  String? placeId,
  bool choose = false,
}) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final actions = ref.read(externalActionsProvider);
  final settings = ref.read(settingsProvider.notifier);
  final rememberedId = ref.read(settingsProvider).navigationApp;
  final remembered = NavigationApp.fromId(rememberedId);
  final platform = Theme.of(context).platform;
  void guide() =>
      openRoutePreview(context, RouteTarget(destination: to, label: label, placeId: placeId));

  if (!choose && rememberedId == lunawayDirectionsId) return guide();
  NavigationApp? app;
  if (!choose && remembered != null && await actions.canNavigateWith(remembered)) {
    app = remembered;
  } else {
    final available = await availableNavigationApps(
      actions,
      NavigationApp.offeredOn(platform, web: kIsWeb),
    );
    if (!context.mounted) return;
    final picked = await showNavigationAppChooser(
      context,
      available,
      selected: remembered,
      lunawaySelected: rememberedId == lunawayDirectionsId,
    );
    if (picked == null || !context.mounted) return;
    if (picked.remember) await settings.setNavigationApp(picked.app?.id ?? lunawayDirectionsId);
    if (!context.mounted) return;
    app = picked.app;
    if (app == null) return guide();
  }
  final opened = await actions.navigate(
    app,
    to,
    from: ref.read(userLocationProvider),
    label: label,
  );
  if (!opened) showMessage(messenger, t.place.openFailed);
}

/// The user's pick in the chooser; a null `app` is Lunaway's own guidance.
typedef NavigationPick = ({NavigationApp? app, bool remember});

/// The chooser: Lunaway's guidance first, then the navigation apps, with the
/// option to remember the choice (on by default: most users always drive
/// with the same app).
Future<NavigationPick?> showNavigationAppChooser(
  BuildContext context,
  List<NavigationApp> apps, {
  NavigationApp? selected,
  bool lunawaySelected = false,
}) => showModalBottomSheet<NavigationPick>(
  context: context,
  // Above the dock and the panels: the shell holds the branches.
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => _Chooser(apps: apps, selected: selected, lunawaySelected: lunawaySelected),
);

class _Chooser extends StatefulWidget {
  const new({required this.apps, this.selected, this.lunawaySelected = false});

  final List<NavigationApp> apps;
  final NavigationApp? selected;
  final bool lunawaySelected;

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
            LunawayGuidanceTile(
              selected: widget.lunawaySelected,
              onTap: () => Navigator.of(context).pop((app: null, remember: _remember)),
            ),
            if (widget.apps.isNotEmpty) const OtherAppsHeading(),
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
