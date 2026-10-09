import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/data/place_thumbs.dart';
import 'package:lunaway/features/navigation/presentation/rich_mark_art.dart';
import 'package:lunaway/features/navigation/presentation/rich_marks.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'rich_marks_providers.g.dart';

/// The photos and prices of the places the route maps draw rich.
// keepAlive: it remembers each place it asked about for the whole run, so
// a place passed again or shown on the preview then the guidance is asked
// once.
@Riverpod(keepAlive: true)
PlaceThumbs placeThumbs(Ref ref) {
  final thumbs = PlaceThumbs(GraphQLPlaceThumbs(ref.watch(graphQLClientProvider)));
  ref.onDispose(thumbs.dispose);
  return thumbs;
}

/// What draws the rich marks of the route maps.
// keepAlive: it remembers which photos failed for the run, so a place
// whose photo would not come is not asked again at each pass.
@Riverpod(keepAlive: true)
RichArt richArt(Ref ref) {
  final fetcher = ref.watch(imageFetcherProvider);
  return PlaceRichArt(
    thumbs: ref.watch(placeThumbsProvider),
    load: (url) => cachedImageBytes(url, fetcher),
  );
}
