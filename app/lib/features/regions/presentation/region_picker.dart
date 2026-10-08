import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/locate_flow.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/features/regions/presentation/region_names.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

final _log = Logger('regions');

/// Opens the choice of the regions whose places the device keeps.
Future<void> showRegionPicker(BuildContext context) =>
    showSheet<void>(context, isScrollControlled: true, builder: (context) => const RegionPicker());

/// The regions of the manifest, each with what it weighs, ticked when kept:
/// France whole or region by region, the other countries whole. "Find my
/// region" asks for the position once and ticks the region there. The
/// button downloads what is added and removes what is no longer ticked.
class RegionPicker extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends ConsumerState<RegionPicker> {
  /// What the user ticked; null until the sheet first knows the choice.
  Set<String>? _selection;

  /// The region where the user is, once known.
  String? _here;
  bool _locating = false;
  bool _franceOpen = false;
  bool _hereFailed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final catalog = ref.watch(regionCatalogControllerProvider);
    final kept = ref.watch(keptRegionsControllerProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final body = switch ((catalog, kept)) {
      (AsyncData(value: final c?), AsyncData(value: final k)) => _list(context, c, k),
      (AsyncData(value: null), _) => _Message(t.regions.unavailable),
      (AsyncError(), _) || (_, AsyncError()) => _Message(
        t.regions.listFailed,
        action: TextButton(
          onPressed: () => ref.read(regionCatalogControllerProvider.notifier).refresh(),
          child: Text(t.common.retry),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t.regions.pickerTitle, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.xs),
            Text(
              t.regions.pickerIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Space.s),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, RegionCatalog catalog, Set<String>? kept) {
    final t = context.t;
    final selection = _selection ??= {...kept ?? catalog.firstChoice(_here)};
    final held = kept ?? const <String>{};
    final added = selection.difference(held);
    final removed = held.difference(selection);
    final here = _here == null ? null : catalog.byCode(_here!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (here != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(
              t.regions.nearYou(name: t.regionName(here)),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _locating ? null : () => _findHere(catalog),
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.locate),
              label: Text(
                _locating
                    ? t.regions.locating
                    : _hereFailed
                    ? t.regions.notCovered
                    : t.regions.findMine,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final group in t.regionGroups(catalog))
                ..._group(context, catalog, group, selection),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        FilledButton(
          onPressed: added.isEmpty && removed.isEmpty && kept != null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await ref.read(keptRegionsControllerProvider.notifier).choose(selection);
                  if (navigator.mounted) navigator.pop();
                },
          child: Text(
            added.isEmpty
                ? t.common.save
                : t.regions.download(size: t.fileSize(catalog.bytesOf(added))),
          ),
        ),
      ],
    );
  }

  List<Widget> _group(
    BuildContext context,
    RegionCatalog catalog,
    RegionGroup group,
    Set<String> selection,
  ) {
    final t = context.t;
    String detail(Iterable<String> codes) {
      final regions = codes.map(catalog.byCode).nonNulls;
      if (regions.every((r) => r.pack == null)) return t.regions.noPack;
      final places = regions.fold(0, (sum, r) => sum + (r.pack?.places ?? 0));
      return t.regions.packInfo(
        n: places,
        count: t.number(places),
        size: t.fileSize(catalog.bytesOf(codes)),
      );
    }

    void toggle(Set<String> codes, {required bool on}) => setState(() {
      on ? selection.addAll(codes) : selection.removeAll(codes);
      // The few French places outside every commune go with any French
      // region kept, and leave with the last one.
      final french = selection.any((c) => catalog.byCode(c)?.frenchRegion ?? false);
      if (catalog.byCode('FR') != null) french ? selection.add('FR') : selection.remove('FR');
    });

    if (!group.split) {
      final r = group.regions.single;
      return [
        CheckboxListTile(
          value: selection.contains(r.code),
          onChanged: (on) => toggle({r.code}, on: on ?? false),
          title: Text(t.regionName(r)),
          subtitle: Text(detail({r.code})),
        ),
      ];
    }
    final ticked = group.codes.where(selection.contains).length;
    return [
      CheckboxListTile(
        tristate: true,
        value: ticked == group.codes.length ? true : (ticked == 0 ? false : null),
        onChanged: (_) => toggle(group.codes, on: ticked != group.codes.length),
        title: Text(t.regions.wholeFrance),
        subtitle: Text(detail(group.codes)),
        secondary: IconButton(
          tooltip: _franceOpen ? t.regions.hideFrance : t.regions.showFrance,
          onPressed: () => setState(() => _franceOpen = !_franceOpen),
          icon: AnimatedRotation(
            turns: _franceOpen ? 0.5 : 0,
            duration: Motion.of(context, Motion.short),
            child: const Icon(AppIcons.expand),
          ),
        ),
      ),
      if (_franceOpen)
        for (final r in group.regions)
          Padding(
            padding: const EdgeInsets.only(left: Space.xl),
            child: CheckboxListTile(
              value: selection.contains(r.code),
              onChanged: (on) => toggle({r.code}, on: on ?? false),
              title: Text(t.regionName(r)),
              subtitle: Text(detail({r.code})),
            ),
          ),
    ];
  }

  /// Asks for the position once (the considerate way), and ticks the
  /// region there.
  Future<void> _findHere(RegionCatalog catalog) async {
    final known = ref.read(userLocationProvider);
    if (known == null && !await ensureLocationAccess(context, ref)) return;
    // The sheet may have closed while the permission dialog was open.
    if (!mounted) return;
    setState(() => _locating = true);
    String? code;
    try {
      final position = known ?? (await ref.read(locationFeedProvider).current())?.position;
      final outlines = await ref.read(packOutlinesProvider.future);
      code = position == null ? null : catalog.regionAt(position, outlines);
    } on Object catch (e) {
      // No fix or no outlines: the user picks by hand, told it failed.
      _log.fine('region of the position not found', e);
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _here = code;
      _hereFailed = code == null;
      if (code != null) _selection?.add(code);
      if (code != null && catalog.byCode(code)!.frenchRegion) _franceOpen = true;
    });
  }
}

class _Message extends StatelessWidget {
  const new(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center),
        ?action,
      ],
    ),
  );
}
