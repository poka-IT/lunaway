import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:meta/meta.dart';

/// What the "On the way" sheet looks for, one chip each, in the order of
/// the chips: fuel first, what a motorhome needs every day next, then the
/// rest. A chip that stands for a whole category of points takes its kinds
/// from the taxonomy ([PoiCategory.kinds]), the one the map's chips read.
enum OnTheWayCategory {
  fuel,
  sleep,
  water,
  groceries,
  bakeries,
  food,
  sights,
  vending,
  toilets,
  health,
  services,
  charging,
  garages;

  /// What the server is asked for this category; null for [fuel], which
  /// has its own search ranked by the price with the detour in it.
  /// [nightFilter] is the night statuses the map's filters keep (empty for
  /// any): [sleep] takes those of them a night can be spent at.
  OnTheWaySearch? search({Set<OvernightStatus> nightFilter = const {}}) => switch (this) {
    fuel => null,
    sleep => OnTheWaySearch(
      places: OnTheWayPlaces(
        overnight: {
          for (final o in nightPossible)
            if (nightFilter.isEmpty || nightFilter.contains(o)) o,
        }.ifEmpty(nightPossible),
      ),
      maxDetourM: 10000,
      nearM: 100000,
    ),
    water => const OnTheWaySearch(
      poiKinds: [PoiKind.drinkingWater, PoiKind.waterPoint, PoiKind.dumpStation],
      places: OnTheWayPlaces(
        anyService: {Service.drinkingWater, Service.greyWater, Service.blackWater},
      ),
    ),
    groceries => const OnTheWaySearch(
      poiKinds: [
        PoiKind.supermarket,
        PoiKind.convenience,
        PoiKind.butcher,
        PoiKind.greengrocer,
        PoiKind.farmShop,
        PoiKind.marketplace,
      ],
    ),
    bakeries => const OnTheWaySearch(poiKinds: [PoiKind.bakery]),
    food => OnTheWaySearch(poiKinds: PoiCategory.food.kinds),
    // Something to see is worth a longer detour, as health is.
    sights => OnTheWaySearch(poiKinds: PoiCategory.sights.kinds, maxDetourM: 10000),
    vending => OnTheWaySearch(poiKinds: PoiCategory.vending.kinds),
    toilets => const OnTheWaySearch(poiKinds: [PoiKind.toilets, PoiKind.shower]),
    health => OnTheWaySearch(poiKinds: PoiCategory.health.kinds, maxDetourM: 10000),
    services => const OnTheWaySearch(
      poiKinds: [
        PoiKind.laundry,
        PoiKind.gasBottles,
        PoiKind.postOffice,
        PoiKind.atm,
        PoiKind.recyclingCentre,
      ],
    ),
    charging => const OnTheWaySearch(poiKinds: [PoiKind.evCharging]),
    garages => const OnTheWaySearch(
      poiKinds: [PoiKind.carRepair, PoiKind.motorhomeShop, PoiKind.carWash, PoiKind.outdoorShop],
      maxDetourM: 10000,
    ),
  };
}

extension<T> on Set<T> {
  Set<T> ifEmpty(Set<T> other) => isEmpty ? other : this;
}

/// What lies within this many metres of where the list starts reads first
/// (about forty minutes of a motorhome); beyond it, the rest waits under
/// "Further on", folded.
const defaultOnTheWayNearM = 50000.0;

/// A search along the route (`AlongRouteInput`).
@immutable
final class OnTheWaySearch {
  const new({
    this.poiKinds = const [],
    this.places,
    this.maxDetourM = 6000,
    this.nearM = defaultOnTheWayNearM,
  });

  final List<PoiKind> poiKinds;

  /// The places it takes; none when null.
  final OnTheWayPlaces? places;

  /// The longest detour, there and back.
  final double maxDetourM;

  /// What lies within it, from where the list starts, comes first.
  final double nearM;

  @override
  bool operator ==(Object other) =>
      other is OnTheWaySearch &&
      _sameList(other.poiKinds, poiKinds) &&
      other.places == places &&
      other.maxDetourM == maxDetourM &&
      other.nearM == nearM;

  @override
  int get hashCode => Object.hash(Object.hashAll(poiKinds), places, maxDetourM, nearM);
}

/// Which places a search takes: every part given holds.
@immutable
final class OnTheWayPlaces {
  const new({this.overnight, this.kinds, this.anyService = const {}});

  /// Only these night statuses; any when null.
  final Set<OvernightStatus>? overnight;

  /// Only these kinds; any when null.
  final Set<PlaceKind>? kinds;

  /// At least one of these services; no condition when empty.
  final Set<Service> anyService;

  @override
  bool operator ==(Object other) =>
      other is OnTheWayPlaces &&
      _sameSet(other.overnight, overnight) &&
      _sameSet(other.kinds, kinds) &&
      _sameSet(other.anyService, anyService);

