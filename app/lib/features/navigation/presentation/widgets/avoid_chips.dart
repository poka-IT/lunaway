import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// What a route avoids, as four switches in a row of chips that wraps.
class AvoidChips extends StatelessWidget {
  const new({required this.value, required this.onChanged, super.key});

  final AvoidOptions value;
  final ValueChanged<AvoidOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget chip(String label, {required bool on, required AvoidOptions next}) => FilterChip(
      mouseCursor: WidgetStateMouseCursor.clickable,
      label: Text(label),
      selected: on,
      onSelected: (_) {
        Haptics.select();
        onChanged(next);
      },
    );
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        chip(
          t.navigation.preview.avoidTolls,
          on: value.tolls,
          next: value.copyWith(tolls: !value.tolls),
        ),
        chip(
          t.navigation.preview.avoidMotorways,
          on: value.motorways,
          next: value.copyWith(motorways: !value.motorways),
        ),
        chip(
          t.navigation.preview.avoidFerries,
          on: value.ferries,
          next: value.copyWith(ferries: !value.ferries),
        ),
        chip(
          t.navigation.preview.avoidUnpaved,
          on: value.unpaved,
          next: value.copyWith(unpaved: !value.unpaved),
        ),
      ],
    );
  }
}
