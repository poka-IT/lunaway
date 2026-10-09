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

  test('a list of days or of times reads with a space after each comma, a comment as written', () {
    expect(readableHours('Su,Tu,Fr 07:00-13:00', fr), 'Dim., mar., ven. 07:00-13:00');
    expect(readableHours('Mo 08:00-12:00,14:00-18:00', en), 'Mon 08:00-12:00, 14:00-18:00');
    expect(readableHours('Mo 08:00-12:00 "jeton 2,50 €"', fr), 'Lun. 08:00-12:00 "jeton 2,50 €"');
  });

  test('a season reads in the order of the language, with its months translated', () {
    const raw = '2026 Mar 27-2026 Oct 11 Mo-Su 07:00-22:00';
    expect(readableHours(raw, fr), '27 mars 2026-11 oct. 2026 lun.-dim. 07:00-22:00');
    expect(readableHours(raw, en), 'Mar 27, 2026-Oct 11, 2026 Mon-Sun 07:00-22:00');
    expect(readableHours('Apr-Oct: Mo-Su 08:00-20:00', fr), 'Avr.-oct.: lun.-dim. 08:00-20:00');
  });

  test('a season from the first of January to the last of December reads as the whole year', () {
    expect(readableHours('Jan 01-Dec 31', fr), "Toute l'année");
    expect(readableHours('Jan 01-Dec 31', en), 'All year');
    expect(readableHours('Apr 01-Oct 31', fr), '1 avr.-31 oct.');
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
