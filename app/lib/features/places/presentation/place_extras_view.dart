import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/domain/account.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/community/presentation/contribution_sheets.dart';
import 'package:lunaway/features/community/presentation/photo_flow.dart';
import 'package:lunaway/features/community/presentation/place_community.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';
import 'package:lunaway/shared/images/thumbhash.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/source_badge.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The photos of a place in a strip, read online then from the cache, with
/// the photos waiting to be sent and a tile to add one. The strip keeps its
/// height while loading, so nothing below it jumps; each photo shows its
/// ThumbHash until it arrives. Offline without a copy, the photos the sync
/// brought (the latest three) stand in. Photos by a muted author never
/// show.
class PlacePhotos extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  static const height = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final muted = ref.watch(mutedAuthorIdsProvider);
    final extras = ref.watch(placeExtrasProvider(place.id));
    final waiting = [
      for (final e in ref.watch(pendingForPlaceProvider(place.id)))
        if (e.kind == ContributionKind.photo && e.fileId != null) e,
    ];
    bool shown(Photo p) => p.authorId == null || !muted.contains(p.authorId);
    final photos = switch (extras) {
      AsyncValue(:final value, hasValue: true) when value != null =>
        value.photos.where(shown).toList(),
      AsyncError() => place.coverPhotos.where(shown).toList(),
      _ => const <Photo>[],
    };
    if (extras is AsyncLoading && !extras.hasValue) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: SizedBox(
          height: height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              Skeleton(width: 160, height: height, radius: LunaTokens.radiusL),
              SizedBox(width: Space.s),
              Skeleton(width: 160, height: height, radius: LunaTokens.radiusL),
              SizedBox(width: Space.s),
              Skeleton(width: 160, height: height, radius: LunaTokens.radiusL),
            ],
          ),
        ),
      );
    }
    final add = _AddPhotoTile(
      first: photos.isEmpty && waiting.isEmpty,
      onTap: () => addPhotoToPlace(context, ref, place.id),
    );
    final tiles = <Widget>[
      for (final e in waiting) _PendingThumb(entry: e),
      for (final (i, photo) in photos.indexed)
        _Thumb(
          photo: photo,
          fetcher: ref.watch(imageFetcherProvider),
          source: itemSourceLabel(t, photo.sourceId, sources: place.sources),
          label: t.place.photoPosition(index: i + 1, count: photos.length),
          onTap: () => showPhotoViewer(
            context,
            photos,
            i,
            placeId: place.id,
            sources: place.sources,
            fetcher: ref.read(imageFetcherProvider),
          ),
        ),
      add,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photos.isEmpty && waiting.isEmpty)
            add
          else
            Semantics(
              label: t.place.photos,
              container: true,
              child: SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tiles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.s),
                  itemBuilder: (context, i) => tiles[i],
                ),
              ),
            ),
          if (extras is AsyncError && photos.isEmpty) ...[
            const SizedBox(height: Space.s),
            _OfflineNote(onRetry: () => ref.invalidate(placeExtrasProvider(place.id))),
          ],
        ],
      ),
    );
  }
}

