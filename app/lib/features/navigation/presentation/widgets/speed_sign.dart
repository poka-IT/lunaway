import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The limit for the vehicle in a road sign's red ring, and beside it the
/// speed, on a pill over the map at the foot of its left side, as a
/// driver's app shows them: the sign grey when the limit is an estimate
/// (the road's default, no sign mapped), none where the limit is not known
/// or the user turned it off. Over the limit, the speed turns to the error
/// colour on its own container. With neither a speed nor a limit, nothing
/// shows: a unit without a figure reads as a fault (a browser standing
/// still gives none).
class SpeedAndLimit extends ConsumerWidget {
  const new({required this.speedMps, required this.aids, required this.units, super.key});

  final double? speedMps;
  final DrivingAids aids;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = LunaTokens.of(context);
    final show = ref.watch(drivingAidsSettingsControllerProvider).value?.showSpeedLimit ?? true;
    final metric = units == DistanceUnits.metric;
    final factor = metric ? 3.6 : 2.236936;
    final speed = speedMps == null ? null : (speedMps! * factor).round();
    final shown = show ? aids.limit : null;
    final limit = shown == null ? null : (metric ? shown.kmh : shown.kmh / 1.609344).round();
    final over = shown != null && aids.overSpeed;
    final unit = metric ? t.navigation.units.kmh : t.navigation.units.mph;
    if (speed == null && limit == null) return const SizedBox.shrink();
    return Material(
      color: tokens.floatingSurface,
      shape: const StadiumBorder(),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shown != null && limit != null)
              Semantics(
                label: shown.estimated
                    ? '${t.navigation.guidance.limitEstimated} $limit'
                    : '${t.navigation.guidance.limit} $limit',
                excludeSemantics: true,
                child: LimitSign(value: limit, estimated: shown.estimated),
              ),
            if (speed != null)
              Semantics(
                label: [
                  '${t.navigation.guidance.speed} $speed',
                  if (over) t.navigation.guidance.overLimit,
                ].join(', '),
                excludeSemantics: true,
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.short),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  margin: EdgeInsets.only(left: limit == null ? 0 : Space.xxs),
                  padding: const EdgeInsets.symmetric(horizontal: Space.s),
                  decoration: BoxDecoration(
                    color: over ? scheme.errorContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$speed',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: over ? scheme.onErrorContainer : scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      Text(
                        unit,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: over ? scheme.onErrorContainer : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A limit as a road sign gives it: the figure in a red ring, a thinner
/// grey ring when it is an estimate. The figure shrinks to stay inside
/// rather than overflow under a large text.
class LimitSign extends StatelessWidget {
  const new({required this.value, this.estimated = false, this.size = 48, this.outline, super.key});

  /// In the units the user reads, as the sign says it.
  final int value;
  final bool estimated;
  final double size;

  /// A thin rim around the sign, where its red ring would melt into a red
  /// ground (a banner over the limit).
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        shape: BoxShape.circle,
        border: Border.all(
          color: estimated ? scheme.outline : scheme.error,
          width: estimated ? size / 16 : size / 9.6,
        ),
        boxShadow: [if (outline case final rim?) BoxShadow(color: rim, spreadRadius: size / 24)],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$value',
          maxLines: 1,
          style: theme.textTheme.titleMedium?.copyWith(
            color: estimated ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
