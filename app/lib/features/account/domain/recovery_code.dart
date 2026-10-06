/// The recovery code as the card shows it and as a person types it: 27
/// symbols of Crockford's base32 (26 for the 128 bits, one Luhn mod 32 check
/// symbol), in groups of four. The rules are the server's
/// (`backend/crates/lunaway-auth/src/recovery.rs`): the app checks a typed
/// code before sending it, so a typo never spends one of the five attempts
/// an hour the server allows.
abstract final class RecoveryCode {
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _dataSymbols = 26;
  static const int symbols = _dataSymbols + 1;

  static int? _value(String c) {
    final upper = switch (c.toUpperCase()) {
      'O' => '0',
      'I' || 'L' => '1',
      final other => other,
    };
    final i = _alphabet.indexOf(upper);
    return i < 0 || upper.length != 1 ? null : i;
  }

  static int _check(List<int> data) {
    var sum = 0;
    var i = 0;
    for (final v in data.reversed) {
      final addend = v * (i.isEven ? 2 : 1);
      sum += addend ~/ 32 + addend % 32;
      i++;
    }
    return (32 - sum % 32) % 32;
  }

  /// The symbols typed so far, read tolerantly (case, spaces, hyphens, O
  /// for 0, I and L for 1), in their canonical letters; null when a
  /// character is not a symbol.
  static String? symbolsOf(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final c = String.fromCharCode(rune);
      if (c.trim().isEmpty || c == '-') continue;
      final v = _value(c);
      if (v == null) return null;
      out.write(_alphabet[v]);
    }
    return out.toString();
  }

  /// The code in its displayed form (`XXXX-XXXX-...-XXX`), or null when
  /// [input] is not a valid code: wrong length, a stray character, a first
  /// symbol too large for 128 bits, or a wrong check symbol.
  static String? parse(String input) {
    if (input.length > 100) return null;
    final symbols = symbolsOf(input);
    if (symbols == null || symbols.length != RecoveryCode.symbols) return null;
    final values = [for (final c in symbols.split('')) _alphabet.indexOf(c)];
    final data = values.sublist(0, _dataSymbols);
    if (_check(data) != values.last || data.first >= 8) return null;
    return group(symbols);
  }

  /// [symbols] in groups of four joined by hyphens.
  static String group(String symbols) {
    final out = StringBuffer();
    for (var i = 0; i < symbols.length; i++) {
      if (i > 0 && i % 4 == 0) out.write('-');
      out.write(symbols[i]);
    }
    return out.toString();
  }

  /// The groups of a displayed code, for a large readable layout.
  static List<String> groups(String code) =>
      code.split('-').where((g) => g.isNotEmpty).toList(growable: false);
}
