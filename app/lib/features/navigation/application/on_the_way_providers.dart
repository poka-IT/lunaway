import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/on_the_way_api.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/places/application/place_digests.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'on_the_way_providers.g.dart';

final _log = Logger('on_the_way');

/// Places and points of interest along a route, through the routing client,
/// which does not wait out a rate limit: the list says at once that the
/// server asks to wait.
// keepAlive: stateless, wired once.
@Riverpod(keepAlive: true)
OnTheWaySource onTheWaySource(Ref ref) => ServerOnTheWay(ref.watch(routingClientProvider));

/// What the sheet shows on a trip: the chip chosen, and a fuel picked
/// there instead of the vehicle's.
@immutable
final class OnTheWayChoice {
  const new({this.trip, this.category = OnTheWayCategory.fuel, this.fuel});

  /// The trip the choice was made on; null before any.
  final RouteTarget? trip;
  final OnTheWayCategory category;

  /// Another fuel than the vehicle's (LPG for the heating); null for the
  /// vehicle's own.
  final FuelType? fuel;

  @override
  bool operator ==(Object other) =>
      other is OnTheWayChoice &&
      other.trip == trip &&
      other.category == category &&
      other.fuel == fuel;

  @override
  int get hashCode => Object.hash(trip, category, fuel);
}

/// The sheet's choice on the current trip: kept from the preview to the
/// guidance and from one opening of the sheet to the next; another trip
/// starts again from fuel.
// keepAlive: the choice must outlive the sheet, closed between openings.
@Riverpod(keepAlive: true)
class OnTheWayChoices extends _$OnTheWayChoices {
  @override
  OnTheWayChoice build() => const OnTheWayChoice();

  /// The choice on [trip]: fuel and the vehicle's own until one is made.
  OnTheWayChoice of(RouteTarget trip) => state.trip == trip ? state : OnTheWayChoice(trip: trip);

  void choose(RouteTarget trip, OnTheWayCategory category) =>
      state = OnTheWayChoice(trip: trip, category: category, fuel: of(trip).fuel);

  /// [fuel] instead of the vehicle's; null goes back to it.
  void chooseFuel(RouteTarget trip, FuelType? fuel) =>
      state = OnTheWayChoice(trip: trip, category: of(trip).category, fuel: fuel);
}

/// What a list along the route asks for.
@immutable
final class OnTheWayQuery {
  const new({required this.line, required this.fromM, required this.category});

  /// The route's own list of points, compared by identity.
  final List<LatLng> line;
  final double fromM;
  final OnTheWayCategory category;

  @override
  bool operator ==(Object other) =>
      other is OnTheWayQuery &&
      identical(other.line, line) &&
      other.fromM == fromM &&
      other.category == category;

  @override
  int get hashCode => Object.hash(identityHashCode(line), fromM, category);
}

/// The items read so far, and how the list goes on.
@immutable
final class OnTheWayResults {
  const new({
    required this.items,
    required this.search,
    this.next,
    this.lineStartM = 0,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<OnTheWayItem> items;

  /// What was asked: its distance of what reads first.
  final OnTheWaySearch search;
  final String? next;
  final double lineStartM;
  final bool loadingMore;

  /// The last page asked did not come: the list offers to try again.
  final bool moreFailed;

  ({List<OnTheWayItem> near, List<OnTheWayItem> further}) get sections =>
      splitNear(items, lineStartM: lineStartM, nearM: search.nearM);

  OnTheWayResults copyWith({
    List<OnTheWayItem>? items,
    String? Function()? next,
    bool? loadingMore,
    bool? moreFailed,
  }) => OnTheWayResults(
    items: items ?? this.items,
    search: search,
    next: next == null ? this.next : next(),
    lineStartM: lineStartM,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// Empty pages read on before the list says nothing is there.
const emptyPagesReadOn = 3;

/// The list of [query], a page at a time; a failure of the first page
/// shows at once (`noRetry`), a later one under the list.
@Riverpod(retry: noRetry)
class OnTheWayList extends _$OnTheWayList {
  @override
  Future<OnTheWayResults> build(OnTheWayQuery query) async {
    // The night statuses the map's filters keep: "where to sleep" keeps
    // those of them a night may be spent at.
    final nights = ref.watch(effectiveFilterProvider).overnight;
    final search = query.category.search(nightFilter: nights);
    if (search == null) {
      throw ArgumentError.value(query.category, 'category', 'searched on its own');
    }
    // The router's profile of the vehicle: the server measures the detours
    // on the roads it may take, and leaves out the places too small for it.
    final profile = ref.watch(vehicleProvider.selectAsync((v) => checkVehicle(v).profile));
    final source = ref.watch(onTheWaySourceProvider);
    final vehicle = (await profile)?.toJson();
    var page = await source.along(
      route: query.line,
      fromM: query.fromM,
      search: search,
      vehicle: vehicle,
    );
    // A page the engine emptied (every detour measured past the limit)
    // says nothing of the next ones: the list reads on, a few pages at
    // most, rather than say there is nothing.
    for (var i = 0; i < emptyPagesReadOn && page.items.isEmpty && page.next != null; i++) {
      page = await source.along(
        route: query.line,
        fromM: query.fromM,
        search: search,
        after: page.next,
        vehicle: vehicle,
      );
    }
    _readRatings(page.items);
    return OnTheWayResults(
      items: page.items,
      search: search,
      next: page.next,
      lineStartM: page.lineStartM,
    );
  }

  /// Reads the next page and adds what it holds that the list does not.
  Future<void> more() async {
    final current = state.value;
    final next = current?.next;
    if (current == null || next == null || current.loadingMore) return;
    final loading = current.copyWith(loadingMore: true, moreFailed: false);
    state = AsyncData(loading);
    // The list was read again meanwhile (another vehicle, other filters):
    // this page belongs to the list before.
    bool stale() => !ref.mounted || !identical(state.value, loading);
    try {
      final vehicle = checkVehicle(await ref.read(vehicleProvider.future)).profile?.toJson();
      final page = await ref
          .read(onTheWaySourceProvider)
          .along(
            route: query.line,
            fromM: query.fromM,
            search: current.search,
            after: next,
            vehicle: vehicle,
          );
      if (stale()) return;
      _readRatings(page.items);
      final known = {for (final i in current.items) i.id};
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            for (final i in page.items)
              if (!known.contains(i.id)) i,
          ],
          next: () => page.next,
          loadingMore: false,
        ),
      );
    } on Object catch (e, st) {
      _log.warning('a page along the route did not come', e, st);
      if (stale()) return;
      state = AsyncData(current.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  /// The ratings of the places of [items] as the lists show them, the
  /// external community source's summary among them (`placeDigests`): read
  /// for the rows on screen and held in memory only.
  void _readRatings(List<OnTheWayItem> items) {
    final ids = [
      for (final i in items)
        if (i is PlaceOnTheWay) i.id,
    ];
    if (ids.isEmpty) return;
    unawaited(
      ref
          .read(placeDigestsProvider.notifier)
          .loadIds(ids, language: LocaleSettings.currentLocale.languageCode),
    );
  }
}
