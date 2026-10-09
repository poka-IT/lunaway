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
import 'package:lunaway/features/regions/presentation/region_names.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/notice_views.dart';
import 'package:lunaway/shared/widgets/over_map.dart';

/// The notices over the map about what works offline. While the basemap's
/// host does not answer, a calm line: the map then shows the region
/// downloaded for this view, or says that this view has none (a tap opens
/// the offline maps where the device keeps them). Online, the offer of the
/// region the user's position entered, when there is one ([RegionOffer]).
/// Nothing otherwise.
///
/// The offline line is a notice of a state that lasts (`shared/notices.dart`):
/// a swipe up folds it into a chip, which opens again by itself when the
/// map loses its downloaded region, and both go when the network is back.
class OfflineMapNotice extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OfflineMapNotice> createState() => _OfflineMapNoticeState();
}

class _OfflineMapNoticeState extends ConsumerState<OfflineMapNotice> {
  final _notices = NoticeBoard();

  @override
  void dispose() {
    _notices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(basemapReachabilityProvider) == false;
    final offer = offline ? null : ref.watch(regionOfferProvider);
    return NoticeScope(
      board: _notices,
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.medium),
        child: offline
            ? const _OfflineLine(key: ValueKey('offline'))
            : offer != null
            ? _RegionOfferCard(key: ValueKey(offer.code), region: offer)
            : const SizedBox.shrink(),
      ),
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
        ? t.offlineMaps.noticePack(
            name: t.areaName(pack.id, fallback: pack.name(t.$meta.locale.languageCode)),
          )
        : installed.isNotEmpty
        ? t.offlineMaps.noticeOutside
        : supported && placesHere
        ? t.offlineMaps.noticePlacesOnly
        : supported
        ? t.offlineMaps.noticeNone
        : t.offlineMaps.noticeOnline;
    final icon = pack != null ? OfflineIcons.ready : OfflineIcons.offline;
    final open = supported ? () => context.push(AppRoutes.offlineMaps) : null;
    // One node for its words and its tap, told once to a screen reader (the
    // column's first frame), not at each region the view crosses.
    // Built under the notice (Builder), where it learns whether it is told.
    final line = Builder(
      builder: (context) => Semantics(
        container: true,
        liveRegion: NoticeLive.of(context),
        button: open != null,
        label: text,
        onTap: open,
        excludeSemantics: true,
        child: FloatingSurface(
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            onTap: open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: Space.s),
                    Flexible(child: Text(text, style: theme.textTheme.labelLarge)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return NoticeColumn(
      centred: true,
      gap: Space.xs,
      standing: [
        StandingNotice(
          id: 'offline',
          text: text,
          icon: icon,
          // A downloaded map for the view is the milder state.
          level: pack != null ? 1 : 2,
          look: line,
        ),
      ],
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
    final name = t.regionName(region);
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
                      tooltip: t.common.close,
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
