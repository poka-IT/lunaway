import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/presentation/offline_maps_screen.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// A calm line over the map while the basemap's host does not answer: the
/// map then shows the region downloaded for this view, or says that this
/// view has none. Nothing shows online. A tap opens the offline maps where
/// the device keeps them.
class OfflineMapNotice extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(basemapReachabilityProvider) == false;
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pack = ref.watch(activeOfflinePackProvider);
    final installed = ref.watch(offlinePacksProvider).value?.installed ?? const {};
    final supported = ref.watch(offlineMapsSupportedProvider);
    final text = pack != null
        ? t.offlineMaps.noticePack(
            name: t.areaName(pack.id, fallback: pack.name(t.$meta.locale.languageCode)),
          )
        : installed.isNotEmpty
        ? t.offlineMaps.noticeOutside
        : supported
        ? t.offlineMaps.noticeNone
        : t.offlineMaps.noticeOnline;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      child: !offline
          ? const SizedBox.shrink()
          : OverMap(
              key: const ValueKey('offline'),
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Semantics(
                  liveRegion: true,
                  child: FloatingSurface(
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                      onTap: supported ? () => context.push(AppRoutes.offlineMaps) : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48, maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.l,
                            vertical: Space.s,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                pack != null ? OfflineIcons.ready : OfflineIcons.offline,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: Space.s),
                              Flexible(child: Text(text, style: theme.textTheme.labelLarge)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The entry to the offline maps in the profile: what the device holds, or
/// what it is for.
class OfflineMapsEntry extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final maps = ref.watch(offlinePacksProvider).value;
    final count = maps?.installed.length ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(AppIcons.map),
      title: Text(t.offlineMaps.title),
      subtitle: Text(
        count == 0
            ? t.offlineMaps.entryHint
            : t.offlineMaps.entryCount(n: count, size: t.fileSize(maps!.bytesNow)),
      ),
      trailing: const Icon(AppIcons.chevron),
      onTap: () => context.push(AppRoutes.offlineMaps),
    );
  }
}
