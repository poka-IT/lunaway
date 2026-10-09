import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The guidance's limit and alerts, in the profile's guidance settings:
/// the limit beside the speed (on by default), the road's limit said in
/// the voice's full mode (off by default), and France's speed camera
/// positions where its zones are the default (off by default), with the
/// law that applies under it and nothing else: no box, no confirmation,
/// no reminder afterwards.
class DrivingAidsSettingsTiles extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final settings =
        ref.watch(drivingAidsSettingsControllerProvider).value ?? const DrivingAidsSettings();
    final controller = ref.read(drivingAidsSettingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: settings.showSpeedLimit,
          onChanged: (on) => controller.setShowSpeedLimit(on: on),
          title: Text(t.navigation.settings.speedLimit),
          subtitle: Text(t.navigation.settings.speedLimitHint),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: settings.speedSound,
          onChanged: (on) => controller.setSpeedSound(on: on),
          title: Text(t.navigation.settings.speedSound),
          subtitle: Text(t.navigation.settings.speedSoundHint),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: settings.exactIn.contains(_france),
          onChanged: (on) => controller.setExactPositions(_france, on: on),
          title: Text(t.navigation.settings.exactFrance),
          subtitle: Text(t.navigation.settings.exactFranceHint),
          isThreeLine: true,
        ),
      ],
    );
  }
}

const _france = 'FR';
