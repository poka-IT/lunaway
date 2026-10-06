import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// "Around me": the six categories of points of interest, one at a time
/// so the night spots keep the map, and once one is on, "Open now" beside it. A
/// second tap on the chip turns the category off. The row scrolls sideways
/// and fades at its edges, like the filters above it.
class PoiChips extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero, this.floating = true, super.key});

  /// The height the row takes, for the map's top padding.
  static const double height = 48 + Space.xs * 2;

  final EdgeInsets padding;

  /// Over the map, chips float with a shadow; in a pane they sit flat.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a search lists its results the chips give way, as the filters
    // do.
    if (ref.watch(searchQueryProvider).trim().isNotEmpty) return const SizedBox.shrink();
    final t = context.t;
    final choice = ref.watch(poiLayerProvider);
    final layer = ref.read(poiLayerProvider.notifier);
    final chips = <Widget>[
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
    return Semantics(
      container: true,
      label: t.poi.chipsLabel,
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, Space.s / rect.width, 1 - Space.xxl / rect.width, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding.add(const EdgeInsets.symmetric(vertical: Space.xs)),
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final c in chips)
                Padding(
                  padding: const EdgeInsets.only(right: Space.s),
                  child: c,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
