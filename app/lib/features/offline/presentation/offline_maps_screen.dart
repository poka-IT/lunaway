import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/domain/packs.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/presentation/kept_regions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/sub_page.dart';

/// "Offline maps", under the profile: first the places of the regions the
/// device keeps (each with its size, all of France and the other countries
/// one choice away, mobile data or not for the updates), then the maps:
/// the regions of the basemap's manifest with their size, the downloads
/// with their progress (pause, resume), the packs on the device (update,
/// delete), the room they take, and the regions to suggest (where the
/// traveller is, where the favourites are). On the web, one plain sentence:
/// the map needs the network there; on the desktops, the places and that
/// sentence for the maps.
class OfflineMapsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final places = [
      if (ref.watch(keepsPlacesProvider) &&
          ref.watch(regionCatalogControllerProvider).value != null) ...[
        _Part(title: t.offlineMaps.placesTitle, hint: t.offlineMaps.placesHint),
        const SectionCard(child: KeptRegionsList()),
      ],
    ];
    if (!ref.watch(offlineMapsSupportedProvider)) {
      return SubPage(
        title: t.offlineMaps.title,
        subtitle: places.isEmpty ? null : t.offlineMaps.intro,
        children: [
          ...places,
          if (places.isNotEmpty) _Part(title: t.offlineMaps.mapsTitle),
          MessageView(
            mood: SceneMood.offline,
            title: kIsWeb ? t.offlineMaps.webTitle : t.offlineMaps.desktopTitle,
            hint: kIsWeb ? t.offlineMaps.web : t.offlineMaps.desktop,
            compact: true,
          ),
        ],
      );
    }
    final maps = ref.watch(offlinePacksProvider);
    final catalog = ref.watch(packCatalogProvider);
    return SubPage(
      title: t.offlineMaps.title,
      subtitle: t.offlineMaps.intro,
      children: [
        ...places,
        if (places.isNotEmpty) _Part(title: t.offlineMaps.mapsTitle, hint: t.offlineMaps.mapsHint),
        ...switch (maps) {
          AsyncValue(value: final value?) => [
            _Storage(maps: value),
            ..._transfers(context, value),
            ..._installed(context, value, catalog.value),
            ..._catalog(context, ref, value, catalog),
          ],
          AsyncError() => [
            MessageView(mood: SceneMood.error, title: t.offlineMaps.unreadable, compact: true),
          ],
          _ => const [SkeletonTile(), SkeletonTile(), SkeletonTile()],
        },
      ],
    );
  }

  List<Widget> _transfers(BuildContext context, OfflineMaps maps) {
    if (maps.transfers.isEmpty) return const [];
    final t = context.t;
    return [
      _Heading(t.offlineMaps.downloads),
      SectionCard(
        child: Column(
          children: [
            for (final transfer in maps.transfers.values) _TransferRow(transfer: transfer),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
        child: Text(
          t.offlineMaps.keepOpen,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  List<Widget> _installed(BuildContext context, OfflineMaps maps, PackCatalog? catalog) {
    if (maps.installed.isEmpty) return const [];
    final t = context.t;
    final language = t.$meta.locale.languageCode;
    final installed = maps.installed.values.toList()
      ..sort((a, b) => a.name(language).compareTo(b.name(language)));
    return [
      _Heading(t.offlineMaps.installed),
      SectionCard(
        child: Column(
          children: [
            for (final pack in installed)
              _InstalledRow(
                pack: pack,
                newer: switch (catalog?.manifest.byId(pack.id)) {
                  final info? when info.build.compareTo(pack.build) > 0 => info,
                  _ => null,
                },
                catalog: catalog,
                updating: maps.transfers.containsKey(pack.id),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _catalog(
    BuildContext context,
    WidgetRef ref,
    OfflineMaps maps,
    AsyncValue<PackCatalog> catalog,
  ) {
    final t = context.t;
    return switch (catalog) {
      AsyncValue(value: final c?) => [
        if (c.fromCopy)
          Padding(
            padding: const EdgeInsets.only(top: Space.l),
            child: Text(
              t.offlineMaps.listCopy,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ..._suggestions(context, ref, maps, c),
        for (final group in PackGroup.values)
          if (_available(c, maps, group, t.$meta.locale.languageCode) case final packs
              when packs.isNotEmpty) ...[
            _Heading(_groupName(t, group)),
            SectionCard(
              child: Column(
                children: [for (final p in packs) _CatalogRow(pack: p, catalog: c)],
              ),
            ),
          ],
      ],
      AsyncError() => [
        const SizedBox(height: Space.l),
        MessageView(
          mood: SceneMood.offline,
          title: t.offlineMaps.listOffline,
          action: t.common.retry,
          onAction: () => ref.invalidate(packCatalogProvider),
          compact: true,
        ),
      ],
      _ => const [SizedBox(height: Space.l), SkeletonTile(), SkeletonTile()],
    };
  }

  /// The packs of [group] neither installed nor downloading, by name.
  static List<PackInfo> _available(
    PackCatalog c,
    OfflineMaps maps,
    PackGroup group,
    String language,
  ) => [
    for (final p in c.manifest.packs)
      if (p.group == group &&
          !maps.installed.containsKey(p.id) &&
          !maps.transfers.containsKey(p.id))
        p,
  ]..sort((a, b) => _sortKey(a.name(language)).compareTo(_sortKey(b.name(language))));

  /// A name as an index reads it: "Île-de-France" among the I.
  static String _sortKey(String name) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final lower = name.toLowerCase();
    final out = StringBuffer();
    for (final c in lower.split('')) {
      final i = from.indexOf(c);
      out.write(i < 0 ? c : to[i]);
    }
    return out.toString();
  }

  static String _groupName(Translations t, PackGroup g) => switch (g) {
    PackGroup.france => t.offlineMaps.france,
    PackGroup.overseas => t.offlineMaps.overseas,
    PackGroup.countries => t.offlineMaps.countries,
  };

  /// Where the traveller is, then where the favourites are, among the packs
  /// not on the device yet.
  List<Widget> _suggestions(BuildContext context, WidgetRef ref, OfflineMaps maps, PackCatalog c) {
    final t = context.t;
    final outlines = ref.watch(packOutlinesProvider).value ?? PackOutlines.empty;
    final here = ref.watch(userLocationProvider) ?? ref.watch(initialPositionProvider);
    final favorites = ref.watch(favoritePositionsProvider).value ?? const <LatLng>[];
    bool missing(PackInfo p) =>
        !maps.installed.containsKey(p.id) && !maps.transfers.containsKey(p.id);
    PackInfo? at(LatLng point) => packAt(
      c.manifest.packs,
      point,
      outlines: outlines,
      id: (p) => p.id,
      bounds: (p) => p.bounds,
    );
    final local = here == null ? null : at(here);
    final counts = <String, int>{};
    for (final f in favorites) {
      if (at(f) case final p?) counts[p.id] = (counts[p.id] ?? 0) + 1;
    }
    final byFavorites = [
      for (final e in (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
        if (c.manifest.byId(e.key) case final p? when missing(p) && p.id != local?.id) (p, e.value),
    ].take(3).toList();
    final rows = [
      if (local != null && missing(local))
        _CatalogRow(pack: local, catalog: c, reason: t.offlineMaps.here),
      for (final (p, n) in byFavorites)
        _CatalogRow(
          pack: p,
          catalog: c,
          reason: t.offlineMaps.favoritesHere(n: n),
        ),
    ];
    if (rows.isEmpty) return const [];
    return [_Heading(t.offlineMaps.suggested), SectionCard(child: Column(children: rows))];
  }
}

/// One of the screen's two parts, the places and the maps: a heading above
/// the sections of the part, and what it is for.
class _Part extends StatelessWidget {
  const new({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, Space.xxl, Space.s, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
          if (hint case final hint?) ...[
            const SizedBox(height: Space.xs),
            Text(
              hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s, Space.xxl, Space.s, Space.s),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class _Storage extends StatelessWidget {
  const new({required this.maps});

  final OfflineMaps maps;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(Space.l),
      child: Row(
        children: [
          Icon(OfflineIcons.storage, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              maps.installed.isEmpty && maps.transfers.isEmpty
                  ? t.offlineMaps.none
                  : t.offlineMaps.used(size: t.fileSize(maps.bytesNow)),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pack of the manifest to download.
class _CatalogRow extends ConsumerWidget {
  const new({required this.pack, required this.catalog, this.reason});

  final PackInfo pack;
  final PackCatalog catalog;

  /// Why it is suggested.
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final name = pack.name(t.$meta.locale.languageCode);
    final size = t.fileSize(pack.size);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: Space.l, right: Space.xs),
      title: Text(name),
      subtitle: Text([?reason, size].join(' · ')),
      trailing: IconButton(
        tooltip: t.offlineMaps.downloadNamed(name: name, size: size),
        icon: const Icon(AppIcons.download),
        onPressed: () => unawaited(ref.read(offlinePacksProvider.notifier).download(pack, catalog)),
      ),
      onTap: () => unawaited(ref.read(offlinePacksProvider.notifier).download(pack, catalog)),
    );
  }
}

/// A download: its progress, and pause, resume or stop.
class _TransferRow extends ConsumerWidget {
  const new({required this.transfer});

  final PackTransfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final packs = ref.read(offlinePacksProvider.notifier);
    final id = transfer.pack.id;
    final name = transfer.pack.name(t.$meta.locale.languageCode);
    final done = t.fileSize(transfer.received);
    final total = t.fileSize(transfer.pack.size);
    final (status, color) = switch (transfer.state) {
      TransferState.running => (
        t.offlineMaps.progress(done: done, total: total),
        scheme.onSurfaceVariant,
      ),
      TransferState.waiting => (t.offlineMaps.waiting, scheme.onSurfaceVariant),
      TransferState.paused => (
        t.offlineMaps.paused(done: done, total: total),
        scheme.onSurfaceVariant,
      ),
      TransferState.verifying => (t.offlineMaps.verifying, scheme.onSurfaceVariant),
      TransferState.failed => (_failure(t, transfer.failure), scheme.error),
    };
    final action = switch (transfer.state) {
      TransferState.running || TransferState.waiting => IconButton(
        tooltip: t.offlineMaps.pause,
        icon: const Icon(OfflineIcons.pause),
        onPressed: () => unawaited(packs.pause(id)),
      ),
      TransferState.paused || TransferState.failed => IconButton(
        tooltip: transfer.state == TransferState.failed ? t.common.retry : t.offlineMaps.resume,
        icon: const Icon(OfflineIcons.resume),
        onPressed: () => unawaited(packs.resume(id)),
      ),
      TransferState.verifying => const SizedBox(width: 48),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                const SizedBox(height: Space.xs),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(LunaTokens.radiusPill)),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: transfer.state == TransferState.verifying ? null : transfer.progress,
                    semanticsLabel: name,
                    semanticsValue: NumberFormat.percentPattern(t.$meta.locale.languageCode)
                        .format(transfer.progress),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(status, style: theme.textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          action,
          IconButton(
            tooltip: t.offlineMaps.cancel,
            icon: const Icon(AppIcons.close),
            onPressed: transfer.state == TransferState.verifying
                ? null
                : () => unawaited(packs.cancel(id)),
          ),
        ],
      ),
    );
  }

  static String _failure(Translations t, PackDownloadFailure? f) => switch (f) {
    PackDownloadFailure.network || null => t.offlineMaps.failedNetwork,
    PackDownloadFailure.server => t.offlineMaps.failedServer,
    PackDownloadFailure.corrupt => t.offlineMaps.failedCorrupt,
    PackDownloadFailure.storage => t.offlineMaps.failedStorage,
  };
}

/// A pack on the device: its size, the date of its data, an update when a
/// newer build is out, and delete.
class _InstalledRow extends ConsumerWidget {
  const new({required this.pack, required this.updating, this.newer, this.catalog});

  final InstalledPack pack;
  final PackInfo? newer;
  final PackCatalog? catalog;
  final bool updating;

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final t = context.t;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.offlineMaps.deleteTitle(name: name)),
        content: Text(t.offlineMaps.deleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.common.delete)),
        ],
      ),
    );
    if (yes == true) await ref.read(offlinePacksProvider.notifier).delete(pack.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final name = pack.name(t.$meta.locale.languageCode);
    final date = pack.dataDate;
    final newer = this.newer;
    final catalog = this.catalog;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                Text(
                  [
                    t.fileSize(pack.size),
                    if (date != null)
                      t.offlineMaps.dataOf(
                        date: MaterialLocalizations.of(context).formatMediumDate(date),
                      ),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (newer != null && catalog != null && !updating)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(
                        ref.read(offlinePacksProvider.notifier).download(newer, catalog),
                      ),
                      icon: const Icon(AppIcons.sync),
                      label: Text(t.offlineMaps.update(size: t.fileSize(newer.size))),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: t.offlineMaps.deleteNamed(name: name),
            icon: const Icon(AppIcons.delete),
            onPressed: () => _delete(context, ref, name),
          ),
        ],
      ),
    );
  }
}

/// The icons of the offline maps that the rest of the app does not use.
abstract final class OfflineIcons {
  static const IconData storage = PhosphorRegular.hardDrives;
  static const IconData pause = PhosphorRegular.pause;
  static const IconData resume = PhosphorRegular.play;
  static const IconData offline = PhosphorRegular.cloudSlash;
  static const IconData ready = PhosphorRegular.cloudCheck;
}
