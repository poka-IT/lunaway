import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';

/// "Around me": the six categories of points of interest, one at a time so
/// the night spots keep the map, and once one is on, "Open now" beside it.
/// A second tap on the chip turns the category off. They sit in the row of
/// the quick filters ([QuickFilters]).
List<Widget> poiCategoryChips(BuildContext context, WidgetRef ref, {required bool floating}) {
  final t = context.t;
  final choice = ref.watch(poiLayerProvider);
  final layer = ref.read(poiLayerProvider.notifier);
  return [
    for (final c in PoiCategory.values) ...[
      MapChip(
        icon: PoiLook.category(c),
        iconColor: PoiLook.tone(c),
        label: t.poiCategory(c),
        selected: choice.category == c,
        floating: floating,
        onTap: () {
          Haptics.select();
          layer.toggle(c);
        },
      ),
      if (choice.category == c)
        MapChip(
          icon: AppIcons.hours,
          label: t.poi.openNow,
          selected: choice.openNowOnly,
          floating: floating,
          onTap: () {
            Haptics.select();
            layer.setOpenNowOnly(on: !choice.openNowOnly);
          },
        ),
    ],
  ];
}
