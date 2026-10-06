import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// Local wall-clock times: the wording is read in the device's time zone.
DateTime at(int day, int hour, [int minute = 0]) => DateTime(2026, 10, day, hour, minute);

OpeningInterval span(DateTime start, DateTime end) => OpeningInterval(start.toUtc(), end.toUtc());

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
  });

  // Tuesday 6 October 2026, open 08:00 to 19:00 every day.
  final daily = [for (var d = 5; d <= 20; d++) span(at(d, 8), at(d, 19))];
  final validUntil = at(20, 0).toUtc();

  group('state', () {
    test('open inside a span, with its closing time', () {
      final state = openingStateAt(daily, at(6, 10).toUtc(), validUntil: validUntil);
      expect(state, isA<OpenUntil>().having((s) => s.closesAt, 'closesAt', at(6, 19).toUtc()));
    });

    test('closed between spans, with the next opening', () {
      final state = openingStateAt(daily, at(6, 21).toUtc(), validUntil: validUntil);
      expect(state, isA<ClosedUntil>().having((s) => s.opensAt, 'opensAt', at(7, 8).toUtc()));
    });

    test('no answer without intervals or once the window has run out', () {
      expect(openingStateAt(null, at(6, 10), validUntil: validUntil), isNull);
      expect(openingStateAt(daily, at(21, 10).toUtc(), validUntil: validUntil), isNull);
    });

    test('closed for the whole window when no span is left', () {
      expect(
        openingStateAt(const [], at(6, 10).toUtc(), validUntil: validUntil),
        isA<ClosedThroughWindow>(),
      );
    });

    test('a span past the window reads as open without a closing time', () {
      final always = [span(at(1, 0), at(25, 0))];
      expect(
        openingStateAt(always, at(6, 10).toUtc(), validUntil: validUntil),
        isA<OpenThroughWindow>(),
      );
    });

    test('adjacent spans across midnight read as one opening', () {
      final night = [span(at(6, 18), at(7, 0)), span(at(7, 0), at(7, 2))];
      final state = openingStateAt(night, at(6, 23).toUtc(), validUntil: validUntil);
      expect(state, isA<OpenUntil>().having((s) => s.closesAt, 'closesAt', at(7, 2).toUtc()));
    });
  });

  group('wording in French', () {
    late Translations t;
    setUp(() async {
      await LocaleSettings.setLocale(AppLocale.fr);
      t = AppLocale.fr.buildSync();
    });

    String say(List<OpeningInterval> spans, DateTime now) =>
        t.opening(openingStateAt(spans, now.toUtc(), validUntil: validUntil)!, now);

    test(
      'open, with the closing hour',
      () => expect(say(daily, at(6, 10)), 'Ouvert, ferme à 19:00'),
    );

    test(
      'closing in 30 minutes',
      () => expect(say(daily, at(6, 18, 30)), 'Ouvert, ferme dans 30 minutes'),
    );

    test(
      'closing in one minute keeps the singular',
      () => expect(say(daily, at(6, 18, 59)), 'Ouvert, ferme dans 1 minute'),
    );

    test(
      'closed tonight, opens tomorrow',
      () => expect(say(daily, at(6, 21)), 'Fermé, ouvre demain à 08:00'),
    );

    test(
      'closed this morning, opens in a few minutes',
      () => expect(say(daily, at(6, 7, 40)), 'Fermé, ouvre dans 20 minutes'),
    );

    test('closed until a weekday later in the week', () {
      final weekend = [span(at(10, 9), at(10, 12))]; // Saturday
      expect(say(weekend, at(6, 10)), 'Fermé, ouvre samedi à 09:00');
    });

    test(
      'closed for the whole window',
      () => expect(say(const [], at(6, 10)), 'Fermé pour les deux prochaines semaines'),
    );

    test('a span crossing midnight closes the next day', () {
      final night = [span(at(6, 18), at(7, 2))];
      expect(say(night, at(6, 20)), 'Ouvert, ferme demain à 02:00');
    });

    test('a span ending at midnight closes at midnight, not tomorrow at 00:00', () {
      final evening = [span(at(6, 18), at(7, 0))];
      expect(say(evening, at(6, 20)), 'Ouvert, ferme à minuit');
    });
  });

  test('wording in English uses the English clock and day names', () async {
    await LocaleSettings.setLocale(AppLocale.en);
    final t = AppLocale.en.buildSync();
    final weekend = [span(at(10, 9), at(10, 12))];
    final state = openingStateAt(weekend, at(6, 10).toUtc(), validUntil: validUntil)!;
    // CLDR puts a narrow no-break space between the time and AM.
    expect(t.opening(state, at(6, 10)), 'Closed, opens Saturday at 9:00\u202fAM');
  });
}
