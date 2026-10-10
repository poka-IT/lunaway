import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/layout/pointer_input.dart';
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
import 'package:lunaway/features/places/application/place_external_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/presentation/rating_text.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/translation/domain/translation.dart';
import 'package:lunaway/features/translation/presentation/translatable_text.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cached_image.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';
import 'package:lunaway/shared/images/retrying_image.dart';
import 'package:lunaway/shared/images/thumbhash.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/source_names.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
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
    final ours = switch (extras) {
      AsyncValue(:final value, hasValue: true) when value != null =>
        value.photos.where(shown).toList(),
      AsyncError() => place.coverPhotos.where(shown).toList(),
      _ => const <Photo>[],
    };
    // The external community source's photos follow Lunaway's, as soon as
    // they come; the strip never waits for them.
    final external = ref.watch(placeExternalProvider(place.id)).value?.content.photos ?? const [];
    final photos = [...ours, ...external];
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
          credit: photoCredit(t, photo, sources: place.sources),
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
          mouseCursor: WidgetStateMouseCursor.clickable,
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
    required this.credit,
    required this.label,
    required this.onTap,
  });

  final Photo photo;
  final ImageFetcher fetcher;

  /// The source of the photo, on its corner: every value shown says where it
  /// came from.
  final String source;

  /// The source and, for another community's photo, its author: what a
  /// screen reader says of the photo.
  final String credit;
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
    final empty = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);
    final author = isLunawayCommunity(photo.sourceId) ? null : photo.authorName;
    return Semantics(
      button: true,
      label: '$label, $credit',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: SizedBox(
          width: width,
          height: PlacePhotos.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RetryingImage(
                image: ResizeImage(CachedImage(photo.thumbUrl, fetcher: fetcher), width: 480),
                fit: BoxFit.cover,
                placeholder: placeholder,
                // A photo the proxy has not fetched yet keeps its frame,
                // still: it may wait hours for the server's daily budget,
                // and a pulse would say it is on its way.
                waiting: hash != null ? placeholder : empty,
                error: hash != null
                    ? placeholder
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: const Icon(AppIcons.noImage),
                      ),
              ),
              // The external community source's long name would cover half
              // the tile: a short tag in a corner stands for it, the whole
              // name in the viewer, the card's sources and what a screen
              // reader says of the photo; its author's tag sits in the
              // opposite corner, so the middle of the photo stays clear.
              if (photo.sourceId == extcomSourceId) ...[
                Positioned(
                  left: Space.s,
                  top: Space.s,
                  right: Space.s,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ExcludeSemantics(
                      child: SourceBadge(
                        label: context.t.sources.extcom.short,
                        icon: AppIcons.externalSource,
                        onPhoto: true,
                      ),
                    ),
                  ),
                ),
                if (author case final name?)
                  Positioned(
                    left: Space.s,
                    bottom: Space.s,
                    right: Space.s,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: ExcludeSemantics(child: SourceBadge(label: name, onPhoto: true)),
                    ),
                  ),
              ] else
                Positioned(
                  left: Space.s,
                  bottom: Space.s,
                  right: Space.s,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    // Another community's photo is credited to its author
                    // too, in a tag of its own under the source's, so the
                    // narrow tile keeps both readable.
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SourceBadge(label: source, onPhoto: true, maxLines: 3),
                          if (author case final name?) ...[
                            const SizedBox(height: Space.xxs),
                            SourceBadge(label: name, onPhoto: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(mouseCursor: WidgetStateMouseCursor.clickable, onTap: onTap),
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

/// The photos full screen, one at a time, with pinch to zoom: a swipe, a
/// drag of the mouse, the arrow keys or the side buttons turn to the next
/// one, Escape closes. A popup route: on the web the map's element under it
/// is covered while it shows, so neither a click nor a drag reaches the map.
Future<void> showPhotoViewer(
  BuildContext context,
  List<Photo> photos,
  int index, {
  required ImageFetcher fetcher,
  String? placeId,
  List<PlaceSource> sources = const [],
}) => showGeneralDialog<void>(
  context: context,
  barrierColor: LunaTokens.of(context).photoBackdrop,
  barrierLabel: context.t.common.close,
  transitionDuration: Motion.of(context, Motion.short),
  pageBuilder: (_, _, _) => PhotoViewer(
    photos: photos,
    initial: index,
    placeId: placeId,
    sources: sources,
    fetcher: fetcher,
  ),
  transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
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

/// The most a photo of the viewer zooms in.
const _maxZoom = 4.0;

class _PhotoViewerState extends ConsumerState<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  /// The zoom of each photo seen, so a zoomed photo pans instead of
  /// turning the page, and a photo left behind comes back whole.
  final _zooms = <int, TransformationController>{};
  bool _zoomed = false;

  /// A mouse moved over the viewer: the side buttons show, on any system,
  /// and a whole photo leaves the drag to the page view (the zoom's own
  /// recogniser would otherwise take a mouse's first move) and zooms with
  /// the wheel ([_wheel]).
  bool _mouse = false;

  @override
  void dispose() {
    _pages.dispose();
    for (final z in _zooms.values) {
      z.dispose();
    }
    super.dispose();
  }

  TransformationController _zoomOf(int page) => _zooms.putIfAbsent(page, () {
    final controller = TransformationController();
    controller.addListener(() {
      if (page != _index) return;
      final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
    return controller;
  });

  /// The wheel, or a trackpad's pinch in a browser, over a whole photo with
  /// a mouse: zooms it around the pointer, as the zoom itself does once the
  /// photo is zoomed. A sideways scroll is left to the page view.
  void _wheel(int page, PointerSignalEvent event) {
    if (page != _index) return;
    final double factor;
    switch (event) {
      case PointerScrollEvent(:final scrollDelta) when scrollDelta.dy != 0:
        factor = math.exp(-scrollDelta.dy / 200);
      case PointerScaleEvent(:final scale):
        factor = scale;
      default:
        return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (event) => _zoomBy(page, factor, event.localPosition),
    );
  }

  /// The zoom when a desktop trackpad's pinch began.
  double _pinchFrom = 1;

  /// A desktop trackpad's pinch over a whole photo (its pan and zoom
  /// events, which only the zoom's own recogniser reads otherwise).
  void _pinch(int page, PointerPanZoomUpdateEvent event) {
    if (page != _index || event.scale == 1) return;
    final now = _zoomOf(page).value.getMaxScaleOnAxis();
    _zoomBy(page, _pinchFrom * event.scale / now, event.localPosition);
  }

  void _zoomBy(int page, double factor, Offset at) {
    final zoom = _zoomOf(page);
    var scale = zoom.value.getMaxScaleOnAxis();
    // A photo shown whole starts from no transform, whatever is left of a
    // pinch that ended a hair above whole.
    if (scale <= 1.01) {
      scale = 1;
      zoom.value = Matrix4.identity();
    }
    final next = (scale * factor).clamp(1.0, _maxZoom);
    if (next == scale) return;
    if (next == 1.0) {
      zoom.value = Matrix4.identity();
      return;
    }
    final focal = zoom.toScene(at);
    zoom.value = zoom.value.clone()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(next / scale, next / scale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  void _turned(int page) {
    _zooms[_index]?.value = Matrix4.identity();
    setState(() {
      _index = page;
      _zoomed = false;
    });
  }

  /// Turns to the photo [delta] pages away, when there is one.
  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.photos.length) return;
    final duration = Motion.of(context, Motion.medium);
    if (duration == Duration.zero) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: duration, curve: Motion.standard);
    }
  }

  Future<void> _act(String action, Photo photo) async {
    switch (action) {
      case 'report':
        await showReportSheet(
          context,
          target: isLunawayCommunity(photo.sourceId)
              ? ReportTarget.photo
              : ReportTarget.externalPhoto,
          id: photo.id,
          placeId: widget.placeId,
        );
      case 'source':
        if (webLink(photo.terms?.pageUrl) case final uri?) {
          await ref.read(externalActionsProvider).openUrl(uri);
        }
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
    final tokens = LunaTokens.of(context);
    final onBackdrop = tokens.onPhotoBackdrop;
    final buttons = (pointerPlatform || _mouse) && widget.photos.length > 1;
    final pages = ScrollConfiguration(
      // A mouse or a trackpad drags the photos too: Flutter scrolls a page
      // view by touch alone otherwise.
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: PageView.builder(
        controller: _pages,
        // A zoomed photo pans under the finger; the page turns once it is
        // whole again.
        physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemCount: widget.photos.length,
        onPageChanged: _turned,
        itemBuilder: (context, i) {
          final p = widget.photos[i];
          final hash = p.thumbhash;
          final ratio = p.width != null && p.height != null && p.height! > 0
              ? p.width! / p.height!
              : null;
          final broken = Icon(AppIcons.brokenImage, color: tokens.onPhotoBackdropMuted, size: 64);
          // The thumbnail the strip already holds, while the large photo
          // comes or when it cannot: the photo shows at once, sharper a
          // moment later.
          final thumb = Image(
            image: ResizeImage(CachedImage(p.thumbUrl, fetcher: widget.fetcher), width: 480),
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, _) =>
                frame != null ? child : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, _, _) => broken,
          );
          final zoomed = i == _index && _zoomed;
          final content = Center(
            child: Semantics(
              label: t.place.photoPosition(index: i + 1, count: widget.photos.length),
              image: true,
              child: RetryingImage(
                // Decoded at the size of the screen, not of the file: a
                // large photo would otherwise take tens of megabytes.
                image: ResizeImage(
                  CachedImage(p.largeUrl, fetcher: widget.fetcher),
                  width: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.contain,
                // The ThumbHash in the photo's own frame while it loads,
                // else the thumbnail.
                placeholder: hash != null && ratio != null
                    ? AspectRatio(
                        aspectRatio: ratio,
                        child: Image(image: ThumbHashImage(hash), fit: BoxFit.fill),
                      )
                    : thumb,
                waiting: thumb,
                error: thumb,
              ),
            ),
          );
          // With a mouse, a whole photo takes no gesture: the zoom's
          // recogniser would take the mouse's first move, and the page
          // would never turn. The wheel zooms it ([_wheel]).
          if (_mouse && !zoomed) {
            return Listener(
              onPointerSignal: (event) => _wheel(i, event),
              onPointerPanZoomStart: (_) => _pinchFrom = _zoomOf(i).value.getMaxScaleOnAxis(),
              onPointerPanZoomUpdate: (event) => _pinch(i, event),
              child: content,
            );
          }
          return InteractiveViewer(
            transformationController: _zoomOf(i),
            // Never smaller than whole: a photo zoomed out would drop back to
            // the page view's drag and jump to its whole size.
            minScale: 1,
            maxScale: _maxZoom,
            // Whole, the drag is the page view's; zoomed, it moves the photo.
            panEnabled: zoomed,
            child: content,
          );
        },
      ),
    );
    final bar = Row(
      children: [
        IconButton.filled(
          style: _onAmber(context),
          tooltip: t.common.close,
          icon: const Icon(AppIcons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Goes onto two lines rather than push the counter out of a phone
        // at a large text size; as high as its text, so the bar stays a bar.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            heightFactor: 1,
            child: SourceBadge(
              label: itemSourceLabel(t, photo.sourceId, sources: widget.sources),
              onPhoto: true,
              maxLines: 2,
            ),
          ),
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
          // Another source's photo: reported to Lunaway's moderators, and
          // opened at its source when it has a page (the partner's never
          // does).
          PopupMenuButton<String>(
            tooltip: t.contribute.more,
            icon: Icon(AppIcons.moreVertical, color: onBackdrop),
            onSelected: (action) => _act(action, photo),
            itemBuilder: (context) => [
              if (photo.terms?.pageUrl != null && photo.sourceId != extcomSourceId)
                PopupMenuItem(
                  value: 'source',
                  child: ListTile(
                    leading: const Icon(AppIcons.openExternal),
                    title: Text(t.place.viewSource),
                  ),
                ),
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  leading: const Icon(AppIcons.report),
                  title: Text(t.reportSheet.photo),
                ),
              ),
            ],
          ),
      ],
    );
    final credit = [?photo.authorName, ?termsLine(t, photo.terms)];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: MouseRegion(
          onHover: (event) {
            if (!_mouse && event.kind == PointerDeviceKind.mouse) setState(() => _mouse = true);
          },
          child: Scaffold(
            backgroundColor: tokens.photoBackdrop,
            body: Stack(
              children: [
                pages,
                // The bar on top of the photo, its text kept readable over
                // a light sky by a shade that fades into the photo.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tokens.photoBackdrop.withValues(alpha: 0.7),
                          tokens.photoBackdrop.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(padding: const EdgeInsets.all(Space.s), child: bar),
                    ),
                  ),
                ),
                if (buttons && _index > 0)
                  Positioned(
                    left: Space.s,
                    top: 0,
                    bottom: 0,
                    child: SafeArea(
                      right: false,
                      child: Center(
                        child: IconButton.filled(
                          style: _onAmber(context),
                          tooltip: t.place.previousPhoto,
                          icon: const Icon(AppIcons.previous),
                          onPressed: () => _go(-1),
                        ),
                      ),
                    ),
                  ),
                if (buttons && _index < widget.photos.length - 1)
                  Positioned(
                    right: Space.s,
                    top: 0,
                    bottom: 0,
                    child: SafeArea(
                      left: false,
                      child: Center(
                        child: IconButton.filled(
                          style: _onAmber(context),
                          tooltip: t.place.nextPhoto,
                          icon: const Icon(AppIcons.next),
                          onPressed: () => _go(1),
                        ),
                      ),
                    ),
                  ),
                if (credit.isNotEmpty)
                  Positioned(
                    left: Space.l,
                    right: Space.l,
                    bottom: Space.l,
                    child: SafeArea(
                      top: false,
                      child: Text(
                        credit.join(' · '),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onBackdrop),
                      ),
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

/// The head of the reviews: the ratings of the place per source, the
/// account's own review, and what stands for the list while it is empty,
/// loading or out of reach. The reviews follow as [placeReviewItems].
class PlaceReviewsSection extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final reviews = ref.watch(placeReviewsProvider(place.id));
    final feed = ref.watch(placeReviewFeedProvider(place.id));
    // The external community source's ratings beside Lunaway's, each with
    // its own badge, average and count: never added together.
    final external = ref.watch(placeExternalProvider(place.id));
    final ratings = [...place.ratings, ...?external.value?.content.ratings];
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
              for (final r in ratings)
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SourceBadge(
                      label: itemSourceLabel(t, r.sourceId, sources: place.sources),
                      maxLines: 2,
                    ),
                    RatingText(average: r.average, count: r.count),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          YourReview(place: place),
          const SizedBox(height: Space.l),
          // The reviews themselves are items of the card's list
          // ([placeReviewItems]), built as they scroll into view.
          switch (reviews) {
            // "None" waits for the external source too: its reviews may
            // still come.
            AsyncData() when feed.reviews.isEmpty && external.isLoading && !external.hasValue =>
              const Skeleton(height: 96, radius: 20),
            AsyncData() when feed.reviews.isEmpty && feed.next == null => Text(
              // With the account's own review just above, "none" would read
              // as if it had not been kept.
              ownText ? t.place.noOtherReviews : t.place.noReviews,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AsyncData() => const SizedBox.shrink(),
            // Lunaway's reviews need a connection; the external source's,
            // when they came, still follow.
            AsyncError() => Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _OfflineNote(onRetry: () => ref.invalidate(placeExtrasProvider(place.id))),
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

/// The reviews of [place], Lunaway's and the external community source's
/// in one list, newest first, one widget each, then the button for the
/// next page: items of the card's own list, so a place with hundreds of
/// reviews builds only those on screen. Nothing until Lunaway's first page
/// is in; the external source's reviews, when they come after it, take
/// their place by date among those already shown.
List<Widget> placeReviewItems(BuildContext context, WidgetRef ref, Place place) {
  final ours = ref.watch(placeReviewsProvider(place.id));
  if (ours.isLoading && !ours.hasValue && !ours.hasError) return const [];
  final feed = ref.watch(placeReviewFeedProvider(place.id));
  final t = context.t;
  return [
    for (final r in feed.reviews)
      Padding(
        key: ValueKey('review-${r.sourceId}-${r.id}'),
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: ReviewCard(review: r, sources: place.sources, placeId: place.id),
      ),
    if (feed.next case final next?)
      Align(
        alignment: Alignment.centerLeft,
        child: feed.loadingMore
            ? const Padding(
                padding: EdgeInsets.all(Space.m),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            : TextButton.icon(
                onPressed: () => switch (next) {
                  ReviewOrigin.lunaway =>
                    ref.read(placeReviewsProvider(place.id).notifier).loadMore(),
                  ReviewOrigin.external =>
                    ref.read(placeExternalProvider(place.id).notifier).loadMore(),
                },
                icon: Icon(feed.moreFailed ? AppIcons.retry : AppIcons.expand),
                label: Text(feed.moreFailed ? t.place.moreReviewsFailed : t.place.moreReviews),
              ),
      ),
  ];
}

class ReviewCard extends ConsumerWidget {
  const new({
    required this.review,
    this.sources = const [],
    this.placeId,
    this.ofPoi = false,
    super.key,
  });

  final Review review;
  final List<PlaceSource> sources;

  /// The place the review is shown on, for a report.
  final String? placeId;

  /// A review of a point of interest: Lunaway's are reported as such, and
  /// read as written (the translation of reviews serves the places').
  final bool ofPoi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    // A long source name ("Source communautaire externe")
                    // goes on two lines in a narrow card rather than past
                    // its edge or cut.
                    Flexible(
                      child: SourceBadge(
                        label: itemSourceLabel(t, review.sourceId, sources: sources),
                        maxLines: 2,
                      ),
                    ),
                    ReviewMenu(review: review, placeId: placeId, ofPoi: ofPoi),
                  ],
                ),
              ],
            ),
            if (review.text case final text? when ofPoi && isLunawayCommunity(review.sourceId)) ...[
              const SizedBox(height: Space.s),
              Text(text, style: theme.textTheme.bodyLarge),
            ] else if (review.text case final text?) ...[
              const SizedBox(height: Space.s),
              TranslatableText(
                // Lunaway's own reviews and the other sources' are kept
                // apart on the server, each named by its own id.
                item: isLunawayCommunity(review.sourceId)
                    ? TranslatableItem.review(review.id)
                    : TranslatableItem.externalReview(review.id),
                text: text,
                lang: review.lang,
                style: theme.textTheme.bodyLarge,
                autoTranslate: ref.watch(settingsProvider.select((s) => s.autoTranslateReviews)),
              ),
            ],
            const SizedBox(height: Space.s),
            Text(
              [
                ?author,
                if (vehicle != null) t.reviewVehicle(vehicle),
                date,
                ?termsLine(t, review.terms),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The viewer's round buttons, filled with the amber: the theme gives every
/// icon button the surface's ink, which reads in Aube and not in Minuit
/// (1.84:1); the amber's own ink reads in both, its focus ring with it.
ButtonStyle _onAmber(BuildContext context) {
  final ink = Theme.of(context).colorScheme.onPrimary;
  return IconButton.styleFrom(foregroundColor: ink).copyWith(side: focusRingIn(ink));
}
