/// The street of an address line without its house number: what titles a
/// place without a name (`Parking · Rue de la Gare`). The sources and the
/// server's reverse geocoding write the number first (`12 Rue de la Gare`,
/// `616-644 Route de Fréjus`, `4 bis, rue Haute`, `4bis rue Haute`,
/// `12 B Rue des Lilas`, `938 SP27`); a line that starts with no number
/// (`D933N`, `Via Monte Grappa`) is kept whole. Null when nothing but a
/// number is left.
String? streetName(String? line) {
  if (line == null) return null;
  final trimmed = line.trim();
  final match = _leadingNumber.firstMatch(trimmed);
  final rest = match == null ? trimmed : trimmed.substring(match.end).trim();
  // A number alone, or a number and a letter ("12 B"), is no street; a
  // road's number is one (`D933N`, `A-136`).
  if (rest.length < 2 || !_letter.hasMatch(rest)) return null;
  return rest;
}

/// A house number at the start of a line: digits, a letter or a range or
/// a kilometre mark glued to them (`12A`, `616-644`, `17+555`), a suffix
/// word glued or apart (`4bis`, `4 bis`, `ter`, `quater`) or a letter apart
/// (`12 B`), then a comma or a space.
final _leadingNumber = RegExp(
  r'^\d+[A-Za-z]?(?:[-/+]\d+[A-Za-z]?)*(?:\s*(?:bis|ter|quater)\b)?(?:\s+[A-Za-z](?=[\s,]))?\s*,?\s+',
  caseSensitive: false,
);

/// A letter, of any script.
final _letter = RegExp(r'\p{L}', unicode: true);
