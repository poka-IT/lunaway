import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_height_entry.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';
import 'package:lunaway/shared/widgets/night_badge.dart';

/// Opens the filters: a sheet on a phone, a dialog on a wider screen. The
/// draft applies only on the button, which says how many places it keeps.
Future<void> showFiltersSheet(BuildContext context) {
  if (WindowSize.of(context) == .compact) {
    return showSheet<void>(
      context,
      // Above the dock and the panels: the shell holds the branches.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      // The panel draws its own handle inside its header: no empty band
      // above the title.
      handle: false,
      // Above the keyboard: the height of the vehicle is typed in the sheet.
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: const FractionallySizedBox(heightFactor: 0.92, child: FiltersPanel()),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
        child: const FiltersPanel(),
      ),
    ),
  );
}

class FiltersPanel extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends ConsumerState<FiltersPanel> {
  late PlaceFilter _draft = ref.read(placeFilterProvider);
  int? _lastCount;

  void _set(PlaceFilter next) {
    Haptics.select();
    setState(() => _draft = next);
  }

  /// Asks the dates of the stay, from today to a year ahead; the filter
  /// keeps the places open every night of it.
  Future<void> _pickStay() async {
    final t = context.t;
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(today.year + 1, today.month, today.day);
    // The dates chosen before, to change them, from today once the stay
    // has begun; tonight when there are none, or when they end past the
    // calendar's last day (it refuses a range outside its days).
    // Without a range, Material's header sets "Date de début" in a slot
    // that cannot shrink, wider than a 400 dp phone in the app's type.
    // A stay holds UTC midnights: its days are read on their fields.
    final chosen = switch (_draft.opening) {
      StayOpening(:final arrival, :final departure) => DateTimeRange(
        start: DateTime(arrival.year, arrival.month, arrival.day),
        end: DateTime(departure.year, departure.month, departure.day),
      ),
      _ => null,
    };
    final initial = switch (chosen) {
      DateTimeRange(:final start, :final end) when !end.isBefore(today) && !end.isAfter(lastDate) =>
        DateTimeRange(start: start.isBefore(today) ? today : start, end: end),
      _ => DateTimeRange(start: today, end: DateTime(now.year, now.month, now.day + 1)),
    };
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: lastDate,
      currentDate: today,
      initialDateRange: initial,
      helpText: t.filters.openingStayTitle,
      fieldStartLabelText: t.filters.openingArrival,
      fieldEndLabelText: t.filters.openingDeparture,
    );
    if (range == null || !mounted) return;
    _set(_draft.copyWith(opening: () => StayOpening(range.start, range.end)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = ref.watch(filterPreviewCountProvider(_draft));
    if (count case AsyncData(:final value)) _lastCount = value;
    final vehicle = ref.watch(vehicleProvider).value;
    final compact = WindowSize.of(context) == .compact;
    return Column(
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xxl, Space.m, Space.m, Space.xs),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t.filters.title, style: theme.textTheme.headlineMedium),
                ),
              ),
              TextButton(
                onPressed: _draft.isEmpty ? null : () => _set(PlaceFilter.none),
                child: Text(t.filters.reset),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
            children: [
              // What a night on the road needs first: may one sleep there,
              // with water and a dump station, will the vehicle fit; then the
              // kind of place and the price.
              _Title(
                t.filters.night,
                // The hint says what the section does now: every place while
                // nothing is chosen, only the chosen statuses after.
                hint: _draft.overnight.isEmpty ? t.filters.nightHint : t.filters.nightChosenHint,
              ),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final o in OvernightStatus.values)
                    _ToggleChip(
                      leading: NightBadge(o),
                      label: t.overnightShort(o),
                      selected: _draft.overnight.contains(o),
                      onTap: () => _set(_draft.toggleOvernight(o)),
                    ),
                ],
              ),
              const SizedBox(height: Space.xxl),
              _Title(t.filters.amenities, hint: t.filters.amenitiesHint),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final a in Amenity.offered)
                    _ToggleChip(
                      leading: Icon(AppIcons.amenity(a), size: 20),
                      label: t.amenity(a),
                      selected: _draft.amenities.contains(a),
                      onTap: () => _set(_draft.toggleAmenity(a)),
                    ),
                ],
              ),
              const SizedBox(height: Space.xxl),
              _Title(t.filters.rating, hint: t.filters.ratingHint),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final step in minRatingSteps)
                    _ToggleChip(
                      leading: const Icon(AppIcons.star, size: 20),
                      label: t.filters.ratingAtLeast(rating: t.ratingStep(step)),
                      selected: _draft.minRating == step,
                      onTap: () => _set(_draft.toggleMinRating(step)),
                    ),
                ],
              ),
              const SizedBox(height: Space.xxl),
              _Title(t.filters.opening, hint: t.filters.openingHint),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  _ToggleChip(
                    leading: const Icon(AppIcons.openAllYear, size: 20),
                    label: t.filters.openingAllYear,
                    selected: _draft.opening is AllYearOpening,
                    onTap: () => _set(_draft.toggleAllYear()),
                  ),
                  // Once chosen, the chip says the dates and a tap changes
                  // them; the button beside it clears them.
                  switch (_draft.opening) {
                    StayOpening(:final arrival, :final departure) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: _ToggleChip(
                            leading: const Icon(AppIcons.stayDates, size: 20),
                            label: t.stay(arrival, departure),
                            selected: true,
                            onTap: _pickStay,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(AppIcons.close),
                          tooltip: t.filters.openingClearDates,
                          onPressed: () => _set(_draft.copyWith(opening: () => null)),
                        ),
                      ],
                    ),
                    _ => _ToggleChip(
                      leading: const Icon(AppIcons.stayDates, size: 20),
                      label: t.filters.openingDates,
                      selected: false,
                      onTap: _pickStay,
                    ),
                  },
                ],
              ),
              const SizedBox(height: Space.xxl),
              _Title(t.filters.vehicle),
              // A Material, not a coloured box: the switch row's ink shows.
              Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(LunaTokens.radiusL),
                clipBehavior: Clip.antiAlias,
                child: vehicle?.heightM == null
                    // No height yet: the card asks for it, so the filter is
                    // one entry away rather than behind the full editor.
                    ? Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(AppIcons.vehicleFits),
                                const SizedBox(width: Space.l),
                                Expanded(
                                  child: Text(
                                    t.filters.myVehicleFits,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: Space.xs),
                            Text(
                              t.vehicleHeight.why,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: Space.l),
                            VehicleHeightEntry(
                              onSaved: (_) {
                                // The panel may have closed while the height
                                // was being stored.
                                if (mounted) _set(_draft.copyWith(fitsMyVehicle: true));
                              },
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          SwitchListTile(
                            value: _draft.fitsMyVehicle,
                            secondary: const Icon(AppIcons.vehicleFits),
                            title: Text(t.filters.myVehicleFits),
                            subtitle: Text(
                              t.filters.myVehicleHint(height: t.metres(vehicle!.heightM!)),
                            ),
                            onChanged: (on) => _set(_draft.copyWith(fitsMyVehicle: on)),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
                              child: TextButton.icon(
                                onPressed: () => showVehicleEditor(context),
                                icon: const Icon(AppIcons.rename, size: 18),
                                label: Text(t.vehicle.edit),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: Space.xxl),
              _Title(
                t.filters.families,
                hint: _draft.families.isEmpty
                    ? t.filters.familiesHint
                    : t.filters.familiesChosenHint,
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = (constraints.maxWidth - Space.s) / 2;
                  return Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final f in KindFamily.values)
                        SizedBox(
                          width: w,
                          child: _FamilyCard(
                            family: f,
                            selected: _draft.families.contains(f),
                            onTap: () => _set(_draft.toggleFamily(f)),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: Space.xxl),
              _Title(t.filters.price, hint: t.filters.freeHint),
              Wrap(
                children: [
                  _ToggleChip(
                    leading: const Icon(AppIcons.free, size: 20),
                    label: t.filters.freeOnly,
                    selected: _draft.freeOnly,
                    onTap: () => _set(_draft.copyWith(freeOnly: !_draft.freeOnly)),
                  ),
                ],
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.m, Space.xxl, Space.m),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    Haptics.confirm();
                    await ref.read(settingsProvider.notifier).setFilter(_draft);
                    navigator.pop();
                  },
                  // While a new count loads, the last one stays: the label
                  // never flickers to something else between two taps.
                  child: Text(switch ((count, _lastCount)) {
                    (AsyncData(:final value), _) ||
                    (_, final int value) => t.filters.show(n: value, count: t.number(value)),
                    _ => t.filters.apply,
                  }),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const new(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(text, style: theme.textTheme.titleLarge)),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// A family as a card: its pin colour and glyph, its name, and what it
/// gathers.
class _FamilyCard extends StatelessWidget {
  const new({required this.family, required this.selected, required this.onTap});

  final KindFamily family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = LunaTokens.familyFill(family);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(40 * 0.32),
                      ),
                      alignment: Alignment.center,
                      child: Icon(AppIcons.family(family), size: 22, color: LunaTokens.pinGlyph),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: Motion.of(context, Motion.short),
                      opacity: selected ? 1 : 0,
                      child: Icon(AppIcons.checkCircle, color: scheme.onSurface, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(t.family(family), style: theme.textTheme.titleSmall),
                const SizedBox(height: Space.hair),
                Text(
                  t.familyHint(family),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip that turns amber when on.
class _ToggleChip extends StatelessWidget {
  const new({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(color: scheme.onSurface),
                  child: leading,
                ),
                const SizedBox(width: Space.s),
                Flexible(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
