import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';

/// The way back through what the map opens, around the map's screen.
///
/// Every change of the selection moves the [SelectionTrail]. In a browser
/// it also moves the address: a selection opened gets an entry of its own
/// in the tab's history (`/map?place=<id>`, a link to share), so the
/// browser's back closes it, or reopens the place a shop was opened from,
/// rather than leaving the app; the address the browser goes back or
/// forward to opens what it names. Elsewhere the system back walks the
/// trail: the place a shop was opened from, then the bare map, then out.
class SelectionHistory extends ConsumerStatefulWidget {
  const new({required this.onLink, required this.child, super.key});

  /// Opens an address the trail does not know (a link from elsewhere, a
  /// page reloaded on a place): the screen reads what it names and brings
  /// the map there.
  final void Function(MapLink link) onLink;

  final Widget child;

  @override
  ConsumerState<SelectionHistory> createState() => _SelectionHistoryState();
}

class _SelectionHistoryState extends ConsumerState<SelectionHistory> {
  GoRouter? _router;

  /// The map's page is not the one shown (another tab, the route preview):
  /// the browser's history no longer has the trail's steps under it.
  bool _away = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(browserProvider) == null) return;
    _router = GoRouter.maybeOf(context)?..routerDelegate.addListener(_onRoute);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }

  Uri? get _location => _router?.routerDelegate.currentConfiguration.uri;

  bool get _onMap => _location?.path == AppRoutes.map;

  MapTrail get _trail => ref.read(mapTrailProvider.notifier);

  /// The router moved: the browser went back or forward, a link or another
  /// screen of the app led here, or the map was left.
  void _onRoute() {
    final location = _location;
    if (location == null) return;
    if (location.path != AppRoutes.map) {
      if (!_away) _trail.set(ref.read(mapTrailProvider).detached());
      _away = true;
      return;
    }
    _away = false;
    final link = MapLink.of(location);
    // Never a provider change while the router builds: just after.
    scheduleMicrotask(() {
      if (!mounted || MapLink.of(_location ?? Uri()) != link) return;
      _arrive(link);
    });
  }

  void _arrive(MapLink link) {
    final trail = ref.read(mapTrailProvider);
    final selection = ref.read(selectionProvider.notifier);
    if (link.names(ref.read(selectionProvider)) && link.names(trail.current)) return;
    if (trail.arrive(link) case (final there, final shown)?) {
      _trail.set(there);
      selection.select(shown);
      return;
    }
    if (link.point) {
      // A point is not written in the address: this session no longer
      // knows which one it was.
      _trail.set(const SelectionTrail());
      selection.select(null);
      _replace(MapLink.none);
      return;
    }
    widget.onLink(link);
  }

  /// The selection changed by the user's hand, or by an address: the trail
  /// follows, and in a browser, the address.
  void _follow(MapSelection? next) {
    final browser = ref.read(browserProvider);
    final (trail, step) = ref
        .read(mapTrailProvider)
        .follow(next, onBareMap: browser == null || (_onMap && MapLink.of(_location!).isNone));
    _trail.set(trail);
    if (browser == null || !_onMap) return;
    final link = MapLink.to(next);
    switch (step) {
      case TrailStay():
        break;
      case TrailPush() || TrailLeave():
        if (MapLink.of(_location!) != link) _router?.go(link.location);
      case TrailReplace():
        _replace(link);
      case TrailBack(:final steps):
        browser.goInHistory(-steps);
    }
  }

  /// The address of [link] in place of the current one, without a new
  /// entry in the history.
  void _replace(MapLink link) {
    final router = _router;
    if (router == null || MapLink.of(_location!) == link) return;
    Router.neglect(context, () => router.go(link.location));
  }

  /// The system back on a selection: the one it was opened from, or none.
  void _back() => ref.read(selectionProvider.notifier).select(ref.read(mapTrailProvider).previous);

  @override
  Widget build(BuildContext context) {
    ref.listen(selectionProvider, (_, next) => _follow(next));
    final selection = ref.watch(selectionProvider);
    final searching = ref.watch(searchQueryProvider).isNotEmpty;
    // The system back closes what lies over the map (the details, then the
    // search) before it may leave the app, as everywhere on Android.
    return PopScope(
      canPop: selection == null && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (ref.read(selectionProvider) != null) {
          _back();
        } else {
          ref.read(searchQueryProvider.notifier).change('');
        }
      },
      child: widget.child,
    );
  }
}
