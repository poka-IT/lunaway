import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/presentation/address_results.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_search.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The shops, services and other points of the map's search, which the
/// API finds in the same request as the addresses: under a title of their
/// own ("Pizzeria à Annecy", "Coiffeur près d'ici") when the text asks for
/// a kind. The previous list stays while the next one loads; offline, one
/// line says they need a network; nothing found, nothing shows.
class PoiSearchSection extends ConsumerStatefulWidget {
  const new({
    required this.query,
    required this.results,
    required this.onTap,
    this.from,
    super.key,
  });

  final String query;
  final AsyncValue<OnlineMatches> results;

  /// The user's position, for the distances, computed here.
  final LatLng? from;
  final ValueChanged<Poi> onTap;

  @override
  ConsumerState<PoiSearchSection> createState() => _PoiSearchSectionState();
}

class _PoiSearchSectionState extends ConsumerState<PoiSearchSection> {
  PoiResults _shown = PoiResults.none;
  String _shownQuery = '';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = widget.query.trim();
    if (query.length < 3) return const SizedBox.shrink();
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
    switch (widget.results) {
      case AsyncValue(value: OnlineMatches(offline: true)):
        _shown = PoiResults.none;
        return note(t.poi.searchOffline);
      case AsyncValue(value: final matches?):
        _shown = matches.pois;
        _shownQuery = query;
      case AsyncError():
        _shown = PoiResults.none;
        return note(t.poi.searchOffline);
      case _ when _shown.pois.isEmpty:
        return note(t.poi.searching);
      case _:
        break;
    }
    final results = _shown;
    if (results.pois.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final from = widget.from;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchHeader(poiSearchTitle(t, results, _shownQuery)),
        for (final poi in results.pois)
          ListTile(
            leading: PoiAvatar(
              kind: poi.kind,
              size: 40,
              faded: poi.hours.opennessAt(now) == PoiOpenness.closed,
            ),
            title: Text(t.poiTitle(poi.name, poi.kind), maxLines: 2),
            subtitle: Text(poiSearchLine(t, poi, now, from: from), maxLines: 2),
            onTap: () => widget.onTap(poi),
          ),
      ],
    );
  }
}

/// The title of the points of a search: what a search by kind seeks and
/// where ("Pizzeria à Annecy", "Coiffeur près d'ici"), else the section's
/// own name.
String poiSearchTitle(Translations t, PoiResults results, String query) {
  if (results.match != PoiMatch.kind) return t.poi.searchSection;
  final what =
      soughtWords(query, town: results.town) ??
      (results.kinds.isEmpty ? null : t.poiKind(results.kinds.first));
  if (what == null) return t.poi.searchSection;
  return switch (results.town) {
    final town? => t.poi.searchKindIn(what: what, town: town),
    null => t.poi.searchKindNear(what: what),
  };
}

/// The line under a point of the search: its kind, what a restaurant
/// cooks, how far, and whether it is open (nothing when its hours are not
/// known).
String poiSearchLine(Translations t, Poi poi, DateTime now, {LatLng? from}) => [
  t.poiKind(poi.kind),
  // The first cuisine the app has a word for: a value of the source in
  // English would read oddly on the line.
  if (poi.category == PoiCategory.food) ?poi.cuisine.map(t.knownCuisine).nonNulls.firstOrNull,
  if (from != null) t.distance(poi.position.distanceTo(from)),
  if (!poi.kind.timeless && poi.hours.opennessAt(now) != PoiOpenness.unknown)
    t.poiOpening(poi.hours, now),
].join(' · ');
