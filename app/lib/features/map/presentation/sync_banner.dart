import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';

/// Why a sync failed, in words the user can act on.
String syncFailureText(Translations t, SyncFailure failure) => switch (failure) {
  SyncFailure.offline => t.sync.failedOffline,
  SyncFailure.busy => t.sync.failedBusy,
  SyncFailure.server => t.sync.failedServer,
  SyncFailure.refused => t.sync.failedRefused,
  SyncFailure.other => t.sync.failedOther,
};

/// Over an empty map, says why it is empty: the first download running, its
/// failure with a retry, or the invitation to download. Gone once the device
/// holds places.
class SyncBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(placeCountProvider).value;
    if (count == null || count > 0) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(syncControllerProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    final catalog = ref.watch(regionCatalogControllerProvider).value;
    final (mood, title, hint, action) = switch (status) {
      SyncRunning(:final received, :final region) => (
        SceneMood.empty,
        switch (region == null ? null : catalog?.byCode(region)) {
          final r? => t.regions.downloadingNamed(name: r.nameIn(t.$meta.locale.languageCode)),
          null => t.map.downloading,
        },
        t.map.downloadingCount(n: received, count: t.number(received)),
        null,
      ),
      SyncFailed(:final failure) => (
        SceneMood.offline,
        t.map.downloadFailed,
        syncFailureText(t, failure),
        t.common.retry,
      ),
      _ => (SceneMood.empty, t.map.noData, t.map.noDataHint, t.map.download),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: FloatingSurface(
        radius: LunaTokens.radiusXl,
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NightScene(mood: mood, width: 150),
            const SizedBox(height: Space.l),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (status is SyncRunning) ...[
              const SizedBox(height: Space.l),
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(LunaTokens.radiusPill)),
                child: LinearProgressIndicator(minHeight: 6),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Space.l),
              FilledButton.icon(
                onPressed: sync.sync,
                icon: Icon(status is SyncFailed ? AppIcons.retry : AppIcons.download),
                label: Text(action),
              ),
            ],
            // Which regions download: France and where the user is, until
            // the user chooses.
            if (catalog != null) ...[
              const SizedBox(height: Space.s),
              TextButton.icon(
                onPressed: () => showRegionPicker(context),
                icon: const Icon(AppIcons.map),
                label: Text(t.regions.choose),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A slim notice while the first full download of the region has not ended:
/// the map holds only part of the places, and says so, with a way to resume.
class IncompleteSyncNotice extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(placeCountProvider).value ?? 0;
    final state = ref.watch(syncStateProvider).value;
    if (count == 0 || state == null || state.completedAt != null) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final status = ref.watch(syncControllerProvider);
    final running = status is SyncRunning;
    return FloatingSurface(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xxs, Space.xxs, Space.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2.2))
          else
            Icon(AppIcons.download, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              running
                  ? t.sync.resuming(count: t.number(count))
                  : t.sync.incomplete(count: t.number(count)),
              style: theme.textTheme.labelLarge,
              maxLines: 2,
            ),
          ),
          if (!running)
            TextButton(
              onPressed: () => ref.read(syncControllerProvider.notifier).sync(),
              child: Text(t.sync.resume),
            )
          else
            const SizedBox(width: Space.m, height: 44),
        ],
      ),
    );
  }
}
