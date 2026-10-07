import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/guidance_screen.dart';
import 'package:lunaway/features/navigation/presentation/route_preview_screen.dart';
import 'package:lunaway/features/places/application/places_providers.dart';

/// Paths of the navigation screens, outside the shell: both take the whole
/// window.
abstract final class NavigationRoutes {
  /// `/route?lat=45.84510&lon=1.28637&name=...&place=<id>`: a link to
  /// share, a web page to bookmark. On the web the point is rounded to 4
  /// decimals (about 10 m), as the address of a page lands in the browser's
  /// history: a place is found again by its id, at its exact spot, and the
  /// point only stands for a place this device does not hold. The apps keep
  /// the exact point, which no history records.
  static const preview = '/route';
  static const guidance = '/guidance';

  static const _decimals = kIsWeb ? 4 : 6;

  static String previewOf(RouteTarget target) => Uri(
    path: preview,
    queryParameters: {
      'lat': target.destination.lat.toStringAsFixed(_decimals),
      'lon': target.destination.lon.toStringAsFixed(_decimals),
      if (target.label != null) 'name': target.label,
      if (target.placeId != null) 'place': target.placeId,
    },
  ).toString();

  /// The target of a preview link; null when the link holds no valid point.
  static RouteTarget? targetOf(Uri uri) {
    final q = uri.queryParameters;
    final lat = double.tryParse(q['lat'] ?? '');
    final lon = double.tryParse(q['lon'] ?? '');
    // NaN passes a range check: it is no number to compare.
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return RouteTarget(destination: LatLng(lat, lon), label: q['name'], placeId: q['place']);
  }
}

/// The navigation's routes, for the app's router.
List<RouteBase> navigationRoutes() => [
  GoRoute(
    path: NavigationRoutes.preview,
    builder: (_, state) => _LinkedPreview(target: NavigationRoutes.targetOf(state.uri)),
  ),
  GoRoute(path: NavigationRoutes.guidance, builder: (_, _) => const GuidanceScreen()),
];

/// Opens the route preview to [target], over the shell.
void openRoutePreview(BuildContext context, RouteTarget target) =>
    unawaited(GoRouter.of(context).push<void>(NavigationRoutes.previewOf(target)));

/// The preview of a link: a place it names is read on the device, for its
/// exact spot; the link's rounded point stands for a place not held here.
class _LinkedPreview extends ConsumerWidget {
  const new({required this.target});

  final RouteTarget? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = this.target;
    final id = target?.placeId;
    if (target == null || id == null) return RoutePreviewScreen(target: target);
    return switch (ref.watch(placeProvider(id))) {
      AsyncValue(:final value, hasValue: true) => RoutePreviewScreen(
        target: value == null
            ? target
            : RouteTarget(destination: value.position, label: target.label, placeId: id),
      ),
      AsyncError() => RoutePreviewScreen(target: target),
      _ => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}
