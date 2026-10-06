import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/hours_text.dart';

void main() {
  late Translations fr;
  late Translations en;
  setUpAll(() async {
    fr = await AppLocale.fr.build();
    en = await AppLocale.en.build();
  });

  test('day codes, holidays and "off" read in the language, one rule per line', () {
    const raw = 'Mo-Fr 08:00-18:00; Sa 09:00-12:00; PH off';
    expect(readableHours(raw, fr), 'Lun.-ven. 08:00-18:00\nSam. 09:00-12:00\nJours fériés fermé');
    expect(readableHours(raw, en), 'Mon-Fri 08:00-18:00\nSat 09:00-12:00\nPublic holidays closed');
  });

  test('a season reads in the order of the language, with its months translated', () {
    const raw = '2026 Mar 27-2026 Oct 11 Mo-Su 07:00-22:00';
    expect(readableHours(raw, fr), '27 mars 2026-11 oct. 2026 lun.-dim. 07:00-22:00');
    expect(readableHours(raw, en), 'Mar 27, 2026-Oct 11, 2026 Mon-Sun 07:00-22:00');
    expect(readableHours('Apr-Oct: Mo-Su 08:00-20:00', fr), 'Avr.-oct.: lun.-dim. 08:00-20:00');
  });

  test('always open says so plainly, and what is not a code stays as written', () {
    expect(readableHours('24/7', fr), '24 h/24, 7 j/7');
    expect(
      readableHours('Mo 10:00-12:00 "sur rendez-vous"', fr),
      'Lun. 10:00-12:00 "sur rendez-vous"',
    );
    expect(readableHours('Marché 08:00-12:00', fr), 'Marché 08:00-12:00');
  });
}
