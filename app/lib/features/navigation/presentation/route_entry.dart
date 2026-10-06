import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The id the settings keep when the user chose Lunaway's own guidance for
/// directions, beside the ids of the navigation apps.
const lunawayDirectionsId = 'lunaway';

/// "Guidage Lunaway", first in the directions chooser: the one route
/// computed for the vehicle's size. Its line says which vehicle, or that one
/// must be described first.
class LunawayGuidanceTile extends ConsumerWidget {
  const new({required this.onTap, this.selected = false, super.key});

  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vehicle = ref.watch(vehicleProvider).value;
    final ready = checkVehicle(vehicle).ready;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: const Icon(AppIcons.inAppNavigation),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.navigation.entry.lunaway,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: Space.hair),
                        Text(
                          vehicle != null && ready
                              ? t.vehicleSummary(vehicle)
                              : t.navigation.entry.vehicleMissing,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        if (ready)
                          Text(
                            t.navigation.entry.lunawayHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? AppIcons.check : AppIcons.chevron,
                    color: scheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The heading above the navigation apps, once Lunaway's own guidance is
/// offered first.
class OtherAppsHeading extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xxl, Space.l, Space.xxl, Space.xxs),
    child: Semantics(
      header: true,
      child: Text(context.t.navigation.entry.others, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
