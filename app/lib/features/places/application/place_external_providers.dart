import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/place_external_source.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'place_external_providers.g.dart';

final _log = Logger('external');

/// Reviews per page of the external community source: the API's default.
const externalPageSize = 20;

// keepAlive: a stateless reader over the app-wide client.
@Riverpod(keepAlive: true)
PlaceExternalSource placeExternalSource(Ref ref) =>
    GraphQLPlaceExternalSource(ref.watch(graphQLClientProvider));

/// The external community source's content on screen, and whether its next
/// page of reviews is on its way.
@immutable
final class ExternalList {
  const new(this.content, {this.loadingMore = false, this.moreFailed = false});

  final ExternalContent content;
  final bool loadingMore;

  /// The last attempt at the next page failed; the button offers a retry.
  final bool moreFailed;
}

/// What the external community source says of a place, read when its card
/// opens and held in memory while it shows: never written to the device's
/// stores, so it is gone with the card. A failure surfaces without retry:
/// the card shows Lunaway's own content and leaves the source out.
@Riverpod(retry: noRetry)
class PlaceExternal extends _$PlaceExternal {
  @override
  Future<ExternalList> build(String placeId) async => ExternalList(
    await ref.watch(placeExternalSourceProvider).fetch(placeId, first: externalPageSize),
  );

  Future<void> loadMore() async {
    final current = state.value;
    final page = current?.content.reviews;
    final after = page?.endCursor;
    if (current == null || current.loadingMore || page == null || !page.hasNextPage) return;
    if (after == null) return;
    state = AsyncData(ExternalList(current.content, loadingMore: true));
    try {
      final next = await ref
          .read(placeExternalSourceProvider)
          .moreReviews(placeId, after: after, first: externalPageSize);
      if (!ref.mounted) return;
      state = AsyncData(ExternalList(current.content.withReviews(page.append(next))));
    } on Object catch (e) {
      _log.info('more external reviews of $placeId failed: $e');
      if (!ref.mounted) return;
      state = AsyncData(ExternalList(current.content, moreFailed: true));
    }
  }
}

/// The reviews a place shows: Lunaway's and the external source's in one
/// list, newest first, each keeping its source.
@immutable
final class ReviewFeed {
  const new({required this.reviews, this.next, this.loadingMore = false, this.moreFailed = false});

  final List<Review> reviews;

  /// The list the next page comes from; null when both are read whole.
  final ReviewOrigin? next;
  final bool loadingMore;
  final bool moreFailed;
}

/// Lunaway's reviews of a place merged with the external source's. The
/// external list counts as empty until it arrives or when it fails: the
/// card never waits on it. A muted author's reviews never show, nor the
/// account's own, which has its own card above the list.
@riverpod
ReviewFeed placeReviewFeed(Ref ref, String placeId) {
  final ours = ref.watch(placeReviewsProvider(placeId)).value;
  final theirs = ref.watch(placeExternalProvider(placeId)).value;
  final muted = ref.watch(mutedAuthorIdsProvider);
  final account = ref.watch(accountControllerProvider);
  final me = account is SignedIn ? account.account.id : null;
  bool shown(Review r) =>
      (r.authorId == null || !muted.contains(r.authorId)) && (me == null || r.authorId != me);
  final merged = mergeReviews(
    ours?.page ?? ReviewPage.empty,
    theirs?.content.reviews ?? ReviewPage.empty,
  );
  return ReviewFeed(
    reviews: merged.reviews.where(shown).toList(),
    next: merged.next,
    loadingMore: (ours?.loadingMore ?? false) || (theirs?.loadingMore ?? false),
    moreFailed: switch (merged.next) {
      ReviewOrigin.lunaway => ours?.moreFailed ?? false,
      ReviewOrigin.external => theirs?.moreFailed ?? false,
      null => false,
    },
  );
}
