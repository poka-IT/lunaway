import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/router/popup_routes.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Wraps a widget drawn over the map. On the web the map is an HTML element
/// that would otherwise receive the clicks meant for the widget; elsewhere
/// this is a no-op.
class OverMap extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!MapShield.enabled) return child;
    // The web plugin's own layout, with its element beside the child
    // rather than around it, so that only the element leaves the tab order
    // (`_Interceptor`).
    return Stack(
      alignment: Alignment.center,
      children: [
        const Positioned.fill(child: _Interceptor()),
        child,
      ],
    );
  }
}

/// An HTML element that takes the clicks over the map, out of the
/// keyboard's way. The framework gives every HTML element a focus node in
/// the tab order: a stop where nothing shows the focus, and one that comes
/// and goes with what it covers. The button drawn only while it holds the
/// focus (`FocusRevealedButton`) made a new one each time it showed, which
/// took the next Tab and, gone with the button, gave the focus back to it:
/// the keyboard went no further on the web.
class _Interceptor extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) =>
      ExcludeFocus(child: PointerInterceptor(child: const SizedBox.expand()));
}

/// Covers the map while a dialog, a sheet or a menu is open
/// ([openPopupsProvider]). On the web the map is an HTML element under the
/// app's canvas: the browser hands it the wheel and the clicks over a
/// dialog too, so scrolling the filters zoomed the map behind them. A
/// transparent element over the map takes them instead; they still reach
/// the app, which listens above both.
///
/// The desktop maps need none: on macOS the engine leaves the web view out
/// of the hit test wherever the app paints over it, and a dialog's barrier
/// paints the whole window; on Windows the web view is a texture inside the
/// app's own hit test.
class MapShield extends ConsumerWidget {
  const new({required this.child, super.key});

  final Widget child;

  /// Whether the map is an HTML element; tests turn it on.
  @visibleForTesting
  static bool enabled = kIsWeb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covered = ref.watch(openPopupsProvider) > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        // As an HTML element the map is a stop of the tab order where
        // nothing shows the focus and no key acts: the browser's focus
        // stays on the app. The keyboard has the map's own buttons.
        if (enabled) ExcludeFocus(child: child) else child,
        if (enabled && covered) const _Interceptor(),
      ],
    );
  }
}
