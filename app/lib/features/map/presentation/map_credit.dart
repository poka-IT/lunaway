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
/// it behind a tap, or not at all in the desktop web view: the map hides
/// theirs (GlMap's attribution margins), this one stands alone.
class MapCredit extends ConsumerWidget {
  const new({super.key});

  /// Its height on the map: a finger-sized target around a small label.
  static const double height = 48;

  /// Its width on the map at the reader's text size: what a control on the
  /// same bottom edge leaves free for it.
  static double widthOf(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: context.t.map.credit, style: _style(Theme.of(context))),
      textDirection: Directionality.of(context),
      textScaler: _scaler(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + Space.xs * 2;
  }

  static TextStyle? _style(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface);

  // A legal line, not reading matter: at large text sizes it would run under
  // the map's buttons.
  static TextScaler _scaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

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
      // A link, so the pointing hand: a gesture detector shows none itself.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(externalActionsProvider).openUrl(osmCopyright),
          // A small label, a finger-sized target: 48 dp tall at least.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height),
            child: Center(
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.78),
                  borderRadius: const BorderRadius.all(Radius.circular(LunaTokens.radiusXs)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
                  child: Text(t.map.credit, style: _style(theme), textScaler: _scaler(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
