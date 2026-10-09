import 'package:lunaway/i18n/strings.g.dart';

/// An OpenStreetMap `opening_hours` value in words a traveller reads at a
/// glance: the English day and month codes in the app language, the dates
/// in the order of that language, one rule per line, "off" as "closed". What
/// it does not know stays as written, so nothing the source said is lost.
///
///     Mo-Fr 08:00-18:00; Sa 09:00-12:00; PH off
///     lun.-ven. 08:00-18:00
///     sam. 09:00-12:00
///     jours fériés fermé
String readableHours(String raw, Translations t) {
  final text = raw.trim();
  if (text == '24/7') return t.hours.allWeek;
  return text
      // The whole year, as a seasonal feed writes it (01-01 to 12-31).
      .replaceAll(RegExp(r'\bJan 0?1\s*-\s*Dec 31\b'), t.hours.allYear)
      // A date reads in the language's order before the month codes are
      // replaced on their own.
      .replaceAllMapped(
        RegExp(r'\b(\d{4}) (' + _months + r') (\d{1,2})\b'),
        (m) => t.hours.dayOfYear(day: int.parse(m[3]!), month: _month(t, m[2]!), year: m[1]!),
      )
      .replaceAllMapped(
        RegExp(r'\b(' + _months + r') (\d{1,2})\b'),
        (m) => t.hours.dayOfMonth(day: int.parse(m[2]!), month: _month(t, m[1]!)),
      )
      .replaceAllMapped(RegExp(r'\b(' + _months + r')\b'), (m) => _month(t, m[1]!))
      .replaceAllMapped(
        RegExp(r'\b(Mo|Tu|We|Th|Fr|Sa|Su|PH|SH|off|closed|sunrise|sunset)\b'),
        (m) => _code(t, m[1]!),
      )
      // A list of days or of times reads with a space after each comma:
      // "Su,Tu,Fr", a market's days, is "dim., mar., ven.". A quoted
      // comment keeps its own commas ("jeton 2,50 €").
      .replaceAllMapped(RegExp(r'"[^"]*"|,(?=\S)'), (m) => m[0] == ',' ? ', ' : m[0]!)
      .split(RegExp(r'\s*(?:;|\|\|)\s*'))
      .where((rule) => rule.isNotEmpty)
      // Each rule on its own line starts as a line does.
      .map((rule) => rule[0].toUpperCase() + rule.substring(1))
      .join('\n');
}

const _months = 'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec';

String _month(Translations t, String code) => switch (code) {
  'Jan' => t.hours.months.jan,
  'Feb' => t.hours.months.feb,
  'Mar' => t.hours.months.mar,
  'Apr' => t.hours.months.apr,
  'May' => t.hours.months.may,
  'Jun' => t.hours.months.jun,
  'Jul' => t.hours.months.jul,
  'Aug' => t.hours.months.aug,
  'Sep' => t.hours.months.sep,
  'Oct' => t.hours.months.oct,
  'Nov' => t.hours.months.nov,
  _ => t.hours.months.dec,
};

String _code(Translations t, String code) => switch (code) {
  'Mo' => t.hours.codes.mo,
  'Tu' => t.hours.codes.tu,
  'We' => t.hours.codes.we,
  'Th' => t.hours.codes.th,
  'Fr' => t.hours.codes.fr,
  'Sa' => t.hours.codes.sa,
  'Su' => t.hours.codes.su,
  'PH' => t.hours.codes.ph,
  'SH' => t.hours.codes.sh,
  'off' => t.hours.codes.off,
  'closed' => t.hours.codes.closed,
  'sunrise' => t.hours.codes.sunrise,
  _ => t.hours.codes.sunset,
};
