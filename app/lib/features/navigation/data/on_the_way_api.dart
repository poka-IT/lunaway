import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/fuel_along_route.dart';
import 'package:lunaway/features/navigation/domain/on_the_way.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

const _alongRouteDocument = r'''
query AlongRoute($input: AlongRouteInput!) {
  alongRoute(input: $input) {
    next
    items {
      alongKm
      distanceM
      detour { km minutes measured }
      place {
        id name kind lat lon overnight services
        address { city }
        municipality
        priceParkingEur
        ratings { sourceId average count }
        ratingForFilters
        reviewCount
        coverPhotos { id sourceId thumbUrl largeUrl thumbhash authorId }
      }
      poi {
        id kind name brand lat lon
        alwaysOpen
        openingIntervals { start end }
        openingIntervalsUntil
      }
      photo { id sourceId thumbUrl largeUrl thumbhash authorName licence }
    }
  }
}
''';

/// What lies along a route besides fuel (`alongRoute`): a page of places
/// and points of interest, their detours measured by the routing engine.
final alongRouteOperation = GraphQLOperation<Map<String, dynamic>>(
  name: 'AlongRoute',
  document: _alongRouteDocument,
  parse: (data) => data['alongRoute'] as Map<String, dynamic>,
);

/// Places and points of interest along a route.
abstract interface class OnTheWaySource {
  /// A page of what [search] asks for along [route] from [fromM] metres
  /// on, after [after] (the `next` of the page before), the detours
  /// measured on the roads [vehicle] (the router's profile, as JSON) may
  /// take.
  Future<OnTheWayPage> along({
    required List<LatLng> route,
    required double fromM,
    required OnTheWaySearch search,
    String? after,
    Map<String, Object?>? vehicle,
  });
}

/// [OnTheWaySource] through the server's search (`alongRoute`). The line
/// sent is the fuel search's ([ServerFuelStations.lineAhead]): it starts
/// [ServerFuelStations.privacyGapM] past the vehicle, so the device's
/// position does not leave it.
final class ServerOnTheWay implements OnTheWaySource {
  new(this._client);

  final GraphQLClient _client;

  /// Items per page: the server's ceiling, measured together.
  static const pageSize = 20;

  @override
  Future<OnTheWayPage> along({
    required List<LatLng> route,
    required double fromM,
    required OnTheWaySearch search,
    String? after,
    Map<String, Object?>? vehicle,
  }) async {
    final sent = ServerFuelStations.lineAhead(route, fromM);
    if (sent == null) return OnTheWayPage.empty;
    final (:polyline, :startM) = sent;
    final places = search.places;
    final page = await _client.execute(alongRouteOperation, {
      'input': {
        'polyline': polyline,
        if (search.poiKinds.isNotEmpty) 'poiKinds': [for (final k in search.poiKinds) k.wire],
        if (places != null)
          'places': {
            if (places.overnight case final o?) 'overnight': [for (final s in o) s.wire],
            if (places.kinds case final k?) 'kinds': [for (final s in k) s.wire],
            if (places.anyService.isNotEmpty)
              'anyService': [for (final s in places.anyService) s.wire],
          },
        'maxDetourKm': (search.maxDetourM / 1000).clamp(0.5, 30),
        'nearKm': (search.nearM / 1000).clamp(1, 1000),
        'limit': pageSize,
        'after': ?after,
        'vehicle': ?vehicle,
      },
    });
    return OnTheWayPage(
      items: [
        for (final i in (page['items'] as List?) ?? const [])
          if (i is Map<String, dynamic>) ?itemFromJson(i, startM: startM),
      ],
      next: page['next'] as String?,
      lineStartM: startM,
    );
  }
}

/// An item of `alongRoute`, its distance along counted from the route's
/// start ([startM] is where the line sent starts); null for an item the
/// app cannot show.
OnTheWayItem? itemFromJson(Map<String, dynamic> i, {required double startM}) {
  final detour = i['detour'] as Map<String, dynamic>?;
  final km = (detour?['km'] as num?)?.toDouble() ?? 0;
  final minutes = (detour?['minutes'] as num?)?.toDouble() ?? 0;
  final alongM = startM + ((i['alongKm'] as num?)?.toDouble() ?? 0) * 1000;
  final offM = (i['distanceM'] as num?)?.toDouble() ?? 0;
  final estimated = detour?['measured'] != true;
  if (!km.isFinite || !minutes.isFinite) return null;
  if (i['place'] case final Map<String, dynamic> p) {
    final place = placeFromJson(p);
    // The community's own photo first, under Lunaway's licence; another
    // source's with its own.
    final own = place.coverPhotos.firstOrNull;
    final other = i['photo'];
    return PlaceOnTheWay(
      id: place.id,
      position: place.position,
      alongM: alongM,
      offM: offM,
      detourM: km * 1000,
      detourS: minutes * 60,
      detourEstimated: estimated,
      place: place.summary,
      photo: own ?? _photo(other),
      photoLicence: own == null && other is Map<String, dynamic>
          ? _nonEmpty(other['licence'])
          : null,
      reviewCount: place.reviewCount,
    );
  }
  if (i['poi'] case final Map<String, dynamic> p) {
    final kind = PoiKind.fromCode(p['kind']);
    final lat = (p['lat'] as num?)?.toDouble();
    final lon = (p['lon'] as num?)?.toDouble();
    final id = p['id'];
    if (kind == null || lat == null || lon == null || id is! String) return null;
    final name = p['name'];
    final brand = p['brand'];
    return PoiOnTheWay(
      id: id,
      position: LatLng(lat, lon),
      alongM: alongM,
      offM: offM,
      detourM: km * 1000,
      detourS: minutes * 60,
      detourEstimated: estimated,
      kind: kind,
      name: name is String && name.isNotEmpty ? name : null,
      brand: brand is String && brand.isNotEmpty ? brand : null,
      hours: p['alwaysOpen'] == true
          ? const PoiHours(alwaysOpen: true)
          : PoiHours(
              intervals: openingIntervalsFromJson(p['openingIntervals']),
              validUntil: DateTime.tryParse('${p['openingIntervalsUntil']}'),
            ),
    );
  }
  return null;
}

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

Photo? _photo(Object? json) => switch (json) {
  {
    'id': final Object id,
    'sourceId': final String source,
    'thumbUrl': final String thumb,
    'largeUrl': final String large,
  }
      when json is Map<String, dynamic> =>
    photoFromJson(json, id: '$id', source: source, thumb: thumb, large: large),
  _ => null,
};
