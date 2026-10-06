import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
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
                  ListTile(
                    title: Text(t.navigation.settings.fuel),
                    trailing: DropdownButton<VehicleFuel>(
                      value: settings.fuel,
                      underline: const SizedBox.shrink(),
                      onChanged: (f) {
                        if (f != null) unawaited(controller.setFuel(f));
                      },
                      items: [
                        for (final f in VehicleFuel.values)
                          DropdownMenuItem(value: f, child: Text(t.fuelName(f))),
                      ],
                    ),
                  ),
                  ConsumptionTile(
                    litres: settings.consumptionL100,
                    onChanged: (l) => unawaited(controller.setConsumption(l)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: settings.voice,
                    onChanged: (on) => controller.setVoice(on: on),
                    title: Text(t.navigation.settings.voice),
                    subtitle: Text(t.navigation.settings.voiceHint),
                  ),
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

/// The vehicle's consumption, in litres per 100 km: typed, kept within the
/// range the settings accept, saved as it is typed.
class ConsumptionTile extends StatefulWidget {
  const new({required this.litres, required this.onChanged, super.key});

  final double litres;
  final ValueChanged<double> onChanged;

  @override
  State<ConsumptionTile> createState() => _ConsumptionTileState();
}

class _ConsumptionTileState extends State<ConsumptionTile> {
  late final _text = TextEditingController(text: _format(widget.litres));

  static String _format(double litres) =>
      litres == litres.roundToDouble() ? '${litres.round()}' : litres.toStringAsFixed(1);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    const range = NavigationSettings.consumptionRange;
    return ListTile(
      title: Text(t.navigation.settings.consumption),
      subtitle: Text(t.navigation.settings.consumptionHint),
      trailing: SizedBox(
        width: 132,
        child: TextField(
          controller: _text,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          decoration: InputDecoration(
            isDense: true,
            suffixText: t.navigation.settings.consumptionUnit,
          ),
          onChanged: (raw) {
            final litres = double.tryParse(raw.replaceAll(',', '.'));
            if (litres != null && litres >= range.min && litres <= range.max) {
              widget.onChanged(litres);
            }
          },
        ),
      ),
    );
  }
}
