import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/core/platform/network_state.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/online_places.dart';
import 'package:lunaway/features/places/data/place_digest_source.dart';
import 'package:lunaway/features/places/data/place_external_source.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/domain/french_departments.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';

/// An in-memory [PlacesRepository] with the same filter semantics as the
/// drift one (the drift one is tested against the same expectations).
final class FakePlacesRepository implements PlacesRepository {
  new(List<Place> places, {this.sync = SyncState.none}) {
    for (final p in places) {
      _places[p.id] = p;
    }
  }

  final Map<String, Place> _places = {};
  final StreamController<void> _changes = StreamController.broadcast();

  /// Where the sync stands, as the store would say.
  SyncState sync;

  /// Makes every read fail, for the error states.
  Exception? failWith;

  List<Place> get all => _places.values.toList();

  void put(Place place) {
    _places[place.id] = place;
    _changes.add(null);
  }

  void remove(String id) {
    _places.remove(id);
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    final error = failWith;
    if (error != null) throw error;
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  bool _keeps(Place p, PlaceFilter f) =>
      f.matches(p.summary, maxHeightM: p.maxHeightM);

  @override
  Stream<List<PlaceSummary>> watchAll(PlaceFilter filter) => _watch(
    () => [
      for (final p in _places.values)
        if (_keeps(p, filter)) p.summary,
    ],
  );

  @override
  Stream<List<PlaceSummary>> watchInBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng center,
    int limit = 200,
  }) => _watch(() {
    final inside =
        [
          for (final p in _places.values)
            if (bounds.contains(p.position) && _keeps(p, filter)) p.summary,
        ]..sort(
          (a, b) => a.position
              .distanceTo(center)
              .compareTo(b.position.distanceTo(center)),
        );
    return inside.take(limit).toList();
  });

  @override
  Stream<Place?> watchPlace(String id) => _watch(() => _places[id]);

  @override
  Future<SearchResults> search(
    String text, {
    LatLng? near,
    int limit = 20,
  }) async {
    final q = text.toLowerCase().trim();
    if (q.isEmpty) return SearchResults.empty;
    final places = [
      for (final p in _places.values)
        if ((p.name ?? '').toLowerCase().contains(q)) p.summary,
    ];
    final towns = <String, List<Place>>{};
    for (final p in _places.values) {
      final city = p.address?.city;
      if (city != null && city.toLowerCase().startsWith(q)) {
        towns.putIfAbsent(city, () => []).add(p);
      }
    }
    return SearchResults(
      places: places.take(limit).toList(),
      municipalities: [
        for (final e in towns.entries)
          Municipality(
            name: e.key,
            center: e.value.first.position,
            placeCount: e.value.length,
          ),
      ],
    );
  }

  @override
  Stream<int> watchCount() => _watch(() => _places.length);

  @override
  Future<int> countMatching(PlaceFilter filter, {GeoBounds? bounds}) async =>
      _places.values
          .where(
            (p) =>
                (bounds == null || bounds.contains(p.position)) &&
                _keeps(p, filter),
          )
          .length;

  @override
  Stream<SyncState> watchSync(String region) => _watch(() => sync);

  void setSync(SyncState next) {
    sync = next;
    _changes.add(null);
  }

  @override
  Future<int> storageSizeBytes() async => 3 * 1024 * 1024 + 300 * 1024;
}

/// The API's places in memory, with the server's semantics: the viewport
/// and the filter, nearest to `near` first, pages by cursor, and every
/// request recorded.
final class FakeOnlinePlaces implements OnlinePlaces {
  new(List<Place> places) {
    for (final p in places) {
      _places[p.id] = p;
    }
  }

  final Map<String, Place> _places = {};

  /// What the server holds from now on for [place]'s id.
  void put(Place place) => _places[place.id] = place;

  /// Every request, as `kind:argument` (`page:<after>`, `search:<text>`,
  /// `place:<id>`).
  final List<String> requests = [];

