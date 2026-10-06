import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/filters_sheet.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// The filters a traveller flips most, one tap each, after the button to the
/// full filter sheet with the count of active filters. The row scrolls
/// sideways and fades at its edges, so a chip cut by the screen edge reads
/// as "more this way" rather than as a mistake.
class QuickFilters extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero, this.floating = true, super.key});

  final EdgeInsets padding;

  /// Over the map, chips float with a shadow; in a pane they sit flat.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a search lists its results the chips give way: below the results
    // they would float at the bottom of the screen, cut from their row.
    if (ref.watch(searchQueryProvider).trim().isNotEmpty) return const SizedBox.shrink();
    final t = context.t;
    final filter = ref.watch(placeFilterProvider);
    final settings = ref.read(settingsProvider.notifier);
    final vehicle = ref.watch(vehicleProvider).value;

    Future<void> apply(PlaceFilter next) async {
      Haptics.select();
      await settings.setFilter(next);
    }

    final chips = <Widget>[
      MapChip(
        icon: AppIcons.filters,
        label: t.map.filters,
        count: filter.activeCount,
        semanticsLabel: filter.activeCount == 0 ? null : t.filters.active(n: filter.activeCount),
        floating: floating,
        onTap: () => showFiltersSheet(context),
      ),
      MapChip(
        leading: const NightBadge(OvernightStatus.allowed),
        label: t.filters.nightPossible,
        selected: filter.nightOk,
        floating: floating,
        onTap: () => apply(filter.withNightOk(on: !filter.nightOk)),
      ),
      for (final a in Amenity.quick)
        MapChip(
          icon: AppIcons.amenity(a),
          label: t.amenity(a),
          selected: filter.amenities.contains(a),
          floating: floating,
          onTap: () => apply(filter.toggleAmenity(a)),
        ),
      MapChip(
        icon: AppIcons.vehicleFits,
        label: vehicle?.heightM == null
            ? t.filters.myVehicleFits
            : t.filters.myVehicleFitsHeight(height: t.metres(vehicle!.heightM!)),
        selected: filter.fitsMyVehicle,
        floating: floating,
        onTap: () async {
          if (!filter.fitsMyVehicle && vehicle?.heightM == null) {
            // First use: the filter needs the vehicle's size, asked once.
            final saved = await showVehicleEditor(
              context,
              reason: VehicleEditorReason.heightFilter,
            );
            if (saved == null || saved.heightM == null) return;
          }
          await apply(filter.copyWith(fitsMyVehicle: !filter.fitsMyVehicle));
        },
      ),
    ];
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, Space.s / rect.width, 1 - Space.xxl / rect.width, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Room for the chips' shadows inside the faded strip.
        padding: padding.add(const EdgeInsets.symmetric(vertical: Space.s)),
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
    );
  }
}

/// A chip over the map: a floating pill, amber-tinted when on. Shared with
/// the row of the points of interest (`features/poi`).
class MapChip extends StatelessWidget {
  const new({
    required this.label,
    required this.onTap,
    required this.floating,
    this.icon,
    this.iconColor,
    this.leading,
    this.selected = false,
    this.count = 0,
    this.semanticsLabel,
    super.key,
  });

  final IconData? icon;

  /// The icon's colour; the theme's text colour by default.
  final Color? iconColor;
  final Widget? leading;
  final String label;
  final bool selected;
  final int count;
  final bool floating;
  final String? semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = LunaTokens.of(context);
    final background = selected
        ? scheme.primaryContainer
        : floating
        ? tokens.floatingSurface
        : scheme.surfaceContainerHigh;
    return OverMap(
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticsLabel == null ? null : '$label, $semanticsLabel',
        excludeSemantics: semanticsLabel != null,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.short),
          // 48 dp: the smallest touch target of the design rules.
          height: 48,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (floating ? Colors.transparent : scheme.outlineVariant),
              width: 1.5,
            ),
            boxShadow: floating ? tokens.floatingShadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.ml),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?leading,
                    if (icon != null) Icon(icon, size: 20, color: iconColor ?? scheme.onSurface),
                    const SizedBox(width: Space.s),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge,
                      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: Space.s),
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$count',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: scheme.onPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
