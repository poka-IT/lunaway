import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';

/// Paths of the navigation screens, outside the shell: both take the whole
/// window.
abstract final class NavigationRoutes {
  /// `/route?lat=45.8451&lon=1.28637&name=...&place=<id>`: a link to share,
  /// a web page to bookmark.
  static const preview = '/route';
  static const guidance = '/guidance';

  static String previewOf(RouteTarget target) => Uri(
    path: preview,
    queryParameters: {
      'lat': target.destination.lat.toStringAsFixed(6),
      'lon': target.destination.lon.toStringAsFixed(6),
      if (target.label != null) 'name': target.label,
      if (target.placeId != null) 'place': target.placeId,
    },
  ).toString();

  /// The target of a preview link; null when the link holds no valid point.
  static RouteTarget? targetOf(Uri uri) {
    final q = uri.queryParameters;
    final lat = double.tryParse(q['lat'] ?? '');
    final lon = double.tryParse(q['lon'] ?? '');
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) return null;
    return RouteTarget(destination: LatLng(lat, lon), label: q['name'], placeId: q['place']);
  }
}

/// The navigation's routes, for the app's router.
List<RouteBase> navigationRoutes() => [
  GoRoute(
    path: NavigationRoutes.preview,
    builder: (_, state) => RoutePreviewScreen(target: NavigationRoutes.targetOf(state.uri)),
  ),
  GoRoute(path: NavigationRoutes.guidance, builder: (_, _) => const GuidanceScreen()),
];

/// Opens the route preview to [target], over the shell.
void openRoutePreview(BuildContext context, RouteTarget target) =>
    unawaited(GoRouter.of(context).push<void>(NavigationRoutes.previewOf(target)));
