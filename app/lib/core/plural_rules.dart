import 'package:lunaway/i18n/strings.g.dart';

/// Gives slang the plural rule of the app's languages it does not carry:
/// Dutch. Without it slang falls back to a guess and prints an error at
/// every plural it resolves. Runs before the first frame, and in tests.
Future<void> registerPluralRules() => LocaleSettings.setPluralResolver(
  language: 'nl',
  cardinalResolver: dutchCardinal,
  ordinalResolver: (n, {zero, one, two, few, many, other}) => other ?? '',
);

/// The cardinal rule of Dutch (CLDR): `one` for 1, `other` for any other
/// count, 1.5 included; `zero` for 0 where a text gives one.
String dutchCardinal(
  num n, {
  String? zero,
  String? one,
  String? two,
  String? few,
  String? many,
  String? other,
}) {
  if (n == 0 && zero != null) return zero;
  if (n == 1 && one != null) return one;
  return other ?? '';
}
