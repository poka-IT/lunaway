import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/presentation/region_names.dart';
import 'package:lunaway/features/regions/presentation/region_picker.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/notice_views.dart';

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
/// holds places, and while the map draws them from the API's tiles: the map
/// is then full, and the download runs behind it.
class SyncBanner extends ConsumerWidget {
  const new({this.compact = false, this.picture = true, super.key});

  /// On a phone, between the chips and the list: a smaller picture, the
  /// text first.
  final bool compact;

  /// Without it on a small phone, where the picture would push the choice
  /// of regions under the list.
  final bool picture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(placesFromTilesProvider)) return const SizedBox.shrink();
    final count = ref.watch(placeCountProvider).value;
    if (count == null || count > 0) return const SizedBox.shrink();
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(syncControllerProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    final catalog = ref.watch(regionCatalogControllerProvider).value;
    final (mood, title, hint, action) = switch (status) {
      SyncRunning(:final received, :final region, :final packBytes, :final packSize) => (
        SceneMood.empty,
        switch (region == null ? null : catalog?.byCode(region)) {
          final r? => t.regions.downloadingNamed(name: t.regionName(r)),
          null => t.map.downloading,
        },
        // A region's pack comes whole: its bytes tell the progress until
        // its places land.
        received == 0 && packSize > 0
            ? t.offlineMaps.progress(done: t.fileSize(packBytes), total: t.fileSize(packSize))
            : t.map.downloadingCount(n: received, count: t.number(received)),
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
        padding: EdgeInsets.all(compact ? Space.l : Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (picture) ...[
              NightScene(mood: mood, width: compact ? 96 : 150),
              SizedBox(height: compact ? Space.s : Space.l),
            ],
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            // Which regions download: the one where the user is, until the
            // user chooses. Above the rest: the map's sheet may cover the
            // foot of the banner.
            if (catalog != null)
              TextButton.icon(
                onPressed: () => showRegionPicker(context),
                icon: const Icon(AppIcons.map),
                label: Text(t.regions.choose),
              ),
            if (status is SyncRunning) ...[
              const SizedBox(height: Space.s),
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(LunaTokens.radiusPill)),
                child: LinearProgressIndicator(minHeight: 6),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Space.l),
              FilledButton.icon(
                onPressed: () => sync.sync(asked: true),
                icon: Icon(status is SyncFailed ? AppIcons.retry : AppIcons.download),
                label: Text(action),
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
/// Not while the map draws them from the API's tiles, which hold them all.
///
/// A notice of a state that lasts (`shared/notices.dart`): a tap beside its
/// button or a swipe up folds it into a chip, which a tap opens again; it
/// goes when the download ends, and comes back open if another one stops
/// halfway. A screen reader hears it once, not at each place counted.
class IncompleteSyncNotice extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<IncompleteSyncNotice> createState() => _IncompleteSyncNoticeState();
}

class _IncompleteSyncNoticeState extends ConsumerState<IncompleteSyncNotice> {
  final _notices = NoticeBoard();

  @override
  void dispose() {
    _notices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(placeCountProvider).value ?? 0;
    final state = ref.watch(syncStateProvider).value;
    final shown =
        !ref.watch(placesFromTilesProvider) &&
        count > 0 &&
        state != null &&
        state.completedAt == null;
    final t = context.t;
    final running = ref.watch(syncControllerProvider) is SyncRunning;
    final text = running
        ? t.sync.resuming(count: t.number(count))
        : t.sync.incomplete(count: t.number(count));
    return NoticeScope(
      board: _notices,
      // Built empty too: the board then forgets a fold whose state is over.
      child: NoticeColumn(
        centred: true,
        gap: Space.xs,
        standing: [
          if (shown)
            StandingNotice(
              id: 'incomplete-sync',
              text: text,
              icon: AppIcons.download,
              look: _IncompleteLine(text: text, running: running),
            ),
        ],
      ),
    );
  }
}

/// The notice's own look: a pill with the count and "Reprendre".
class _IncompleteLine extends ConsumerWidget {
  const new({required this.text, required this.running});

  final String text;
  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
          Flexible(child: Text(text, style: theme.textTheme.labelLarge, maxLines: 2)),
          if (!running)
            TextButton(
              onPressed: () => ref.read(syncControllerProvider.notifier).sync(asked: true),
              child: Text(context.t.sync.resume),
            )
          else
            const SizedBox(width: Space.m, height: 44),
        ],
      ),
    );
  }
}