  /// The `near` of each page asked: what the API learns of where the user
  /// looks.
  final List<LatLng> nears = [];

  /// The filter of each page asked.
  final List<PlaceFilter> filters = [];

  /// The `first` of each page asked.
  final List<int> firsts = [];

  /// Makes every request fail as a lost network would.
  bool offline = false;

  /// Holds the answers of the next pages (a cursor given) until it
  /// completes: a page on its way while the map moves.
  Completer<void>? holdPages;

  void _ask(String request) {
    requests.add(request);
    if (offline) throw GraphQLNetworkException('offline', null);
  }

  @override
  Future<PlacePage> inBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng near,
    int first = 50,
    String? after,
  }) async {
    _ask('page:${after ?? ''}');
    nears.add(near);
    filters.add(filter);
    firsts.add(first);
    if (after != null) await holdPages?.future;
    final inside =
        [
          for (final p in _places.values)
            if (bounds.contains(p.position) &&
                filter.matches(p.summary, maxHeightM: p.maxHeightM))
              p.summary,
        ]..sort(
          (a, b) => a.position
              .distanceTo(near)
              .compareTo(b.position.distanceTo(near)),
        );
    final start = int.tryParse(after ?? '') ?? 0;
    final end = (start + first).clamp(0, inside.length);
    return PlacePage(
      places: inside.sublist(start.clamp(0, inside.length), end),
      total: inside.length,
      hasNextPage: end < inside.length,
      endCursor: '$end',
    );
  }

  /// What the server's geocoders know: [searchAll] answers those whose
  /// name or town holds the text.
  final List<AddressMatch> addresses = [];

  /// Holds the answers of [searchAll] until it completes.
  Completer<void>? holdSearches;

  /// The language of each [searchAll].
  final List<String?> languages = [];

  /// The searches cancelled by their caller while held.
  final List<String> aborted = [];

  @override
  Future<SearchAnswer> searchAll(
    String text, {
    LatLng? near,
    bool places = true,
    String? language,
    Future<void>? abort,
  }) async {
    languages.add(language);
    _ask('${places ? 'searchAll' : 'addresses'}:$text');
    if (near != null) nears.add(near);
    final hold = holdSearches;
    if (hold != null) {
      var cancelled = false;
      await Future.any([
        hold.future,
        if (abort != null) abort.then((_) => cancelled = true),
      ]);
      if (cancelled) {
        aborted.add(text);
        throw GraphQLNetworkException('aborted', null);
      }
    }
    final q = text.toLowerCase();
    // As the server's towns: every place of a town whose name starts like
    // the text, whatever the page of places holds, one town per name and
    // department.
    final towns = <(String, String?), List<Place>>{};
    if (places) {
      for (final p in _places.values) {
        final city = p.address?.city;
        if (city != null && city.toLowerCase().startsWith(q)) {
          towns
              .putIfAbsent((
                city,
                departmentOfPostcode(p.address?.postcode),
              ), () => [])
              .add(p);
        }
      }
    }
    return SearchAnswer(
      places: places ? await _match(text, near: near) : const [],
      towns: [
        for (final MapEntry(key: (name, department), value: inTown)
            in towns.entries)
          Municipality(
            name: name,
            postcode: inTown.first.address?.postcode,
            department: department,
            countryCode: inTown.first.address?.countryCode,
            center: inTown.first.position,
            placeCount: inTown.length,
          ),
      ],
      addresses: [
        for (final a in addresses)
          if (a.name.toLowerCase().contains(q) ||
              (a.city ?? '').toLowerCase().contains(q))
            a,
      ],
    );
  }

  @override
  Future<List<PlaceSummary>> search(
    String text, {
    LatLng? near,
    int first = 20,
  }) async {
    _ask('search:$text');
    return await _match(text, first: first);
  }

  Future<List<PlaceSummary>> _match(
    String text, {
    LatLng? near,
    int first = 20,
  }) async {
    final q = text.toLowerCase();
    return [
      for (final p in _places.values)
        if ((p.name ?? '').toLowerCase().contains(q) ||
            (p.address?.city ?? '').toLowerCase().startsWith(q))
          p.summary,
    ].take(first).toList();
  }

  /// Holds the answers of [place] until it completes: what the page shows
  /// while the place is on its way.
  Completer<void>? hold;

  @override
  Future<Place?> place(String id) async {
    _ask('place:$id');
    await hold?.future;
    return _places[id];
  }
}

