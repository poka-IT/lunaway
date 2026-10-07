import 'package:logging/logging.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

final _log = Logger('external');

/// Where the external community source's reviews, ratings and photos of a
/// place come from: the API, online, when the place's card opens.
abstract interface class PlaceExternalSource {
  /// [ExternalContent.empty] when the place no longer exists or the API
  /// does not serve the source.
  Future<ExternalContent> fetch(String placeId, {required int first});

  Future<ReviewPage> moreReviews(String placeId, {required String after, required int first});
}

final class GraphQLPlaceExternalSource implements PlaceExternalSource {
  new(this.client);

  final GraphQLClient client;

  // No session goes with these reads: the server serves the same to every
  // reader, so nothing ties the account to the places it looks at.
  @override
  Future<ExternalContent> fetch(String placeId, {required int first}) async {
    try {
      final content = await client.execute<ExternalContent?>(externalOperation, {
        'id': placeId,
        'first': first,
      });
      return content ?? ExternalContent.empty;
    } on GraphQLResponseException catch (e) {
      // An API older than the source refuses the fields: the place has
      // nothing from it, which is no error to show.
      if (e.errors.any((error) => error.unknownField)) {
        _log.fine('the API does not serve the external community source yet');
        return ExternalContent.empty;
      }
      rethrow;
    }
  }

  @override
  Future<ReviewPage> moreReviews(String placeId, {required String after, required int first}) =>
      client.execute(externalReviewsOperation, {'id': placeId, 'first': first, 'after': after});
}
