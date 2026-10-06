import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Where the OpenStreetMap copyright page lives: the credit opens it.
final Uri osmCopyright = Uri.parse('https://www.openstreetmap.org/copyright');

/// The basemap's credit, always visible in the bottom left corner of the
/// map: the OpenStreetMap licence asks for it on the map itself, and
/// Protomaps for its style. The engines' own attribution controls only show
/// it behind a tap, or not at all in the desktop web view.
class MapCredit extends ConsumerWidget {
  const new({super.key});

  /// Space kept on the left for the native engines' info button, which sits
  /// in the same corner on Android and iOS.
  static double get leading =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
      ? 36
      : 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: t.map.creditLabel,
      onTap: () => ref.read(externalActionsProvider).openUrl(osmCopyright),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(externalActionsProvider).openUrl(osmCopyright),
        // A small label, a finger-sized target: 48 dp tall at least.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.78),
                borderRadius: const BorderRadius.all(Radius.circular(LunaTokens.radiusXs)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
                child: Text(
                  t.map.credit,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurface),
                  // A legal line, not reading matter: at large text sizes
                  // it would run under the map's buttons.
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