/// The tile that adds a photo: a dashed frame in the strip, or a full-width
/// button when the place has none yet.
class _AddPhotoTile extends StatelessWidget {
  const new({required this.first, required this.onTap});

  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (first) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(AppIcons.addPhoto),
        label: Text(t.contribute.firstPhoto),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      );
    }
    return Semantics(
      button: true,
      label: t.contribute.addPhoto,
      // The excluded ink's tap, given back to a screen reader.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          ),
          onTap: onTap,
          child: SizedBox(
            width: 112,
            height: PlacePhotos.height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.addPhoto, color: scheme.primary, size: 28),
                const SizedBox(height: Space.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s),
                  child: Text(
                    t.contribute.addPhoto,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A photo waiting in the outbox: the picture itself, and its progress or
/// the wait for the network.
class _PendingThumb extends ConsumerWidget {
  const new({required this.entry});

  final PendingContribution entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(pendingPhotoProvider(entry.fileId!)).value;
    final progress = ref.watch(uploadProgressProvider).value?[entry.id];
    final sending = entry.state == OutboxState.sending;
    const width = PlacePhotos.height * 4 / 3;
    return Semantics(
      label: progress != null && sending
          ? t.photoFlow.sending(percent: '${(progress * 100).round()}')
          : t.photoFlow.pending,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: SizedBox(
          width: width,
          height: PlacePhotos.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes != null)
                Image.memory(bytes, fit: BoxFit.cover, excludeFromSemantics: true)
              else
                ColoredBox(color: scheme.surfaceContainerHigh),
              ColoredBox(color: scheme.scrim.withValues(alpha: 0.35)),
              Center(
                child: sending && progress != null
                    ? SizedBox.square(
                        dimension: 40,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3.5,
                          color: LunaTokens.of(context).onPhotoBackdrop,
                        ),
                      )
                    : Icon(
                        entry.failed ? AppIcons.error : AppIcons.waiting,
                        color: LunaTokens.of(context).onPhotoBackdrop,
                        size: 32,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const new({
    required this.photo,
    required this.fetcher,
    required this.source,
    required this.label,
    required this.onTap,
  });

  final Photo photo;
  final ImageFetcher fetcher;

  /// The source of the photo, on its corner: every value shown says where it
  /// came from.
  final String source;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const width = PlacePhotos.height * 4 / 3;
    final hash = photo.thumbhash;
    // The ThumbHash holds the frame until the first frame of the photo, so
    // the strip never shows an empty box.
    final placeholder = hash == null
        ? const Skeleton(width: width, height: PlacePhotos.height, radius: 0)
        : Image(image: ThumbHashImage(hash), fit: BoxFit.cover, excludeFromSemantics: true);
    return Semantics(
      button: true,
      label: '$label, $source',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: SizedBox(
          width: width,
          height: PlacePhotos.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: ResizeImage(CachedImage(photo.thumbUrl, fetcher: fetcher), width: 480),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, _) => AnimatedSwitcher(
                  duration: Motion.of(context, Motion.short),
                  child: frame == null ? placeholder : child,
                ),
                errorBuilder: (context, _, _) => hash != null
                    ? placeholder
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: const Icon(AppIcons.noImage),
                      ),
              ),
              Positioned(
                left: Space.s,
                bottom: Space.s,
                right: Space.s,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ExcludeSemantics(child: SourceBadge(label: source, onPhoto: true)),
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
  required ImageFetcher fetcher,
  String? placeId,
  List<PlaceSource> sources = const [],
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierColor: LunaTokens.of(context).photoBackdrop,
    pageBuilder: (_, _, _) => PhotoViewer(
      photos: photos,
      initial: index,
      placeId: placeId,
      sources: sources,
      fetcher: fetcher,
    ),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class PhotoViewer extends ConsumerStatefulWidget {
  const new({
    required this.photos,
    required this.initial,
    required this.fetcher,
    this.placeId,
    this.sources = const [],
    super.key,
  });

  final List<Photo> photos;
  final int initial;
  final ImageFetcher fetcher;
  final String? placeId;
  final List<PlaceSource> sources;

  @override
  ConsumerState<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _act(String action, Photo photo) async {
    switch (action) {
      case 'report':
        await showReportSheet(
          context,
          target: ReportTarget.photo,
          id: photo.id,
          placeId: widget.placeId,
        );
      case 'mute':
        final author = photo.authorId;
        final name = photo.authorName;
        if (author == null || name == null) return;
        await confirmMute(context, ref, Author(id: author, pseudonym: name));
        if (mounted) Navigator.of(context).pop();
      case 'delete':
        final t = context.t;
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.reportSheet.deletePhotoTitle),
            content: Text(t.reportSheet.deletePhotoBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.common.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.common.delete),
              ),
            ],
          ),
        );
        if (!(ok ?? false) || !mounted) return;
        final navigator = Navigator.of(context)..pop();
        await submitContribution(
          navigator.context,
          ContributionKind.deletePhoto,
          placeId: widget.placeId,
          payload: {'id': photo.id},
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final photo = widget.photos[_index];
    final account = ref.watch(accountControllerProvider);
    final mine = account is SignedIn && photo.authorId == account.account.id;
    final community = isLunawayCommunity(photo.sourceId);
    final onBackdrop = LunaTokens.of(context).onPhotoBackdrop;
    return Scaffold(
      backgroundColor: LunaTokens.of(context).photoBackdrop,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final p = widget.photos[i];
              final hash = p.thumbhash;
              final ratio = p.width != null && p.height != null && p.height! > 0
                  ? p.width! / p.height!
                  : null;
              return InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image(
                    // Decoded at the size of the screen, not of the file: a
                    // large photo would otherwise take tens of megabytes.
                    image: ResizeImage(
                      CachedImage(p.largeUrl, fetcher: widget.fetcher),
                      width:
                          (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      policy: ResizeImagePolicy.fit,
                    ),
                    fit: BoxFit.contain,
                    semanticLabel: t.place.photoPosition(index: i + 1, count: widget.photos.length),
                    // The ThumbHash in the photo's own frame while it loads.
                    frameBuilder: (context, child, frame, _) => frame != null
                        ? child
                        : hash != null && ratio != null
                        ? AspectRatio(
                            aspectRatio: ratio,
                            child: Image(image: ThumbHashImage(hash), fit: BoxFit.fill),
                          )
                        : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (context, _, _) => Icon(
                      AppIcons.brokenImage,
                      color: LunaTokens.of(context).onPhotoBackdropMuted,
                      size: 64,
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.s),
              child: Row(
                children: [
                  IconButton.filled(
                    tooltip: t.common.close,
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  SourceBadge(
                    label: itemSourceLabel(t, photo.sourceId, sources: widget.sources),
                    onPhoto: true,
                  ),
                  const SizedBox(width: Space.m),
                  Text(
                    '${_index + 1} / ${widget.photos.length}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onBackdrop),
                  ),
                  if (community)
                    PopupMenuButton<String>(
                      tooltip: t.contribute.more,
                      icon: Icon(AppIcons.moreVertical, color: onBackdrop),
                      onSelected: (action) => _act(action, photo),
                      itemBuilder: (context) => [
                        if (mine)
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: const Icon(AppIcons.delete),
                              title: Text(t.reportSheet.deletePhoto),
                            ),
                          )
                        else ...[
                          PopupMenuItem(
                            value: 'report',
                            child: ListTile(
                              leading: const Icon(AppIcons.report),
                              title: Text(t.reportSheet.photo),
                            ),
                          ),
                          if (photo.authorId != null && photo.authorName != null)
                            PopupMenuItem(
                              value: 'mute',
                              child: ListTile(
                                leading: const Icon(AppIcons.muted),
                                title: Text(t.reportSheet.mute(name: photo.authorName!)),
                              ),
                            ),
                        ],
                      ],
                    )
                  else
                    const SizedBox(width: Space.s),
                ],
              ),
            ),
          ),
          if (photo.authorName != null)
            Positioned(
              left: Space.l,
              right: Space.l,
              bottom: Space.l,
              child: SafeArea(
                top: false,
                child: Text(
                  photo.authorName!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onBackdrop),
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
    final muted = ref.watch(mutedAuthorIdsProvider);
    final account = ref.watch(accountControllerProvider);
    final me = account is SignedIn ? account.account.id : null;
    // The account's own review shows in its own card above; a muted
    // author's never.
    bool shown(Review r) =>
        (r.authorId == null || !muted.contains(r.authorId)) && (me == null || r.authorId != me);
    final ownText =
        OwnReview.of(
          ref.watch(placeExtrasProvider(place.id)).value?.myReview,
          ref.watch(pendingForPlaceProvider(place.id)),
        )?.text !=
        null;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(t.place.reviewsTitle, style: theme.textTheme.titleLarge),
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
                    SourceBadge(label: itemSourceLabel(t, r.sourceId, sources: place.sources)),
                    RatingText(average: r.average, count: r.count),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          YourReview(place: place),
          const SizedBox(height: Space.l),
          switch (reviews) {
            AsyncData(:final value) when value.page.nodes.where(shown).isEmpty => Text(
              // With the account's own review just above, "none" would read
              // as if it had not been kept.
              ownText ? t.place.noOtherReviews : t.place.noReviews,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in value.page.nodes.where(shown))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: ReviewCard(review: r, sources: place.sources, placeId: place.id),
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

class ReviewCard extends StatelessWidget {
  const new({required this.review, this.sources = const [], this.placeId, super.key});

  final Review review;
  final List<PlaceSource> sources;

  /// The place the review is shown on, for a report.
  final String? placeId;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final rating = review.rating;
    // The day of the stay is a calendar date already; the writing time is
    // an instant, shown in the reader's zone.
    final date = DateFormat.yMMMM(t.$meta.locale.languageCode)
        .format(review.visitedAt ?? review.createdAt.toLocal());
    // A deleted account leaves its community reviews without a name.
    final author =
        review.authorName ?? (isLunawayCommunity(review.sourceId) ? t.place.deletedAccount : null);
    final vehicle = review.authorVehicle;
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
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SourceBadge(label: itemSourceLabel(t, review.sourceId, sources: sources)),
                    ReviewMenu(review: review, placeId: placeId),
                  ],
                ),
              ],
            ),
            if (review.text != null) ...[
              const SizedBox(height: Space.s),
              Text(review.text!, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: Space.s),
            Text(
              [?author, if (vehicle != null) t.reviewVehicle(vehicle), date].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
