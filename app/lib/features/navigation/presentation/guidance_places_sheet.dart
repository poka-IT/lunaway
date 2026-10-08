import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/guidance_camera.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/guidance_places.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

/// The guidance's places sheet: show the places and services on the map or
/// not, those of the map's own filters or a few groups a driver looks for.
/// The choice is kept for the next guidances. The map stays where it is
/// while the sheet is open.
Future<void> showGuidancePlacesSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final release = container.read(guidanceCameraProvider.notifier).hold();
  try {
    await showSheet<void>(
      context,
      // A phone on its side, or large text: the sheet scrolls rather than
      // hide its last choices.
      isScrollControlled: true,
      builder: (_) => const GuidancePlacesSheet(),
    );
  } finally {
    release();
  }
}

/// The body of the sheet, public for the tests.
class GuidancePlacesSheet extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choice =
        ref.watch(routeSettingsControllerProvider).value?.guidancePlaces ?? const GuidancePlaces();
    void set(GuidancePlaces next) =>
        unawaited(ref.read(routeSettingsControllerProvider.notifier).setGuidancePlaces(next));
    final shown = choice.shown;
    String label(GuidancePlaceGroup group) => switch (group) {
      GuidancePlaceGroup.nights => t.navigation.guidance.places.nights,
      GuidancePlaceGroup.fuel => t.navigation.guidance.places.fuel,
      GuidancePlaceGroup.water => t.navigation.guidance.places.water,
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t.navigation.guidance.places.title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.s),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: shown,
              onChanged: (on) => set(GuidancePlaces(shown: on, groups: choice.groups)),
              title: Text(t.navigation.guidance.places.show),
            ),
            const SizedBox(height: Space.s),
            Text(
              t.navigation.guidance.places.which,
              style: theme.textTheme.titleSmall?.copyWith(
                color: shown ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                FilterChip(
                  label: Text(t.navigation.guidance.places.mapFilters),
                  selected: shown && choice.mapFilters,
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  onSelected: shown ? (_) => set(const GuidancePlaces()) : null,
                ),
                for (final group in GuidancePlaceGroup.values)
                  FilterChip(
                    label: Text(label(group)),
                    selected: shown && choice.groups.contains(group),
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onSelected: shown ? (_) => set(choice.toggle(group)) : null,
                  ),
              ],
            ),
            if (shown && choice.mapFilters) ...[
              const SizedBox(height: Space.s),
              Text(
                t.navigation.guidance.places.mapFiltersHint,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
