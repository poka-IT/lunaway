import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// One route of the answer: its time and length, what it uses (tolls,
/// motorways, a ferry), and how many limits to watch. The chosen one wears
/// the amber rim of a selection.
class RouteOptionCard extends StatelessWidget {
  const new({
    required this.route,
    required this.ordinal,
    required this.selected,
    required this.units,
    this.onTap,
    super.key,
  });

  final RouteOption route;

  /// 0 for the recommended route, then 1, 2 for the alternatives.
  final int ordinal;
  final bool selected;
  final DistanceUnits units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final facts = [
      if (route.hasToll) t.navigation.preview.toll,
      if (route.hasMotorway) t.navigation.preview.motorway,
      if (route.hasFerry) t.navigation.preview.ferry,
    ];
    final warnings = route.warnings.length;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.short),
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ordinal == 0
                        ? t.navigation.preview.recommended
                        : t.navigation.preview.alternative(n: '$ordinal'),
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Space.xxs),
                  Wrap(
                    spacing: Space.m,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(t.routeDuration(route.durationS), style: theme.textTheme.headlineSmall),
                      Text(
                        t.routeDistance(route.distanceM, units),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (facts.isNotEmpty || warnings > 0) ...[
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xxs,
                      children: [
                        for (final f in facts) _Fact(text: f),
                        if (warnings > 0)
                          _Fact(
                            text: t.navigation.preview.warnings(n: warnings),
                            icon: AppIcons.error,
                            alert: true,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const new({required this.text, this.icon, this.alert = false});

  final String text;
  final IconData? icon;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = alert ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: alert ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: Space.xxs),
            ],
            // A long fact wraps inside its chip rather than past the card.
            Flexible(
              child: Text(text, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
