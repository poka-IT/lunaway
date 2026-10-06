import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The danger zone ahead or around the vehicle ("Zone de danger dans
/// 800 m", then "Zone de danger, encore 1,2 km"), with a warning sign and
/// never a camera's picture nor its place; where a country allows points,
/// the camera ahead with its limit. Shown only where the rule of the
/// country the vehicle is in allows it (the guidance decides).
class EnforcementNotice extends StatelessWidget {
  const new({required this.alert, required this.units, super.key});

  final EnforcementAlert alert;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final camera = alert.kind == EnforcementKind.camera;
    final limit = alert.limitKmh;
    final text = switch ((camera, alert.inside)) {
      (true, _) when limit != null => t.navigation.guidance.cameraLimit(
        distance: t.routeDistance(alert.aheadM, units),
        limit: '$limit',
      ),
      (true, _) => t.navigation.guidance.cameraAhead(
        distance: t.routeDistance(alert.aheadM, units),
      ),
      (false, true) => t.navigation.guidance.inDangerZone(
        distance: t.routeDistance(alert.remainingM, units),
      ),
      (false, false) => t.navigation.guidance.dangerZone(
        distance: t.routeDistance(alert.aheadM, units),
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
          child: Row(
            children: [
              Icon(camera ? AppIcons.camera : AppIcons.warning, color: scheme.onErrorContainer),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
