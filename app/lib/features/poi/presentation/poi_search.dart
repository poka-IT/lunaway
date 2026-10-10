import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/town_names.dart';
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
    // The words of the search without its town: "pizzeria poissy" asks for
    // pizza, not fish.
    final sought = soughtWords(_shownQuery, town: results.town) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchHeader(poiSearchTitle(t, results, _shownQuery)),
        for (final poi in shownOrder(results, from))
          ListTile(
            leading: PoiAvatar(
              kind: poi.kind,
              size: 40,
              faded: poi.hours.opennessAt(now) == PoiOpenness.closed,
            ),
            title: Text(t.poiTitle(poi.name, poi.kind), maxLines: 2),
            subtitle: Text(poiSearchLine(t, poi, now, from: from, sought: sought), maxLines: 2),
            onTap: () => widget.onTap(poi),
          ),
      ],
    );
  }
}

/// The title of the points of a search: what a search by kind seeks and
/// where ("Pizzeria à Annecy", "Coiffeur près d'ici"), else the section's
/// own name. One word that spells the one kind it names, typed a little
/// wrong, reads as the kind's name ("coifeur": "Coiffeur"); any other word
/// is the user's own, which says more than the kind ("curry", "restaurant
/// italien", "pizzeria").
String poiSearchTitle(Translations t, PoiResults results, String query) {
  if (results.match != PoiMatch.kind) return t.poi.searchSection;
  final sought = soughtWords(query, town: results.town);
  final kind = results.kinds.length == 1 ? t.poiKind(results.kinds.single) : null;
  final what = kind != null && (sought == null || _spells(sought, kind))
      ? kind
      : sought ?? (results.kinds.isEmpty ? null : t.poiKind(results.kinds.first));
  if (what == null) return t.poi.searchSection;
  return switch (results.town) {
    final town? => t.poi.searchKindIn(what: what, town: town),
    null => t.poi.searchKindNear(what: what),
  };
}

/// Whether the one word [sought] spells the kind's name [kind]: the same
/// first four letters, accents aside, of a name in one piece ("Clinique,
/// centre de santé" is two).
bool _spells(String sought, String kind) {
  if (sought.contains(' ') || kind.contains(',')) return false;
  final stem = _stem(sought);
  return stem != null && stem == _stem(kind);
}

/// The first four letters of [word], accents aside; null for a shorter
/// word. Two words with the same stem name the same thing to the search's
/// rows and title ("coifeur" and "Coiffeur", "pizzeria" and "Pizza").
String? _stem(String word) {
  final folded = foldForSearch(word);
  return folded.length >= 4 ? folded.substring(0, 4) : null;
}

/// What is neither a letter nor a digit, between the words of a search:
/// "l'italien" holds the word "italien".
final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// The line under a point of the search: its kind, what a restaurant
/// cooks (the cuisine [sought] names first), how far, and whether it is
/// open (nothing when its hours are not known).
String poiSearchLine(Translations t, Poi poi, DateTime now, {LatLng? from, String sought = ''}) => [
  t.poiKind(poi.kind),
  if (poi.category == PoiCategory.food) ?_shownCuisine(t, poi.cuisine, sought),
  if (from != null) t.distance(poi.position.distanceTo(from)),
  if (!poi.kind.timeless && poi.hours.opennessAt(now) != PoiOpenness.unknown)
    t.poiOpening(poi.hours, now),
].join(' · ');

/// The cuisine a row of the search says: the one a word of [sought] spells
/// ("pizzeria" finds "Pizza" in a restaurant both regional and pizza, which
/// the search listed for its pizza), else the first the app has a word
/// for. A value of the source in English would read oddly on the line.
String? _shownCuisine(Translations t, List<String> cuisine, String sought) {
  final known = cuisine.map(t.knownCuisine).nonNulls.toList();
  final stems = {for (final w in sought.split(_separators)) ?_stem(w)};
  return known.firstWhereOrNull((label) => stems.contains(_stem(label))) ?? known.firstOrNull;
}
