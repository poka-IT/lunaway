import 'package:logging/logging.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/translation/domain/translation.dart';

final _log = Logger('translation');

/// Where translations come from: Lunaway's API, which asks its own
/// translation server. Throws [TranslationException] with why it failed.
abstract interface class TranslationSource {
  Future<Translation> translate(TranslatableItem item, String targetLang);
}

final class GraphQLTranslationSource implements TranslationSource {
  new(this.client);

  final GraphQLClient client;

  // No session goes with it: the server translates the same text for
  // every reader, so nothing ties the account to what it reads.
  @override
  Future<Translation> translate(TranslatableItem item, String targetLang) async {
    try {
      return await client.execute(translateOperation, translateVariables(item, targetLang));
    } on GraphQLRateLimitedException {
      // The client already waited what the server asked, or the wait was
      // too long to keep a spinner up.
      throw const TranslationException(TranslationFailure.busy);
    } on GraphQLNetworkException catch (e) {
      _log.info('translation of $item: no answer: $e');
      throw const TranslationException(TranslationFailure.offline);
    } on GraphQLResponseException catch (e) {
      throw TranslationException(_failure(e));
    }
  }

  static TranslationFailure _failure(GraphQLResponseException e) {
    if (e.errors.any((error) => error.reason == 'UNSUPPORTED_LANGUAGE')) {
      return TranslationFailure.unsupported;
    }
    if (e.hasCode(GraphQLError.notFound)) return TranslationFailure.gone;
    if (e.hasCode(GraphQLError.rateLimited)) return TranslationFailure.busy;
    // Down, failed, or an API older than the feature: nothing the reader
    // can fix, worth trying again later.
    _log.info('translation refused: $e');
    return TranslationFailure.unavailable;
  }
}
