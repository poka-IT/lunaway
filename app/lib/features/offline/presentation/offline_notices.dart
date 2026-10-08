import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/presentation/offline_maps_screen.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/features/regions/presentation/kept_regions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// The notices over the map about what works offline. While the basemap's
/// host does not answer, a calm line: the map then shows the region
/// downloaded for this view, or says that this view has none (a tap opens
/// the offline maps where the device keeps them). Online, the offer of the
/// region the user's position entered, when there is one ([RegionOffer]).
/// Nothing otherwise.
class OfflineMapNotice extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(basemapReachabilityProvider) == false;
    final offer = offline ? null : ref.watch(regionOfferProvider);
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      child: offline
          ? const _OfflineLine(key: ValueKey('offline'))
          : offer != null
          ? _RegionOfferCard(key: ValueKey(offer.code), region: offer)
          : const SizedBox.shrink(),
    );
  }
}

class _OfflineLine extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pack = ref.watch(activeOfflinePackProvider);
    final installed = ref.watch(offlinePacksProvider).value?.installed ?? const {};
    final supported = ref.watch(offlineMapsSupportedProvider);
    // The places of the view on the device, its map not: the list and the
    // pins work, only the streets are missing.
    final placesHere = ref.watch(viewRegionProvider)?.held ?? false;
    final text = pack != null
        ? t.offlineMaps.noticePack(name: pack.name(t.$meta.locale.languageCode))
        : installed.isNotEmpty
        ? t.offlineMaps.noticeOutside
        : supported && placesHere
        ? t.offlineMaps.noticePlacesOnly
        : supported
        ? t.offlineMaps.noticeNone
        : t.offlineMaps.noticeOnline;
    return OverMap(
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
                  padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
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
    );
  }
}

/// "Bretagne : garder ses lieux hors connexion ?", its size, and the
/// download; closed, it does not come back for that region.
class _RegionOfferCard extends ConsumerWidget {
  const new({required this.region, super.key});

  final RegionInfo region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = region.nameIn(t.$meta.locale.languageCode);
    final pack = region.pack;
    final offers = ref.read(regionOfferProvider.notifier);
    return OverMap(
      child: Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Semantics(
          liveRegion: true,
          child: FloatingSurface(
            radius: LunaTokens.radiusXl,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xxs, Space.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xxs),
                      child: Icon(AppIcons.download, size: 20, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.regions.offerTitle(name: name), style: theme.textTheme.labelLarge),
                          if (pack != null)
                            Text(
                              t.regions.packInfo(
                                n: pack.places,
                                count: t.number(pack.places),
                                size: t.fileSize(pack.bytes),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(height: Space.xxs),
                          FilledButton.tonal(
                            onPressed: () => unawaited(offers.accept()),
                            child: Text(t.regions.downloadThis),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: t.regions.offerLater,
                      icon: const Icon(AppIcons.close),
                      onPressed: offers.dismiss,
                    ),
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

/// The entry to the offline maps in the profile: what the device holds
/// (the regions of places, the maps), or what it is for.
class OfflineMapsEntry extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final maps = ref.watch(offlinePacksProvider).value;
    final count = maps?.installed.length ?? 0;
    final catalog = ref.watch(regionCatalogControllerProvider).value;
    final kept = ref.watch(keptRegionsControllerProvider).value;
    final rows = catalog == null || kept == null
        ? const <KeptRegionRow>[]
        : keptRegionRows(t, catalog, kept);
    final parts = [
      if (rows.isNotEmpty && rows.length <= 2)
        t.offlineMaps.entryPlaces(names: rows.map((r) => r.name).join(', ')),
      if (rows.length > 2) t.offlineMaps.entryPlacesCount(n: rows.length),
      if (count > 0) t.offlineMaps.entryCount(n: count, size: t.fileSize(maps!.bytesNow)),
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(AppIcons.map),
      title: Text(t.offlineMaps.title),
      subtitle: Text(parts.isEmpty ? t.offlineMaps.entryHint : parts.join(' · ')),
      trailing: const Icon(AppIcons.chevron),
      onTap: () => context.push(AppRoutes.offlineMaps),
    );
  }
}