final class FakeFavoritesRepository implements FavoritesRepository {
  final List<({int id, String? name, bool isDefault})> _lists = [
    (id: 1, name: null, isDefault: true),
  ];
  final List<FavoriteEntry> _entries = [];
  final List<FavoritePointEntry> _points = [];
  final StreamController<void> _changes = StreamController.broadcast();
  int _nextId = 2;

  List<FavoriteEntry> get entries => List.unmodifiable(_entries);

  /// The saved points of every list, oldest first.
  List<FavoritePointEntry> get points => List.unmodifiable(_points);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void _changed() => _changes.add(null);

  @override
  Stream<List<FavoriteList>> watchLists() => _watch(
    () => [
      for (final l in _lists)
        FavoriteList(
          id: l.id,
          name: l.name,
          isDefault: l.isDefault,
          count:
              _entries.where((e) => e.listId == l.id).length +
              _points.where((e) => e.listId == l.id).length,
        ),
    ],
  );

  @override
  Stream<List<FavoriteEntry>> watchEntries(int listId) => _watch(
    () => _entries.where((e) => e.listId == listId).toList().reversed.toList(),
  );

  @override
  Stream<List<Favorite>> watchFavorites(int listId) => _watch(
    // Newest first; the places of a test share one date, the last added
    // first among them (a stable sort).
    () => <Favorite>[
      ..._entries.where((e) => e.listId == listId).toList().reversed,
      ..._points.where((e) => e.listId == listId).toList().reversed,
    ]..sort((a, b) => b.addedAt.compareTo(a.addedAt)),
  );

  @override
  Stream<List<FavoritePointEntry>> watchPoints(int listId) => _watch(
    () => _points.where((e) => e.listId == listId).toList().reversed.toList(),
  );

  @override
  Stream<Set<int>> watchListsOf(String id) => _watch(
    () => {
      for (final e in _entries)
        if (e.placeId == id) e.listId,
      for (final e in _points)
        if (e.point.id == id) e.listId,
    },
  );

  @override
  Stream<SavedPoint?> watchPoint(String id) =>
      _watch(() => _points.where((e) => e.point.id == id).lastOrNull?.point);

  /// When the next point is saved: each one a minute after the last, so
  /// the lists order them as they were saved.
  DateTime _pointClock = DateTime.utc(2026, 10, 6, 12);

  @override
  Future<void> addPoint(int listId, SavedPoint point) async {
    if (failWrites) throw StateError('disk full');
    final i = _points.indexWhere(
      (e) => e.listId == listId && e.point.id == point.id,
    );
    if (i >= 0) {
      _points[i] = FavoritePointEntry(
        listId: listId,
        point: point,
        addedAt: _points[i].addedAt,
      );
    } else {
      _pointClock = _pointClock.add(const Duration(minutes: 1));
      _points.add(
        FavoritePointEntry(listId: listId, point: point, addedAt: _pointClock),
      );
    }
    _changed();
  }

  @override
  Future<void> addPointToDefault(SavedPoint point) => addPoint(1, point);

  @override
  Future<FavoritePointEntry?> removePoint(int listId, String id) async {
    if (failWrites) throw StateError('disk full');
    final removed = _points
        .where((e) => e.listId == listId && e.point.id == id)
        .firstOrNull;
    _points.removeWhere((e) => e.listId == listId && e.point.id == id);
    _changed();
    return removed;
  }