  @override
  int get hashCode => Object.hash(
    overnight == null ? null : Object.hashAllUnordered(overnight!),
    kinds == null ? null : Object.hashAllUnordered(kinds!),
    Object.hashAllUnordered(anyService),
  );
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSet<T>(Set<T>? a, Set<T>? b) =>
    a == null ? b == null : b != null && a.length == b.length && a.containsAll(b);

/// A place or a point of interest along the route, and what reaching it
/// costs.
@immutable
sealed class OnTheWayItem {
  const new({
    required this.id,
    required this.position,
    required this.alongM,
    required this.offM,
    required this.detourM,
    required this.detourS,
    this.detourEstimated = false,
  });

  final String id;
  final LatLng position;

  /// Where the route passes it, metres from the route's start.
  final double alongM;

  /// Metres from the route, in a straight line.
  final double offM;

  /// Metres and seconds the stop adds to the route.
  final double detourM;
  final double detourS;

  /// The detour is reckoned from the distance to the route, not routed.
  final bool detourEstimated;

  @override
  bool operator ==(Object other) =>
      other is OnTheWayItem &&
      other.runtimeType == runtimeType &&
      other.id == id &&
      other.detourS == detourS &&
      other.alongM == alongM;

  @override
  int get hashCode => Object.hash(id, detourS, alongM);
}

/// A place to stay, or to stop at for water.
final class PlaceOnTheWay extends OnTheWayItem {
  const new({
    required super.id,
    required super.position,
    required super.alongM,
    required super.offM,
    required super.detourM,
    required super.detourS,
    required this.place,
    super.detourEstimated,
    this.photo,
    this.photoLicence,
    this.reviewCount = 0,
  });

  final PlaceSummary place;

  /// Its photo: the community's own first, else another source's.
  final Photo? photo;

  /// The licence of another source's photo, shown beside it with its
  /// source and author; null for the community's own.
  final String? photoLicence;

  /// Reviews with text on Lunaway.
  final int reviewCount;
}

/// A shop, a machine, a service.
final class PoiOnTheWay extends OnTheWayItem {
  const new({
    required super.id,
    required super.position,
    required super.alongM,
    required super.offM,
    required super.detourM,
    required super.detourS,
    required this.kind,
    super.detourEstimated,
    this.name,
    this.brand,
    this.hours = PoiHours.unknown,
  });

  final PoiKind kind;
  final String? name;
  final String? brand;

  /// Its hours, as the server computed them.
  final PoiHours hours;

  /// The feature its page opens from.
  PoiFeature get feature =>
      PoiFeature(id: id, kind: kind, position: position, name: name, hours: hours);
}

/// A page of what lies along the route, and where the list goes on.
@immutable
final class OnTheWayPage {
  const new({required this.items, this.next, this.lineStartM = 0});

  static const empty = OnTheWayPage(items: []);

  final List<OnTheWayItem> items;

  /// The cursor of the next page; null on the last.
  final String? next;

  /// Where the line the server searched starts, metres from the route's
  /// start: what lies within the search's `nearM` of it reads first.
  final double lineStartM;
}

/// [items] split where the list folds: those reached within [nearM] of
/// [lineStartM], in the server's order, and the others.
({List<OnTheWayItem> near, List<OnTheWayItem> further}) splitNear(
  List<OnTheWayItem> items, {
  required double lineStartM,
  required double nearM,
}) {
  final near = <OnTheWayItem>[];
  final further = <OnTheWayItem>[];
  for (final i in items) {
    (i.alongM - lineStartM <= nearM ? near : further).add(i);
  }
  return (near: near, further: further);
}

/// Seconds the route takes from its start to [alongM] metres along it, by
/// its steps' own times, each spread evenly over its road; null without
/// steps.
double? secondsTo(RouteOption route, double alongM) {
  if (route.steps.isEmpty) return null;
  var metres = 0.0;
  var seconds = 0.0;
  for (final s in route.steps) {
    if (alongM <= metres + s.distanceM) {
      final share = s.distanceM > 0 ? (alongM - metres) / s.distanceM : 0.0;
      return seconds + s.durationS * share.clamp(0, 1);
    }
    metres += s.distanceM;
    seconds += s.durationS;
  }
  return seconds;
}

/// When the vehicle, at [fromM] along [route] at [now], reaches [item]:
/// the route's time to where it leaves the road, then half the detour.
/// Null when the route carries no times.
DateTime? passageAt(RouteOption route, double fromM, OnTheWayItem item, DateTime now) {
  final from = secondsTo(route, fromM);
  final to = secondsTo(route, item.alongM);
  if (from == null || to == null) return null;
  final seconds = (to - from).clamp(0, double.infinity) + item.detourS / 2;
  return now.add(Duration(seconds: seconds.round()));
}
