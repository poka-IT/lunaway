import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/town_names.dart';
import 'package:meta/meta.dart';

/// Read access to the places the device holds. Every method answers from the
/// local store, without network; filters are applied locally.
abstract interface class PlacesRepository {
  /// Every place passing [filter], as light rows for the map's clustered
  /// source. Emits again when a sync changes the store.
  Stream<List<PlaceSummary>> watchAll(PlaceFilter filter);

  /// Places inside [bounds] passing [filter], nearest to [center] first, at
  /// most [limit].
  Stream<List<PlaceSummary>> watchInBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng center,
    int limit = 200,
  });

  /// The full place, or null once a sync removed it.
  Stream<Place?> watchPlace(String id);

  /// Places and towns whose name starts with the words of [text], accents
  /// ignored.
  Future<SearchResults> search(String text, {LatLng? near, int limit = 20});

  /// How many places the device holds, whatever the filter.
  Stream<int> watchCount();

  /// How many places pass [filter], inside [bounds] when given: the list's
  /// count of a view and the button of the filter sheet.
  Future<int> countMatching(PlaceFilter filter, {GeoBounds? bounds});

  /// Where the sync of [region] stands: when it last completed (null before
  /// the first full sync ends) and whether a run is waiting to resume.
  Stream<SyncState> watchSync(String region);

  /// Bytes the local store takes on the device.
  Future<int> storageSizeBytes();
}

/// A town of the places, from the API's towns or from those the device
/// holds: the search moves the map there without a gazetteer.
@immutable
final class Municipality {
  const new({
    required this.name,
    required this.center,
    required this.placeCount,
    this.postcode,
    this.department,
    this.countryCode,
  });

  final String name;
  final String? postcode;

  /// The French department (`07`, `2A`, `974`); null outside France. With
  /// the postcode it tells homonyms apart.
  final String? department;

  /// ISO 3166-1 alpha-2, upper case, when known.
  final String? countryCode;
  final LatLng center;

  /// Every place of the town the API or the device holds, wherever the
  /// map looks.
  final int placeCount;

  @override
  bool operator ==(Object other) =>
      other is Municipality &&
      other.name == name &&
      other.postcode == postcode &&
      other.department == department &&
      other.countryCode == countryCode &&
      other.center == center &&
      other.placeCount == placeCount;

  @override
  int get hashCode => Object.hash(name, postcode, department, countryCode, center, placeCount);
}

/// The towns the device lists for [text], from its places grouped by town
/// name and area (`area`: the department in France, the start of the
/// postcode elsewhere), at most [max]:
///
/// - in one area and country, two groups are one town when their names
///   fold alike, or when one starts the other and their postcodes agree:
///   two spellings of one commune ("Chamonix" and "Chamonix-Mont-Blanc",
///   74400), which the server tells apart by the commune's code and the
///   device, keeping no code, by the postcode; the bigger group gives its
///   name;
/// - then a group of an unknown area joins the one town of its name and
///   country, when there is exactly one, whatever their sizes;
///
/// then the towns named exactly as typed first (the homonyms of several
/// departments together), then by their places.
List<Municipality> mergeTowns(
  String text,
  List<({Municipality town, String? area})> groups, {
  int max = 6,
}) {
  final towns = [for (final g in groups) (town: g.town, area: g.area, key: townKey(g.town.name))];
  Municipality joined(Municipality big, Municipality small) {
    final n = big.placeCount + small.placeCount;
    LatLng mid(LatLng a, int na, LatLng b, int nb) =>
        LatLng((a.lat * na + b.lat * nb) / (na + nb), (a.lon * na + b.lon * nb) / (na + nb));
    return Municipality(
      name: big.name,
      postcode: big.postcode ?? small.postcode,
      department: big.department ?? small.department,
      countryCode: big.countryCode ?? small.countryCode,
      center: mid(big.center, big.placeCount, small.center, small.placeCount),
      placeCount: n,
    );
  }

  bool oneTown(({Municipality town, String? area, String key}) a, String bKey, Municipality b) =>
      a.key == bKey ||
      (a.town.postcode != null &&
          a.town.postcode == b.postcode &&
          (a.key.startsWith('$bKey ') || bKey.startsWith('${a.key} ')));

  // Biggest first: a group joins the bigger one it belongs to.
  towns.sort((a, b) => b.town.placeCount.compareTo(a.town.placeCount));
  final kept = <({Municipality town, String? area, String key})>[];
  void into(int i, Municipality small) {
    final k = kept[i];
    kept[i] = (town: joined(k.town, small), area: k.area, key: k.key);
  }

  for (final g in towns.where((g) => g.area != null)) {
    final i = kept.indexWhere(
      (k) =>
          k.area == g.area && k.town.countryCode == g.town.countryCode && oneTown(k, g.key, g.town),
    );
    if (i < 0) {
      kept.add(g);
    } else {
      into(i, g.town);
    }
  }
  for (final g in towns.where((g) => g.area == null)) {
    final named = [
      for (var i = 0; i < kept.length; i++)
        if (kept[i].area != null &&
            kept[i].key == g.key &&
            kept[i].town.countryCode == g.town.countryCode)
          i,
    ];
    final alone = kept.indexWhere(
      (k) => k.area == null && k.key == g.key && k.town.countryCode == g.town.countryCode,
    );
    if (named.length == 1) {
      into(named.single, g.town);
    } else if (alone >= 0) {
      into(alone, g.town);
    } else {
      kept.add(g);
    }
  }
  final typed = townKey(text);
  kept.sort((a, b) {
    final exact = (b.key == typed ? 1 : 0).compareTo(a.key == typed ? 1 : 0);
    return exact != 0 ? exact : b.town.placeCount.compareTo(a.town.placeCount);
  });
  return [for (final k in kept.take(max)) k.town];
}

@immutable
final class SearchResults {
  const new({this.places = const [], this.municipalities = const [], this.addresses});

  static const empty = SearchResults();

  final List<PlaceSummary> places;
  final List<Municipality> municipalities;

  /// The addresses the server's geocoders found with the places, when the
  /// places came from the API; null when the device searched its own.
  final List<AddressMatch>? addresses;

  bool get isEmpty => places.isEmpty && municipalities.isEmpty;
}

/// Turns what a user typed into an FTS5 prefix query: every word must start a
/// word of the indexed text. Quotes and operators the user typed are dropped
/// so a stray `"` or `-` can never break the query. Returns null when nothing
/// searchable is left.
String? ftsPrefixQuery(String text) {
  final words = text
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .take(8)
      .map((w) => '"${w.toLowerCase()}"*');
  if (words.isEmpty) return null;
  return words.join(' ');
}
