import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// Wall-clock times of a place in France (summer time in October, UTC+2),
/// as UTC instants: the wording reads them in the place's zone, whatever
/// the zone of the machine running the test.
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute).subtract(const Duration(hours: 2));

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

    String say(List<OpeningInterval> spans, DateTime now) => t.opening(
      openingStateAt(spans, now.toUtc(), validUntil: validUntil)!,
      now,
      zone: PlaceZone.central,
    );

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
      () => expect(say(const [], at(6, 10)), 'Fermé pendant les deux semaines à venir'),
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
    expect(
      t.opening(state, at(6, 10), zone: PlaceZone.central),
      'Closed, opens Saturday at 9:00\u202fAM',
    );
  });

  test('the hours of a place in Portugal read in Portuguese time, not in the device zone', () {
    final t = AppLocale.fr.buildSync();
    // 08:00 to 19:00 in Lisbon (UTC+1 in October) is 09:00 to 20:00 in Paris.
    final lisbon = [
      for (var d = 5; d <= 20; d++)
        OpeningInterval(DateTime.utc(2026, 10, d, 7), DateTime.utc(2026, 10, d, 18)),
    ];
    final now = DateTime.utc(2026, 10, 6, 9);
    final state = openingStateAt(lisbon, now, validUntil: validUntil)!;
    expect(t.opening(state, now, zone: PlaceZone.ofCountry('PT')), 'Ouvert, ferme à 19:00');
    expect(t.opening(state, now, zone: PlaceZone.ofCountry('FR')), 'Ouvert, ferme à 20:00');
  });

  group('the place zone', () {
    test(
      'follows European summer time, from the last Sunday of March to October, at 01:00 UTC',
      () {
        const paris = PlaceZone.central;
        expect(paris.offsetAt(DateTime.utc(2026, 3, 29, 0, 59)), const Duration(hours: 1));
        expect(paris.offsetAt(DateTime.utc(2026, 3, 29, 1)), const Duration(hours: 2));
        expect(paris.offsetAt(DateTime.utc(2026, 10, 25, 0, 59)), const Duration(hours: 2));
        expect(paris.offsetAt(DateTime.utc(2026, 10, 25, 1)), const Duration(hours: 1));
        expect(PlaceZone.iceland.offsetAt(DateTime.utc(2026, 7)), Duration.zero);
        expect(PlaceZone.ofCountry('fi'), PlaceZone.eastern);
        expect(PlaceZone.ofCountry(null), PlaceZone.central, reason: "France, the app's region");
      },
    );

    test('gives the wall clock of the place', () {
      expect(
        PlaceZone.central.wallClock(DateTime.utc(2026, 1, 10, 23, 30)),
        DateTime.utc(2026, 1, 11, 0, 30),
      );
    });

    test('finds the instant at which the place reads a wall clock time, in winter and summer', () {
      const paris = PlaceZone.central;
      expect(paris.instantOf(DateTime.utc(2026, 1, 11, 0, 30)), DateTime.utc(2026, 1, 10, 23, 30));
      expect(paris.instantOf(DateTime.utc(2026, 10, 6, 20)), DateTime.utc(2026, 10, 6, 18));
      expect(
        PlaceZone.ofCountry('PT').instantOf(DateTime.utc(2026, 7, 1, 8)),
        DateTime.utc(2026, 7, 1, 7),
      );
    });
  });

  test('the demo hours are on the clock of France, whatever the zone of the machine', () {
    final t = AppLocale.fr.buildSync();
    // Tuesday 6 October 2026, 10:30 in France. Each pattern of the demo
    // hours read then, in France: a zone of the machine leaking into the
    // intervals (the CI runs in UTC) shifts every one of them.
    final now = DateTime.utc(2026, 10, 6, 8, 30);
    final said = {
      for (final p in demoPlaces(count: 400, now: now))
        if (openingStateAt(p.openingIntervals, now, validUntil: p.openingValidUntil)
            case final state?)
          t.opening(state, now, zone: PlaceZone.central),
    };
    expect(said, {
      'Ouvert maintenant',
      'Ouvert, ferme à 20:00',
      'Ouvert, ferme à 18:00',
      'Ouvert, ferme à 22:00',
      'Fermé, ouvre vendredi à 18:00',
      'Ouvert, ferme à 12:00',
    });
  });
}
