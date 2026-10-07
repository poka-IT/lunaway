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
  Widget build(BuildContext context) => PointerInterceptor(child: child);
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
        child,
        if (enabled && covered) PointerInterceptor(child: const SizedBox.expand()),
      ],
    );
  }
}
