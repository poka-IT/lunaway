import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';

/// Wraps a map that is an HTML element of the page (the web) and tells the
/// page what the app's own hit test sees of it: whether the mouse is over
/// the map or over something the app draws above it (a dialog, a sheet, a
/// button, the barrier of a menu), and whether a press is the map's.
///
/// The browser picks the cursor from the element under the mouse, and hands
/// that element the touches and clicks, while the map's element sits under
/// the app's canvas wherever the map is laid out. Without this, the map's
/// grab hand showed over every button of a sheet open above the map, and
/// the map took the taps meant for that sheet, and the late clicks of a tap
/// on a list that had gone meanwhile. With it, the map shows its own cursor
/// only where the app sees the map, and hears only the gestures whose first
/// press the app gave it (`lunawayGestures` in web/lunaway_maplibre.js).
/// Every map of the app built on an HTML element goes through this widget
/// (structure_check rule `web-map-gestures`).
class WebMapPointer extends StatefulWidget {
  const new({
    required this.child,
    this.onChanged = markPointerOnWebMap,
    this.onPress = claimWebMapGesture,
    super.key,
  });

  final Widget child;

  /// Told when the mouse enters (`on` true) or leaves the map; the page's
  /// rules by default, a recorder in tests.
  final void Function({required bool on}) onChanged;

  /// Told when a pointer goes down on the map as the app's hit test sees
  /// it, while the app handles that press: the page lets the gesture reach
  /// the map. The page's gate by default, a recorder in tests.
  final VoidCallback onPress;

  /// Whether the map is an HTML element; tests turn it on.
  @visibleForTesting
  static bool enabled = kIsWeb;

  @override
  State<WebMapPointer> createState() => _WebMapPointerState();
}

class _WebMapPointerState extends State<WebMapPointer> {
  bool _inside = false;

  void _set(bool inside) {
    if (inside == _inside) return;
    _inside = inside;
    widget.onChanged(on: inside);
  }

  @override
  void dispose() {
    // A map that goes while the mouse is over it (a route closed with the
    // keyboard) must not leave the page believing it is still there.
    _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!WebMapPointer.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => widget.onPress(),
      child: MouseRegion(
        onEnter: (_) => _set(true),
        onExit: (_) => _set(false),
        child: widget.child,
      ),
    );
  }
}

/// How long a bare tap waits before it acts on this engine, with the
/// pointer that pressed last ([FreeTap.doubleTapWindowFor]).
Duration freeTapWindow() => FreeTap.doubleTapWindowFor(
  web: kIsWeb,
  platform: defaultTargetPlatform,
  pointer: webMapPointerKind(),
);