  @override
  Future<List<FavoritePointEntry>> removePointEverywhere(String id) async {
    if (failWrites) throw StateError('disk full');
    final removed = _points.where((e) => e.point.id == id).toList();
    _points.removeWhere((e) => e.point.id == id);
    _changed();
    return removed;
  }

  @override
  Future<void> updatePoint(SavedPoint point) async {
    for (var i = 0; i < _points.length; i++) {
      final e = _points[i];
      if (e.point.id != point.id) continue;
      _points[i] = FavoritePointEntry(
        listId: e.listId,
        point: e.point.renamed(point.name, point.note),
        addedAt: e.addedAt,
      );
    }
    _changed();
  }

  @override
  Future<void> restorePoints(List<FavoritePointEntry> entries) async {
    for (final e in entries) {
      if (!_lists.any((l) => l.id == e.listId)) continue;
      _points
        ..removeWhere((x) => x.listId == e.listId && x.point.id == e.point.id)
        ..add(e);
    }
    _changed();
  }

  @override
  Future<int> defaultListId() async => 1;

  @override
  Future<void> addToDefault(PlaceSummary place) => add(1, place);

  /// Makes every later add and removal fail, as a full disk would.
  bool failWrites = false;

  @override
  Future<void> add(int listId, PlaceSummary place) async {
    if (failWrites) throw StateError('disk full');
    _entries
      ..removeWhere((e) => e.listId == listId && e.placeId == place.id)
      ..add(
        FavoriteEntry(
          listId: listId,
          placeId: place.id,
          name: place.name,
          kind: place.kind,
          overnight: place.overnight,
          city: place.city,
          position: place.position,
          addedAt: DateTime.utc(2026, 10, 6),
        ),
      );
    _changed();
  }

  @override
  Future<FavoriteEntry?> remove(int listId, String placeId) async {
    if (failWrites) throw StateError('disk full');
    final removed = _entries
        .where((e) => e.listId == listId && e.placeId == placeId)
        .firstOrNull;
    _entries.removeWhere((e) => e.listId == listId && e.placeId == placeId);
    _changed();
    return removed;
  }

  @override
  Future<int> createList(String name) async {
    final id = _nextId++;
    _lists.add((id: id, name: name, isDefault: false));
    _changed();
    return id;
  }

  @override
  Future<void> renameList(int listId, String name) async {
    final i = _lists.indexWhere((l) => l.id == listId);
    _lists[i] = (id: listId, name: name, isDefault: _lists[i].isDefault);
    _changed();
  }

  @override
  Future<void> deleteList(int listId) async {
    _lists.removeWhere((l) => l.id == listId && !l.isDefault);
    _entries.removeWhere((e) => e.listId == listId);
    _points.removeWhere((e) => e.listId == listId);
    _changed();
  }

  @override
  Future<void> restore(FavoriteEntry entry) async {
    _entries.add(entry);
    _changed();
  }
}

/// Records what the app hands to other apps, through the same checks as
/// the platform implementation.
final class FakeExternalActions implements ExternalActions {
  final List<Uri> opened = [];
  final List<String> shared = [];
  final List<String> dialled = [];
  final List<({NavigationApp app, LatLng to})> routes = [];
  bool openSucceeds = true;

  /// The navigation apps "installed".
  Set<NavigationApp> installed = {NavigationApp.googleMaps, NavigationApp.waze};

  @override
  Future<bool> openUrl(Uri url) async {
    if (!PlatformExternalActions.isWebPage(url)) return false;
    opened.add(url);
    return openSucceeds;
  }

  @override
  Future<bool> dial(String number) async {
    dialled.add(number);
    return openSucceeds;
  }

  @override
  Future<bool> navigate(
    NavigationApp app,
    LatLng to, {
    LatLng? from,
    String? label,
  }) async {
    routes.add((app: app, to: to));
    return openSucceeds;
  }

  @override
  Future<bool> canNavigateWith(NavigationApp app) async =>
      installed.contains(app);

