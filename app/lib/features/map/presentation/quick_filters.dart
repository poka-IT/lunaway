import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/presentation/filters_sheet.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The filters a traveller flips most, one tap each, and the button to the
/// full filter sheet with the count of active filters.
class QuickFilters extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero, this.floating = true, super.key});

  final EdgeInsets padding;

  /// Over the map, chips need a solid background and a shadow to stand out.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a search lists its results the chips give way: below the results
    // they would float at the bottom of the screen, cut from their row.
    if (ref.watch(searchQueryProvider).trim().isNotEmpty) return const SizedBox.shrink();
    final t = context.t;
    final filter = ref.watch(placeFilterProvider);
    final settings = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final background = floating ? theme.colorScheme.surfaceContainerHigh : null;
    final elevation = floating ? 2.0 : 0.0;
    Widget chip({
      required Widget avatar,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(right: Space.s),
      child: FilterChip(
        avatar: avatar,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: background,
        elevation: elevation,
        shadowColor: LunaTokens.of(context).shadow,
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: Badge(
              isLabelVisible: filter.activeCount > 0,
              // The count alone says nothing to a screen reader.
              label: Semantics(
                label: t.filters.active(n: filter.activeCount),
                excludeSemantics: true,
                child: Text('${filter.activeCount}'),
              ),
              child: ActionChip(
                avatar: const Icon(AppIcons.filters),
                label: Text(t.map.filters),
                onPressed: () => showFiltersSheet(context),
                backgroundColor: background,
                elevation: elevation,
                shadowColor: LunaTokens.of(context).shadow,
              ),
            ),
          ),
          chip(
            avatar: const LunaIcon(LunaIcons.moonStar),
            label: t.filters.night,
            selected: filter.nightOk,
            onTap: () => settings.setFilter(filter.copyWith(nightOk: !filter.nightOk)),
          ),
          for (final a in Amenity.values)
            chip(
              avatar: LunaIcon(LunaIcons.service(a.services.first)),
              label: t.amenity(a),
              selected: filter.amenities.contains(a),
              onTap: () => settings.setFilter(filter.toggleAmenity(a)),
            ),
        ],
      ),
    );
  }
}
