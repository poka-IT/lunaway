import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/route_marks.dart';
import 'package:lunaway/features/navigation/presentation/route_point_card.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// The tappable points of a route map, the same on the preview and in the
/// guidance: the places by the route, the stations the fuel list found, the
/// stops.
final class RoutePoints {
  const new({required this.places, required this.stations, required this.stops});

  final List<PlaceSummary> places;
  final List<FuelOffer> stations;
  final List<RouteStop> stops;

  List<RouteMarker> markers(Translations t) => [
    for (final place in places)
      RouteMarker(
        RouteMapMark(
          id: 'place:${place.id}',
          position: LatLng(place.lat, place.lon),
          kind: RouteMarkKind.place,
          badge: RouteBadge.place(place.kind),
          // Many along a long route: they show closer in, under the marks
          // about the vehicle.
          minor: true,
        ),
        PlaceSubject(place),
      ),
    for (final s in stations)
      RouteMarker(
        RouteMapMark(
          id: 'poi:${s.id}',
          position: s.position,
          kind: RouteMarkKind.fuel,
          badge: RouteBadge.fuel,
          side: t.shortPrice(s.priceEur),
        ),
        FuelSubject(s),
      ),
    for (final (i, s) in stops.indexed)
      RouteMarker(
        RouteMapMark(
          id: 'stop:$i',
          position: s.position,
          kind: RouteMarkKind.stop,
          badge: RouteBadge.stop,
          label: '${i + 1}',
        ),
        StopSubject(i, s),
      ),
  ];

  /// The point a tap on the mark [id] stands for; null when it is gone.
  RoutePoint? pointOf(String id, Translations t, DateTime now) {
    final (kind, key) = switch (id.split(':')) {
      [final kind, final key] => (kind, key),
      _ => ('', ''),
    };
    switch (kind) {
      case 'place':
        final place = places.where((x) => x.id == key).firstOrNull;
        if (place == null) return null;
        return RoutePoint(
          position: LatLng(place.lat, place.lon),
          title: t.summaryTitle(place),
          subtitle: t.kind(place.kind),
          placeId: place.id,
        );
      case 'poi':
        final s = stations.where((x) => x.id == key).firstOrNull;
        if (s == null) return null;
        return RoutePoint(
          position: s.position,
          title: s.name ?? s.brand ?? t.navigation.fuel.station,
          subtitle:
              '${t.fuelType(s.fuel)} ${t.litrePrice(s.priceEur)} · '
              '${t.priceAge(s.priceUpdatedAt, now)}',
          credit: '${t.navigation.fuel.attribution}\n${t.navigation.preview.attributionOsm}',
          poiId: s.id,
        );
      case 'stop':
        final i = int.tryParse(key);
        if (i == null || i < 0 || i >= stops.length) return null;
        final stop = stops[i];
        return RoutePoint(
          position: stop.position,
          title: stop.label,
          placeId: stop.placeId,
          poiId: stop.poiId,
          stopIndex: i,
        );
    }
    return null;
  }
}
