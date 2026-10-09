import 'package:meta/meta.dart';

/// The last day of the year, 31 December of a leap year.
const int lastDayOfYear = 366;

/// Days before each month in a leap year.
const List<int> _daysBefore = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];

/// Days of a leap year, both ends included: 1 is 1 January, 60 is 29
/// February, 366 is 31 December (`DayRange` in the contract). A date of a
/// common year takes the number of its month and day in a leap year, so 1
/// March is always 61 and a season reads the same every year.
@immutable
final class DayRange {
  const new(this.from, this.to);

  /// The whole year.
  static const wholeYear = DayRange(1, lastDayOfYear);

  final int from;
  final int to;

  /// The range as the map's tiles (`o1`, `o2`) and the device's cache
  /// carry it: first day * 1000 + last day, 92305 for 1 April to 31
  /// October.
  int get code => from * 1000 + to;

  /// The range a [code] stands for; null when it is no whole number or no
  /// range of the year.
  static DayRange? fromCode(Object? code) {
    if (code is! num || !code.isFinite || code != code.roundToDouble()) return null;
    final n = code.toInt();
    final range = DayRange(n ~/ 1000, n % 1000);
    return range.isValid ? range : null;
  }

  /// Within the year, the last day not before the first.
  bool get isValid => 1 <= from && from <= to && to <= lastDayOfYear;

  /// Whether every day of [other] is one of these.
  bool holds(DayRange other) => from <= other.from && other.to <= to;

  bool holdsDay(int day) => from <= day && day <= to;

  @override
  bool operator ==(Object other) => other is DayRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DayRange($from-$to)';
}

/// [ranges] as a place's season, the shape the server sends: one or two
/// ranges of the year, sorted, the second after the first. Null for
/// anything else, which then reads as no season (a place whose opening is
/// not known by the day) rather than a wrong one.
List<DayRange>? seasonOf(List<DayRange> ranges) {
  if (ranges.isEmpty || ranges.length > 2) return null;
  if (!ranges.every((r) => r.isValid)) return null;
  if (ranges.length == 2 && ranges[1].from <= ranges[0].to) return null;
  return List.unmodifiable(ranges);
}

/// The season of the codes the tiles and the cache carry ([DayRange.code]):
/// none without a first range, nor when a code is not a range.
List<DayRange>? seasonFromCodes(Object? first, Object? second) {
  if (first == null) return null;
  final a = DayRange.fromCode(first);
  if (a == null) return null;
  if (second == null) return seasonOf([a]);
  final b = DayRange.fromCode(second);
  return b == null ? null : seasonOf([a, b]);
}

/// The day of the year of [date] by its month and day, in a leap year: 1
/// March is 61 whatever the year. Read on the fields of [date] as given, so
/// a caller passes the date of the place or of the user, never an instant.
int dayOfYear(DateTime date) => _daysBefore[date.month - 1] + date.day;

/// A date whose month and day are those of [day] (in a leap year, so that
/// 60 is 29 February), to format.
DateTime dateOfDay(int day) => DateTime.utc(2000, 1, day);

/// The days a stay needs open: the nights spent, from [arrival] to the day
/// before [departure], or that one day when they are the same date. A stay
/// across the new year is two ranges (28 December to 3 January is 1 to 2
/// and 363 to 366), and one of a year or more is the whole year.
List<DayRange> stayDays(DateTime arrival, DateTime departure) {
  // In UTC, so a change of the clocks never makes a night of 23 hours.
  final first = DateTime.utc(arrival.year, arrival.month, arrival.day);
  final end = DateTime.utc(departure.year, departure.month, departure.day);
  final nights = end.difference(first).inDays;
  if (nights >= 365) return const [DayRange.wholeYear];
  final last = nights <= 0 ? first : end.subtract(const Duration(days: 1));
  final from = dayOfYear(first);
  final to = dayOfYear(last);
  if (last.year == first.year) return [DayRange(from, to)];
  // Across the new year the two ends meet once the stay covers every day.
  if (to + 1 >= from) return const [DayRange.wholeYear];
  return [DayRange(1, to), DayRange(from, lastDayOfYear)];
}

/// Whether a place of [season] is open on every day of [days]: each range
/// of the days within one range of the season. A place without a season
/// passes, its opening not being known by the day.
bool seasonCovers(List<DayRange>? season, List<DayRange> days) =>
    season == null || days.every((d) => season.any((r) => r.holds(d)));

/// Whether a place of a season is open on a day, and until when.
@immutable
sealed class SeasonState {
  const new();
}

/// Open every day of the year.
final class SeasonAllYear extends SeasonState {
  const new();
}

/// Open, until [lastDay] included.
final class SeasonOpenUntil extends SeasonState {
  const new(this.lastDay);

  final int lastDay;

  @override
  bool operator ==(Object other) => other is SeasonOpenUntil && other.lastDay == lastDay;

  @override
  int get hashCode => lastDay.hashCode;
}

/// Closed, until [firstDay], when it opens.
final class SeasonClosedUntil extends SeasonState {
  const new(this.firstDay);

  final int firstDay;

  @override
  bool operator ==(Object other) => other is SeasonClosedUntil && other.firstDay == firstDay;

  @override
  int get hashCode => firstDay.hashCode;
}

/// The state of a place of [season] on [day] (a [dayOfYear]); null
/// without a season.
SeasonState? seasonStateOn(List<DayRange>? season, int day) {
  if (season == null || season.isEmpty) return null;
  if (season.length == 1 && season.first == DayRange.wholeYear) return const SeasonAllYear();
  for (final range in season) {
    if (!range.holdsDay(day)) continue;
    // A season across the new year is cut there: open on 31 December, it
    // stays open until the end of its range of January.
    final wraps = range.to == lastDayOfYear && season.first.from == 1 && season.first != range;
    return SeasonOpenUntil(wraps ? season.first.to : range.to);
  }
  final next = season.where((r) => r.from > day).firstOrNull ?? season.first;
  return SeasonClosedUntil(next.from);
}
