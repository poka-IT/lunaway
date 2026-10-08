import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/core/web/browser.dart';
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

  /// The target the app opened the preview with, carried beside its link
  /// ([extra]): the exact point, where the link holds it rounded. Only
  /// when it is the one the link names; a link reloaded or typed has the
  /// rounded point alone.
  static RouteTarget? exactOf(Object? extra, RouteTarget? linked) {
    if (extra is! RouteTarget || linked == null) return linked;
    final same =
        extra.destination.lat.toStringAsFixed(_decimals) ==
            linked.destination.lat.toStringAsFixed(_decimals) &&
        extra.destination.lon.toStringAsFixed(_decimals) ==
            linked.destination.lon.toStringAsFixed(_decimals) &&
        extra.label == linked.label &&
        extra.placeId == linked.placeId;
    return same ? extra : linked;
  }
}

/// The navigation's routes, for the app's router.
List<RouteBase> navigationRoutes() => [
  GoRoute(
    path: NavigationRoutes.preview,
    builder: (_, state) => _LeavesForMap(
      child: _LinkedPreview(
        target: NavigationRoutes.exactOf(state.extra, NavigationRoutes.targetOf(state.uri)),
      ),
    ),
  ),
  GoRoute(path: NavigationRoutes.guidance, builder: (_, _) => const GuidanceScreen()),
];

/// Opens the route preview to [target], over the shell: its link holds the
/// point rounded on the web, the screen shows and routes to it exact.
void openRoutePreview(BuildContext context, RouteTarget target) =>
    unawaited(GoRouter.of(context).push<void>(NavigationRoutes.previewOf(target), extra: target));

/// Shows [location] in place of the page over the map that [context] is
/// on (the guidance after its preview, another preview), on the same entry
/// of the tab's history: the page still holds the one entry above the
/// map's, which [leaveForMap] goes back from.
void replaceOverMap(BuildContext context, String location, {Object? extra}) {
  final router = GoRouter.of(context);
  Router.neglect(context, () => unawaited(router.pushReplacement<void>(location, extra: extra)));
}

/// Leaves the route preview or the guidance for the map under it.
///
/// In a browser, by going back one entry in the tab's history, as the
/// browser's own back does: the page holds the entry above the map's
/// ([openRoutePreview], [replaceOverMap]). Popped by the app, the page
/// would stay in the history under a new entry of the map, and the next
/// back, the browser's or a close of what the map shows, would land on it
/// again: the preview reopened, or the guidance without its route. A page
/// opened on its own (a link typed or reloaded) has no map under it: the
/// map takes its place, its entry included.
///
/// Once per page: in a browser the page stays until the history has moved,
/// and a second press meanwhile would go back one entry more (the place
/// closed, or the tab out of the app).
void leaveForMap(BuildContext context) {
  if (ModalRoute.of(context) case final page?) {
    if (_left[page] ?? false) return;
    _left[page] = true;
  }
  final router = GoRouter.of(context);
  final browser = ProviderScope.containerOf(context, listen: false).read(browserProvider);
  if (router.canPop()) {
    if (browser != null) {
      browser.goInHistory(-1);
    } else {
      router.pop();
    }
  } else if (browser != null) {
    Router.neglect(context, () => router.go(AppRoutes.map));
  } else {
    router.go(AppRoutes.map);
  }
}

/// The pages [leaveForMap] has left.
final _left = Expando<bool>('left for the map');

/// A page over the map whose every way out is [leaveForMap]: in a browser
/// the back of an app bar, or any other pop asked of the page, goes back
/// through the history instead.
class _LeavesForMap extends ConsumerWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopScope(
    canPop: ref.watch(browserProvider) == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leaveForMap(context);
    },
    child: child,
  );
}

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
