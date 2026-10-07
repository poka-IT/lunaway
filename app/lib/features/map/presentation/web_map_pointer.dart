import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/presentation/web_map_controls.dart'
    if (dart.library.js_interop) 'package:lunaway/features/map/presentation/web_map_controls_web.dart';

/// Wraps a map that is an HTML element of the page (the web) and tells the
/// page whether the mouse is over it as the app's own hit test sees it:
/// directly over the map, or over something the app draws above it (a
/// dialog, a sheet, a button, the barrier of a menu).
///
/// The browser picks the cursor from the element under the mouse, and the
/// map's element sits under the app's canvas wherever the map is laid out:
/// without this, the map's grab hand showed over every button of a sheet
/// open above the map. With it, the map shows its own cursor only where the
/// app sees the map, and the cursor the app sets everywhere else.
class WebMapPointer extends StatefulWidget {
  const new({required this.child, this.onChanged = markPointerOnWebMap, super.key});

  final Widget child;

  /// Told when the mouse enters (`on` true) or leaves the map; the page's
  /// rules by default, a recorder in tests.
  final void Function({required bool on}) onChanged;

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
    return MouseRegion(onEnter: (_) => _set(true), onExit: (_) => _set(false), child: widget.child);
  }
}

/// How long a bare tap waits before it acts on this engine, with the
/// pointer that pressed last ([FreeTap.doubleTapWindowFor]).
Duration freeTapWindow() => FreeTap.doubleTapWindowFor(
  web: kIsWeb,
  platform: defaultTargetPlatform,
  pointer: webMapPointerKind(),
);
