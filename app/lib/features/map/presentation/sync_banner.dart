import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

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
    final status = ref.watch(syncControllerProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    final (icon, title, hint, action) = switch (status) {
      SyncRunning(:final received) => (
        null,
        t.map.downloading,
        t.map.downloadingCount(n: received),
        null,
      ),
      SyncFailed() => (AppIcons.offline, t.map.downloadFailed, null, t.common.retry),
      _ => (AppIcons.downloadOffline, t.map.noData, t.map.noDataHint, t.map.download),
    };
    return OverMap(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: LunaTokens.of(context).floatingElevation,
          shadowColor: LunaTokens.of(context).shadowStrong,
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon == null)
                  const SizedBox.square(dimension: 40, child: CircularProgressIndicator())
                else
                  Icon(
                    icon,
                    size: 40,
                    color: status is SyncFailed
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                const SizedBox(height: Space.ml),
                Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                if (hint != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: Space.l),
                  FilledButton.icon(
                    onPressed: sync.sync,
                    icon: const Icon(AppIcons.download),
                    label: Text(action),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
