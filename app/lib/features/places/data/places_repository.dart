import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
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

/// A town derived from the places the device holds: the search can move the
/// map there without a gazetteer.
@immutable
final class Municipality {
  const new({required this.name, required this.center, required this.placeCount, this.postcode});

  final String name;
  final String? postcode;
  final LatLng center;
  final int placeCount;

  @override
  bool operator ==(Object other) =>
      other is Municipality &&
      other.name == name &&
      other.postcode == postcode &&
      other.center == center &&
      other.placeCount == placeCount;

  @override
  int get hashCode => Object.hash(name, postcode, center, placeCount);
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
