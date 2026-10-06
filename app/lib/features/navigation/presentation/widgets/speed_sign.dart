import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The speed, and beside it the limit for the vehicle in a road sign's
/// red ring: grey when the limit is an estimate (the road's default, no
/// sign mapped), none where the limit is not known or the user turned it
/// off. Over the limit, the speed turns to the error colour on its own
/// container, and the sign with it.
class SpeedAndLimit extends ConsumerWidget {
  const new({
    required this.speedMps,
    required this.aids,
    required this.units,
    required this.color,
    super.key,
  });

  final double? speedMps;
  final DrivingAids aids;
  final DistanceUnits units;

  /// The colour of the speed on the panel.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final show = ref.watch(drivingAidsSettingsControllerProvider).value?.showSpeedLimit ?? true;
    final metric = units == DistanceUnits.metric;
    final factor = metric ? 3.6 : 2.236936;
    final speed = speedMps == null ? null : (speedMps! * factor).round();
    final shown = show ? aids.limit : null;
    final limit = shown == null ? null : (metric ? shown.kmh : shown.kmh / 1.609344).round();
    final over = shown != null && aids.overSpeed;
    final unit = metric ? t.navigation.units.kmh : t.navigation.units.mph;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: [
            '${t.navigation.guidance.speed} ${speed ?? ''}',
            if (over) t.navigation.guidance.overLimit,
          ].join(', '),
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.short),
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            decoration: BoxDecoration(
              color: over ? scheme.errorContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(LunaTokens.radiusM),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  speed == null ? '' : '$speed',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: over ? scheme.onErrorContainer : color,
                    fontWeight: over ? FontWeight.w700 : null,
                  ),
                ),
                Text(
                  unit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: over ? scheme.onErrorContainer : color,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shown != null && limit != null) ...[
          const SizedBox(width: Space.s),
          Semantics(
            label: shown.estimated
                ? '${t.navigation.guidance.limitEstimated} $limit'
                : '${t.navigation.guidance.limit} $limit',
            excludeSemantics: true,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                shape: BoxShape.circle,
                border: Border.all(
                  color: shown.estimated ? scheme.outline : scheme.error,
                  width: shown.estimated ? 3 : 5,
                ),
              ),
              child: Text(
                '$limit',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: shown.estimated ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
