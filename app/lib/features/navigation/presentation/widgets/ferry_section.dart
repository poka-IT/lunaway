import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The ferry crossings of the chosen route: the line, its ports, the
/// countries on each side, where and how long. When the user avoids ferries
/// and the route still crosses, it says the destination cannot be reached
/// without one: avoiding ferries is a preference the server keeps when a
/// road exists.
class FerrySection extends StatelessWidget {
  const new({required this.route, required this.avoided, required this.units, super.key});

  final RouteOption route;

  /// Whether the route was asked to avoid ferries.
  final bool avoided;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ferries = route.ferries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.navigation.ferry.title(n: ferries.length), style: theme.textTheme.titleMedium),
        if (avoided) ...[
          const SizedBox(height: Space.xs),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(LunaTokens.radiusM),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Text(
                t.navigation.ferry.needed,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
          ),
        ],
        const SizedBox(height: Space.xs),
        for (final f in ferries) FerryTile(crossing: f, units: units),
      ],
    );
  }
}

/// One crossing: the line, then its ports, countries, and where and how
/// long, each on its line.
class FerryTile extends StatelessWidget {
  const new({required this.crossing, required this.units, this.iconSize = 40, super.key});

  final FerryCrossing crossing;
  final DistanceUnits units;

  /// The disc of the icon: a step of the roadbook shows a smaller one.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = t.ferryDetails(crossing, units);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(
                AppIcons.ferry,
                color: scheme.onSecondaryContainer,
                size: iconSize * 0.55,
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.ferryTitle(crossing), style: theme.textTheme.titleMedium),
                  for (final (i, line) in details.indexed)
                    Text(
                      line,
                      style: i == details.length - 1
                          ? theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)
                          : theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
