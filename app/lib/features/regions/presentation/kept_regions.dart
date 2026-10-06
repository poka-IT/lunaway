import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The regions whose places the device keeps, in the profile's offline
/// data: each with its places, its size and where its sync stands, a way
/// to remove it, and the picker to add others. Nothing against an API
/// without regions, or before the first sync chose them.
class KeptRegionsList extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final catalog = ref.watch(regionCatalogControllerProvider).value;
    final kept = ref.watch(keptRegionsControllerProvider).value;
    if (catalog == null || kept == null) return const SizedBox.shrink();
    final language = t.$meta.locale.languageCode;
    final states = ref.watch(regionStatesProvider).value ?? const {};
    final counts = ref.watch(regionPlaceCountsProvider).value ?? const {};
    final status = ref.watch(syncControllerProvider);
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final rows = <_Row>[];
    for (final group in catalog.groups(language)) {
      final held = group.codes.where(kept.contains).toSet();
      if (held.isEmpty) continue;
      if (group.split && held.length < group.codes.length) {
        // Part of France: its regions one by one.
        for (final r in group.regions.where((r) => held.contains(r.code))) {
          rows.add(_Row(name: r.nameIn(language), codes: {r.code}));
        }
      } else {
        rows.add(
          _Row(
            name: group.split ? t.regions.wholeFrance : group.regions.single.nameIn(language),
            codes: held,
          ),
        );
      }
    }
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.m),
        Semantics(header: true, child: Text(t.regions.kept, style: theme.textTheme.titleMedium)),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(t.regions.noneKept, style: muted),
          ),
        for (final row in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row.name),
            subtitle: Text(
              _detail(t, catalog, row.codes, states, counts, status, now),
              style: muted,
            ),
            trailing: IconButton(
              tooltip: t.regions.removeNamed(name: row.name),
              icon: const Icon(AppIcons.delete),
              onPressed: () => _remove(context, ref, row),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showRegionPicker(context),
            icon: const Icon(AppIcons.add),
            label: Text(t.regions.change),
          ),
        ),
      ],
    );
  }

  /// "2 854 lieux, 412 Ko, à jour il y a 2 h", or the download under way.
  static String _detail(
    Translations t,
    RegionCatalog catalog,
    Set<String> codes,
    Map<String, SyncState> states,
    Map<String, int> counts,
    SyncStatus status,
    DateTime now,
  ) {
    final places = codes.fold(0, (sum, c) => sum + (counts[c] ?? 0));
    final size = t.fileSize(catalog.bytesOf(codes));
    final running = status is SyncRunning && codes.contains(status.region);
    if (running && status.packSize > 0 && status.packBytes < status.packSize) {
      return t.regions.downloading(
        done: t.fileSize(status.packBytes),
        total: t.fileSize(status.packSize),
      );
    }
    if (running) return t.regions.updating(count: t.number(places), n: places);
    final dates = [for (final c in codes) states[c]?.completedAt];
    final base = t.regions.packInfo(n: places, count: t.number(places), size: size);
    if (dates.any((d) => d == null)) return '$base, ${t.regions.waiting}';
    final oldest = dates.nonNulls.reduce((a, b) => a.isBefore(b) ? a : b);
    return '$base, ${t.regions.updated(when: t.ago(oldest, now))}';
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, _Row row) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = ref.read(keptRegionsControllerProvider.notifier);
    await controller.remove(row.codes);
    showMessage(
      messenger,
      t.regions.removed(name: row.name),
      action: SnackBarAction(
        label: t.common.undo,
        onPressed: () => unawaited(controller.add(row.codes)),
      ),
    );
  }
}

/// One line of the list: a country, all of France, or one French region.
final class _Row {
  const new({required this.name, required this.codes});

  final String name;
  final Set<String> codes;
}
