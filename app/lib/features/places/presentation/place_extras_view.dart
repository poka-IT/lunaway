import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The photos of a place in a strip, read online then from the cache; the
/// strip keeps its height while loading, so nothing below it jumps.
class PlacePhotos extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  static const height = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return switch (ref.watch(placeExtrasProvider(place.id))) {
      AsyncData(value: final extras?) when extras.photos.isNotEmpty => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: Semantics(
          label: t.place.photos,
          container: true,
          child: SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: extras.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (context, i) => _Thumb(
                photo: extras.photos[i],
                label: t.place.photoPosition(index: i + 1, count: extras.photos.length),
                onTap: () => showPhotoViewer(context, extras.photos, i, sources: place.sources),
              ),
            ),
          ),
        ),
      ),
      AsyncData() => const SizedBox.shrink(),
      AsyncError() => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: _OfflineNote(onRetry: () => ref.invalidate(placeExtrasProvider(place.id))),
      ),
      AsyncLoading() => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: SizedBox(
          height: height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              Skeleton(width: 160, height: height, radius: 16),
              SizedBox(width: Space.s),
              Skeleton(width: 160, height: height, radius: 16),
              SizedBox(width: Space.s),
              Skeleton(width: 160, height: height, radius: 16),
            ],
          ),
        ),
      ),
    };
  }
}

class _Thumb extends StatelessWidget {
  const new({required this.photo, required this.label, required this.onTap});

  final Photo photo;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const width = PlacePhotos.height * 4 / 3;
    return Semantics(
      button: true,
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LunaTokens.of(context).radiusL),
        child: SizedBox(
          width: width,
          height: PlacePhotos.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: ResizeImage(CachedImage(photo.thumbUrl), width: 480),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                // The skeleton holds the place until the first frame, so the
                // strip never changes size while photos arrive.
                frameBuilder: (context, child, frame, _) => frame == null
                    ? const Skeleton(width: width, height: PlacePhotos.height, radius: 0)
                    : child,
                errorBuilder: (context, _, _) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(AppIcons.noImage),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const new({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(AppIcons.offline, color: theme.colorScheme.onSurfaceVariant),
        title: Text(t.place.extrasOffline, style: theme.textTheme.bodyMedium),
        trailing: TextButton(onPressed: onRetry, child: Text(t.common.retry)),
      ),
    );
  }
}

/// The photos full screen, one at a time, with pinch to zoom.
Future<void> showPhotoViewer(
  BuildContext context,
  List<Photo> photos,
  int index, {
  List<PlaceSource> sources = const [],
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierColor: LunaTokens.of(context).photoBackdrop,
    pageBuilder: (_, _, _) => PhotoViewer(photos: photos, initial: index, sources: sources),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class PhotoViewer extends StatefulWidget {
  const new({required this.photos, required this.initial, this.sources = const [], super.key});

  final List<Photo> photos;
  final int initial;
  final List<PlaceSource> sources;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: LunaTokens.of(context).photoBackdrop,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Image(
                  image: CachedImage(widget.photos[i].largeUrl),
                  fit: BoxFit.contain,
                  semanticLabel: t.place.photoPosition(index: i + 1, count: widget.photos.length),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (context, _, _) => Icon(
                    AppIcons.brokenImage,
                    color: LunaTokens.of(context).onPhotoBackdropMuted,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.s),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: t.common.close,
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  SourceBadge(label: sourceName(t, photo.sourceId, sources: widget.sources)),
                  const SizedBox(width: Space.m),
                  Text(
                    '${_index + 1} / ${widget.photos.length}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: LunaTokens.of(context).onPhotoBackdrop),
                  ),
                  const SizedBox(width: Space.s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ratings of the place per source, then its reviews, newest first,
/// with the next page on demand.
class PlaceReviewsSection extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final reviews = ref.watch(placeReviewsProvider(place.id));
    final total = combinedRating(place.ratings);
    if (total == null && reviews.value?.page.nodes.isEmpty != false && reviews is! AsyncLoading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(t.place.reviewsTitle, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final r in place.ratings)
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SourceBadge(label: sourceName(t, r.sourceId, sources: place.sources)),
                    RatingText(average: r.average, count: r.count),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          switch (reviews) {
            AsyncData(:final value) when value.page.nodes.isEmpty => Text(
              t.place.noReviews,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in value.page.nodes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: ReviewCard(review: r, sources: place.sources),
                  ),
                if (value.page.hasNextPage)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: value.loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(Space.m),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: () =>
                                ref.read(placeReviewsProvider(place.id).notifier).loadMore(),
                            icon: Icon(value.moreFailed ? AppIcons.retry : AppIcons.expand),
                            label: Text(
                              value.moreFailed ? t.place.moreReviewsFailed : t.place.moreReviews,
                            ),
                          ),
                  ),
              ],
            ),
            AsyncError() => _OfflineNote(
              onRetry: () => ref.invalidate(placeExtrasProvider(place.id)),
            ),
            AsyncLoading() => const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Skeleton(height: 96, radius: 20),
                SizedBox(height: Space.sm),
                Skeleton(height: 96, radius: 20),
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// "★ 4,3 (128)": the rating and how many reviews it rests on.
class RatingText extends StatelessWidget {
  const new({required this.average, required this.count, this.style, super.key});

  final double average;
  final int count;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return Semantics(
      label: '${t.place.stars(rating: t.ratingValue(average))}, ${t.place.reviewsCount(n: count)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.star, size: 20, color: theme.colorScheme.tertiary),
          const SizedBox(width: Space.hair),
          Flexible(
            child: Text(
              '${t.ratingValue(average)} ($count)',
              style: style ?? theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewCard extends StatelessWidget {
  const new({required this.review, this.sources = const [], super.key});

  final Review review;
  final List<PlaceSource> sources;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final rating = review.rating;
    final date = DateFormat.yMMMM(t.$meta.locale.languageCode)
        .format((review.visitedAt ?? review.createdAt).toLocal());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A wrap, not a row: at a large text size the badge moves under
            // the stars instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s,
              runSpacing: Space.xxs,
              children: [
                if (rating != null)
                  Semantics(
                    label: t.place.stars(rating: '$rating'),
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= rating ? AppIcons.star : AppIcons.starEmpty,
                            size: 18,
                            color: theme.colorScheme.tertiary,
                          ),
                      ],
                    ),
                  ),
                SourceBadge(label: sourceName(t, review.sourceId, sources: sources)),
              ],
            ),
            if (review.text != null) ...[
              const SizedBox(height: Space.s),
              Text(review.text!, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: Space.s),
            Text(
              [?review.authorName, ?review.authorVehicle, date].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
