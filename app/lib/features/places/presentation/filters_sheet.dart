import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/luna_colors.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Opens the filters: a sheet on a phone, a dialog on a wider screen. The
/// draft applies only on the button, which says how many places it keeps.
Future<void> showFiltersSheet(BuildContext context) {
  if (WindowSize.of(context) == .compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => FiltersPanel(scrollController: controller),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: const FiltersPanel(),
      ),
    ),
  );
}

class FiltersPanel extends ConsumerStatefulWidget {
  const new({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<FiltersPanel> createState() => _FiltersPanelState();
}

/// The vehicle heights the slider offers; the first stop means "any".
const List<double?> _heights = [
  null,
  1.9,
  2.0,
  2.1,
  2.2,
  2.3,
  2.4,
  2.5,
  2.6,
  2.7,
  2.8,
  2.9,
  3.0,
  3.2,
  3.4,
  3.6,
  3.8,
  4.0,
];

class _FiltersPanelState extends ConsumerState<FiltersPanel> {
  late PlaceFilter _draft = ref.read(placeFilterProvider);

  int? _lastCount;

  void _set(PlaceFilter next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final count = ref.watch(filterPreviewCountProvider(_draft));
    if (count case AsyncData(:final value)) _lastCount = value;
    final heightIndex = _heights.indexOf(_draft.vehicleHeightM).clamp(0, _heights.length - 1);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xxl, Space.l, Space.m, 0),
          child: Row(
            children: [
              Expanded(child: Text(t.filters.title, style: theme.textTheme.headlineSmall)),
              TextButton(
                onPressed: _draft.isEmpty ? null : () => _set(PlaceFilter.none),
                child: Text(t.filters.reset),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
            children: [
              _Title(t.filters.families),
              // Two columns whose rows grow with the text size, rather than a
              // grid with a fixed ratio that would clip a large font.
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final f in KindFamily.values)
                      SizedBox(
                        width: (constraints.maxWidth - 10) / 2,
                        child: _FamilyTile(
                          family: f,
                          selected: _draft.families.contains(f),
                          onTap: () => _set(_draft.toggleFamily(f)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile(
                  value: _draft.nightOk,
                  onChanged: (v) => _set(_draft.copyWith(nightOk: v)),
                  secondary: LunaIcon(LunaIcons.moonStar, color: LunaColors.of(context).allowed),
                  title: Text(t.filters.night),
                  subtitle: Text(t.filters.nightHint),
                ),
              ),
              const SizedBox(height: Space.xl),
              _Title(t.filters.amenities),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in Amenity.values)
                    FilterChip(
                      avatar: LunaIcon(LunaIcons.service(a.services.first)),
                      label: Text(t.amenity(a)),
                      selected: _draft.amenities.contains(a),
                      onSelected: (_) => _set(_draft.toggleAmenity(a)),
                    ),
                ],
              ),
              const SizedBox(height: Space.xl),
              _Title(t.filters.height),
              Text(
                _draft.vehicleHeightM == null
                    ? t.filters.heightAny
                    : t.metres(_draft.vehicleHeightM!),
                style: theme.textTheme.headlineSmall,
              ),
              Slider(
                value: heightIndex.toDouble(),
                max: (_heights.length - 1).toDouble(),
                divisions: _heights.length - 1,
                label: _draft.vehicleHeightM == null
                    ? t.filters.heightAny
                    : t.metres(_draft.vehicleHeightM!),
                onChanged: (v) => _set(_draft.copyWith(vehicleHeightM: () => _heights[v.round()])),
              ),
              Text(
                t.filters.heightHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.l),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await ref.read(settingsProvider.notifier).setFilter(_draft);
                  navigator.pop();
                },
                // While a new count loads, the last one stays: the label
                // never flickers to something else between two taps.
                child: Text(switch ((count, _lastCount)) {
                  (AsyncData(:final value), _) || (_, final int value) => t.filters.show(n: value),
                  _ => t.filters.title,
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _FamilyTile extends StatelessWidget {
  const new({required this.family, required this.selected, required this.onTap});

  final KindFamily family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = LunaColors.pinFamily(family);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? color.withValues(alpha: 0.16) : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusL),
          side: BorderSide(
            color: selected ? color : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusL),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: LunaIcon(
                    LunaIcons.family(family),
                    size: 20,
                    color: LunaTokens.of(context).onAccent,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    context.t.family(family),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (selected) Icon(AppIcons.checkCircle, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
