import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/home_views.dart';
import 'package:lunaway/features/places/presentation/address_results.dart';
import 'package:lunaway/features/places/presentation/locality_line.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/features/search/domain/recent_search.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/touch_target.dart';

/// The title of an entry of the history, as its result's row titled it.
String recentTitle(Translations t, RecentSearch entry) => switch (entry) {
  RecentPlace(:final place) => t.summaryTitle(place),
  RecentPoi(:final name, :final poiKind) => t.poiTitle(name, poiKind),
  RecentTown(:final town) => town.name,
  RecentAddress(:final address) => address.name,
  RecentText(:final text) => text,
};

/// The line under an entry: what it is and where it lies, as under its
/// result ("Restaurant · Annecy (74)", "Commune · Drôme", "Adresse · Lyon
/// 3e"); a text searched says it is one.
String recentLine(Translations t, RecentSearch entry, {required String home}) => switch (entry) {
  RecentPlace(:final place) => [
    t.kind(place.kind),
    ?localityLine(t, place.locality, home: home),
  ].join(' · '),
  RecentPoi(:final poiKind, :final locality) => [
    t.poiKind(poiKind),
    ?localityLine(t, locality, home: home),
  ].join(' · '),
  RecentTown(:final town) => townWhere(t, town, home: home),
  RecentAddress(:final address) => addressLine(t, address, home: home),
  RecentText() => t.search.recentText,
};

/// One entry of the history: the clock of what was opened before, its
/// title and its line, and a cross that takes it out (with [onRemove]),
/// each a target of 48 at least and a stop of the keyboard, named to a
/// screen reader.
class RecentSearchTile extends ConsumerWidget {
  const new({required this.entry, required this.onTap, this.onRemove, super.key});

  final RecentSearch entry;
  final VoidCallback onTap;

  /// Takes the entry out of the history; null among the results, where the
  /// row only reopens it.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final title = recentTitle(t, entry);
    final remove = onRemove;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
        child: Semantics(label: t.search.recentMark, child: const Icon(AppIcons.recent)),
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        recentLine(t, entry, home: homeCountry(ref)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      trailing: remove == null
          ? null
          : TouchTarget(
              minSize: const Size.square(48),
              child: IconButton(
                tooltip: t.search.removeRecent(name: title),
                icon: const Icon(AppIcons.close),
                onPressed: remove,
              ),
            ),
    );
  }
}

/// The user's home at the head of what the empty search field lists: a tap
/// starts the route there, the one thing a home is searched for.
class HomeSearchTile extends StatelessWidget {
  const new({required this.home, required this.onTap, super.key});

  final SavedPoint home;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final line = homeLine(home);
    return Semantics(
      button: true,
      label: t.home.directionsHome,
      excludeSemantics: true,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: const Icon(AppIcons.home),
        ),
        title: Text(t.home.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(line, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(AppIcons.directions, color: scheme.primary),
        onTap: onTap,
      ),
    );
  }
}

/// What lies under the empty search field: the home first, then the
/// history, the results opened and the texts searched before, the most
/// recent first, each with its cross, then "Clear the history". Nothing
/// shows while there is neither.
class RecentSearchesList extends StatelessWidget {
  const new({
    required this.entries,
    required this.onOpen,
    required this.onRemove,
    required this.onClear,
    this.home,
    this.onHome,
    super.key,
  });

  final List<RecentSearch> entries;
  final ValueChanged<RecentSearch> onOpen;
  final ValueChanged<RecentSearch> onRemove;
  final VoidCallback onClear;

  /// The user's home, which heads the list; none while there is none.
  final SavedPoint? home;

  /// The route to [home].
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    // The geocoders of the addresses listed, credited as under the results.
    final sources = {
      for (final e in entries)
        if (e case RecentAddress(:final address) when address.attribution.isNotEmpty)
          address.attribution,
    };
    final home = this.home;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      children: [
        if (home != null) HomeSearchTile(home: home, onTap: () => onHome?.call()),
        if (entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.xxs),
            child: Semantics(
              header: true,
              child: Text(
                t.search.recent,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final entry in entries)
          RecentSearchTile(
            key: ValueKey(entry.key),
            entry: entry,
            onTap: () => onOpen(entry),
            onRemove: () => onRemove(entry),
          ),
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxs, Space.xl, Space.xxs),
            child: Text(
              t.search.addressSources(sources: sources.join(' · ')),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(AppIcons.delete),
                label: Text(t.search.clearHistory),
              ),
            ),
          ),
      ],
    );
  }
}