  @override
  Future<void> share(String text, {String? subject, Rect? origin}) async =>
      shared.add(text);
}

/// The location permission, answered from fields the test sets.
final class FakeLocationPermissions implements LocationPermissions {
  LocationAccess current = LocationAccess.granted;

  /// What the system prompt answers.
  LocationAccess afterRequest = LocationAccess.granted;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<LocationAccess> status() async => current;

  @override
  Future<LocationAccess> request() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

/// The system's word on the network, set by the test; [state] null, as on
/// a desktop, says nothing. [change] announces a new state, as the system
/// does when the user switches a network on or off.
final class FakeNetworkMonitor implements NetworkMonitor {
  new([this.state]);

  NetworkState? state;
  final _changes = StreamController<NetworkState>.broadcast();

  void change(NetworkState next) {
    state = next;
    _changes.add(next);
  }

  @override
  Future<NetworkState?> current() async => state;

  @override
  Stream<NetworkState> changes() => _changes.stream;
}

/// Photos and reviews served from memory; [online] false makes the network
/// fail.
final class FakeExtrasSource implements PlaceExtrasSource {
  new({
    this.photos = const [],
    this.reviews = const [],
    this.pageSize = 2,
    this.myReview,
  });

  final List<Photo> photos;
  final List<Review> reviews;
  final int pageSize;

  /// The reader's own review, as the server would add it with a session.
  Review? myReview;
  bool online = true;
  int fetches = 0;

  ReviewPage _page(int start, int first) {
    final end = (start + first).clamp(0, reviews.length);
    return ReviewPage(
      nodes: reviews.sublist(start, end),
      endCursor: '$end',
      hasNextPage: end < reviews.length,
      totalCount: reviews.length,
    );
  }

  @override
  Future<PlaceExtrasRead?> fetch(String placeId, {required int first}) async {
    fetches++;
    if (!online) throw StateError('offline');
    return (photos: photos, reviews: _page(0, pageSize), myReview: myReview);
  }

  @override
  Future<ReviewPage> moreReviews(
    String placeId, {
    required String after,
    required int first,
  }) async {
    if (!online) throw StateError('offline');
    return _page(int.parse(after), pageSize);
  }
}

/// The digests the API gives the rows of a list: those given, a place of
/// an area found by its [positions]. Every request is recorded.
final class FakeDigestSource implements PlaceDigestSource {
  new([List<PlaceDigest> digests = const [], this.positions = const {}])
    : _byId = {for (final d in digests) d.placeId: d};

  final Map<String, PlaceDigest> _byId;
  final Map<String, LatLng> positions;

  /// The ids asked, request by request.
  final idRequests = <List<String>>[];

  /// The areas asked.
  final areaRequests = <GeoBounds>[];

  /// The languages asked.
  final languages = <String>[];
  bool offline = false;

  /// Refuses the reads as the API past the client's quota, for this long.
  Duration? refusedFor;
  Completer<void>? hold;

  @override
  Future<List<PlaceDigest>> ofPlaces(
    List<String> ids, {
    required String language,
  }) async {
    idRequests.add(ids);
    languages.add(language);
    await hold?.future;
    if (offline) throw GraphQLNetworkException('offline', null);
    if (refusedFor case final wait?) throw GraphQLRateLimitedException(wait);
    return [for (final id in ids) ?_byId[id]];
  }

  @override
  Future<List<PlaceDigest>> inArea(
    GeoBounds area, {
    required String language,
  }) async {
    areaRequests.add(area);
    languages.add(language);
    await hold?.future;
    if (offline) throw GraphQLNetworkException('offline', null);
    if (refusedFor case final wait?) throw GraphQLRateLimitedException(wait);
    return [
      for (final d in _byId.values)
        if (positions[d.placeId] case final p? when area.contains(p)) d,
    ];
  }
}

/// The external community source served from memory: [content] for a
/// place's card, then the pages of [more] by their cursor. While [hold] is
/// set, reads wait for it, as on a slow network.
final class FakeExternalSource implements PlaceExternalSource {
  new({this.content = ExternalContent.empty, this.more = const {}});

