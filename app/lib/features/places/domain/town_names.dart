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

/// Whether two postcodes lie in the same area, each with its country
/// (ISO 3166-1 alpha-2, null when unknown): their French department when
/// both are French or of no known country (each overseas department its
/// own, 2A and 2B apart), else their first two characters, as the server
/// compares them (`lunaway-domain/src/address.rs`, `area`); unknown on
/// either side, the same. Hamburg 20095 and 20457 are one area.
bool sameTownArea(String? a, String? b, {String? aCountry, String? bCountry}) {
  if (a == null || b == null || a.length < 2 || b.length < 2) return true;
  String area(String postcode, String? country) {
    final french = country == null || country.toUpperCase() == 'FR';
    return (french ? departmentOfPostcode(postcode) : null) ?? postcode.substring(0, 2);
  }

  return area(a, aCountry) == area(b, bCountry);
}
