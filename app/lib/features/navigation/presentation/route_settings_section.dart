import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/driving_aids_settings.dart';
import 'package:lunaway/features/navigation/presentation/widgets/avoid_chips.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/segmented.dart';

/// The guidance settings of the profile: what routes avoid by default, the
/// voice, the units. Drawn like the profile's other groups.
class RouteSettingsSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(routeSettingsControllerProvider).value ?? const NavigationSettings();
    final controller = ref.read(routeSettingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.s),
          child: Row(
            children: [
              Icon(AppIcons.inAppNavigation, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: Space.s),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t.navigation.settings.title, style: theme.textTheme.titleLarge),
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
                    child: Text(
                      t.navigation.settings.avoidTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                    child: AvoidChips(value: settings.avoid, onChanged: controller.setAvoid),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.navigation.settings.voice, style: theme.textTheme.titleMedium),
                        const SizedBox(height: Space.s),
                        LunaSegmented<VoiceMode>(
                          segments: [
                            Segment(value: VoiceMode.full, label: t.navigation.settings.voiceFull),
                            Segment(
                              value: VoiceMode.alerts,
                              label: t.navigation.settings.voiceAlerts,
                            ),
                            Segment(
                              value: VoiceMode.muted,
                              label: t.navigation.settings.voiceMuted,
                            ),
                          ],
                          selected: settings.voiceMode,
                          onChanged: controller.setVoiceMode,
                        ),
                        const SizedBox(height: Space.s),
                        // What the mode chosen says, told as it changes.
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            switch (settings.voiceMode) {
                              VoiceMode.full => t.navigation.settings.voiceFullHint,
                              VoiceMode.alerts => t.navigation.settings.voiceAlertsHint,
                              VoiceMode.muted => t.navigation.settings.voiceMutedHint,
                            },
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  const DrivingAidsSettingsTiles(),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.navigation.settings.units, style: theme.textTheme.titleMedium),
                        const SizedBox(height: Space.s),
                        LunaSegmented<DistanceUnits>(
                          segments: [
                            Segment(
                              value: DistanceUnits.metric,
                              label: t.navigation.settings.metric,
                            ),
                            Segment(
                              value: DistanceUnits.imperial,
                              label: t.navigation.settings.imperial,
                            ),
                          ],
                          selected: settings.units,
                          onChanged: controller.setUnits,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
