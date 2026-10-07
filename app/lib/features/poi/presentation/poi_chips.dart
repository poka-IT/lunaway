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
import 'package:lunaway/shared/theme/tokens.dart';

/// "Around me": the chip of one category of points of interest, and once it
/// is on, "Open now" beside it. One category at a time, so the night spots
/// keep the map; a second tap turns it off. The row of the quick filters
/// ([QuickFilters]) places each category by how much it matters on the
/// road. The vending machines' chip first asks what the machines should
/// sell ([showVendingMenu]): pizza alone, say, and the chip then names it.
List<Widget> poiCategoryChip(
  BuildContext context,
  WidgetRef ref,
  PoiCategory c, {
  required bool floating,
}) {
  final t = context.t;
  final choice = ref.watch(poiLayerProvider);
  final layer = ref.read(poiLayerProvider.notifier);
  final on = choice.category == c;
  final kind = on ? choice.vending : null;
  return [
    Builder(
      builder: (chipContext) => MapChip(
        icon: kind == null ? PoiLook.category(c) : PoiLook.kind(kind),
        iconColor: PoiLook.tone(c),
        label: kind == null ? t.poiCategory(c) : t.poiVendingChip(kind),
        selected: on,
        floating: floating,
        // A screen reader hears that this chip asks a choice first.
        semanticsLabel: c == PoiCategory.vending && !on
            ? t.poi.vendingMenu
            : null,
        onTap: () async {
          Haptics.select();
          if (c != PoiCategory.vending || on) return layer.toggle(c);
          final picked = await showVendingMenu(chipContext);
          if (picked != null) layer.showVending(picked.kind);
        },
      ),
    ),
    if (on)
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

/// The vending chip's small menu, under the chip of [chipContext]: what
/// the machines sell, pizza first, then every machine. Null when it is
/// dismissed; a null kind inside asks for every machine.
Future<({PoiKind? kind})?> showVendingMenu(BuildContext chipContext) {
  final t = chipContext.t;
  final box = chipContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(chipContext).context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(
    Offset(0, box.size.height),
    ancestor: overlay,
  );
  const tone = PoiCategory.vending;
  PopupMenuItem<({PoiKind? kind})> item(
    PoiKind? kind,
    IconData icon,
    String label,
  ) => PopupMenuItem(
    value: (kind: kind),
    child: Row(
      children: [
        Icon(icon, color: PoiLook.tone(tone)),
        const SizedBox(width: Space.m),
        Flexible(child: Text(label)),
      ],
    ),
  );
  return showMenu<({PoiKind? kind})>(
    context: chipContext,
    position: RelativeRect.fromRect(
      topLeft & Size.zero,
      Offset.zero & overlay.size,
    ),
    semanticLabel: t.poi.vendingMenu,
    items: [
      for (final kind in PoiKind.vendingChoices)
        item(kind, PoiLook.kind(kind), t.poiVendingSells(kind)),
      const PopupMenuDivider(),
      item(null, PoiLook.category(tone), t.poi.vendingAll),
    ],
  );
}
