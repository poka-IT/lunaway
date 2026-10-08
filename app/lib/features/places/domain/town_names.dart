import 'package:lunaway/features/places/domain/french_departments.dart';

/// [text] in lower case without the accents of the Latin languages the map
/// covers, so that "Évian" starts like "evi".
String foldForSearch(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().trim().runes) {
    final c = String.fromCharCode(rune);
    out.write(_unaccented[c] ?? c);
  }
  return out.toString();
}

const _unaccented = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', //
  'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', //
  'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae', 'ß': 'ss', 'ł': 'l', //
  'š': 's', 'ž': 'z', 'č': 'c', //
};

final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// A town's name as one town is told from another: folded, every run of
/// what is neither a letter nor a digit one space, as the server folds its
/// towns (`lunaway_town_fold`): "Chamonix-Mont-Blanc" is
/// "chamonix mont blanc", which "Chamonix" starts.
String townKey(String name) => foldForSearch(name).replaceAll(_separators, ' ').trim();

/// Whether two postcodes lie in the same area: their French department
/// when both are French postcodes (each overseas department its own, 2A
/// and 2B apart), else their first two characters; unknown on either side,
/// the same.
bool sameTownArea(String? a, String? b) {
  if (a == null || b == null || a.length < 2 || b.length < 2) return true;
  final (da, db) = (departmentOfPostcode(a), departmentOfPostcode(b));
  if (da != null && db != null) return da == db;
  return a.substring(0, 2) == b.substring(0, 2);
}
