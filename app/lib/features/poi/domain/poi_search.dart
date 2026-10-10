import 'package:collection/collection.dart';
import 'package:lunaway/features/places/domain/town_names.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// How the points of a search answer its text (`PoiMatch`).
enum PoiMatch {
  /// The text asks for a kind ("coiffeur", "pizzeria annecy"): the nearest
  /// of that kind, named so or not.
  kind,

  /// The best point bears every word of the text, in order.
  name,

  /// Points bear some of the words.
  partial,

  /// None.
  none;

  static PoiMatch fromWire(Object? wire) =>
      values.firstWhereOrNull((m) => m.name.toUpperCase() == wire) ?? none;
}

/// The points of interest and establishments a search found, and how they
/// answer it.
@immutable
final class PoiResults {
  const new({this.pois = const [], this.match = PoiMatch.none, this.kinds = const [], this.town});

  static const none = PoiResults();

  /// The best first, as the server ranks them (relevance, then distance).
  final List<Poi> pois;
  final PoiMatch match;

  /// The kinds the text names; empty for a name.
  final List<PoiKind> kinds;

  /// The town the text names, around which the points are ranked.
  final String? town;

  /// The text asks for a kind or names a point: the points come before
  /// the towns and the addresses, unless a town bears the text itself
  /// ([poisFirst]).
  bool get strong => pois.isNotEmpty && (match == PoiMatch.kind || match == PoiMatch.name);
}

/// Whether the points of [results] come before the towns and the addresses
/// of a search for [query]: they answer it as a kind or a name, and no town
/// of [towns] is named exactly so ("Annecy" is the town before the
/// "Annecy Plage" restaurant).
bool poisFirst(PoiResults results, String query, Iterable<String> towns) {
  if (!results.strong) return false;
  return !townNamed(query, towns);
}

/// Whether [query] is the name of one of [towns] as typed ("Annecy",
/// "annecy le vieux"): that town heads the search's list, before the
/// places that bear its name and those that lie in it.
bool townNamed(String query, Iterable<String> towns) {
  final key = townKey(query);
  return towns.any((t) => townKey(t) == key);
}

/// The words that link a kind and a town in a search ("pizzeria à annecy",
/// "hotel near lyon"), folded: left out with the town.
const _linkWords = {
  'a', 'au', 'aux', 'en', 'dans', 'pres', 'de', 'du', 'vers', //
  'in', 'near', 'at', 'around', //
  'bei', 'nahe', 'um', //
  'cerca', 'junto', //
  'vicino', 'di', //
  'bij', 'rond', 'nabij', //
};

/// What [query] seeks, without the town [town] it names: "pizzeria
/// annecy" seeks "Pizzeria" around Annecy. The user's own words, the first
/// letter in capital, for the title of a search by kind; null when nothing
/// is left.
String? soughtWords(String query, {String? town}) {
  var words = query.trim().split(RegExp(r'[\s,]+')).where((w) => w.isNotEmpty).toList();
  final townKeyed = town == null ? '' : townKey(town);
  if (townKeyed.isNotEmpty) {
    for (var i = 0; i < words.length; i++) {
      for (var j = words.length; j > i; j--) {
        if (townKey(words.sublist(i, j).join(' ')) != townKeyed) continue;
        var start = i;
        if (start > 0 && _linkWords.contains(townKey(words[start - 1]))) start--;
        words = [...words.sublist(0, start), ...words.sublist(j)];
        i = words.length;
        break;
      }
    }
  }
  if (words.isEmpty) return null;
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}
