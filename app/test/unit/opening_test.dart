import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/core/geo/geo.dart';
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

const parisCentre = LatLng(48.86, 2.35);
const lisbonCentre = LatLng(38.72, -9.14);
const marrakech = LatLng(31.63, -8);

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
      zone: PlaceZone.paris,
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
      t.opening(state, at(6, 10), zone: PlaceZone.paris),
      'Closed, opens Saturday at 9:00\u202fAM',
    );
  });

  test('a weekday takes the article German and Spanish set before it', () {
    final weekend = [span(at(10, 9), at(10, 12))];
    final state = openingStateAt(weekend, at(6, 10).toUtc(), validUntil: validUntil)!;
    final de = AppLocale.de.buildSync();
    final es = AppLocale.es.buildSync();
    final it = AppLocale.it.buildSync();
    expect(
      de.opening(state, at(6, 10), zone: PlaceZone.paris),
      'Geschlossen, öffnet am Samstag um 09:00',
    );
    expect(
      es.opening(state, at(6, 10), zone: PlaceZone.paris),
      'Cerrado, abre el sábado a las 9:00',
    );
    expect(it.opening(state, at(6, 10), zone: PlaceZone.paris), 'Chiuso, apre sabato alle 09:00');
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
    expect(t.opening(state, now, zone: PlaceZone.of('PT', lisbonCentre)), 'Ouvert, ferme à 19:00');
    expect(t.opening(state, now, zone: PlaceZone.of('FR', parisCentre)), 'Ouvert, ferme à 20:00');
  });

  group('the place zone', () {
    test('follows European summer time in France, from the last Sunday of March to October', () {
      final paris = PlaceZone.of('FR', parisCentre);
      expect(paris.name, 'Europe/Paris');
      expect(paris.offsetAt(DateTime.utc(2026, 3, 29, 0, 59)), const Duration(hours: 1));
      expect(paris.offsetAt(DateTime.utc(2026, 3, 29, 1)), const Duration(hours: 2));
      expect(paris.offsetAt(DateTime.utc(2026, 10, 25, 0, 59)), const Duration(hours: 2));
      expect(paris.offsetAt(DateTime.utc(2026, 10, 25, 1)), const Duration(hours: 1));
      expect(paris.offsetAt(DateTime.utc(2027, 7, 15, 12)), const Duration(hours: 2));
      expect(
        PlaceZone.of('IS', const LatLng(64.15, -21.94)).offsetAt(DateTime.utc(2026, 7)),
        Duration.zero,
      );
      expect(PlaceZone.of('fi', const LatLng(60.17, 24.94)).name, 'Europe/Helsinki');
      expect(PlaceZone.of(null, marrakech), PlaceZone.paris, reason: "France, the app's region");
      expect(PlaceZone.of('XK', const LatLng(42.67, 21.17)), PlaceZone.paris, reason: 'no row');
    });

    test('in Morocco, follows the database: +01 until 20 September 2026, then +00 for good', () {
      // tzdata 2026c: Decree 2.26.530 returns Morocco to UTC on 2026-09-20
      // at 02:00 local. Ramadan 2026 (15 February to 22 March) was at +00;
      // ramadan 2027 (around 7 February to 14 March) no longer moves the
      // clock. Western Sahara keeps the same clock under a zone of its own.
      final morocco = PlaceZone.of('MA', marrakech);
      expect(morocco.name, 'Africa/Casablanca');
      expect(PlaceZone.of('EH', const LatLng(27.15, -13.2)).name, 'Africa/El_Aaiun');
      expect(morocco.offsetAt(DateTime.utc(2026, 3)), Duration.zero, reason: 'ramadan 2026');
      expect(
        morocco.offsetAt(DateTime.utc(2026, 7, 15, 12)),
        const Duration(hours: 1),
        reason: 'summer 2026',
      );
      expect(morocco.offsetAt(DateTime.utc(2026, 9, 20, 0, 59)), const Duration(hours: 1));
      expect(morocco.offsetAt(DateTime.utc(2026, 9, 20, 1)), Duration.zero);
      expect(
        morocco.offsetAt(DateTime.utc(2027, 2, 20, 12)),
        Duration.zero,
        reason: 'ramadan 2027',
      );
      expect(morocco.offsetAt(DateTime.utc(2027, 7, 15, 12)), Duration.zero, reason: 'summer 2027');
    });

    test('reads a place in Marrakech on its own clock, two hours behind Paris in summer', () {
      final t = AppLocale.fr.buildSync();
      // Open 09:00 to 18:00 in Marrakech every day of July 2027: 09:00 to
      // 18:00 UTC, 11:00 to 20:00 in Paris.
      final spans = [
        for (var d = 12; d <= 25; d++)
          OpeningInterval(DateTime.utc(2027, 7, d, 9), DateTime.utc(2027, 7, d, 18)),
      ];
      final until = DateTime.utc(2027, 7, 26);
      final noon = DateTime.utc(2027, 7, 15, 12);
      final open = openingStateAt(spans, noon, validUntil: until)!;
      expect(t.opening(open, noon, zone: PlaceZone.of('MA', marrakech)), 'Ouvert, ferme à 18:00');
      expect(t.opening(open, noon, zone: PlaceZone.of('FR', parisCentre)), 'Ouvert, ferme à 20:00');
      final early = DateTime.utc(2027, 7, 15, 6);
      final closed = openingStateAt(spans, early, validUntil: until)!;
      expect(t.opening(closed, early, zone: PlaceZone.of('MA', marrakech)), 'Fermé, ouvre à 09:00');
    });

    test('tells islands from their mainland by the nearest principal location', () {
      expect(PlaceZone.of('ES', const LatLng(28.1, -15.43)).name, 'Atlantic/Canary');
      expect(PlaceZone.of('ES', const LatLng(40.42, -3.70)).name, 'Europe/Madrid');
      expect(PlaceZone.of('PT', const LatLng(37.74, -25.67)).name, 'Atlantic/Azores');
      expect(PlaceZone.of('PT', const LatLng(32.65, -16.91)).name, 'Atlantic/Madeira');
      expect(PlaceZone.of('PT', lisbonCentre).name, 'Europe/Lisbon');
      expect(PlaceZone.of('AX', const LatLng(60.1, 19.94)).name, 'Europe/Mariehamn');
      expect(PlaceZone.of('SJ', const LatLng(78.22, 15.65)).name, 'Arctic/Longyearbyen');
      expect(PlaceZone.of('TR', const LatLng(41.01, 28.97)).name, 'Europe/Istanbul');
      // In winter Canarian midnight is UTC midnight, an hour after Madrid's.
      expect(
        PlaceZone.of('ES', const LatLng(28.1, -15.43)).offsetAt(DateTime.utc(2026, 11, 2)),
        Duration.zero,
      );
    });

    test('gives Russia and Ukraine no zone of their own, where the nearest city would err', () {
      // Odesa lies nearer Simferopol (Crimea, +03 all year) than Kyiv, and
      // Makhachkala nearer Astrakhan (+04) than Moscow; the server gives
      // their places no intervals.
      expect(PlaceZone.of('UA', const LatLng(46.48, 30.73)), PlaceZone.paris);
      expect(PlaceZone.of('RU', const LatLng(42.98, 47.5)), PlaceZone.paris);
      // Germany's two zones keep one clock: the nearest city is harmless.
      final freiburg = PlaceZone.of('DE', const LatLng(47.99, 7.85));
      final berlin = PlaceZone.of('DE', const LatLng(52.52, 13.4));
      for (final at in [DateTime.utc(2026, 1, 15), DateTime.utc(2027, 7, 15)]) {
        expect(freiburg.offsetAt(at), berlin.offsetAt(at));
      }
    });

    test('gives the wall clock of the place', () {
      expect(
        PlaceZone.paris.wallClock(DateTime.utc(2026, 1, 10, 23, 30)),
        DateTime.utc(2026, 1, 11, 0, 30),
      );
    });

    test('finds the instant at which the place reads a wall clock time, in winter and summer', () {
      final paris = PlaceZone.paris;
      expect(paris.instantOf(DateTime.utc(2026, 1, 11, 0, 30)), DateTime.utc(2026, 1, 10, 23, 30));
      expect(paris.instantOf(DateTime.utc(2026, 10, 6, 20)), DateTime.utc(2026, 10, 6, 18));
      expect(
        PlaceZone.of('PT', lisbonCentre).instantOf(DateTime.utc(2026, 7, 1, 8)),
        DateTime.utc(2026, 7, 1, 7),
      );
      expect(
        PlaceZone.of('MA', marrakech).instantOf(DateTime.utc(2027, 7, 15, 9)),
        DateTime.utc(2027, 7, 15, 9),
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
          t.opening(state, now, zone: PlaceZone.paris),
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
