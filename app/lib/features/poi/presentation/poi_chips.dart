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

/// "Around me": the chip of one category of points of interest, and once it
/// is on, "Open now" beside it. One category at a time, so the night spots
/// keep the map; a second tap turns it off. The row of the quick filters
/// ([QuickFilters]) places each category by how much it matters on the
/// road.
List<Widget> poiCategoryChip(
  BuildContext context,
  WidgetRef ref,
  PoiCategory c, {
  required bool floating,
}) {
  final t = context.t;
  final choice = ref.watch(poiLayerProvider);
  final layer = ref.read(poiLayerProvider.notifier);
  return [
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
  ];
}