  ExternalContent content;
  final Map<String, ReviewPage> more;
  bool online = true;
  Completer<void>? hold;
  final fetched = <String>[];
  final pagesAfter = <String>[];

  @override
  Future<ExternalContent> fetch(String placeId, {required int first}) async {
    fetched.add(placeId);
    await hold?.future;
    if (!online) throw StateError('offline');
    return content;
  }

  @override
  Future<ReviewPage> moreReviews(
    String placeId, {
    required String after,
    required int first,
  }) async {
    pagesAfter.add(after);
    if (!online) throw StateError('offline');
    return more[after] ?? ReviewPage.empty;
  }
}

/// Stands in for the map in widget tests, where platform views do not
/// render: every pin is a button keyed `pin-<id>`, a long press on the map
/// surface reports [longPressAt], and camera commands are recorded.
base class FakeMap implements LunaMapController {
  final List<({LatLng center, double? zoom})> moves = [];
  final List<GeoBounds> fits = [];
  LatLng? userPosition;
  LunaMapProps? lastProps;
  LatLng longPressAt = const LatLng(45.7629, 4.831697);

  /// False for a map that never gets ready (a platform view that does not
  /// come): it reports its camera but never hands its controller over.
  bool becomesReady = true;
  MapViewport viewport = const MapViewport(
    bounds: GeoBounds(south: 41, west: -5.5, north: 51.5, east: 10),
    center: LatLng(46.6, 2.5),
    zoom: 6,
  );

  @override
  Future<void> moveTo(LatLng center, {double? zoom}) async =>
      moves.add((center: center, zoom: zoom));

  @override
  Future<void> fitBounds(GeoBounds bounds) async => fits.add(bounds);

  final List<double> zooms = [];

  @override
  Future<void> zoomBy(double delta) async => zooms.add(delta);

  @override
  Future<LatLng?> locateUser() async => userPosition;

  /// The positions the app marked itself (the browser's, on the web).
  final List<LatLng> shown = [];

  @override
  Future<void> showPosition(LatLng position, {double? accuracy}) async =>
      shown.add(position);

  /// Where the camera is while it still moves, before its next rest; the
  /// last viewport when null.
  LatLng? moving;

  /// The zoom while the camera still moves (a double tap zooming); the last
  /// viewport's when null.
  double? zooming;

  @override
  Future<({LatLng center, double zoom})?> camera() async =>
      (center: moving ?? viewport.center, zoom: zooming ?? viewport.zoom);

  /// The props of the first build: the camera the map is made with.
  LunaMapProps? firstProps;

  Widget build(BuildContext context, LunaMapProps props) {
    firstProps ??= props;
    lastProps = props;
    return _FakeMapView(map: this, props: props);
  }
}

class _FakeMapView extends StatefulWidget {
  const new({required this.map, required this.props});

  final FakeMap map;
  final LunaMapProps props;

  @override
  State<_FakeMapView> createState() => _FakeMapViewState();
}

class _FakeMapViewState extends State<_FakeMapView> {
  @override
  void initState() {
    super.initState();
    // Like the real map: ready once built, then the camera rests.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (widget.map.becomesReady) widget.props.onMapReady(widget.map);
      widget.props.onViewportChanged(widget.map.viewport);
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('fake-map'),
    onLongPress: () => widget.props.onLongPress(widget.map.longPressAt),
    child: ColoredBox(
      color: const Color(0xFFDDE3EA),
      child: Align(
        child: Wrap(
          children: [
            for (final p in widget.props.places.take(30))
              SizedBox(
                width: 10,
                height: 10,
                child: GestureDetector(
                  key: ValueKey('pin-${p.id}'),
                  onTap: () => widget.props.onPlaceTap(p.id),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
