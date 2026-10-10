import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:meta/meta.dart';

/// What a row of a list shows of a place beyond its summary
/// (`PlaceDigest` in the contract): its ratings by source, the opening of
/// its description, the day Lunaway added it. Read online for the rows on
/// screen and held in memory only: the external source's ratings never
/// reach the device's stores.
@immutable
final class PlaceDigest {
  const new({required this.placeId, required this.addedAt, this.ratings = const [], this.excerpt});

  final String placeId;

  /// By source, never added together: Lunaway users' and the external
  /// community source's summary.
  final List<SourceRating> ratings;

  /// The opening of the description, in the language asked when a source
  /// wrote one in it.
  final LocalizedText? excerpt;
  final DateTime addedAt;

  @override
  bool operator ==(Object other) =>
      other is PlaceDigest &&
      other.placeId == placeId &&
      other.addedAt == addedAt &&
      other.excerpt == excerpt &&
      _sameRatings(other.ratings, ratings);

  @override
  int get hashCode => Object.hash(placeId, addedAt, excerpt, Object.hashAll(ratings));
}

bool _sameRatings(List<SourceRating> a, List<SourceRating> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One source's rating as a screen shows it: its average, how many ratings
/// it rests on, and whose it is.
typedef RowRating = ({double average, int count, String sourceId});

/// From this many ratings, Lunaway users' average stands on its own: one
/// rating more then moves it by a fifth of a star at most, and the
/// standard error of a mean of ratings spread as on a five-star scale
/// (about one star) is near a quarter of a star. Below it, one or two
/// users' ratings next to hundreds elsewhere read as the place's rating
/// (one 4 put 246 ratings of 3.3 out of sight, 2026-10-10).
const lunawayRatingsOnTheirOwn = 20;

/// What a place shows of its ratings, in order, from its ratings by source
/// (Lunaway users' and the other sources'), on every screen: the card, the
/// rows of a list, "On the way". Lunaway users' first; beside it, while
/// they count fewer than [lunawayRatingsOnTheirOwn], the other source with
/// the most ratings, each with its own count and never added together;
/// from that count, Lunaway users' alone. Without a Lunaway rating, the
/// other source's. Empty when no source rated the place. What orders and
/// filters places is the mean of every rating ([sortRating],
/// `Place.ratingForFilters`).
List<RowRating> shownRatings(Iterable<SourceRating> ratings) {
  SourceRating? ours;
  SourceRating? other;
  for (final r in ratings) {
    if (r.count <= 0) continue;
    if (isLunawayCommunity(r.sourceId)) {
      if (ours == null || r.count > ours.count) ours = r;
    } else if (other == null || r.count > other.count) {
      other = r;
    }
  }
  RowRating row(SourceRating r) => (average: r.average, count: r.count, sourceId: r.sourceId);
  return [
    if (ours != null) row(ours),
    if (other != null && (ours == null || ours.count < lunawayRatingsOnTheirOwn)) row(other),
  ];
}

/// The ratings a row of [place] shows ([shownRatings]), with its [digest]
/// when the API answered for it: the digest's by source, else the
/// summary's Lunaway rating (read from the sync or the API's list; the
/// tiles carry none).
List<RowRating> rowRatings(PlaceSummary place, PlaceDigest? digest) =>
    shownRatings(_ratingsOf(place, digest));

/// Every rating at hand for [place]: its [digest]'s by source, and the
/// summary's Lunaway rating when the digest has none.
List<SourceRating> _ratingsOf(PlaceSummary place, PlaceDigest? digest) {
  final ratings = digest?.ratings ?? const <SourceRating>[];
  final hasOurs = ratings.any((r) => isLunawayCommunity(r.sourceId) && r.count > 0);
  return [
    ...ratings,
    if (!hasOurs && place.ratingCount > 0)
      if (place.ratingAverage case final average?)
        SourceRating(sourceId: communityCcBySourceId, average: average, count: place.ratingCount),
  ];
}

/// What the order by rating compares for [place]: the rating the filters
/// use (`Place.ratingForFilters`, every rating of every source, each
/// weighing the same, as the server computes it and the tiles carry it),
/// else the same mean of the ratings at hand; and how many ratings stand
/// behind it, for a tie. Null when no source rated the place.
({double average, int count})? sortRating(PlaceSummary place, PlaceDigest? digest) {
  final all = combinedRating(_ratingsOf(place, digest));
  final average = place.ratingForFilters ?? all?.average;
  if (average == null) return null;
  return (average: average, count: all?.count ?? 0);
}

/// How the list beside the map is ordered; the user's choice is kept.
enum ListSort {
  /// Nearest to the user, or to the map's centre, first.
  distance,

  /// Best rated first ([sortRating]: every source's ratings together), the
  /// places nobody rated after them, each group nearest first.
  rating,

  /// Added to Lunaway most recently first, by day, then nearest first.
  newest;

  static ListSort fromName(String? name) => values.asNameMap()[name] ?? ListSort.distance;
}

/// [places], nearest first, in the order of [sort]: the order they come
/// in stands for the distance, and settles every tie.
List<PlaceSummary> sortRows(
  List<PlaceSummary> places,
  Map<String, PlaceDigest> digests,
  ListSort sort,
) {
  if (sort == ListSort.distance) return places;
  final rank = {for (final (i, p) in places.indexed) p.id: i};
  int byDistance(PlaceSummary a, PlaceSummary b) => rank[a.id]!.compareTo(rank[b.id]!);
  final sorted = [...places];
  switch (sort) {
    case ListSort.distance:
      break;
    case ListSort.rating:
      final ratings = {for (final p in places) p.id: sortRating(p, digests[p.id])};
      sorted.sort((a, b) {
        final ra = ratings[a.id];
        final rb = ratings[b.id];
        if (ra == null || rb == null) {
          if (ra != rb) return ra == null ? 1 : -1;
          return byDistance(a, b);
        }
        final byAverage = rb.average.compareTo(ra.average);
        if (byAverage != 0) return byAverage;
        final byCount = rb.count.compareTo(ra.count);
        return byCount != 0 ? byCount : byDistance(a, b);
      });
    case ListSort.newest:
      final days = {for (final p in places) p.id: _addedDay(p, digests[p.id])};
      sorted.sort((a, b) {
        final da = days[a.id];
        final db = days[b.id];
        if (da == null || db == null) {
          if (da != db) return da == null ? 1 : -1;
          return byDistance(a, b);
        }
        final byDay = db.compareTo(da);
        return byDay != 0 ? byDay : byDistance(a, b);
      });
  }
  return sorted;
}

/// The day [place] was added, in UTC: its digest's, else the time its id
/// carries (a UUID v7, made when Lunaway created the place).
DateTime? _addedDay(PlaceSummary place, PlaceDigest? digest) {
  final at = digest?.addedAt ?? uuidV7Time(place.id);
  if (at == null) return null;
  final utc = at.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// The creation time a UUID v7 carries (its first 48 bits, milliseconds
/// since the epoch); null for another version or a malformed id.
DateTime? uuidV7Time(String id) {
  final hex = id.replaceAll('-', '');
  if (hex.length != 32 || hex[12] != '7') return null;
  final ms = int.tryParse(hex.substring(0, 12), radix: 16);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// The area a list read from the map's tiles asks the digests of:
/// [widened], a view already widened to the API's grid, or null when it is
/// wider than the API serves.
GeoBounds? digestArea(GeoBounds widened) {
  final area = (widened.north - widened.south) * (widened.east - widened.west);
  return area > maxDigestAreaDeg2 ? null : widened;
}

/// Largest area the API reads digests of (`MAX_DIGEST_AREA_DEG2`).
const maxDigestAreaDeg2 = 1.0;

/// Most places the API reads digests of by id (`MAX_DIGEST_IDS`).
const maxDigestIds = 200;
