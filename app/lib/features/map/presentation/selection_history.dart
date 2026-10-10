import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/core/web/browser.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_history.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';

/// The way back through what the map opens, around the map's screen: the
/// browser's and the system's back, handed to [MapFlow], which decides.
///
/// In a browser each selection has an entry of its own in the tab's
/// history (`/map?place=<id>`, a link to share): the browser's back or
/// forward lands on an address, and the map opens what it names
/// ([MapFlow.arrived]). Elsewhere the system back walks the way back: the
/// place a shop was opened from, then the bare map, then the search, then
/// out ([MapFlow.back]).
class SelectionHistory extends ConsumerStatefulWidget {
  const new({required this.onLink, required this.child, super.key});

  /// Opens an address the way back does not know (a link from elsewhere, a
  /// page reloaded on a place): the screen reads what it names and brings
  /// the map there.
  final void Function(MapLink link) onLink;

  final Widget child;

  @override
  ConsumerState<SelectionHistory> createState() => _SelectionHistoryState();
}

class _SelectionHistoryState extends ConsumerState<SelectionHistory> {
  GoRouter? _router;

  /// Another tab is shown: the browser's history no longer has the way
  /// back's steps under it.
  bool _away = false;

  /// An address the map came to waits to be judged.
  bool _judging = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(browserProvider) == null) return;
    _router = GoRouter.maybeOf(context)?..routerDelegate.addListener(_onRoute);
    // The writer of the tab's history from the map's first frame: a popup
    // opened over the bare map takes its entry from it.
    ref.read(mapHistoryProvider);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }

  MapFlow get _flow => ref.read(mapFlowProvider.notifier);

  MapHistory get _history => ref.read(mapHistoryProvider);

  /// The router moved: the browser went back or forward, a link or another
  /// screen of the app led here, or the map was left.
  void _onRoute() {
    final location = _router?.routerDelegate.currentConfiguration.uri;
    if (location == null) return;
    if (location.path != AppRoutes.map) {
      if (!_away) _flow.detach();
      _away = true;
      return;
    }
    // A page over the map holds the entry above the map's and leaves by the
    // browser's back: the map comes back on its own entry.
    if (!_history.mapShown) return;
    _away = false;
    if (_judging) return;
    _judging = true;
    // Once the moves and writes asked of the history have landed: an
    // address on the way (the bare map of a close, before the pin tapped
    // after it) is not where the browser stays.
    _history.whenSettled(_judge);
  }

  /// The browser shows the map at an address: the map opens what it names.
  void _judge() {
    _judging = false;
    if (!mounted || !_history.mapShown) return;
    if (_flow.arrived(_history.address) case final open?) widget.onLink(open);
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final searching = ref.watch(searchQueryProvider).isNotEmpty;
    // The system back closes what lies over the map (the details, then the
    // search) before it may leave the app, as everywhere on Android.
    return PopScope(
      canPop: selection == null && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _flow.back();
      },
      child: widget.child,
    );
  }
}
