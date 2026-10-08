import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/places/application/place_digests.dart';
import 'package:lunaway/features/places/application/places_providers.dart' show noRetry;
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'listed_places.g.dart';

/// How long the list waits for its rows' digests before it shows them
/// without: the rows then gain their ratings when the answer comes.
const digestWait = Duration(milliseconds: 1200);

/// The list beside the map as it shows: the rows of
/// [nearbyPlacesPageProvider] in the order the user chose, with what their
/// digests add.
@immutable
final class ListedPage {
  const new(this.page, {this.digests = const {}, this.rankedAmong});

  /// The rows, in their order; no further page once ranked otherwise than
  /// by distance.
  final NearbyPage page;
  final Map<String, PlaceDigest> digests;

  /// Ranked among the nearest this many rows, when the view holds more:
  /// the order covers only those.
  final int? rankedAmong;
}

/// The list beside the map as it shows. The digests of its rows come from
/// the API: by the ids of a page the API sent, by the area (on the API's
/// grid) of a list read from the tiles or the device, so that no request
/// says more of the view than the tiles or the list's own requests do. The
/// list waits for them a moment, so the rows do not jump when the ratings
/// come.
// No retry of its own: it fails only when the page of the view does,
// which retries already; retried twice over, the list would stay loading
// long after that page gave up.
@Riverpod(retry: noRetry)
Future<ListedPage> listedPlaces(Ref ref) async {
  final sort = ref.watch(settingsProvider.select((s) => s.listSort));
  // The excerpts follow the language; the rows gain their digests as they
  // come, whatever the wait gave.
  ref
    ..watch(settingsProvider.select((s) => s.localeCode))
    ..watch(placeDigestsProvider);
  final viewport = ref.watch(viewportProvider) ?? initialViewport;
  final page = await ref.watch(nearbyPlacesPageProvider.future);
  final language = LocaleSettings.currentLocale.languageCode;
  final digests = ref.read(placeDigestsProvider.notifier);
  final Future<void> load;
  // The ids of a page the API sent say nothing it does not know; a list
  // read on the device asks by area, as wide as the grid makes it, and
  // only from the zoom where the map's tiles name their places: below,
  // the area would say more of the view than the tiles do.
  if (page.query != null) {
    load = digests.loadIds([for (final p in page.places) p.id], language: language);
  } else if (viewport.zoom >= PlaceTiles.nameZoom) {
    final area = digestAreaOf(viewport.bounds);
    load = area == null ? Future.value() : digests.loadArea(area, language: language);
  } else {
    load = Future.value();
  }
  await _within(ref, load, digestWait);
  // A digest that came meanwhile rebuilt the list: this build is gone.
  if (!ref.mounted) return ListedPage(page);
  final known = ref.read(placeDigestsProvider);
  final ranked = sort != ListSort.distance;
  // No total: the list stopped at its limit without counting the view.
  final more = page.hasMore || page.total == null || page.total! > page.places.length;
  return ListedPage(
    NearbyPage(
      sortRows(page.places, known, sort),
      total: page.total,
      hasMore: !ranked && page.hasMore,
      cursor: page.cursor,
      query: page.query,
      loadingMore: page.loadingMore,
      moreFailed: page.moreFailed,
    ),
    digests: known,
    rankedAmong: ranked && more ? page.places.length : null,
  );
}

/// [load], or [limit] if it takes longer; a failure is the absence of the
/// digests, which the rows do without.
Future<void> _within(Ref ref, Future<void> load, Duration limit) {
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final timer = Timer(limit, finish);
  ref.onDispose(timer.cancel);
  unawaited(load.then((_) => finish(), onError: (Object _) => finish()));
  return done.future.whenComplete(timer.cancel);
}
