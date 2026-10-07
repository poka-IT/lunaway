import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The icon of a restriction: what it limits.
IconData warningIcon(RouteWarningKind kind) => switch (kind) {
  RouteWarningKind.lowClearance || RouteWarningKind.unknownClearance => AppIcons.height,
  RouteWarningKind.narrow => AppIcons.width,
  RouteWarningKind.tooLong => AppIcons.length,
  RouteWarningKind.tooHeavy ||
  RouteWarningKind.axleLoad ||
  RouteWarningKind.goodsVehicleWeight => AppIcons.weight,
  RouteWarningKind.motorhomeBan => AppIcons.vehicle,
  RouteWarningKind.trailerBan => AppIcons.towing,
};

/// One restriction of a route: what it is and its figure, where it lies,
/// the vehicle's own figure, and where the figure comes from. Amber when the
/// vehicle passes with little margin, coral when it does not pass.
class WarningTile extends StatelessWidget {
  const new({required this.warning, required this.units, this.aheadM, this.onTap, super.key});

  final RouteWarning warning;
  final DistanceUnits units;

  /// Metres from the vehicle, during guidance; the distance from the start
  /// otherwise.
  final double? aheadM;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Coral, the colour of alerts: full for a limit the vehicle exceeds,
    // soft for one it passes with little margin.
    final blocking = warning.severity == WarningSeverity.blocking;
    final disc = blocking ? scheme.error : scheme.errorContainer;
    final glyph = blocking ? scheme.onError : scheme.onErrorContainer;
    final where = aheadM == null
        ? t.navigation.warning.fromStart(
            distance: t.routeDistance(warning.distanceFromStartM, units),
          )
        : t.navigation.warning.ahead(distance: t.routeDistance(aheadM!, units));
    final details = [where, ?t.warningVehicle(warning), ?warning.name].join(' · ');
    final source = [
      t.warningSource(warning),
      if (warning.certainty == RestrictionCertainty.disputed) t.navigation.warning.disputed,
      if (warning.kind == RouteWarningKind.goodsVehicleWeight) t.navigation.warning.goodsOnly,
    ].join(' · ');
    return Semantics(
      button: onTap != null,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
                child: Icon(warningIcon(warning.kind), color: glyph, size: 22),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.warningTitle(warning), style: theme.textTheme.titleMedium),
                    Text(details, style: theme.textTheme.bodyMedium),
                    Text(
                      source,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
