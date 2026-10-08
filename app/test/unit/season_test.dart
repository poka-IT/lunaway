import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

PlaceSummary _place({List<DayRange>? season}) => PlaceSummary(
  id: 'p',
  kind: PlaceKind.campsite,
  lat: 45,
  lon: 6,
  overnight: OvernightStatus.allowed,
  openingSeason: season,
);

void main() {
  group('days of the year', () {
    test('a date counts in a leap year, whatever its own year', () {
      expect(dayOfYear(DateTime(2027)), 1);
      expect(dayOfYear(DateTime(2028, 2, 29)), 60);
      expect(dayOfYear(DateTime(2027, 3)), 61, reason: 'a common year skips 60');
      expect(dayOfYear(DateTime(2028, 3)), 61);
      expect(dayOfYear(DateTime(2026, 4)), 92);
      expect(dayOfYear(DateTime(2026, 10, 31)), 305);
      expect(dayOfYear(DateTime(2026, 12)), 336);
      expect(dayOfYear(DateTime(2026, 12, 31)), 366);
    });

    test('a day of the year formats as its month and day', () {
      expect(dateOfDay(60), DateTime.utc(2000, 2, 29));
      expect(dateOfDay(305), DateTime.utc(2000, 10, 31));
      expect(dateOfDay(366), DateTime.utc(2000, 12, 31));
    });

    test('a range reads from and back to the code of the tiles', () {
      expect(const DayRange(92, 305).code, 92305);
      expect(DayRange.wholeYear.code, 1366);
      expect(DayRange.fromCode(92305), const DayRange(92, 305));
      expect(DayRange.fromCode(1366.0), DayRange.wholeYear, reason: 'a number of a platform');
      expect(DayRange.fromCode(305092), isNull, reason: 'the last day before the first');
      expect(DayRange.fromCode(1367), isNull, reason: 'past 31 December');
      expect(DayRange.fromCode(92305.5), isNull);
      expect(DayRange.fromCode('92305'), isNull);
    });

    test('a season is one or two ranges in order, else none', () {
      expect(seasonFromCodes(92305, null), const [DayRange(92, 305)]);
      expect(seasonFromCodes(1091, 305366), const [DayRange(1, 91), DayRange(305, 366)]);
      expect(seasonFromCodes(null, 305366), isNull, reason: 'no first range, no season');
      expect(seasonFromCodes(305366, 1091), isNull, reason: 'out of order');
      expect(seasonFromCodes(1100, 50200), isNull, reason: 'overlapping');
      expect(seasonFromCodes(92305, 0), isNull, reason: 'a second code that is no range');
    });
  });

  group('the nights of a stay', () {
    test('are the days from arrival to the eve of departure', () {
      expect(stayDays(DateTime(2026, 10, 12), DateTime(2026, 10, 15)), const [DayRange(286, 288)]);
    });

    test('arriving and leaving the same day asks that one day', () {
      expect(stayDays(DateTime(2026, 10, 12), DateTime(2026, 10, 12)), const [DayRange(286, 286)]);
    });

    test('across the new year are two ranges', () {
      expect(stayDays(DateTime(2026, 12, 28), DateTime(2027, 1, 3)), const [
        DayRange(1, 2),
        DayRange(363, 366),
      ]);
      expect(stayDays(DateTime(2026, 12, 31), DateTime(2027)), const [
        DayRange(366, 366),
      ], reason: 'the night of 31 December only');
    });

    test('a common year maps by month and day', () {
      expect(stayDays(DateTime(2027, 2, 28), DateTime(2027, 3, 2)), const [DayRange(59, 61)]);
    });

    test('a year or more of nights is the whole year', () {
      expect(stayDays(DateTime(2026, 10, 8), DateTime(2027, 10, 8)), const [DayRange.wholeYear]);
      expect(stayDays(DateTime(2026, 3), DateTime(2027, 2, 28)), const [
        DayRange(1, 58),
        DayRange(61, 366),
      ], reason: '364 nights: 28 February is the day of departure');
    });

    test('a change of the clocks counts no night twice nor none', () {
      // 29 March 2026 has 23 hours in France, 25 October 25.
      expect(stayDays(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), const [DayRange(88, 89)]);
      expect(stayDays(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), const [DayRange(298, 299)]);
    });
  });

  group('a season covers', () {
    const summer = [DayRange(92, 305)];
    const winter = [DayRange(1, 91), DayRange(305, 366)];

    test('the days within one of its ranges', () {
      expect(seasonCovers(summer, const [DayRange(286, 288)]), isTrue);
      expect(seasonCovers(summer, const [DayRange(300, 310)]), isFalse, reason: 'half outside');
      expect(seasonCovers(summer, const [DayRange.wholeYear]), isFalse);
      expect(seasonCovers(const [DayRange.wholeYear], const [DayRange.wholeYear]), isTrue);
    });

    test('a stay across the new year in a season across it', () {
      final stay = stayDays(DateTime(2026, 12, 28), DateTime(2027, 1, 3));
      expect(seasonCovers(winter, stay), isTrue);
      expect(seasonCovers(summer, stay), isFalse);
    });

    test('anything when there is no season', () {
      expect(seasonCovers(null, const [DayRange.wholeYear]), isTrue);
    });
  });

  group('the state of a season on a day', () {
    test('open all year', () {
      expect(seasonStateOn(const [DayRange.wholeYear], 40), const SeasonAllYear());
    });

    test('open until the last day of the range holding the day', () {
      expect(seasonStateOn(const [DayRange(92, 305)], 280), const SeasonOpenUntil(305));
      expect(seasonStateOn(const [DayRange(92, 305)], 305), const SeasonOpenUntil(305));
    });

    test('closed until the next range starts, next year after the last', () {
      expect(seasonStateOn(const [DayRange(92, 305)], 40), const SeasonClosedUntil(92));
      expect(seasonStateOn(const [DayRange(92, 305)], 320), const SeasonClosedUntil(92));
      expect(
        seasonStateOn(const [DayRange(1, 91), DayRange(152, 244)], 100),
        const SeasonClosedUntil(152),
      );
    });

    test('a season across the new year stays open past 31 December', () {
      const winter = [DayRange(1, 91), DayRange(305, 366)];
      expect(seasonStateOn(winter, 340), const SeasonOpenUntil(91));
      expect(seasonStateOn(winter, 20), const SeasonOpenUntil(91));
      expect(seasonStateOn(winter, 200), const SeasonClosedUntil(305));
    });

    test('none without a season', () {
      expect(seasonStateOn(null, 40), isNull);
    });
  });

  group('the opening filter', () {
    test('all year keeps the places open all year and those without a season', () {
      const filter = PlaceFilter(opening: AllYearOpening());
      expect(filter.openDays, const [DayRange.wholeYear]);
      expect(filter.matches(_place(season: const [DayRange.wholeYear])), isTrue);
      expect(filter.matches(_place()), isTrue, reason: 'opening not known by the day');
      expect(filter.matches(_place(season: const [DayRange(92, 305)])), isFalse);
    });

    test('a stay keeps the places open every night of it', () {
      final filter = PlaceFilter(
        opening: StayOpening(DateTime(2026, 10, 12, 18), DateTime(2026, 10, 15)),
      );
      expect(filter.openDays, const [DayRange(286, 288)], reason: 'the time of a date is dropped');
      expect(filter.matches(_place(season: const [DayRange(92, 305)])), isTrue);
      expect(filter.matches(_place(season: const [DayRange(92, 287)])), isFalse);
      expect(filter.matches(_place()), isTrue);
    });

    test('counts as one criterion, compares by its dates, and toggles all year', () {
      final stay = StayOpening(DateTime(2026, 10, 12), DateTime(2026, 10, 15));
      final filter = PlaceFilter(freeOnly: true, opening: stay);
      expect(filter.activeCount, 2);
      expect(filter.isEmpty, isFalse);
      expect(
        filter,
        PlaceFilter(
          freeOnly: true,
          opening: StayOpening(DateTime.utc(2026, 10, 12, 9), DateTime(2026, 10, 15)),
        ),
      );
      expect(filter.hashCode, PlaceFilter(freeOnly: true, opening: stay).hashCode);
      expect(filter, isNot(const PlaceFilter(freeOnly: true, opening: AllYearOpening())));
      expect(filter.toggleAllYear().opening, const AllYearOpening(), reason: 'replaces the stay');
      expect(filter.toggleAllYear().toggleAllYear().opening, isNull, reason: 'a second tap clears');
      expect(filter.resolve(vehicleHeightM: 2.9).opening, stay, reason: 'resolving keeps it');
      expect(filter.copyWith(opening: () => null).activeCount, 1);
    });
  });

  group('the API', () {
    test('a season reads from its JSON and writes back the same', () {
      final json = [
        {'from': 1, 'to': 91},
        {'from': 305, 'to': 366},
      ];
      final season = openingSeasonFromJson(json);
      expect(season, const [DayRange(1, 91), DayRange(305, 366)]);
      expect(openingSeasonToJson(season), json);
      expect(openingSeasonFromJson(null), isNull, reason: 'an API older than the field');
      expect(openingSeasonToJson(null), isNull);
    });

    test('a place carries its season to its summary and through its JSON', () {
      final place = Place(
        id: 'p',
        kind: PlaceKind.campsite,
        lat: 45,
        lon: 6,
        overnight: OvernightStatus.allowed,
        updatedAt: DateTime.utc(2026, 10),
        openingHours: 'Apr 01-Oct 31',
        openingHoursParsed: true,
        openingSeason: const [DayRange(92, 305)],
      );
      final back = placeFromJson(placeToJson(place));
      expect(back, place);
      expect(back.summary.openingSeason, const [DayRange(92, 305)]);
    });
  });

  group('the words of a season', () {
    setUpAll(() async {
      await initializeDateFormatting('fr');
      await initializeDateFormatting('en');
    });

    test('in French', () {
      final t = AppLocale.fr.buildSync();
      expect(t.season(const SeasonAllYear()), "Ouvert toute l'année");
      expect(t.season(const SeasonOpenUntil(305)), "Ouvert jusqu'au 31 octobre");
      expect(t.season(const SeasonClosedUntil(92)), 'Fermé, ouvre le 1er avril');
    });

    test('in English', () {
      final t = AppLocale.en.buildSync();
      expect(t.season(const SeasonAllYear()), 'Open all year');
      expect(t.season(const SeasonOpenUntil(305)), 'Open until October 31');
      expect(t.season(const SeasonClosedUntil(92)), 'Closed, opens April 1');
    });

    test('a stay says the month once when its dates share it', () {
      final fr = AppLocale.fr.buildSync();
      final en = AppLocale.en.buildSync();
      final oct12 = DateTime(2026, 10, 12);
      expect(fr.stay(oct12, DateTime(2026, 10, 15)), 'Du 12 au 15 oct.');
      expect(en.stay(oct12, DateTime(2026, 10, 15)), 'Oct 12 to 15');
      expect(fr.stay(DateTime(2026, 12, 28), DateTime(2027, 1, 3)), 'Du 28 déc. au 3 janv.');
      expect(en.stay(DateTime(2026, 12, 28), DateTime(2027, 1, 3)), 'Dec 28 to Jan 3');
      expect(fr.stay(oct12, oct12), 'Le 12 oct.');
      expect(en.stay(oct12, oct12), 'On Oct 12');
      expect(
        fr.stay(DateTime(2026, 11), DateTime(2026, 11, 4)),
        'Du 1er au 4 nov.',
        reason: 'French says the first of a month 1er',
      );
    });
  });
}
