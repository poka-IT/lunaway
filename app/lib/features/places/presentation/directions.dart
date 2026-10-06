import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The navigation apps a platform offers. Android hands a `geo:` link to the
/// system, which lists every installed navigation app; elsewhere the app
/// offers the usual ones as web links, which open the app when installed.
enum NavigationTarget {
  system,
  appleMaps,
  googleMaps,
  waze,
  openStreetMap;

  static List<NavigationTarget> forPlatform(TargetPlatform platform, {required bool web}) {
    if (web) return const [googleMaps, openStreetMap];
    return switch (platform) {
      TargetPlatform.android => const [system],
      TargetPlatform.iOS => const [appleMaps, googleMaps, waze],
      TargetPlatform.macOS => const [appleMaps, googleMaps, openStreetMap],
      _ => const [googleMaps, openStreetMap],
    };
  }

  Uri url(LatLng to, {String? label}) {
    final lat = to.lat.toStringAsFixed(6);
    final lon = to.lon.toStringAsFixed(6);
    return switch (this) {
      system => Uri.parse(
        '${CoordinateFormat.geoUri.format(to)}?q=$lat,$lon${label == null ? '' : '(${Uri.encodeComponent(label)})'}',
      ),
      appleMaps => Uri.https('maps.apple.com', '/', {'daddr': '$lat,$lon', 'dirflg': 'd'}),
      googleMaps => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '$lat,$lon',
      }),
      waze => Uri.https('waze.com', '/ul', {'ll': '$lat,$lon', 'navigate': 'yes'}),
      openStreetMap => Uri.https('www.openstreetmap.org', '/directions', {'route': ';$lat,$lon'}),
    };
  }

  String label(Translations t) => switch (this) {
    system => t.directions.system,
    appleMaps => t.directions.appleMaps,
    googleMaps => t.directions.googleMaps,
    waze => t.directions.waze,
    openStreetMap => t.directions.osm,
  };

  IconData get icon => switch (this) {
    system => AppIcons.navigationSystem,
    appleMaps => AppIcons.map,
    googleMaps => AppIcons.navigationGoogle,
    waze => AppIcons.navigationWaze,
    openStreetMap => AppIcons.navigationOsm,
  };
}

/// Hands the trip to [to] to a navigation app: at once when the platform has
/// one way, through a short chooser otherwise.
Future<void> openDirections(BuildContext context, WidgetRef ref, LatLng to, {String? label}) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final targets = NavigationTarget.forPlatform(Theme.of(context).platform, web: kIsWeb);
  final target = targets.length == 1
      ? targets.single
      : await showModalBottomSheet<NavigationTarget>(
          context: context,
          useSafeArea: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.s),
                  child: Text(t.directions.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                for (final target in targets)
                  ListTile(
                    leading: Icon(target.icon),
                    title: Text(target.label(t)),
                    onTap: () => Navigator.of(context).pop(target),
                  ),
                const SizedBox(height: Space.s),
              ],
            ),
          ),
        );
  if (target == null) return;
  final opened = await ref.read(externalActionsProvider).openUrl(target.url(to, label: label));
  if (!opened) messenger?.showSnackBar(SnackBar(content: Text(t.place.openFailed)));
}
