import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';

final _log = Logger('digests');

/// Where the digests of a list's rows come from: the API, online.
abstract interface class PlaceDigestSource {
  /// The digests of [ids], those a list just received from the API.
  Future<List<PlaceDigest>> ofPlaces(List<String> ids, {required String language});

  /// The digests of the places inside [area], already on the API's grid:
  /// a list read from the map's tiles, whose ids would say more of the view
  /// than the tiles do.
  Future<List<PlaceDigest>> inArea(GeoBounds area, {required String language});
}

final class GraphQLPlaceDigestSource implements PlaceDigestSource {
  new(this.client);

  final GraphQLClient client;

  // No session goes with these reads, as with a place's external content:
  // nothing ties the account to the places it lists.
  @override
  Future<List<PlaceDigest>> ofPlaces(List<String> ids, {required String language}) =>
      _ask({'ids': ids, 'language': language});

  @override
  Future<List<PlaceDigest>> inArea(GeoBounds area, {required String language}) =>
      _ask({'bbox': bboxInput(area), 'language': language});

  Future<List<PlaceDigest>> _ask(Map<String, Object?> variables) async {
    try {
      return await client.execute(placeDigestsOperation, variables);
    } on GraphQLResponseException catch (e) {
      // An API older than the digests: the rows show what the summaries
      // hold, which is no error to show.
      if (e.errors.any((error) => error.unknownField)) {
        _log.fine('the API does not serve the digests yet');
        return const [];
      }
      rethrow;
    }
  }
}
